import Foundation

/// The two ways a live document's paragraphs can be read, each a ladder of
/// evenly spaced steps on a measure the app checks for itself, so that every
/// swipe or pinch changes a paragraph by about as much as the one before.
///
/// Difficulty is measured as the Flesch–Kincaid grade level. There are six
/// levels, 2.5 grades apart, from grade 2 (a seven-year-old) to grade 14.5 (a
/// specialist), far enough apart that every swipe reads differently. The
/// middle, level 3, is grade 9.5: where most writing for adults sits.
///
/// Length is measured in words. There are seven lengths, 20 words apart, from
/// 140 words down to a 20-word gist. The originals run about 80 words, which
/// is length 3. Each step is about two lines of text on the page.
enum Scale {
  // ─── Difficulty ──────────────────────────────────────────────────────────

  static let levels = 6
  static let gradeStep = 2.5
  static let lowestGrade = 2.0
  /// Where a paragraph starts when nothing says otherwise.
  static let middle = 3

  /// The grade level `level` reads at.
  static func grade(_ level: Int) -> Double { lowestGrade + gradeStep * Double(level) }

  /// Who each level is written for.
  static let readers = [
    "a seven-year-old",
    "a ten-year-old",
    "a twelve-year-old",
    "an educated adult reading the science pages of a newspaper",
    "a university student in the field",
    "a specialist researcher in the field",
  ]

  /// How far from its level a rewrite may measure: under half a step, so
  /// neighboring levels never overlap. Grade is only measured on paragraphs of
  /// `gradedWords` or more: a sentence or two is too few to tell.
  static let gradeSlack = 1.0
  static let gradedWords = 30

  // ─── Length ──────────────────────────────────────────────────────────────

  /// Words at each zoom, from the longest (zoom 0) to the gist.
  static let lengths = [140, 120, 100, 80, 60, 40, 20]
  static let lengthStep = 20
  /// How far from its length a rewrite may run: under half a step, so
  /// neighboring lengths never overlap.
  static let lengthSlack = 9

  /// The ladder for a paragraph that's found rather than written to measure: it
  /// reads at `n` words, at zoom 3, whatever that is. Three steps up, each as long as
  /// a step down from it is a share of it; three steps down, to a quarter of it, or
  /// ten words if that's more. An 80-word paragraph gets just the ladder above.
  static func ladder(for n: Int) -> [Int] {
    let n = max(n, 1)
    let floor = max(min(10, n), n / 4)
    let down = (1...3).map { n - (n - floor) * $0 / 3 }
    let step = max(lengthStep, Int((Double(n) / 4 / 10).rounded()) * 10)
    return [n + 3 * step, n + 2 * step, n + step, n] + down
  }

  /// The level a paragraph reads at, as measured. Below `gradedWords` a paragraph
  /// is too short to tell, and `fallback` stands in for it.
  static func level(of text: String, fallback: Int = middle) -> Int {
    guard count(text) >= gradedWords else { return fallback }
    return level(atGrade: grade(of: text))
  }

  static func level(atGrade g: Double) -> Int { min(levels - 1, max(0, Int(((g - lowestGrade) / gradeStep).rounded()))) }

  // ─── Measures ────────────────────────────────────────────────────────────

  /// How many words `text` has. Where a script has no spaces, two characters count as a word.
  static func count(_ text: String) -> Int {
    var n = 0
    for w in words(text) {
      let cjk = w.unicodeScalars.filter(PageReader.isCJK).count
      n += cjk > 0 ? max(1, cjk / 2) : 1
    }
    return n
  }

  /// The words of `text`: what's between spaces, if it has a letter or digit in it.
  static func words(_ text: String) -> [Substring] {
    text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
      .filter { $0.contains { $0.isLetter || $0.isNumber } && !NoteToken.isBare(String($0)) }
  }

  /// The Flesch–Kincaid grade level of `text`:
  /// 0.39 × words per sentence + 11.8 × syllables per word − 15.59.
  static func grade(of text: String) -> Double {
    // A note's mark comes after the period it follows, and neither is a word.
    let text = NoteToken.strip(text)
    let ws = words(text)
    guard !ws.isEmpty else { return 0 }
    let range = NSRange(text.startIndex..., in: text)
    let sentences = max(1, sentenceEnd.numberOfMatches(in: text, range: range))
    let syllables = ws.reduce(0) { $0 + syllableCount($1) }
    return 0.39 * Double(ws.count) / Double(sentences) + 11.8 * Double(syllables) / Double(ws.count) - 15.59
  }

  private static let sentenceEnd = try! NSRegularExpression(pattern: #"[.!?]+(\s|$)"#)
  private static let silentEnd = try! NSRegularExpression(pattern: #"(?:[^laeiouy]es|ed|[^laeiouy]e)$"#)
  private static let leadingY = try! NSRegularExpression(pattern: "^y")
  private static let vowels = try! NSRegularExpression(pattern: "[aeiouy]{1,2}")

  /// Syllables in a word, by the usual rule of thumb: groups of vowels, less a silent ending.
  private static func syllableCount(_ word: Substring) -> Int {
    var w = String(word.lowercased().unicodeScalars.filter { $0 >= "a" && $0 <= "z" })
    if w.isEmpty { return 0 }
    if w.count <= 3 { return 1 }
    for pattern in [silentEnd, leadingY] {
      w = pattern.stringByReplacingMatches(in: w, range: NSRange(w.startIndex..., in: w), withTemplate: "")
    }
    return max(1, vowels.numberOfMatches(in: w, range: NSRange(w.startIndex..., in: w)))
  }
}
