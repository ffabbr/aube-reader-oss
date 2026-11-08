import UIKit
import WebKit

/// Plays a drawing from the library. The library's animation is CSS (paths to
/// travel along, staggered delays, calc() and the like), so a web view is what
/// can play it faithfully. Web views are slow to start and would catch the
/// card mid-flight, so a few are started ahead, kept empty, and lent out: a
/// drawing appears in one the moment it's put in, starting from its first
/// stroke, plays through once and slows to a stop.
final class DrawingView: UIView {
  /// Small, the drawing goes without its lettering, and its lines stand a
  /// little heavier, so that it still reads at a third of its size.
  var small = false
  /// In the library's inks, on its paper, rather than the desk's greys.
  var paper = false
  private var canvas: Canvas?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    canvas?.web.frame = bounds
  }

  func show(_ drawing: Drawing) {
    guard canvas == nil, let svg = drawing.svg else { return }
    let c = Canvas.take()
    canvas = c
    c.web.frame = bounds
    addSubview(c.web)
    c.draw(svg, small: small, paper: paper)
  }

  /// Hands the web view back, for the next topic.
  func putAway() {
    guard let c = canvas else { return }
    canvas = nil
    c.web.removeFromSuperview()
    Canvas.give(c)
  }
}

/// A web view with nothing in it but a place to put a drawing.
private final class Canvas: NSObject, WKNavigationDelegate {
  let web: WKWebView
  private var ready = false
  /// A drawing put in before the page had loaded.
  private var waiting: (svg: String, small: Bool, paper: Bool)?

  private static var spare: [Canvas] = []

  /// Enough for a topic's drawings to be shown without starting another.
  static func warm() {
    while spare.count < TopicWriter.count { spare.append(Canvas()) }
  }

  static func take() -> Canvas { spare.popLast() ?? Canvas() }

  static func give(_ c: Canvas) {
    c.clear()
    spare.append(c)
  }

  private static let page = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
    html,body{margin:0;height:100%;background:transparent;overflow:hidden}
    body>svg{display:block;width:100%;height:100%}
    body.small .t{display:none}
    body.small .s{stroke-width:2.1}
    body.small .q{stroke-width:1.8}
    body.small .f{stroke-width:1.5}
    body.small .hair{stroke-width:1.4!important}
    body.small .bold{stroke-width:2.8!important}
    body.paper{--ink:#2e2418;--quiet:#6a5a44;--faint:#b5a78d;--wash:#efe8d8}
    @media (prefers-color-scheme:dark){body.paper{--ink:#e8dcc6;--quiet:#a39d93;--faint:#5e5648;--wash:#26231f}}
    </style><script>
    // The drawings are built to loop, fading out at 9 s of 10. Here each plays
    // once: from 7.5 s, with everything drawn, all its motion slows to a halt
    // over 3 s, coming to rest at 8.5 s, short of the fade.
    var run = 0;
    function draw(svg, small, paper) {
      document.body.className = (small ? 'small ' : '') + (paper ? 'paper' : '');
      document.body.innerHTML = svg;
      var me = ++run, start = performance.now(), all = null;
      function tick(now) {
        if (me !== run) return;
        var u = (now - start - 7500) / 3000;
        if (u >= 0) {
          all = all || document.getAnimations();
          for (var a of all) {
            if (u >= 1) {
              if (a.animationName === 'out') a.currentTime = 0;
              a.pause();
            } else {
              a.playbackRate = (1 - u) * (1 - u);
            }
          }
          if (u >= 1) return;
        }
        requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    }
    // As a drawing played through comes to rest: everything drawn, nothing moving.
    function still(svg) {
      run++;
      document.body.className = 'small';
      document.body.innerHTML = svg;
      for (var a of document.getAnimations()) {
        a.currentTime = a.animationName === 'out' ? 0 : 8500;
        a.pause();
      }
    }
    </script></head><body></body></html>
    """

  override init() {
    web = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
    super.init()
    web.isOpaque = false
    web.backgroundColor = .clear
    web.scrollView.backgroundColor = .clear
    web.scrollView.isScrollEnabled = false
    web.scrollView.contentInsetAdjustmentBehavior = .never
    web.isUserInteractionEnabled = false
    web.navigationDelegate = self
    web.loadHTMLString(Canvas.page, baseURL: nil)
  }

  func draw(_ svg: String, small: Bool, paper: Bool = false) {
    guard ready else {
      waiting = (svg, small, paper)
      return
    }
    // Encoded as JSON, the SVG arrives as a string literal, whatever's in it.
    guard
      let data = try? JSONSerialization.data(withJSONObject: [svg]),
      let list = String(data: data, encoding: .utf8)
    else { return }
    web.evaluateJavaScript("draw(\(list)[0],\(small),\(paper));0")
  }

  /// `svg` at rest as a picture `width` points wide, on nothing. The web view
  /// has to be in a window for this.
  func picture(of svg: String, dark: Bool, width: CGFloat) async -> UIImage? {
    for _ in 0..<100 where !ready { try? await Task.sleep(for: .milliseconds(50)) }
    guard ready, let data = try? JSONSerialization.data(withJSONObject: [svg]), let list = String(data: data, encoding: .utf8) else { return nil }
    web.overrideUserInterfaceStyle = dark ? .dark : .light
    guard (try? await web.evaluateJavaScript("still(\(list)[0]);0")) != nil else { return nil }
    let config = WKSnapshotConfiguration()
    config.rect = web.bounds
    config.snapshotWidth = NSNumber(value: Double(width))
    return try? await web.takeSnapshot(configuration: config)
  }

  private func clear() {
    waiting = nil
    if ready { web.evaluateJavaScript("run++;document.body.innerHTML='';0") }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    ready = true
    if let w = waiting {
      waiting = nil
      draw(w.svg, small: w.small, paper: w.paper)
    }
  }

  /// The system ends web processes it wants the memory of; this starts it again.
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    ready = false
    web.loadHTMLString(Canvas.page, baseURL: nil)
  }
}

extension DrawingView {
  /// Starts the web views a topic will borrow, ahead of the first long press.
  static func warm() { Canvas.warm() }

  /// The one web view pictures of drawings are taken in. Kept beside `host`,
  /// out of sight, since a web view outside a window draws nothing.
  private static var easel: Canvas?

  /// A drawing at rest and without its lettering, as a picture `width` points wide, on nothing.
  static func picture(of svg: String, dark: Bool, width: CGFloat, in host: UIView) async -> UIImage? {
    let easel = easel ?? Canvas()
    Self.easel = easel
    if easel.web.superview !== host {
      // The drawings' own canvas, off the edge of the screen.
      easel.web.frame = CGRect(x: -500, y: 0, width: 400, height: 240)
      host.insertSubview(easel.web, at: 0)
    }
    return await easel.picture(of: svg, dark: dark, width: width)
  }
}

/// Bars standing in for words not yet written, breathing as the placeholders
/// on the reader's page do: a bar per word, in a wave along the line.
final class Bones: UIView {
  private let bars = CALayer()
  private var built: CGSize?
  private let words: [Int]
  private let font: UIFont
  private var letter: CGFloat { font.pointSize * 0.47 }
  private var space: CGFloat { font.pointSize * 0.26 }

  /// `words` is how many letters each stands for.
  init(words: [Int], font: UIFont) {
    self.words = words
    self.font = font
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    layer.addSublayer(bars)
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Bones, _) in
      self.built = nil
      self.setNeedsLayout()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// How tall the bars' line stands.
  var lineHeight: CGFloat { (font.lineHeight * 1.1).rounded() }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard built != bounds.size else { return }
    built = bounds.size
    build()
  }

  private func build() {
    bars.sublayers?.forEach { $0.removeFromSuperlayer() }
    bars.frame = bounds
    let thick = (font.xHeight * 1.25).rounded()
    // Breaks into lines as text would, each centered.
    var lines: [[CGFloat]] = [[]]
    var used: CGFloat = 0
    for w in words.map({ (CGFloat($0) * letter).rounded() }) {
      if !lines[lines.count - 1].isEmpty && used + space + w > bounds.width {
        lines.append([])
        used = 0
      }
      used += (lines[lines.count - 1].isEmpty ? 0 : space) + w
      lines[lines.count - 1].append(w)
    }
    let color = Palette.ink.resolvedColor(with: traitCollection).withAlphaComponent(0.13).cgColor
    let calm = UIAccessibility.isReduceMotionEnabled
    let top = ((bounds.height - lineHeight * CGFloat(lines.count)) / 2).rounded()
    let epoch = CACurrentMediaTime()
    for (n, line) in lines.enumerated() {
      var x = ((bounds.width - line.reduce(0, +) - space * CGFloat(line.count - 1)) / 2).rounded()
      let y = top + CGFloat(n) * lineHeight + ((lineHeight - thick) / 2).rounded()
      for w in line {
        let bar = StillLayer()
        bar.frame = CGRect(x: x, y: y, width: w, height: thick)
        bar.cornerRadius = thick / 2
        bar.backgroundColor = color
        if !calm {
          let a = CABasicAnimation(keyPath: "opacity")
          a.fromValue = 1
          a.toValue = 0.4
          a.duration = 0.75
          a.autoreverses = true
          a.repeatCount = .infinity
          a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          a.beginTime = epoch + Double(x) / 700 + Double(y) / 2600
          a.fillMode = .backwards
          bar.add(a, forKey: "breathe")
        }
        bars.addSublayer(bar)
        x += w + space
      }
    }
  }

  /// Fades the bars away as the words come.
  func finish() {
    guard !isHidden, bars.animation(forKey: "go") == nil else { return }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in self?.isHidden = true }
    let a = CABasicAnimation(keyPath: "opacity")
    a.fromValue = 1
    a.toValue = 0
    a.duration = 0.5
    a.timingFunction = CAMediaTimingFunction(name: .easeOut)
    bars.opacity = 0
    bars.add(a, forKey: "go")
    CATransaction.commit()
  }
}
