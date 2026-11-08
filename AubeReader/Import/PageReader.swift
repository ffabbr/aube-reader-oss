import PDFKit
import UIKit

/// Reads one page of a PDF into runs of words and marks, in page points.
enum PageReader {
  private struct Char {
    let text: String
    let rect: CGRect
    let size: CGFloat
    let color: Tint
    /// Whether a space or line break came just before it.
    let spaced: Bool
    let strongRTL: Bool
  }

  /// Letters that hang below the line or sit above it, so they don't mark where it is.
  private static let offLine = Set("gjpqyQJ,;()[]{}/|\\\"'’‘“”^*°`~_-–—=+<>:")

  static func read(_ page: PDFPage, catalog: FontCatalog) -> RawPage {
    // A page set sideways or upside down is turned upright before anything else, for reading and for showing.
    let asFound = characters(page, frame: PageFrame(page))
    let turn = turnNeeded(asFound)
    if turn != 0 { page.rotation = (page.rotation + turn) % 360 }
    let frame = PageFrame(page)
    var raw = RawPage(size: frame.size)
    raw.turn = turn
    let scan = PageScan(page, frame: frame, catalog: catalog)
    raw.rules = scan.rules
    raw.panels = scan.panels
    raw.paper = scan.paper
    raw.marks = scan.images.map { RawMark(rect: $0, kind: .image) } + scan.vectors.map { RawMark(rect: $0, kind: .vector) } + scan.tints.map { RawMark(rect: $0, kind: .tint) }

    let chars = turn == 0 ? asFound : characters(page, frame: frame)
    let found = runs(chars, scan: scan, catalog: catalog)
    raw.runs = found.runs
    raw.sideways = found.sideways

    // A picture covering the page, with little or nothing printed over it, is a scan.
    let area = frame.size.width * frame.size.height
    let cover = scan.images.map { $0.width * $0.height }.max() ?? 0
    let hidden = raw.runs.flatMap(\.words).filter(\.hidden).count
    let words = raw.runs.flatMap(\.words).count
    raw.scanned = cover > area * 0.7 && (words < 8 || hidden > words / 2)
    raw.garbled = looksGarbled(chars)
    raw.shows = scan.ops.count
    return raw
  }

  private static func characters(_ page: PDFPage, frame: PageFrame) -> [Char] {
    guard let string = page.string, !string.isEmpty else { return [] }
    let ns = string as NSString
    let n = ns.length
    // Sizes and colors, by run, from the attributed text (its font names can't be believed).
    var styles: [(end: Int, size: CGFloat, color: Tint)] = []
    if let a = page.attributedString, a.length == n {
      a.enumerateAttributes(in: NSRange(location: 0, length: n)) { at, r, _ in
        let size = (at[.font] as? UIFont)?.pointSize ?? 0
        let color = Tint(at[.foregroundColor] as? UIColor) ?? .black
        styles.append((r.location + r.length, size, color))
      }
    }
    let bounds = boundsReader(page, ns)
    var out: [Char] = []
    out.reserveCapacity(n)
    var spaced = false
    var s = 0
    var i = 0
    while i < n {
      let r = ns.rangeOfComposedCharacterSequence(at: i)
      let text = ns.substring(with: r)
      defer { i = r.location + r.length }
      if text.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) || $0.value == 0xAD || $0.value == 0x200B || $0.value == 0xFEFF }) {
        spaced = true
        continue
      }
      while s < styles.count - 1 && styles[s].end <= i { s += 1 }
      var rect = bounds(i).applying(frame.toDisplay)
      let size = styles.indices.contains(s) && styles[s].size > 0 ? styles[s].size : max(rect.height, rect.width, 1)
      if rect.height < size * 0.05 {
        rect = CGRect(x: rect.minX, y: rect.minY - size * 0.7, width: max(rect.width, size * 0.3), height: size * 0.7)
      }
      guard rect.width.isFinite, rect.height.isFinite else { continue }
      let rtl = text.unicodeScalars.contains { isRTL($0) }
      out.append(Char(text: text, rect: rect, size: size, color: styles.indices.contains(s) ? styles[s].color : .black, spaced: spaced, strongRTL: rtl))
      spaced = false
    }
    return out
  }

  /// How far to turn a page, clockwise, for its text to run left to right: from
  /// which way one letter follows another. Right-to-left scripts don't get a say.
  private static func turnNeeded(_ chars: [Char]) -> Int {
    var votes = (right: 0, left: 0, down: 0, up: 0)
    for (a, b) in zip(chars, chars.dropFirst()) where !a.strongRTL && !b.strongRTL {
      let (dx, dy) = (b.rect.midX - a.rect.midX, b.rect.midY - a.rect.midY)
      guard abs(dx) + abs(dy) < max(a.size, 4) * 1.6 else { continue }
      if abs(dx) > abs(dy) * 2 {
        if dx > 0 { votes.right += 1 } else { votes.left += 1 }
      } else if abs(dy) > abs(dx) * 2 {
        if dy > 0 { votes.down += 1 } else { votes.up += 1 }
      }
    }
    let total = votes.right + votes.left + votes.down + votes.up
    guard total >= 40 else { return 0 }
    let needed = total * 7 / 10
    if votes.down >= needed { return 270 }
    if votes.up >= needed { return 90 }
    if votes.left >= needed { return 180 }
    return 0
  }

  /// Where the character at index `i` of `string` lies. `characterBounds(at:)` is
  /// the only thing that gives a letter's own box, and so shows when it's raised, but
  /// it counts differently from `string`, which has line breaks it hasn't, and spells out
  /// ligatures it counts as one: every "fi" on a page puts everything after it one
  /// letter off, so that the last letter of a line lands on the next. `selection(for:)`
  /// keeps to `string`'s indices but only knows the line a letter's on, and gives a
  /// ligature's letters one box between them. So the two are walked along together,
  /// each letter's selection saying which box is its own, which also puts them back in
  /// step after whatever else may come between them. Where none fits, the selection will do.
  private static func boundsReader(_ page: PDFPage, _ ns: NSString) -> (Int) -> CGRect {
    let n = ns.length
    var rects = [CGRect](repeating: .zero, count: n)
    // Nearest first: the same step as the last letter, then a ligature's next letter, then further off.
    let tries = [0, -1, 1, -2, 2, -3, 3, 4, 5, 6, 8, 10, 12, 16, 20]
    var at = 0
    var i = 0
    while i < n {
      let r = ns.rangeOfComposedCharacterSequence(at: i)
      i = r.location + r.length
      let first = ns.character(at: r.location)
      if first == 10 || first == 13 { continue }
      if CharacterSet.whitespaces.contains(UnicodeScalar(first) ?? "a") {
        at += 1
        continue
      }
      guard let own = page.selection(for: r)?.bounds(for: page), !own.isEmpty else {
        rects[r.location] = page.characterBounds(at: at)
        at += 1
        continue
      }
      var found: CGRect?
      for step in tries where at + step >= 0 && at + step < n {
        let b = page.characterBounds(at: at + step)
        if abs(b.minX - own.minX) <= max(1, min(b.width, own.width) * 0.4), abs(b.midY - own.midY) < max(own.height, 2) {
          found = b
          at += step + 1
          break
        }
      }
      // Set at an angle, a letter's box is in terms of its own slant and matches nothing. It still takes up a place.
      if found == nil { at += 1 }
      rects[r.location] = found ?? own
    }
    return { $0 < rects.count ? rects[$0] : .zero }
  }

  static func isRTL(_ u: Unicode.Scalar) -> Bool {
    (0x0590...0x08FF).contains(u.value) || (0xFB1D...0xFDFF).contains(u.value) || (0xFE70...0xFEFF).contains(u.value)
  }

  static func isCJK(_ u: Unicode.Scalar) -> Bool {
    (0x3040...0x30FF).contains(u.value) || (0x3400...0x4DBF).contains(u.value) || (0x4E00...0x9FFF).contains(u.value)
      || (0xF900...0xFAFF).contains(u.value) || (0xFF00...0xFFEF).contains(u.value) || (0xAC00...0xD7AF).contains(u.value)
      || (0x3000...0x303F).contains(u.value)
  }

  /// A text layer whose characters mostly aren't letters of anything: private
  /// use, replacement characters, stray controls.
  private static func looksGarbled(_ chars: [Char]) -> Bool {
    guard chars.count >= 40 else { return false }
    var bad = 0
    var letters = 0
    for c in chars {
      for u in c.text.unicodeScalars {
        if u.value == 0xFFFD || (0xE000...0xF8FF).contains(u.value) || u.value < 0x20 { bad += 1 }
        if u.properties.isAlphabetic { letters += 1 }
      }
    }
    return Double(bad) > Double(chars.count) * 0.15 || Double(letters) < Double(chars.count) * 0.25
  }

  // ─── Runs ────────────────────────────────────────────────────────────────

  private struct Open {
    var chars: [(c: Char, op: PageScan.TextOp?)] = []
    var words: [[(c: Char, op: PageScan.TextOp?)]] = []
    /// Where the letters stand: from the stream, which says exactly, wherever it can.
    var base: CGFloat = 0
    var size: CGFloat = 0
    var last = CGRect.null
    var rtl = false
  }

  /// Text set sideways comes one letter a step down the page from the last, level
  /// across, each step less than a line: a preprint server's stamp, a rotated label.
  /// Taken out here, or those letters would go looking for a baseline among the text.
  private static func withoutSideways(_ chars: [Char]) -> (kept: [Char], sideways: [CGRect]) {
    var kept: [Char] = []
    kept.reserveCapacity(chars.count)
    var sideways: [CGRect] = []
    var i = 0
    func steps(_ a: Char, _ b: Char) -> Bool {
      let down = abs(b.rect.midY - a.rect.midY)
      return abs(b.rect.minX - a.rect.minX) < max(a.size * 0.15, 1.5) && down > a.size * 0.08 && down < a.size * 0.95
    }
    while i < chars.count {
      var j = i
      while j + 1 < chars.count, steps(chars[j], chars[j + 1]) { j += 1 }
      if j - i >= 4 {
        var r = chars[i].rect
        for k in i...j { r = r.union(chars[k].rect) }
        sideways.append(r)
        i = j + 1
      } else {
        kept.append(chars[i])
        i += 1
      }
    }
    return (kept, sideways)
  }

  private static func runs(_ all: [Char], scan: PageScan, catalog: FontCatalog) -> (runs: [RawRun], sideways: [CGRect]) {
    let (chars, turned) = withoutSideways(all)
    // Where each show of text starts, by the line it's on, to find a character's
    // font and its true baseline. PDFKit's boxes won't do for the height: one
    // symbol from a math font, and every letter on its line gets a box half as
    // tall again, reaching down past the line below.
    let ops = scan.ops.sorted { $0.point.y < $1.point.y }
    func op(at c: Char, on line: CGFloat?, after last: CGFloat) -> PageScan.TextOp? {
      guard !ops.isEmpty else { return nil }
      // A show starting inside a letter's width isn't its own unless it starts by its middle:
      // an "l" before a raised mark would otherwise take the mark's baseline for its own.
      let latest = c.rect.minX + min(c.size * 0.3, c.rect.width * 0.5)
      // An inflated box tells little about where its letter stands: several lines' baselines
      // can lie inside it. So the text's own continuity decides: the line it's already
      // on if that's among them, and otherwise the next one down.
      if c.rect.height > c.size * 1.08 {
        let inside = ops.filter { $0.point.y >= c.rect.minY && $0.point.y <= c.rect.maxY && $0.point.x <= latest }
        if let line, let here = inside.filter({ abs($0.point.y - line) <= c.size * 0.3 }).max(by: { $0.point.x < $1.point.x }) { return here }
        let below = inside.filter { $0.point.y > last + c.size * 0.5 }
        if let y = below.map(\.point.y).min(), let next = below.filter({ abs($0.point.y - y) < 1 }).max(by: { $0.point.x < $1.point.x }) { return next }
      }
      // A letter's middle lies about a quarter of its size above the baseline.
      let y = c.rect.midY + c.size * 0.25
      let reach = max(c.size * 0.42, 1.5)
      var lo = 0
      var hi = ops.count
      while lo < hi {
        let m = (lo + hi) / 2
        if ops[m].point.y < y - reach { lo = m + 1 } else { hi = m }
      }
      var best: PageScan.TextOp?
      var bestX = -CGFloat.infinity
      var nearest: PageScan.TextOp?
      var nearestD = CGFloat.infinity
      var k = lo
      while k < ops.count, ops[k].point.y <= y + reach {
        let o = ops[k]
        if o.point.x <= latest, o.point.x > bestX {
          best = o
          bestX = o.point.x
        }
        let d = abs(o.point.x - c.rect.minX)
        if d < nearestD {
          nearest = o
          nearestD = d
        }
        k += 1
      }
      return best ?? nearest
    }

    var runs: [RawRun] = []
    var sideways = turned
    var open = Open()

    func start(_ c: Char, _ o: PageScan.TextOp?) {
      open = Open()
      open.chars = [(c, o)]
      open.words = [[(c, o)]]
      open.base = o?.point.y ?? c.rect.maxY
      open.size = c.size
      open.last = c.rect
      open.rtl = c.strongRTL
    }
    var lastBase = -CGFloat.infinity
    func flush() {
      if !open.chars.isEmpty, let run = close(open) {
        runs.append(run)
        // Only what's on the line counts: a raised scrap isn't where the next line starts from.
        if run.words.count >= 2 { lastBase = run.baseline }
      }
      open = Open()
    }

    for c in chars {
      // Back across the column, it's a new line, whatever its box says.
      let goesOn = !open.chars.isEmpty && (c.strongRTL || c.rect.minX >= open.last.minX - max(open.size, c.size) * 0.6)
      let o = op(at: c, on: goesOn ? open.base : nil, after: open.chars.isEmpty ? lastBase : max(lastBase, goesOn ? lastBase : open.base))
      guard !open.chars.isEmpty else {
        start(c, o)
        continue
      }
      let em = max(open.size, c.size)
      let forward = c.rect.minX - open.last.maxX
      let backward = open.last.minX - c.rect.maxX
      // Hebrew and Arabic run leftward through the text.
      let gap = (c.strongRTL || open.rtl) && backward > forward ? backward : forward
      let y = o?.point.y ?? c.rect.maxY
      // Letters somewhat smaller may be raised or lowered and still be on the line.
      // Far smaller is another thing altogether: the text beside a drop cap.
      let ratio = min(c.size, open.size) / max(c.size, open.size, 1)
      let band = ratio >= 0.42 && abs(y - open.base) <= em * (ratio < 0.9 ? 0.7 : 0.3)
      let along = gap > -em * 0.6 && gap < em * 1.15
      guard band && along else {
        flush()
        start(c, o)
        continue
      }
      if c.spaced || gap > em * 0.2 {
        open.words.append([(c, o)])
      } else {
        open.words[open.words.count - 1].append((c, o))
      }
      open.chars.append((c, o))
      open.last = c.rect
      if c.size >= open.size {
        open.base = y
        open.size = c.size
      }
      open.rtl = open.rtl || c.strongRTL
    }
    flush()
    return lift(runs, sideways: &sideways)
  }

  /// Text set sideways arrives a letter at a time, each its own run, stacked:
  /// a page's vertical stamp, a rotated axis label. They become part of the picture.
  private static func lift(_ runs: [RawRun], sideways: inout [CGRect]) -> (runs: [RawRun], sideways: [CGRect]) {
    var keep: [RawRun] = []
    var i = 0
    while i < runs.count {
      var j = i
      while j + 1 < runs.count, isLetterOrTwo(runs[j]), isLetterOrTwo(runs[j + 1]),
        abs(runs[j + 1].rect.midX - runs[j].rect.midX) < max(runs[j].size * 0.6, 2),
        // A letter along from the last, not a line down: stray marks on successive lines line up too.
        abs(runs[j + 1].baseline - runs[j].baseline) < runs[j].size * 0.95
      {
        j += 1
      }
      if j - i >= 4 {
        var r = runs[i].rect
        for k in i...j { r = r.union(runs[k].rect) }
        sideways.append(r)
        i = j + 1
      } else {
        keep.append(runs[i])
        i += 1
      }
    }
    return (keep, sideways)
  }

  /// A run of one word of at most two letters: short enough to be one letter
  /// of something running sideways.
  private static func isLetterOrTwo(_ r: RawRun) -> Bool { r.words.count == 1 && r.words[0].text.count <= 2 }

  private static func close(_ open: Open) -> RawRun? {
    // The line's size is the one most of its letters are set at, so a superscript at its start doesn't set it.
    var tally: [CGFloat: Int] = [:]
    for (c, _) in open.chars { tally[(c.size * 2).rounded() / 2, default: 0] += 1 }
    let size = tally.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? open.size

    // The baseline: where most of its full-sized letters stand.
    func stands(_ e: (c: Char, op: PageScan.TextOp?)) -> CGFloat { e.op?.point.y ?? e.c.rect.maxY }
    let standing = open.chars.filter { e in e.c.size >= size * 0.85 && (e.op != nil || !offLine.contains(where: { e.c.text.contains($0) })) }
    let levels = (standing.isEmpty ? open.chars : standing).map(stands).sorted()
    let baseline = levels[levels.count / 2]

    /// How high a word's letters reach, from the size they're set at rather than the box they were given.
    func box(_ x0: CGFloat, _ x1: CGFloat, base: CGFloat, size: CGFloat) -> CGRect {
      CGRect(x: x0, y: base - size * 0.74, width: max(x1 - x0, 0.5), height: size * 0.96)
    }

    var words: [RawWord] = []
    var fontTally: [Int: Int] = [:]
    var colorTally: [Tint: Int] = [:]
    for group in open.words {
      // A word's letters, split wherever the script changes, so "x²" keeps its raised part.
      var i = 0
      while i < group.count {
        func script(_ e: (c: Char, op: PageScan.TextOp?)) -> Int {
          guard e.c.size < size * 0.86 else { return 0 }
          let lift = baseline - stands(e)
          if lift > size * 0.14 { return 1 }
          if lift < -size * 0.06 { return -1 }
          return 0
        }
        let kind = script(group[i])
        var j = i
        while j + 1 < group.count, script(group[j + 1]) == kind { j += 1 }
        let part = group[i...j]
        let x0 = part.map(\.c.rect.minX).min()!
        let x1 = part.map(\.c.rect.maxX).max()!
        let head = part.first!
        let rect = box(x0, x1, base: stands(head), size: head.c.size)
        let font = head.op?.font ?? -1
        words.append(
          RawWord(
            text: part.map(\.c.text).joined(), rect: rect, size: head.c.size, font: font, color: head.c.color, script: kind,
            hidden: head.op?.hidden ?? false, glued: i > 0))
        fontTally[font, default: 0] += part.count
        colorTally[head.c.color, default: 0] += part.count
        i = j + 1
      }
    }
    guard !words.isEmpty else { return nil }
    var rect = box(words[0].rect.minX, words[0].rect.maxX, base: baseline, size: size)
    for w in words { rect = rect.union(CGRect(x: w.rect.minX, y: rect.minY, width: w.rect.width, height: rect.height)) }
    let font = fontTally.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? -1
    let color = colorTally.max { $0.value < $1.value }?.key ?? .black
    return RawRun(words: words, rect: rect, baseline: baseline, size: size, font: font, color: color)
  }
}

