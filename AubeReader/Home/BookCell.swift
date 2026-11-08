import UIKit

/// A book in the library.
final class BookCell: UICollectionViewCell {
  let book = BookView()
  var spec: BookSpec?
  private var slip: StatusSlip { book.slip }
  private var isCurrent = false
  private var stage: ImportEntry.Stage?
  private var stamp: UIImage?

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(book)
    isAccessibilityElement = true
    accessibilityTraits = .button
    addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// `stamp`: its drawing, as ink only; nil until it's come. `current`: it's the one read last.
  func set(_ d: Document, stamp: UIImage?, current: Bool) {
    isCurrent = current
    self.stamp = stamp
    accessibilityLabel = d.authors.isEmpty ? d.title : "\(d.title), by \(LibraryFace.authors(d.authors))"
    showStatus(of: d.id)
    dress()
  }

  private func dress() {
    guard let spec else { return }
    book.dress(spec, faces: BookArt.faces(spec, stamp: stamp, status: stage), current: isCurrent)
  }

  /// A drawing that has just come.
  func show(stamp: UIImage?) {
    guard stamp !== self.stamp else { return }
    self.stamp = stamp
    UIView.transition(with: book, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.dress() }
  }

  /// Shows what's happening to a document on its way in, if anything is.
  func showStatus(of id: String) {
    let status = ImportStatus(id)
    slip.show(status)
    accessibilityValue = status.said
    if status.stage != stage {
      stage = status.stage
      if spec?.design == .parcel { dress() }
    }
    setNeedsLayout()
  }

  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      book.press(isHighlighted)
    }
  }

  @objc private func hovered(_ g: UIHoverGestureRecognizer) {
    switch g.state {
    case .began, .changed: book.hovered = !UIAccessibility.isReduceMotionEnabled
    default: book.hovered = false
    }
  }

  /// What a page zooms out of and back onto.
  var sheetView: UIView { book }
  /// The cover, to swing open as the page zooms out.
  var cover: CoverFaces? {
    guard let spec, let front = book.coverImage else { return nil }
    return CoverFaces(front: front, inside: BookArt.inside(spec))
  }
  /// Takes the cover away, while a copy of it travels.
  func lift(_ lifted: Bool) { book.lift(lifted) }
  /// What lifts when pressed and held, and its outline.
  var preview: (view: UIView, outline: UIBezierPath)? {
    (book, UIBezierPath(roundedRect: book.bounds, cornerRadius: 2.6))
  }

  /// The light moved, or the cell did.
  func reposition(in collection: UICollectionView) {
    let origin = collection.bounds.origin
    let centre = CGPoint(x: center.x - origin.x, y: center.y - origin.y)
    let viewport = collection.bounds.size
    book.reposition(centre: centre, vanish: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport, tilt: Tilt.shared.value)
  }

  override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
    super.apply(layoutAttributes)
    if let a = layoutAttributes as? CarouselAttributes { book.pose(angle: a.angle, depth: a.depth) }
    if let c = superview as? UICollectionView { reposition(in: c) }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if let c = superview as? UICollectionView { reposition(in: c) }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    book.frame = contentView.bounds
    if let c = superview as? UICollectionView { reposition(in: c) }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    book.lift(false)
    book.hovered = false
    stage = nil
  }
}
