import UIKit

// ─── Settings ────────────────────────────────────────────────────────────────

/// The settings dialog, opened from the gear in the library's bar: a centred
/// form sheet holding an inset-grouped list, one hand-drawn glyph, one title
/// and one control or fact to a row, every row the same tall height. It keeps
/// the library's colors, cards of the card's stock and lettering in its inks,
/// on a quieter sheet, its age at half the library's, and type the system's own.
final class SettingsViewController: UITableViewController {
  /// The dialog's size; the form sheet clamps it to the window.
  static let popupSize = CGSize(width: 560, height: 1000)

  private enum Row {
    case toggle(String, SettingsGlyph, UISwitch)
    case value(String, SettingsGlyph, String)
  }

  private struct Section {
    let header: String
    let rows: [Row]
  }

  private let luna = UISwitch()
  private let fast = UISwitch()
  private let onGesture = UISwitch()
  private let inspect = UISwitch()
  private var sections: [Section] = []

  init() { super.init(style: .insetGrouped) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// The dialog in its navigation controller, presented as a form sheet.
  static func sheet() -> UINavigationController {
    let nav = UINavigationController(rootViewController: SettingsViewController())
    Parchment.dress(nav.navigationBar, script: false)
    nav.modalPresentationStyle = .formSheet
    nav.preferredContentSize = popupSize
    nav.sheetPresentationController?.preferredCornerRadius = 28
    return nav
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Settings"
    navigationItem.largeTitleDisplayMode = .never
    preferredContentSize = Self.popupSize
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Done", primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })

    tableView.backgroundColor = Parchment.paper
    tableView.backgroundView = PaperBackdrop(strength: 0.5)
    tableView.separatorStyle = .none
    tableView.rowHeight = SettingsRow.height
    tableView.sectionHeaderHeight = UITableView.automaticDimension
    tableView.estimatedSectionHeaderHeight = 46
    tableView.register(SettingsRow.self, forCellReuseIdentifier: "row")

    luna.isOn = Store.useLuna
    luna.addAction(UIAction { [weak self] _ in self?.lunaChanged() }, for: .valueChanged)
    fast.isOn = Store.fastTier
    fast.addAction(UIAction { [weak self] _ in Store.fastTier = self?.fast.isOn ?? false }, for: .valueChanged)
    onGesture.isOn = Store.writeOnGesture
    onGesture.addAction(UIAction { [weak self] _ in Store.writeOnGesture = self?.onGesture.isOn ?? true }, for: .valueChanged)
    inspect.isOn = Store.checkImports
    inspect.addAction(UIAction { [weak self] _ in Store.checkImports = self?.inspect.isOn ?? true }, for: .valueChanged)
    for s in [luna, fast, onGesture, inspect] { s.onTintColor = Parchment.accent }

    sections = makeSections()
  }

  private func makeSections() -> [Section] {
    let info = Bundle.main.infoDictionary
    let version = "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    return [
      Section(header: "Asking", rows: [
        .value("Model", .model, OpenAI.model),
        .toggle("Use gpt-6-luna", .luna, luna),
        .toggle("Fast tier", .fast, fast),
        .toggle("Write only on gesture", .gesture, onGesture),
        .value("API key", .key, OpenAI.key == nil ? "Missing" : "Set"),
      ]),
      Section(header: "Importing", rows: [
        .toggle("Check with the model", .check, inspect)
      ]),
      Section(header: "About", rows: [
        .value("Version", .version, version)
      ]),
    ]
  }

  /// The Model row names the model now in use, so it changes with the switch.
  private func lunaChanged() {
    Store.useLuna = luna.isOn
    sections = makeSections()
    tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
  }

  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].header }

  override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
    guard let header = view as? UITableViewHeaderFooterView else { return }
    var config = header.defaultContentConfiguration()
    config.text = sections[section].header
    config.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
    config.textProperties.color = Parchment.faded
    config.textProperties.transform = .none
    config.directionalLayoutMargins.top = 26
    config.directionalLayoutMargins.bottom = 10
    header.contentConfiguration = config
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsRow
    // The last row of a card closes it, so it carries no hairline.
    cell.showsHairline = indexPath.row < sections[indexPath.section].rows.count - 1
    switch sections[indexPath.section].rows[indexPath.row] {
    case let .toggle(title, glyph, control):
      cell.contentConfiguration = SettingsRow.content(title, glyph)
      cell.accessoryView = control
    case let .value(title, glyph, value):
      cell.contentConfiguration = SettingsRow.content(title, glyph, value: value)
      cell.accessoryView = nil
    }
    return cell
  }

  override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool { false }
}

/// A settings row: tall, on a card of the card's stock, with a hairline of
/// faded ink that starts at the title's column and stops at the card's margin.
private final class SettingsRow: UITableViewCell {
  static let height = SettingsGlyph.side + 34
  static let padding: CGFloat = 14

  private let hairline = UIView()

  var showsHairline = true { didSet { hairline.isHidden = !showsHairline } }

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    var background = UIBackgroundConfiguration.listGroupedCell()
    background.backgroundColor = Parchment.card
    background.cornerRadius = 20
    backgroundConfiguration = background
    hairline.backgroundColor = Parchment.faded.withAlphaComponent(0.3)
    addSubview(hairline)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// The glyph, the title, and at most a short fact on the trailing edge.
  static func content(_ title: String, _ glyph: SettingsGlyph, value: String? = nil) -> UIListContentConfiguration {
    var config = value == nil ? UIListContentConfiguration.cell() : UIListContentConfiguration.valueCell()
    config.text = title
    config.textProperties.font = .systemFont(ofSize: 18)
    config.textProperties.color = Parchment.ink
    config.secondaryText = value
    config.secondaryTextProperties.font = .systemFont(ofSize: 17)
    config.secondaryTextProperties.color = Parchment.quiet
    config.image = glyph.image
    config.imageProperties.tintColor = Parchment.ink
    config.imageProperties.reservedLayoutSize = CGSize(width: SettingsGlyph.side, height: SettingsGlyph.side)
    config.imageToTextPadding = padding
    let inset = (height - SettingsGlyph.side) / 2
    config.directionalLayoutMargins = NSDirectionalEdgeInsets(top: inset, leading: 0, bottom: inset, trailing: 0)
    return config
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

// ─── Glyphs ──────────────────────────────────────────────────────────────────

/// The settings' glyphs, drawn rather than taken from SF Symbols: one canvas,
/// one round stroke, so a column of them reads as a set. Template images, so a
/// row inks them.
enum SettingsGlyph {
  case model, luna, fast, gesture, key, version, check

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
