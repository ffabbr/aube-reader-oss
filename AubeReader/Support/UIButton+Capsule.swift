import UIKit

extension UIButton.Configuration {
  /// A filled capsule in `fill`, its title in `ink` in the library's rounded
  /// lettering at `size` points.
  static func capsule(_ title: String, fill: UIColor, ink: UIColor, size: CGFloat) -> UIButton.Configuration {
    var config = UIButton.Configuration.filled()
    config.title = title
    config.baseBackgroundColor = fill
    config.baseForegroundColor = ink
    config.cornerStyle = .capsule
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = LibraryFace.rounded(size, .semibold)
      return attributes
    }
    return config
  }
}
