import Foundation

/// A paragraph's state is a point (difficulty, zoom) on a grid of versions.
/// Between grid points it is drawn as a morph between the two nearest versions.
struct Morph {
  struct Pair: Hashable {
    var paragraph = 0
    var ac: Int, az: Int, bc: Int, bz: Int
  }

  var a: (c: Int, z: Int)
  var b: (c: Int, z: Int)
  var t: Double
  /// Difficulty swaps slide sideways; zoom swaps shrink in place.
  var sideways: Bool

  var pair: Pair { Pair(ac: a.c, az: a.z, bc: b.c, bz: b.z) }

  init(c: Double, z: Double, cMax: Int, zMax: Int) {
    let c = clamp(c, 0, Double(cMax))
    let z = clamp(z, 0, Double(zMax))
    let fc = c - c.rounded(.down)
    let fz = z - z.rounded(.down)
    let dc = min(fc, 1 - fc)
    let dz = min(fz, 1 - fz)
    if dc < 1e-4 && dz < 1e-4 {
      a = (Int(c.rounded()), Int(z.rounded()))
      b = a
      t = 0
      sideways = false
    } else if dc >= dz {
      let zi = Int(z.rounded())
      let c0 = Int(c.rounded(.down))
      a = (c0, zi)
      b = (c0 + 1, zi)
      t = fc
      sideways = true
    } else {
      let ci = Int(c.rounded())
      let z0 = Int(z.rounded(.down))
      a = (ci, z0)
      b = (ci, z0 + 1)
      t = fz
      sideways = false
    }
  }
}
