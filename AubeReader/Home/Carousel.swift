import UIKit

// ─── Carousel ────────────────────────────────────────────────────────────────

/// One book at a time, big and front and centre, the others turned away to
/// either side, standing on a timber panel. A swipe scrubs through them. Every book's pose
/// follows from its distance from the centre by smooth curves alone, with no
/// animation of its own, so it's exactly as fluid as the finger.
@MainActor
final class Carousel {
  private unowned let host: LibraryViewController
  private let collection: UICollectionView
  let layout = CarouselLayout()
  private let caption = UIView()
  private let name = UILabel()
  private let byline = UILabel()
  private let tick = UISelectionFeedbackGenerator()
  private var bookSpecs: [String: BookSpec] = [:]
  private var specUnit: CGFloat = 0
  private var plan: [String: BookSpec.Choice] = [:]
  private var planned = ""
  /// The book at the centre, kept through a change of size.
  private var centred = 0
  private var placed = false
  private var captioned: String?
  private var warming = false

  init(host: LibraryViewController, collection: UICollectionView) {
    self.host = host
    self.collection = collection
    layout.size = { [weak self] path, unit in
      guard let self, let d = self.host.document(at: path) else { return nil }
      return self.spec(d, unit: unit).shownSize
    }
    name.font = .systemFont(ofSize: 20, weight: .semibold)
    name.textColor = Self.gilt
    name.textAlignment = .center
    name.numberOfLines = 2
    byline.font = .systemFont(ofSize: 14)
    byline.numberOfLines = 0
    byline.textColor = Self.gilt.withAlphaComponent(0.72)
    byline.textAlignment = .center
    caption.addSubview(name)
    caption.addSubview(byline)
    caption.isUserInteractionEnabled = false
  }

  /// The caption's ink, as the bar's, over the timber.
  private static let gilt = UIColor(hex: 0xf0e2c4)

  private func spec(_ d: Document, unit: CGFloat) -> BookSpec {
    if unit != specUnit {
      bookSpecs = [:]
      specUnit = unit
    }
    let order = host.allDocuments.map(\.id).joined(separator: "/")
    if order != planned {
      planned = order
      plan = BookSpec.plan(host.allDocuments.map(\.id))
      bookSpecs = [:]
    }
    let openable = d.openable
    let key = d.id + (openable ? "" : "/parcel")
    if let s = bookSpecs[key], s.title == d.title { return s }
    // Bound at a book's usual size, then enlarged whole, lettering and all.
    let bound: CGFloat = 152
    var s = BookSpec(d, unit: bound, openable: openable, choice: plan[d.id])
    s.magnified = unit / bound
    bookSpecs[key] = s
    return s
  }

  /// Sets up the collection view, and puts the caption over it.
  func install() {
    let c = collection
    c.alwaysBounceVertical = false
    c.alwaysBounceHorizontal = true
    c.decelerationRate = .fast
    c.showsHorizontalScrollIndicator = false
    c.showsVerticalScrollIndicator = false
    // The panel's moulding stays along the foot of the screen, and the books stand clear of it.
    c.contentInset.bottom = TimberPanel.cornice
    host.view.insertSubview(caption, aboveSubview: c)
    laidOut()
  }

  func cell(at path: IndexPath, for d: Document) -> BookCell {
    let cell = collection.dequeueReusableCell(withReuseIdentifier: "book", for: path) as! BookCell
    cell.spec = spec(d, unit: layout.metrics.unit)
    return cell
  }

  /// The host's view changed size.
  func laidOut() {
    let c = collection
    layout.invalidateLayout()
    c.layoutIfNeeded()
    let m = layout.metrics
    c.contentOffset = CGPoint(x: CGFloat(centred) * m.step, y: -c.adjustedContentInset.top)
    let top = c.adjustedContentInset.top + m.floor + 30
    caption.frame = CGRect(x: 40, y: top, width: host.view.bounds.width - 80, height: 120)
    place()
    scrolled()
  }

  /// What's shown changed.
  func refreshed() {
    let c = collection
    c.layoutIfNeeded()
    let count = c.numberOfSections > 0 ? c.numberOfItems(inSection: 0) : 0
    // The first time up, on the book read last.
    if !placed, count > 0 {
      placed = true
      if let i = (0..<count).first(where: { host.document(at: IndexPath(item: $0, section: 0))?.id == Store.lastDocument }) {
        centred = i
        c.contentOffset.x = CGFloat(i) * layout.metrics.step
      }
    }
    if centred >= count, count > 0 {
      centred = count - 1
      c.contentOffset.x = CGFloat(centred) * layout.metrics.step
    }
    captioned = nil
    scrolled()
    warm()
  }

  /// The collection view scrolled, or was laid out afresh.
  func scrolled() {
    let c = collection
    let step = max(1, layout.metrics.step)
    let at = c.contentOffset.x / step
    let count = c.numberOfSections > 0 ? c.numberOfItems(inSection: 0) : 0
    guard count > 0 else {
      caption.alpha = 0
      return
    }
    let nearest = min(count - 1, max(0, Int(at.rounded())))
    if nearest != centred {
      centred = nearest
      if c.isTracking || c.isDecelerating { tick.selectionChanged() }
    }
    // The caption fades out halfway to the next book and back in on it.
    caption.alpha = 1 - min(1, abs(at - CGFloat(nearest)) * 2.4)
    if let d = host.document(at: IndexPath(item: nearest, section: 0)), captioned != d.id {
      captioned = d.id
      name.text = d.title
      byline.text = Face.authors(d.authors)
      place()
    }
  }

  private func place() {
    let w = caption.bounds.width
    let h = name.sizeThatFits(CGSize(width: w, height: 60)).height
    name.frame = CGRect(x: 0, y: 0, width: w, height: h)
    // The authors wrap rather than run wide.
    let bw = min(w, 300)
    let bh = byline.sizeThatFits(CGSize(width: bw, height: 60)).height
    byline.frame = CGRect(x: ((w - bw) / 2).rounded(), y: h + 3, width: bw, height: bh)
  }

  /// Brings the book at `path` to the centre, at once.
  func bring(_ path: IndexPath) {
    centred = path.item
    collection.contentOffset.x = CGFloat(path.item) * layout.metrics.step
    scrolled()
  }

  /// A book at the side comes to the centre, rather than opening.
  func tapped(_ path: IndexPath) -> Bool {
    let c = collection
    guard path.item != centred else { return false }
    c.setContentOffset(CGPoint(x: CGFloat(path.item) * layout.metrics.step, y: c.contentOffset.y), animated: true)
    return true
  }

  /// A fling comes to rest with a book exactly at the centre.
  func rest(for proposed: CGPoint, velocity: CGPoint) -> CGPoint {
    let step = max(1, layout.metrics.step)
    let speed = abs(velocity.x)
    // A nudge settles on the nearest book, a flick moves on by one, and only a hard fling goes further.
    let moved = speed < 0.3 ? 0 : speed < 2 ? 1 : speed < 3.5 ? 2 : 3
    let sign = velocity.x > 0 ? 1 : -1
    var to = proposed
    to.x = CGFloat(centred + sign * moved) * step
    to.x = min(max(0, to.x), max(0, collection.contentSize.width - collection.bounds.width))
    return to
  }

  /// Whether the library is on screen, to stop anything that moves on its own while it isn't.
  func awake(_ awake: Bool) {
    if awake {
      Tilt.shared.start()
      tick.prepare()
    } else {
      Tilt.shared.stop()
    }
  }

  // ─── Covers ready before they're needed ──────────────────────────────────

  /// Paints covers ahead of time, nearest first, one at a time and only while
  /// nothing's moving, so a swipe never has to wait for one.
  private func warm() {
    guard !warming else { return }
    warming = true
    warmNext()
  }

  private func warmNext() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
      guard let self else { return }
      let c = self.collection
      if self.host.busy || !self.host.awake {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.warmNext() }
        return
      }
      let count = c.numberOfSections > 0 ? c.numberOfItems(inSection: 0) : 0
      let order = (0..<count).sorted { abs($0 - self.centred) < abs($1 - self.centred) }
      for i in order {
        guard let d = self.host.document(at: IndexPath(item: i, section: 0)), d.openable else { continue }
        let spec = self.spec(d, unit: self.layout.metrics.unit)
        guard let stamp = Icons.shared.stamp(for: d.title), !BookArt.hasFaces(spec, stamp: stamp) else { continue }
        _ = BookArt.faces(spec, stamp: stamp)
        self.warmNext()
        return
      }
      self.warming = false
    }
  }
}

// ─── The layout ──────────────────────────────────────────────────────────────

struct CarouselMetrics {
  /// How wide a book usually is.
  let unit: CGFloat
  /// How far a swipe travels from one book to the next.
  let step: CGFloat
  /// Where the books stand, from the top of the content.
  let floor: CGFloat
  /// How far out a book's centre lies at a distance of one, past what the curves add.
  let spread: CGFloat
  let push: CGFloat

  init(size: CGSize) {
    let room = max(200, size.height)
    // Room for the caption, less of it where height is short (a phone on its side) and the caption has the width to itself.
    let caption = min(130, max(60, room - 300))
    unit = min(420, (size.width * 0.46).rounded(), ((room - caption) * 0.82 / BookView.tallest).rounded())
    step = (unit * 0.62).rounded()
    floor = (room / 2 + unit * BookView.tallest / 2 - 40).rounded()
    spread = unit * 0.3
    push = unit * 0.62
  }

  /// `p`: how many books from the centre, in fractions. Smooth everywhere, so nothing catches as a book passes through.
  static func turned(_ p: CGFloat) -> CGFloat { tanh(p * 1.7) }
  func x(_ p: CGFloat) -> CGFloat { p * spread + Self.turned(p) * push }
  func angle(_ p: CGFloat) -> CGFloat { -Self.turned(p) * 62 * .pi / 180 }
  func depth(_ p: CGFloat) -> CGFloat {
    let t = Self.turned(p)
    return -(t * t * unit * 0.62 + (sqrt(p * p + 1) - 1) * unit * 0.1)
  }
}

final class CarouselAttributes: UICollectionViewLayoutAttributes {
  var angle: CGFloat = 0
  var depth: CGFloat = 0

  override func copy(with zone: NSZone? = nil) -> Any {
    let a = super.copy(with: zone) as! CarouselAttributes
    a.angle = angle
    a.depth = depth
    return a
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let o = object as? CarouselAttributes, o.angle == angle, o.depth == depth else { return false }
    return super.isEqual(object)
  }
}

final class CarouselLayout: UICollectionViewLayout {
  override class var layoutAttributesClass: AnyClass { CarouselAttributes.self }

  var size: ((IndexPath, CGFloat) -> CGSize?)?
  private(set) var metrics = CarouselMetrics(size: CGSize(width: 800, height: 800))
  private var sizes: [CGSize] = []
  private var room: CGSize = .zero
  /// How many books either side stay laid out, so they're dressed well before they show.
  private static let reach = 9

  override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
    if context.invalidateEverything || context.invalidateDataSourceCounts { sizes = [] }
    super.invalidateLayout(with: context)
  }

  override func prepare() {
    super.prepare()
    guard let c = collectionView else { return }
    let inset = c.adjustedContentInset
    let now = CGSize(width: c.bounds.width, height: c.bounds.height - inset.top - inset.bottom)
    if now != room {
      room = now
      metrics = CarouselMetrics(size: now)
      sizes = []
    }
    let count = c.numberOfSections > 0 ? c.numberOfItems(inSection: 0) : 0
    if sizes.count != count {
      sizes = (0..<count).map { size?(IndexPath(item: $0, section: 0), metrics.unit) ?? CGSize(width: metrics.unit, height: metrics.unit * 1.42) }
    }
  }

  override var collectionViewContentSize: CGSize {
    guard !sizes.isEmpty else { return room }
    return CGSize(width: CGFloat(sizes.count - 1) * metrics.step + room.width, height: room.height)
  }

  // Every frame of a swipe lays out again: only what's near, from what's already worked out.
  override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    guard let c = collectionView, !sizes.isEmpty else { return [] }
    let at = Int((c.bounds.minX / max(1, metrics.step)).rounded())
    let low = max(0, at - Self.reach)
    let high = min(sizes.count - 1, at + Self.reach)
    guard low <= high else { return [] }
    return (low...high).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
  }

  override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    guard let c = collectionView, indexPath.item < sizes.count else { return nil }
    let a = CarouselAttributes(forCellWith: indexPath)
    let s = sizes[indexPath.item]
    let p = (CGFloat(indexPath.item) * metrics.step - c.bounds.minX) / max(1, metrics.step)
    a.size = s
    a.center = CGPoint(x: c.bounds.minX + c.bounds.width / 2 + metrics.x(p), y: metrics.floor - s.height / 2)
    a.angle = metrics.angle(p)
    a.depth = metrics.depth(p)
    a.zIndex = 10_000 - Int(abs(p) * 100)
    return a
  }

  override func targetContentOffset(forProposedContentOffset proposed: CGPoint) -> CGPoint {
    var to = proposed
    to.x = (proposed.x / max(1, metrics.step)).rounded() * metrics.step
    return to
  }
}
