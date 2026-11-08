import UIKit

/// How far through a document the reader is, in place of a page number: a small
/// ring in the corner, barely there, that follows the scroll exactly. On reaching
/// a new page what's been read brightens for a moment, in its own ink, and fades
/// back down. Tapped, it opens the contents (see `ContentsTip`).
///
/// The pulse is all Core Animation, so that nothing has to keep the desk's frame
/// loop awake for the moment it takes.
final class PageRing: UIControl {
  static let diameter: CGFloat = 20
  private static let lineWidth: CGFloat = 1.75

  /// How long the light takes to come up, and to let go.
  private static let rise = 0.28
  private static let letGo = 1.3
  /// How strongly what's been read shows, at rest and while it's lit.
  private static let quiet: Float = 0.34
  private static let lit: Float = 0.9
  /// How strongly the soft edge shows while it's lit.
  private static let bloom: Float = 0.35

  /// Set when text can run beneath the ring, as it can where the margin is narrow: a disc of the page to rest on.
  var plated = false {
    didSet { plate.isHidden = !plated }
  }

  private let plate = CALayer()
  private let track = CAShapeLayer()
  /// What's been read.
  private let read = CAShapeLayer()
  /// The page last lit for, of how many.
  private var reached: (page: Int, of: Int)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    addInteraction(UIPointerInteraction())
    bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
    let path = UIBezierPath(
      arcCenter: CGPoint(x: Self.diameter / 2, y: Self.diameter / 2), radius: (Self.diameter - Self.lineWidth) / 2,
      startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true
    ).cgPath
    plate.frame = bounds.insetBy(dx: -4, dy: -4)
    plate.cornerRadius = plate.bounds.width / 2
    plate.isHidden = true
    plate.actions = ["hidden": NSNull()]
    layer.addSublayer(plate)
    for l in [track, read] {
      l.fillColor = nil
      l.lineWidth = Self.lineWidth
      l.lineCap = .round
      l.frame = bounds
      l.path = path
      layer.addSublayer(l)
    }
    track.opacity = 0.1
    read.opacity = Self.quiet
    read.strokeEnd = 0
    read.shadowRadius = 3
    read.shadowOffset = .zero
    read.shadowOpacity = 0
    alpha = 0
    dress()
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: PageRing, _) in self.dress() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// So small a thing is still a whole fingertip to hit.
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.insetBy(dx: -12, dy: -12).contains(point)
  }

  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
        self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 1.25, y: 1.25) : .identity
      }
    }
  }

  private func dress() {
    let ink = Palette.ink.resolvedColor(with: traitCollection).cgColor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    plate.backgroundColor = Palette.page.resolvedColor(with: traitCollection).cgColor
    track.strokeColor = ink
    read.strokeColor = ink
    read.shadowColor = ink
    CATransaction.commit()
  }

  /// Says the reader's `progress` of the way through, from 0 to 1, or nil if
  /// there's nowhere to scroll to, and on `page` of `of`, counting from 0.
  func set(progress: Double?, page: Int, of: Int) {
    let wanted: CGFloat = progress == nil ? 0 : 1
    if alpha != wanted { UIView.animate(withDuration: 0.4) { self.alpha = wanted } }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    read.strokeEnd = CGFloat(min(1, max(0, progress ?? 0)))
    CATransaction.commit()

    // The first thing it's told is simply where things stand, and reflowing can
    // change how many screenfuls a text comes to, but neither is reaching anything.
    guard let last = reached, last.of == of else {
      reached = (page, of)
      return
    }
    if page > last.page {
      reached = (page, of)
      light()
    } else if page < last.page - 1 {
      // A nudge back over a page's edge and on again isn't reaching it twice.
      reached = (page, of)
    }
  }

  /// Up quickly, from wherever an earlier light has got to, and slowly back down.
  private func light() {
    let total = Self.rise + Self.letGo
    let keyTimes = [0, NSNumber(value: Self.rise / total), 1]
    let curves = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]

    let ink = CAKeyframeAnimation(keyPath: "opacity")
    ink.values = [read.presentation()?.opacity ?? Self.quiet, Self.lit, Self.quiet]
    let edge = CAKeyframeAnimation(keyPath: "shadowOpacity")
    edge.values = [read.presentation()?.shadowOpacity ?? 0, Self.bloom, 0]
    for (key, a) in [("ink", ink), ("edge", edge)] {
      a.keyTimes = keyTimes
      a.timingFunctions = curves
      a.duration = total
      read.add(a, forKey: key)
    }
  }
}
