import CoreText
import UIKit

// ─── Content ─────────────────────────────────────────────────────────────────

/// A version of a paragraph as far as it has been written: its text and,
/// while it is still being written, the placeholders it shows, one for each
/// word it's expected to have. The text is set over them as it comes; those
/// it hasn't reached yet stay just where they were.
struct Draft {
  var text: String
  /// How many words the placeholders stand for, or nil once the version is written.
  var skeleton: Int?
  /// Changes whenever the draft does, so its typesetting is kept until then.
  var revision: Int

  var done: Bool { skeleton == nil }
}

/// A text's paragraphs, each on a grid of versions: difficulty (0 = simplest)
/// by zoom (0 = longest). Every version may be written already, or some may
/// still be on their way.
protocol Versions: AnyObject {
  var count: Int { get }
  var cMax: Int { get }
  var zMax: Int { get }
  /// The version each paragraph starts at, and goes back to on a double tap.
  var defaultDifficulty: Int { get }
  var defaultZoom: Int { get }
  /// How many paragraphs, from the first, every look shows; the rest appear only on the journal page.
  var coreCount: Int { get }
  /// The looks the text can be dressed in.
  var looks: [ReadingStyle] { get }
  func draft(_ paragraph: Int, _ c: Int, _ z: Int) -> Draft
  /// The version a paragraph is as found, where every paragraph has one of its
  /// own: each starts there, and a double tap goes back to it.
  func home(_ paragraph: Int) -> (c: Int, z: Int)
}

extension Versions {
  func home(_ paragraph: Int) -> (c: Int, z: Int) { (defaultDifficulty, defaultZoom) }
}

/// A document that comes with the app, every version of it written ahead
/// (by tools/levels): each paragraph at the six levels of difficulty on
/// `Scale`, and each of those at every one of the document's lengths, from
/// the most detailed to a gist.
final class Content: Decodable, Versions {
  /// paragraphs[paragraph][difficulty][zoom]
  let paragraphs: [[[String]]]
  let defaultDifficulty: Int
  let defaultZoom: Int
  let core: Int?
  /// Its title and authors, where the paper it's set in doesn't give them.
  let title: String?
  let authors: [String]?

  private static var loaded: [String: Content] = [:]

  /// The document in the bundled file `name`.json, read once.
  static func named(_ name: String) -> Content {
    if let c = loaded[name] { return c }
    guard
      let url = Bundle.main.url(forResource: name, withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let content = try? JSONDecoder().decode(Content.self, from: data)
    else { fatalError("\(name).json is missing from the app bundle") }
    loaded[name] = content
    return content
  }

  var count: Int { paragraphs.count }
  var cMax: Int { paragraphs[0].count - 1 }
  var zMax: Int { paragraphs[0][0].count - 1 }
  var coreCount: Int { min(core ?? paragraphs.count, paragraphs.count) }
  var looks: [ReadingStyle] { ReadingStyle.allCases }

  func draft(_ paragraph: Int, _ c: Int, _ z: Int) -> Draft {
    Draft(text: paragraphs[paragraph][c][z], skeleton: nil, revision: 0)
  }
}

// ─── Words ───────────────────────────────────────────────────────────────────

/// A footnote's mark within a typeset word: which note it opens, and where its capsule lies.
struct GlyphMark {
  let note: Int
  let x: CGFloat
  let width: CGFloat
  /// Up from the baseline to the capsule's middle.
  let rise: CGFloat
  let height: CGFloat
}

/// A word typeset once, to be drawn wherever it lands.
final class Glyphs {
  let text: String
  let pieces: [Piece]
  let width: CGFloat
  /// Stands in for a word not yet written: its one piece is the bar it's drawn as.
  let placeholder: Bool
  /// The notes marked in it.
  let marks: [GlyphMark]

  init(text: String, pieces: [Piece], width: CGFloat, placeholder: Bool = false, marks: [GlyphMark] = []) {
    self.text = text
    self.pieces = pieces
    self.width = width
    self.placeholder = placeholder
    self.marks = marks
  }
}

struct Word {
  let glyphs: Glyphs
  /// Lowercased, punctuation-free form used to match words across versions.
  let key: String
  /// Short function words are cheap to match, so they don't steer the alignment.
  let stop: Bool
  /// The left of the word and the top of its line, from the paragraph's top left.
  var x: Double
  let y: Double
}

struct Layout {
  let words: [Word]
  let height: Double
}

private let stopWords = Set(
  "a an the of to in on at by for from with and or but is are was were be been it its this that these those as so than then there their they them which who what when where while can could would should will not no if into out up over about very just only also even"
    .split(separator: " ").map(String.init)
)

private func keyOf(_ text: String) -> String {
  // A word's the same word with or without a mark on it.
  let text = NoteToken.strip(text).isEmpty ? text : NoteToken.strip(text)
  let scalars = text.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
    switch $0.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .decimalNumber, .letterNumber, .otherNumber:
      return true
    default:
      return false
    }
  }
  let key = String(String.UnicodeScalarView(scalars))
  return key.isEmpty ? text : key
}

// Inline math is written between single dollar signs, the way Pandoc reads it:
// no space just inside either dollar, and no digit right after the closing one.
private let mathPattern = try! NSRegularExpression(pattern: #"\$([^\s$](?:[^$\n]*?[^\s$])?)\$(?!\d)"#)

private func findMath(_ text: String) -> [(range: Range<String.Index>, tex: String)] {
  let ns = text as NSString
  return mathPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
    guard let r = Range(m.range, in: text), let t = Range(m.range(at: 1), in: text) else { return nil }
    return (r, String(text[t]))
  }
}

/// Splits text into words, keeping each formula whole even when it contains spaces.
func tokenize(_ text: String) -> [String] {
  var sealed = ""
  var last = text.startIndex
  for (range, _) in findMath(text) {
    sealed += text[last..<range.lowerBound]
    sealed += text[range].replacingOccurrences(of: " ", with: "\u{1}")
    last = range.upperBound
  }
  sealed += text[last...]
  return sealed
    .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
    .map { $0.replacingOccurrences(of: "\u{1}", with: " ") }
}

/// Splits a text found in a document into words: at spaces, and between the
/// characters of a script that doesn't use them, its punctuation staying with
/// the character before so a line never starts on a comma.
func tokenizeFound(_ text: String) -> [String] {
  var out: [String] = []
  for token in text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }) {
    guard token.unicodeScalars.contains(where: PageReader.isCJK) else {
      out.append(String(token))
      continue
    }
    var run = ""
    for ch in token {
      let isCJK = ch.unicodeScalars.first.map(PageReader.isCJK) == true
      let closes = "，。、；：！？）》」』】”’,.;:!?)".contains(ch)
      if closes || (!isCJK && !run.isEmpty && !(run.unicodeScalars.last.map(PageReader.isCJK) ?? false)) {
        run.append(ch)
      } else {
        if !run.isEmpty { out.append(run) }
        run = String(ch)
      }
    }
    if !run.isEmpty { out.append(run) }
  }
  return out
}

// ─── Setting type ────────────────────────────────────────────────────────────

/// Typesets and wraps the texts into a column, the way a browser would: words
/// one after another, separated by a space, a new line whenever the next word
/// doesn't fit. Set `justify` and every line but the last is spread to fill
/// the column, and `indent` to start each paragraph in from the left, as on a
/// printed page.
final class Typesetter {
  let fontSize: CGFloat
  let lineHeight: CGFloat
  let column: CGFloat
  let font: UIFont
  let justify: Bool
  let indent: CGFloat
  /// Where the baseline sits in a line box, from its top: the leading split evenly above and below.
  let baseline: CGFloat
  /// The face formulas are set in, or nil for the system serif.
  private let mathFamily: String?
  /// Whether `$…$` means a formula. A text found rather than written can hold
  /// dollar signs that mean dollars.
  private let math: Bool
  /// What each note a mark can lead to is labelled on the page (see `NoteToken`).
  private let notes: [Int: String]
  private let space: CGFloat
  /// How wide a lowercase letter runs, on average.
  private let letter: CGFloat
  private var cache: [String: Glyphs] = [:]

  init(
    fontSize: CGFloat, column: CGFloat, serif: Bool = false, leading: CGFloat = 1.6, justify: Bool = false, indent: CGFloat = 0,
    face: UIFont? = nil, math: Bool = true, notes: [Int: String] = [:]
  ) {
    self.fontSize = fontSize
    self.lineHeight = (fontSize * leading).rounded()
    self.column = column
    self.justify = justify
    self.indent = indent
    self.math = math
    self.notes = notes
    font = face ?? (serif ? (UIFont(name: "TimesNewRomanPSMT", size: fontSize) ?? .systemFont(ofSize: fontSize)) : .systemFont(ofSize: fontSize))
    mathFamily = serif ? "Times New Roman" : nil
    baseline = ((lineHeight - (font.ascender - font.descender)) / 2 + font.ascender).rounded()
    space = lineWidth(makeLine(" ", font))
    letter = lineWidth(makeLine("abcdefghijklmnopqrstuvwxyz", font)) / 26
  }

  /// About how tall `characters` of text will set, without setting them.
  func estimate(characters: Int) -> Double {
    guard characters > 0 else { return 0 }
    let wide = letter * 1.08 * CGFloat(characters)
    return Double((wide / max(column, 1)).rounded(.up)) * Double(lineHeight)
  }

  /// A placeholder for a word of about `letters` letters: a bar the height of
  /// the lowercase letters, sitting where they would. `name` tells it from
  /// every other, so that in a morph it's matched only with itself.
  func placeholder(_ letters: Int, name: String) -> Glyphs {
    let width = (CGFloat(letters) * letter).rounded()
    let height = (font.xHeight * 1.25).rounded()
    return Glyphs(
      text: "\u{0}" + name, pieces: [.rule(x: 0, width: width, rise: font.xHeight / 2, thickness: height)], width: width,
      placeholder: true)
  }

  func glyphs(_ token: String) -> Glyphs {
    if let g = cache[token] { return g }
    var pieces: [Piece] = []
    var marks: [GlyphMark] = []
    var x: CGFloat = 0
    func plain(_ s: Substring) {
      for part in NoteToken.parts(String(s)) {
        switch part {
        case let .text(t):
          let line = makeLine(t, font)
          pieces.append(.text(line, x: x, rise: 0))
          x += lineWidth(line)
        case let .mark(id):
          // A dangling mark, whose note a correction took away, says nothing.
          guard let label = notes[id] else { continue }
          // No taller than the line it's on, and level with the middle of the capitals beside it.
          let height = min(Halo.diameter(fontSize), (lineHeight * 0.94).rounded())
          let face = Halo.font(height)
          let line = makeLine(label, face)
          let width = Halo.width(label, height)
          let rise = min(font.capHeight / 2, baseline - height / 2 - 0.5)
          let at = x + fontSize * 0.14
          pieces.append(.halo(x: at, width: width, rise: rise, height: height))
          pieces.append(.text(line, x: at + (width - lineWidth(line)) / 2, rise: rise - face.capHeight / 2))
          marks.append(GlyphMark(note: id, x: at, width: width, rise: rise, height: height))
          x = at + width + fontSize * 0.06
        }
      }
    }
    var last = token.startIndex
    for (range, tex) in math ? findMath(token) : [] {
      plain(token[last..<range.lowerBound])
      let math = TeX(tex, size: fontSize, family: mathFamily)
      for p in math.pieces {
        switch p {
        case let .text(line, px, rise): pieces.append(.text(line, x: x + px, rise: rise))
        case let .rule(px, w, rise, t): pieces.append(.rule(x: x + px, width: w, rise: rise, thickness: t))
        case .halo: break
        }
      }
      x += math.x
      last = range.upperBound
    }
    plain(token[last...])
    let g = Glyphs(text: token, pieces: pieces, width: x, marks: marks)
    cache[token] = g
    return g
  }

  /// Sets `text`, then `then`, placeholders for the words still to come.
  func layout(_ text: String, then pending: [Glyphs] = []) -> Layout {
    let tokens = math ? tokenize(text) : tokenizeFound(text)
    let all = tokens.map { (glyphs($0), keyOf($0)) } + pending.map { ($0, $0.text) }
    var words: [Word] = []
    var x = indent
    var line = 0
    var start = 0
    /// Characters of a script without spaces follow one another directly, and a mark its word.
    func spaced(_ g: Glyphs) -> CGFloat {
      if NoteToken.isBare(g.text) { return 0 }
      guard let before = words.last?.glyphs.text.unicodeScalars.last, PageReader.isCJK(before),
        let first = g.text.unicodeScalars.first, PageReader.isCJK(first)
      else { return space }
      return 0
    }
    /// Spreads the full line made of words[start..<end] across the column.
    func spread(_ end: Int) {
      guard justify, end - start > 1 else { return }
      let last = words[end - 1]
      let slack = column - (CGFloat(last.x) + last.glyphs.width)
      guard slack > 0 else { return }
      let gap = Double(slack / CGFloat(end - start - 1))
      for k in start + 1..<end { words[k].x += gap * Double(k - start) }
    }
    for (g, key) in all {
      let fresh = words.count == start
      let gap = spaced(g)
      if !fresh && x + gap + g.width > column {
        spread(words.count)
        start = words.count
        line += 1
        x = 0
      } else if !fresh {
        x += gap
      }
      // Placeholders count for little when matched, like function words.
      words.append(Word(glyphs: g, key: key, stop: g.placeholder || stopWords.contains(key), x: x, y: Double(line) * lineHeight))
      x += g.width
    }
    // Hebrew and Arabic read from the right: each line, set the other way round.
    if text.unicodeScalars.first(where: { $0.properties.isAlphabetic }).map(PageReader.isRTL) == true {
      for k in words.indices { words[k].x = Double(column) - words[k].x - Double(words[k].glyphs.width) }
    }
    return Layout(words: words, height: words.isEmpty ? 0 : Double(line + 1) * lineHeight)
  }
}
