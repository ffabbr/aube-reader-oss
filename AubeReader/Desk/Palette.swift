import UIKit

/// Every color the reader uses, each with its light and dark value, so the app
/// follows the system appearance. Greys leaning ever so slightly warm, toward
/// the library's paper: red a hair above green and blue a hair below, too
/// little to read as a color, so nothing leans blue.
enum Palette {
  static let page = gray(0xff, 0x16)
  static let ink = gray(0x11, 0xe5)
  static let quiet = gray(0x55, 0xa3)
  static let muted = gray(0x90, 0x73)
  static let faint = gray(0xb8, 0x52)
  static let line = gray(0xd0, 0x4d)
  static let fill = gray(0xf5, 0x23)
  /// The deepest shadow; lighter ones are shares of it.
  static let shadow = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.65) : UIColor(white: 0, alpha: 0.16) }

  private static func gray(_ light: Int, _ dark: Int) -> UIColor {
    UIColor { traits in
      let night = traits.userInterfaceStyle == .dark
      let v = CGFloat(night ? dark : light) / 255
      // By day the warmth comes out of blue; by night it goes into red.
      let (r, g, b): (CGFloat, CGFloat, CGFloat) = night ? (2, 1, -1.5) : (0, -1.5, -4.5)
      return UIColor(red: min(1, v + r / 255), green: v + g / 255, blue: max(0, v + b / 255), alpha: 1)
    }
  }

  /// `share` of `top` over `bottom`, resolved for `traits`.
  static func mix(_ top: UIColor, _ share: CGFloat, over bottom: UIColor, _ traits: UITraitCollection) -> UIColor {
    var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    var b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    top.resolvedColor(with: traits).getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
    bottom.resolvedColor(with: traits).getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
    let s = max(0, min(1, share))
    return UIColor(red: b.0 + (a.0 - b.0) * s, green: b.1 + (a.1 - b.1) * s, blue: b.2 + (a.2 - b.2) * s, alpha: b.3 + (a.3 - b.3) * s)
  }
}

/// A layer that never animates on its own: the frame loop moves it.
class StillLayer: CALayer {
  override func action(forKey event: String) -> CAAction? { NSNull() }
}
