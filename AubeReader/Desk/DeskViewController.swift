import CoreImage.CIFilterBuiltins
import UIKit

// ─── Feel ────────────────────────────────────────────────────────────────────
enum Feel {
  static let zoomPerLogScale = 3.6  // pinch scale → zoom levels
  static let swipePx = 130.0  // finger travel per difficulty level
  static let follow = 0.09  // spring response while fingers drive a value
  static let settle = 0.5  // spring response when a value settles after release
  static let zoomBand = 0.5  // how far a pinch can be stretched past the ends
  static let swipeBand = 0.4  // how far difficulty can be stretched past the ends
  static let drift = 22.0  // px swapped-out words slide sideways when difficulty changes
  static let detent = 0.12  // how much values stick to whole levels while dragging
  static let textSlop = 32.0  // px either side of the text column that still count as "on the text"
  // A swipe that starts this soon after the last one, level with its paragraph
  // give or take streakSlop, carries on changing that paragraph: on a page in
  // columns it doesn't matter which column it starts in.
  static let streakMs = 800.0
  static let streakSlop = 40.0
  /// How far a released scroll glides on, per pt/s it was moving at.
  static let glide = 0.45
  /// A finger put down on a scroll moving faster than this (pt/s) only stops it: the touch is no tap or press.
  static let catchSpeed = 40.0
  // Share of a pinch felt by the paragraph under the fingers, then its
  // neighbors, and so on, when the fingers start out on different paragraphs:
  // the ones just above and below follow along at 0.6, which still rounds to a
  // whole level for every level the pinch moves. Fingers on a single
  // paragraph change only that one.
  static let falloff = [1, 0.6]
}

/// How much of a pinch a paragraph `distance` away from the fingers feels.
private func weight(_ distance: Int?, _ falloff: [Double]) -> Double { distance.flatMap { falloff[safe: $0] } ?? 0 }

/// Makes a dragged value linger slightly on whole levels, like soft clicks.
private func detent(_ x: Double, _ max: Double) -> Double {
  x <= 0 || x >= max ? x : x - (Feel.detent / (2 * .pi)) * sin(2 * .pi * x)
}

private func ms() -> Double { CACurrentMediaTime() * 1000 }

// ─── State ───────────────────────────────────────────────────────────────────

private enum Kind { case pinch, swipe, scroll }

private final class Gesture {
  let kind: Kind
  /// The paragraph being swiped or pinched.
  var para = 0
  var raw = 0.0
  /// Swipe only: where its paragraph's difficulty stops, and how far along them it is.
  var steps: Steps?
  var s = 0.0
  /// Pinch only: the share each paragraph feels, by distance from the fingers.
  var falloff: [Double] = [1]
  /// Pinch only: zoom of each paragraph when the pinch began, and how far it can go.
  var from: [Double] = []
  var lo = 0.0
  var hi = 0.0

  init(_ kind: Kind) { self.kind = kind }
}

// ─── The desk ────────────────────────────────────────────────────────────────

/// Holds the reader of the open document, and the library over it while that shows.
final class DeskViewController: UIViewController, UIGestureRecognizerDelegate {
  /// The document being read.
  private(set) var document: Document
  private var library: Library
  /// Each document's texts, typeset, kept for when it's opened again.
  private var libraries: [String: Library] = [:]
  /// When a live document's rewriter was last told what's being read.
  private var wished = 0.0
  /// The library of documents (not `library`, the paragraphs' text), in a
  /// navigation controller of its own, over the reader while it shows.
  private let homeController = LibraryViewController()
  private lazy var homeNavigation = homeController.inNavigation()
  private var home: UIView { homeNavigation.view }
  /// The time and battery show over the library, but not over the page; they
  /// fade as the library comes and goes.
  private var atHome = true
  /// How far down the library starts while the status bar shows. It keeps to
  /// that while the bar is away, so nothing in it moves as the bar comes and goes.
  private var barTop: CGFloat = 0
  /// Plain paper over the reader while a page zooms between it and the library,
  /// so the live page doesn't show through the library as it fades.
  private let curtain = UIView()
  /// The library's books no longer show the documents as they are.
  private var homeStale = true
  /// Documents improved while they were being read, to catch up when they're put down.
  private var stale = Set<String>()

  private var reader: ReaderView!

  private var gesture: Gesture?
  private var panLast = CGPoint.zero
  private var panRecognizer: UIPanGestureRecognizer!
  private var pinchRecognizer: UIPinchGestureRecognizer!
  private var tapRecognizer: UITapGestureRecognizer!
  private var doubleTapRecognizer: UITapGestureRecognizer!
  private var pressRecognizer: UILongPressGestureRecognizer!
  /// The paragraph the last sideways swipe changed, and when it let go.
  private var lastSwipe: (para: Int, ended: Double)?
  /// Whether a scroll let go, or a key's, is still on its way to rest.
  private var gliding = false
  /// The touch last seen, and whether all it did was stop a glide.
  private weak var lastTouch: UITouch?
  private var touchCaughtGlide = false
  /// The closer look at a paragraph, while one is open.
  private var topic: TopicOverlay?
  /// A footnote opened at its mark, and where the text stood when it was, so it goes if the text moves.
  private var tip: (view: NoteTip, y: Double)?
  /// The table of contents, while it's open.
  private var contents: ContentsTip?

  private var W = 0.0
  private var H = 0.0

  private var link: CADisplayLink!
  private var lastFrame = 0.0
  private var saving: DispatchWorkItem?
  private var saved = Data()

  init(document: Document? = nil) {
    let document = document ?? .last
    self.document = document
    library = Self.library(for: document)
    super.init(nibName: nil, bundle: nil)
    libraries[document.id] = library
  }

  private static func library(for d: Document) -> Library {
    if d.imported, let book = Imports.shared.book(d.id) { return Library(book.text, book: book) }
    return Library(Content.named(d.resource ?? "content"), manuscript: Manuscript.of(d.id))
  }

  /// The texts of `d`, typeset, made the first time they're wanted.
  private func library(for d: Document) -> Library {
    if let l = libraries[d.id] { return l }
    let l = Self.library(for: d)
    libraries[d.id] = l
    listen(l)
    return l
  }

  /// Lets a live text's versions reach the reader as they're written: the
  /// frame loop wakes for a version on show, and trouble is said on the page.
  private func listen(_ l: Library) {
    guard let live = l.texts as? LiveText else { return }
    live.onChange = { [weak self, weak l] key in
      guard let self, let l, l === self.library else { return }
      if let key, !self.reader.shows(key.p, key.c, key.z) { return }
      self.kick()
    }
    live.rewriter.onTrouble = { [weak self, weak l] why in
      guard let self, let l, l === self.library, !self.atHome else { return }
      self.reader.say("Couldn’t write: \(why)", for: 3)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var prefersStatusBarHidden: Bool { !atHome }
  override var preferredStatusBarStyle: UIStatusBarStyle { atHome ? .lightContent : .default }
  override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
  override var canBecomeFirstResponder: Bool { true }

  // ─── Setup ───────────────────────────────────────────────────────────────

  override func viewDidLoad() {
    super.viewDidLoad()
    Zoom.warmUp()
    listen(library)
    view.backgroundColor = Palette.page
    curtain.backgroundColor = Palette.page
    curtain.isUserInteractionEnabled = false
    curtain.isHidden = true
    view.addSubview(curtain)
    addChild(homeNavigation)
    view.addSubview(home)
    homeNavigation.didMove(toParent: self)
    homeController.onOpen = { [weak self] i in self?.openFromHome(i) }
    let imports = Imports.shared
    imports.onChange = { [weak self] in
      // `resume` below reports to here before the reader is laid. The library is yet to be shown, and will show it then.
      guard let self, self.reader != nil else { return }
      // The document being read has been deleted: the first one takes its place, under the library.
      if self.document.imported, !Document.all.contains(where: { $0.id == self.document.id }) {
        self.libraries[self.document.id] = nil
        self.lay(.written)
      }
      self.homeStale = true
      if self.atHome { self.reloadHome() }
    }
    Icons.shared.host = view
    imports.onProgress = { [weak self] id in self?.homeController.showProgress(of: id) }
    imports.onDocument = { [weak self] id in self?.documentChanged(id) }
    imports.resume()

    panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(onPan))
    panRecognizer.maximumNumberOfTouches = 1
    panRecognizer.allowedScrollTypesMask = .continuous
    pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(onPinch))
    tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onTap))
    doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap))
    doubleTapRecognizer.numberOfTapsRequired = 2
    pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(onPress))
    pressRecognizer.minimumPressDuration = 0.32
    for g in [panRecognizer!, pinchRecognizer!, tapRecognizer!, doubleTapRecognizer!, pressRecognizer!] as [UIGestureRecognizer] {
      g.delegate = self
      view.addGestureRecognizer(g)
    }

    W = Double(view.bounds.width)
    H = Double(view.bounds.height)
    lay()

    link = CADisplayLink(target: self, selector: #selector(frame))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    kick()

    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: DeskViewController, _) in
      self.kick()
      // Covers drawn in the old inks go.
      self.homeStale = true
      DispatchQueue.main.async {
        if self.atHome { self.reloadHome() }
        // An open topic pictured its paragraph and the reader behind it in the
        // old inks. The reader is set in the new ones first (it has restyled by
        // now), so that's what the new pictures show.
        if let topic = self.topic {
          CATransaction.begin()
          CATransaction.setDisableActions(true)
          _ = self.tick(0, ms())
          CATransaction.commit()
          topic.restyle()
        }
      }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    becomeFirstResponder()
    // So the first long press has nothing to start up.
    DrawingView.warm()
    DispatchQueue.global(qos: .utility).async { TopicWriter.warm() }
  }

  override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    // Its mark won't be where it was.
    closeTips(quickly: true)
    // An open topic finds its paragraph again once the reader has reset its
    // text for the new shape of the screen.
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.topic?.settle() }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let size = view.bounds.size
    home.frame = view.bounds
    curtain.frame = view.bounds
    if Double(size.width) != W || Double(size.height) != H {
      W = Double(size.width)
      H = Double(size.height)
      measure(force: true)
      homeStale = true
    }
    if atHome && homeStale { reloadHome() }
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    let top = view.safeAreaInsets.top
    if atHome { barTop = top }
    homeNavigation.additionalSafeAreaInsets.top = max(0, barTop - top)
  }

  private func measure(force: Bool = false) {
    let changed = library.measure(width: CGFloat(W))
    reader.frame = CGRect(x: 0, y: 0, width: W, height: H)
    if changed || force { reader.restyle() }
    kick()
  }

  /// Sets out the document as it was left.
  private func lay() {
    let saved = Store.loadReading(document.id)
    let r = ReaderView(
      library: library, c: saved?.c, z: saved?.z, style: saved?.style.flatMap(ReadingStyle.init(rawValue:)) ?? library.startingLook)
    r.onStyle = { [weak self] in
      // The contents were for the look that's going.
      self?.closeContents(quickly: true)
      self?.kick()
    }
    r.onHome = { [weak self] in self?.showHome() }
    r.onContents = { [weak self] in self?.toggleContents() }
    r.frame = CGRect(x: 0, y: 0, width: W, height: H)
    view.insertSubview(r, belowSubview: curtain)
    reader = r
    measure(force: true)
    r.layoutText()
    r.anchor.screenY = r.anchorRange().hi
    r.place(0, held: false)
  }

  /// Puts the reader away and sets out `next` in its place.
  private func lay(_ next: Document, again: Bool = false) {
    guard again || next.id != document.id else { return }
    closeTips(quickly: true)
    finish()
    saveNow()
    (library.texts as? LiveText)?.rewriter.want([])
    reader.removeFromSuperview()
    document = next
    library = library(for: next)
    Store.lastDocument = next.id
    saved = Data()
    lay()
  }

  // ─── Frame loop ──────────────────────────────────────────────────────────

  private func kick() { link?.isPaused = false }

  @objc private func frame(_ link: CADisplayLink) {
    let now = link.timestamp
    let dt = lastFrame > 0 ? min(now - lastFrame, 1.0 / 30) : 1.0 / 60
    lastFrame = now
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let moving = tick(dt, ms())
    CATransaction.commit()
    if !moving {
      link.isPaused = true
      lastFrame = 0
    }
  }

  /// Advances everything by one frame; returns whether anything is still moving.
  private func tick(_ dt: Double, _ now: Double) -> Bool {
    let r = reader!
    r.stretch.step(dt)
    for (i, p) in r.paras.enumerated() {
      p.z.step(dt)
      r.stepDifficulty(i, dt)
    }
    r.layoutText()
    r.place(dt, held: gesture != nil && gesture?.kind != .swipe)

    keepNoteInPlace()
    if gesture == nil { remember() }
    if gliding && r.offset.resting { gliding = false }

    let moving = gesture != nil || r.moving
    wish(now, settled: !moving)
    return moving
  }

  /// Tells a live document's rewriter which versions the reader is nearest,
  /// a few times a second while things move and once more when they settle.
  private func wish(_ now: Double, settled: Bool) {
    guard let live = library.texts as? LiveText, !atHome else { return }
    guard settled || now - wished > 150 else { return }
    wished = now
    let focus = gesture.flatMap { $0.kind == .swipe || $0.kind == .pinch ? $0.para : nil }
    live.rewriter.want(reader.wishes(focus: focus))
  }

  /// Stores how the document is being read once that changes.
  private func remember() {
    let state = ReadingState(
      c: reader.paras.map { Int($0.c.target.rounded()) },
      z: reader.paras.map { Int($0.z.target.rounded()) },
      style: reader.style.rawValue)
    guard let json = try? JSONEncoder().encode(state), json != saved else { return }
    saved = json
    saving?.cancel()
    let id = document.id
    let work = DispatchWorkItem { Store.saveReading(id, state) }
    saving = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  func saveNow() {
    saving?.perform()
    saving = nil
    for l in libraries.values { (l.texts as? LiveText)?.saveNow() }
  }

  // ─── Gestures ────────────────────────────────────────────────────────────

  /// The library, and buttons anywhere, take their touches straight away: the
  /// reader's recognizers never see them, so none holds back a tap's end while it
  /// waits to see whether a second tap or a long press follows.
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard !atHome, !(touch.view is UIControl) else { return false }
    // A note's own words are selected and scrolled within it.
    if let tip, tip.view.holds(touch) { return false }
    // So are the contents' rows chosen and scrolled.
    if let contents, contents.holds(touch) { return false }
    // Every recognizer is asked about a new touch, before any of them acts on it.
    if touch !== lastTouch {
      lastTouch = touch
      touchCaughtGlide = catchGlide()
    }
    return !touchCaughtGlide || g === panRecognizer || g === pinchRecognizer
  }

  /// Stops a scroll still gliding where it is, as a finger put down on it does;
  /// true if it was going fast enough for that to be all the finger meant.
  private func catchGlide() -> Bool {
    guard gliding, gesture == nil else { return false }
    gliding = false
    defer { kick() }
    let fast = abs(reader.offset.velocity) > Feel.catchSpeed
    reader.anchorForScrolling()
    return fast
  }

  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    if atHome { return false }
    let at = g.location(in: view)
    if g === tapRecognizer { return tip != nil || contents != nil || markUnder(at) != nil }
    if g === doubleTapRecognizer { return reader.overText(Double(at.x)) && tip == nil && contents == nil && markUnder(at) == nil }
    if g === pressRecognizer { return topicUnder(at) != nil }
    if g === panRecognizer {
      // Sideways changes a paragraph's difficulty, so it has to start over the text.
      let v = panRecognizer.velocity(in: view)
      return abs(v.x) <= abs(v.y) || reader.overText(Double(at.x)) || swipeToContinue(at: at, ms()) != nil
    }
    return true
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    g === pinchRecognizer || other === pinchRecognizer
  }

  @objc private func onPan(_ g: UIPanGestureRecognizer) {
    let t = g.translation(in: view)
    let v = g.velocity(in: view)
    switch g.state {
    case .began:
      panLast = t
      if gesture?.kind == .pinch { break }
      closeTips()
      finish()
      // Touches arrive with the travel so far; a trackpad's scroll may not, so its speed tells the way.
      let moved = abs(t.x) + abs(t.y) >= 4
      let sideways = moved ? abs(t.x) > abs(t.y) : abs(v.x) > abs(v.y)
      let at = g.location(in: view)
      if sideways {
        beginSwipe(at, ms(), para: swipeToContinue(at: at, ms()))
        swipeBy(-Double(t.x))
      } else {
        beginScroll()
        scrollBy(-Double(t.y))
      }
    case .changed:
      let dx = -Double(t.x - panLast.x)
      let dy = -Double(t.y - panLast.y)
      panLast = t
      switch gesture?.kind {
      case .swipe: swipeBy(dx)
      case .scroll: scrollBy(dy)
      default: break
      }
    default:
      // Speed in the direction the content moves, as a scroll wheel reports it.
      if gesture?.kind != .pinch { finish(vx: -Double(v.x), vy: -Double(v.y)) }
    }
    kick()
  }

  /// The paragraph the last swipe changed, if one starting at `at` now carries on with it.
  private func swipeToContinue(at: CGPoint, _ now: Double) -> Int? {
    let r = reader!
    guard let last = lastSwipe, now - last.ended < Feel.streakMs, r.apart(last.para, last.para) != nil else { return nil }
    let p = r.paras[last.para]
    let top = r.currentY + p.top
    let y = Double(at.y)
    return y > top - Feel.streakSlop && y < top + p.height + Feel.streakSlop ? last.para : nil
  }

  private func beginSwipe(_ at: CGPoint, _ now: Double, para: Int? = nil) {
    let r = reader!
    let i = para ?? r.hit(Double(at.y), x: Double(at.x))
    let p = r.paras[i]
    r.rebase(i, 0)
    p.c.response = Feel.follow
    let g = Gesture(.swipe)
    g.para = i
    // From the level it's on its way to, so a swipe starting while the last one settles loses nothing.
    let c = Int(clamp(p.c.target.rounded(), 0, Double(library.cMax)))
    let steps = r.steps(i, from: c)
    g.steps = steps
    g.s = Double(steps.index(of: c))
    g.raw = g.s
    gesture = g
  }

  /// Each swipePx of travel is a step to the next version that reads differently.
  private func swipeBy(_ dx: Double) {
    guard let g = gesture, g.kind == .swipe, let steps = g.steps else { return }
    let n = Double(steps.last)
    g.raw += dx / Feel.swipePx
    g.s = rubber(detent(g.raw, n), 0, n, Feel.swipeBand)
    reader.paras[g.para].c.target = steps.level(g.s)
  }

  private func beginScroll() {
    let r = reader!
    r.anchorForScrolling()
    let (lo, hi) = r.anchorRange()
    let g = Gesture(.scroll)
    g.raw = unrubber(r.anchor.screenY, lo, hi, H * 0.18)
    gesture = g
  }

  private func scrollBy(_ dy: Double) {
    guard let g = gesture, g.kind == .scroll else { return }
    let (lo, hi) = reader.anchorRange()
    g.raw -= dy
    reader.anchor.screenY = rubber(g.raw, lo, hi, H * 0.18)
  }

  /// Ends the gesture underway, letting what it moved settle. `vx` and `vy` are
  /// how fast the fingers were going when they let go, in the direction the content moves.
  private func finish(vx: Double = 0, vy: Double = 0) {
    guard let g = gesture else { return }
    gesture = nil
    let r = reader!
    switch g.kind {
    case .pinch:
      let focus = r.paras[g.para].z
      let amount = clamp(rubber(g.raw, g.lo, g.hi, Feel.zoomBand), g.lo, g.hi)
      settleZoom(g.para, g.from, (amount + focus.velocity * 0.05).rounded(), g.falloff)
    case .swipe:
      let p = r.paras[g.para]
      p.c.response = Feel.settle
      if let steps = g.steps {
        // A quick release carries on by a step at most, so that every swipe of a run goes about as far.
        let k = Int(clamp((g.s + clamp(vx / Feel.swipePx * 0.1, -1, 1)).rounded(), 0, Double(steps.last)))
        p.c.target = Double(steps.at[k])
      }
      lastSwipe = (g.para, ms())
    case .scroll:
      // The text glides on, and eases to a stop, or against the end it reached.
      r.anchorForScrolling()
      let (lo, hi) = r.anchorRange()
      let speed = -vy
      let rest = clamp(r.anchor.screenY + speed * Feel.glide, lo, hi)
      r.offset.value = r.anchor.screenY - rest
      r.anchor.screenY = rest
      r.offset.velocity = speed
      r.offset.response = 0.85
      gliding = true
    }
    kick()
  }

  // ─── Pinching ────────────────────────────────────────────────────────────

  @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
    let raw = -log(max(Double(g.scale), 0.01)) * Feel.zoomPerLogScale
    switch g.state {
    case .began:
      closeTips()
      finish()
      let fingers = g.numberOfTouches >= 2 ? (0..<2).map { g.location(ofTouch: $0, in: view) } : []
      beginPinch(g.location(in: view), fingers: fingers)
      setPinch(raw)
    case .changed:
      setPinch(raw)
    default:
      if gesture?.kind == .pinch { finish() }
    }
    kick()
  }

  private func beginPinch(_ at: CGPoint, fingers: [CGPoint]) {
    let r = reader!
    r.anchorAt(Double(at.y), x: Double(at.x))
    r.origin = CGPoint(x: at.x, y: r.anchor.screenY)
    let g = Gesture(.pinch)
    g.para = r.anchor.index
    // Fingers that start out on different paragraphs reach the ones around them too.
    let touched = Set(fingers.map { r.hit(Double($0.y), x: Double($0.x)) })
    g.falloff = touched.count > 1 ? Feel.falloff : [1]
    r.pinTop(around: g.para, reach: g.falloff.count - 1)
    g.from = r.paras.map { $0.z.value }
    // The pinch goes on until every paragraph it touches has reached an end.
    let zMax = Double(library.zMax)
    for (j, p) in r.paras.enumerated() {
      let d = r.apart(j, g.para) ?? 0
      let w = weight(r.apart(j, g.para), g.falloff)
      guard w > 0 else { continue }
      g.lo = min(g.lo, -g.from[j] / w)
      g.hi = max(g.hi, (zMax - g.from[j]) / w)
      p.z.response = Feel.follow + 0.04 * Double(d)  // neighbors trail slightly, like a ripple
    }
    r.stretch.response = Feel.follow
    gesture = g
  }

  /// Moves a pinch to `raw` zoom levels from where it began; positive is fingers closing.
  private func setPinch(_ raw: Double) {
    guard let g = gesture, g.kind == .pinch else { return }
    g.raw = raw
    let r = reader!
    let pulled = rubber(raw, g.lo, g.hi, Feel.zoomBand)
    let amount = clamp(pulled, g.lo, g.hi)
    r.stretch.target = pulled - amount
    let zMax = Double(library.zMax)
    for (j, p) in r.paras.enumerated() {
      let w = weight(r.apart(j, g.para), g.falloff)
      if w > 0 { p.z.target = clamp(detent(g.from[j] + amount * w, zMax), 0, zMax) }
    }
  }

  /// Lands every touched paragraph on a whole level, consistent with how far the focus moved.
  private func settleZoom(_ focus: Int, _ from: [Double], _ steps: Double, _ falloff: [Double] = [1]) {
    let r = reader!
    for (j, p) in r.paras.enumerated() {
      let w = weight(r.apart(j, focus), falloff)
      guard w > 0 else { continue }
      p.z.response = Feel.settle
      p.z.target = clamp((from[j] + steps * w).rounded(), 0, Double(library.zMax))
    }
    r.stretch.response = Feel.settle
    r.stretch.target = 0
  }

  /// Springs the paragraph under a double tap back to the text as first written.
  @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
    let at = g.location(in: view)
    act {
      let r = reader!
      r.anchorAt(Double(at.y), x: Double(at.x))
      let i = r.anchor.index
      r.pinTop(around: i, reach: 0)
      let p = r.paras[i]
      let home = library.texts.home(i)
      p.c.response = Feel.settle
      p.z.response = Feel.settle
      p.c.target = clamp(Double(home.c), 0, Double(library.cMax))
      p.z.target = clamp(Double(home.z), 0, Double(library.zMax))
    }
  }

  // ─── A closer look ───────────────────────────────────────────────────────

  /// The paragraph under `p`, if it's written and can be looked at: its topic
  /// if one was written by hand, which paragraph, and where it is.
  private func topicUnder(_ p: CGPoint) -> (topic: Topic?, index: Int, frame: CGRect)? {
    guard !atHome, topic == nil, gesture == nil, !reader.moving else { return nil }
    let r = reader!
    let i = r.hit(Double(p.y), x: Double(p.x))
    guard r.written(i) else { return nil }
    let t = document.handTopics ? Topic.at(i, in: r.style) : nil
    let frame = r.content.convert(r.frame(of: i), to: view)
    return frame.insetBy(dx: -12, dy: -12).contains(p) ? (t, i, frame) : nil
  }

  /// A long press on a paragraph lifts it out of the page and opens its topic.
  @objc private func onPress(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began else { return }
    closeTips(quickly: true)
    openTopic(at: g.location(in: view))
  }

  private func openTopic(at point: CGPoint) {
    guard let (t, i, frame) = topicUnder(point) else { return }
    // The finger that pressed belongs to the topic now, not the reader.
    for r in [panRecognizer!, pinchRecognizer!] {
      r.isEnabled = false
      r.isEnabled = true
    }
    let r = reader!
    let scale = (view.window?.screen.scale ?? 2) * 1.6
    // Starts now, so the time the card takes to open is time to find out what to put on it.
    let writer = t == nil ? TopicWriter(paragraph: r.text(of: i), from: document.title) : nil
    let overlay = TopicOverlay(
      topic: t, writer: writer, paragraph: frame, text: r.picture(of: i, scale: scale), textSize: r.fontSize(of: i),
      label: r.text(of: i), in: view
    ) { [weak self, weak r] in
      guard let self, let r else { return nil }
      return (r.content.convert(r.frame(of: i), to: self.view), r.picture(of: i, scale: scale), r.fontSize(of: i))
    }
    overlay.onClosed = { [weak self] in
      self?.topic = nil
      self?.becomeFirstResponder()
    }
    view.addSubview(overlay)
    topic = overlay
    overlay.open()
  }

  // ─── Footnotes ───────────────────────────────────────────────────────────

  /// The mark under a finger at `p`, if the page can be read just now.
  private func markUnder(_ p: CGPoint) -> TapMark? {
    guard !atHome, topic == nil else { return nil }
    return reader.mark(at: reader.content.convert(p, from: view))
  }

  /// Opens a note at its mark, in place, over the page.
  private func openNote(_ mark: TapMark) {
    guard let text = library.book?.noteText(mark.note, traits: traitCollection) else { return }
    closeTips()
    let at = reader.content.convert(mark.rect, to: view)
    let note = NoteTip(note: mark.note, label: library.book?.noteLabels[mark.note] ?? "", text: text, mark: at, host: view)
    view.insertSubview(note, aboveSubview: curtain)
    tip = (note, reader.currentY)
    note.open()
    kick()
  }

  /// Puts away the open note, if there is one.
  private func closeNote(quickly: Bool = false) {
    guard let open = tip else { return }
    tip = nil
    open.view.close(quickly: quickly)
  }

  /// A note belongs to where it was opened: it goes when the text moves from under it.
  private func keepNoteInPlace() {
    if contents != nil, atHome { closeContents(quickly: true) }
    guard let open = tip else { return }
    if atHome || abs(reader.currentY - open.y) > 1.5 { closeNote(quickly: true) }
  }

  /// Puts away whatever's open over the page.
  private func closeTips(quickly: Bool = false) {
    closeNote(quickly: quickly)
    closeContents(quickly: quickly)
  }

  @objc private func onTap(_ g: UITapGestureRecognizer) { tapped(g.location(in: view)) }

  private func tapped(_ p: CGPoint) {
    // With the contents open, a tap only puts them away.
    if contents != nil { return closeContents() }
    // On a mark, its note; anywhere else, only puts away the one that's open.
    if let mark = markUnder(p), mark.note != tip?.view.note {
      openNote(mark)
    } else {
      closeTips()
    }
  }

  // ─── The contents ────────────────────────────────────────────────────────

  /// Opens the contents out of the ring, or puts them back.
  private func toggleContents() {
    guard contents == nil else { return closeContents() }
    guard !atHome else { return }
    closeNote()
    // A tap on a button never reaches the recognizers, which is what stops a scroll otherwise.
    _ = catchGlide()
    let r = reader!
    let rows = r.contents()
    guard !rows.isEmpty else { return }
    let panel = ContentsTip(rows: rows, current: r.currentRow(in: rows), spot: r.ringSpot, ring: r.content.convert(r.ringFrame, to: view), host: view)
    panel.onPick = { [weak self] row in self?.go(to: row) }
    panel.onEscape = { [weak self] in self?.closeContents() }
    view.insertSubview(panel, aboveSubview: curtain)
    contents = panel
    panel.open()
    kick()
  }

  private func closeContents(quickly: Bool = false) {
    contents?.close(quickly: quickly)
    contents = nil
  }

  /// Puts the contents away and takes the text to where `row` leads.
  private func go(to row: ContentsRow) {
    closeContents()
    guard !atHome else { return }
    finish()
    reader.travel(to: row.place)
    gliding = true
    kick()
  }

  // ─── The library ─────────────────────────────────────────────────────────

  /// What was made of a document has changed: what was kept of it no longer
  /// stands. The one being read is left alone until it's put down.
  private func documentChanged(_ id: String) {
    if id == document.id && !atHome {
      stale.insert(id)
      return
    }
    refresh(id)
  }

  private func refresh(_ id: String) {
    stale.remove(id)
    libraries[id] = nil
    if id == document.id, let d = Document.all.first(where: { $0.id == id }), d.openable {
      // Paragraphs may have merged or split, so their levels no longer line up.
      let count = Imports.shared.book(id)?.text.count ?? 0
      if let state = Store.loadReading(id), (state.c?.count ?? count) != count {
        Store.saveReading(id, ReadingState(style: state.style))
      }
      lay(d, again: true)
    }
    homeStale = true
    if atHome { reloadHome() }
  }

  private var libraryIndex: Int { Document.all.firstIndex { $0.id == document.id } ?? 0 }

  private func reloadHome() {
    homeStale = false
    // Under the library, the page comes to rest, so nothing is seen to jump when it's opened.
    if document.openable { reader.rest() }
    homeController.show(Document.all)
  }

  /// Takes the library through a change of state on a steep ease-in-out curve:
  /// gentle to set off, quick through the middle, gentle to land.
  private func transition(_ change: @escaping () -> Void, done: @escaping () -> Void) {
    let a = UIViewPropertyAnimator(
      duration: 0.65, controlPoint1: CGPoint(x: 0.76, y: 0), controlPoint2: CGPoint(x: 0.24, y: 1), animations: change)
    a.addCompletion { _ in done() }
    a.startAnimation()
  }

  /// Steps out of the reader into the library, the page on screen shrinking under its book's cover.
  private func showHome() {
    guard !atHome, topic == nil else { return }
    closeTips(quickly: true)
    finish()
    remember()
    // Nothing more is written ahead while the library shows.
    (library.texts as? LiveText)?.rewriter.want([])
    if stale.contains(document.id) { DispatchQueue.main.async { self.refresh(self.document.id) } }
    let r = reader!
    // The screen as it is, taken at once rather than drawn again, to set off from.
    let screen = r.snapshotView(afterScreenUpdates: false)
    atHome = true
    homeController.awake = true
    // The page goes back to its document's book.
    let index = libraryIndex
    home.isHidden = false
    homeController.scroll(to: index)
    home.alpha = 0
    home.isUserInteractionEnabled = false
    homeController.hideSheet(index, true)
    let sheet = homeController.sheetFrame(index, in: view)
    var zoom: Zoom?
    if let screen {
      let z = Zoom(covers: r.bounds, crop: r.sheetRect, sheet: sheet.size)
      z.show(screen)
      z.full(view.bounds)
      view.insertSubview(z, aboveSubview: home)
      // A book's cover, wide open off the side of the screen, comes back round to shut on the page.
      z.hinge(homeController.sheetCover(index), above: z)
      z.full(view.bounds)
      curtain.isHidden = false
      zoom = z
    }
    transition {
      self.setNeedsStatusBarAppearanceUpdate()
      self.home.alpha = 1
      zoom?.lie(on: sheet)
      zoom?.blur()
    } done: {
      zoom?.removeFromSuperview()
      self.homeController.hideSheet(index, false)
      self.homeController.scrolled()
      self.home.isUserInteractionEnabled = true
    }
    // The covers are brought up to date while the page travels.
    DispatchQueue.main.async {
      self.reloadHome()
      zoom?.smear(self.glimpse(r))
    }
  }

  /// Opens document `index` where it was left.
  private func openFromHome(_ index: Int) {
    guard atHome, home.isUserInteractionEnabled else { return }
    // A document on its way can't be opened yet, or needs seeing to.
    if let next = Document.all[safe: index], !next.openable {
      homeController.explain(next)
      return
    }
    let sheet = homeController.sheetFrame(index, in: view, now: true)
    // What was made of it may have changed while it was put away.
    if stale.contains(document.id) { refresh(document.id) }
    // Another document takes the reader's place, under the library.
    if let next = Document.all[safe: index] { lay(next) }
    leaveHome(from: sheet, cover: homeController.sheetCover(index)) { [weak self] in
      self?.homeController.hideSheet(index, $0)
    }
  }

  /// Grows the book's page out to fill the screen, onto the reader, while
  /// the library fades away around it.
  private func leaveHome(from sheet: CGRect, cover: CoverFaces?, hide: @escaping (Bool) -> Void) {
    finish()
    let r = reader!
    let z = Zoom(covers: r.bounds, crop: r.sheetRect, sheet: sheet.size)
    z.lie(on: sheet)
    view.insertSubview(z, aboveSubview: home)
    z.hinge(cover, above: z)
    z.lie(on: sheet)
    curtain.isHidden = false
    hide(true)
    home.isUserInteractionEnabled = false
    atHome = false
    transition {
      self.setNeedsStatusBarAppearanceUpdate()
      z.full(self.view.bounds)
      z.blur()
      self.home.alpha = 0
    } done: {
      self.home.isHidden = true
      self.curtain.isHidden = true
      self.homeController.awake = false
      hide(false)
      self.becomeFirstResponder()
      // The live page takes over from its copy.
      UIView.animate(withDuration: 0.2, animations: { z.alpha = 0 }) { _ in z.removeFromSuperview() }
    }
    // The page as the screen will show it comes in under the cover while that
    // still hides it: a copy of the reader, which has waited under the library
    // just as it will show, taken as it is rather than drawn again.
    DispatchQueue.main.async {
      if let screen = r.snapshotView(afterScreenUpdates: false) { z.show(screen) }
      z.smear(self.glimpse(r))
    }
  }

  /// A rough picture of the page as the screen shows it, a pixel to every four points, only to smear.
  private func glimpse(_ r: ReaderView) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 0.25
    return UIGraphicsImageRenderer(bounds: r.bounds, format: format).image { _ in
      r.drawHierarchy(in: r.bounds, afterScreenUpdates: false)
    }
  }

  // ─── Keyboard (the same moves, without touch) ────────────────────────────

  override var keyCommands: [UIKeyCommand]? {
    func key(_ input: String, _ action: Selector, _ title: String? = nil) -> UIKeyCommand {
      let c = UIKeyCommand(input: input, modifierFlags: [], action: action)
      c.wantsPriorityOverSystemBehavior = true
      if let title { c.discoverabilityTitle = title }
      return c
    }
    if atHome {
      return homeController.presenting ? [] : [key("\r", #selector(keyContinue), "Continue Reading")]
    }
    if topic != nil {
      return [key(UIKeyCommand.inputEscape, #selector(keyCloseTopic), "Close")]
    }
    return [
      key(UIKeyCommand.inputRightArrow, #selector(keyHarder), "Harder"),
      key(UIKeyCommand.inputLeftArrow, #selector(keyEasier), "Simpler"),
      key("-", #selector(keyShorter), "Shorter"),
      key("=", #selector(keyLonger), "Longer"),
      key(UIKeyCommand.inputDownArrow, #selector(keyDown)),
      key(UIKeyCommand.inputUpArrow, #selector(keyUp)),
      key(" ", #selector(keyPageDown)),
      key(UIKeyCommand.inputEscape, #selector(keyEscape), "Library"),
    ]
  }

  /// Runs a change to the page from a key or a tap, once whatever's open over it is put away.
  private func act(_ action: () -> Void) {
    guard !atHome else { return }
    closeTips()
    finish()
    action()
    kick()
  }

  /// The paragraph a key acts on: the one in the middle of the screen.
  private var middle: Double { H / 2 }

  private func nudgeZoom(_ d: Double) {
    let r = reader!
    r.anchorAt(middle, x: W / 2)
    r.origin = CGPoint(x: W / 2, y: r.anchor.screenY)
    let focus = r.anchor.index
    r.pinTop(around: focus, reach: 0)
    let before = r.paras.map { $0.z.target }
    settleZoom(focus, before, d)
    // Nothing left to change: bump against the end instead.
    if zip(r.paras, before).allSatisfy({ $0.z.target == $1 }) { r.stretch.velocity += d * 8 }
  }

  private func nudgeComplexity(_ d: Double) {
    let r = reader!
    let i = r.hit(middle, x: W / 2)
    let p = r.paras[i]
    r.rebase(i, 0)
    p.c.response = Feel.settle
    // A step to the next version that reads differently.
    let c = Int(clamp(p.c.target.rounded(), 0, Double(library.cMax)))
    let steps = r.steps(i, from: c)
    let next = steps.index(of: c) + Int(d)
    if next < 0 || next > steps.last { p.c.velocity += d * 6 }
    p.c.target = Double(steps.at[min(max(next, 0), steps.last)])
  }

  private func glide(_ d: Double) {
    reader.anchor.screenY -= d
    reader.offset.value += d
    gliding = true
  }

  @objc private func keyHarder() { act { nudgeComplexity(1) } }
  @objc private func keyEasier() { act { nudgeComplexity(-1) } }
  @objc private func keyShorter() { act { nudgeZoom(1) } }
  @objc private func keyLonger() { act { nudgeZoom(-1) } }
  @objc private func keyDown() { act { glide(Double(reader.typeset.setter.lineHeight) * 3) } }
  @objc private func keyUp() { act { glide(-Double(reader.typeset.setter.lineHeight) * 3) } }
  @objc private func keyPageDown() { act { glide(H * 0.8) } }
  @objc private func keyCloseTopic() { topic?.close() }
  @objc private func keyContinue() {
    homeController.scroll(to: libraryIndex)
    openFromHome(libraryIndex)
  }
  @objc private func keyEscape() {
    // Whatever's open on the page goes first.
    if tip != nil || contents != nil { closeTips() } else { showHome() }
  }
}

/// A page on its way between the desk and its sheet in the library. It holds
/// the page as the screen shows it (`covers`, all of it); over it, where `crop`
/// of the page lies, the sheet's own picture; and over that the sheet's paper.
/// It fills the screen looking just as the screen does, or lies on the sheet
/// looking just as the sheet does, clipped to it.
private final class Zoom: UIView {
  private let covers: CGRect
  private let crop: CGRect
  /// A book's cover, if the sheet is a book: over the page, hinged at its left.
  private var leaf: CoverLeaf?
  /// The shadow in the book's gutter, along the page's left edge; gone once it fills the screen.
  private let gutter = GutterView()
  private var radius: CGFloat
  /// The page and everything drawn on it, moved and scaled as one.
  private let page = UIView()
  /// The sheet's picture, there while it lies on the sheet.
  private let thumb = UIImageView()
  /// A softened copy of the page, laid over it to stand in for motion blur.
  private let streak = UIImageView()
  /// The sheet's paper over the page: its stock, its grain and its edge, there
  /// while it lies on the sheet, gone as it fills the screen.
  private let wash = UIView()
  private let grain = UIView()
  private let edge = UIView()

  private static let sheetRadius: CGFloat = 6

  /// The hairline round a sheet.
  private static func edge(_ t: UITraitCollection) -> UIColor {
    t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : Parchment.umbra.resolvedColor(with: t).withAlphaComponent(0.1)
  }

  /// `sheet` is the size of what it lies on, which needn't be the page's shape.
  init(covers: CGRect, crop: CGRect, sheet size: CGSize) {
    self.covers = covers
    self.crop = crop
    radius = Self.sheetRadius
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = Palette.page
    layer.cornerCurve = .continuous
    page.bounds = CGRect(origin: .zero, size: covers.size)
    var sheet = crop.offsetBy(dx: -covers.minX, dy: -covers.minY)
    sheet.size.height = sheet.width * size.height / max(1, size.width)
    thumb.frame = sheet
    thumb.contentMode = .scaleToFill
    streak.frame = page.bounds
    streak.alpha = 0
    for v in [thumb, streak] { page.addSubview(v) }
    addSubview(page)
    wash.layer.compositingFilter = "multiplyBlendMode"
    edge.layer.cornerCurve = .continuous
    for v in [wash, grain, edge] { addSubview(v) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    let t = traitCollection
    wash.backgroundColor = Parchment.wash
    grain.backgroundColor = t.userInterfaceStyle == .dark ? nil : PaperBackdrop.grain(t)
    edge.layer.borderColor = Self.edge(t).cgColor
    edge.layer.borderWidth = 1 / max(t.displayScale, 1)
  }

  /// Lays the page as the screen shows it, buttons and all, under the sheet's picture.
  func show(_ screen: UIView) {
    screen.frame = page.bounds
    page.insertSubview(screen, at: 0)
  }

  /// Softens `picture`, all of the page, to stand in for motion blur. Away from
  /// the main thread: the blur isn't wanted until the page is well on its way.
  func smear(_ picture: UIImage) {
    DispatchQueue.global(qos: .userInteractive).async {
      let soft = Self.soften(picture)
      DispatchQueue.main.async { self.streak.image = soft }
    }
  }

  /// Scales the page by `s`, its top left at `origin`. A transform rather
  /// than a frame, so what's drawn on it is only ever scaled, never drawn again.
  private func place(_ s: CGFloat, _ origin: CGPoint) {
    page.transform = CGAffineTransform(scaleX: s, y: s)
    page.center = CGPoint(x: origin.x + covers.width * s / 2, y: origin.y + covers.height * s / 2)
  }

  /// How much of the sheet shows: 1 lying on it, 0 filling the screen.
  private func sheeted(_ a: CGFloat) {
    for v in [wash, grain, edge] { v.frame = bounds }
    edge.layer.cornerRadius = layer.cornerRadius
    for v in [thumb, wash, edge] { v.alpha = a }
    grain.alpha = 0.6 * a
    gutter.alpha = a
  }

  func full(_ screen: CGRect) {
    frame = screen
    layer.cornerRadius = 0
    sheeted(0)
    place(1, covers.origin)
    leaf?.open(over: screen)
  }

  /// Hangs a cover, if there's one, over the page: a sibling above it, since a
  /// clipped view can't let it swing out, and removed along with it.
  func hinge(_ cover: CoverFaces?, above view: UIView) {
    guard let cover, let parent = superview else { return }
    let leaf = CoverLeaf(cover, size: CGSize(width: max(1, thumb.bounds.width), height: max(1, thumb.bounds.height)))
    parent.insertSubview(leaf, aboveSubview: view)
    self.leaf = leaf
    // Under a closed cover there's no paper to show but the page itself.
    thumb.isHidden = true
    radius = 2.6
    gutter.frame = page.bounds
    page.addSubview(gutter)
  }

  override func removeFromSuperview() {
    leaf?.removeFromSuperview()
    super.removeFromSuperview()
  }

  /// Lies on `sheet`, which shows `crop` of the page.
  func lie(on sheet: CGRect) {
    let s = sheet.width / crop.width
    frame = sheet
    layer.cornerRadius = radius
    sheeted(1)
    place(s, CGPoint(x: (covers.minX - crop.minX) * s, y: (covers.minY - crop.minY) * s))
    leaf?.shut(on: sheet)
  }

  /// Blurs the page while it travels fastest, sharp again as it comes to rest.
  /// Called inside the transition's animations, whose curve it shares, so the
  /// blur peaks halfway, where the curve is steepest.
  func blur() {
    UIView.animateKeyframes(withDuration: 0, delay: 0, options: .calculationModeCubic) {
      UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) { self.streak.alpha = 0.85 }
      UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) { self.streak.alpha = 0 }
    }
  }

  private static let ci = CIContext()

  /// Builds Core Image's blur once, ahead of time, so the first zoom doesn't wait on it.
  static func warmUp() {
    DispatchQueue.global(qos: .utility).async {
      _ = soften(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in })
    }
  }

  /// A small, blurred copy of `image`, a pixel to every four points; it's only ever seen in motion.
  private static func soften(_ image: UIImage) -> UIImage? {
    guard let cg = image.cgImage else { return nil }
    let k = 0.25 / image.scale
    let small = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: k, y: k))
    let extent = small.extent
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = small.clampedToExtent()
    blur.radius = 2.5
    guard let out = blur.outputImage?.cropped(to: extent), let made = ci.createCGImage(out, from: extent) else { return nil }
    return UIImage(cgImage: made)
  }
}

/// The shade where a page turns in toward a book's spine.
private final class GutterView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    guard let g = layer as? CAGradientLayer else { return }
    g.colors = [UIColor(white: 0, alpha: 0.34).cgColor, UIColor(white: 0, alpha: 0.08).cgColor, UIColor(white: 0, alpha: 0).cgColor]
    g.locations = [0, 0.07, 0.2]
    g.startPoint = .zero
    g.endPoint = CGPoint(x: 1, y: 0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}

/// A book's cover on its way between shut on the book and wide open beyond the
/// edge of the screen: both faces, on a hinge along the left, in perspective.
/// It's scaled rather than laid out afresh, so that the whole thing moves with
/// the page beneath it, one transform to each.
private final class CoverLeaf: UIView {
  /// A transform layer, so that each face is in space rather than flattened
  /// onto its parent, and turning its back hides it.
  private final class Swing: UIView {
    override class var layerClass: AnyClass { CATransformLayer.self }
  }
  private let swing = Swing()
  private let front = UIImageView()
  private let inside = UIImageView()
  /// The front as the library's lamp lights it, there while it's shut on the book.
  private let lit = UIImageView()
  /// Light leaving each face as it turns away.
  private let frontShade = UIView()
  private let insideShade = UIView()
  private let size: CGSize

  init(_ faces: CoverFaces, size: CGSize) {
    self.size = size
    super.init(frame: CGRect(origin: .zero, size: size))
    isUserInteractionEnabled = false
    layer.sublayerTransform = {
      var p = CATransform3DIdentity
      p.m34 = -1 / (size.width * 3.1)
      return p
    }()
    swing.frame = bounds
    swing.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
    swing.layer.position = CGPoint(x: 0, y: size.height / 2)
    addSubview(swing)
    for (v, image) in [(inside, faces.inside), (front, faces.front)] {
      v.image = image
      v.frame = swing.bounds
      v.contentMode = .scaleToFill
      v.layer.isDoubleSided = false
      swing.addSubview(v)
    }
    inside.transform3D = CATransform3DMakeRotation(.pi, 0, 1, 0)
    lit.image = faces.lit
    lit.isHidden = faces.lit == nil
    lit.frame = front.bounds
    lit.contentMode = .scaleToFill
    front.addSubview(lit)
    frontShade.backgroundColor = .black
    insideShade.backgroundColor = .black
    frontShade.frame = front.bounds
    insideShade.frame = inside.bounds
    front.addSubview(frontShade)
    inside.addSubview(insideShade)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func shut(on sheet: CGRect) {
    let sx = sheet.width / size.width
    let sy = sheet.height / size.height
    transform = CGAffineTransform(scaleX: sx, y: sy)
    center = CGPoint(x: sheet.midX, y: sheet.midY)
    swing.transform3D = CATransform3DIdentity
    // In the library's light, as the book it lies on is; out of it as it leaves, with the library.
    lit.alpha = 1
    frontShade.alpha = 0
    // Only seen once it's past halfway, coming into the light from the dark.
    insideShade.alpha = 0.7
  }

  func open(over screen: CGRect) {
    // As tall as the screen, and off its left edge by the time it's there.
    let sx = screen.width / size.width
    let sy = screen.height / size.height
    transform = CGAffineTransform(scaleX: sx, y: sy)
    center = CGPoint(x: screen.midX, y: screen.midY)
    swing.transform3D = CATransform3DMakeRotation(-.pi * 0.97, 0, 1, 0)
    lit.alpha = 0
    frontShade.alpha = 0.72
    insideShade.alpha = 0
  }
}

// ─── Driving the app from a script, for testing ──────────────────────────────

#if DEBUG
extension DeskViewController {
  /// Runs a script of commands, one to a line, against the real import pipeline
  /// and the real reader: `-drive path` on launch. Nothing here reaches a release build.
  func drive(_ path: String) {
    let log = path + ".log"
    FileManager.default.createFile(atPath: log, contents: nil)
    func say(_ s: String) {
      let line = "\(String(format: "%.1f", CACurrentMediaTime())) \(s)\n"
      if let h = FileHandle(forWritingAtPath: log) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
      }
    }
    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    Task { @MainActor [weak self] in
      guard let self, let script = try? String(contentsOfFile: path, encoding: .utf8) else { return }
      await wait(1.5)
      var lastImport: String?
      for raw in script.split(separator: "\n") {
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first, !command.hasPrefix("#") else { continue }
        let arg = parts.count > 1 ? parts[1] : ""
        say("> \(raw)")
        switch command {
        case "check": Store.checkImports = arg == "on"
        case "import":
          Structure.tracing = true
          Structure.trace = []
          lastImport = Imports.shared.add([URL(fileURLWithPath: arg)]).last
          await wait(0.5)
        case "ready", "done":
          let limit = CACurrentMediaTime() + (command == "ready" ? 300 : 900)
          while CACurrentMediaTime() < limit {
            guard let id = lastImport, let e = Imports.shared.entry(id) else { break }
            if e.stage == .failed || e.stage == .locked { say("  stage \(e.stage.rawValue): \(e.problem ?? "")"); break }
            if command == "ready" ? e.readable : e.stage == .done { break }
            await wait(0.25)
          }
          if let id = lastImport, let e = Imports.shared.entry(id) { say("  stage \(e.stage.rawValue) readable \(e.readable) report \(e.report.rawValue) title: \(e.title)") }
        case "open":
          let i = arg == "last" ? Document.all.count - 1 : (Int(arg) ?? 0)
          if !self.atHome { self.showHome(); await wait(1) }
          self.openFromHome(i)
          await wait(1.2)
        case "home":
          self.showHome()
          await wait(1.2)
        case "look":
          self.reader.setStyle(ReadingStyle(rawValue: Int(arg) ?? 0) ?? .plain)
          self.kick()
          await wait(0.8)
        case "scroll":
          let r = self.reader!
          r.anchorForScrolling()
          r.anchor.screenY -= Double(arg) ?? 0
          self.kick()
          await wait(0.9)
        case "shorter": self.act { self.nudgeZoom(1) }; await wait(1)
        case "longer": self.act { self.nudgeZoom(-1) }; await wait(1)
        case "harder": self.act { self.nudgeComplexity(1) }; await wait(1)
        case "easier": self.act { self.nudgeComplexity(-1) }; await wait(1)
        case "wait": await wait(Double(arg) ?? 1)
        case "homebook":
          self.homeController.scroll(to: Int(arg) ?? 0)
          await wait(0.5)
        case "settings":
          self.homeController.openSettings()
          await wait(1)
        case "slow":
          // Everything on screen at `arg` of its speed, to look at a transition frame by frame.
          self.view.window?.layer.speed = Float(arg) ?? 1
        case "topic":
          let xy = arg.split(separator: " ").compactMap { Double($0) }
          if xy.count == 2 { self.openTopic(at: CGPoint(x: xy[0], y: xy[1])) }
          await wait(3)
        case "closetopic":
          self.topic?.close()
          await wait(1)
        case "notes":
          // Everything found, and what small print wasn't taken for a note, for checking an import by.
          guard let doc = Imports.shared.book(self.document.id)?.doc else { break }
          let linked = doc.blocks.filter { $0.mark != nil }
          say("  notes \(linked.count) footnotes \(linked.filter { $0.role == .footnote }.count) printed \(doc.marks.count) folios \(doc.pages.reduce(0) { $0 + $1.folios.count }) pages \(doc.pages.count)")
          for b in linked {
            let host = doc.blocks.first { NoteToken.ids($0.text).contains(b.id) }
            var near = "(no mark)"
            if let t = host?.text, let r = t.range(of: NoteToken.make(b.id)) { near = String(NoteToken.strip(String(t[..<r.lowerBound])).suffix(28)) }
            say("  [\(b.mark ?? "?")] p\(b.pieces.first.map { $0.page + 1 } ?? 0) \(b.role.rawValue) pieces \(b.pieces.count) after “\(near)” (\(host?.role.rawValue ?? "-")): \(b.text.prefix(120))")
          }
          for b in doc.blocks where b.role == .note || (b.role == .minor && b.words >= 6) { say("  small \(b.role.rawValue) p\((b.pieces.first?.page ?? 0) + 1): \(b.text.prefix(90))") }
        case "snap":
          // For a real screenshot to be taken from outside, which is the only way to see glass as it is.
          say("SNAP \(arg)")
          await wait(1.4)
        case "trace":
          for line in Structure.trace { say(line) }
          Structure.trace = []
        case "tapnote":
          let marks = self.reader.marksInView().filter { $0.rect.midY > 90 && $0.rect.midY < CGFloat(self.H) - 90 }
          say("  marks in view \(marks.count)")
          if let m = marks[safe: Int(arg) ?? 0] {
            self.openNote(m)
            say("  opened \(m.note) at \(self.reader.content.convert(m.rect, to: self.view))")
          }
          await wait(1.2)
        case "tapat":
          // As a finger on the page would: what's under it, if anything, opens.
          let xy = arg.split(separator: " ").compactMap { Double($0) }
          if xy.count == 2 { self.tapped(CGPoint(x: xy[0], y: xy[1])) }
          say("  note open: \(self.tip?.view.note.description ?? "none")")
          await wait(1)
        case "marks":
          let r = self.reader!
          for m in r.marksInView() { say("  mark \(m.note) at \(r.content.convert(m.rect, to: self.view))") }
        case "selftest":
          // What marks do to text, with nothing to look at.
          @MainActor func check(_ name: String, _ got: String, _ want: String) { say("  \(got == want ? "ok" : "FAILED") \(name): \(got)\(got == want ? "" : " (wanted \(want))")") }
          check("strip", NoteToken.strip("a word[^12], and[^3] more"), "a word, and more")
          check("tighten", NoteToken.tighten("a word [^12], and  [^3] more"), "a word[^12], and[^3] more")
          check("shift", NoteToken.shift("a[^1] b[^20]", by: 5), "a[^6] b[^25]")
          check("keeps a mark that stayed", NoteToken.restore("the bees dance[^1] well.", from: "bees dance[^1] very well."), "the bees dance[^1] well.")
          check("puts back a dropped mark", NoteToken.restore("the bees dance very well.", from: "bees dance,[^1] very well."), "the bees dance[^1] very well.")
          check("after what closes the word", NoteToken.restore("they dance, in turn.", from: "Bees dance,[^7] then rest."), "they dance,[^7] in turn.")
          check("at the end if its word is gone", NoteToken.restore("something else entirely.", from: "Bees dance[^4] well."), "something else entirely.[^4]")
          check("drops an invented mark", NoteToken.restore("bees[^9] dance.", from: "bees dance."), "bees dance.")
          check("label of a number", MarkLabel.normal("¹²") ?? "nil", "12")
          check("label of an asterisk", MarkLabel.normal("∗") ?? "nil", "*")
          check("not a mark", MarkLabel.normal("st") ?? "nil", "nil")
          check("list", (MarkLabel.list("3–5") ?? []).joined(separator: " "), "3 4 5")
          check("list of a number and a symbol", (MarkLabel.list("1,∗†") ?? []).joined(separator: " "), "1 * †")
          check("words in a word", String(Scale.count("one two[^3] [^4] three")), "3")
          check("sentences past a mark", String(format: "%.1f", Scale.grade(of: "The bee flew.[^1] It came back.")), String(format: "%.1f", Scale.grade(of: "The bee flew. It came back.")))
          check("address over two lines", NoteToken.joinNote(["See https://a.org/b-", "c/d for it."], known: { _ in true }), "See https://a.org/b-c/d for it.")
          check("address that ends", NoteToken.joinNote(["See https://a.org/b", "for it."], known: { _ in true }), "See https://a.org/b for it.")
        case "closenote":
          self.closeTips()
          await wait(0.8)
        case "contents":
          // As a finger on the ring would.
          self.toggleContents()
          let rows = self.reader.contents()
          say("  current \(self.reader.currentRow(in: rows).map(String.init) ?? "none") of \(rows.count)")
          for (k, row) in rows.enumerated().prefix(60) { say("  [\(k)] \(String(repeating: "  ", count: row.depth))\(row.title) p\(row.page.map { String($0 + 1) } ?? "-")") }
          await wait(1.2)
        case "hit":
          // What a finger put down there would land on.
          let xy = arg.split(separator: " ").compactMap { Double($0) }
          if xy.count == 2 {
            let p = CGPoint(x: xy[0], y: xy[1])
            let v = self.view.hitTest(p, with: nil)
            say("  hit \(v.map { String(describing: type(of: $0)) } ?? "nothing") for the page's recognizers: \(!(v is UIControl) && !(v.map { $0.isDescendant(of: self.contents ?? UIView()) } ?? false))")
          }
        case "tips":
          say("  contents on screen \(self.view.subviews.filter { $0 is ContentsTip }.count)")
        case "pick":
          // As a finger on a row would.
          if let row = self.reader.contents()[safe: Int(arg) ?? 0] { self.go(to: row) }
          await wait(1.4)
          let r = self.reader!
          say("  y \(r.currentY) range \(r.range()) page \(r.ringSpot.page + 1) of \(r.ringSpot.of) contents open \(self.contents != nil)")
        case "text":
          // The paragraph on screen, with its marks, as the text holds it.
          let r = self.reader!
          say("  \(r.library.texts.draft(r.hit(self.H / 2), Int(r.paras[r.hit(self.H / 2)].c.target), Int(r.paras[r.hit(self.H / 2)].z.target)).text.prefix(400))")
        case "dismiss":
          self.presentedViewController?.dismiss(animated: false)
          await wait(0.5)
        case "unlock":
          if let id = lastImport { say("  unlocked: \(Imports.shared.unlock(id, password: arg))") }
          await wait(0.5)
        case "remove":
          if let id = lastImport { Imports.shared.remove(id) }
          await wait(0.5)
        case "style":
          self.view.window?.overrideUserInterfaceStyle = arg == "dark" ? .dark : .light
          await wait(0.8)
        case "size":
          // As if the window were this size, which is as near as a script can get to rotating it in windowed mode.
          let wh = arg.split(separator: " ").compactMap { Double($0) }
          if wh.count == 2 { self.view.window?.frame = CGRect(x: 0, y: 0, width: wh[0], height: wh[1]) }
          await wait(1.2)
        case "orient":
          self.setNeedsUpdateOfSupportedInterfaceOrientations()
          self.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: arg == "portrait" ? .portrait : .landscapeLeft)) { e in say("  orient: \(e.localizedDescription)") }
          await wait(1.5)
          say("  bounds \(self.view.bounds.size)")
        case "shot":
          guard let window = self.view.window else { break }
          let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
          try? image.pngData()?.write(to: URL(fileURLWithPath: arg))
          say("  shot \(arg)")
        case "memory":
          var info = task_vm_info_data_t()
          var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
          let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
          if kr == KERN_SUCCESS { say("  footprint \(info.phys_footprint / 1024 / 1024) MB") }
        case "state":
          let r = self.reader!
          say("  doc \(self.document.title.prefix(40)) look \(r.style.name) paragraphs \(r.paras.count) shown \(r.order.count) height \(Int(r.contentH)) y \(Int(r.currentY))")
        case "quit":
          say("bye")
          exit(0)
        default: say("  unknown")
        }
      }
      say("end of script")
    }
  }
}
#endif
