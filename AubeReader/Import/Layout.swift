import CoreGraphics
import Foundation

// ─── Lines and blocks on a page ──────────────────────────────────────────────

/// Words on one baseline, within one column.
struct TextLine {
  var words: [RawWord]
  var rect: CGRect
  var baseline: CGFloat
  var size: CGFloat
  var font: Int
  var color: Tint
  var text: String
  /// How many stretches wide gaps divide it into, as a table's rows are divided.
  var runs: Int
}

/// A block as found on one page, before the document is looked at as a whole.
struct PageBlock {
  enum Kind { case text, figure, table }
  var kind: Kind
  var lines: [TextLine] = []
  var ink: CGRect
  var tile: CGRect
  /// In the page's layout it has no tile of its own: it overlaps something else there.
  var loose = false
  var photo = false
}

/// A page, cut into tiles, with its blocks in the order they read.
struct PageLayout {
  var blocks: [PageBlock]
  /// Whose block numbers are indices into `blocks`.
  var tile: PageTile
  /// Lines overlapping an already-claimed figure, kept for the text.
  var photos: [CGRect]
}

/// What a whole document's pages have in common, for reading any one of them.
struct DocMeasure {
  /// The size most of the running text is set at.
  var body: CGFloat
  /// Right-to-left, so columns read the other way.
  var rtl: Bool

  static func of(_ pages: [RawPage]) -> DocMeasure {
    var sizes: [CGFloat: Int] = [:]
    var rtl = 0
    var ltr = 0
    for p in pages {
      for r in p.runs {
        let n = r.words.reduce(0) { $0 + $1.text.count }
        // Long runs say more about the running text than labels do.
        sizes[(r.size * 2).rounded() / 2, default: 0] += r.words.count >= 4 ? n : n / 4
        for w in r.words.prefix(4) {
          for u in w.text.unicodeScalars where u.properties.isAlphabetic {
            if PageReader.isRTL(u) { rtl += 1 } else { ltr += 1 }
          }
        }
      }
    }
    let body = sizes.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 10
    return DocMeasure(body: max(body, 4), rtl: rtl > ltr)
  }
}

// ─── Reading a page's layout ─────────────────────────────────────────────────

/// Works out how a page is laid out, from where its words and pictures fall:
/// which pictures belong together, how the text divides into columns, what
/// order those read in, and what's a paragraph. Everything comes from geometry,
/// so it works the same for any PDF, in any language.
struct PageAnalyzer {
  private let raw: RawPage
  private let measure: DocMeasure
  private let fonts: [FontRecord]
  private var body: CGFloat { measure.body }

  /// Something the cuts must go around.
  private struct El {
    var rect: CGRect
    /// An index into `raw.runs`, or −1.
    var run = -1
    /// An index into `atoms`, or −1.
    var atom = -1
  }

  /// A figure or table, whole.
  private struct Atom {
    var rect: CGRect
    var kind: PageBlock.Kind
    var photo: Bool
    var lines: [TextLine] = []
  }

  private final class Node {
    enum Kind { case stack, side, leaf }
    var kind: Kind
    var rect: CGRect
    var kids: [Node] = []
    var els: [El] = []
    init(_ kind: Kind, _ rect: CGRect) {
      self.kind = kind
      self.rect = rect
    }
  }

  private var atoms: [Atom] = []

  static func analyze(_ raw: RawPage, measure: DocMeasure, fonts: [FontRecord]) -> PageLayout {
    var a = PageAnalyzer(raw: raw, measure: measure, fonts: fonts)
    return a.run()
  }

  private init(raw: RawPage, measure: DocMeasure, fonts: [FontRecord]) {
    var raw = raw
    Self.seatDropCaps(&raw, body: measure.body)
    self.raw = raw
    self.measure = measure
    self.fonts = fonts
  }

  /// A paragraph's large first letter, set beside its first few lines: it goes
  /// back on the front of its word, and the lines it pushed in count as flush
  /// with the column, so they don't read as a new paragraph when it ends.
  private static func seatDropCaps(_ raw: inout RawPage, body: CGFloat) {
    var gone: [Int] = []
    for (i, cap) in raw.runs.enumerated() {
      let text = cap.words.map(\.text).joined()
      guard text.count <= 2, text.contains(where: \.isLetter), cap.size >= body * 1.7 else { continue }
      // How tall it stands from its true baseline: capitals are about 0.7 of the size.
      let top = cap.baseline - cap.size * 0.8
      let beside = raw.runs.indices.filter { j in
        guard j != i else { return false }
        let r = raw.runs[j]
        return r.size < cap.size * 0.7 && r.rect.minX >= cap.rect.maxX - 2 && r.rect.minX <= cap.rect.maxX + r.size * 1.5
          && r.baseline >= top && r.baseline <= cap.baseline + r.size * 1.2
      }
      guard let first = beside.min(by: { raw.runs[$0].baseline < raw.runs[$1].baseline }) else { continue }
      raw.runs[first].words[0].text = text + raw.runs[first].words[0].text
      for j in beside {
        let r = raw.runs[j].rect
        raw.runs[j].rect = CGRect(x: cap.rect.minX, y: r.minY, width: r.maxX - cap.rect.minX, height: r.height)
      }
      gone.append(i)
    }
    for i in gone.reversed() { raw.runs.remove(at: i) }
  }

  private mutating func run() -> PageLayout {
    let page = CGRect(origin: .zero, size: raw.size)
    let (tableRuns, tableRules) = findRuledTables()
    let claimed = findFigures(skipping: tableRuns, rules: tableRules).union(tableRuns)
    var els: [El] = []
    for (i, r) in raw.runs.enumerated() where !claimed.contains(i) { els.append(El(rect: r.rect, run: i)) }
    for (i, a) in atoms.enumerated() { els.append(El(rect: a.rect, atom: i)) }

    let root = cut(page, els, depth: 0)
    collapseTables(root)
    var blocks: [PageBlock] = []
    let tile = build(root, &blocks)
    let photos = atoms.filter(\.photo).map(\.rect)
    return PageLayout(blocks: blocks, tile: tile, photos: photos)
  }

  // ─── Figures ─────────────────────────────────────────────────────────────

  /// Groups the page's pictures and line art into figures, by how near they lie,
  /// and takes in the labels on and around them. Returns the runs taken in.
  private mutating func findFigures(skipping taken: Set<Int>, rules usedRules: Set<Int>) -> Set<Int> {
    var marks = raw.marks
    marks += raw.sideways.map { RawMark(rect: $0, kind: .vector) }
    // A diagram's boxes and arrows are drawn with thin lines too. Short ones count; long ones
    // separate things, and the ones that rule off a table have been dealt with.
    for (i, r) in raw.rules.enumerated() where !usedRules.contains(i) && max(r.width, r.height) < raw.size.width * 0.3 {
      marks.append(RawMark(rect: r, kind: .vector))
    }
    // A picture of the page itself is the page, not a figure on it.
    let area = raw.size.width * raw.size.height
    if raw.scanned { marks.removeAll { $0.kind == .image && $0.rect.width * $0.rect.height > area * 0.6 } }
    // Filled shapes count as marks only if they aren't there for the text on them:
    // a sidebar's panel, or a tint behind a link.
    for p in raw.panels where !holdsProse(p.rect) { marks.append(RawMark(rect: p.rect, kind: .vector)) }
    marks.removeAll { $0.kind == .tint && $0.rect.width * $0.rect.height >= 60 && textCover($0.rect) > 0.22 }
    guard !marks.isEmpty else { return [] }

    // Marks close enough to touch, on a coarse grid, however many of them there are.
    let cell: CGFloat = 4
    let cols = Int(raw.size.width / cell) + 2
    let rows = Int(raw.size.height / cell) + 2
    var grid = [Int32](repeating: -1, count: cols * rows)
    var parent = Array(marks.indices)
    func find(_ x: Int) -> Int {
      var x = x
      while parent[x] != x {
        parent[x] = parent[parent[x]]
        x = parent[x]
      }
      return x
    }
    let reach: CGFloat = 8
    for (i, m) in marks.enumerated() {
      let r = m.rect.insetBy(dx: -reach / 2, dy: -reach / 2)
      let x0 = max(0, Int(r.minX / cell))
      let x1 = min(cols - 1, Int(r.maxX / cell))
      let y0 = max(0, Int(r.minY / cell))
      let y1 = min(rows - 1, Int(r.maxY / cell))
      guard x0 <= x1, y0 <= y1 else { continue }
      for y in y0...y1 {
        for x in x0...x1 {
          let k = y * cols + x
          if grid[k] >= 0 {
            let (a, b) = (find(Int(grid[k])), find(i))
            if a != b { parent[a] = b }
          }
          grid[k] = Int32(i)
        }
      }
    }
    var groups: [Int: (rect: CGRect, image: CGFloat, count: Int)] = [:]
    for (i, m) in marks.enumerated() {
      let root = find(i)
      var g = groups[root] ?? (m.rect, 0, 0)
      g.rect = g.rect.union(m.rect)
      if m.kind == .image { g.image += m.rect.width * m.rect.height }
      g.count += 1
      groups[root] = g
    }
    var clusters = groups.values
      .filter { $0.rect.width >= 14 && $0.rect.height >= 14 && $0.rect.width * $0.rect.height >= 500 }
      .map { (rect: $0.rect, photo: $0.image > $0.rect.width * $0.rect.height * 0.5) }

    // A figure's panels, side by side or stacked, with nothing being read between them.
    var merged = true
    while merged {
      merged = false
      outer: for i in clusters.indices {
        for j in clusters.indices where j > i {
          let (a, b) = (clusters[i].rect, clusters[j].rect)
          let u = a.union(b)
          let across = min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) * 0.5 && u.width - a.width - b.width < body * 3
          let down = min(a.maxX, b.maxX) - max(a.minX, b.minX) > min(a.width, b.width) * 0.5 && u.height - a.height - b.height < body * 2
          guard across || down, !holdsText(u, besides: [a, b]) else { continue }
          clusters[i] = (u, clusters[i].photo || clusters[j].photo)
          clusters.remove(at: j)
          merged = true
          break outer
        }
      }
    }

    var claimed = taken
    let atomsBefore = atoms.count
    for c in clusters {
      var box = c.rect
      // A table already found isn't a figure too.
      if atoms[0..<atomsBefore].contains(where: { $0.rect.intersects(c.rect) && $0.rect.intersection(c.rect).width * $0.rect.intersection(c.rect).height > c.rect.width * c.rect.height * 0.5 }) { continue }
      // PageText laid over or inside it makes it a backdrop or a frame: the text is
      // read, and the marks stay on the page but aren't a figure.
      if holdsProse(c.rect) { continue }
      var took: [Int] = []
      for (i, r) in raw.runs.enumerated() where !claimed.contains(i) && box.insetBy(dx: -2, dy: -2).contains(CGPoint(x: r.rect.midX, y: r.rect.midY)) {
        took.append(i)
      }
      // Axis labels and the like just outside it: short, no larger than the text, not a caption.
      for _ in 0..<2 {
        for (i, r) in raw.runs.enumerated() where !claimed.contains(i) && !took.contains(i) {
          let near = box.insetBy(dx: -body * 1.1, dy: -body * 1.1).intersects(r.rect)
          guard near, r.words.count <= 4, r.size <= body * 1.05, r.rect.width < raw.size.width * 0.3 else { continue }
          let t = PageText.line(r.words)
          if Structure.captionPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { continue }
          if t.hasSuffix(".") && r.words.count > 2 { continue }
          took.append(i)
          box = box.union(r.rect)
        }
      }
      claimed.formUnion(took)
      let lines = took.map { Self.line(from: raw.runs[$0]) }
      atoms.append(Atom(rect: box, kind: .figure, photo: c.photo, lines: lines))
    }
    return claimed
  }

  /// Tables and algorithm boxes ruled off by lines of one length, one above another: the
  /// plainest thing a page can say about where a table begins and ends. The rows between
  /// the first and last rule, and a header just over the first, are kept whole.
  private mutating func findRuledTables() -> (runs: Set<Int>, rules: Set<Int>) {
    let across = raw.rules.indices.filter { raw.rules[$0].width >= 40 && raw.rules[$0].height <= 2.5 }.sorted { raw.rules[$0].minY < raw.rules[$1].minY }
    var groups: [[Int]] = []
    for i in across {
      let r = raw.rules[i]
      if let g = groups.lastIndex(where: { group in
        let head = raw.rules[group[0]]
        return abs(head.minX - r.minX) <= 6 && abs(head.maxX - r.maxX) <= 6 && r.minY - raw.rules[group.last!].minY < body * 26
      }) {
        groups[g].append(i)
      } else {
        groups.append([i])
      }
    }
    // Rules of one length can still belong to different tables: a caption or a sentence between them says so.
    var sections: [[Int]] = []
    for group in groups {
      var current = [group[0]]
      for pair in zip(group, group.dropFirst()) {
        let (a, b) = (raw.rules[pair.0], raw.rules[pair.1])
        let between = raw.runs.contains { run in
          guard run.rect.midY > a.maxY, run.rect.midY < b.minY, run.rect.midX > a.minX, run.rect.midX < a.maxX else { return false }
          let t = PageText.line(run.words)
          return run.words.filter({ $0.text.count >= 3 && $0.text.contains(where: \.isLetter) }).count >= 7 || Structure.captionPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
        }
        if between {
          sections.append(current)
          current = []
        }
        current.append(pair.1)
      }
      sections.append(current)
    }
    var runs = Set<Int>()
    var rules = Set<Int>()
    for group in sections where group.count >= 2 {
      let top = raw.rules[group[0]]
      let bottom = raw.rules[group.last!]
      guard bottom.minY - top.minY > body * 1.5 else { continue }
      var box = CGRect(x: min(top.minX, bottom.minX), y: top.minY, width: max(top.maxX, bottom.maxX) - min(top.minX, bottom.minX), height: bottom.maxY - top.minY)
      // Curves or a picture between them: those lines are a chart's axes or a diagram's boxes, not a table's rules.
      let drawn = raw.marks.filter { $0.kind == .image || $0.rect.width > 3 || $0.rect.height > 3 }.filter { box.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
      if drawn.contains(where: { $0.kind == .image }) || drawn.count > 4 { continue }
      // A table's cells lie within its rules; a line that crosses them isn't one of them.
      let inside = raw.runs.indices.filter { !runs.contains($0) && box.insetBy(dx: -body * 0.6, dy: 0).contains(raw.runs[$0].rect.insetBy(dx: 0, dy: raw.runs[$0].rect.height / 2 - 0.5)) }
      let across = raw.runs.contains { r in r.rect.midY > box.minY && r.rect.midY < box.maxY && r.rect.intersects(box) && (r.rect.minX < box.minX - body || r.rect.maxX > box.maxX + body) }
      guard inside.count >= 2, !across else { continue }
      // Sentences between the rules mean something else is being set off: a boxed passage, or a whole page between its head and foot.
      let long = inside.filter { raw.runs[$0].words.count >= 9 }.count
      guard Double(long) <= Double(inside.count) * 0.3, inside.count < 400 else { continue }
      var took = inside
      // A header sitting just above the first rule, as tables often have.
      let reach = body * 2.6
      let above = raw.runs.indices.filter { i in
        let r = raw.runs[i].rect
        return !inside.contains(i) && r.maxY <= box.minY + 1 && r.maxY > box.minY - reach && r.minX >= box.minX - 4 && r.maxX <= box.maxX + 4 && raw.runs[i].words.count <= 6
      }
      let isCaption = above.contains { i in
        let t = PageText.line(raw.runs[i].words)
        return Structure.captionPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
      }
      if !isCaption { took += above }
      for i in took { box = box.union(raw.runs[i].rect) }
      runs.formUnion(took)
      for (k, r) in raw.rules.enumerated() where box.insetBy(dx: -3, dy: -3).intersects(r) { rules.insert(k) }
      atoms.append(Atom(rect: box.insetBy(dx: -1, dy: -2), kind: .table, photo: false, lines: took.map { Self.line(from: raw.runs[$0]) }))
    }
    return (runs, rules)
  }

  /// Whether a stretch of the page has running text in it: several long lines at about the text's size.
  private func holdsProse(_ r: CGRect) -> Bool {
    var long = 0
    for run in raw.runs where run.words.count >= 5 && run.size >= body * 0.8 {
      if r.contains(CGPoint(x: run.rect.midX, y: run.rect.midY)) {
        long += 1
        if long >= 3 { return true }
      }
    }
    return false
  }

  /// Whether a stretch of the page holds a line of running text, outside `besides`.
  private func holdsText(_ r: CGRect, besides: [CGRect]) -> Bool {
    raw.runs.contains { run in
      let at = CGPoint(x: run.rect.midX, y: run.rect.midY)
      return run.words.count >= 6 && r.contains(at) && !besides.contains { $0.contains(at) }
    }
  }

  /// How much of `r` is covered by text.
  private func textCover(_ r: CGRect) -> CGFloat {
    var covered: CGFloat = 0
    for run in raw.runs where run.rect.intersects(r) {
      let o = run.rect.intersection(r)
      covered += o.width * o.height
    }
    return covered / max(r.width * r.height, 1)
  }

  // ─── Columns ─────────────────────────────────────────────────────────────

  private static func gaps(_ spans: [(lo: CGFloat, hi: CGFloat)]) -> [(lo: CGFloat, hi: CGFloat)] {
    let sorted = spans.sorted { $0.lo < $1.lo }
    guard var end = sorted.first?.hi else { return [] }
    var out: [(lo: CGFloat, hi: CGFloat)] = []
    for s in sorted.dropFirst() {
      if s.lo > end { out.append((end, s.lo)) }
      end = max(end, s.hi)
    }
    return out
  }

  /// A clear gutter down the whole of `els`: wide enough, and not just the gap
  /// between a list's bullets or a table's row labels and what follows them.
  private func gutters(_ els: [El]) -> [(lo: CGFloat, hi: CGFloat)] {
    let wide = max(body * 0.9, 5)
    var found = Self.gaps(els.map { ($0.rect.minX, $0.rect.maxX) }).filter { $0.hi - $0.lo >= wide }
    guard !found.isEmpty else { return [] }
    found = found.filter { g in
      let left = els.filter { $0.rect.maxX <= g.lo }
      let right = els.filter { $0.rect.minX >= g.hi }
      return !isMargin(left, beside: right) && !isMargin(right, beside: left)
    }
    return found
  }

  /// Whether `a` is only a column of bullets, numbers or labels, each set beside a line of `b`.
  private func isMargin(_ a: [El], beside b: [El]) -> Bool {
    guard !a.isEmpty, a.count <= b.count, a.allSatisfy({ $0.run >= 0 }) else { return false }
    let width = a.map(\.rect.maxX).max()! - a.map(\.rect.minX).min()!
    guard width < body * 3.5, b.contains(where: { $0.rect.width > body * 8 }) else { return false }
    return a.allSatisfy { e in
      let text = raw.runs[e.run].words.map(\.text).joined()
      return text.count <= 6 && b.contains { abs($0.rect.midY - e.rect.midY) < body }
    }
  }

  private func allOneLine(_ els: [El]) -> Bool {
    guard let first = els.first else { return true }
    return els.allSatisfy { $0.run >= 0 && abs($0.rect.midY - first.rect.midY) < min($0.rect.height, first.rect.height) * 0.6 }
  }

  /// Divides `rect` by the gutters and gaps among `els`, as far as they go.
  private func cut(_ rect: CGRect, _ els: [El], depth: Int) -> Node {
    let leaf = Node(.leaf, rect)
    leaf.els = els
    guard els.count > 1, depth < 18, !allOneLine(els) else { return leaf }
    if isFormulaRegion(els) { return leaf }

    // Columns first: a gutter clear down the whole stretch is the strongest thing a page can say.
    let down = gutters(els)
    if !down.isEmpty {
      let node = Node(.side, rect)
      var left = rect.minX
      var rest = els
      for g in down {
        let cutAt = (g.lo + g.hi) / 2
        let part = rest.filter { $0.rect.midX < cutAt }
        rest.removeAll { $0.rect.midX < cutAt }
        node.kids.append(cut(CGRect(x: left, y: rect.minY, width: cutAt - left, height: rect.height), part, depth: depth + 1))
        left = cutAt
      }
      node.kids.append(cut(CGRect(x: left, y: rect.minY, width: rect.maxX - left, height: rect.height), rest, depth: depth + 1))
      if measure.rtl { node.kids.reverse() }
      return node
    }

    // No gutter. Perhaps something runs across the columns, a title or a wide figure:
    // the gap that lets columns show on one side of it, wherever it is.
    let ys = Self.gaps(els.map { ($0.rect.minY, $0.rect.maxY) }).sorted { ($0.hi - $0.lo) > ($1.hi - $1.lo) }
    for g in ys.prefix(40) {
      let cutAt = (g.lo + g.hi) / 2
      let above = els.filter { $0.rect.midY < cutAt }
      let below = els.filter { $0.rect.midY >= cutAt }
      guard !above.isEmpty, !below.isEmpty else { continue }
      if (below.count >= 6 && !gutters(below).isEmpty && hasColumns(below)) || (above.count >= 6 && !gutters(above).isEmpty && hasColumns(above)) {
        return split(rect, els, at: [cutAt], depth: depth)
      }
    }

    // Otherwise, across wide gaps, which may free columns further in.
    let typical = medianLineGap(els)
    let wide = max(body * 0.85, typical * 1.5)
    let cuts = ys.filter { g in
      guard g.hi - g.lo >= wide else { return false }
      if g.hi - g.lo > body * 3 { return true }
      // Math above and below it, one over the other, is one formula.
      let above = els.filter { $0.run >= 0 && $0.rect.maxY <= g.lo + 0.5 && $0.rect.maxY > g.lo - body && mathRun(raw.runs[$0.run]) }
      let below = els.filter { $0.run >= 0 && $0.rect.minY >= g.hi - 0.5 && $0.rect.minY < g.hi + body && mathRun(raw.runs[$0.run]) }
      return !above.contains { a in below.contains { b in min(a.rect.maxX, b.rect.maxX) > max(a.rect.minX, b.rect.minX) - body * 2 } }
    }.map { ($0.lo + $0.hi) / 2 }.sorted()
    if !cuts.isEmpty { return split(rect, els, at: cuts, depth: depth) }
    return leaf
  }

  /// Whether everything in a stretch is the pieces of one displayed formula, whose gaps don't divide it.
  private func isFormulaRegion(_ els: [El]) -> Bool {
    guard els.count >= 2, els.allSatisfy({ $0.run >= 0 }) else { return false }
    let top = els.map(\.rect.minY).min()!
    let bottom = els.map(\.rect.maxY).max()!
    guard bottom - top < body * 11 else { return false }
    let math = els.filter { mathRun(raw.runs[$0.run]) }.count
    // Short bits of plain text ("where", "(4)") come with them, but sentences don't.
    let sentences = els.filter { raw.runs[$0.run].words.filter { $0.text.count >= 3 && $0.script == 0 }.count >= 5 && !mathRun(raw.runs[$0.run]) }.count
    return sentences == 0 && Double(math) >= Double(els.count) * 0.5
  }

  /// Whether a run is mostly math.
  private func mathRun(_ r: RawRun) -> Bool {
    var math = 0
    var total = 0
    for w in r.words {
      let n = w.text.count
      total += n
      if (fonts.indices.contains(w.font) && fonts[w.font].math) || w.script != 0 {
        math += n
      } else {
        math += w.text.unicodeScalars.filter(Structure.mathSymbols.contains).count
      }
    }
    return total > 0 && Double(math) / Double(total) > 0.3
  }

  private func split(_ rect: CGRect, _ els: [El], at cuts: [CGFloat], depth: Int) -> Node {
    let node = Node(.stack, rect)
    var top = rect.minY
    var rest = els
    for y in cuts + [rect.maxY + 1] {
      let bottom = min(y, rect.maxY)
      let part = rest.filter { $0.rect.midY < y }
      rest.removeAll { $0.rect.midY < y }
      let r = CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
      node.kids.append(cut(r, part, depth: depth + 1))
      top = bottom
    }
    return node
  }

  /// Whether the two sides of the first gutter both run on for a while, rather than a few stray lines.
  private func hasColumns(_ els: [El]) -> Bool {
    guard let g = gutters(els).max(by: { ($0.hi - $0.lo) < ($1.hi - $1.lo) }) else { return false }
    let left = els.filter { $0.rect.midX < g.lo }
    let right = els.filter { $0.rect.midX > g.hi }
    return left.count >= 2 && right.count >= 2
  }

  private func medianLineGap(_ els: [El]) -> CGFloat {
    let gaps = Self.gaps(els.map { ($0.rect.minY, $0.rect.maxY) }).map { $0.hi - $0.lo }.sorted()
    return gaps.isEmpty ? 0 : gaps[gaps.count / 2]
  }

  // ─── Tables ──────────────────────────────────────────────────────────────

  /// Narrow columns of short pieces whose rows line up aren't columns of text
  /// but a table, which has to be kept whole.
  private mutating func collapseTables(_ node: Node) {
    if node.kind == .side, let els = tableEls(node) {
      var box = els[0].rect
      for e in els { box = box.union(e.rect) }
      let lines = els.filter { $0.run >= 0 }.map { Self.line(from: raw.runs[$0.run]) }
      atoms.append(Atom(rect: box, kind: .table, photo: false, lines: lines))
      node.kind = .leaf
      node.kids = []
      node.els = [El(rect: box, atom: atoms.count - 1)]
      return
    }
    for k in node.kids { collapseTables(k) }
  }

  private func tableEls(_ node: Node) -> [El]? {
    var cols: [[El]] = []
    for k in node.kids {
      guard let leafEls = Self.gather(k), !leafEls.isEmpty else { return nil }
      cols.append(leafEls)
    }
    guard cols.count >= 2 else { return nil }
    let all = cols.flatMap { $0 }
    guard all.allSatisfy({ $0.run >= 0 }), all.count >= cols.count * 2 else { return nil }
    let runs = all.map { raw.runs[$0.run] }
    let meanWords = Double(runs.reduce(0) { $0 + $1.words.count }) / Double(runs.count)
    guard meanWords <= 6 else { return nil }
    // A magazine's narrow columns have short lines too, but they fill their column, and read as sentences.
    var filling = 0
    for c in cols {
      let lines = c.map { raw.runs[$0.run] }
      let widest = lines.map(\.rect.width).max() ?? 1
      let full = lines.filter { $0.rect.width > widest * 0.72 && $0.words.count >= 3 }.count
      if lines.count >= 4, Double(full) > Double(lines.count) * 0.55 { filling += 1 }
    }
    if filling * 2 >= cols.count { return nil }
    // Sentences mean text, even with a real table sitting in one of the columns.
    if Double(runs.filter { $0.words.count >= 7 }.count) > Double(runs.count) * 0.2 { return nil }
    // Rows: baselines, and how many of them more than one column shares.
    let baselines = runs.map(\.baseline).sorted()
    var rows: [CGFloat] = []
    for b in baselines where rows.last.map({ b - $0 > 2.5 }) ?? true { rows.append(b) }
    var shared = 0
    for row in rows {
      let touching = cols.filter { c in c.contains { abs(raw.runs[$0.run].baseline - row) <= 2.5 } }.count
      if touching >= 2 { shared += 1 }
    }
    guard rows.count >= 2, Double(shared) >= Double(rows.count) * 0.45 else { return nil }
    // Two columns of the same long lines are text, however well their baselines line up.
    let wideRuns = runs.filter { $0.rect.width > node.rect.width * 0.3 }.count
    if cols.count == 2 && Double(wideRuns) > Double(runs.count) * 0.5 { return nil }
    return all
  }

  private static func gather(_ node: Node) -> [El]? {
    switch node.kind {
    case .leaf: return node.els
    case .stack, .side: return node.kids.flatMap { gather($0) ?? [] }
    }
  }

  // ─── Lines ───────────────────────────────────────────────────────────────

  private static func line(from run: RawRun) -> TextLine {
    TextLine(words: run.words, rect: run.rect, baseline: run.baseline, size: run.size, font: run.font, color: run.color, text: PageText.line(run.words), runs: 1)
  }

  /// Puts runs on the same baseline together, across whatever gaps there are.
  private func lines(_ els: [El]) -> [TextLine] {
    let runs = els.filter { $0.run >= 0 }.map { raw.runs[$0.run] }.sorted { $0.baseline < $1.baseline }
    // A fraction or a stacked script, sitting in a gap in a line of text, isn't a line itself.
    let substantial = runs.filter { $0.words.count >= 3 || $0.rect.width > body * 8 }
    var strays: [RawRun] = []
    var spine: [RawRun] = []
    for r in runs {
      if r.words.count < 3 && r.rect.width <= body * 8, !substantial.isEmpty,
        substantial.contains(where: { abs($0.baseline - r.baseline) < max($0.size, r.size) * 0.95 && overlapX($0.rect, r.rect) < 0.5 }),
        // A label of its own, well clear of any text, stays a line.
        substantial.contains(where: { abs($0.baseline - r.baseline) < max($0.size, r.size) * 0.95 && !(r.rect.minX > $0.rect.maxX + body * 2 || r.rect.maxX < $0.rect.minX - body * 2) })
      {
        strays.append(r)
      } else {
        spine.append(r)
      }
    }
    var groups: [[RawRun]] = []
    for r in spine {
      // Runs of another size may be raised or lowered from the line they belong to.
      let reach = { (b: RawRun) -> CGFloat in abs(r.size - b.size) > 0.5 ? max(r.size, b.size) * 0.55 : min(r.size, b.size) * 0.5 }
      if let g = groups.last, g.contains(where: { abs(r.baseline - $0.baseline) < reach($0) }), !g.contains(where: { overlapX($0.rect, r.rect) > 0.5 }) {
        groups[groups.count - 1].append(r)
      } else {
        groups.append([r])
      }
    }
    for r in strays {
      guard
        let at = groups.indices.min(by: { a, b in
          func distance(_ i: Int) -> CGFloat { groups[i].map { abs($0.baseline - r.baseline) }.min() ?? .infinity }
          return distance(a) < distance(b)
        })
      else { continue }
      groups[at].append(r)
    }
    return groups.map { g in
      let sorted = measure.rtl ? g.sorted { $0.rect.minX > $1.rect.minX } : g.sorted { $0.rect.minX < $1.rect.minX }
      var rect = sorted[0].rect
      for r in sorted { rect = rect.union(r.rect) }
      let main = sorted.max { $0.rect.width < $1.rect.width }!
      // Parts that touch are one word, and parts set small and off the line are its scripts.
      var words: [RawWord] = []
      for (k, r) in sorted.enumerated() {
        var part = r.words
        let off = main.baseline - r.baseline
        if r.size < main.size * 0.86, abs(off) > main.size * 0.1 {
          for w in part.indices where part[w].script == 0 { part[w].script = off > 0 ? 1 : -1 }
        }
        if k > 0, let first = part.indices.first {
          let gap = measure.rtl ? sorted[k - 1].rect.minX - r.rect.maxX : r.rect.minX - sorted[k - 1].rect.maxX
          if gap < main.size * 0.15 { part[first].glued = true }
        }
        words += part
      }
      let byX = g.sorted { $0.rect.minX < $1.rect.minX }
      let wide = zip(byX, byX.dropFirst()).filter { $1.rect.minX - $0.rect.maxX > main.size * 1.5 }.count
      return TextLine(
        words: words, rect: rect, baseline: main.baseline, size: main.size, font: main.font, color: main.color, text: PageText.line(words), runs: wide + 1)
    }
  }

  private func overlapX(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let o = min(a.maxX, b.maxX) - max(a.minX, b.minX)
    return o / max(min(a.width, b.width), 1)
  }

  // ─── Blocks ──────────────────────────────────────────────────────────────

  private func style(_ l: TextLine) -> (bold: Bool, mono: Bool) {
    guard fonts.indices.contains(l.font) else { return (false, false) }
    return (fonts[l.font].bold, fonts[l.font].mono)
  }

  /// Whether a line starts a list item.
  static func opensItem(_ t: String) -> Bool {
    guard let first = t.first else { return false }
    if "•◦▪▫‣●○■□◆◇➢➤✓✔∙·*".contains(first) { return true }
    if "–—-".contains(first), t.dropFirst().first == " " { return true }
    return itemPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
  }

  private static let itemPattern = try! NSRegularExpression(pattern: #"^(\(?\d{1,3}[.)]|\(?[a-zA-Z][.)]|\[\d{1,4}\]|\(?[ivxIVX]{1,4}[.)])\s"#)

  /// Whether a line is a displayed formula: mostly math, and set in from both sides of its column.
  private func isFormula(_ l: TextLine, left: CGFloat, right: CGFloat) -> Bool {
    let width = max(right - left, 1)
    guard l.rect.minX - left > width * 0.04 || l.rect.maxX < right - width * 0.04 else { return false }
    var math = 0
    var total = 0
    for w in l.words {
      let n = w.text.count
      total += n
      if (fonts.indices.contains(w.font) && fonts[w.font].math) || w.script != 0 {
        math += n
      } else {
        math += w.text.unicodeScalars.filter(Structure.mathSymbols.contains).count
      }
    }
    // Sentences have long words of plain letters; a formula has few.
    let longest = l.words.filter { $0.script == 0 && !(fonts.indices.contains($0.font) && fonts[$0.font].math) }.map(\.text.count).max() ?? 0
    return total > 0 && Double(math) / Double(total) > 0.3 && l.words.count <= 40 && longest <= 8
  }

  /// Divides a column's lines into paragraphs, by the leading, the indents, and what the type does.
  private func paragraphs(_ lines: [TextLine]) -> [[TextLine]] {
    guard !lines.isEmpty else { return [] }
    let left = lines.map(\.rect.minX).min()!
    let right = lines.map(\.rect.maxX).max()!
    let width = max(right - left, 1)
    let steps = zip(lines, lines.dropFirst()).map { $1.baseline - $0.baseline }.filter { $0 > 0 }.sorted()
    let leading = steps.isEmpty ? (lines[0].size * 1.2) : steps[steps.count / 2]

    var out: [[TextLine]] = []
    var current = [lines[0]]
    var hanging = false
    for b in lines.dropFirst() {
      let a = current.last!
      let em = max(a.size, b.size)
      let step = b.baseline - a.baseline
      let (sa, sb) = (style(a), style(b))
      var breaks = false
      // The lines of a displayed formula, a sum's limits and a fraction's parts among them, are one thing.
      if isFormula(a, left: left, right: right), isFormula(b, left: left, right: right) {
        if step > max(leading * 2.4, em * 3) {
          out.append(current)
          current = [b]
          hanging = false
        } else {
          current.append(b)
        }
        continue
      }
      // The type changes. A line's dominant font can change just because a few of its
      // words do, so a change of font alone counts only where the line before stopped.
      if abs(a.size - b.size) > max(0.6, em * 0.08) { breaks = true }
      if sa.bold != sb.bold || sa.mono != sb.mono, Structure.endsSentence(a.text) || a.rect.maxX < right - width * 0.1 { breaks = true }
      // A gap wider than the text keeps between its lines.
      if step > max(leading * 1.3, em * 1.5) { breaks = true }
      // A displayed formula stands apart from the sentence that leads into it, and the one after.
      if isFormula(a, left: left, right: right) != isFormula(b, left: left, right: right) { breaks = true }
      // A new list item.
      if Self.opensItem(b.text) && !Self.opensItem(a.text) || (Self.opensItem(b.text) && step > 0) { breaks = true }
      let centered = abs(a.rect.midX - b.rect.midX) < 2.5 && a.rect.minX - left > em && b.rect.minX - left > 0.5
      if !centered {
        let ax = a.rect.minX - left
        let bx = b.rect.minX - left
        let first = current[0].rect.minX - left
        if current.count == 1 && bx > ax + em * 0.7 && a.rect.maxX > right - width * 0.12 {
          // Indented under its first line: a hanging entry, as a list or a bibliography has.
          hanging = true
        } else if hanging && bx < (current.last!.rect.minX - left) - em * 0.7 && abs(bx - first) < em * 0.5 {
          breaks = true
        } else if !hanging && bx > ax + em * 0.7 && ax < em * 0.6 {
          // Indented where the line before wasn't: a new paragraph, as printed books have them.
          breaks = true
        }
        // A short line that ends a sentence, then one that starts one.
        if a.rect.maxX < right - width * 0.15, step > 0, Structure.endsSentence(a.text), b.text.first?.isUppercase == true || b.text.first?.isNumber == true, !hanging {
          breaks = true
        }
      }
      if breaks {
        out.append(current)
        current = [b]
        hanging = false
      } else {
        current.append(b)
      }
    }
    out.append(current)
    return out
  }

  /// Rows of a table left in with text: lines of wide gaps, one after another, with their gaps in the same places.
  private func carveTables(_ lines: [TextLine]) -> [(lines: [TextLine], table: Bool)] {
    var out: [(lines: [TextLine], table: Bool)] = []
    var i = 0
    while i < lines.count {
      var j = i
      while j < lines.count, lines[j].runs >= 3 { j += 1 }
      if j - i >= 2 {
        out.append((Array(lines[i..<j]), true))
        i = j
      } else {
        let start = i
        i = max(j, i + 1)
        while i < lines.count {
          var k = i
          while k < lines.count, lines[k].runs >= 3 { k += 1 }
          if k - i >= 2 { break }
          i += 1
        }
        out.append((Array(lines[start..<i]), false))
      }
    }
    return out
  }

  // ─── Tiles ───────────────────────────────────────────────────────────────

  private func build(_ node: Node, _ blocks: inout [PageBlock]) -> PageTile {
    switch node.kind {
    case .stack, .side:
      let kids = node.kids.map { build($0, &blocks) }
      return PageTile(kind: node.kind == .stack ? .stack : .side, rect: node.rect, kids: kids)
    case .leaf:
      return leaf(node, &blocks)
    }
  }

  private func leaf(_ node: Node, _ blocks: inout [PageBlock]) -> PageTile {
    let atomEls = node.els.filter { $0.atom >= 0 }
    let textEls = node.els.filter { $0.run >= 0 }
    let found = lines(textEls)
    guard !(atomEls.isEmpty && found.isEmpty) else { return PageTile(kind: .blank, rect: node.rect) }

    // Text beside a picture with no gutter to go by (wrapped around it, or laid over
    // it) can't be moved without tearing the page. The tile stays as it is; what it says is still read.
    let tangled = atomEls.contains { a in
      found.contains { l in
        let o = min(a.rect.maxY, l.rect.maxY) - max(a.rect.minY, l.rect.minY)
        return o > l.rect.height * 0.5 && a.rect.intersects(l.rect.insetBy(dx: -body, dy: 0))
      }
    }
    if tangled {
      for a in atomEls { blocks.append(pictureBlock(atoms[a.atom], tile: a.rect, loose: true)) }
      for g in paragraphs(found) {
        blocks.append(PageBlock(kind: .text, lines: g, ink: Self.bounds(g), tile: Self.bounds(g), loose: true))
      }
      return PageTile(kind: .blank, rect: node.rect)
    }

    // In order down the column: pictures and paragraphs.
    enum Item {
      case picture(Atom)
      case text([TextLine])
      case rows([TextLine])
      var top: CGFloat {
        switch self {
        case let .picture(a): return a.rect.minY
        case let .text(l), let .rows(l): return l[0].rect.minY
        }
      }
    }
    var items: [Item] = atomEls.map { .picture(atoms[$0.atom]) }
    var stretches: [[TextLine]] = [[]]
    let walls = atomEls.map(\.rect.midY).sorted()
    var wall = 0
    for l in found {
      while wall < walls.count, l.rect.midY > walls[wall] {
        wall += 1
        if !stretches[stretches.count - 1].isEmpty { stretches.append([]) }
      }
      stretches[stretches.count - 1].append(l)
    }
    for part in stretches.filter({ !$0.isEmpty }).flatMap(carveTables) {
      if part.table {
        items.append(.rows(part.lines))
      } else {
        items += paragraphs(part.lines).map { .text($0) }
      }
    }
    items.sort { $0.top < $1.top }

    func ink(_ item: Item) -> CGRect {
      switch item {
      case let .picture(a): return a.rect
      case let .text(l), let .rows(l): return Self.bounds(l)
      }
    }
    var kids: [PageTile] = []
    var top = node.rect.minY
    for (i, item) in items.enumerated() {
      let box = ink(item)
      let bottom: CGFloat
      if i + 1 < items.count {
        bottom = max(top, min(node.rect.maxY, max(box.maxY + 0.5, (box.maxY + ink(items[i + 1]).minY) / 2)))
      } else {
        bottom = node.rect.maxY
      }
      let tile = CGRect(x: node.rect.minX, y: top, width: node.rect.width, height: bottom - top)
      top = bottom
      var block: PageBlock
      switch item {
      case let .picture(a): block = pictureBlock(a, tile: tile, loose: false)
      case let .rows(l): block = PageBlock(kind: .table, lines: l, ink: box, tile: tile)
      case let .text(l): block = PageBlock(kind: .text, lines: l, ink: box, tile: tile)
      }
      block.tile = tile
      blocks.append(block)
      kids.append(PageTile(kind: .block, rect: tile, block: blocks.count - 1, piece: 0))
    }
    return kids.count == 1 ? kids[0] : PageTile(kind: .stack, rect: node.rect, kids: kids)
  }

  private func pictureBlock(_ a: Atom, tile: CGRect, loose: Bool) -> PageBlock {
    PageBlock(kind: a.kind, lines: a.lines, ink: a.rect, tile: tile, loose: loose, photo: a.photo)
  }

  private static func bounds(_ lines: [TextLine]) -> CGRect {
    var r = lines[0].rect
    for l in lines { r = r.union(l.rect) }
    return r
  }
}
