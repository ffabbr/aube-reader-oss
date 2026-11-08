import CoreGraphics
import Foundation

// ─── Corrections ─────────────────────────────────────────────────────────────

/// A change the model asks for, in the shape it answers in.
struct Fix: Codable {
  enum Op: String, Codable, CaseIterable {
    /// What a block is doing: `block`, `role`, `level` for a heading.
    case setRole = "set_role"
    /// The same, for every block set in the same type as `block`, on any page.
    case setRoleLike = "set_role_like"
    /// `blocks`, in the order given, are one block.
    case merge
    /// `block` is two: the second starting at `before`.
    case split
    /// What `block` says, where it was misread: `text`.
    case setText = "set_text"
    /// `blocks` read in the order given.
    case reorder
    /// `block` isn't part of the text: a running head, a page number.
    case drop
    /// There's a figure or table here that wasn't noticed: `box`, `role`.
    case addFigure = "add_figure"
    /// `block`, a picture, should cover `box` instead.
    case setBox = "set_box"
    /// Text the page couldn't give up, read from its picture: `text`, `role`, `box`.
    case addText = "add_text"
    /// The page's text is nonsense, or missing: read it again from its picture.
    case readAgain = "read_again"
    /// The page is sideways or upside down: turn it `degrees` clockwise and read it again.
    case turnPage = "turn_page"
    /// The page can't be made sense of as text, such as a form: show it whole.
    case flattenPage = "flatten_page"
    /// `block`'s type would be better matched by `family`.
    case setFont = "set_font"
    /// `block` is a footnote, marked `text` in the first of `blocks`, right after the words `before`, and printed at `box`.
    case linkFootnote = "link_footnote"
  }

  var op: Op
  var block: Int?
  var blocks: [Int]?
  var role: BlockRole?
  var level: Int?
  var text: String?
  var before: String?
  /// [left, top, right, bottom], from 0 to 1000 across and down the page.
  var box: [Double]?
  var family: String?
  var degrees: Int?
  var why: String
}

/// Applies corrections to a document. Nothing the model says is taken on trust:
/// blocks it names must exist and be on the page in question, text it supplies
/// must be close to what's there unless the page really couldn't be read, and
/// a page's worth of changes that loses too much of the text is undone whole.
enum DocEditor {
  /// Fonts a block can be asked to be set in: those a stand-in may be, and that every iPad has.
  static let families = [
    "Times New Roman", "Georgia", "Palatino", "Charter", "Baskerville", "Didot", "Hoefler Text", "Cochin", "Iowan Old Style", "Bodoni 72",
    "Helvetica Neue", "Helvetica", "Arial", "Avenir Next", "Gill Sans", "Futura", "Optima", "Verdana", "Trebuchet MS", "Menlo", "Courier New", "American Typewriter",
  ]

  /// Applies `fixes`, found on `page`, and returns what was done, and what wasn't and why.
  static func apply(_ fixes: [Fix], page: Int, to doc: inout ImportedDoc, readable: Bool) -> (applied: [Fix], refused: [(Fix, String)]) {
    let before = doc
    let wordsBefore = cleanWords(doc, page: page)
    var applied: [Fix] = []
    var refused: [(Fix, String)] = []
    for fix in fixes.prefix(40) {
      if let why = apply(fix, page: page, to: &doc, readable: readable) {
        refused.append((fix, why))
      } else {
        applied.append(fix)
      }
    }
    retile(&doc)
    tidyNotes(&doc)
    // Putting a page right shouldn't take most of it away, unless the page was asked to be a picture.
    let wholesale = applied.contains { $0.op == .flattenPage }
    if !wholesale, wordsBefore > 30, cleanWords(doc, page: page) * 10 < wordsBefore * 6 {
      doc = before
      return ([], fixes.map { ($0, "These changes together would have lost most of the page’s text.") })
    }
    return (applied, refused)
  }

  /// How many words of a page the clean looks read.
  private static func cleanWords(_ doc: ImportedDoc, page: Int) -> Int {
    doc.blocks.filter { b in
      b.role != .furniture && b.role != .figure && b.role != .table && b.pieces.contains { $0.page == page }
    }.reduce(0) { $0 + $1.words }
  }

  private static func index(_ id: Int?, _ doc: ImportedDoc) -> Int? {
    guard let id else { return nil }
    return doc.blocks.firstIndex { $0.id == id }
  }

  /// A box the model drew, in points, kept within the page.
  private static func rect(_ box: [Double]?, page: Int, _ doc: ImportedDoc) -> CGRect? {
    guard let box, box.count == 4, let size = doc.pages[safe: page]?.size else { return nil }
    let r = CGRect(
      x: min(box[0], box[2]) / 1000 * size.width, y: min(box[1], box[3]) / 1000 * size.height,
      width: abs(box[2] - box[0]) / 1000 * size.width, height: abs(box[3] - box[1]) / 1000 * size.height)
    let kept = r.intersection(CGRect(origin: .zero, size: size))
    return kept.width > 4 && kept.height > 4 ? kept : nil
  }

  /// Returns why it couldn't be done, or nil once it's done.
  private static func apply(_ fix: Fix, page: Int, to doc: inout ImportedDoc, readable: Bool) -> String? {
    switch fix.op {
    case .setRole:
      guard let i = index(fix.block, doc), let role = fix.role else { return "No such block." }
      if role == .figure || role == .table || role == .equation { doc.blocks[i].pieces = doc.blocks[i].pieces.map { $0 } }
      doc.blocks[i].role = role
      if role == .heading { doc.blocks[i].level = min(max(fix.level ?? 2, 1), 4) }
      return nil

    case .setRoleLike:
      guard let i = index(fix.block, doc), let role = fix.role else { return "No such block." }
      let like = doc.blocks[i].style
      // A footnote's mark was found for it by name; that it's set like some other small print says nothing against it.
      for k in doc.blocks.indices where !doc.blocks[k].role.isPicture && (doc.blocks[k].role != .footnote || k == i) {
        let s = doc.blocks[k].style
        if s.font == like.font, abs(s.size - like.size) < 0.3, (doc.blocks[k].words < 40) == (doc.blocks[i].words < 40) {
          doc.blocks[k].role = role
          if role == .heading { doc.blocks[k].level = min(max(fix.level ?? doc.blocks[k].level, 1), 4) }
        }
      }
      return nil

    case .merge:
      guard let ids = fix.blocks, ids.count >= 2 else { return "Nothing to merge." }
      let found = ids.compactMap { index($0, doc) }
      guard found.count == ids.count, Set(ids).count == ids.count else { return "No such block." }
      let keep = found[0]
      var lines = [doc.blocks[keep].text]
      var pieces = doc.blocks[keep].pieces
      for k in found.dropFirst() {
        lines.append(doc.blocks[k].text)
        pieces += doc.blocks[k].pieces
      }
      doc.blocks[keep].text = PageText.join(lines)
      doc.blocks[keep].pieces = pieces
      // Set as most of it is set, which a bold lead-in shouldn't decide.
      if let main = found.max(by: { doc.blocks[$0].words < doc.blocks[$1].words }) { doc.blocks[keep].style = doc.blocks[main].style }
      let gone = Set(ids.dropFirst())
      doc.blocks.removeAll { gone.contains($0.id) }
      for k in doc.blocks.indices {
        if let c = doc.blocks[k].captionOf, gone.contains(c) { doc.blocks[k].captionOf = ids[0] }
      }
      return nil

    case .split:
      guard let i = index(fix.block, doc), let mark = fix.before, !mark.isEmpty, let at = doc.blocks[i].text.range(of: mark),
        at.lowerBound != doc.blocks[i].text.startIndex
      else { return "That text isn’t in the block." }
      let b = doc.blocks[i]
      let first = String(b.text[..<at.lowerBound]).trimmingCharacters(in: .whitespaces)
      let second = String(b.text[at.lowerBound...]).trimmingCharacters(in: .whitespaces)
      doc.blocks[i].text = first
      // Its marks can't be told apart any more, so the second half has no tile of its own.
      var loose = b
      loose.id = doc.nextId
      loose.text = second
      loose.role = fix.role ?? b.role
      loose.pieces = b.pieces.last.map { [BlockPiece(page: $0.page, tile: .zero, ink: $0.ink)] } ?? []
      doc.blocks.insert(loose, at: i + 1)
      return nil

    case .setText:
      guard let i = index(fix.block, doc), let text = fix.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "No such block." }
      if text.contains("$") {
        // Formulas are held to the stricter test: the words around them have to be the page's.
        guard faithful(text, to: doc.blocks[i].text) else { return "The formula can’t be set, or the words around it aren’t the page’s." }
        doc.blocks[i].math = true
      } else if readable, similarity(NoteToken.strip(doc.blocks[i].text), NoteToken.strip(text)) < 0.65 {
        // Only misreadings: a rewrite would pass off the model's words as the document's.
        return "Too far from what the page’s text says."
      }
      doc.blocks[i].text = NoteToken.restore(text, from: doc.blocks[i].text)
      return nil

    case .reorder:
      guard let ids = fix.blocks, ids.count >= 2, Set(ids).count == ids.count else { return "Nothing to reorder." }
      let slots = ids.compactMap { index($0, doc) }
      guard slots.count == ids.count else { return "No such block." }
      let blocks = slots.map { doc.blocks[$0] }
      for (slot, b) in zip(slots.sorted(), blocks) { doc.blocks[slot] = b }
      return nil

    case .drop:
      guard let i = index(fix.block, doc) else { return "No such block." }
      doc.blocks[i].role = .furniture
      return nil

    case .addFigure:
      guard let box = rect(fix.box, page: page, doc) else { return "No usable box." }
      var at = doc.blocks.firstIndex { $0.pieces.contains { $0.page == page && $0.ink.minY >= box.minY } } ?? doc.blocks.endIndex
      let id = doc.nextId
      // Labels and text wholly inside it are part of the picture now.
      for k in doc.blocks.indices where doc.blocks[k].role != .furniture {
        let b = doc.blocks[k]
        if b.pieces.count == 1, let p = b.pieces.first, p.page == page, box.insetBy(dx: -3, dy: -3).contains(p.ink) { doc.blocks[k].role = .furniture }
      }
      at = min(at, doc.blocks.endIndex)
      doc.blocks.insert(DocBlock(id: id, role: fix.role == .table ? .table : .figure, text: "", pieces: [BlockPiece(page: page, tile: .zero, ink: box)]), at: at)
      return nil

    case .setBox:
      guard let i = index(fix.block, doc), doc.blocks[i].role.isPicture, let box = rect(fix.box, page: page, doc), let p = doc.blocks[i].pieces.first else {
        return "Only pictures have boxes to set."
      }
      doc.blocks[i].pieces[0].ink = box
      _ = p
      return nil

    case .addText:
      guard let text = fix.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "No text." }
      // Only for a page that couldn't be read any other way.
      guard doc.pages[safe: page]?.unread == true || !readable else { return "This page’s text can be read directly." }
      let size = doc.pages[safe: page]?.size ?? CGSize(width: 612, height: 792)
      let box = rect(fix.box, page: page, doc) ?? CGRect(origin: .zero, size: size)
      let block = DocBlock(id: doc.nextId, role: fix.role ?? .paragraph, level: fix.level ?? 0, text: text, pieces: [BlockPiece(page: page, tile: .zero, ink: box)])
      // After whatever's already been added for the page, before the next page's.
      let after = doc.blocks.lastIndex { $0.pieces.contains { $0.page <= page } }.map { $0 + 1 } ?? 0
      doc.blocks.insert(block, at: after)
      return nil

    case .readAgain, .turnPage:
      // Taken care of by the inspector, which has the file.
      return nil

    case .flattenPage:
      guard let size = doc.pages[safe: page]?.size else { return "No such page." }
      for k in doc.blocks.indices where doc.blocks[k].pieces.contains(where: { $0.page == page }) { doc.blocks[k].role = .furniture }
      let at = doc.blocks.firstIndex { $0.pieces.contains { $0.page == page } } ?? doc.blocks.endIndex
      let whole = CGRect(origin: .zero, size: size)
      let id = doc.nextId
      doc.blocks.insert(DocBlock(id: id, role: .figure, text: "", pieces: [BlockPiece(page: page, tile: whole, ink: whole)]), at: at)
      doc.pages[page].tile = PageTile(kind: .block, rect: whole, block: id, piece: 0)
      return nil

    case .setFont:
      guard let i = index(fix.block, doc), let family = fix.family, families.contains(family) else { return "That font isn’t available." }
      let font = doc.blocks[i].style.font
      guard doc.fonts.indices.contains(font) else { return "This block’s font isn’t known." }
      doc.fonts[font].standIn = family
      return nil

    case .linkFootnote:
      return linkFootnote(fix, page: page, to: &doc)
    }
  }

  /// A footnote the device couldn't pair with its mark: on a scan, say, where nothing shows a mark is raised.
  private static func linkFootnote(_ fix: Fix, page: Int, to doc: inout ImportedDoc) -> String? {
    guard let n = index(fix.block, doc), let h = index(fix.blocks?.first, doc), n != h else { return "No such block." }
    guard let label = fix.text.flatMap(MarkLabel.normal) else { return "That’s not a footnote’s mark." }
    guard let words = fix.before, !words.isEmpty, let at = doc.blocks[h].text.range(of: words) else { return "Those words aren’t in the block." }
    guard !doc.blocks[n].role.isPicture, !doc.blocks[h].role.isPicture else { return "A picture can’t hold a footnote." }
    var text = doc.blocks[h].text
    // What's printed for the mark, if the text read it, gives way to the mark.
    var end = at.upperBound
    let printed = [fix.text ?? "", PageText.scripted(label, 1), label]
    for form in printed where !form.isEmpty && text[end...].hasPrefix(form) {
      text.removeSubrange(end..<text.index(end, offsetBy: form.count))
      end = at.upperBound
      break
    }
    text.insert(contentsOf: NoteToken.make(doc.blocks[n].id), at: end)
    doc.blocks[h].text = text
    doc.blocks[n].role = .footnote
    doc.blocks[n].mark = label
    // The same, off the front of what the note says.
    var note = doc.blocks[n].text
    for form in printed where !form.isEmpty && note.hasPrefix(form) {
      note = String(note.dropFirst(form.count)).trimmingCharacters(in: CharacterSet(charactersIn: " .):"))
      break
    }
    doc.blocks[n].text = note
    if let size = doc.pages[safe: page]?.size, let b = fix.box, b.count == 4 {
      let box = CGRect(
        x: min(b[0], b[2]) / 1000 * size.width, y: min(b[1], b[3]) / 1000 * size.height,
        width: abs(b[2] - b[0]) / 1000 * size.width, height: abs(b[3] - b[1]) / 1000 * size.height)
      doc.marks.append(PrintedMark(note: doc.blocks[n].id, page: page, box: box))
    }
    return nil
  }

  /// Keeps marks and notes answering each other, whatever corrections did to
  /// either: a footnote nothing leads to is small print again, so it can still
  /// be read, and a mark whose note has gone is what was printed, or nothing.
  static func tidyNotes(_ doc: inout ImportedDoc) {
    var labels: [Int: String] = [:]
    for b in doc.blocks where b.mark != nil && (b.role != .furniture) { labels[b.id] = b.mark }
    var led = Set<Int>()
    for i in doc.blocks.indices where doc.blocks[i].text.contains("[^") {
      let ids = NoteToken.ids(doc.blocks[i].text)
      guard !ids.isEmpty else { continue }
      if ids.contains(where: { labels[$0] == nil }) {
        doc.blocks[i].text = NoteToken.parts(doc.blocks[i].text).map { part in
          switch part {
          case let .text(s): return s
          case let .mark(id): return labels[id] != nil ? NoteToken.make(id) : ""
          }
        }.joined()
      }
      led.formUnion(ids.filter { labels[$0] != nil })
    }
    // A mark in a table is printed there, and tapped there, and in no text.
    led.formUnion(doc.marks.map(\.note).filter { labels[$0] != nil })
    for i in doc.blocks.indices where doc.blocks[i].mark != nil && !led.contains(doc.blocks[i].id) {
      if doc.blocks[i].role == .footnote { doc.blocks[i].role = .note }
      doc.blocks[i].mark = nil
    }
    // Set as a footnote with nothing to say which: only `link_footnote` can make one.
    for i in doc.blocks.indices where doc.blocks[i].role == .footnote && doc.blocks[i].mark == nil { doc.blocks[i].role = .note }
    doc.marks.removeAll { !led.contains($0.note) }
  }

  /// Whether a transcription is the same paragraph: every formula can be set, and
  /// outside the formulas it has the words the page has, in that order, and nothing else.
  static func faithful(_ text: String, to original: String) -> Bool {
    guard !text.isEmpty, text.filter({ $0 == "$" }).count % 2 == 0 else { return false }
    let parts = text.components(separatedBy: "$")
    for (i, part) in parts.enumerated() where i % 2 == 1 {
      // A note's mark goes outside its formula, where it can be tapped.
      if part.isEmpty || part.count > 400 || part.contains("[^") || !TeX.supports(part) { return false }
    }
    let prose = parts.enumerated().filter { $0.offset % 2 == 0 }.map(\.element).joined(separator: " ")
    func words(_ s: String) -> [Substring] { s.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 3 } }
    let ours = words(prose)
    let theirs = words(original)
    guard !theirs.isEmpty else { return true }
    // Nothing added: what it says outside formulas was on the page.
    let known = Set(theirs)
    let added = ours.filter { !known.contains($0) }.count
    if Double(added) > Double(max(ours.count, 1)) * 0.06 { return false }
    // Nothing lost: most of what the page says is still there. Words in formulas may have gone into them.
    let kept = Set(ours)
    let lost = theirs.filter { !kept.contains($0) && !text.lowercased().contains($0) }.count
    return Double(lost) <= Double(theirs.count) * 0.06
  }

  /// How alike two texts are, by the words they share, from 0 to 1.
  static func similarity(_ a: String, _ b: String) -> Double {
    func tally(_ s: String) -> [Substring: Int] {
      var t: [Substring: Int] = [:]
      for w in s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) { t[w, default: 0] += 1 }
      return t
    }
    let (x, y) = (tally(a), tally(b))
    let total = max(x.values.reduce(0, +), y.values.reduce(0, +))
    guard total > 0 else { return 1 }
    let shared = x.reduce(0) { $0 + min($1.value, y[$1.key] ?? 0) }
    return Double(shared) / Double(total)
  }

  /// Makes every page's tiles name the blocks that now occupy them, after blocks have merged, split or gone.
  static func retile(_ doc: inout ImportedDoc) {
    var owners: [String: (id: Int, piece: Int)] = [:]
    func key(_ page: Int, _ r: CGRect) -> String { "\(page)/\(r.minX)/\(r.minY)/\(r.width)/\(r.height)" }
    for b in doc.blocks {
      for (n, p) in b.pieces.enumerated() where p.tile.width > 0 { owners[key(p.page, p.tile)] = (b.id, n) }
    }
    func walk(_ t: PageTile, _ page: Int) -> PageTile {
      var out = t
      if let kids = t.kids {
        out.kids = kids.map { walk($0, page) }
      } else if let o = owners[key(page, t.rect)] {
        out.kind = .block
        out.block = o.id
        out.piece = o.piece
      } else {
        out.kind = .blank
        out.block = nil
        out.piece = nil
      }
      return out
    }
    for i in doc.pages.indices { doc.pages[i].tile = walk(doc.pages[i].tile, i) }
  }
}
