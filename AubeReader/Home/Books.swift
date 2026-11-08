import CoreMotion
import UIKit

// ─── A book's particulars ────────────────────────────────────────────────────

/// How a document is bound, settled once and for all by its id.
@MainActor
struct BookSpec {
  enum Design: Int, CaseIterable { case gilt, label, plate, paperback, parcel }
  enum Foil {
    case gold, silver, copper
    case ink(UInt32)

    var stops: [UInt32]? {
      switch self {
      case .gold: [0x7a5a20, 0xd2b166, 0xf6e7b4, 0xb78e3d, 0x866526, 0xe9d08a, 0x96752f]
      case .silver: [0x777a7c, 0xc9cccc, 0xf4f5f2, 0xa5a8a8, 0x7e8182, 0xdfe1df, 0x8a8d8d]
      case .copper: [0x7b4322, 0xc78a5c, 0xf2c8a2, 0xb0693c, 0x83472a, 0xdda67c, 0x8f5230]
      case .ink: nil
      }
    }
    var inkColor: UIColor? {
      if case let .ink(v) = self { return UIColor(hex: v) }
      return nil
    }
  }

  let id: String
  let title: String
  let authors: [String]
  let seed: UInt64
  let design: Design
  let cloth: UInt32
  let foil: Foil
  let size: CGSize
  let thickness: CGFloat
  /// How many times larger than `size` it's shown. It's drawn as a book of `size`
  /// with finer pixels, so lettering and rules grow in proportion to the cover.
  var magnified: CGFloat = 1
  var shownSize: CGSize { CGSize(width: (size.width * magnified).rounded(), height: (size.height * magnified).rounded()) }

  /// The bindings a book may have, as a real run of old library bindings.
  private static let bindings: [(UInt32, Foil)] = [
    (0x6a1b1f, .gold), (0x1c4433, .gold), (0x1a2c52, .gold), (0x47234a, .gold), (0x154f58, .gold), (0x1d1a18, .gold),
    (0x8a3518, .gold), (0x4b5427, .gold), (0x25406a, .silver), (0x28423c, .copper), (0x7b2233, .gold),
    (0xd3c5a6, .ink(0x2a2017)), (0x9d9a8c, .ink(0x1d1712)), (0xb98a33, .ink(0x2a1a0c)), (0x6f8a84, .ink(0x14201d)),
  ]
  private static let stocks: [UInt32] = [0xb5402b, 0x1f5f6a, 0xd2902a, 0x2a4c7d, 0x4d6b47, 0x7c2f46]

  /// What's been settled about a book's look.
  struct Choice {
    var design: Design
    var binding: Int
    var stock: Int
  }

  /// What a document would choose for itself.
  private static func preference(_ id: String) -> Choice {
    var rng = Seeded(steadyHash(id + "/choice-1"))
    let roll = rng(0...1)
    let design: Design = roll < 0.34 ? .gilt : roll < 0.6 ? .label : roll < 0.85 ? .plate : .paperback
    return Choice(design: design, binding: Int.random(in: 0..<bindings.count, using: &rng), stock: Int.random(in: 0..<stocks.count, using: &rng))
  }

  /// Goes along the library letting each book have what it would choose, unless
  /// the books just before it have that binding, or that design, already.
  static func plan(_ ids: [String]) -> [String: Choice] {
    var plan: [String: Choice] = [:]
    var bindingsLately: [Int] = []
    var stocksLately: [Int] = []
    var designsLately: [Design] = []
    let designs: [Design] = [.gilt, .label, .plate, .paperback]
    for id in ids {
      var c = preference(id)
      var tries = 0
      while designsLately.suffix(1).contains(c.design), tries < 4 {
        c.design = designs[(designs.firstIndex(of: c.design)! + 1) % designs.count]
        tries += 1
      }
      while bindingsLately.suffix(5).contains(c.binding) { c.binding = (c.binding + 1) % bindings.count }
      while stocksLately.suffix(2).contains(c.stock) { c.stock = (c.stock + 1) % stocks.count }
      if c.design == .paperback { stocksLately.append(c.stock) } else { bindingsLately.append(c.binding) }
      designsLately.append(c.design)
      plan[id] = c
    }
    return plan
  }

  init(_ d: Document, unit: CGFloat, openable: Bool, choice: Choice?) {
    id = d.id
    title = d.title
    authors = d.authors
    seed = steadyHash(d.id + "/binding-3")
    var rng = Seeded(seed)
    let choice = choice ?? Self.preference(d.id)
    design = openable ? choice.design : .parcel
    let binding = Self.bindings[choice.binding]
    cloth = design == .paperback ? Self.stocks[choice.stock] : binding.0
    foil = binding.1
    let w = unit * rng(0.94...1.07)
    let h = unit * 1.42 * rng(0.93...1.05)
    size = CGSize(width: w.rounded(), height: h.rounded())
    var t = rng(20...38)
    if d.imported, let pages = Imports.shared.book(d.id)?.doc.pages.count {
      // A book as thick as it has pages.
      t = min(52, 15 + CGFloat(pages) * 0.42)
    }
    if design == .paperback { t *= 0.72 }
    thickness = t.rounded()
  }

  /// Whatever depends on what's drawn on it.
  var key: String { "\(id)|\(title)|\(design.rawValue)|\(size.width)x\(size.height)x\(thickness)x\(magnified)" }
}

// ─── A book's faces ──────────────────────────────────────────────────────────

/// Draws a book. Everything is drawn once and baked, and kept while there's room:
/// a book's cover, then the foil alone, so that a highlight can run over it.
@MainActor
enum BookArt {
  struct Faces {
    let cover: UIImage
    /// Where there's foil, as alpha; nil where nothing on the cover is metal.
    let foil: UIImage?
    let spine: UIImage
    let fore: UIImage
    let head: UIImage
  }

  private final class Box {
    let faces: Faces
    init(_ f: Faces) { faces = f }
  }
  private static let cache: NSCache<NSString, Box> = {
    let c = NSCache<NSString, Box>()
    c.countLimit = 60
    return c
  }()

  static func faces(_ spec: BookSpec, stamp: UIImage?, status: ImportEntry.Stage? = nil) -> Faces {
    let parcelState = spec.design == .parcel ? "\(status?.rawValue ?? "")" : ""
    let key = "\(spec.key)|\(stamp != nil)|\(parcelState)" as NSString
    if let box = cache.object(forKey: key) { return box.faces }
    let faces = make(spec, stamp: stamp, status: status)
    cache.setObject(Box(faces), forKey: key)
    return faces
  }

  /// Whether `faces` would have this book's ready at once.
  static func hasFaces(_ spec: BookSpec, stamp: UIImage?) -> Bool {
    cache.object(forKey: "\(spec.key)|\(stamp != nil)|" as NSString) != nil
  }

  /// How much finer than usual the faces being made are drawn.
  private static var magnifying: CGFloat = 1
  private static var scale: CGFloat { max(2, UITraitCollection.current.displayScale) * magnifying }

  private static func render(_ size: CGSize, opaque: Bool = false, _ draw: (CGContext) -> Void) -> UIImage {
    let f = UIGraphicsImageRendererFormat()
    f.scale = scale
    f.opaque = opaque
    return UIGraphicsImageRenderer(size: size, format: f).image { draw($0.cgContext) }
  }

  /// A gradient between two points, painting nothing beyond them unless it's to `extend`.
  static func gradient(_ ctx: CGContext, _ colors: [UIColor], _ locations: [CGFloat]? = nil, from: CGPoint, to: CGPoint, extend: Bool = false) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let g = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: locations) else { return }
    ctx.drawLinearGradient(g, start: from, end: to, options: extend ? [.drawsBeforeStartLocation, .drawsAfterEndLocation] : [])
  }

  private static func make(_ spec: BookSpec, stamp: UIImage?, status: ImportEntry.Stage?) -> Faces {
    magnifying = spec.magnified
    defer { magnifying = 1 }
    let size = spec.size
    var mask: UIImage?
    var over: ((CGContext, CGRect) -> Void)?
    switch spec.design {
    case .gilt: mask = render(size) { gilt($0, spec, stamp) }
    case .plate: mask = render(size) { plate($0, spec, stamp) }
    case .label:
      mask = render(size) { labelFoil($0, spec) }
      over = { ctx, _ in label(ctx, spec, stamp) }
    case .paperback, .parcel: break
    }
    let cover: UIImage
    switch spec.design {
    case .paperback: cover = paperback(spec, stamp)
    case .parcel: cover = parcel(spec, status)
    default:
      cover = render(size) { ctx in
        let r = CGRect(origin: .zero, size: size)
        boards(ctx, r, spec)
        if let mask { foiled(ctx, r, mask, spec) }
        over?(ctx, r)
        finish(ctx, r, spec)
      }
    }
    return Faces(
      cover: cover,
      foil: spec.foil.stops == nil ? nil : mask,
      spine: spine(spec),
      fore: fore(spec),
      head: head(spec))
  }

  // ─── Cloth boards ──────────────────────────────────────────────────────

  private static func boardOutline(_ r: CGRect) -> UIBezierPath {
    UIBezierPath(
      roundedRect: r, byRoundingCorners: [.topRight, .bottomRight], cornerRadii: CGSize(width: 2.6, height: 2.6))
  }

  /// The boards in their cloth: the weave, a little mottling, light falling from
  /// above, and the groove of the hinge beside the spine.
  private static func boards(_ ctx: CGContext, _ r: CGRect, _ spec: BookSpec) {
    boardOutline(r).addClip()
    let base = UIColor(hex: spec.cloth)
    base.setFill()
    ctx.fill(r)
    ctx.saveGState()
    ctx.setBlendMode(.overlay)
    ctx.setAlpha(0.42)
    ctx.setPatternPhase(CGSize(width: CGFloat(spec.seed % 90), height: CGFloat(spec.seed >> 8 % 90)))
    Cloth.weave(scale: scale).setFill()
    ctx.fill(r)
    ctx.restoreGState()
    var rng = Seeded(spec.seed ^ 0xABC)
    // Mottling: the cloth has faded unevenly.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    for _ in 0..<7 {
      let at = CGPoint(x: rng(0...1) * r.width, y: rng(0...1) * r.height)
      let radius = rng(0.25...0.6) * r.width
      let pale = rng(0...1) < 0.5
      let c = pale ? UIColor(white: 1, alpha: rng(0.018...0.05)) : UIColor(white: 0, alpha: rng(0.03...0.08))
      let g = CGGradient(colorsSpace: space, colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
      ctx.drawRadialGradient(g, startCenter: at, startRadius: 0, endCenter: at, endRadius: radius, options: [])
    }
    // Light from above and a little to the left.
    gradient(
      ctx, [UIColor(white: 1, alpha: 0.13), UIColor(white: 1, alpha: 0), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.2)],
      [0, 0.34, 0.62, 1], from: CGPoint(x: r.width * 0.2, y: 0), to: CGPoint(x: r.width * 0.55, y: r.height), extend: true)
    hinge(ctx, r)
  }

  /// The groove the cover turns in: dark at the bottom of it, a highlight on its far wall.
  private static func hinge(_ ctx: CGContext, _ r: CGRect) {
    let w = r.width
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: w * 0.125, height: r.height))
    gradient(
      ctx,
      [
        UIColor(white: 0, alpha: 0.32), UIColor(white: 0, alpha: 0.05), UIColor(white: 1, alpha: 0.05), UIColor(white: 0, alpha: 0),
        UIColor(white: 0, alpha: 0.36), UIColor(white: 1, alpha: 0.13), UIColor(white: 1, alpha: 0),
      ],
      [0, 0.26, 0.42, 0.54, 0.72, 0.82, 1], from: CGPoint(x: 0, y: 0), to: CGPoint(x: w * 0.125, y: 0))
    ctx.restoreGState()
  }

  /// Foil pressed into the cloth: a shadow on the wall the light comes over, a
  /// catch of light on the wall opposite, and the metal itself, worn in specks.
  private static func foiled(_ ctx: CGContext, _ r: CGRect, _ mask: UIImage, _ spec: BookSpec) {
    mask.draw(in: r.offsetBy(dx: 0, dy: -0.55), blendMode: .normal, alpha: 0.5)
    mask.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: r.offsetBy(dx: 0, dy: 0.7), blendMode: .normal, alpha: 0.17)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    mask.draw(in: r)
    ctx.setBlendMode(.sourceIn)
    if let stops = spec.foil.stops {
      gradient(ctx, stops.map { UIColor(hex: $0) }, nil, from: CGPoint(x: 0, y: 0), to: CGPoint(x: r.width * 0.55, y: r.height), extend: true)
    } else {
      (spec.foil.inkColor ?? .black).setFill()
      ctx.fill(r)
    }
    // Where the foil has worn off.
    ctx.setBlendMode(.destinationOut)
    var rng = Seeded(spec.seed ^ 0x1F01)
    UIColor(white: 0, alpha: 1).setFill()
    for _ in 0..<Int(r.width * r.height / 90) {
      let d = rng(0.25...0.8)
      ctx.setAlpha(rng(0.2...0.85))
      ctx.fillEllipse(in: CGRect(x: rng(0...1) * r.width, y: rng(0...1) * r.height, width: d, height: d))
    }
    ctx.setAlpha(1)
    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()
  }

  /// The edges of the boards: rubbed pale where hands have got at them, lit along
  /// the top, dark along the foot.
  private static func finish(_ ctx: CGContext, _ r: CGRect, _ spec: BookSpec) {
    var rng = Seeded(spec.seed ^ 0xED6E)
    ctx.saveGState()
    let outline = boardOutline(r.insetBy(dx: 0.4, dy: 0.4)).cgPath
    ctx.addPath(outline)
    ctx.setStrokeColor(UIColor(white: 1, alpha: 0.13).cgColor)
    ctx.setLineWidth(1.1)
    ctx.strokePath()
    // Corners rub through first.
    for corner in [CGPoint(x: r.maxX, y: 0), CGPoint(x: r.maxX, y: r.maxY)] {
      for _ in 0..<26 {
        let d = rng(0.3...1.3)
        let reach = rng(0...7)
        let angle = rng(0...(2 * .pi))
        ctx.setFillColor(UIColor(white: 1, alpha: rng(0.03...0.17)).cgColor)
        ctx.fillEllipse(in: CGRect(x: corner.x + cos(angle) * reach - d / 2, y: corner.y + sin(angle) * reach - d / 2, width: d, height: d))
      }
    }
    ctx.restoreGState()
    UIColor(white: 1, alpha: 0.24).setFill()
    ctx.fill(CGRect(x: r.minX, y: 0, width: r.width, height: 0.5))
    UIColor(white: 0, alpha: 0.42).setFill()
    ctx.fill(CGRect(x: r.minX, y: r.maxY - 0.75, width: r.width, height: 0.75))
    UIColor(white: 1, alpha: 0.07).setFill()
    ctx.fill(CGRect(x: r.maxX - 0.5, y: 0, width: 0.5, height: r.height))
  }

  // ─── Lettering ─────────────────────────────────────────────────────────

  private static func style(_ align: NSTextAlignment, _ leading: CGFloat, _ size: CGFloat) -> NSParagraphStyle {
    let s = NSMutableParagraphStyle()
    s.alignment = align
    s.lineBreakMode = .byWordWrapping
    s.minimumLineHeight = (size * leading).rounded()
    s.maximumLineHeight = (size * leading).rounded()
    return s
  }

  /// `text` at the largest size that fits, with no word broken, drawn in `rect`
  /// and centred in it upright; where it ended up is returned.
  @discardableResult
  static func letter(
    _ text: String, in rect: CGRect, font: (CGFloat) -> UIFont, largest: CGFloat, smallest: CGFloat, color: UIColor = .black,
    align: NSTextAlignment = .center, leading: CGFloat = 1.14, tracking: CGFloat = 0, valign: CGFloat = 0.5
  ) -> CGRect {
    var size = largest
    var attributed = NSAttributedString()
    var fitted = CGRect.zero
    let longest = text.split(separator: " ").map(String.init)
    while true {
      let f = font(size)
      let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: style(align, leading, size), .kern: tracking]
      attributed = NSAttributedString(string: text, attributes: attrs)
      fitted = attributed.boundingRect(
        with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
      let widest = longest.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
      if (fitted.height <= rect.height && widest <= rect.width) || size <= smallest { break }
      size -= 0.5
    }
    let h = min(rect.height, ceil(fitted.height))
    let at = CGRect(x: rect.minX, y: rect.minY + ((rect.height - h) * valign), width: rect.width, height: h)
    attributed.draw(with: at, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
    return at
  }

  static func named(_ name: String, _ size: CGFloat) -> UIFont { UIFont(name: name, size: size) ?? Face.serif(size) }

  /// `image`, keeping its shape, fit in `rect` and centred; `tint` if given. Where it landed is returned.
  @discardableResult
  static func place(_ image: UIImage, in rect: CGRect, tint: UIColor? = nil) -> CGRect {
    let k = min(rect.width / image.size.width, rect.height / image.size.height)
    let w = image.size.width * k
    let h = image.size.height * k
    let at = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    (tint.map { image.withTintColor($0, renderingMode: .alwaysOriginal) } ?? image).draw(in: at)
    return at
  }

  /// What stands in on a cover until a drawing comes, or if none does.
  private static func fleuron(in rect: CGRect, color: UIColor = .black) {
    let size = min(rect.height * 0.5, 34)
    letter("❦", in: rect, font: { named("ZapfDingbatsITC", $0) }, largest: size, smallest: size, color: color, leading: 1)
  }

  private static func rule(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat) {
    ctx.setStrokeColor(UIColor.black.cgColor)
    ctx.setLineWidth(width)
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
  }

  private static func diamond(_ ctx: CGContext, at p: CGPoint, _ r: CGFloat) {
    ctx.setFillColor(UIColor.black.cgColor)
    ctx.move(to: CGPoint(x: p.x, y: p.y - r))
    ctx.addLine(to: CGPoint(x: p.x + r, y: p.y))
    ctx.addLine(to: CGPoint(x: p.x, y: p.y + r))
    ctx.addLine(to: CGPoint(x: p.x - r, y: p.y))
    ctx.closePath()
    ctx.fillPath()
  }

  // ─── Designs ───────────────────────────────────────────────────────────

  private static func field(_ size: CGSize) -> CGRect {
    CGRect(x: size.width * 0.15, y: size.height * 0.052, width: size.width * 0.79, height: size.height * 0.896)
  }

  /// A gilt double frame, a rule with a lozenge under the title, the drawing below it, and the authors at the foot.
  private static func gilt(_ ctx: CGContext, _ spec: BookSpec, _ stamp: UIImage?) {
    let f = field(spec.size)
    ctx.setStrokeColor(UIColor.black.cgColor)
    ctx.setLineWidth(1.15)
    ctx.stroke(f)
    let inner = f.insetBy(dx: 3.2, dy: 3.2)
    ctx.setLineWidth(0.45)
    ctx.stroke(inner)
    for p in [CGPoint(x: inner.minX + 5, y: inner.minY + 5), CGPoint(x: inner.maxX - 5, y: inner.minY + 5), CGPoint(x: inner.minX + 5, y: inner.maxY - 5), CGPoint(x: inner.maxX - 5, y: inner.maxY - 5)] {
      diamond(ctx, at: p, 1.7)
    }
    let w = inner.width - 14
    let x = inner.minX + 7
    let foot = spec.authors.isEmpty ? inner.maxY - 8 : inner.maxY - 26
    letter(
      spec.title, in: CGRect(x: x, y: inner.minY + 11, width: w, height: inner.height * 0.40), font: { named("Baskerville-SemiBold", $0) }, largest: 19,
      smallest: 10.5, leading: 1.13, valign: 0.42)
    let ruleY = inner.minY + 11 + inner.height * 0.40 + 8
    let cx = inner.midX
    rule(ctx, from: CGPoint(x: cx - 24, y: ruleY), to: CGPoint(x: cx - 5, y: ruleY), width: 0.6)
    rule(ctx, from: CGPoint(x: cx + 5, y: ruleY), to: CGPoint(x: cx + 24, y: ruleY), width: 0.6)
    diamond(ctx, at: CGPoint(x: cx, y: ruleY), 2.2)
    let drawing = CGRect(x: x + 1, y: ruleY + 8, width: w - 2, height: foot - ruleY - 12)
    if let stamp {
      // Pressed twice over, so that the faint lines hold in metal.
      place(stamp, in: drawing)
      place(stamp, in: drawing)
    } else {
      fleuron(in: drawing)
    }
    if !spec.authors.isEmpty {
      letter(
        Face.authors(spec.authors), in: CGRect(x: x, y: inner.maxY - 24, width: w, height: 18), font: { named("Baskerville-Italic", $0) }, largest: 10.5, smallest: 8,
        leading: 1.05, valign: 0.6)
    }
  }

  /// The drawing large and alone, the title in engraver's capitals above it,
  /// between a thick and a thin rule that run from hinge to edge.
  private static func plate(_ ctx: CGContext, _ spec: BookSpec, _ stamp: UIImage?) {
    let size = spec.size
    let left = size.width * 0.15
    let right = size.width * 0.94
    let w = right - left
    let top = size.height * 0.07
    rule(ctx, from: CGPoint(x: left, y: top), to: CGPoint(x: right, y: top), width: 1.5)
    rule(ctx, from: CGPoint(x: left, y: top + 3), to: CGPoint(x: right, y: top + 3), width: 0.45)
    let bottom = size.height * 0.93
    rule(ctx, from: CGPoint(x: left, y: bottom), to: CGPoint(x: right, y: bottom), width: 1.5)
    rule(ctx, from: CGPoint(x: left, y: bottom - 3), to: CGPoint(x: right, y: bottom - 3), width: 0.45)
    let titled = letter(
      spec.title.uppercased(), in: CGRect(x: left, y: top + 11, width: w, height: size.height * 0.33), font: { named("Copperplate", $0) }, largest: 15.5,
      smallest: 8.5, leading: 1.18, tracking: 0.5, valign: 0.15)
    let foot = spec.authors.isEmpty ? bottom - 8 : bottom - 26
    let drawing = CGRect(x: left - 1, y: max(titled.maxY + 8, size.height * 0.38), width: w + 2, height: foot - max(titled.maxY + 8, size.height * 0.38))
    if let stamp {
      place(stamp, in: drawing)
      place(stamp, in: drawing)
    } else {
      fleuron(in: drawing)
    }
    if !spec.authors.isEmpty {
      letter(
        Face.authors(spec.authors).uppercased(), in: CGRect(x: left, y: bottom - 22, width: w, height: 16), font: { named("Copperplate", $0) }, largest: 8, smallest: 6.5, leading: 1.05,
        tracking: 0.5, valign: 0.6)
    }
  }

  private static func labelRect(_ size: CGSize) -> CGRect {
    CGRect(x: size.width * 0.17, y: size.height * 0.1, width: size.width * 0.75, height: size.height * 0.66)
  }

  /// Gilt lines above and below the pasted label, and the authors under it.
  private static func labelFoil(_ ctx: CGContext, _ spec: BookSpec) {
    let size = spec.size
    let l = labelRect(size)
    let top = size.height * 0.052
    let bottom = size.height * 0.948
    rule(ctx, from: CGPoint(x: l.minX, y: top), to: CGPoint(x: l.maxX, y: top), width: 0.9)
    rule(ctx, from: CGPoint(x: l.minX, y: bottom), to: CGPoint(x: l.maxX, y: bottom), width: 0.9)
    if !spec.authors.isEmpty {
      letter(
        Face.authors(spec.authors), in: CGRect(x: l.minX, y: l.maxY + 5, width: l.width, height: bottom - l.maxY - 10), font: { named("Baskerville-Italic", $0) }, largest: 11.5, smallest: 8)
    } else {
      diamond(ctx, at: CGPoint(x: l.midX, y: (l.maxY + bottom) / 2), 2.6)
    }
  }

  /// A label of paper pasted to the cloth, printed in black and gone a little
  /// brown, the title on it and the drawing under that.
  private static func label(_ ctx: CGContext, _ spec: BookSpec, _ stamp: UIImage?) {
    let l = labelRect(spec.size)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0.8), blur: 1.6, color: UIColor(white: 0, alpha: 0.55).cgColor)
    UIColor(hex: 0xe9dfc8).setFill()
    ctx.fill(l)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.clip(to: l)
    var rng = Seeded(spec.seed ^ 0xFAB)
    // Foxing, and browning in from the edges.
    for _ in 0..<26 {
      let d = rng(0.5...2.4)
      ctx.setFillColor(UIColor(red: 0.5, green: 0.33, blue: 0.14, alpha: rng(0.04...0.2)).cgColor)
      ctx.fillEllipse(in: CGRect(x: l.minX + rng(0...1) * l.width, y: l.minY + rng(0...1) * l.height, width: d, height: d))
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let tan = UIColor(red: 0.47, green: 0.33, blue: 0.16, alpha: 0.26)
    let g = CGGradient(colorsSpace: space, colors: [UIColor.clear.cgColor, UIColor.clear.cgColor, tan.cgColor] as CFArray, locations: [0, 0.55, 1])!
    let c = CGPoint(x: l.midX, y: l.midY)
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: l.width / l.height, y: 1)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: l.height * 0.66, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    let ink = UIColor(hex: 0x1c1610)
    ctx.setStrokeColor(ink.cgColor)
    ctx.setLineWidth(1)
    ctx.stroke(l.insetBy(dx: 3.6, dy: 3.6))
    ctx.setLineWidth(0.4)
    ctx.stroke(l.insetBy(dx: 5.8, dy: 5.8))
    let inner = l.insetBy(dx: 10, dy: 10)
    let titled = letter(
      spec.title, in: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * 0.58), font: { named("HoeflerText-Black", $0) }, largest: 16, smallest: 9, color: ink,
      leading: 1.12, valign: 0.15)
    let drawing = CGRect(x: inner.minX, y: titled.maxY + 5, width: inner.width, height: inner.maxY - titled.maxY - 5)
    if let stamp { place(stamp, in: drawing, tint: ink) } else { fleuron(in: drawing, color: ink) }
  }

  /// A paperback: a block of color with the title reversed out of it, stock
  /// below with the drawing printed on it, a crease where the cover's been
  /// bent, and a laminate that catches the light.
  private static func paperback(_ spec: BookSpec, _ stamp: UIImage?) -> UIImage {
    let size = spec.size
    return render(size) { ctx in
      let r = CGRect(origin: .zero, size: size)
      UIBezierPath(roundedRect: r, byRoundingCorners: [.topRight, .bottomRight], cornerRadii: CGSize(width: 1.6, height: 1.6)).addClip()
      UIColor(hex: 0xf1ebdc).setFill()
      ctx.fill(r)
      let block = CGRect(x: 0, y: 0, width: size.width, height: (size.height * 0.5).rounded())
      UIColor(hex: spec.cloth).setFill()
      ctx.fill(block)
      let left = size.width * 0.115
      let w = size.width * 0.82
      letter(
        spec.title, in: CGRect(x: left, y: 14, width: w, height: block.height - 34), font: { UIFont(name: "AvenirNext-Bold", size: $0) ?? .boldSystemFont(ofSize: $0) }, largest: 21, smallest: 10,
        color: UIColor(hex: 0xfaf5e8), align: .left, leading: 1.07, tracking: -0.2, valign: 0)
      if !spec.authors.isEmpty {
        letter(
          Face.authors(spec.authors), in: CGRect(x: left, y: block.maxY - 19, width: w, height: 13), font: { UIFont(name: "AvenirNext-Medium", size: $0) ?? .systemFont(ofSize: $0) }, largest: 9, smallest: 7,
          color: UIColor(hex: 0xfaf5e8, alpha: 0.86), align: .left, leading: 1.1, valign: 1)
      }
      let ink = UIColor(hex: 0x1a1612)
      let drawing = CGRect(x: left, y: block.maxY + 12, width: w, height: size.height - block.maxY - 24)
      if let stamp { place(stamp, in: drawing, tint: ink) } else { fleuron(in: drawing, color: ink) }
      // The crease, and where it's cracked the print.
      ctx.setFillColor(UIColor(white: 1, alpha: 0.28).cgColor)
      ctx.fill(CGRect(x: size.width * 0.045, y: 0, width: 0.8, height: size.height))
      ctx.setFillColor(UIColor(white: 0, alpha: 0.2).cgColor)
      ctx.fill(CGRect(x: size.width * 0.045 + 0.8, y: 0, width: 0.8, height: size.height))
      gradient(ctx, [UIColor(white: 0, alpha: 0.24), UIColor(white: 0, alpha: 0)], nil, from: .zero, to: CGPoint(x: size.width * 0.04, y: 0))
      // Laminate: one soft sweep of reflected window, and worn corners.
      gradient(
        ctx, [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.13), UIColor(white: 1, alpha: 0), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.13)],
        [0.1, 0.27, 0.45, 0.62, 1], from: CGPoint(x: 0, y: 0), to: CGPoint(x: size.width * 0.5, y: size.height), extend: true)
      var rng = Seeded(spec.seed ^ 0xBEE)
      for corner in [CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height)] {
        for _ in 0..<18 {
          let d = rng(0.3...1)
          let reach = rng(0...5)
          let angle = rng(0...(2 * .pi))
          ctx.setFillColor(UIColor(white: 1, alpha: rng(0.08...0.32)).cgColor)
          ctx.fillEllipse(in: CGRect(x: corner.x + cos(angle) * reach - d / 2, y: corner.y + sin(angle) * reach - d / 2, width: d, height: d))
        }
      }
    }
  }

  /// A document still on its way in hasn't been bound yet: it comes in brown
  /// paper tied up with string, addressed on a label by its file's name. One
  /// that's locked has a seal on it; one that couldn't be read, a stamp.
  private static func parcel(_ spec: BookSpec, _ status: ImportEntry.Stage?) -> UIImage {
    let size = spec.size
    return render(size) { ctx in
      let r = CGRect(origin: .zero, size: size)
      var rng = Seeded(spec.seed ^ 0xC0DE)
      UIColor(hex: 0xb4946a).setFill()
      ctx.fill(r)
      // The paper's long fibres.
      ctx.setLineCap(.round)
      for _ in 0..<420 {
        let p = CGPoint(x: rng(0...1) * size.width, y: rng(0...1) * size.height)
        let length = rng(2...11)
        let angle = rng(-0.5...0.5)
        let pale = rng(0...1) < 0.5
        ctx.setStrokeColor((pale ? UIColor(hex: 0xe4cfa8, alpha: rng(0.08...0.3)) : UIColor(hex: 0x5c432a, alpha: rng(0.06...0.24))).cgColor)
        ctx.setLineWidth(rng(0.25...0.6))
        ctx.move(to: p)
        ctx.addLine(to: CGPoint(x: p.x + cos(angle) * length, y: p.y + sin(angle) * length))
        ctx.strokePath()
      }
      // Where the wrapping's been folded over the boards.
      for (a, b) in [
        (CGPoint(x: 0, y: size.height * 0.2), CGPoint(x: size.width * 0.2, y: 0)), (CGPoint(x: size.width, y: size.height * 0.84), CGPoint(x: size.width * 0.76, y: size.height)),
      ] {
        ctx.setStrokeColor(UIColor(white: 0, alpha: 0.13).cgColor)
        ctx.setLineWidth(1.4)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.13).cgColor)
        ctx.setLineWidth(0.7)
        ctx.move(to: CGPoint(x: a.x + 1.2, y: a.y + 1.2))
        ctx.addLine(to: CGPoint(x: b.x + 1.2, y: b.y + 1.2))
        ctx.strokePath()
      }
      gradient(ctx, [UIColor(white: 1, alpha: 0.13), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.2)], [0, 0.4, 1], from: .zero, to: CGPoint(x: size.width * 0.4, y: size.height), extend: true)
      // The address label.
      let tag = CGRect(x: size.width * 0.14, y: size.height * 0.5, width: size.width * 0.72, height: size.height * 0.28)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 0.7), blur: 1.2, color: UIColor(white: 0, alpha: 0.42).cgColor)
      UIColor(hex: 0xf2ead8).setFill()
      ctx.fill(tag)
      ctx.restoreGState()
      letter(
        spec.title, in: tag.insetBy(dx: 7, dy: 5), font: { named("Courier", $0) }, largest: 11, smallest: 7.5, color: UIColor(hex: 0x2c2620), align: .left, leading: 1.16, valign: 0.15)
      // String, tied at the crossing.
      let knot = CGPoint(x: size.width * 0.5, y: size.height * 0.33)
      func string(_ a: CGPoint, _ b: CGPoint) {
        ctx.setLineCap(.round)
        ctx.setStrokeColor(UIColor(white: 0, alpha: 0.32).cgColor)
        ctx.setLineWidth(2.3)
        ctx.move(to: CGPoint(x: a.x + 0.3, y: a.y + 0.9))
        ctx.addLine(to: CGPoint(x: b.x + 0.3, y: b.y + 0.9))
        ctx.strokePath()
        ctx.setStrokeColor(UIColor(hex: 0xe9dcc0).cgColor)
        ctx.setLineWidth(1.7)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setStrokeColor(UIColor(hex: 0x8d7a58, alpha: 0.85).cgColor)
        ctx.setLineWidth(1.7)
        ctx.setLineDash(phase: 0, lengths: [0.8, 1.9])
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
      }
      string(CGPoint(x: knot.x, y: 0), CGPoint(x: knot.x, y: tag.minY))
      string(CGPoint(x: knot.x, y: tag.maxY), CGPoint(x: knot.x, y: size.height))
      string(CGPoint(x: 0, y: knot.y), CGPoint(x: size.width, y: knot.y))
      func loop(_ dx: CGFloat) {
        let p = UIBezierPath()
        p.move(to: knot)
        p.addCurve(to: CGPoint(x: knot.x + dx, y: knot.y - 2), controlPoint1: CGPoint(x: knot.x + dx * 0.3, y: knot.y - 15), controlPoint2: CGPoint(x: knot.x + dx * 1.1, y: knot.y - 14))
        p.addCurve(to: knot, controlPoint1: CGPoint(x: knot.x + dx * 0.9, y: knot.y + 5), controlPoint2: CGPoint(x: knot.x + dx * 0.3, y: knot.y + 3))
        ctx.setStrokeColor(UIColor(hex: 0xe9dcc0).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(p.cgPath)
        ctx.strokePath()
      }
      loop(-17)
      loop(17)
      ctx.setFillColor(UIColor(hex: 0xd9c9a7).cgColor)
      ctx.fillEllipse(in: CGRect(x: knot.x - 3, y: knot.y - 2.6, width: 6, height: 5.2))
      if status == .locked {
        // A blob of red wax, pressed flat.
        let c = CGPoint(x: size.width * 0.72, y: size.height * 0.2)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(
          colorsSpace: space, colors: [UIColor(hex: 0xc23a32).cgColor, UIColor(hex: 0x8f1d1c).cgColor, UIColor(hex: 0x5e0f10).cgColor] as CFArray, locations: [0, 0.7, 1])!
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor(white: 0, alpha: 0.5).cgColor)
        ctx.addEllipse(in: CGRect(x: c.x - 15, y: c.y - 14, width: 30, height: 28.5))
        ctx.setFillColor(UIColor(hex: 0x8f1d1c).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - 15, y: c.y - 14, width: 30, height: 28.5))
        ctx.clip()
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - 5, y: c.y - 6), startRadius: 0, endCenter: c, endRadius: 17, options: [])
        ctx.restoreGState()
        letter("A", in: CGRect(x: c.x - 12, y: c.y - 11, width: 24, height: 22), font: { named("Baskerville-Bold", $0) }, largest: 18, smallest: 18, color: UIColor(hex: 0x5e0f10), leading: 1.15)
      } else if status == .failed {
        ctx.saveGState()
        ctx.translateBy(x: size.width * 0.5, y: size.height * 0.2)
        ctx.rotate(by: -0.14)
        let red = UIColor(hex: 0x9e2820, alpha: 0.78)
        let box = CGRect(x: -size.width * 0.4, y: -12, width: size.width * 0.8, height: 24)
        ctx.setStrokeColor(red.cgColor)
        ctx.setLineWidth(1.6)
        ctx.stroke(box)
        letter("UNREADABLE", in: box.insetBy(dx: 3, dy: 3), font: { named("Courier-Bold", $0) }, largest: 13, smallest: 8, color: red, leading: 1.2)
        ctx.restoreGState()
      }
    }
  }

  // ─── The other faces ───────────────────────────────────────────────────

  /// The spine: rounded, so lit along its middle, with raised bands ruled in foil.
  private static func spine(_ spec: BookSpec) -> UIImage {
    let size = CGSize(width: spec.thickness, height: spec.size.height)
    return render(size, opaque: true) { ctx in
      let r = CGRect(origin: .zero, size: size)
      UIColor(hex: spec.design == .parcel ? 0xa78860 : spec.cloth).setFill()
      ctx.fill(r)
      if spec.design != .paperback && spec.design != .parcel {
        ctx.saveGState()
        ctx.setBlendMode(.overlay)
        ctx.setAlpha(0.42)
        Cloth.weave(scale: scale).setFill()
        ctx.fill(r)
        ctx.restoreGState()
        let stops = spec.foil.stops ?? [0x2a2017]
        let gilt = UIColor(hex: stops[stops.count / 2], alpha: 0.9)
        for share in [0.13, 0.29, 0.71, 0.87] as [CGFloat] {
          let y = size.height * share
          gradient(
            ctx, [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.3), UIColor(white: 1, alpha: 0.22), UIColor(white: 0, alpha: 0.32), UIColor(white: 0, alpha: 0)], nil,
            from: CGPoint(x: 0, y: y - 3.5), to: CGPoint(x: 0, y: y + 3.5))
          ctx.setFillColor(gilt.cgColor)
          ctx.fill(CGRect(x: 0, y: y - 3.3, width: size.width, height: 0.55))
          ctx.fill(CGRect(x: 0, y: y + 2.8, width: size.width, height: 0.55))
        }
      }
      // Roundness, and the turn into the boards at either side.
      gradient(
        ctx, [UIColor(white: 0, alpha: 0.5), UIColor(white: 0, alpha: 0.05), UIColor(white: 1, alpha: 0.12), UIColor(white: 0, alpha: 0.05), UIColor(white: 0, alpha: 0.55)],
        [0, 0.24, 0.5, 0.76, 1], from: .zero, to: CGPoint(x: size.width, y: 0))
      gradient(ctx, [UIColor(white: 1, alpha: 0.07), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.2)], [0, 0.4, 1], from: .zero, to: CGPoint(x: 0, y: size.height))
    }
  }

  private static func pageLines(_ ctx: CGContext, _ r: CGRect, along vertical: Bool, seed: UInt64) {
    var rng = Seeded(seed)
    let across = vertical ? r.width : r.height
    let count = Int(across * 1.9)
    for i in 0..<count {
      let at = (vertical ? r.minX : r.minY) + CGFloat(i) / CGFloat(max(1, count)) * across
      let thick = rng(0.18...0.42)
      let dark = rng(0...1) < 0.72
      ctx.setFillColor((dark ? UIColor(hex: 0x5c4a30, alpha: rng(0.05...0.3)) : UIColor(white: 1, alpha: rng(0.08...0.45))).cgColor)
      ctx.fill(vertical ? CGRect(x: at, y: r.minY, width: thick, height: r.height) : CGRect(x: r.minX, y: at, width: r.width, height: thick))
    }
  }

  /// The fore-edge: boards front and back, and the block of pages set back between them, hollowed a little.
  private static func fore(_ spec: BookSpec) -> UIImage {
    let size = CGSize(width: spec.thickness, height: spec.size.height)
    let paperback = spec.design == .paperback
    return render(size, opaque: true) { ctx in
      let r = CGRect(origin: .zero, size: size)
      let board: CGFloat = paperback ? 0.6 : 1.9
      UIColor(hex: spec.design == .parcel ? 0xa78860 : spec.cloth).setFill()
      ctx.fill(r)
      let pages = r.insetBy(dx: board, dy: paperback ? 0 : 1.8)
      UIColor(hex: 0x17110a).setFill()
      ctx.fill(CGRect(x: board, y: 0, width: size.width - 2 * board, height: size.height))
      if spec.design == .parcel {
        UIColor(hex: 0xa78860).setFill()
        ctx.fill(r)
        return
      }
      UIColor(hex: 0xe6dcc5).setFill()
      ctx.fill(pages)
      pageLines(ctx, pages, along: true, seed: spec.seed ^ 0x77)
      ctx.saveGState()
      ctx.clip(to: pages)
      gradient(
        ctx, [UIColor(white: 0, alpha: 0.26), UIColor(white: 0, alpha: 0.03), UIColor(white: 0, alpha: 0.13), UIColor(white: 0, alpha: 0.03), UIColor(white: 0, alpha: 0.3)],
        [0, 0.2, 0.52, 0.8, 1], from: CGPoint(x: pages.minX, y: 0), to: CGPoint(x: pages.maxX, y: 0))
      gradient(ctx, [UIColor(white: 1, alpha: 0.12), UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.32)], [0, 0.3, 1], from: .zero, to: CGPoint(x: 0, y: size.height))
      ctx.restoreGState()
    }
  }

  /// The head: the pages from above, between the boards, with a headband at the spine.
  private static func head(_ spec: BookSpec) -> UIImage {
    let size = CGSize(width: spec.size.width, height: spec.thickness)
    let paperback = spec.design == .paperback
    return render(size, opaque: true) { ctx in
      let r = CGRect(origin: .zero, size: size)
      let board: CGFloat = paperback ? 0.6 : 1.9
      let cloth = UIColor(hex: spec.design == .parcel ? 0xc0a27a : spec.cloth)
      cloth.setFill()
      ctx.fill(r)
      if spec.design == .parcel { return }
      let pages = CGRect(x: paperback ? 0 : 3.5, y: board, width: size.width - (paperback ? 0 : 5.5), height: size.height - 2 * board)
      UIColor(hex: 0xece3cd).setFill()
      ctx.fill(pages)
      pageLines(ctx, pages, along: false, seed: spec.seed ^ 0x99)
      if !paperback {
        // A headband of two colors of silk.
        let band = CGRect(x: pages.minX, y: pages.minY, width: 3, height: pages.height)
        UIColor(hex: 0xa22b24).setFill()
        ctx.fill(band)
        ctx.setFillColor(UIColor(hex: 0xf0e4c8, alpha: 0.9).cgColor)
        var y = band.minY
        while y < band.maxY {
          ctx.fill(CGRect(x: band.minX, y: y, width: band.width, height: 0.9))
          y += 2.1
        }
      }
      ctx.saveGState()
      ctx.clip(to: pages)
      gradient(ctx, [UIColor(white: 0, alpha: 0.42), UIColor(white: 0, alpha: 0.05), UIColor(white: 0, alpha: 0.12)], [0, 0.55, 1], from: CGPoint(x: 0, y: pages.minY), to: CGPoint(x: 0, y: pages.maxY))
      ctx.restoreGState()
    }
  }

  /// The inside of the cover: marbled endpaper, combed from the book's own colors.
  static func inside(_ spec: BookSpec) -> UIImage {
    let w = 90
    let h = Int(90 * spec.size.height / spec.size.width)
    let base = UIColor(hex: spec.cloth)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    base.getRed(&r, green: &g, blue: &b, alpha: nil)
    let a = SIMD3<Float>(Float(r), Float(g), Float(b))
    let pale = SIMD3<Float>(0.91, 0.85, 0.72)
    let gold = SIMD3<Float>(0.7, 0.54, 0.26)
    let seed = Float(spec.seed % 1000) / 7
    let cg = Wood.bitmap(w, h) { px, stride in
      for y in 0..<h {
        var at = px + y * stride
        for x in 0..<w {
          let u = Float(x) / 90
          let v = Float(y) / 90
          let warp = Noise.fbm(u * 3 + seed, v * 3, 3)
          let comb = sin((u * 22 + warp * 9) + sin(v * 28) * 0.8)
          let vein = Noise.fbm(u * 7 + warp * 3, v * 7 - warp * 2 + seed, 2)
          var c = a + (pale - a) * Noise.smooth(0.05, 0.75, comb) * 0.8
          c = c + (gold - c) * Noise.smooth(0.56, 0.68, vein) * 0.8
          at[0] = UInt8(min(255, c.x * 255))
          at[1] = UInt8(min(255, c.y * 255))
          at[2] = UInt8(min(255, c.z * 255))
          at[3] = 255
          at += 4
        }
      }
    }
    return render(spec.size) { ctx in
      let rect = CGRect(origin: .zero, size: spec.size)
      if spec.design == .paperback {
        UIColor(hex: 0xf1ebdc).setFill()
        ctx.fill(rect)
      } else if let cg {
        ctx.interpolationQuality = .high
        UIImage(cgImage: cg).draw(in: rect)
      }
      // The board's turn-ins shade the paper a little at its edges.
      gradient(ctx, [UIColor(white: 0, alpha: 0.34), UIColor(white: 0, alpha: 0)], nil, from: CGPoint(x: spec.size.width, y: 0), to: CGPoint(x: spec.size.width * 0.86, y: 0))
    }
  }
}

// ─── Springing a layer ───────────────────────────────────────────────────────

extension CALayer {
  /// Takes a layer's transform to `to` on a spring, carrying on from wherever it is on screen.
  func spring(transform to: CATransform3D, damping: CGFloat = 16, stiffness: CGFloat = 230) {
    let from = presentation()?.transform ?? transform
    removeAnimation(forKey: "spring")
    transform = to
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    let a = CASpringAnimation(keyPath: "transform")
    a.fromValue = NSValue(caTransform3D: from)
    a.toValue = NSValue(caTransform3D: to)
    a.damping = damping
    a.stiffness = stiffness
    a.mass = 1
    a.duration = min(1, a.settlingDuration)
    add(a, forKey: "spring")
  }
}

/// Where a camera `distance` away, looking at `vanish`, sees a layer whose centre is at `centre`.
func perspective(centre: CGPoint, vanish: CGPoint, distance: CGFloat) -> CATransform3D {
  var p = CATransform3DIdentity
  p.m34 = -1 / distance
  let dx = centre.x - vanish.x
  let dy = centre.y - vanish.y
  return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(dx, dy, 0), p), CATransform3DMakeTranslation(-dx, -dy, 0))
}

// ─── A book ──────────────────────────────────────────────────────────────────

/// A book as a real box in three dimensions: its cover at z = 0, so it's exactly
/// where the layout puts it, and spine, fore-edge and head going back from it.
final class BookView: UIView {
  /// The camera's distance from the books' covers.
  static let cameraDistance: CGFloat = 1250
  /// The tallest a book gets, in book widths.
  static let tallest: CGFloat = 1.42 * 1.05

  private let scene = StillLayer()
  /// How the carousel has turned it, under whatever a finger or pointer does to the body.
  private let turn = StillTransformLayer()
  /// The shadow on the floor it stands on.
  private let floorShadow = StillLayer()
  private let body = StillTransformLayer()
  private let coverFace = StillLayer()
  private let spineFace = StillLayer()
  private let foreFace = StillLayer()
  private let headFace = StillLayer()
  private let marker = StillLayer()
  private let shine = StillGradientLayer()
  private let shineMask = StillLayer()
  private let gloss = StillGradientLayer()
  private var spec: BookSpec?
  private var faces: BookArt.Faces?
  private var shineOffset: CGFloat = 0
  private var isMetal = false
  private(set) var coverImage: UIImage?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.addSublayer(scene)
    scene.addSublayer(turn)
    turn.addSublayer(floorShadow)
    turn.addSublayer(body)
    floorShadow.shadowColor = UIColor.black.cgColor
    floorShadow.shadowOpacity = 0.42
    floorShadow.shadowRadius = 16
    floorShadow.shadowOffset = .zero
    for f in [spineFace, foreFace, headFace, marker, coverFace] {
      f.contentsGravity = .resize
      f.isDoubleSided = false
      f.minificationFilter = .trilinear
      body.addSublayer(f)
    }
    coverFace.addSublayer(gloss)
    shine.mask = shineMask
    coverFace.addSublayer(shine)
    shineMask.contentsGravity = .resize
    marker.isHidden = true
    gloss.startPoint = CGPoint(x: 0, y: 0)
    gloss.endPoint = CGPoint(x: 1, y: 0.35)
    gloss.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.09).cgColor, UIColor(white: 1, alpha: 0).cgColor]
    shine.startPoint = CGPoint(x: 0, y: 0.15)
    shine.endPoint = CGPoint(x: 1, y: 0.85)
    let hot = UIColor(red: 1, green: 0.97, blue: 0.84, alpha: 1)
    shine.colors = [hot.withAlphaComponent(0).cgColor, hot.withAlphaComponent(0.42).cgColor, hot.cgColor, hot.withAlphaComponent(0.42).cgColor, hot.withAlphaComponent(0).cgColor]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func dress(_ spec: BookSpec, faces: BookArt.Faces, current: Bool) {
    self.spec = spec
    self.faces = faces
    coverImage = faces.cover
    coverFace.contents = faces.cover.cgImage
    spineFace.contents = faces.spine.cgImage
    foreFace.contents = faces.fore.cgImage
    headFace.contents = faces.head.cgImage
    shineMask.contents = faces.foil?.cgImage
    isMetal = faces.foil != nil
    shine.isHidden = !isMetal
    shineOffset = CGFloat(spec.seed % 100) / 100 - 0.5
    marker.isHidden = !current
    if current, marker.contents == nil { marker.contents = Self.ribbon.cgImage }
    setNeedsLayout()
  }

  /// A length of crimson silk, cut to a swallow-tail, left in the book being read.
  private static let ribbon: UIImage = {
    let size = CGSize(width: 13, height: 44)
    let f = UIGraphicsImageRendererFormat()
    f.scale = 2
    return UIGraphicsImageRenderer(size: size, format: f).image { r in
      let ctx = r.cgContext
      let p = UIBezierPath()
      p.move(to: CGPoint(x: 0, y: 0))
      p.addLine(to: CGPoint(x: size.width / 2, y: 6))
      p.addLine(to: CGPoint(x: size.width, y: 0))
      p.addLine(to: CGPoint(x: size.width, y: size.height))
      p.addLine(to: CGPoint(x: 0, y: size.height))
      p.close()
      p.addClip()
      BookArt.gradient(
        ctx, [UIColor(hex: 0x5c0d13), UIColor(hex: 0xa8232a), UIColor(hex: 0xc23a3a), UIColor(hex: 0x8d1820), UIColor(hex: 0x5c0d13)], [0, 0.26, 0.45, 0.72, 1], from: .zero, to: CGPoint(x: size.width, y: 0))
      ctx.setFillColor(UIColor(white: 1, alpha: 0.05).cgColor)
      var x: CGFloat = 0.7
      while x < size.width {
        ctx.fill(CGRect(x: x, y: 0, width: 0.5, height: size.height))
        x += 1.4
      }
      BookArt.gradient(ctx, [UIColor(white: 0, alpha: 0), UIColor(white: 0, alpha: 0.5)], nil, from: CGPoint(x: 0, y: 18), to: CGPoint(x: 0, y: size.height))
    }
  }()

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let spec else { return }
    let w = bounds.width
    let h = bounds.height
    let t = spec.thickness * spec.magnified
    scene.frame = bounds
    turn.frame = bounds
    body.frame = bounds
    let shadow = CGSize(width: w * 1.02, height: t + 70)
    floorShadow.transform = CATransform3DIdentity
    floorShadow.bounds = CGRect(origin: .zero, size: shadow)
    floorShadow.position = CGPoint(x: w / 2, y: h)
    floorShadow.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)
    floorShadow.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: shadow)).cgPath
    coverFace.frame = bounds
    gloss.frame = bounds
    shine.frame = bounds
    shineMask.frame = bounds
    spineFace.anchorPoint = CGPoint(x: 1, y: 0.5)
    spineFace.bounds = CGRect(x: 0, y: 0, width: t, height: h)
    spineFace.position = CGPoint(x: 0, y: h / 2)
    spineFace.transform = CATransform3DMakeRotation(-.pi / 2, 0, 1, 0)
    foreFace.anchorPoint = CGPoint(x: 0, y: 0.5)
    foreFace.bounds = CGRect(x: 0, y: 0, width: t, height: h)
    foreFace.position = CGPoint(x: w - 0.5, y: h / 2)
    foreFace.transform = CATransform3DMakeRotation(.pi / 2, 0, 1, 0)
    headFace.anchorPoint = CGPoint(x: 0.5, y: 1)
    headFace.bounds = CGRect(x: 0, y: 0, width: w, height: t)
    headFace.position = CGPoint(x: w / 2, y: 0)
    headFace.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)
    // The ribbon stands in the block of pages, somewhat behind the cover and up out of the head.
    marker.bounds = CGRect(x: 0, y: 0, width: 13, height: 44)
    marker.position = CGPoint(x: w * 0.72, y: 22 - 16)
    marker.transform = CATransform3DMakeTranslation(0, 0, -t * 0.4)
  }

  /// Sets the camera, and the light on the foil, for where the book is on screen.
  func reposition(centre: CGPoint, vanish: CGPoint, viewport: CGSize, tilt: CGPoint) {
    scene.sublayerTransform = perspective(centre: centre, vanish: vanish, distance: Self.cameraDistance)
    let nx = (centre.x - vanish.x) / max(1, viewport.width)
    let ny = (centre.y - vanish.y) / max(1, viewport.height)
    let band = 0.5 + ny * 2.4 + nx * 0.9 + shineOffset + tilt.x * 2.2 + tilt.y * 2.2
    if isMetal {
      shine.locations = [band - 0.3, band - 0.1, band, band + 0.1, band + 0.3].map { NSNumber(value: Double($0)) }
    }
    let wide = 0.5 + ny * 1.1 + nx * 1.1 + tilt.x * 1.4 + tilt.y * 1.4
    gloss.locations = [wide - 0.42, wide, wide + 0.42].map { NSNumber(value: Double($0)) }
  }

  /// Turned by `angle` about its upright and set `depth` back, as the carousel has it.
  func pose(angle: CGFloat, depth: CGFloat) {
    turn.transform = CATransform3DRotate(CATransform3DMakeTranslation(0, 0, depth), angle, 0, 1, 0)
  }

  /// Tilted under a finger, as under a pointer.
  func press(_ pressed: Bool) {
    if pressed {
      body.spring(transform: Self.tilted, damping: 15, stiffness: 240)
    } else {
      body.spring(transform: resting, damping: 15, stiffness: 240)
    }
  }

  /// With a pointer over it, it stands at a small fixed tilt, wherever on it the pointer is.
  var hovered = false {
    didSet {
      guard hovered != oldValue else { return }
      body.spring(transform: resting, damping: 15, stiffness: 240)
    }
  }

  private var resting: CATransform3D {
    hovered ? Self.tilted : CATransform3DIdentity
  }

  /// Turned a little about its upright, under a pointer or a finger alike.
  private static let tilted = CATransform3DRotate(CATransform3DMakeTranslation(0, 0, 10), -0.1, 0, 1, 0)

  /// Takes the cover away while a copy of it travels; the rest of the book stays where it stood.
  func lift(_ lifted: Bool) {
    coverFace.isHidden = lifted
    marker.opacity = lifted ? 0 : 1
  }
}

/// The two faces of a book's cover, for it to swing open on its hinge as a page zooms out of it.
struct CoverFaces {
  let front: UIImage
  let inside: UIImage
  /// The front as the room's light falls on it in the library, if it's known.
  var lit: UIImage? = nil
}

/// A book in the library.
final class BookCell: UICollectionViewCell {
  let book = BookView()
  var spec: BookSpec?
  private let slip = StatusSlip()
  private var isCurrent = false
  private var stage: ImportEntry.Stage?
  private var stamp: UIImage?

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(book)
    contentView.addSubview(slip)
    isAccessibilityElement = true
    accessibilityTraits = .button
    addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// `stamp`: its drawing, as ink only; nil until it's come. `current`: it's the one read last.
  func set(_ d: Document, stamp: UIImage?, current: Bool) {
    isCurrent = current
    self.stamp = stamp
    accessibilityLabel = d.authors.isEmpty ? d.title : "\(d.title), by \(Face.authors(d.authors))"
    showStatus(of: d.id)
    dress()
  }

  private func dress() {
    guard let spec else { return }
    book.dress(spec, faces: BookArt.faces(spec, stamp: stamp, status: stage), current: isCurrent)
  }

  /// A drawing that has just come.
  func show(stamp: UIImage?) {
    guard (stamp == nil) != (self.stamp == nil) || stamp !== self.stamp else { return }
    self.stamp = stamp
    UIView.transition(with: book, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.dress() }
  }

  /// Shows what's happening to a document on its way in, if anything is.
  func showStatus(of id: String) {
    let status = ImportStatus(id)
    slip.show(status)
    accessibilityValue = status.said
    if status.stage != stage {
      stage = status.stage
      if spec?.design == .parcel { dress() }
    }
    setNeedsLayout()
  }

  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      book.press(isHighlighted)
    }
  }

  @objc private func hovered(_ g: UIHoverGestureRecognizer) {
    switch g.state {
    case .began, .changed: book.hovered = !UIAccessibility.isReduceMotionEnabled
    default: book.hovered = false
    }
  }

  /// What a page zooms out of and back onto.
  var sheetView: UIView { book }
  /// The cover, to swing open as the page zooms out.
  var cover: CoverFaces? {
    guard let spec, let front = book.coverImage else { return nil }
    return CoverFaces(front: front, inside: BookArt.inside(spec))
  }
  /// Takes the cover away, while a copy of it travels.
  func lift(_ lifted: Bool) { book.lift(lifted) }
  /// What lifts when pressed and held, and its outline.
  var preview: (view: UIView, outline: UIBezierPath)? {
    (book, UIBezierPath(roundedRect: book.bounds, cornerRadius: 2.6))
  }

  /// The light moved, or the cell did.
  func reposition(in collection: UICollectionView) {
    let origin = collection.bounds.origin
    let centre = CGPoint(x: center.x - origin.x, y: center.y - origin.y)
    let viewport = collection.bounds.size
    book.reposition(centre: centre, vanish: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport, tilt: Tilt.shared.value)
  }

  override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
    super.apply(layoutAttributes)
    if let a = layoutAttributes as? CarouselAttributes { book.pose(angle: a.angle, depth: a.depth) }
    if let c = superview as? UICollectionView { reposition(in: c) }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if let c = superview as? UICollectionView { reposition(in: c) }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    book.frame = contentView.bounds
    let w = bounds.width
    slip.frame = CGRect(x: 10, y: bounds.height - StatusSlip.height - 12, width: w - 20, height: StatusSlip.height)
    if let c = superview as? UICollectionView { reposition(in: c) }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    book.lift(false)
    book.hovered = false
    stage = nil
  }
}

// ─── The tilt of the iPad ────────────────────────────────────────────────────

/// How the iPad is tilted, smoothed, for foil to catch the light by.
@MainActor
final class Tilt {
  static let shared = Tilt()
  private(set) var value = CGPoint.zero
  var onChange: (() -> Void)?
  private let motion = CMMotionManager()
  private var rest: CGPoint?

  func start() {
    guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive, !UIAccessibility.isReduceMotionEnabled else { return }
    motion.deviceMotionUpdateInterval = 1 / 30
    motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
      guard let self, let m else { return }
      // Measured from however it's first held, so only moving it moves the light.
      let now = CGPoint(x: CGFloat(m.attitude.roll), y: CGFloat(m.attitude.pitch))
      let rest = self.rest ?? now
      self.rest = rest
      let goal = CGPoint(x: now.x - rest.x, y: now.y - rest.y)
      self.value.x += (goal.x - self.value.x) * 0.16
      self.value.y += (goal.y - self.value.y) * 0.16
      // The rest follows slowly, so a new way of holding it becomes the new rest.
      self.rest = CGPoint(x: rest.x + (now.x - rest.x) * 0.004, y: rest.y + (now.y - rest.y) * 0.004)
      self.onChange?()
    }
  }

  func stop() {
    motion.stopDeviceMotionUpdates()
    rest = nil
  }
}
