import UIKit

/// A closer look at what one paragraph is about: a drawing, a title and a
/// line beneath it, then a few aspects to open one at a time (the page shows
/// the first three). The paragraph itself comes along as the page's text.
struct Topic {
  struct Aspect {
    let title: String
    let teaser: String
    let body: String
    let sketch: Sketch
  }

  let title: String
  let deck: String
  let sketch: Sketch
  let aspects: [Aspect]

  /// The page of a topic not written by hand, before `TopicWriter` has filled it in.
  static let blank = Topic(title: "", deck: "", sketch: Sketch(400, 240, []), aspects: [])

  /// The paragraphs written by hand, in each look (by index in content.json);
  /// every other paragraph's topic is found by `TopicWriter` when it's asked for.
  static let demo: [ReadingStyle: (paragraph: Int, topic: Topic)] = [
    .plain: (2, .horizon),
    .paper: (3, .dilation),
    .journal: (9, .kerr),
  ]

  static func at(_ paragraph: Int, in style: ReadingStyle) -> Topic? {
    demo[style].flatMap { $0.paragraph == paragraph ? $0.topic : nil }
  }
}

// ─── Drawing helpers ─────────────────────────────────────────────────────────

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// A clock face that has ticked through `share` of a turn.
private func clock(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ share: CGFloat) -> Mark {
  let a = -CGFloat.pi / 2 + share * 2 * .pi
  let end = pt(cx + cos(a) * r * 0.86, cy + sin(a) * r * 0.86)
  let wedge = "M\(cx),\(cy) L\(cx),\(cy - r * 0.86) A\(r * 0.86),\(r * 0.86) 0 \(share > 0.5 ? 1 : 0) 1 \(end.x),\(end.y) Z"
  let ticks = (0..<12).map { i -> String in
    let t = CGFloat(i) / 12 * 2 * .pi
    let inner = i % 3 == 0 ? r * 0.78 : r * 0.88
    return "M\(cx + cos(t) * inner),\(cy + sin(t) * inner) L\(cx + cos(t) * r),\(cy + sin(t) * r)"
  }.joined(separator: " ")
  return .together([
    .fill(wedge),
    .stroke(circle(cx, cy, r), width: 1.5),
    .stroke(ticks, .quiet, width: 1),
    .stroke("M\(cx),\(cy) L\(cx + cos(a) * r * 0.7),\(cy + sin(a) * r * 0.7)", width: 1.8),
    .fill(circle(cx, cy, 2.6), .ink),
  ])
}

/// A light cone with its apex at (x, y), edges reaching `left` and `right` of x at height `h`.
private func cone(_ x: CGFloat, _ y: CGFloat, _ left: CGFloat, _ right: CGFloat, _ h: CGFloat) -> Mark {
  .together([
    .fill("M\(x - left),\(y - h) L\(x),\(y) L\(x + right),\(y - h) Z"),
    .stroke("M\(x - left),\(y - h) L\(x),\(y) L\(x + right),\(y - h)", width: 1.5),
    .fill(circle(x, y, 2.4), .ink),
  ])
}

/// A cubic Bézier evaluated at `t`.
private func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
  let u = 1 - t
  let a = u * u * u
  let b = 3 * u * u * t
  let c = 3 * u * t * t
  let d = t * t * t
  return pt(a * p0.x + b * p1.x + c * p2.x + d * p3.x, a * p0.y + b * p1.y + c * p2.y + d * p3.y)
}

/// A short arc of radius `r` around (cx, cy) with an arrowhead where it ends.
private func turning(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from a: CGFloat, by sweep: CGFloat) -> Mark {
  let points = (0...12).map { i -> CGPoint in
    let t = a + sweep * CGFloat(i) / 12
    return pt(cx + cos(t) * r, cy + sin(t) * r)
  }
  let end = a + sweep
  let heading = end + (sweep > 0 ? .pi / 2 : -.pi / 2)
  return .stroke(polyline(points) + " " + arrowhead(points.last!, heading, size: 6), width: 1.4)
}

// ─── The event horizon ───────────────────────────────────────────────────────

extension Topic {
  static let horizon = Topic(
    title: "The Event Horizon",
    deck: "A boundary drawn in cause and effect, not in matter.",
    sketch: funnel(),
    aspects: [
      Aspect(
        title: "Light cones tip over",
        teaser: "Why every future points inward.",
        body:
          "Draw every path light can take from an event and you get a cone: the edge of everything that event can ever influence. Far from the hole the cones stand upright. Closer in they lean toward the center. At the horizon the outward edge stands vertical, so light aimed straight out hovers in place. Inside, the whole cone points inward, and the center lies not ahead in space but ahead in time.",
        sketch: Sketch(400, 170, [
          .stroke("M30,150 H382 M30,150 V22", .quiet, width: 1.2),
          .label("r", pt(388, 150), anchor: 0),
          .label("t", pt(30, 12)),
          .stroke("M200,24 V150", width: 1.4, dash: [5, 5]),
          .label("r = rₛ", pt(200, 12)),
          cone(330, 128, 38, 38, 56),
          cone(262, 128, 48, 22, 56),
          cone(200, 128, 62, 0, 56),
          cone(128, 128, 76, -20, 56),
        ])),
      Aspect(
        title: "Three kilometers per Sun",
        teaser: "The Schwarzschild radius, rₛ = 2GM/c².",
        body:
          "The horizon grows in proportion to mass. Pack the Sun inside a radius of three kilometers and it becomes a black hole; the Earth would have to fit within nine millimeters, the size of a marble. Because the radius grows only linearly with mass, the largest black holes are surprisingly tenuous: averaged inside its horizon, one of a hundred million Suns is about as dense as water.",
        sketch: Sketch(400, 170, [
          .stroke(circle(110, 78, 58), .quiet, width: 1.4),
          .fill(circle(110, 78, 2.2), .ink),
          .label("the Earth", pt(110, 154)),
          .stroke("M113,75 L150,40 H176", .faint, width: 1),
          .label("9 mm", pt(180, 40), anchor: 0),
          .stroke(circle(290, 78, 70), .faint, width: 1.4, dash: [4, 5]),
          .fill(circle(290, 78, 4), .ink),
          .label("the Sun", pt(290, 164)),
          .stroke("M294,82 L322,108 H344", .faint, width: 1),
          .label("3 km", pt(348, 108), anchor: 0),
        ])),
      Aspect(
        title: "Nothing happens at the crossing",
        teaser: "Its meaning is global, not local.",
        body:
          "A falling observer carries no instrument that could detect the moment of crossing. Their watch ticks evenly, the local laws of physics are unchanged, and for a large black hole the tides there are gentle. The horizon shows itself only in hindsight, by asking which events could ever send a signal back out.",
        sketch: crossing()),
      Aspect(
        title: "Spin reshapes it",
        teaser: "A smaller horizon, and an ergosphere around it.",
        body:
          "A rotating black hole has a smaller horizon than a still one of the same mass, shrinking toward half the Schwarzschild radius at the greatest possible spin. Around it opens the ergosphere, a flattened region touching the horizon at the poles, where space is dragged around so fast that nothing can stay at rest relative to the distant stars.",
        sketch: Sketch(400, 170, [
          .stroke("M200,8 V168", .faint, width: 1, dash: [3, 5]),
          .stroke(circle(200, 88, 62), .faint, width: 1.2, dash: [4, 5]),
          .label("without spin", pt(128, 22), anchor: 1, .faint),
          .fill(ellipse(200, 88, 84, 44)),
          .stroke(ellipse(200, 88, 84, 44), width: 1.4, dash: [6, 4]),
          .fill(circle(200, 88, 44), .ink),
          .stroke("M182,18 A18,6 0 1 0 218,18" + " " + arrowhead(pt(218, 18), -1.25, size: 6), width: 1.3),
          .label("ergosphere", pt(296, 88), anchor: 0),
        ])),
    ])

  /// Flamm's paraboloid seen from above at an angle, with a ray of light spiralling in.
  private static func funnel() -> Sketch {
    let cx: CGFloat = 300
    let rh: CGFloat = 44
    let rOut: CGFloat = 272
    let tilt: CGFloat = 0.2
    func depth(_ r: CGFloat) -> CGFloat { 66 + 178 * (1 - sqrt(max(0, r - rh) / (rOut - rh))) }
    func at(_ r: CGFloat, _ θ: CGFloat) -> CGPoint { pt(cx + r * cos(θ), depth(r) + tilt * r * sin(θ)) }

    let rings = [272, 214, 164, 124, 94, 72, 56].map { r -> String in ellipse(cx, depth(CGFloat(r)), CGFloat(r), tilt * CGFloat(r)) }
    let radii = stride(from: rOut, through: rh, by: -4).map { $0 }
    let spokes = (0..<16).map { i -> String in
      let θ = CGFloat(i) / 16 * 2 * .pi
      return polyline(radii.map { at($0, θ) })
    }
    let spiral = (0...160).map { i -> CGPoint in
      let s = CGFloat(i) / 160
      let r = rh + (262 - rh) * pow(1 - s, 1.5)
      return at(r, -0.25 + s * 3.6 * .pi)
    }
    let hy = depth(rh)
    return Sketch(600, 300, [
      .stroke(rings.joined(separator: " "), .faint, width: 1),
      .stroke(spokes.joined(separator: " "), .faint, width: 0.8),
      .fill("M\(cx - rh),\(hy) C\(cx - rh + 6),\(hy + 22) \(cx - 30),\(hy + 36) \(cx - 28),300 L\(cx + 28),300 C\(cx + 30),\(hy + 36) \(cx + rh - 6),\(hy + 22) \(cx + rh),\(hy) Z", .ink),
      .fill(ellipse(cx, hy, rh, tilt * rh), .ink),
      .stroke(ellipse(cx, hy, rh + 3, tilt * (rh + 3)), width: 1.6, dash: [5, 4]),
      .together([.fill(circle(spiral[0].x, spiral[0].y, 3.6), .ink), .label("light", pt(spiral[0].x + 10, spiral[0].y - 12), anchor: 0)]),
      .stroke(polyline(spiral), width: 1.8),
      .stroke("M\(cx + rh + 6),\(hy + 4) L\(cx + 96),\(hy + 26) H\(cx + 112)", .quiet, width: 1),
      .label("event horizon", pt(cx + 118, hy + 26), anchor: 0),
    ])
  }

  /// A path falling through the horizon, its watch ticking evenly all the way.
  private static func crossing() -> Sketch {
    let p0 = pt(40, 34)
    let p1 = pt(150, 40)
    let p2 = pt(250, 84)
    let p3 = pt(362, 132)
    let ticks = stride(from: 0.08, through: 0.96, by: 0.08).map { t -> String in
      let a = bezier(p0, p1, p2, p3, CGFloat(t))
      let b = bezier(p0, p1, p2, p3, CGFloat(t) + 0.01)
      let n = atan2(b.y - a.y, b.x - a.x) + .pi / 2
      return "M\(a.x - cos(n) * 6),\(a.y - sin(n) * 6) L\(a.x + cos(n) * 6),\(a.y + sin(n) * 6)"
    }
    return Sketch(400, 170, [
      .fill("M246,10 Q228,85 246,160 L400,160 L400,10 Z"),
      .stroke("M246,10 Q228,85 246,160", width: 1.5, dash: [5, 4]),
      .label("horizon", pt(256, 18), anchor: 0),
      .stroke("M\(p0.x),\(p0.y) C\(p1.x),\(p1.y) \(p2.x),\(p2.y) \(p3.x),\(p3.y)", width: 1.8),
      .stroke(ticks.joined(separator: " "), .quiet, width: 1.2),
      .label("the watch ticks on, evenly", pt(40, 150), anchor: 0),
    ])
  }
}

// ─── Time dilation ───────────────────────────────────────────────────────────

extension Topic {
  static let dilation = Topic(
    title: "Clocks Near the Edge",
    deck: "The closer a clock sits to a black hole, the slower it runs. At the horizon, seen from afar, it stops.",
    sketch: clocks(),
    aspects: [
      Aspect(
        title: "The rate of a clock",
        teaser: "√(1 − rₛ/r), from zero to one.",
        body:
          "The slowing is negligible far away and steepens sharply near the end. Even around the Earth it is measurable: higher in the Earth’s gravity, the clocks on GPS satellites gain about forty-five microseconds a day on clocks at the ground, and the system corrects for it. Near a black hole the same law runs all the way down to zero.",
        sketch: rate()),
      Aspect(
        title: "Frozen at the edge",
        teaser: "What a distant observer sees.",
        body:
          "Watch something fall in from far away and it never seems to arrive. Each signal it sends takes longer to climb out than the last, so it appears to slow, flatten against the horizon and freeze. It fades as it freezes, its light redshifted exponentially fast, and for a stellar black hole it is gone from view within milliseconds.",
        sketch: Sketch(400, 170, [
          .fill("M332,10 V140 H400 V10 Z"),
          .stroke("M332,10 V140", width: 1.5, dash: [5, 4]),
          .label("horizon", pt(340, 152), anchor: 0),
          .together((0..<7).map { k -> Mark in
            let x = 332 - 262 * pow(0.56, CGFloat(k)) - 10
            let ink: Ink = k < 2 ? .ink : k < 4 ? .quiet : .faint
            return .stroke(circle(x, 75, 9), ink, width: 1.5)
          }),
          .stroke("M60,108 H296" + " " + arrowhead(pt(296, 108), 0, size: 6), .quiet, width: 1.1),
          .label("seen from afar: slower, dimmer, redder", pt(60, 132), anchor: 0),
        ])),
      Aspect(
        title: "A brief fall, by your own watch",
        teaser: "Finite time for you, endless for them.",
        body:
          "For the one falling, nothing freezes. Their own watch counts a short, finite time to the horizon and on past it: for a black hole of ten solar masses, the trip from the horizon to the center takes at most a seventh of a millisecond. Every tick of that watch matches a moment on a distant clock, but those moments spread ever further apart, and the crossing itself matches none of them.",
        sketch: watches()),
      Aspect(
        title: "Tides, and why size matters",
        teaser: "2GML/r³: why giants are gentler.",
        body:
          "What harms a falling body is the difference in pull between its head and its feet, which grows as 2GML/r³. At the horizon this goes as 1/M², so the small black holes are the dangerous ones: a stellar-mass hole pulls a person apart long before the horizon, while a supermassive one could be crossed without noticing anything at all.",
        sketch: Sketch(400, 170, [
          .fill("M400,30 A55,55 0 0 0 400,140 Z", .ink),
          .stroke(circle(70, 85, 16), width: 1.5),
          .stroke(ellipse(180, 85, 25, 12), width: 1.5),
          .stroke(ellipse(290, 85, 42, 7), width: 1.5),
          .stroke(
            "M246,85 H226 " + arrowhead(pt(226, 85), .pi, size: 6) + " M334,85 H354 " + arrowhead(pt(354, 85), 0, size: 6),
            .quiet, width: 1.2),
          .label("stretch ∝ M / r³", pt(40, 150), anchor: 0),
        ])),
    ])

  private static func clocks() -> Sketch {
    var wave: [CGPoint] = []
    var phase: CGFloat = 0
    var x: CGFloat = 108
    while x <= 572 {
      let s = (x - 108) / 464
      let λ = 13 + 62 * pow(s, 1.25)
      wave.append(pt(x, 74 - 9 * sin(phase)))
      phase += 2 * .pi * 2 / λ
      x += 2
    }
    let places: [(x: CGFloat, r: String, rate: CGFloat)] = [(150, "1.2 rₛ", 0.41), (262, "2 rₛ", 0.71), (390, "4 rₛ", 0.87), (522, "10 rₛ", 0.95)]
    var marks: [Mark] = [
      .fill("M0,98 A72,72 0 0 1 0,242 Z", .ink),
      .stroke("M0,82 A88,88 0 0 1 0,258", .faint, width: 1, dash: [4, 5]),
    ]
    for p in places {
      marks.append(clock(p.x, 170, 30, p.rate))
      marks.append(.together([
        .label(p.r, pt(p.x, 222), .ink),
        .label("×" + String(format: "%.2f", p.rate), pt(p.x, 242), .faint),
      ]))
    }
    marks.append(.stroke(polyline(wave) + " " + arrowhead(pt(584, 74), 0, size: 7), width: 1.4))
    marks.append(.label("light climbing out is stretched", pt(108, 40), anchor: 0))
    return Sketch(600, 270, marks)
  }

  private static func rate() -> Sketch {
    let box = CGRect(x: 48, y: 22, width: 326, height: 116)
    func px(_ r: CGFloat) -> CGFloat { box.minX + (r - 1) / 7 * box.width }
    func py(_ v: CGFloat) -> CGFloat { box.maxY - v * box.height }
    let curve = stride(from: 1.0, through: 8.0, by: 0.02).map { r -> CGPoint in
      pt(px(CGFloat(r)), py(sqrt(1 - 1 / CGFloat(r))))
    }
    return Sketch(400, 170, [
      .stroke("M\(box.minX),\(box.minY - 8) V\(box.maxY) H\(box.maxX + 8)", .quiet, width: 1.2),
      .stroke("M\(box.minX),\(py(1)) H\(box.maxX)", .faint, width: 1, dash: [4, 5]),
      .label("1", pt(box.minX - 10, py(1)), anchor: 1),
      .label("0", pt(box.minX - 10, box.maxY), anchor: 1),
      .stroke(polyline(curve), width: 1.9),
      .label("√(1 − rₛ/r)", pt(px(3.6), py(0.62)), anchor: 0, .ink),
      .label("rₛ", pt(px(1), box.maxY + 16)),
      .label("r", pt(box.maxX + 12, box.maxY), anchor: 0),
      .label("clock rate", pt(box.minX + 8, box.minY - 4), anchor: 0),
    ])
  }

  private static func watches() -> Sketch {
    let top = (0...10).map { 40 + CGFloat($0) * 26 }
    let bottom = (0...10).map { 40 + 18 * (pow(1.38, CGFloat($0)) - 1) }
    let links = zip(top, bottom).map { "M\($0),62 L\(min($1, 420)),\($1 > 420 ? 62 + (128 - 62) * (420 - $0) / ($1 - $0) : 128)" }
    return Sketch(400, 170, [
      .stroke("M40,56 H300", width: 1.5),
      .stroke(top.map { "M\($0),50 V62" }.joined(separator: " "), width: 1.3),
      .stroke("M294,44 L306,56 M306,44 L294,56", width: 1.6),
      .label("your watch", pt(40, 34), anchor: 0),
      .label("crossing", pt(300, 30), .ink),
      .stroke(links.joined(separator: " "), .faint, width: 0.9),
      .stroke("M40,134 H380 " + arrowhead(pt(388, 134), 0, size: 6), .quiet, width: 1.3),
      .stroke(bottom.filter { $0 < 380 }.map { "M\($0),128 V140" }.joined(separator: " "), .quiet, width: 1.2),
      .label("distant clocks", pt(40, 156), anchor: 0),
      .label("∞", pt(394, 134), anchor: 0, .ink),
    ])
  }
}

// ─── The Kerr black hole ─────────────────────────────────────────────────────

extension Topic {
  static let kerr = Topic(
    title: "The Kerr Black Hole",
    deck: "Real black holes spin, and a spinning one drags space around with it.",
    sketch: kerrSketch(),
    aspects: [
      Aspect(
        title: "Three numbers, no hair",
        teaser: "Mass, spin and charge. Nothing else.",
        body:
          "However complicated the star that collapsed, the black hole that settles is described by exactly three numbers: its mass, its angular momentum and its electric charge. Every other detail — shape, makeup, magnetic fields — is radiated away or swallowed. Real black holes carry almost no charge, so in practice two numbers are enough.",
        sketch: dials()),
      Aspect(
        title: "A horizon that shrinks",
        teaser: "From 2GM/c² down to GM/c².",
        body:
          "Spin pulls the horizon in. A still black hole’s horizon lies at 2GM/c²; as the spin rises toward its maximum, the horizon contracts until, in the extremal limit, it reaches GM/c², half the size. Any more spin would leave no horizon at all, which is thought to be impossible.",
        sketch: Sketch(400, 170, [
          .stroke(circle(200, 85, 74), .quiet, width: 1.4, dash: [5, 5]),
          .label("2GM/c²", pt(284, 30), anchor: 0),
          .together([0.25, 0.75, 1.25, 1.75].map { a -> Mark in
            let θ = CGFloat(a) * .pi
            let from = pt(200 + cos(θ) * 68, 85 + sin(θ) * 68)
            let to = pt(200 + cos(θ) * 44, 85 + sin(θ) * 44)
            return .stroke("M\(from.x),\(from.y) L\(to.x),\(to.y) " + arrowhead(to, θ + .pi, size: 6), .quiet, width: 1.2)
          }),
          .fill(circle(200, 85, 37)),
          .stroke(circle(200, 85, 37), width: 1.8),
          .label("GM/c²", pt(200, 85), .ink),
          .label("as spin approaches its limit", pt(200, 166)),
        ])),
      Aspect(
        title: "The ergosphere",
        teaser: "Where nothing can stand still.",
        body:
          "Between the horizon and a flattened surface around it lies the ergosphere. There, frame dragging is so strong that no rocket, however powerful, can hold a position fixed relative to the distant stars: everything must turn with the hole. Unlike the horizon, the ergosphere can still be left again.",
        sketch: Sketch(400, 170, [
          .fill(circle(200, 85, 78)),
          .stroke(circle(200, 85, 78), width: 1.4, dash: [6, 4]),
          .fill(circle(200, 85, 38), .ink),
          .together((0..<6).map { i -> Mark in
            let a = CGFloat(i) / 6 * 2 * .pi
            return .together([
              .fill(circle(200 + cos(a) * 58, 85 + sin(a) * 58, 3), .ink),
              turning(200, 85, 58, from: a + 0.12, by: 0.5),
            ])
          }),
          .label("everything here turns", pt(296, 150), anchor: 0),
          .label("with the hole", pt(296, 166), anchor: 0),
        ])),
      Aspect(
        title: "Mining the spin",
        teaser: "Penrose’s way to extract energy.",
        body:
          "In 1969 Roger Penrose showed that the ergosphere holds energy that can be taken out. A particle that splits in two there can send one half onto an orbit of negative energy, as measured from afar, which falls into the hole; the other half escapes with more energy than the whole had. The hole pays by spinning down. Magnetic versions of the same idea are thought to power some of the most energetic jets in the universe.",
        sketch: Sketch(400, 170, [
          .fill("M400,-25 A110,110 0 0 0 400,195 Z"),
          .stroke("M400,-25 A110,110 0 0 0 400,195", width: 1.4, dash: [6, 4]),
          .fill("M400,40 A45,45 0 0 0 400,130 Z", .ink),
          .label("ergosphere", pt(300, 160), .quiet),
          .stroke("M30,28 C120,24 240,40 312,72", width: 1.7),
          .label("E", pt(90, 16), .ink),
          .fill(circle(312, 72, 3.4), .ink),
          .stroke("M312,72 C330,82 344,88 358,94", .quiet, width: 1.5, dash: [3, 4]),
          .label("−ε", pt(340, 112), .ink),
          .stroke("M312,72 C250,100 150,128 48,140 " + arrowhead(pt(48, 140), .pi - 0.12, size: 7), width: 1.7),
          .label("E + ε", pt(60, 120), anchor: 0, .ink),
        ])),
    ])

  private static func kerrSketch() -> Sketch {
    let cx: CGFloat = 300
    let cy: CGFloat = 150
    return Sketch(600, 300, [
      .stroke("M\(cx),10 V290", .faint, width: 1, dash: [3, 5]),
      .stroke("M50,\(cy) A250,40 0 0 1 550,\(cy)", .faint, width: 1.1),
      .stroke("M120,\(cy) A180,29 0 0 1 480,\(cy)", .quiet, width: 1.2),
      .fill(ellipse(cx, cy, 122, 66)),
      .stroke(ellipse(cx, cy, 122, 66), width: 1.5, dash: [6, 4]),
      .fill(circle(cx, cy, 66), .ink),
      .stroke("M550,\(cy) A250,40 0 0 1 50,\(cy)", .faint, width: 1.1),
      .stroke("M480,\(cy) A180,29 0 0 1 120,\(cy)", .quiet, width: 1.2),
      .together([
        .stroke(arrowhead(pt(cx + 4, cy + 40), 0, size: 8), .faint, width: 1.3),
        .stroke(arrowhead(pt(cx + 4, cy + 29), 0, size: 8), .quiet, width: 1.4),
      ]),
      .stroke("M\(cx - 20),26 A20,6 0 1 0 \(cx + 20),26 " + arrowhead(pt(cx + 20, 26), -1.3, size: 6), width: 1.4),
      .label("spin", pt(cx + 30, 26), anchor: 0),
      .stroke("M\(cx + 104),\(cy - 40) L\(cx + 136),\(cy - 74) H\(cx + 152)", .quiet, width: 1),
      .label("ergosphere", pt(cx + 158, cy - 74), anchor: 0),
      .stroke("M\(cx - 50),\(cy - 44) L\(cx - 118),\(cy - 92) H\(cx - 134)", .quiet, width: 1),
      .label("horizon", pt(cx - 140, cy - 92), anchor: 1),
      .label("frame dragging", pt(cx + 200, cy + 62)),
    ])
  }

  private static func dials() -> Sketch {
    let dials: [(x: CGFloat, name: String, at: CGFloat)] = [(78, "mass  M", 0.62), (200, "spin  J", 0.84), (322, "charge  Q", 0.03)]
    return Sketch(400, 170, dials.map { d -> Mark in
      let cy: CGFloat = 104
      let r: CGFloat = 50
      let ticks = (0...8).map { i -> String in
        let a = CGFloat.pi + CGFloat(i) / 8 * .pi
        let inner = i % 4 == 0 ? r - 10 : r - 6
        return "M\(d.x + cos(a) * inner),\(cy + sin(a) * inner) L\(d.x + cos(a) * r),\(cy + sin(a) * r)"
      }.joined(separator: " ")
      let a = CGFloat.pi + d.at * .pi
      return .together([
        .fill("M\(d.x - r),\(cy) A\(r),\(r) 0 0 1 \(d.x + r),\(cy) Z"),
        .stroke("M\(d.x - r),\(cy) A\(r),\(r) 0 0 1 \(d.x + r),\(cy)", width: 1.5),
        .stroke(ticks, .quiet, width: 1),
        .stroke("M\(d.x),\(cy) L\(d.x + cos(a) * (r - 14)),\(cy + sin(a) * (r - 14))", width: 1.9),
        .fill(circle(d.x, cy, 3), .ink),
        .label(d.name, pt(d.x, cy + 26), .ink),
      ])
    })
  }
}
