import UIKit

/// A line of the contents, and where it leads.
struct ContentsRow {
  enum Place {
    case entry(Entry)
    /// The top of a page of the original, for a text with no headings to go by.
    case page(Int)
  }

  let title: String
  /// How many steps in from the margin it's set.
  let depth: Int
  /// The page of the original it's on, counting from 0, where the text has pages.
  let page: Int?
  let place: Place
}

/// The table of contents, opened out of the ring in the corner. As a footnote does
/// from its mark (see `NoteTip`), one shape of Liquid Glass starts out around the
/// ring and stretches from there, across and then up a beat later, into a sheet in
/// the corner. The ring stays put at its foot, with the page beside it, and the rows
/// stand still as the glass reaches them.
///
/// Only the rows take touches. Everything else reaches the page, which puts the
/// contents away, the ring included (see `DeskViewController`).
final class ContentsTip: UIView, UITableViewDataSource, UITableViewDelegate {
  private static let margin: CGFloat = 12
  private static let widest: CGFloat = 360
  /// From the ring to the edges of the glass, and the glass around it before it opens.
  private static let edge: CGFloat = 12
  private static let hug: CGFloat = 6
  private static let corner: CGFloat = 22
  /// From the rows to the top of the glass and the foot of the list.
  private static let padding = UIEdgeInsets(top: 10, left: 0, bottom: 2, right: 0)
  private static let side: CGFloat = 18
  private static let indent: CGFloat = 14
  private static let pageColumn: CGFloat = 40
  private static let textSize: CGFloat = 15
  /// Up to two lines, with this much above and below them.
  private static let rowPadding: CGFloat = 10
  private static let shortestRow: CGFloat = 40

  var onPick: ((ContentsRow) -> Void)?
  var onEscape: (() -> Void)?

  private let rows: [ContentsRow]
  private let current: Int?
  private let heights: [CGFloat]
  /// Under the glass: a little of the page, so the words under it don't compete with its own.
  private let backing = UIView()
  /// Around the glass, not under it: a shadow would darken what's meant to be seen through.
  private let shade = CALayer()
  private let shadeCut = CAShapeLayer()
  private let body = UIVisualEffectView()
  /// Everything on the glass, held where it rests on the screen whatever the glass is doing.
  private let sheet = UIView()
  private let list = UITableView(frame: .zero, style: .plain)
  private let holder = UIView()
  private let edges = CAGradientLayer()
  private let dial = PageRing()
  private let place = UILabel()
  private let ring: CGRect
  private let start: CGRect
  private let rest: CGRect
  private let calm = UIAccessibility.isReduceMotionEnabled
  /// How far the glass has reached, from around the ring (0) to where it rests (1), across and up.
  private let wide = Tween(0)
  private let tall = Tween(0)
  private var link: CADisplayLink?
  private var last = 0.0
  private var leaving = false

  /// The contents `rows`, with `current` being read, for the ring at `ring` in `host` saying `spot`.
  init(rows: [ContentsRow], current: Int?, spot: (progress: Double?, page: Int, of: Int), ring: CGRect, host: UIView) {
    self.rows = rows
    self.current = current
    self.ring = ring
    start = ring.insetBy(dx: -Self.hug, dy: -Self.hug)

    let left = ring.minX - Self.edge
    let bottom = ring.maxY + Self.edge
    let foot = ring.height + 2 * Self.edge
    let width = min(Self.widest, host.bounds.width - left - Self.margin)
    let paged = rows.contains { $0.page != nil }
    let measured = rows.map { Self.height(of: $0, width: width, paged: paged) }
    heights = measured
    let wanted = measured.reduce(0, +) + Self.padding.top + Self.padding.bottom + foot
    let room = min(bottom - Self.margin - host.safeAreaInsets.top, max(host.bounds.height * 0.66, 240))
    let height = ceil(min(wanted, room))
    rest = CGRect(x: left, y: bottom - height, width: width, height: height)

    super.init(frame: host.bounds)
    autoresizingMask = [.flexibleWidth, .flexibleHeight]

    shade.frame = bounds
    shade.shadowColor = UIColor.black.cgColor
    shade.shadowOffset = CGSize(width: 0, height: 8)
    shade.shadowRadius = 26
    shade.shadowOpacity = host.traitCollection.userInterfaceStyle == .dark ? 0.45 : 0.16
    shade.opacity = 0
    shadeCut.frame = bounds
    shadeCut.fillRule = .evenOdd
    shade.mask = shadeCut
    layer.addSublayer(shade)

    backing.frame = start
    backing.backgroundColor = Self.backingColor
    backing.alpha = 0
    backing.layer.cornerCurve = .continuous
    backing.layer.cornerRadius = start.height / 2
    addSubview(backing)

    body.frame = start
    NoteTip.round(body, start.height / 2)
    addSubview(body)
    body.contentView.clipsToBounds = true
    body.contentView.layer.cornerCurve = .continuous
    body.contentView.layer.cornerRadius = start.height / 2

    sheet.bounds = CGRect(origin: .zero, size: rest.size)
    sheet.frame = rest.offsetBy(dx: -start.minX, dy: -start.minY)
    body.contentView.addSubview(sheet)

    // The list, fading out at either edge as it runs past them.
    holder.frame = CGRect(x: 0, y: 0, width: width, height: height - foot)
    holder.alpha = 0
    edges.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    let fade = NSNumber(value: Double(min(14 / max(holder.bounds.height, 1), 0.2)))
    edges.locations = [0, fade, NSNumber(value: 1 - fade.doubleValue), 1]
    edges.frame = holder.bounds
    holder.layer.mask = edges
    sheet.addSubview(holder)

    list.frame = holder.bounds
    list.backgroundColor = .clear
    list.separatorStyle = .none
    list.showsVerticalScrollIndicator = false
    list.contentInsetAdjustmentBehavior = .never
    list.contentInset = Self.padding
    list.alwaysBounceVertical = wanted > room
    list.dataSource = self
    list.delegate = self
    list.register(Row.self, forCellReuseIdentifier: Row.reuse)
    holder.addSubview(list)
    // The first thing seen is the row being read.
    list.layoutIfNeeded()
    list.contentOffset.y = -Self.padding.top
    if wanted > room, let current {
      let mid = measured[..<current].reduce(0, +) + measured[current] / 2 - holder.bounds.height / 2
      let most = measured.reduce(0, +) + Self.padding.bottom - holder.bounds.height
      list.contentOffset.y = max(-Self.padding.top, min(mid, most))
    }

    // The ring itself, drawn over itself, so that nothing changes as the glass takes over.
    dial.isUserInteractionEnabled = false
    dial.alpha = 1
    dial.center = CGPoint(x: ring.midX - rest.minX, y: ring.midY - rest.minY)
    dial.set(progress: spot.progress, page: spot.page, of: spot.of)
    sheet.addSubview(dial)

    place.text = spot.of > 1 ? "Page \(spot.page + 1) of \(spot.of)" : nil
    place.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    place.textColor = Palette.quiet
    place.alpha = 0
    let x = ring.maxX - rest.minX + 10
    place.frame = CGRect(x: x, y: height - foot, width: width - x - Self.side, height: foot)
    sheet.addSubview(place)

    accessibilityViewIsModal = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  // ─── Shape ───────────────────────────────────────────────────────────────

  /// More of the page under the glass than a note has: a list has less to hold on to than a sentence.
  private static let backingColor = UIColor { traits in
    Palette.page.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.42 : 0.3)
  }

  private static func font(current: Bool) -> UIFont { .systemFont(ofSize: textSize, weight: current ? .semibold : .regular) }

  /// How tall a row is, in a sheet `width` across: measured in the heavier weight, so being current never takes another line.
  private static func height(of row: ContentsRow, width: CGFloat, paged: Bool) -> CGFloat {
    let w = width - 2 * side - CGFloat(row.depth) * indent - (paged ? pageColumn : 0)
    let font = font(current: true)
    let tall = (row.title as NSString).boundingRect(
      with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
    ).height
    return max(shortestRow, ceil(min(tall, font.lineHeight * 2)) + 2 * rowPadding)
  }

  /// Puts everything as it is with the glass over `frame`, keeping the rows and the ring where they are on the screen.
  private func shape(_ frame: CGRect, radius: CGFloat) {
    body.frame = frame
    backing.frame = frame
    NoteTip.round(body, radius)
    body.contentView.layer.cornerRadius = radius
    backing.layer.cornerRadius = radius
    sheet.frame = rest.offsetBy(dx: -frame.minX, dy: -frame.minY)
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
    let reached = min(w, h)
    backing.alpha = CGFloat(smoothstep(0, 0.6, reached))
    holder.alpha = CGFloat(smoothstep(0.3, 0.8, reached))
    place.alpha = CGFloat(smoothstep(0.3, 0.8, w))
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
    if leaving { removeFromSuperview() }
  }

  // ─── Coming and going ────────────────────────────────────────────────────

  /// Soft away from the ring, with a long landing; up a beat later, running a hair past.
  private static let across = Ease(0.3, 0, 0.14, 1)
  private static let upward = Ease(0.36, 0, 0.16, 1.02)

  func open() {
    defer { UIAccessibility.post(notification: .screenChanged, argument: list) }
    guard !calm else {
      wide.to(1, over: 0.001, Ease.rise, now: 0)
      tall.to(1, over: 0.001, Ease.rise, now: 0)
      wide.step(1, 0)
      tall.step(1, 0)
      step()
      alpha = 0
      body.effect = NoteTip.material()
      UIView.animate(withDuration: 0.2) { self.alpha = 1 }
      return
    }
    let now = CACurrentMediaTime()
    wide.to(1, over: 0.44, Self.across, now: now)
    tall.to(1, over: 0.5, after: 0.05, Self.upward, now: now)
    step()
    run()
    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { self.body.effect = NoteTip.material() }
  }

  /// Draws back into the ring, and goes. `quickly` for when the page itself is on its way somewhere.
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
    // Down first, then in: the way it came, from wherever it had got to.
    tall.to(0, over: 0.32, Ease.fold, now: now)
    wide.to(0, over: 0.36, after: 0.04, Ease.fold, now: now)
    run()
    // The glass gives way to the ring on the page just as it gets there.
    UIView.animate(withDuration: 0.14, delay: 0.28, options: [.curveEaseOut]) { self.body.effect = nil }
  }

  // ─── Touches ─────────────────────────────────────────────────────────────

  /// Whether a point is the contents' own, and not for the page. The ring is the page's: tapped, it puts them away.
  private func owns(_ point: CGPoint) -> Bool { rest.contains(point) && !ring.insetBy(dx: -12, dy: -12).contains(point) }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, owns(point) else { return nil }
    return super.hitTest(point, with: event) ?? self
  }

  /// Whether a touch is the contents' own, and not for the page under it.
  func holds(_ touch: UITouch) -> Bool { owns(touch.location(in: self)) }

  override func accessibilityPerformEscape() -> Bool {
    onEscape?()
    return true
  }

  // ─── The rows ────────────────────────────────────────────────────────────

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { heights[indexPath.row] }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: Row.reuse, for: indexPath) as! Row
    let paged = rows.contains { $0.page != nil }
    cell.show(rows[indexPath.row], current: indexPath.row == current, pageColumn: paged ? Self.pageColumn : 0)
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    onPick?(rows[indexPath.row])
  }

  private final class Row: UITableViewCell {
    static let reuse = "row"
    private let title = UILabel()
    private let page = UILabel()
    private var inset: CGFloat = 0
    private var column: CGFloat = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
      super.init(style: style, reuseIdentifier: reuseIdentifier)
      backgroundColor = .clear
      contentView.backgroundColor = .clear
      let pressed = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
      let fill = UIView()
      fill.backgroundColor = Palette.ink.withAlphaComponent(0.09)
      fill.layer.cornerRadius = 12
      fill.layer.cornerCurve = .continuous
      fill.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      pressed.addSubview(fill)
      fill.frame = pressed.bounds.inset(by: UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6))
      selectedBackgroundView = pressed
      title.numberOfLines = 2
      title.lineBreakMode = .byTruncatingTail
      page.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
      page.textColor = Palette.muted
      page.textAlignment = .right
      contentView.addSubview(title)
      contentView.addSubview(page)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ row: ContentsRow, current: Bool, pageColumn: CGFloat) {
      title.text = row.title
      title.font = ContentsTip.font(current: current)
      title.textColor = current ? Palette.ink : Palette.quiet
      page.text = row.page.map { String($0 + 1) }
      inset = CGFloat(row.depth) * ContentsTip.indent
      column = pageColumn
      accessibilityLabel = row.page.map { "\(row.title), page \($0 + 1)" } ?? row.title
      accessibilityTraits = current ? [.button, .selected] : .button
      setNeedsLayout()
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      let b = contentView.bounds
      let left = ContentsTip.side + inset
      title.frame = CGRect(x: left, y: 0, width: b.width - left - ContentsTip.side - column, height: b.height)
      page.frame = CGRect(x: b.width - ContentsTip.side - column, y: 0, width: column, height: b.height)
    }
  }
}
