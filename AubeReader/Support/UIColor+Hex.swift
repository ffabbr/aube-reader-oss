import UIKit

extension UIColor {
  convenience init(hex v: UInt32, alpha: CGFloat = 1) {
    self.init(red: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: alpha)
  }
}
