import Foundation

extension Manuscript {
  /// “How a Swarm Chooses a Home”: a review made up for the app, its authors,
  /// journal and institutions invented. Everything around its paragraphs,
  /// which are in `Resources/swarm.json`.
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
      Section(title: "Scouting for cavities", paragraphs: [1], after: [.table(0)]),
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
    tables: [
      Table(
        caption: "What scouts measure in a cavity, and the values swarms choose and avoid.",
        header: ["Property", "Chosen", "Avoided"],
        rows: [
          ["Cavity volume", "≈ 40 L", "< 10 L or > 100 L"],
          ["Entrance area", "≈ 15 cm^{2}", "> 75 cm^{2}"],
          ["Entrance height", "> 3 m", "near the ground"],
          ["Entrance faces", "the sun", "away from it"],
        ])
    ],
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
