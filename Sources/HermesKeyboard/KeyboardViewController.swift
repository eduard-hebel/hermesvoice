import UIKit

/// Kleine Einfüge-Tastatur: Die Haupt-App nimmt auf und transkribiert lokal, die Tastatur
/// fügt nur den fertigen HermesVoice-Text aus der App Group in das aktive Textfeld ein.
final class KeyboardViewController: UIInputViewController {

    private let brandLabel = UILabel()
    private let statusLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let nextButton = UIButton(type: .system)

    private func L(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let height = view.heightAnchor.constraint(equalToConstant: 220)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        autoInsertIfFresh()
    }

    override func viewWillLayoutSubviews() {
        nextButton.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    private func setupUI() {
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1)
                : UIColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 1)
        }

        brandLabel.text = "HermesVoice"
        brandLabel.font = .preferredFont(forTextStyle: .headline)
        brandLabel.textColor = .label
        brandLabel.textAlignment = .center

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        var configuration = UIButton.Configuration.filled()
        configuration.title = L("Diktat einfügen")
        configuration.subtitle = L("aus HermesVoice")
        configuration.image = UIImage(systemName: "text.insert")
        configuration.imagePadding = 8
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = UIColor(red: 0.38, green: 0.51, blue: 0.98, alpha: 1)
        configuration.baseForegroundColor = .white
        insertButton.configuration = configuration
        insertButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)

        hintLabel.text = L("App öffnen, sprechen, zurück zur Tastatur. Frische Diktate werden einmalig automatisch eingesetzt.")
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        nextButton.setTitle(L("⌨︎  Tastatur wechseln"), for: .normal)
        nextButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [brandLabel, statusLabel, insertButton, hintLabel, nextButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            insertButton.heightAnchor.constraint(equalToConstant: 52),
            nextButton.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    private func refresh() {
        guard hasFullAccess else {
            statusLabel.text = L("Vollzugriff fehlt: Einstellungen → Allgemein → Tastatur → HermesVoice → erlauben.")
            insertButton.isEnabled = false
            insertButton.alpha = 0.4
            return
        }
        let has = PendingStore.latest()?.text.isEmpty == false
        insertButton.isEnabled = has
        insertButton.alpha = has ? 1 : 0.4
        statusLabel.text = has ? L("Bereit · letzter HermesVoice-Text gefunden.") : L("Noch kein Diktat. Erst in HermesVoice aufnehmen.")
    }

    private func autoInsertIfFresh() {
        guard hasFullAccess else { return }
        guard let text = PendingStore.unconsumedFresh() else { return }
        performInsert(text, auto: true)
    }

    @objc private func insertTapped() {
        guard hasFullAccess else { statusLabel.text = L("Vollzugriff nötig (siehe oben)."); return }
        guard let text = PendingStore.latest()?.text, !text.isEmpty else {
            statusLabel.text = L("Noch kein HermesVoice-Diktat gefunden.")
            return
        }
        performInsert(text, auto: false)
    }

    private func performInsert(_ text: String, auto: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        textDocumentProxy.insertText(text)
        PendingStore.markConsumed()
        statusLabel.text = auto
            ? String(format: L("Automatisch eingefügt · %d Zeichen"), text.count)
            : String(format: L("Eingefügt · %d Zeichen"), text.count)
    }

    @objc private func nextTapped() {
        advanceToNextInputMode()
    }
}
