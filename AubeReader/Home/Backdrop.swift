import UIKit

// ─── Timber ──────────────────────────────────────────────────────────────────

/// The timber the library's panel is made of, grown and shaded once for day and for night.
enum Timber: String {
  case stile, fascia, cornice

  /// Points to pixels.
  var scale: CGFloat {
    switch self {
    case .stile, .cornice: 2
    case .fascia: 1
    }
  }

  var points: CGSize {
    switch self {
    case .stile: CGSize(width: 32, height: 1400)
    case .fascia: CGSize(width: 1800, height: 320)
    case .cornice: CGSize(width: 1800, height: 32)
    }
  }

  @MainActor func fetch(night: Bool, then: @escaping (UIImage) -> Void) {
    let piece = self
    Larder.shared.fetch("timber-\(rawValue)-\(night ? "night" : "day")", scale: scale, make: { piece.make(night: night) }, then: then)
  }

  private nonisolated func make(night: Bool) -> CGImage? {
    let stain = night ? Stain.walnut : Stain.oak
    let k = Float(scale)
    let w = Int(points.width * scale)
    let h = Int(points.height * scale)
    func rows(_ px: UnsafeMutablePointer<UInt8>, _ stride: Int, _ f: (Float) -> Float) {
      for y in 0..<h {
        let m = f(Float(y) / Float(h - 1))
        var at = px + y * stride
        for _ in 0..<w {
          at[0] = UInt8(min(255, Float(at[0]) * m))
          at[1] = UInt8(min(255, Float(at[1]) * m))
          at[2] = UInt8(min(255, Float(at[2]) * m))
          at += 4
        }
      }
    }
    func lerp(_ stops: [(Float, Float)], _ t: Float) -> Float {
      var last = stops[0]
      for s in stops {
        if t <= s.0 {
          let span = max(0.0001, s.0 - last.0)
          let u = (t - last.0) / span
          return last.1 + (s.1 - last.1) * u * u * (3 - 2 * u)
        }
        last = s
      }
      return last.1
    }
    return Wood.bitmap(w, h) { px, stride in
      switch self {
      case .stile:
        Wood.paint(px, stride: stride, x: 0, y: 0, width: w, height: h, scale: k, upright: true, .init(seed: 5, stain: stain, heart: nil, figure: 0.55))
        for y in 0..<h {
          var at = px + y * stride
          for x in 0..<w {
            let m = lerp([(0, 0.6), (0.06, 1.1), (0.12, 1.02), (0.88, 0.9), (0.96, 0.82), (1, 0.5)], Float(x) / Float(w - 1))
            at[0] = UInt8(min(255, Float(at[0]) * m))
            at[1] = UInt8(min(255, Float(at[1]) * m))
            at[2] = UInt8(min(255, Float(at[2]) * m))
            at += 4
          }
        }
      case .fascia:
        Wood.paint(px, stride: stride, x: 0, y: 0, width: w, height: h, scale: k, upright: false, .init(seed: 8, stain: stain.dimmed(0.92), heart: (980, 480), figure: 0.8))
      case .cornice:
        Wood.paint(px, stride: stride, x: 0, y: 0, width: w, height: h, scale: k, upright: false, .init(seed: 3, stain: stain.dimmed(0.95), heart: (300, -90)))
        // A bead, a fillet and a cove, as a moulding plane would leave them.
        rows(px, stride) {
          lerp([(0, 0.62), (0.05, 0.98), (0.3, 1.0), (0.36, 0.55), (0.42, 1.25), (0.55, 1.42), (0.7, 0.98), (0.76, 0.5), (0.82, 1.3), (0.92, 1.05), (1, 0.4)], $0)
        }
      }
    }
  }
}

// ─── The panel ───────────────────────────────────────────────────────────────

/// What the library stands in front of: a panel of boards one above the other,
/// every other one flipped so that they meet, between two upright sides and over
/// a moulding along the foot of the screen.
final class TimberPanel: UIView {
  /// The moulding's height, which the books stand clear of.
  static let cornice: CGFloat = 32

  private var boards: [StillLayer] = []
  private let cornice = StillLayer()
  private let stiles = (0..<2).map { _ in StillLayer() }
  private var images: [Timber: UIImage] = [:]

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.addSublayer(cornice)
    for s in stiles { layer.addSublayer(s) }
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: TimberPanel, _) in self.loadTimber() }
    loadTimber()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private var night: Bool { traitCollection.userInterfaceStyle == .dark }

  /// The upright sides' width.
  private var stileWidth: CGFloat { bounds.width < 700 ? 16 : 26 }

  private func loadTimber() {
    let n = night
    backgroundColor = (n ? Stain.walnut : Stain.oak).dimmed(0.45).average
    for piece in [Timber.fascia, .cornice, .stile] {
      piece.fetch(night: n) { [weak self] image in
        guard let self, self.night == n else { return }
        self.images[piece] = image
        self.applyTimber()
      }
    }
  }

  private func applyTimber() {
    for b in boards { b.contents = images[.fascia]?.cgImage }
    cornice.contents = images[.cornice]?.cgImage
    for s in stiles { s.contents = images[.stile]?.cgImage }
  }

  /// The middle of a piece of timber `whole` wide, as much as `width` needs.
  private func cropped(width: CGFloat, from whole: CGFloat) -> CGRect {
    let share = min(1, width / whole)
    return CGRect(x: (1 - share) / 2, y: 0, width: share, height: 1)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width
    let h = bounds.height
    guard w > 0, h > 0 else { return }
    let board = Timber.fascia.points.height
    let foot = h - Self.cornice
    let needed = Int((foot / board).rounded(.up))
    while boards.count < needed {
      let b = StillLayer()
      b.contents = images[.fascia]?.cgImage
      layer.insertSublayer(b, below: cornice)
      boards.append(b)
    }
    while boards.count > needed { boards.removeLast().removeFromSuperlayer() }
    let across = cropped(width: w, from: Timber.fascia.points.width)
    for (i, b) in boards.enumerated() {
      b.transform = CATransform3DIdentity
      b.frame = CGRect(x: 0, y: foot - board * CGFloat(i + 1), width: w, height: board)
      b.contentsRect = across
      if i % 2 == 1 { b.transform = CATransform3DMakeScale(1, -1, 1) }
    }
    cornice.frame = CGRect(x: 0, y: foot, width: w, height: Self.cornice)
    cornice.contentsRect = cropped(width: w, from: Timber.cornice.points.width)
    let side = stileWidth
    for (i, s) in stiles.enumerated() {
      s.transform = CATransform3DIdentity
      s.frame = CGRect(x: i == 0 ? 0 : w - side, y: 0, width: side, height: h)
      s.contentsRect = CGRect(x: 0, y: 0, width: 1, height: min(1, h / Timber.stile.points.height))
      // The right side is the left one turned round, so the light falls on both alike.
      if i == 1 { s.transform = CATransform3DMakeScale(-1, 1, 1) }
    }
  }
}

// ─── Lamplight ───────────────────────────────────────────────────────────────

/// The light in the room, multiplied over the whole library: daylight falling
/// off a little at the corners, or at night a lamp above the middle of the case,
/// warm where it lands and leaving the rest in the dark.
final class Lamplight: UIImageView {
  private var drawn: (CGSize, UIUserInterfaceStyle)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.compositingFilter = "multiplyBlendMode"
    contentMode = .scaleToFill
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Lamplight, _) in self.setNeedsLayout() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    let style = traitCollection.userInterfaceStyle
    guard bounds.width > 0, drawn?.0 != bounds.size || drawn?.1 != style else { return }
    drawn = (bounds.size, style)
    let night = style == .dark
    let size = bounds.size
    let f = UIGraphicsImageRendererFormat()
    f.scale = 0.5
    image = UIGraphicsImageRenderer(size: size, format: f).image { r in
      let ctx = r.cgContext
      let space = CGColorSpace(name: CGColorSpace.sRGB)!
      UIColor.white.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
      let colors: [UIColor] =
        night
        ? [UIColor(hex: 0xfff3dc), UIColor(hex: 0xe6c79a), UIColor(hex: 0x8d6d4e), UIColor(hex: 0x38291f)]
        : [UIColor(hex: 0xffffff), UIColor(hex: 0xfdf8ee), UIColor(hex: 0xe5d8c4), UIColor(hex: 0xb7a48d)]
      let g = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.34, 0.74, 1])!
      let reach = hypot(size.width, size.height) * (night ? 0.62 : 0.6)
      ctx.translateBy(x: size.width / 2, y: size.height * 0.42)
      ctx.scaleBy(x: size.width / size.height * 1.16, y: 1)
      ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: reach, options: [.drawsAfterEndLocation])
    }
  }

  /// `picture`, lying on `rect` in the light's own coordinates, as the light
  /// falls on it there: for a copy of something that leaves the room.
  func lit(_ picture: UIImage, on rect: CGRect) -> UIImage? {
    guard let light = image, rect.width > 0, rect.height > 0, bounds.width > 0 else { return nil }
    let f = UIGraphicsImageRendererFormat()
    f.scale = picture.scale
    let b = CGRect(origin: .zero, size: picture.size)
    let sx = b.width / rect.width
    let sy = b.height / rect.height
    return UIGraphicsImageRenderer(size: b.size, format: f).image { _ in
      picture.draw(in: b)
      light.draw(
        in: CGRect(x: -rect.minX * sx, y: -rect.minY * sy, width: bounds.width * sx, height: bounds.height * sy),
        blendMode: .multiply, alpha: 1)
      // The light only where the picture is, not in its clear corners.
      picture.draw(in: b, blendMode: .destinationIn, alpha: 1)
    }
  }
}
