import CoreGraphics
import Foundation

// ─── A note's mark, in a text ────────────────────────────────────────────────

/// How a block's text says a note is marked there: `[^12]`, by the note's block
/// number, attached to the word it follows. Every look, the rewriter and the
/// check all read from the text, so that's where a mark has to live for it to
/// follow the words wherever they go. The label a reader sees is the note's own
/// (`DocBlock.mark`), since the same 1 or * can come round again on every page.
enum NoteToken {
  private static let pattern = try! NSRegularExpression(pattern: #"\[\^(\d+)\]"#)
  /// Before blocks have numbers, a mark goes by its note's `Found.uid`.
  private static let unsettled = try! NSRegularExpression(pattern: #"\[\^@(\d+)\]"#)
  private static let spaceBefore = try! NSRegularExpression(pattern: #"\s+(\[\^\d+\])"#)
  private static let literal = try! NSRegularExpression(pattern: #"\[\^(\d)"#)

  static func make(_ id: Int) -> String { "[^\(id)]" }
  static func pending(_ uid: Int) -> String { "[^@\(uid)]" }

  enum Part {
    case text(String)
    case mark(Int)
  }

  /// A text's words and marks, in the order they come.
  static func parts(_ t: String) -> [Part] {
    guard t.contains("[^") else { return t.isEmpty ? [] : [.text(t)] }
    var out: [Part] = []
    var last = t.startIndex
    for m in pattern.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
      guard let r = Range(m.range, in: t), let n = Range(m.range(at: 1), in: t), let id = Int(t[n]) else { continue }
      if r.lowerBound > last { out.append(.text(String(t[last..<r.lowerBound]))) }
      out.append(.mark(id))
      last = r.upperBound
    }
    if last < t.endIndex { out.append(.text(String(t[last...]))) }
    return out
  }

  /// A text as it reads without its marks.
  static func strip(_ t: String) -> String {
    guard t.contains("[^") else { return t }
    return pattern.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
  }

  /// The notes a text's marks lead to.
  static func ids(_ t: String) -> [Int] {
    guard t.contains("[^") else { return [] }
    return parts(t).compactMap { if case let .mark(id) = $0 { return id } else { return nil } }
  }

  /// Whether a word is nothing but a mark.
  static func isBare(_ word: String) -> Bool { word.hasPrefix("[^") && strip(word).isEmpty }

  /// A mark belongs to the word before it, whatever spacing it came with.
  static func tighten(_ t: String) -> String {
    guard t.contains("[^") else { return t }
    return spaceBefore.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1")
  }

  /// The same marks under block numbers `base` higher.
  static func shift(_ t: String, by base: Int) -> String {
    parts(t).map { part in
      switch part {
      case let .text(s): return s
      case let .mark(id): return make(id + base)
      }
    }.joined()
  }

  /// Keeps only the marks whose notes still stand, the rest going back to what was printed, or nothing.
  static func keep(_ t: String, _ printed: (Int) -> String?) -> String {
    parts(t).map { part in
      switch part {
      case let .text(s): return s
      case let .mark(id): return printed(id) ?? ""
      }
    }.joined()
  }

  /// `[^@uid]`, now that blocks have numbers. What only looked like a mark in
  /// the text as found (`[^0-9]`, in a paper about regular expressions) is kept from being taken for one.
  static func settle(_ t: String, uids: [Int: Int]) -> String {
    guard t.contains("[^") else { return t }
    var out = literal.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "[\u{2060}^$1")
    let found = unsettled.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
    for m in found {
      guard let r = Range(m.range, in: out), let n = Range(m.range(at: 1), in: out), let uid = Int(out[n]) else { continue }
      out.replaceSubrange(r, with: uids[uid].map(make) ?? "")
    }
    return out
  }

  private static let named = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)

  /// A text written as Markdown writes marks, `[^name]`, with the blocks `names` says they lead to.
  static func settleNamed(_ t: String, _ names: [String: Int]) -> String {
    guard t.contains("[^") else { return t }
    var out = t
    for m in named.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
      guard let r = Range(m.range, in: out), let n = Range(m.range(at: 1), in: out) else { continue }
      // A number no note goes by, as in `[^0-9]`, is only text.
      out.replaceSubrange(r, with: names[String(out[n])].map(make) ?? out[r].replacingOccurrences(of: "[^", with: "[\u{2060}^"))
    }
    return tighten(out)
  }

  /// `new`, a rewriting of `old`, with `old`'s marks and no others. One a writer
  /// dropped goes back after the word it followed, or, if that word's gone too,
  /// at the end: a note should stay within reach, whatever's become of the words around it.
  static func restore(_ new: String, from old: String) -> String {
    let wanted = ids(old)
    guard !wanted.isEmpty || new.contains("[^") else { return new }
    guard !new.isEmpty else { return new }
    let known = Set(wanted)
    var text = tighten(parts(new).map { part in
      switch part {
      case let .text(s): return s
      case let .mark(id): return known.contains(id) ? make(id) : ""
      }
    }.joined())
    let have = Set(ids(text))
    var before = ""
    for part in parts(old) {
      switch part {
      case let .text(s): before += s
      case let .mark(id):
        guard !have.contains(id) else { continue }
        let share = Double(before.count) / Double(max(strip(old).count, 1))
        text = insert(id, after: before, near: share, in: text)
      }
    }
    return text
  }

  private static func insert(_ id: Int, after before: String, near share: Double, in text: String) -> String {
    // The last word of any length before it, wherever it's nearest to where it was.
    let word = before.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last { $0.count >= 3 }.map(String.init)
    var best: Range<String.Index>?
    if let word {
      var bestOff = Double.infinity
      var from = text.startIndex
      while let r = text.range(of: word, options: .caseInsensitive, range: from..<text.endIndex) {
        let off = abs(Double(text.distance(from: text.startIndex, to: r.lowerBound)) / Double(max(text.count, 1)) - share)
        if off < bestOff {
          bestOff = off
          best = r
        }
        from = r.upperBound
      }
    }
    guard let best else { return text + make(id) }
    var end = best.upperBound
    // The rest of the word, and what closes it: a mark comes after the comma.
    while end < text.endIndex, text[end].isLetter || text[end].isNumber { end = text.index(after: end) }
    while end < text.endIndex, ".,;:!?)”\"’'".contains(text[end]) { end = text.index(after: end) }
    var out = text
    out.insert(contentsOf: make(id), at: end)
    return out
  }

  /// A note's lines as one text. Notes are where addresses are given, and an address broken
  /// over two lines runs straight on, its hyphen and all: it's only ever broken at a character it can be.
  static func joinNote(_ lines: [String], known: (String) -> Bool) -> String {
    var out = ""
    for line in lines {
      if let tail = out.split(separator: " ").last, tail.contains("://") || tail.contains("www."), let end = tail.last, "/-_#?&=%~.".contains(end),
        end != "." || line.first?.isLowercase == true
      {
        out += line.trimmingCharacters(in: .whitespaces)
      } else {
        out = PageText.join([out, line], known: known)
      }
    }
    return out
  }
}

// ─── What a mark says ────────────────────────────────────────────────────────

/// What a mark is, however it's printed.
enum MarkLabel {
  private static let digits: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"]
  /// All the asterisks and bars a font's encoding can make of one mark.
  private static let same: [Character: Character] = ["∗": "*", "⁎": "*", "＊": "*", "✱": "*", "∥": "‖", "♯": "#", "✝": "†"]
  static let symbols: Set<Character> = ["*", "†", "‡", "§", "¶", "‖", "#", "⋆", "★", "☆", "♭", "♮", "✠"]
  private static let trimmed: Set<Character> = ["(", ")", "[", "]", "{", "}", ".", ",", ":", ";", "⁽", "⁾"]

  /// The mark `raw` is, in one spelling, if it's one at all: a number, a symbol
  /// or two of the same, or a lowercase letter.
  static func normal(_ raw: String) -> String? {
    var t = ""
    for c in PageText.plain(raw) where !trimmed.contains(c) { t.append(same[c] ?? digits[c] ?? c) }
    guard !t.isEmpty else { return nil }
    if t.allSatisfy({ $0.isASCII && $0.isNumber }) {
      guard t.count <= 3, let n = Int(t), n > 0 else { return nil }
      return String(n)
    }
    if let f = t.first, symbols.contains(f), t.count <= 3, t.allSatisfy({ $0 == f }) { return t }
    if t.count == 1, let c = t.first, c.isASCII, c.isLowercase { return t }
    return nil
  }

  static func isNumber(_ label: String) -> Bool { label.first?.isNumber == true }

  /// The marks in what's set raised as one word: "1", "1,2", "3–5".
  static func list(_ raw: String) -> [String]? {
    let plain = PageText.plain(raw).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:()[]"))
    guard !plain.isEmpty else { return nil }
    var out: [String] = []
    for part in plain.split(whereSeparator: { $0 == "," || $0 == ";" }) {
      // Symbols run together, each its own: "∗†". And on a number, as an author's affiliation and a note can share a place: "1∗".
      if let runs = symbolRuns(part) {
        out += runs
        continue
      }
      if let split = part.firstIndex(where: { symbols.contains(same[$0] ?? $0) }), split != part.startIndex, let number = normal(String(part[..<split])), let runs = symbolRuns(part[split...]) {
        out.append(number)
        out += runs
        continue
      }
      let span = part.split(whereSeparator: { "–—-−".contains($0) })
      if span.count == 2, let a = normal(String(span[0])), let b = normal(String(span[1])), let x = Int(a), let y = Int(b), x < y, y - x <= 12 {
        out += (x...y).map(String.init)
      } else if let one = normal(String(part)) {
        out.append(one)
      } else {
        return nil
      }
    }
    return out.isEmpty ? nil : out
  }

  /// What's nothing but symbols, as the marks they make: "∗†" is two, "∗∗" is one.
  private static func symbolRuns<S: StringProtocol>(_ text: S) -> [String]? {
    var out: [String] = []
    for c in text {
      let canon = same[c] ?? c
      guard symbols.contains(canon) else { return nil }
      if let last = out.last, last.first == canon { out[out.count - 1].append(canon) } else { out.append(String(canon)) }
    }
    return out.isEmpty ? nil : out
  }

  /// A word ending in symbols that are set at the size of the text: `Doe∗`, `Doe,∗`, `Doe∗†`.
  static func symbolTail(_ word: String) -> (lead: String, labels: [String])? {
    let chars = Array(word)
    var k = chars.count
    while k > 0, symbols.contains(same[chars[k - 1]] ?? chars[k - 1]) { k -= 1 }
    guard k < chars.count, chars.count - k <= 4, let labels = symbolRuns(String(chars[k...])) else { return nil }
    return (String(chars[..<k]), labels)
  }

  /// A word ending in digits in the characters that are raised by themselves: `word¹`.
  static func raisedTail(_ word: String) -> (lead: String, label: String)? {
    let chars = Array(word)
    var k = chars.count
    while k > 0, digits[chars[k - 1]] != nil { k -= 1 }
    guard k < chars.count, k > 0, let label = normal(String(chars[k...])) else { return nil }
    return (String(chars[..<k]), label)
  }
}

// ─── Finding footnotes ───────────────────────────────────────────────────────

/// A mark printed in the text that hasn't got as far as a block number yet.
struct PendingMark {
  var note: Int
  var page: Int
  var box: CGRect
}

/// Works out which small print at the foot of a page is a footnote, and where
/// in the text it's marked. A mark and a note only count once each is found to
/// answer the other: raised numbers are everywhere (x², 10³, 2nd) and so is
/// small print (copyright lines, numbered lists), and neither says anything alone.
/// So a note is small print at the foot of its page or column that opens with
/// what a mark raised in that page's text says, and the rest is left as it was.
/// It all comes from geometry and fonts, so no one language or publisher is
/// assumed; what's beyond it (a scan's marks can't be seen to be raised) is left
/// for the check to link up (`Fix.Op.linkFootnote`).
extension Structure {
  #if DEBUG
  /// What was seen at the foot of each page, for checking an import by, when a drive script asks (`trace`).
  nonisolated(unsafe) static var tracing = false
  nonisolated(unsafe) static var trace: [String] = []
  #endif

  /// One word of the text that could be a mark, or several in a row.
  private struct Spot {
    var at: Int
    var line: Int
    var word: Int
    var page: Int
    /// What comes before the mark in that word.
    var lead: String
    var labels: [String]
    var raised: Bool
    var box: CGRect
    var score: Int
    /// Which note each of `labels` was found to lead to.
    var notes: [Int?]
  }

  private struct Head {
    var line: Int
    var word: Int
    var label: String
    var raised: Bool
    /// What's left of the word once the mark's taken off it.
    var rest: String?
    /// Whether it can be believed to open a note, given how the block it's in is set.
    var credible = false
  }

  /// What one page holds that could be notes and marks.
  private struct PageNotes {
    var foot = Set<Int>()
    var ruled = Set<Int>()
    var spots: [Spot] = []
    var heads: [Int: [Head]] = [:]
  }

  /// Finds footnotes and marks them in the text, and returns where they're printed.
  /// First what each page holds; then each note takes the mark on its own page
  /// that best answers it; then what's left looks at the pages either side, since
  /// a page break can come between a mark and its note, whichever comes first.
  static func findFootnotes(_ found: inout [Found], raw: [RawPage], body: CGFloat, fonts: [FontRecord], furniture: Set<Int>) -> [PendingMark] {
    for i in found.indices { found[i].uid = i }
    var nextUid = found.count
    var byPage: [Int: [Int]] = [:]
    for i in found.indices { byPage[found[i].page, default: []].append(i) }
    // A list of references or notes can end at the foot of a page, in small type, with
    // numbers that answer the text's. It's a list all the same, unless a rule says otherwise.
    func heading(_ i: Int) -> Bool {
      guard found[i].block.kind == .text, found[i].words <= 6 else { return false }
      let t = found[i].block.lines.map(\.text).joined(separator: " ")
      return hits(referencesHeading, t) || hits(notesHeading, t)
    }
    let listFrom = found.indices.last(where: heading) ?? found.count

    var pages = raw.indices.map { _ in PageNotes() }
    for page in raw.indices {
      let here = byPage[page] ?? []
      let foot = footOf(here, &found, raw: raw[page], body: body, furniture: furniture)
      var ruled = Set<Int>()
      for i in foot.sorted(by: { found[$0].block.ink.minY < found[$1].block.ink.minY }) {
        if found[i].rule != nil || ruled.contains(where: { overlaps(found[$0].block.ink, found[i].block.ink) }) { ruled.insert(i) }
      }
      // The text's possible marks, and a table's: an author's name in a table of authors has one as well as any.
      var spots: [Spot] = []
      for i in here where found[i].block.kind != .figure && found[i].role != .furniture {
        if foot.contains(i), found[i].block.lines.first.flatMap({ headAtStart($0) }) != nil { continue }
        spots += possibleMarks(in: found[i], at: i, fonts: fonts)
      }
      let expected = Set(spots.filter { $0.score != keptBack }.flatMap(\.labels))
      var heads: [Int: [Head]] = [:]
      for i in foot where i < listFrom || ruled.contains(i) {
        guard found[i].role != .equation, reads(found[i], fonts: fonts) else { continue }
        // A plain number at the size of the text, with no rule over it, is a list.
        let small = isSmall(found[i], body: body)
        let hs = headsIn(found[i], expected: expected)
        heads[i] = hs.map { h in
          var h = h
          h.credible = small || ruled.contains(i) || h.raised || !MarkLabel.isNumber(h.label)
          return h
        }
      }
      pages[page] = PageNotes(foot: foot, ruled: ruled, spots: spots, heads: heads)
      #if DEBUG
      if tracing {
        trace.append("page \(page + 1) foot \(foot.count) spots \(spots.map { "\($0.labels)@\($0.score)" })")
        for i in foot.sorted() {
          let f = found[i]
          trace.append("  foot #\(i) role \(f.role.rawValue) small \(isSmall(f, body: body)) rule \(f.rule != nil) ink \(Int(f.block.ink.minX)),\(Int(f.block.ink.minY))")
          for l in f.block.lines.prefix(6) {
            trace.append("    line size \(l.size) base \(l.baseline): " + l.words.prefix(7).map { "\($0.text)[\($0.size),\($0.script)\($0.glued ? ",g" : "")]" }.joined(separator: " "))
          }
        }
      }
      #endif
    }

    // Each note, in reading order, takes the mark that best answers it.
    var printed: [PendingMark] = []
    var taken: [Int: [Int: Int]] = [:]
    func give(_ uid: Int, spot s: Int, part k: Int, on page: Int) {
      pages[page].spots[s].notes[k] = uid
      printed.append(PendingMark(note: uid, page: page, box: box(of: k, in: pages[page].spots[s])))
    }
    for page in raw.indices {
      // One symbol can come round again on a page, each time marking a note of its own.
      var copies: [String: Int] = [:]
      for hs in pages[page].heads.values { for h in hs { copies[h.label, default: 0] += 1 } }
      for i in pages[page].heads.keys.sorted() {
        for (n, h) in (pages[page].heads[i] ?? []).enumerated() where h.credible {
          let hit = answer(h.label, shared: copies[h.label] == 1, spots: pages[page].spots)
          guard !hit.isEmpty else { continue }
          let uid = nextUid
          nextUid += 1
          taken[i, default: [:]][n] = uid
          for (s, k) in hit { give(uid, spot: s, part: k, on: page) }
        }
      }
    }
    for page in raw.indices {
      for i in pages[page].heads.keys.sorted() {
        for (n, h) in (pages[page].heads[i] ?? []).enumerated() where h.credible && MarkLabel.isNumber(h.label) && taken[i]?[n] == nil {
          for other in [page - 1, page + 1] where raw.indices.contains(other) {
            // Only what reads very like a mark: on another page, nothing else says it's this one.
            guard let (s, k) = pages[other].spots.enumerated().compactMap({ (s, spot) -> (Int, Int)? in
              guard spot.score >= 4, let k = spot.labels.firstIndex(of: h.label), spot.notes[k] == nil else { return nil }
              return (s, k)
            }).last else { continue }
            let uid = nextUid
            nextUid += 1
            taken[i, default: [:]][n] = uid
            give(uid, spot: s, part: k, on: other)
            break
          }
        }
      }
    }

    // A note that's every bit a note, raised and ruled off at the foot of its page, with
    // nothing else to answer it: then the mark's on the end of a formula, where marks can be too.
    for page in raw.indices {
      for i in pages[page].heads.keys.sorted() where pages[page].ruled.contains(i) && isSmall(found[i], body: body) {
        for (n, h) in (pages[page].heads[i] ?? []).enumerated() where h.raised && MarkLabel.isNumber(h.label) && taken[i]?[n] == nil {
          guard let (s, k) = pages[page].spots.enumerated().compactMap({ (s, spot) -> (Int, Int)? in
            guard spot.score == keptBack, let k = spot.labels.firstIndex(of: h.label), spot.notes[k] == nil else { return nil }
            return (s, k)
          }).last else { continue }
          let uid = nextUid
          nextUid += 1
          taken[i, default: [:]][n] = uid
          give(uid, spot: s, part: k, on: page)
        }
      }
    }

    // The marks found to lead to a note, in place in the text.
    for page in pages {
      for s in page.spots where s.notes.contains(where: { $0 != nil }) && found[s.at].block.kind == .text { write(s, into: &found) }
    }

    // The notes, cut out of the small print they were found in.
    var replaced: [Int: [Found]] = [:]
    for page in pages {
      for (i, hs) in page.heads where taken[i] != nil && !hs.isEmpty {
        var parts: [(start: (line: Int, word: Int), head: Head?, uid: Int?)] = []
        if hs[0].line > 0 || hs[0].word > 0 { parts.append(((0, 0), nil, nil)) }
        for (n, h) in hs.enumerated() { parts.append(((h.line, h.word), h, taken[i]?[n])) }
        replaced[i] = cut(found[i], parts)
      }
    }

    var out: [Found] = []
    out.reserveCapacity(found.count)
    for i in found.indices { out += replaced[i] ?? [found[i]] }
    found = carryOver(out)
    return printed
  }

  /// Whether a block of small print reads as words at all, rather than the end of a formula.
  private static func reads(_ f: Found, fonts: [FontRecord]) -> Bool {
    var words = 0
    var plain = 0
    var math = 0
    for l in f.block.lines {
      for w in l.words {
        words += 1
        let isMath = fonts.indices.contains(w.font) && fonts[w.font].math
        if isMath || w.text.unicodeScalars.contains(where: Structure.mathSymbols.contains) {
          math += 1
        } else if letterRun(w.text) >= 3 {
          plain += 1
        }
      }
    }
    return plain >= 1 && math * 2 < words
  }

  private static func letterRun(_ text: String) -> Int {
    var run = 0
    var longest = 0
    for c in text {
      run = c.isLetter ? run + 1 : 0
      longest = max(longest, run)
    }
    return longest
  }

  // ─── The foot of a page ──────────────────────────────────────────────────

  private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxX, b.maxX) - max(a.minX, b.minX) > 1 }

  private static func isSmall(_ f: Found, body: CGFloat) -> Bool {
    let sizes = f.block.lines.map(\.size).sorted()
    return !sizes.isEmpty && sizes[sizes.count / 2] < body * 0.95
  }

  /// What's at the foot of a page or column: small print, or anything under a
  /// rule or opening with a mark, with nothing but more of the same below it.
  /// Going up from the bottom, each block can see whether what's below it counts.
  private static func footOf(_ here: [Int], _ found: inout [Found], raw: RawPage, body: CGFloat, furniture: Set<Int>) -> Set<Int> {
    var foot = Set<Int>()
    let h = raw.size.height
    let pictures = here.filter { found[$0].block.kind != .text }.map { found[$0].block.ink }
    let rules = raw.rules.filter { r in r.height <= 2.5 && r.width >= 12 && !pictures.contains { $0.insetBy(dx: -2, dy: -2).intersects(r) } }
    for i in here.sorted(by: { found[$0].block.ink.minY > found[$1].block.ink.minY }) where found[i].block.kind == .text && !furniture.contains(i) {
      let ink = found[i].block.ink
      let clear = here.allSatisfy { j in
        let other = found[j]
        guard j != i, other.block.ink.minY >= ink.maxY - 1, overlaps(other.block.ink, ink) else { return true }
        if foot.contains(j) || other.role == .furniture { return true }
        // A label or date of no size, down in the margin.
        return other.role == .minor && other.words <= 6 && other.block.ink.minY > h * 0.88
      }
      guard clear else { continue }
      let size = found[i].block.lines.first?.size ?? body
      let rule = rules.filter { r in
        let gap = ink.minY - r.maxY
        return gap > -2 && gap < max(size * 2.2, 14) && r.minX < ink.maxX && r.maxX > ink.minX
      }.min { $0.minY > $1.minY }
      let opens = found[i].block.lines.first.flatMap { headAtStart($0) } != nil
      if isSmall(found[i], body: body) || rule != nil || opens {
        foot.insert(i)
        found[i].foot = true
        found[i].rule = rule
      }
    }
    return foot
  }

  // ─── How a note opens ────────────────────────────────────────────────────

  private static func headAtStart(_ line: TextLine) -> Head? {
    guard let w = line.words.first else { return nil }
    if w.script > 0, let label = MarkLabel.normal(w.text) { return Head(line: 0, word: 0, label: label, raised: true) }
    if let label = MarkLabel.normal(w.text), MarkLabel.isNumber(label) || MarkLabel.symbols.contains(label.first ?? " ") {
      return Head(line: 0, word: 0, label: label, raised: false)
    }
    // Run into the word it marks: "∗Equal", "†Work", "1Department".
    let chars = Array(w.text)
    var k = 0
    while k < chars.count, MarkLabel.normal(String(chars[k])).map({ !MarkLabel.isNumber($0) && $0.first?.isLetter != true }) == true { k += 1 }
    if k > 0, k < chars.count, k <= 3, let label = MarkLabel.normal(String(chars[..<k])) {
      return Head(line: 0, word: 0, label: label, raised: false, rest: String(chars[k...]))
    }
    k = 0
    while k < chars.count, chars[k].isNumber { k += 1 }
    // Digits set smaller than what they run into are a mark, whatever it is they run into.
    if k > 0, k <= 2, k < chars.count, chars[k].isUppercase || w.size < line.size * 0.86, let label = MarkLabel.normal(String(chars[..<k])) {
      return Head(line: 0, word: 0, label: label, raised: false, rest: String(chars[k...]))
    }
    return nil
  }

  /// Where a block of small print's notes start. Usually at the start of a line,
  /// but several can be run together, each after the sentence before it stops.
  private static func headsIn(_ f: Found, expected: Set<String>) -> [Head] {
    var out: [Head] = []
    for (l, line) in f.block.lines.enumerated() {
      if var h = headAtStart(line), l == 0 || h.raised || expected.contains(h.label) {
        h.line = l
        out.append(h)
      }
      for (k, w) in line.words.enumerated().dropFirst() where w.script > 0 {
        guard let label = MarkLabel.normal(w.text), expected.contains(label), endsSentence(line.words[k - 1].text) else { continue }
        out.append(Head(line: l, word: k, label: label, raised: true))
      }
    }
    return out
  }

  // ─── How a mark looks ────────────────────────────────────────────────────

  /// How much a word that could be a mark reads like one where it stands, or nil
  /// if it's clearly something else: the power on `x²`, on `10³`, on `km²`.
  private static func follows(_ prev: RawWord?, fonts: [FontRecord]) -> Int? {
    guard let prev else { return nil }
    let text = NoteToken.strip(prev.text)
    // After a previous mark, or a comma or a period, it can't be a power of anything.
    if text.isEmpty { return 3 }
    if let last = text.last, ".,;:!?”\"’'»".contains(last) { return 3 }
    let longest = letterRun(text)
    let math = fonts.indices.contains(prev.font) && fonts[prev.font].math
    if !math {
      if longest >= 3 { return 2 }
      // A short name: Li, Xu, Wu.
      if longest == 2, text.first?.isUppercase == true { return 2 }
    }
    if text.unicodeScalars.contains(where: PageReader.isCJK) { return 2 }
    // A year: "in 2010¹", "(Seeley, 2010)¹".
    let digits = text.filter(\.isNumber)
    if digits.count == 4, let y = Int(digits), y > 1400, y < 2100, !math { return 2 }
    return nil
  }

  /// How a raised word scores if it reads like a power.
  private static let keptBack = -1

  private static func possibleMarks(in f: Found, at index: Int, fonts: [FontRecord]) -> [Spot] {
    var out: [Spot] = []
    let lines = f.block.lines
    for (l, line) in lines.enumerated() {
      for (k, w) in line.words.enumerated() where !w.hidden {
        let prev = k > 0 ? line.words[k - 1] : (l > 0 ? lines[l - 1].words.last : nil)
        let next = line.words[safe: k + 1]
        let small = w.size < line.size * 0.86
        func spot(_ labels: [String], lead: String, raised: Bool, box: CGRect, score: Int) {
          out.append(Spot(at: index, line: l, word: k, page: f.page, lead: lead, labels: labels, raised: raised, box: box, score: score, notes: labels.map { _ in nil }))
        }
        // Set raised, or set small among the text: "word¹", "word,¹", "¹⁵N" isn't.
        if w.script > 0 || (small && w.text.allSatisfy(\.isNumber)), let labels = MarkLabel.list(w.text) {
          if let next, next.glued, next.text.first?.isLetter == true || next.text.first?.isNumber == true { continue }
          // What reads like a power is kept back, for a note that plainly is one and has found nothing better.
          guard w.script > 0 || follows(prev, fonts: fonts) != nil, prev != nil else { continue }
          let plainFont = !(fonts.indices.contains(w.font) && fonts[w.font].math)
          let score = follows(prev, fonts: fonts).map { $0 + (plainFont ? 2 : 0) + (w.glued ? 1 : 0) } ?? Self.keptBack
          spot(labels, lead: "", raised: true, box: w.rect, score: score)
          continue
        }
        guard w.script == 0 else { continue }
        let perChar = w.rect.width / CGFloat(max(w.text.count, 1))
        if let tail = MarkLabel.symbolTail(w.text) {
          // On the word it's run into, or the one before it if it stands alone: a symbol can be a norm's bar or a product too.
          var lead = w
          lead.text = tail.lead
          guard follows(tail.lead.isEmpty ? prev : lead, fonts: fonts) != nil else { continue }
          let wide = perChar * CGFloat(tail.labels.joined().count)
          spot(tail.labels, lead: tail.lead, raised: false, box: CGRect(x: w.rect.maxX - wide, y: w.rect.minY, width: wide, height: w.rect.height), score: 3)
        } else if let tail = MarkLabel.raisedTail(w.text) {
          var lead = w
          lead.text = tail.lead
          guard let reads = follows(lead, fonts: fonts) else { continue }
          let wide = perChar * CGFloat(max(tail.label.count, 1))
          spot([tail.label], lead: tail.lead, raised: true, box: CGRect(x: w.rect.maxX - wide, y: w.rect.minY, width: wide, height: w.rect.height), score: reads)
        }
      }
    }
    return out
  }

  private static func box(of k: Int, in s: Spot) -> CGRect {
    let n = CGFloat(max(s.labels.count, 1))
    let w = s.box.width / n
    return CGRect(x: s.box.minX + w * CGFloat(k), y: s.box.minY, width: w, height: s.box.height)
  }

  /// The marks a note labelled `label` answers: a symbol that's `shared`, every one
  /// the page has, as when several authors share one note; otherwise the one that reads
  /// most like a mark, and the first of those: a note's only marked once, and in order.
  private static func answer(_ label: String, shared: Bool, spots: [Spot]) -> [(Int, Int)] {
    var hits: [(s: Int, k: Int)] = []
    for (s, spot) in spots.enumerated() where spot.score != keptBack {
      for (k, l) in spot.labels.enumerated() where l == label && spot.notes[k] == nil { hits.append((s, k)) }
    }
    guard !hits.isEmpty else { return [] }
    if shared, !MarkLabel.isNumber(label), label.first?.isLetter != true { return hits.map { ($0.s, $0.k) } }
    let best = hits.max { a, b in (spots[a.s].score, -a.s) < (spots[b.s].score, -b.s) }!
    return [(best.s, best.k)]
  }

  /// Puts what was found to be a mark into the word it was printed as.
  private static func write(_ s: Spot, into found: inout [Found]) {
    var line = found[s.at].block.lines[s.line]
    var text = s.lead
    for (k, label) in s.labels.enumerated() {
      if let uid = s.notes[k] {
        text += NoteToken.pending(uid)
      } else {
        let lit = (k > 0 && s.notes[k - 1] == nil ? "," : "") + label
        text += s.raised ? PageText.scripted(lit, 1) : lit
      }
    }
    var w = line.words[s.word]
    guard w.text != text else { return }
    w.text = text
    w.script = 0
    // What's raised on its own hangs on the word before; with a word of its own in front, it stays where that is.
    if s.lead.isEmpty { w.glued = s.word > 0 || s.line > 0 }
    // It says nothing about what the sentence is set in: cmr7 is a math font too.
    if s.word > 0 { w.font = line.words[s.word - 1].font } else if s.line > 0, let before = found[s.at].block.lines[s.line - 1].words.last { w.font = before.font }
    line.words[s.word] = w
    line.text = PageText.line(line.words)
    found[s.at].block.lines[s.line] = line
  }

  // ─── Cutting notes out ───────────────────────────────────────────────────

  private static func slice(_ line: TextLine, _ range: Range<Int>) -> TextLine? {
    guard !range.isEmpty else { return nil }
    var l = line
    l.words = Array(line.words[range])
    var r = l.words[0].rect
    for w in l.words { r = r.union(w.rect) }
    l.rect = CGRect(x: r.minX, y: line.rect.minY, width: r.width, height: line.rect.height)
    l.text = PageText.line(l.words)
    return l
  }

  private static func bounds(_ lines: [TextLine]) -> CGRect {
    var r = lines[0].rect
    for l in lines { r = r.union(l.rect) }
    return r
  }

  /// A block of small print as what it's found to hold: its notes, and whatever
  /// else was there, which keeps the block's tile. If it's all notes, the first has it.
  private static func cut(_ f: Found, _ parts: [(start: (line: Int, word: Int), head: Head?, uid: Int?)]) -> [Found] {
    var out: [Found] = []
    let lines = f.block.lines
    for (p, part) in parts.enumerated() {
      let end = parts[safe: p + 1]?.start ?? (lines.count, 0)
      var kept: [TextLine] = []
      for l in part.start.line...min(end.line, lines.count - 1) {
        let from = l == part.start.line ? part.start.word : 0
        let to = l == end.line ? end.word : lines[l].words.count
        if from < to, let s = slice(lines[l], from..<to) { kept.append(s) }
      }
      guard !kept.isEmpty else { continue }
      let ink = bounds(kept)
      var piece = Found(page: f.page, block: PageBlock(kind: .text, lines: kept, ink: ink, tile: .zero, loose: true), role: f.role)
      piece.foot = true
      piece.uid = part.uid ?? f.uid
      if p == 0 { piece.rule = f.rule }
      if let uid = part.uid, let head = part.head {
        // The mark itself is gone from what the note says.
        var words = kept[0].words
        if let rest = head.rest { words[0].text = rest } else { words.removeFirst() }
        while let w = words.first, !w.text.contains(where: { $0.isLetter || $0.isNumber }), w.text.count <= 2 { words.removeFirst() }
        var lines = kept
        if words.isEmpty {
          lines.removeFirst()
        } else {
          lines[0].words = words
          lines[0].text = PageText.line(words)
        }
        guard lines.contains(where: { $0.text.contains(where: { $0.isLetter || $0.isNumber }) }) else { continue }
        piece.block.lines = lines
        piece.role = .footnote
        piece.label = head.label
        piece.uid = uid
      }
      out.append(piece)
    }
    // What's still as it was keeps the tile the picture of the page is cut along.
    if let owner = out.firstIndex(where: { $0.role != .footnote }) ?? out.indices.first {
      out[owner].block.tile = f.block.tile
      out[owner].block.loose = f.block.loose
      if out[owner].role != .footnote { out[owner].uid = f.uid }
    }
    return out
  }

  /// A long note runs on at the foot of the next column or page, with no mark
  /// to say so, and a note can have more than one paragraph. Small print at the
  /// foot that takes up where the last note stopped is more of that note.
  private static func carryOver(_ list: [Found]) -> [Found] {
    var out: [Found] = []
    out.reserveCapacity(list.count)
    var last: Int?
    for f in list {
      if f.role == .footnote {
        out.append(f)
        last = out.count - 1
        continue
      }
      if let l = last, f.foot, f.block.kind == .text, f.role != .furniture, continues(out[l], f) {
        out[l].merged.append(f)
        continue
      }
      out.append(f)
    }
    return out
  }

  private static func continues(_ note: Found, _ f: Found) -> Bool {
    let tail = note.merged.last ?? note
    guard let end = tail.block.lines.last, let start = f.block.lines.first, abs(end.size - start.size) < 0.6, f.page <= tail.page + 1 else { return false }
    let lower = start.text.first?.isLowercase == true
    let stopped = endsSentence(end.text)
    if f.page == tail.page, overlaps(tail.block.ink, f.block.ink), f.block.ink.minY > tail.block.ink.minY {
      // Under it. A line of print can't be told from more of the note, but a gap the size of a line can.
      return f.block.ink.minY - tail.block.ink.maxY < end.size * 1.8 && (!stopped || lower)
    }
    return !stopped && (lower || f.rule != nil)
  }

  // ─── Notes gathered at the end ───────────────────────────────────────────

  static let notesHeading = try! NSRegularExpression(
    pattern: #"^\s*(\d+\.?\s+)?(notes|endnotes|end\s*notes|anmerkungen|fußnoten|notas|remarques)\s*$"#, options: [.caseInsensitive])
  private static let bracketCitation = try! NSRegularExpression(pattern: #"\[\d{1,3}(?:\s*[,–-]\s*\d{1,3})*\]"#)

  /// Notes gathered in a section of their own, or a numbered list of references
  /// that the text cites by raised numbers, stay where they are, and marks open
  /// them too. Only raised numbers that the list answers count, and only if there are enough
  /// of them to show that's how this document cites: a list and one stray `10²` aren't that.
  static func linkLists(_ found: inout [Found], fonts: [FontRecord]) -> [PendingMark] {
    var printed: [PendingMark] = []
    func text(_ f: Found) -> String { NoteToken.strip(f.block.lines.map(\.text).joined(separator: " ")) }
    let notes = found.lastIndex { $0.block.kind == .text && $0.role != .furniture && hits(notesHeading, text($0)) }
    let references = found.lastIndex { $0.block.kind == .text && $0.role != .furniture && hits(referencesHeading, text($0)) }

    for (start, isNotes) in [(notes, true), (references, false)] {
      guard let start else { continue }
      // The list's entries, by what they're numbered.
      var entries: [String: Int] = [:]
      var repeated = Set<String>()
      for n in (start + 1)..<max(found.count, start + 1) {
        let f = found[n]
        if f.role == .heading && f.level > 0 && f.level <= max(found[start].level, 1) { break }
        guard f.block.kind == .text, f.role != .furniture, f.role != .footnote, f.role != .caption, f.label == nil else { continue }
        guard let first = f.block.lines.first?.words.first, let label = MarkLabel.normal(first.text), MarkLabel.isNumber(label) else { continue }
        if entries[label] != nil { repeated.insert(label) }
        entries[label] = n
      }
      for r in repeated { entries[r] = nil }
      guard entries.count >= (isNotes ? 1 : 2) else { continue }

      // The text's raised numbers, all before the list.
      var spots: [Spot] = []
      var brackets = 0
      for i in 0..<start where found[i].block.kind == .text && found[i].role != .furniture && found[i].role != .footnote {
        spots += possibleMarks(in: found[i], at: i, fonts: fonts).filter { $0.raised && $0.score >= 3 }
        if !isNotes {
          let t = found[i].block.lines.map(\.text).joined(separator: " ")
          brackets += bracketCitation.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t))
        }
      }
      var answered = Set<String>()
      var total = 0
      for s in spots.indices {
        for (k, label) in spots[s].labels.enumerated() {
          total += 1
          if let n = entries[label] {
            spots[s].notes[k] = found[n].uid
            answered.insert(label)
          }
        }
      }
      // A document that cites in brackets isn't citing with its raised numbers.
      guard answered.count >= (isNotes ? 1 : 3), answered.count * 2 >= total || isNotes, isNotes || brackets < total else { continue }
      for s in spots where s.notes.contains(where: { $0 != nil }) {
        for (k, uid) in s.notes.enumerated() {
          if let uid { printed.append(PendingMark(note: uid, page: s.page, box: box(of: k, in: s))) }
        }
        write(s, into: &found)
      }
      for label in answered {
        if let n = entries[label] { found[n].label = label }
      }
      // Having found the one, the other isn't looked for: a raised 3 means one thing in a document.
      break
    }
    return printed
  }

  // ─── Page numbers ────────────────────────────────────────────────────────

  private static let trailingNumber = try! NSRegularExpression(pattern: #"^(?:[^\d]{0,4}|\d{1,8}[-–])(\d{1,5})[)\].,\-–]*$"#)

  /// Where each page's number is printed: a number in the margins' furniture
  /// that counts up with the pages, whatever else is said around it. A journal's
  /// year or volume stays, since those don't.
  static func findFolios(_ found: [Found], raw: [RawPage]) -> [Int: [CGRect]] {
    var candidates: [(page: Int, value: Int, rect: CGRect)] = []
    var bare: [Int: [(value: Int?, rect: CGRect)]] = [:]
    var tally: [Int: Set<Int>] = [:]
    for f in found where f.role == .furniture && f.block.kind == .text {
      let t = f.block.lines.map(\.text).joined(separator: " ")
      let alone = hits(pageNumber, t)
      var first: Int?
      for line in f.block.lines {
        for w in line.words {
          let s = w.text
          guard let m = trailingNumber.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s), let n = Int(s[r]) else { continue }
          if first == nil { first = n }
          if !alone { candidates.append((f.page, n, w.rect)) }
          tally[n - f.page, default: []].insert(f.page)
        }
      }
      if alone { bare[f.page, default: []].append((first, f.block.ink)) }
    }
    let numbered = Set(tally.values.flatMap { $0 }).count
    let enough = max(2, Int(Double(numbered) * 0.4))
    let counting = Set(tally.filter { $0.value.count >= enough }.keys)
    var out: [Int: [CGRect]] = [:]
    for c in candidates where counting.contains(c.value - c.page) { out[c.page, default: []].append(c.rect) }
    for (page, list) in bare {
      for b in list {
        // A number alone in a margin, if it fits how the others count. Few pages have nothing to compare it with.
        if let v = b.value, raw.count > 2, !counting.isEmpty, !counting.contains(v - page) { continue }
        out[page, default: []].append(b.rect)
      }
    }
    return out
  }
}
