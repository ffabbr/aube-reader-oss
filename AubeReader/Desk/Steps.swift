import Foundation

/// The levels of difficulty a paragraph's swipes and keys stop at: one for each
/// run of neighboring levels that read the same.
struct Steps {
  /// The level each stop is at, and the level its run begins at.
  let at: [Int]
  let starts: [Int]
  /// The hardest level there is.
  let top: Int

  var last: Int { at.count - 1 }

  /// The stop whose run level `c` is in.
  func index(of c: Int) -> Int { starts.lastIndex { $0 <= c } ?? 0 }

  /// The level a swipe `s` stops along reads at. Between two stops it crosses
  /// only the levels where the text changes, so all of the swipe goes into the
  /// change; past either end it's pulled against the simplest or hardest level.
  /// On a stop, it's the stop's level, or the one of its run nearest `near`.
  func level(_ s: Double, near: Double? = nil) -> Double {
    let n = Double(last)
    if s < 0 { return s }
    if s > n { return Double(top) + s - n }
    let k = Int(s.rounded(.down))
    let f = s - Double(k)
    guard f == 0 else { return Double(end(k)) + f }
    return near.map { clamp($0, Double(starts[k]), Double(end(k))) } ?? Double(at[k])
  }

  /// How far along the stops level `c` is: the inverse of `level`.
  func along(_ c: Double) -> Double {
    if c < 0 { return c }
    if c > Double(top) { return Double(last) + c - Double(top) }
    let k = index(of: Int(c.rounded(.down)))
    return Double(k) + max(0, c - Double(end(k)))
  }

  /// The last level of stop `k`'s run.
  private func end(_ k: Int) -> Int { k < last ? starts[k + 1] - 1 : top }
}
