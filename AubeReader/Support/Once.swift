import Foundation

/// Runs its work once, however many times it's asked.
final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var done = false

  func run(_ work: () -> Void) {
    let first = lock.withLock { () -> Bool in
      defer { done = true }
      return !done
    }
    if first { work() }
  }
}
