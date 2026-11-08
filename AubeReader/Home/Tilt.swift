import CoreMotion
import UIKit

/// How the iPad is tilted, smoothed, for foil to catch the light by.
@MainActor
final class Tilt {
  static let shared = Tilt()
  private(set) var value = CGPoint.zero
  var onChange: (() -> Void)?
  private let motion = CMMotionManager()
  private var rest: CGPoint?

  func start() {
    guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive, !UIAccessibility.isReduceMotionEnabled else { return }
    motion.deviceMotionUpdateInterval = 1 / 30
    motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
      guard let self, let m else { return }
      // Measured from however it's first held, so only moving it moves the light.
      let now = CGPoint(x: CGFloat(m.attitude.roll), y: CGFloat(m.attitude.pitch))
      let rest = self.rest ?? now
      self.rest = rest
      let goal = CGPoint(x: now.x - rest.x, y: now.y - rest.y)
      self.value.x += (goal.x - self.value.x) * 0.16
      self.value.y += (goal.y - self.value.y) * 0.16
      // The rest follows slowly, so a new way of holding it becomes the new rest.
      self.rest = CGPoint(x: rest.x + (now.x - rest.x) * 0.004, y: rest.y + (now.y - rest.y) * 0.004)
      self.onChange?()
    }
  }

  func stop() {
    motion.stopDeviceMotionUpdates()
    rest = nil
  }
}
