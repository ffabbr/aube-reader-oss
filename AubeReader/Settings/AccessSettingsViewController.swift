import UIKit

/// The page Settings opens from its AI row: the same three ways as the welcome
/// screen, the chosen one ticked, then the ChatGPT account and the API key,
/// each with what can be done about it. A key is typed in place, and anything
/// that goes wrong is said beneath its section. In the dialog's own look.
final class AccessSettingsViewController: UITableViewController {
  private enum Row {
    /// One of the three ways, with a word on how it stands.
    case way(Access, String, SettingsGlyph, String?)
    case value(String, SettingsGlyph, String)
    case action(String, SettingsGlyph, String?, destructive: Bool, () -> Void)
    /// The field an API key is typed into.
    case keyField
  }

  private struct Section {
    let header: String
    var footer: String?
    var footerIsProblem = false
    let rows: [Row]
  }

  private var sections: [Section] = []
  /// A sentence beneath the ways: why a sign-in didn't work, or what to know.
  private var notice: (text: String, isProblem: Bool)?
  /// Whether the key field is out, in place of the row that opens it.
  private var typingKey = false
  /// Whether a sign-in, a sign-out or a key check is under way, which the rows wait for.
  private var working = false
  private let keyField = KeyField(framed: false)

  init() { super.init(style: .insetGrouped) }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "AI"
    navigationItem.largeTitleDisplayMode = .never
    // The sheet keeps the height Settings gave it, so nothing jumps on the way
    // in or out; this page scrolls if it ever needs more.
    tableView.dressForSettings()
    tableView.register(KeyFieldRow.self, forCellReuseIdentifier: "key")
    keyField.onSave = { [weak self] key in self?.save(key) }
    refresh()
  }

  private func refresh() {
    sections = makeSections()
    tableView.reloadData()
  }

  private func makeSections() -> [Section] {
    let plan = ChatGPT.shared
    let session = plan.session
    let chatGPTState = session == nil ? "Sign in" : plan.ready ? session?.email ?? "Signed in" : "Plan not available"
    let keyState = OpenAI.key == nil ? "Not set" : "Entered"

    var out = [
      Section(header: "Use AI with", rows: [
        .way(.chatGPT, "ChatGPT", .chatGPT, chatGPTState),
        .way(.apiKey, "OpenAI API key", .key, keyState),
        .way(.off, "Without AI", .offline, nil),
      ])
    ]

    if let session {
      var rows: [Row] = [.value("Account", .account, session.email ?? "Signed in")]
      if plan.ready {
        rows.append(.value("Model", .model, plan.choice.name))
        rows.append(.value("Speed", .fast, plan.choice.tier.name))
        rows.append(.action("Using ChatGPT plan", .usage, "Manage usage", destructive: false) { UIApplication.shared.open(ChatGPT.usageURL) })
      }
      rows.append(.action("Sign Out", .signOut, nil, destructive: true) { [weak self] in self?.confirmSignOut() })
      out.append(Section(header: "ChatGPT", rows: rows))
    }

    var keyRows: [Row] = typingKey
      ? [.keyField]
      : [.action(OpenAI.key == nil ? "Enter Key" : "Change Key", .key, nil, destructive: false) { [weak self] in self?.openKeyField() }]
    if OpenAI.key != nil {
      keyRows.append(.action("Remove Key", .signOut, nil, destructive: true) { [weak self] in self?.removeKey() })
    }
    out.append(Section(header: "API key", rows: keyRows))

    if let notice {
      out[0].footer = notice.text
      out[0].footerIsProblem = notice.isProblem
    }
    return out
  }

  private func tell(_ text: String?, isProblem: Bool = true) {
    notice = text.map { ($0, isProblem) }
    refresh()
  }

  // ─── Choosing ────────────────────────────────────────────────────────────

  private func choose(_ way: Access) {
    notice = nil
    switch way {
    case .chatGPT:
      if ChatGPT.shared.ready {
        Store.access = .chatGPT
        refresh()
      } else {
        signIn()
      }
    case .apiKey:
      if OpenAI.key != nil {
        Store.access = .apiKey
        refresh()
      } else {
        openKeyField()
      }
    case .off:
      Store.access = .off
      refresh()
    }
  }

  private func signIn() {
    working = true
    Task { @MainActor in
      let outcome = await AccessFlow.signIn(from: self)
      working = false
      if case let .failed(why) = outcome { return tell(why) }
      refresh()
    }
  }

  private func openKeyField() {
    notice = nil
    typingKey = true
    refresh()
    // The field is in its row only once the table has laid the row out.
    tableView.layoutIfNeeded()
    keyField.field.text = nil
    keyField.field.becomeFirstResponder()
  }

  private func save(_ key: String) {
    working = true
    keyField.busy = true
    Task { @MainActor in
      let problem = await AccessFlow.save(key: key)
      working = false
      keyField.busy = false
      if let problem { return keyField.reject(problem.hint) }
      keyField.field.resignFirstResponder()
      typingKey = false
      tell(nil)
    }
  }

  private func removeKey() {
    OpenAI.key = nil
    tell(nil)
  }

  private func confirmSignOut() {
    let alert = UIAlertController(
      title: "Sign Out of ChatGPT?", message: "Rewriting and asking stop until you sign in again or choose another way.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in self?.signOut() })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
  }

  private func signOut() {
    working = true
    Task { @MainActor in
      let confirmed = await ChatGPT.shared.signOut()
      working = false
      tell(
        confirmed ? nil : "Signed out on this iPad. OpenAI couldn’t be reached to confirm it; you can also disconnect Aube Reader in your ChatGPT settings.",
        isProblem: false)
    }
  }

  // ─── The table ───────────────────────────────────────────────────────────

  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].header }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

  override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
    SettingsRow.dress(header: view, sections[section].header)
  }

  override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
    guard let footer = view as? UITableViewHeaderFooterView, let text = sections[section].footer else { return }
    var config = footer.defaultContentConfiguration()
    config.text = text
    config.textProperties.font = LibraryFace.rounded(15)
    config.textProperties.color = sections[section].footerIsProblem ? .systemRed : Parchment.faded
    footer.contentConfiguration = config
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let row = sections[indexPath.section].rows[indexPath.row]
    if case .keyField = row {
      let cell = tableView.dequeueReusableCell(withIdentifier: "key", for: indexPath) as! KeyFieldRow
      cell.hold(keyField)
      return cell
    }
    let cell = tableView.dequeueReusableCell(withIdentifier: SettingsRow.reuse, for: indexPath) as! SettingsRow
    cell.showsHairline = indexPath.row < sections[indexPath.section].rows.count - 1
    switch row {
    case let .way(way, title, glyph, value):
      cell.contentConfiguration = SettingsRow.content(title, glyph, value: value)
      cell.accessoryView = way == OpenAI.access ? SettingsRow.check() : nil
    case let .value(title, glyph, value):
      cell.contentConfiguration = SettingsRow.content(title, glyph, value: value)
      cell.accessoryView = nil
    case let .action(title, glyph, value, destructive, _):
      cell.contentConfiguration = SettingsRow.content(title, glyph, value: value, ink: destructive ? .systemRed : Parchment.ink)
      cell.accessoryView = destructive ? nil : SettingsRow.chevron()
    case .keyField:
      break
    }
    return cell
  }

  override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
    switch sections[indexPath.section].rows[indexPath.row] {
    case .way, .action: !working
    case .value, .keyField: false
    }
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    defer { tableView.deselectRow(at: indexPath, animated: true) }
    guard !working else { return }
    switch sections[indexPath.section].rows[indexPath.row] {
    case let .way(way, _, _, _): choose(way)
    case let .action(_, _, _, _, act): act()
    case .value, .keyField: break
    }
  }
}

/// A row of the AI page holding the key field, on the same card as the rows
/// around it, behind the key's glyph.
private final class KeyFieldRow: UITableViewCell {
  private let glyph = UIImageView(image: SettingsGlyph.key.image)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundConfiguration = SettingsRow.card
    glyph.tintColor = Parchment.ink
    glyph.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(glyph)
    NSLayoutConstraint.activate([
      glyph.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
      glyph.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      glyph.widthAnchor.constraint(equalToConstant: SettingsGlyph.side),
      glyph.heightAnchor.constraint(equalToConstant: SettingsGlyph.side),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// Puts `field` in the row, after the glyph.
  func hold(_ field: KeyField) {
    guard field.superview !== contentView else { return }
    field.removeFromSuperview()
    field.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(field)
    NSLayoutConstraint.activate([
      field.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: SettingsRow.padding),
      field.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      field.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }
}
