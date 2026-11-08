import UIKit

/// A small drawing written as SVG path data on a `size` viewBox, rendered as
/// shape layers in the page's own inks so it follows light and dark. Played,
/// it draws itself on stroke by stroke, the way a pen would.
struct Sketch {
  var size: CGSize
  var marks: [Mark]

  init(_ w: CGFloat, _ h: CGFloat, _ marks: [Mark]) {
    size = CGSize(width: w, height: h)
    self.marks = marks
  }
}

enum Ink {
  case ink, quiet, faint, wash

  var color: UIColor {
    switch self {
    case .ink: Palette.ink
    case .quiet: Palette.quiet
    case .faint: Palette.faint
    case .wash: Palette.fill
    }
  }
}

enum Mark {
  /// A pen line along SVG path data.
  case stroke(String, Ink = .ink, width: CGFloat = 1.5, dash: [CGFloat]? = nil)
  /// A filled shape; fades in rather than drawing on.
  case fill(String, Ink = .wash)
  /// An italic label, `anchor` 0 left … 1 right of `at`.
  case label(String, CGPoint, anchor: CGFloat = 0.5, Ink = .quiet)
  /// Several marks that appear at once.
  case together([Mark])
}

// ─── Path data helpers ───────────────────────────────────────────────────────

/// SVG path data for an ellipse, as two arcs.
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> String {
  "M\(cx - rx),\(cy) A\(rx),\(ry) 0 1 0 \(cx + rx),\(cy) A\(rx),\(ry) 0 1 0 \(cx - rx),\(cy) Z"
}

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> String { ellipse(cx, cy, r, r) }

/// SVG path data through `points`, as straight segments.
func polyline(_ points: [CGPoint]) -> String {
  points.enumerated().map { "\($0.offset == 0 ? "M" : "L")\($0.element.x),\($0.element.y)" }.joined(separator: " ")
}

/// An arrowhead at `tip`, pointing along `angle` (radians, 0 = right).
func arrowhead(_ tip: CGPoint, _ angle: CGFloat, size s: CGFloat = 9) -> String {
  let a = angle + .pi - 0.42
  let b = angle + .pi + 0.42
  return "M\(tip.x + cos(a) * s),\(tip.y + sin(a) * s) L\(tip.x),\(tip.y) L\(tip.x + cos(b) * s),\(tip.y + sin(b) * s)"
}

// ─── Parsing SVG path data ───────────────────────────────────────────────────

/// Reads the path data subset sketches use: M L H V C S Q T A Z, absolute and relative.
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

// ─── The view ────────────────────────────────────────────────────────────────

/// Draws a `Sketch` fitted to its bounds, and draws it on when played.
final class SketchView: UIView {
  var sketch: Sketch? {
    didSet { built = nil; setNeedsLayout() }
  }
  /// Scales line widths and lettering with the drawing, a little.
  var weight: CGFloat = 1
  /// Whether the drawing's lettering is drawn; without it, only the lines and fills.
  var lettered = true {
    didSet { built = nil; setNeedsLayout() }
  }
  /// Whether the soft washes behind the lines are drawn.
  var washed = true {
    didSet { built = nil; setNeedsLayout() }
  }
  /// Whether the drawing is fitted by what it actually draws rather than by
  /// its whole canvas, so that sparse drawings fill the view as fully as dense ones.
  var trimmed = false {
    didSet { built = nil; setNeedsLayout() }
  }

  private var groups: [[CALayer]] = []
  private var built: CGSize?
  private var played = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: SketchView, _) in
      self.built = nil
      self.setNeedsLayout()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard built != bounds.size else { return }
    build()
  }

  private func build() {
    // Only the marks' own layers: a subview's (a library drawing shown in the
    // sketch's place) must stay, or its view is left without one.
    groups.joined().forEach { $0.removeFromSuperlayer() }
    groups = []
    built = bounds.size
    guard let sketch, bounds.width > 0, bounds.height > 0 else { return }
    let canvas = trimmed ? drawn(sketch.marks) ?? CGRect(origin: .zero, size: sketch.size) : CGRect(origin: .zero, size: sketch.size)
    let k = min(bounds.width / canvas.width, bounds.height / canvas.height)
    let ox = (bounds.width - canvas.width * k) / 2 - canvas.minX * k
    let oy = (bounds.height - canvas.height * k) / 2 - canvas.minY * k
    var t = CGAffineTransform(translationX: ox, y: oy).scaledBy(x: k, y: k)
    let pen = max(0.75, min(1.4, k)) * weight
    traitCollection.performAsCurrent {
      func make(_ mark: Mark) -> [CALayer] {
        switch mark {
        case let .stroke(d, ink, width, dash):
          let l = CAShapeLayer()
          l.path = SVGPath.parse(d).copy(using: &t)
          l.fillColor = nil
          l.strokeColor = ink.color.cgColor
          l.lineWidth = width * pen
          l.lineCap = .round
          l.lineJoin = .round
          l.lineDashPattern = dash?.map { NSNumber(value: Double($0 * pen)) }
          return [l]
        case let .fill(d, ink):
          guard washed || ink != .wash else { return [] }
          let l = CAShapeLayer()
          l.path = SVGPath.parse(d).copy(using: &t)
          l.fillColor = ink.color.cgColor
          l.strokeColor = nil
          return [l]
        case let .label(text, at, anchor, ink):
          guard lettered else { return [] }
          let l = CATextLayer()
          let font = Faces.serif(13 * max(0.85, min(1.25, k)) * weight, italic: true)
          let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink.color])
          let size = s.size()
          let p = at.applying(t)
          l.string = s
          l.contentsScale = window?.screen.scale ?? 2
          l.frame = CGRect(x: p.x - size.width * anchor, y: p.y - size.height / 2, width: ceil(size.width) + 2, height: ceil(size.height))
          return [l]
        case let .together(marks):
          return marks.flatMap(make)
        }
      }
      // Beneath any subviews, in the order drawn.
      var n: UInt32 = 0
      for mark in sketch.marks {
        let ls = make(mark)
        for l in ls {
          layer.insertSublayer(l, at: n)
          n += 1
        }
        groups.append(ls)
      }
    }
    if !played { hide() }
  }

  /// The area the marks that will be drawn cover, in the sketch's own units.
  private func drawn(_ marks: [Mark]) -> CGRect? {
    marks.reduce(nil as CGRect?) { area, mark in
      let r: CGRect?
      switch mark {
      case let .stroke(d, _, width, _): r = SVGPath.parse(d).boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2)
      case let .fill(d, ink): r = washed || ink != .wash ? SVGPath.parse(d).boundingBoxOfPath : nil
      case .label: r = nil  // lettering has no path to measure; trim drawings without it

      case let .together(inner): r = drawn(inner)
      }
      guard let r, !r.isNull else { return area }
      return area.map { $0.union(r) } ?? r
    }
  }

  private func hide() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for l in groups.joined() {
      if let s = l as? CAShapeLayer, s.fillColor == nil { s.strokeEnd = 0 } else { l.opacity = 0 }
    }
    CATransaction.commit()
  }

  /// Hides the drawing, ready to be played again.
  func reset() {
    played = false
    groups.joined().forEach { $0.removeAllAnimations() }
    hide()
  }

  /// Draws the sketch on, mark by mark, starting after `delay` seconds.
  func play(delay: Double = 0, pace: Double = 1) {
    layoutIfNeeded()
    played = true
    let now = CACurrentMediaTime() + delay
    let pen = CAMediaTimingFunction(controlPoints: 0.55, 0.05, 0.25, 1)
    let soft = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
    var at = 0.0
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for group in groups {
      var longest = 0.0
      for l in group {
        if let s = l as? CAShapeLayer, s.fillColor == nil {
          let length = s.path.map { Double($0.boundingBoxOfPath.width + $0.boundingBoxOfPath.height) } ?? 100
          let duration = clamp(0.3 + length / 1100, 0.35, 0.85) * pace
          let a = CABasicAnimation(keyPath: "strokeEnd")
          a.fromValue = 0
          a.toValue = 1
          a.duration = duration
          a.beginTime = now + at
          a.timingFunction = pen
          a.fillMode = .backwards
          s.strokeEnd = 1
          s.add(a, forKey: "draw")
          longest = max(longest, duration)
        } else {
          let fade = CABasicAnimation(keyPath: "opacity")
          fade.fromValue = 0
          fade.toValue = 1
          let rise = CABasicAnimation(keyPath: "transform")
          rise.fromValue = CATransform3DMakeTranslation(0, l is CATextLayer ? 5 : 0, 0)
          rise.toValue = CATransform3DIdentity
          let g = CAAnimationGroup()
          g.animations = [fade, rise]
          g.duration = 0.6 * pace
          g.beginTime = now + at
          g.timingFunction = soft
          g.fillMode = .backwards
          l.opacity = 1
          l.add(g, forKey: "fade")
          longest = max(longest, 0.5 * pace)
        }
      }
      // Each mark starts as the one before is well under way.
      at += min(longest * 0.3, 0.11) * pace
    }
    CATransaction.commit()
  }
}

// ─── Type ────────────────────────────────────────────────────────────────────

/// The faces of the topic pages.
enum Faces {
  static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
    var d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    d = d.withDesign(.serif) ?? d
    if italic { d = d.withSymbolicTraits(d.symbolicTraits.union(.traitItalic)) ?? d }
    return UIFont(descriptor: d, size: size)
  }

  static func sans(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont { .systemFont(ofSize: size, weight: weight) }

  static func text(
    _ s: String, _ font: UIFont, _ color: UIColor, leading: CGFloat = 1.25, tracking: CGFloat = 0,
    align: NSTextAlignment = .natural
  ) -> NSAttributedString {
    let ps = NSMutableParagraphStyle()
    ps.lineHeightMultiple = leading
    ps.alignment = align
    ps.hyphenationFactor = 0.3
    ps.paragraphSpacing = font.pointSize * 0.7
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps, .kern: tracking])
  }
}
