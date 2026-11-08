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
  private var watching: NSObjectProtocol?

  init(_ text: LiveText) {
    self.text = text
    // Once the model can be reached again, what was waiting on it needn't wait out its rest.
    watching = NotificationCenter.default.addObserver(forName: OpenAI.accessChanged, object: nil, queue: .main) { [weak self] _ in
      self?.resting = [:]
      self?.pump()
    }
  }

  deinit {
    if let watching { NotificationCenter.default.removeObserver(watching) }
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
    let brief = RewriteBrief(
      w.key, from: start(for: w, in: text), among: text.versions(of: w.p), target: target, slack: text.slack(w.p, w.z), graded: text.graded)
    var messages = RewritePrompt.messages(text, brief)
    var best: (text: String, problems: [RewriteProblem])?
    do {
      for attempt in 0..<Self.tries {
        var got = ""
        var shown = (at: Date.distantPast, text: "")
        for try await piece in OpenAI.stream(messages, effort: "none") {
          got += piece
          // The first try streams onto the page, a whole word at a time.
          guard attempt == 0, Date().timeIntervalSince(shown.at) > 0.08 else { continue }
          let whole = RewritePrompt.clean(String(got[..<(got.lastIndex(where: \.isWhitespace) ?? got.startIndex)]))
          guard whole != shown.text else { continue }
          shown = (Date(), whole)
          text.show(w.key, whole, skeleton: target)
        }
        got = RewritePrompt.clean(got)
        let problems = RewritePrompt.problems(got, brief)
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
      // Without the model nothing will work until Settings gives it one.
      let times = (resting[w.key]?.times ?? 0) + 1
      let wait = OpenAI.available ? min(60, 4 * pow(2, Double(times - 1))) : 3600
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
