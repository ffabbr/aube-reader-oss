import Foundation
import os

/// Where the app keeps what it makes and remembers, and how it writes it there.
enum Disk {
  private static let log = Logger(subsystem: "aube-reader", category: "disk")

  /// Application Support: what the app keeps for itself, out of the user's sight.
  static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

  /// Writes `data` to `file` whole or not at all, making its folder if need
  /// be. False, and logged, if it couldn't.
  @discardableResult
  static func write(_ data: Data?, to file: URL) -> Bool {
    guard let data else { return false }
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
      return true
    } catch {
      log.error("Couldn't write \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  /// `value` as JSON, written to `file` as `write` does.
  @discardableResult
  static func writeJSON<T: Encodable>(_ value: T, to file: URL) -> Bool {
    write(try? JSONEncoder().encode(value), to: file)
  }
}
