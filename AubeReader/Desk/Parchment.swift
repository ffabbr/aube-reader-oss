import UIKit

// ─── The library's paper ─────────────────────────────────────────────────────

/// The library is laid out on an old sheet of paper: cream gone a little
/// yellow by day, a sheet read by lamplight at night. The one place the app
/// leans warm; the desk and its pages keep to `Palette`'s greys.
enum Parchment {
  static let paper = rgb(0xf2ecdf, 0x1b1a18)
  /// Iron-gall ink: the headings, and everything written on the sheet.
  static let ink = rgb(0x2e2418, 0xe8dcc6)
  /// Ink that has faded: placeholders, labels, circles left empty.
  static let faded = rgb(0x8f7d62, 0x8a7d69)
  /// Where the paper has browned: its edges and clouding.
  static let tan = rgb(0x948a7c, 0x050403)
  /// Ink between the two: a status on a sheet.
  static let quiet = rgb(0x6a5a44, 0xa39d93)
  /// The slip across a sheet: a newer, paler stock than the sheet it lies on.
  /// At night it keeps the desk's own grey.
  static let card = rgb(0xf9f6ef, 0x161616)
  /// Laid over a white page with a multiply, it turns the page to the same
  /// stock. White at night, where it leaves the page as it is.
  static let wash = rgb(0xf7f2e8, 0xffffff)
  /// The color of a shadow on paper: brown by day, black by night.
  static let umbra = rgb(0x3a2812, 0x000000)
  /// A switch turned on.
  static let accent = rgb(0x8a6a3e, 0xb8976a)

  private static func rgb(_ light: UInt32, _ dark: UInt32) -> UIColor {
    UIColor { traits in
      let v = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(
        red: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
  }

  /// A heading written by hand, in a copperplate roundhand.
  static func script(_ size: CGFloat) -> UIFont {
    UIFont(name: "SnellRoundhand-Bold", size: size) ?? Face.serif(size, .semibold)
  }

  static func italic(_ size: CGFloat) -> UIFont {
    UIFont(name: "Baskerville-Italic", size: size) ?? .italicSystemFont(ofSize: size)
  }

  /// Dresses a navigation bar for the paper: no fill of its own, everything
  /// in its ink, or `ink` if what's behind it isn't paper, and its titles in
  /// roundhand unless `script` is false.
  static func dress(_ bar: UINavigationBar, script: Bool = true, ink given: UIColor? = nil) {
    let ink = given ?? self.ink
    bar.tintColor = ink
    let look = UINavigationBarAppearance()
    look.configureWithTransparentBackground()
    look.largeTitleTextAttributes = [.font: script ? Parchment.script(58) : .systemFont(ofSize: 34, weight: .bold), .foregroundColor: ink]
    look.titleTextAttributes = [.font: script ? Parchment.script(28) : .systemFont(ofSize: 17, weight: .semibold), .foregroundColor: ink]
    let button = UIBarButtonItemAppearance()
    for state in [button.normal, button.highlighted] { state.titleTextAttributes = [.foregroundColor: ink] }
    look.buttonAppearance = button
    look.doneButtonAppearance = button
    bar.standardAppearance = look
    bar.scrollEdgeAppearance = look
    bar.compactAppearance = look
  }
}

/// The same numbers every time, so the paper's grain and clouding
/// stay where they were from one launch to the next.
struct Seeded: RandomNumberGenerator {
  private var state: UInt64
  init(_ seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func callAsFunction(_ range: ClosedRange<CGFloat>) -> CGFloat { .random(in: range, using: &self) }
}

/// The sheet behind the library: a fine grain with fibres in it, tiled; and
/// over it, drawn once for the whole screen, the clouding of old paper and
/// edges gone brown.
/// All of it held back, so it reads as paper rather than as a picture of it;
/// further still at a `strength` below 1. Pale paper swallows the clouding
/// that dark paper shows, so by day it is laid on more heavily.
final class PaperBackdrop: UIView {
  private let grain = UIView()
  private let age = UIImageView()
  private let strength: CGFloat
  private var drawn: (CGSize, UIUserInterfaceStyle)?

  init(strength: CGFloat = 1) {
    self.strength = strength
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = Parchment.paper
    age.contentMode = .scaleToFill
    addSubview(age)
    addSubview(grain)
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: PaperBackdrop, _) in self.setNeedsLayout() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    grain.frame = bounds
    age.frame = bounds
    let style = traitCollection.userInterfaceStyle
    guard bounds.width > 0, drawn?.0 != bounds.size || drawn?.1 != style else { return }
    if drawn?.1 != style {
      grain.backgroundColor = PaperBackdrop.grain(traitCollection)
      let night = style == .dark
      age.alpha = (night ? 0.55 : 0.8) * strength
      grain.alpha = 0.3 + 0.3 * strength
    }
    drawn = (bounds.size, style)
    age.image = PaperBackdrop.aged(bounds.size, traitCollection)
  }

  // ─── Grain ─────────────────────────────────────────────────────────────

  private static let tileSide: CGFloat = 256

  private static var grains: [UIUserInterfaceStyle: UIColor] = [:]

  /// The grain as a pattern, made once for each appearance.
  static func grain(_ traits: UITraitCollection) -> UIColor {
    let style = traits.userInterfaceStyle
    if let g = grains[style] { return g }
    let g = UIColor(patternImage: tile(traits))
    grains[style] = g
    return g
  }

  /// A square of grain and fibres that tiles without a seam.
  private static func tile(_ traits: UITraitCollection) -> UIImage {
    let dark = traits.userInterfaceStyle == .dark
    let scale = max(traits.displayScale, 1)
    let px = Int(tileSide * scale)
    var rng = Seeded(0xA6E_D9A9E5)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return UIImage() }

    // Every pixel a speck of brown (or, at night, of pale) at a strength skewed toward none.
    let specks = ctx.data!.bindMemory(to: UInt8.self, capacity: px * px * 4)
    let (sr, sg, sb): (CGFloat, CGFloat, CGFloat) = dark ? (0.93, 0.9, 0.84) : (0.36, 0.27, 0.15)
    let (lr, lg, lb): (CGFloat, CGFloat, CGFloat) = dark ? (0, 0, 0) : (1, 1, 0.97)
    for i in 0..<(px * px) {
      let n = rng(0...1)
      var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat)
      if n < 0.5 {
        (r, g, b) = (sr, sg, sb)
        a = pow(rng(0...1), 3) * (dark ? 0.07 : 0.085)
      } else {
        (r, g, b) = (lr, lg, lb)
        a = pow(rng(0...1), 3) * (dark ? 0.12 : 0.16)
      }
      // Now and then a speck of grit.
      if rng(0...1) < 0.0006 {
        (r, g, b) = (sr, sg, sb)
        a = rng(0.12...0.3)
      }
      specks[i * 4] = UInt8(r * a * 255)
      specks[i * 4 + 1] = UInt8(g * a * 255)
      specks[i * 4 + 2] = UInt8(b * a * 255)
      specks[i * 4 + 3] = UInt8(a * 255)
    }

    // Fibres: short, thin, gently bent, each drawn again a tile over wherever it would cross an edge.
    ctx.scaleBy(x: scale, y: scale)
    ctx.setLineCap(.round)
    let fibre = dark ? UIColor(red: 0.9, green: 0.87, blue: 0.81, alpha: 1) : UIColor(red: 0.42, green: 0.31, blue: 0.17, alpha: 1)
    let s = tileSide
    for _ in 0..<110 {
      let p = CGPoint(x: rng(0...s), y: rng(0...s))
      let angle = rng(0...(2 * .pi))
      let length = pow(rng(0...1), 2.4) * 18 + 3
      let bend = rng(-0.6...0.6)
      let q = CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length)
      let c = CGPoint(
        x: (p.x + q.x) / 2 + cos(angle + .pi / 2) * length * bend * 0.3,
        y: (p.y + q.y) / 2 + sin(angle + .pi / 2) * length * bend * 0.3)
      ctx.setStrokeColor(fibre.withAlphaComponent(rng(0.025...0.08) * (dark ? 0.8 : 1)).cgColor)
      ctx.setLineWidth(rng(0.3...0.7))
      for dx in [-s, 0, s] {
        for dy in [-s, 0, s] {
          ctx.move(to: CGPoint(x: p.x + dx, y: p.y + dy))
          ctx.addQuadCurve(to: CGPoint(x: q.x + dx, y: q.y + dy), control: CGPoint(x: c.x + dx, y: c.y + dy))
          ctx.strokePath()
        }
      }
    }
    guard let image = ctx.makeImage() else { return UIImage() }
    return UIImage(cgImage: image, scale: scale, orientation: .up)
  }

  // ─── Age ───────────────────────────────────────────────────────────────

  /// Everything that doesn't repeat: soft, so it's drawn at one pixel a point.
  private static func aged(_ size: CGSize, _ traits: UITraitCollection) -> UIImage {
    let dark = traits.userInterfaceStyle == .dark
    let tan = Parchment.tan.resolvedColor(with: traits)
    let light = dark ? UIColor(red: 0.93, green: 0.9, blue: 0.83, alpha: 1) : UIColor(white: 1, alpha: 1)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    func blot(_ ctx: CGContext, _ at: CGPoint, _ r: CGFloat, _ color: UIColor, _ alpha: CGFloat) {
      let g = CGGradient(
        colorsSpace: space,
        colors: [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(alpha * 0.45).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 0.5, 1])!
      ctx.drawRadialGradient(g, startCenter: at, startRadius: 0, endCenter: at, endRadius: r, options: [])
    }

    return UIGraphicsImageRenderer(size: size, format: format).image { r in
      let ctx = r.cgContext
      let w = size.width
      let h = size.height
      // Placed as shares of the screen, so they keep their places when it turns.
      var rng = Seeded(0x01D_9A9E5)

      // Clouding: broad, faint, uneven. Pale paper hides a change of shade
      // that dark paper shows, so by day it takes several times the strength.
      for _ in 0..<26 {
        let at = CGPoint(x: rng(-0.1...1.1) * w, y: rng(-0.1...1.1) * h)
        let radius = rng(0.12...0.38) * max(w, h)
        if rng(0...1) < 0.6 {
          blot(ctx, at, radius, tan, rng(0.025...0.055) * (dark ? 1.6 : 4.5))
        } else {
          blot(ctx, at, radius, light, rng(0.04...0.09) * (dark ? 0.35 : 3))
        }
      }

      // The edges, browned where light and hands got at them; the corners most.
      let centre = CGPoint(x: w / 2, y: h / 2)
      let reach = hypot(w, h) / 2
      let edges = CGGradient(
        colorsSpace: space,
        colors: [tan.withAlphaComponent(0).cgColor, tan.withAlphaComponent(0).cgColor, tan.withAlphaComponent(dark ? 0.5 : 0.32).cgColor, tan.withAlphaComponent(dark ? 0.75 : 0.6).cgColor] as CFArray,
        locations: [0, dark ? 0.55 : 0.35, 0.88, 1])!
      ctx.saveGState()
      ctx.translateBy(x: centre.x, y: centre.y)
      ctx.scaleBy(x: w / (2 * reach) * 1.12, y: h / (2 * reach) * 1.12)
      ctx.drawRadialGradient(
        edges, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: reach, options: [.drawsAfterEndLocation])
      ctx.restoreGState()
      // A thin darker band right at the edge, where paper browns fastest.
      for (side, rect) in [
        (CGPoint(x: 0, y: 0), CGRect(x: 0, y: 0, width: w, height: 14)),
        (CGPoint(x: 0, y: h), CGRect(x: 0, y: h - 14, width: w, height: 14)),
      ] {
        let band = CGGradient(
          colorsSpace: space, colors: [tan.withAlphaComponent(dark ? 0.3 : 0.14).cgColor, tan.withAlphaComponent(0).cgColor] as CFArray,
          locations: [0, 1])!
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(
          band, start: side, end: CGPoint(x: side.x, y: side.y == 0 ? 14 : h - 14), options: [])
        ctx.restoreGState()
      }
    }
  }
}
