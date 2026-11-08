import CoreGraphics
import Foundation
import NaturalLanguage

// ─── A document's pages, read as one text ────────────────────────────────────

/// Works out what each block on each page is doing, by what the document as a
/// whole does: what's repeated page after page, what's set larger than the
/// running text, and what carries on from one column into the next. These are
/// good guesses. The model checks them later, against pictures of the pages.
enum Structure {
  /// "Figure 3:", "Fig. 2", "Table IV.", "Box A": a word for a picture, then something that numbers it.
  static let captionPattern = try! NSRegularExpression(
    pattern: #"^\s*(?i:fig(?:ure|\.)?|tab(?:le|\.)?|chart|plate|exhibit|scheme|graph|map|box|photo|image|abbildung|abb\.|tabelle|figura|tabla|tableau|illustration|algorithm|listing)\s*(?:\d[\w.\-]*|[IVXLC]+\b|[A-Z]\b|[A-Z][.\-]\d+)\s*[:.—–|)\-]?"#)
  /// A caption's number followed by the punctuation that sets it off from what it says.
  private static let captionMarked = try! NSRegularExpression(
    pattern: #"^\s*(?i:fig(?:ure|\.)?|tab(?:le|\.)?|chart|plate|exhibit|scheme|graph|map|box|photo|image|abbildung|abb\.|tabelle|figura|tabla|tableau|illustration|algorithm|listing)\s*(?:\d[\w.\-]*|[IVXLC]+\b|[A-Z]\b|[A-Z][.\-]\d+)\s*[:.—–|)\-]"#)
  private static let numberedHeading = try! NSRegularExpression(pattern: #"^(\d{1,2}(\.\d{1,2}){0,3}\.?|[IVXLC]{1,5}\.|[A-Z]\.)\s+\S"#)
  static let pageNumber = try! NSRegularExpression(pattern: #"^\s*((page|p\.|seite|página)\s*)?[\divxlc]{1,5}(\s*(/|of|von|de)\s*\d{1,5})?\s*$"#, options: [.caseInsensitive])
  static let referencesHeading = try! NSRegularExpression(
    pattern: #"^\s*(\d+\.?\s+|[IVX]+\.\s+)?(references|bibliography|works cited|literature cited|literatur|bibliografía|bibliographie|références)\s*$"#, options: [.caseInsensitive])
  private static let abstractLead = try! NSRegularExpression(pattern: #"^\s*(abstract|summary|zusammenfassung|résumé|resumen)\s*[—–:.\-]*\s*"#, options: [.caseInsensitive])
  static let mathSymbols = CharacterSet(charactersIn: "∑∏∫∂∇√∞≤≥≠≈≡∈∉⊂⊃∪∩→←↔⇒⇔±×÷∝∀∃αβγδεζηθικλμνξπρστυφχψωΓΔΘΛΞΠΣΦΨΩ")

  static func endsSentence(_ t: String) -> Bool {
    // A note's mark comes after the period it follows.
    let bare = NoteToken.strip(t)
    var s = Substring(bare)
    while let c = s.last, "\"”’')]}⁰¹²³⁴⁵⁶⁷⁸⁹".contains(c) { s = s.dropLast() }
    guard let last = s.last else { return false }
    return ".!?:;。！？؟".contains(last)
  }

  static func hits(_ r: NSRegularExpression, _ t: String) -> Bool {
    r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
  }

  struct Found {
    var page: Int
    var block: PageBlock
    var role = BlockRole.paragraph
    var level = 0
    var captionOf: Int?
    var merged: [Found] = []
    var id = -1
    /// Stays with it through everything, so that a mark can say which note it leads to.
    var uid = -1
    /// What it's marked with on the page, if a mark in the text leads to it.
    var label: String?
    /// Small print at the foot of its page or column.
    var foot = false
    /// The rule over it there, if there is one.
    var rule: CGRect?

    var text: String { block.lines.first?.text ?? "" }
    var last: TextLine? { (merged.last?.block ?? block).lines.last }
    var firstLine: TextLine? { block.lines.first }
    var words: Int { block.lines.reduce(0) { $0 + $1.words.count } }
    var size: CGFloat { block.lines.first?.size ?? 0 }
  }

  /// `known` says whether a word mended across a line break is a word.
  static func document(
    id: String, fileName: String, pages raw: [RawPage], layouts: [PageLayout], fonts: [FontRecord], measure: DocMeasure,
    metaTitle: String?, metaAuthor: String?, known: @escaping (String) -> Bool = { _ in true }
  ) -> ImportedDoc {
    var found: [Found] = []
    for (p, layout) in layouts.enumerated() {
      for b in layout.blocks { found.append(Found(page: p, block: b)) }
    }

    let (_, bodyBold) = runningText(found, fonts: fonts, body: measure.body)
    let isBold: (TextLine) -> Bool = { fonts.indices.contains($0.font) && fonts[$0.font].bold }

    // ─── What's repeated from page to page ──────────────────────────────
    let furniture = findFurniture(found, raw: raw)
    var stamps: [String: Set<Int>] = [:]
    func stamp(_ r: CGRect) -> String { "\(Int(r.minX / 6))/\(Int(r.minY / 6))/\(Int(r.width / 6))/\(Int(r.height / 6))" }
    for f in found where f.block.kind == .figure { stamps[stamp(f.block.ink), default: []].insert(f.page) }
    let enoughStamps = max(3, raw.count / 5)

    // ─── Each block by itself ───────────────────────────────────────────
    for i in found.indices {
      let f = found[i]
      let size = raw[f.page].size
      switch f.block.kind {
      case .figure:
        // A narrow strip beside the text, like a preprint server's stamp, is no figure.
        let strip = f.block.ink.width < size.width * 0.07 && f.block.ink.height > f.block.ink.width * 4
        let outside = f.block.ink.maxX < size.width * 0.1 || f.block.ink.minX > size.width * 0.9
        let repeated = (stamps[stamp(f.block.ink)]?.count ?? 0) >= enoughStamps
        found[i].role = (strip && outside) || repeated ? .furniture : .figure
      case .table: found[i].role = .table
      case .text:
        // A short line at the very edge of a page: a journal's masthead, a copyright line.
        let edge = f.block.ink.maxY < size.height * 0.075 || f.block.ink.minY > size.height * 0.925
        if furniture.contains(i) || (edge && f.block.lines.count <= 2 && f.words <= 24) {
          found[i].role = .furniture
        } else {
          found[i].role = role(of: f, body: measure.body, bodyBold: bodyBold, bold: isBold, fonts: fonts, pageSize: raw[f.page].size)
        }
      }
    }

    // ─── Footnotes, and the marks in the text that lead to them ─────────
    var printed = findFootnotes(&found, raw: raw, body: measure.body, fonts: fonts, furniture: furniture)

    // ─── Heading levels: the larger, the higher ─────────────────────────
    var styles = Set<CGFloat>()
    for f in found where f.role == .heading { styles.insert((f.size * 2).rounded() / 2) }
    let ladder = styles.sorted(by: >)
    for i in found.indices where found[i].role == .heading {
      let k = ladder.firstIndex(of: (found[i].size * 2).rounded() / 2) ?? 0
      found[i].level = min(k + 1, 4)
    }

    assignFrontMatter(&found, raw: raw, measure: measure, metaTitle: metaTitle)
    assignReferences(&found)
    printed += linkLists(&found, fonts: fonts)
    linkCaptions(&found)
    mergeAcrossBreaks(&found)

    // ─── As the model will come to see them ─────────────────────────────
    var blocks: [DocBlock] = []
    var ids: [String: (id: Int, piece: Int)] = [:]
    var nextId = 0
    var uids: [Int: Int] = [:]
    func key(_ page: Int, _ tile: CGRect) -> String { "\(page)/\(tile.minX)/\(tile.minY)/\(tile.width)/\(tile.height)" }
    for i in found.indices {
      let f = found[i]
      let parts = [f] + f.merged
      let id = nextId
      nextId += 1
      found[i].id = id
      uids[f.uid] = id
      for (n, part) in parts.enumerated() where !part.block.loose {
        ids[key(part.page, part.block.tile)] = (id, n)
      }
      let lines = parts.flatMap(\.block.lines)
      var text: String
      switch f.role {
      case .figure, .table:
        text = lines.map(\.text).joined(separator: " ")
      case .code:
        text = lines.map(\.text).joined(separator: "\n")
      default:
        text = PageText.join(lines.map(\.text), known: known)
      }
      if f.role == .abstract { text = strip(abstractLead, from: text) }
      if f.role == .footnote {
        // A line of a note can come in pieces, where it's spread wide around a long address. By where they lie, not how they were found.
        let inOrder = parts.flatMap { part in part.block.lines.map { (part.page, $0) } }.sorted { a, b in
          if a.0 != b.0 { return a.0 < b.0 }
          let (x, y) = ((a.1.baseline / 3).rounded(), (b.1.baseline / 3).rounded())
          return x != y ? x < y : a.1.rect.minX < b.1.rect.minX
        }
        // Each piece in order within its column: only pieces of one line need bringing together.
        let sameOrder = parts.count == 1
        text = NoteToken.joinNote(sameOrder ? lines.map(\.text) : inOrder.map(\.1.text), known: known)
      }
      let pieces = parts.map { BlockPiece(page: $0.page, tile: $0.block.tile, ink: $0.block.ink, rule: $0.rule) }
      var block = DocBlock(id: id, role: f.role, level: f.level, text: text, pieces: pieces, style: blockStyle(parts), captionOf: nil)
      block.mark = f.label
      block.mathy = lines.contains { l in
        l.words.contains { w in
          let font = fonts.indices.contains(w.font) && fonts[w.font].math
          // A footnote's mark or a CO₂ is raised or lowered too, but only letters mean a formula.
          let script = w.script != 0 && w.text.contains(where: \.isLetter)
          return font || script || w.text.unicodeScalars.contains(where: mathSymbols.contains)
        }
      }
      blocks.append(block)
    }
    // Captions point at ids, now that there are ids, and so do marks.
    for i in found.indices {
      if let at = found[i].captionOf { blocks[i].captionOf = found[at].id }
    }
    for i in blocks.indices { blocks[i].text = NoteToken.settle(blocks[i].text, uids: uids) }

    // Pages, their tiles now naming ids rather than a page's own blocks.
    var pages: [DocPage] = []
    var running = 0
    for (p, layout) in layouts.enumerated() {
      func rename(_ t: PageTile) -> PageTile {
        var out = t
        out.kids = t.kids?.map(rename)
        if t.kind == .block, let b = t.block {
          let block = layout.blocks[b]
          if let hit = ids[key(p, block.tile)] {
            out.block = hit.id
            out.piece = hit.piece
          } else {
            out.kind = .blank
            out.block = nil
            out.piece = nil
          }
        }
        return out
      }
      running += layout.blocks.count
      let r = raw[p]
      var photos = layout.photos
      if r.scanned { photos = photos.filter { $0.width * $0.height < r.size.width * r.size.height * 0.6 } }
      pages.append(
        DocPage(
          size: r.size, tile: rename(layout.tile), scanned: r.scanned || r.ocr, unread: r.runs.isEmpty && (r.shows > 0 || r.scanned),
          paper: r.paper, photos: photos, turn: r.turn))
    }

    let folios = findFolios(found, raw: raw)
    for (p, rects) in folios where pages.indices.contains(p) { pages[p].folios = rects }
    var doc = ImportedDoc(id: id, fileName: fileName, title: fileName, fonts: fonts, pages: pages, blocks: blocks)
    doc.marks = printed.compactMap { m in uids[m.note].map { PrintedMark(note: $0, page: m.page, box: m.box) } }
    let titled = NoteToken.strip(blocks.filter { $0.role == .title }.map(\.text).joined(separator: " "))
    doc.title = bestTitle(found: titled, meta: metaTitle, fileName: fileName)
    if let a = metaAuthor, let names = plausibleAuthors(a) { doc.authors = names }
    doc.language = language(of: blocks)
    return doc
  }

  private static func strip(_ r: NSRegularExpression, from t: String) -> String {
    r.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
  }

  // ─── The running text ────────────────────────────────────────────────────

  private static func runningText(_ found: [Found], fonts: [FontRecord], body: CGFloat) -> (font: Int, bold: Bool) {
    var tally: [Int: Int] = [:]
    for f in found where f.block.kind == .text {
      for l in f.block.lines where abs(l.size - body) < 1 && l.words.count >= 4 { tally[l.font, default: 0] += l.words.count }
    }
    let font = tally.max { $0.value < $1.value }?.key ?? -1
    return (font, fonts.indices.contains(font) && fonts[font].bold)
  }

  /// Blocks in the page's margins that say the same on many pages, whatever the
  /// page number in them, and bare page numbers.
  private static func findFurniture(_ found: [Found], raw: [RawPage]) -> Set<Int> {
    func margin(_ f: Found) -> Bool {
      let h = raw[f.page].size.height
      return f.block.ink.maxY < h * 0.12 || f.block.ink.minY > h * 0.88
    }
    func shape(_ t: String) -> String {
      String(t.lowercased().map { $0.isNumber ? "#" : $0 }).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var counts: [String: Set<Int>] = [:]
    for f in found where f.block.kind == .text && margin(f) && f.words <= 30 {
      counts[shape(f.block.lines.map(\.text).joined(separator: " ")), default: []].insert(f.page)
    }
    let enough = max(3, raw.count / 5)
    var out = Set<Int>()
    for (i, f) in found.enumerated() where f.block.kind == .text && margin(f) {
      let t = f.block.lines.map(\.text).joined(separator: " ")
      if f.words <= 30, (counts[shape(t)]?.count ?? 0) >= enough { out.insert(i) }
      // A page number alone, or a title and page number that vary only by chapter.
      if hits(pageNumber, t) { out.insert(i) }
    }
    return out
  }

  private static func role(
    of f: Found, body: CGFloat, bodyBold: Bool, bold: (TextLine) -> Bool, fonts: [FontRecord], pageSize: CGSize
  ) -> BlockRole {
    let lines = f.block.lines
    guard let first = lines.first else { return .minor }
    let text = lines.map(\.text).joined(separator: " ")
    let words = f.words
    let size = first.size

    // "Figure 3: …", or set smaller than the text, labelled in bold. "Table 13 compares …" is just a sentence.
    if hits(captionPattern, text), words >= 2 {
      let marked = hits(captionMarked, text)
      if marked || size < body * 0.97 || bold(first) || lines.first?.words.first.map({ fonts.indices.contains($0.font) && fonts[$0.font].bold }) == true {
        return .caption
      }
    }

    // Mostly a font of symbols, or a line of them, centered: a displayed equation.
    var mathy = 0
    var total = 0
    var mono = 0
    for l in lines {
      for w in l.words {
        let n = w.text.count
        total += n
        if fonts.indices.contains(w.font), fonts[w.font].math { mathy += n }
        else { mathy += w.text.unicodeScalars.filter(mathSymbols.contains).count }
        if fonts.indices.contains(w.font), fonts[w.font].mono { mono += n }
      }
    }
    if total > 0, Double(mono) / Double(total) > 0.7, lines.count >= 2 || total > 30 { return .code }
    let scriptWords = lines.flatMap(\.words).filter { $0.script != 0 }.count
    let mathShare = Double(mathy + scriptWords) / Double(max(total, 1))
    let ends = hits(try! NSRegularExpression(pattern: #"\(\d{1,3}[a-z]?\)\s*$"#), text)
    if lines.count <= 14, words <= 110, mathShare > 0.25 || (ends && mathShare > 0.1) {
      // Prose with some math in it has plain words of some length, and fills its column; a formula does neither.
      let plain = lines.flatMap(\.words).filter { w in
        w.script == 0 && w.text.count >= 4 && w.text.allSatisfy(\.isLetter) && !(fonts.indices.contains(w.font) && fonts[w.font].math)
      }.count
      let setIn = f.block.ink.width < f.block.tile.width * 0.9
      if plain <= 3 + lines.count * 2, setIn || ends { return .equation }
    }

    let letters = text.filter(\.isLetter)
    let caps = letters.isEmpty ? 0 : Double(letters.filter(\.isUppercase).count) / Double(letters.count)
    let isBig = size >= body * 1.12
    let isBold = bold(first) && !bodyBold
    let numbered = hits(numberedHeading, text)
    let short = lines.count <= 4 && words <= 24
    // An author can bold a whole sentence; a heading doesn't stop at a period.
    let sentence = text.hasSuffix(".") && words > 6 && !numbered
    if short && !sentence {
      if isBig || (isBold && words <= 16) || (caps > 0.85 && letters.count >= 3 && words <= 12 && size >= body * 0.95) || (numbered && caps > 0.5) {
        return .heading
      }
    }
    if Self.opensList(first.text) { return .list }
    if size < body * 0.87 { return words >= 25 ? .note : .minor }
    if isBig && words > 24 { return .quote }
    // A scrap: too short to be anything but a label, unless it reads as a sentence.
    if words < 6 && !endsSentence(text) { return .minor }
    return .paragraph
  }

  private static func opensList(_ t: String) -> Bool {
    guard let first = t.first else { return false }
    if "•◦▪▫‣●○■□◆◇➢➤✓✔∙·".contains(first) { return true }
    if "–—-".contains(first), t.dropFirst().first == " " { return true }
    return hits(try! NSRegularExpression(pattern: #"^(\(?\d{1,3}\)|\d{1,3}\.\s|\(?[a-z]\)\s)"#), t)
  }

  // ─── The front of a document ─────────────────────────────────────────────

  private static func assignFrontMatter(_ found: inout [Found], raw: [RawPage], measure: DocMeasure, metaTitle: String?) {
    // The first page with any text at all.
    guard let front = found.first(where: { $0.block.kind == .text && $0.role != .furniture })?.page else { return }
    let here = found.indices.filter { found[$0].page == front && found[$0].block.kind == .text && found[$0].role != .furniture }
    let h = raw[front].size.height
    // The largest type in its upper reaches.
    let upper = here.filter { found[$0].block.ink.minY < h * 0.6 }
    guard let top = upper.max(by: { (found[$0].size, -found[$0].block.ink.minY) < (found[$1].size, -found[$1].block.ink.minY) }),
      found[top].size >= measure.body * 1.15, found[top].words <= 40
    else {
      markAbstract(&found, from: 0, page: front)
      return
    }
    found[top].role = .title
    // Lines of it broken into blocks.
    var last = top
    var next = top + 1
    while let n = here.first(where: { $0 == next }), abs(found[n].size - found[top].size) < 0.5, found[n].words <= 30 {
      found[n].role = .title
      last = n
      next += 1
    }
    // Between the title and whatever comes next, short blocks are who wrote it and where they work.
    var k = last + 1
    while let n = here.first(where: { $0 == k }) {
      let f = found[n]
      // A note on an author, or on the title, is at the foot of the page whatever stands above it.
      if f.role == .footnote {
        k += 1
        continue
      }
      let t = f.block.lines.map(\.text).joined(separator: " ")
      if hits(abstractLead, t) || f.role == .paragraph && f.words > 40 || f.role == .heading && hits(numberedHeading, t) { break }
      if f.words > 45 { break }
      if f.role != .heading || f.size < found[top].size { found[n].role = .byline }
      k += 1
    }
    markAbstract(&found, from: last, page: front)
  }

  /// "Abstract", as a heading over the paragraphs that follow it, or leading into one.
  private static func markAbstract(_ found: inout [Found], from start: Int, page: Int) {
    for i in max(0, start)..<found.count where found[i].page <= page + 1 {
      let t = found[i].block.lines.map(\.text).joined(separator: " ")
      guard found[i].block.kind == .text, hits(abstractLead, t), found[i].role != .caption else { continue }
      let bare = strip(abstractLead, from: t).trimmingCharacters(in: .whitespaces)
      if bare.isEmpty {
        // Its own heading, over the abstract that follows.
        found[i].role = .heading
        found[i].level = 2
        var n = i + 1
        while n < found.count, found[n].page <= page + 1 {
          if found[n].role == .paragraph || found[n].role == .byline || found[n].role == .note {
            found[n].role = .abstract
            n += 1
          } else {
            break
          }
        }
      } else {
        found[i].role = .abstract
      }
      return
    }
  }

  private static func assignReferences(_ found: inout [Found]) {
    var i = found.count - 1
    // The last such heading in the document, since that's where a bibliography goes.
    while i >= 0 {
      let t = found[i].block.lines.map(\.text).joined(separator: " ")
      if found[i].block.kind == .text, found[i].role != .furniture, hits(referencesHeading, t) { break }
      i -= 1
    }
    guard i >= 0 else { return }
    found[i].role = .heading
    if found[i].level == 0 { found[i].level = 1 }
    var n = i + 1
    while n < found.count {
      switch found[n].role {
      case .heading where found[n].level > 0 && found[n].level <= found[i].level: return
      case .furniture, .figure, .table, .caption, .equation, .footnote: break
      default: found[n].role = .references
      }
      n += 1
    }
  }

  /// A caption describes the nearest figure or table on its page: the kind it
  /// names, if there's one, close by.
  private static func linkCaptions(_ found: inout [Found]) {
    for i in found.indices where found[i].role == .caption {
      let c = found[i]
      let t = c.block.lines.first?.text.lowercased() ?? ""
      let wantsTable = t.hasPrefix("tab")
      var best: (Int, CGFloat)?
      for j in found.indices where found[j].page == c.page && found[j].role.isPicture && found[j].role != .equation {
        let f = found[j]
        var d = max(0, max(f.block.ink.minY - c.block.ink.maxY, c.block.ink.minY - f.block.ink.maxY))
        // In another column, it's less likely to be its figure.
        let across = min(f.block.ink.maxX, c.block.ink.maxX) - max(f.block.ink.minX, c.block.ink.minX)
        if across <= 0 { d += 400 }
        if wantsTable != (f.role == .table) { d += 150 }
        if best.map({ d < $0.1 }) ?? true { best = (j, d) }
      }
      if let best, best.1 < 500 { found[i].captionOf = best.0 }
    }
  }

  // ─── Across breaks ───────────────────────────────────────────────────────

  /// A paragraph that stops short of a sentence's end at the foot of a column,
  /// and carries on at the top of the next, is one paragraph.
  private static func mergeAcrossBreaks(_ found: inout [Found]) {
    var keep: [Found] = []
    // Blocks' indices shift as they merge, so captions are carried over by mapping.
    var moved: [Int: Int] = [:]
    var i = 0
    var open: Int?
    while i < found.count {
      let f = found[i]
      moved[i] = keep.count
      if let o = open, f.role == .paragraph || f.role == .list || f.role == .references || f.role == .abstract, canContinue(keep[o], into: f) {
        keep[o].merged.append(f)
        moved[i] = o
        i += 1
        continue
      }
      keep.append(f)
      switch f.role {
      case .paragraph, .abstract, .list, .references: open = keep.count - 1
      // What can stand between a paragraph's two halves on the page.
      case .furniture, .figure, .table, .caption, .minor, .note, .footnote: break
      default: open = nil
      }
      i += 1
    }
    for k in keep.indices {
      if let c = keep[k].captionOf { keep[k].captionOf = moved[c] }
    }
    found = keep
  }

  private static func canContinue(_ a: Found, into b: Found) -> Bool {
    guard !a.block.loose, !b.block.loose, let end = a.last, let start = b.firstLine, !endsSentence(end.text) else { return false }
    let tail = a.merged.last ?? a
    // Only where the text has moved on: a new page, or back up to a new column.
    let moved = b.page != tail.page || b.block.ink.minY < tail.block.ink.maxY - 1
    guard moved else { return false }
    guard abs(end.size - start.size) < 0.6, end.font == start.font || start.text.first?.isLowercase == true else { return false }
    // Set as the same stretch of text: the first line isn't indented relative to its own block.
    if b.block.lines.count >= 2, start.rect.minX > b.block.lines[1].rect.minX + start.size * 0.6 { return false }
    if start.text.first?.isLowercase == true { return true }
    // A capital can carry on too, if the line before ran to the column's edge.
    let width = tail.block.ink.width
    return end.rect.maxX > tail.block.ink.maxX - width * 0.06 && end.text.hasSuffix(",") == false ? !Structure.opensItem(start.text) : true
  }

  private static func opensItem(_ t: String) -> Bool { PageAnalyzer.opensItem(t) }

  // ─── Style ───────────────────────────────────────────────────────────────

  private static func blockStyle(_ parts: [Found]) -> BlockStyle {
    let lines = parts.flatMap(\.block.lines)
    guard let first = lines.first else { return BlockStyle() }
    var fontTally: [Int: Int] = [:]
    var sizes: [CGFloat: Int] = [:]
    var colors: [Tint: Int] = [:]
    for l in lines {
      fontTally[l.font, default: 0] += l.words.count
      sizes[l.size, default: 0] += l.words.count
      colors[l.color, default: 0] += l.words.count
    }
    var style = BlockStyle()
    style.font = fontTally.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? first.font
    style.size = sizes.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? first.size
    style.color = colors.max { $0.value < $1.value }?.key ?? first.color
    let steps = zip(lines, lines.dropFirst()).map { $1.baseline - $0.baseline }.filter { $0 > style.size * 0.7 && $0 < style.size * 2.6 }.sorted()
    style.leading = steps.isEmpty ? style.size * 1.2 : steps[steps.count / 2]
    let box = parts[0].block.ink
    let own = parts[0].block.lines
    if own.count >= 2 {
      let rest = own.dropFirst().map(\.rect.minX).min() ?? box.minX
      style.indent = max(0, own[0].rect.minX - rest)
    }
    style.align = alignment(own, box: box)
    let advances = lines.compactMap { l -> CGFloat? in
      let n = l.text.count
      return n >= 16 && l.runs == 1 && l.size > 0 ? l.rect.width / (CGFloat(n) * l.size) : nil
    }.sorted()
    if !advances.isEmpty { style.advance = advances[advances.count / 2] }
    return style
  }

  private static func alignment(_ lines: [TextLine], box: CGRect) -> TextAlign {
    guard lines.count >= 2 else {
      return .left
    }
    let full = lines.dropLast()
    let tolerance = max(box.width * 0.02, 2)
    let leftEven = lines.dropFirst().allSatisfy { abs($0.rect.minX - box.minX) < tolerance * 1.5 }
    let rightEven = full.filter { abs($0.rect.maxX - box.maxX) < tolerance }.count >= max(1, full.count * 3 / 4)
    if leftEven && rightEven { return .justified }
    let middle = lines.allSatisfy { abs($0.rect.midX - box.midX) < tolerance * 1.5 }
    if middle { return .center }
    if rightEven && !leftEven { return .right }
    return .left
  }

  // ─── What it's called ────────────────────────────────────────────────────

  private static func bestTitle(found: String, meta: String?, fileName: String) -> String {
    let t = found.trimmingCharacters(in: .whitespacesAndNewlines)
    if !t.isEmpty { return t }
    if let m = meta?.trimmingCharacters(in: .whitespacesAndNewlines), m.count >= 4, !isToolTitle(m) { return m }
    return (fileName as NSString).deletingPathExtension
  }

  /// Word processors fill the title in with the file's own name or their own.
  private static func isToolTitle(_ t: String) -> Bool {
    let low = t.lowercased()
    // Metadata its writer couldn't encode.
    if t.contains("??") || t.unicodeScalars.contains(where: { $0.value == 0xFFFD }) { return true }
    return low.hasSuffix(".pdf") || low.hasSuffix(".doc") || low.hasSuffix(".docx") || low.hasPrefix("microsoft word") || low == "untitled" || low.contains(".indd") || low.contains(".dvi") || low.hasPrefix("powerpoint")
  }

  private static func plausibleAuthors(_ a: String) -> [String]? {
    let names = a.split(whereSeparator: { ";,".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !names.isEmpty, names.count <= 30, names.allSatisfy({ $0.count < 60 && $0.first?.isLetter == true }) else { return nil }
    return names
  }

  private static func language(of blocks: [DocBlock]) -> String? {
    // The longest paragraphs: short ones full of names and numbers can pass for anything.
    let longest = blocks.filter { $0.role.isProse }.sorted { $0.text.count > $1.text.count }.prefix(12)
    let sample = longest.map(\.text).joined(separator: " ")
    guard sample.count > 40 else { return nil }
    let r = NLLanguageRecognizer()
    r.processString(String(sample.prefix(6000)))
    return r.dominantLanguage?.rawValue
  }
}
