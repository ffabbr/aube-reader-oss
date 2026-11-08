import Foundation

/// A timing curve as CSS writes one: cubic-bezier(x1, y1, x2, y2), from (0, 0)
/// to (1, 1). A y outside 0…1 overshoots.
struct Ease {
  private let ax, bx, cx, ay, by, cy: Double

  init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    cx = 3 * x1
    bx = 3 * (x2 - x1) - cx
    ax = 1 - cx - bx
    cy = 3 * y1
    by = 3 * (y2 - y1) - cy
    ay = 1 - cy - by
  }

  private func x(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
  private func y(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
  private func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

  /// How far along the curve is when a share `p` of the time has passed.
  func callAsFunction(_ p: Double) -> Double {
    if p <= 0 { return 0 }
    if p >= 1 { return 1 }
    // Newton's method first; bisection where the slope is too flat for it.
    var t = p
    for _ in 0..<8 {
      let e = x(t) - p
      if abs(e) < 1e-6 { return y(t) }
      let d = dx(t)
      if abs(d) < 1e-6 { break }
      t -= e / d
    }
    var lo = 0.0
    var hi = 1.0
    t = p
    while hi - lo > 1e-6 {
      if x(t) < p { lo = t } else { hi = t }
      t = (lo + hi) / 2
    }
    return y(t)
  }

  /// Slow away and slow for a while, fast through the middle, a long soft landing.
  static let unfold = Ease(0.86, 0, 0.22, 1)
  /// The same, running a hair past the end before it settles.
  static let pour = Ease(0.82, 0, 0.18, 1.045)
  /// A quick rise that eases into place.
  static let rise = Ease(0.25, 0.1, 0.25, 1)
  /// For folding back up: under way sooner, still landing softly.
  static let fold = Ease(0.55, 0, 0.25, 1)
}

/// A value carried from where it is to a target over a set time, along an `Ease`.
final class Tween {
  private(set) var value: Double
  /// How fast it moved over the last step, per second.
  private(set) var velocity = 0.0
  private var start = 0.0
  private var target: Double
  private var begin = 0.0
  private var duration = 0.0
  private var curve = Ease.unfold

  init(_ value: Double) {
    self.value = value
    target = value
  }

  /// Sets off for `target` after `delay` seconds, arriving `duration` seconds later.
  func to(_ target: Double, over duration: Double, after delay: Double = 0, _ curve: Ease, now: Double) {
    start = value
    self.target = target
    begin = now + delay
    self.duration = max(duration, 1e-3)
    self.curve = curve
  }

  func step(_ now: Double, _ dt: Double) {
    let was = value
    let p = (now - begin) / duration
    value = p <= 0 ? start : start + (target - start) * curve(p)
    if p >= 1 { value = target }
    velocity = dt > 0 ? (value - was) / dt : 0
  }

  var resting: Bool { value == target }
  var goal: Double { target }
}
