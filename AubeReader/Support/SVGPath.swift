import UIKit

/// Reads SVG path data into a `CGPath`: the commands M L H V C S Q T A Z,
/// absolute and relative.
enum SVGPath {
  static func parse(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var tokens = tokenize(d)[...]
    var cur = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?
    var cmd: Character = "M"

    func num() -> CGFloat {
      guard case let .number(v)? = tokens.first else { return 0 }
      tokens.removeFirst()
      return v
    }
    func point(_ rel: Bool) -> CGPoint {
      let x = num()
      let y = num()
      return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
    }

    while let t = tokens.first {
      if case let .command(c) = t {
        cmd = c
        tokens.removeFirst()
      } else if cmd == "Z" || cmd == "z" {
        break  // numbers after Z: malformed
      }
      let rel = cmd.isLowercase
      switch cmd.uppercased().first! {
      case "M":
        cur = point(rel)
        start = cur
        path.move(to: cur)
        cmd = rel ? "l" : "L"  // further pairs are lines
        lastControl = nil
      case "L":
        cur = point(rel)
        path.addLine(to: cur)
        lastControl = nil
      case "H":
        cur = CGPoint(x: rel ? cur.x + num() : num(), y: cur.y)
        path.addLine(to: cur)
        lastControl = nil
      case "V":
        cur = CGPoint(x: cur.x, y: rel ? cur.y + num() : num())
        path.addLine(to: cur)
        lastControl = nil
      case "C":
        let c1 = point(rel)
        let c2 = point(rel)
        let p = point(rel)
        path.addCurve(to: p, control1: c1, control2: c2)
        lastControl = c2
        cur = p
      case "S":
        let c1 = lastControl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
        let c2 = point(rel)
        let p = point(rel)
        path.addCurve(to: p, control1: c1, control2: c2)
        lastControl = c2
        cur = p
      case "Q":
        let c = point(rel)
        let p = point(rel)
        path.addQuadCurve(to: p, control: c)
        lastControl = c
        cur = p
      case "T":
        let c = lastControl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
        let p = point(rel)
        path.addQuadCurve(to: p, control: c)
        lastControl = c
        cur = p
      case "A":
        let rx = num()
        let ry = num()
        let rot = num() * .pi / 180
        let large = num() != 0
        let sweep = num() != 0
        let p = point(rel)
        arc(path, from: cur, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
        cur = p
        lastControl = nil
      case "Z":
        path.closeSubpath()
        cur = start
        lastControl = nil
      default:
        tokens.removeFirst()
      }
    }
    return path
  }

  private enum Token {
    case command(Character)
    case number(CGFloat)
  }

  private static func tokenize(_ d: String) -> [Token] {
    var out: [Token] = []
    var number = ""
    func flush() {
      if let v = Double(number) { out.append(.number(CGFloat(v))) }
      number = ""
    }
    for ch in d {
      if ch.isLetter && ch != "e" && ch != "E" {
        flush()
        out.append(.command(ch))
      } else if ch == "-" && !(number.last == "e" || number.last == "E") {
        flush()
        number = "-"
      } else if ch == "." && number.contains(".") {
        flush()
        number = "."
      } else if ch.isNumber || ch == "." || ch == "e" || ch == "E" {
        number.append(ch)
      } else {
        flush()
      }
    }
    flush()
    return out
  }

  /// An SVG elliptical arc, by way of its center parameterisation (SVG 1.1, appendix F.6).
  private static func arc(
    _ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation φ: CGFloat,
    large: Bool, sweep: Bool
  ) {
    var rx = abs(rx)
    var ry = abs(ry)
    guard rx > 0, ry > 0, p0 != p1 else {
      path.addLine(to: p1)
      return
    }
    let dx = (p0.x - p1.x) / 2
    let dy = (p0.y - p1.y) / 2
    let x1 = cos(φ) * dx + sin(φ) * dy
    let y1 = -sin(φ) * dx + cos(φ) * dy
    let λ = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if λ > 1 {
      rx *= sqrt(λ)
      ry *= sqrt(λ)
    }
    let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var k = sqrt(max(0, num / den))
    if large == sweep { k = -k }
    let cx1 = k * rx * y1 / ry
    let cy1 = -k * ry * x1 / rx
    let cx = cos(φ) * cx1 - sin(φ) * cy1 + (p0.x + p1.x) / 2
    let cy = sin(φ) * cx1 + cos(φ) * cy1 + (p0.y + p1.y) / 2
    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
      atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
    let θ1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var Δθ = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep && Δθ > 0 { Δθ -= 2 * .pi }
    if sweep && Δθ < 0 { Δθ += 2 * .pi }
    // Unit circle arc, scaled into the ellipse and turned.
    let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: φ).scaledBy(x: rx, y: ry)
    // Starts where the path already is, so it continues the subpath.
    path.addArc(center: .zero, radius: 1, startAngle: θ1, endAngle: θ1 + Δθ, clockwise: Δθ < 0, transform: t)
  }
}
