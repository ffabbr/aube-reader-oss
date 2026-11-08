import UIKit

/// A footnote opened where it's marked. There's one shape of Liquid Glass, and it
/// starts out as the mark: the same circle, in the same place, with the same
/// number in it. It then stretches out from there into the note, the number
/// staying put at its corner and the words beside it standing still as the glass
/// reaches them, so that it reads as the mark itself opening up. As the topic card
/// does, it unfolds across and then pours down a beat later, stepped here frame by
/// frame (see `Ease`), so that it can turn back from anywhere. Closing runs the same way back.
///
/// It grows onward from the mark, right and down, over what's still to be read and
/// not what led to it. Where there's no room that way it goes the other.
///
/// Only the note's words take touches, so they can be selected, scrolled and followed
/// if they're a link. Everything else reaches the page, which puts the note away,
/// the mark included (see `DeskViewController`).
final class NoteTip: UIView, UITextViewDelegate {
  static let textSize: CGFloat = 15
  static let leading: CGFloat = 1.4
  private static let margin: CGFloat = 16
  private static let widest: CGFloat = 400
  /// From the mark to the near edges of the glass, from the mark to the words, and from the words to the far edge.
  private static let edge: CGFloat = 9
  private static let beside: CGFloat = 9
  private static let far: CGFloat = 16
  private static let corner: CGFloat = 22

  let note: Int
  var onClosed: (() -> Void)?

  /// Under the glass: a little of the page, so the words under it don't compete with its own.
  private let backing = UIView()
  /// Around the glass, not under it: a shadow would darken what's meant to be seen through.
  private let shade = CALayer()
  private let shadeCut = CAShapeLayer()
  private let body = UIVisualEffectView()
  private let number = UILabel()
  private let words = UITextView()
  /// Under a tip too tall to show whole, its words fade out at the edges they run past.
  private let edges = CAGradientLayer()
  private let mark: CGRect
  private let rest: CGRect
  private let wordsAt: CGRect
  private let scrolls: Bool
  private let calm = UIAccessibility.isReduceMotionEnabled
  /// How far the glass has reached, from the mark (0) to where it rests (1), across and down.
  private let wide = Tween(0)
  private let tall = Tween(0)
  private var link: CADisplayLink?
  private var last = 0.0
  private var leaving = false

  /// A tip for note `note`, marked `label`, saying `text`, for the mark at `mark` in `host`.
  init(note: Int, label: String, text: NSAttributedString, mark: CGRect, host: UIView) {
    self.note = note
    self.mark = mark
    let shape = Self.lay(text, mark: mark, in: host.bounds, safe: host.safeAreaInsets)
    rest = shape.rest
    wordsAt = shape.words
    scrolls = shape.scrolls
    super.init(frame: host.bounds)
    autoresizingMask = [.flexibleWidth, .flexibleHeight]

    shade.frame = bounds
    shade.shadowColor = UIColor.black.cgColor
    shade.shadowOffset = CGSize(width: 0, height: 8)
    shade.shadowRadius = 22
    shade.shadowOpacity = host.traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.15
    shade.opacity = 0
    shadeCut.frame = bounds
    shadeCut.fillRule = .evenOdd
    shade.mask = shadeCut
    layer.addSublayer(shade)

    backing.frame = mark
    backing.backgroundColor = Self.backingColor
    backing.alpha = 0
    backing.layer.cornerCurve = .continuous
    backing.layer.cornerRadius = mark.height / 2
    addSubview(backing)

    body.frame = mark
    Self.round(body, mark.height / 2)
    addSubview(body)
    body.contentView.clipsToBounds = true
    body.contentView.layer.cornerCurve = .continuous
    body.contentView.layer.cornerRadius = mark.height / 2

    words.attributedText = text
    words.backgroundColor = .clear
    words.isEditable = false
    words.isSelectable = true
    words.dataDetectorTypes = [.link]
    words.delegate = self
    words.tintColor = Palette.ink
    words.linkTextAttributes = [.foregroundColor: Palette.ink, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Palette.muted]
    words.textContainer.lineFragmentPadding = 0
    words.textContainerInset = .zero
    words.isScrollEnabled = scrolls
    words.showsVerticalScrollIndicator = false
    words.alwaysBounceVertical = scrolls
    words.alpha = 0
    words.accessibilityLabel = "Footnote"
    words.frame = wordsAt.offsetBy(dx: -mark.minX, dy: -mark.minY)
    body.contentView.addSubview(words)

    // The mark itself, drawn over itself, so that nothing changes as the glass takes over.
    number.text = label
    number.textAlignment = .center
    number.font = Halo.font(mark.height)
    number.textColor = Palette.ink
    number.isUserInteractionEnabled = false
    number.frame = CGRect(origin: .zero, size: mark.size)
    body.contentView.addSubview(number)

    if scrolls {
      // The words fade toward the foot, where they go on.
      edges.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
      edges.locations = [0, 0.86, 1]
      edges.frame = CGRect(origin: .zero, size: wordsAt.size)
      words.layer.mask = edges
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  // ─── Shape ───────────────────────────────────────────────────────────────

  /// How much of the page lies under the glass: as little as lets its words be read.
  /// Pale words on the dark are more easily lost in those behind them.
  private static let backingColor = UIColor { traits in
    Palette.page.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.32 : 0.12)
  }

  /// Glass where there's glass; before it, the thinnest material.
  static func material() -> UIVisualEffect {
    if #available(iOS 26.0, *) { return UIGlassEffect(style: .regular) }
    return UIBlurEffect(style: .systemThinMaterial)
  }

  static func round(_ v: UIVisualEffectView, _ r: CGFloat) {
    if #available(iOS 26.0, *) {
      v.cornerConfiguration = .corners(radius: .fixed(r))
    } else {
      v.layer.cornerRadius = r
      v.layer.cornerCurve = .continuous
      v.clipsToBounds = true
    }
  }

  /// Where the glass comes to rest around the mark, and where the words lie in it:
  /// as narrow as they can be without taking another line, so that a note's last line
  /// isn't left with a word on it, and no taller than fits. The first line is level with
  /// the mark, or if the note has to grow upward, the last.
  private static func lay(_ text: NSAttributedString, mark: CGRect, in screen: CGRect, safe: UIEdgeInsets) -> (rest: CGRect, words: CGRect, scrolls: Bool) {
    let line = textSize * leading
    let gutter = edge + mark.width + beside
    // Onward if there's reasonable room, otherwise whichever way has more.
    let rightward = screen.maxX - margin - (mark.minX - edge)
    let leftward = (mark.maxX + edge) - (screen.minX + margin)
    let onward = rightward >= min(widest, 300) || rightward >= leftward
    let wide = min(widest, onward ? rightward : leftward)
    let column = wide - gutter - far
    func measure(_ w: CGFloat) -> CGRect {
      text.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }
    let tall = ceil(measure(column).height)
    var width = column
    var lo = min(column, 120)
    var hi = column
    for _ in 0..<7 {
      let w = (lo + hi) / 2
      if ceil(measure(w).height) > tall { lo = w } else { hi = w; width = w }
    }
    if tall <= line * 1.5 { width = min(column, ceil(measure(column).width) + 1) }
    width = ceil(width)
    let across = gutter + width + far
    let x = onward ? mark.minX - edge : mark.maxX + edge - across

    let lead = max(0, (mark.height - line) / 2) + edge
    let foot = max(edge, 12)
    let needed = max(mark.height + 2 * edge, lead + tall + foot)
    let downward = screen.maxY - margin - safe.bottom - (mark.minY - edge)
    let upward = (mark.maxY + edge) - (screen.minY + margin + safe.top)
    let down = needed <= downward || downward >= upward
    let room = min(down ? downward : upward, max(screen.height * 0.46, 200))
    let height = min(needed, room)
    let y = down ? mark.minY - edge : mark.maxY + edge - height
    let rest = CGRect(x: x.rounded(), y: y.rounded(), width: across, height: ceil(height))
    let wordsX = onward ? rest.minX + gutter : rest.minX + far
    let wordsY = down ? rest.minY + lead : rest.minY + foot
    return (rest, CGRect(x: wordsX, y: wordsY, width: width, height: rest.height - lead - foot), needed > room)
  }

  /// Puts everything as it is with the glass over `frame`, keeping the mark and the
  /// words where they are on the screen, whatever the glass does around them.
  private func shape(_ frame: CGRect, radius: CGFloat) {
    body.frame = frame
    backing.frame = frame
    Self.round(body, radius)
    body.contentView.layer.cornerRadius = radius
    backing.layer.cornerRadius = radius
    number.frame = mark.offsetBy(dx: -frame.minX, dy: -frame.minY)
    words.frame = wordsAt.offsetBy(dx: -frame.minX, dy: -frame.minY)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let outline = UIBezierPath(roundedRect: frame, cornerRadius: radius)
    shade.shadowPath = outline.cgPath
    let cut = UIBezierPath(rect: bounds)
    cut.append(outline)
    shadeCut.path = cut.cgPath
    shade.opacity = Float(clamp(Double(tall.value), 0, 1))
    CATransaction.commit()
  }

  /// The glass as far along as it's got.
  private func step() {
    func along(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
    let (w, h) = (wide.value, tall.value)
    let frame = CGRect(
      x: along(mark.minX, rest.minX, w), y: along(mark.minY, rest.minY, h),
      width: along(mark.width, rest.width, w), height: along(mark.height, rest.height, h))
    shape(frame, radius: min(frame.height / 2, frame.width / 2, Self.corner))
    // What's under the glass and the words on it come with its reach, so they go back the way they came.
    let reached = min(w, h)
    backing.alpha = CGFloat(smoothstep(0, 0.6, reached))
    words.alpha = CGFloat(smoothstep(0.3, 0.8, reached))
  }

  private func run() {
    guard link == nil else { return }
    last = 0
    let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
    l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    l.add(to: .main, forMode: .common)
    link = l
  }

  @objc private func frame(_ link: CADisplayLink) {
    let now = CACurrentMediaTime()
    let dt = last > 0 ? now - last : 1.0 / 120
    last = now
    wide.step(now, dt)
    tall.step(now, dt)
    step()
    guard wide.resting, tall.resting else { return }
    link.invalidate()
    self.link = nil
    if leaving { gone() }
  }

  private func gone() {
    removeFromSuperview()
    onClosed?()
  }

  // ─── Coming and going ────────────────────────────────────────────────────

  /// Soft away from the mark, with a long landing; down a beat later, running a hair past.
  private static let across = Ease(0.3, 0, 0.14, 1)
  private static let downward = Ease(0.36, 0, 0.16, 1.035)

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
    wide.to(1, over: 0.5, Self.across, now: now)
    tall.to(1, over: 0.52, after: 0.07, Self.downward, now: now)
    step()
    run()
    // The first frame is the mark as it already was: the glass comes up over it where it stands.
    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.body.effect = Self.material() }
  }

  /// Draws back into the mark, and goes. `quickly` for when the page itself is on its way somewhere.
  func close(quickly: Bool = false) {
    guard !leaving else { return }
    leaving = true
    isUserInteractionEnabled = false
    words.selectedTextRange = nil
    if quickly || calm {
      link?.invalidate()
      link = nil
      UIView.animate(withDuration: quickly ? 0.12 : 0.18, delay: 0, options: [.curveEaseOut]) {
        self.alpha = 0
      } completion: { _ in self.gone() }
      return
    }
    let now = CACurrentMediaTime()
    // Up first, then in: the way it came, from wherever it had got to.
    tall.to(0, over: 0.34, Ease.fold, now: now)
    wide.to(0, over: 0.38, after: 0.05, Ease.fold, now: now)
    run()
    // The glass gives way to the mark on the page just as it gets there.
    UIView.animate(withDuration: 0.14, delay: 0.3, options: [.curveEaseOut]) { self.body.effect = nil }
  }

  // ─── Touches ─────────────────────────────────────────────────────────────

  /// Whether a point is the note's own, and not for the page. Its mark is the page's: tapped, it puts the note away.
  private func owns(_ point: CGPoint) -> Bool { rest.contains(point) && !mark.insetBy(dx: -8, dy: -8).contains(point) }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, owns(point) else { return nil }
    return super.hitTest(point, with: event) ?? self
  }

  /// Whether a touch is the note's own, and not for the page under it.
  func holds(_ touch: UITouch) -> Bool { owns(touch.location(in: self)) }

  /// Lets the words' fade follow them to the foot once they've been scrolled there.
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrolls else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    edges.frame = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
    let left = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
    let fade = min(max(left, 0), 44) / 44
    edges.locations = [0, NSNumber(value: Double(1 - 0.14 * fade)), 1]
    CATransaction.commit()
  }
}
