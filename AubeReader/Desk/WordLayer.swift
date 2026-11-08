import UIKit

/// One word, typeset once and moved about by the frame loop.
final class WordLayer: StillLayer {
  static let pad: CGFloat = 6

  var glyphs: Glyphs? {
    didSet {
      guard glyphs !== oldValue else { return }
      resize()
      setNeedsDisplay()
      dress()
    }
  }

  var ink: CGColor = UIColor.black.cgColor {
    didSet {
      if ink != oldValue {
        setNeedsDisplay()
        dress()
      }
    }
  }

  var lineHeight: CGFloat = 32 { didSet { if lineHeight != oldValue { resize() } } }
  var baseline: CGFloat = 22 {
    didSet {
      if baseline != oldValue {
        setNeedsDisplay()
        dress()
      }
    }
  }

  /// The bar a placeholder is drawn as: a sublayer, so it can breathe in and
  /// out while the frame loop sets how strongly the word shows.
  private var bar: StillLayer?
  /// One moment every bar's breathing is counted from, so that across a
  /// paragraph they ripple as one.
  private static let epoch = CACurrentMediaTime()

  /// Shows a placeholder's bar, or puts it away for a word.
  private func dress() {
    guard let glyphs, glyphs.placeholder, case let .rule(x, width, rise, thickness)? = glyphs.pieces.first else {
      bar?.isHidden = true
      bar?.removeAllAnimations()
      return
    }
    let b = bar ?? StillLayer()
    if bar == nil {
      bar = b
      addSublayer(b)
    }
    b.isHidden = false
    b.frame = CGRect(x: WordLayer.pad + x, y: baseline - rise - thickness / 2, width: width, height: thickness)
    b.cornerRadius = thickness / 2
    b.backgroundColor = UIColor(cgColor: ink).withAlphaComponent(0.13).cgColor
  }

  /// Sets a placeholder's bar breathing, in step with the others: a wave that
  /// runs along each line and down the paragraph, from the bar's place `x`, `y`.
  private func breathe(_ x: Double, _ y: Double) {
    guard let bar, !bar.isHidden, bar.animation(forKey: "breathe") == nil, !UIAccessibility.isReduceMotionEnabled else {
      return
    }
    bar.add(CABasicAnimation.breathing(x: x, y: y, epoch: bar.convertTime(WordLayer.epoch, from: nil)), forKey: "breathe")
  }

  /// What was last written, so unchanged properties aren't written again.
  var shown: (x: Double, y: Double, scale: Double, opacity: Double)?

  override init() {
    super.init()
    needsDisplayOnBoundsChange = true
  }

  override init(layer: Any) { super.init(layer: layer) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private func resize() {
    let w = (glyphs?.width ?? 0) + 2 * WordLayer.pad
    bounds = CGRect(x: 0, y: 0, width: ceil(w), height: lineHeight)
    shown = nil
  }

  override func draw(in ctx: CGContext) {
    guard let glyphs, !glyphs.placeholder else { return }
    ctx.setFillColor(ink)
    drawPieces(glyphs.pieces, in: ctx, x: WordLayer.pad, baseline: baseline)
  }

  /// Puts the word's left edge at `x` on the line whose top is at `y`.
  func paint(x: Double, y: Double, scale: Double, opacity: Double) {
    let w = Double(glyphs?.width ?? 0)
    let x = (x * 100).rounded() / 100
    let y = (y * 100).rounded() / 100
    let scale = (scale * 1000).rounded() / 1000
    let opacity = opacity >= 0.999 ? 1 : opacity <= 0.001 ? 0 : (opacity * 1000).rounded() / 1000
    if let s = shown, s == (x, y, scale, opacity) { return }
    if shown?.x != x || shown?.y != y {
      position = CGPoint(x: x + w / 2, y: y + Double(lineHeight) / 2)
      if glyphs?.placeholder == true { breathe(x, y) }
    }
    if shown?.scale != scale {
      transform = scale == 1 ? CATransform3DIdentity : CATransform3DMakeScale(scale, scale, 1)
    }
    if shown?.opacity != opacity {
      self.opacity = Float(opacity)
      isHidden = opacity == 0
    }
    shown = (x, y, scale, opacity)
  }
}
