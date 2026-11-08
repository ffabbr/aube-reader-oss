import UIKit

// ─── Fonts ───────────────────────────────────────────────────────────────────

/// Finds the closest font the device has to one a document names. Documents
/// embed their fonts, but only the letters they use, so a rewritten paragraph
/// can't be set in them. It's set in a stand-in: the same font if the device has
/// it, otherwise a relative, otherwise whichever of its class runs about as wide,
/// so lines break much where they did.
enum FontMatch {
  /// Names a document might use, and the family on the device that's nearest.
  private static let relatives: [(String, String)] = [
    ("timesnewroman", "Times New Roman"), ("times", "Times New Roman"), ("nimbusrom", "Times New Roman"), ("tex gyre termes", "Times New Roman"), ("stix", "Times New Roman"),
    ("cmr", "Times New Roman"), ("lmroman", "Times New Roman"), ("sfrm", "Times New Roman"), ("cmti", "Times New Roman"), ("cmbx", "Times New Roman"), ("libertine", "Palatino"),
    ("georgia", "Georgia"), ("palatino", "Palatino"), ("pagella", "Palatino"), ("book antiqua", "Palatino"), ("charter", "Charter"), ("baskerville", "Baskerville"),
    ("didot", "Didot"), ("bodoni", "Bodoni 72"), ("hoefler", "Hoefler Text"), ("cochin", "Cochin"), ("iowan", "Iowan Old Style"), ("garamond", "Baskerville"), ("minion", "Hoefler Text"),
    ("caslon", "Baskerville"), ("cambria", "Georgia"), ("sabon", "Baskerville"), ("kepler", "Hoefler Text"),
    ("helveticaneue", "Helvetica Neue"), ("helvetica", "Helvetica"), ("arial", "Arial"), ("liberationsans", "Arial"), ("nimbussan", "Helvetica"), ("avenirnext", "Avenir Next"), ("avenir", "Avenir"),
    ("gillsans", "Gill Sans"), ("gill", "Gill Sans"), ("futura", "Futura"), ("optima", "Optima"), ("verdana", "Verdana"), ("dejavusans", "Verdana"), ("tahoma", "Verdana"), ("trebuchet", "Trebuchet MS"),
    ("calibri", "Avenir Next"), ("carlito", "Avenir Next"), ("segoe", "Avenir Next"), ("myriad", "Avenir Next"), ("frutiger", "Avenir Next"), ("univers", "Helvetica Neue"), ("roboto", "Helvetica Neue"), ("ubuntu", "Avenir Next"), ("inter", "Helvetica Neue"), ("lato", "Avenir Next"),
    ("courier", "Courier New"), ("menlo", "Menlo"), ("consol", "Menlo"), ("monaco", "Menlo"), ("cmtt", "Courier New"), ("sftt", "Courier New"), ("nimbusmon", "Courier New"), ("dejavusansmono", "Menlo"), ("liberationmono", "Menlo"),
  ]

  private static let serifs = ["Times New Roman", "Georgia", "Palatino", "Charter", "Baskerville", "Hoefler Text", "Iowan Old Style"]
  private static let sanses = ["Helvetica Neue", "Avenir Next", "Arial", "Gill Sans", "Optima", "Verdana"]

  private static var widths: [String: CGFloat] = [:]
  private static let lock = NSLock()

  /// How wide a character of `family` runs, as a share of the size.
  private static func advance(_ family: String) -> CGFloat {
    lock.lock()
    defer { lock.unlock() }
    if let w = widths[family] { return w }
    let sample = "the quality of a printed line depends on how evenly its letters and words are spaced across it"
    let font = UIFont(name: family, size: 100) ?? UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: family]), size: 100)
    let w = (sample as NSString).size(withAttributes: [.font: font]).width / (CGFloat(sample.count) * 100)
    widths[family] = w
    return w
  }

  /// The family nearest `record`, among those the device has.
  static func family(_ record: FontRecord?, advance measured: CGFloat) -> String {
    let low = (record?.name ?? "").lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    if !low.isEmpty {
      let sorted = relatives.sorted { $0.0.count > $1.0.count }
      for (name, family) in sorted where low.contains(name.replacingOccurrences(of: " ", with: "")) {
        return family
      }
    }
    if record?.mono == true { return "Menlo" }
    let class_ = record?.serif == true ? serifs : sanses
    guard measured > 0 else { return class_[0] }
    return class_.min { abs(advance($0) - measured) < abs(advance($1) - measured) } ?? class_[0]
  }

  /// `family`, at `size`, as bold and italic as `record` is.
  static func face(_ record: FontRecord?, size: CGFloat, advance: CGFloat) -> UIFont {
    // The very font, if the device has it.
    if record?.standIn == nil, let name = record?.name, let exact = UIFont(name: name, size: size) { return exact }
    let family = record?.standIn ?? Self.family(record, advance: advance)
    var d = UIFontDescriptor(fontAttributes: [.family: family])
    var traits: UIFontDescriptor.SymbolicTraits = []
    if record?.bold == true { traits.insert(.traitBold) }
    if record?.italic == true && record?.math != true { traits.insert(.traitItalic) }
    if !traits.isEmpty, let styled = d.withSymbolicTraits(traits) { d = styled }
    return UIFont(descriptor: d, size: size)
  }
}
