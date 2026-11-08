import UIKit

/// What the app opens on the first time: a sheet of the library's paper that
/// asks how it should use AI, three ways, the strongest first. An API key is
/// typed in place, and anything that goes wrong is said beneath the buttons.
/// The column scrolls, so the keyboard never covers the key field. It stays
/// until a way is chosen; Settings can change it after.
final class WelcomeViewController: UIViewController {
  static let popupSize = CGSize(width: 520, height: 480)

  /// Called once a way has been chosen.
  var onFinish: (() -> Void)?

  private let chatGPT = UIButton(type: .system)
  private let apiKey = UIButton(type: .system)
  private let keyField = KeyField(framed: true)
  private let offline = UIButton(type: .system)
  private let message = UILabel()
  private let column = UIStackView()
  private let scroll = UIScrollView()

  /// The welcome as a form sheet that can't be swiped away.
  static func sheet(onFinish: @escaping () -> Void) -> WelcomeViewController {
    let vc = WelcomeViewController()
    vc.onFinish = onFinish
    vc.modalPresentationStyle = .formSheet
    vc.preferredContentSize = popupSize
    vc.isModalInPresentation = true
    vc.sheetPresentationController?.preferredCornerRadius = 28
    return vc
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = Parchment.paper
    let backdrop = PaperBackdrop(strength: 0.5)
    backdrop.frame = view.bounds
    backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(backdrop)

    let title = label("Welcome to Aube Reader", LibraryFace.rounded(30, .bold), Parchment.ink)
    let lead = label(
      "To use the AI features, either sign in with your ChatGPT account or paste an OpenAI API key. If you continue without AI, you can still explore the default documents.",
      LibraryFace.rounded(17), Parchment.quiet)

    style(chatGPT, "Sign in with ChatGPT", image: ChatGPTMark.image(side: 21), fill: Parchment.ink, ink: Parchment.paper)
    style(apiKey, "Enter API Key", fill: Parchment.card, ink: Parchment.ink, edge: Parchment.faded.withAlphaComponent(0.5))
    style(offline, "Continue Without AI", fill: .clear, ink: Parchment.quiet)
    chatGPT.addAction(UIAction { [weak self] _ in self?.signIn() }, for: .touchUpInside)
    apiKey.addAction(UIAction { [weak self] _ in self?.showKeyField() }, for: .touchUpInside)
    offline.addAction(UIAction { [weak self] _ in self?.finish(.off) }, for: .touchUpInside)
    keyField.isHidden = true
    keyField.onSave = { [weak self] key in self?.save(key) }

    message.font = LibraryFace.rounded(15)
    message.textColor = .systemRed
    message.textAlignment = .natural
    message.numberOfLines = 0
    message.isHidden = true

    for v in [title, lead, chatGPT, apiKey, keyField, offline, message] { column.addArrangedSubview(v) }
    column.axis = .vertical
    column.spacing = 14
    column.setCustomSpacing(10, after: title)
    column.setCustomSpacing(34, after: lead)
    layOut()
  }

  /// The column sits in the middle of the sheet while there's room, in a
  /// scroll view that ends at the keyboard, so that once the keyboard is up
  /// the column can be scrolled clear of it.
  private func layOut() {
    let page = UIView()
    scroll.keyboardDismissMode = .interactive
    for v in [scroll, page, column] { v.translatesAutoresizingMaskIntoConstraints = false }
    view.addSubview(scroll)
    scroll.addSubview(page)
    page.addSubview(column)

    let middle = column.centerYAnchor.constraint(equalTo: page.centerYAnchor)
    middle.priority = .defaultHigh
    let width = column.widthAnchor.constraint(equalToConstant: 400)
    width.priority = .defaultHigh
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

      page.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      page.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      page.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      page.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      page.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      page.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),

      column.centerXAnchor.constraint(equalTo: page.centerXAnchor),
      column.leadingAnchor.constraint(greaterThanOrEqualTo: page.layoutMarginsGuide.leadingAnchor),
      column.trailingAnchor.constraint(lessThanOrEqualTo: page.layoutMarginsGuide.trailingAnchor),
      column.topAnchor.constraint(greaterThanOrEqualTo: page.topAnchor, constant: 32),
      column.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -32),
      middle,
      width,
    ])
  }

  /// Labels of several lines wrap at the column's width once it's known,
  /// rather than at whatever width they were first measured at, which cuts
  /// their last line off.
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let width = column.bounds.width
    var changed = false
    for case let label as UILabel in column.arrangedSubviews where label.preferredMaxLayoutWidth != width {
      label.preferredMaxLayoutWidth = width
      changed = true
    }
    if changed { view.setNeedsLayout() }
    // With the keyboard up, the field being typed in is kept in sight.
    if keyField.field.isFirstResponder {
      scroll.scrollRectToVisible(keyField.convert(keyField.bounds.insetBy(dx: 0, dy: -24), to: scroll), animated: true)
    }
  }

  private func label(_ text: String, _ font: UIFont, _ color: UIColor) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = font
    label.textColor = color
    label.textAlignment = .natural
    label.numberOfLines = 0
    return label
  }

  private func style(_ button: UIButton, _ title: String, image: UIImage? = nil, fill: UIColor, ink: UIColor, edge: UIColor? = nil) {
    var config = UIButton.Configuration.capsule(title, fill: fill, ink: ink, size: 18)
    config.image = image
    config.imagePadding = 10
    config.background.strokeColor = edge
    config.background.strokeWidth = edge == nil ? 0 : 1
    button.configuration = config
    button.heightAnchor.constraint(equalToConstant: KeyField.height).isActive = true
  }

  // ─── Choosing ────────────────────────────────────────────────────────────

  private func say(_ text: String?) {
    message.text = text
    message.isHidden = text == nil
  }

  private func signIn() {
    say(nil)
    setBusy(true)
    chatGPT.configuration?.showsActivityIndicator = true
    Task { @MainActor in
      let outcome = await AccessFlow.signIn(from: self)
      setBusy(false)
      chatGPT.configuration?.showsActivityIndicator = false
      switch outcome {
      case .signedIn: onFinish?()
      case .cancelled: break
      case let .failed(why): say(why)
      }
    }
  }

  /// The Enter API Key button gives way to the field itself.
  private func showKeyField() {
    say(nil)
    UIView.animate(withDuration: 0.25) {
      self.apiKey.isHidden = true
      self.keyField.isHidden = false
    }
    keyField.field.becomeFirstResponder()
  }

  private func save(_ key: String) {
    say(nil)
    setBusy(true)
    keyField.busy = true
    Task { @MainActor in
      let problem = await AccessFlow.save(key: key)
      setBusy(false)
      keyField.busy = false
      if let problem { return keyField.reject(problem.hint) }
      keyField.field.resignFirstResponder()
      onFinish?()
    }
  }

  private func setBusy(_ busy: Bool) {
    for b in [chatGPT, apiKey, offline] { b.isEnabled = !busy }
  }

  private func finish(_ access: Access) {
    Store.access = access
    onFinish?()
  }
}
