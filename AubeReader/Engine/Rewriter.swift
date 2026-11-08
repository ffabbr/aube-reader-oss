import Foundation

/// A version of a paragraph the reader would like written, and how soon:
/// lower `rank` first.
struct Wish: Equatable {
  let p: Int
  let c: Int
  let z: Int
  let rank: Double
  /// On screen already, as placeholders, rather than a step ahead.
  let shown: Bool
  /// The version the paragraph reads at now, best to start from.
  let fromC: Int
  let fromZ: Int

  var key: LiveText.Key { LiveText.Key(p: p, c: c, z: z) }
}

/// Writes the versions of a live document's paragraphs that the reader is
/// nearest, a few at a time, each from a version already written beside it.
/// The words stream onto the page as they come, in place of placeholders;
/// each finished version is checked against `Scale` before it's kept.
final class Rewriter {
  /// How many versions are written at once.
  static let lanes = 4
  /// How many times a version is asked for before the closest is kept.
  static let tries = 2

  private weak var text: LiveText?
  /// What's wanted, most wanted first.
  private var queue: [Wish] = []
  private var busy: Set<LiveText.Key> = []
  /// Versions that couldn't be written, and when to try again.
  private var resting: [LiveText.Key: (until: Date, times: Int)] = [:]
  private var wake: Timer?
  /// Called when a version can't be written, with why, at most every few seconds.
  var onTrouble: ((String) -> Void)?
  private var complained = Date.distantPast

  init(_ text: LiveText) {
    self.text = text
  }

  /// Puts `wishes` in place of whatever was wanted before. Versions already
  /// being written carry on; they'll be wanted again soon enough.
  func want(_ wishes: [Wish]) {
    queue = wishes
    pump()
  }

  /// Starts on the most wanted versions while there are lanes free.
  private func pump() {
    guard let text else { return }
    let now = Date()
    while busy.count < Self.lanes {
      guard
        let i = queue.firstIndex(where: { w in
          !busy.contains(w.key) && text.text(w.key) == nil && (resting[w.key]?.until ?? .distantPast) <= now
        })
      else { break }
      let w = queue.remove(at: i)
      busy.insert(w.key)
      Task { @MainActor [weak self] in await self?.write(w) }
    }
    // Something waiting out a failure is tried again once it has rested.
    let next = queue.compactMap { resting[$0.key]?.until }.filter { $0 > now }.min()
    wake?.invalidate()
    wake = next.map { Timer.scheduledTimer(withTimeInterval: $0.timeIntervalSinceNow + 0.05, repeats: false) { [weak self] _ in self?.pump() } }
  }

  @MainActor
  private func write(_ w: Wish) async {
    defer {
      busy.remove(w.key)
      pump()
    }
    guard let text else { return }
    let target = text.length(w.p, w.z)
    let brief = Brief(
      w.key, from: start(for: w, in: text), among: text.versions(of: w.p), target: target, slack: text.slack(w.p, w.z), graded: text.graded)
    var messages = Prompt.messages(text, brief)
    var best: (text: String, problems: [Problem])?
    do {
      for attempt in 0..<Self.tries {
        var got = ""
        var shown = (at: Date.distantPast, text: "")
        for try await piece in OpenAI.stream(messages, effort: "none") {
          got += piece
          // The first try streams onto the page, a whole word at a time.
          guard attempt == 0, Date().timeIntervalSince(shown.at) > 0.08 else { continue }
          let whole = Prompt.clean(String(got[..<(got.lastIndex(where: \.isWhitespace) ?? got.startIndex)]))
          guard whole != shown.text else { continue }
          shown = (Date(), whole)
          text.show(w.key, whole, skeleton: target)
        }
        got = Prompt.clean(got)
        let problems = Prompt.problems(got, brief)
        if best.map({ problems.count < $0.problems.count }) ?? true { best = (got, problems) }
        // Something already on screen is only written again if it's well wide of the mark.
        let serious = w.shown ? problems.filter(\.serious) : problems
        if serious.isEmpty || attempt == Self.tries - 1 { break }
        // While it's written again, the first try stays on the page.
        if attempt == 0 { text.show(w.key, got, skeleton: 0) }
        messages += [
          ["role": "assistant", "content": got],
          ["role": "user", "content": "Not quite: " + problems.map(\.said).joined(separator: "; and ") + ". Write it again, changing only what that needs."],
        ]
      }
      guard let best, !best.text.isEmpty else { throw OpenAI.Failure(errorDescription: "The model wrote nothing.") }
      resting[w.key] = nil
      // Whatever became of the words, a paragraph's notes stay within reach.
      text.keep(w.key, NoteToken.restore(best.text, from: text.source.paragraphs[w.p]))
    } catch {
      // A first try that came through is better than nothing.
      if let best, !best.text.isEmpty {
        text.keep(w.key, NoteToken.restore(best.text, from: text.source.paragraphs[w.p]))
        return
      }
      text.drop(w.key)
      // Without a key nothing will work until the app is built with one.
      let times = (resting[w.key]?.times ?? 0) + 1
      let wait = OpenAI.key == nil ? 3600 : min(60, 4 * pow(2, Double(times - 1)))
      resting[w.key] = (Date().addingTimeInterval(wait), times)
      if Date().timeIntervalSince(complained) > 8 {
        complained = Date()
        onTrouble?(error.localizedDescription)
      }
    }
  }

  /// The version to write `w` from: the nearest one written, counting steps
  /// along both axes; of those, the one the reader is at, then one along a
  /// single axis, so that the change asked for is as simple as it can be.
  private func start(for w: Wish, in text: LiveText) -> (key: LiveText.Key, text: String) {
    text.versions(of: w.p).min { a, b in
      func cost(_ k: LiveText.Key) -> (Int, Int, Int) {
        let dc = abs(k.c - w.c)
        let dz = abs(k.z - w.z)
        return (dc + dz, k.c == w.fromC && k.z == w.fromZ ? 0 : 1, min(dc, dz))
      }
      return cost(a.key) < cost(b.key)
    }!
  }
}

// ─── What's asked ───────────────────────────────────────────────────────────

typealias Version = (key: LiveText.Key, text: String)

/// What a rewrite is asked for: version `key`, written from version `from`,
/// and, when its level changes, the versions already written at its length
/// on either side of it, which it has to read between.
struct Brief {
  let key: LiveText.Key
  let from: Version
  let easier: Version?
  let harder: Version?
  /// How many words it should run to, and how far from that it may land.
  let target: Int
  let slack: Int
  /// Whether its level can be measured: only in English.
  let graded: Bool

  init(_ key: LiveText.Key, from: Version, among written: [Version], target: Int, slack: Int, graded: Bool) {
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
struct Problem {
  let said: String
  /// Far enough off to write again even once it's been seen.
  let serious: Bool
}

enum Prompt {
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
  static func messages(_ text: LiveText, _ brief: Brief) -> [[String: String]] {
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
  static func problems(_ got: String, _ brief: Brief) -> [Problem] {
    let (key, from) = (brief.key, brief.from)
    var found: [Problem] = []
    let n = Scale.count(got)
    let target = brief.target
    let off = abs(n - target)
    if off > brief.slack {
      found.append(
        Problem(
          said: "it has \(n) words; it needs between \(target - brief.slack) and \(target + brief.slack)",
          serious: off > 2 * brief.slack))
    }
    if brief.graded && key.c != from.key.c && n >= Scale.gradedWords {
      let g = Scale.grade(of: got)
      let want = Scale.grade(key.c)
      // The ladder has to run one way: each level reads harder than the one below it.
      var order: [Problem] = []
      if let e = brief.easier, case let ge = Scale.grade(of: e.text), g <= ge {
        order.append(
          Problem(said: "it measures grade \(grade(g)), no harder than level \(e.key.c) (grade \(grade(ge)))", serious: ge - g > 0.5))
      }
      if let h = brief.harder, case let gh = Scale.grade(of: h.text), g >= gh {
        order.append(
          Problem(said: "it measures grade \(grade(g)), no easier than level \(h.key.c) (grade \(grade(gh)))", serious: g - gh > 0.5))
      }
      found += order
      let backwards = (key.c > from.key.c) != (g > Scale.grade(of: from.text))
      if order.isEmpty && (backwards || abs(g - want) > Scale.gradeSlack) {
        found.append(
          Problem(
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
