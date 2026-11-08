import UIKit

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
