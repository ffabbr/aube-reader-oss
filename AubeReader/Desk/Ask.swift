import UIKit

// ─── The bar ─────────────────────────────────────────────────────────────────

/// Where a question is written: a field of Liquid Glass with a send button
/// beside it, both in one glass container, so the button wells up out of the
/// field's end once there is something to send and sinks back into it after.
/// While an answer is being written, the button stops it.
final class AskBar: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
  static let font = Faces.sans(16)
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
    AskBar.round(capsule, AskBar.corner)
    AskBar.round(knob, AskBar.low / 2)
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

  private static func round(_ v: UIVisualEffectView, _ r: CGFloat) {
    if #available(iOS 26.0, *) {
      v.cornerConfiguration = .corners(radius: .fixed(r))
    } else {
      v.layer.cornerRadius = r
      v.layer.cornerCurve = .continuous
      v.clipsToBounds = true
    }
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

// ─── A question, sent ────────────────────────────────────────────────────────

/// A question as sent: its text set just as it was in the field, on a soft
/// pill of the page's fill.
final class Bubble: UIView {
  let text = UITextView()

  init(_ question: String) {
    super.init(frame: .zero)
    backgroundColor = Palette.fill
    layer.cornerRadius = AskBar.corner
    layer.cornerCurve = .continuous
    Bubble.style(text)
    text.text = question
    text.isEditable = false
    text.isScrollEnabled = false
    addSubview(text)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    text.frame = bounds
  }

  private static func style(_ t: UITextView) {
    t.font = AskBar.font
    t.textColor = Palette.ink
    t.backgroundColor = .clear
    t.textContainerInset = AskBar.inset
    t.textContainer.lineFragmentPadding = 0
  }

  private static let sizer: UITextView = {
    let t = UITextView()
    style(t)
    t.isScrollEnabled = false
    return t
  }()

  /// The bubble's size for `question`, at most `widest` across: as wide as
  /// its longest line, its lines broken just as the field broke them.
  static func size(_ question: String, widest: CGFloat) -> CGSize {
    let across = AskBar.inset.left + AskBar.inset.right
    let inner = widest - across
    let r = (question as NSString).boundingRect(
      with: CGSize(width: inner, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: AskBar.font], context: nil)
    let w = min(inner, ceil(r.width) + 2) + across
    sizer.text = question
    let h = ceil(sizer.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
    return CGSize(width: w, height: max(AskBar.low, h))
  }
}

// ─── A block of an answer ────────────────────────────────────────────────────

/// One block of an answer, set as its kind is: a paragraph, heading or list
/// item as text, a quote with a rule beside it, code on a tinted ground, a
/// displayed formula centered, a rule across.
final class Passage: UIView {
  private(set) var mark: Markdown
  private(set) var partial: Bool
  private let label = UILabel()
  private let picture = UIImageView()
  private let bar = UIView()
  private var fitted: (width: CGFloat, height: CGFloat)?

  static let body = Prose(size: 17, color: Palette.ink)

  init(_ mark: Markdown, partial: Bool) {
    self.mark = mark
    self.partial = partial
    super.init(frame: .zero)
    label.numberOfLines = 0
    addSubview(label)
    addSubview(picture)
    bar.backgroundColor = Palette.line
    addSubview(bar)
    layer.cornerCurve = .continuous
    render()
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Passage, _) in
      self.render()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func set(_ mark: Markdown, partial: Bool) {
    guard mark != self.mark || partial != self.partial else { return }
    self.mark = mark
    self.partial = partial
    render()
  }

  private func render() {
    fitted = nil
    let traits = traitCollection
    label.isHidden = false
    picture.isHidden = true
    bar.isHidden = true
    backgroundColor = nil
    layer.cornerRadius = 0
    switch mark {
    case let .paragraph(s):
      label.attributedText = Passage.body.set(s, partial: partial, traits: traits)
    case let .heading(s, level):
      let p = Prose(size: level <= 2 ? 21 : 18, weight: .semibold, color: Palette.ink, leading: 1.2)
      label.attributedText = p.set(s, partial: partial, traits: traits)
    case let .item(s, marker, depth):
      let indent = CGFloat(depth) * 22
      let hang: CGFloat = marker.count > 2 ? 30 : 22
      let m = NSMutableAttributedString(
        string: marker + "\t", attributes: [.font: Passage.body.font(), .foregroundColor: Palette.quiet])
      m.append(Passage.body.set(s, partial: partial, traits: traits))
      let ps = NSMutableParagraphStyle()
      ps.lineHeightMultiple = Passage.body.leading
      ps.hyphenationFactor = 0.3
      ps.firstLineHeadIndent = indent
      ps.headIndent = indent + hang
      ps.tabStops = [NSTextTab(textAlignment: .left, location: indent + hang)]
      m.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: m.length))
      label.attributedText = m
    case let .quote(s):
      let p = Prose(size: 17, italic: true, color: Palette.quiet)
      label.attributedText = p.set(s, partial: partial, traits: traits)
      bar.isHidden = false
    case let .code(s):
      let ps = NSMutableParagraphStyle()
      ps.lineHeightMultiple = 1.2
      label.attributedText = NSAttributedString(
        string: s, attributes: [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: Palette.ink, .paragraphStyle: ps])
      backgroundColor = Palette.fill
      layer.cornerRadius = 12
    case let .math(s):
      label.isHidden = true
      picture.isHidden = false
      picture.image = TeX.picture(s, size: 18, color: Palette.ink.resolvedColor(with: traits), display: true).image
    case .rule:
      label.isHidden = true
      backgroundColor = Palette.line
    }
  }

  /// Sets out the block at `width` and returns its height.
  func measure(_ width: CGFloat) -> CGFloat {
    if let f = fitted, f.width == width { return f.height }
    func fit(_ w: CGFloat) -> CGFloat { ceil(label.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height) }
    let h: CGFloat
    switch mark {
    case .math:
      let size = picture.image?.size ?? .zero
      // Wider than the column, it is drawn smaller to fit.
      let s = min(1, width / max(size.width, 1))
      picture.frame = CGRect(x: ((width - size.width * s) / 2).rounded(), y: 0, width: size.width * s, height: size.height * s)
      h = size.height * s
    case .rule:
      h = 1
    case .code:
      let lh = fit(width - 32)
      label.frame = CGRect(x: 16, y: 12, width: width - 32, height: lh)
      h = lh + 24
    case .quote:
      let lh = fit(width - 20)
      label.frame = CGRect(x: 20, y: 0, width: width - 20, height: lh)
      bar.frame = CGRect(x: 2, y: 4, width: 2.5, height: max(0, lh - 8))
      h = lh
    default:
      let lh = fit(width)
      label.frame = CGRect(x: 0, y: 0, width: width, height: lh)
      h = lh
    }
    fitted = (width, h)
    return h
  }

  /// The space between two blocks.
  static func gap(_ a: Markdown, _ b: Markdown) -> CGFloat {
    switch (a, b) {
    case (.item, .item): return 6
    case (_, .heading): return 24
    case (.heading, _): return 8
    case (_, .math), (.math, _): return 12
    case (_, .rule), (.rule, _): return 18
    default: return 14
    }
  }
}

// ─── Waiting ─────────────────────────────────────────────────────────────────

/// Three dots that breathe one after another, while an answer is on its way.
final class Dots: UIView {
  private let dots = (0..<3).map { _ in CALayer() }

  override init(frame: CGRect) {
    super.init(frame: frame)
    for d in dots { layer.addSublayer(d) }
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Dots, _) in self.tint() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private func tint() {
    for d in dots { d.backgroundColor = Palette.muted.resolvedColor(with: traitCollection).cgColor }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    tint()
    for (i, d) in dots.enumerated() {
      d.frame = CGRect(x: CGFloat(i) * 14, y: (bounds.height - 7) / 2, width: 7, height: 7)
      d.cornerRadius = 3.5
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    let now = CACurrentMediaTime()
    for (i, d) in dots.enumerated() {
      d.removeAllAnimations()
      guard window != nil else { continue }
      let a = CAKeyframeAnimation(keyPath: "opacity")
      a.values = [0.25, 1, 0.25]
      let s = CAKeyframeAnimation(keyPath: "transform.scale")
      s.values = [0.75, 1.05, 0.75]
      let g = CAAnimationGroup()
      g.animations = [a, s]
      g.duration = 1.1
      g.repeatCount = .infinity
      g.beginTime = now + Double(i) * 0.16
      g.fillMode = .backwards
      for k in [a, s] { k.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)] }
      d.add(g, forKey: "breathe")
    }
  }
}

// ─── An answer ───────────────────────────────────────────────────────────────

/// An answer as it is written: its blocks, each coming in softly as it
/// begins, three dots while there is nothing yet, and a quiet note if it
/// stopped short. Press and hold to copy it.
final class AnswerView: UIView, UIContextMenuInteractionDelegate {
  private var passages: [Passage] = []
  private let dots = Dots()
  private let note = UILabel()
  private var source = ""

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(dots)
    note.numberOfLines = 0
    note.isHidden = true
    addSubview(note)
    addInteraction(UIContextMenuInteraction(delegate: self))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// Shows `text`, as far as it has been written.
  func show(_ text: String, partial: Bool) {
    source = text
    let marks = Markdown.read(text, partial: partial)
    for (i, m) in marks.enumerated() {
      let open = partial && i == marks.count - 1
      if i < passages.count {
        passages[i].set(m, partial: open)
        continue
      }
      let p = Passage(m, partial: open)
      addSubview(p)
      passages.append(p)
      // A new block rises into place, fading in.
      p.alpha = 0
      p.transform = CGAffineTransform(translationX: 0, y: 8)
      UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
        p.alpha = 1
        p.transform = .identity
      }
    }
    while passages.count > marks.count { passages.removeLast().removeFromSuperview() }
    if !passages.isEmpty && !dots.isHidden {
      UIView.animate(withDuration: 0.2) { self.dots.alpha = 0 } completion: { _ in self.dots.isHidden = true }
    }
  }

  /// Ends the answer, with a line on why if it stopped short.
  func end(_ why: String?) {
    dots.isHidden = true
    note.isHidden = why == nil
    note.attributedText = why.map { Faces.text($0, Faces.sans(14), Palette.muted, leading: 1.2) }
  }

  /// Sets out the answer at `width` and returns its height.
  func measure(_ width: CGFloat) -> CGFloat {
    var y: CGFloat = 0
    if passages.isEmpty && !dots.isHidden {
      dots.frame = CGRect(x: 2, y: 4, width: 40, height: 18)
      y = 26
    }
    for (i, p) in passages.enumerated() {
      if i > 0 { y += Passage.gap(passages[i - 1].mark, p.mark) }
      let h = p.measure(width)
      p.bounds = CGRect(x: 0, y: 0, width: width, height: h)
      p.center = CGPoint(x: width / 2, y: y + h / 2)
      y += h
    }
    if !note.isHidden {
      if !passages.isEmpty { y += 10 }
      let h = ceil(note.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
      note.frame = CGRect(x: 0, y: y, width: width, height: h)
      y += h
    }
    return y
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    guard !source.isEmpty else { return nil }
    let text = source
    return UIContextMenuConfiguration(actionProvider: { _ in
      UIMenu(children: [
        UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = text },
      ])
    })
  }
}

// ─── The conversation ────────────────────────────────────────────────────────

/// What has been asked about a topic and answered, one under another.
/// Answers stream in from `OpenAI` and are shown a little behind what has
/// arrived, at a steady pace, so that they read as written rather than dropped in.
final class Talk: UIView {
  final class Turn {
    let question: String
    let bubble: Bubble
    let answer = AnswerView()
    var letters: [Character] = []
    /// How many letters are on show, and how many were drawn last.
    var shown = 0.0
    var drawn = -1
    var done = false
    var settled = false
    var note: String?
    var task: Task<Void, Never>?

    init(_ question: String) {
      self.question = question
      bubble = Bubble(question)
    }
  }

  /// Tells the model what the reader is looking at.
  var brief = ""
  /// Called when the conversation's height may have changed.
  var onChange: (() -> Void)?
  /// Called when an answer starts or stops being written.
  var onBusy: ((Bool) -> Void)?
  private(set) var turns: [Turn] = []
  private var link: CADisplayLink?
  private var last = 0.0

  deinit {
    for t in turns { t.task?.cancel() }
    link?.invalidate()
  }

  /// Sends `question`, with the conversation so far, and starts on its answer.
  func ask(_ question: String) -> Turn {
    var messages = [["role": "system", "content": brief]]
    for t in turns where !t.letters.isEmpty {
      messages.append(["role": "user", "content": t.question])
      messages.append(["role": "assistant", "content": String(t.letters)])
    }
    messages.append(["role": "user", "content": question])

    let t = Turn(question)
    t.bubble.alpha = 0
    t.answer.alpha = 0
    addSubview(t.bubble)
    addSubview(t.answer)
    turns.append(t)
    onBusy?(true)
    t.task = Task { [weak self] in
      do {
        for try await piece in OpenAI.stream(messages) {
          guard !t.done else { return }
          t.letters.append(contentsOf: piece)
          self?.run()
        }
        self?.finish(t, note: nil)
      } catch {
        self?.finish(t, note: Task.isCancelled ? nil : error.localizedDescription)
      }
    }
    onChange?()
    return t
  }

  /// Stops the answer being written, where it has got to on screen.
  func stop() {
    guard let t = turns.last, !t.done else { return }
    t.task?.cancel()
    t.letters = Array(t.letters.prefix(Int(t.shown)))
    finish(t, note: t.letters.isEmpty ? "Stopped." : nil)
  }

  private func finish(_ t: Turn, note: String?) {
    guard !t.done else { return }
    t.done = true
    t.note = note
    onBusy?(false)
    run()
  }

  private func run() {
    guard link == nil else { return }
    let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
    l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    l.add(to: .main, forMode: .common)
    link = l
    last = 0
  }

  @objc private func tick(_ l: CADisplayLink) {
    let dt = last > 0 ? min(l.timestamp - last, 1.0 / 30) : 1.0 / 120
    last = l.timestamp
    var changed = false
    var behind = false
    for t in turns {
      let total = Double(t.letters.count)
      if t.shown < total {
        // Never slower than a quick reader, and quicker the further behind.
        t.shown = min(total, t.shown + max(70, (total - t.shown) * 5) * dt)
        behind = true
        if Int(t.shown) != t.drawn {
          t.drawn = Int(t.shown)
          t.answer.show(String(t.letters.prefix(t.drawn)), partial: true)
          changed = true
        }
      } else if t.done && !t.settled {
        t.settled = true
        t.answer.show(String(t.letters), partial: false)
        t.answer.end(t.note)
        changed = true
      }
    }
    if changed { onChange?() }
    if !behind && turns.allSatisfy({ !$0.done || $0.settled }) {
      l.invalidate()
      link = nil
    }
  }

  /// Sets out the conversation at `width` and returns its height: each
  /// question to the right, no wider than the field it was asked in, and its
  /// answer across the column beneath.
  func measure(_ width: CGFloat) -> CGFloat {
    var y: CGFloat = 0
    for (n, t) in turns.enumerated() {
      if n > 0 { y += 40 }
      let s = Bubble.size(t.question, widest: width - AskBar.room)
      t.bubble.frame = CGRect(x: width - s.width, y: y, width: s.width, height: s.height)
      y += s.height + 20
      let h = t.answer.measure(width)
      t.answer.frame = CGRect(x: 0, y: y, width: width, height: h)
      y += h
    }
    return y
  }
}
