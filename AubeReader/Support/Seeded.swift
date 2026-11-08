import CoreGraphics

/// The same numbers every time from the same seed (SplitMix64), so that what's
/// drawn from them, like the paper's grain or a paragraph's placeholders, stays
/// where it was from one launch to the next.
struct Seeded: RandomNumberGenerator {
  private var state: UInt64
  init(_ seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func callAsFunction(_ range: ClosedRange<CGFloat>) -> CGFloat { .random(in: range, using: &self) }
}
