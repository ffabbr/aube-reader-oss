import UIKit

/// The settings dialog, opened from the gear in the library's bar: a centred
/// form sheet holding an inset-grouped list, one hand-drawn glyph, one title
/// and one control or fact to a row, every row the same tall height. It keeps
/// the library's colors, cards of the card's stock and lettering in its inks,
/// on a quieter sheet, its age at half the library's, and type the system's own.
final class SettingsViewController: UITableViewController {
  /// The dialog's width. Its height is what its rows need, which the form
  /// sheet clamps to the window.
  static let width: CGFloat = 560

  private enum Row {
    case toggle(String, SettingsGlyph, UISwitch)
    case value(String, SettingsGlyph, String)
    /// A row that does something when tapped: opens a page, or a link.
    case link(String, SettingsGlyph, String?, () -> Void)
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
    nav.sheetPresentationController?.preferredCornerRadius = 28
    return nav
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Settings"
    navigationItem.largeTitleDisplayMode = .never
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Done", primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })

    tableView.dressForSettings()

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

  /// The most rows Asking holds: an API key's model, Luna, fast tier and the rest.
  private static let mostAskingRows = 5

  /// The sheet stays one height whatever the AI page shows and however AI is
  /// reached: what these rows need with Asking at its fullest.
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let asking = sections.first?.rows.count ?? Self.mostAskingRows
    tableView.fitSheet(to: self, extraRows: Self.mostAskingRows - asking)
  }

  /// Coming back from the AI page, what it changed shows here.
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sections = makeSections()
    tableView.reloadData()
  }

  /// How the app reaches OpenAI, in a word or two.
  private var accessName: String {
    switch OpenAI.access {
    case .chatGPT: ChatGPT.shared.ready ? "ChatGPT" : "ChatGPT, signed out"
    case .apiKey: OpenAI.key == nil ? "API key, missing" : "API key"
    case .off: "Off"
    }
  }

  private func makeSections() -> [Section] {
    let info = Bundle.main.infoDictionary
    let version = "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    var asking: [Row] = [.link("AI", .access, accessName) { [weak self] in self?.openAccess() }]
    switch OpenAI.access {
    case .chatGPT:
      asking.append(.value("Model", .model, ChatGPT.shared.choice.name))
      // Near the model, as OpenAI asks: that requests use the plan, and where to see how much.
      asking.append(.link("Using ChatGPT plan", .usage, "Manage usage") { UIApplication.shared.open(ChatGPT.usageURL) })
    case .apiKey:
      asking += [.value("Model", .model, OpenAI.model), .toggle("Use \(OpenAI.lunaModel)", .luna, luna), .toggle("Fast tier", .fast, fast)]
    case .off:
      break
    }
    asking.append(.toggle("Write only on gesture", .gesture, onGesture))
    return [
      Section(header: "Asking", rows: asking),
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
    tableView.reloadData()
  }

  private func openAccess() {
    navigationController?.pushViewController(AccessSettingsViewController(), animated: true)
  }

  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].header }

  override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
    SettingsRow.dress(header: view, sections[section].header)
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: SettingsRow.reuse, for: indexPath) as! SettingsRow
    // The last row of a card closes it, so it carries no hairline.
    cell.showsHairline = indexPath.row < sections[indexPath.section].rows.count - 1
    switch sections[indexPath.section].rows[indexPath.row] {
    case let .toggle(title, glyph, control):
      cell.contentConfiguration = SettingsRow.content(title, glyph)
      cell.accessoryView = control
    case let .value(title, glyph, value):
      cell.contentConfiguration = SettingsRow.content(title, glyph, value: value)
      cell.accessoryView = nil
    case let .link(title, glyph, value, _):
      cell.contentConfiguration = SettingsRow.content(title, glyph, value: value)
      cell.accessoryView = SettingsRow.chevron()
    }
    return cell
  }

  override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
    if case .link = sections[indexPath.section].rows[indexPath.row] { return true }
    return false
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if case let .link(_, _, _, action) = sections[indexPath.section].rows[indexPath.row] { action() }
  }
}
