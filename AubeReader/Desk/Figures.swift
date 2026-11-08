import UIKit

/// The papers' figures. Drawn rather than pictured, in the page's own inks, so
/// they follow light and dark and stay sharp at any zoom of the desk.
enum Figure {
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
  var wide: Bool { self == .evidence || self == .dance }
}

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
