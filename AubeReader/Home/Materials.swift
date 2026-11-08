import UIKit

// ─── Noise ───────────────────────────────────────────────────────────────────

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

/// A stable number for a string: Swift's own hash changes with every launch, and
/// a document has to keep its binding from one launch to the next.
func steadyHash(_ s: String) -> UInt64 {
  var h: UInt64 = 0xcbf2_9ce4_8422_2325
  for b in s.utf8 {
    h ^= UInt64(b)
    h &*= 0x0000_0100_0000_01B3
  }
  // FNV leaves the low bits of similar strings alike; a last stir spreads them.
  h ^= h >> 29
  h &*= 0xBF58_476D_1CE4_E5B9
  return h ^ (h >> 32)
}

extension UIColor {
  convenience init(hex v: UInt32, alpha: CGFloat = 1) {
    self.init(red: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: alpha)
  }
}

// ─── Wood ────────────────────────────────────────────────────────────────────

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
    var brightness: Float = 1
  }

  /// Paints `grain` into a rectangle of a bitmap. Along a board is left to right,
  /// or top to bottom if it's `upright`.
  static func paint(_ px: UnsafeMutablePointer<UInt8>, stride: Int, x: Int, y: Int, width: Int, height: Int, scale: Float, upright: Bool, _ grain: Grain) {
    let seed = grain.seed
    let dark = grain.stain.dark
    let mid = grain.stain.mid
    let light = grain.stain.light
    let lift = grain.brightness
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
        c *= (1 - 0.3 * pore) * lift
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
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let data = ctx.data
    else { return nil }
    work(data.bindMemory(to: UInt8.self, capacity: width * height * 4), ctx.bytesPerRow)
    return ctx.makeImage()
  }
}

// ─── Materials kept on disk ──────────────────────────────────────────────────

/// Things slow to make, made once away from the main thread and kept in the caches.
@MainActor
final class Larder {
  static let shared = Larder()
  /// Changes whenever what's made changes, so nothing old is kept.
  private static let version = "3"
  private var kept: [String: UIImage] = [:]
  private var waiting: [String: [(UIImage) -> Void]] = [:]

  private static func file(_ name: String) -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LibraryMaterials", isDirectory: true)
      .appendingPathComponent("\(version)-\(name).jpg")
  }

  /// Hands over the picture called `name`, at once if it's in memory, or else
  /// when it's been read or made. `scale` is points to pixels.
  func fetch(_ name: String, scale: CGFloat, make: @escaping @Sendable () -> CGImage?, then: @escaping (UIImage) -> Void) {
    if let image = kept[name] {
      then(image)
      return
    }
    if waiting[name] != nil {
      waiting[name]?.append(then)
      return
    }
    waiting[name] = [then]
    let file = Self.file(name)
    DispatchQueue.global(qos: .userInitiated).async {
      var made: UIImage?
      if let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: scale) {
        made = image.preparingForDisplay() ?? image
      } else if let cg = make() {
        let image = UIImage(cgImage: cg, scale: scale, orientation: .up)
        made = image
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? image.jpegData(compressionQuality: 0.94)?.write(to: file, options: .atomic)
      }
      DispatchQueue.main.async {
        guard let made else { return }
        self.kept[name] = made
        for then in self.waiting.removeValue(forKey: name) ?? [] { then(made) }
      }
    }
  }
}

// ─── Layers that never animate on their own ──────────────────────────────────

final class StillTransformLayer: CATransformLayer {
  override func action(forKey event: String) -> CAAction? { NSNull() }
}

final class StillGradientLayer: CAGradientLayer {
  override func action(forKey event: String) -> CAAction? { NSNull() }
}

// ─── Cloth ───────────────────────────────────────────────────────────────────

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
