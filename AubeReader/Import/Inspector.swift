import PDFKit
import UIKit

// ─── Looking over an import ──────────────────────────────────────────────────

/// Has the model look at what an import made of a document, the way a person
/// would: the original page beside the page as the reader shows it. It says
/// what's wrong and how to put it right, the corrections are made, and the pages
/// it changed are looked at again, a few times at most.
///
/// Reading the document never depends on this. It can be opened before this
/// starts, and if there's no key, no connection, or checks are turned off, it
/// stays as the device read it.
@MainActor
final class Inspector {
  private var doc: ImportedDoc
  private let file: URL
  private let say: (String, Double) -> Void
  private let improved: (ImportedDoc) -> Void

  /// How many pages of a long document get looked at. The first page or two says
  /// most about how it's set; the corrections can reach pages that aren't looked at.
  private static let pageBudget = 24
  private static let rounds = 3
  private nonisolated static let lanes = 3

  init(_ doc: ImportedDoc, file: URL, say: @escaping (String, Double) -> Void, onImproved: @escaping (ImportedDoc) -> Void) {
    self.doc = doc
    self.file = file
    self.say = say
    improved = onImproved
  }

  func run() async -> ImportedDoc {
    doc.report = ImportReport()
    guard Store.checkImports else { return finish(.skipped, why: "Checking imports is turned off in Settings.") }
    guard OpenAI.key != nil else { return finish(.skipped, why: "There’s no API key, so the model couldn’t look it over.") }
    do {
      say("Understanding it", 0.02)
      try await understand()
      if doc.flowing { return finish(.checked, why: nil) }
      try await readMath()

      var pages = choosePages()
      let total = pages.count
      var unresolved: [Int: [String]] = [:]
      var seen = Set<Int>()
      for round in 1...Self.rounds where !pages.isEmpty {
        doc.report.rounds = round
        let found = try await look(at: pages, round: round, of: total)
        seen.formUnion(pages)
        // Corrections go in one page at a time, against the document as it then stands.
        var next = Set<Int>()
        unresolved = unresolved.filter { !pages.contains($0.key) }
        for (page, verdict) in found.sorted(by: { $0.key < $1.key }) {
          let serious = verdict.problems.filter(\.serious).map(\.what)
          if !serious.isEmpty { unresolved[page] = serious }
          // A page read afresh has new blocks, so nothing else said about the old ones still applies.
          if let turn = verdict.fixes.first(where: { $0.op == .turnPage }) {
            await readAgain(page, turning: turn.degrees ?? 0)
            next.insert(page)
            continue
          }
          if verdict.fixes.contains(where: { $0.op == .readAgain }) {
            await readAgain(page, turning: 0)
            next.insert(page)
            continue
          }
          let fixes = verdict.fixes.map { snapped($0, page: page) }
          let (applied, refused) = DocEditor.apply(fixes, page: page, to: &doc, readable: isReadable(page))
          for f in applied { doc.report.notes.append(ImportNote(page: page, said: f.why, fixed: true)) }
          for (f, why) in refused { doc.report.notes.append(ImportNote(page: page, said: "\(f.why) (\(why))", fixed: false)) }
          if !applied.isEmpty { next.insert(page) }
        }
        doc.report.pagesChecked = seen.count
        improved(stamped())
        pages = Array(next).sorted()
      }
      // What the last look at each page still found wrong.
      for (page, list) in unresolved {
        for what in list { doc.report.notes.append(ImportNote(page: page, said: what, fixed: false)) }
      }
      return finish(unresolved.isEmpty ? .checked : .flagged, why: nil)
    } catch is CancellationError {
      return doc
    } catch {
      return finish(.skipped, why: "The model couldn’t look it over: \(error.localizedDescription)")
    }
  }

  private func stamped() -> ImportedDoc {
    var d = doc
    d.report.state = .pending
    return d
  }

  private func finish(_ state: ImportReport.State, why: String?) -> ImportedDoc {
    doc.report.state = state
    doc.report.why = why
    return doc
  }

  /// Whether a page's own text can be believed, so corrections to it have to stay near what it says.
  private func isReadable(_ page: Int) -> Bool {
    guard let p = doc.pages[safe: page] else { return true }
    return !p.scanned && !p.unread
  }

  /// Every page of a short document. Of a long one, the first ones, the last ones,
  /// any that couldn't be read, and an even spread of the rest.
  private func choosePages() -> [Int] {
    let n = doc.pages.count
    guard n > Self.pageBudget else { return Array(0..<n) }
    var chosen = Set(0..<8)
    chosen.formUnion((n - 2)..<n)
    for (i, p) in doc.pages.enumerated() where p.unread && chosen.count < Self.pageBudget { chosen.insert(i) }
    var k = 8
    let step = max(1, (n - 10) / max(1, Self.pageBudget - chosen.count))
    while chosen.count < Self.pageBudget, k < n - 2 {
      chosen.insert(k)
      k += step
    }
    return chosen.sorted()
  }

  // ─── What it is ──────────────────────────────────────────────────────────

  private struct Meta: Codable {
    var title: String
    var authors: [String]
    var field: String
    var language: String?
    var kind: String
    var why: String
  }

  /// One look at the document as a whole: what it's called, who wrote it, what it's about.
  private func understand() async throws {
    var parts: [OpenAI.Part] = []
    if !doc.flowing {
      for page in 0..<min(2, doc.pages.count) {
        if let plain = await Proof.original(doc, file: file, page: page) { parts.append(.jpeg(plain)) }
      }
    }
    let opening = doc.blocks.filter { $0.role != .furniture }.prefix(40).map { b in
      "#\(b.id) \(b.role.rawValue): \(String(NoteToken.strip(b.text).prefix(240)))"
    }.joined(separator: "\n")
    parts.append(.text("The document's file is called \"\(doc.fileName)\". It has \(doc.pages.count) pages. Its opening, as read:\n\n\(opening)"))
    let data = try await OpenAI.answer(
      system: Self.metaBriefing, parts, schemaName: "document", schema: Self.metaSchema, effort: "low")
    let meta = try JSONDecoder().decode(Meta.self, from: data)
    if !meta.title.isEmpty { doc.title = meta.title }
    doc.authors = meta.authors
    doc.field = meta.field
    if let l = meta.language, !l.isEmpty { doc.language = l }
    doc.report.kind = meta.kind
    improved(stamped())
  }

  private static let metaBriefing = """
    You identify a document for a reading app, from pictures of its first pages and the text read from them. Give its \
    real title as a reader would cite it (not a journal's name, a running head, or a file name), the names of its authors \
    in order (people or organizations; none if it doesn't say), the field it belongs to in a few words (such as "behavioural \
    ecology" or "consumer tax forms"), its language as a BCP 47 tag, and what kind of document it is.
    """

  private static let metaSchema: [String: Any] = [
    "type": "object", "additionalProperties": false,
    "required": ["title", "authors", "field", "language", "kind", "why"],
    "properties": [
      "title": ["type": "string"],
      "authors": ["type": "array", "items": ["type": "string"]],
      "field": ["type": "string"],
      "language": ["type": ["string", "null"]],
      "kind": ["type": "string", "enum": ["paper", "article", "magazine", "report", "book", "slides", "form", "letter", "manual", "other"]],
      "why": ["type": "string"],
    ],
  ]

  // ─── The math ────────────────────────────────────────────────────────────

  private struct Formulas: Codable {
    struct Paragraph: Codable {
      var block: Int
      var text: String
    }
    var paragraphs: [Paragraph]
  }

  /// A paragraph with math in it reads badly from a PDF's characters: the parts of a
  /// fraction out of order, a root sign in the next word, a sum's limits run together.
  /// So the model reads those paragraphs from the picture of the page, writing their
  /// formulas in TeX, and the app's own engine sets them. It's only taken at its word
  /// where its prose matches the page's, and the engine can set every formula it wrote.
  private func readMath() async throws {
    let targets = doc.blocks.filter { b in
      guard b.mathy, !b.math, let head = b.pieces.first, head.page >= 0 else { return false }
      switch b.role {
      case .paragraph, .abstract, .list, .quote, .note, .footnote, .caption, .heading, .minor: return true
      default: return false
      }
    }
    guard !targets.isEmpty else { return }
    let byPage = Array(Dictionary(grouping: targets) { $0.pieces[0].page }.sorted { $0.key < $1.key }.prefix(Self.mathPages))
    var written = 0
    var refused = 0
    var done = 0
    var next = byPage.makeIterator()
    try await withThrowingTaskGroup(of: Formulas?.self) { group in
      var running = 0
      func start() {
        while running < Self.lanes, let (page, blocks) = next.next() {
          running += 1
          group.addTask { @MainActor in
            do {
              return try await self.formulas(on: page, blocks)
            } catch is CancellationError {
              throw CancellationError()
            } catch {
              return nil
            }
          }
        }
      }
      start()
      while let found = try await group.next() {
        running -= 1
        done += 1
        say("Reading the math", 0.02 + 0.03 * Double(done) / Double(max(byPage.count, 1)))
        for p in found?.paragraphs ?? [] {
          guard let i = doc.blocks.firstIndex(where: { $0.id == p.block }), doc.blocks[i].mathy else { continue }
          let text = NoteToken.restore(p.text.trimmingCharacters(in: .whitespacesAndNewlines), from: doc.blocks[i].text)
          if DocEditor.faithful(text, to: NoteToken.strip(doc.blocks[i].text)) {
            doc.blocks[i].text = text
            doc.blocks[i].math = text.contains("$")
            written += 1
          } else {
            refused += 1
          }
        }
        start()
      }
    }
    if written > 0 { doc.report.notes.append(ImportNote(page: nil, said: "Formulas in \(written) paragraphs were read from the page and set as TeX.", fixed: true)) }
    if refused > 0 { doc.report.notes.append(ImportNote(page: nil, said: "\(refused) paragraphs keep their formulas as the PDF had them: what was read for them couldn’t be trusted.", fixed: false)) }
    improved(stamped())
  }

  private func formulas(on page: Int, _ blocks: [DocBlock]) async throws -> Formulas {
    var pages = [page]
    for b in blocks { for p in b.pieces where !pages.contains(p.page) { pages.append(p.page) } }
    var parts: [OpenAI.Part] = []
    for p in pages.prefix(3) {
      if let picture = await Proof.original(doc, file: file, page: p) {
        parts.append(.text("Page \(p + 1):"))
        parts.append(.jpeg(picture))
      }
    }
    let list = blocks.map { "#\($0.id): \($0.text)" }.joined(separator: "\n\n")
    parts.append(.text("The paragraphs, as the PDF's characters read:\n\n\(list)"))
    let data = try await OpenAI.answer(system: Self.mathBriefing, parts, schemaName: "formulas", schema: Self.mathSchema, effort: "low")
    return try JSONDecoder().decode(Formulas.self, from: data)
  }

  /// How many pages of a long document get their math read.
  private static let mathPages = 40

  private static let mathBriefing = """
    You transcribe paragraphs from pages of a document for a reading app, which sets formulas with its own TeX engine. You \
    get pictures of the pages and each paragraph's text as read from the PDF's characters. That text is right about the words \
    but scrambles math: the parts of a fraction out of order, a root sign stuck in the next word, a sum's limits run together.

    Give back each paragraph that has math in it, using the picture as the authority for the math:
    - Keep every word outside a formula exactly as given, in the same order. Don't reword, correct, shorten or complete \
    anything. Keep citations as they are, and keep a mark like [^12], which opens a footnote, exactly where it stands, outside any formula.
    - Write every formula, however small, between single dollar signs, in TeX: a lone variable $x$, $d_k$, $\\sqrt{d_k}$, \
    $\\frac{1}{\\sqrt{d_k}}$, $q_\\phi(z|x)$, $\\sum_{i=1}^{N}$. A number with a unit isn't a formula unless it's set as one.
    - Use only these commands: Greek letters, \\frac, \\sqrt, \\sum, \\prod, \\int, \\log, \\exp, \\min, \\max, \\sup, \\inf, \\lim, \\sin, \\cos, \\tan, \\mathrm, \\mathbf, \\mathcal, \\mathbb, \\text, \\hat, \\bar, \\tilde, \\vec, \\dot, \\ddot, \
    \\leq, \\geq, \\neq, \\approx, \\sim, \\equiv, \\propto, \\in, \\notin, \\subset, \\cup, \\cap, \\times, \\cdot, \\pm, \\to, \\rightarrow, \\Rightarrow, \\infty, \\partial, \\nabla, \
    \\ldots, \\cdots, \\ell, \\hbar, \\odot, \\top, \\langle, \\rangle, \\quad, \\left, \\right. Nothing else: no environments, \\begin or \\\\.
    - A dollar sign that means money isn't allowed in a formula: leave paragraphs with prices out unless the math is clear.

    Leave out any paragraph with no real math in it. Use the number each paragraph is given.
    """

  private static let mathSchema: [String: Any] = [
    "type": "object", "additionalProperties": false,
    "required": ["paragraphs"],
    "properties": [
      "paragraphs": [
        "type": "array",
        "items": [
          "type": "object", "additionalProperties": false,
          "required": ["block", "text"],
          "properties": ["block": ["type": "integer"], "text": ["type": "string"]],
        ],
      ]
    ],
  ]

  // ─── Pictures, exactly ───────────────────────────────────────────────────

  /// A box the model drew is only as good as its eye. Marks and text around it on
  /// the page say exactly where a figure ends, so it's fitted to them.
  private func snapped(_ fix: Fix, page: Int) -> Fix {
    guard fix.op == .addFigure || fix.op == .setBox, let box = fix.box, box.count == 4, let size = doc.pages[safe: page]?.size, !doc.flowing,
      let p = PDFDocument(url: file)?.page(at: page)
    else { return fix }
    let raw = PageReader.read(p, index: page, catalog: FontCatalog())
    let r = CGRect(
      x: min(box[0], box[2]) / 1000 * size.width, y: min(box[1], box[3]) / 1000 * size.height,
      width: abs(box[2] - box[0]) / 1000 * size.width, height: abs(box[3] - box[1]) / 1000 * size.height)
    // Strokes just over its edge are part of it. Text only counts where the box takes it in,
    // since a line just past a formula is the next line of the paragraph.
    let wide = r.insetBy(dx: -size.width * 0.02, dy: -size.height * 0.02)
    func strokes(_ m: CGRect) -> Bool { wide.contains(CGPoint(x: m.midX, y: m.midY)) }
    func words(_ m: CGRect) -> Bool { r.contains(CGPoint(x: m.midX, y: m.midY)) }
    var fitted: CGRect?
    for m in (raw.marks.map(\.rect) + raw.rules + raw.sideways).filter(strokes) + raw.runs.map(\.rect).filter(words) {
      fitted = fitted?.union(m) ?? m
    }
    guard let fitted, fitted.width > 8, fitted.height > 8 else { return fix }
    var out = fix
    out.box = [fitted.minX / size.width * 1000, fitted.minY / size.height * 1000, fitted.maxX / size.width * 1000, fitted.maxY / size.height * 1000]
    return out
  }

  // ─── Each page ───────────────────────────────────────────────────────────

  private struct Verdict: Codable {
    struct Trouble: Codable {
      var what: String
      var serious: Bool
    }
    var verdict: String
    var problems: [Trouble]
    var fixes: [Fix]
  }

  private func look(at pages: [Int], round: Int, of total: Int) async throws -> [Int: Verdict] {
    var found: [Int: Verdict] = [:]
    let book = ImportedBook(doc, file: file)
    var next = pages.makeIterator()
    var done = 0
    try await withThrowingTaskGroup(of: (Int, Verdict?).self) { group in
      var running = 0
      func start() {
        while running < Self.lanes, let page = next.next() {
          running += 1
          group.addTask { @MainActor in
            do {
              return (page, try await self.inspect(page, book: book, round: round))
            } catch is CancellationError {
              throw CancellationError()
            } catch let e as OpenAI.Failure {
              // One page failing shouldn't sink the rest, unless the key itself is bad, which they'd all hit.
              if e.errorDescription?.lowercased().contains("api key") == true { throw e }
              return (page, nil)
            } catch {
              return (page, nil)
            }
          }
        }
      }
      start()
      while let (page, verdict) = try await group.next() {
        running -= 1
        done += 1
        if let verdict { found[page] = verdict }
        let share = 0.05 + 0.9 * Double(done) / Double(max(pages.count, 1))
        say(round == 1 ? "Checking page \(page + 1) of \(doc.pages.count)" : "Checking what changed", share)
        start()
      }
    }
    return found
  }

  private func inspect(_ page: Int, book: ImportedBook, round: Int) async throws -> Verdict {
    var parts: [OpenAI.Part] = []
    let unread = doc.pages[safe: page]?.unread == true
    guard let original = await Proof.marked(doc, file: file, page: page) else { throw OpenAI.Failure(errorDescription: "The page wouldn’t draw.") }
    parts.append(.text("IMAGE 1: original page \(page + 1) of \(doc.pages.count), with a numbered box around each block that was found. The ticks along the edges count from 0 to 1000 across and down."))
    parts.append(.jpeg(original))
    if !unread, let clean = await Proof.clean(book, page: page) {
      parts.append(.text("IMAGE 2: the same blocks as the reader's clean Paper look sets them, each marked with its number in the left margin. Furniture is left out on purpose. Figures, tables and equations are pictures cut from the page."))
      parts.append(.jpeg(clean))
    }
    if !unread, page == firstProsePage || page == middleProsePage, let typeset = await Proof.typeset(book, page: page) {
      parts.append(.text("IMAGE 3: the Magazine look, which keeps the original layout, with every paragraph set live in the nearest font this device has, as happens when a reader changes one. It only needs to read as the same page: similar type, sizes and positions. Each paragraph is simply drawn where the original began, with nothing moved to make room: in the reader what's below it moves down, so text running into what's beneath it here isn't a problem."))
      parts.append(.jpeg(typeset))
    }
    let table = doc.blocks.filter { $0.pieces.contains { $0.page == page } }.map { b -> String in
      let cont = b.pieces.count > 1 ? " (runs across \(b.pieces.count) places)" : ""
      let level = b.role == .heading ? " level \(b.level)" : b.role == .footnote ? " marked \(b.mark ?? "?")" : ""
      let text = b.text.count > 260 ? "\(b.text.prefix(170)) … \(b.text.suffix(80))" : b.text
      return "#\(b.id) \(b.role.rawValue)\(level)\(cont): \(text)"
    }.joined(separator: "\n")
    var note = "The blocks on this page, in the order the reader shows them:\n\n\(table.isEmpty ? "(none found)" : table)"
    if unread {
      note += "\n\nNo text could be read from this page on the device. Transcribe it from the picture with add_text fixes, in reading order, one per paragraph, exactly as written, keeping its language."
    } else if doc.pages[safe: page]?.scanned == true {
      note += "\n\nThis page's text came from reading its picture on the device, which can go badly wrong, especially outside the Latin script. Mend small misreadings with set_text. If a block is mostly wrong, or text on the page is missing from the blocks, drop what's wrong and transcribe the page's text with add_text, in reading order, exactly as written, keeping its language."
    }
    if round > 1 { note += "\n\nCorrections have already been made to this page. Report only what is still wrong." }
    parts.append(.text(note))
    let data = try await OpenAI.answer(system: Self.pageBriefing, parts, schemaName: "page_check", schema: Self.pageSchema, effort: "low")
    return try JSONDecoder().decode(Verdict.self, from: data)
  }

  private var firstProsePage: Int? { doc.blocks.first { ImportedBook.rewritable($0) }?.pieces.first?.page }
  private var middleProsePage: Int? {
    let prose = doc.blocks.filter { ImportedBook.rewritable($0) }
    return prose[safe: prose.count / 2]?.pieces.first?.page
  }

  /// Reads a page again from its picture, and puts what's found in place of what was there.
  private func readAgain(_ page: Int, turning: Int) async {
    let (doc, file) = (self.doc, self.file)
    let already = doc.pages[safe: page]?.turn ?? 0
    let total = ((already + turning) % 360 + 360) % 360
    let fresh: ImportedDoc? = await Task.detached(priority: .userInitiated) {
      guard let pdf = PDFDocument(url: file), let p = pdf.page(at: page) else { return nil }
      p.rotation = (p.rotation + total) % 360
      let catalog = FontCatalog()
      var raw = PageReader.read(p, index: 0, catalog: catalog)
      raw.turn = (raw.turn + total) % 360
      guard let picture = PagePicture.make(p, pixels: 2200) else { return nil }
      raw.runs = []
      PageOCR.read(&raw, picture: picture, plain: catalog.stand(FontNames.record("", flags: 2, weight: 0, angle: 0)))
      ScanFigures.find(&raw, picture: picture)
      let measure = DocMeasure.of([raw])
      let layout = PageAnalyzer.analyze(raw, measure: measure, fonts: catalog.fonts)
      return Structure.document(
        id: doc.id, fileName: doc.fileName, pages: [raw], layouts: [layout], fonts: catalog.fonts, measure: measure, metaTitle: nil, metaAuthor: nil)
    }.value
    guard var fresh, let sheet = fresh.pages.first else {
      self.doc.report.notes.append(ImportNote(page: page, said: "Reading the page again from its picture didn’t work.", fixed: false))
      return
    }
    // Its blocks in place of the page's old ones, under new numbers, with fonts of their own.
    let base = self.doc.nextId
    let fontBase = self.doc.fonts.count
    self.doc.fonts += fresh.fonts
    fresh.blocks = fresh.blocks.map { b in
      var b = b
      b.id += base
      b.text = NoteToken.shift(b.text, by: base)
      b.captionOf = b.captionOf.map { $0 + base }
      b.style.font = b.style.font >= 0 ? b.style.font + fontBase : -1
      b.pieces = b.pieces.map { p in
        var p = p
        p.page = page
        return p
      }
      if b.role == .title || b.role == .byline { b.role = .heading; b.level = 1 }
      return b
    }
    let at = self.doc.blocks.firstIndex { $0.pieces.contains { $0.page == page } } ?? self.doc.blocks.endIndex
    self.doc.blocks.removeAll { b in b.pieces.allSatisfy { $0.page == page } }
    self.doc.blocks.insert(contentsOf: fresh.blocks, at: min(at, self.doc.blocks.endIndex))
    self.doc.marks += fresh.marks.map { PrintedMark(note: $0.note + base, page: page, box: $0.box) }
    // Notes on that page may have gone, with what led to them.
    DocEditor.tidyNotes(&self.doc)
    var replacement = sheet
    func renumber(_ t: PageTile) -> PageTile {
      var t = t
      t.kids = t.kids?.map(renumber)
      t.block = t.block.map { $0 + base }
      return t
    }
    replacement.tile = renumber(sheet.tile)
    replacement.scanned = true
    self.doc.pages[page] = replacement
    self.doc.report.notes.append(ImportNote(page: page, said: "The page’s text was unusable, so it was read again from its picture.", fixed: true))
  }

  private static let pageBriefing = """
    You are the last check in a reading app's PDF import. A page has been analyzed on the device into numbered blocks, each \
    with a role, and set in the app's own clean reading layout. Compare the original page with the result and decide whether \
    a reader would get what the page says, in the right order, with nothing important lost or mangled.

    Look for these, and only these:
    - Text in the wrong order: columns read across each other; a block before what it follows.
    - One paragraph cut in two, or two run together.
    - Wrong roles: a heading set as a paragraph or the reverse; a caption, footnote, or page furniture (running heads, page \
    numbers, journal mastheads, repeated footers) read as part of the text.
    - A figure or table missed, cut off, or with too much around it, so its picture in the clean layout is wrong; or a table \
    read as loose scraps of text.
    - Garbled text: letters that don't match the page, in a block's text or the clean layout.
    - Text on the page that's nowhere in the blocks and isn't furniture.

    Text between dollar signs is a formula in TeX, which the reader typesets; check that it says what the page says, and correct \
    it with set_text if it doesn't. Displayed equations are pictures cut from the page: check that none is cut off.

    The roles: title, byline (authors and affiliations), abstract, heading (level 1 is largest), paragraph, list, quote, note \
    (small print nothing in the text leads to), footnote, caption, figure, table, equation, code, references, furniture (not \
    part of the text), minor (a short label or scrap).

    The reader never sets a footnote among the text. Its mark, written [^n] in the text of the block it's in (n being the \
    footnote's own block number), shows as a small mark a reader taps to open the note in place. So a footnote left out of \
    IMAGE 2 and IMAGE 3, and missing from the foot of the page in them, isn't a problem, and neither is a page number left out. \
    What is a problem: small print at the foot of a page, or a mark like it in the text, that the reader has not joined up (use \
    link_footnote), or a footnote found where there isn't one (use set_role to put it back: its mark then goes back too). Never \
    change or remove a [^n] in a set_text; say what's wrong with it instead.

    Fixes are applied by machine, so be exact:
    - set_role: block, role, and level for a heading.
    - set_role_like: as set_role, for every block set in the same type as this one throughout the document. Use it when \
    you can see the mistake is systematic: it reaches pages you aren't shown.
    - merge: blocks, in reading order, become one. For one paragraph cut in two.
    - split: block, and before, the exact words that start the second part.
    - set_text: block, and its text, only to mend misread characters or formulas. Never reword, summarize or complete \
    anything. A formula goes between dollar signs, in TeX, using only: Greek letters, \\frac, \\sqrt, \\sum, \\prod, \\int, \\log, \\exp, \\min, \\max, \
    \\mathrm, \\mathbf, \\mathcal, \\mathbb, \\text, \\hat, \\bar, \\tilde, \\vec, \\leq, \\geq, \\neq, \\approx, \\sim, \\in, \\times, \\cdot, \\pm, \\to, \\infty, \\partial, \\nabla, \\ldots.
    - reorder: blocks, in the order they should read.
    - drop: block isn't part of the text. Marks it furniture.
    - add_figure: a figure or table nobody found. box and role (figure or table).
    - set_box: block, a figure, table or equation, should cover box instead.
    - add_text: only if told this page couldn't be read. text, role, box.
    - read_again: the page's text is nonsense, so read it again from its picture.
    - turn_page: the page itself is sideways or upside down. degrees clockwise to bring it upright: 90, 180 or 270.
    - flatten_page: the page is a form, or too intricate to read as flowing text. It's then shown whole, as a picture.
    - set_font: block's type is badly matched in IMAGE 3. family, from: \(DocEditor.families.joined(separator: ", ")).
    - link_footnote: block is a footnote at the foot of this page that has no [^n] leading to it. blocks holds just the one block \
    whose text has its mark. before is the exact words of that block's text that come just before the mark. text is the mark as \
    printed: 3, *, †. box is around the printed mark.
    A box is [left, top, right, bottom], from 0 to 1000 across and down the page, by the ticks along its edges.

    Be conservative. Differences of type, spacing and styling between the two images are the whole point of the clean layout, \
    and aren't problems. A headline or chart label set differently is fine. If the page is fine, say verdict "good" with no \
    problems and no fixes. Mark a problem serious only if it would mislead a reader or lose content. Give each fix a short \
    reason in plain words, for the document's report. Write the reason in English.
    """

  private static let pageSchema: [String: Any] = [
    "type": "object", "additionalProperties": false,
    "required": ["verdict", "problems", "fixes"],
    "properties": [
      "verdict": ["type": "string", "enum": ["good", "minor", "bad"]],
      "problems": [
        "type": "array",
        "items": [
          "type": "object", "additionalProperties": false,
          "required": ["what", "serious"],
          "properties": ["what": ["type": "string"], "serious": ["type": "boolean"]],
        ],
      ],
      "fixes": [
        "type": "array",
        "items": [
          "type": "object", "additionalProperties": false,
          "required": ["op", "block", "blocks", "role", "level", "text", "before", "box", "family", "degrees", "why"],
          "properties": [
            "op": ["type": "string", "enum": Fix.Op.allCases.map(\.rawValue)],
            "block": ["type": ["integer", "null"]],
            "blocks": ["type": ["array", "null"], "items": ["type": "integer"]],
            "role": ["type": ["string", "null"], "enum": BlockRole.allCases.map(\.rawValue) + [NSNull()]],
            "level": ["type": ["integer", "null"]],
            "text": ["type": ["string", "null"]],
            "before": ["type": ["string", "null"]],
            "box": ["type": ["array", "null"], "items": ["type": "number"]],
            "family": ["type": ["string", "null"]],
            "degrees": ["type": ["integer", "null"]],
            "why": ["type": "string"],
          ],
        ],
      ],
    ],
  ]
}

// ─── What the model is shown ─────────────────────────────────────────────────

/// Pictures for the model to look at, drawn with the reader's own code, so that
/// what it checks is what a reader would see.
@MainActor
enum Proof {
  private static let wide = 1224

  private static func atlas(_ doc: ImportedDoc, _ file: URL) -> PageAtlas { PageAtlas(url: file, pages: doc.pages) }

  private static func jpeg(_ image: UIImage) -> Data? { image.jpegData(compressionQuality: 0.72) }

  private static let light = UITraitCollection {
    $0.userInterfaceStyle = .light
    $0.displayScale = 1
  }

  /// Just the page.
  static func original(_ doc: ImportedDoc, file: URL, page: Int) async -> Data? {
    guard let image = await atlas(doc, file).picture(PageAtlas.Key(page: page, pixels: wide, dark: false, crop: nil)) else { return nil }
    return jpeg(UIImage(cgImage: image))
  }

  /// The page, with every block outlined and numbered, and ticks along its edges to read positions by.
  static func marked(_ doc: ImportedDoc, file: URL, page: Int) async -> Data? {
    guard let info = doc.pages[safe: page], info.size.width > 0,
      let image = await atlas(doc, file).picture(PageAtlas.Key(page: page, pixels: wide, dark: false, crop: nil))
    else { return nil }
    let size = CGSize(width: image.width, height: image.height)
    let s = size.width / info.size.width
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let drawn = UIGraphicsImageRenderer(size: size, format: format).image { r in
      UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
      let ctx = r.cgContext
      for b in doc.blocks {
        for piece in b.pieces where piece.page == page {
          let color = roleColor(b.role)
          let box = CGRect(x: piece.ink.minX * s, y: piece.ink.minY * s, width: piece.ink.width * s, height: piece.ink.height * s)
          ctx.setStrokeColor(color.cgColor)
          ctx.setLineWidth(b.role == .furniture ? 1 : 1.5)
          ctx.stroke(box)
          let tag = NSAttributedString(string: " \(b.id) ", attributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.white, .backgroundColor: color])
          tag.draw(at: CGPoint(x: max(0, box.minX), y: max(0, box.minY - 15)))
        }
      }
      // Ticks every hundred, numbered.
      let tick: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.systemRed]
      ctx.setStrokeColor(UIColor.systemRed.cgColor)
      ctx.setLineWidth(1)
      for k in stride(from: 0, through: 1000, by: 100) {
        let x = size.width * CGFloat(k) / 1000
        let y = size.height * CGFloat(k) / 1000
        ctx.stroke(CGRect(x: x, y: 0, width: 0.5, height: 8))
        ctx.stroke(CGRect(x: 0, y: y, width: 8, height: 0.5))
        ("\(k)" as NSString).draw(at: CGPoint(x: min(x + 2, size.width - 28), y: 8), withAttributes: tick)
        ("\(k)" as NSString).draw(at: CGPoint(x: 10, y: min(y, size.height - 14)), withAttributes: tick)
      }
    }
    return jpeg(drawn)
  }

  private static func roleColor(_ role: BlockRole) -> UIColor {
    switch role {
    case .title, .heading: return UIColor(red: 0.85, green: 0, blue: 0.45, alpha: 1)
    case .paragraph, .abstract, .quote: return UIColor(red: 0, green: 0.3, blue: 0.9, alpha: 1)
    case .figure, .table, .equation, .code: return UIColor(red: 0, green: 0.55, blue: 0.1, alpha: 1)
    case .caption, .note, .footnote, .references, .list, .byline: return UIColor(red: 0.75, green: 0.42, blue: 0, alpha: 1)
    case .furniture, .minor: return UIColor(white: 0.5, alpha: 1)
    }
  }

  /// One page's blocks as the Paper look sets them, each numbered in the margin.
  static func clean(_ book: ImportedBook, page: Int) async -> Data? {
    let width: CGFloat = 900
    let margin: CGFloat = 70
    let sheet = Sheet(left: 0, width: Double(width - margin - 30), column: Double(width - margin - 30), gutter: 0, columns: 1, fontSize: 18)
    let setter = Typesetter(fontSize: sheet.fontSize, column: CGFloat(sheet.column), math: false, notes: book.noteLabels)
    let ids = Set(book.doc.blocks.filter { $0.pieces.contains { $0.page == page } }.map(\.id))
    let shown = book.proofEntries(sheet: sheet, traits: light, only: ids)
    // Pictures first, since the rest is drawn in one go.
    var pictures: [ObjectIdentifier: CGImage] = [:]
    for item in shown {
      if case let .block(b, _) = item, let sprite = b.sprite, let image = await sprite.atlas.picture(sprite.key) {
        pictures[ObjectIdentifier(b)] = image
      }
    }
    func tall(_ item: ImportedBook.ProofEntry) -> CGFloat {
      switch item {
      case let .block(b, _): return CGFloat(b.height)
      case let .text(_, t, _): return CGFloat(setter.layout(t).height) + 14
      }
    }
    let total = min(shown.reduce(CGFloat(40)) { $0 + tall($1) }, 2800)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let tag: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.systemRed]
    let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: max(total, 120)), format: format).image { r in
      let ctx = r.cgContext
      light.performAsCurrent {
        UIColor.white.setFill()
        r.fill(CGRect(x: 0, y: 0, width: width, height: max(total, 120)))
        var y: CGFloat = 20
        for item in shown where y < 2800 {
          switch item {
          case let .block(b, id):
            ctx.saveGState()
            ctx.translateBy(x: margin, y: y)
            b.layer.paint?(CGRect(origin: .zero, size: b.layer.bounds.size))
            if let inner = b.spriteFrame, let image = pictures[ObjectIdentifier(b)] {
              UIImage(cgImage: image).draw(in: inner)
            }
            ctx.restoreGState()
            if let id { ("#\(id)" as NSString).draw(at: CGPoint(x: 8, y: y + 2), withAttributes: tag) }
          case let .text(id, text, ink):
            let l = setter.layout(text)
            ctx.setFillColor(ink.cgColor)
            for w in l.words { drawPieces(w.glyphs.pieces, in: ctx, x: margin + w.x, baseline: y + w.y + setter.baseline) }
            ("#\(id)" as NSString).draw(at: CGPoint(x: 8, y: y + 2), withAttributes: tag)
          }
          y += tall(item)
        }
      }
    }
    return jpeg(image)
  }

  /// A page of the Magazine look, with every paragraph as a reader changing it would see it: set live, in the nearest font.
  static func typeset(_ book: ImportedBook, page: Int) async -> Data? {
    guard let info = book.doc.pages[safe: page],
      let raster = await book.atlas?.picture(PageAtlas.Key(page: page, pixels: wide, dark: false, crop: nil))
    else { return nil }
    let size = CGSize(width: raster.width, height: raster.height)
    let sheet = Sheet(left: 0, width: Double(size.width), column: Double(size.width), gutter: 0, columns: 1, fontSize: 12)
    let s = size.width / info.size.width
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
      UIImage(cgImage: raster).draw(in: CGRect(origin: .zero, size: size))
      let ctx = r.cgContext
      for (i, b) in book.paragraphs.enumerated() {
        guard let head = b.pieces.first, head.page == page else { continue }
        let box = CGRect(x: head.ink.minX * s, y: head.ink.minY * s, width: head.ink.width * s, height: head.ink.height * s)
        let setter = book.magazineSetter(i, sheet: sheet)
        UIColor.white.setFill()
        r.fill(box.insetBy(dx: -1, dy: -1))
        let l = setter.layout(b.text)
        ctx.setFillColor((book.ink(i, dark: false) ?? .black).cgColor)
        for w in l.words { drawPieces(w.glyphs.pieces, in: ctx, x: box.minX + w.x, baseline: box.minY + w.y + setter.baseline) }
      }
    }
    return jpeg(image)
  }
}
