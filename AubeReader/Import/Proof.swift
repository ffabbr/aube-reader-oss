import PDFKit
import UIKit

/// Pictures for the model to look at, drawn with the reader's own code, so that
/// what it checks is what a reader would see.
@MainActor
enum Proof {
  private static let wide = 1224

  private static func atlas(_ doc: ImportedDoc, _ file: URL) -> PageAtlas { PageAtlas(url: file, pages: doc.pages) }

  private static func jpeg(_ image: UIImage) -> Data? { image.jpegData(compressionQuality: 0.72) }

  private static let light = UITraitCollection {
    $0.userInterfaceStyle = .light
    $0.displayScale = 1
  }

  /// Just the page.
  static func original(_ doc: ImportedDoc, file: URL, page: Int) async -> Data? {
    guard let image = await atlas(doc, file).picture(PageAtlas.Key(page: page, pixels: wide, dark: false, crop: nil)) else { return nil }
    return jpeg(UIImage(cgImage: image))
  }

  /// The page, with every block outlined and numbered, and ticks along its edges to read positions by.
  static func marked(_ doc: ImportedDoc, file: URL, page: Int) async -> Data? {
    guard let info = doc.pages[safe: page], info.size.width > 0,
      let image = await atlas(doc, file).picture(PageAtlas.Key(page: page, pixels: wide, dark: false, crop: nil))
    else { return nil }
    let size = CGSize(width: image.width, height: image.height)
    let s = size.width / info.size.width
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let drawn = UIGraphicsImageRenderer(size: size, format: format).image { r in
      UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
      let ctx = r.cgContext
      for b in doc.blocks {
        for piece in b.pieces where piece.page == page {
          let color = roleColor(b.role)
          let box = CGRect(x: piece.ink.minX * s, y: piece.ink.minY * s, width: piece.ink.width * s, height: piece.ink.height * s)
          ctx.setStrokeColor(color.cgColor)
          ctx.setLineWidth(b.role == .furniture ? 1 : 1.5)
          ctx.stroke(box)
          let tag = NSAttributedString(string: " \(b.id) ", attributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.white, .backgroundColor: color])
          tag.draw(at: CGPoint(x: max(0, box.minX), y: max(0, box.minY - 15)))
        }
      }
      // Ticks every hundred, numbered.
      let tick: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.systemRed]
      ctx.setStrokeColor(UIColor.systemRed.cgColor)
      ctx.setLineWidth(1)
      for k in stride(from: 0, through: 1000, by: 100) {
        let x = size.width * CGFloat(k) / 1000
        let y = size.height * CGFloat(k) / 1000
        ctx.stroke(CGRect(x: x, y: 0, width: 0.5, height: 8))
        ctx.stroke(CGRect(x: 0, y: y, width: 8, height: 0.5))
        ("\(k)" as NSString).draw(at: CGPoint(x: min(x + 2, size.width - 28), y: 8), withAttributes: tick)
        ("\(k)" as NSString).draw(at: CGPoint(x: 10, y: min(y, size.height - 14)), withAttributes: tick)
      }
    }
    return jpeg(drawn)
  }

  private static func roleColor(_ role: BlockRole) -> UIColor {
    switch role {
    case .title, .heading: return UIColor(red: 0.85, green: 0, blue: 0.45, alpha: 1)
    case .paragraph, .abstract, .quote: return UIColor(red: 0, green: 0.3, blue: 0.9, alpha: 1)
    case .figure, .table, .equation, .code: return UIColor(red: 0, green: 0.55, blue: 0.1, alpha: 1)
    case .caption, .note, .footnote, .references, .list, .byline: return UIColor(red: 0.75, green: 0.42, blue: 0, alpha: 1)
    case .furniture, .minor: return UIColor(white: 0.5, alpha: 1)
    }
  }

  /// One page's blocks as the Paper look sets them, each numbered in the margin.
  static func clean(_ book: ImportedBook, page: Int) async -> Data? {
    let width: CGFloat = 900
    let margin: CGFloat = 70
    let sheet = Sheet(left: 0, width: Double(width - margin - 30), column: Double(width - margin - 30), gutter: 0, columns: 1, fontSize: 18)
    let setter = Typesetter(fontSize: sheet.fontSize, column: CGFloat(sheet.column), math: false, notes: book.noteLabels)
    let ids = Set(book.doc.blocks.filter { $0.pieces.contains { $0.page == page } }.map(\.id))
    let shown = book.proofEntries(sheet: sheet, traits: light, only: ids)
    // Pictures first, since the rest is drawn in one go.
    var pictures: [ObjectIdentifier: CGImage] = [:]
    for item in shown {
      if case let .block(b, _) = item, let sprite = b.sprite, let image = await sprite.atlas.picture(sprite.key) {
        pictures[ObjectIdentifier(b)] = image
      }
    }
    func tall(_ item: ImportedBook.ProofEntry) -> CGFloat {
      switch item {
      case let .block(b, _): return CGFloat(b.height)
      case let .text(_, t, _): return CGFloat(setter.layout(t).height) + 14
      }
    }
    let total = min(shown.reduce(CGFloat(40)) { $0 + tall($1) }, 2800)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let tag: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.systemRed]
    let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: max(total, 120)), format: format).image { r in
      let ctx = r.cgContext
      light.performAsCurrent {
        UIColor.white.setFill()
        r.fill(CGRect(x: 0, y: 0, width: width, height: max(total, 120)))
        var y: CGFloat = 20
        for item in shown where y < 2800 {
          switch item {
          case let .block(b, id):
            ctx.saveGState()
            ctx.translateBy(x: margin, y: y)
            b.layer.paint?(CGRect(origin: .zero, size: b.layer.bounds.size))
            if let inner = b.spriteFrame, let image = pictures[ObjectIdentifier(b)] {
              UIImage(cgImage: image).draw(in: inner)
            }
            ctx.restoreGState()
            if let id { ("#\(id)" as NSString).draw(at: CGPoint(x: 8, y: y + 2), withAttributes: tag) }
          case let .text(id, text, ink):
            let l = setter.layout(text)
            ctx.setFillColor(ink.cgColor)
            for w in l.words { drawPieces(w.glyphs.pieces, in: ctx, x: margin + w.x, baseline: y + w.y + setter.baseline) }
            ("#\(id)" as NSString).draw(at: CGPoint(x: 8, y: y + 2), withAttributes: tag)
          }
          y += tall(item)
        }
      }
    }
    return jpeg(image)
  }

  /// A page of the Magazine look, with every paragraph as a reader changing it would see it: set live, in the nearest font.
  static func typeset(_ book: ImportedBook, page: Int) async -> Data? {
    guard let info = book.doc.pages[safe: page],
      let raster = await book.atlas?.picture(PageAtlas.Key(page: page, pixels: wide, dark: false, crop: nil))
    else { return nil }
    let size = CGSize(width: raster.width, height: raster.height)
    let sheet = Sheet(left: 0, width: Double(size.width), column: Double(size.width), gutter: 0, columns: 1, fontSize: 12)
    let s = size.width / info.size.width
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
      UIImage(cgImage: raster).draw(in: CGRect(origin: .zero, size: size))
      let ctx = r.cgContext
      for (i, b) in book.paragraphs.enumerated() {
        guard let head = b.pieces.first, head.page == page else { continue }
        let box = CGRect(x: head.ink.minX * s, y: head.ink.minY * s, width: head.ink.width * s, height: head.ink.height * s)
        let setter = book.magazineSetter(i, sheet: sheet)
        UIColor.white.setFill()
        r.fill(box.insetBy(dx: -1, dy: -1))
        let l = setter.layout(b.text)
        ctx.setFillColor((book.ink(i, dark: false) ?? .black).cgColor)
        for w in l.words { drawPieces(w.glyphs.pieces, in: ctx, x: box.minX + w.x, baseline: box.minY + w.y + setter.baseline) }
      }
    }
    return jpeg(image)
  }
}
