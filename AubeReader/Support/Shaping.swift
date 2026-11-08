import Foundation

// Small functions for shaping numbers over time and distance: clamping,
// interpolating, easing, and the rubber band that resists a pull past an end.

@inline(__always) func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// 0 below `e0`, 1 above `e1`, and an S-curve between.
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
  let t = clamp((x - e0) / (e1 - e0), 0, 1)
  return t * t * (3 - 2 * t)
}

/// How far a value pulled `d` past an end actually goes: less and less, never more than `dim`.
func band(_ d: Double, _ dim: Double) -> Double { dim * (1 - 1 / ((d / dim) * 0.55 + 1)) }
/// The pull past the end that `band` turns into `b`.
func unband(_ b: Double, _ dim: Double) -> Double { (dim / 0.55) * (1 / (1 - min(b / dim, 0.999)) - 1) }

/// `x`, held within `lo`…`hi` by a rubber band `dim` long.
func rubber(_ x: Double, _ lo: Double, _ hi: Double, _ dim: Double) -> Double {
  x < lo ? lo - band(lo - x, dim) : x > hi ? hi + band(x - hi, dim) : x
}

/// The `x` that `rubber` turns into the one given.
func unrubber(_ x: Double, _ lo: Double, _ hi: Double, _ dim: Double) -> Double {
  x < lo ? lo - unband(lo - x, dim) : x > hi ? hi + unband(x - hi, dim) : x
}
