import Foundation

/// A document in the library. Each remembers on its own how it was left: its
/// look, and where each of its paragraphs sits.
struct Document {
  let id: String
  let title: String
  let authors: [String]
  /// For one that comes with the app, the bundled file its every version is written in.
  var resource: String? = nil
  /// Came from the reader's own files (see `Imports`), rather than with the app.
  var imported = false

  /// Whether `Topic.demo`'s hand-written topics are about this document's paragraphs.
  var handTopics: Bool { id == Self.written.id }

  /// The black holes paper, every version of it written ahead.
  static let written = Document(
    id: "black-holes", title: Manuscript.blackHoles.title, authors: Manuscript.blackHoles.authors, resource: "content")

  /// How honeybees choose a home, every version of it written ahead too.
  @MainActor static let live: Document = {
    let c = Content.named("swarm")
    return Document(id: "swarm", title: c.title ?? "", authors: c.authors ?? [], resource: "swarm")
  }()

  /// The documents that come with the app, then whatever's been brought in, in the order it came.
  @MainActor static var all: [Document] { [written, live] + Imports.shared.documents }

  /// Whether it can be opened yet: an import may still be on its way, or what was made of it may be gone.
  @MainActor var openable: Bool { !imported || Imports.shared.book(id) != nil }

  /// The document read last, to open on.
  @MainActor static var last: Document { all.first { $0.id == Store.lastDocument && $0.openable } ?? written }
}

/// How a document was left: where each paragraph sits on the grid of versions,
/// and the look it's read in, so it opens again as it was.
struct ReadingState: Codable {
  /// Difficulty and zoom of each paragraph.
  var c: [Int]?
  var z: [Int]?
  /// The look (see `ReadingStyle`); the document's own first look if missing.
  var style: Int?
}

enum Store {
  private static let defaults = UserDefaults.standard

  static func newId() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

  /// Where each paragraph sat was kept on the eleven levels there once were; it's
  /// kept apart for the six there are now, so every document starts afresh.
  private static func readingKey(_ document: String) -> String { "aube-reading-\(Scale.levels)/\(document)" }

  static func loadReading(_ document: String) -> ReadingState? {
    defaults.data(forKey: readingKey(document)).flatMap { try? JSONDecoder().decode(ReadingState.self, from: $0) }
  }

  static func saveReading(_ document: String, _ state: ReadingState) {
    if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: readingKey(document)) }
  }

  static func forgetReading(_ document: String) {
    defaults.removeObject(forKey: readingKey(document))
  }

  /// Whether the chat model answers on OpenAI's fast service tier, rather than
  /// its normal one.
  static var fastTier: Bool {
    get { defaults.object(forKey: "aube-fast-tier") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "aube-fast-tier") }
  }

  /// Whether a version is written only once a gesture on the page calls for it,
  /// rather than also a step ahead of the paragraphs in view.
  static var writeOnGesture: Bool {
    get { defaults.object(forKey: "aube-write-on-gesture") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "aube-write-on-gesture") }
  }

  /// Whether requests go to gpt-6-luna rather than gpt-6.1-terra.
  static var useLuna: Bool {
    get { defaults.object(forKey: "aube-use-luna") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "aube-use-luna") }
  }

  /// Whether a document brought in is looked over by the model, which sees pictures of its pages.
  static var checkImports: Bool {
    get { defaults.object(forKey: "aube-check-imports") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "aube-check-imports") }
  }

  /// Which document was read last.
  static var lastDocument: String? {
    get { defaults.string(forKey: "aube-last-document") }
    set { defaults.set(newValue, forKey: "aube-last-document") }
  }
}
