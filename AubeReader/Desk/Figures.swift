import UIKit

/// The papers' figures. Drawn rather than pictured, in the page's own inks, so
/// they follow light and dark and stay sharp at any zoom of the desk.
enum Figure {
  /// The Transformer: the encoder and decoder stacks side by side.
  case transformer
  /// Two panels: scaled dot-product attention, and multi-head attention built of it.
  case attention
  /// Where one word's attention goes in a sentence: from "making" to "more difficult".
  case making
  /// The same, from "its" to the noun it stands for.
  case anaphora
  /// GW150914 in each LIGO detector: strain, waveforms, residuals and time–frequency, a column to each.
  case signal
  /// GW150914's waveform at full bandwidth, the horizons meeting, and the pair's separation and speed.
  case waveform
  /// An Advanced LIGO detector, where the two sites are, and how quiet each was.
  case detector
  /// Two histograms: the generic transient search, and the binary coalescence search.
  case searches
  /// Schwarzschild radius against mass, log–log, with known black holes on the line.
  case radius
  /// The onion-shell star whose core is about to collapse.
  case star
  /// Light cones tipping over at the horizon.
  case cones
  /// Time dilation and redshift against distance from the horizon.
  case clocks
  /// Two panels: the orbit of S2, and a gravitational-wave chirp.
  case evidence
  /// Two panels: the waggle dance's geometry, and how its circuits fall off from trip to trip.
  case dance
  /// Scouts at two rival sites, until one reaches a quorum.
  case quorum

  /// Two panels side by side, which on a journal page of two columns run across both.
  var wide: Bool { [.attention, .making, .anaphora, .signal, .detector, .searches, .evidence, .dance].contains(self) }
}

/// The fractional part of `x`, for figures' fixed pseudo-random scatter.
private func frac(_ x: Double) -> Double { x - floor(x) }

/// Maps data onto a plot's box: linear or logarithmic on either axis.
private struct Plot {
  let box: CGRect
  let x: (lo: Double, hi: Double)
  let y: (lo: Double, hi: Double)
  var logX = false
  var logY = false

  func px(_ v: Double) -> CGFloat {
    let f = { (u: Double) in self.logX ? log10(u) : u }
    return box.minX + CGFloat((f(v) - f(x.lo)) / (f(x.hi) - f(x.lo))) * box.width
  }

  func py(_ v: Double) -> CGFloat {
    let f = { (u: Double) in self.logY ? log10(u) : u }
    return box.maxY - CGFloat((f(v) - f(y.lo)) / (f(y.hi) - f(y.lo))) * box.height
  }

  func at(_ a: Double, _ b: Double) -> CGPoint { CGPoint(x: px(a), y: py(b)) }
}

/// A number as a tick label prints it, with a true minus sign.
private func tickText(_ v: Double, _ digits: Int) -> String {
  String(format: "%.\(digits)f", abs(v) < 1e-9 ? 0 : v).replacingOccurrences(of: "-", with: "−")
}

private func ticks(_ lo: Double, _ hi: Double, _ step: Double) -> [Double] {
  stride(from: (lo / step).rounded(.up) * step, through: hi + step * 1e-6, by: step).map { $0 }
}

extension Press {
  /// The size of lettering inside figures.
  private var fs: CGFloat { serif ? max(10, size * 0.74) : max(10, size * 0.6) }

  func draw(_ figure: Figure, in r: CGRect) {
    switch figure {
    case .transformer: transformer(r)
    case .attention:
      let gap = fs * 2
      let w = (r.width - gap) / 2
      scaledDot(CGRect(x: r.minX, y: r.minY, width: w, height: r.height))
      multiHead(CGRect(x: r.minX + w + gap, y: r.minY, width: w, height: r.height))
    case .making:
      sentence(
        r, words: "It is in this spirit that a majority of American governments have passed new laws since 2009 making the registration or voting process more difficult . <EOS> <pad> <pad>",
        from: 17, heads: [[(27, 0.9), (28, 0.5)], [(27, 0.5), (28, 0.8)], [(28, 0.7), (27, 0.3)], [(17, 0.6), (27, 0.4)], [(28, 0.9)]])
    case .anaphora:
      sentence(
        r, words: "The Law will never be perfect , but its application should be just - this is what we are missing , in my opinion . <EOS> <pad>",
        from: 8, heads: [[(1, 0.95), (9, 0.35)], [(9, 0.9), (1, 0.4)]])
    case .signal:
      let gap = fs * 1.2
      // The left column also carries the axis titles.
      let titles = fs * 1.5
      let w = (r.width - titles - gap) / 2
      gwColumn(CGRect(x: r.minX, y: r.minY, width: titles + w, height: r.height), h1: true, titles: titles)
      gwColumn(CGRect(x: r.minX + titles + w + gap, y: r.minY, width: w, height: r.height), h1: false, titles: 0)
    case .waveform: gwWaveform(r)
    case .detector:
      let gap = fs * 1.6
      if r.width > 700 {
        let dw = (r.width * 0.54).rounded()
        interferometer(CGRect(x: r.minX, y: r.minY, width: dw, height: r.height))
        let x = r.minX + dw + gap
        let ah = (r.height * 0.38).rounded()
        ligoSites(CGRect(x: x, y: r.minY, width: r.maxX - x, height: ah))
        ligoNoise(CGRect(x: x, y: r.minY + ah + gap * 0.5, width: r.maxX - x, height: r.height - ah - gap * 0.5))
      } else {
        let dh = (r.height * 0.58).rounded()
        interferometer(CGRect(x: r.minX, y: r.minY, width: r.width, height: dh))
        let w = (r.width - gap) / 2
        let y = r.minY + dh + gap * 0.5
        ligoSites(CGRect(x: r.minX, y: y, width: w, height: r.maxY - y))
        ligoNoise(CGRect(x: r.minX + w + gap, y: y, width: w, height: r.maxY - y))
      }
    case .searches:
      let gap = fs * 2
      let w = (r.width - gap) / 2
      searchPanel(CGRect(x: r.minX, y: r.minY, width: w, height: r.height), coalescence: false)
      searchPanel(CGRect(x: r.minX + w + gap, y: r.minY, width: w, height: r.height), coalescence: true)
    case .radius: radius(r)
    case .star: star(r)
    case .cones: cones(r)
    case .clocks: clocks(r)
    case .evidence:
      let gap = fs * 2
      let w = (r.width - gap) / 2
      orbit(CGRect(x: r.minX, y: r.minY, width: w, height: r.height))
      chirp(CGRect(x: r.minX + w + gap, y: r.minY, width: w, height: r.height))
    case .dance:
      let gap = fs * 2
      let w = (r.width - gap) / 2
      waggle(CGRect(x: r.minX, y: r.minY, width: w, height: r.height))
      decay(CGRect(x: r.minX + w + gap, y: r.minY, width: w, height: r.height))
    case .quorum: quorum(r)
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  private func label(
    _ s: String, _ p: CGPoint, ax: CGFloat = 0.5, ay: CGFloat = 0.5, color: UIColor = Palette.ink, scale: CGFloat = 1
  ) {
    let a = rich(s, size: fs * scale, color: color)
    let z = a.size()
    a.draw(at: CGPoint(x: p.x - z.width * ax, y: p.y - z.height * ay))
  }

  /// A label turned to read upward, centered on `p`.
  private func upright(_ s: String, _ p: CGPoint, color: UIColor = Palette.ink, scale: CGFloat = 1) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: -.pi / 2)
    label(s, .zero, color: color, scale: scale)
    ctx.restoreGState()
  }

  private func stroke(_ path: UIBezierPath, _ color: UIColor = Palette.ink, width: CGFloat = 1, dash: [CGFloat] = []) {
    resolved(color).setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.setLineDash(dash, count: dash.count, phase: 0)
    path.stroke()
  }

  private func segment(_ a: CGPoint, _ b: CGPoint) -> UIBezierPath {
    let p = UIBezierPath()
    p.move(to: a)
    p.addLine(to: b)
    return p
  }

  private func curve(_ points: [CGPoint]) -> UIBezierPath {
    let p = UIBezierPath()
    for (i, q) in points.enumerated() { i == 0 ? p.move(to: q) : p.addLine(to: q) }
    return p
  }

  private func dot(_ p: CGPoint, _ r: CGFloat, filled: Bool = true) {
    let c = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    resolved(filled ? Palette.ink : Palette.page).setFill()
    c.fill()
    if !filled { stroke(c, width: 1) }
  }

  /// The box a plot sits in within `r`, leaving room for its labels.
  private func box(_ r: CGRect, left: CGFloat = 4.4) -> CGRect {
    CGRect(x: r.minX + fs * left, y: r.minY + fs * 0.6, width: r.width - fs * left - fs * 0.9, height: r.height - fs * 0.6 - fs * 3.3)
  }

  /// A framed plot: ticks pointing in on all four sides, numbers on the left and bottom, and axis titles.
  private func axes(_ p: Plot, x xt: [(Double, String?)], y yt: [(Double, String?)], xTitle: String, yTitle: String?) {
    let b = p.box
    let major = fs * 0.45
    for (v, s) in xt {
      let x = p.px(v)
      stroke(segment(CGPoint(x: x, y: b.maxY), CGPoint(x: x, y: b.maxY - major)), width: 0.7)
      stroke(segment(CGPoint(x: x, y: b.minY), CGPoint(x: x, y: b.minY + major)), width: 0.7)
      if let s { label(s, CGPoint(x: x, y: b.maxY + fs * 0.35), ay: 0) }
    }
    var widest: CGFloat = 0
    for (v, s) in yt {
      let y = p.py(v)
      stroke(segment(CGPoint(x: b.minX, y: y), CGPoint(x: b.minX + major, y: y)), width: 0.7)
      stroke(segment(CGPoint(x: b.maxX, y: y), CGPoint(x: b.maxX - major, y: y)), width: 0.7)
      if let s {
        label(s, CGPoint(x: b.minX - fs * 0.4, y: y), ax: 1)
        widest = max(widest, rich(s, size: fs).size().width)
      }
    }
    stroke(UIBezierPath(rect: b), width: 0.9)
    label(xTitle, CGPoint(x: b.midX, y: b.maxY + fs * 1.75), ay: 0)
    if let yTitle { upright(yTitle, CGPoint(x: b.minX - fs * 0.4 - widest - fs * 0.95, y: b.midY)) }
  }

  private func clip(_ rect: CGRect, _ body: () -> Void) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    body()
    ctx.restoreGState()
  }

  private func arrowhead(_ tip: CGPoint, toward d: CGPoint, _ color: UIColor = Palette.ink) {
    let n = max(0.001, hypot(d.x, d.y))
    let u = CGPoint(x: d.x / n, y: d.y / n)
    let k = fs * 0.5
    let head = UIBezierPath()
    head.move(to: tip)
    head.addLine(to: CGPoint(x: tip.x - u.x * k - u.y * k * 0.5, y: tip.y - u.y * k + u.x * k * 0.5))
    head.addLine(to: CGPoint(x: tip.x - u.x * k + u.y * k * 0.5, y: tip.y - u.y * k - u.x * k * 0.5))
    head.close()
    resolved(color).setFill()
    head.fill()
  }

  // ─── Fig.: the Transformer ─────────────────────────────────────────────

  /// Paper of the page tinted with `share` of the ink, for filling a box.
  private func tint(_ share: CGFloat) -> UIColor { Palette.mix(Palette.ink, share, over: Palette.page, .current) }

  /// A box with rounded corners, filled, outlined and labelled line by line.
  private func unit(_ b: CGRect, _ lines: [String], fill: CGFloat, weight: CGFloat = 1.3) {
    let path = UIBezierPath(roundedRect: b, cornerRadius: min(b.height * 0.25, fs * 0.5))
    tint(fill).setFill()
    path.fill()
    stroke(path, width: weight)
    let lead = fs * 1.15
    for (k, l) in lines.enumerated() {
      label(l, CGPoint(x: b.midX, y: b.midY + (CGFloat(k) - CGFloat(lines.count - 1) / 2) * lead))
    }
  }

  /// A line from `a` up or across to `b`, with a head at `b`.
  private func arrow(_ points: [CGPoint], width: CGFloat = 1.2) {
    guard points.count > 1 else { return }
    let tip = points[points.count - 1]
    let from = points[points.count - 2]
    let d = CGPoint(x: tip.x - from.x, y: tip.y - from.y)
    let n = max(0.001, hypot(d.x, d.y))
    // The line stops short of the tip, under the head.
    let k = fs * 0.4
    var body = points
    body[body.count - 1] = CGPoint(x: tip.x - d.x / n * k, y: tip.y - d.y / n * k)
    stroke(rounded(body, fs * 0.6), width: width)
    arrowhead(tip, toward: d)
  }

  /// A path through `points` with its corners rounded off by `radius`.
  private func rounded(_ points: [CGPoint], _ radius: CGFloat) -> UIBezierPath {
    let p = UIBezierPath()
    guard let first = points.first else { return p }
    p.move(to: first)
    if points.count > 2 {
      for i in 1..<(points.count - 1) {
        let a = points[i - 1], c = points[i], b = points[i + 1]
        let la = hypot(c.x - a.x, c.y - a.y), lb = hypot(b.x - c.x, b.y - c.y)
        let t = min(radius, la / 2, lb / 2)
        let p1 = CGPoint(x: c.x + (a.x - c.x) / max(la, 0.001) * t, y: c.y + (a.y - c.y) / max(la, 0.001) * t)
        let p2 = CGPoint(x: c.x + (b.x - c.x) / max(lb, 0.001) * t, y: c.y + (b.y - c.y) / max(lb, 0.001) * t)
        p.addLine(to: p1)
        p.addQuadCurve(to: p2, controlPoint: c)
      }
    }
    p.addLine(to: points[points.count - 1])
    return p
  }

  /// The three inputs of an attention box whose bottom is at `y`, forking from the line up at `x`.
  private func fork(_ x: CGFloat, _ y: CGFloat, spread: CGFloat, from: CGFloat, skip: Bool = false) {
    arrow([CGPoint(x: x, y: from), CGPoint(x: x, y: y)])
    let split = from - (from - y) * 0.35
    for side in [-1.0, 1.0] where !(skip && side < 0) {
      let at = x + spread * CGFloat(side)
      arrow([CGPoint(x: x, y: split), CGPoint(x: at, y: split), CGPoint(x: at, y: y)], width: 1.1)
    }
  }

  private func transformer(_ r: CGRect) {
    let u = r.width / 100
    let v = r.height / 118
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * u, y: r.minY + y * v) }
    func R(_ cx: CGFloat, _ y0: CGFloat, _ y1: CGFloat, w: CGFloat = 24) -> CGRect {
      CGRect(x: r.minX + (cx - w / 2) * u, y: r.minY + y0 * v, width: w * u, height: (y1 - y0) * v)
    }
    let ex: CGFloat = 31
    let dx: CGFloat = 69
    let attention: CGFloat = 0.16
    let forward: CGFloat = 0.07
    let norm: CGFloat = 0.02

    // The two stacks, each repeated N times.
    for (frame, x, side) in [(R(ex, 46, 91, w: 34), CGFloat(4), "N×"), (R(dx, 26, 91, w: 34), CGFloat(96), "N×")] {
      let path = UIBezierPath(roundedRect: frame, cornerRadius: fs * 0.9)
      tint(0.035).setFill()
      path.fill()
      stroke(path, width: 1.2)
      label(side, CGPoint(x: r.minX + x * u, y: frame.midY), scale: 1.15)
    }

    // The encoder, from the bottom up: the main line, its sub-layers, and the residual paths around them.
    stroke(segment(P(ex, 95), P(ex, 85.5)), width: 1.2)
    fork(r.minX + ex * u, R(ex, 75, 83).maxY, spread: 7 * u, from: r.minY + 87.5 * v)
    arrow([P(ex, 89), P(ex - 14, 89), P(ex - 14, 72.5), P(ex - 12, 72.5)])
    unit(R(ex, 75, 83), ["Multi-Head", "Attention"], fill: attention)
    unit(R(ex, 70.5, 74.5), ["Add & Norm"], fill: norm)
    arrow([P(ex, 70.5), P(ex, 64)])
    arrow([P(ex, 67.5), P(ex - 14, 67.5), P(ex - 14, 54.5), P(ex - 12, 54.5)])
    unit(R(ex, 56, 64), ["Feed", "Forward"], fill: forward)
    unit(R(ex, 52.5, 56.5), ["Add & Norm"], fill: norm)
    // Out of the encoder, over the gap, and into the decoder's middle attention.
    stroke(rounded([P(ex, 52.5), P(ex, 43), P(50, 43), P(50, 68), P(dx - 7, 68)], fs * 0.6), width: 1.2)
    arrow([P(dx - 7, 68), P(dx - 7, 64)], width: 1.1)
    arrow([P(50, 68), P(dx, 68), P(dx, 64)], width: 1.1)

    // The decoder.
    stroke(segment(P(dx, 95), P(dx, 87)), width: 1.2)
    fork(r.minX + dx * u, R(dx, 75, 85).maxY, spread: 7 * u, from: r.minY + 88.5 * v)
    arrow([P(dx, 89.5), P(dx + 14, 89.5), P(dx + 14, 72.5), P(dx + 12, 72.5)])
    unit(R(dx, 75, 85), ["Masked", "Multi-Head", "Attention"], fill: attention)
    unit(R(dx, 70.5, 74.5), ["Add & Norm"], fill: norm)
    // Its own stream is the query, on the right; the encoder's gives keys and values.
    arrow([P(dx, 70.5), P(dx, 69.5), P(dx + 7, 69.5), P(dx + 7, 64)], width: 1.1)
    arrow([P(dx + 7, 69.5), P(dx + 14, 69.5), P(dx + 14, 52.5), P(dx + 12, 52.5)])
    unit(R(dx, 56, 64), ["Multi-Head", "Attention"], fill: attention)
    unit(R(dx, 50.5, 54.5), ["Add & Norm"], fill: norm)
    arrow([P(dx, 50.5), P(dx, 44)])
    arrow([P(dx, 47.5), P(dx + 14, 47.5), P(dx + 14, 32.5), P(dx + 12, 32.5)])
    unit(R(dx, 36, 44), ["Feed", "Forward"], fill: forward)
    unit(R(dx, 30.5, 34.5), ["Add & Norm"], fill: norm)
    arrow([P(dx, 30.5), P(dx, 22)])
    unit(R(dx, 17, 22), ["Linear"], fill: 0.05)
    arrow([P(dx, 17), P(dx, 13)])
    unit(R(dx, 8, 13), ["Softmax"], fill: 0.1)
    arrow([P(dx, 8), P(dx, 5.5)])
    label("Output Probabilities", P(dx, 3))

    // Below the stacks: embeddings, and the positions added to them.
    for (x, out, words) in [(ex, -1.0, ["Input", "Embedding"]), (dx, 1.0, ["Output", "Embedding"])] {
      unit(R(x, 99, 107), words, fill: 0.09)
      let plus = P(x, 95)
      let rad = fs * 0.55
      arrow([P(x, 110), P(x, 107)])
      arrow([P(x, 99), CGPoint(x: plus.x, y: plus.y + rad)])
      let ring = UIBezierPath(ovalIn: CGRect(x: plus.x - rad, y: plus.y - rad, width: 2 * rad, height: 2 * rad))
      tint(0).setFill()
      ring.fill()
      stroke(ring, width: 1.1)
      stroke(segment(CGPoint(x: plus.x - rad * 0.6, y: plus.y), CGPoint(x: plus.x + rad * 0.6, y: plus.y)), width: 1)
      stroke(segment(CGPoint(x: plus.x, y: plus.y - rad * 0.6), CGPoint(x: plus.x, y: plus.y + rad * 0.6)), width: 1)
      // A sinusoid in a circle, the positional encoding, beside the sum it goes into.
      let wave = P(x + CGFloat(out) * 9, 95)
      let wr = fs * 0.85
      stroke(segment(CGPoint(x: plus.x + CGFloat(out) * rad, y: plus.y), CGPoint(x: wave.x - CGFloat(out) * wr, y: wave.y)), width: 1.1)
      let circle = UIBezierPath(ovalIn: CGRect(x: wave.x - wr, y: wave.y - wr, width: 2 * wr, height: 2 * wr))
      tint(0).setFill()
      circle.fill()
      stroke(circle, width: 1.1)
      stroke(curve(stride(from: -1.0, through: 1.0, by: 0.05).map { t in
        CGPoint(x: wave.x + CGFloat(t) * wr * 0.75, y: wave.y - CGFloat(sin(t * .pi)) * wr * 0.4)
      }), width: 1)
      let name = ["Positional", "Encoding"]
      let at = x + CGFloat(out) * 14
      for (k, line) in name.enumerated() {
        label(line, CGPoint(x: r.minX + at * u, y: plus.y + (CGFloat(k) - 0.5) * fs * 1.15), ax: out < 0 ? 1 : 0, color: Palette.quiet)
      }
    }
    label("Inputs", P(ex, 112))
    label("Outputs", P(dx, 111))
    label("(shifted right)", P(dx, 115), color: Palette.quiet)
  }

  /// Scaled dot-product attention: two matrix products, with a scaling, an optional mask and a softmax between.
  private func scaledDot(_ r: CGRect) {
    let u = r.width / 100
    let v = r.height / 100
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * u, y: r.minY + y * v) }
    func R(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
      CGRect(x: r.minX + x0 * u, y: r.minY + y0 * v, width: (x1 - x0) * u, height: (y1 - y0) * v)
    }
    label("**Scaled Dot-Product Attention**", P(50, 3))
    let cx: CGFloat = 40
    let w: CGFloat = 34
    arrow([P(47.5, 18), P(47.5, 9)])
    unit(R(cx - w / 2, 72, 18, 25.5), ["MatMul"], fill: 0.13)
    arrow([P(cx, 37), P(cx, 25.5)])
    unit(R(cx - w / 2, cx + w / 2, 30, 37), ["SoftMax"], fill: 0.08)
    arrow([P(cx, 49), P(cx, 37)])
    unit(R(cx - w / 2, cx + w / 2, 42, 49), ["Mask (opt.)"], fill: 0.05)
    arrow([P(cx, 61), P(cx, 49)])
    unit(R(cx - w * 0.35, cx + w * 0.35, 54, 61), ["Scale"], fill: 0.02)
    arrow([P(cx, 73), P(cx, 61)])
    unit(R(cx - w / 2, cx + w / 2, 73, 80.5), ["MatMul"], fill: 0.13)
    for (x, name) in [(cx - 9, "Q"), (cx + 9, "K")] {
      arrow([P(x, 90), P(x, 80.5)])
      label(name, P(x, 95), scale: 1.15)
    }
    arrow([P(64, 90), P(64, 25.5)])
    label("V", P(64, 95), scale: 1.15)
  }

  /// Multi-head attention: queries, keys and values projected h times, attended to in parallel, joined and projected again.
  private func multiHead(_ r: CGRect) {
    let u = r.width / 100
    let v = r.height / 100
    func R(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> CGRect {
      CGRect(x: r.minX + x0 * u, y: r.minY + y0 * v, width: (x1 - x0) * u, height: (y1 - y0) * v)
    }
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * u, y: r.minY + y * v) }
    label("**Multi-Head Attention**", P(50, 3))
    let step = CGPoint(x: 2.2 * u, y: -2.2 * v)
    // The heads behind, fainter the further back.
    for k in stride(from: 2, through: 1, by: -1) {
      let off = CGAffineTransform(translationX: step.x * CGFloat(k), y: step.y * CGFloat(k))
      let back = R(6, 86, 46, 60).applying(off)
      let path = UIBezierPath(roundedRect: back, cornerRadius: fs * 0.5)
      tint(0.06).setFill()
      path.fill()
      stroke(path, Palette.muted, width: 1)
      for x in [20.0, 50.0, 80.0] {
        let lin = R(CGFloat(x) - 12, CGFloat(x) + 12, 72, 79.5).applying(off)
        let lp = UIBezierPath(roundedRect: lin, cornerRadius: fs * 0.4)
        tint(0.02).setFill()
        lp.fill()
        stroke(lp, Palette.muted, width: 1)
      }
    }
    for (x, name) in [(20.0, "V"), (50.0, "K"), (80.0, "Q")] {
      let x = CGFloat(x)
      arrow([P(x, 89), P(x, 79.5)])
      label(name, P(x, 94), scale: 1.15)
      unit(R(x - 12, x + 12, 72, 79.5), ["Linear"], fill: 0.02)
      arrow([P(x, 72), P(x, 60)])
    }
    unit(R(6, 86, 46, 60), ["Scaled Dot-Product", "Attention"], fill: 0.13)
    // The brace that counts the heads.
    let brace = UIBezierPath()
    brace.move(to: P(89, 41))
    brace.addQuadCurve(to: P(92, 50), controlPoint: P(92, 42))
    brace.addQuadCurve(to: P(89, 57), controlPoint: P(92, 56))
    stroke(brace, width: 1.1)
    stroke(segment(P(92, 49.5), P(95, 49.5)), width: 1)
    label("*h*", P(97.5, 49.5), scale: 1.15)
    arrow([P(46, 46), P(46, 33)])
    unit(R(30, 62, 25.5, 33), ["Concat"], fill: 0.05)
    arrow([P(46, 25.5), P(46, 18.5)])
    unit(R(32, 60, 11, 18.5), ["Linear"], fill: 0.02)
    arrow([P(46, 11), P(46, 6)])
  }

  // ─── Fig.: attention in a sentence ─────────────────────────────────────

  /// A sentence set twice, word by word, upright in two rows, and lines from
  /// word `from` in the upper row to the words its heads attend to in the
  /// lower, one style of line for each head and as strong as its weight.
  private func sentence(_ r: CGRect, words line: String, from: Int, heads: [[(Int, CGFloat)]]) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    let words = line.split(separator: " ").map(String.init)
    let pitch = r.width / CGFloat(words.count)
    let scale = min(1, pitch / (fs * 1.15))
    let tall = words.map { rich($0, size: fs * scale).size().width }.max() ?? 0
    let top = r.minY + tall + fs * 0.3
    let bottom = r.maxY - tall - fs * 0.3
    func x(_ i: Int) -> CGFloat { r.minX + pitch * (CGFloat(i) + 0.5) }
    let styles: [[CGFloat]] = [[], [5, 3], [1.4, 2.6], [8, 3, 1.4, 3], [2.5, 2.5]]
    for (k, head) in heads.enumerated() {
      for (to, weight) in head {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x(from), y: top + fs * 0.2))
        path.addLine(to: CGPoint(x: x(to), y: bottom - fs * 0.2))
        ctx.saveGState()
        ctx.setAlpha(0.3 + 0.7 * weight)
        stroke(path, width: 0.6 + 1.6 * weight, dash: styles[k % styles.count])
        ctx.restoreGState()
      }
    }
    let targets = Set(heads.flatMap { $0.map(\.0) })
    for (i, w) in words.enumerated() {
      let pad = w.hasPrefix("<") ? Palette.muted : Palette.ink
      // Read upward: the upper row runs up from its line ends, the lower row up to them.
      for (row, y) in [(0, top), (1, bottom)] {
        ctx.saveGState()
        ctx.translateBy(x: x(i), y: y)
        ctx.rotate(by: -.pi / 2)
        let strong = (row == 0 && i == from) || (row == 1 && targets.contains(i))
        let a = rich(strong ? "**\(w)**" : w, size: fs * scale, color: pad)
        let z = a.size()
        a.draw(at: CGPoint(x: row == 0 ? fs * 0.1 : -z.width - fs * 0.1, y: -z.height / 2))
        ctx.restoreGState()
      }
    }
  }

  // ─── Figs.: GW150914 ───────────────────────────────────────────────────

  private static let gwSpan = (lo: -0.36, hi: 0.06)
  private static let gwRate = 16384.0

  /// GW150914's strain against seconds from its peak, in units of 10⁻²¹, with its frequency and amplitude
  /// at each moment: a Newtonian chirp for a chirp mass of 30 solar masses, from 35 Hz up to 150 Hz at the
  /// peak, then the remnant ringing down at 250 Hz.
  private static let gwWave: [(h: Double, f: Double, a: Double)] = {
    var out: [(Double, Double, Double)] = []
    var phase = 0.0
    for i in 0...Int((gwSpan.hi - gwSpan.lo) * gwRate) {
      let t = gwSpan.lo + Double(i) / gwRate
      let f: Double
      let a: Double
      if t < 0 {
        f = 18 * pow(-t + 0.0035, -0.375)
        a = pow(f / 150, 2.0 / 3)
      } else {
        f = 250 - 100 * exp(-t / 0.0015)
        a = exp(-t / 0.004)
      }
      phase += 2 * .pi * f / gwRate
      out.append((a * cos(phase), f, a))
    }
    return out
  }()

  /// The waveform `t` seconds from its peak; nothing outside the stretch it's worked out for.
  private func gw(_ t: Double) -> (h: Double, f: Double, a: Double) {
    let i = Int(((t - Self.gwSpan.lo) * Self.gwRate).rounded())
    guard i >= 0, i < Self.gwWave.count else { return (0, 0, 0) }
    return Self.gwWave[i]
  }

  /// The waveform as the 35–350 Hz bandpass leaves it.
  private func gwFiltered(_ t: Double) -> Double {
    let w = gw(t)
    let u = max(0, min(1, (w.f - 28) / 12))
    return w.h * u * u * (3 - 2 * u)
  }

  /// A detector's noise after the bandpass: a fixed sum of tones between 40 and 300 Hz, its own for each seed.
  private func gwNoise(_ t: Double, seed: Int, rms: Double = 0.26) -> Double {
    var s = 0.0
    for k in 0..<48 {
      let a = Double(k * 7 + seed * 131 + 1)
      let f = 40 + 260 * frac(sin(a * 12.9898) * 43758.5453)
      s += cos(2 * .pi * f * t + 2 * .pi * frac(sin(a * 78.233) * 12543.137))
    }
    return s * rms / sqrt(24)
  }

  /// A band between two curves, filled.
  private func band(_ upper: [CGPoint], _ lower: [CGPoint], _ color: UIColor) {
    guard let first = upper.first else { return }
    let path = UIBezierPath()
    path.move(to: first)
    for q in upper.dropFirst() { path.addLine(to: q) }
    for q in lower.reversed() { path.addLine(to: q) }
    path.close()
    resolved(color).setFill()
    path.fill()
  }

  /// A short sample of a line for a key, and what it stands for after it.
  private func key(_ at: CGPoint, _ name: String, color: UIColor = Palette.ink, dash: [CGFloat] = [], dot: Bool? = nil, line: Bool = true) {
    let w = fs * 1.8
    if line { stroke(segment(at, CGPoint(x: at.x + w, y: at.y)), color, width: 1.1, dash: dash) }
    if let filled = dot { self.dot(CGPoint(x: at.x + w / 2, y: at.y), fs * 0.24, filled: filled) }
    label(name, CGPoint(x: at.x + w + fs * 0.4, y: at.y), ax: 0, color: Palette.quiet, scale: 0.85)
  }

  /// A logarithmic tick's label, 10 to the power `k`.
  private func decade(_ k: Int) -> String { "10^{\(tickText(Double(k), 0))}" }

  // Fig. 1 ──────────────────────────────────────────────────────────────

  /// One detector's column of Fig. 1, from the top: observed strain, the waveform and its reconstructions,
  /// what's left when the waveform is taken away, and the strain's time–frequency map. `titles` is room
  /// at the left for the axis titles, which only the first column sets.
  private func gwColumn(_ r: CGRect, h1: Bool, titles: CGFloat) {
    let head = fs * 1.8
    let foot = fs * 3.0
    let pad = fs * 0.5
    let left = titles + fs * 2.4
    let rh = (r.height - head - foot - pad * 3) / 4
    let t0 = 0.25, t1 = 0.45
    // L1 saw it first; H1 6.9 ms later and, for the way it faces, upside down.
    let lag = 0.0069
    let peak = h1 ? 0.423 : 0.423 - lag
    let sign = h1 ? -1.0 : 1.0
    let seed = h1 ? 1 : 2
    func row(_ k: Int) -> CGRect {
      CGRect(x: r.minX + left, y: r.minY + head + CGFloat(k) * (rh + pad), width: r.width - left - fs * 1.1, height: rh)
    }
    label(h1 ? "**Hanford, Washington (H1)**" : "**Livingston, Louisiana (L1)**", CGPoint(x: row(0).midX, y: r.minY + head * 0.42))
    let ts = Array(stride(from: t0, through: t1, by: 1 / 4096.0))
    func wave(_ t: Double) -> Double { sign * gwFiltered(t - peak) }
    func h1Data(_ t: Double) -> Double { -gwFiltered(t - 0.423) + gwNoise(t, seed: 1) }
    func data(_ t: Double) -> Double { h1 ? h1Data(t) : wave(t) + gwNoise(t, seed: seed) }
    let strain: [(Double, String?)] = [(-1, "−1"), (-0.5, nil), (0, "0"), (0.5, nil), (1, "1")]
    let time = ticks(t0, t1, 0.05).map { ($0, nil as String?) }
    func tag(_ b: CGRect, _ s: String) { label(s, CGPoint(x: b.minX + fs * 0.4, y: b.minY + fs * 0.3), ax: 0, ay: 0, color: Palette.quiet, scale: 0.85) }

    // Observed, with H1 brought forward and turned over beside L1.
    var p = Plot(box: row(0), x: (t0, t1), y: (-1.6, 1.6))
    clip(p.box) {
      if !h1 { stroke(curve(ts.map { p.at($0, -h1Data($0 + lag)) }), Palette.muted, width: 0.8) }
      stroke(curve(ts.map { p.at($0, data($0)) }), width: 0.8)
    }
    tag(p.box, h1 ? "H1 observed" : "L1 observed; H1 shifted, inverted (grey)")
    axes(p, x: time, y: strain, xTitle: "", yTitle: nil)

    // The waveform, within the two reconstructions' 90% regions.
    p = Plot(box: row(1), x: (t0, t1), y: (-1.6, 1.6))
    clip(p.box) {
      for (width, share) in [(0.2, 0.12), (0.1, 0.32)] {
        let w = { (t: Double) in width * (0.25 + 0.75 * min(1, self.gw(t - peak).a)) }
        band(ts.map { p.at($0, wave($0) + w($0)) }, ts.map { p.at($0, wave($0) - w($0)) }, tint(CGFloat(share)))
      }
      stroke(curve(ts.map { p.at($0, wave($0)) }), width: 1)
    }
    tag(p.box, "Numerical relativity; reconstructed")
    axes(p, x: time, y: strain, xTitle: "", yTitle: nil)

    // What the waveform doesn't account for.
    p = Plot(box: row(2), x: (t0, t1), y: (-1.6, 1.6))
    clip(p.box) { stroke(curve(ts.map { p.at($0, data($0) - wave($0)) }), width: 0.8) }
    tag(p.box, "Residual")
    axes(p, x: time, y: strain, xTitle: "", yTitle: nil)

    // Time–frequency: the signal climbing, over a faint speckle of noise.
    p = Plot(box: row(3), x: (t0, t1), y: (32, 512), logY: true)
    let nx = 96, ny = 36
    let cw = p.box.width / CGFloat(nx)
    let ch = p.box.height / CGFloat(ny)
    for i in 0..<nx {
      let t = t0 + (t1 - t0) * (Double(i) + 0.5) / Double(nx)
      let w = gw(t - peak)
      for j in 0..<ny {
        let f = 32 * pow(16, (Double(j) + 0.5) / Double(ny))
        let ridge = w.f > 30 ? exp(-pow(log(f / w.f) / 0.2, 2)) * min(1, w.a * 1.25) : 0
        let speckle = 0.14 * frac(sin(Double(i * 131 + j * 17 + seed * 7)) * 43758.5453)
        tint(0.03 + 0.85 * CGFloat(min(1, ridge + speckle))).setFill()
        UIRectFill(CGRect(x: p.box.minX + CGFloat(i) * cw, y: p.box.maxY - CGFloat(j + 1) * ch, width: cw + 0.5, height: ch + 0.5))
      }
    }
    axes(
      p, x: ticks(t0, t1, 0.05).map { ($0, tickText($0, 2)) }, y: [(32, "32"), (64, nil), (128, "128"), (256, nil), (512, "512")],
      xTitle: "Time (s)", yTitle: nil)

    if titles > 0 {
      let x = r.minX + fs * 0.6
      upright("Strain (10^{−21})", CGPoint(x: x, y: (row(0).minY + row(2).maxY) / 2), scale: 0.9)
      upright("Frequency (Hz)", CGPoint(x: x, y: row(3).midY), scale: 0.8)
    }
  }

  // Fig. 2 ──────────────────────────────────────────────────────────────

  /// The waveform at full bandwidth under the horizons as they meet, and below it how far apart, in
  /// Schwarzschild radii, and how fast, as a share of light's speed, the two black holes were.
  private func gwWaveform(_ r: CGRect) {
    let t0 = 0.30, t1 = 0.46, peak = 0.423
    let left = fs * 3.4
    let right = fs * 3.6
    let insets = fs * 3.0
    let foot = fs * 3.0
    let gap = fs * 0.5
    let usable = r.height - insets - foot - gap
    let top = CGRect(x: r.minX + left, y: r.minY + insets, width: r.width - left - right, height: (usable * 0.56).rounded())
    let low = CGRect(x: top.minX, y: top.maxY + gap, width: top.width, height: usable - top.height)
    let ends = [0.4125, 0.4265]
    let ts = Array(stride(from: t0, through: t1, by: 1 / 8192.0))

    var p = Plot(box: top, x: (t0, t1), y: (-1.3, 1.3))
    clip(top) { stroke(curve(ts.map { p.at($0, -gw($0 - peak).h) }), width: 1) }
    for e in ends {
      stroke(segment(CGPoint(x: p.px(e), y: top.minY), CGPoint(x: p.px(e), y: low.maxY)), Palette.muted, width: 0.8, dash: [0.1, 3])
    }
    // The phases, with the horizons above each as numerical relativity draws them.
    let rad = fs * 0.42
    let phases: [(String, Double, [CGFloat])] = [
      ("Inspiral", (t0 + ends[0]) / 2, [-2.3, 2.3]), ("Merger", (ends[0] + ends[1]) / 2, [-0.75, 0.75]),
      ("Ringdown", (ends[1] + t1) / 2, [0]),
    ]
    for (k, (name, t, centres)) in phases.enumerated() {
      let x = p.px(t)
      let y = r.minY + insets * 0.42
      for c in centres {
        let rr = centres.count == 1 ? rad * 1.3 : rad
        resolved(Palette.ink).setFill()
        UIBezierPath(ovalIn: CGRect(x: x + c * rad - rr, y: y - rr, width: 2 * rr, height: 2 * rr)).fill()
      }
      label(name, CGPoint(x: x, y: top.minY + fs * 0.25), ay: 0, color: Palette.quiet, scale: k == 1 ? 0.75 : 0.85)
    }
    axes(
      p, x: ticks(t0, t1, 0.05).map { ($0, nil) }, y: [(-1, "−1"), (-0.5, nil), (0, "0"), (0.5, nil), (1, "1")],
      xTitle: "", yTitle: "Strain (10^{−21})")

    // Kepler's separation and the post-Newtonian speed, through the inspiral; GM/c³ is 0.345 ms for 70 solar masses.
    p = Plot(box: low, x: (t0, t1), y: (0, 4.5))
    let speed = Plot(box: low, x: (t0, t1), y: (0.2, 0.65))
    let inspiral = ts.filter { $0 <= peak + 0.0015 }
    let v = inspiral.map { t -> Double in pow(.pi * 3.45e-4 * max(gw(t - peak).f, 1), 1.0 / 3) }
    clip(low) {
      stroke(curve(zip(inspiral, v).map { p.at($0, 0.5 / ($1 * $1)) }), width: 1.3)
      stroke(curve(zip(inspiral, v).map { speed.at($0, $1) }), width: 1.3, dash: [5, 3])
    }
    let at = Int(Double(v.count) * 0.22)
    label("separation", p.at(inspiral[at], 0.5 / (v[at] * v[at])).applying(.init(translationX: 0, y: -fs * 0.35)), ay: 1, color: Palette.quiet, scale: 0.85)
    label("velocity", speed.at(inspiral[at], v[at]).applying(.init(translationX: 0, y: fs * 0.35)), ay: 0, color: Palette.quiet, scale: 0.85)
    axes(
      p, x: ticks(t0, t1, 0.05).map { ($0, tickText($0, 2)) }, y: ticks(0, 4, 1).map { ($0, tickText($0, 0)) },
      xTitle: "Time (s)", yTitle: "Separation (*R*_{S})")
    // Speed reads off the right-hand side.
    for s in [0.3, 0.4, 0.5, 0.6] {
      let y = speed.py(s)
      stroke(segment(CGPoint(x: low.maxX, y: y), CGPoint(x: low.maxX - fs * 0.45, y: y)), width: 0.7)
      label(tickText(s, 1), CGPoint(x: low.maxX + fs * 0.4, y: y), ax: 0)
    }
    upright("Velocity (*c*)", CGPoint(x: low.maxX + fs * 2.9, y: low.midY))
  }

  // Fig. 3 ──────────────────────────────────────────────────────────────

  /// A mirror across a beam: a short slab, standing up for a beam across and lying down for a beam up.
  private func mirror(_ c: CGPoint, upright: Bool, length: CGFloat, share: CGFloat = 0.35) {
    let t = fs * 0.32
    let rect = upright
      ? CGRect(x: c.x - t / 2, y: c.y - length / 2, width: t, height: length)
      : CGRect(x: c.x - length / 2, y: c.y - t / 2, width: length, height: t)
    tint(share).setFill()
    UIRectFill(rect)
    stroke(UIBezierPath(rect: rect), width: 0.9)
  }

  /// An Advanced LIGO detector, not to scale: a Michelson interferometer whose arms are 4 km cavities,
  /// with power recycling at its input and signal recycling at its output.
  private func interferometer(_ r: CGRect) {
    let u = r.width / 100
    let v = r.height / 100
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * u, y: r.minY + y * v) }
    let beam: CGFloat = 64
    let bs = P(42, beam)
    let small = min(9 * v, 9 * u)
    let big = min(13 * v, 13 * u)
    // The beams: thin where the light passes once, heavy where it builds up in the arms.
    stroke(segment(P(15, beam), bs), width: 1.1)
    stroke(segment(bs, P(54, beam)), width: 1.1)
    stroke(segment(bs, P(42, 52)), width: 1.1)
    stroke(segment(P(54, beam), P(95, beam)), width: 2.6)
    stroke(segment(P(42, 52), P(42, 8)), width: 2.6)
    stroke(segment(bs, P(42, 91)), width: 1.1)
    // The laser, the recycling mirrors, the test masses, the splitter and the photodetector.
    unit(CGRect(x: P(2, beam).x, y: bs.y - fs * 0.9, width: 13 * u, height: fs * 1.8), ["Laser"], fill: 0.1, weight: 1.1)
    mirror(P(26, beam), upright: true, length: small)
    mirror(P(54, beam), upright: true, length: small)
    mirror(P(95, beam), upright: true, length: big, share: 0.55)
    mirror(P(42, 52), upright: false, length: small)
    mirror(P(42, 8), upright: false, length: big, share: 0.55)
    mirror(P(42, 82), upright: false, length: small)
    let split = UIBezierPath()
    split.move(to: CGPoint(x: bs.x - small * 0.45, y: bs.y + small * 0.45))
    split.addLine(to: CGPoint(x: bs.x + small * 0.45, y: bs.y - small * 0.45))
    stroke(split, width: 3)
    let pd = P(42, 94)
    let cup = UIBezierPath(arcCenter: pd, radius: fs * 0.6, startAngle: 0, endAngle: .pi, clockwise: true)
    cup.close()
    resolved(Palette.ink).setFill()
    cup.fill()
    // What each part is.
    let s: CGFloat = 0.85
    label("20 W", P(20.5, beam - 2), ay: 1, color: Palette.quiet, scale: s)
    label("700 W", P(34, beam - 2), ay: 1, color: Palette.quiet, scale: s)
    label("Power-recycling", P(26, beam + 7), ay: 0, color: Palette.quiet, scale: s)
    label("mirror", CGPoint(x: P(26, 0).x, y: P(0, beam + 7).y + fs * 1.05), ay: 0, color: Palette.quiet, scale: s)
    label("Beam splitter", P(40, beam - 9), ax: 1, color: Palette.quiet, scale: s)
    // Beside the mirrors across the upward arm, clear of their ends.
    let beside = { (half: CGFloat, y: CGFloat) in CGPoint(x: bs.x + half / 2 + self.fs * 0.5, y: P(0, y).y) }
    label("Input test mass", beside(small, 52), ax: 0, color: Palette.quiet, scale: s)
    label("End test mass", beside(big, 8), ax: 0, color: Palette.quiet, scale: s)
    label("4 km", P(39, 30), ax: 1, scale: s)
    label("Input", P(54, beam + 7), ay: 0, color: Palette.quiet, scale: s)
    label("test mass", CGPoint(x: P(54, 0).x, y: P(0, beam + 7).y + fs * 1.05), ay: 0, color: Palette.quiet, scale: s)
    label("End", P(96, beam + 9), ax: 1, ay: 0, color: Palette.quiet, scale: s)
    label("test mass", CGPoint(x: P(96, 0).x, y: P(0, beam + 9).y + fs * 1.05), ax: 1, ay: 0, color: Palette.quiet, scale: s)
    label("4 km", P(74.5, beam + 3), ay: 0, scale: s)
    label("100 kW circulating", P(74.5, beam - 2.5), ay: 1, color: Palette.quiet, scale: s)
    label("Signal-recycling mirror", beside(small, 82), ax: 0, color: Palette.quiet, scale: s)
    label("Photodetector", CGPoint(x: pd.x + fs * 1.1, y: pd.y + fs * 0.3), ax: 0, color: Palette.quiet, scale: s)
  }

  /// Inset (a): the two sites, each an L at its own bearing, about 3,000 km and 10 light-milliseconds apart.
  private func ligoSites(_ r: CGRect) {
    let f = r.insetBy(dx: 1, dy: 1)
    stroke(UIBezierPath(roundedRect: f, cornerRadius: fs * 0.4), Palette.line, width: 0.8)
    label("(a)", CGPoint(x: f.minX + fs * 0.5, y: f.minY + fs * 0.4), ax: 0, ay: 0)
    let h = CGPoint(x: f.minX + f.width * 0.3, y: f.minY + f.height * 0.4)
    let l = CGPoint(x: f.minX + f.width * 0.7, y: f.minY + f.height * 0.68)
    stroke(segment(h, l), Palette.muted, width: 0.8, dash: [3, 3])
    let arm = min(fs * 1.5, f.height * 0.16)
    for (c, turn) in [(h, -0.63), (l, 0.31)] {
      let a = CGFloat(turn)
      let x = CGPoint(x: c.x + cos(a) * arm, y: c.y + sin(a) * arm)
      let y = CGPoint(x: c.x + sin(a) * arm, y: c.y - cos(a) * arm)
      stroke(curve([x, c, y]), width: 1.6)
      dot(c, fs * 0.2)
    }
    label("Hanford, WA (H1)", CGPoint(x: f.minX + fs * 0.6, y: h.y - arm - fs * 0.5), ax: 0, ay: 1, scale: 0.85)
    label("Livingston, LA (L1)", CGPoint(x: f.maxX - fs * 0.6, y: l.y + arm + fs * 0.5), ax: 1, ay: 0, scale: 0.85)
    label("10 ms", CGPoint(x: (h.x + l.x) / 2 + fs * 0.5, y: (h.y + l.y) / 2 - fs * 0.3), ax: 0, ay: 1, color: Palette.quiet, scale: 0.85)
  }

  /// Inset (b): each detector's noise as an amplitude spectral density in strain, near the time of the
  /// signal, with its calibration lines, the suspension fibres' 500 Hz modes, and the mains' harmonics.
  private func ligoNoise(_ r: CGRect) {
    let p = Plot(box: box(r, left: 4.8), x: (20, 2000), y: (1e-24, 1e-20), logX: true, logY: true)
    let b = p.box
    let lines: [(Double, Double)] = [
      (35.9, 25), (36.7, 18), (37.3, 22), (60, 12), (120, 5), (180, 3), (331.9, 20), (500, 40), (1000, 18), (1080, 25), (1500, 6),
    ]
    func asd(_ f: Double, l1: Bool) -> Double {
      let base = 5.5e-24 * sqrt(40 * pow(50 / f, 8) + 1 + pow(f / 160, 2)) * (l1 ? 0.85 : 1)
      let spikes = lines.reduce(0.0) { s, l in s + l.1 * (l1 ? 0.7 : 1) * exp(-pow((f - l.0) / (l.0 * 0.003), 2)) }
      return base * (1 + spikes)
    }
    var freqs: [Double] = (0...400).map { 20 * pow(100, Double($0) / 400) }
    for (f0, _) in lines { freqs += [f0 * 0.994, f0 * 0.997, f0, f0 * 1.003, f0 * 1.006] }
    freqs.sort()
    clip(b) {
      stroke(curve(freqs.map { p.at($0, asd($0, l1: true)) }), Palette.muted, width: 0.9)
      stroke(curve(freqs.map { p.at($0, asd($0, l1: false)) }), width: 0.9)
    }
    key(CGPoint(x: b.maxX - fs * 4.6, y: b.minY + fs * 0.9), "H1")
    key(CGPoint(x: b.maxX - fs * 4.6, y: b.minY + fs * 2.1), "L1", color: Palette.muted)
    label("(b)", CGPoint(x: b.minX + fs * 0.5, y: b.minY + fs * 0.4), ax: 0, ay: 0)
    var xt: [(Double, String?)] = []
    for d in [10.0, 100, 1000] {
      for k in 1...9 where d * Double(k) >= 20 && d * Double(k) <= 2000 { xt.append((d * Double(k), k == 1 ? decade(Int(log10(d))) : nil)) }
    }
    axes(p, x: xt, y: (-24 ... -20).map { (pow(10, Double($0)), decade($0)) }, xTitle: "Frequency (Hz)", yTitle: "Strain noise (1/√Hz)")
  }

  // Fig. 4 ──────────────────────────────────────────────────────────────

  /// One search's histogram: candidate events and the mean background per bin, against the detection
  /// statistic, with each value's significance along the top.
  private func searchPanel(_ r: CGRect, coalescence: Bool) {
    let x = coalescence ? (lo: 8.0, hi: 24.6) : (lo: 8.0, hi: 22.0)
    let y = coalescence ? (lo: -4, hi: 3) : (lo: -2, hi: 3)
    var b = box(r, left: 4.4)
    b = CGRect(x: b.minX, y: b.minY + fs * 1.5, width: b.width, height: b.height - fs * 1.5)
    let p = Plot(box: b, x: x, y: (pow(10, Double(y.lo)), pow(10, Double(y.hi))), logY: true)
    let bin = 0.4
    let event = coalescence ? 23.6 : 20.0
    // The search's background (solid) and the other one drawn with it (dashed): for the generic search,
    // the classes C2 + C3 together; for the coalescence search, the background without GW150914's chance
    // coincidences, whose tail runs on under the solid line.
    func main(_ v: Double) -> Double { coalescence ? 300 * exp(-(v - 8) / 0.55) : 40 * exp(-(v - 8) / 0.9) }
    func solid(_ v: Double) -> Double { coalescence && v < 23.2 ? main(v) + 0.02 * exp(-(v - 8) / 4.5) : main(v) }
    func dashed(_ v: Double) -> Double { coalescence ? main(v) : 120 * exp(-(v - 8) / 1.4) }
    let bins = Array(stride(from: x.lo, to: x.hi, by: bin))
    func steps(_ m: (Double) -> Double) -> [CGPoint] {
      bins.flatMap { a -> [CGPoint] in
        let h = max(m(a + bin / 2), 1e-12)
        return [p.at(a, h), p.at(a + bin, h)]
      }
    }
    clip(b) {
      stroke(curve(steps(dashed)), width: 1.1, dash: [5, 3])
      stroke(curve(steps(solid)), width: 1.1)
    }
    // Candidates, about as many in each bin as the background expects.
    func found(_ m: (Double) -> Double, seed: Double) -> [(Double, Double)] {
      bins.enumerated().compactMap { k, a in
        let n = (m(a + bin / 2) * (0.75 + 0.5 * frac(sin(Double(k) * 12.9898 + seed) * 43758.5453))).rounded()
        return n >= 1 ? (a + bin / 2, n) : nil
      }
    }
    for (v, n) in found(main, seed: 1) { dot(p.at(v, n), fs * 0.24) }
    if !coalescence { for (v, n) in found(dashed, seed: 2) { dot(p.at(v + bin * 0.3, n), fs * 0.26, filled: false) } }
    let gw = p.at(event, 1)
    if !coalescence { dot(gw, fs * 0.42, filled: false) }
    dot(gw, fs * 0.26)
    label("GW150914", CGPoint(x: gw.x - fs * 0.7, y: gw.y), ax: 1, scale: 0.85)
    // Significance along the top.
    for s in 1...(coalescence ? 5 : 4) {
      let at = p.px(x.lo + (event - x.lo) * Double(s) / (coalescence ? 5.1 : 4.6))
      stroke(segment(CGPoint(x: at, y: b.minY), CGPoint(x: at, y: b.minY - fs * 0.4)), width: 0.7)
      label("\(s)σ", CGPoint(x: at, y: b.minY - fs * 0.5), ay: 1, scale: 0.85)
    }
    // A key where there's room for one clear of the data; the caption says the rest.
    if b.width > fs * 26 {
      let lx = b.maxX - fs * (coalescence ? 16.5 : 12.5)
      let names: [(String, [CGFloat], Bool?, Bool)] = coalescence
        ? [("Search result", [], true, false), ("Search background", [], nil, true), ("Background excluding GW150914", [5, 3], nil, true)]
        : [("Search result", [], true, false), ("Search background", [], nil, true), ("Search result C2+C3", [], false, false), ("Background C2+C3", [5, 3], nil, true)]
      for (k, (name, dash, filled, line)) in names.enumerated() {
        key(CGPoint(x: lx, y: b.minY + fs * (0.9 + 1.2 * CGFloat(k))), name, dash: dash, dot: filled, line: line)
      }
    }
    let every = b.height / CGFloat(y.hi - y.lo) < fs * 1.3 ? 2 : 1
    axes(
      p, x: ticks(x.lo, x.hi, 2).map { ($0, Int($0) % 4 == 0 ? tickText($0, 0) : nil) },
      y: (y.lo...y.hi).map { (pow(10, Double($0)), ($0 - y.lo) % every == 0 ? decade($0) : nil) },
      xTitle: coalescence ? "Detection statistic *ρ̂*_{c}" : "Detection statistic *η*_{c}", yTitle: "Number of events")
  }

  // ─── Fig.: Schwarzschild radius ────────────────────────────────────────

  private func radius(_ r: CGRect) {
    let p = Plot(box: box(r), x: (1e-1, 1e11), y: (1e-1, 1e12), logX: true, logY: true)
    let b = p.box
    // Familiar lengths, for scale.
    for (v, name) in [(6.96e5, "*R*_{⊙}"), (1.496e8, "1 au")] {
      let y = p.py(v)
      stroke(segment(CGPoint(x: b.minX, y: y), CGPoint(x: b.maxX, y: y)), Palette.muted, width: 0.8, dash: [0.1, 3])
      label(name, CGPoint(x: b.minX + fs * 0.8, y: y - 1), ax: 0, ay: 1, color: Palette.quiet)
    }
    clip(b) { stroke(segment(p.at(1e-1, 0.295), p.at(1e11, 2.95e11)), width: 1.4) }
    // (mass in Suns, hollow, label to the lower right rather than upper left)
    let objects: [(String, Double, Bool, Bool)] = [
      ("Sun", 1, true, true), ("Cyg X-1", 21.2, false, false), ("GW150914", 62, false, true),
      ("Sgr A\\*", 4.3e6, false, false), ("M87\\*", 6.5e9, false, false),
    ]
    for (name, m, hollow, lower) in objects {
      let q = p.at(m, 2.95 * m)
      dot(q, fs * 0.3, filled: !hollow)
      if lower {
        label(name, CGPoint(x: q.x + fs * 0.6, y: q.y + fs * 0.2), ax: 0, ay: 0)
      } else {
        label(name, CGPoint(x: q.x - fs * 0.6, y: q.y - fs * 0.2), ax: 1, ay: 1)
      }
    }
    axes(
      p,
      x: (-1...11).map { (pow(10, Double($0)), $0 % 2 == 0 ? "10^{\($0)}" : nil) },
      y: (-1...12).map { (pow(10, Double($0)), $0 % 3 == 0 ? "10^{\($0)}" : nil) },
      xTitle: "*M* / *M*_{⊙}", yTitle: "*r*_{s}  (km)")
  }

  // ─── Fig.: the star before collapse ────────────────────────────────────

  private func star(_ r: CGRect) {
    let R = min(r.height * 0.46, r.width * 0.3)
    let radii: [CGFloat] = [1, 0.82, 0.64, 0.48, 0.33, 0.18]
    let shades: [CGFloat] = [0.05, 0.1, 0.17, 0.26, 0.38, 0.62]
    let names = ["H envelope", "He", "C + O", "O + Ne + Mg", "Si + S", "Fe core  (→ 1.4 *M*_{⊙})"]
    // Where each leader leaves its shell: lower down for each shell further in, so no two leaders cross.
    let angles: [CGFloat] = [-0.6, -0.35, -0.15, 0.1, 0.35, 1.4]
    let widest = names.map { rich($0, size: fs).size().width }.max() ?? 0
    let total = 2 * R + fs * 2.2 + widest
    let c = CGPoint(x: r.minX + max(fs * 0.8, (r.width - total) / 2) + R, y: r.midY)
    for (i, k) in radii.enumerated() {
      let s = R * k
      let shell = UIBezierPath(ovalIn: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s))
      Palette.mix(Palette.ink, shades[i], over: Palette.page, .current).setFill()
      shell.fill()
      stroke(shell, width: 0.6)
    }
    let labelX = c.x + R + fs * 2.2
    for i in names.indices {
      let mid = i == names.count - 1 ? R * radii[i] * 0.65 : R * (radii[i] + radii[i + 1]) / 2
      let t = CGFloat(i) / CGFloat(names.count - 1)
      let from = CGPoint(x: c.x + mid * cos(angles[i]), y: c.y + mid * sin(angles[i]))
      let y = r.minY + r.height * (0.1 + 0.8 * t)
      stroke(segment(from, CGPoint(x: labelX - fs * 0.4, y: y)), width: 0.6)
      dot(from, 1.6)
      label(names[i], CGPoint(x: labelX, y: y), ax: 0)
    }
    label("not to scale", CGPoint(x: r.minX, y: r.maxY), ax: 0, ay: 1, color: Palette.muted, scale: 0.85)
  }

  // ─── Fig.: light cones ─────────────────────────────────────────────────

  private func cones(_ r: CGRect) {
    let b = box(r, left: 2.6)
    // Equal scales on both axes, so light moving inward runs at 45°.
    let top = 3 * Double(b.height / b.width)
    let p = Plot(box: b, x: (0, 3), y: (0, top))
    clip(b) {
      // Ingoing light: t* + r constant.
      for k in stride(from: 0.0, through: top + 3, by: 0.3) {
        stroke(segment(p.at(0, k), p.at(3, k - 3)), Palette.line, width: 0.6)
      }
      // Outgoing light: t* = r + 2 ln|r − 1| + constant, peeling off the horizon outside and falling in inside.
      for k in stride(from: -3.0, through: top + 2, by: 0.45) {
        for inside in [true, false] {
          let pts = stride(from: -7.0, through: inside ? 0 : log(2.2), by: 0.05).map { u -> CGPoint in
            let rr = inside ? 1 - exp(u) : 1 + exp(u)
            return p.at(rr, rr + 2 * log(abs(rr - 1)) + k)
          }
          stroke(curve(pts), Palette.muted, width: 0.7)
        }
      }
      stroke(segment(p.at(1, 0), p.at(1, top)), width: 1.1, dash: [5, 4])
      // The singularity, drawn as a zigzag.
      let zig = UIBezierPath()
      var y = b.maxY
      var flip = false
      zig.move(to: CGPoint(x: b.minX + 1, y: y))
      while y > b.minY {
        y -= fs * 0.45
        flip.toggle()
        zig.addLine(to: CGPoint(x: b.minX + (flip ? fs * 0.45 : 1), y: y))
      }
      stroke(zig, width: 1.1)
    }
    let length = b.height * 0.16
    for (rr, f) in [(0.42, 0.66), (0.74, 0.3), (1.0, 0.68), (1.4, 0.3), (2.05, 0.64), (2.65, 0.28)] {
      let apex = p.at(rr, f * top)
      // Screen directions of the two rays: inward at 45°, outward tipping with r.
      let s = (rr - 1) / (rr + 1)
      let out = CGPoint(x: s, y: -1)
      let inn = CGPoint(x: -1, y: -1)
      func reach(_ d: CGPoint) -> CGPoint {
        let n = sqrt(d.x * d.x + d.y * d.y)
        return CGPoint(x: apex.x + d.x / n * length, y: apex.y + d.y / n * length)
      }
      let a = reach(out)
      let c = reach(inn)
      let wedge = UIBezierPath()
      wedge.move(to: apex)
      wedge.addLine(to: a)
      wedge.addQuadCurve(to: c, controlPoint: reach(CGPoint(x: (out.x + inn.x) / 2, y: -1)).applying(.init(translationX: 0, y: -length * 0.08)))
      wedge.close()
      Palette.mix(Palette.ink, 0.16, over: Palette.page, .current).setFill()
      wedge.fill()
      stroke(segment(apex, a), width: 1.2)
      stroke(segment(apex, c), width: 1.2)
      dot(apex, 1.8)
    }
    label("*r* = *r*_{s}", CGPoint(x: p.px(1) + fs * 0.4, y: b.minY + fs * 0.3), ax: 0, ay: 0)
    label("*r* = 0", CGPoint(x: b.minX + fs * 0.9, y: b.minY + fs * 0.3), ax: 0, ay: 0)
    axes(p, x: (0...3).map { (Double($0), "\($0)") }, y: [], xTitle: "*r* / *r*_{s}", yTitle: "*t*\\*")
  }

  // ─── Fig.: clocks and redshift ─────────────────────────────────────────

  private func clocks(_ r: CGRect) {
    let p = Plot(box: box(r, left: 3.8), x: (1, 8), y: (0, 3))
    let b = p.box
    clip(b) {
      stroke(segment(p.at(1, 1), p.at(8, 1)), Palette.muted, width: 0.8, dash: [0.1, 3])
      for x in [1.5, 3] {
        stroke(segment(p.at(x, 0), p.at(x, 3)), Palette.muted, width: 0.8, dash: [0.1, 3])
      }
      let us = stride(from: 0.0, through: 1, by: 1.0 / 400)
      stroke(curve(us.map { u in let x = 1 + 7 * u * u; return p.at(x, sqrt(1 - 1 / x)) }), width: 1.4)
      stroke(curve(us.map { u in let x = 1.09 + 6.91 * u * u; return p.at(x, 1 / sqrt(1 - 1 / x)) }), width: 1.4, dash: [6, 4])
    }
    for (x, name) in [(1.5, "photon sphere"), (3.0, "ISCO")] {
      let w = rich(name, size: fs * 0.85).size().width
      upright(name, CGPoint(x: p.px(x) + fs * 0.6, y: b.minY + fs * 0.6 + w / 2), color: Palette.quiet, scale: 0.85)
    }
    // Legend, in the empty top right.
    let lx = b.maxX - fs * 7.5
    for (i, (name, dash)) in [("d*τ*/d*t*", [CGFloat]()), ("1 + *z*", [6, 4])].enumerated() {
      let y = b.minY + fs * (1.2 + 1.5 * CGFloat(i))
      stroke(segment(CGPoint(x: lx, y: y), CGPoint(x: lx + fs * 2.4, y: y)), width: 1.4, dash: dash)
      label(name, CGPoint(x: lx + fs * 3, y: y), ax: 0)
    }
    axes(
      p, x: (1...8).map { (Double($0), "\($0)") }, y: ticks(0, 3, 0.5).map { ($0, $0 == $0.rounded() ? "\(Int($0))" : nil) },
      xTitle: "*r* / *r*_{s}", yTitle: nil)
  }

  // ─── Fig.: the evidence ────────────────────────────────────────────────

  /// The star S2 about Sgr A*, at the focus of its ellipse, with an equal scale on both axes.
  private func orbit(_ r: CGRect) {
    let a = 0.125
    let e = 0.884
    let bb = a * sqrt(1 - e * e)
    let tilt = -105 * Double.pi / 180
    func at(_ E: Double) -> (Double, Double) {
      let x = a * (cos(E) - e)
      let y = bb * sin(E)
      return (x * cos(tilt) - y * sin(tilt), x * sin(tilt) + y * cos(tilt))
    }
    let ring = stride(from: 0.0, through: 2 * .pi, by: .pi / 180).map(at)
    let xs = ring.map(\.0) + [0]
    let ys = ring.map(\.1) + [0]
    let b = box(r, left: 4.2)
    var x = (lo: xs.min()!, hi: xs.max()!)
    var y = (lo: ys.min()!, hi: ys.max()!)
    let margin = 0.12 * (y.hi - y.lo)
    x = (x.lo - margin, x.hi + margin)
    y = (y.lo - margin, y.hi + margin)
    let scale = min(Double(b.width) / (x.hi - x.lo), Double(b.height) / (y.hi - y.lo))
    let cx = (x.lo + x.hi) / 2
    let cy = (y.lo + y.hi) / 2
    let hw = Double(b.width) / scale / 2
    let hh = Double(b.height) / scale / 2
    let p = Plot(box: b, x: (cx - hw, cx + hw), y: (cy - hh, cy + hh))
    clip(b) {
      stroke(curve(ring.map { p.at($0.0, $0.1) }), width: 1)
      // Epochs evenly spaced in time crowd toward the far end of the orbit, as observations do.
      let n = 26
      for k in 0..<n {
        let m = 2 * Double.pi * (Double(k) + 0.5) / Double(n)
        var E = m
        for _ in 0..<12 { E -= (E - e * sin(E) - m) / (1 - e * cos(E)) }
        var (px, py) = at(E)
        px += 0.0022 * sin(Double(k) * 12.9898)
        py += 0.0022 * sin(Double(k) * 78.233)
        let q = p.at(px, py)
        let err = CGFloat(0.004 * scale)
        stroke(segment(CGPoint(x: q.x - err, y: q.y), CGPoint(x: q.x + err, y: q.y)), Palette.quiet, width: 0.6)
        stroke(segment(CGPoint(x: q.x, y: q.y - err), CGPoint(x: q.x, y: q.y + err)), Palette.quiet, width: 0.6)
        dot(q, 2.2)
      }
      let o = p.at(0, 0)
      let s = fs * 0.5
      stroke(segment(CGPoint(x: o.x - s, y: o.y), CGPoint(x: o.x + s, y: o.y)), width: 1.3)
      stroke(segment(CGPoint(x: o.x, y: o.y - s), CGPoint(x: o.x, y: o.y + s)), width: 1.3)
      label("Sgr A\\*", CGPoint(x: o.x - fs * 0.9, y: o.y), ax: 1, ay: 0.5)
      label("S2", p.at(at(.pi * 0.8).0, at(.pi * 0.8).1).applying(.init(translationX: fs * 0.9, y: 0)), ax: 0)
    }
    label("(a)", CGPoint(x: b.minX + fs * 0.5, y: b.minY + fs * 0.4), ax: 0, ay: 0)
    let step = 0.05
    axes(
      p, x: ticks(p.x.lo, p.x.hi, step).map { ($0, tickText($0, 2)) }, y: ticks(p.y.lo, p.y.hi, step).map { ($0, tickText($0, 2)) },
      xTitle: "Δ*α*  (arcsec)", yTitle: "Δ*δ*  (arcsec)")
  }

  /// Strain from two black holes spiraling together: frequency and amplitude climb, then the remnant rings down.
  private func chirp(_ r: CGRect) {
    let p = Plot(box: box(r, left: 3.6), x: (-0.2, 0.04), y: (-1.3, 1.3))
    let b = p.box
    var phase = 0.0
    var pts: [CGPoint] = []
    let n = 2400
    let dt = 0.24 / Double(n)
    for i in 0...n {
      let t = -0.2 + Double(i) * dt
      let f: Double
      let amp: Double
      if t < 0 {
        f = 35 * pow(max(-t, 0.0035) / 0.2, -0.375)
        amp = pow(f / 160, 2.0 / 3)
      } else {
        f = 250
        amp = exp(-t / 0.0045)
      }
      phase += 2 * .pi * f * dt
      pts.append(p.at(t, amp * cos(phase)))
    }
    clip(b) {
      stroke(segment(p.at(-0.2, 0), p.at(0.04, 0)), Palette.line, width: 0.6)
      stroke(curve(pts), width: 0.9)
    }
    label("inspiral", p.at(-0.13, 0.75), color: Palette.quiet)
    label("merger", p.at(0, 1.1).applying(.init(translationX: -fs * 0.2, y: 0)), ax: 1, color: Palette.quiet)
    label("ringdown", p.at(0.04, -1.12).applying(.init(translationX: -fs * 0.3, y: 0)), ax: 1, color: Palette.quiet)
    label("(b)", CGPoint(x: b.minX + fs * 0.5, y: b.minY + fs * 0.4), ax: 0, ay: 0)
    axes(
      p, x: ticks(-0.2, 0, 0.05).map { ($0, tickText($0, 2)) }, y: ticks(-1, 1, 0.5).map { ($0, $0 == $0.rounded() ? tickText($0, 0) : nil) },
      xTitle: "*t* − *t*_{c}  (s)", yTitle: "*h*  (10^{−21})")
  }

  // ─── Fig.: the waggle dance ────────────────────────────────────────────

  /// An arc from straight up, turning clockwise by `angle`, about `c`.
  private func angleMark(_ c: CGPoint, _ radius: CGFloat, _ angle: CGFloat, _ name: String) {
    let arc = UIBezierPath(arcCenter: c, radius: radius, startAngle: -.pi / 2, endAngle: -.pi / 2 + angle, clockwise: true)
    stroke(arc, width: 0.8)
    let mid = -.pi / 2 + angle / 2
    label(name, CGPoint(x: c.x + cos(mid) * radius * 1.45, y: c.y + sin(mid) * radius * 1.45))
  }

  /// On the comb, the straight run at θ from vertical and the loops back either side;
  /// in the field, the site at θ from the sun.
  private func waggle(_ r: CGRect) {
    let theta: CGFloat = 40 * .pi / 180
    let d = CGPoint(x: sin(theta), y: -cos(theta))
    let n = CGPoint(x: cos(theta), y: sin(theta))
    let half = r.width / 2
    // The comb.
    let L = min(r.height * 0.42, half * 0.62)
    let foot = r.maxY - fs * 2.6
    let c = CGPoint(x: r.minX + half * 0.5, y: (r.minY + fs * 2.4 + L * 0.95 + foot - L * 0.6) / 2)
    let up = CGPoint(x: c.x, y: c.y - L * 0.95)
    stroke(segment(CGPoint(x: c.x, y: c.y + L * 0.2), up), Palette.muted, width: 0.8, dash: [3, 3])
    arrowhead(up, toward: CGPoint(x: 0, y: -1), Palette.muted)
    label("up", CGPoint(x: up.x, y: up.y - fs * 0.35), ay: 1, color: Palette.quiet)
    let start = CGPoint(x: c.x - d.x * L * 0.45, y: c.y - d.y * L * 0.45)
    let end = CGPoint(x: c.x + d.x * L * 0.45, y: c.y + d.y * L * 0.45)
    for side: CGFloat in [1, -1] {
      let loop = UIBezierPath()
      loop.move(to: end)
      loop.addCurve(
        to: start,
        controlPoint1: CGPoint(x: end.x + side * n.x * L * 0.8 + d.x * L * 0.25, y: end.y + side * n.y * L * 0.8 + d.y * L * 0.25),
        controlPoint2: CGPoint(x: start.x + side * n.x * L * 0.8 - d.x * L * 0.25, y: start.y + side * n.y * L * 0.8 - d.y * L * 0.25))
      stroke(loop, Palette.quiet, width: 0.8, dash: [4, 3])
    }
    let wiggle = stride(from: 0.0, through: 1.0, by: 1.0 / 120).map { u -> CGPoint in
      let w = fs * 0.28 * CGFloat(sin(u * 2 * .pi * 7)) * CGFloat(min(1, min(u, 1 - u) * 8))
      let along = CGFloat(u)
      return CGPoint(x: start.x + (end.x - start.x) * along + n.x * w, y: start.y + (end.y - start.y) * along + n.y * w)
    }
    stroke(curve(wiggle), width: 1.3)
    arrowhead(CGPoint(x: end.x + d.x * fs * 0.5, y: end.y + d.y * fs * 0.5), toward: d)
    angleMark(c, L * 0.32, theta, "*θ*")
    label("comb", CGPoint(x: c.x, y: foot + fs * 0.7), ay: 0, color: Palette.quiet)

    // The field, seen from above.
    let hive = CGPoint(x: r.minX + half * 1.36, y: foot)
    let reach = min(r.height - fs * 4.6, half * 0.8)
    let sun = CGPoint(x: hive.x, y: hive.y - reach)
    stroke(segment(hive, CGPoint(x: sun.x, y: sun.y + fs * 0.9)), Palette.muted, width: 0.8, dash: [3, 3])
    let disc = UIBezierPath(ovalIn: CGRect(x: sun.x - fs * 0.45, y: sun.y - fs * 0.45, width: fs * 0.9, height: fs * 0.9))
    stroke(disc, width: 0.9)
    for k in 0..<8 {
      let a = CGFloat(k) * .pi / 4
      stroke(segment(CGPoint(x: sun.x + cos(a) * fs * 0.65, y: sun.y + sin(a) * fs * 0.65), CGPoint(x: sun.x + cos(a) * fs * 0.9, y: sun.y + sin(a) * fs * 0.9)), width: 0.8)
    }
    label("sun", CGPoint(x: sun.x + fs * 1.2, y: sun.y), ax: 0, color: Palette.quiet)
    let site = CGPoint(x: hive.x + d.x * reach * 0.9, y: hive.y + d.y * reach * 0.9)
    stroke(segment(hive, CGPoint(x: site.x - d.x * fs * 0.6, y: site.y - d.y * fs * 0.6)), width: 1.2)
    arrowhead(CGPoint(x: site.x - d.x * fs * 0.4, y: site.y - d.y * fs * 0.4), toward: d)
    dot(site, fs * 0.32, filled: false)
    label("site", CGPoint(x: site.x + fs * 0.7, y: site.y), ax: 0, color: Palette.quiet)
    let box = UIBezierPath(rect: CGRect(x: hive.x - fs * 0.35, y: hive.y - fs * 0.35, width: fs * 0.7, height: fs * 0.7))
    resolved(Palette.ink).setFill()
    box.fill()
    label("swarm", CGPoint(x: hive.x, y: hive.y + fs * 0.7), ay: 0, color: Palette.quiet)
    angleMark(hive, reach * 0.28, theta, "*θ*")
    label("(a)", CGPoint(x: r.minX + fs * 0.2, y: r.minY + fs * 0.2), ax: 0, ay: 0)
  }

  /// Circuits danced on each return to the swarm, for an excellent site and a mediocre one.
  private func decay(_ r: CGRect) {
    let p = Plot(box: box(r, left: 3.8), x: (0.5, 7.5), y: (0, 100))
    let b = p.box
    let excellent = (1...7).map { (Double($0), 90 - 15 * Double($0 - 1)) }
    let mediocre = (1...3).map { (Double($0), 30 - 15 * Double($0 - 1)) }
    clip(b) {
      stroke(curve(excellent.map { p.at($0.0, $0.1) }), width: 1.2)
      stroke(curve(mediocre.map { p.at($0.0, $0.1) }), width: 1.2, dash: [5, 3])
    }
    for (x, y) in excellent { dot(p.at(x, y), fs * 0.28) }
    for (x, y) in mediocre { dot(p.at(x, y), fs * 0.28, filled: false) }
    // Legend, in the empty top right.
    let lx = b.maxX - fs * 8
    for (i, (name, filled)) in [("excellent", true), ("mediocre", false)].enumerated() {
      let y = b.minY + fs * (1.2 + 1.5 * CGFloat(i))
      stroke(segment(CGPoint(x: lx, y: y), CGPoint(x: lx + fs * 2.4, y: y)), width: 1.2, dash: filled ? [] : [5, 3])
      dot(CGPoint(x: lx + fs * 1.2, y: y), fs * 0.28, filled: filled)
      label(name, CGPoint(x: lx + fs * 3, y: y), ax: 0)
    }
    label("(b)", CGPoint(x: b.minX + fs * 0.5, y: b.minY + fs * 0.4), ax: 0, ay: 0)
    axes(
      p, x: (1...7).map { (Double($0), "\($0)") }, y: ticks(0, 100, 20).map { ($0, tickText($0, 0)) },
      xTitle: "return trip", yTitle: "circuits per dance")
  }

  // ─── Fig.: reaching a quorum ───────────────────────────────────────────

  private func quorum(_ r: CGRect) {
    let p = Plot(box: box(r, left: 3.8), x: (0, 14), y: (0, 30))
    let b = p.box
    let lift = 12.9
    let piping = 11.9
    func a(_ t: Double) -> Double { 26 / (1 + exp(-(t - 10) / 1.6)) }
    func bb(_ t: Double) -> Double { let u = t / 6.5; return 13 * u * u * exp(2 * (1 - u)) }
    let ts = stride(from: 0.0, through: lift, by: 0.05)
    clip(b) {
      stroke(segment(p.at(0, 20), p.at(14, 20)), Palette.muted, width: 0.8, dash: [0.1, 3])
      for x in [piping, lift] {
        stroke(segment(p.at(x, 0), p.at(x, 30)), Palette.muted, width: 0.8, dash: [0.1, 3])
      }
      stroke(curve(ts.map { p.at($0, a($0)) }), width: 1.4)
      stroke(curve(ts.map { p.at($0, bb($0)) }), width: 1.4, dash: [6, 4])
    }
    label("quorum", p.at(0.3, 20).applying(.init(translationX: 0, y: -fs * 0.2)), ax: 0, ay: 1, color: Palette.quiet)
    for (x, name) in [(piping, "piping"), (lift, "lift-off")] {
      let w = rich(name, size: fs * 0.85).size().width
      upright(name, CGPoint(x: p.px(x) - fs * 0.6, y: b.maxY - fs * 0.6 - w / 2), color: Palette.quiet, scale: 0.85)
    }
    label("site A", p.at(10.6, a(10.6)).applying(.init(translationX: fs * 0.7, y: fs * 0.2)), ax: 0, ay: 0)
    label("site B", p.at(6.5, bb(6.5)).applying(.init(translationX: 0, y: -fs * 0.4)), ay: 1)
    axes(
      p, x: ticks(0, 14, 2).map { ($0, tickText($0, 0)) }, y: ticks(0, 30, 5).map { ($0, Int($0) % 10 == 0 ? tickText($0, 0) : nil) },
      xTitle: "time since scouting began  (h)", yTitle: "scouts at site")
  }
}
