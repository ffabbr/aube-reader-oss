import UIKit

/// A page on its way between the desk and its sheet in the library. It holds
/// the page as the screen shows it (`covers`, all of it); over it, where `crop`
/// of the page lies, the sheet's own picture; and over that the sheet's paper.
/// It fills the screen looking just as the screen does, or lies on the sheet
/// looking just as the sheet does, clipped to it.
final class Zoom: UIView {
  private let covers: CGRect
  private let crop: CGRect
  /// A book's cover, if the sheet is a book: over the page, hinged at its left.
  private var leaf: CoverLeaf?
  /// The shadow in the book's gutter, along the page's left edge; gone once it fills the screen.
  private let gutter = GutterView()
  private var radius: CGFloat
  /// The page and everything drawn on it, moved and scaled as one.
  private let page = UIView()
  /// The sheet's picture, there while it lies on the sheet.
  private let thumb = UIImageView()
  /// A softened copy of the page, laid over it to stand in for motion blur.
  private let streak = UIImageView()
  /// The sheet's paper over the page: its stock, its grain and its edge, there
  /// while it lies on the sheet, gone as it fills the screen.
  private let wash = UIView()
  private let grain = UIView()
  private let edge = UIView()

  private static let sheetRadius: CGFloat = 6

  /// The hairline round a sheet.
  private static func edge(_ t: UITraitCollection) -> UIColor {
    t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : Parchment.umbra.resolvedColor(with: t).withAlphaComponent(0.1)
  }

  /// `sheet` is the size of what it lies on, which needn't be the page's shape.
  init(covers: CGRect, crop: CGRect, sheet size: CGSize) {
    self.covers = covers
    self.crop = crop
    radius = Self.sheetRadius
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = Palette.page
    layer.cornerCurve = .continuous
    page.bounds = CGRect(origin: .zero, size: covers.size)
    var sheet = crop.offsetBy(dx: -covers.minX, dy: -covers.minY)
    sheet.size.height = sheet.width * size.height / max(1, size.width)
    thumb.frame = sheet
    thumb.contentMode = .scaleToFill
    streak.frame = page.bounds
    streak.alpha = 0
    for v in [thumb, streak] { page.addSubview(v) }
    addSubview(page)
    wash.layer.compositingFilter = "multiplyBlendMode"
    edge.layer.cornerCurve = .continuous
    for v in [wash, grain, edge] { addSubview(v) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    let t = traitCollection
    wash.backgroundColor = Parchment.wash
    grain.backgroundColor = t.userInterfaceStyle == .dark ? nil : PaperBackdrop.grain(t)
    edge.layer.borderColor = Self.edge(t).cgColor
    edge.layer.borderWidth = 1 / max(t.displayScale, 1)
  }

  /// Lays the page as the screen shows it, buttons and all, under the sheet's picture.
  func show(_ screen: UIView) {
    screen.frame = page.bounds
    page.insertSubview(screen, at: 0)
  }

  /// Softens `picture`, all of the page, to stand in for motion blur. Away from
  /// the main thread: the blur isn't wanted until the page is well on its way.
  func smear(_ picture: UIImage) {
    DispatchQueue.global(qos: .userInteractive).async {
      let soft = Self.soften(picture)
      DispatchQueue.main.async { self.streak.image = soft }
    }
  }

  /// Scales the page by `s`, its top left at `origin`. A transform rather
  /// than a frame, so what's drawn on it is only ever scaled, never drawn again.
  private func place(_ s: CGFloat, _ origin: CGPoint) {
    page.transform = CGAffineTransform(scaleX: s, y: s)
    page.center = CGPoint(x: origin.x + covers.width * s / 2, y: origin.y + covers.height * s / 2)
  }

  /// How much of the sheet shows: 1 lying on it, 0 filling the screen.
  private func sheeted(_ a: CGFloat) {
    for v in [wash, grain, edge] { v.frame = bounds }
    edge.layer.cornerRadius = layer.cornerRadius
    for v in [thumb, wash, edge] { v.alpha = a }
    grain.alpha = 0.6 * a
    gutter.alpha = a
  }

  func full(_ screen: CGRect) {
    frame = screen
    layer.cornerRadius = 0
    sheeted(0)
    place(1, covers.origin)
    leaf?.open(over: screen)
  }

  /// Hangs a cover, if there's one, over the page: a sibling above it, since a
  /// clipped view can't let it swing out, and removed along with it.
  func hinge(_ cover: CoverFaces?, above view: UIView) {
    guard let cover, let parent = superview else { return }
    let leaf = CoverLeaf(cover, size: CGSize(width: max(1, thumb.bounds.width), height: max(1, thumb.bounds.height)))
    parent.insertSubview(leaf, aboveSubview: view)
    self.leaf = leaf
    // Under a closed cover there's no paper to show but the page itself.
    thumb.isHidden = true
    radius = 2.6
    gutter.frame = page.bounds
    page.addSubview(gutter)
  }

  override func removeFromSuperview() {
    leaf?.removeFromSuperview()
    super.removeFromSuperview()
  }

  /// Lies on `sheet`, which shows `crop` of the page.
  func lie(on sheet: CGRect) {
    let s = sheet.width / crop.width
    frame = sheet
    layer.cornerRadius = radius
    sheeted(1)
    place(s, CGPoint(x: (covers.minX - crop.minX) * s, y: (covers.minY - crop.minY) * s))
    leaf?.shut(on: sheet)
  }

  /// Blurs the page while it travels fastest, sharp again as it comes to rest.
  /// Called inside the transition's animations, whose curve it shares, so the
  /// blur peaks halfway, where the curve is steepest.
  func blur() {
    UIView.animateKeyframes(withDuration: 0, delay: 0, options: .calculationModeCubic) {
      UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) { self.streak.alpha = 0.85 }
      UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) { self.streak.alpha = 0 }
    }
  }

  private static let ci = CIContext()

  /// Builds Core Image's blur once, ahead of time, so the first zoom doesn't wait on it.
  static func warmUp() {
    DispatchQueue.global(qos: .utility).async {
      _ = soften(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in })
    }
  }

  /// A small, blurred copy of `image`, a pixel to every four points; it's only ever seen in motion.
  private static func soften(_ image: UIImage) -> UIImage? {
    guard let cg = image.cgImage else { return nil }
    let k = 0.25 / image.scale
    let small = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: k, y: k))
    let extent = small.extent
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = small.clampedToExtent()
    blur.radius = 2.5
    guard let out = blur.outputImage?.cropped(to: extent), let made = ci.createCGImage(out, from: extent) else { return nil }
    return UIImage(cgImage: made)
  }
}

/// The shade where a page turns in toward a book's spine.
final class GutterView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    guard let g = layer as? CAGradientLayer else { return }
    g.colors = [UIColor(white: 0, alpha: 0.34).cgColor, UIColor(white: 0, alpha: 0.08).cgColor, UIColor(white: 0, alpha: 0).cgColor]
    g.locations = [0, 0.07, 0.2]
    g.startPoint = .zero
    g.endPoint = CGPoint(x: 1, y: 0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}

/// A book's cover on its way between shut on the book and wide open beyond the
/// edge of the screen: both faces, on a hinge along the left, in perspective.
/// It's scaled rather than laid out afresh, so that the whole thing moves with
/// the page beneath it, one transform to each.
final class CoverLeaf: UIView {
  /// A transform layer, so that each face is in space rather than flattened
  /// onto its parent, and turning its back hides it.
  private final class Swing: UIView {
    override class var layerClass: AnyClass { CATransformLayer.self }
  }
  private let swing = Swing()
  private let front = UIImageView()
  private let inside = UIImageView()
  /// The front as the library's lamp lights it, there while it's shut on the book.
  private let lit = UIImageView()
  /// Light leaving each face as it turns away.
  private let frontShade = UIView()
  private let insideShade = UIView()
  private let size: CGSize

  init(_ faces: CoverFaces, size: CGSize) {
    self.size = size
    super.init(frame: CGRect(origin: .zero, size: size))
    isUserInteractionEnabled = false
    layer.sublayerTransform = {
      var p = CATransform3DIdentity
      p.m34 = -1 / (size.width * 3.1)
      return p
    }()
    swing.frame = bounds
    swing.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
    swing.layer.position = CGPoint(x: 0, y: size.height / 2)
    addSubview(swing)
    for (v, image) in [(inside, faces.inside), (front, faces.front)] {
      v.image = image
      v.frame = swing.bounds
      v.contentMode = .scaleToFill
      v.layer.isDoubleSided = false
      swing.addSubview(v)
    }
    inside.transform3D = CATransform3DMakeRotation(.pi, 0, 1, 0)
    lit.image = faces.lit
    lit.isHidden = faces.lit == nil
    lit.frame = front.bounds
    lit.contentMode = .scaleToFill
    front.addSubview(lit)
    frontShade.backgroundColor = .black
    insideShade.backgroundColor = .black
    frontShade.frame = front.bounds
    insideShade.frame = inside.bounds
    front.addSubview(frontShade)
    inside.addSubview(insideShade)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func shut(on sheet: CGRect) {
    let sx = sheet.width / size.width
    let sy = sheet.height / size.height
    transform = CGAffineTransform(scaleX: sx, y: sy)
    center = CGPoint(x: sheet.midX, y: sheet.midY)
    swing.transform3D = CATransform3DIdentity
    // In the library's light, as the book it lies on is; out of it as it leaves, with the library.
    lit.alpha = 1
    frontShade.alpha = 0
    // Only seen once it's past halfway, coming into the light from the dark.
    insideShade.alpha = 0.7
  }

  func open(over screen: CGRect) {
    // As tall as the screen, and off its left edge by the time it's there.
    let sx = screen.width / size.width
    let sy = screen.height / size.height
    transform = CGAffineTransform(scaleX: sx, y: sy)
    center = CGPoint(x: screen.midX, y: screen.midY)
    swing.transform3D = CATransform3DMakeRotation(-.pi * 0.97, 0, 1, 0)
    lit.alpha = 0
    frontShade.alpha = 0.72
    insideShade.alpha = 0
  }
}
