import UIKit

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
        Disk.write(image.jpegData(compressionQuality: 0.94), to: file)
      }
      DispatchQueue.main.async {
        guard let made else { return }
        self.kept[name] = made
        for then in self.waiting.removeValue(forKey: name) ?? [] { then(made) }
      }
    }
  }
}
