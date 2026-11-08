import CoreGraphics
import Foundation

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
