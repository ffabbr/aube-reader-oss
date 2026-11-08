import UIKit

// ─── Plans ───────────────────────────────────────────────────────────────────

enum Paper {
  /// The page for a look: the text's paragraphs, in order, and whatever that
  /// look sets around them. The plain and paper looks show the first `core`
  /// of the `n` paragraphs; the journal shows them all. `height` is how tall a
  /// paragraph reads now, for balancing the journal's columns.
  static func plan(
    _ style: ReadingStyle, _ sheet: Sheet, _ manuscript: Manuscript, core: Int, paragraphs n: Int,
    traits: UITraitCollection = .current, height: (Int) -> Double
  ) -> [Band] {
    let press = Press(style: style, sheet: sheet, manuscript: manuscript, traits: traits)
    switch style {
    case .plain: return [.span((0..<core).map { .para($0) })]
    case .paper: return press.paper(core)
    case .journal: return press.journal(core, n, height: height)
    }
  }
}

/// Sets everything on the page that isn't the paragraphs, in the look's type.
struct Press {
  let style: ReadingStyle
  let sheet: Sheet
  /// The paper whose title page, sections and figures it sets; a document
  /// brought in sets only its own text, and never asks.
  var manuscript: Manuscript = .attention
  /// The appearance the page is set for, which the marks of its notes are drawn in.
  var traits: UITraitCollection = .current

  var serif: Bool { style == .journal }
  /// The body text size.
  var size: CGFloat { sheet.fontSize }
  private var column: CGFloat { CGFloat(sheet.column) }
  private var full: CGFloat { CGFloat(sheet.width) }
  /// The whole width of the text.
  var fullWidth: CGFloat { full }

  // ─── Paper ─────────────────────────────────────────────────────────────

  fileprivate func paper(_ n: Int) -> [Band] {
    let w = full
    var e: [Entry] = []
    let m = manuscript
    e.append(text(rich(m.preprint, size: size * 0.62, color: Palette.muted, bold: true, tracking: 1.4), width: w, below: size * 1.1))
    e.append(landmark(text(rich(m.title, size: size * 1.7, bold: true, leading: 1.18), width: w, below: size * 0.8), m.title, level: 0))
    e.append(marked(m.byline, size: size * 0.9, width: w, below: size * 0.3))
    let places = m.affiliations.enumerated().map { "^{\($0 + 1)}\($1.short)" }.joined(separator: "   ")
    e.append(text(rich(places, size: size * 0.7, color: Palette.quiet, leading: 1.5), width: w, below: size * 1.6))
    e.append(abstractBlock(width: w))
    e.append(text(rich("**Keywords**   " + m.keywords, size: size * 0.7, color: Palette.quiet, leading: 1.5), width: w, below: size * 0.6))
    e.append(rule(width: w, below: 0))

    var counter = Counter()
    var placed = Set<Int>()
    let numbers = m.numbers(journal: false)
    // Whether the last thing set was a heading, which the next one sits closer under.
    var opened = false
    for (k, s) in m.sections.enumerated() {
      let shown = s.paragraphs.filter { $0 < n }
      // A section whose text this look leaves out goes; one that opens onto subsections stays.
      guard !shown.isEmpty || s.paragraphs.isEmpty else { continue }
      e.append(heading(s, number: numbers[k], width: w, first: k == 0, under: opened))
      opened = shown.isEmpty && s.after.isEmpty
      for i in shown {
        e.append(.para(i))
        e += (s.within[i] ?? []).map { extra($0, &counter, width: w) }
      }
      placed.formUnion(shown)
      e += s.after.map { extra($0, &counter, width: w) }
    }
    for i in 0..<n where !placed.contains(i) { e.append(.para(i)) }

    if let thanks = m.acknowledgements {
      e.append(landmark(text(rich("Acknowledgements", size: size * 1.05, bold: true), width: w, above: size * 2, below: size * 0.5), "Acknowledgements", level: 1))
      e.append(text(rich(thanks, size: size * 0.85, color: Palette.quiet, leading: 1.5), width: w))
    }
    e.append(landmark(text(rich("References", size: size * 1.2, bold: true), width: w, above: size * 2, below: size * 0.7), "References", level: 1))
    e.append(text(references(m.references, from: 1, size: size * 0.72, color: Palette.quiet), width: w, below: size * 2))
    if let notes = footnotes(size: size * 0.72, color: Palette.quiet, width: w) { e.append(notes) }
    return [.span(e)]
  }

  private func abstractBlock(width: CGFloat) -> Entry {
    let label = rich("ABSTRACT", size: size * 0.62, color: Palette.muted, bold: true, tracking: 1.4)
    let body = rich(manuscript.abstract, size: size * 0.85, color: Palette.quiet, leading: 1.5)
    let inset: CGFloat = 20
    let lh = textHeight(label, width - inset)
    let bh = textHeight(body, width - inset)
    let gap = size * 0.5
    let below = size * 1.1
    return .block(
      Block(width: width, height: lh + gap + bh + below) { _ in
        resolved(Palette.line).setFill()
        UIRectFill(CGRect(x: 0, y: 2, width: 3, height: lh + gap + bh - 2))
        drawText(label, CGRect(x: inset, y: 0, width: width - inset, height: lh))
        drawText(body, CGRect(x: inset, y: lh + gap, width: width - inset, height: bh))
      })
  }

  /// The notes that aren't marked in the text but on the title page, set under a short rule as a
  /// paper prints them at the foot of its first page; nil if there are none. Those marked in the text open from their marks.
  private func footnotes(size s: CGFloat, color: UIColor, width: CGFloat) -> Entry? {
    let m = manuscript
    let ids = Array(Set(m.authorNotes.flatMap { $0 })).sorted()
    guard !ids.isEmpty else { return nil }
    let lines = ids.compactMap { id in m.notes[id].map { "^{\($0.label)}\u{2009}" + $0.text } }.joined(separator: "\n")
    let body = typed(lines, math: true, literal: false, labels: [:], size: s, color: color, align: serif ? .justified : .natural, leading: 1.35, traits: traits)
    let h = textHeight(body, width)
    let above = s * 1.2
    return .block(
      Block(width: width, height: above + 6 + h + s * 2) { _ in
        resolved(Palette.line).setFill()
        UIRectFill(CGRect(x: 0, y: above, width: width * 0.2, height: 0.6))
        drawText(body, CGRect(x: 0, y: above + 6, width: width, height: h))
      })
  }

  // ─── Journal ───────────────────────────────────────────────────────────

  fileprivate func journal(_ core: Int, _ n: Int, height: (Int) -> Double) -> [Band] {
    let w = full
    let col = column
    let m = manuscript
    var head: [Entry] = []
    head.append(runningHead(width: w))
    head.append(landmark(text(rich(m.title, size: size * 1.32, bold: true, align: .center, leading: 1.2), width: w, inset: w * 0.06, below: size * 0.9), m.title, level: 0))
    head.append(marked(m.journalByline, size: size * 0.98, align: .center, width: w, below: size * 0.35))
    let places = m.affiliations.enumerated().map { "^{\($0 + 1)}*\($1.full)*" }.joined(separator: "\n")
    head.append(text(rich(places, size: size * 0.8, align: .center, leading: 1.3), width: w, below: size * 0.6))
    head.append(text(rich(m.received, size: size * 0.78, align: .center), width: w, below: size * 1.1))
    head.append(text(rich(m.abstract, size: size * 0.92, align: .justified, leading: 1.28), width: w, inset: w * 0.07, below: size * 0.7))
    head.append(text(rich(m.doi, size: size * 0.78, align: .center), width: w, below: size * 1.6))

    // The text runs down the left column and on at the top of the right, split
    // where the two come out most even for the paragraphs as they read now.
    // Equations follow their paragraph; figures and tables follow the section.
    var bands: [Band] = [.span(head)]
    var counter = Counter()
    var flow: [(entry: Entry, height: Double, heading: Bool)] = []
    var wide: [Entry] = []
    func add(_ e: Entry, heading: Bool = false) {
      switch e {
      case let .para(i): flow.append((e, height(i), false))
      case let .block(b): flow.append((e, b.height, heading))
      }
    }
    func spans(_ x: Extra) -> Bool {
      guard sheet.columns > 1 else { return false }
      switch x {
      case let .figure(f): return f.wide
      case let .table(t): return m.tables[safe: t]?.wide ?? false
      case .equation: return false
      }
    }
    // Sets out the text gathered so far, in columns.
    func flush() {
      guard !flow.isEmpty else { return }
      guard sheet.columns > 1 else {
        bands.append(.span(flow.map(\.entry)))
        flow = []
        return
      }
      for (k, page) in pages(flow.map { ($0.height, $0.heading) }).enumerated() {
        // Where one page's columns end and the next's begin, a rule across both, so the eye goes back to the left.
        if k > 0 { bands.append(.span([rule(width: w, above: size * 0.9, below: size * 1.4)])) }
        let items = Array(flow[page])
        let split = balance(items.map { ($0.height, $0.heading) })
        bands.append(.columns([items[..<split].map(\.entry), items[split...].map(\.entry)]))
      }
      flow = []
    }
    var placed = Set<Int>()
    let numbers = m.numbers(journal: true)
    var opened = false
    for (k, s) in m.sections.enumerated() {
      let shown = s.paragraphs.filter { $0 < core }
      guard !shown.isEmpty || s.paragraphs.isEmpty else { continue }
      // A section of figures alone, such as an appendix, starts on a page of its own.
      if m.paged, s.paragraphs.isEmpty, !s.after.isEmpty, s.after.allSatisfy(spans) {
        flush()
        bands.append(.span([heading(s, number: numbers[k], width: w, first: false, under: false)] + s.after.map { extra($0, &counter, width: w) }))
        continue
      }
      add(heading(s, number: numbers[k], width: col, first: k == 0, under: opened), heading: true)
      opened = shown.isEmpty && s.after.isEmpty
      func place(_ x: Extra) {
        if spans(x) { wide.append(extra(x, &counter, width: w)) } else { add(extra(x, &counter, width: col)) }
      }
      for i in shown {
        add(.para(i))
        for x in s.within[i] ?? [] { place(x) }
      }
      placed.formUnion(shown)
      let after = s.after
      for x in after { if case .equation = x { add(extra(x, &counter, width: col)) } }
      for j in s.more where j < n {
        add(.para(j))
        placed.insert(j)
      }
      for x in after {
        if case .equation = x { continue }
        place(x)
      }
      // On a paper set out page by page, what runs across both columns comes after the page it's mentioned on.
      if m.paged, !wide.isEmpty {
        flush()
        bands.append(.span(wide))
        wide = []
      }
    }
    for j in 0..<n where !placed.contains(j) { add(.para(j)) }
    if let thanks = m.acknowledgements {
      add(landmark(text(rich("ACKNOWLEDGMENTS", size: size * 0.86, bold: true, align: .center, tracking: 0.5), width: col, above: size, below: size * 0.55), "Acknowledgements", level: 1), heading: true)
      add(text(rich(thanks, size: size, align: .justified, leading: 1.3), width: col))
    }
    flush()
    bands.append(.span(wide))

    // References in footnote type, split across the columns.
    let refs = m.references
    let half = (refs.count + 1) / 2
    let small = size * 0.78
    bands.append(.span([landmark(rule(width: w, short: true, above: size * 0.6, below: size * 0.8), "References", level: 1)]))
    if sheet.columns > 1 {
      bands.append(
        .columns([
          [text(references(Array(refs[..<half]), from: 1, size: small), width: col)],
          [text(references(Array(refs[half...]), from: half + 1, size: small), width: col)],
        ]))
    } else {
      bands.append(.span([text(references(refs, from: 1, size: small), width: col)]))
    }
    if let notes = footnotes(size: small, color: Palette.ink, width: w) { bands.append(.span([notes])) }
    bands.append(.span([footer(width: w)]))
    return bands
  }

  /// How a paper set out page by page divides the text gathered between two
  /// wide figures: into runs that fill both columns of a page, about as tall as
  /// a printed page is for its width, never leaving a heading at a page's foot.
  /// A paper set out at once is one run.
  private func pages(_ items: [(height: Double, heading: Bool)]) -> [Range<Int>] {
    guard manuscript.paged, !items.isEmpty else { return [0..<items.count] }
    // As few pages as hold it, each filled about as full as the others, so the last isn't a scrap.
    let total = items.reduce(0) { $0 + $1.height }
    let count = max(1, Int((total / (sheet.width * 1.3 * 2)).rounded(.up)))
    let target = total / Double(count)
    var out: [Range<Int>] = []
    var start = 0
    var filled = 0.0
    for (k, item) in items.enumerated() {
      if k > start, out.count < count - 1, filled + item.height / 2 > target {
        // A heading goes over with what it heads.
        var cut = k
        while cut > start + 1, items[cut - 1].heading { cut -= 1 }
        out.append(start..<cut)
        start = cut
        filled = items[cut..<k].reduce(0) { $0 + $1.height }
      }
      filled += item.height
    }
    out.append(start..<items.count)
    return out
  }

  /// Where to start the right column so that the taller column is as short as
  /// it can be, never leaving a heading at the foot of the left one.
  private func balance(_ items: [(height: Double, heading: Bool)]) -> Int {
    let total = items.reduce(0) { $0 + $1.height }
    var best = items.count
    var bestTall = Double.infinity
    var left = 0.0
    for k in 1..<max(items.count, 1) {
      left += items[k - 1].height
      guard !items[k - 1].heading else { continue }
      let tall = max(left, total - left)
      if tall < bestTall {
        bestTall = tall
        best = k
      }
    }
    return best
  }

  /// The journal's name, volume and date above a rule, as at the top of every page.
  private func runningHead(width: CGFloat) -> Entry {
    let s = size * 0.72
    let left = rich(manuscript.journal, size: s, tracking: 0.3)
    let right = rich(manuscript.date, size: s, tracking: 0.3)
    let h = left.size().height
    let below = size * 1.6
    return .block(
      Block(width: width, height: h + 6 + 3 + below) { _ in
        left.draw(at: .zero)
        let rw = right.size().width
        if left.size().width + rw + 24 < width { right.draw(at: CGPoint(x: width - rw, y: 0)) }
        resolved(Palette.ink).setFill()
        UIRectFill(CGRect(x: 0, y: h + 5, width: width, height: 0.8))
        UIRectFill(CGRect(x: 0, y: h + 7.5, width: width, height: 0.8))
      })
  }

  private func footer(width: CGFloat) -> Entry {
    let s = size * 0.68
    let left = rich(manuscript.footer.left, size: s)
    let right = rich(manuscript.footer.right, size: s)
    let above = size * 2.2
    let h = left.size().height
    return .block(
      Block(width: width, height: above + 8 + h + size * 3) { _ in
        resolved(Palette.ink).setFill()
        UIRectFill(CGRect(x: 0, y: above, width: width, height: 0.6))
        left.draw(at: CGPoint(x: 0, y: above + 6))
        let rw = right.size().width
        if left.size().width + rw + 24 < width { right.draw(at: CGPoint(x: width - rw, y: above + 6)) }
      })
  }

  // ─── Pieces both looks use ─────────────────────────────────────────────

  private struct Counter {
    var equation = 0
    var figure = 0
    var table = 0
  }

  /// A section's heading, numbered `number`. One `under` another, with nothing
  /// between them, sits closer beneath it.
  private func heading(_ s: Manuscript.Section, number: String?, width: CGFloat, first: Bool, under: Bool) -> Entry {
    let title = s.title
    if serif {
      let n = number.map { "\($0). " } ?? ""
      let line: NSAttributedString
      switch s.level {
      case 1: line = rich(n + title.uppercased(), size: size * 0.86, bold: true, align: .center, tracking: 0.5)
      case 2: line = rich(n + title, size: size * 0.92, bold: true, align: .center)
      default: line = rich("*" + n + title + "*", size: size * 0.92, align: .natural)
      }
      let above = first || under ? size * 0.2 : size * (s.level == 1 ? 1.0 : 0.8)
      return landmark(text(line, width: width, above: first ? 0 : above, below: size * 0.55), title, level: s.level)
    }
    let n = number.map { "\($0)\u{2003}" } ?? ""
    let scale: CGFloat = s.level == 1 ? 1.2 : s.level == 2 ? 1.05 : 0.95
    let line = rich(n + title, size: size * scale, bold: true)
    let above: CGFloat = under ? size * 0.5 : first ? size * 1.6 : size * (s.level == 1 ? 2.0 : 1.5)
    return landmark(text(line, width: width, above: above, below: size * 0.55), title, level: s.level)
  }

  /// `entry`, under the name the contents know it by.
  private func landmark(_ entry: Entry, _ title: String, level: Int) -> Entry {
    if case let .block(b) = entry { b.landmark = (title, level) }
    return entry
  }

  private func extra(_ x: Extra, _ counter: inout Counter, width: CGFloat) -> Entry {
    switch x {
    case let .equation(tex):
      counter.equation += 1
      return equation(tex, number: counter.equation, width: width)
    case let .figure(f):
      counter.figure += 1
      return figure(f, number: counter.figure, width: width)
    case let .table(t):
      counter.table += 1
      return table(manuscript.tables[safe: t], number: counter.table, width: width)
    }
  }

  /// A line of the title page whose notes open from their marks.
  private func marked(_ s: String, size: CGFloat, align: NSTextAlignment = .natural, width: CGFloat, below: CGFloat) -> Entry {
    let a = typed(s, math: false, literal: false, labels: manuscript.noteLabels, size: size, align: align, traits: traits)
    let entry = text(a, width: width, below: below)
    if case let .block(b) = entry { b.show(Press.markRects(a, width: width, origin: .zero), traits: traits) }
    return entry
  }

  /// A displayed equation, centered, with its number at the right. Its fractions are stacked,
  /// as displayed math sets them, and the line grows to hold them.
  private func equation(_ tex: String, number: Int, width: CGFloat) -> Entry {
    let family = serif ? "Times New Roman" : nil
    let tag = rich("(\(number))", size: size)
    let tagW = tag.size().width
    var mathSize = size * 1.04
    var math = TeX(tex, size: mathSize, family: family, display: true)
    let room = width - 2 * (tagW + 12)
    if math.x > room {
      mathSize *= room / math.x
      math = TeX(tex, size: mathSize, family: family, display: true)
    }
    let reach = TeX.extent(math.pieces)
    let above = size * (serif ? 0.45 : 0.7)
    // The usual line puts the baseline two thirds down it; a taller formula gets as much more room as it needs.
    let up = max(size * 1.9 * 0.66, reach.ascent + size * 0.25)
    let down = max(size * 1.9 * 0.34, reach.descent + size * 0.25)
    let below = size * (serif ? 0.45 : 0.7)
    let tagFont = font(size)
    return .block(
      Block(width: width, height: above + up + down + below) { _ in
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let baseline = above + up
        ctx.setFillColor(resolved(Palette.ink).cgColor)
        drawPieces(math.pieces, in: ctx, x: ((width - math.x) / 2).rounded(), baseline: baseline)
        tag.draw(at: CGPoint(x: width - tagW, y: baseline - tagFont.ascender))
      })
  }

  /// A drawn figure and its caption.
  private func figure(_ f: Figure, number: Int, width: CGFloat) -> Entry {
    let aspect: CGFloat
    // A drawing as tall as it's wide is set no wider than it needs to be, centered.
    var drawn = width
    switch f {
    case .transformer:
      drawn = min(width, max(size * 25, 300))
      aspect = 1.18
    case .attention: aspect = width > 700 ? 0.46 : 0.66
    case .making, .anaphora: aspect = width > 700 ? 0.3 : 0.46
    case .signal: aspect = width > 700 ? 0.72 : 1.3
    case .waveform: aspect = width > 500 ? 0.66 : 1
    case .detector: aspect = width > 700 ? 0.52 : 1.15
    case .searches: aspect = width > 700 ? 0.36 : 0.62
    case .radius: aspect = serif ? 0.66 : 0.6
    case .star: aspect = serif ? 0.52 : 0.46
    case .cones: aspect = serif ? 0.62 : 0.58
    case .clocks: aspect = serif ? 0.6 : 0.54
    case .evidence, .dance: aspect = width > 700 ? (serif ? 0.3 : 0.34) : 0.5
    case .quorum: aspect = serif ? 0.6 : 0.54
    }
    let graphic = (drawn * aspect).rounded()
    let caption =
      serif
      ? rich("FIG. \(number). " + (manuscript.captions[f] ?? ""), size: size * 0.86, align: .justified, leading: 1.22)
      : rich("**Figure \(number).** " + (manuscript.captions[f] ?? ""), size: size * 0.75, color: Palette.quiet, leading: 1.45)
    let inset = serif ? 0 : width * 0.04
    let capH = textHeight(caption, width - 2 * inset)
    let above = size * (serif ? 0.7 : 1.4)
    let gap = size * 0.7
    let below = size * (serif ? 1.0 : 1.4)
    return .block(
      Block(width: width, height: above + graphic + gap + capH + below) { _ in
        self.draw(f, in: CGRect(x: ((width - drawn) / 2).rounded(), y: above, width: drawn, height: graphic))
        drawText(caption, CGRect(x: inset, y: above + graphic + gap, width: width - 2 * inset, height: capH))
      })
  }

  /// A table between rules, captioned above as tables are.
  private func table(_ t: Manuscript.Table?, number: Int, width: CGFloat) -> Entry {
    guard let t, t.header.count > 1 else { return .block(Block(width: width, height: 0) { _ in }) }
    let caption =
      serif
      ? rich("TABLE \(Manuscript.roman[safe: number - 1] ?? "\(number)"). " + t.caption, size: size * 0.86, align: .justified, leading: 1.22)
      : rich("**Table \(number).** " + t.caption, size: size * 0.75, color: Palette.quiet, leading: 1.45)
    let cols = t.header.count
    // Set at the size tables are, unless it's then too wide for the page; then as much smaller as it takes.
    func setting(_ ts: CGFloat) -> (header: [NSAttributedString], rows: [[NSAttributedString]], over: [NSAttributedString], widths: [CGFloat], pad: CGFloat) {
      let header = t.header.map { rich($0, size: ts, bold: !serif) }
      let rows = t.rows.map { $0.map { rich($0, size: ts) } }
      let over = t.over.map { rich($0.title, size: ts, bold: !serif) }
      var widths = header.map { $0.size().width }
      // A cell that runs on into the columns after it (marked "<") doesn't widen its own.
      for (k, row) in rows.enumerated() {
        for (j, c) in row.enumerated() where j < cols && !Self.joins(t.rows[k], j) { widths[j] = max(widths[j], c.size().width) }
      }
      // A heading over columns needs them wide enough together to sit over.
      for (k, o) in t.over.enumerated() where o.from < cols && o.to < cols {
        let under = widths[o.from...o.to].reduce(0, +) + ts * CGFloat(o.to - o.from)
        let need = over[k].size().width - under
        if need > 0 { widths[o.to] += need }
      }
      // Columns spread to fill the width, but not so far that a row stops reading as one.
      let pad = min(max(ts * 0.6, (width - widths.reduce(0, +)) / CGFloat(cols - 1)), ts * 3.5)
      return (header, rows, over, widths, pad)
    }
    var ts = size * (serif ? 0.84 : 0.72)
    var set = setting(ts)
    let natural = set.widths.reduce(0, +) + set.pad * CGFloat(cols - 1)
    if natural > width {
      ts = max(7, (ts * width / natural * 0.98).rounded(.down))
      set = setting(ts)
    }
    let (header, rows, over, widths, pad) = set
    let span = widths.reduce(0, +) + pad * CGFloat(cols - 1)
    let x0 = max(0, ((width - span) / 2).rounded())
    var xs: [CGFloat] = [x0]
    for j in 1..<cols { xs.append(xs[j - 1] + widths[j - 1] + pad) }
    let capH = textHeight(caption, width)
    let rowH = (ts * 1.65).rounded()
    let above = size * (serif ? 0.7 : 1.4)
    let gap = ts * 0.6
    let below = size * (serif ? 1.0 : 1.4)
    let overH = over.isEmpty ? 0 : rowH
    let tableH = rowH * CGFloat(rows.count + 1) + overH + 12 + CGFloat(t.breaks.count) * 3
    // Still too wide at the smallest type, as on a narrow window: drawn smaller still, whole.
    let fit = min(1, width / max(span, 1))
    return .block(
      Block(width: width, height: above + capH + gap + tableH * fit + below) { _ in
        drawText(caption, CGRect(x: 0, y: above, width: width, height: capH))
        var y = above + capH + gap
        if fit < 1, let ctx = UIGraphicsGetCurrentContext() {
          ctx.translateBy(x: 0, y: y)
          ctx.scaleBy(x: fit, y: fit)
          y = 0
        }
        resolved(Palette.ink).setFill()
        func hline(_ t: CGFloat, from: CGFloat? = nil, to: CGFloat? = nil) {
          let a = from ?? x0
          UIRectFill(CGRect(x: a, y: y, width: (to ?? x0 + span) - a, height: t))
        }
        // Journals rule a table twice above and below; preprints once, heavier.
        if serif {
          hline(0.6)
          y += 2.4
          hline(0.6)
          y += 3
        } else {
          hline(1.2)
          y += 4
        }
        // The first column reads as names, set from the left; the rest as values, each centered in its column.
        func cell(_ c: NSAttributedString, _ j: Int) {
          let x = j == 0 ? xs[0] : xs[j] + (widths[j] - c.size().width) / 2
          c.draw(at: CGPoint(x: x, y: y + (rowH - c.size().height) / 2))
        }
        if !over.isEmpty {
          for (k, o) in t.over.enumerated() where o.from < cols && o.to < cols {
            let left = xs[o.from]
            let right = xs[o.to] + widths[o.to]
            let c = over[k]
            c.draw(at: CGPoint(x: left + (right - left - c.size().width) / 2, y: y + (rowH - c.size().height) / 2 - 1))
            y += rowH - 2
            hline(0.5, from: left, to: right)
            y -= rowH - 2
          }
          y += rowH
        }
        func line(_ cells: [NSAttributedString], _ raw: [String]? = nil) {
          for (j, c) in cells.enumerated() where j < cols && raw?[j] != "<" {
            guard let raw, Self.joins(raw, j) else {
              cell(c, j)
              continue
            }
            // Centered across the columns it runs on into.
            var last = j
            while last + 1 < cols, raw[safe: last + 1] == "<" { last += 1 }
            let right = xs[last] + widths[last]
            c.draw(at: CGPoint(x: xs[j] + (right - xs[j] - c.size().width) / 2, y: y + (rowH - c.size().height) / 2))
          }
          y += rowH
        }
        line(header)
        hline(0.6)
        y += 2
        for (k, row) in rows.enumerated() {
          if t.breaks.contains(k) {
            y += 1
            hline(0.5)
            y += 2
          }
          line(row, t.rows[k])
        }
        if serif {
          hline(0.6)
          y += 2.4
          hline(0.6)
        } else {
          hline(1.2)
        }
      })
  }

  /// Whether a table's cell `j` runs on into the next, which is marked "<".
  private static func joins(_ row: [String], _ j: Int) -> Bool { row[safe: j + 1] == "<" }

  private func references(_ refs: [String], from first: Int, size s: CGFloat, color: UIColor = Palette.ink) -> NSAttributedString {
    // Room for the widest number, so that a list of tens still sets its entries in line.
    let indent = max(s * 2, (rich("[\(first + max(refs.count - 1, 0))]", size: s).size().width + s * 0.5).rounded(.up))
    let out = NSMutableAttributedString()
    for (i, r) in refs.enumerated() {
      let entry = rich("[\(first + i)]\t" + r + (i < refs.count - 1 ? "\n" : ""), size: s, color: color, align: serif ? .justified : .natural, leading: 1.3)
      out.append(entry)
    }
    let ps = NSMutableParagraphStyle()
    ps.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
    ps.defaultTabInterval = indent
    ps.headIndent = indent
    ps.alignment = serif ? .justified : .natural
    ps.minimumLineHeight = (s * 1.3).rounded()
    ps.maximumLineHeight = (s * 1.3).rounded()
    ps.paragraphSpacing = s * (serif ? 0.15 : 0.5)
    ps.hyphenationFactor = serif ? 0.8 : 0
    out.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: out.length))
    return out
  }

  private func rule(width: CGFloat, short: Bool = false, above: CGFloat = 0, below: CGFloat) -> Entry {
    .block(
      Block(width: width, height: above + 1 + below) { _ in
        resolved(short ? Palette.ink : Palette.line).setFill()
        let w = short ? width * 0.2 : width
        UIRectFill(CGRect(x: (width - w) / 2, y: above, width: w, height: short ? 0.6 : 1))
      })
  }

  /// A run of text across `width`, with room above and below.
  func textBlock(_ s: NSAttributedString, width: CGFloat, above: CGFloat = 0, below: CGFloat = 0) -> Entry {
    text(s, width: width, above: above, below: below)
  }

  /// A run of text across `width`, with room above and below, and `inset` from either side.
  private func text(_ s: NSAttributedString, width: CGFloat, inset: CGFloat = 0, above: CGFloat = 0, below: CGFloat = 0) -> Entry {
    let w = width - 2 * inset
    let h = textHeight(s, w)
    return .block(Block(width: width, height: above + h + below) { _ in drawText(s, CGRect(x: inset, y: above, width: w, height: h)) })
  }

  // ─── Type ──────────────────────────────────────────────────────────────

  func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
    if serif {
      let name =
        bold && italic
        ? "TimesNewRomanPS-BoldItalicMT" : bold ? "TimesNewRomanPS-BoldMT" : italic ? "TimesNewRomanPS-ItalicMT" : "TimesNewRomanPSMT"
      return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }
    let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    guard italic, let d = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
    return UIFont(descriptor: d, size: size)
  }

  /// Sets a little markup: *italic*, **bold**, _{subscript} and ^{superscript};
  /// a backslash keeps the next character as it is. `leading` fixes the line height, as a share of `size`.
  func rich(
    _ s: String, size: CGFloat, color: UIColor = Palette.ink, bold: Bool = false, align: NSTextAlignment = .natural,
    leading: CGFloat? = nil, tracking: CGFloat = 0
  ) -> NSMutableAttributedString {
    let out = NSMutableAttributedString()
    var italic = false
    var strong = bold
    var script = 0
    var run = ""
    // A script just closed with nothing after it yet: which way it went, and how wide it was.
    var closed: (script: Int, width: CGFloat)? = nil
    // The width of the script the one being set stacks under.
    var under: CGFloat? = nil
    var lastWidth: CGFloat = 0
    /// Moves what follows the last character on by `dx`.
    func nudge(_ dx: CGFloat) {
      guard out.length > 0 else { return }
      let r = NSRange(location: out.length - 1, length: 1)
      let kern = out.attribute(.kern, at: r.location, effectiveRange: nil) as? CGFloat ?? 0
      out.addAttribute(.kern, value: kern + dx, range: r)
    }
    func flush() {
      guard !run.isEmpty else { return }
      var attrs: [NSAttributedString.Key: Any] = [
        .font: font(script == 0 ? size : size * 0.7, bold: strong, italic: italic), .foregroundColor: color,
      ]
      if script != 0 { attrs[.baselineOffset] = script > 0 ? size * 0.36 : -size * 0.15 }
      if tracking != 0 { attrs[.kern] = tracking }
      let piece = NSAttributedString(string: run, attributes: attrs)
      lastWidth = piece.size().width
      out.append(piece)
      run = ""
      if script == 0 { closed = nil }
    }
    let chars = Array(s)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      let n = chars[safe: i + 1]
      if c == "\\", let n {
        run.append(n)
        i += 2
      } else if c == "*" {
        flush()
        if n == "*" {
          strong.toggle()
          i += 2
        } else {
          italic.toggle()
          i += 1
        }
      } else if c == "_" || c == "^", n == "{" {
        flush()
        script = c == "^" ? 1 : -1
        // A subscript straight after a superscript, or the other way about, stacks under it, as in 36^{+5}_{−4}.
        if let last = closed, last.script == -script {
          nudge(-last.width)
          under = last.width
        }
        closed = nil
        i += 2
      } else if c == "}" && script != 0 {
        lastWidth = 0
        flush()
        if let over = under {
          if over > lastWidth { nudge(over - lastWidth) }
          under = nil
        } else {
          closed = (script, lastWidth)
        }
        script = 0
        i += 1
      } else {
        run.append(c)
        i += 1
      }
    }
    flush()
    let ps = NSMutableParagraphStyle()
    ps.alignment = align
    if let leading {
      ps.minimumLineHeight = (size * leading).rounded()
      ps.maximumLineHeight = (size * leading).rounded()
    }
    ps.hyphenationFactor = align == .justified ? 0.9 : 0
    out.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: out.length))
    return out
  }
}

// ─── Drawing text ────────────────────────────────────────────────────────────

/// A color as it reads in the appearance being drawn.
func resolved(_ c: UIColor) -> UIColor { c.resolvedColor(with: .current) }

func textHeight(_ s: NSAttributedString, _ width: CGFloat) -> CGFloat {
  s.boundingRect(
    with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
    context: nil
  ).height.rounded(.up)
}

func drawText(_ s: NSAttributedString, _ rect: CGRect) {
  s.draw(with: rect.insetBy(dx: 0, dy: -1).offsetBy(dx: 0, dy: 1), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
}

// ─── Marks among words set by UIKit ──────────────────────────────────────────

extension Press {
  /// Text that wants more than `rich` gives it: its `$…$` formulas typeset, where it has `math`, and
  /// its marks `[^n]` set as taps on the notes `labels` names. A `literal` text, one found rather
  /// than written, takes every character as itself; any other reads `rich`'s markup.
  func typed(
    _ text: String, math: Bool, literal: Bool, labels: [Int: String], size: CGFloat, color: UIColor = Palette.ink,
    bold: Bool = false, align: NSTextAlignment = .natural, leading: CGFloat? = nil, traits: UITraitCollection
  ) -> NSAttributedString {
    let own = { (t: String) in literal ? Press.escaped(t) : t }
    guard math || text.contains("[^") else { return rich(own(text), size: size, color: color, bold: bold, align: align, leading: leading) }
    let out = NSMutableAttributedString()
    let ink = color.resolvedColor(with: traits)
    func words(_ part: String) {
      for piece in NoteToken.parts(part) {
        switch piece {
        case let .text(s):
          out.append(rich(own(s), size: size, color: color, bold: bold, align: align, leading: leading))
        case let .mark(id):
          guard let label = labels[id] else { continue }
          out.append(markRun(id, label, size: size, traits: traits))
        }
      }
    }
    if math {
      for (i, part) in text.components(separatedBy: "$").enumerated() {
        if i % 2 == 0 {
          words(part)
        } else {
          let (image, descent) = TeX.picture(part, size: size, color: ink)
          let attachment = NSTextAttachment()
          attachment.image = image
          attachment.bounds = CGRect(x: 0, y: -descent, width: image.size.width, height: image.size.height)
          out.append(NSAttributedString(attachment: attachment))
        }
      }
    } else {
      words(text)
    }
    // Marks and formulas have no line spacing of their own to bring in.
    if out.length > 0, let style = rich(" ", size: size, align: align, leading: leading).attribute(.paragraphStyle, at: 0, effectiveRange: nil) {
      out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
    }
    return out
  }

  /// A note's mark among words set by UIKit, the same size whatever they're set at.
  private func markRun(_ id: Int, _ label: String, size: CGFloat, traits: UITraitCollection) -> NSAttributedString {
    let diameter = Halo.diameter(self.size)
    let image = Halo.image(label, diameter: diameter, ink: Palette.ink.resolvedColor(with: traits), scale: max(traits.displayScale, 1))
    let attachment = NSTextAttachment()
    attachment.image = image
    // Level with the middle of the capitals beside it.
    attachment.bounds = CGRect(x: 0, y: font(size).capHeight / 2 - diameter / 2, width: image.size.width, height: diameter)
    let out = NSMutableAttributedString(string: "\u{2009}", attributes: [.font: font(size)])
    let mark = NSMutableAttributedString(attachment: attachment)
    mark.addAttribute(.noteMark, value: id, range: NSRange(location: 0, length: mark.length))
    out.append(mark)
    return out
  }

  /// Where the marks in `s` come out, set `width` wide with its top left at `origin`.
  static func markRects(_ s: NSAttributedString, width: CGFloat, origin: CGPoint) -> [TapMark] {
    var runs: [(id: Int, range: NSRange)] = []
    s.enumerateAttribute(.noteMark, in: NSRange(location: 0, length: s.length)) { value, range, _ in
      if let id = value as? Int { runs.append((id, range)) }
    }
    guard !runs.isEmpty else { return [] }
    let storage = NSTextStorage(attributedString: s)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    return runs.compactMap { run in
      guard let attachment = s.attribute(.attachment, at: run.range.location, effectiveRange: nil) as? NSTextAttachment else { return nil }
      let first = manager.glyphRange(forCharacterRange: run.range, actualCharacterRange: nil).location
      let line = manager.lineFragmentRect(forGlyphAt: first, effectiveRange: nil)
      let at = manager.location(forGlyphAt: first)
      let shown = attachment.bounds
      return TapMark(note: run.id, rect: CGRect(x: origin.x + line.minX + at.x, y: origin.y + line.minY + at.y - shown.minY - shown.height, width: shown.width, height: shown.height))
    }
  }

  /// Text as found holds asterisks and underscores that mean only themselves.
  static func escaped(_ t: String) -> String {
    var out = ""
    out.reserveCapacity(t.count)
    for c in t {
      if c == "*" || c == "\\" || c == "_" || c == "^" || c == "}" { out.append("\\") }
      out.append(c)
    }
    return out
  }
}
