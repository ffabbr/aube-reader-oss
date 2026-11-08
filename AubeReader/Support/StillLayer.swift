import QuartzCore

/// Layers that never animate on their own: the frame loop, or the code that
/// owns them, moves them.
class StillLayer: CALayer {
  override func action(forKey event: String) -> CAAction? { NSNull() }
}

final class StillTransformLayer: CATransformLayer {
  override func action(forKey event: String) -> CAAction? { NSNull() }
}

final class StillGradientLayer: CAGradientLayer {
  override func action(forKey event: String) -> CAAction? { NSNull() }
}
