import UIKit

/// One shape of Liquid Glass that opens out of something small on the page (a
/// footnote's mark, the contents ring) into a sheet resting beside it. It starts
/// out at `start`, stretches across toward `rest` and then down or up a beat later,
/// stepped here frame by frame (see `Ease`) so that it can turn back from
/// anywhere. Closing runs the same way back, and the glass gives way to the page
/// just as it gets there.
///
/// Subclasses put what's on the glass in `arrange(on:)` and bring it in with
/// `reveal(across:reached:)`. Only the sheet takes touches, and not `keepOut`,
/// which is the page's: tapped, it puts the tip away (see `DeskViewController`).
class GlassTip: UIView {
  /// How long each part of opening and closing takes.
  struct Timing {
    /// Opening: across over `across` seconds, then down or up over `reach`,
    /// starting `lag` later, along `reachEase`.
    var across: Double
    var reach: Double
    var lag: Double
    var reachEase: Ease
    /// Closing: back over `back` seconds, then in over `inward`, starting
    /// `closeLag` later; the glass gives way to the page at `fadeAt`.
    var back: Double
    var inward: Double
    var closeLag: Double
    var fadeAt: Double
  }

  /// Soft away from where it starts, with a long landing.
  private static let across = Ease(0.3, 0, 0.14, 1)
  private static let corner: CGFloat = 22

  /// Where the glass starts, and where it comes to rest.
  let start: CGRect
  let rest: CGRect
  let body = UIVisualEffectView()

  private let keepOut: CGRect
  private let timing: Timing
  /// Under the glass: a little of the page, so the words under it don't compete with its own.
  private let backing = UIView()
  /// Around the glass, not under it: a shadow would darken what's meant to be seen through.
  private let shade = CALayer()
  private let shadeCut = CAShapeLayer()
  private let calm = UIAccessibility.isReduceMotionEnabled
  /// How far the glass has reached, from `start` (0) to where it rests (1), across and down or up.
  private let wide = Tween(0)
  private let tall = Tween(0)
  private var link: CADisplayLink?
  private var last = 0.0
  private var leaving = false

  /// A tip over `host` from `start` to `rest`. Its shadow is `shadowRadius`
  /// across at `shadowOpacity` (light, dark), and as much of the page lies
  /// under the glass as `backing` says (light, dark).
  init(
    start: CGRect, rest: CGRect, keepOut: CGRect, host: UIView, timing: Timing,
    shadowRadius: CGFloat, shadowOpacity: (light: Float, dark: Float), backing backingAlpha: (light: CGFloat, dark: CGFloat)
  ) {
    self.start = start
    self.rest = rest
    self.keepOut = keepOut
    self.timing = timing
    super.init(frame: host.bounds)
    autoresizingMask = [.flexibleWidth, .flexibleHeight]

    shade.frame = bounds
    shade.shadowColor = UIColor.black.cgColor
    shade.shadowOffset = CGSize(width: 0, height: 8)
    shade.shadowRadius = shadowRadius
    shade.shadowOpacity = host.traitCollection.userInterfaceStyle == .dark ? shadowOpacity.dark : shadowOpacity.light
    shade.opacity = 0
    shadeCut.frame = bounds
    shadeCut.fillRule = .evenOdd
    shade.mask = shadeCut
    layer.addSublayer(shade)

    backing.frame = start
    backing.backgroundColor = UIColor { traits in
      Palette.page.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? backingAlpha.dark : backingAlpha.light)
    }
    backing.alpha = 0
    backing.layer.cornerCurve = .continuous
    backing.layer.cornerRadius = start.height / 2
    addSubview(backing)

    body.frame = start
    body.roundCorners(start.height / 2)
    addSubview(body)
    body.contentView.clipsToBounds = true
    body.contentView.layer.cornerCurve = .continuous
    body.contentView.layer.cornerRadius = start.height / 2
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// Glass where there's glass; before it, the thinnest material.
  static func material() -> UIVisualEffect {
    if #available(iOS 26.0, *) { return UIGlassEffect(style: .regular) }
    return UIBlurEffect(style: .systemThinMaterial)
  }

  // ─── For subclasses ──────────────────────────────────────────────────────

  /// Puts what's on the glass where it belongs with the glass over `frame`,
  /// keeping it still on the screen whatever the glass does around it.
  func arrange(on frame: CGRect) {}

  /// Brings in what's on the glass as it reaches across (`across`) and as far
  /// as it has reached both ways (`reached`), each from 0 to 1.
  func reveal(across: Double, reached: Double) {}

  // ─── Shape ───────────────────────────────────────────────────────────────

  private func shape(_ frame: CGRect, radius: CGFloat) {
    body.frame = frame
    backing.frame = frame
    body.roundCorners(radius)
    body.contentView.layer.cornerRadius = radius
    backing.layer.cornerRadius = radius
    arrange(on: frame)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let outline = UIBezierPath(roundedRect: frame, cornerRadius: radius)
    shade.shadowPath = outline.cgPath
    let cut = UIBezierPath(rect: bounds)
    cut.append(outline)
    shadeCut.path = cut.cgPath
    shade.opacity = Float(clamp(tall.value, 0, 1))
    CATransaction.commit()
  }

  /// The glass as far along as it's got.
  private func step() {
    func along(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    let (w, h) = (wide.value, tall.value)
    let frame = CGRect(
      x: along(start.minX, rest.minX, w), y: along(start.minY, rest.minY, h),
      width: along(start.width, rest.width, w), height: along(start.height, rest.height, h))
    shape(frame, radius: min(frame.height / 2, frame.width / 2, Self.corner))
    // What's under the glass and what's on it come with its reach, so they go back the way they came.
    let reached = min(w, h)
    backing.alpha = CGFloat(smoothstep(0, 0.6, reached))
    reveal(across: w, reached: reached)
  }

  private func run() {
    guard link == nil else { return }
    last = 0
    link = .driving(self) { $0.frame($1) }
  }

  private func frame(_ link: CADisplayLink) {
    let now = CACurrentMediaTime()
    let dt = last > 0 ? now - last : 1.0 / 120
    last = now
    wide.step(now, dt)
    tall.step(now, dt)
    step()
    guard wide.resting, tall.resting else { return }
    link.invalidate()
    self.link = nil
    if leaving { removeFromSuperview() }
  }

  // ─── Coming and going ────────────────────────────────────────────────────

  func open() {
    guard !calm else {
      wide.to(1, over: 0.001, Ease.rise, now: 0)
      tall.to(1, over: 0.001, Ease.rise, now: 0)
      wide.step(1, 0)
      tall.step(1, 0)
      step()
      alpha = 0
      body.effect = Self.material()
      UIView.animate(withDuration: 0.2) { self.alpha = 1 }
      return
    }
    let now = CACurrentMediaTime()
    wide.to(1, over: timing.across, Self.across, now: now)
    tall.to(1, over: timing.reach, after: timing.lag, timing.reachEase, now: now)
    step()
    run()
    // The first frame is what was on the page already: the glass comes up over it where it stands.
    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.body.effect = Self.material() }
  }

  /// Draws back to where it started, and goes. `quickly` for when the page itself is on its way somewhere.
  func close(quickly: Bool = false) {
    guard !leaving else { return }
    leaving = true
    isUserInteractionEnabled = false
    if quickly || calm {
      link?.invalidate()
      link = nil
      UIView.animate(withDuration: quickly ? 0.12 : 0.18, delay: 0, options: [.curveEaseOut]) {
        self.alpha = 0
      } completion: { _ in self.removeFromSuperview() }
      return
    }
    let now = CACurrentMediaTime()
    // Back first, then in: the way it came, from wherever it had got to.
    tall.to(0, over: timing.back, Ease.fold, now: now)
    wide.to(0, over: timing.inward, after: timing.closeLag, Ease.fold, now: now)
    run()
    // The glass gives way to the page just as it gets there.
    UIView.animate(withDuration: 0.14, delay: timing.fadeAt, options: [.curveEaseOut]) { self.body.effect = nil }
  }

  // ─── Touches ─────────────────────────────────────────────────────────────

  /// Whether a point is the tip's own, and not for the page.
  private func owns(_ point: CGPoint) -> Bool { rest.contains(point) && !keepOut.contains(point) }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, owns(point) else { return nil }
    return super.hitTest(point, with: event) ?? self
  }

  /// Whether a touch is the tip's own, and not for the page under it.
  func holds(_ touch: UITouch) -> Bool { owns(touch.location(in: self)) }
}

extension UIVisualEffectView {
  /// Rounds the view to `radius`: Liquid Glass's own corners where there's
  /// glass, and a continuous clip before it.
  func roundCorners(_ radius: CGFloat) {
    if #available(iOS 26.0, *) {
      cornerConfiguration = .corners(radius: .fixed(radius))
    } else {
      layer.cornerRadius = radius
      layer.cornerCurve = .continuous
      clipsToBounds = true
    }
  }
}
