import UIKit

// ─── Text that has no pages ──────────────────────────────────────────────────

/// Plain text and RTF have no layout of their own to keep, only paragraphs.
enum Flowing {
  static func read(file: URL, id: String, fileName: String) throws -> ImportedDoc {
    let lines: [(text: String, heading: Int)]
    if file.pathExtension.lowercased() == "rtf" {
      lines = try rich(file)
    } else {
      lines = try plain(file)
    }
    guard lines.contains(where: { !$0.text.isEmpty }) else {
      throw DocumentReader.Trouble.unreadable("This file has no text in it.")
    }
    var blocks: [DocBlock] = []
    let nothing = BlockPiece(page: 0, tile: .zero, ink: .zero)
    // A note written as Markdown writes them, "[^name]: what it says", wherever it stands.
    var named: [String: Int] = [:]
    var notes: [DocBlock] = []
    for (text, _) in lines {
      for (name, says) in noteDefinitions(text) where named[name] == nil && !says.isEmpty {
        named[name] = blocks.count + notes.count
        notes.append(DocBlock(id: named[name]!, role: .footnote, text: says, pieces: [nothing], mark: String(notes.count + 1)))
      }
    }
    blocks = notes
    for (text, heading) in lines where !text.isEmpty && noteDefinitions(text).isEmpty {
      let role: BlockRole = heading > 0 ? .heading : text.split(separator: " ").count < 6 ? .minor : .paragraph
      blocks.append(DocBlock(id: blocks.count, role: role, level: heading, text: NoteToken.settleNamed(text, named), pieces: [nothing]))
    }
    // The first heading, if the file starts on one, is its title.
    if let first = blocks.firstIndex(where: { $0.role != .footnote }), blocks[first].role == .heading { blocks[first].role = .title }
    var doc = ImportedDoc(id: id, fileName: fileName, title: (fileName as NSString).deletingPathExtension, blocks: blocks)
    if let t = blocks.first(where: { $0.role == .title }) { doc.title = NoteToken.strip(t.text) }
    doc.flowing = true
    // A note nothing leads to is read where it is rather than lost.
    DocEditor.tidyNotes(&doc)
    return doc
  }

  private static let noteDefinition = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]:\s*"#)

  /// The notes a paragraph defines, if that's all it is: `[^a]: says this`, one or several run together.
  private static func noteDefinitions(_ text: String) -> [(name: String, says: String)] {
    let found = noteDefinition.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard let first = found.first, first.range.location == 0 else { return [] }
    var out: [(String, String)] = []
    for (k, m) in found.enumerated() {
      guard let name = Range(m.range(at: 1), in: text), let start = Range(m.range, in: text)?.upperBound else { continue }
      let end = found[safe: k + 1].flatMap { Range($0.range, in: text)?.lowerBound } ?? text.endIndex
      out.append((String(text[name]), text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return out
  }

  private static func plain(_ file: URL) throws -> [(String, Int)] {
    var used = String.Encoding.utf8
    let text: String
    do {
      text = try String(contentsOf: file, usedEncoding: &used)
    } catch {
      guard let latin = try? String(contentsOf: file, encoding: .isoLatin1) else {
        throw DocumentReader.Trouble.unreadable("This file’s text couldn’t be read.")
      }
      text = latin
    }
    return paragraphs(text).map { p in
      // A Markdown heading says so; otherwise a short first line with no period may well be one.
      var level = 0
      var body = Substring(p)
      while body.first == "#", level < 4 {
        level += 1
        body = body.dropFirst()
      }
      return (body.trimmingCharacters(in: .whitespaces), level)
    }
  }

  /// Blank lines divide paragraphs; single line breaks within one are wrapping.
  private static func paragraphs(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").map { chunk in
      chunk.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private static func rich(_ file: URL) throws -> [(String, Int)] {
    guard let a = try? NSAttributedString(url: file, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
      throw DocumentReader.Trouble.unreadable("This RTF file couldn’t be read.")
    }
    var sizes: [CGFloat: Int] = [:]
    a.enumerateAttribute(.font, in: NSRange(location: 0, length: a.length)) { v, r, _ in
      if let f = v as? UIFont { sizes[f.pointSize, default: 0] += r.length }
    }
    let body = sizes.max { $0.value < $1.value }?.key ?? 12
    var out: [(String, Int)] = []
    (a.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: a.length), options: .byParagraphs) { s, r, _, _ in
      guard let s else { return }
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty else { return }
      let f = a.attribute(.font, at: r.location, effectiveRange: nil) as? UIFont
      let size = f?.pointSize ?? body
      let bold = f?.fontDescriptor.symbolicTraits.contains(.traitBold) == true
      let short = t.split(separator: " ").count <= 16
      out.append((t, short && size > body * 1.1 ? 1 : short && bold ? 2 : 0))
    }
    return out
  }
}
