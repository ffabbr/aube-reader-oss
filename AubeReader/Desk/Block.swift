import UIKit

/// Something on the page besides the paragraphs: a title, a heading, a figure.
/// Drawn once, then moved about with the text.
final class Block {
  let layer = BlockLayer()
  let height: Double
  var x = 0.0
  var top = 0.0
  var placed: CGPoint?
  /// A picture of part of a page to show, rather than anything drawn; `picture`
  /// is the layer it goes in, where the block also draws around it.
  var sprite: Sprite?
  private var picture: CALayer?
  /// Whether it's on the page now, or off it, costing nothing, while it's far from the screen.
  private(set) var attached = false
  /// Set for a tile: laid out at exactly this x, whatever the column.
  var fixedX: Double?
  /// The page of the original it comes from, where it comes from one.
  var page: Int?
  /// What the contents call it, if it's a title or a heading: a title is level 0, the largest heading 1.
  var landmark: (title: String, level: Int)?
  /// Notes marked on it, and where in it, for tapping.
  private(set) var marks: [TapMark] = []

  init(width: CGFloat, height: CGFloat, draw: @escaping (CGRect) -> Void) {
    self.height = Double(height.rounded(.up))
    layer.anchorPoint = .zero
    layer.bounds = CGRect(x: 0, y: 0, width: width, height: height.rounded(.up))
    layer.paint = draw
  }

  /// A tile of a page: nothing drawn, just its sprite, exactly `size`, at `offset.x`.
  init(size: CGSize, sprite: Sprite, offset: CGPoint) {
    height = Double(size.height)
    self.sprite = sprite
    fixedX = offset.x
    layer.anchorPoint = .zero
    layer.bounds = CGRect(origin: .zero, size: size)
    layer.contentsRect = sprite.part
    layer.contentsGravity = .resize
  }

  /// Text drawn around a sprite placed at `spriteRect`.
  init(width: CGFloat, height: CGFloat, sprite: Sprite, spriteRect: CGRect, draw: @escaping (CGRect) -> Void) {
    self.height = Double(height.rounded(.up))
    self.sprite = sprite
    layer.anchorPoint = .zero
    layer.bounds = CGRect(x: 0, y: 0, width: width, height: height.rounded(.up))
    layer.paint = draw
    let inner = StillLayer()
    inner.frame = spriteRect
    inner.contentsGravity = .resize
    layer.addSublayer(inner)
    picture = inner
  }

  /// The notes marked on it. Those that say what to paint have nothing else to show them: on a
  /// picture of a page, the mark's painted over where it was printed, as a mark among the words looks.
  func show(_ marks: [TapMark], traits: UITraitCollection) {
    self.marks = marks
    let ink = Palette.ink.resolvedColor(with: traits)
    for m in marks {
      guard let label = m.paint else { continue }
      let badge = StillLayer()
      badge.frame = m.rect
      badge.contents = Halo.image(label, diameter: m.rect.height, ink: ink, scale: max(traits.displayScale, 1)).cgImage
      badge.contentsScale = max(traits.displayScale, 1)
      layer.addSublayer(badge)
    }
  }

  /// Puts it on the page under `parent`, and asks for what it shows.
  func attach(to parent: CALayer) {
    guard !attached else { return }
    attached = true
    parent.insertSublayer(layer, at: 0)
    if layer.paint != nil { layer.setNeedsDisplay() }
    guard let sprite else { return }
    let target = picture ?? layer
    sprite.atlas.picture(sprite.key) { [weak self, weak target] image in
      guard let self, self.attached, let target else { return }
      target.contents = image
    }
  }

  /// Takes it off the page, and lets go of what it was showing.
  func detach() {
    guard attached else { return }
    attached = false
    layer.removeFromSuperlayer()
    layer.contents = nil
    picture?.contents = nil
    placed = nil
  }

  /// Where its sprite goes within it, if it's set among other things.
  var spriteFrame: CGRect? { picture?.frame }

  /// What it shows, cropped, for drawing elsewhere.
  var picturePart: CGImage? {
    guard let sprite, let image = ((picture ?? layer).contents as! CGImage?) else { return nil }
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    return image.cropping(to: CGRect(x: sprite.part.minX * w, y: sprite.part.minY * h, width: sprite.part.width * w, height: sprite.part.height * h))
  }
}

/// Somewhere a reader can tap to open a note.
struct TapMark {
  let note: Int
  /// In the coordinates of what it's on: a block, or the page once `ReaderView` has found it.
  let rect: CGRect
  /// What to paint there, where nothing's set to show it.
  var paint: String?
}

/// Draws a block with UIKit, in the colors of the reader's appearance.
final class BlockLayer: StillLayer {
  var paint: ((CGRect) -> Void)?
  var traits = UITraitCollection.current

  override func draw(in ctx: CGContext) {
    UIGraphicsPushContext(ctx)
    traits.performAsCurrent { paint?(bounds) }
    UIGraphicsPopContext()
  }
}

/// One paragraph of the text, or a block set beside it.
enum Entry {
  case para(Int)
  case block(Block)
}

/// A stretch of the page: entries across its full width, or side-by-side
/// columns of them that the next band waits for.
enum Band {
  case span([Entry])
  case columns([[Entry]])
  /// An original page, with its own arrangement of columns (see `ImportedBook`).
  case region(Region)

  /// Everything in it, in the order it reads.
  var entries: [Entry] {
    switch self {
    case let .span(items): return items
    case let .columns(cols): return cols.flatMap { $0 }
    case let .region(r): return r.entries
    }
  }
}
