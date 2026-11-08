import UIKit

// ─── A chip ──────────────────────────────────────────────────────────────────

/// An aspect's name in a pill. Chosen, it fills with ink; the blend follows
/// `chosen`, a spring the page steps.
final class Chip: UIControl {
  let chosen = Spring(0, response: 0.32)
  private let label = UILabel()
  private let text: String

  init(_ text: String) {
    self.text = text
    super.init(frame: .zero)
    layer.cornerCurve = .continuous
    label.isUserInteractionEnabled = false
    addSubview(label)
    isAccessibilityElement = true
    accessibilityLabel = text
    accessibilityTraits = .button
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Chip, _) in self.tint() }
    tint()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var intrinsicContentSize: CGSize {
    let s = label.intrinsicContentSize
    return CGSize(width: ceil(s.width) + 34, height: 40)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
    label.sizeToFit()
    label.center = CGPoint(x: bounds.midX, y: bounds.midY)
  }

  /// Colors for how far chosen it is.
  func tint() {
    let t = CGFloat(clamp(chosen.value, 0, 1))
    let traits = traitCollection
    layer.backgroundColor = Palette.mix(Palette.ink, t, over: Palette.fill, traits).cgColor
    label.attributedText = Faces.text(text, Faces.sans(15, weight: .medium), Palette.mix(Palette.page, t, over: Palette.ink, traits), leading: 1)
    accessibilityTraits = chosen.target > 0.5 ? [.button, .selected] : .button
  }

  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      UIView.animate(
        withDuration: isHighlighted ? 0.12 : 0.5, delay: 0, usingSpringWithDamping: isHighlighted ? 1 : 0.55,
        initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]
      ) {
        self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
      }
    }
  }
}

// ─── An aspect, opened ───────────────────────────────────────────────────────

/// What a chip opens: the aspect's drawing and its account.
final class AspectPanel: UIView {
  let show = Spring(0, response: 0.42)
  private let sketch = SketchView()
  private let body = UILabel()
  private var drawn = false

  init(_ aspect: Topic.Aspect) {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    sketch.sketch = aspect.sketch
    // Set as the answers asked for below the chips are, so the two read alike.
    body.attributedText = Faces.text(aspect.body, Passage.body.font(), Palette.ink, leading: Passage.body.leading)
    body.numberOfLines = 0
    addSubview(sketch)
    addSubview(body)
    alpha = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// Sets out the panel at `width` for a sketch of `ratio` and returns its height.
  func measure(_ width: CGFloat, ratio: CGSize) -> CGFloat {
    let sh = min(210, width * ratio.height / ratio.width)
    sketch.frame = CGRect(x: 0, y: 8, width: width, height: sh)
    let bh = body.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    body.frame = CGRect(x: 0, y: sketch.frame.maxY + 22, width: width, height: bh)
    return body.frame.maxY + 8
  }

  /// Fades the panel in rising, or out in place; draws the sketch as it arrives.
  func apply() {
    let coming = show.target > 0.5
    let a = CGFloat(smoothstep(coming ? 0.25 : 0, 1, show.value))
    alpha = a
    transform = CGAffineTransform(translationX: 0, y: coming ? 18 * (1 - a) : 0)
    if coming && show.value > 0.2 && !drawn {
      drawn = true
      sketch.play(pace: 0.85)
    } else if !coming && show.value < 0.02 && drawn {
      drawn = false
      sketch.reset()
    }
  }
}

// ─── A small drawing ─────────────────────────────────────────────────────────

/// One of the four small drawings beside the title: an aspect's sketch, bare
/// on the page, lines only (no lettering, no washes), tipped by `tilt` (radians) so that
/// it leans in toward the title. The tilt sits on the drawing inside, so the
/// page's entrance can move the tile as a whole.
final class Tile: UIView {
  let sketch = SketchView()
  /// Where a drawing from the library goes, for a topic that has one in place of a sketch.
  let art = DrawingView()

  init(_ sketch: Sketch, tilt: CGFloat) {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    self.sketch.sketch = sketch
    self.sketch.weight = 0.8
    self.sketch.lettered = false
    self.sketch.washed = false
    self.sketch.trimmed = true
    self.sketch.transform = CGAffineTransform(rotationAngle: tilt)
    addSubview(self.sketch)
    art.small = true
    art.transform = self.sketch.transform
    addSubview(art)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    sketch.bounds = bounds
    sketch.center = CGPoint(x: bounds.midX, y: bounds.midY)
    art.bounds = bounds
    art.center = sketch.center
  }
}

// ─── The close button ────────────────────────────────────────────────────────

/// A drawn ×, in a soft circle that gives under the finger.
final class CloseButton: UIControl {
  private let disc = CAShapeLayer()
  private let cross = CAShapeLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    for l in [disc, cross] { layer.addSublayer(l) }
    cross.fillColor = nil
    cross.lineWidth = 1.6
    cross.lineCap = .round
    accessibilityLabel = "Close"
    accessibilityTraits = .button
    isAccessibilityElement = true
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: CloseButton, _) in self.tint() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private func tint() {
    disc.fillColor = Palette.fill.resolvedColor(with: traitCollection).cgColor
    cross.strokeColor = Palette.quiet.resolvedColor(with: traitCollection).cgColor
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    tint()
    disc.frame = bounds
    disc.path = UIBezierPath(ovalIn: bounds).cgPath
    cross.frame = bounds
    let s: CGFloat = 5.5
    let c = CGPoint(x: bounds.midX, y: bounds.midY)
    let p = UIBezierPath()
    p.move(to: CGPoint(x: c.x - s, y: c.y - s))
    p.addLine(to: CGPoint(x: c.x + s, y: c.y + s))
    p.move(to: CGPoint(x: c.x + s, y: c.y - s))
    p.addLine(to: CGPoint(x: c.x - s, y: c.y + s))
    cross.path = p.cgPath
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -10, dy: -10).contains(point) }

  override var isHighlighted: Bool {
    didSet {
      UIView.animate(withDuration: isHighlighted ? 0.1 : 0.35, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
        self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
      }
    }
  }
}

// ─── The page ────────────────────────────────────────────────────────────────

/// What a topic says, set as a page: a large serif title and the line beneath
/// it between four small drawings, two either side, the paragraph that was
/// pressed, then three aspects as chips, each opening a panel below them. Laid
/// out by hand so that each piece can make its own entrance. At the foot of the
/// card, a bar to ask about the topic; questions and their answers follow on down the page.
///
/// A topic written by hand has all of this from the start. Any other paragraph
/// has a `TopicWriter` finding its title, line and drawings while the card opens:
/// the page keeps their place, so nothing moves when they come, and shows
/// `Bones` for the words if the card gets there first.
final class TopicPage: UIView, UIScrollViewDelegate {
  let scroll = UIScrollView()
  let close = CloseButton()
  /// The paragraph, drawn as it read on the page. The overlay flies it in and
  /// out; in between it rests here, at `slot`.
  let text: UIImageView
  private(set) var slot = CGRect.zero
  /// Called when something on the page starts to move, so the frame loop runs.
  var wake: (() -> Void)?
  /// The most the card around the page can show; past this, the page scrolls.
  var room: CGFloat = .greatestFiniteMagnitude

  private let topic: Topic
  private let writer: TopicWriter?
  /// The paragraph as it reads, for what the model is told about the page.
  private let paragraph: String
  private let titleBones = Bones(words: [7, 6], font: Faces.serif(TopicPage.titleSizes[0]))
  private let deckBones = Bones(words: [5, 7, 3, 6, 8, 4, 6, 5], font: Faces.serif(18, italic: true))
  /// The title's size, and the width and title it was chosen for.
  private var titleFit: (size: CGFloat, width: CGFloat, text: String)?
  /// The paragraph's type size on the page, so it can be set at a steady size here.
  private var textSize: CGFloat
  /// The small drawings, left top, right top, left bottom, right bottom.
  private let tiles: [Tile]
  private let title = UILabel()
  private let deck = UILabel()
  /// The aspects on show: the first three.
  private let aspects: [Topic.Aspect]
  private let chips: [Chip]
  private let panels: [AspectPanel]
  private let tray = UIView()
  /// How tall the tray of panels is, in points.
  private let trayH = Spring(0, response: 0.48, damping: 0.86, precision: 0.1)
  private var chosen: Int?
  /// Space above the page's content, so that a short page sits a little above
  /// the middle of a tall card instead of hugging its top.
  private var lead: CGFloat = 0

  private var drawn = false
  /// Set while the page glides to show an opened aspect.
  private var glide: Spring?

  /// Where a question is asked, and what has been asked and answered.
  let ask = AskBar()
  let talk = Talk()
  /// How far the keyboard reaches up over the page.
  private var under: CGFloat = 0
  /// Once a question is sent, the page scrolls to set it near the top, and
  /// keeps room below to stay there while its answer is written.
  private var pin: CGFloat?

  /// The pieces in the order they arrive (the text arrives on its own).
  private var cast: [UIView] { tiles + [title, deck] + chips + [tray] }

  init(_ topic: Topic?, writer: TopicWriter?, text image: UIImage, textSize: CGFloat, label: String) {
    let topic = topic ?? .blank
    self.topic = topic
    self.writer = writer
    paragraph = label
    self.textSize = textSize
    text = UIImageView(image: image)
    aspects = Array(topic.aspects.prefix(3))
    chips = aspects.map { Chip($0.title) }
    panels = aspects.map { AspectPanel($0) }
    let small = writer != nil ? Array(repeating: topic.sketch, count: TopicWriter.count) : topic.aspects.prefix(4).map(\.sketch)
    // Those on the left turn counterclockwise and those on the right the
    // other way, so that each pair rises toward the title between them.
    tiles = small.enumerated().map { i, sketch in Tile(sketch, tilt: (i % 2 == 0 ? -1 : 1) * 0.1) }
    super.init(frame: .zero)
    scroll.alwaysBounceVertical = true
    scroll.showsVerticalScrollIndicator = false
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.delegate = self
    addSubview(scroll)
    addSubview(close)

    set(title, topic.title)
    title.numberOfLines = 0
    title.accessibilityTraits = .header
    set(deck, topic.deck)
    deck.numberOfLines = 0
    text.isAccessibilityElement = true
    text.accessibilityLabel = label
    tray.clipsToBounds = true
    tray.isUserInteractionEnabled = false
    for p in panels { tray.addSubview(p) }
    for v in cast { scroll.addSubview(v) }
    // Behind the words they stand in for.
    if let writer {
      scroll.insertSubview(titleBones, belowSubview: title)
      scroll.insertSubview(deckBones, belowSubview: deck)
      writer.onChange = { [weak self] in self?.written() }
      written(animated: false)
    }
    for (i, c) in chips.enumerated() {
      c.addAction(UIAction { [weak self] _ in self?.choose(i) }, for: .touchUpInside)
    }

    scroll.addSubview(talk)
    scroll.keyboardDismissMode = .interactive
    insertSubview(ask, belowSubview: close)
    talk.brief = brief
    talk.onChange = { [weak self] in self?.setNeedsLayout() }
    talk.onBusy = { [weak self] in self?.ask.busy = $0 }
    ask.onSend = { [weak self] in self?.send($0) }
    ask.onStop = { [weak self] in self?.talk.stop() }
    ask.onResize = { [weak self] in
      guard let self else { return }
      UIView.animate(springDuration: 0.35, bounce: 0, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
        self.arrange()
        self.ask.layoutIfNeeded()
      }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    scroll.frame = bounds
    close.frame = CGRect(x: bounds.width - 16 - 36, y: 14, width: 36, height: 36)
    arrange()
  }

  /// Sets out every piece down the page.
  private func arrange() {
    let w = bounds.width
    guard w > 0 else { return }
    let pad: CGFloat = w > 600 ? 36 : 22
    let inner = w - 2 * pad
    var y: CGFloat = 52 + lead
    // Narrower labels sit centered in the column.
    func fit(_ l: UILabel, _ y: CGFloat, width: CGFloat? = nil) -> CGFloat {
      let lw = width ?? inner
      let h = l.sizeThatFits(CGSize(width: lw, height: .greatestFiniteMagnitude)).height
      place(l, CGRect(x: pad + (inner - lw) / 2, y: y, width: lw, height: h))
      return y + h
    }
    func measure(_ l: UILabel, _ width: CGFloat) -> CGFloat {
      l.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
    // The title and the line under it, stacked from `y`. For a topic being
    // written they're centered in the room kept for them, which doesn't change
    // when they come; returns where that room ends.
    func words(_ y: CGFloat, gap: CGFloat) -> CGFloat {
      let dw = min(inner, 600)
      fitTitle(inner)
      guard writer != nil else { return fit(deck, fit(title, y) + gap, width: dw) }
      // Counting the line beneath at its full room, so the title stays put when it comes.
      let told = measure(title, inner) + gap + TopicPage.deckRoom
      let room = TopicPage.kept
      _ = fit(deck, fit(title, y + (room - told) / 2) + gap, width: dw)
      placeBones(y, room, x: pad + (inner - dw) / 2, width: dw)
      return y + room
    }
    do {
      // Two small drawings either side of the title, the pair stacked from the
      // top of the page and the title set a little lower, the drawings leaning
      // in toward it. Each drawing is fitted to the same box by what it draws,
      // and the box sits in the middle of the room beside the title, so the
      // four weigh about the same and stand evenly apart. Too narrow for
      // that, the four stand in a row above the title.
      let middle = min(420, (inner * 0.46).rounded())
      let side = (inner - middle) / 2
      let tw = min(180, side - 40)
      let th = (tw * 0.6).rounded()
      let gap = (th * 0.45).rounded()
      if middle >= 280 && tw >= 110 {
        fitTitle(middle)
        let told = measure(title, middle) + 12 + (writer == nil ? measure(deck, middle) : TopicPage.deckRoom)
        let words = writer == nil ? told : TopicPage.kept
        let pair = 2 * th + gap
        // The upper pair rides above the title's first line.
        let drop = max(0, (pair - words) / 2 + th * 0.7)
        let ty = fit(title, y + drop + (words - told) / 2, width: middle)
        _ = fit(deck, ty + 12, width: middle)
        placeBones(y + drop, words, x: pad + (inner - middle) / 2, width: middle)
        for (i, t) in tiles.enumerated() {
          // The upper pair moves in over the title's corners; the lower pair
          // keeps to the middle of its side.
          let inward = i < 2 ? (tw * 0.35).rounded() : 0
          let cx = i % 2 == 0 ? pad + side / 2 + inward : pad + inner - side / 2 - inward
          place(t, CGRect(x: cx - tw / 2, y: y + CGFloat(i / 2) * (th + gap), width: tw, height: th))
        }
        y += max(pair, drop + words) + 34
      } else {
        let tw = ((inner - 3 * 16) / 4).rounded(.down)
        let rh = (tw * 0.6).rounded()
        // Left to right: the two on the left, then the two on the right.
        for (n, i) in [0, 2, 3, 1].enumerated() where i < tiles.count {
          place(tiles[i], CGRect(x: pad + CGFloat(n) * (tw + 16), y: y, width: tw, height: rh))
        }
        y += rh + 22
        y = words(y, gap: 12)
        y += 34
      }
    }
    // The paragraph keeps its own face and line breaks, scaled so its type
    // reads at 16 points whichever look it came from.
    let size = text.image?.size ?? CGSize(width: 1, height: 1)
    let tw = min(inner, size.width * 16 / max(textSize, 1)).rounded()
    slot = CGRect(x: pad + ((inner - tw) / 2).rounded(), y: y, width: tw, height: (tw * size.height / size.width).rounded())
    if docked { text.frame = slot }
    y = slot.maxY + 44

    // The chips flow in lines, each line centered.
    let gap: CGFloat = 10
    let chipH = chips.first?.intrinsicContentSize.height ?? 0
    var lines: [[Chip]] = [[]]
    var used: CGFloat = 0
    for c in chips {
      let cw = c.intrinsicContentSize.width
      if !lines[lines.count - 1].isEmpty && used + gap + cw > inner {
        lines.append([])
        used = 0
      }
      used += (lines[lines.count - 1].isEmpty ? 0 : gap) + cw
      lines[lines.count - 1].append(c)
    }
    for (n, line) in lines.enumerated() {
      let lw = line.reduce(0) { $0 + $1.intrinsicContentSize.width } + gap * CGFloat(line.count - 1)
      var x = pad + (inner - lw) / 2
      for c in line {
        let s = c.intrinsicContentSize
        place(c, CGRect(x: x, y: y, width: s.width, height: s.height))
        x += s.width + gap
      }
      if n < lines.count - 1 { y += chipH + gap }
    }
    y += chipH + 26

    // The panels keep to the paragraph's column, so their text reads at the same measure.
    let column = slot.width
    let heights = zip(panels, aspects).map { $0.measure(column, ratio: $1.sketch.size) }
    for (p, h) in zip(panels, heights) {
      p.bounds = CGRect(x: 0, y: 0, width: column, height: h)
      p.center = CGPoint(x: column / 2, y: h / 2)
    }
    trayH.target = chosen.map { Double(heights[$0]) } ?? 0
    let th = CGFloat(max(0, trayH.value))
    place(tray, CGRect(x: slot.minX, y: y, width: column, height: th))
    y += th + 36

    // What has been asked, and answered.
    if !talk.turns.isEmpty {
      let h = talk.measure(column)
      place(talk, CGRect(x: slot.minX, y: y + 8, width: column, height: h))
      y += h + 52
    }
    // The bar keeps to the paragraph's column, at the foot of the card, or
    // just above the keyboard.
    let barH = ask.height(for: column)
    let foot = under > 0 ? under + 12 : 18
    place(ask, CGRect(x: slot.minX, y: bounds.height - foot - barH, width: column, height: barH))
    let below = barH + foot + 12
    if scroll.contentInset.bottom != below {
      scroll.contentInset.bottom = below
      scroll.verticalScrollIndicatorInsets.bottom = below
    }
    scroll.contentSize = CGSize(width: w, height: max(y, (pin ?? 0) + bounds.height - below))
    // Beside the small drawings, the title keeps nearer the top. Once there
    // is a conversation, the page stays put above it.
    let want = max(0, (bounds.height - AskBar.low - 30 - (y - lead)) * 0.06).rounded()
    if talk.turns.isEmpty && abs(want - lead) > 0.5 {
      lead = want
      arrange()
    }
  }

  /// Sets out the bars in the room kept for the words, a line of title over
  /// two of the line beneath.
  private func placeBones(_ y: CGFloat, _ room: CGFloat, x: CGFloat, width: CGFloat) {
    let th = titleBones.lineHeight
    let dh = 2 * deckBones.lineHeight
    let top = y + (room - th - 12 - dh) / 2
    place(titleBones, CGRect(x: x, y: top, width: width, height: th))
    place(deckBones, CGRect(x: x, y: top + th + 12, width: width, height: dh))
  }

  /// Sets a frame without disturbing the entrance transform.
  private func place(_ v: UIView, _ f: CGRect) {
    v.bounds = CGRect(origin: .zero, size: f.size)
    v.center = CGPoint(x: f.midX, y: f.midY)
  }

  /// Shows the paragraph as the reader now sets it.
  func retext(_ image: UIImage, size: CGFloat) {
    text.image = image
    textSize = size
    setNeedsLayout()
  }

  /// Takes the flown-in paragraph to rest on the page.
  func dock() {
    text.transform = .identity
    text.layer.mask = nil
    text.layer.zPosition = 0
    scroll.addSubview(text)
    text.frame = slot
  }

  var docked: Bool { text.superview === scroll }

  // ─── Entrance ──────────────────────────────────────────────────────────

  /// Brings the pieces in as the card opens (`t` 0 → 1), one after another,
  /// each rising a little as it arrives. Leaving, they go together, early.
  func reveal(_ t: Double, leaving: Bool) {
    for (i, v) in cast.enumerated() {
      let a: Double
      if leaving {
        a = smoothstep(0.55, 0.95, t)
      } else {
        // The title and the line under it wait for the paragraph to fly past;
        // the chips come last, close on each other's heels. Small drawings
        // come in a pair at a time, top first.
        let k = i - tiles.count
        let start = k < 0 ? 0.3 + 0.08 * Double(i / 2) : [0.58, 0.64][safe: k] ?? 0.68 + 0.04 * Double(k - 2)
        a = smoothstep(start, min(1, start + 0.42), t)
      }
      v.alpha = CGFloat(a)
      let rise = leaving ? 0 : CGFloat(26 * (1 - a))
      let grow = (v is Chip || v is Tile) && !leaving ? 0.86 + 0.14 * CGFloat(a) : 1
      v.transform = CGAffineTransform(translationX: 0, y: rise).scaledBy(x: grow, y: grow)
    }
    // The bars come as the words would have.
    for (b, l) in [(titleBones, title), (deckBones, deck)] where b.superview != nil {
      b.alpha = l.alpha
      b.transform = l.transform
    }
    close.alpha = CGFloat(leaving ? smoothstep(0.6, 0.95, t) : smoothstep(0.5, 0.9, t))
    // The bar rises in last, as the card settles.
    let bar = leaving ? smoothstep(0.6, 0.95, t) : smoothstep(0.72, 1, t)
    ask.alpha = CGFloat(bar)
    ask.transform = CGAffineTransform(translationX: 0, y: leaving ? 0 : CGFloat(22 * (1 - bar)))
    if !leaving && t > 0.4 && !drawn {
      drawn = true
      for (i, tile) in tiles.enumerated() { tile.sketch.play(delay: 0.04 + 0.12 * Double(i), pace: 0.85) }
      drawIn()
    }
  }

  // ─── A topic being written ─────────────────────────────────────────────

  /// The title's sizes, largest first: it takes the largest that fits two lines.
  fileprivate static let titleSizes: [CGFloat] = [46, 40, 34, 30]
  /// The room kept for a written topic's words: two lines of title and two of the line beneath.
  private static let kept: CGFloat = (2 * Faces.serif(titleSizes[0]).lineHeight + 12 + deckRoom).rounded()
  private static let deckRoom: CGFloat = (2 * 1.25 * Faces.serif(18, italic: true).lineHeight).rounded()

  private func set(_ l: UILabel, _ s: String) {
    l.attributedText = l === title
      ? Faces.text(s, Faces.serif(titleFit?.size ?? TopicPage.titleSizes[0], weight: .regular), Palette.ink, leading: 1, tracking: -0.8, align: .center)
      : Faces.text(s, Faces.serif(18, italic: true), Palette.quiet, leading: 1.25, align: .center)
  }

  /// Sizes a written topic's title to stay within the room kept for it.
  private func fitTitle(_ width: CGFloat) {
    guard writer != nil, let s = writer?.title else { return }
    if let f = titleFit, f.width == width, f.text == s { return }
    let room = 2 * Faces.serif(TopicPage.titleSizes[0]).lineHeight + 1
    for size in TopicPage.titleSizes {
      titleFit = (size, width, s)
      set(title, s)
      if title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height <= room { break }
    }
  }

  /// Takes up whatever the writer has found since last time.
  private func written(animated: Bool = true) {
    guard let writer else { return }
    func arrive(_ l: UILabel, _ s: String?, _ bones: Bones) {
      if let s, l.attributedText?.string != s {
        UIView.performWithoutAnimation {
          set(l, s)
          setNeedsLayout()
          layoutIfNeeded()
        }
        if animated {
          // A plain fade, in place, as words come on the reader's page. Additive,
          // because the page's entrance may still be setting the label's own alpha.
          let fade = CABasicAnimation(keyPath: "opacity")
          fade.fromValue = -1
          fade.toValue = 0
          fade.isAdditive = true
          fade.duration = 0.5
          fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
          l.layer.add(fade, forKey: "arrive")
        }
      }
      if s != nil || writer.wordsSettled {
        if animated { bones.finish() } else { bones.isHidden = true }
      }
    }
    arrive(title, writer.title, titleBones)
    arrive(deck, writer.deck, deckBones)
    talk.brief = brief
    drawIn()
  }

  /// Sets the chosen drawings going, once the page has reached them and they've
  /// been chosen, whichever comes last. Each starts from its first stroke, a
  /// pair at a time as a hand-drawn topic's do.
  private func drawIn() {
    guard drawn, let writer else { return }
    let chosen = writer.drawings
    for (i, (tile, d)) in zip(tiles, chosen).enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i)) { [weak tile] in tile?.art.show(d) }
    }
  }

  /// Hands back what the page borrowed, as it goes.
  func putAway() {
    for t in tiles { t.art.putAway() }
  }

  // ─── Aspects ───────────────────────────────────────────────────────────

  private func choose(_ i: Int) {
    chosen = chosen == i ? nil : i
    for (j, c) in chips.enumerated() { c.chosen.target = chosen == j ? 1 : 0 }
    for (j, p) in panels.enumerated() {
      p.show.target = chosen == j ? 1 : 0
      // Going, a panel clears out quickly for the next one.
      p.show.response = chosen == j ? 0.5 : 0.22
    }
    UISelectionFeedbackGenerator().selectionChanged()
    arrange()
    if let i = chosen {
      // Glide so the opened panel shows, as far as it fits.
      // The card grows with the page until it fills the screen; only then does the page scroll.
      let bottom = tray.frame.minY + CGFloat(trayH.target)
      let total = bottom + 52
      let view = min(room, total)
      var goal = scroll.contentOffset.y
      if bottom - goal > view - 30 { goal = min(chips[i].frame.minY - 40, bottom - view + 30) }
      goal = min(max(0, goal), max(0, total - view))
      if abs(goal - scroll.contentOffset.y) > 1 {
        let s = Spring(Double(scroll.contentOffset.y), response: 0.62)
        s.target = Double(goal)
        glide = s
      }
    }
    wake?()
  }

  /// Advances the page's springs; returns whether anything still moves.
  func step(_ dt: Double) -> Bool {
    var moving = false
    for c in chips where !c.chosen.resting {
      c.chosen.step(dt)
      c.tint()
      moving = true
    }
    for p in panels where !p.show.resting {
      p.show.step(dt)
      p.apply()
      moving = true
    }
    if !trayH.resting {
      trayH.step(dt)
      moving = true
      arrange()
    }
    if let g = glide {
      g.step(dt)
      scroll.contentOffset.y = CGFloat(g.value)
      if g.resting { glide = nil } else { moving = true }
    }
    return moving
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { glide = nil }

  // ─── Asking ────────────────────────────────────────────────────────────

  /// Sends a question. The text leaves the field as it was set there and is
  /// carried up the page, the field's glass turning into the question's
  /// bubble around it, while the page scrolls to set it near the top; its
  /// answer starts beneath.
  private func send(_ question: String) {
    let start = ask.fieldFrame(in: self)
    let turn = talk.ask(question)
    ask.clear()
    glide = nil
    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
    arrange()
    let b = talk.convert(turn.bubble.frame, to: scroll)
    let goal = max(0, b.minY - 72)
    pin = goal
    arrange()

    let flyer = Bubble(question)
    flyer.isUserInteractionEnabled = false
    flyer.frame = start
    flyer.backgroundColor = .clear
    flyer.layer.shadowColor = UIColor.black.cgColor
    flyer.layer.shadowRadius = 14
    flyer.layer.shadowOffset = CGSize(width: 0, height: 6)
    insertSubview(flyer, belowSubview: ask)
    let calm = UIAccessibility.isReduceMotionEnabled
    // On its way up it is lifted a little toward the eye, shadow and all,
    // and set down as it arrives.
    UIView.animateKeyframes(withDuration: calm ? 0 : 0.5, delay: 0, options: [.calculationModeCubic]) {
      UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.45) {
        flyer.layer.shadowOpacity = 0.12
      }
      UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
        flyer.layer.shadowOpacity = 0
      }
    }
    UIView.animate(
      springDuration: calm ? 0 : 0.62, bounce: 0.2, initialSpringVelocity: 0, delay: 0,
      options: [.allowUserInteraction]
    ) {
      self.scroll.contentOffset.y = goal
      flyer.frame = CGRect(x: b.minX, y: b.minY - goal, width: b.width, height: b.height)
      flyer.backgroundColor = Palette.fill
    } completion: { _ in
      turn.bubble.alpha = 1
      flyer.removeFromSuperview()
    }
    UIView.animate(withDuration: 0.4, delay: calm ? 0 : 0.35, options: [.curveEaseOut, .allowUserInteraction]) {
      turn.answer.alpha = 1
    }
  }

  /// Keeps the bar above the keyboard, moving with it.
  @objc private func keyboard(_ n: Notification) {
    guard let info = n.userInfo, let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, let window else { return }
    var reach: CGFloat = 0
    // A floating keyboard leaves the page as it is.
    if !end.isEmpty {
      let screen = (n.object as? UIScreen) ?? window.screen
      reach = max(0, bounds.maxY - screen.coordinateSpace.convert(end, to: self).minY)
    }
    guard abs(reach - under) > 0.5 else { return }
    under = reach
    let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
    UIView.animate(withDuration: duration, delay: 0, options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState]) {
      self.arrange()
      self.ask.layoutIfNeeded()
    }
  }

  /// What the model is told about the page it is asked from.
  private var brief: String {
    let name = writer?.title ?? topic.title
    let line = writer?.deck ?? topic.deck
    let head = name.isEmpty ? "" : "Topic: \(name). \(line)\n\n"
    let aspects = topic.aspects.prefix(3).map { "- \($0.title): \($0.body)" }.joined(separator: "\n")
    let says = aspects.isEmpty ? "" : "What the page says about it:\n\(aspects)\n\n"
    return """
      You are a patient, exact tutor inside Aube Reader, an iPad app for reading. \
      The reader has long-pressed a paragraph to look closer at its topic, and is asking you about it.

      \(head)The paragraph:
      \(paragraph)

      \(says)Answer the question itself, plainly and briefly: a short paragraph or two unless more is asked for. \
      Write in Markdown. Put mathematics in LaTeX, $…$ inline and $$…$$ on lines of their own for an \
      equation worth showing. Keep the LaTeX simple (fractions, roots, sub- and superscripts, Greek \
      letters), with no environments, and use no tables.
      """
  }

  /// Whether the page is scrolled to its top, so a pull down should move the card instead.
  var atTop: Bool { scroll.contentOffset.y <= 0.5 }
}
