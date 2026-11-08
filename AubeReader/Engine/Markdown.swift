import UIKit

/// Markdown as answers are written in it, read into blocks: paragraphs,
/// headings, list items, quotes, code, displayed formulas and rules. Inline it
/// knows bold, italic, code, links and TeX between `$…$` or `\(…\)`; displayed
/// TeX sits between `$$…$$` or `\[…\]`. Tables are kept as they were written,
/// set like code.
enum Markdown: Equatable {
  case paragraph(String)
  case heading(String, level: Int)
  case item(String, marker: String, depth: Int)
  case quote(String)
  case code(String)
  case math(String)
  case rule

  /// Reads `source` into blocks. `partial` is for text still arriving: a
  /// displayed formula not yet closed is held back rather than shown as its source.
  static func read(_ source: String, partial: Bool) -> [Markdown] {
    var out: [Markdown] = []
    var para: [String] = []
    var quote: [String] = []
    func flush() {
      if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))) }
      if !quote.isEmpty { out.append(.quote(quote.joined(separator: " "))) }
      para = []
      quote = []
    }
    let lines = source.components(separatedBy: "\n")
    var i = 0
    while i < lines.count {
      let line = lines[i]
      let t = line.trimmingCharacters(in: .whitespaces)
      i += 1
      if t.isEmpty {
        flush()
        continue
      }
      // Code, to its closing fence (or for now, to where the text has got to).
      if t.hasPrefix("```") || t.hasPrefix("~~~") {
        flush()
        var body: [String] = []
        while i < lines.count {
          let l = lines[i]
          i += 1
          if l.trimmingCharacters(in: .whitespaces).hasPrefix(t.prefix(3)) { break }
          body.append(l)
        }
        out.append(.code(body.joined(separator: "\n")))
        continue
      }
      // A displayed formula, on one line or over several.
      if t.hasPrefix("$$") || t.hasPrefix("\\[") {
        let close = t.hasPrefix("$$") ? "$$" : "\\]"
        var body = String(t.dropFirst(2))
        var closed = false
        if let r = body.range(of: close) {
          body = String(body[..<r.lowerBound])
          closed = true
        } else {
          var j = i
          while j < lines.count {
            let l = lines[j]
            j += 1
            if let r = l.range(of: close) {
              body += "\n" + l[..<r.lowerBound]
              closed = true
              break
            }
            body += "\n" + l
          }
          if closed { i = j }
        }
        if closed {
          flush()
          out.append(.math(body.trimmingCharacters(in: .whitespacesAndNewlines)))
          continue
        }
        if partial {
          // Everything from here is the formula, still being written.
          flush()
          return out
        }
      }
      if let (level, text) = heading(t) {
        flush()
        out.append(.heading(text, level: level))
        continue
      }
      if isRule(t) {
        flush()
        out.append(.rule)
        continue
      }
      if t.hasPrefix(">") {
        if !para.isEmpty { flush() }
        quote.append(t.dropFirst().trimmingCharacters(in: .whitespaces))
        continue
      }
      if t.hasPrefix("|") {
        flush()
        var rows = [t]
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
          rows.append(lines[i].trimmingCharacters(in: .whitespaces))
          i += 1
        }
        out.append(.code(rows.joined(separator: "\n")))
        continue
      }
      if let (marker, text, depth) = item(line) {
        flush()
        out.append(.item(text, marker: marker, depth: depth))
        continue
      }
      // A line indented under a list item goes on with it.
      if para.isEmpty, quote.isEmpty, line.hasPrefix("  "), case let .item(text, marker, depth)? = out.last {
        out[out.count - 1] = .item(text + " " + t, marker: marker, depth: depth)
        continue
      }
      if !quote.isEmpty { flush() }
      para.append(t)
    }
    flush()
    return out
  }

  private static func heading(_ t: String) -> (Int, String)? {
    let hashes = t.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
    return (hashes, t.dropFirst(hashes).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")))
  }

  private static func isRule(_ t: String) -> Bool {
    let marks = t.filter { $0 != " " }
    guard marks.count >= 3, let c = marks.first, "-*_".contains(c) else { return false }
    return marks.allSatisfy { $0 == c }
  }

  /// A bullet (•, then ◦ deeper in) or a number, the item's text, and how deep it sits.
  private static func item(_ line: String) -> (String, String, Int)? {
    let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    let t = line.drop { $0 == " " || $0 == "\t" }
    let depth = min(3, indent / 2)
    if let c = t.first, "-*+•".contains(c), t.dropFirst().first == " " {
      return (depth % 2 == 0 ? "•" : "◦", t.dropFirst(2).trimmingCharacters(in: .whitespaces), depth)
    }
    let digits = t.prefix { $0.isNumber }
    if (1...3).contains(digits.count), let p = t.dropFirst(digits.count).first, p == "." || p == ")",
       t.dropFirst(digits.count + 1).first == " " {
      return ("\(digits).", t.dropFirst(digits.count + 2).trimmingCharacters(in: .whitespaces), depth)
    }
    return nil
  }
}

// ─── Inline ──────────────────────────────────────────────────────────────────

/// How a run of answer text is set: its size, weight and slant, in serif.
struct Prose {
  var size: CGFloat
  var weight: UIFont.Weight = .regular
  var italic = false
  var color: UIColor
  var leading: CGFloat = 1.36
  var mono = false

  func font(bold: Bool = false, italic slant: Bool = false) -> UIFont {
    if mono { return .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular) }
    return Faces.serif(size, weight: bold ? .semibold : weight, italic: italic || slant)
  }

  /// `source` set in this style: its markdown emphasis, code and links, and
  /// its formulas drawn in place. Still `partial`ly written, a formula or a
  /// run of code not yet closed is held back, and bold not yet closed is shown bold.
  func set(_ source: String, partial: Bool = false, traits: UITraitCollection) -> NSAttributedString {
    enum Hole {
      case math(String, display: Bool)
      case code(String)
    }
    // Formulas and code come out first, so markdown can't read into them;
    // each leaves a private-use character in its place.
    var text = ""
    var holes: [Hole] = []
    func hole(_ h: Hole) {
      text.unicodeScalars.append(Unicode.Scalar(0xE000 + holes.count)!)
      holes.append(h)
    }
    let c = Array(source)
    func find(_ s: String, from: Int) -> Int? {
      let k = Array(s)
      var j = from
      while j + k.count <= c.count {
        if Array(c[j..<j + k.count]) == k { return j }
        j += 1
      }
      return nil
    }
    var i = 0
    scan: while i < c.count {
      let ch = c[i]
      if ch == "\\", i + 1 < c.count {
        let next = c[i + 1]
        if next == "(" || next == "[" {
          if let end = find(next == "(" ? "\\)" : "\\]", from: i + 2) {
            hole(.math(String(c[i + 2..<end]), display: next == "["))
            i = end + 2
            continue
          }
          if partial { break scan }
        }
        if next == "$" {
          text.append("$")
          i += 2
          continue
        }
        text.append(ch)
        text.append(next)
        i += 2
        continue
      }
      if ch == "`" {
        if let end = find("`", from: i + 1) {
          hole(.code(String(c[i + 1..<end])))
          i = end + 1
          continue
        }
        if partial { break scan }
      }
      if ch == "$" {
        if i + 1 < c.count, c[i + 1] == "$" {
          if let end = find("$$", from: i + 2) {
            hole(.math(String(c[i + 2..<end]), display: true))
            i = end + 2
            continue
          }
          if partial { break scan }
        } else if i + 1 < c.count, c[i + 1] != " " {
          // A closing $ that hugs what it closes; "$5 and $10" stays money.
          var j = i + 1
          var end: Int?
          while let k = find("$", from: j) {
            if c[k - 1] != " " && c[k - 1] != "\\" {
              end = k
              break
            }
            j = k + 1
          }
          if let end {
            hole(.math(String(c[i + 1..<end]), display: false))
            i = end + 1
            continue
          }
          if partial && !c[i + 1].isNumber { break scan }
        }
      }
      text.append(ch)
      i += 1
    }
    if partial && text.components(separatedBy: "**").count % 2 == 0 { text += "**" }

    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
    let parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    let ps = NSMutableParagraphStyle()
    ps.lineHeightMultiple = leading
    ps.hyphenationFactor = 0.3
    let ink = color.resolvedColor(with: traits)
    let out = NSMutableAttributedString()
    for run in parsed.runs {
      let intent = run.inlinePresentationIntent ?? []
      var attrs: [NSAttributedString.Key: Any] = [
        .font: font(bold: intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized)),
        .foregroundColor: color,
        .paragraphStyle: ps,
      ]
      if intent.contains(.code) {
        attrs[.font] = UIFont.monospacedSystemFont(ofSize: size * 0.86, weight: .regular)
        attrs[.backgroundColor] = Palette.fill
      }
      if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      if run.link != nil {
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attrs[.underlineColor] = Palette.faint
      }
      out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attrs))
    }

    // Back into the holes go the formulas, drawn, and the code.
    let ns = out.string as NSString
    for at in stride(from: ns.length - 1, through: 0, by: -1) {
      let u = ns.character(at: at)
      guard u >= 0xE000, Int(u) - 0xE000 < holes.count else { continue }
      let attrs = out.attributes(at: at, effectiveRange: nil)
      let piece: NSAttributedString
      switch holes[Int(u) - 0xE000] {
      case let .math(tex, display):
        let (image, descent) = TeX.picture(
          tex.trimmingCharacters(in: .whitespacesAndNewlines), size: size * (display ? 1.06 : 0.96), color: ink, display: display)
        let a = NSTextAttachment()
        a.image = image
        a.bounds = CGRect(x: 0, y: -descent, width: image.size.width, height: image.size.height)
        let m = NSMutableAttributedString(attachment: a)
        m.addAttributes([.paragraphStyle: ps], range: NSRange(location: 0, length: m.length))
        piece = m
      case let .code(s):
        var a = attrs
        a[.font] = UIFont.monospacedSystemFont(ofSize: size * 0.86, weight: .regular)
        a[.backgroundColor] = Palette.fill
        piece = NSAttributedString(string: s, attributes: a)
      }
      out.replaceCharacters(in: NSRange(location: at, length: 1), with: piece)
    }
    return out
  }
}
