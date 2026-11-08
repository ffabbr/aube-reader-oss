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
final class ContentsTip: GlassTip, UITableViewDataSource, UITableViewDelegate {
  private static let margin: CGFloat = 12
  private static let widest: CGFloat = 360
  /// From the ring to the edges of the glass, and the glass around it before it opens.
  private static let edge: CGFloat = 12
  private static let hug: CGFloat = 6
  /// From the rows to the top of the glass and the foot of the list.
  private static let padding = UIEdgeInsets(top: 10, left: 0, bottom: 2, right: 0)
  private static let side: CGFloat = 18
  private static let indent: CGFloat = 14
  private static let pageColumn: CGFloat = 40
  private static let textSize: CGFloat = 15
  /// Up to two lines, with this much above and below them.
  private static let rowPadding: CGFloat = 10
  private static let shortestRow: CGFloat = 40
  /// Up a beat after it reaches across, running a hair past.
  private static let timing = Timing(
    across: 0.44, reach: 0.5, lag: 0.05, reachEase: Ease(0.36, 0, 0.16, 1.02),
    back: 0.32, inward: 0.36, closeLag: 0.04, fadeAt: 0.28)

  var onPick: ((ContentsRow) -> Void)?
  var onEscape: (() -> Void)?

  private let rows: [ContentsRow]
  private let current: Int?
  private let heights: [CGFloat]
  /// Everything on the glass, held where it rests on the screen whatever the glass is doing.
  private let sheet = UIView()
  private let list = UITableView(frame: .zero, style: .plain)
  private let holder = UIView()
  private let edges = CAGradientLayer()
  private let dial = PageRing()
  private let place = UILabel()
  private let ring: CGRect

  /// The contents `rows`, with `current` being read, for the ring at `ring` in `host` saying `spot`.
  init(rows: [ContentsRow], current: Int?, spot: (progress: Double?, page: Int, of: Int), ring: CGRect, host: UIView) {
    self.rows = rows
    self.current = current
    self.ring = ring

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
    let rest = CGRect(x: left, y: bottom - height, width: width, height: height)
    let start = ring.insetBy(dx: -Self.hug, dy: -Self.hug)

    // More of the page lies under the glass than under a note: a list has less to hold on to than a sentence.
    super.init(
      start: start, rest: rest, keepOut: ring.insetBy(dx: -12, dy: -12), host: host, timing: Self.timing,
      shadowRadius: 26, shadowOpacity: (light: 0.16, dark: 0.45), backing: (light: 0.3, dark: 0.42))

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

  // ─── Shape ───────────────────────────────────────────────────────────────

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

  /// Keeps the rows and the ring where they are on the screen, whatever the glass does around them.
  override func arrange(on frame: CGRect) {
    sheet.frame = rest.offsetBy(dx: -frame.minX, dy: -frame.minY)
  }

  override func reveal(across: Double, reached: Double) {
    holder.alpha = CGFloat(smoothstep(0.3, 0.8, reached))
    place.alpha = CGFloat(smoothstep(0.3, 0.8, across))
  }

  override func open() {
    super.open()
    UIAccessibility.post(notification: .screenChanged, argument: list)
  }

  // ─── Touches ─────────────────────────────────────────────────────────────

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
