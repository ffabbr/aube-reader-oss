import Foundation

/// Turning words as a page set them into text as a reader expects it.
enum PageText {
  private static let raised: [Character: Character] = [
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "−": "⁻",
    "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
  ]
  private static let lowered: [Character: Character] = [
    "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "−": "₋",
    "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "h": "ₕ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "p": "ₚ", "s": "ₛ", "t": "ₜ",
  ]

  /// Raised or lowered text in the characters that say so, where they exist.
  static func scripted(_ text: String, _ script: Int) -> String {
    guard script != 0 else { return text }
    let map = script > 0 ? raised : lowered
    let out = text.map { map[$0] }
    return out.allSatisfy { $0 != nil } ? String(out.compactMap { $0 }) : text
  }

  /// Letters a font joined into one, and the odd spaces and hyphens, in their plain forms.
  static func plain(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.count)
    for u in text.unicodeScalars {
      switch u.value {
      case 0xFB00: out += "ff"
      case 0xFB01: out += "fi"
      case 0xFB02: out += "fl"
      case 0xFB03: out += "ffi"
      case 0xFB04: out += "ffl"
      case 0xFB05, 0xFB06: out += "st"
      case 0x00A0, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: out += " "
      case 0x00AD, 0x200B, 0x2060, 0xFEFF: break
      case 0x2010, 0x2011: out += "-"
      default: out.unicodeScalars.append(u)
      }
    }
    return out
  }

  /// Accents TeX sets as separate marks beside their letters ("M¨uller",
  /// "Mont´ufar"), put back on them.
  static func composeAccents(_ text: String) -> String {
    let marks: [Unicode.Scalar: Unicode.Scalar] = [
      "\u{00B4}": "\u{0301}", "\u{00A8}": "\u{0308}", "\u{02DC}": "\u{0303}", "\u{02C6}": "\u{0302}", "\u{02C7}": "\u{030C}", "\u{02D8}": "\u{0306}", "\u{02D9}": "\u{0307}",
      "\u{02DA}": "\u{030A}", "\u{00B8}": "\u{0327}", "\u{02DD}": "\u{030B}", "`": "\u{0300}",
    ]
    guard text.unicodeScalars.contains(where: { marks[$0] != nil }) else { return text }
    let u = Array(text.unicodeScalars)
    var out = String.UnicodeScalarView()
    var i = 0
    while i < u.count {
      if let mark = marks[u[i]], i + 1 < u.count, u[i + 1].properties.isAlphabetic,
        // In a word, or starting one. A backquote only inside one, since it means other things elsewhere.
        u[i] != "`" || (i > 0 && u[i - 1].properties.isAlphabetic)
      {
        // Dotless i and j, as TeX spells them under an accent, take it as plain letters.
        let base: Unicode.Scalar = u[i + 1] == "\u{0131}" ? "i" : u[i + 1] == "\u{0237}" ? "j" : u[i + 1]
        out.append(base)
        out.append(mark)
        i += 2
      } else {
        out.append(u[i])
        i += 1
      }
    }
    return String(out).precomposedStringWithCanonicalMapping
  }

  /// A line's words as text: spaces between words but not between the parts of
  /// one, and none between characters of a script that doesn't use them.
  static func line(_ words: [RawWord]) -> String {
    var out = ""
    for w in words {
      let text = scripted(plain(w.text), w.script)
      guard !text.isEmpty else { continue }
      if !out.isEmpty, !w.glued, !(out.unicodeScalars.last.map(PageReader.isCJK) == true && text.unicodeScalars.first.map(PageReader.isCJK) == true) {
        out += " "
      }
      out += text
    }
    return composeAccents(out)
  }

  /// Joins lines into a paragraph: a word broken at a line's end is mended, by
  /// `known`, which says whether the mended form is a word.
  static func join(_ lines: [String], known: (String) -> Bool = { _ in true }) -> String {
    var out = ""
    for raw in lines {
      let l = raw.trimmingCharacters(in: .whitespaces)
      guard !l.isEmpty else { continue }
      if out.isEmpty {
        out = l
        continue
      }
      if out.hasSuffix("-"), let next = l.first, next.isLowercase {
        // "exam-" + "ple" is one word; "well-" + "known" keeps its hyphen.
        let head = out.dropLast().split(whereSeparator: { $0 == " " }).last.map(String.init) ?? ""
        let tail = l.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
        let word = (head + tail).trimmingCharacters(in: .punctuationCharacters)
        if head.hasSuffix("-") == false, known(word) { out.removeLast() }
        out += l
      } else if out.unicodeScalars.last.map(PageReader.isCJK) == true, l.unicodeScalars.first.map(PageReader.isCJK) == true {
        out += l
      } else {
        out += " " + l
      }
    }
    return out
  }
}
