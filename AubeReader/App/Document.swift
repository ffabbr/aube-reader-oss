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

  /// “Attention Is All You Need”, the paper itself, every version of it written ahead.
  static let attention = Document(
    id: "attention", title: Manuscript.attention.title, authors: Manuscript.attention.authors, resource: "attention")

  /// The LIGO paper announcing GW150914, the first black hole merger observed, every version of it written ahead.
  static let gw150914 = Document(
    id: "gw150914", title: Manuscript.gw150914.title, authors: Manuscript.gw150914.authors, resource: "gw150914")

  /// “Black Holes”, a review made up for the app, every version of it written ahead.
  static let blackHoles = Document(
    id: "black-holes", title: Manuscript.blackHoles.title, authors: Manuscript.blackHoles.authors, resource: "black-holes")

  /// “How a Swarm Chooses a Home”, a review made up for the app, every version of it written ahead.
  static let swarm = Document(
    id: "swarm", title: Manuscript.swarm.title, authors: Manuscript.swarm.authors, resource: "swarm")

  /// The documents that come with the app, then whatever's been brought in, in the order it came.
  @MainActor static var all: [Document] { [attention, gw150914, blackHoles, swarm] + Imports.shared.documents }

  /// Whether it can be opened yet: an import may still be on its way, or what was made of it may be gone.
  @MainActor var openable: Bool { !imported || Imports.shared.book(id) != nil }

  /// The document read last, to open on.
  @MainActor static var last: Document { all.first { $0.id == Store.lastDocument && $0.openable } ?? attention }
}
