import PDFKit
import UIKit

enum PagePicture {
  /// All of `page`, white behind, `pixels` wide.
  static func make(_ page: PDFPage, pixels: Int) -> CGImage? {
    let frame = PageFrame(page)
    guard frame.size.width > 0, frame.size.height > 0 else { return nil }
    let s = CGFloat(pixels) / frame.size.width
    let h = Int((frame.size.height * s).rounded(.up))
    guard
      let ctx = CGContext(
        data: nil, width: pixels, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace.sRGBSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: h))
    ctx.scaleBy(x: s, y: s)
    page.draw(with: .cropBox, to: ctx)
    return ctx.makeImage()
  }
}

/// Finds the pictures in a scan, where nothing says what's what: dark patches of
/// the page that aren't text, large enough to matter.
enum ScanFigures {
  static func find(_ raw: inout RawPage, picture: CGImage) {
    let w = 200
    let h = max(1, Int(CGFloat(w) * raw.size.height / max(raw.size.width, 1)))
    var px = [UInt8](repeating: 255, count: w * h)
    let drawn: Bool = px.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let ctx = CGContext(
          data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      ctx.draw(picture, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    guard drawn else { return }
    // The paper: the commonest shade.
    var tally = [Int](repeating: 0, count: 256)
    for v in px { tally[Int(v)] += 1 }
    let paper = tally.indices.max { tally[$0] < tally[$1] } ?? 255
    var ink = px.map { abs(Int($0) - paper) > 40 }
    // Text doesn't count. Bitmap rows run from the top, as the page's own y does.
    let (sx, sy) = (CGFloat(w) / raw.size.width, CGFloat(h) / raw.size.height)
    for run in raw.runs {
      let r = run.rect.insetBy(dx: -2, dy: -2)
      let (x0, x1) = (max(0, Int(r.minX * sx)), min(w - 1, Int(r.maxX * sx)))
      let (y0, y1) = (max(0, Int(r.minY * sy)), min(h - 1, Int(r.maxY * sy)))
      guard x0 <= x1, y0 <= y1 else { continue }
      for y in y0...y1 { for x in x0...x1 { ink[y * w + x] = false } }
    }
    // Patches of ink, near enough to count as one.
    var seen = [Bool](repeating: false, count: w * h)
    var stack: [Int] = []
    for start in ink.indices where ink[start] && !seen[start] {
      var (x0, x1, y0, y1, n) = (w, 0, h, 0, 0)
      stack = [start]
      seen[start] = true
      while let at = stack.popLast() {
        let (x, y) = (at % w, at / w)
        x0 = min(x0, x)
        x1 = max(x1, x)
        y0 = min(y0, y)
        y1 = max(y1, y)
        n += 1
        for dy in -2...2 {
          for dx in -2...2 {
            let (nx, ny) = (x + dx, y + dy)
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let k = ny * w + nx
            if ink[k] && !seen[k] {
              seen[k] = true
              stack.append(k)
            }
          }
        }
      }
      let box = CGRect(x: CGFloat(x0) / sx, y: CGFloat(y0) / sy, width: CGFloat(x1 - x0 + 1) / sx, height: CGFloat(y1 - y0 + 1) / sy)
      let share = box.width * box.height / (raw.size.width * raw.size.height)
      // Big enough to be a picture, and solid enough not to be a page's dark edge.
      if share > 0.015, n > (x1 - x0 + 1) * (y1 - y0 + 1) / 8, box.width > 30, box.height > 30, share < 0.85 {
        raw.marks.append(RawMark(rect: box, kind: .image))
      }
    }
  }
}
