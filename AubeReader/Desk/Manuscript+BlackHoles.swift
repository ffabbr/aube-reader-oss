import Foundation

extension Manuscript {
  /// “Black Holes: Collapse, Horizons, and the Observational Record”: a review
  /// made up for the app, its authors, journal and institutions invented.
  /// Everything around its paragraphs, which are in `Resources/black-holes.json`.
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
      Section(title: "Observational evidence", paragraphs: [4], after: [.table(0), .figure(.evidence)], more: [12]),
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
    tables: [
      Table(
        caption: "Representative black holes, their masses, and the Schwarzschild radii those masses imply.",
        header: ["Object", "*M* / *M*_{⊙}", "*r*_{s}", "Method"],
        rows: [
          ["Cygnus X-1", "21.2", "63 km", "X-ray binary"],
          ["V404 Cygni", "9", "27 km", "X-ray binary"],
          ["GW150914 remnant", "62", "180 km", "GW signal"],
          ["Sgr A\\*", "4.3 × 10^{6}", "0.085 au", "Stellar orbits"],
          ["M87\\*", "6.5 × 10^{9}", "130 au", "EHT imaging"],
        ])
    ],
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
}
