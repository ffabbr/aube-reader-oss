import UIKit

/// A book as a real box in three dimensions: its cover at z = 0, so it's exactly
/// where the layout puts it, and spine, fore-edge and head going back from it.
final class BookView: UIView {
  /// The camera's distance from the books' covers.
  static let cameraDistance: CGFloat = 1250
  /// The tallest a book gets, in book widths.
  static let tallest: CGFloat = BookSpec.aspect * 1.05

  private let scene = StillLayer()
  /// How the carousel has turned it, under whatever a finger or pointer does to the body.
  private let turn = StillTransformLayer()
  /// The shadow on the floor it stands on.
  private let floorShadow = StillLayer()
  private let body = StillTransformLayer()
  private let coverFace = StillLayer()
  private let spineFace = StillLayer()
  private let foreFace = StillLayer()
  private let headFace = StillLayer()
  private let marker = StillLayer()
  private let shine = StillGradientLayer()
  private let shineMask = StillLayer()
  private let gloss = StillGradientLayer()
  /// What's being done to it on its way in, tucked across the foot of the cover.
  let slip = StatusSlip()
  private var spec: BookSpec?
  private var faces: BookArt.TopicFace?
  private var shineOffset: CGFloat = 0
  private var isMetal = false
  private(set) var coverImage: UIImage?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.addSublayer(scene)
    scene.addSublayer(turn)
    turn.addSublayer(floorShadow)
    turn.addSublayer(body)
    floorShadow.shadowColor = UIColor.black.cgColor
    floorShadow.shadowOpacity = 0.42
    floorShadow.shadowRadius = 16
    floorShadow.shadowOffset = .zero
    for f in [spineFace, foreFace, headFace, marker, coverFace] {
      f.contentsGravity = .resize
      f.isDoubleSided = false
      f.minificationFilter = .trilinear
      body.addSublayer(f)
    }
    body.addSublayer(slip)
    coverFace.addSublayer(gloss)
    shine.mask = shineMask
    coverFace.addSublayer(shine)
    shineMask.contentsGravity = .resize
    marker.isHidden = true
    gloss.startPoint = CGPoint(x: 0, y: 0)
    gloss.endPoint = CGPoint(x: 1, y: 0.35)
    gloss.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.09).cgColor, UIColor(white: 1, alpha: 0).cgColor]
    shine.startPoint = CGPoint(x: 0, y: 0.15)
    shine.endPoint = CGPoint(x: 1, y: 0.85)
    let hot = UIColor(red: 1, green: 0.97, blue: 0.84, alpha: 1)
    shine.colors = [hot.withAlphaComponent(0).cgColor, hot.withAlphaComponent(0.42).cgColor, hot.cgColor, hot.withAlphaComponent(0.42).cgColor, hot.withAlphaComponent(0).cgColor]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func dress(_ spec: BookSpec, faces: BookArt.TopicFace, current: Bool) {
    self.spec = spec
    self.faces = faces
    coverImage = faces.cover
    coverFace.contents = faces.cover.cgImage
    spineFace.contents = faces.spine.cgImage
    foreFace.contents = faces.fore.cgImage
    headFace.contents = faces.head.cgImage
    shineMask.contents = faces.foil?.cgImage
    isMetal = faces.foil != nil
    shine.isHidden = !isMetal
    shineOffset = CGFloat(spec.seed % 100) / 100 - 0.5
    marker.isHidden = !current
    if current, marker.contents == nil { marker.contents = Self.ribbon.cgImage }
    setNeedsLayout()
  }

  /// A length of crimson silk, cut to a swallow-tail, left in the book being read.
  private static let ribbon: UIImage = {
    let size = CGSize(width: 13, height: 44)
    let f = UIGraphicsImageRendererFormat()
    f.scale = 2
    return UIGraphicsImageRenderer(size: size, format: f).image { r in
      let ctx = r.cgContext
      let p = UIBezierPath()
      p.move(to: CGPoint(x: 0, y: 0))
      p.addLine(to: CGPoint(x: size.width / 2, y: 6))
      p.addLine(to: CGPoint(x: size.width, y: 0))
      p.addLine(to: CGPoint(x: size.width, y: size.height))
      p.addLine(to: CGPoint(x: 0, y: size.height))
      p.close()
      p.addClip()
      BookArt.gradient(
        ctx, [UIColor(hex: 0x5c0d13), UIColor(hex: 0xa8232a), UIColor(hex: 0xc23a3a), UIColor(hex: 0x8d1820), UIColor(hex: 0x5c0d13)], [0, 0.26, 0.45, 0.72, 1], from: .zero, to: CGPoint(x: size.width, y: 0))
      ctx.setFillColor(UIColor(white: 1, alpha: 0.05).cgColor)
      var x: CGFloat = 0.7
      while x < size.width {
        ctx.fill(CGRect(x: x, y: 0, width: 0.5, height: size.height))
        x += 1.4
      }
      BookArt.gradient(ctx, [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.5)], nil, from: CGPoint(x: 0, y: 18), to: CGPoint(x: 0, y: size.height))
    }
  }()

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let spec else { return }
    let w = bounds.width
    let h = bounds.height
    let t = spec.thickness * spec.magnified
    scene.frame = bounds
    turn.frame = bounds
    body.frame = bounds
    let shadow = CGSize(width: w * 1.02, height: t + 70)
    floorShadow.transform = CATransform3DIdentity
    floorShadow.bounds = CGRect(origin: .zero, size: shadow)
    floorShadow.position = CGPoint(x: w / 2, y: h)
    floorShadow.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)
    floorShadow.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: shadow)).cgPath
    coverFace.frame = bounds
    gloss.frame = bounds
    shine.frame = bounds
    shineMask.frame = bounds
    spineFace.anchorPoint = CGPoint(x: 1, y: 0.5)
    spineFace.bounds = CGRect(x: 0, y: 0, width: t, height: h)
    spineFace.position = CGPoint(x: 0, y: h / 2)
    spineFace.transform = CATransform3DMakeRotation(-.pi / 2, 0, 1, 0)
    foreFace.anchorPoint = CGPoint(x: 0, y: 0.5)
    foreFace.bounds = CGRect(x: 0, y: 0, width: t, height: h)
    foreFace.position = CGPoint(x: w - 0.5, y: h / 2)
    foreFace.transform = CATransform3DMakeRotation(.pi / 2, 0, 1, 0)
    headFace.anchorPoint = CGPoint(x: 0.5, y: 1)
    headFace.bounds = CGRect(x: 0, y: 0, width: w, height: t)
    headFace.position = CGPoint(x: w / 2, y: 0)
    headFace.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)
    // The ribbon stands in the block of pages, somewhat behind the cover and up out of the head.
    marker.bounds = CGRect(x: 0, y: 0, width: 13, height: 44)
    marker.position = CGPoint(x: w * 0.72, y: 22 - 16)
    marker.transform = CATransform3DMakeTranslation(0, 0, -t * 0.4)
    // A hair in front of the cover, so it stands over it from every angle.
    slip.transform = CATransform3DIdentity
    slip.frame = CGRect(x: 10, y: h - StatusSlip.height - 12, width: w - 20, height: StatusSlip.height)
    slip.transform = CATransform3DMakeTranslation(0, 0, 1)
    slip.scale = max(2, traitCollection.displayScale)
  }

  /// Sets the camera, and the light on the foil, for where the book is on screen.
  func reposition(centre: CGPoint, vanish: CGPoint, viewport: CGSize, tilt: CGPoint) {
    scene.sublayerTransform = perspective(centre: centre, vanish: vanish, distance: Self.cameraDistance)
    let nx = (centre.x - vanish.x) / max(1, viewport.width)
    let ny = (centre.y - vanish.y) / max(1, viewport.height)
    let band = 0.5 + ny * 2.4 + nx * 0.9 + shineOffset + tilt.x * 2.2 + tilt.y * 2.2
    if isMetal {
      shine.locations = [band - 0.3, band - 0.1, band, band + 0.1, band + 0.3].map { NSNumber(value: Double($0)) }
    }
    let wide = 0.5 + ny * 1.1 + nx * 1.1 + tilt.x * 1.4 + tilt.y * 1.4
    gloss.locations = [wide - 0.42, wide, wide + 0.42].map { NSNumber(value: Double($0)) }
  }

  /// Turned by `angle` about its upright and set `depth` back, as the carousel has it.
  func pose(angle: CGFloat, depth: CGFloat) {
    turn.transform = CATransform3DRotate(CATransform3DMakeTranslation(0, 0, depth), angle, 0, 1, 0)
  }

  /// Tilted under a finger, as under a pointer.
  func press(_ pressed: Bool) {
    if pressed {
      body.spring(transform: Self.tilted, damping: 15, stiffness: 240)
    } else {
      body.spring(transform: resting, damping: 15, stiffness: 240)
    }
  }

  /// With a pointer over it, it stands at a small fixed tilt, wherever on it the pointer is.
  var hovered = false {
    didSet {
      guard hovered != oldValue else { return }
      body.spring(transform: resting, damping: 15, stiffness: 240)
    }
  }

  private var resting: CATransform3D {
    hovered ? Self.tilted : CATransform3DIdentity
  }

  /// Turned a little about its upright, under a pointer or a finger alike.
  private static let tilted = CATransform3DRotate(CATransform3DMakeTranslation(0, 0, 10), -0.1, 0, 1, 0)

  /// Takes the cover away while a copy of it travels; the rest of the book stays where it stood.
  func lift(_ lifted: Bool) {
    coverFace.isHidden = lifted
    marker.opacity = lifted ? 0 : 1
  }
}

/// The two faces of a book's cover, for it to swing open on its hinge as a page zooms out of it.
struct CoverFaces {
  let front: UIImage
  let inside: UIImage
  /// The front as the room's light falls on it in the library, if it's known.
  var lit: UIImage? = nil
}
