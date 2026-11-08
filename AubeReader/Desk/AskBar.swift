import UIKit

/// Where a question is written: a field of Liquid Glass with a send button
/// beside it, both in one glass container, so the button wells up out of the
/// field's end once there is something to send and sinks back into it after.
/// While an answer is being written, the button stops it.
final class AskBar: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
  static let font = TopicFace.sans(16)
  /// Around the text, in the field and in a sent question's bubble alike, so
  /// that one can turn into the other without the text moving inside it.
  static let inset = UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
  static let corner: CGFloat = 24
  static let low: CGFloat = 48
  static let high: CGFloat = 136
  /// What the send button takes from the field's width once it is out: its
  /// own width and a gap a little wider than the glass bridges, so that at
  /// rest the two stand apart and only run together on the way out and in.
  static let room: CGFloat = low + 12

  let field = UITextView()
  var onSend: ((String) -> Void)?
  var onStop: (() -> Void)?
  /// Called when the bar would like a different height.
  var onResize: (() -> Void)?
  var busy = false {
    didSet { if busy != oldValue { refresh() } }
  }

  private let glass = UIVisualEffectView()
  private let capsule = UIVisualEffectView()
  private let knob = UIVisualEffectView()
  private let glyph = UIImageView()
  private let hint = UILabel()
  /// Whether the send button is out of the field.
  private var out = false
  private var tall = AskBar.low

  override init(frame: CGRect) {
    super.init(frame: frame)
    if #available(iOS 26.0, *) {
      let c = UIGlassContainerEffect()
      c.spacing = 8
      glass.effect = c
    }
    addSubview(glass)
    capsule.effect = AskBar.glass(tinted: false)
    capsule.roundCorners(AskBar.corner)
    knob.roundCorners(AskBar.low / 2)
    // The button waits behind the field's end.
    glass.contentView.addSubview(knob)
    glass.contentView.addSubview(capsule)

    hint.text = "Ask about this…"
    hint.font = AskBar.font
    hint.textColor = Palette.muted
    hint.isAccessibilityElement = false
    capsule.contentView.addSubview(hint)
    field.font = AskBar.font
    field.textColor = Palette.ink
    field.tintColor = Palette.ink
    field.backgroundColor = .clear
    field.textContainerInset = AskBar.inset
    field.textContainer.lineFragmentPadding = 0
    field.isScrollEnabled = false
    field.returnKeyType = .send
    field.enablesReturnKeyAutomatically = true
    field.accessibilityLabel = "Ask about this topic"
    field.delegate = self
    capsule.contentView.addSubview(field)

    // The knob's own glass answers the touch, so a plain tap beside it
    // (rather than a button inside, whose touch the glass would take) sends.
    glyph.contentMode = .center
    glyph.tintColor = AskBar.glassy ? Palette.page : Palette.ink
    glyph.alpha = 0
    knob.contentView.addSubview(glyph)
    knob.isAccessibilityElement = true
    knob.accessibilityTraits = .button
    let tap = UITapGestureRecognizer(target: self, action: #selector(press))
    tap.delegate = self
    knob.addGestureRecognizer(tap)
    refresh()
    // The button's glass is tinted with the ink as it was when it came out.
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: AskBar, _) in
      if self.out { self.knob.effect = AskBar.glass(tinted: true) }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private static var glassy: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  private static func glass(tinted: Bool) -> UIVisualEffect {
    if #available(iOS 26.0, *) {
      let g = UIGlassEffect()
      g.isInteractive = true
      if tinted { g.tintColor = Palette.ink }
      return g
    }
    return UIBlurEffect(style: .systemThinMaterial)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    glass.frame = bounds
    let w = bounds.width - (out ? AskBar.room : 0)
    capsule.frame = CGRect(x: 0, y: 0, width: w, height: bounds.height)
    field.frame = capsule.bounds
    hint.frame = CGRect(
      x: AskBar.inset.left, y: AskBar.inset.top,
      width: w - AskBar.inset.left - AskBar.inset.right, height: ceil(AskBar.font.lineHeight))
    let k = AskBar.low
    knob.bounds = CGRect(x: 0, y: 0, width: k, height: k)
    knob.center = out
      ? CGPoint(x: bounds.width - k / 2, y: bounds.height - k / 2)
      : CGPoint(x: w - k / 2 - 6, y: bounds.height - k / 2)
    knob.transform = out ? .identity : CGAffineTransform(scaleX: 0.55, y: 0.55)
    glyph.frame = knob.contentView.bounds
  }

  /// How tall the bar would be at `width`, for the text in the field.
  func height(for width: CGFloat) -> CGFloat {
    let w = width - (out ? AskBar.room : 0)
    let h = ceil(field.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
    if field.isScrollEnabled != (h > AskBar.high) { field.isScrollEnabled = h > AskBar.high }
    return min(AskBar.high, max(AskBar.low, h))
  }

  /// The field's glass, in `view`'s coordinates.
  func fieldFrame(in view: UIView) -> CGRect { capsule.convert(capsule.bounds, to: view) }

  /// Empties the field once its question has been sent.
  func clear() {
    field.text = ""
    textViewDidChange(field)
  }

  private var question: String { field.text.trimmingCharacters(in: .whitespacesAndNewlines) }

  @objc private func press() {
    if busy {
      onStop?()
    } else if !question.isEmpty {
      onSend?(question)
    }
  }

  /// Brings the button out of the field or back into it, and shows it as
  /// send or stop.
  private func refresh() {
    let shape = UIImage.SymbolConfiguration(pointSize: busy ? 13 : 17, weight: .semibold)
    glyph.image = UIImage(systemName: busy ? "stop.fill" : "arrow.up", withConfiguration: shape)
    knob.accessibilityLabel = busy ? "Stop" : "Send"
    let want = busy || !question.isEmpty
    guard want != out else { return }
    out = want
    let move = {
      self.setNeedsLayout()
      self.layoutIfNeeded()
      self.knob.effect = want ? AskBar.glass(tinted: true) : nil
      self.glyph.alpha = want ? 1 : 0
    }
    if window == nil || UIAccessibility.isReduceMotionEnabled {
      move()
    } else {
      UIView.animate(
        springDuration: want ? 0.55 : 0.4, bounce: want ? 0.32 : 0.1, initialSpringVelocity: 0, delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction], animations: move)
    }
    onResize?()
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

  func textViewDidChange(_ textView: UITextView) {
    hint.isHidden = !field.text.isEmpty
    refresh()
    let h = height(for: bounds.width)
    if h != tall {
      tall = h
      onResize?()
    }
  }

  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    guard text == "\n" else { return true }
    if !busy && !question.isEmpty { onSend?(question) }
    return false
  }
}
