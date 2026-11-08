import UIKit

/// Three colors a timber runs through, from its darkest grain to its palest.
struct Stain {
  let dark: SIMD3<Float>
  let mid: SIMD3<Float>
  let light: SIMD3<Float>

  init(_ dark: (Float, Float, Float), _ mid: (Float, Float, Float), _ light: (Float, Float, Float)) {
    self.dark = SIMD3(dark.0, dark.1, dark.2) / 255
    self.mid = SIMD3(mid.0, mid.1, mid.2) / 255
    self.light = SIMD3(light.0, light.1, light.2) / 255
  }

  private init(dark: SIMD3<Float>, mid: SIMD3<Float>, light: SIMD3<Float>) {
    self.dark = dark
    self.mid = mid
    self.light = light
  }

  /// The same timber with its light taken down.
  func dimmed(_ k: Float) -> Stain { Stain(dark: dark * k, mid: mid * k, light: light * k) }

  var average: UIColor { UIColor(red: CGFloat(mid.x), green: CGFloat(mid.y), blue: CGFloat(mid.z), alpha: 1) }

  /// Oak gone honey-colored, by day.
  static let oak = Stain((104, 66, 34), (158, 110, 64), (208, 164, 112))
  /// Walnut, by lamplight.
  static let walnut = Stain((30, 18, 11), (78, 50, 31), (132, 92, 60))
}

/// Timber grown a pixel at a time: growth rings of uneven width that close round
/// a heart if the board has one, long sweeps of grain, fine fibres, the short
/// dark dashes of pores, thickest in the early wood, and the chatoyant cloud that
/// makes a planed board look lit from within.
enum Wood {
  struct Grain {
    var seed: Float
    var stain: Stain
    /// Where the rings close, in points along the board and across it.
    var heart: (along: Float, across: Float)?
    /// How far the grain wanders.
    var figure: Float = 1
  }

  /// Paints `grain` into a rectangle of a bitmap. Along a board is left to right,
  /// or top to bottom if it's `upright`.
  static func paint(_ px: UnsafeMutablePointer<UInt8>, stride: Int, x: Int, y: Int, width: Int, height: Int, scale: Float, upright: Bool, _ grain: Grain) {
    let seed = grain.seed
    let dark = grain.stain.dark
    let mid = grain.stain.mid
    let light = grain.stain.light
    let shiftU = seed * 311
    let shiftV = seed * 97
    let heart = grain.heart
    let figure = grain.figure
    for row in 0..<height {
      var at = px + (y + row) * stride + x * 4
      for col in 0..<width {
        let along = (upright ? Float(row) : Float(col)) / scale
        let across = (upright ? Float(col) : Float(row)) / scale
        let u = along + shiftU
        let v = across + shiftV
        let sweep = Noise.fbm(u * 0.0011, v * 0.0042, 3) * 150 * figure + Noise.value(u * 0.006, v * 0.02) * 9
        var d: Float
        if let heart {
          let ex = (along - heart.along) * 0.052
          let ey = across - heart.across
          d = (ey * ey + ex * ex).squareRoot() + sweep * 0.55
        } else {
          d = across + sweep
        }
        d += Noise.fbm(d * 0.009 + seed, seed * 0.7, 3) * 64
        let cycle = d * 0.21
        let ring = cycle - cycle.rounded(.down)
        // The dark late wood that ends each year.
        let late = Noise.smooth(0.55, 0.98, ring) * (1 - Noise.smooth(0.985, 1, ring))
        let fibre = Noise.value(u * 0.016, v * 1.5) * 0.6 + Noise.value(u * 0.05, v * 3.1) * 0.4
        let early = 0.12 * (1 - ring)
        let pore = Noise.smooth(0.74 - early, 0.86 - early, Noise.value(u * 0.075, v * 2.8))
        let broad = Noise.fbm(u * 0.0009, v * 0.0075 + 5, 3)
        let cloud = Noise.fbm(u * 0.0035 + 9, v * 0.0035 + 3, 2)
        var t = 0.42 + 1.05 * (broad - 0.5) - 0.4 * late + 0.34 * (fibre - 0.5) + 0.34 * (cloud - 0.5)
        t = min(1, max(0, t))
        var c = t < 0.5 ? dark + (mid - dark) * (t / 0.5) : mid + (light - mid) * ((t - 0.5) / 0.5)
        c *= 1 - 0.3 * pore
        at[0] = UInt8(min(255, c.x * 255))
        at[1] = UInt8(min(255, c.y * 255))
        at[2] = UInt8(min(255, c.z * 255))
        at[3] = 255
        at += 4
      }
    }
  }

  /// A bitmap painted by `work`, `width` by `height` pixels.
  static func bitmap(_ width: Int, _ height: Int, _ work: (UnsafeMutablePointer<UInt8>, Int) -> Void) -> CGImage? {
    let space = CGColorSpace.sRGBSpace
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let data = ctx.data
    else { return nil }
    work(data.bindMemory(to: UInt8.self, capacity: width * height * 4), ctx.bytesPerRow)
    return ctx.makeImage()
  }
}
