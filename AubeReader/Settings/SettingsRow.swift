import UIKit

extension UITableView {
  /// Dresses the table as a page of Settings: cards of rows, all one height,
  /// on the library's paper.
  func dressForSettings() {
    backgroundColor = Parchment.paper
    backgroundView = PaperBackdrop(strength: 0.5)
    separatorStyle = .none
    rowHeight = SettingsRow.height
    sectionHeaderHeight = UITableView.automaticDimension
    estimatedSectionHeaderHeight = 46
    register(SettingsRow.self, forCellReuseIdentifier: SettingsRow.reuse)
  }

  /// Sizes the sheet `vc` is shown in to the table's rows, and `extraRows`
  /// more, at the dialog's width: the navigation controller's too, which the
  /// sheet goes by, and which doesn't follow a page pushed onto it by itself.
  func fitSheet(to vc: UIViewController, extraRows: Int = 0) {
    let height = ceil(contentSize.height) + CGFloat(max(0, extraRows)) * SettingsRow.height
    let size = CGSize(width: SettingsViewController.width, height: height)
    if vc.preferredContentSize != size { vc.preferredContentSize = size }
    guard let nav = vc.navigationController, nav.topViewController === vc else { return }
    let whole = CGSize(width: size.width, height: size.height + nav.navigationBar.frame.height)
    if nav.preferredContentSize != whole { nav.preferredContentSize = whole }
  }
}

/// A settings row: tall, on a card of the card's stock, with a hairline of
/// faded ink that starts at the title's column and stops at the card's margin.
final class SettingsRow: UITableViewCell {
  static let reuse = "row"
  static let height = SettingsGlyph.side + 34
  static let padding: CGFloat = 14

  /// The card of the card's stock that every row of Settings sits on.
  static var card: UIBackgroundConfiguration {
    var background = UIBackgroundConfiguration.listGroupedCell()
    background.backgroundColor = Parchment.card
    background.cornerRadius = 20
    return background
  }

  /// Sets a section's header in Settings' lettering.
  static func dress(header view: UIView, _ text: String) {
    guard let header = view as? UITableViewHeaderFooterView else { return }
    var config = header.defaultContentConfiguration()
    config.text = text
    config.textProperties.font = LibraryFace.rounded(17, .semibold)
    config.textProperties.color = Parchment.faded
    config.textProperties.transform = .none
    config.directionalLayoutMargins.top = 26
    config.directionalLayoutMargins.bottom = 10
    header.contentConfiguration = config
  }

  private let hairline = UIView()

  var showsHairline = true { didSet { hairline.isHidden = !showsHairline } }

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundConfiguration = SettingsRow.card
    hairline.backgroundColor = Parchment.faded.withAlphaComponent(0.3)
    addSubview(hairline)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// The glyph, the title, and at most a short fact on the trailing edge.
  /// `ink` for a title in another color, as a destructive action's is.
  static func content(_ title: String, _ glyph: SettingsGlyph, value: String? = nil, ink: UIColor = Parchment.ink) -> UIListContentConfiguration {
    var config = value == nil ? UIListContentConfiguration.cell() : UIListContentConfiguration.valueCell()
    config.text = title
    config.textProperties.font = LibraryFace.rounded(18)
    config.textProperties.color = ink
    config.secondaryText = value
    config.secondaryTextProperties.font = LibraryFace.rounded(17)
    config.secondaryTextProperties.color = Parchment.quiet
    config.image = glyph.image
    config.imageProperties.tintColor = ink
    config.imageProperties.reservedLayoutSize = CGSize(width: SettingsGlyph.side, height: SettingsGlyph.side)
    config.imageToTextPadding = padding
    let inset = (height - SettingsGlyph.side) / 2
    config.directionalLayoutMargins = NSDirectionalEdgeInsets(top: inset, leading: 0, bottom: inset, trailing: 0)
    return config
  }

  /// The mark of a row that opens something, in faded ink.
  static func chevron() -> UIImageView {
    let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
    let view = UIImageView(image: UIImage(systemName: "chevron.forward", withConfiguration: config))
    view.tintColor = Parchment.faded
    return view
  }

  /// The mark of the chosen row among several, in the accent.
  static func check() -> UIImageView {
    let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    let view = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: config))
    view.tintColor = Parchment.accent
    return view
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    bringSubviewToFront(hairline)
    let thickness = 1 / max(traitCollection.displayScale, 1)
    let leading = layoutMargins.left + SettingsGlyph.side + Self.padding
    hairline.frame = CGRect(
      x: leading, y: bounds.height - thickness, width: max(0, bounds.width - leading - layoutMargins.right), height: thickness)
  }
}
