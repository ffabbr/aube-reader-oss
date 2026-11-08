import Foundation

/// How a document was left: where each paragraph sits on the grid of versions,
/// and the look it's read in, so it opens again as it was.
struct ReadingState: Codable {
  /// Difficulty and zoom of each paragraph.
  var c: [Int]?
  var z: [Int]?
  /// The look (see `ReadingStyle`); the document's own first look if missing.
  var style: Int?
}

/// The app's settings and what it remembers between launches, kept in
/// UserDefaults. Secrets aren't kept here, but in the `Keychain`.
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

  /// How the app reaches OpenAI, once chosen on the welcome screen or in
  /// Settings; nil until then.
  static var access: Access? {
    get { defaults.string(forKey: "aube-access").flatMap(Access.init) }
    set {
      defaults.set(newValue?.rawValue, forKey: "aube-access")
      OpenAI.announceChange()
    }
  }

  /// Whether the note that requests now run on the ChatGPT plan has been shown:
  /// once, after the first sign-in that granted it.
  static var planNoted: Bool {
    get { defaults.bool(forKey: "aube-chatgpt-plan-noted") }
    set { defaults.set(newValue, forKey: "aube-chatgpt-plan-noted") }
  }

  /// Which document was read last.
  static var lastDocument: String? {
    get { defaults.string(forKey: "aube-last-document") }
    set { defaults.set(newValue, forKey: "aube-last-document") }
  }
}
