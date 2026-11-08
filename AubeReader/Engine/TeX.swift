import CoreText
import UIKit

/// One stroke of a typeset word: a run of text, or a rule (a square root's bar),
/// placed relative to the word's left edge and baseline.
enum Piece {
  case text(CTLine, x: CGFloat, rise: CGFloat)
  case rule(x: CGFloat, width: CGFloat, rise: CGFloat, thickness: CGFloat)
  /// The faint capsule a note's mark sits in, to show it can be tapped. `rise` is to its middle.
  case halo(x: CGFloat, width: CGFloat, rise: CGFloat, height: CGFloat)
}

/// Draws its runs in the color of the graphics context, so one typeset word
/// can be painted in any color (light or dark mode) without being typeset again.
private let inkFromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)

func makeLine(_ text: String, _ font: UIFont) -> CTLine {
  CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, inkFromContext: true]))
}

func lineWidth(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }

/// Draws typeset pieces in the context's fill color, starting at `x`, with the baseline at `baseline`.
func drawPieces(_ pieces: [Piece], in ctx: CGContext, x: CGFloat, baseline: CGFloat) {
  for piece in pieces {
    switch piece {
    case let .text(line, px, rise):
      ctx.saveGState()
      ctx.textMatrix = .identity
      ctx.translateBy(x: x + px, y: baseline - rise)
      ctx.scaleBy(x: 1, y: -1)
      ctx.textPosition = .zero
      CTLineDraw(line, ctx)
      ctx.restoreGState()
    case let .rule(px, width, rise, thickness):
      ctx.fill(CGRect(x: x + px, y: baseline - rise - thickness / 2, width: width, height: thickness))
    case let .halo(px, width, rise, height):
      ctx.saveGState()
      ctx.setAlpha(Halo.strength)
      ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x + px, y: baseline - rise - height / 2, width: width, height: height), cornerRadius: height / 2).cgPath)
      ctx.fillPath()
      ctx.restoreGState()
    }
  }
}

/// How a note's mark is drawn: a number at about the size of the words, in the app's
/// own type whatever the document is set in, in a faint circle. It looks the same
/// wherever it is, in every look, and it's what opens into the note (see `NoteTip`).
enum Halo {
  /// How much of the ink the circle is filled with.
  static let strength: CGFloat = 0.1

  /// How tall a mark is among words of size `body`.
  static func diameter(_ body: CGFloat) -> CGFloat { (body * 1.15).rounded() }

  /// The face of the number in a mark that tall.
  static func font(_ diameter: CGFloat) -> UIFont { .systemFont(ofSize: diameter * 0.7, weight: .medium) }

  /// How wide a mark runs: a circle for a number or a symbol, drawn out for a longer one.
  static func width(_ label: String, _ diameter: CGFloat) -> CGFloat {
    max(diameter, ceil((label as NSString).size(withAttributes: [.font: font(diameter)]).width + diameter * 0.45))
  }

  /// A mark as a picture, for where it isn't set among typeset words.
  static func image(_ label: String, diameter: CGFloat, ink: UIColor, scale: CGFloat) -> UIImage {
    let size = CGSize(width: width(label, diameter), height: diameter)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      ink.withAlphaComponent(strength).setFill()
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: diameter / 2).fill()
      let attrs: [NSAttributedString.Key: Any] = [.font: font(diameter), .foregroundColor: ink]
      let text = (label as NSString).size(withAttributes: attrs)
      (label as NSString).draw(at: CGPoint(x: (size.width - text.width) / 2, y: (diameter - text.height) / 2), withAttributes: attrs)
    }
  }
}

/// Typesets the small piece of inline TeX the texts use: italic variables,
/// upright numbers and names, sub- and superscripts, Greek, a few operators,
/// square roots with a bar, and inline fractions (stacked, when `display`).
/// Set in the system serif, as formulas are, beside the sans-serif text, or in
/// `family` beside serif text.
final class TeX {
  private(set) var pieces: [Piece] = []
  private(set) var x: CGFloat = 0
  private let size: CGFloat
  private let family: String?
  private let display: Bool
  private let chars: [Character]
  private var i = 0
  /// Whether the last thing set was an operand, so a following minus is subtraction, not a sign.
  private var lastOrd = false

  init(_ tex: String, size: CGFloat, family: String? = nil, display: Bool = false) {
    self.size = size
    self.family = family
    self.display = display
    self.chars = Array(tex)
    var upright = false
    list(level: 0, rise: 0, upright: &upright, closing: false)
  }

  // ─── Fonts ──────────────────────────────────────────────────────────────

  private static var fonts: [String: UIFont] = [:]

  private func sizeAt(_ level: Int) -> CGFloat { size * 1.08 * [1, 0.7, 0.56][min(level, 2)] }

  private func font(_ level: Int, italic: Bool) -> UIFont {
    let s = sizeAt(level)
    let key = "\(family ?? "")\(s)\(italic)"
    if let f = TeX.fonts[key] { return f }
    var d = family.map { UIFontDescriptor(fontAttributes: [.family: $0]) } ?? UIFont.systemFont(ofSize: s).fontDescriptor
    if family == nil { d = d.withDesign(.serif) ?? d }
    if italic { d = d.withSymbolicTraits(.traitItalic) ?? d }
    let f = UIFont(descriptor: d, size: s)
    TeX.fonts[key] = f
    return f
  }

  // ─── Setting ────────────────────────────────────────────────────────────

  private func put(_ s: String, _ level: Int, _ rise: CGFloat, italic: Bool) {
    let line = makeLine(s, font(level, italic: italic))
    pieces.append(.text(line, x: x, rise: rise))
    x += lineWidth(line)
  }

  private func space(_ em: CGFloat, _ level: Int) { x += em * sizeAt(level) }

  /// A binary operator gets medium space around it, a relation thick space;
  /// a sign (a minus with nothing before it) gets none.
  private func op(_ s: String, _ level: Int, _ rise: CGFloat, relation: Bool) {
    let gap: CGFloat = level > 0 ? 0 : relation ? 0.278 : 0.222
    if !relation && !lastOrd {
      put(s, level, rise, italic: false)
    } else {
      space(gap, level)
      put(s, level, rise, italic: false)
      space(gap, level)
    }
    lastOrd = false
  }

  // ─── Parsing ────────────────────────────────────────────────────────────

  private var peek: Character? { i < chars.count ? chars[i] : nil }

  private func list(level: Int, rise: CGFloat, upright: inout Bool, closing: Bool) {
    while let c = peek {
      i += 1
      if c == "}" {
        if closing { return }
        continue
      }
      atom(c, level: level, rise: rise, upright: &upright)
    }
  }

  private func atom(_ c: Character, level: Int, rise: CGFloat, upright: inout Bool) {
    switch c {
    case "{":
      var inner = upright
      list(level: level, rise: rise, upright: &inner, closing: true)
      lastOrd = true
    case "^", "_":
      let parent = sizeAt(level)
      let r = c == "^" ? rise + parent * 0.4 : rise - parent * 0.2
      argument(level: level + 1, rise: r, upright: upright)
      lastOrd = true
    case "\\":
      command(level: level, rise: rise, upright: &upright)
    case " ", "\t", "\n", "\u{00a0}", "&":
      break
    case "'":
      put("′", level, rise, italic: false)
      lastOrd = true
    case "-", "−":
      op("−", level, rise, relation: false)
    case "+":
      op("+", level, rise, relation: false)
    case "=", "<", ">":
      op(String(c), level, rise, relation: true)
    case "*":
      put("∗", level, rise, italic: false)
      lastOrd = true
    case "(", "[", "/":
      put(String(c), level, rise, italic: false)
      lastOrd = false
    case ",":
      put(",", level, rise, italic: false)
      space(0.167, level)
      lastOrd = false
    default:
      put(String(c), level, rise, italic: !upright && c.isLetter)
      lastOrd = true
    }
  }

  /// A script's or command's argument: a braced group, a command, or one character.
  private func argument(level: Int, rise: CGFloat, upright: Bool) {
    guard let c = peek else { return }
    i += 1
    var u = upright
    if c == "{" {
      list(level: level, rise: rise, upright: &u, closing: true)
    } else {
      atom(c, level: level, rise: rise, upright: &u)
    }
  }

  /// The raw text of a braced argument, for commands that restyle letters.
  private func rawArgument() -> String {
    guard let c = peek else { return "" }
    i += 1
    if c != "{" { return String(c) }
    var out = ""
    while let d = peek, d != "}" {
      out.append(d)
      i += 1
    }
    i += 1
    return out
  }

  /// The raw text of an argument with any braces inside it: a braced group,
  /// a command's name, or one character.
  private func group() -> String {
    while peek == " " { i += 1 }
    guard let c = peek else { return "" }
    i += 1
    if c == "\\" {
      var s = "\\"
      while let d = peek, d.isLetter {
        s.append(d)
        i += 1
      }
      if s == "\\", let d = peek {
        s.append(d)
        i += 1
      }
      return s
    }
    if c != "{" { return String(c) }
    var depth = 1
    var out = ""
    while let d = peek {
      i += 1
      if d == "{" { depth += 1 }
      if d == "}" {
        depth -= 1
        if depth == 0 { break }
      }
      out.append(d)
    }
    return out
  }

  /// A fraction set as displayed math sets it: numerator over denominator,
  /// each centered over a rule on the math axis.
  private func stack(_ top: String, _ bottom: String, rise: CGFloat) {
    let n = TeX(top, size: size, family: family)
    let d = TeX(bottom, size: size, family: family)
    let em = sizeAt(0)
    let axis = em * 0.25
    let thickness = max(0.8, em * 0.05)
    let gap = em * 0.12
    let (_, nd) = TeX.extent(n.pieces, tight: true)
    let (da, _) = TeX.extent(d.pieces, tight: true)
    let w = max(n.x, d.x) + em * 0.24
    space(0.1, 0)
    pieces += TeX.shift(n.pieces, x: x + (w - n.x) / 2, rise: rise + axis + thickness / 2 + gap + nd)
    pieces += TeX.shift(d.pieces, x: x + (w - d.x) / 2, rise: rise + axis - thickness / 2 - gap - da)
    pieces.append(.rule(x: x, width: w, rise: rise + axis, thickness: thickness))
    x += w
    space(0.1, 0)
  }

  private func command(level: Int, rise: CGFloat, upright: inout Bool) {
    var name = ""
    while let c = peek, c.isLetter {
      name.append(c)
      i += 1
    }
    if name.isEmpty, let c = peek {
      i += 1
      switch c {
      case "\\": space(1, level)
      case ",": space(0.167, level)
      case ";": space(0.278, level)
      case ":": space(0.222, level)
      case "!": space(-0.167, level)
      case " ": space(0.25, level)
      default: put(String(c), level, rise, italic: false)
      }
      return
    }
    if let g = TeX.greek[name] {
      let capital = name.first!.isUppercase
      put(g, level, rise, italic: !capital && !upright)
      lastOrd = true
      return
    }
    if let (s, kind) = TeX.symbols[name] {
      switch kind {
      case .relation: op(s, level, rise, relation: true)
      case .binary: op(s, level, rise, relation: false)
      case .ordinary:
        put(s, level, rise, italic: false)
        lastOrd = true
      }
      return
    }
    switch name {
    case "rm":
      upright = true
    case "mathrm", "operatorname", "mathbf", "boldsymbol", "mathsf":
      argument(level: level, rise: rise, upright: true)
      lastOrd = true
    case "text", "textrm", "mbox":
      // Words keep their spaces.
      put(group(), level, rise, italic: false)
      lastOrd = true
    case "mathit":
      argument(level: level, rise: rise, upright: false)
      lastOrd = true
    case "hat", "vec", "bar", "overline", "dot", "ddot", "tilde", "widehat", "widetilde":
      // An accent sits on one letter as a combining mark; over more, it is left off.
      let base = group()
      let mark = ["hat": "\u{302}", "widehat": "\u{302}", "vec": "\u{20D7}", "bar": "\u{304}", "overline": "\u{305}",
                  "dot": "\u{307}", "ddot": "\u{308}", "tilde": "\u{303}", "widetilde": "\u{303}"][name]!
      if base.count == 1, let c = base.first {
        put(String(c) + mark, level, rise, italic: !upright && c.isLetter)
      } else {
        let inner = TeX(base, size: size, family: family)
        pieces += TeX.shift(inner.pieces, x: x, rise: rise)
        x += inner.x
      }
      lastOrd = true
    case "begin", "end":
      // Environments are set as their contents, row after row.
      _ = group()
    case "mathcal", "mathscr":
      put(String(rawArgument().map(TeX.script)), level, rise, italic: false)
      lastOrd = true
    case "mathbb":
      put(String(rawArgument().map(TeX.doubleStruck)), level, rise, italic: false)
      lastOrd = true
    case "sqrt":
      let f = font(level, italic: false)
      put("√", level, rise, italic: false)
      let start = x
      let first = pieces.count
      argument(level: level, rise: rise, upright: upright)
      let thickness = max(0.8, sizeAt(level) * 0.055)
      // Over something tall, a stacked fraction say, the bar rises clear of it.
      let top = TeX.extent(Array(pieces[first...]), tight: true).ascent + thickness * 1.5
      pieces.append(.rule(x: start - 0.5, width: x - start + 1.5, rise: max(rise + f.ascender * 0.9, top), thickness: thickness))
      space(0.06, level)
      lastOrd = true
    case "frac" where display && level == 0, "dfrac" where display && level == 0:
      stack(group(), group(), rise: rise)
      lastOrd = true
    case "frac", "tfrac", "dfrac":
      argument(level: level + 1, rise: rise + sizeAt(level) * 0.32, upright: upright)
      put("⁄", level, rise, italic: false)
      argument(level: level + 1, rise: rise - sizeAt(level) * 0.05, upright: upright)
      lastOrd = true
    case "quad":
      space(1, level)
    case "qquad":
      space(2, level)
    case "ln", "log", "exp", "sin", "cos", "tan", "lim", "max", "min", "det", "sup", "inf", "arg", "dim", "ker", "gcd", "tanh", "sinh", "cosh", "Pr", "mod", "deg":
      put(name, level, rise, italic: false)
      lastOrd = false
    case "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr":
      // The delimiter after it is set at its usual size; an empty one, not at all.
      if peek == "." { i += 1 }
    case "displaystyle", "textstyle", "limits", "nolimits":
      break
    default:
      put(name, level, rise, italic: false)
      lastOrd = true
    }
  }

  // ─── Tables ─────────────────────────────────────────────────────────────

  private enum Kind { case ordinary, binary, relation }

  private static let greek: [String: String] = [
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε",
    "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ",
    "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ",
    "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
    "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
    "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
  ]

  private static let symbols: [String: (String, Kind)] = [
    "odot": ("⊙", .ordinary), "hbar": ("ℏ", .ordinary), "partial": ("∂", .ordinary),
    "infty": ("∞", .ordinary), "ldots": ("…", .ordinary), "dots": ("…", .ordinary),
    "prime": ("′", .ordinary), "nabla": ("∇", .ordinary),
    "pm": ("±", .binary), "mp": ("∓", .binary), "times": ("×", .binary), "cdot": ("⋅", .binary),
    "setminus": ("∖", .binary),
    "int": ("∫", .ordinary), "iint": ("∬", .ordinary), "oint": ("∮", .ordinary),
    "sum": ("∑", .ordinary), "prod": ("∏", .ordinary), "cdots": ("⋯", .ordinary), "vdots": ("⋮", .ordinary),
    "ell": ("ℓ", .ordinary), "emptyset": ("∅", .ordinary), "forall": ("∀", .ordinary), "exists": ("∃", .ordinary),
    "langle": ("⟨", .ordinary), "rangle": ("⟩", .ordinary), "angle": ("∠", .ordinary), "degree": ("°", .ordinary),
    "circ": ("∘", .binary), "div": ("÷", .binary), "ast": ("∗", .binary), "star": ("⋆", .binary),
    "cup": ("∪", .binary), "cap": ("∩", .binary), "wedge": ("∧", .binary), "vee": ("∨", .binary),
    "otimes": ("⊗", .binary), "oplus": ("⊕", .binary), "dagger": ("†", .ordinary),
    "vert": ("|", .ordinary), "lvert": ("|", .ordinary), "rvert": ("|", .ordinary), "Vert": ("‖", .ordinary),
    "lfloor": ("⌊", .ordinary), "rfloor": ("⌋", .ordinary), "lceil": ("⌈", .ordinary), "rceil": ("⌉", .ordinary),
    "Re": ("ℜ", .ordinary), "Im": ("ℑ", .ordinary), "aleph": ("ℵ", .ordinary),
    "in": ("∈", .relation), "notin": ("∉", .relation), "ni": ("∋", .relation),
    "subset": ("⊂", .relation), "subseteq": ("⊆", .relation), "supset": ("⊃", .relation), "supseteq": ("⊇", .relation),
    "ll": ("≪", .relation), "gg": ("≫", .relation), "perp": ("⊥", .relation), "parallel": ("∥", .relation),
    "mid": ("∣", .relation), "cong": ("≅", .relation), "doteq": ("≐", .relation),
    "leftarrow": ("←", .relation), "gets": ("←", .relation), "leftrightarrow": ("↔", .relation),
    "Rightarrow": ("⇒", .relation), "implies": ("⇒", .relation), "Leftarrow": ("⇐", .relation),
    "Leftrightarrow": ("⇔", .relation), "iff": ("⇔", .relation), "mapsto": ("↦", .relation),
    "longrightarrow": ("⟶", .relation), "uparrow": ("↑", .relation), "downarrow": ("↓", .relation),
    "approx": ("≈", .relation), "sim": ("∼", .relation), "simeq": ("≃", .relation),
    "gtrsim": ("≳", .relation), "lesssim": ("≲", .relation), "to": ("→", .relation),
    "rightarrow": ("→", .relation), "leq": ("≤", .relation), "le": ("≤", .relation),
    "geq": ("≥", .relation), "ge": ("≥", .relation), "neq": ("≠", .relation), "ne": ("≠", .relation),
    "propto": ("∝", .relation), "equiv": ("≡", .relation), "lt": ("<", .relation), "gt": (">", .relation),
    "top": ("⊤", .ordinary), "bot": ("⊥", .ordinary), "ddagger": ("‡", .ordinary), "bullet": ("∙", .binary),
    "triangle": ("△", .ordinary), "square": ("□", .ordinary), "neg": ("¬", .ordinary), "lor": ("∨", .binary), "land": ("∧", .binary),
  ]

  /// Every command `TeX` sets as it should, rather than printing its name.
  private static let known: Set<String> = {
    var k = Set(greek.keys).union(symbols.keys)
    k.formUnion([
      "rm", "mathrm", "operatorname", "mathbf", "boldsymbol", "mathsf", "text", "textrm", "mbox", "mathit", "hat", "vec", "bar", "overline", "dot", "ddot",
      "tilde", "widehat", "widetilde", "mathcal", "mathscr", "mathbb", "sqrt", "frac", "tfrac", "dfrac", "quad", "qquad", "ln", "log", "exp", "sin", "cos", "tan",
      "lim", "max", "min", "det", "sup", "inf", "arg", "dim", "ker", "gcd", "tanh", "sinh", "cosh", "Pr", "mod", "deg", "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl",
      "Bigr", "displaystyle", "textstyle", "limits", "nolimits",
    ])
    return k
  }()

  /// Whether `tex` can be set as it's meant to be: its braces balance, and every command in it is known.
  static func supports(_ tex: String) -> Bool {
    var depth = 0
    let chars = Array(tex)
    var i = 0
    while i < chars.count {
      switch chars[i] {
      case "{": depth += 1
      case "}":
        depth -= 1
        if depth < 0 { return false }
      case "\\":
        var name = ""
        var j = i + 1
        while j < chars.count, chars[j].isLetter {
          name.append(chars[j])
          j += 1
        }
        if name.isEmpty {
          i += 1
        } else {
          if !known.contains(name) { return false }
          i = j - 1
        }
      default: break
      }
      i += 1
    }
    return depth == 0
  }

  /// Blackboard capitals, for ℝ and its like; the gaps in that block live in Letterlike Symbols.
  private static func doubleStruck(_ c: Character) -> Character {
    let holes: [Character: Character] = ["C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ"]
    if let h = holes[c] { return h }
    guard let v = c.asciiValue, c.isUppercase, let s = Unicode.Scalar(0x1D538 + UInt32(v - 65)) else { return c }
    return Character(s)
  }

  /// Mathematical script capitals; the gaps in that Unicode block live in Letterlike Symbols.
  private static func script(_ c: Character) -> Character {
    let holes: [Character: Character] = [
      "B": "ℬ", "E": "ℰ", "F": "ℱ", "H": "ℋ", "I": "ℐ", "L": "ℒ", "M": "ℳ", "R": "ℛ",
    ]
    if let h = holes[c] { return h }
    guard let v = c.asciiValue, c.isUppercase, let s = Unicode.Scalar(0x1D49C + UInt32(v - 65)) else { return c }
    return Character(s)
  }
}

// ─── Pictures ────────────────────────────────────────────────────────────────

extension TeX {
  /// How far typeset pieces reach above and below their baseline: by the
  /// font's line metrics, or `tight`ly, by the ink.
  static func extent(_ pieces: [Piece], tight: Bool = false) -> (ascent: CGFloat, descent: CGFloat) {
    var a: CGFloat = 0
    var d: CGFloat = 0
    for piece in pieces {
      switch piece {
      case let .text(line, _, rise):
        if tight {
          let ink = CTLineGetImageBounds(line, nil)
          a = max(a, rise + ink.maxY)
          d = max(d, -ink.minY - rise)
        } else {
          var asc: CGFloat = 0
          var desc: CGFloat = 0
          CTLineGetTypographicBounds(line, &asc, &desc, nil)
          a = max(a, rise + asc)
          d = max(d, desc - rise)
        }
      case .halo: break
      case let .rule(_, _, rise, thickness):
        a = max(a, rise + thickness / 2)
        d = max(d, thickness / 2 - rise)
      }
    }
    return (a, d)
  }

  static func shift(_ pieces: [Piece], x dx: CGFloat, rise dr: CGFloat) -> [Piece] {
    pieces.map {
      switch $0 {
      case let .text(line, x, rise): return .text(line, x: x + dx, rise: rise + dr)
      case let .rule(x, width, rise, thickness): return .rule(x: x + dx, width: width, rise: rise + dr, thickness: thickness)
      case let .halo(x, width, rise, height): return .halo(x: x + dx, width: width, rise: rise + dr, height: height)
      }
    }
  }

  private static var pictures: [String: (UIImage, CGFloat)] = [:]

  /// `tex` drawn in `color`, and how far below its baseline the picture reaches.
  static func picture(_ tex: String, size: CGFloat, color: UIColor, display: Bool = false) -> (image: UIImage, descent: CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    let key = "\(tex)|\(size)|\(display)|\(r),\(g),\(b),\(a)"
    if let p = pictures[key] { return p }
    let t = TeX(tex, size: size, display: display)
    let loose = extent(t.pieces)
    let ink = extent(t.pieces, tight: true)
    let ascent = ceil(max(loose.ascent, ink.ascent + 1))
    let descent = ceil(max(loose.descent, ink.descent + 1))
    let format = UIGraphicsImageRendererFormat.preferred()
    format.opaque = false
    // A little room on the right, where an italic letter leans out.
    let image = UIGraphicsImageRenderer(size: CGSize(width: max(1, ceil(t.x + 1)), height: ascent + descent), format: format).image { c in
      c.cgContext.setFillColor(color.cgColor)
      drawPieces(t.pieces, in: c.cgContext, x: 0, baseline: ascent)
    }
    if pictures.count > 400 { pictures.removeAll() }
    pictures[key] = (image, descent)
    return (image, descent)
  }
}
