import Foundation

/// A damped spring parameterised the way Apple describes them: `response` is
/// roughly how long (in seconds) the spring takes to get where it's going, and
/// `damping` is 1 for no overshoot, less than 1 for bounce.
final class Spring {
  var value: Double
  var target: Double
  var velocity: Double = 0
  var response: Double
  var damping: Double
  private let precision: Double

  init(_ value: Double, response: Double = 0.5, damping: Double = 1, precision: Double = 1e-4) {
    self.value = value
    self.target = value
    self.response = response
    self.damping = damping
    self.precision = precision
  }

  func step(_ dt: Double) {
    if resting { return }
    let w = 2 * Double.pi / response
    let stiffness = w * w
    let friction = 2 * damping * w
    var left = dt
    while left > 0 {
      let h = min(left, 1.0 / 240)
      velocity += (-stiffness * (value - target) - friction * velocity) * h
      value += velocity * h
      left -= h
    }
    if abs(value - target) < precision && abs(velocity) < precision * 10 {
      value = target
      velocity = 0
    }
  }

  /// Jumps straight to `x`, at rest.
  func snap(_ x: Double) {
    value = x
    target = x
    velocity = 0
  }

  var resting: Bool { value == target && velocity == 0 }
}

// ─── Shaping ─────────────────────────────────────────────────────────────────

@inline(__always) func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
  let t = clamp((x - e0) / (e1 - e0), 0, 1)
  return t * t * (3 - 2 * t)
}

/// How far a value pulled `d` past an end actually goes: less and less, never more than `dim`.
func band(_ d: Double, _ dim: Double) -> Double { dim * (1 - 1 / ((d / dim) * 0.55 + 1)) }
func unband(_ b: Double, _ dim: Double) -> Double { (dim / 0.55) * (1 / (1 - min(b / dim, 0.999)) - 1) }

func rubber(_ x: Double, _ lo: Double, _ hi: Double, _ dim: Double) -> Double {
  x < lo ? lo - band(lo - x, dim) : x > hi ? hi + band(x - hi, dim) : x
}

func unrubber(_ x: Double, _ lo: Double, _ hi: Double, _ dim: Double) -> Double {
  x < lo ? lo - unband(lo - x, dim) : x > hi ? hi + unband(x - hi, dim) : x
}
