import UIKit

/// An API key typed in place: a secure field with a Save button at its end,
/// which turns to a spinner while OpenAI looks at the key. A key that won't do
/// is shaken off rather than explained. `framed`, it's a capsule of its own,
/// as tall as the buttons around it; otherwise it sits bare in a row of Settings.
final class KeyField: UIView, UITextFieldDelegate {
  static let height: CGFloat = 54

  let field = UITextField()
  /// Called with what was typed, on Save or Return.
  var onSave: ((String) -> Void)?

  var busy = false {
    didSet {
      field.isEnabled = !busy
      save.isEnabled = !busy
      save.configuration?.showsActivityIndicator = busy
    }
  }

  private let save = UIButton(type: .system)

  init(framed: Bool) {
    super.init(frame: .zero)
    if framed {
      backgroundColor = Parchment.card
      layer.cornerRadius = Self.height / 2
      layer.borderWidth = 1
      layer.borderColor = Parchment.faded.withAlphaComponent(0.5).cgColor
      heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    field.placeholder = Self.placeholder
    // Typing again puts the usual placeholder back after a refusal.
    field.addAction(UIAction { [weak self] _ in self?.field.placeholder = Self.placeholder }, for: .editingChanged)
    field.font = LibraryFace.rounded(17)
    field.textColor = Parchment.ink
    field.tintColor = Parchment.ink
    field.isSecureTextEntry = true
    field.autocorrectionType = .no
    field.autocapitalizationType = .none
    field.spellCheckingType = .no
    field.returnKeyType = .done
    field.delegate = self

    var config = UIButton.Configuration.capsule("Save", fill: Parchment.ink, ink: Parchment.paper, size: 17)
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22)
    save.configuration = config
    // The button keeps its width; a long key scrolls inside the field instead.
    save.setContentHuggingPriority(.required, for: .horizontal)
    save.setContentCompressionResistancePriority(.required, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    save.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

    let row = UIStackView(arrangedSubviews: [field, save])
    row.spacing = 10
    row.alignment = .center
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    let inset: CGFloat = framed ? 6 : 0
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: framed ? 22 : 0),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      row.topAnchor.constraint(equalTo: topAnchor, constant: inset),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
      save.heightAnchor.constraint(equalToConstant: Self.height - 12),
    ])
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: KeyField, _) in
      self.layer.borderColor = Parchment.faded.withAlphaComponent(0.5).cgColor
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private static let placeholder = "Paste your API key"

  /// Refuses what was typed: the field shakes, as a password field does, with
  /// a tap of the error haptic, and `hint` takes the place of what was typed.
  func reject(_ hint: String?) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
    shake.values = [0, -12, 10, -8, 6, -3, 0]
    shake.duration = 0.45
    shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
    layer.add(shake, forKey: "shake")
    if let hint {
      field.text = nil
      field.attributedPlaceholder = NSAttributedString(string: hint, attributes: [.foregroundColor: UIColor.systemRed.withAlphaComponent(0.75)])
    }
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submit()
    return false
  }

  private func submit() {
    guard !busy else { return }
    onSave?(field.text ?? "")
  }
}
