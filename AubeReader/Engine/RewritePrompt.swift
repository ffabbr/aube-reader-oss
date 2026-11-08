import Foundation

/// A version of a paragraph already written, and which one it is.
typealias WrittenVersion = (key: LiveText.Key, text: String)

/// What a rewrite is asked for: version `key`, written from version `from`,
/// and, when its level changes, the versions already written at its length
/// on either side of it, which it has to read between.
struct RewriteBrief {
  let key: LiveText.Key
  let from: WrittenVersion
  let easier: WrittenVersion?
  let harder: WrittenVersion?
  /// How many words it should run to, and how far from that it may land.
  let target: Int
  let slack: Int
  /// Whether its level can be measured: only in English.
  let graded: Bool

  init(_ key: LiveText.Key, from: WrittenVersion, among written: [WrittenVersion], target: Int, slack: Int, graded: Bool) {
    self.key = key
    self.from = from
    self.target = target
    self.slack = slack
    self.graded = graded
    let level = key.c != from.key.c
    let row = written.filter { level && $0.key.z == key.z }
    easier = row.filter { $0.key.c < key.c }.max { $0.key.c < $1.key.c }
    harder = row.filter { $0.key.c > key.c }.min { $0.key.c < $1.key.c }
  }
}

/// Something wrong with a rewrite, as the model is told it.
struct RewriteProblem {
  let said: String
  /// Far enough off to write again even once it's been seen.
  let serious: Bool
}

/// The instructions and messages a rewrite is asked with, and the checks its
/// answer has to pass.
enum RewritePrompt {
  static let system = """
    You rewrite single paragraphs of a document for an adaptive reader. Readers make any paragraph easier or harder, \
    and shorter or longer, one step at a time, and expect every step to change it by the same, predictable amount.

    Difficulty is measured as the Flesch–Kincaid grade level: 0.39 × (words per sentence) + 11.8 × (syllables per word) \
    − 15.59. There are \(Scale.levels) levels, each \(Scale.gradeStep) grades above the one before:
    \((0..<Scale.levels).map { "- Level \($0): grade \(grade(Scale.grade($0))), for \(Scale.readers[$0])." }.joined(separator: "\n"))
    To lower the grade, split sentences and prefer short, common words; to raise it, combine ideas into longer \
    sentences and use the precise, longer terms of the field. Higher levels also assume more background and carry \
    more exact detail; lower levels explain or leave out what a younger reader wouldn't know.

    Length is measured in words (whitespace-separated). Each paragraph has its own ladder of seven evenly spaced \
    lengths, from about a quarter of the original to well over it, and every request gives you the length to reach. \
    Always land within the range you're given.

    Rules:
    - Write in the language of the original paragraph, whatever it is.
    - Stay faithful to the original paragraph: same subject, same claims, nothing that contradicts it. Any added \
    detail must be accurate and well established.
    - Write only this paragraph's content; the paragraphs around it are given for context and must not be repeated \
    or anticipated.
    - Output the paragraph's text alone: one paragraph of plain prose, with no title, quotes, lists, markdown or \
    commentary.
    - Formulas are written in TeX between dollar signs. Wherever one is still needed, keep it exactly as it is, between \
    its dollar signs, and don't spell it out in words. Never put dollar signs around anything else.
    - Something like [^12] is the mark of a footnote the reader can open. Keep every one exactly as it is, with no space \
    before it, straight after the word or punctuation it belongs to, moving it with those words if they move. Never add \
    one, renumber one, or say in words what it is, and don't count it as a word.
    """

  private static func grade(_ g: Double) -> String { String(format: "%.1f", g) }

  /// Asks for the version `brief` describes of one of `text`'s paragraphs.
  static func messages(_ text: LiveText, _ brief: RewriteBrief) -> [[String: String]] {
    let (key, from) = (brief.key, brief.from)
    let doc = text.source
    let p = key.p
    let paragraphs = doc.paragraphs
    let original = paragraphs[p]
    let (c0, z0) = text.home(p)
    let basis = from.text
    let had = Scale.count(basis)
    let target = brief.target
    var lines = ["Document: \"\(doc.title)\" (\(doc.field)). Paragraph \(p + 1) of \(paragraphs.count)."]
    if p > 0 { lines.append("Previous paragraph, for context: \"\(paragraphs[p - 1])\"") }
    if p + 1 < paragraphs.count { lines.append("Next paragraph, for context: \"\(paragraphs[p + 1])\"") }
    lines.append(
      "ORIGINAL (level \(c0), \(Scale.count(original)) words, grade \(grade(Scale.grade(of: original)))): \"\(original)\"")
    if (from.key.c, from.key.z) == (c0, z0) {
      lines.append("CURRENT is the original.")
    } else {
      lines.append("CURRENT (level \(from.key.c), \(had) words, grade \(grade(Scale.grade(of: basis)))): \"\(basis)\"")
    }
    let around = [brief.easier, brief.harder].compactMap { $0 }
    for v in around where v.key != from.key {
      lines.append(
        "Already written at this length, for comparison: level \(v.key.c) (grade \(grade(Scale.grade(of: v.text)))): \"\(v.text)\"")
    }
    var how: [String] = []
    if key.c != from.key.c {
      let n = abs(key.c - from.key.c)
      how.append(
        "make it \(n) level\(n > 1 ? "s" : "") \(key.c > from.key.c ? "harder" : "easier"), from grade "
          + "\(grade(Scale.grade(of: basis))) to grade \(grade(Scale.grade(key.c))) (level \(key.c), for "
          + "\(Scale.readers[key.c])); keep its facts in the same order, and keep CURRENT's wording wherever it "
          + "already suits that level"
          + (around.isEmpty
            ? ""
            : "; it has to read "
              + [brief.easier.map { "harder than level \($0.key.c)" }, brief.harder.map { "easier than level \($0.key.c)" }]
              .compactMap { $0 }.joined(separator: " and ")))
    }
    if key.z > from.key.z {
      how.append(
        "make it shorter, from \(had) to \(target) words, mainly by deleting: drop words, phrases and whole "
          + "sentences, keep the most important ideas, and leave the wording that remains as it is (fix grammar "
          + "only where a cut breaks it)")
    } else if key.z < from.key.z {
      how.append(
        "make it longer, from \(had) to \(target) words, mainly by inserting: keep every sentence of CURRENT in "
          + "order and in its wording, and add clauses and sentences with more detail on the same point, from "
          + "ORIGINAL first, then accurate, well-established facts")
    } else {
      how.append("keep it at \(target) words")
    }
    lines.append("Rewrite CURRENT: " + how.joined(separator: "; ") + ".")
    lines.append(
      "Target: \(target) words (between \(target - brief.slack) and \(target + brief.slack))"
        + (key.c != from.key.c ? ", grade \(grade(Scale.grade(key.c)))." : ", at the same level."))
    return [["role": "system", "content": system], ["role": "user", "content": lines.joined(separator: "\n\n")]]
  }

  /// How a rewrite misses its length, or, when its level changed, its grade:
  /// out of order with the levels written either side of it, or else wide of its own.
  static func problems(_ got: String, _ brief: RewriteBrief) -> [RewriteProblem] {
    let (key, from) = (brief.key, brief.from)
    var found: [RewriteProblem] = []
    let n = Scale.count(got)
    let target = brief.target
    let off = abs(n - target)
    if off > brief.slack {
      found.append(
        RewriteProblem(
          said: "it has \(n) words; it needs between \(target - brief.slack) and \(target + brief.slack)",
          serious: off > 2 * brief.slack))
    }
    if brief.graded && key.c != from.key.c && n >= Scale.gradedWords {
      let g = Scale.grade(of: got)
      let want = Scale.grade(key.c)
      // The ladder has to run one way: each level reads harder than the one below it.
      var order: [RewriteProblem] = []
      if let e = brief.easier, case let ge = Scale.grade(of: e.text), g <= ge {
        order.append(
          RewriteProblem(said: "it measures grade \(grade(g)), no harder than level \(e.key.c) (grade \(grade(ge)))", serious: ge - g > 0.5))
      }
      if let h = brief.harder, case let gh = Scale.grade(of: h.text), g >= gh {
        order.append(
          RewriteProblem(said: "it measures grade \(grade(g)), no easier than level \(h.key.c) (grade \(grade(gh)))", serious: g - gh > 0.5))
      }
      found += order
      let backwards = (key.c > from.key.c) != (g > Scale.grade(of: from.text))
      if order.isEmpty && (backwards || abs(g - want) > Scale.gradeSlack) {
        found.append(
          RewriteProblem(
            said: "it measures grade \(grade(g)); it needs grade \(grade(want))"
              + (g > want ? " (shorter sentences, simpler words)" : " (longer sentences, more precise terms)"),
            serious: backwards))
      }
    }
    return found
  }

  /// The paragraph alone: one line, without quotes round it.
  static func clean(_ s: String) -> String {
    var t = NoteToken.tighten(s.split(whereSeparator: \.isWhitespace).joined(separator: " "))
    for (open, close) in [("\"", "\""), ("“", "”")] where t.hasPrefix(open) && t.hasSuffix(close) && t.count > 1 {
      t = String(t.dropFirst().dropLast())
    }
    return t
  }
}
