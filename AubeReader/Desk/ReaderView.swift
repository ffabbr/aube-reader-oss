import UIKit

/// A word's place in the morph underway, and the layers that draw it. A word
/// shared by both versions but spelled differently (punctuation, case) is drawn
/// twice and crossfades in place.
private struct Item {
  let layer: WordLayer
  let alt: WordLayer?
  let a: Int
  let b: Int
}

/// One paragraph on the page: where it sits on the grid of versions (its
/// difficulty `c` and zoom `z`, each a spring), the layer it's drawn in, and
/// the morph between versions it's part way through.
final class Para {
  let layer = StillLayer()
  /// Difficulty, 0 = simplest.
  let c: Spring
  /// Zoom, 0 = most detailed.
  let z: Spring
  fileprivate var pair: Morph.Pair?
  /// What the two versions of `pair` were when the words were set out from them.
  fileprivate var revisions: [Int] = []
  /// As more of a version is written, the words that came, fading in where
  /// they stand (by layer, from when); the placeholders they cover, fading
  /// out where they stood as the words over them fade in; and the height it
  /// grew or shrank from, easing over. A word's fade can start a little after
  /// it came, so that bursts of words are let in at a steady pace.
  fileprivate var arriving: [ObjectIdentifier: CFTimeInterval] = [:]
  fileprivate var going: [(layer: WordLayer, since: CFTimeInterval, from: Double)] = []
  fileprivate var grew: (from: Double, since: CFTimeInterval)?
  /// When the last word to come starts fading in.
  fileprivate var revealed: CFTimeInterval = 0
  fileprivate var items: [Item] = []
  /// Word layers not in use, kept to be used again.
  fileprivate var spare: [WordLayer] = []
  fileprivate var drawn: (t: Double, version: Int)?
  fileprivate var placed: CGPoint?
  /// The left edge of the paragraph's column, on the page.
  var x = 0.0
  var top = 0.0
  var height = 0.0
  /// How wide it runs, where it differs from the look's column.
  var width: Double?
  /// How far in from the left of its column its words start.
  var inset = 0.0
  /// On an original page, the tile it lies on while it's just as it was found.
  var tile: ParaTile?
  /// How much of it is the original on show: 1 as found, 0 once it's been changed at all.
  var original = 0.0
  /// Whether its layer is on the page, where a long text keeps only what's near the screen.
  fileprivate var attached = false
  /// Whether it's been set for real this time near the screen, or only guessed at.
  fileprivate var isSet = false
  /// The ink its words are written in, where that isn't the page's own.
  fileprivate var ink: CGColor?

  init(c: Double, z: Double) {
    self.c = Spring(c, response: Feel.settle)
    self.z = Spring(z, response: Feel.settle)
    layer.anchorPoint = .zero
  }

  /// How long a word takes to fade in or out as it's written, and how long
  /// after the word before it each starts.
  static let fade = 0.5
  static let pace = 0.025

  var fading: Bool { !arriving.isEmpty || !going.isEmpty || grew != nil }

  /// Puts away what was fading at once: what came shows, what went is gone.
  fileprivate func settle() {
    arriving = [:]
    for g in going {
      g.layer.isHidden = true
      g.layer.shown = nil
      spare.append(g.layer)
    }
    going = []
    grew = nil
  }
}

/// A page of text whose paragraphs each sit somewhere on a grid of versions,
/// and morph word by word between them. The page can be dressed as plain
/// prose, as a paper, or as a two-column journal page (see `ReadingStyle`).
final class ReaderView: UIView {
  let edition: Edition
  /// The page itself, clipped to the screen; everything drawn goes in it.
  let content = UIView()

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
  let stage = StillLayer()
  let paras: [Para]
  private(set) var style: ReadingStyle
  /// Called after the look changes, so what depends on the look can follow.
  var onStyle: (() -> Void)?
  /// Called when the home button is tapped.
  var onHome: (() -> Void)?
  /// Called when the ring is tapped, to open or put away the contents.
  var onContents: (() -> Void)?
  /// Where the text sits on the page in the current look.
  private(set) var sheet: Sheet
  /// The paragraphs, and everything set around them, in reading order.
  private var plan: [Band] = []
  private var blocks: [Block] = []
  /// The paragraphs this look shows, in reading order, and each paragraph's
  /// place in that order (nil for one the look leaves out).
  private(set) var order: [Int] = []
  private var rank: [Int?] = []
  private let styleButton = UIButton(type: .system)
  private let styleName = UILabel()
  private let homeButton = UIButton(type: .system)
  /// How far through the document the reader is, in the corner.
  private let ring = PageRing()
  /// Where each page of the original starts on an original page, and what the
  /// clean looks set from each, in order, to tell which page is being read.
  private var pageTops: [Double] = []
  private var pageStops: [(entry: Entry, page: Int)] = []
  private var ringSeen: (y: Double, h: Double)?
  /// The point of the text that stays put while the layout changes under it.
  var anchor = (index: 0, frac: 0.0, screenY: 0.0)
  let offset = Spring(0, response: 0.42, precision: 0.05)
  var currentY = 0.0
  var contentH = 0.0
  /// How far a pinch is being pulled past the ends; shown as the page stretching.
  let stretch = Spring(0, response: Feel.settle)
  var origin = CGPoint.zero
  private var staged: Double = 1
  /// A long text keeps layers only for what's near the screen.
  private let windowed: Bool
  /// The bands' paragraphs and blocks have to be sized before anything is known about where they lie.
  private var unsized = true

  init(edition: Edition, c: [Int]?, z: [Int]?, style: ReadingStyle = .plain) {
    self.edition = edition
    let style = edition.texts.looks.contains(style) ? style : edition.texts.looks[0]
    self.style = style
    sheet = edition.sheet(style)
    let texts = edition.texts
    paras = (0..<texts.count).map { i in
      let home = texts.home(i)
      return Para(
        c: clamp(Double(c?[safe: i] ?? home.c), 0, Double(edition.cMax)),
        z: clamp(Double(z?[safe: i] ?? home.z), 0, Double(edition.zMax))
      )
    }
    windowed = edition.book != nil || paras.count > 60
    super.init(frame: .zero)
    content.backgroundColor = Palette.page
    content.clipsToBounds = true
    addSubview(content)
    stage.anchorPoint = .zero
    self.content.layer.addSublayer(stage)
    if !windowed {
      for p in paras {
        stage.addSublayer(p.layer)
        p.attached = true
      }
    }
    setUpStyleButton()
    replan()
    isAccessibilityElement = true
    accessibilityTraits = .staticText
    accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: "Next Reading Style") { [weak self] _ in
        self?.nextStyle()
        return true
      },
      UIAccessibilityCustomAction(name: "Contents") { [weak self] _ in
        self?.onContents?()
        return true
      },
    ]
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (self: ReaderView, _) in
      self.restyle()
    }
  }

  var typeset: Typeset { edition.typeset(style) }
  private var lineHeight: Double { Double(typeset.setter.lineHeight) }

  /// Whether `x` is over the text, give or take `Feel.textSlop`.
  func overText(_ x: Double) -> Bool {
    x > sheet.left - Feel.textSlop && x < sheet.left + sheet.width + Feel.textSlop
  }

  /// The text as it currently reads, for VoiceOver.
  override var accessibilityLabel: String? {
    get {
      order.map { spoken($0) }.joined(separator: "\n\n")
    }
    set {}
  }

  /// How far through it the reader is, which the ring shows and VoiceOver says.
  override var accessibilityValue: String? {
    get {
      let spot = readingSpot()
      return spot.of > 1 ? "Page \(spot.page + 1) of \(spot.of)" : nil
    }
    set {}
  }

  /// Paragraph `i` to be read aloud, with what's in its footnotes said where each is marked.
  private func spoken(_ i: Int) -> String {
    let p = paras[i]
    let d = edition.texts.draft(i, Int(p.c.target.rounded()), Int(p.z.target.rounded()))
    guard d.text.contains("[^") else { return text(of: i) }
    let said = NoteToken.keep(d.text) { id in self.edition.spokenNote(id).map { " (Footnote: \($0))" } }
    return edition.book != nil ? said : said.replacingOccurrences(of: "$", with: "")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    content.frame = bounds
    styleButton.frame = CGRect(x: bounds.width - 52, y: 14, width: 40, height: 40)
    homeButton.frame = CGRect(x: 12, y: 14, width: 40, height: 40)
    // Under Home, on a line with it, as far from the bottom as it is from the top.
    ring.center = CGPoint(x: homeButton.center.x, y: bounds.height - homeButton.center.y)
    dressButtons()
    styleName.sizeToFit()
    styleName.bounds.size.width = min(styleName.bounds.width, max(0, bounds.width - 140))
    styleName.center = CGPoint(x: styleButton.frame.minX - 2 - styleName.bounds.width / 2, y: styleButton.center.y)
  }

  /// Forgets everything drawn, after the layouts or the appearance changed.
  func restyle() {
    let ink = Palette.ink.resolvedColor(with: traitCollection).cgColor
    let scale = traitCollection.displayScale
    replan()
    for p in paras {
      p.settle()
      for l in p.items.flatMap({ [$0.layer] + ($0.alt.map { [$0] } ?? []) }) + p.spare {
        l.ink = p.ink ?? ink
        l.contentsScale = scale
      }
      p.pair = nil
      p.drawn = nil
      p.placed = nil
    }
    staged = .nan
  }

  /// Sets out the page again for the current look and width: where the text
  /// goes, and the titles, figures and the rest around it.
  private func replan() {
    for b in blocks { b.detach() }
    sheet = edition.sheet(style)
    let set = typeset
    let (cMax, zMax) = (Double(edition.cMax), Double(edition.zMax))
    if let book = edition.book {
      plan = book.plan(style, sheet, traits: traitCollection)
      let dark = traitCollection.userInterfaceStyle == .dark
      for (i, p) in paras.enumerated() {
        p.tile = style == .journal ? book.tiles[i] : nil
        p.width = p.tile?.width
        p.inset = style == .journal ? 0 : Double(book.cleanInset(i, size: sheet.fontSize))
        p.ink = style == .journal ? book.ink(i, dark: dark)?.cgColor : nil
        // Over an original page it's hidden while the page shows it. Everywhere else it's all there is.
        if p.tile == nil { p.layer.opacity = 1 }
      }
      // An original page is printed on its own paper.
      content.backgroundColor = style == .journal ? (book.paper(dark: dark) ?? Palette.page) : Palette.page
    } else if let manuscript = edition.manuscript {
      plan = Paper.plan(style, sheet, manuscript, core: edition.texts.coreCount, paragraphs: paras.count, traits: traitCollection) { i in
        let p = self.paras[i]
        return set.layout(i, (Int(clamp(p.c.target, 0, cMax).rounded()), Int(clamp(p.z.target, 0, zMax).rounded()))).height
      }
    } else {
      plan = [.span((0..<edition.texts.coreCount).map { .para($0) })]
    }
    let entries = plan.flatMap(\.entries)
    order = entries.compactMap { if case let .para(i) = $0 { return i } else { return nil } }
    rank = paras.map { _ in nil }
    for (k, i) in order.enumerated() { rank[i] = k }
    for (i, p) in paras.enumerated() {
      p.layer.isHidden = rank[i] == nil
      if rank[i] == nil {
        p.height = 0
        p.top = 0
      }
    }
    for p in paras { p.isSet = false }
    blocks = entries.compactMap { if case let .block(b) = $0 { return b } else { return nil } }
    pageTops = []
    ringSeen = nil
    pageStops = []
    if let book = edition.book, style != .journal {
      pageStops = entries.compactMap { e in
        switch e {
        case let .para(i): return (e, book.page(ofParagraph: i))
        case let .block(b): return b.page.map { (e, $0) }
        }
      }
    }
    for b in blocks {
      b.layer.contentsScale = traitCollection.displayScale
      b.layer.traits = traitCollection
      b.placed = nil
    }
    unsized = true
    dressButtons()
    styleButton.accessibilityValue = edition.name(style)
    refreshMenu()
  }

  /// Home is dressed as Aa is: bare on the plain look, if the margin keeps the text
  /// clear of them, and on a circle otherwise. The ring goes by the same margin.
  private var dressed: (bare: Bool, ink: ReadingStyle)?

  private func dressButtons() {
    let cramped = CGFloat(edition.sheet(.plain).left) < homeButton.frame.maxX
    let bare = style == .plain && !cramped
    // Called with every layout, and dressing a button asks for another.
    guard dressed?.bare != bare || dressed?.ink != style else { ring.plated = cramped; return }
    dressed = (bare, style)
    for button in [styleButton, homeButton] {
      var config = button.configuration ?? .plain()
      config.baseForegroundColor = bare ? Palette.quiet : Palette.ink
      config.background.backgroundColor = bare ? .clear : Palette.fill
      button.configuration = config
    }
    ring.plated = cramped
  }

  // ─── Reading style ───────────────────────────────────────────────────────

  private func setUpStyleButton() {
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: "textformat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
    config.cornerStyle = .capsule
    config.contentInsets = .zero
    styleButton.configuration = config
    styleButton.isPointerInteractionEnabled = true
    styleButton.accessibilityLabel = "Reading Style"
    styleButton.showsMenuAsPrimaryAction = true
    // The current look and model can change, so the menu is rebuilt each time it opens.
    styleButton.addAction(UIAction { [weak self] _ in self?.refreshMenu() }, for: .menuActionTriggered)
    styleName.font = .systemFont(ofSize: 13, weight: .medium)
    styleName.lineBreakMode = .byTruncatingTail
    styleName.textColor = Palette.muted
    styleName.alpha = 0
    content.addSubview(styleName)
    content.addSubview(styleButton)

    // Home mirrors Aa in the opposite corner.
    var home = UIButton.Configuration.plain()
    home.image = UIImage(systemName: "house", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
    home.cornerStyle = .capsule
    home.contentInsets = .zero
    home.baseForegroundColor = Palette.quiet
    homeButton.configuration = home
    homeButton.isPointerInteractionEnabled = true
    homeButton.accessibilityLabel = "Library"
    homeButton.addAction(UIAction { [weak self] _ in self?.onHome?() }, for: .primaryActionTriggered)
    content.addSubview(homeButton)
    ring.addAction(UIAction { [weak self] _ in self?.onContents?() }, for: .touchUpInside)
    content.addSubview(ring)
  }

  private func refreshMenu() { styleButton.menu = UIMenu(children: styleMenu()) }

  /// The looks to choose from; for a text written as it's read, what writes it.
  private func styleMenu() -> [UIMenuElement] {
    let looks = edition.texts.looks.map { s in
      UIAction(title: edition.name(s), image: UIImage(systemName: s.symbol), state: s == style ? .on : .off) { [weak self] _ in
        self?.setStyle(s)
      }
    }
    if let live = edition.texts as? LiveText { return importedMenu(looks, live) }
    return [UIMenu(options: .displayInline, children: looks)]
  }

  /// An imported document's looks, and what writes its versions.
  private func importedMenu(_ looks: [UIAction], _ live: LiveText) -> [UIMenuElement] {
    let forget = UIAction(
      title: "Forget Rewritten Versions", subtitle: "Each is written again when next wanted",
      image: UIImage(systemName: "arrow.counterclockwise"), attributes: .destructive
    ) { _ in live.forget() }
    return [
      UIMenu(options: .displayInline, children: looks),
      UIMenu(title: "Rewritten by \(OpenAI.model) as you read", options: .displayInline, children: [forget]),
    ]
  }

  /// Plain, then paper, then journal, then plain again: whichever of them the text has.
  @objc func nextStyle() {
    let looks = edition.texts.looks
    guard looks.count > 1 else { return }
    setStyle(looks[((looks.firstIndex(of: style) ?? 0) + 1) % looks.count])
    say(edition.name(style))
  }

  /// Shows `words` beside Aa for `seconds`, then lets them fade.
  func say(_ words: String, for seconds: Double = 0.9) {
    styleName.text = words
    setNeedsLayout()
    styleName.layer.removeAllAnimations()
    UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.styleName.alpha = 1
    } completion: { _ in
      UIView.animate(withDuration: 0.6, delay: seconds, options: [.allowUserInteraction]) { self.styleName.alpha = 0 }
    }
  }

  /// Dresses the page differently, keeping in place the text being read.
  func setStyle(_ next: ReadingStyle) {
    guard next != style, edition.texts.looks.contains(next) else { return }
    let atTop = currentY >= range().hi - 1
    if !atTop { anchorAt(Double(bounds.height) / 2, x: Double(bounds.width) / 2) }
    let before = order
    UIView.transition(with: content, duration: 0.4, options: [.transitionCrossDissolve, .allowUserInteraction]) {
      self.style = next
      self.restyle()
      self.layoutText()
      // A paragraph the new look leaves out hands the anchor to the one it followed.
      if self.rank[self.anchor.index] == nil, let k = before.firstIndex(of: self.anchor.index) {
        if let kept = before[..<k].last(where: { self.rank[$0] != nil }) ?? self.order.first {
          self.anchor.index = kept
          self.anchor.frac = 1
        }
      }
      if atTop {
        self.anchor = (self.order.first ?? 0, 0, 0)
        self.anchor.screenY = self.anchorRange().hi
        self.offset.snap(0)
      }
      self.place(0, held: false)
    }
    onStyle?()
  }

  // ─── Drawing ─────────────────────────────────────────────────────────────

  private func morph(_ p: Para) -> Morph {
    Morph(c: p.c.value, z: p.z.value, cMax: edition.cMax, zMax: edition.zMax)
  }

  /// Sets out `p`'s words for morph `m`. `written` when it's the same two
  /// versions with more of them written: words that come fade in, and words
  /// that go (most often the placeholders the words cover) fade out, each
  /// where it stands.
  private func rebuild(_ p: Para, _ pi: Int, _ m: Morph, written: Bool = false) {
    let set = typeset
    let wordsA = set.layout(pi, m.a).words
    let wordsB = set.layout(pi, m.b).words
    let tracks = set.tracks(pi, m)
    // Layers already showing a word keep showing it, so most words are drawn only
    // once. Matched by the typeset word itself, so a change of face redraws them.
    var free: [ObjectIdentifier: [WordLayer]] = [:]
    for l in p.items.flatMap({ [$0.layer] + ($0.alt.map { [$0] } ?? []) }) + p.spare {
      if let g = l.glyphs { free[ObjectIdentifier(g), default: []].append(l) }
    }
    // A word that appears more than once keeps its layers in reading order, the
    // first "the" on the first, so none sets off from another's place.
    func exact(_ g: Glyphs) -> WordLayer? {
      guard var list = free[ObjectIdentifier(g)], !list.isEmpty else { return nil }
      let l = list.removeFirst()
      free[ObjectIdentifier(g)] = list
      return l
    }
    var wants: [(main: Glyphs, alt: Glyphs?, track: Track)] = []
    for t in tracks {
      if t.a >= 0 && t.b >= 0 && wordsA[t.a].glyphs.text != wordsB[t.b].glyphs.text {
        wants.append((wordsA[t.a].glyphs, wordsB[t.b].glyphs, t))
      } else {
        wants.append((t.b >= 0 ? wordsB[t.b].glyphs : wordsA[t.a].glyphs, nil, t))
      }
    }
    var matched: [(WordLayer?, WordLayer?)] = wants.map { (exact($0.main), $0.alt.map(exact) ?? nil) }
    var leftover = free.values.flatMap { $0 }
    let now = CACurrentMediaTime()
    for l in leftover { p.arriving[ObjectIdentifier(l)] = nil }
    // Words that came, in reading order: where each line of them ends, and when each starts to show.
    var came: [(y: Double, end: Double, since: CFTimeInterval)] = []
    let going = written ? leftover.filter { !$0.isHidden } : []
    leftover.removeAll { written && !$0.isHidden }
    let ink = p.ink ?? Palette.ink.resolvedColor(with: traitCollection).cgColor
    let setter = set.setter(pi)
    func fresh(_ g: Glyphs) -> WordLayer {
      let l = leftover.popLast() ?? {
        let l = WordLayer()
        l.contentsScale = traitCollection.displayScale
        p.layer.addSublayer(l)
        return l
      }()
      l.ink = ink
      l.lineHeight = setter.lineHeight
      l.baseline = setter.baseline
      l.glyphs = g
      return l
    }
    p.items = wants.indices.map { i in
      let w = wants[i]
      // Whether a word was on show already: a layer kept from an earlier
      // version, put away until now, comes in like a new one.
      let before = [matched[i].0, matched[i].1].compactMap { $0 }.contains { !$0.isHidden || p.arriving[ObjectIdentifier($0)] != nil }
      let main = matched[i].0 ?? fresh(w.main)
      let alt = w.alt.map { matched[i].1 ?? fresh($0) }
      if written && !before {
        let since = max(now, p.revealed + Para.pace)
        p.revealed = since
        for l in [main, alt].compactMap({ $0 }) { p.arriving[ObjectIdentifier(l)] = since }
        let word = w.track.b >= 0 ? wordsB[w.track.b] : wordsA[w.track.a]
        came.append((word.y, word.x + Double(word.glyphs.width), since))
      }
      matched[i] = (main, alt)
      return Item(layer: main, alt: alt, a: w.track.a, b: w.track.b)
    }
    // Each placeholder that goes fades as the word written over it comes, or,
    // where no word lands on it, the next one after it does.
    for l in going {
      let s = l.shown ?? (0, 0, 1, 0)
      let over = came.first { $0.y > s.y + 1 || (abs($0.y - s.y) <= 1 && $0.end > s.x) }
      p.going.append((l, over?.since ?? came.last?.since ?? max(now, p.revealed), s.opacity))
    }
    for l in leftover {
      l.isHidden = true
      l.shown = nil
    }
    p.spare = leftover
  }

  /// How much of a paragraph is the original on show: all of it while it's as
  /// found, none once it's a whole step away, as the changed text takes over.
  private func originalShare(_ p: Para, _ pi: Int) -> Double {
    guard p.tile != nil else { return 0 }
    let home = edition.texts.home(pi)
    return 1 - min(1, abs(p.c.value - Double(home.c)) + abs(p.z.value - Double(home.z)))
  }

  private func draw(_ p: Para, _ pi: Int) {
    // Just as it was found, it's the page itself, and nothing need be set at all.
    let share = originalShare(p, pi)
    p.original = share
    if let tile = p.tile {
      tile.block.layer.opacity = Float(share)
      p.layer.opacity = Float(1 - share)
      if share >= 0.9999 {
        p.height = tile.inkHeight
        return
      }
    }
    var m = morph(p)
    let set = typeset
    // Neighboring levels can read the same (the journal's extra paragraphs are
    // written at fewer levels); between them there is nothing to morph.
    if m.t > 0 && set.same(pi, m.a, m.b) {
      m.b = m.a
      m.t = 0
      m.sideways = false
    }
    // More of a version written, or all of it: the words fade in over the
    // placeholders that stood for them, and nothing moves.
    let revisions = [set.revision(pi, m.a), set.revision(pi, m.b)]
    let now = CACurrentMediaTime()
    if m.pair != p.pair || revisions != p.revisions {
      let written = m.pair == p.pair
      let was = p.height
      p.pair = m.pair
      p.revisions = revisions
      rebuild(p, pi, m, written: written)
      p.drawn = nil
      // It makes room at once for words still to show, but gives it up only
      // once the last of them, and the placeholders they cover, have faded.
      if written {
        let next = lerp(set.layout(pi, m.a).height, set.layout(pi, m.b).height, smoothstep(0.15, 0.85, m.t))
        p.grew = (was, next > was ? now : max(now, p.revealed))
      }
    }
    let layoutA = set.layout(pi, m.a)
    let layoutB = set.layout(pi, m.b)
    let t = m.t
    let setter = set.setter(pi)
    let lineHeight = Double(setter.lineHeight)
    // Sequenced so words never pile up: dropped words dissolve, the rest close
    // ranks, then new words fade into the gaps. Played backwards (zooming in),
    // gaps open first and the extra words appear inside them.
    let move = smoothstep(0.15, 0.85, t)
    p.height = lerp(layoutA.height, layoutB.height, move)
    if let g = p.grew {
      let k = smoothstep(0, 1, (now - g.since) / Para.fade)
      p.height = lerp(g.from, p.height, k)
      if k >= 1 { p.grew = nil }
    }
    // From the original's height to the set text's, as the one gives way to the other.
    if let tile = p.tile { p.height = lerp(p.height, tile.inkHeight, share) }

    let key = ((t * 1e5).rounded() / 1e5, edition.version)
    if let d = p.drawn, d == key, !p.fading { return }
    p.drawn = key

    // Difficulty swaps share few words, so their crossfade overlaps a little to
    // avoid a moment where the paragraph is empty.
    let leaving = 1 - smoothstep(0, m.sideways ? 0.65 : 0.42, t)
    let arriving = smoothstep(m.sideways ? 0.35 : 0.58, 1, t)
    let ease = smoothstep(0, 1, t)
    // Difficulty swaps slide sideways, following the fingers; zoom swaps shrink in place.
    let slide = m.sideways ? Feel.drift : 0
    let column = Double(setter.column)

    let tall = max(layoutA.height, layoutB.height, 1)
    // How far a word that came with more of the text has faded in.
    func shown(_ l: WordLayer) -> Double {
      p.arriving[ObjectIdentifier(l)].map { smoothstep(0, 1, (now - $0) / Para.fade) } ?? 1
    }
    for it in p.items {
      if it.a >= 0 && it.b >= 0 {
        let wa = layoutA.words[it.a]
        let wb = layoutB.words[it.b]
        // The reflow cascades down the paragraph, so only a few lines are in flight at once.
        let f = (wa.y + wb.y) / 2 / tall
        let k = smoothstep(0.15 + 0.2 * f, 0.65 + 0.2 * f, t)
        // Words that wrap to another line (or travel far along one) ghost while in
        // flight; words sliding along their own line stay crisp and anchor the eye.
        // Across a difficulty swap every shared word dips a little to blend with the dissolve.
        let travel = max(min(1, abs(wb.y - wa.y) / lineHeight), min(1, abs(wb.x - wa.x) / (column * 0.5)))
        let ghost = max(slide > 0 ? 0.4 : 0, travel * 0.65)
        let o = 1 - ghost * sin(.pi * k)
        let x = lerp(wa.x, wb.x, k)
        let y = lerp(wa.y, wb.y, k)
        if let alt = it.alt {
          let s = smoothstep(0.3, 0.7, t)
          it.layer.paint(x: x, y: y, scale: 1, opacity: o * (1 - s) * shown(it.layer))
          alt.paint(x: x, y: y, scale: 1, opacity: o * s * shown(alt))
        } else {
          it.layer.paint(x: x, y: y, scale: 1, opacity: o * shown(it.layer))
        }
      } else if it.a >= 0 {
        let w = layoutA.words[it.a]
        it.layer.paint(
          x: w.x - slide * ease, y: w.y, scale: slide > 0 ? 1 : 0.9 + 0.1 * leaving, opacity: leaving * shown(it.layer))
      } else {
        let w = layoutB.words[it.b]
        it.layer.paint(
          x: w.x + slide * (1 - ease), y: w.y, scale: slide > 0 ? 1 : 0.9 + 0.1 * arriving, opacity: arriving * shown(it.layer))
      }
    }
    p.arriving = p.arriving.filter { now - $0.value < Para.fade }
    // What the text no longer has fades where it stood, then is put away.
    p.going.removeAll { g in
      let k = smoothstep(0, 1, (now - g.since) / Para.fade)
      guard k < 1, let s = g.layer.shown else {
        g.layer.isHidden = true
        g.layer.shown = nil
        p.spare.append(g.layer)
        return true
      }
      g.layer.paint(x: s.x, y: s.y, scale: s.scale, opacity: g.from * (1 - k))
      return false
    }
  }

  // ─── Placing ─────────────────────────────────────────────────────────────

  /// Draws every paragraph and sets out the page: the paragraphs and what is
  /// around them stacked down their columns, a band at a time.
  func layoutText() {
    if windowed {
      // A text this long isn't all set at once. Before anything's known of where
      // anything lies, everything gets a height, cheaply, so as to know.
      if unsized {
        unsized = false
        for (i, p) in paras.enumerated() where rank[i] != nil {
          p.original = originalShare(p, i)
          p.height = farHeight(p, i)
        }
        stackBands()
      }
      // Setting a paragraph for real can change how tall it is from what was guessed,
      // which brings others near that weren't. So it goes round until that settles:
      // nothing on screen is left unset for want of a next frame.
      for round in 0..<6 {
        let a = paras[anchor.index]
        let view = anchor.screenY - (a.top + anchor.frac * a.height) + offset.value
        var more = false
        for (i, p) in paras.enumerated() where rank[i] != nil {
          if near(p, in: view) || !p.c.resting || !p.z.resting || p.fading {
            if round == 0 || !p.isSet {
              draw(p, i)
              p.isSet = true
              more = true
            }
          } else if round == 0 {
            park(p, i)
            p.isSet = false
          }
        }
        guard more else { break }
        stackBands()
      }
    } else {
      for (i, p) in paras.enumerated() where rank[i] != nil { draw(p, i) }
    }
    stackBands()
  }

  /// Whether a paragraph is close enough to the screen, whose top is at `view`, to be set for real.
  private func near(_ p: Para, in view: Double) -> Bool {
    let h = Double(bounds.height)
    let top = view + p.top
    return top + p.height > -h && top < 2 * h
  }

  /// A paragraph's height, without setting it.
  private func farHeight(_ p: Para, _ pi: Int) -> Double {
    let home = edition.texts.home(pi)
    let c = Int(clamp(p.c.target, 0, Double(edition.cMax)).rounded())
    let z = Int(clamp(p.z.target, 0, Double(edition.zMax)).rounded())
    if let tile = p.tile, c == home.c, z == home.z { return tile.inkHeight }
    return typeset.height(pi, (c, z))
  }

  /// Lets go of a paragraph far from the screen, keeping only how tall it is.
  private func park(_ p: Para, _ pi: Int) {
    if !p.items.isEmpty || !p.spare.isEmpty {
      for l in p.items.flatMap({ [$0.layer] + ($0.alt.map { [$0] } ?? []) }) + p.spare { l.removeFromSuperlayer() }
      p.items = []
      p.spare = []
      p.settle()
      p.pair = nil
      p.drawn = nil
    }
    p.original = originalShare(p, pi)
    p.height = farHeight(p, pi)
  }

  /// Sets out the page: the paragraphs and what is around them stacked down
  /// their columns, a band at a time.
  private func stackBands() {
    let zMax = Double(edition.zMax)
    let lh = lineHeight
    func stack(_ items: [Entry], x: Double, from top: Double) -> Double {
      var y = top
      var last: Para?
      for item in items {
        switch item {
        case let .para(i):
          let p = paras[i]
          // Condensed paragraphs sit closer together. On the journal page they
          // run on, marked by their indents, as in print.
          if let q = last, style != .journal {
            let z = (clamp(q.z.value, 0, zMax) + clamp(p.z.value, 0, zMax)) / 2
            y += lerp(lh * 0.85, lh * 0.5, z / zMax)
          }
          p.x = x + p.inset
          p.top = y
          y += p.height
          last = p
        case let .block(b):
          b.x = x
          b.top = y
          y += b.height
          last = nil
        }
      }
      return y
    }
    /// A stretch of an original page: its tiles in the arrangement they had.
    func lay(_ r: Region, from top: Double) -> Double {
      switch r.kind {
      case let .stack(kids):
        var y = top
        for k in kids { y = lay(k, from: y) }
        return y
      case let .side(kids):
        var bottom = top
        for k in kids { bottom = max(bottom, lay(k, from: top)) }
        return bottom
      case let .block(b):
        b.x = b.fixedX ?? sheet.left
        b.top = top
        return top + b.height
      case let .para(i, b):
        let p = paras[i]
        guard let t = p.tile else { return top + b.height }
        b.x = b.fixedX ?? sheet.left
        b.top = top
        p.x = b.x + t.insetLeft
        p.top = top + t.insetTop
        return p.top + p.height + t.insetBottom
      case let .tail(i, b):
        b.x = b.fixedX ?? sheet.left
        b.top = top
        // Folds away as the paragraph it belongs to takes over from the original, if
        // that's on this look at all; a correction can leave it with no tile of its own.
        let share = paras[i].tile == nil ? 1 : paras[i].original
        b.layer.opacity = Float(share)
        return top + b.height * share
      }
    }
    var top = 0.0
    for band in plan {
      switch band {
      case let .span(items):
        top = stack(items, x: sheet.left, from: top)
      case let .columns(cols):
        let start = top
        for (i, col) in cols.enumerated() { top = max(top, stack(col, x: sheet.columnX(i), from: start)) }
      case let .region(r):
        if let page = r.page {
          if pageTops.count <= page { pageTops += Array(repeating: top, count: page + 1 - pageTops.count) }
          pageTops[page] = top
        }
        top = lay(r, from: top)
      }
    }
    contentH = top
  }

  /// Where the top of the text may rest: centered if it fits, otherwise
  /// scrollable with margins. A paper or journal page starts at the top.
  func range() -> (lo: Double, hi: Double) {
    let viewH = Double(bounds.height)
    let original = style == .journal && edition.book != nil
    let pad = style == .plain ? max(56, viewH * 0.16) : original ? 0 : 72
    if contentH <= viewH - 2 * pad {
      let center = style == .plain ? (viewH - contentH) / 2 : pad
      return (center, center)
    }
    return (viewH - pad - contentH, pad)
  }

  /// Where the anchor may rest: `range`, moved down to wherever the anchor sits in the text.
  func anchorRange() -> (lo: Double, hi: Double) {
    let a = paras[anchor.index]
    let shift = a.top + anchor.frac * a.height
    let (lo, hi) = range()
    return (lo + shift, hi + shift)
  }

  /// Moves the text into place. Unless `held` by a pinch or scroll, it eases back into its resting range.
  func place(_ dt: Double, held: Bool) {
    let a = paras[anchor.index]
    let base = anchor.screenY - (a.top + anchor.frac * a.height)
    if !held {
      let (lo, hi) = range()
      offset.target = clamp(base, lo, hi) - base
    }
    offset.step(dt)
    currentY = base + offset.value

    let cMax = Double(edition.cMax)
    let screen = Double(bounds.height)
    for (i, p) in paras.enumerated() {
      let top = currentY + p.top
      let shown = !windowed || (rank[i] != nil && top + p.height > -screen && top < 2 * screen)
      if shown != p.attached {
        p.attached = shown
        if shown { stage.addSublayer(p.layer) } else { p.layer.removeFromSuperlayer() }
      }
      guard shown else { continue }
      let over = p.c.value - clamp(p.c.value, 0, cMax)
      let at = CGPoint(x: ((p.x - over * 90) * 100).rounded() / 100, y: (top * 100).rounded() / 100)
      if at != p.placed {
        p.layer.position = at
        p.placed = at
      }
    }
    // A tile lands on whole pixels, as its neighbors do, so no seam shows between them.
    let dpr = max(traitCollection.displayScale, 1)
    for b in blocks {
      let top = currentY + b.top
      guard !windowed || (top + b.height > -screen && top < 2 * screen) else {
        b.detach()
        continue
      }
      b.attach(to: stage)
      let y = b.fixedX != nil ? (CGFloat(top) * dpr).rounded() / dpr : CGFloat((top * 100).rounded() / 100)
      let at = CGPoint(x: b.x, y: Double(y))
      if at != b.placed {
        b.layer.position = at
        b.placed = at
      }
    }

    // Pinching past the ends stretches the page itself, then lets it go.
    let scale = 1 - stretch.value * 0.1
    if scale != staged {
      staged = scale
      let o = origin
      stage.transform =
        abs(scale - 1) < 1e-4
        ? CATransform3DIdentity
        : CATransform3DConcat(
          CATransform3DConcat(CATransform3DMakeTranslation(-o.x, -o.y, 0), CATransform3DMakeScale(scale, scale, 1)),
          CATransform3DMakeTranslation(o.x, o.y, 0)
        )
    }
    updateRing()
  }

  // ─── How far through it ──────────────────────────────────────────────────

  /// Tells the ring how far the reader has scrolled and which page that's on, whenever those may have changed.
  private func updateRing() {
    guard bounds.height > 0, contentH > 0 else { return }
    if let s = ringSeen, abs(s.y - currentY) < 0.5, abs(s.h - contentH) < 0.5 { return }
    ringSeen = (currentY, contentH)
    let spot = ringSpot
    ring.set(progress: spot.progress, page: spot.page, of: spot.of)
  }

  /// What the ring says: how far along, or nil if there's nowhere to scroll to, and on which page of how many.
  var ringSpot: (progress: Double?, page: Int, of: Int) {
    let spot = readingSpot()
    let (lo, hi) = range()
    return (lo < hi ? (hi - currentY) / (hi - lo) : nil, spot.page, spot.of)
  }

  /// Where the ring rests in `content`, whether or not a finger is making it swell.
  var ringFrame: CGRect {
    CGRect(x: ring.center.x - PageRing.diameter / 2, y: ring.center.y - PageRing.diameter / 2, width: PageRing.diameter, height: PageRing.diameter)
  }

  /// The page in the middle of the screen, of how many. A text with pages of its
  /// own goes by those, in whichever look; one without goes by screenfuls.
  private func readingSpot() -> (page: Int, of: Int) {
    let view = Double(bounds.height)
    let line = view * 0.5 - currentY
    let (lo, hi) = range()
    // At the very end, it's the last page, however little of it reaches the middle.
    let ended = lo < hi && currentY <= lo + 1
    if let book = edition.book, !book.doc.flowing, book.doc.pages.count > 1 {
      let of = book.doc.pages.count
      if ended { return (of - 1, of) }
      var page = 0
      if style == .journal {
        for (k, top) in pageTops.enumerated() where top <= line { page = k }
      } else {
        for stop in pageStops {
          let top: Double
          switch stop.entry {
          case let .para(i): top = paras[i].top
          case let .block(b): top = b.top
          }
          if top > line { break }
          page = max(page, stop.page)
        }
      }
      return (page, of)
    }
    let of = max(1, Int((contentH / view).rounded(.up)))
    if ended { return (of - 1, of) }
    return (min(of - 1, max(0, Int(line / view))), of)
  }

  // ─── Contents ────────────────────────────────────────────────────────────

  /// How far below the top of the screen a place in the contents comes to rest: clear of the buttons.
  private static let arrival = 64.0

  /// The contents of the look being read: its title and headings, each on the page
  /// it's on where the text has pages. A text with no headings goes by its pages,
  /// or failing that by how some of its paragraphs open.
  func contents() -> [ContentsRow] {
    let pages = edition.book.flatMap { $0.doc.flowing ? nil : $0.doc.pages.count } ?? 0
    func name(_ s: String) -> String {
      NoteToken.strip(s).replacingOccurrences(of: "$", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    let marked: [(title: String, level: Int, entry: Entry, page: Int?)] = plan.flatMap(\.entries).compactMap { e in
      guard case let .block(b) = e, let mark = b.landmark else { return nil }
      let title = name(mark.title)
      return title.isEmpty ? nil : (title, mark.level, e, pages > 1 ? b.page : nil)
    }
    // The largest heading used sits at the margin, whatever level that is, and two steps in is as far as they go.
    let largest = marked.map(\.level).filter { $0 > 0 }.min() ?? 1
    let rows = marked.map { ContentsRow(title: $0.title, depth: $0.level == 0 ? 0 : min($0.level - largest, 2), page: $0.page, place: .entry($0.entry)) }
    if !rows.isEmpty { return rows }
    // The built-in text keeps its section titles in every look, even the one that doesn't print them.
    if let m = edition.manuscript {
      let sections = order.flatMap { i in
        m.headings(at: i).map { ContentsRow(title: $0.title, depth: min($0.level - 1, 2), page: nil, place: .entry(.para(i))) }
      }
      if !sections.isEmpty { return sections }
    }
    if pages > 1 {
      return (0..<pages).map { ContentsRow(title: "Page \($0 + 1)", depth: 0, page: nil, place: .page($0)) }
    }
    return stride(from: 0, to: order.count, by: max(1, order.count / 40)).compactMap { k in
      let i = order[k]
      let words = name(text(of: i))
      guard written(i), !words.isEmpty else { return nil }
      return ContentsRow(title: String(words.prefix(90)), depth: 0, page: nil, place: .entry(.para(i)))
    }
  }

  /// The row being read, which is the last one to have passed a line a third of the way down the screen.
  func currentRow(in rows: [ContentsRow]) -> Int? {
    let line = Double(bounds.height) / 3 - currentY
    var best: (index: Int, top: Double)?
    for (k, row) in rows.enumerated() {
      let at = top(of: row.place)
      if at <= line, at >= (best?.top ?? -.infinity) { best = (k, at) }
    }
    return best?.index
  }

  private func top(of place: ContentsRow.Place) -> Double {
    switch place {
    case let .entry(.para(i)): return paras[i].top
    case let .entry(.block(b)): return b.top
    case let .page(n):
      if style == .journal { return pageTops[safe: n] ?? 0 }
      return pageStops.first { $0.page >= n }.map { top(of: .entry($0.entry)) } ?? 0
    }
  }

  /// Sets off for `place`. From far away it sets off from only a little way short:
  /// the spring takes as long whatever the distance, and there's nothing to be read in passing.
  func travel(to place: ContentsRow.Place) {
    let target = top(of: place)
    guard let near = order.first(where: { paras[$0].top + paras[$0].height > target }) ?? order.last else { return }
    let (lo, hi) = range()
    let to = clamp(Self.arrival - target, lo, hi)
    let reach = Double(bounds.height) * 1.5
    let gap = currentY - to
    // Held by the paragraph it arrives at, so that what's read there stays put as the text changes around it.
    anchor = (near, 0, to + paras[near].top)
    offset.response = 0.5
    offset.velocity = 0
    offset.value = clamp(gap, -reach, reach)
  }

  // ─── Notes ───────────────────────────────────────────────────────────────

  /// Every mark on the page near the screen that can be tapped just now, in `content`'s coordinates.
  func marksInView() -> [TapMark] {
    var out: [TapMark] = []
    let screen = Double(bounds.height)
    for i in order {
      let p = paras[i]
      let top = currentY + p.top
      guard top + p.height > -40, top < screen + 40 else { continue }
      // On an original page, while it's as found, its marks are on the tile.
      if p.tile != nil && p.original > 0.5 { continue }
      let m = morph(p)
      guard m.t == 0 else { continue }
      let setter = typeset.setter(i)
      for w in typeset.layout(i, m.a).words where !w.glyphs.marks.isEmpty {
        for g in w.glyphs.marks {
          let y = top + w.y + Double(setter.baseline) - Double(g.rise) - Double(g.height) / 2
          out.append(TapMark(note: g.note, rect: CGRect(x: p.x + w.x + Double(g.x), y: y, width: Double(g.width), height: Double(g.height))))
        }
      }
    }
    for b in blocks where b.attached && !b.marks.isEmpty && b.layer.opacity > 0.5 {
      let top = currentY + b.top
      guard top + b.height > -40, top < screen + 40 else { continue }
      for m in b.marks { out.append(TapMark(note: m.note, rect: m.rect.offsetBy(dx: b.x, dy: top))) }
    }
    return out
  }

  /// The mark a finger at `at` means: the nearest within reach, since a mark's far smaller than a finger.
  func mark(at point: CGPoint, reach: CGFloat = 24) -> TapMark? {
    var best: TapMark?
    var bestD = CGFloat.infinity
    for m in marksInView() {
      let d = hypot(m.rect.midX - point.x, m.rect.midY - point.y)
      if d < reach + max(m.rect.width, m.rect.height) / 2, d < bestD {
        best = m
        bestD = d
      }
    }
    return best
  }

  /// The paragraph nearest a point `y` down the page, and `x` across it when
  /// the text is set in columns.
  func hit(_ y: Double, x: Double? = nil) -> Int {
    var best = order.first ?? 0
    var bestD = Double.infinity
    for (i, p) in paras.enumerated() where rank[i] != nil {
      let top = currentY + p.top
      let bottom = top + p.height
      let column = p.width ?? sheet.column
      var d = y < top ? top - y : y > bottom ? y - bottom : 0
      if let x { d += x < p.x ? p.x - x : x > p.x + column ? x - p.x - column : 0 }
      if d < bestD {
        bestD = d
        best = i
      }
    }
    return best
  }

  /// Whether paragraph `p` shows version (`c`, `z`) now, or is on its way to it.
  func shows(_ p: Int, _ c: Int, _ z: Int) -> Bool {
    let para = paras[p]
    let m = morph(para)
    let target = (Int(para.c.target.rounded()), Int(para.z.target.rounded()))
    return [m.a, m.b, target].contains { $0 == (c, z) }
  }

  /// The versions of a live text worth writing next, nearest the eye first.
  /// First, any on screen that aren't written yet, showing as placeholders;
  /// then, for each paragraph in view, a step each way along both axes from
  /// the version it reads at, once that one is written: the paragraph at
  /// `focus` (a swipe or pinch underway, or mid-screen) before the rest, then
  /// by how far each is from the middle. Paragraphs more than half a screen
  /// off are left alone, unless they're next to the focus, and so is one still
  /// under the fingers: the versions it passes on the way aren't wanted, only
  /// the one it's let go at. With `Store.writeOnGesture`, only what's on screen
  /// as placeholders is wanted, which is what a gesture has asked for.
  func wishes(focus: Int?) -> [Wish] {
    let onGesture = Store.writeOnGesture
    let texts = edition.texts
    let h = Double(bounds.height)
    let mid = focus ?? hit(h / 2, x: Double(bounds.width) / 2)
    let (cMax, zMax) = (edition.cMax, edition.zMax)
    var shown: [Wish] = []
    var ahead: [Wish] = []
    var seen = Set<LiveText.Key>()
    for i in order {
      let p = paras[i]
      let top = currentY + p.top
      let bottom = top + p.height
      let off = top > h ? (top - h) / h : bottom < 0 ? -bottom / h : 0
      guard onGesture ? off == 0 : off <= 0.5 || (apart(i, mid) ?? 2) <= 1 else { continue }
      let distance = i == mid ? 0 : 0.1 + off + abs((top + bottom) / 2 - h / 2) / h
      guard p.c.target == p.c.target.rounded(), p.z.target == p.z.target.rounded() else { continue }
      let c = Int(clamp(p.c.target, 0, Double(cMax)))
      let z = Int(clamp(p.z.target, 0, Double(zMax)))
      // A whole document's worth of paragraphs isn't written ahead: only those next
      // to where the reader's looking, unless the reader goes to one and wants it.
      let nearEnough = edition.book == nil || (apart(i, mid) ?? 2) <= 1
      func want(_ v: (c: Int, z: Int), _ rank: Double, on: Bool, into list: inout [Wish]) {
        guard v.c >= 0, v.c <= cMax, v.z >= 0, v.z <= zMax, !texts.draft(i, v.c, v.z).done,
          seen.insert(LiveText.Key(p: i, c: v.c, z: v.z)).inserted
        else { return }
        list.append(Wish(p: i, c: v.c, z: v.z, rank: rank, shown: on, fromC: c, fromZ: z))
      }
      want((c, z), distance, on: off == 0, into: &shown)
      guard !onGesture, nearEnough, texts.draft(i, c, z).done else { continue }
      for v in [(c + 1, z), (c - 1, z), (c, z + 1), (c, z - 1)] { want(v, 1 + distance, on: false, into: &ahead) }
    }
    return (shown + ahead).sorted { $0.rank < $1.rank }
  }

  /// Where paragraph `i` sits, in the coordinates of `content`.
  func frame(of i: Int) -> CGRect {
    let p = paras[i]
    return CGRect(x: p.x, y: currentY + p.top, width: p.width ?? (sheet.columns > 1 ? sheet.column : sheet.width), height: p.height)
  }

  /// The size paragraph `i` is set at.
  func fontSize(of i: Int) -> CGFloat { paras.indices.contains(i) ? typeset.setter(i).fontSize : sheet.fontSize }

  /// Keeps the first thing on screen still while what's above it changes size, so
  /// a long text's heights can be put right as it's read without anything moving.
  func anchorForScrolling() {
    guard windowed, let first = order.first(where: { i in currentY + paras[i].top + paras[i].height > 0 }) else {
      rebase(order.first ?? 0, 0)
      return
    }
    rebase(first, 0)
  }

  /// Paragraph `i` drawn as it reads now, glyphs and all, at `scale` pixels per point.
  func picture(of i: Int, scale: CGFloat) -> UIImage {
    let p = paras[i]
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: frame(of: i).size, format: format).image { r in
      let ctx = r.cgContext
      if let tile = p.tile, p.original > 0.5, let part = tile.block.picturePart {
        // The whole tile, with its air, offset so its marks land where the paragraph is.
        let rect = CGRect(x: -tile.insetLeft, y: -tile.insetTop, width: Double(tile.block.layer.bounds.width), height: tile.block.height)
        UIImage(cgImage: part).draw(in: rect)
        return
      }
      for case let w as WordLayer in p.layer.sublayers ?? [] where !w.isHidden && w.opacity > 0 {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(w.opacity))
        ctx.translateBy(x: w.position.x, y: w.position.y)
        ctx.concatenate(CATransform3DGetAffineTransform(w.transform))
        ctx.translateBy(x: -w.bounds.width * w.anchorPoint.x, y: -w.bounds.height * w.anchorPoint.y)
        w.draw(in: ctx)
        ctx.restoreGState()
      }
    }
  }

  /// The part of the page a thumbnail shows: the text and its margins, cut to
  /// the shape of a sheet of letter paper. It may run below the screen.
  var sheetRect: CGRect {
    let pad = min(64, sheet.left)
    let w = min(Double(bounds.width), sheet.width + 2 * pad)
    return CGRect(x: ((Double(bounds.width) - w) / 2).rounded(), y: 0, width: w, height: (w * 11 / 8.5).rounded())
  }

  /// Whether paragraph `i` is written, as it now reads, rather than on its way.
  func written(_ i: Int) -> Bool {
    let p = paras[i]
    return edition.texts.draft(i, Int(p.c.target.rounded()), Int(p.z.target.rounded())).done
  }

  /// Paragraph `i` as it reads now, for VoiceOver.
  func text(of i: Int) -> String {
    let p = paras[i]
    let d = edition.texts.draft(i, Int(p.c.target.rounded()), Int(p.z.target.rounded()))
    if d.text.isEmpty { return "Being written" }
    return edition.book != nil ? NoteToken.strip(d.text) : NoteToken.strip(d.text).replacingOccurrences(of: "$", with: "")
  }

  /// Whether a paragraph that changes length pushes down only what lies below
  /// it in its own column, rather than the page around the fingers.
  var growsDown: Bool { style == .journal && (sheet.columns > 1 || edition.book != nil) }

  /// When columns grow downward, holds still the top of the earliest paragraph
  /// a change will reach (`reach` paragraphs before `focus` in reading order),
  /// so that everything above it, and the other column, stays where it is.
  func pinTop(around focus: Int, reach: Int) {
    guard growsDown, let k = rank[focus] else { return }
    rebase(order[max(0, k - reach)], 0)
  }

  /// Where a swipe or key stops along paragraph `i`'s difficulty, from level `c`:
  /// once for each run of neighboring levels that read the same at its zoom (as
  /// the journal's extra paragraphs do, written at fewer levels), so that every
  /// step changes the text.
  func steps(_ i: Int, from c: Int) -> Steps {
    let set = typeset
    let cMax = edition.cMax
    let z = Int(clamp(paras[i].z.target.rounded(), 0, Double(edition.zMax)))
    var starts = [0]
    for k in stride(from: 1, through: cMax, by: 1) where !set.same(i, (k - 1, z), (k, z)) { starts.append(k) }
    // Each run is stopped at by its end nearest `c`, and by `c` itself in its own;
    // the first and last at the ends, to be pulled past just as anywhere else.
    let at = starts.indices.map { r in
      r == 0 ? 0 : r == starts.count - 1 ? cMax : min(max(c, starts[r]), starts[r + 1] - 1)
    }
    return Steps(at: at, starts: starts, top: cMax)
  }

  /// Moves paragraph `i`'s difficulty on by `dt`, counting the way by the
  /// versions it reads as: neighboring levels that read the same are crossed
  /// at once, unseen, and take up none of the way. So a change only takes the
  /// time the text takes to change, and meets either end as gently as anywhere.
  func stepDifficulty(_ i: Int, _ dt: Double) {
    let p = paras[i]
    let c = p.c
    guard !c.resting else { return }
    // Partway between two zooms, versions are told apart by more than difficulty.
    guard abs(p.z.value - p.z.value.rounded()) < 1e-3 else { return c.step(dt) }
    let s = steps(i, from: Int(clamp(c.target.rounded(), 0, Double(edition.cMax))))
    guard s.at.count <= edition.cMax else { return c.step(dt) }
    let way = Spring(s.along(c.value), response: c.response, damping: c.damping)
    way.target = s.along(c.target)
    way.velocity = c.velocity
    way.step(dt)
    if way.resting {
      c.snap(c.target)
    } else {
      c.value = s.level(way.value, near: c.target)
      c.velocity = way.velocity
    }
  }

  /// How far apart two paragraphs are in reading order, or nil if this look leaves either out.
  func apart(_ a: Int, _ b: Int) -> Int? {
    guard let x = rank[a], let y = rank[b] else { return nil }
    return abs(x - y)
  }

  /// Re-expresses the current position relative to a new anchor, without moving anything.
  func rebase(_ index: Int, _ frac: Double) {
    let p = paras[index]
    anchor = (index, frac, currentY + p.top + frac * p.height)
    offset.snap(0)
    offset.response = 0.42
  }

  func anchorAt(_ y: Double, x: Double? = nil) {
    let i = hit(y, x: x)
    let p = paras[i]
    rebase(i, clamp((y - currentY - p.top) / max(p.height, 1), 0, 1))
  }

  var moving: Bool {
    !stretch.resting || !offset.resting || paras.contains { !$0.z.resting || !$0.c.resting || $0.fading }
  }

  /// Brings everything still moving to rest at once, where it was going.
  func rest() {
    for p in paras {
      p.z.snap(p.z.target)
      p.c.snap(p.c.target)
    }
    stretch.snap(stretch.target)
    layoutText()
    place(0, held: false)
    offset.snap(offset.target)
    place(0, held: false)
  }
}
