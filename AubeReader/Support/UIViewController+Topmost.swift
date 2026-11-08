import UIKit

extension UIViewController {
  /// Whatever is presented over this, and over that, to the top: where
  /// something new has to be presented to be seen.
  var topmost: UIViewController {
    var top = self
    while let next = top.presentedViewController { top = next }
    return top
  }
}
