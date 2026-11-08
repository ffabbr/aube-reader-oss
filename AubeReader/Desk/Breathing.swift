import QuartzCore

extension CABasicAnimation {
  /// The slow pulse of a placeholder waiting for its words, for one at (`x`,
  /// `y`) on the page. Every placeholder keeps time from `epoch`, offset a
  /// little by where it is, so the pulse sweeps gently down and across the page.
  static func breathing(x: Double, y: Double, epoch: CFTimeInterval) -> CABasicAnimation {
    let a = CABasicAnimation(keyPath: "opacity")
    a.fromValue = 1
    a.toValue = 0.4
    a.duration = 0.75
    a.autoreverses = true
    a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    a.beginTime = epoch + x / 700 + y / 2600
    a.fillMode = .backwards
    return a
  }
}
