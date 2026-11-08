import CoreGraphics
import Foundation

/// What a stretch of a document is doing there. Only paragraphs (and the longer
/// list items and quotes) can be rewritten; the rest is set as it was found.
enum BlockRole: String, Codable, CaseIterable {
  case title, byline, abstract, heading, paragraph, list, quote
  /// A sidebar's small print, or a note nothing in the text leads to: text worth keeping, but not the argument.
  case note
  /// A footnote: never set among the text, only opened from its mark (see `NoteToken`).
  case footnote
  case caption, figure, table, equation, code, references
  /// Running heads, page numbers: they belong to the page, not the text.
  case furniture
  /// A scrap of text that fits nowhere else: a label, a date, a line of a form.
  case minor

  var isProse: Bool { self == .paragraph || self == .list || self == .quote || self == .abstract }
  /// Shown as a picture of the original, in every look that shows it.
  var isPicture: Bool { self == .figure || self == .table || self == .equation }
}

enum TextAlign: String, Codable {
  case left, center, right, justified
}

/// How a block was set in the original.
struct BlockStyle: Codable, Equatable {
  /// Index into the document's `fonts`, or −1 if unknown.
  var font = -1
  var size: CGFloat = 10
  /// From baseline to baseline.
  var leading: CGFloat = 12
  var color = Tint.black
  var align = TextAlign.left
  var indent: CGFloat = 0
  /// How wide a character runs on average, as a share of the size; 0 if unknown.
  var advance: CGFloat = 0
}

/// The part of a block on one page. A paragraph that runs across a column or
/// page break has one for each; the first is where it reads from.
struct BlockPiece: Codable, Equatable {
  var page: Int
  /// Its share of the page, all the way to its neighbors: every point of a page
  /// lies in exactly one tile, so laying them out again draws the page whole.
  var tile: CGRect
  /// The box around just its marks.
  var ink: CGRect
  /// For a footnote, the rule that sets it off from the text above, which goes where it goes.
  var rule: CGRect?
}

/// One block of an imported document, in reading order: a paragraph, a heading,
/// a figure, a footnote. Its text is what a reader reads; its pieces, where it
/// lies on the original pages.
struct DocBlock: Codable, Equatable {
  var id: Int
  var role: BlockRole
  /// For a heading, 1 is the largest.
  var level = 0
  var text: String
  var pieces: [BlockPiece]
  var style = BlockStyle()
  /// For a caption, the figure or table it describes.
  var captionOf: Int?
  /// Set in math fonts, somewhere in it: what it says isn't all in its characters.
  var mathy = false
  /// Its formulas have been written out in TeX, between dollar signs, and are to be set as formulas.
  var math = false
  /// What a note is marked with on the page: 3, *, †. Set on any block a mark in the text can open.
  var mark: String?

  var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// How a page's tiles fit together: stacked, side by side, or a tile itself.
struct PageTile: Codable, Equatable {
  enum Kind: String, Codable { case stack, side, block, blank }
  var kind: Kind
  var rect: CGRect
  var kids: [PageTile]?
  /// For a block's tile: which block, and which of its pieces.
  var block: Int?
  var piece: Int?

  var leaves: [PageTile] { kids.map { $0.flatMap(\.leaves) } ?? [self] }
}

/// One page of an imported document as it was printed: its size, how it's
/// cut into tiles of blocks, and what reading it found about it.
struct DocPage: Codable, Equatable {
  /// A US Letter page, in points: the size taken for a page whose own is unknown.
  static let letter = CGSize(width: 612, height: 792)

  var size: CGSize
  var tile: PageTile
  /// A picture of a page: its text came from OCR or the model.
  var scanned = false
  /// Nothing could be read on the device; the model is asked to read it.
  var unread = false
  var paper = Tint.white
  /// Where photographs lie, which keep their colors when the page goes dark.
  var photos: [CGRect] = []
  /// How far it's turned, clockwise, beyond what the file says, to bring its text upright.
  var turn = 0
  /// Where its page number is printed: the original look leaves it out.
  var folios: [CGRect] = []
}

/// Where a footnote's mark is printed on an original page, which is what's
/// tapped there. What the text says about it is in the text (see `NoteToken`).
struct PrintedMark: Codable, Equatable {
  /// The block it opens.
  var note: Int
  var page: Int
  var box: CGRect
}

/// A note of what the check found and did, for the document's report.
struct ImportNote: Codable, Equatable {
  var page: Int?
  var said: String
  var fixed: Bool
}

struct ImportReport: Codable, Equatable {
  enum State: String, Codable {
    /// Not looked at yet.
    case pending
    /// Looked at, and either nothing needed changing or everything was put right.
    case checked
    /// Looked at, and something couldn't be put right.
    case flagged
    /// Couldn't be looked at: no key, no connection, or checks turned off.
    case skipped
  }
  var state = State.pending
  var pagesChecked = 0
  var rounds = 0
  var notes: [ImportNote] = []
  /// What kind of document the model took it for.
  var kind: String?
  var why: String?
}

/// A document as an import understood it: its blocks in reading order, its
/// pages, its notes and what the check found. Saved as JSON beside the original file.
struct ImportedDoc: Codable, Equatable {
  /// Changes whenever documents read earlier have to be read again.
  static let format = 2

  var format = Self.format
  var id: String
  var fileName: String
  var title: String
  var authors: [String] = []
  /// What it's about, for the rewriter's sense of "in the field".
  var field = ""
  /// A BCP 47 tag, when it could be told.
  var language: String?
  var fonts: [FontRecord] = []
  var pages: [DocPage] = []
  /// In reading order.
  var blocks: [DocBlock] = []
  /// Every footnote mark as it's printed on the pages.
  var marks: [PrintedMark] = []
  var report = ImportReport()
  /// Set when there's no original layout to show: plain text and RTF.
  var flowing = false

  func block(_ id: Int) -> DocBlock? { blocks.first { $0.id == id } }
  var nextId: Int { (blocks.map(\.id).max() ?? -1) + 1 }
}
