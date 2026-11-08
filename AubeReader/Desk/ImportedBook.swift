import UIKit

// ─── Tiles ───────────────────────────────────────────────────────────────────

/// A part of a page, cut from the picture of it the atlas draws. Sharing one
/// picture among a page's tiles costs nothing for each, and redraws nothing.
final class Sprite {
  let atlas: PageAtlas
  let key: PageAtlas.Key
  /// The part of the picture it shows, in shares of it.
  let part: CGRect

  init(atlas: PageAtlas, key: PageAtlas.Key, part: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
    self.atlas = atlas
    self.key = key
    self.part = part
  }
}

/// A stretch of an original page as a reader lays it out: a tile, or tiles
/// stacked or side by side, which grow as the paragraphs in them do.
final class Region {
  enum Kind {
    case stack([Region])
    case side([Region])
    case block(Block)
    /// A paragraph that reads from here, with the original under it while it's as found.
    case para(Int, Block)
    /// More of a paragraph that started elsewhere: it folds away when the paragraph leaves what it was.
    case tail(Int, Block)
  }

  let kind: Kind
  /// The page of the original it's all of, for a region that's a whole page.
  var page: Int?

  init(_ kind: Kind) { self.kind = kind }

  /// Everything in it, in the order it reads.
  var entries: [Entry] {
    switch kind {
    case let .stack(kids), let .side(kids): return kids.flatMap(\.entries)
    case let .block(b): return [.block(b)]
    case let .para(i, b): return [.para(i), .block(b)]
    case let .tail(_, b): return [.block(b)]
    }
  }
}

/// How a paragraph sits in its tile: the marks are only a part of it, and the rest is air.
struct ParaTile {
  let block: Block
  let insetTop: Double
  let insetBottom: Double
  let insetLeft: Double
  let width: Double
  let inkHeight: Double
}

extension NSAttributedString.Key {
  /// On a note's mark: the note it opens.
  static let noteMark = NSAttributedString.Key("aube.noteMark")
}

// ─── A document, set out ─────────────────────────────────────────────────────

/// An imported document, and what it takes to show it: which of its blocks can be
/// rewritten, how each look sets them, and the pictures of its pages.
final class ImportedBook {
  let doc: ImportedDoc
  let atlas: PageAtlas?
  let text: LiveText
  /// The blocks that can be rewritten, in reading order. The reader's paragraphs, by index.
  let paragraphs: [DocBlock]
  private let paragraphOf: [Int: Int]
  private let captions: [Int: DocBlock]
  private let blockOf: [Int: DocBlock]
  /// Blocks a mark in the text can open, by number, and what each is marked with.
  private let notes: [Int: DocBlock]
  let noteLabels: [Int: String]
  /// Where marks are printed, on each page.
  private let printed: [Int: [PrintedMark]]
  /// How each paragraph sits in its tile, for the page width it was last set out for.
  private(set) var tiles: [Int: ParaTile] = [:]

  /// A paragraph too short to rewrite is set as it stands.
  static func rewritable(_ b: DocBlock) -> Bool {
    b.role.isProse && Scale.count(b.text) >= 15
  }

  init(_ doc: ImportedDoc, file: URL) {
    self.doc = doc
    paragraphs = doc.blocks.filter(Self.rewritable)
    var of: [Int: Int] = [:]
    for (i, b) in paragraphs.enumerated() { of[b.id] = i }
    paragraphOf = of
    var linked: [Int: DocBlock] = [:]
    for b in doc.blocks where b.role == .caption { if let target = b.captionOf { linked[target] = b } }
    captions = linked
    blockOf = Dictionary(doc.blocks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let noted = doc.blocks.filter { $0.mark != nil }
    notes = Dictionary(noted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    noteLabels = Dictionary(noted.map { ($0.id, $0.mark ?? "") }, uniquingKeysWith: { a, _ in a })
    let notedIds = Set(noted.map(\.id))
    printed = Dictionary(grouping: doc.marks.filter { notedIds.contains($0.note) }, by: \.page)

    if doc.flowing {
      atlas = nil
    } else {
      // The original pages come without what's now opened from a mark, or shown by the ring.
      var erased: [Int: [CGRect]] = [:]
      for b in noted where b.role == .footnote {
        for p in b.pieces {
          erased[p.page, default: []].append(p.ink.insetBy(dx: -1.5, dy: -1.5))
          if let rule = p.rule { erased[p.page, default: []].append(rule.insetBy(dx: -1, dy: -1)) }
        }
      }
      for (i, page) in doc.pages.enumerated() { erased[i, default: []] += page.folios.map { $0.insetBy(dx: -1, dy: -1) } }
      // The marks as they were printed: ours go in their place. Only a box of about that size: a model may have drawn it.
      for m in doc.marks where notedIds.contains(m.note) && m.box.width < 40 && m.box.height < 30 { erased[m.page, default: []].append(m.box) }
      atlas = PageAtlas(url: file, pages: doc.pages, erasing: erased)
    }

    // Every paragraph's level as measured; those too short to measure read at the document's own.
    let measured = paragraphs.filter { Scale.count($0.text) >= Scale.gradedWords }.map { Scale.level(atGrade: Scale.grade(of: $0.text)) }.sorted()
    let usual = measured.isEmpty ? Scale.middle : measured[measured.count / 2]
    let english = doc.language.map { $0.hasPrefix("en") } ?? true
    let source = LiveText.Source(
      title: doc.title, authors: doc.authors, field: doc.field.isEmpty ? "general reading" : doc.field,
      // Nothing to rewrite still needs a paragraph to hold the page's place by; it's never shown.
      paragraphs: paragraphs.isEmpty ? [""] : paragraphs.map(\.text),
      levels: paragraphs.isEmpty ? [usual] : paragraphs.map { english ? Scale.level(of: $0.text, fallback: usual) : Scale.middle },
      ladders: paragraphs.isEmpty ? [Scale.ladder(for: 1)] : paragraphs.map { Scale.ladder(for: Scale.count($0.text)) },
      language: doc.language)
    text = LiveText(id: doc.id, source: source)
    text.looks = looks
  }

  /// A file that has no pages has no original look to keep; a document with nothing to read is all look.
  var looks: [ReadingStyle] {
    if doc.flowing { return [.plain, .paper] }
    return paragraphs.isEmpty && !doc.blocks.contains { $0.role.isPicture } ? [.journal] : ReadingStyle.allCases
  }

  /// What it opens in: the clean page, where there is one.
  var look: ReadingStyle { looks.contains(.paper) ? .paper : looks[0] }

  /// What the original look is called. The name "Journal" belongs to the other document's dressing.
  static let originalName = "Magazine"

  // ─── How paragraphs are set ──────────────────────────────────────────────

  /// The page as the magazine look lays it out on a screen `width` wide.
  func magazineSheet(_ width: CGFloat) -> Sheet {
    let w = Double(width)
    let shown = min(w, 1120).rounded()
    let body = doc.blocks.first { Self.rewritable($0) }?.style.size ?? 10
    let page = doc.pages.first?.size.width ?? 612
    let size = max(10, body * CGFloat(shown) / page)
    return Sheet(left: ((w - shown) / 2).rounded(), width: shown, column: shown, gutter: 0, columns: 1, fontSize: size)
  }

  private func scale(_ page: Int, _ sheet: Sheet) -> CGFloat {
    CGFloat(sheet.width) / max(doc.pages[safe: page]?.size.width ?? 612, 1)
  }

  /// How paragraph `i` is set on a page like the original: in as near its own
  /// type as the device has, to its own measure.
  func magazineSetter(_ i: Int, sheet: Sheet) -> Typesetter {
    guard let b = paragraphs[safe: i], let head = b.pieces.first else {
      return Typesetter(fontSize: sheet.fontSize, column: CGFloat(sheet.column), math: false)
    }
    let s = scale(head.page, sheet)
    let size = max(4, b.style.size * s)
    let record = doc.fonts[safe: b.style.font]
    return Typesetter(
      fontSize: size, column: max(head.ink.width * s, size * 4), serif: record?.serif ?? false, leading: max(1, b.style.leading / max(b.style.size, 1)),
      justify: b.style.align == .justified, indent: b.style.indent * s, face: FontMatch.face(record, size: size, advance: b.style.advance), math: b.math, notes: noteLabels)
  }

  /// How far a paragraph's words are from the column's edge in the clean looks, and how they're set.
  func cleanInset(_ i: Int, size: CGFloat) -> CGFloat {
    switch paragraphs[safe: i]?.role {
    case .quote: return size * 1.4
    case .list: return size * 0.9
    default: return 0
    }
  }

  func cleanSetter(_ i: Int, sheet: Sheet) -> Typesetter {
    let size = sheet.fontSize
    let inset = cleanInset(i, size: size)
    let math = paragraphs[safe: i]?.math ?? false
    if paragraphs[safe: i]?.role == .quote {
      let base = UIFont.systemFont(ofSize: size)
      let italic = base.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: size) } ?? base
      return Typesetter(fontSize: size, column: CGFloat(sheet.column) - inset, face: italic, math: math, notes: noteLabels)
    }
    return Typesetter(fontSize: size, column: CGFloat(sheet.column) - inset, math: math, notes: noteLabels)
  }

  /// The color paragraph `i`'s words are written in on the original page.
  func ink(_ i: Int, dark: Bool) -> UIColor? {
    guard let t = paragraphs[safe: i]?.style.color else { return nil }
    return dark ? darkened(t) : UIColor(red: t.r, green: t.g, blue: t.b, alpha: 1)
  }

  /// The paper the original pages are printed on.
  func paper(dark: Bool) -> UIColor? {
    guard let t = doc.pages.first?.paper, t != .white else { return nil }
    return dark ? UIColor(hue: 0, saturation: 0, brightness: max(0.08, (1 - t.luma) * 0.5), alpha: 1) : UIColor(red: t.r, green: t.g, blue: t.b, alpha: 1)
  }

  // ─── Plans ───────────────────────────────────────────────────────────────

  func plan(_ style: ReadingStyle, _ sheet: Sheet, traits: UITraitCollection) -> [Band] {
    let press = Press(style: style, sheet: sheet)
    switch style {
    case .plain: return plain(press, traits: traits)
    case .paper: return clean(press, traits: traits)
    case .journal: return magazine(sheet, traits: traits)
    }
  }

  /// Plain: the words, in order, with the headings that find your place in them.
  private func plain(_ press: Press, traits: UITraitCollection) -> [Band] {
    let size = press.size
    let w = press.fullWidth
    var e: [Entry] = []
    let gap = (size * 1.6 * 0.85).rounded()
    for b in doc.blocks {
      if let i = paragraphOf[b.id] {
        e.append(.para(i))
        continue
      }
      let start = e.count
      switch b.role {
      case .title:
        e.append(set(typed(b, press, size: size * 1.25, bold: true, leading: 1.25, traits: traits), press, width: w, below: gap, traits: traits))
      case .heading:
        e.append(set(typed(b, press, size: size, bold: true, leading: 1.5, traits: traits), press, width: w, above: gap * 0.7, below: gap * 0.45, traits: traits))
      case .paragraph, .list, .quote, .abstract, .note, .minor, .references:
        e.append(set(typed(b, press, size: size, leading: 1.6, traits: traits), press, width: w, above: gap * 0.3, below: gap * 0.7, traits: traits))
      case .equation:
        // A displayed formula is part of the argument: the sentence before it often stops in the middle for it.
        if let picture = picture(b, press: press, traits: traits) { e.append(picture) }
      default:
        break
      }
      tag(e[start...], with: b)
    }
    return [.span(e)]
  }

  /// Paper: every part of the document, figures and all, in the app's own clean type.
  private func clean(_ press: Press, traits: UITraitCollection) -> [Band] { [.span(clean(press, traits: traits, only: nil))] }

  /// The entries of the clean look, for all the blocks or just `only`.
  private func clean(_ press: Press, traits: UITraitCollection, only: Set<Int>?) -> [Entry] {
    let size = press.size
    let w = press.fullWidth
    var e: [Entry] = []
    var abstractLabelled = false
    var openReferences = false
    let bylines = doc.blocks.filter { $0.role == .byline && (only?.contains($0.id) ?? true) }.map(\.text).joined(separator: "\n")
    var bylined = false
    func byline() -> Entry {
      set(typed(bylines, math: false, press, size: size * 0.8, color: Palette.quiet, leading: 1.45, traits: traits), press, width: w, below: size * 1.4, traits: traits)
    }
    for b in doc.blocks {
      if let only, !only.contains(b.id) { continue }
      if b.role != .references { openReferences = false }
      if b.role == .heading, b.text.lowercased().hasPrefix("abstract") { abstractLabelled = true }
      if b.role == .abstract, !abstractLabelled {
        abstractLabelled = true
        e.append(press.textBlock(press.rich("ABSTRACT", size: size * 0.62, color: Palette.muted, bold: true, tracking: 1.4), width: w, above: size * 0.4, below: size * 0.45))
      }
      if let i = paragraphOf[b.id] {
        e.append(.para(i))
        continue
      }
      let start = e.count
      switch b.role {
      case .title:
        e.append(set(typed(b, press, size: size * 1.7, bold: true, leading: 1.18, traits: traits), press, width: w, below: size * 0.8, traits: traits))
        if !bylined, !bylines.isEmpty {
          bylined = true
          e.append(byline())
        }
      case .byline:
        // Under the title, or here if it has none.
        if !bylined {
          bylined = true
          e.append(byline())
        }
      case .heading:
        let big = b.level <= 2
        let s = big ? size * 1.2 : size * 1.02
        e.append(set(typed(b, press, size: s, bold: true, leading: 1.3, traits: traits), press, width: w, above: big ? size * 2 : size * 1.4, below: size * 0.55, traits: traits))
      case .paragraph, .list, .quote, .abstract:
        e.append(set(typed(b, press, size: size, leading: 1.6, traits: traits), press, width: w, above: size * 0.25, below: size * 0.9, traits: traits))
      case .note, .minor:
        e.append(set(typed(b, press, size: size * 0.72, color: Palette.quiet, leading: 1.45, traits: traits), press, width: w, above: size * 0.2, below: size * 0.7, traits: traits))
      case .references:
        if !openReferences { openReferences = true }
        e.append(press.textBlock(press.rich(escaped(NoteToken.strip(b.text)), size: size * 0.72, color: Palette.quiet, leading: 1.35), width: w, below: size * 0.4))
      case .caption:
        // One that isn't shown under a picture stands by itself.
        if !hasPicture(b) {
          e.append(set(typed(b, press, size: size * 0.75, color: Palette.quiet, leading: 1.45, traits: traits), press, width: w, above: size * 0.4, below: size, traits: traits))
        }
      case .figure, .table, .equation, .code:
        if let picture = picture(b, press: press, traits: traits) { e.append(picture) }
      case .furniture, .footnote:
        // A footnote is only ever opened from its mark.
        break
      }
      tag(e[start...], with: b)
    }
    return e
  }

  /// Says which page of the original what was set for `b` comes from.
  private func tag(_ entries: ArraySlice<Entry>, with b: DocBlock) {
    for entry in entries {
      if case let .block(block) = entry { block.page = b.pieces.first?.page }
    }
    if case let .block(block)? = entries.first { block.landmark = landmark(b) }
  }

  /// What the contents call a block, if it's a title or a heading.
  private func landmark(_ b: DocBlock) -> (title: String, level: Int)? {
    switch b.role {
    case .title: return (b.text, 0)
    case .heading: return (b.text, max(b.level, 1))
    default: return nil
    }
  }

  /// A run of text set as a block, with what's marked in it ready to be tapped.
  private func set(_ s: NSAttributedString, _ press: Press, width w: CGFloat, above: CGFloat = 0, below: CGFloat = 0, traits: UITraitCollection) -> Entry {
    let entry = press.textBlock(s, width: w, above: above, below: below)
    if case let .block(block) = entry { block.show(markRects(s, width: w, origin: CGPoint(x: 0, y: above)), traits: traits) }
    return entry
  }

  /// How much of the page to cut for a picture. A formula's big symbols and
  /// fraction bars reach well beyond its lines of text, so it gets room around
  /// them, as far as the gap to its neighbors allows; a figure a little, for the
  /// strokes that overhang its marks.
  private func cropBox(_ b: DocBlock, _ piece: BlockPiece) -> CGRect {
    let page = CGRect(origin: .zero, size: doc.pages[safe: piece.page]?.size ?? .zero)
    let reach = b.role == .equation || b.role == .code ? max(b.style.size, 8) * 1.1 : 3
    var r = piece.ink.insetBy(dx: -reach, dy: -reach)
    if piece.tile.width > 0, piece.tile != piece.ink {
      let t = piece.tile
      let top = max(r.minY, t.minY)
      let bottom = min(r.maxY, t.maxY)
      r = CGRect(x: max(r.minX, t.minX), y: top, width: min(r.maxX, t.maxX) - max(r.minX, t.minX), height: max(bottom - top, piece.ink.height))
    }
    return r.intersection(page)
  }

  /// Whether a caption is set under its picture: the picture has to be one
  /// that's shown, and this has to be the caption it's shown with.
  private func hasPicture(_ caption: DocBlock) -> Bool {
    guard let target = caption.captionOf, let picture = doc.block(target), picture.role.isPicture else { return false }
    return captions[target]?.id == caption.id
  }

  /// Our mark where a mark's printed on a picture of a page drawn `scale` times over,
  /// of which `box` is shown, at `offset`. It has to sit among letters that can't make room for it, so
  /// it's a little smaller than among words, and level with the line, not raised as it was.
  private func badge(_ m: PrintedMark, scale: CGFloat, in box: CGRect, body: CGFloat, offset: CGPoint) -> TapMark? {
    guard let label = noteLabels[m.note] else { return nil }
    let height = body.rounded()
    let wide = Halo.width(label, height)
    // Set raised, a mark's foot is about level with the line's lowercase letters, a little under the middle of its capitals; at the size of the text, its own middle is.
    let onLine = m.box.height * scale >= body * 0.85
    let y = onLine ? (m.box.midY - box.minY) * scale : (m.box.maxY - box.minY) * scale - body * 0.14
    return TapMark(
      note: m.note,
      rect: CGRect(x: offset.x + ((m.box.midX - box.minX) * scale - wide / 2 + 2).rounded(), y: offset.y + (y - height / 2).rounded(), width: wide, height: height),
      paint: label)
  }

  /// A figure, table, equation or listing, cut from the page it's on and set to
  /// the column, with its caption in the app's own type.
  private func picture(_ b: DocBlock, press: Press, traits: UITraitCollection) -> Entry? {
    guard let atlas, let piece = b.pieces.first, piece.ink.width > 1, piece.ink.height > 1 else { return nil }
    let size = press.size
    let w = press.fullWidth
    // Set to the same scale as the text beside it, and no wider than the column.
    let body = paragraphs.first?.style.size ?? 10
    let natural = size / max(body, 1)
    let fitted = min(natural, w / piece.ink.width)
    var scale = b.role == .figure ? max(fitted, min(w / piece.ink.width, 1)) : fitted
    if b.role == .figure { scale = min(w / piece.ink.width, max(scale, natural * 0.9)) }
    let box = cropBox(b, piece)
    let shown = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
    let dpr = max(traits.displayScale, 1)
    let crop = box
    let key = PageAtlas.Key(page: piece.page, pixels: min(Int(shown.width * dpr), 2600), dark: traits.userInterfaceStyle == .dark, crop: crop)
    let caption = captions[b.id]
    var label: NSAttributedString?
    if let caption { label = typed(caption, press, size: size * 0.75, color: Palette.quiet, leading: 1.45, traits: traits) }
    let inset = w * 0.04
    let capH = label.map { textHeight($0, w - 2 * inset) } ?? 0
    let tiny = b.role == .equation
    let above = tiny ? size * 0.5 : size * 1.2
    let below = tiny ? size * 0.5 : size * 1.2
    let gap = label == nil ? 0 : size * 0.7
    let captionFirst = b.role == .table
    let x = b.role == .code ? 0 : ((w - shown.width) / 2).rounded()
    let capY = captionFirst ? above : above + shown.height + gap
    let block = Block(width: w, height: above + shown.height + gap + capH + below, sprite: Sprite(atlas: atlas, key: key), spriteRect: CGRect(x: x, y: above + (captionFirst ? capH + gap : 0), width: shown.width, height: shown.height)) { _ in
      guard let label else { return }
      drawText(label, CGRect(x: inset, y: capY, width: w - 2 * inset, height: capH))
    }
    var marks = label.map { markRects($0, width: w - 2 * inset, origin: CGPoint(x: inset, y: capY)) } ?? []
    // A mark printed on the picture itself, as on a table of authors.
    let inPicture = CGPoint(x: x, y: above + (captionFirst ? capH + gap : 0))
    for m in printed[piece.page] ?? [] where box.contains(CGPoint(x: m.box.midX, y: m.box.midY)) {
      if let mark = badge(m, scale: scale, in: box, body: size, offset: inPicture) { marks.append(mark) }
    }
    block.show(marks, traits: traits)
    return .block(block)
  }

  // ─── For the model to look at ────────────────────────────────────────────

  /// Something in a proof of the clean look: a block already set, or a paragraph to set.
  enum ProofEntry {
    case block(Block, id: Int?)
    case text(id: Int, String, ink: UIColor)
  }

  /// The blocks `only`, as the clean look would set them, each with the number it goes by.
  func proofEntries(sheet: Sheet, traits: UITraitCollection, only: Set<Int>) -> [ProofEntry] {
    let press = Press(style: .paper, sheet: sheet)
    var out: [ProofEntry] = []
    for b in doc.blocks where only.contains(b.id) {
      if paragraphOf[b.id] != nil {
        out.append(.text(id: b.id, b.text, ink: .black))
        continue
      }
      for entry in ImportedBook.cleanOne(self, b, press: press, traits: traits) {
        if case let .block(block) = entry { out.append(.block(block, id: b.id)) }
      }
    }
    return out
  }

  private static func cleanOne(_ book: ImportedBook, _ b: DocBlock, press: Press, traits: UITraitCollection) -> [Entry] {
    book.clean(press, traits: traits, only: [b.id])
  }

  /// A block's text in `press`'s type, its formulas, if it has any, set among the
  /// words. It's only drawn once, so they're pictures, in the look's ink.
  private func typed(_ b: DocBlock, _ press: Press, size: CGFloat, color: UIColor = Palette.ink, bold: Bool = false, leading: CGFloat? = nil, traits: UITraitCollection) -> NSAttributedString {
    typed(b.text, math: b.math, press, size: size, color: color, bold: bold, leading: leading, traits: traits)
  }

  private func typed(_ text: String, math: Bool, _ press: Press, size: CGFloat, color: UIColor = Palette.ink, bold: Bool = false, leading: CGFloat? = nil, traits: UITraitCollection) -> NSAttributedString {
    guard math || text.contains("[^") else { return press.rich(escaped(text), size: size, color: color, bold: bold, leading: leading) }
    let out = NSMutableAttributedString()
    let ink = color.resolvedColor(with: traits)
    func words(_ part: String) {
      for piece in NoteToken.parts(part) {
        switch piece {
        case let .text(s):
          out.append(press.rich(escaped(s), size: size, color: color, bold: bold, leading: leading))
        case let .mark(id):
          guard let label = noteLabels[id] else { continue }
          out.append(markRun(id, label, press, size: size, traits: traits))
        }
      }
    }
    if math {
      for (i, part) in text.components(separatedBy: "$").enumerated() {
        if i % 2 == 0 {
          words(part)
        } else {
          let (image, descent) = TeX.picture(part, size: size, color: ink)
          let attachment = NSTextAttachment()
          attachment.image = image
          attachment.bounds = CGRect(x: 0, y: -descent, width: image.size.width, height: image.size.height)
          out.append(NSAttributedString(attachment: attachment))
        }
      }
    } else {
      words(text)
    }
    // Marks and formulas have no line spacing of their own to bring in.
    if out.length > 0, let style = press.rich(" ", size: size, leading: leading).attribute(.paragraphStyle, at: 0, effectiveRange: nil) {
      out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
    }
    return out
  }

  /// A note's mark among words set by UIKit, the same size whatever they're set at.
  private func markRun(_ id: Int, _ label: String, _ press: Press, size: CGFloat, traits: UITraitCollection) -> NSAttributedString {
    let diameter = Halo.diameter(press.size)
    let image = Halo.image(label, diameter: diameter, ink: Palette.ink.resolvedColor(with: traits), scale: max(traits.displayScale, 1))
    let attachment = NSTextAttachment()
    attachment.image = image
    // Level with the middle of the capitals beside it.
    attachment.bounds = CGRect(x: 0, y: press.font(size).capHeight / 2 - diameter / 2, width: image.size.width, height: diameter)
    let out = NSMutableAttributedString(string: "\u{2009}", attributes: [.font: press.font(size)])
    let mark = NSMutableAttributedString(attachment: attachment)
    mark.addAttribute(.noteMark, value: id, range: NSRange(location: 0, length: mark.length))
    out.append(mark)
    return out
  }

  /// Where the marks in `s` come out, set `width` wide with its top left at `origin`.
  private func markRects(_ s: NSAttributedString, width: CGFloat, origin: CGPoint) -> [TapMark] {
    var runs: [(id: Int, range: NSRange)] = []
    s.enumerateAttribute(.noteMark, in: NSRange(location: 0, length: s.length)) { value, range, _ in
      if let id = value as? Int { runs.append((id, range)) }
    }
    guard !runs.isEmpty else { return [] }
    let storage = NSTextStorage(attributedString: s)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    return runs.compactMap { run in
      guard let attachment = s.attribute(.attachment, at: run.range.location, effectiveRange: nil) as? NSTextAttachment else { return nil }
      let first = manager.glyphRange(forCharacterRange: run.range, actualCharacterRange: nil).location
      let line = manager.lineFragmentRect(forGlyphAt: first, effectiveRange: nil)
      let at = manager.location(forGlyphAt: first)
      let shown = attachment.bounds
      return TapMark(note: run.id, rect: CGRect(x: origin.x + line.minX + at.x, y: origin.y + line.minY + at.y - shown.minY - shown.height, width: shown.width, height: shown.height))
    }
  }

  /// What a note says, set to be read over the page when its mark is tapped.
  func noteText(_ id: Int, traits: UITraitCollection) -> NSAttributedString? {
    guard let b = notes[id] else { return nil }
    var text = NoteToken.strip(b.text)
    // In a list of its own, a note still opens with the number it's marked with.
    if b.role != .footnote, let first = text.split(separator: " ").first, MarkLabel.normal(String(first)) == b.mark {
      text = String(text.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
    }
    return typed(text, math: b.math, Press(style: .paper, sheet: .plain(620)), size: NoteTip.textSize, leading: NoteTip.leading, traits: traits)
  }

  /// What a note says, for VoiceOver.
  func spokenNote(_ id: Int) -> String? { notes[id].map { NoteToken.strip($0.text).replacingOccurrences(of: "$", with: "") } }

  /// The pages of the original each paragraph starts on.
  func page(ofParagraph i: Int) -> Int { paragraphs[safe: i]?.pieces.first?.page ?? 0 }

  /// Text as found holds asterisks and underscores that mean only themselves.
  private func escaped(_ t: String) -> String {
    var out = ""
    out.reserveCapacity(t.count)
    for c in t {
      if c == "*" || c == "\\" || c == "_" || c == "^" || c == "}" { out.append("\\") }
      out.append(c)
    }
    return out
  }

  // ─── The original page ───────────────────────────────────────────────────

  /// Magazine: each page as it was, cut into tiles along its own gutters and gaps.
  /// Laid edge to edge the tiles draw the original exactly, and with a paragraph
  /// as found that's what's seen. A paragraph that's been changed is set live in
  /// the nearest type, in its place, and what's below it in its column moves down.
  private func magazine(_ sheet: Sheet, traits: UITraitCollection) -> [Band] {
    guard let atlas else { return [] }
    tiles = [:]
    var bands: [Band] = []
    let dpr = max(traits.displayScale, 1)
    let dark = traits.userInterfaceStyle == .dark
    for (n, page) in doc.pages.enumerated() {
      let s = CGFloat(sheet.width) / max(page.size.width, 1)
      let key = PageAtlas.Key(page: n, pixels: min(Int(CGFloat(sheet.width) * dpr), 2600), dark: dark, crop: nil)
      func snap(_ v: CGFloat) -> CGFloat { (v * s * dpr).rounded() / dpr }
      let onPage = printed[n] ?? []
      func tile(_ t: PageTile) -> Block {
        let r = t.rect
        let size = CGSize(width: snap(r.maxX) - snap(r.minX), height: snap(r.maxY) - snap(r.minY))
        let part = CGRect(
          x: r.minX / page.size.width, y: r.minY / page.size.height, width: r.width / page.size.width, height: r.height / page.size.height)
        let b = Block(size: size, sprite: Sprite(atlas: atlas, key: key, part: part), offset: CGPoint(x: sheet.left + Double(snap(r.minX)), y: 0))
        b.page = n
        // The marks printed on this tile, each with ours in its place.
        let here = onPage.filter { r.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
        if !here.isEmpty {
          b.show(here.compactMap { badge($0, scale: s, in: r, body: CGFloat(sheet.fontSize), offset: .zero) }, traits: traits)
        }
        return b
      }
      func region(_ t: PageTile) -> Region {
        switch t.kind {
        case .stack: return Region(.stack((t.kids ?? []).map(region)))
        case .side: return Region(.side((t.kids ?? []).map(region)))
        case .blank: return Region(.block(tile(t)))
        case .block:
          // A footnote takes up no room: its column closes up without it.
          if let id = t.block, blockOf[id]?.role == .footnote { return Region(.stack([])) }
          let b = tile(t)
          // A title or heading is found by its first piece.
          if let id = t.block, let block = blockOf[id], t.piece ?? 0 == 0 { b.landmark = landmark(block) }
          guard let id = t.block, let i = paragraphOf[id], let block = blockOf[id] else { return Region(.block(b)) }
          let index = t.piece ?? 0
          guard index == 0, let head = block.pieces.first else { return Region(.tail(i, b)) }
          tiles[i] = ParaTile(
            block: b, insetTop: Double(snap(head.ink.minY) - snap(t.rect.minY)), insetBottom: Double(snap(t.rect.maxY) - snap(head.ink.maxY)),
            insetLeft: Double(head.ink.minX - t.rect.minX) * Double(s), width: Double(head.ink.width * s),
            inkHeight: Double(snap(head.ink.maxY) - snap(head.ink.minY)))
          return Region(.para(i, b))
        }
      }
      let whole = region(page.tile)
      whole.page = n
      bands.append(.region(whole))
      if n + 1 < doc.pages.count {
        // Between pages, a hairline across the whole screen, margins and all.
        let rule = Block(width: CGFloat(sheet.left * 2 + sheet.width), height: 1) { r in
          resolved(Palette.line).setFill()
          UIRectFill(CGRect(x: 0, y: 0, width: r.width, height: 1 / dpr))
        }
        // Laid out as a tile is, so it lands on a whole pixel and stays one pixel thin.
        rule.fixedX = 0
        bands.append(.region(Region(.block(rule))))
      }
    }
    return bands
  }
}
