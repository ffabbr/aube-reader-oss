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
final class StatusSlip: UIView {
  private let label = UILabel()
  private let track = UIView()
  private let fill = UIView()
  private var share: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor(hex: 0xf6f0e2)
    layer.cornerRadius = 2.5
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.4
    layer.shadowRadius = 3
    layer.shadowOffset = CGSize(width: 0, height: 1.5)
    label.font = UIFont(name: "Baskerville-Italic", size: 12.5) ?? .italicSystemFont(ofSize: 12)
    label.textColor = UIColor(hex: 0x4a3d2b)
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.75
    label.textAlignment = .center
    track.backgroundColor = UIColor(hex: 0x4a3d2b, alpha: 0.16)
    fill.backgroundColor = UIColor(hex: 0x8a6a3e)
    track.addSubview(fill)
    addSubview(label)
    addSubview(track)
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  static var height: CGFloat { 34 }

  func show(_ status: ImportStatus) {
    isHidden = status.said == nil
    label.text = status.said
    track.isHidden = !status.moving
    share = status.share
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let moving = !track.isHidden
    label.frame = CGRect(x: 7, y: moving ? 4 : 0, width: bounds.width - 14, height: moving ? 18 : bounds.height)
    track.frame = CGRect(x: 8, y: bounds.height - 8, width: bounds.width - 16, height: 2)
    fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * min(1, max(0, share)), height: 2)
    layer.shadowPath = UIBezierPath(rect: bounds).cgPath
  }
}
