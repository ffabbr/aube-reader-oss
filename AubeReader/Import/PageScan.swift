import PDFKit
import UIKit

/// The operators' callbacks are plain C functions, so they find their way back
/// through these: the scan the callback belongs to, and the numbers it was given.
private func scan(_ info: UnsafeMutableRawPointer?) -> PageScan {
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

  private static let table: CGPDFOperatorTableRef = makeTable()
  private static let budget = 400_000
  private static let deepest = 6

  private var state: State
  private var stack: [State] = []
  private var tm = CGAffineTransform.identity
  private var tlm = CGAffineTransform.identity
  private var path: CGRect?
  private var pendingClip = false
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
    if count > Self.budget { CGPDFScannerStop(scanner) }
  }

  // ─── Marks ───────────────────────────────────────────────────────────────

  private func extend(_ p: CGPoint) {
    let q = p.applying(state.ctm)
    let r = CGRect(x: q.x, y: q.y, width: 0, height: 0)
    path = path?.union(r) ?? r
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

    on("q") { _, i in let s = scan(i); s.stack.append(s.state) }
    on("Q") { _, i in let s = scan(i); if let top = s.stack.popLast() { s.state = top } }
    on("cm") { sc, i in
      guard let v = numbers(sc, 6) else { return }
      let s = scan(i)
      s.state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(s.state.ctm)
    }
    on("w") { sc, i in if let v = numbers(sc, 1) { scan(i).state.lineWidth = v[0] } }

    // Paths.
    on("m") { sc, i in if let v = numbers(sc, 2) { scan(i).extend(CGPoint(x: v[0], y: v[1])); scan(i).spend(sc) } }
    on("l") { sc, i in if let v = numbers(sc, 2) { scan(i).extend(CGPoint(x: v[0], y: v[1])); scan(i).spend(sc) } }
    on("c") { sc, i in
      guard let v = numbers(sc, 6) else { return }
      let s = scan(i)
      for k in [0, 2, 4] { s.extend(CGPoint(x: v[k], y: v[k + 1])) }
      s.spend(sc)
    }
    on("v") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      let s = scan(i)
      for k in [0, 2] { s.extend(CGPoint(x: v[k], y: v[k + 1])) }
      s.spend(sc)
    }
    on("y") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      let s = scan(i)
      for k in [0, 2] { s.extend(CGPoint(x: v[k], y: v[k + 1])) }
      s.spend(sc)
    }
    on("re") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      let s = scan(i)
      s.extend(CGPoint(x: v[0], y: v[1]))
      s.extend(CGPoint(x: v[0] + v[2], y: v[1] + v[3]))
      s.spend(sc)
    }
    for name in ["f", "F", "f*"] { on(name) { _, i in scan(i).paint(filled: true, stroked: false) } }
    for name in ["S", "s"] { on(name) { _, i in scan(i).paint(filled: false, stroked: true) } }
    for name in ["B", "B*", "b", "b*"] { on(name) { _, i in scan(i).paint(filled: true, stroked: true) } }
    on("n") { _, i in scan(i).paint(filled: false, stroked: false) }
    on("W") { _, i in scan(i).pendingClip = true }
    on("W*") { _, i in scan(i).pendingClip = true }
    on("sh") { _, i in
      let s = scan(i)
      if s.state.clip.width * s.state.clip.height < s.pageSize.width * s.pageSize.height * 0.8 { s.vectors.append(s.state.clip) }
    }

    // Colors, for telling what's white, and the paper.
    on("g") { sc, i in if let v = numbers(sc, 1) { scan(i).state.fill = Tint(r: v[0], g: v[0], b: v[0]) } }
    on("rg") { sc, i in if let v = numbers(sc, 3) { scan(i).state.fill = Tint(r: v[0], g: v[1], b: v[2]) } }
    on("k") { sc, i in
      guard let v = numbers(sc, 4) else { return }
      scan(i).state.fill = Tint(r: (1 - v[0]) * (1 - v[3]), g: (1 - v[1]) * (1 - v[3]), b: (1 - v[2]) * (1 - v[3]))
    }
    for name in ["sc", "scn"] {
      on(name) { sc, i in
        var comps: [CGFloat] = []
        var x: CGPDFReal = 0
        while comps.count < 4, CGPDFScannerPopNumber(sc, &x) { comps.insert(x, at: 0) }
        let s = scan(i)
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
      let s = scan(i)
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
    on("EI") { _, i in scan(i).image() }

    // Text.
    on("BT") { _, i in
      let s = scan(i)
      s.tm = .identity
      s.tlm = .identity
    }
    on("Tf") { sc, i in
      var size: CGPDFReal = 0
      var name: UnsafePointer<CChar>?
      guard CGPDFScannerPopNumber(sc, &size), CGPDFScannerPopName(sc, &name), let name else { return }
      scan(i).setFont(String(cString: name), size, sc)
    }
    on("Tr") { sc, i in
      var v: CGPDFInteger = 0
      if CGPDFScannerPopInteger(sc, &v) { scan(i).state.render = Int32(v) }
    }
    on("Tc") { sc, i in if let v = numbers(sc, 1) { scan(i).state.charSpace = v[0] } }
    on("Tw") { sc, i in if let v = numbers(sc, 1) { scan(i).state.wordSpace = v[0] } }
    on("Tz") { sc, i in if let v = numbers(sc, 1) { scan(i).state.scale = v[0] / 100 } }
    on("TL") { sc, i in if let v = numbers(sc, 1) { scan(i).state.leading = v[0] } }
    on("Ts") { sc, i in if let v = numbers(sc, 1) { scan(i).state.rise = v[0] } }
    on("Td") { sc, i in if let v = numbers(sc, 2) { scan(i).nextLine(v[0], v[1]) } }
    on("TD") { sc, i in
      guard let v = numbers(sc, 2) else { return }
      scan(i).state.leading = -v[1]
      scan(i).nextLine(v[0], v[1])
    }
    on("Tm") { sc, i in
      guard let v = numbers(sc, 6) else { return }
      let m = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
      scan(i).tm = m
      scan(i).tlm = m
    }
    on("T*") { _, i in scan(i).nextLine(0, -scan(i).state.leading) }
    on("Tj") { sc, i in
      var str: CGPDFStringRef?
      if CGPDFScannerPopString(sc, &str), let str { scan(i).show(str) }
    }
    on("'") { sc, i in
      var str: CGPDFStringRef?
      guard CGPDFScannerPopString(sc, &str), let str else { return }
      let s = scan(i)
      s.nextLine(0, -s.state.leading)
      s.show(str)
    }
    on("\"") { sc, i in
      var str: CGPDFStringRef?
      guard CGPDFScannerPopString(sc, &str), let str else { return }
      let s = scan(i)
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
      let s = scan(i)
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
