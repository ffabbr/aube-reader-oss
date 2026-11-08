import UIKit

// ─── Looks ───────────────────────────────────────────────────────────────────

/// How a reader dresses its text: plain prose; a paper, with a title, an
/// abstract, headings, equations and figures; or a journal page, set in a
/// serif in two justified columns. The paragraphs morph the same way in each.
enum ReadingStyle: Int, CaseIterable {
  case plain, paper, journal

  var next: ReadingStyle { ReadingStyle(rawValue: (rawValue + 1) % ReadingStyle.allCases.count)! }
  var name: String { ["Plain", "Paper", "Journal"][rawValue] }
  var symbol: String { ["text.alignleft", "doc.richtext", "newspaper"][rawValue] }
}

/// Where the text sits on a page, in page units.
struct Sheet: Equatable {
  /// The left edge of the text, and how wide it runs across all its columns.
  var left: Double
  var width: Double
  var column: Double
  var gutter: Double
  var columns: Int
  var fontSize: CGFloat

  func columnX(_ i: Int) -> Double { left + Double(i) * (column + gutter) }

  /// One column of sans-serif text, centered.
  static func plain(_ width: CGFloat) -> Sheet {
    let column = Double(min(620, (width - 48).rounded()))
    let left = ((Double(width) - column) / 2).rounded()
    return Sheet(left: left, width: column, column: column, gutter: 0, columns: 1, fontSize: width < 640 ? 17.5 : 20)
  }

  /// Two columns of serif text with a printed page's margins: about the
  /// proportions of a letter-size journal page, scaled to the screen.
  static func journal(_ width: CGFloat) -> Sheet {
    let w = Double(width)
    let margin = max(32, (w * 0.07).rounded())
    let text = min(w - 2 * margin, 980)
    let columns = text < 560 ? 1 : 2
    let gutter = columns == 1 ? 0 : (text * 0.035).rounded()
    let column = ((text - gutter) / Double(columns)).rounded(.down)
    let full = column * Double(columns) + gutter
    let size = CGFloat(clamp((column * (columns == 1 ? 0.03 : 0.034) * 2).rounded() / 2, 13, 17))
    return Sheet(
      left: ((w - full) / 2).rounded(), width: full, column: column, gutter: gutter, columns: columns, fontSize: size)
  }
}

// ─── The page ────────────────────────────────────────────────────────────────

/// Something on the page besides the paragraphs: a title, a heading, a figure.
/// Drawn once, then moved about with the text.
final class Block {
  let layer = BlockLayer()
  let height: Double
  var x = 0.0
  var top = 0.0
  var placed: CGPoint?
  /// A picture of part of a page to show, rather than anything drawn; `picture`
  /// is the layer it goes in, where the block also draws around it.
  var sprite: Sprite?
  private var picture: CALayer?
  /// Whether it's on the page now, or off it, costing nothing, while it's far from the screen.
  private(set) var attached = false
  /// Set for a tile: laid out at exactly this x, whatever the column.
  var fixedX: Double?
  /// The page of the original it comes from, where it comes from one.
  var page: Int?
  /// What the contents call it, if it's a title or a heading: a title is level 0, the largest heading 1.
  var landmark: (title: String, level: Int)?
  /// Notes marked on it, and where in it, for tapping.
  private(set) var marks: [TapMark] = []

  init(width: CGFloat, height: CGFloat, draw: @escaping (CGRect) -> Void) {
    self.height = Double(height.rounded(.up))
    layer.anchorPoint = .zero
    layer.bounds = CGRect(x: 0, y: 0, width: width, height: height.rounded(.up))
    layer.paint = draw
  }

  /// A tile of a page: nothing drawn, just its sprite, exactly `size`, at `offset.x`.
  init(size: CGSize, sprite: Sprite, offset: CGPoint) {
    height = Double(size.height)
    self.sprite = sprite
    fixedX = offset.x
    layer.anchorPoint = .zero
    layer.bounds = CGRect(origin: .zero, size: size)
    layer.contentsRect = sprite.part
    layer.contentsGravity = .resize
  }

  /// Text drawn around a sprite placed at `spriteRect`.
  init(width: CGFloat, height: CGFloat, sprite: Sprite, spriteRect: CGRect, draw: @escaping (CGRect) -> Void) {
    self.height = Double(height.rounded(.up))
    self.sprite = sprite
    layer.anchorPoint = .zero
    layer.bounds = CGRect(x: 0, y: 0, width: width, height: height.rounded(.up))
    layer.paint = draw
    let inner = StillLayer()
    inner.frame = spriteRect
    inner.contentsGravity = .resize
    layer.addSublayer(inner)
    picture = inner
  }

  /// The notes marked on it. Those that say what to paint have nothing else to show them: on a
  /// picture of a page, the mark's painted over where it was printed, as a mark among the words looks.
  func show(_ marks: [TapMark], traits: UITraitCollection) {
    self.marks = marks
    let ink = Palette.ink.resolvedColor(with: traits)
    for m in marks {
      guard let label = m.paint else { continue }
      let badge = StillLayer()
      badge.frame = m.rect
      badge.contents = Halo.image(label, diameter: m.rect.height, ink: ink, scale: max(traits.displayScale, 1)).cgImage
      badge.contentsScale = max(traits.displayScale, 1)
      layer.addSublayer(badge)
    }
  }

  /// Puts it on the page under `parent`, and asks for what it shows.
  func attach(to parent: CALayer) {
    guard !attached else { return }
    attached = true
    parent.insertSublayer(layer, at: 0)
    if layer.paint != nil { layer.setNeedsDisplay() }
    guard let sprite else { return }
    let target = picture ?? layer
    sprite.atlas.picture(sprite.key) { [weak self, weak target] image in
      guard let self, self.attached, let target else { return }
      target.contents = image
    }
  }

  /// Takes it off the page, and lets go of what it was showing.
  func detach() {
    guard attached else { return }
    attached = false
    layer.removeFromSuperlayer()
    layer.contents = nil
    picture?.contents = nil
    placed = nil
  }

  /// Whether what it's to show is showing yet: pictures of pages take a moment to draw.
  var showing: Bool { sprite == nil || (picture ?? layer).contents != nil }

  /// Where its sprite goes within it, if it's set among other things.
  var spriteFrame: CGRect? { picture?.frame }

  /// What it shows, cropped, for drawing elsewhere.
  var picturePart: CGImage? {
    guard let sprite, let image = ((picture ?? layer).contents as! CGImage?) else { return nil }
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
    return image.cropping(to: CGRect(x: sprite.part.minX * w, y: sprite.part.minY * h, width: sprite.part.width * w, height: sprite.part.height * h))
  }
}

/// Somewhere a reader can tap to open a note.
struct TapMark {
  let note: Int
  /// In the coordinates of what it's on: a block, or the page once `ReaderView` has found it.
  let rect: CGRect
  /// What to paint there, where nothing's set to show it.
  var paint: String?
}

/// Draws a block with UIKit, in the colors of the reader's appearance.
final class BlockLayer: StillLayer {
  var paint: ((CGRect) -> Void)?
  var traits = UITraitCollection.current

  override func draw(in ctx: CGContext) {
    UIGraphicsPushContext(ctx)
    traits.performAsCurrent { paint?(bounds) }
    UIGraphicsPopContext()
  }
}

/// One paragraph of the text, or a block set beside it.
enum Entry {
  case para(Int)
  case block(Block)
}

/// A stretch of the page: entries across its full width, or side-by-side
/// columns of them that the next band waits for.
enum Band {
  case span([Entry])
  case columns([[Entry]])
  /// An original page, with its own arrangement of columns (see `ImportedBook`).
  case region(Region)

  /// Everything in it, in the order it reads.
  var entries: [Entry] {
    switch self {
    case let .span(items): return items
    case let .columns(cols): return cols.flatMap { $0 }
    case let .region(r): return r.entries
    }
  }
}

// ─── What the paper says ─────────────────────────────────────────────────────

/// A paper's own words around its paragraphs: its title page, its sections,
/// what each section sets after its text, and its references. One to each
/// document that comes with the app.
struct Manuscript {
  struct Section {
    let title: String
    /// Its paragraphs (by index in the text), shown in every look.
    let paragraphs: [Int]
    /// What it sets after them.
    var after: [Extra] = []
    /// Further paragraphs that only the journal page sets.
    var more: [Int] = []
  }

  struct Table {
    let caption: String
    let header: [String]
    let rows: [[String]]
  }

  /// The document it belongs to.
  let id: String
  let title: String
  let abstract: String
  let keywords: String
  let authors: [String]
  /// Which of `affiliations` each author belongs to, from 1.
  let places: [Int]
  /// Each place the authors work, short on the preprint and in full in the journal.
  let affiliations: [(short: String, full: String)]
  let received: String
  /// Over the preprint's title.
  let preprint: String
  /// The journal's name, volume and page, and its date, at the head of its page.
  let journal: String
  let date: String
  let doi: String
  /// At the foot of the journal page.
  let footer: (left: String, right: String)
  let sections: [Section]
  var captions: [Figure: String] = [:]
  var table: Table? = nil
  let references: [String]

  static let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

  /// The section opening at paragraph `p`, if one does.
  func heading(at p: Int) -> String? { sections.first { $0.paragraphs.first == p }?.title }

  /// The authors as the preprint lists them, each marked with where they work.
  var byline: String {
    zip(authors, places).map { "\($0)^{\($1)}" }.joined(separator: ", ")
  }

  /// The authors as the journal lists them.
  var journalByline: String {
    let marked = zip(authors, places).enumerated().map { i, a in
      authors.count > 2 && i < authors.count - 1 ? "\(a.0),^{\(a.1)}" : "\(a.0)^{\(a.1)}"
    }
    guard marked.count > 1 else { return marked.joined() }
    return marked.dropLast().joined(separator: " ") + " and " + marked.last!
  }

  /// The manuscript of the document with `id`, if it has one.
  static func of(_ id: String) -> Manuscript? {
    [blackHoles, swarm].first { $0.id == id }
  }

  // ─── Black holes ───────────────────────────────────────────────────────

  static let blackHoles = Manuscript(
    id: "black-holes",
    title: "Black Holes: Collapse, Horizons, and the Observational Record",
    abstract:
      "We review the physics of black holes from the Schwarzschild solution of general relativity to present-day observations. We describe how the cores of massive stars collapse once they exceed the Chandrasekhar mass, why the event horizon is a causal rather than a material boundary, and how gravitational time dilation and redshift grow without bound as it is approached. We then summarize the independent lines of evidence (X-ray binaries, stellar orbits at the Galactic Center, gravitational waves from merging binaries, and horizon-scale imaging) that establish black holes as astrophysical objects.",
    keywords: "black holes · general relativity · event horizons · gravitational waves",
    authors: ["Ana Lindqvist", "Malik Okafor", "Julia Reyes"],
    places: [1, 2, 1],
    affiliations: [
      ("Department of Physics, Northgate University", "Department of Physics, Northgate University, Northgate, United Kingdom"),
      ("Calder Institute for Gravitational Astronomy", "Calder Institute for Gravitational Astronomy, Calder, Canada"),
    ],
    received: "(Received 14 March 2026; revised 2 August 2026; published 1 November 2026)",
    preprint: "PREPRINT  ·  NOVEMBER 2026",
    journal: "JOURNAL OF GRAVITATIONAL PHYSICS **14**, 021101 (2026)",
    date: "1 NOVEMBER 2026",
    doi: "DOI: 10.0000/JGP.14.021101",
    footer: ("1550-0000/26/14(2)/021101(4)", "© 2026 Society for Gravitational Physics"),
    sections: [
      Section(
        title: "Introduction", paragraphs: [0],
        after: [.equation(#"r_s = 2GM/c^2 \approx 2.95\,\mathrm{km}\,(M/M_\odot)"#), .figure(.radius)], more: [5, 6]),
      Section(title: "Formation by core collapse", paragraphs: [1], after: [.figure(.star)], more: [7, 8]),
      Section(
        title: "The event horizon", paragraphs: [2],
        after: [.equation(#"ds^2 = -(1 - r_s/r)\,c^2dt^2 + (1 - r_s/r)^{-1}dr^2 + r^2d\Omega^2"#), .figure(.cones)], more: [9, 10]),
      Section(
        title: "Time dilation and redshift", paragraphs: [3],
        after: [.equation(#"d\tau = \sqrt{1 - r_s/r}\;dt"#), .equation(#"1 + z = (1 - r_s/r)^{-1/2}"#), .figure(.clocks)], more: [11]),
      Section(title: "Observational evidence", paragraphs: [4], after: [.table, .figure(.evidence)], more: [12]),
    ],
    captions: [
      .radius:
        "Schwarzschild radius as a function of mass, *r*_{s} = 2*GM*/*c*^{2}. The relation is linear, so the mean density inside the horizon falls as *M*^{−2}. Dotted lines mark the solar radius and one astronomical unit.",
      .star:
        "Onion-shell structure of a massive star shortly before core collapse (not to scale). Silicon burning grows the inert iron core until it nears the Chandrasekhar mass, *M*_{Ch} ≈ 1.4 *M*_{⊙}, and electron degeneracy pressure fails.",
      .cones:
        "Light cones in ingoing Eddington–Finkelstein coordinates. Outside the horizon (dashed) outgoing light can escape to large *r*; at *r* = *r*_{s} it stands still, and inside every future-directed path ends at *r* = 0.",
      .clocks:
        "Rate of a static clock relative to one at infinity, d*τ*/d*t* (solid), and the redshift 1 + *z* of light it emits (dashed). Dotted lines mark the photon sphere, *r* = 1.5 *r*_{s}, and the innermost stable circular orbit, *r* = 3 *r*_{s}.",
      .evidence:
        "Two independent lines of evidence (schematic). (a) Astrometric orbit of the star S2 about Sgr A\\*: period 16 yr, eccentricity 0.88. (b) Gravitational-wave strain from a binary black-hole merger, after GW150914: inspiral, merger and ringdown.",
    ],
    table: Table(
      caption: "Representative black holes, their masses, and the Schwarzschild radii those masses imply.",
      header: ["Object", "*M* / *M*_{⊙}", "*r*_{s}", "Method"],
      rows: [
        ["Cygnus X-1", "21.2", "63 km", "X-ray binary"],
        ["V404 Cygni", "9", "27 km", "X-ray binary"],
        ["GW150914 remnant", "62", "180 km", "GW signal"],
        ["Sgr A\\*", "4.3 × 10^{6}", "0.085 au", "Stellar orbits"],
        ["M87\\*", "6.5 × 10^{9}", "130 au", "EHT imaging"],
      ]),
    references: [
      "K. Schwarzschild, Sitzungsber. Preuss. Akad. Wiss. Berlin **1916**, 189 (1916).",
      "S. Chandrasekhar, Astrophys. J. **74**, 81 (1931).",
      "J. R. Oppenheimer and H. Snyder, Phys. Rev. **56**, 455 (1939).",
      "D. Finkelstein, Phys. Rev. **110**, 965 (1958).",
      "C. T. Bolton, Nature **235**, 271 (1972).",
      "B. P. Abbott *et al.* (LIGO Scientific and Virgo Collaborations), Phys. Rev. Lett. **116**, 061102 (2016).",
      "R. Abuter *et al.* (GRAVITY Collaboration), Astron. Astrophys. **615**, L15 (2018).",
      "K. Akiyama *et al.* (Event Horizon Telescope Collaboration), Astrophys. J. Lett. **875**, L1 (2019).",
      "J. Michell, Phil. Trans. R. Soc. London **74**, 35 (1784).",
      "R. P. Kerr, Phys. Rev. Lett. **11**, 237 (1963).",
      "R. Penrose, Phys. Rev. Lett. **14**, 57 (1965).",
      "J. D. Bekenstein, Phys. Rev. D **7**, 2333 (1973).",
      "S. W. Hawking, Commun. Math. Phys. **43**, 199 (1975).",
    ])

  // ─── How a swarm chooses a home ────────────────────────────────────────

  static let swarm = Manuscript(
    id: "swarm",
    title: "How a Swarm Chooses a Home: Collective Nest-Site Selection in Honeybees",
    abstract:
      "When a honeybee colony reproduces, some ten thousand workers and their queen leave the nest and must find a new cavity within days. We review how a few hundred scouts make that choice for the whole swarm. Scouts assess candidate cavities independently and advertise them with waggle dances whose vigour scales with site quality and decays with each return; they inhibit rival dancers with stop signals; and they commit once a quorum of scouts is present at one site, after which piping readies the swarm and streaking guides it in flight. We describe how these simple rules combine into a fast and accurate decision, and compare the process to evidence accumulation in neural circuits.",
    keywords: "honeybees · swarm intelligence · collective decisions · quorum sensing · waggle dance",
    authors: ["Maren Holt", "Teodor Vasile"],
    places: [1, 2],
    affiliations: [
      ("Department of Ecology and Evolution, Lindmoor University", "Department of Ecology and Evolution, Lindmoor University, Lindmoor, Sweden"),
      ("Institute for Collective Behaviour, Brașca", "Institute for Collective Behaviour, Brașca, Romania"),
    ],
    received: "(Received 9 February 2026; revised 21 July 2026; published 3 November 2026)",
    preprint: "PREPRINT  ·  NOVEMBER 2026",
    journal: "JOURNAL OF BEHAVIOURAL ECOLOGY **37**, 114502 (2026)",
    date: "3 NOVEMBER 2026",
    doi: "DOI: 10.0000/JBE.37.114502",
    footer: ("0942-0000/26/37(11)/114502(3)", "© 2026 Society for Behavioural Ecology"),
    sections: [
      Section(title: "Introduction", paragraphs: [0]),
      Section(title: "Scouting for cavities", paragraphs: [1], after: [.table]),
      Section(
        title: "Advertising a site", paragraphs: [2, 3],
        after: [.equation(#"D \approx v_w\,t_w, \quad v_w \approx 0.75\,\mathrm{km\,s^{-1}}"#), .figure(.dance)]),
      Section(
        title: "Cross-inhibition", paragraphs: [4],
        after: [.equation(#"dy_A/dt = \gamma_A U - \alpha y_A + \rho_A y_A U - \sigma y_A y_B"#)]),
      Section(title: "Quorum and lift-off", paragraphs: [5], after: [.figure(.quorum)]),
      Section(title: "Guiding the flight", paragraphs: [6]),
      Section(title: "Discussion", paragraphs: [7]),
    ],
    captions: [
      .dance:
        "The waggle dance on the vertical face of the cluster. (a) The scout's straight run points as far from vertical as the site lies from the sun's azimuth, here *θ* = 40°; the return loops alternate left and right. (b) Circuits danced on successive returns, for an excellent and a mediocre site: both decline by about fifteen circuits a trip, so support for the poorer site dies out first.",
      .quorum:
        "Scouts present at two candidate sites through a decision (schematic). Stop signals between the two camps suppress the weaker site; once about twenty scouts are present at one site together (dotted), piping begins and the swarm lifts off within the hour.",
    ],
    table: Table(
      caption: "What scouts measure in a cavity, and the values swarms choose and avoid.",
      header: ["Property", "Chosen", "Avoided"],
      rows: [
        ["Cavity volume", "≈ 40 L", "< 10 L or > 100 L"],
        ["Entrance area", "≈ 15 cm^{2}", "> 75 cm^{2}"],
        ["Entrance height", "> 3 m", "near the ground"],
        ["Entrance faces", "the sun", "away from it"],
      ]),
    references: [
      "M. Lindauer, Z. Vergl. Physiol. **37**, 263 (1955).",
      "K. von Frisch, *The Dance Language and Orientation of Bees* (Harvard University Press, Cambridge, MA, 1967).",
      "T. D. Seeley and R. A. Morse, Insectes Soc. **25**, 323 (1978).",
      "T. D. Seeley and S. C. Buhrman, Behav. Ecol. Sociobiol. **45**, 19 (1999).",
      "T. D. Seeley and P. K. Visscher, Behav. Ecol. Sociobiol. **56**, 594 (2004).",
      "K. M. Passino and T. D. Seeley, Behav. Ecol. Sociobiol. **59**, 427 (2006).",
      "M. Beekman, R. L. Fathke, and T. D. Seeley, Anim. Behav. **71**, 161 (2006).",
      "T. D. Seeley, *Honeybee Democracy* (Princeton University Press, Princeton, NJ, 2010).",
      "T. D. Seeley *et al.*, Science **335**, 108 (2012).",
      "J. A. R. Marshall *et al.*, J. R. Soc. Interface **6**, 1065 (2009).",
    ])
}

/// What a section sets after its paragraphs.
enum Extra {
  case equation(String)
  case figure(Figure)
  case table
}

// ─── Plans ───────────────────────────────────────────────────────────────────

enum Paper {
  /// The page for a look: the text's paragraphs, in order, and whatever that
  /// look sets around them. The plain and paper looks show the first `core`
  /// of the `n` paragraphs; the journal shows them all. `height` is how tall a
  /// paragraph reads now, for balancing the journal's columns.
  static func plan(
    _ style: ReadingStyle, _ sheet: Sheet, _ manuscript: Manuscript, core: Int, paragraphs n: Int, height: (Int) -> Double
  ) -> [Band] {
    let press = Press(style: style, sheet: sheet, manuscript: manuscript)
    switch style {
    case .plain: return [.span((0..<core).map { .para($0) })]
    case .paper: return press.paper(core)
    case .journal: return press.journal(core, n, height: height)
    }
  }
}

/// Sets everything on the page that isn't the paragraphs, in the look's type.
struct Press {
  let style: ReadingStyle
  let sheet: Sheet
  /// The paper whose title page, sections and figures it sets; a document
  /// brought in sets only its own text, and never asks.
  var manuscript: Manuscript = .blackHoles

  var serif: Bool { style == .journal }
  /// The body text size.
  var size: CGFloat { sheet.fontSize }
  private var column: CGFloat { CGFloat(sheet.column) }
  private var full: CGFloat { CGFloat(sheet.width) }
  /// The whole width of the text.
  var fullWidth: CGFloat { full }

  // ─── Paper ─────────────────────────────────────────────────────────────

  fileprivate func paper(_ n: Int) -> [Band] {
    let w = full
    var e: [Entry] = []
    let m = manuscript
    e.append(text(rich(m.preprint, size: size * 0.62, color: Palette.muted, bold: true, tracking: 1.4), width: w, below: size * 1.1))
    e.append(landmark(text(rich(m.title, size: size * 1.7, bold: true, leading: 1.18), width: w, below: size * 0.8), m.title, level: 0))
    e.append(text(rich(m.byline, size: size * 0.9), width: w, below: size * 0.3))
    let places = m.affiliations.enumerated().map { "^{\($0 + 1)}\($1.short)" }.joined(separator: "   ")
    e.append(text(rich(places, size: size * 0.7, color: Palette.quiet, leading: 1.5), width: w, below: size * 1.6))
    e.append(abstractBlock(width: w))
    e.append(text(rich("**Keywords**   " + m.keywords, size: size * 0.7, color: Palette.quiet, leading: 1.5), width: w, below: size * 0.6))
    e.append(rule(width: w, below: 0))

    var counter = Counter()
    var placed = Set<Int>()
    for (k, s) in m.sections.enumerated() {
      let shown = s.paragraphs.filter { $0 < n }
      guard !shown.isEmpty else { continue }
      e.append(heading(k, s.title, width: w, first: k == 0))
      for i in shown { e.append(.para(i)) }
      placed.formUnion(shown)
      e += s.after.map { extra($0, &counter, width: w) }
    }
    for i in 0..<n where !placed.contains(i) { e.append(.para(i)) }

    e.append(landmark(text(rich("References", size: size * 1.2, bold: true), width: w, above: size * 2, below: size * 0.7), "References", level: 1))
    e.append(text(references(m.references, from: 1, size: size * 0.72, color: Palette.quiet), width: w, below: size * 2))
    return [.span(e)]
  }

  private func abstractBlock(width: CGFloat) -> Entry {
    let label = rich("ABSTRACT", size: size * 0.62, color: Palette.muted, bold: true, tracking: 1.4)
    let body = rich(manuscript.abstract, size: size * 0.85, color: Palette.quiet, leading: 1.5)
    let inset: CGFloat = 20
    let lh = textHeight(label, width - inset)
    let bh = textHeight(body, width - inset)
    let gap = size * 0.5
    let below = size * 1.1
    return .block(
      Block(width: width, height: lh + gap + bh + below) { r in
        resolved(Palette.line).setFill()
        UIRectFill(CGRect(x: 0, y: 2, width: 3, height: lh + gap + bh - 2))
        drawText(label, CGRect(x: inset, y: 0, width: width - inset, height: lh))
        drawText(body, CGRect(x: inset, y: lh + gap, width: width - inset, height: bh))
      })
  }

  // ─── Journal ───────────────────────────────────────────────────────────

  fileprivate func journal(_ core: Int, _ n: Int, height: (Int) -> Double) -> [Band] {
    let w = full
    let col = column
    let m = manuscript
    var head: [Entry] = []
    head.append(runningHead(width: w))
    head.append(landmark(text(rich(m.title, size: size * 1.32, bold: true, align: .center, leading: 1.2), width: w, inset: w * 0.06, below: size * 0.9), m.title, level: 0))
    head.append(text(rich(m.journalByline, size: size * 0.98, align: .center), width: w, below: size * 0.35))
    let places = m.affiliations.enumerated().map { "^{\($0 + 1)}*\($1.full)*" }.joined(separator: "\n")
    head.append(text(rich(places, size: size * 0.8, align: .center, leading: 1.3), width: w, below: size * 0.6))
    head.append(text(rich(m.received, size: size * 0.78, align: .center), width: w, below: size * 1.1))
    head.append(text(rich(m.abstract, size: size * 0.92, align: .justified, leading: 1.28), width: w, inset: w * 0.07, below: size * 0.7))
    head.append(text(rich(m.doi, size: size * 0.78, align: .center), width: w, below: size * 1.6))

    // The text runs down the left column and on at the top of the right, split
    // where the two come out most even for the paragraphs as they read now.
    // Equations follow their paragraph; figures and tables follow the section.
    var counter = Counter()
    var flow: [(entry: Entry, height: Double, heading: Bool)] = []
    var wide: [Entry] = []
    func add(_ e: Entry, heading: Bool = false) {
      switch e {
      case let .para(i): flow.append((e, height(i), false))
      case let .block(b): flow.append((e, b.height, heading))
      }
    }
    var placed = Set<Int>()
    for (k, s) in m.sections.enumerated() {
      let shown = s.paragraphs.filter { $0 < core }
      guard !shown.isEmpty else { continue }
      add(heading(k, s.title, width: col, first: k == 0), heading: true)
      for i in shown { add(.para(i)) }
      placed.formUnion(shown)
      let after = s.after
      for x in after { if case .equation = x { add(extra(x, &counter, width: col)) } }
      for j in s.more where j < n {
        add(.para(j))
        placed.insert(j)
      }
      for x in after {
        if case .equation = x { continue }
        if case let .figure(f) = x, f.wide, sheet.columns > 1 {
          wide.append(extra(x, &counter, width: w))
        } else {
          add(extra(x, &counter, width: col))
        }
      }
    }
    for j in 0..<n where !placed.contains(j) { add(.para(j)) }

    var bands: [Band] = [.span(head)]
    if sheet.columns > 1 {
      let split = balance(flow.map { ($0.height, $0.heading) })
      bands.append(.columns([flow[..<split].map(\.entry), flow[split...].map(\.entry)]))
    } else {
      bands.append(.span(flow.map(\.entry)))
    }
    bands.append(.span(wide))

    // References in footnote type, split across the columns.
    let refs = m.references
    let half = (refs.count + 1) / 2
    let small = size * 0.78
    bands.append(.span([landmark(rule(width: w, short: true, above: size * 0.6, below: size * 0.8), "References", level: 1)]))
    if sheet.columns > 1 {
      bands.append(
        .columns([
          [text(references(Array(refs[..<half]), from: 1, size: small), width: col)],
          [text(references(Array(refs[half...]), from: half + 1, size: small), width: col)],
        ]))
    } else {
      bands.append(.span([text(references(refs, from: 1, size: small), width: col)]))
    }
    bands.append(.span([footer(width: w)]))
    return bands
  }

  /// Where to start the right column so that the taller column is as short as
  /// it can be, never leaving a heading at the foot of the left one.
  private func balance(_ items: [(height: Double, heading: Bool)]) -> Int {
    let total = items.reduce(0) { $0 + $1.height }
    var best = items.count
    var bestTall = Double.infinity
    var left = 0.0
    for k in 1..<max(items.count, 1) {
      left += items[k - 1].height
      guard !items[k - 1].heading else { continue }
      let tall = max(left, total - left)
      if tall < bestTall {
        bestTall = tall
        best = k
      }
    }
    return best
  }

  /// The journal's name, volume and date above a rule, as at the top of every page.
  private func runningHead(width: CGFloat) -> Entry {
    let s = size * 0.72
    let left = rich(manuscript.journal, size: s, tracking: 0.3)
    let right = rich(manuscript.date, size: s, tracking: 0.3)
    let h = left.size().height
    let below = size * 1.6
    return .block(
      Block(width: width, height: h + 6 + 3 + below) { r in
        left.draw(at: .zero)
        let rw = right.size().width
        if left.size().width + rw + 24 < width { right.draw(at: CGPoint(x: width - rw, y: 0)) }
        resolved(Palette.ink).setFill()
        UIRectFill(CGRect(x: 0, y: h + 5, width: width, height: 0.8))
        UIRectFill(CGRect(x: 0, y: h + 7.5, width: width, height: 0.8))
      })
  }

  private func footer(width: CGFloat) -> Entry {
    let s = size * 0.68
    let left = rich(manuscript.footer.left, size: s)
    let right = rich(manuscript.footer.right, size: s)
    let above = size * 2.2
    let h = left.size().height
    return .block(
      Block(width: width, height: above + 8 + h + size * 3) { r in
        resolved(Palette.ink).setFill()
        UIRectFill(CGRect(x: 0, y: above, width: width, height: 0.6))
        left.draw(at: CGPoint(x: 0, y: above + 6))
        let rw = right.size().width
        if left.size().width + rw + 24 < width { right.draw(at: CGPoint(x: width - rw, y: above + 6)) }
      })
  }

  // ─── Pieces both looks use ─────────────────────────────────────────────

  private struct Counter {
    var equation = 0
    var figure = 0
    var table = 0
  }

  private func heading(_ i: Int, _ title: String, width: CGFloat, first: Bool) -> Entry {
    if serif {
      let s = rich("\(Manuscript.roman[safe: i] ?? "\(i + 1)"). \(title.uppercased())", size: size * 0.86, bold: true, align: .center, tracking: 0.5)
      return landmark(text(s, width: width, above: first ? 0 : size * 1.0, below: size * 0.55), title, level: 1)
    }
    let s = rich("\(i + 1)\u{2003}\(title)", size: size * 1.2, bold: true)
    return landmark(text(s, width: width, above: first ? size * 1.6 : size * 2.0, below: size * 0.55), title, level: 1)
  }

  /// `entry`, under the name the contents know it by.
  private func landmark(_ entry: Entry, _ title: String, level: Int) -> Entry {
    if case let .block(b) = entry { b.landmark = (title, level) }
    return entry
  }

  private func extra(_ x: Extra, _ counter: inout Counter, width: CGFloat) -> Entry {
    switch x {
    case let .equation(tex):
      counter.equation += 1
      return equation(tex, number: counter.equation, width: width)
    case let .figure(f):
      counter.figure += 1
      return figure(f, number: counter.figure, width: width)
    case .table:
      counter.table += 1
      return table(number: counter.table, width: width)
    }
  }

  /// A displayed equation, centered, with its number at the right.
  private func equation(_ tex: String, number: Int, width: CGFloat) -> Entry {
    let family = serif ? "Times New Roman" : nil
    let tag = rich("(\(number))", size: size)
    let tagW = tag.size().width
    var mathSize = size * 1.04
    var math = TeX(tex, size: mathSize, family: family)
    let room = width - 2 * (tagW + 12)
    if math.x > room {
      mathSize *= room / math.x
      math = TeX(tex, size: mathSize, family: family)
    }
    let above = size * (serif ? 0.45 : 0.7)
    let line = size * 1.9
    let below = size * (serif ? 0.45 : 0.7)
    let tagFont = font(size)
    return .block(
      Block(width: width, height: above + line + below) { r in
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let baseline = above + line * 0.66
        ctx.setFillColor(resolved(Palette.ink).cgColor)
        drawPieces(math.pieces, in: ctx, x: ((width - math.x) / 2).rounded(), baseline: baseline)
        tag.draw(at: CGPoint(x: width - tagW, y: baseline - tagFont.ascender))
      })
  }

  /// A drawn figure and its caption.
  private func figure(_ f: Figure, number: Int, width: CGFloat) -> Entry {
    let aspect: CGFloat
    switch (f, serif) {
    case (.radius, false): aspect = 0.6
    case (.radius, true): aspect = 0.66
    case (.star, false): aspect = 0.46
    case (.star, true): aspect = 0.52
    case (.cones, false): aspect = 0.58
    case (.cones, true): aspect = 0.62
    case (.clocks, false): aspect = 0.54
    case (.clocks, true): aspect = 0.6
    case (.evidence, _), (.dance, _): aspect = width > 700 ? (serif ? 0.3 : 0.34) : 0.5
    case (.quorum, false): aspect = 0.54
    case (.quorum, true): aspect = 0.6
    }
    let graphic = (width * aspect).rounded()
    let caption =
      serif
      ? rich("FIG. \(number). " + (manuscript.captions[f] ?? ""), size: size * 0.86, align: .justified, leading: 1.22)
      : rich("**Figure \(number).** " + (manuscript.captions[f] ?? ""), size: size * 0.75, color: Palette.quiet, leading: 1.45)
    let inset = serif ? 0 : width * 0.04
    let capH = textHeight(caption, width - 2 * inset)
    let above = size * (serif ? 0.7 : 1.4)
    let gap = size * 0.7
    let below = size * (serif ? 1.0 : 1.4)
    return .block(
      Block(width: width, height: above + graphic + gap + capH + below) { r in
        self.draw(f, in: CGRect(x: 0, y: above, width: width, height: graphic))
        drawText(caption, CGRect(x: inset, y: above + graphic + gap, width: width - 2 * inset, height: capH))
      })
  }

  /// A table between rules, captioned above as tables are.
  private func table(number: Int, width: CGFloat) -> Entry {
    guard let t = manuscript.table, t.header.count > 1 else { return .block(Block(width: width, height: 0) { _ in }) }
    let ts = size * (serif ? 0.84 : 0.72)
    let caption =
      serif
      ? rich("TABLE \(Manuscript.roman[safe: number - 1] ?? "\(number)"). " + t.caption, size: size * 0.86, align: .justified, leading: 1.22)
      : rich("**Table \(number).** " + t.caption, size: size * 0.75, color: Palette.quiet, leading: 1.45)
    let header = t.header.map { rich($0, size: ts, bold: !serif) }
    let rows = t.rows.map { $0.map { rich($0, size: ts) } }
    let cols = header.count
    var widths = header.map { $0.size().width }
    for row in rows { for (j, c) in row.enumerated() { widths[j] = max(widths[j], c.size().width) } }
    // Columns spread to fill the width, but not so far that a row stops reading as one.
    let pad = min(max(8, (width - widths.reduce(0, +)) / CGFloat(cols - 1)), ts * 3.5)
    let span = widths.reduce(0, +) + pad * CGFloat(cols - 1)
    let x0 = ((width - span) / 2).rounded()
    var xs: [CGFloat] = [x0]
    for j in 1..<cols { xs.append(xs[j - 1] + widths[j - 1] + pad) }
    let capH = textHeight(caption, width)
    let rowH = (ts * 1.65).rounded()
    let above = size * (serif ? 0.7 : 1.4)
    let gap = ts * 0.6
    let below = size * (serif ? 1.0 : 1.4)
    let tableH = rowH * CGFloat(rows.count + 1) + 12
    return .block(
      Block(width: width, height: above + capH + gap + tableH + below) { r in
        drawText(caption, CGRect(x: 0, y: above, width: width, height: capH))
        var y = above + capH + gap
        resolved(Palette.ink).setFill()
        func hline(_ t: CGFloat) {
          UIRectFill(CGRect(x: x0, y: y, width: span, height: t))
        }
        // Journals rule a table twice above and below; preprints once, heavier.
        if serif {
          hline(0.6)
          y += 2.4
          hline(0.6)
          y += 3
        } else {
          hline(1.2)
          y += 4
        }
        func line(_ cells: [NSAttributedString]) {
          for (j, c) in cells.enumerated() {
            c.draw(at: CGPoint(x: xs[j], y: y + (rowH - c.size().height) / 2))
          }
          y += rowH
        }
        line(header)
        hline(serif ? 0.6 : 0.6)
        y += 2
        for row in rows { line(row) }
        if serif {
          hline(0.6)
          y += 2.4
          hline(0.6)
        } else {
          hline(1.2)
        }
      })
  }

  private func references(_ refs: [String], from first: Int, size s: CGFloat, color: UIColor = Palette.ink) -> NSAttributedString {
    let indent = s * 2
    let out = NSMutableAttributedString()
    for (i, r) in refs.enumerated() {
      let entry = rich("[\(first + i)]\t" + r + (i < refs.count - 1 ? "\n" : ""), size: s, color: color, align: serif ? .justified : .natural, leading: 1.3)
      out.append(entry)
    }
    let ps = NSMutableParagraphStyle()
    ps.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
    ps.defaultTabInterval = indent
    ps.headIndent = indent
    ps.alignment = serif ? .justified : .natural
    ps.minimumLineHeight = (s * 1.3).rounded()
    ps.maximumLineHeight = (s * 1.3).rounded()
    ps.paragraphSpacing = s * (serif ? 0.15 : 0.5)
    ps.hyphenationFactor = serif ? 0.8 : 0
    out.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: out.length))
    return out
  }

  private func rule(width: CGFloat, short: Bool = false, above: CGFloat = 0, below: CGFloat) -> Entry {
    .block(
      Block(width: width, height: above + 1 + below) { r in
        resolved(short ? Palette.ink : Palette.line).setFill()
        let w = short ? width * 0.2 : width
        UIRectFill(CGRect(x: (width - w) / 2, y: above, width: w, height: short ? 0.6 : 1))
      })
  }

  /// A run of text across `width`, with room above and below.
  func textBlock(_ s: NSAttributedString, width: CGFloat, above: CGFloat = 0, below: CGFloat = 0) -> Entry {
    text(s, width: width, above: above, below: below)
  }

  /// A run of text across `width`, with room above and below, and `inset` from either side.
  private func text(_ s: NSAttributedString, width: CGFloat, inset: CGFloat = 0, above: CGFloat = 0, below: CGFloat = 0) -> Entry {
    let w = width - 2 * inset
    let h = textHeight(s, w)
    return .block(Block(width: width, height: above + h + below) { r in drawText(s, CGRect(x: inset, y: above, width: w, height: h)) })
  }

  // ─── Type ──────────────────────────────────────────────────────────────

  func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
    if serif {
      let name =
        bold && italic
        ? "TimesNewRomanPS-BoldItalicMT" : bold ? "TimesNewRomanPS-BoldMT" : italic ? "TimesNewRomanPS-ItalicMT" : "TimesNewRomanPSMT"
      return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }
    let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    guard italic, let d = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
    return UIFont(descriptor: d, size: size)
  }

  /// Sets a little markup: *italic*, **bold**, _{subscript} and ^{superscript};
  /// a backslash keeps the next character as it is. `leading` fixes the line height, as a share of `size`.
  func rich(
    _ s: String, size: CGFloat, color: UIColor = Palette.ink, bold: Bool = false, align: NSTextAlignment = .natural,
    leading: CGFloat? = nil, tracking: CGFloat = 0
  ) -> NSMutableAttributedString {
    let out = NSMutableAttributedString()
    var italic = false
    var strong = bold
    var script = 0
    var run = ""
    func flush() {
      guard !run.isEmpty else { return }
      var attrs: [NSAttributedString.Key: Any] = [
        .font: font(script == 0 ? size : size * 0.7, bold: strong, italic: italic), .foregroundColor: color,
      ]
      if script != 0 { attrs[.baselineOffset] = script > 0 ? size * 0.36 : -size * 0.15 }
      if tracking != 0 { attrs[.kern] = tracking }
      out.append(NSAttributedString(string: run, attributes: attrs))
      run = ""
    }
    let chars = Array(s)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      let n = chars[safe: i + 1]
      if c == "\\", let n {
        run.append(n)
        i += 2
      } else if c == "*" {
        flush()
        if n == "*" {
          strong.toggle()
          i += 2
        } else {
          italic.toggle()
          i += 1
        }
      } else if c == "_" || c == "^", n == "{" {
        flush()
        script = c == "^" ? 1 : -1
        i += 2
      } else if c == "}" && script != 0 {
        flush()
        script = 0
        i += 1
      } else {
        run.append(c)
        i += 1
      }
    }
    flush()
    let ps = NSMutableParagraphStyle()
    ps.alignment = align
    if let leading {
      ps.minimumLineHeight = (size * leading).rounded()
      ps.maximumLineHeight = (size * leading).rounded()
    }
    ps.hyphenationFactor = align == .justified ? 0.9 : 0
    out.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: out.length))
    return out
  }
}

// ─── Drawing text ────────────────────────────────────────────────────────────

/// A color as it reads in the appearance being drawn.
func resolved(_ c: UIColor) -> UIColor { c.resolvedColor(with: .current) }

func textHeight(_ s: NSAttributedString, _ width: CGFloat) -> CGFloat {
  s.boundingRect(
    with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
    context: nil
  ).height.rounded(.up)
}

func drawText(_ s: NSAttributedString, _ rect: CGRect) {
  s.draw(with: rect.insetBy(dx: 0, dy: -1).offsetBy(dx: 0, dy: 1), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
}
