import CoreGraphics
import Foundation
import PDFKit
import Vision

#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

// ─── What a page holds ───────────────────────────────────────────────────────

/// A color as a page prints it.
struct Tint: Codable, Equatable, Hashable {
  var r: CGFloat
  var g: CGFloat
  var b: CGFloat

  static let black = Tint(r: 0, g: 0, b: 0)
  static let white = Tint(r: 1, g: 1, b: 1)

  var luma: CGFloat { 0.3 * r + 0.59 * g + 0.11 * b }

  init(r: CGFloat, g: CGFloat, b: CGFloat) {
    self.r = r
    self.g = g
    self.b = b
  }

  init?(_ color: PlatformColor?) {
    guard let color else { return nil }
    let cg = color.cgColor
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let c = cg.converted(to: srgb, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else {
      guard let c = cg.components, let v = c.first else { return nil }
      self.init(r: v, g: v, b: v)
      return
    }
    self.init(r: c[0], g: c[1], b: c[2])
  }
}

/// A font as the document names it. PDFKit's own answer is a stand-in (nearly
/// everything comes back as Helvetica), so this is read from the page's resources.
struct FontRecord: Codable, Equatable, Hashable {
  /// The name with any subset prefix ("ABCDEF+") taken off.
  var name: String
  var bold: Bool
  var italic: Bool
  var serif: Bool
  var mono: Bool
  /// A font of symbols: math, dingbats. Text in it isn't prose.
  var math: Bool
  /// The family to set it in, if the check found a better one than the device's own guess.
  var standIn: String?
}

/// A word on a page, in page points, y down.
struct RawWord {
  var text: String
  var rect: CGRect
  var size: CGFloat
  var font: Int
  var color: Tint
  /// +1 raised, −1 lowered, 0 on the line.
  var script = 0
  var hidden = false
  /// Touches the word before it: the parts of "x²" are one word to a reader.
  var glued = false
}

/// Words that stand together on one baseline, with no wide gap between them.
struct RawRun {
  var words: [RawWord]
  var rect: CGRect
  var baseline: CGFloat
  var size: CGFloat
  var font: Int
  var color: Tint
}

/// What's on a page besides text.
struct RawMark {
  /// `tint` is a shape that's only filled: it may just be there to color what's on it.
  enum Kind { case image, vector, tint }
  var rect: CGRect
  var kind: Kind
}

struct RawPage {
  var index: Int
  var size: CGSize
  var runs: [RawRun] = []
  /// Pictures and line art, ungrouped.
  var marks: [RawMark] = []
  /// Thin lines: table rules and separators, which belong to no figure.
  var rules: [CGRect] = []
  /// Filled shapes large enough for text to sit on.
  var panels: [(rect: CGRect, tint: Tint)] = []
  /// Text set sideways or at an angle, kept only as part of the picture.
  var sideways: [CGRect] = []
  /// The whole page is a picture of a page.
  var scanned = false
  /// How the text was got.
  var ocr = false
  /// Whether the text layer looks like nonsense, so what it says can't be used.
  var garbled = false
  /// How many shows of text the page's stream holds, whatever came of them.
  var shows = 0
  /// How far it was turned, clockwise, to bring its text upright.
  var turn = 0
  /// The paper's color, where the page prints one.
  var paper: Tint = .white
}

// ─── Where a page lies ───────────────────────────────────────────────────────

/// Maps a page's own coordinates (y up, turned by its rotation) to what a
/// reader sees: y down from the top left of the page as it's displayed.
struct PageFrame {
  let size: CGSize
  let toDisplay: CGAffineTransform

  init(_ page: PDFPage) {
    let box = page.bounds(for: .cropBox)
    let (w, h) = (box.width, box.height)
    switch ((page.rotation % 360) + 360) % 360 {
    case 90:
      size = CGSize(width: h, height: w)
      toDisplay = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: -box.minY, ty: -box.minX)
    case 180:
      size = CGSize(width: w, height: h)
      toDisplay = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: box.maxX, ty: -box.minY)
    case 270:
      size = CGSize(width: h, height: w)
      toDisplay = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: box.maxY, ty: box.maxX)
    default:
      size = CGSize(width: w, height: h)
      toDisplay = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -box.minX, ty: box.maxY)
    }
  }
}

// ─── The content stream ──────────────────────────────────────────────────────

/// The operators' callbacks are plain C functions, so they find their way back through these.
private func me(_ info: UnsafeMutableRawPointer?) -> PageScan {
  Unmanaged<PageScan>.fromOpaque(info!).takeUnretainedValue()
}

private func numbers(_ scanner: CGPDFScannerRef, _ n: Int) -> [CGFloat]? {
  var v = [CGFloat](repeating: 0, count: n)
  for i in stride(from: n - 1, through: 0, by: -1) {
    var x: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &x) else { return nil }
    v[i] = x
  }
  return v
}

/// Walks a page's content stream, as a printer would, for what PDFKit doesn't
/// tell: the real fonts, where each run of text starts, every picture and path.
/// Bounded, since nothing says a page can't hold millions of strokes.
final class PageScan {
  struct TextOp {
    let point: CGPoint
    let font: Int
    let hidden: Bool
  }

  private struct State {
    var ctm: CGAffineTransform
    var clip: CGRect
    var fill = Tint.black
    var fillAlpha: CGFloat = 1
    var lineWidth: CGFloat = 1
    var render: Int32 = 0
    var font = -1
    var fontSize: CGFloat = 0
    var charSpace: CGFloat = 0
    var wordSpace: CGFloat = 0
    var scale: CGFloat = 1
    var leading: CGFloat = 0
    var rise: CGFloat = 0
  }

  /// A font's widths, to tell how far a show of text moves the pen.
  private struct Metrics {
    var first = 0
    var widths: [CGFloat] = []
    var missing: CGFloat = 500
    var wide = false
  }

  private(set) var ops: [TextOp] = []
  private(set) var images: [CGRect] = []
  private(set) var vectors: [CGRect] = []
  private(set) var tints: [CGRect] = []
  private(set) var rules: [CGRect] = []
  private(set) var panels: [(rect: CGRect, tint: Tint)] = []
  private(set) var paper: Tint = .white
  /// How many paths were skipped once the budget ran out.
  private(set) var overflowed = false

  private static let table: CGPDFOperatorTableRef = makeTable()
  private static let budget = 400_000
  private static let deepest = 6

  private var state: State
  private var stack: [State] = []
  private var tm = CGAffineTransform.identity
  private var tlm = CGAffineTransform.identity
  private var path: CGRect?
  private var pending = false
  private var pendingClip = false
  private var cursor = CGPoint.zero
  private var count = 0
  private var depth = 0
  private let pageSize: CGSize

  /// Every font met so far, shared across a document's pages.
  private let catalog: FontCatalog
  private var metrics: [Int: Metrics] = [:]
  private var named: [String: Int] = [:]

  init(_ page: PDFPage, frame: PageFrame, catalog: FontCatalog) {
    pageSize = frame.size
    self.catalog = catalog
    state = State(ctm: frame.toDisplay, clip: CGRect(origin: .zero, size: frame.size))
    guard let ref = page.pageRef else { return }
    let stream = CGPDFContentStreamCreateWithPage(ref)
    run(stream)
  }

  private func run(_ stream: CGPDFContentStreamRef) {
    let info = Unmanaged.passUnretained(self).toOpaque()
    let scanner = CGPDFScannerCreate(stream, Self.table, info)
    _ = CGPDFScannerScan(scanner)
    CGPDFScannerRelease(scanner)
  }

  private func spend(_ scanner: CGPDFScannerRef) {
    count += 1
    if count > Self.budget {
      overflowed = true
      CGPDFScannerStop(scanner)
    }
  }

  // ─── Marks ───────────────────────────────────────────────────────────────

  private func extend(_ p: CGPoint) {
    let q = p.applying(state.ctm)
    let r = CGRect(x: q.x, y: q.y, width: 0, height: 0)
    path = path?.union(r) ?? r
    cursor = p
  }

  private func paint(filled: Bool, stroked: Bool) {
    defer {
      if pendingClip, let path { state.clip = state.clip.intersection(path) }
      pendingClip = false
      path = nil
    }
    guard filled || stroked, var r = path else { return }
    let t = state.ctm
    let stretch = sqrt(abs(t.a * t.d - t.b * t.c))
    if stroked { r = r.insetBy(dx: -state.lineWidth * stretch / 2, dy: -state.lineWidth * stretch / 2) }
    r = r.intersection(state.clip)
    guard !r.isNull, r.width > 0 || r.height > 0 else { return }
    let page = pageSize.width * pageSize.height
    let area = r.width * r.height
    // Thin and long is a rule, whichever way it runs.
    let thin = min(r.width, r.height)
    let long = max(r.width, r.height)
    if thin <= 2.5 && long >= 12 {
      if filled && state.fill.luma > 0.97 && !stroked { return }
      rules.append(r)
      return
    }
    if filled && !stroked {
      // White on white marks nothing; a color covering the page is the paper it's printed on.
      if state.fill.luma > 0.985 && state.fillAlpha > 0.5 { return }
      if area > page * 0.8 {
        paper = state.fill
        return
      }
      if area > page * 0.015 {
        panels.append((r, state.fill))
        return
      }
      tints.append(r)
      return
    }
    vectors.append(r)
  }

  private func image() {
    let t = state.ctm
    let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)].map { $0.applying(t) }
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    let r = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).intersection(state.clip)
    if !r.isNull, r.width > 1, r.height > 1 { images.append(r) }
  }

  private func form(_ stream: CGPDFStreamRef, parent: CGPDFContentStreamRef) {
    guard depth < Self.deepest, let dict = CGPDFStreamGetDictionary(stream) else { return }
    let saved = state
    let savedStack = stack
    let (savedTm, savedTlm) = (tm, tlm)
    var matrix: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(dict, "Matrix", &matrix), let matrix {
      var v = [CGPDFReal](repeating: 0, count: 6)
      var ok = true
      for i in 0..<6 where !CGPDFArrayGetNumber(matrix, i, &v[i]) { ok = false }
      if ok { state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(state.ctm) }
    }
    var bbox: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(dict, "BBox", &bbox), let bbox {
      var v = [CGPDFReal](repeating: 0, count: 4)
      var ok = true
      for i in 0..<4 where !CGPDFArrayGetNumber(bbox, i, &v[i]) { ok = false }
      if ok {
        let r = CGRect(x: min(v[0], v[2]), y: min(v[1], v[3]), width: abs(v[2] - v[0]), height: abs(v[3] - v[1])).applying(state.ctm)
        state.clip = state.clip.intersection(r)
      }
    }
    var resources: CGPDFDictionaryRef?
    _ = CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
    let inner = CGPDFContentStreamCreateWithStream(stream, resources ?? dict, parent)
    depth += 1
    run(inner)
    depth -= 1
    state = saved
    stack = savedStack
    tm = savedTm
    tlm = savedTlm
  }

  // ─── Text ────────────────────────────────────────────────────────────────

  private func setFont(_ name: String, _ size: CGFloat, _ scanner: CGPDFScannerRef) {
    state.fontSize = size
    // A name means one font within a stream; forms may have their own.
    let key = "\(depth)/\(name)"
    if let known = named[key] {
      state.font = known
      return
    }
    defer { named[key] = state.font }
    let stream = CGPDFScannerGetContentStream(scanner)
    guard let object = CGPDFContentStreamGetResource(stream, "Font", name) else {
      state.font = -1
      return
    }
    var dict: CGPDFDictionaryRef?
    guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else {
      state.font = -1
      return
    }
    state.font = catalog.index(of: dict)
    if metrics[state.font] == nil { metrics[state.font] = Self.metrics(dict) }
  }

  private static func metrics(_ dict: CGPDFDictionaryRef) -> Metrics {
    var m = Metrics()
    var name: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(dict, "Subtype", &name), let name, String(cString: name) == "Type0" {
      m.wide = true
      return m
    }
    var first: CGPDFInteger = 0
    if CGPDFDictionaryGetInteger(dict, "FirstChar", &first) { m.first = first }
    var widths: CGPDFArrayRef?
    if CGPDFDictionaryGetArray(dict, "Widths", &widths), let widths {
      let n = CGPDFArrayGetCount(widths)
      m.widths.reserveCapacity(n)
      for i in 0..<n {
        var w: CGPDFReal = 0
        _ = CGPDFArrayGetNumber(widths, i, &w)
        m.widths.append(w)
      }
    }
    return m
  }

  private func note() {
    let at = CGPoint(x: 0, y: state.rise).applying(tm).applying(state.ctm)
    ops.append(TextOp(point: at, font: state.font, hidden: state.render == 3))
  }

  /// How far `bytes` of text move the pen, in text space.
  private func advance(_ bytes: UnsafeBufferPointer<UInt8>) -> CGFloat {
    let m = metrics[state.font] ?? Metrics()
    var w: CGFloat = 0
    if m.wide {
      w = CGFloat(bytes.count / 2) * 0.55 * state.fontSize
    } else {
      for b in bytes {
        let i = Int(b) - m.first
        let glyph = m.widths.indices.contains(i) ? m.widths[i] : m.missing
        w += glyph / 1000 * state.fontSize + state.charSpace + (b == 32 ? state.wordSpace : 0)
      }
    }
    return w * state.scale
  }

  private func show(_ string: CGPDFStringRef) {
    note()
    guard let p = CGPDFStringGetBytePtr(string) else { return }
    let w = advance(UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(string)))
    tm = CGAffineTransform(translationX: w, y: 0).concatenating(tm)
  }

  private func nextLine(_ x: CGFloat, _ y: CGFloat) {
    tlm = CGAffineTransform(translationX: x, y: y).concatenating(tlm)
    tm = tlm
  }

  // ─── The operators ───────────────────────────────────────────────────────

  private static func makeTable() -> CGPDFOperatorTableRef {
    let t = CGPDFOperatorTableCreate()!
    func on(_ name: String, _ body: @escaping CGPDFOperatorCallback) { CGPDFOperatorTableSetCallback(t, name, body) }

    on("q") { _, i in let s = me(i); s.stack.append(s.state) }
    on("Q") { _, i in let s = me(i); if let top = s.stack.popLast() { s.state = top } }
    on("cm") { sc, i in
      guard let v = numbers(sc, 6) else { return }
      let s = me(i)
      s.state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(s.state.ctm)
    }
    on("w") { sc, i in if let v = numbers(sc, 1) { me(i).state.lineWidth = v[0] } }

    // Paths.
    on("m") { sc, i in if let v = numbers(sc, 2) { me(i).extend(CGPoint(x: v[0], y: v[1])); me(i).spend(sc) } }
    on("l") { sc, i in if let v = numbers(sc, 2) { me(i).extend(CGPoint(x: v[0], y: v[1])); me(i).spend(sc) } }
    on("c") { sc, i in
      guard let v = numbers(sc, 6) else { return }
      let s = me(i)
      for k in [0, 2, 4] { s.extend(CGPoint(x: v[k], y: v[k + 1])) }
      s.spend(sc)
    }
    on("v") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      let s = me(i)
      for k in [0, 2] { s.extend(CGPoint(x: v[k], y: v[k + 1])) }
      s.spend(sc)
    }
    on("y") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      let s = me(i)
      for k in [0, 2] { s.extend(CGPoint(x: v[k], y: v[k + 1])) }
      s.spend(sc)
    }
    on("re") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      let s = me(i)
      s.extend(CGPoint(x: v[0], y: v[1]))
      s.extend(CGPoint(x: v[0] + v[2], y: v[1] + v[3]))
      s.spend(sc)
    }
    for name in ["f", "F", "f*"] { on(name) { _, i in me(i).paint(filled: true, stroked: false) } }
    for name in ["S", "s"] { on(name) { _, i in me(i).paint(filled: false, stroked: true) } }
    for name in ["B", "B*", "b", "b*"] { on(name) { _, i in me(i).paint(filled: true, stroked: true) } }
    on("n") { _, i in me(i).paint(filled: false, stroked: false) }
    on("W") { _, i in me(i).pendingClip = true }
    on("W*") { _, i in me(i).pendingClip = true }
    on("sh") { _, i in
      let s = me(i)
      if s.state.clip.width * s.state.clip.height < s.pageSize.width * s.pageSize.height * 0.8 { s.vectors.append(s.state.clip) }
    }

    // Colors, for telling what's white, and the paper.
    on("g") { sc, i in if let v = numbers(sc, 1) { me(i).state.fill = Tint(r: v[0], g: v[0], b: v[0]) } }
    on("rg") { sc, i in if let v = numbers(sc, 3) { me(i).state.fill = Tint(r: v[0], g: v[1], b: v[2]) } }
    on("k") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      me(i).state.fill = Tint(r: (1 - v[0]) * (1 - v[3]), g: (1 - v[1]) * (1 - v[3]), b: (1 - v[2]) * (1 - v[3]))
    }
    for name in ["sc", "scn"] {
      on(name) { sc, i in
        var comps: [CGFloat] = []
        var x: CGPDFReal = 0
        while comps.count < 4, CGPDFScannerPopNumber(sc, &x) { comps.insert(x, at: 0) }
        let s = me(i)
        switch comps.count {
        case 1: s.state.fill = Tint(r: comps[0], g: comps[0], b: comps[0])
        case 3: s.state.fill = Tint(r: comps[0], g: comps[1], b: comps[2])
        case 4: s.state.fill = Tint(r: (1 - comps[0]) * (1 - comps[3]), g: (1 - comps[1]) * (1 - comps[3]), b: (1 - comps[2]) * (1 - comps[3]))
        default: s.state.fill = Tint(r: 0.5, g: 0.5, b: 0.5)
        }
      }
    }

    // Pictures and forms.
    on("Do") { sc, i in
      var name: UnsafePointer<CChar>?
      guard CGPDFScannerPopName(sc, &name), let name else { return }
      let s = me(i)
      s.spend(sc)
      let cs = CGPDFScannerGetContentStream(sc)
      guard let object = CGPDFContentStreamGetResource(cs, "XObject", name) else { return }
      var stream: CGPDFStreamRef?
      guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) else { return }
      var subtype: UnsafePointer<CChar>?
      guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype else { return }
      switch String(cString: subtype) {
      case "Image": s.image()
      case "Form": s.form(stream, parent: cs)
      default: break
      }
    }
    on("EI") { _, i in me(i).image() }

    // Text.
    on("BT") { _, i in
      let s = me(i)
      s.tm = .identity
      s.tlm = .identity
    }
    on("Tf") { sc, i in
      var size: CGPDFReal = 0
      var name: UnsafePointer<CChar>?
      guard CGPDFScannerPopNumber(sc, &size), CGPDFScannerPopName(sc, &name), let name else { return }
      me(i).setFont(String(cString: name), size, sc)
    }
    on("Tr") { sc, i in
      var v: CGPDFInteger = 0
      if CGPDFScannerPopInteger(sc, &v) { me(i).state.render = Int32(v) }
    }
    on("Tc") { sc, i in if let v = numbers(sc, 1) { me(i).state.charSpace = v[0] } }
    on("Tw") { sc, i in if let v = numbers(sc, 1) { me(i).state.wordSpace = v[0] } }
    on("Tz") { sc, i in if let v = numbers(sc, 1) { me(i).state.scale = v[0] / 100 } }
    on("TL") { sc, i in if let v = numbers(sc, 1) { me(i).state.leading = v[0] } }
    on("Ts") { sc, i in if let v = numbers(sc, 1) { me(i).state.rise = v[0] } }
    on("Td") { sc, i in if let v = numbers(sc, 2) { me(i).nextLine(v[0], v[1]) } }
    on("TD") { sc, i in
      guard let v = numbers(sc, 2) else { return }
      me(i).state.leading = -v[1]
      me(i).nextLine(v[0], v[1])
    }
    on("Tm") { sc, i in
      guard let v = numbers(sc, 6) else { return }
      let m = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
      me(i).tm = m
      me(i).tlm = m
    }
    on("T*") { _, i in me(i).nextLine(0, -me(i).state.leading) }
    on("Tj") { sc, i in
      var str: CGPDFStringRef?
      if CGPDFScannerPopString(sc, &str), let str { me(i).show(str) }
    }
    on("'") { sc, i in
      var str: CGPDFStringRef?
      guard CGPDFScannerPopString(sc, &str), let str else { return }
      let s = me(i)
      s.nextLine(0, -s.state.leading)
      s.show(str)
    }
    on("\"") { sc, i in
      var str: CGPDFStringRef?
      guard CGPDFScannerPopString(sc, &str), let str else { return }
      let s = me(i)
      if let v = numbers(sc, 2) {
        s.state.wordSpace = v[0]
        s.state.charSpace = v[1]
      }
      s.nextLine(0, -s.state.leading)
      s.show(str)
    }
    on("TJ") { sc, i in
      var array: CGPDFArrayRef?
      guard CGPDFScannerPopArray(sc, &array), let array else { return }
      let s = me(i)
      s.note()
      var w: CGFloat = 0
      for k in 0..<CGPDFArrayGetCount(array) {
        var str: CGPDFStringRef?
        var n: CGPDFReal = 0
        if CGPDFArrayGetString(array, k, &str), let str, let p = CGPDFStringGetBytePtr(str) {
          w += s.advance(UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(str)))
        } else if CGPDFArrayGetNumber(array, k, &n) {
          w -= n / 1000 * s.state.fontSize * s.state.scale
        }
      }
      s.tm = CGAffineTransform(translationX: w, y: 0).concatenating(s.tm)
    }
    return t
  }
}

/// The fonts a document uses, each kept once.
final class FontCatalog {
  private(set) var fonts: [FontRecord] = []
  private var seen: [FontRecord: Int] = [:]

  func index(of dict: CGPDFDictionaryRef) -> Int { stand(Self.read(dict)) }

  /// A font's place in the catalog, added if it's new.
  func stand(_ record: FontRecord) -> Int {
    if let i = seen[record] { return i }
    fonts.append(record)
    seen[record] = fonts.count - 1
    return fonts.count - 1
  }

  private static func read(_ dict: CGPDFDictionaryRef) -> FontRecord {
    var name = ""
    var c: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(dict, "BaseFont", &c), let c { name = String(cString: c) }
    if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
      name = String(name[name.index(after: plus)...])
    }
    var descriptor: CGPDFDictionaryRef?
    if !CGPDFDictionaryGetDictionary(dict, "FontDescriptor", &descriptor) {
      var kids: CGPDFArrayRef?
      var kid: CGPDFDictionaryRef?
      if CGPDFDictionaryGetArray(dict, "DescendantFonts", &kids), let kids, CGPDFArrayGetDictionary(kids, 0, &kid), let kid {
        _ = CGPDFDictionaryGetDictionary(kid, "FontDescriptor", &descriptor)
      }
    }
    var flags: CGPDFInteger = 0
    var weight: CGPDFReal = 0
    var angle: CGPDFReal = 0
    if let descriptor {
      _ = CGPDFDictionaryGetInteger(descriptor, "Flags", &flags)
      _ = CGPDFDictionaryGetNumber(descriptor, "FontWeight", &weight)
      _ = CGPDFDictionaryGetNumber(descriptor, "ItalicAngle", &angle)
    }
    // A descriptor can claim a fixed pitch its widths give the lie to.
    var widths: CGPDFArrayRef?
    if flags & 1 != 0, CGPDFDictionaryGetArray(dict, "Widths", &widths), let widths {
      var distinct = Set<Int>()
      for i in 0..<CGPDFArrayGetCount(widths) {
        var w: CGPDFReal = 0
        if CGPDFArrayGetNumber(widths, i, &w), w > 0 { distinct.insert(Int(w)) }
      }
      if distinct.count > 2 { flags &= ~1 }
    }
    return FontNames.record(name, flags: flags, weight: weight, angle: angle)
  }
}

/// What a font's name gives away, on top of what its descriptor says.
enum FontNames {
  static func record(_ name: String, flags: Int, weight: CGFloat, angle: CGFloat) -> FontRecord {
    let low = name.lowercased()
    func has(_ words: [String]) -> Bool { words.contains { low.contains($0) } }
    let bold =
      has(["bold", "black", "heavy", "demi", "cmbx", "cmb10", "sfbx", "nimbusromno9l-medi", "-medi", "-semibold", "extrabold"]) || weight >= 600 || flags & (1 << 18) != 0
    let italic = has(["italic", "oblique", "cmti", "cmmi", "sfti", "sfsl", "cmsl", "-regu-ital", "-medi-ital", "-ital"]) || abs(angle) > 1 || flags & 64 != 0
    let mono = has(["mono", "courier", "consol", "menlo", "typewriter", "cmtt", "sftt", "lmtt", "inconsolata", "andale", "lucidacons", "fixed"]) || flags & 1 != 0
    let math = has(["cmmi", "cmsy", "cmex", "msam", "msbm", "cmr5", "cmr6", "cmr7", "stmary", "math", "symbol", "wasy", "dingbat", "esint", "rsfs", "eufm", "mtsy", "mtmi", "euclid", "txsy", "pxsy"])
    let sansName = has(["helvet", "arial", "sans", "gothic", "verdana", "tahoma", "calibri", "segoe", "avenir", "futura", "gill", "univers", "frutiger", "myriad", "roboto", "lato", "opensans", "inter", "cmss", "lmss", "sfss", "nimbussan", "source sans", "dejavusans", "ubuntu", "noto sans", "notosans", "franklin", "trebuchet", "optima", "din", "aptos"])
    let serifName = has(["times", "roman", "serif", "georgia", "garamond", "palatino", "minion", "cambria", "baskerville", "caslon", "bookman", "charter", "cmr", "lmr", "sfrm", "nimbusrom", "utopia", "didot", "bodoni", "century", "book", "libertine", "kepler", "tiempos", "lora", "merriweather", "crimson", "droid serif", "pt serif", "sabon", "stix", "tex gyre termes", "newsreader"])
    let serif = sansName ? false : (serifName || flags & 2 != 0)
    return FontRecord(name: name, bold: bold, italic: italic, serif: serif, mono: mono, math: math)
  }
}

// ─── Text, from PDFKit ───────────────────────────────────────────────────────

/// Reads one page of a PDF into runs of words and marks, in page points.
enum PageReader {
  private struct Char {
    let text: String
    let rect: CGRect
    let size: CGFloat
    let color: Tint
    /// Whether a space or line break came just before it.
    let spaced: Bool
    let strongRTL: Bool
  }

  /// Letters that hang below the line or sit above it, so they don't mark where it is.
  private static let offLine = Set("gjpqyQJ,;()[]{}/|\\\"'’‘“”^*°`~_-–—=+<>:")

  static func read(_ page: PDFPage, index: Int, catalog: FontCatalog) -> RawPage {
    // A page set sideways or upside down is turned upright before anything else, for reading and for showing.
    let asFound = characters(page, frame: PageFrame(page))
    let turn = turnNeeded(asFound)
    if turn != 0 { page.rotation = (page.rotation + turn) % 360 }
    let frame = PageFrame(page)
    var raw = RawPage(index: index, size: frame.size)
    raw.turn = turn
    let scan = PageScan(page, frame: frame, catalog: catalog)
    raw.rules = scan.rules
    raw.panels = scan.panels
    raw.paper = scan.paper
    raw.marks = scan.images.map { RawMark(rect: $0, kind: .image) } + scan.vectors.map { RawMark(rect: $0, kind: .vector) } + scan.tints.map { RawMark(rect: $0, kind: .tint) }

    let chars = turn == 0 ? asFound : characters(page, frame: frame)
    let found = runs(chars, scan: scan, catalog: catalog)
    raw.runs = found.runs
    raw.sideways = found.sideways

    // A picture covering the page, with little or nothing printed over it, is a scan.
    let area = frame.size.width * frame.size.height
    let cover = scan.images.map { $0.width * $0.height }.max() ?? 0
    let hidden = raw.runs.flatMap(\.words).filter(\.hidden).count
    let words = raw.runs.flatMap(\.words).count
    raw.scanned = cover > area * 0.7 && (words < 8 || hidden > words / 2)
    raw.garbled = looksGarbled(chars)
    raw.shows = scan.ops.count
    return raw
  }

  private static func characters(_ page: PDFPage, frame: PageFrame) -> [Char] {
    guard let string = page.string, !string.isEmpty else { return [] }
    let ns = string as NSString
    let n = ns.length
    // Sizes and colors, by run, from the attributed text (its font names can't be believed).
    var styles: [(end: Int, size: CGFloat, color: Tint)] = []
    if let a = page.attributedString, a.length == n {
      a.enumerateAttributes(in: NSRange(location: 0, length: n)) { at, r, _ in
        let size = (at[.font] as? PlatformFont)?.pointSize ?? 0
        let color = Tint(at[.foregroundColor] as? PlatformColor) ?? .black
        styles.append((r.location + r.length, size, color))
      }
    }
    let bounds = boundsReader(page, ns)
    var out: [Char] = []
    out.reserveCapacity(n)
    var spaced = false
    var s = 0
    var i = 0
    while i < n {
      let r = ns.rangeOfComposedCharacterSequence(at: i)
      let text = ns.substring(with: r)
      defer { i = r.location + r.length }
      if text.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) || $0.value == 0xAD || $0.value == 0x200B || $0.value == 0xFEFF }) {
        spaced = true
        continue
      }
      while s < styles.count - 1 && styles[s].end <= i { s += 1 }
      var rect = bounds(i).applying(frame.toDisplay)
      let size = styles.indices.contains(s) && styles[s].size > 0 ? styles[s].size : max(rect.height, rect.width, 1)
      if rect.height < size * 0.05 {
        rect = CGRect(x: rect.minX, y: rect.minY - size * 0.7, width: max(rect.width, size * 0.3), height: size * 0.7)
      }
      guard rect.width.isFinite, rect.height.isFinite else { continue }
      let rtl = text.unicodeScalars.contains { isRTL($0) }
      out.append(Char(text: text, rect: rect, size: size, color: styles.indices.contains(s) ? styles[s].color : .black, spaced: spaced, strongRTL: rtl))
      spaced = false
    }
    return out
  }

  /// How far to turn a page, clockwise, for its text to run left to right: from
  /// which way one letter follows another. Right-to-left scripts don't get a say.
  private static func turnNeeded(_ chars: [Char]) -> Int {
    var votes = (right: 0, left: 0, down: 0, up: 0)
    for (a, b) in zip(chars, chars.dropFirst()) where !a.strongRTL && !b.strongRTL {
      let (dx, dy) = (b.rect.midX - a.rect.midX, b.rect.midY - a.rect.midY)
      guard abs(dx) + abs(dy) < max(a.size, 4) * 1.6 else { continue }
      if abs(dx) > abs(dy) * 2 {
        if dx > 0 { votes.right += 1 } else { votes.left += 1 }
      } else if abs(dy) > abs(dx) * 2 {
        if dy > 0 { votes.down += 1 } else { votes.up += 1 }
      }
    }
    let total = votes.right + votes.left + votes.down + votes.up
    guard total >= 40 else { return 0 }
    let needed = total * 7 / 10
    if votes.down >= needed { return 270 }
    if votes.up >= needed { return 90 }
    if votes.left >= needed { return 180 }
    return 0
  }

  /// Where the character at index `i` of `string` lies. `characterBounds(at:)` is
  /// the only thing that gives a letter's own box, and so shows when it's raised, but
  /// it counts differently from `string`, which has line breaks it hasn't, and spells out
  /// ligatures it counts as one: every "fi" on a page puts everything after it one
  /// letter off, so that the last letter of a line lands on the next. `selection(for:)`
  /// keeps to `string`'s indices but only knows the line a letter's on, and gives a
  /// ligature's letters one box between them. So the two are walked along together,
  /// each letter's selection saying which box is its own, which also puts them back in
  /// step after whatever else may come between them. Where none fits, the selection will do.
  private static func boundsReader(_ page: PDFPage, _ ns: NSString) -> (Int) -> CGRect {
    let n = ns.length
    var rects = [CGRect](repeating: .zero, count: n)
    // Nearest first: the same step as the last letter, then a ligature's next letter, then further off.
    let tries = [0, -1, 1, -2, 2, -3, 3, 4, 5, 6, 8, 10, 12, 16, 20]
    var at = 0
    var i = 0
    while i < n {
      let r = ns.rangeOfComposedCharacterSequence(at: i)
      i = r.location + r.length
      let first = ns.character(at: r.location)
      if first == 10 || first == 13 { continue }
      if CharacterSet.whitespaces.contains(UnicodeScalar(first) ?? "a") {
        at += 1
        continue
      }
      guard let own = page.selection(for: r)?.bounds(for: page), !own.isEmpty else {
        rects[r.location] = page.characterBounds(at: at)
        at += 1
        continue
      }
      var found: CGRect?
      for step in tries where at + step >= 0 && at + step < n {
        let b = page.characterBounds(at: at + step)
        if abs(b.minX - own.minX) <= max(1, min(b.width, own.width) * 0.4), abs(b.midY - own.midY) < max(own.height, 2) {
          found = b
          at += step + 1
          break
        }
      }
      // Set at an angle, a letter's box is in terms of its own slant and matches nothing. It still takes up a place.
      if found == nil { at += 1 }
      rects[r.location] = found ?? own
    }
    return { $0 < rects.count ? rects[$0] : .zero }
  }

  static func isRTL(_ u: Unicode.Scalar) -> Bool {
    (0x0590...0x08FF).contains(u.value) || (0xFB1D...0xFDFF).contains(u.value) || (0xFE70...0xFEFF).contains(u.value)
  }

  static func isCJK(_ u: Unicode.Scalar) -> Bool {
    (0x3040...0x30FF).contains(u.value) || (0x3400...0x4DBF).contains(u.value) || (0x4E00...0x9FFF).contains(u.value)
      || (0xF900...0xFAFF).contains(u.value) || (0xFF00...0xFFEF).contains(u.value) || (0xAC00...0xD7AF).contains(u.value)
      || (0x3000...0x303F).contains(u.value)
  }

  /// A text layer whose characters mostly aren't letters of anything: private
  /// use, replacement characters, stray controls.
  private static func looksGarbled(_ chars: [Char]) -> Bool {
    guard chars.count >= 40 else { return false }
    var bad = 0
    var letters = 0
    for c in chars {
      for u in c.text.unicodeScalars {
        if u.value == 0xFFFD || (0xE000...0xF8FF).contains(u.value) || u.value < 0x20 { bad += 1 }
        if u.properties.isAlphabetic { letters += 1 }
      }
    }
    return Double(bad) > Double(chars.count) * 0.15 || Double(letters) < Double(chars.count) * 0.25
  }

  // ─── Runs ────────────────────────────────────────────────────────────────

  private struct Open {
    var chars: [(c: Char, op: PageScan.TextOp?)] = []
    var words: [[(c: Char, op: PageScan.TextOp?)]] = []
    /// Where the letters stand: from the stream, which says exactly, wherever it can.
    var base: CGFloat = 0
    var size: CGFloat = 0
    var last = CGRect.null
    var rtl = false
  }

  /// Text set sideways comes one letter a step down the page from the last, level
  /// across, each step less than a line: a preprint server's stamp, a rotated label.
  /// Taken out here, or those letters would go looking for a baseline among the text.
  private static func withoutSideways(_ chars: [Char]) -> (kept: [Char], sideways: [CGRect]) {
    var kept: [Char] = []
    kept.reserveCapacity(chars.count)
    var sideways: [CGRect] = []
    var i = 0
    func steps(_ a: Char, _ b: Char) -> Bool {
      let down = abs(b.rect.midY - a.rect.midY)
      return abs(b.rect.minX - a.rect.minX) < max(a.size * 0.15, 1.5) && down > a.size * 0.08 && down < a.size * 0.95
    }
    while i < chars.count {
      var j = i
      while j + 1 < chars.count, steps(chars[j], chars[j + 1]) { j += 1 }
      if j - i >= 4 {
        var r = chars[i].rect
        for k in i...j { r = r.union(chars[k].rect) }
        sideways.append(r)
        i = j + 1
      } else {
        kept.append(chars[i])
        i += 1
      }
    }
    return (kept, sideways)
  }

  private static func runs(_ all: [Char], scan: PageScan, catalog: FontCatalog) -> (runs: [RawRun], sideways: [CGRect]) {
    let (chars, turned) = withoutSideways(all)
    // Where each show of text starts, by the line it's on, to find a character's
    // font and its true baseline. PDFKit's boxes won't do for the height: one
    // symbol from a math font, and every letter on its line gets a box half as
    // tall again, reaching down past the line below.
    let ops = scan.ops.sorted { $0.point.y < $1.point.y }
    func op(at c: Char, on line: CGFloat?, after last: CGFloat) -> PageScan.TextOp? {
      guard !ops.isEmpty else { return nil }
      // A show starting inside a letter's width isn't its own unless it starts by its middle:
      // an "l" before a raised mark would otherwise take the mark's baseline for its own.
      let latest = c.rect.minX + min(c.size * 0.3, c.rect.width * 0.5)
      // An inflated box tells little about where its letter stands: several lines' baselines
      // can lie inside it. So the text's own continuity decides: the line it's already
      // on if that's among them, and otherwise the next one down.
      if c.rect.height > c.size * 1.08 {
        let inside = ops.filter { $0.point.y >= c.rect.minY && $0.point.y <= c.rect.maxY && $0.point.x <= latest }
        if let line, let here = inside.filter({ abs($0.point.y - line) <= c.size * 0.3 }).max(by: { $0.point.x < $1.point.x }) { return here }
        let below = inside.filter { $0.point.y > last + c.size * 0.5 }
        if let y = below.map(\.point.y).min(), let next = below.filter({ abs($0.point.y - y) < 1 }).max(by: { $0.point.x < $1.point.x }) { return next }
      }
      // A letter's middle lies about a quarter of its size above the baseline.
      let y = c.rect.midY + c.size * 0.25
      let reach = max(c.size * 0.42, 1.5)
      var lo = 0
      var hi = ops.count
      while lo < hi {
        let m = (lo + hi) / 2
        if ops[m].point.y < y - reach { lo = m + 1 } else { hi = m }
      }
      var best: PageScan.TextOp?
      var bestX = -CGFloat.infinity
      var nearest: PageScan.TextOp?
      var nearestD = CGFloat.infinity
      var k = lo
      while k < ops.count, ops[k].point.y <= y + reach {
        let o = ops[k]
        if o.point.x <= latest, o.point.x > bestX {
          best = o
          bestX = o.point.x
        }
        let d = abs(o.point.x - c.rect.minX)
        if d < nearestD {
          nearest = o
          nearestD = d
        }
        k += 1
      }
      return best ?? nearest
    }

    var runs: [RawRun] = []
    var sideways = turned
    var open = Open()

    func start(_ c: Char, _ o: PageScan.TextOp?) {
      open = Open()
      open.chars = [(c, o)]
      open.words = [[(c, o)]]
      open.base = o?.point.y ?? c.rect.maxY
      open.size = c.size
      open.last = c.rect
      open.rtl = c.strongRTL
    }
    var lastBase = -CGFloat.infinity
    func flush() {
      if !open.chars.isEmpty, let run = close(open) {
        runs.append(run)
        // Only what's on the line counts: a raised scrap isn't where the next line starts from.
        if run.words.count >= 2 { lastBase = run.baseline }
      }
      open = Open()
    }

    for c in chars {
      // Back across the column, it's a new line, whatever its box says.
      let goesOn = !open.chars.isEmpty && (c.strongRTL || c.rect.minX >= open.last.minX - max(open.size, c.size) * 0.6)
      let o = op(at: c, on: goesOn ? open.base : nil, after: open.chars.isEmpty ? lastBase : max(lastBase, goesOn ? lastBase : open.base))
      guard !open.chars.isEmpty else {
        start(c, o)
        continue
      }
      let em = max(open.size, c.size)
      let forward = c.rect.minX - open.last.maxX
      let backward = open.last.minX - c.rect.maxX
      // Hebrew and Arabic run leftward through the text.
      let gap = (c.strongRTL || open.rtl) && backward > forward ? backward : forward
      let y = o?.point.y ?? c.rect.maxY
      // Letters somewhat smaller may be raised or lowered and still be on the line.
      // Far smaller is another thing altogether: the text beside a drop cap.
      let ratio = min(c.size, open.size) / max(c.size, open.size, 1)
      let band = ratio >= 0.42 && abs(y - open.base) <= em * (ratio < 0.9 ? 0.7 : 0.3)
      let along = gap > -em * 0.6 && gap < em * 1.15
      guard band && along else {
        flush()
        start(c, o)
        continue
      }
      if c.spaced || gap > em * 0.2 {
        open.words.append([(c, o)])
      } else {
        open.words[open.words.count - 1].append((c, o))
      }
      open.chars.append((c, o))
      open.last = c.rect
      if c.size >= open.size {
        open.base = y
        open.size = c.size
      }
      open.rtl = open.rtl || c.strongRTL
    }
    flush()
    return lift(runs, sideways: &sideways)
  }

  /// Text set sideways arrives a letter at a time, each its own run, stacked:
  /// a page's vertical stamp, a rotated axis label. They become part of the picture.
  private static func lift(_ runs: [RawRun], sideways: inout [CGRect]) -> (runs: [RawRun], sideways: [CGRect]) {
    var keep: [RawRun] = []
    var i = 0
    while i < runs.count {
      var j = i
      while j + 1 < runs.count, tall(runs[j]), tall(runs[j + 1]),
        abs(runs[j + 1].rect.midX - runs[j].rect.midX) < max(runs[j].size * 0.6, 2),
        // A letter along from the last, not a line down: stray marks on successive lines line up too.
        abs(runs[j + 1].baseline - runs[j].baseline) < runs[j].size * 0.95
      {
        j += 1
      }
      if j - i >= 4 {
        var r = runs[i].rect
        for k in i...j { r = r.union(runs[k].rect) }
        sideways.append(r)
        i = j + 1
      } else {
        keep.append(runs[i])
        i += 1
      }
    }
    return (keep, sideways)
  }

  /// Short enough to be one letter of something running sideways.
  private static func tall(_ r: RawRun) -> Bool { r.words.count == 1 && r.words[0].text.count <= 2 }

  private static func close(_ open: Open) -> RawRun? {
    // The line's size is the one most of its letters are set at, so a superscript at its start doesn't set it.
    var tally: [CGFloat: Int] = [:]
    for (c, _) in open.chars { tally[(c.size * 2).rounded() / 2, default: 0] += 1 }
    let size = tally.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? open.size

    // The baseline: where most of its full-sized letters stand.
    func stands(_ e: (c: Char, op: PageScan.TextOp?)) -> CGFloat { e.op?.point.y ?? e.c.rect.maxY }
    let standing = open.chars.filter { e in e.c.size >= size * 0.85 && (e.op != nil || !offLine.contains(where: { e.c.text.contains($0) })) }
    let levels = (standing.isEmpty ? open.chars : standing).map(stands).sorted()
    let baseline = levels[levels.count / 2]

    /// How high a word's letters reach, from the size they're set at rather than the box they were given.
    func box(_ x0: CGFloat, _ x1: CGFloat, base: CGFloat, size: CGFloat) -> CGRect {
      CGRect(x: x0, y: base - size * 0.74, width: max(x1 - x0, 0.5), height: size * 0.96)
    }

    var words: [RawWord] = []
    var fontTally: [Int: Int] = [:]
    var colorTally: [Tint: Int] = [:]
    for group in open.words {
      // A word's letters, split wherever the script changes, so "x²" keeps its raised part.
      var i = 0
      while i < group.count {
        func script(_ e: (c: Char, op: PageScan.TextOp?)) -> Int {
          guard e.c.size < size * 0.86 else { return 0 }
          let lift = baseline - stands(e)
          if lift > size * 0.14 { return 1 }
          if lift < -size * 0.06 { return -1 }
          return 0
        }
        let kind = script(group[i])
        var j = i
        while j + 1 < group.count, script(group[j + 1]) == kind { j += 1 }
        let part = group[i...j]
        let x0 = part.map(\.c.rect.minX).min()!
        let x1 = part.map(\.c.rect.maxX).max()!
        let head = part.first!
        let rect = box(x0, x1, base: stands(head), size: head.c.size)
        let font = head.op?.font ?? -1
        words.append(
          RawWord(
            text: part.map(\.c.text).joined(), rect: rect, size: head.c.size, font: font, color: head.c.color, script: kind,
            hidden: head.op?.hidden ?? false, glued: i > 0))
        fontTally[font, default: 0] += part.count
        colorTally[head.c.color, default: 0] += part.count
        i = j + 1
      }
    }
    guard !words.isEmpty else { return nil }
    var rect = box(words[0].rect.minX, words[0].rect.maxX, base: baseline, size: size)
    for w in words { rect = rect.union(CGRect(x: w.rect.minX, y: rect.minY, width: w.rect.width, height: rect.height)) }
    let font = fontTally.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? -1
    let color = colorTally.max { $0.value < $1.value }?.key ?? .black
    return RawRun(words: words, rect: rect, baseline: baseline, size: size, font: font, color: color)
  }
}

// ─── Text, from pictures ─────────────────────────────────────────────────────

/// Reads a page that has no usable text from a picture of it, on the device.
enum PageOCR {
  static func read(_ raw: inout RawPage, picture: CGImage, plain: Int) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(iOS 16, macOS 13, *) { request.automaticallyDetectsLanguage = true }
    let handler = VNImageRequestHandler(cgImage: picture, options: [:])
    guard (try? handler.perform([request])) != nil, let lines = request.results, !lines.isEmpty else { return }
    let size = raw.size
    func place(_ b: CGRect) -> CGRect {
      CGRect(x: b.minX * size.width, y: (1 - b.maxY) * size.height, width: b.width * size.width, height: b.height * size.height)
    }
    var runs: [RawRun] = []
    // The boxes come out a little taller or shorter from line to line, which isn't a change
    // of type. Lines near the page's usual height are given just that height.
    let heights = lines.map { place($0.boundingBox).height }.sorted()
    let usual = heights.isEmpty ? 10 : heights[heights.count / 2]
    for line in lines {
      guard let best = line.topCandidates(1).first else { continue }
      let string = best.string
      let box = place(line.boundingBox)
      // Taller than it's wide, with words in it, it runs sideways: a stamp, a rotated label.
      if box.height > box.width * 1.5, string.count > 4 {
        raw.sideways.append(box)
        continue
      }
      let em = max((abs(box.height - usual) < usual * 0.3 ? usual : box.height) * 0.85, 3)
      var words: [RawWord] = []
      string.enumerateSubstrings(in: string.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
        // Words carry their punctuation, as the text layer's would.
        var end = range.upperBound
        while end < string.endIndex, !string[end].isWhitespace, !string[end].isLetter, !string[end].isNumber { end = string.index(after: end) }
        let word = string[range.lowerBound..<end]
        let rect = (try? best.boundingBox(for: range.lowerBound..<end)).flatMap { $0 }.map { place($0.boundingBox) } ?? box
        words.append(RawWord(text: String(word), rect: rect, size: em, font: plain, color: .black))
      }
      if words.isEmpty { words = [RawWord(text: string, rect: box, size: em, font: plain, color: .black)] }
      runs.append(RawRun(words: words, rect: box, baseline: box.maxY - em * 0.2, size: em, font: plain, color: .black))
    }
    raw.runs = runs
    raw.ocr = true
    raw.garbled = false
  }
}

// ─── Pictures of pages, for reading ──────────────────────────────────────────

enum PagePicture {
  /// All of `page`, white behind, `pixels` wide.
  static func make(_ page: PDFPage, pixels: Int) -> CGImage? {
    let frame = PageFrame(page)
    guard frame.size.width > 0, frame.size.height > 0 else { return nil }
    let s = CGFloat(pixels) / frame.size.width
    let h = Int((frame.size.height * s).rounded(.up))
    guard
      let ctx = CGContext(
        data: nil, width: pixels, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
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
