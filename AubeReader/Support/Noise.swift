import Foundation

/// Smooth noise on a fixed lattice, so a material comes out the same every time.
enum Noise {
  private static let side = 256
  private static let lattice: UnsafeMutablePointer<Float> = {
    let p = UnsafeMutablePointer<Float>.allocate(capacity: side * side)
    var rng = Seeded(0x5EED_0FA0_BE11)
    for i in 0..<(side * side) { p[i] = Float.random(in: 0...1, using: &rng) }
    return p
  }()

  @inline(__always) static func value(_ x: Float, _ y: Float) -> Float {
    let fx = x.rounded(.down)
    let fy = y.rounded(.down)
    let tx = x - fx
    let ty = y - fy
    let sx = tx * tx * (3 - 2 * tx)
    let sy = ty * ty * (3 - 2 * ty)
    let xi = Int(fx) & 255
    let yi = Int(fy) & 255
    let xj = (xi + 1) & 255
    let yj = (yi + 1) & 255
    let l = lattice
    let a = l[yi << 8 | xi]
    let b = l[yi << 8 | xj]
    let c = l[yj << 8 | xi]
    let d = l[yj << 8 | xj]
    let top = a + (b - a) * sx
    return top + ((c + (d - c) * sx) - top) * sy
  }

  /// Several octaves of `value`, each half the size and half the strength of the last, from 0 to 1.
  @inline(__always) static func fbm(_ x: Float, _ y: Float, _ octaves: Int) -> Float {
    var sum: Float = 0
    var strength: Float = 1
    var total: Float = 0
    var scale: Float = 1
    for i in 0..<octaves {
      let n = Float(i)
      sum += strength * value(x * scale + n * 17.3, y * scale + n * 9.1)
      total += strength
      strength *= 0.5
      scale *= 2
    }
    return sum / total
  }

  @inline(__always) static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
  }
}
