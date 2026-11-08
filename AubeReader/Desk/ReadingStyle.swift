import UIKit

/// How a reader dresses its text: plain prose; a paper, with a title, an
/// abstract, headings, equations and figures; or a journal page, set in a
/// serif in two justified columns. The paragraphs morph the same way in each.
enum ReadingStyle: Int, CaseIterable {
  case plain, paper, journal

  var name: String { ["Plain", "Paper", "Journal"][rawValue] }
  var symbol: String { ["text.alignleft", "doc.richtext", "newspaper"][rawValue] }
}

/// Where the text sits on a page, in page units.
struct Sheet: Equatable {
  /// The left edge of the text, and how wide it runs across all its columns.
  var left: Double
  var width: Double
  var column: Double
  var gutter: Double
  var columns: Int
  var fontSize: CGFloat

  func columnX(_ i: Int) -> Double { left + Double(i) * (column + gutter) }

  /// Where a note is set, to be read over the page in its tip.
  static let notes = Sheet.plain(620)

  /// One column of sans-serif text, centered.
  static func plain(_ width: CGFloat) -> Sheet {
    let column = Double(min(620, (width - 48).rounded()))
    let left = ((Double(width) - column) / 2).rounded()
    return Sheet(left: left, width: column, column: column, gutter: 0, columns: 1, fontSize: width < 640 ? 17.5 : 20)
  }

  /// Two columns of serif text with a printed page's margins: about the
  /// proportions of a letter-size journal page, scaled to the screen.
  static func journal(_ width: CGFloat) -> Sheet {
    let w = Double(width)
    let margin = max(32, (w * 0.07).rounded())
    let text = min(w - 2 * margin, 980)
    let columns = text < 560 ? 1 : 2
    let gutter = columns == 1 ? 0 : (text * 0.035).rounded()
    let column = ((text - gutter) / Double(columns)).rounded(.down)
    let full = column * Double(columns) + gutter
    let size = CGFloat(clamp((column * (columns == 1 ? 0.03 : 0.034) * 2).rounded() / 2, 13, 17))
    return Sheet(
      left: ((w - full) / 2).rounded(), width: full, column: column, gutter: gutter, columns: columns, fontSize: size)
  }
}
