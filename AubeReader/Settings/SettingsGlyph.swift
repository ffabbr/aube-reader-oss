import UIKit

/// The settings' glyphs, drawn rather than taken from SF Symbols: one canvas,
/// one round stroke, so a column of them reads as a set. Template images, so a
/// row inks them.
enum SettingsGlyph {
  case model, luna, fast, gesture, key, version, check, access, usage, chatGPT, offline, account, signOut

  static let side: CGFloat = 30
  private static var cache: [SettingsGlyph: UIImage] = [:]

  var image: UIImage {
    if let cached = Self.cache[self] { return cached }
    let drawn = UIGraphicsImageRenderer(size: CGSize(width: Self.side, height: Self.side)).image { _ in
      UIColor.black.setStroke()
      UIColor.black.setFill()
      let (strokes, fills) = paths()
      for p in fills { p.fill() }
      for p in strokes {
        p.lineWidth = 1.9
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
      }
    }.withRenderingMode(.alwaysTemplate)
    Self.cache[self] = drawn
    return drawn
  }

  private func line(_ points: [(CGFloat, CGFloat)], closed: Bool = false) -> UIBezierPath {
    let p = UIBezierPath()
    for (i, (x, y)) in points.enumerated() {
      if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    if closed { p.close() }
    return p
  }

  private func paths() -> ([UIBezierPath], [UIBezierPath]) {
    switch self {
    case .access:
      // A four-pointed spark.
      return ([line([(15, 3.5), (17.6, 12.4), (26.5, 15), (17.6, 17.6), (15, 26.5), (12.4, 17.6), (3.5, 15), (12.4, 12.4)], closed: true)], [])
    case .usage:
      // A gauge, its needle past the middle.
      let dial = UIBezierPath(arcCenter: CGPoint(x: 15, y: 19), radius: 10.5, startAngle: .pi, endAngle: 0, clockwise: true)
      let hub = UIBezierPath(ovalIn: CGRect(x: 13, y: 17, width: 4, height: 4))
      return ([dial, line([(15, 19), (20.5, 12)])], [hub])
    case .chatGPT:
      // The ChatGPT logo itself, inset to sit with the strokes around it.
      let mark = ChatGPTMark.path(side: 26)
      mark.apply(CGAffineTransform(translationX: 2, y: 2))
      return ([], [mark])
    case .offline:
      // An open book.
      let left = UIBezierPath()
      left.move(to: CGPoint(x: 15, y: 9))
      left.addCurve(to: CGPoint(x: 4, y: 7.5), controlPoint1: CGPoint(x: 12, y: 6.5), controlPoint2: CGPoint(x: 7.5, y: 6.5))
      left.addLine(to: CGPoint(x: 4, y: 23.5))
      left.addCurve(to: CGPoint(x: 15, y: 25), controlPoint1: CGPoint(x: 7.5, y: 22.5), controlPoint2: CGPoint(x: 12, y: 22.5))
      let right = left.copy() as! UIBezierPath
      right.apply(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 30, ty: 0))
      return ([left, right, line([(15, 9), (15, 25)])], [])
    case .account:
      // A head and shoulders.
      let head = UIBezierPath(ovalIn: CGRect(x: 10.5, y: 5, width: 9, height: 9))
      let shoulders = UIBezierPath()
      shoulders.move(to: CGPoint(x: 6, y: 25))
      shoulders.addCurve(to: CGPoint(x: 15, y: 17), controlPoint1: CGPoint(x: 6, y: 20), controlPoint2: CGPoint(x: 10, y: 17))
      shoulders.addCurve(to: CGPoint(x: 24, y: 25), controlPoint1: CGPoint(x: 20, y: 17), controlPoint2: CGPoint(x: 24, y: 20))
      return ([head, shoulders], [])
    case .signOut:
      // An arrow leaving an open box.
      return ([line([(17, 6), (6, 6), (6, 24), (17, 24)]), line([(12, 15), (26, 15)]), line([(22, 11), (26, 15), (22, 19)])], [])
    case .model:
      // A speech bubble with a spark in it.
      let bubble = UIBezierPath(roundedRect: CGRect(x: 4, y: 5, width: 22, height: 15.5), cornerRadius: 6)
      let tail = line([(9.5, 20.5), (8, 25.5), (14, 20.5)])
      let spark = line([(15, 8.5), (15, 17)])
      spark.append(line([(10.75, 12.75), (19.25, 12.75)]))
      return ([bubble, tail, spark], [])
    case .luna:
      // A crescent moon.
      let moon = UIBezierPath()
      moon.move(to: CGPoint(x: 20, y: 5))
      moon.addArc(withCenter: CGPoint(x: 14.5, y: 15), radius: 11.4, startAngle: -1.067, endAngle: 1.067, clockwise: false)
      moon.addArc(withCenter: CGPoint(x: 20, y: 15), radius: 10, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
      return ([moon], [])
    case .fast:
      // A bolt.
      return ([line([(17, 4.5), (8, 16.5), (14.5, 16.5), (13, 25.5), (22, 13.5), (15.5, 13.5)], closed: true)], [])
    case .gesture:
      // A fingertip's touch, and the ring it leaves.
      let tip = UIBezierPath(ovalIn: CGRect(x: 11, y: 11, width: 8, height: 8))
      let ring = UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 20, height: 20))
      return ([ring], [tip])
    case .key:
      let bow = UIBezierPath(ovalIn: CGRect(x: 4, y: 9, width: 11, height: 11))
      return ([bow, line([(15, 14.5), (26, 14.5)]), line([(22, 14.5), (22, 18.5)]), line([(25.5, 14.5), (25.5, 17.5)])], [])
    case .check:
      // A page with a tick across it.
      let page = line([(7, 4.5), (23, 4.5), (23, 25.5), (7, 25.5)], closed: true)
      return ([page, line([(11, 15.5), (14, 19), (19.5, 11)])], [])
    case .version:
      // A page with its corner turned.
      let page = line([(8, 4.5), (18, 4.5), (23, 9.5), (23, 25.5), (8, 25.5)], closed: true)
      let fold = line([(18, 4.5), (18, 9.5), (23, 9.5)])
      return ([page, fold, line([(11.5, 15), (19.5, 15)]), line([(11.5, 19.5), (17, 19.5)])], [])
    }
  }
}
