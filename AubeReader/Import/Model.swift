import CoreGraphics
import Foundation

// ─── A document, once it's understood ────────────────────────────────────────

/// What a stretch of a document is doing there. Only paragraphs (and the longer
/// list items and quotes) can be rewritten; the rest is set as it was found.
enum BlockRole: String, Codable, CaseIterable {
  case title, byline, abstract, heading, paragraph, list, quote
  /// A sidebar's small print, or a note nothing in the text leads to: text worth keeping, but not the argument.
  case note
  /// A footnote: never set among the text, only opened from its mark (see `NoteToken`).
  case footnote
  case caption, figure, table, equation, code, references
  /// Running heads, page numbers: they belong to the page, not the text.
  case furniture
  /// A scrap of text that fits nowhere else: a label, a date, a line of a form.
  case minor

  var isProse: Bool { self == .paragraph || self == .list || self == .quote || self == .abstract }
  /// Shown as a picture of the original, in every look that shows it.
  var isPicture: Bool { self == .figure || self == .table || self == .equation }
}

enum TextAlign: String, Codable {
  case left, center, right, justified
}

/// How a block was set in the original.
struct BlockStyle: Codable, Equatable {
  /// Index into the document's `fonts`, or −1 if unknown.
  var font = -1
  var size: CGFloat = 10
  /// From baseline to baseline.
  var leading: CGFloat = 12
  var color = Tint.black
  var align = TextAlign.left
  var indent: CGFloat = 0
  /// How wide a character runs on average, as a share of the size; 0 if unknown.
  var advance: CGFloat = 0
}

/// The part of a block on one page. A paragraph that runs across a column or
/// page break has one for each; the first is where it reads from.
struct BlockPiece: Codable, Equatable {
  var page: Int
  /// Its share of the page, all the way to its neighbors: every point of a page
  /// lies in exactly one tile, so laying them out again draws the page whole.
  var tile: CGRect
  /// The box around just its marks.
  var ink: CGRect
  /// For a footnote, the rule that sets it off from the text above, which goes where it goes.
  var rule: CGRect?
}

struct DocBlock: Codable, Equatable {
  var id: Int
  var role: BlockRole
  /// For a heading, 1 is the largest.
  var level = 0
  var text: String
  var pieces: [BlockPiece]
  var style = BlockStyle()
  /// For a caption, the figure or table it describes.
  var captionOf: Int?
  /// Set in math fonts, somewhere in it: what it says isn't all in its characters.
  var mathy = false
  /// Its formulas have been written out in TeX, between dollar signs, and are to be set as formulas.
  var math = false
  /// What a note is marked with on the page: 3, *, †. Set on any block a mark in the text can open.
  var mark: String?

  var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// How a page's tiles fit together: stacked, side by side, or a tile itself.
struct PageTile: Codable, Equatable {
  enum Kind: String, Codable { case stack, side, block, blank }
  var kind: Kind
  var rect: CGRect
  var kids: [PageTile]?
  /// For a block's tile: which block, and which of its pieces.
  var block: Int?
  var piece: Int?

  var leaves: [PageTile] { kids.map { $0.flatMap(\.leaves) } ?? [self] }
}

struct DocPage: Codable, Equatable {
  var size: CGSize
  var tile: PageTile
  /// A picture of a page: its text came from OCR or the model.
  var scanned = false
  /// Nothing could be read on the device; the model is asked to read it.
  var unread = false
  var paper = Tint.white
  /// Where photographs lie, which keep their colors when the page goes dark.
  var photos: [CGRect] = []
  /// How far it's turned, clockwise, beyond what the file says, to bring its text upright.
  var turn = 0
  /// Where its page number is printed: the original look leaves it out.
  var folios: [CGRect] = []
}

/// Where a footnote's mark is printed on an original page, which is what's
/// tapped there. What the text says about it is in the text (see `NoteToken`).
struct PrintedMark: Codable, Equatable {
  /// The block it opens.
  var note: Int
  var page: Int
  var box: CGRect
}

/// A note of what the check found and did, for the document's report.
struct ImportNote: Codable, Equatable {
  var page: Int?
  var said: String
  var fixed: Bool
}

struct ImportReport: Codable, Equatable {
  enum State: String, Codable {
    /// Not looked at yet.
    case pending
    /// Looked at, and either nothing needed changing or everything was put right.
    case checked
    /// Looked at, and something couldn't be put right.
    case flagged
    /// Couldn't be looked at: no key, no connection, or checks turned off.
    case skipped
  }
  var state = State.pending
  var pagesChecked = 0
  var rounds = 0
  var notes: [ImportNote] = []
  /// What kind of document the model took it for.
  var kind: String?
  var why: String?
}

struct ImportedDoc: Codable, Equatable {
  /// Changes whenever documents read earlier have to be read again.
  static let format = 2

  var format = Self.format
  var id: String
  var fileName: String
  var title: String
  var authors: [String] = []
  /// What it's about, for the rewriter's sense of "in the field".
  var field = ""
  /// A BCP 47 tag, when it could be told.
  var language: String?
  var fonts: [FontRecord] = []
  var pages: [DocPage] = []
  /// In reading order.
  var blocks: [DocBlock] = []
  /// Every footnote mark as it's printed on the pages.
  var marks: [PrintedMark] = []
  var report = ImportReport()
  /// Set when there's no original layout to show: plain text and RTF.
  var flowing = false

  func block(_ id: Int) -> DocBlock? { blocks.first { $0.id == id } }
  var nextId: Int { (blocks.map(\.id).max() ?? -1) + 1 }
}

// ─── Text as a page sets it ──────────────────────────────────────────────────

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
