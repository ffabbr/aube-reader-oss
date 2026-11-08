import Foundation

/// A drawing in the library (`graphics/`, bundled as `svg/` and `index.json`).
struct Drawing: Decodable {
  let id: String
  let discipline: String
  let title: String
  let description: String
  let tags: [String]

  static let all: [Drawing] = {
    guard
      let url = Bundle.main.url(forResource: "index", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let all = try? JSONDecoder().decode([Drawing].self, from: data)
    else { return [] }
    return all
  }()

  /// The drawing itself: standalone SVG, its house style and animation baked in.
  var svg: String? {
    Bundle.main.url(forResource: id, withExtension: "svg", subdirectory: "svg").flatMap { try? String(contentsOf: $0) }
  }
}

extension Drawing {
  /// Asks of every drawing what `question` asks of it about `input`, and hands
  /// them back likeliest first, or none if the Decisions API can't be reached.
  /// One question per drawing rather than one question over all of them: a
  /// single choice piles its probability on one winner, and leaves nothing to
  /// tell the runners-up apart. Tried twice.
  static func ranked(for input: String, asking question: String) async -> [Drawing] {
    let questions = all.map { d in
      OpenAI.Predicate(name: d.id, instructions: "\(question) Drawing: \(d.title): \(d.description) (\(d.tags.joined(separator: ", ")))")
    }
    guard !questions.isEmpty else { return [] }
    for _ in 0..<2 {
      guard let odds = try? await OpenAI.decide(input, questions) else { continue }
      return all.filter { odds[$0.id] != nil }.sorted { odds[$0.id]! > odds[$1.id]! }
    }
    return []
  }
}

/// Finds what a paragraph is about, in the time its topic takes to open: a
/// title and a line beneath it from the chat model, and four drawings from the
/// Decisions API. The two run side by side, and each part is handed over as
/// soon as it's known. What's found is kept on disk, by the paragraph's text,
/// so the same paragraph opens at once from then on.
final class TopicWriter {
  private(set) var title: String?
  private(set) var deck: String?
  private(set) var drawings: [Drawing] = []
  /// Whether the title and the line have stopped coming, written or not.
  private(set) var wordsSettled = false
  /// Called on the main thread whenever any of the above changes.
  var onChange: (() -> Void)?

  private let paragraph: String
  private let passage: String

  /// How many drawings a topic shows.
  static let count = 4

  /// `source` is the document the paragraph comes from, to give it context.
  init(paragraph: String, from source: String) {
    self.paragraph = paragraph
    passage = "From \"\(source)\":\n\n\(paragraph)"
    let kept = Self.kept[paragraph]
    title = kept?.title
    deck = kept?.deck
    drawings = (kept?.drawings ?? []).compactMap { id in Drawing.all.first { $0.id == id } }
    wordsSettled = title != nil && deck != nil
    if !wordsSettled { Task { @MainActor in await self.write() } }
    if drawings.isEmpty { Task { @MainActor in await self.choose() } }
  }

  // ─── The words ───────────────────────────────────────────────────────────

  private static let briefing = """
    You title a passage for the head of a page that looks closer at its topic. Reply with exactly two \
    lines of plain text, with no Markdown and no quotation marks. Line 1: the topic, one to four words, \
    at most 26 letters, in sentence case, with no final period. Line 2: at most twelve words on why it \
    matters, not repeating the title.
    """

  @MainActor private func write() async {
    for attempt in 0..<2 where title == nil || deck == nil {
      // Past this, the skeleton has shown long enough; the page does without.
      let task = Task { @MainActor in try await self.stream() }
      let watchdog = Task {
        try await Task.sleep(for: .seconds(10))
        task.cancel()
      }
      let done = (try? await task.value) != nil
      watchdog.cancel()
      if done || attempt == 1 { break }
    }
    wordsSettled = true
    onChange?()
    remember()
  }

  /// The title is shown as soon as its line ends, before the line under it is written.
  @MainActor private func stream() async throws {
    var got = ""
    let messages = [["role": "system", "content": Self.briefing], ["role": "user", "content": passage]]
    for try await piece in OpenAI.stream(messages, effort: "none") {
      got += piece
      if title == nil, let end = got.firstIndex(of: "\n"), let line = Self.clean(got[..<end]) {
        title = line
        onChange?()
      }
    }
    let lines = got.split(separator: "\n").compactMap { Self.clean($0) }
    guard let first = lines.first else { throw OpenAI.Failure(errorDescription: "Nothing came back.") }
    if title == nil { title = first }
    deck = lines.count > 1 ? lines[1] : nil
    onChange?()
  }

  /// A line as written, without any dressing the model gave it anyway.
  private static func clean(_ line: Substring) -> String? {
    let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "*_#\"“”")))
    return trimmed.isEmpty ? nil : trimmed
  }

  // ─── The drawings ────────────────────────────────────────────────────────

  /// Keeps the most likely to illustrate the passage.
  @MainActor private func choose() async {
    let ranked = await Drawing.ranked(for: passage, asking: "Would this small drawing, set beside the passage, directly illustrate something the passage is about?")
    guard !ranked.isEmpty else { return }
    drawings = Array(ranked.prefix(Self.count))
    onChange?()
    remember()
  }

  // ─── On disk ─────────────────────────────────────────────────────────────

  private struct Kept: Codable {
    var title: String?
    var deck: String?
    var drawings: [String]?
  }

  private static var file: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Topics.json")
  }

  /// By the paragraph's text.
  private static var kept: [String: Kept] = {
    guard let data = try? Data(contentsOf: file), let kept = try? JSONDecoder().decode([String: Kept].self, from: data) else {
      return [:]
    }
    return kept
  }()

  /// Keeps what's complete: a title without its line is asked for again next time.
  @MainActor private func remember() {
    var k = Self.kept[paragraph] ?? Kept()
    if let title, let deck {
      k.title = title
      k.deck = deck
    }
    if !drawings.isEmpty { k.drawings = drawings.map(\.id) }
    guard k.title != nil || k.drawings != nil else { return }
    Self.kept[paragraph] = k
    let all = Self.kept
    let file = Self.file
    DispatchQueue.global(qos: .utility).async {
      guard let data = try? JSONEncoder().encode(all) else { return }
      try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
  }

  /// Reads the library and what's been kept ahead of the first long press.
  static func warm() {
    _ = Drawing.all
    _ = kept
  }
}
