import UIKit

/// The fonts a document uses, each kept once.
final class FontCatalog {
  private(set) var fonts: [FontRecord] = []
  private var seen: [FontRecord: Int] = [:]

  func index(of dict: CGPDFDictionaryRef) -> Int { stand(Self.read(dict)) }

  /// A font's place in the catalog, added if it's new.
  func stand(_ record: FontRecord) -> Int {
    if let i = seen[record] { return i }
    fonts.append(record)
    seen[record] = fonts.count - 1
    return fonts.count - 1
  }

  private static func read(_ dict: CGPDFDictionaryRef) -> FontRecord {
    var name = ""
    var c: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(dict, "BaseFont", &c), let c { name = String(cString: c) }
    if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
      name = String(name[name.index(after: plus)...])
    }
    var descriptor: CGPDFDictionaryRef?
    if !CGPDFDictionaryGetDictionary(dict, "FontDescriptor", &descriptor) {
      var kids: CGPDFArrayRef?
      var kid: CGPDFDictionaryRef?
      if CGPDFDictionaryGetArray(dict, "DescendantFonts", &kids), let kids, CGPDFArrayGetDictionary(kids, 0, &kid), let kid {
        _ = CGPDFDictionaryGetDictionary(kid, "FontDescriptor", &descriptor)
      }
    }
    var flags: CGPDFInteger = 0
    var weight: CGPDFReal = 0
    var angle: CGPDFReal = 0
    if let descriptor {
      _ = CGPDFDictionaryGetInteger(descriptor, "Flags", &flags)
      _ = CGPDFDictionaryGetNumber(descriptor, "FontWeight", &weight)
      _ = CGPDFDictionaryGetNumber(descriptor, "ItalicAngle", &angle)
    }
    // A descriptor can claim a fixed pitch its widths give the lie to.
    var widths: CGPDFArrayRef?
    if flags & 1 != 0, CGPDFDictionaryGetArray(dict, "Widths", &widths), let widths {
      var distinct = Set<Int>()
      for i in 0..<CGPDFArrayGetCount(widths) {
        var w: CGPDFReal = 0
        if CGPDFArrayGetNumber(widths, i, &w), w > 0 { distinct.insert(Int(w)) }
      }
      if distinct.count > 2 { flags &= ~1 }
    }
    return FontNames.record(name, flags: flags, weight: weight, angle: angle)
  }
}

/// What a font's name gives away, on top of what its descriptor says.
enum FontNames {
  static func record(_ name: String, flags: Int, weight: CGFloat, angle: CGFloat) -> FontRecord {
    let low = name.lowercased()
    func has(_ words: [String]) -> Bool { words.contains { low.contains($0) } }
    let bold =
      has(["bold", "black", "heavy", "demi", "cmbx", "cmb10", "sfbx", "nimbusromno9l-medi", "-medi", "-semibold", "extrabold"]) || weight >= 600 || flags & (1 << 18) != 0
    let italic = has(["italic", "oblique", "cmti", "cmmi", "sfti", "sfsl", "cmsl", "-regu-ital", "-medi-ital", "-ital"]) || abs(angle) > 1 || flags & 64 != 0
    let mono = has(["mono", "courier", "consol", "menlo", "typewriter", "cmtt", "sftt", "lmtt", "inconsolata", "andale", "lucidacons", "fixed"]) || flags & 1 != 0
    let math = has(["cmmi", "cmsy", "cmex", "msam", "msbm", "cmr5", "cmr6", "cmr7", "stmary", "math", "symbol", "wasy", "dingbat", "esint", "rsfs", "eufm", "mtsy", "mtmi", "euclid", "txsy", "pxsy"])
    let sansName = has(["helvet", "arial", "sans", "gothic", "verdana", "tahoma", "calibri", "segoe", "avenir", "futura", "gill", "univers", "frutiger", "myriad", "roboto", "lato", "opensans", "inter", "cmss", "lmss", "sfss", "nimbussan", "source sans", "dejavusans", "ubuntu", "noto sans", "notosans", "franklin", "trebuchet", "optima", "din", "aptos"])
    let serifName = has(["times", "roman", "serif", "georgia", "garamond", "palatino", "minion", "cambria", "baskerville", "caslon", "bookman", "charter", "cmr", "lmr", "sfrm", "nimbusrom", "utopia", "didot", "bodoni", "century", "book", "libertine", "kepler", "tiempos", "lora", "merriweather", "crimson", "droid serif", "pt serif", "sabon", "stix", "tex gyre termes", "newsreader"])
    let serif = sansName ? false : (serifName || flags & 2 != 0)
    return FontRecord(name: name, bold: bold, italic: italic, serif: serif, mono: mono, math: math)
  }
}
