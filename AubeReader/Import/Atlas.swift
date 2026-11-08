import CoreImage
import PDFKit
import UIKit

// ─── Pictures of pages ───────────────────────────────────────────────────────

/// Draws a PDF's pages, and parts of them, into pictures, away from the main
/// thread, in the colors of the reader's appearance. PDF pages can take a long
/// time to draw, so nothing on the main thread ever waits for one: a tile shows
/// blank paper until its picture is ready. The newest request goes first, since
/// it's the one on screen. A few pictures are kept, the most recently used.
/// Its own state is only ever touched on the main thread, which is what makes
/// it safe to hand across to it.
final class PageAtlas: @unchecked Sendable {
  struct Key: Hashable {
    var page: Int
    /// The picture's width in pixels.
    var pixels: Int
    var dark: Bool
    /// The part of the page, in page points; nil for all of it.
    var crop: CGRect?
  }

  private struct Waiting {
    let key: Key
    var done: [(CGImage?) -> Void]
  }

  private let url: URL
  private let photos: [Int: [CGRect]]
  /// Pages turned upright when they were read, and how far. Done on this copy of them too.
  private let turns: [Int: Int]
  private var turned = Set<Int>()
  /// What's left out of each page, in page points: footnotes, and page numbers.
  private let erased: [Int: [CGRect]]
  private let papers: [Int: Tint]
  private let queue = DispatchQueue(label: "aube.atlas", qos: .userInitiated)
  /// Only ever touched on `queue`.
  private var pdf: PDFDocument?

  // On the main thread.
  private var cache: [Key: CGImage] = [:]
  private var recent: [Key] = []
  private var waiting: [Waiting] = []
  private var running = false
  private var bytes = 0
  private var memoryWatch: NSObjectProtocol?
  private static let budget = 260 * 1024 * 1024

  /// With no color management: inverting and lifting are meant in the page's own
  /// values, and in linear light the night page's dark grey would come out far too pale.
  private static let ci = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])

  init(url: URL, pages: [DocPage], erasing erased: [Int: [CGRect]] = [:]) {
    self.url = url
    self.erased = erased
    var papers: [Int: Tint] = [:]
    for (i, p) in pages.enumerated() where p.paper != .white { papers[i] = p.paper }
    self.papers = papers
    var photos: [Int: [CGRect]] = [:]
    var turns: [Int: Int] = [:]
    for (i, p) in pages.enumerated() {
      if !p.photos.isEmpty { photos[i] = p.photos }
      if p.turn != 0 { turns[i] = p.turn }
    }
    self.photos = photos
    self.turns = turns
    memoryWatch = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
      self?.forget()
    }
  }

  deinit {
    if let memoryWatch { NotificationCenter.default.removeObserver(memoryWatch) }
  }

  /// A picture of `key`, at once if it's kept, otherwise when it's drawn. On the main thread.
  func picture(_ key: Key, _ done: @escaping (CGImage?) -> Void) {
    if let hit = cache[key] {
      touch(key)
      done(hit)
      return
    }
    if let i = waiting.firstIndex(where: { $0.key == key }) {
      var w = waiting.remove(at: i)
      w.done.append(done)
      waiting.append(w)
    } else {
      waiting.append(Waiting(key: key, done: [done]))
    }
    next()
  }

  /// The same, for code that can wait.
  func picture(_ key: Key) async -> CGImage? {
    await withCheckedContinuation { c in
      DispatchQueue.main.async { self.picture(key) { c.resume(returning: $0) } }
    }
  }

  private func touch(_ key: Key) {
    if let i = recent.firstIndex(of: key) { recent.remove(at: i) }
    recent.append(key)
  }

  private func next() {
    guard !running, let w = waiting.popLast() else { return }
    running = true
    queue.async { [self] in
      let image = autoreleasepool { draw(w.key) }
      DispatchQueue.main.async { [self] in
        running = false
        if let image { keep(image, w.key) }
        for d in w.done { d(image) }
        next()
      }
    }
  }

  private func keep(_ image: CGImage, _ key: Key) {
    cache[key] = image
    touch(key)
    bytes += image.bytesPerRow * image.height
    while bytes > Self.budget, recent.count > 1 {
      let old = recent.removeFirst()
      if let gone = cache.removeValue(forKey: old) { bytes -= gone.bytesPerRow * gone.height }
    }
  }

  /// Lets go of every picture kept, when memory runs short.
  func forget() {
    cache = [:]
    recent = []
    bytes = 0
  }

  // ─── Drawing ─────────────────────────────────────────────────────────────

  private func draw(_ key: Key) -> CGImage? {
    if pdf == nil {
      pdf = PDFDocument(url: url)
      // Links' borders are for clicking, not for reading.
      if let pdf {
        for i in 0..<pdf.pageCount {
          for a in pdf.page(at: i)?.annotations ?? [] where a.type == "Link" { a.shouldDisplay = false }
        }
      }
    }
    guard let page = pdf?.page(at: key.page) else { return nil }
    if let turn = turns[key.page], turned.insert(key.page).inserted { page.rotation = (page.rotation + turn) % 360 }
    let frame = PageFrame(page)
    let target = key.crop ?? CGRect(origin: .zero, size: frame.size)
    guard target.width > 0, target.height > 0 else { return nil }
    let s = CGFloat(key.pixels) / target.width
    let w = max(1, Int((target.width * s).rounded(.up)))
    let h = max(1, Int((target.height * s).rounded(.up)))
    guard
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.setFillColor(UIColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.saveGState()
    // PDFKit draws the box with its corner at the origin, y up, however the page is turned.
    ctx.translateBy(x: -target.minX * s, y: -(frame.size.height - target.maxY) * s)
    ctx.scaleBy(x: s, y: s)
    page.draw(with: .cropBox, to: ctx)
    ctx.restoreGState()
    // Painted over in the paper's own color, so it comes out as bare paper by day or by night.
    let paper = papers[key.page] ?? .white
    ctx.setFillColor(red: paper.r, green: paper.g, blue: paper.b, alpha: 1)
    for r in erased[key.page] ?? [] where r.intersects(target) {
      let o = r.intersection(target)
      // From the page's y down to the context's y up.
      ctx.fill(CGRect(x: (o.minX - target.minX) * s, y: (target.maxY - o.maxY) * s, width: o.width * s, height: o.height * s))
    }
    guard let drawn = ctx.makeImage() else { return nil }
    if key.dark { return darken(drawn, key: key, target: target, scale: s) }
    // By day, a warm breath of the page's own color, so it's one sheet with the rest.
    let light = Palette.page.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    ctx.setBlendMode(.multiply)
    ctx.setFillColor(light.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? drawn
  }

  /// A page for the dark: what's dark goes light, keeping its hue, and white
  /// paper goes to the desk's night page. Photographs keep their colors.
  private func darken(_ image: CGImage, key: Key, target: CGRect, scale s: CGFloat) -> CGImage? {
    let night = Palette.page.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    night.getRed(&r, green: &g, blue: &b, alpha: &a)
    var i = CIImage(cgImage: image)
      .applyingFilter("CIColorInvert")
      .applyingFilter("CIHueAdjust", parameters: ["inputAngle": Float.pi])
    i = i.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputRVector": CIVector(x: 1 - r, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 1 - g, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 1 - b, w: 0),
        "inputBiasVector": CIVector(x: r, y: g, z: b, w: 0),
      ])
    guard let dark = Self.ci.createCGImage(i, from: CGRect(x: 0, y: 0, width: image.width, height: image.height)) else { return nil }
    let kept = (photos[key.page] ?? []).filter { $0.intersects(target) }
    guard !kept.isEmpty else { return dark }
    guard
      let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return dark }
    let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.draw(dark, in: full)
    for p in kept {
      let o = p.intersection(target)
      // From the page's y down to the context's y up.
      let px = CGRect(x: (o.minX - target.minX) * s, y: (target.maxY - o.maxY) * s, width: o.width * s, height: o.height * s)
      ctx.saveGState()
      ctx.clip(to: px)
      ctx.draw(image, in: full)
      ctx.restoreGState()
    }
    return ctx.makeImage() ?? dark
  }
}

/// A color as it should read on a page gone dark: dark inks light, hues kept.
func darkened(_ t: Tint) -> UIColor {
  var h: CGFloat = 0
  var s: CGFloat = 0
  var b: CGFloat = 0
  var a: CGFloat = 0
  UIColor(red: t.r, green: t.g, blue: t.b, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
  // Brightness is the inverse of how dark the ink was, and never quite white.
  return UIColor(hue: h, saturation: min(s, 0.55), brightness: max(0.82, 1 - t.luma * 0.5), alpha: 1)
}
