import PDFKit
import UIKit

/// A color as a page prints it.
struct Tint: Codable, Equatable, Hashable {
  var r: CGFloat
  var g: CGFloat
  var b: CGFloat

  static let black = Tint(r: 0, g: 0, b: 0)
  static let white = Tint(r: 1, g: 1, b: 1)

  var luma: CGFloat { 0.3 * r + 0.59 * g + 0.11 * b }

  init(r: CGFloat, g: CGFloat, b: CGFloat) {
    self.r = r
    self.g = g
    self.b = b
  }

  init?(_ color: UIColor?) {
    guard let color else { return nil }
    let cg = color.cgColor
    let srgb = CGColorSpace.sRGBSpace
    guard let c = cg.converted(to: srgb, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else {
      guard let c = cg.components, let v = c.first else { return nil }
      self.init(r: v, g: v, b: v)
      return
    }
    self.init(r: c[0], g: c[1], b: c[2])
  }
}

/// A font as the document names it. PDFKit's own answer is a stand-in (nearly
/// everything comes back as Helvetica), so this is read from the page's resources.
struct FontRecord: Codable, Equatable, Hashable {
  /// The name with any subset prefix ("ABCDEF+") taken off.
  var name: String
  var bold: Bool
  var italic: Bool
  var serif: Bool
  var mono: Bool
  /// A font of symbols: math, dingbats. Text in it isn't prose.
  var math: Bool
  /// The family to set it in, if the check found a better one than the device's own guess.
  var standIn: String?
}

/// A word on a page, in page points, y down.
struct RawWord {
  var text: String
  var rect: CGRect
  var size: CGFloat
  var font: Int
  var color: Tint
  /// +1 raised, −1 lowered, 0 on the line.
  var script = 0
  var hidden = false
  /// Touches the word before it: the parts of "x²" are one word to a reader.
  var glued = false
}

/// Words that stand together on one baseline, with no wide gap between them.
struct RawRun {
  var words: [RawWord]
  var rect: CGRect
  var baseline: CGFloat
  var size: CGFloat
  var font: Int
  var color: Tint
}

/// What's on a page besides text.
struct RawMark {
  /// `tint` is a shape that's only filled: it may just be there to color what's on it.
  enum Kind { case image, vector, tint }
  var rect: CGRect
  var kind: Kind
}

struct RawPage {
  var size: CGSize
  var runs: [RawRun] = []
  /// Pictures and line art, ungrouped.
  var marks: [RawMark] = []
  /// Thin lines: table rules and separators, which belong to no figure.
  var rules: [CGRect] = []
  /// Filled shapes large enough for text to sit on.
  var panels: [(rect: CGRect, tint: Tint)] = []
  /// Text set sideways or at an angle, kept only as part of the picture.
  var sideways: [CGRect] = []
  /// The whole page is a picture of a page.
  var scanned = false
  /// The text was read from the page's picture (OCR), not its text layer.
  var ocr = false
  /// Whether the text layer looks like nonsense, so what it says can't be used.
  var garbled = false
  /// How many shows of text the page's stream holds, whatever came of them.
  var shows = 0
  /// How far it was turned, clockwise, to bring its text upright.
  var turn = 0
  /// The paper's color, where the page prints one.
  var paper: Tint = .white
}

/// Maps a page's own coordinates (y up, turned by its rotation) to what a
/// reader sees: y down from the top left of the page as it's displayed.
struct PageFrame {
  let size: CGSize
  let toDisplay: CGAffineTransform

  init(_ page: PDFPage) {
    let box = page.bounds(for: .cropBox)
    let (w, h) = (box.width, box.height)
    switch ((page.rotation % 360) + 360) % 360 {
    case 90:
      size = CGSize(width: h, height: w)
      toDisplay = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: -box.minY, ty: -box.minX)
    case 180:
      size = CGSize(width: w, height: h)
      toDisplay = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: box.maxX, ty: -box.minY)
    case 270:
      size = CGSize(width: h, height: w)
      toDisplay = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: box.maxY, ty: box.maxX)
    default:
      size = CGSize(width: w, height: h)
      toDisplay = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -box.minX, ty: box.maxY)
    }
  }
}
