import UIKit

/// Book cloth: a grey weave of threads over and under, each thread a little
/// different from its neighbours, to lay over a color with an overlay.
enum Cloth {
  private static var weaves: [CGFloat: UIColor] = [:]

  @MainActor static func weave(scale: CGFloat) -> UIColor {
    if let w = weaves[scale] { return w }
    let w = UIColor(patternImage: tile(scale: scale))
    weaves[scale] = w
    return w
  }

  private static func tile(scale: CGFloat) -> UIImage {
    // Threads on a pitch of a point.
    let pitch = max(2, Int(scale.rounded()))
    let threads = 120
    let side = threads * pitch
    var rng = Seeded(0xC1_07_11)
    let warp = (0..<threads).map { _ in Float.random(in: -0.11...0.11, using: &rng) }
    let weft = (0..<threads).map { _ in Float.random(in: -0.11...0.11, using: &rng) }
    let image = Wood.bitmap(side, side) { px, stride in
      for y in 0..<side {
        var at = px + y * stride
        let ty = y / pitch
        let fy = Float(y % pitch) / Float(pitch) - 0.5
        for x in 0..<side {
          let tx = x / pitch
          let fx = Float(x % pitch) / Float(pitch) - 0.5
          let over = (tx + ty) % 2 == 0
          // A thread is round, so it's brightest along its middle.
          var v: Float = over ? 0.62 - fx * fx * 1.5 + warp[tx] : 0.5 - fy * fy * 1.5 + weft[ty]
          v += Float.random(in: -0.035...0.035, using: &rng)
          let b = UInt8(min(255, max(0, v * 255)))
          at[0] = b
          at[1] = b
          at[2] = b
          at[3] = 255
          at += 4
        }
      }
    }
    guard let image else { return UIImage() }
    return UIImage(cgImage: image, scale: scale, orientation: .up)
  }
}
