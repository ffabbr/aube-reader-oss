import UIKit

/// A topic page lifted out of the reader. The paragraph that was pressed comes
/// up off the page and flies, straight, to its place in the topic's page,
/// while a card unfolds around it and the reader sinks back onto the desk.
/// Closing runs the same way back, ending with the paragraph set down where it
/// was. The card can also be pulled down and let go.
///
/// Opening and closing are timed on cubic-bézier curves (see `Ease`), stepped
/// here frame by frame: `lift` picks the paragraph up, `wide` and `tall`
/// unfold the card across and down (down a beat later and running a hair
/// past, so it pours open rather than scales, tipping a little as it speeds
/// up), `fly` carries the paragraph. `pull` is a spring that follows a finger
/// dragging the card away; `drop` takes it back from wherever it was let go.
final class TopicOverlay: UIView, UIGestureRecognizerDelegate {
  var onClosed: (() -> Void)?

  /// Where the paragraph sits on the page, and the card's first frame around it.
  private var para: CGRect
  private var from: CGRect
  /// Finds the paragraph again, where it now sits and how it now reads, after
  /// the screen has turned and the reader has set its text anew.
  private let locate: () -> (frame: CGRect, text: UIImage, size: CGFloat)?
  private weak var host: UIView?
  /// The picture of the reader behind, as it was when last taken.
  private var shot: UIView
  private let backdrop = UIView()
  private let scrim = UIView()
  private let patch = UIView()
  private let card = UIView()
  private let sheet = UIView()
  /// Cuts the flying paragraph off at the card's edge, as the page will once it lands.
  private let clip = CAShapeLayer()
  private let page: TopicPage

  private let lift = Tween(0)
  private let wide = Tween(0)
  private let tall = Tween(0)
  private let fly = Tween(0)
  private let pull = Spring(0, response: 0.42, damping: 0.86)
  private let drop = Tween(0)
  private var leaving = false
  /// Where the card had been pulled to when it was let go to close.
  private var pullFrom = 0.0
  private var landed = false
  private var dragging = false
  private var link: CADisplayLink?
  private var last = 0.0
  private let calm = UIAccessibility.isReduceMotionEnabled

  /// Opens `topic` from the paragraph at `paragraph` (in `host`'s coordinates),
  /// drawn as `text` at `textSize` points. Without a topic written by hand,
  /// `writer` finds one as the card opens.
  init(
    topic: Topic?, writer: TopicWriter?, paragraph: CGRect, text: UIImage, textSize: CGFloat, label: String, in host: UIView,
    locate: @escaping () -> (frame: CGRect, text: UIImage, size: CGFloat)?
  ) {
    let bounds = host.bounds
    para = paragraph
    from = TopicOverlay.around(paragraph, in: bounds)
    self.locate = locate
    self.host = host
    shot = host.snapshotView(afterScreenUpdates: false) ?? UIView()
    page = TopicPage(topic, writer: writer, text: text, textSize: textSize, label: label)
    super.init(frame: bounds)
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Behind the shrinking reader is more of the same page, dimmed with it,
    // so the reader recedes without an edge of its own.
    backgroundColor = Palette.page

    backdrop.frame = bounds
    backdrop.clipsToBounds = true
    shot.frame = backdrop.bounds
    backdrop.addSubview(shot)
    // Where the paragraph was lifted from, the page shows through bare.
    patch.backgroundColor = Palette.page
    patch.frame = paragraph.insetBy(dx: -3, dy: -2)
    patch.alpha = 0
    backdrop.addSubview(patch)
    scrim.frame = bounds
    scrim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scrim.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.6) : UIColor(white: 0.05, alpha: 0.32) }
    scrim.alpha = 0
    addSubview(backdrop)
    addSubview(scrim)

    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = 0
    sheet.backgroundColor = Palette.page
    sheet.clipsToBounds = true
    sheet.layer.cornerCurve = .continuous
    card.addSubview(sheet)
    sheet.addSubview(page)
    // Tipped, the card would cut through the reader behind it; it stays well in front.
    card.layer.zPosition = 300
    addSubview(card)
    // The paragraph flies above everything, unclipped, until it lands in the page.
    page.text.frame = paragraph
    page.text.layer.zPosition = 400
    addSubview(page.text)

    page.wake = { [weak self] in self?.run() }
    page.close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
    tap.delegate = self
    addGestureRecognizer(tap)
    let drag = UIPanGestureRecognizer(target: self, action: #selector(onDrag))
    drag.delegate = self
    addGestureRecognizer(drag)

    accessibilityViewIsModal = true
    paint()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private static let corner: CGFloat = 16

  /// How far the card rests from the screen's edges: a little all round, and
  /// more at the sides when the screen is wide.
  private var gap: CGSize {
    let edge: CGFloat = 22
    return CGSize(width: bounds.width > bounds.height ? (bounds.width * 0.09).rounded() : edge, height: edge)
  }

  /// Where the card comes to rest: the screen but for its gap. A page taller
  /// than that scrolls.
  private var to: CGRect {
    let g = gap
    let size = CGSize(width: bounds.width - 2 * g.width, height: bounds.height - 2 * g.height)
    page.room = size.height
    if page.bounds.size != size {
      page.bounds.size = size
      page.layoutIfNeeded()
    }
    return CGRect(origin: CGPoint(x: g.width, y: g.height), size: size)
  }

  private static func around(_ paragraph: CGRect, in bounds: CGRect) -> CGRect {
    paragraph.insetBy(dx: -16, dy: -10).intersection(bounds.insetBy(dx: 4, dy: 4))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Turning, the old picture of the reader stays centered behind until
    // `settle()` takes a new one.
    backdrop.bounds = CGRect(origin: .zero, size: bounds.size)
    shot.center = CGPoint(x: bounds.midX, y: bounds.midY)
    paint()
  }

  /// After the screen has turned: finds the paragraph where the reader now
  /// sets it, and swaps in a fresh picture of the reader behind.
  func settle() {
    guard let host, !leaving else { return }
    if let (frame, text, size) = locate() {
      para = frame
      from = TopicOverlay.around(frame, in: host.bounds)
      patch.frame = frame.insetBy(dx: -3, dy: -2)
      page.retext(text, size: size)
    }
    retake()
    run()
  }

  /// After the appearance has changed, once the reader has redrawn in the new
  /// inks: the paragraph and the reader behind were pictured in the old ones,
  /// so both are taken again. Opening or closing, the paragraph keeps its place.
  func restyle() {
    if let (_, text, size) = locate() { page.retext(text, size: size) }
    retake()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    paint()
    CATransaction.commit()
    run()
  }

  /// Swaps in a fresh picture of the reader behind, fading it over the old.
  private func retake() {
    guard let host else { return }
    // The overlay hides for the moment the picture is taken, so it isn't in it.
    isHidden = true
    let fresh = host.snapshotView(afterScreenUpdates: true) ?? UIView()
    isHidden = false
    fresh.frame = backdrop.bounds
    fresh.alpha = 0
    backdrop.insertSubview(fresh, aboveSubview: shot)
    let old = shot
    shot = fresh
    UIView.animate(withDuration: 0.25, animations: { fresh.alpha = 1 }, completion: { _ in old.removeFromSuperview() })
  }

  // ─── Opening and closing ───────────────────────────────────────────────

  func open() {
    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
    let now = CACurrentMediaTime()
    // The paragraph comes up off the page first; a beat later it all unfolds,
    // the card across before down.
    // Unhurried on purpose: the time it takes is time for the page to be written.
    let k = calm ? 0.0 : 1.3
    lift.to(1, over: 0.3 * k, .rise, now: now)
    // It lands as the card settles, so it rests in place from then on.
    fly.to(1, over: 1.1 * k, after: 0.1 * k, .unfold, now: now)
    wide.to(1, over: 0.84 * k, after: 0.1 * k, .unfold, now: now)
    tall.to(1, over: 1.0 * k, after: 0.17 * k, .pour, now: now)
    run()
  }

  func close(throw velocity: Double = 0) {
    guard !leaving else { return }
    leaving = true
    // The keyboard goes down with the card.
    endEditing(true)
    if page.docked {
      let r = slotOnScreen(card.frame)
      addSubview(page.text)
      page.text.layer.zPosition = 400
      page.text.frame = r
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      paint()
      CATransaction.commit()
    }
    // Thrown away, it all goes a little quicker.
    let k = (calm ? 0 : 1) * (velocity > 0 ? max(0.7, 1 - velocity / 6000) : 1)
    let now = CACurrentMediaTime()
    tall.to(0, over: 0.5 * k, .fold, now: now)
    wide.to(0, over: 0.48 * k, after: 0.04 * k, .fold, now: now)
    fly.to(0, over: 0.56 * k, .fold, now: now)
    drop.to(1, over: 0.5 * k, .fold, now: now)
    pullFrom = pull.value
    run()
  }

  /// Takes the overlay away at once, as after the screen turned.
  func dismissNow() {
    link?.invalidate()
    link = nil
    page.putAway()
    removeFromSuperview()
    onClosed?()
  }

  @objc private func closeTapped() { close() }

  @objc private func backdropTapped(_ g: UITapGestureRecognizer) { close() }

  override func accessibilityPerformEscape() -> Bool {
    close()
    return true
  }

  // ─── Pulling the card away ─────────────────────────────────────────────

  override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard !leaving else { return false }
    let p = g.location(in: self)
    if g is UITapGestureRecognizer { return !card.frame.contains(p) }
    guard let pan = g as? UIPanGestureRecognizer, pan.view === self else { return super.gestureRecognizerShouldBegin(g) }
    let v = pan.velocity(in: self)
    // Down, and from the top of the page if it starts on the card.
    return v.y > abs(v.x) && (!card.frame.contains(p) || page.atTop)
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    g is UIPanGestureRecognizer && other === page.scroll.panGestureRecognizer
  }

  @objc private func onDrag(_ g: UIPanGestureRecognizer) {
    let dy = Double(g.translation(in: self).y)
    switch g.state {
    case .began, .changed:
      dragging = true
      // The page stays at its top while the card itself is pulled.
      page.scroll.contentOffset.y = 0
      pull.snap(dy < 0 ? -band(-dy, 40) : dy)
      run()
    case .ended, .cancelled, .failed:
      dragging = false
      let vy = Double(g.velocity(in: self).y)
      if g.state == .ended && (dy > 130 || vy > 900) {
        pull.velocity = vy
        close(throw: vy)
      } else {
        pull.target = 0
        pull.velocity = vy
        run()
      }
    default: break
    }
  }

  // ─── Frames ────────────────────────────────────────────────────────────

  private func run() {
    if link == nil {
      let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
      l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
      l.add(to: .main, forMode: .common)
      link = l
      last = 0
    }
  }

  @objc private func frame(_ l: CADisplayLink) {
    let dt = last > 0 ? min(l.timestamp - last, 1.0 / 30) : 1.0 / 120
    last = l.timestamp
    let now = CACurrentMediaTime()
    // Closing, the paragraph is set back down once it is nearly home.
    if leaving && fly.value < 0.1 && tall.value < 0.25 && !landed {
      landed = true
      lift.to(0, over: calm ? 0 : 0.2, .rise, now: now)
      UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }
    for t in [lift, wide, tall, fly, drop] { t.step(now, dt) }
    if leaving {
      pull.snap(pullFrom * (1 - drop.value))
    } else if !dragging {
      pull.step(dt)
    }
    let busy = page.step(dt)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    paint()
    CATransaction.commit()

    if leaving && landed && [lift, wide, tall, fly, drop].allSatisfy(\.resting) {
      dismissNow()
      return
    }
    if !leaving && !page.docked && fly.resting && fly.value == 1 { page.dock() }
    if !busy && !dragging && !leaving && [lift, wide, tall, fly].allSatisfy(\.resting) && pull.resting {
      l.invalidate()
      link = nil
    }
  }

  /// Where the paragraph's place in the page is on screen, for a card at `f`
  /// (untilted), with the page centered on it at its final width.
  private func slotOnScreen(_ f: CGRect) -> CGRect {
    page.layoutIfNeeded()
    return page.slot.offsetBy(dx: f.midX - page.bounds.width / 2, dy: f.minY - page.scroll.contentOffset.y)
  }

  /// Puts everything where the tweens say.
  private func paint() {
    let to = self.to
    var tx = CGFloat(wide.value)
    var ty = CGFloat(tall.value)
    var m = CGFloat(fly.value)
    let lifted = CGFloat(lift.value)
    let pulled = CGFloat(pull.value)
    if calm {
      (tx, ty, m) = (1, 1, 1)
    }
    let open = min(1, max(0, CGFloat(tall.value)))
    // How far the card has been pulled away, as a share of letting it go.
    let away = min(1, max(0, pulled / 520))

    // The card: from around the paragraph to the page, each axis on its own timing.
    var f = CGRect(
      x: from.minX + (to.minX - from.minX) * tx,
      y: from.minY + (to.minY - from.minY) * ty,
      width: from.width + (to.width - from.width) * tx,
      height: from.height + (to.height - from.height) * ty)
    // Picked up, it swells a touch, then settles as it opens.
    let swell = 1 + 0.04 * lifted * (1 - open) - 0.1 * away
    f = f.insetBy(dx: f.width * (1 - swell) / 2, dy: f.height * (1 - swell) / 2)
    f.origin.y += pulled
    card.transform3D = CATransform3DIdentity
    card.bounds = CGRect(origin: .zero, size: f.size)
    card.center = CGPoint(x: f.midX, y: f.midY)
    // It tips back as it rises and leans into its travel, by how fast it goes.
    if !calm {
      var t = CATransform3DIdentity
      t.m34 = -1 / 1600
      let across: CGFloat = to.midX >= from.midX ? 1 : -1
      t = CATransform3DRotate(t, CGFloat(clamp(tall.velocity * 0.012, -0.07, 0.07)), 1, 0, 0)
      t = CATransform3DRotate(t, CGFloat(clamp(wide.velocity * 0.008, -0.05, 0.05)) * across, 0, 1, 0)
      card.transform3D = t
    }
    sheet.frame = card.bounds
    let radius = 10 + (TopicOverlay.corner - 10) * open + 8 * away
    sheet.layer.cornerRadius = radius
    // The card appears under the paragraph as it is picked up, and goes as it is set down.
    card.alpha = calm ? open : min(1, lifted * 1.6 + open)

    var white: CGFloat = 0
    var deepest: CGFloat = 0
    Palette.shadow.resolvedColor(with: traitCollection).getWhite(&white, alpha: &deepest)
    card.layer.shadowOpacity = Float(deepest * (0.9 * lifted + 0.5 * open) * (1 - 0.4 * away))
    card.layer.shadowRadius = 10 + 26 * lifted + 14 * open
    card.layer.shadowOffset = CGSize(width: 0, height: 6 + 14 * lifted + 8 * open)
    card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: radius).cgPath

    // The page inside is laid out at its final width, centered on the card,
    // so it is uncovered rather than squeezed as the card grows.
    page.frame = CGRect(x: (f.width - to.width) / 2, y: 0, width: to.width, height: to.height)
    page.reveal(Double(open), leaving: leaving)

    // The paragraph, in flight: straight from its place on the page to its
    // place in the card once settled (not the card as it is now, which would
    // drag it about), swelling a little halfway as if lifted toward the eye.
    if !page.docked {
      let rest = to.offsetBy(dx: 0, dy: pulled).insetBy(dx: to.width * 0.05 * away, dy: to.height * 0.05 * away)
      let goal = slotOnScreen(rest)
      let k = min(1, max(0, m))
      var r = CGRect(
        x: para.minX + (goal.minX - para.minX) * m,
        y: para.minY + (goal.minY - para.minY) * m,
        width: para.width + (goal.width - para.width) * m,
        height: para.height + (goal.height - para.height) * m)
      let breath = 1 + 0.035 * sin(.pi * k) + 0.02 * lifted * (1 - k)
      r = r.insetBy(dx: r.width * (1 - breath) / 2, dy: r.height * (1 - breath) / 2)
      page.text.frame = r
      // Where the card is too short to show all of it, the paragraph's lines
      // run out under the card's edge all the way in, instead of being cut
      // off when it lands.
      clip.path = UIBezierPath(roundedRect: f.offsetBy(dx: -r.minX, dy: -r.minY), cornerRadius: radius).cgPath
      if page.text.layer.mask !== clip { page.text.layer.mask = clip }
    }

    // The reader sinks back onto the desk, and comes forward as the card is pulled away.
    let sunk = open * (1 - 0.6 * away)
    let s = 1 - 0.07 * sunk - 0.012 * lifted * (1 - open)
    backdrop.center = CGPoint(x: bounds.midX, y: bounds.midY + 14 * sunk)
    backdrop.transform = CGAffineTransform(scaleX: s, y: s)
    scrim.alpha = sunk
    // The paragraph's picture lies exactly over the paragraph, so the swap is
    // all or nothing: a fade would show both at once, doubled.
    patch.alpha = !calm && (lifted > 0.001 || open > 0) ? 1 : 0
  }
}
