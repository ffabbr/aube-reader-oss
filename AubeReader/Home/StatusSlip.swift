import UIKit

// ─── What's said of a document on its way in ─────────────────────────────────

/// How far along a document being brought in has got.
struct ImportStatus {
  /// What to say, or nil once there's nothing to say.
  var said: String?
  /// Whether `share` means anything.
  var moving = false
  var share: CGFloat = 0
  var stage: ImportEntry.Stage?

  @MainActor init(_ id: String) {
    let entry = Imports.shared.entry(id)
    let progress = Imports.shared.progress[id]
    stage = entry?.stage
    switch entry?.stage {
    case .queued: said = "Waiting"
    case .reading: said = progress?.said ?? "Reading"
    case .understanding: said = "Understanding"
    case .checking: said = progress?.said ?? "Checking"
    case .locked: said = "Locked: tap to open"
    case .failed: said = "Couldn’t be read"
    case .done, nil: said = nil
    }
    moving = entry?.stage == .reading || entry?.stage == .checking
    share = CGFloat(progress?.done ?? 0)
  }
}

/// A slip of paper tucked across something: what's being done to a document, and how far along it is.
/// A layer rather than a view, so it can sit in a book's 3D space and turn and lean with its cover.
final class StatusSlip: StillLayer {
  private let words = StillLayer()
  private let track = StillLayer()
  private let fill = StillLayer()
  private var said: String?
  private var moving = false
  private var share: CGFloat = 0
  /// What `words` was last drawn for, to draw it again only when that changes.
  private var drawn: (said: String, size: CGSize, scale: CGFloat)?
  /// The pixel density to draw the words at.
  var scale: CGFloat = 2 {
    didSet { if scale != oldValue { setNeedsLayout() } }
  }

  override init() {
    super.init()
    backgroundColor = UIColor(hex: 0xf6f0e2).cgColor
    cornerRadius = 2.5
    shadowColor = UIColor.black.cgColor
    shadowOpacity = 0.4
    shadowRadius = 3
    shadowOffset = CGSize(width: 0, height: 1.5)
    track.backgroundColor = UIColor(hex: 0x4a3d2b, alpha: 0.16).cgColor
    fill.backgroundColor = UIColor(hex: 0x8a6a3e).cgColor
    words.contentsGravity = .center
    track.addSublayer(fill)
    addSublayer(words)
    addSublayer(track)
    isHidden = true
  }

  override init(layer: Any) { super.init(layer: layer) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  static var height: CGFloat { 34 }

  func show(_ status: ImportStatus) {
    isHidden = status.said == nil
    said = status.said
    moving = status.moving
    track.isHidden = !moving
    share = status.share
    setNeedsLayout()
  }

  override func layoutSublayers() {
    super.layoutSublayers()
    let frame = CGRect(x: 7, y: moving ? 4 : 0, width: bounds.width - 14, height: moving ? 18 : bounds.height)
    words.frame = frame
    words.contentsScale = scale
    if let said, frame.width > 0, drawn.map({ $0.said != said || $0.size != frame.size || $0.scale != scale }) ?? true {
      words.contents = Self.draw(said, in: frame.size, scale: scale).cgImage
      drawn = (said, frame.size, scale)
    }
    track.frame = CGRect(x: 8, y: bounds.height - 8, width: bounds.width - 16, height: 2)
    fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * min(1, max(0, share)), height: 2)
    shadowPath = UIBezierPath(rect: bounds).cgPath
  }

  /// The words, centred, shrunk by up to a quarter to fit, and cut short if they still don't.
  private static func draw(_ text: String, in size: CGSize, scale: CGFloat) -> UIImage {
    let full: CGFloat = 12.5
    let attributes = { (pt: CGFloat) -> [NSAttributedString.Key: Any] in
      let style = NSMutableParagraphStyle()
      style.alignment = .center
      style.lineBreakMode = .byTruncatingTail
      return [
        .font: UIFont(name: "Baskerville-Italic", size: pt) ?? .italicSystemFont(ofSize: pt),
        .foregroundColor: UIColor(hex: 0x4a3d2b),
        .paragraphStyle: style,
      ]
    }
    let width = (text as NSString).size(withAttributes: attributes(full)).width
    let pt = width > size.width ? max(full * 0.75, full * size.width / width) : full
    let a = attributes(pt)
    let line = (text as NSString).size(withAttributes: a).height
    let f = UIGraphicsImageRendererFormat()
    f.scale = scale
    f.opaque = false
    return UIGraphicsImageRenderer(size: size, format: f).image { _ in
      (text as NSString).draw(in: CGRect(x: 0, y: (size.height - line) / 2, width: size.width, height: line), withAttributes: a)
    }
  }
}
