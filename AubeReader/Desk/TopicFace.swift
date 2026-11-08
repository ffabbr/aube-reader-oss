import UIKit

/// The type of the topic pages: New York for titles, SF for the rest.
enum TopicFace {
  static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
    var d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    d = d.withDesign(.serif) ?? d
    if italic { d = d.withSymbolicTraits(d.symbolicTraits.union(.traitItalic)) ?? d }
    return UIFont(descriptor: d, size: size)
  }

  static func sans(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont { .systemFont(ofSize: size, weight: weight) }

  static func text(
    _ s: String, _ font: UIFont, _ color: UIColor, leading: CGFloat = 1.25, tracking: CGFloat = 0,
    align: NSTextAlignment = .natural
  ) -> NSAttributedString {
    let ps = NSMutableParagraphStyle()
    ps.lineHeightMultiple = leading
    ps.alignment = align
    ps.hyphenationFactor = 0.3
    ps.paragraphSpacing = font.pointSize * 0.7
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps, .kern: tracking])
  }
}
