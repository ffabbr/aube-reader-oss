import UIKit

extension CALayer {
  /// Takes a layer's transform to `to` on a spring, carrying on from wherever it is on screen.
  func spring(transform to: CATransform3D, damping: CGFloat = 16, stiffness: CGFloat = 230) {
    let from = presentation()?.transform ?? transform
    removeAnimation(forKey: "spring")
    transform = to
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    let a = CASpringAnimation(keyPath: "transform")
    a.fromValue = NSValue(caTransform3D: from)
    a.toValue = NSValue(caTransform3D: to)
    a.damping = damping
    a.stiffness = stiffness
    a.mass = 1
    a.duration = min(1, a.settlingDuration)
    add(a, forKey: "spring")
  }
}

/// Where a camera `distance` away, looking at `vanish`, sees a layer whose centre is at `centre`.
func perspective(centre: CGPoint, vanish: CGPoint, distance: CGFloat) -> CATransform3D {
  var p = CATransform3DIdentity
  p.m34 = -1 / distance
  let dx = centre.x - vanish.x
  let dy = centre.y - vanish.y
  return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(dx, dy, 0), p), CATransform3DMakeTranslation(-dx, -dy, 0))
}
