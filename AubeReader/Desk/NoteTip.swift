import UIKit

/// A footnote opened where it's marked. There's one shape of Liquid Glass, and it
/// starts out as the mark: the same circle, in the same place, with the same
/// number in it. It then stretches out from there into the note, the number
/// staying put at its corner and the words beside it standing still as the glass
/// reaches them, so that it reads as the mark itself opening up. As the topic card
/// does, it unfolds across and then pours down a beat later, stepped here frame by
/// frame (see `Ease`), so that it can turn back from anywhere. Closing runs the same way back.
///
/// It grows onward from the mark, right and down, over what's still to be read and
/// not what led to it. Where there's no room that way it goes the other.
///
/// Only the note's words take touches, so they can be selected, scrolled and followed
/// if they're a link. Everything else reaches the page, which puts the note away,
/// the mark included (see `DeskViewController`).
final class NoteTip: GlassTip, UITextViewDelegate {
  static let textSize: CGFloat = 15
  static let leading: CGFloat = 1.4
  private static let margin: CGFloat = 16
  private static let widest: CGFloat = 400
  /// From the mark to the near edges of the glass, from the mark to the words, and from the words to the far edge.
  private static let edge: CGFloat = 9
  private static let beside: CGFloat = 9
  private static let far: CGFloat = 16
  /// Down a beat after it reaches across, running a hair past.
  private static let timing = Timing(
    across: 0.5, reach: 0.52, lag: 0.07, reachEase: Ease(0.36, 0, 0.16, 1.035),
    back: 0.34, inward: 0.38, closeLag: 0.05, fadeAt: 0.3)

  let note: Int

  private let number = UILabel()
  private let words = UITextView()
  /// Under a tip too tall to show whole, its words fade out at the edges they run past.
  private let edges = CAGradientLayer()
  private let mark: CGRect
  private let wordsAt: CGRect
  private let scrolls: Bool

  /// A tip for note `note`, marked `label`, saying `text`, for the mark at `mark` in `host`.
  init(note: Int, label: String, text: NSAttributedString, mark: CGRect, host: UIView) {
    self.note = note
    self.mark = mark
    let shape = Self.lay(text, mark: mark, in: host.bounds, safe: host.safeAreaInsets)
    wordsAt = shape.words
    scrolls = shape.scrolls
    // Pale words on the dark are more easily lost in those behind them, so more of the page lies under them.
    super.init(
      start: mark, rest: shape.rest, keepOut: mark.insetBy(dx: -8, dy: -8), host: host, timing: Self.timing,
      shadowRadius: 22, shadowOpacity: (light: 0.15, dark: 0.45), backing: (light: 0.12, dark: 0.32))

    words.attributedText = text
    words.backgroundColor = .clear
    words.isEditable = false
    words.isSelectable = true
    words.dataDetectorTypes = [.link]
    words.delegate = self
    words.tintColor = Palette.ink
    words.linkTextAttributes = [.foregroundColor: Palette.ink, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Palette.muted]
    words.textContainer.lineFragmentPadding = 0
    words.textContainerInset = .zero
    words.isScrollEnabled = scrolls
    words.showsVerticalScrollIndicator = false
    words.alwaysBounceVertical = scrolls
    words.alpha = 0
    words.accessibilityLabel = "Footnote"
    words.frame = wordsAt.offsetBy(dx: -mark.minX, dy: -mark.minY)
    body.contentView.addSubview(words)

    // The mark itself, drawn over itself, so that nothing changes as the glass takes over.
    number.text = label
    number.textAlignment = .center
    number.font = Halo.font(mark.height)
    number.textColor = Palette.ink
    number.isUserInteractionEnabled = false
    number.frame = CGRect(origin: .zero, size: mark.size)
    body.contentView.addSubview(number)

    if scrolls {
      // The words fade toward the foot, where they go on.
      edges.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
      edges.locations = [0, 0.86, 1]
      edges.frame = CGRect(origin: .zero, size: wordsAt.size)
      words.layer.mask = edges
    }
  }

  // ─── Shape ───────────────────────────────────────────────────────────────

  /// Where the glass comes to rest around the mark, and where the words lie in it:
  /// as narrow as they can be without taking another line, so that a note's last line
  /// isn't left with a word on it, and no taller than fits. The first line is level with
  /// the mark, or if the note has to grow upward, the last.
  private static func lay(_ text: NSAttributedString, mark: CGRect, in screen: CGRect, safe: UIEdgeInsets) -> (rest: CGRect, words: CGRect, scrolls: Bool) {
    let line = textSize * leading
    let gutter = edge + mark.width + beside
    // Onward if there's reasonable room, otherwise whichever way has more.
    let rightward = screen.maxX - margin - (mark.minX - edge)
    let leftward = (mark.maxX + edge) - (screen.minX + margin)
    let onward = rightward >= min(widest, 300) || rightward >= leftward
    let wide = min(widest, onward ? rightward : leftward)
    let column = wide - gutter - far
    func measure(_ w: CGFloat) -> CGRect {
      text.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }
    let tall = ceil(measure(column).height)
    var width = column
    var lo = min(column, 120)
    var hi = column
    for _ in 0..<7 {
      let w = (lo + hi) / 2
      if ceil(measure(w).height) > tall { lo = w } else { hi = w; width = w }
    }
    if tall <= line * 1.5 { width = min(column, ceil(measure(column).width) + 1) }
    width = ceil(width)
    let across = gutter + width + far
    let x = onward ? mark.minX - edge : mark.maxX + edge - across

    let lead = max(0, (mark.height - line) / 2) + edge
    let foot = max(edge, 12)
    let needed = max(mark.height + 2 * edge, lead + tall + foot)
    let downward = screen.maxY - margin - safe.bottom - (mark.minY - edge)
    let upward = (mark.maxY + edge) - (screen.minY + margin + safe.top)
    let down = needed <= downward || downward >= upward
    let room = min(down ? downward : upward, max(screen.height * 0.46, 200))
    let height = min(needed, room)
    let y = down ? mark.minY - edge : mark.maxY + edge - height
    let rest = CGRect(x: x.rounded(), y: y.rounded(), width: across, height: ceil(height))
    let wordsX = onward ? rest.minX + gutter : rest.minX + far
    let wordsY = down ? rest.minY + lead : rest.minY + foot
    return (rest, CGRect(x: wordsX, y: wordsY, width: width, height: rest.height - lead - foot), needed > room)
  }

  /// Keeps the mark and the words where they are on the screen, whatever the glass does around them.
  override func arrange(on frame: CGRect) {
    number.frame = mark.offsetBy(dx: -frame.minX, dy: -frame.minY)
    words.frame = wordsAt.offsetBy(dx: -frame.minX, dy: -frame.minY)
  }

  override func reveal(across: Double, reached: Double) {
    words.alpha = CGFloat(smoothstep(0.3, 0.8, reached))
  }

  override func close(quickly: Bool = false) {
    words.selectedTextRange = nil
    super.close(quickly: quickly)
  }

  // ─── Touches ─────────────────────────────────────────────────────────────

  /// Lets the words' fade follow them to the foot once they've been scrolled there.
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrolls else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    edges.frame = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
    let left = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
    let fade = min(max(left, 0), 44) / 44
    edges.locations = [0, NSNumber(value: Double(1 - 0.14 * fade)), 1]
    CATransaction.commit()
  }
}
