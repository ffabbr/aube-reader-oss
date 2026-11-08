import Foundation

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
