import UIKit

/// The library's lettering: SF Rounded for the app's own words, around the
/// books, in the welcome and in Settings; New York for a paper's own title.
enum LibraryFace {
  static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
    let d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    return UIFont(descriptor: d.withDesign(.rounded) ?? d, size: size)
  }

  static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
    let d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    return UIFont(descriptor: d.withDesign(.serif) ?? d, size: size)
  }

  static func authors(_ names: [String]) -> String {
    names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
  }
}
