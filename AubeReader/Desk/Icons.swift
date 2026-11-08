import CryptoKit
import UIKit

/// The drawing that stands for each document in the library. The Decisions API
/// picks it from the library of drawings, going by the document's title alone,
/// and the choice is kept on disk by that title, so it's asked once. In the
/// library a drawing is a stamp: ink and nothing else, at rest and without its
/// lettering, that each look prints as it likes, as foil on a book's cover or
/// type on a card. A stamp is taken once and kept in the caches, so the library
/// needs no web view to show one.
@MainActor final class Icons {
  static let shared = Icons()

  /// Called when something has come that wasn't there before.
  var onChange: (() -> Void)?
  /// Where pictures are taken: a view in the window.
  weak var host: UIView?

  private lazy var chosen: [String: String] = {
    guard let data = try? Data(contentsOf: Self.file), let chosen = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return chosen
  }()
  /// By drawing.
  private var stamps: [String: UIImage] = [:]
  /// Titles still to be asked about, and drawings still to be stamped, each dealt with one at a time.
  private var questions: [String] = []
  private var asking = false
  private var sittings: [(id: String, svg: String)] = []
  private var picturing = false

  /// The drawing chosen for a title. Nil until it's come, or if it can't:
  /// `onChange` says when to look again, and what failed is tried again the next
  /// time it's looked for.
  func drawing(for title: String) -> Drawing? {
    guard let id = chosen[title], let drawing = Drawing.all.first(where: { $0.id == id }) else {
      ask(about: title)
      return nil
    }
    return drawing
  }

  /// The chosen drawing as ink alone: black, its alpha the strength of the ink,
  /// cut close, so it can be tinted, masked and placed by what's actually drawn.
  func stamp(for title: String) -> UIImage? {
    guard let drawing = drawing(for: title) else { return nil }
    if let stamp = stamps[drawing.id] { return stamp }
    guard let svg = drawing.svg else { return nil }
    if let data = try? Data(contentsOf: Self.cached(svg)), let kept = UIImage(data: data, scale: 2) {
      stamps[drawing.id] = kept
      return kept
    }
    take(drawing.id, svg)
    return nil
  }

  // ─── Choosing ────────────────────────────────────────────────────────────

  /// Worded by trying it out: asked more plainly, the model says yes to whatever's at hand.
  private static let question = "Going only by the title given as input, would a reader expect this drawing on the document's cover because it shows what the document is about?"

  private func ask(about title: String) {
    guard !questions.contains(title) else { return }
    questions.append(title)
    guard !asking else { return }
    asking = true
    Task {
      while let title = questions.first {
        let ranked = await Drawing.ranked(for: title, asking: Self.question)
        questions.removeFirst()
        if let best = ranked.first {
          chosen[title] = best.id
          remember()
          onChange?()
        }
      }
      asking = false
    }
  }

  private static var file: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DocumentIcons.json")
  }

  private func remember() {
    let chosen = chosen
    let file = Self.file
    DispatchQueue.global(qos: .utility).async {
      guard let data = try? JSONEncoder().encode(chosen) else { return }
      try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
  }

  // ─── Stamping ────────────────────────────────────────────────────────────

  /// How wide a drawing is taken, in points: enough for the largest use of it.
  private static let width: CGFloat = 440

  private func take(_ id: String, _ svg: String) {
    guard !sittings.contains(where: { $0.id == id }) else { return }
    sittings.append((id, svg))
    guard !picturing else { return }
    picturing = true
    Task {
      while let next = sittings.first {
        if let host, let drawing = await DrawingView.picture(of: next.svg, dark: false, width: Self.width, in: host),
          let inked = await Task.detached(priority: .userInitiated, operation: { Self.ink(drawing) }).value
        {
          stamps[next.id] = inked
          let file = Self.cached(next.svg)
          DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? inked.pngData()?.write(to: file, options: .atomic)
          }
          sittings.removeFirst()
          onChange?()
        } else {
          sittings.removeFirst()
        }
      }
      picturing = false
    }
  }

  /// Turns a picture of a drawing, dark on pale, into how much ink lies at each
  /// point: the page's wash comes to nothing and the darkest line to all of it,
  /// the faint guides held up a little so that they survive being printed small.
  private nonisolated static func ink(_ picture: UIImage) -> UIImage? {
    guard let cg = picture.cgImage else { return nil }
    let w = cg.width
    let h = cg.height
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let data = ctx.data
    else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var minX = w
    var minY = h
    var maxX = -1
    var maxY = -1
    for y in 0..<h {
      var at = px + y * w * 4
      for x in 0..<w {
        let a = Float(at[3]) / 255
        var cover: Float = 0
        if a > 0.004 {
          let lum = (0.299 * Float(at[0]) + 0.587 * Float(at[1]) + 0.114 * Float(at[2])) / (255 * a)
          cover = a * pow(max(0, min(1, (0.93 - lum) / 0.86)), 0.72)
        }
        at[0] = 0
        at[1] = 0
        at[2] = 0
        at[3] = UInt8(cover * 255)
        if cover > 0.06 {
          minX = min(minX, x)
          maxX = max(maxX, x)
          minY = min(minY, y)
          maxY = max(maxY, y)
        }
        at += 4
      }
    }
    guard maxX >= minX, let whole = ctx.makeImage() else { return nil }
    // Bitmap rows run from the top, as a cropping rectangle does.
    let pad = 2
    let box = CGRect(x: max(0, minX - pad), y: max(0, minY - pad), width: min(w, maxX + pad + 1) - max(0, minX - pad), height: min(h, maxY + pad + 1) - max(0, minY - pad))
    guard let cut = whole.cropping(to: box) else { return nil }
    return UIImage(cgImage: cut, scale: 2, orientation: .up)
  }

  /// Where a stamp is kept, named for what's in it, so that a drawing that changes is taken again.
  private static func cached(_ svg: String) -> URL {
    let what = "\(width) \(svg)"
    let name = SHA256.hash(data: Data(what.utf8)).map { String(format: "%02x", $0) }.joined()
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DocumentStamps").appendingPathComponent(name + ".png")
  }
}
