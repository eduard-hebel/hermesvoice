import UIKit

/// Hermes-Tastatur (Stage 2, On-Device-Flow). Hält KEIN Whisper-Modell (77-MB-RAM-Limit)
/// und nimmt NICHT auf (iOS verbietet Mikro + App-Öffnen aus einer Tastatur). Aufgenommen
/// + on-device transkribiert wird in der HermesVoice-App (per Action Button); die App legt
/// den Text in die System-Zwischenablage.
///
/// Diese Tastatur ist eine Spezial-Tastatur OHNE Buchstaben — man wechselt nur zu ihr, um
/// ein Diktat einzusetzen. Deshalb: sobald sie erscheint und ein FRISCHES Diktat vorliegt
/// (Pasteboard-`changeCount` hat sich seit dem letzten Einsetzen geändert), fügt sie es
/// AUTOMATISCH ein. So wird der Flow: Action Button → sprechen → zurückwischen → Text da.
final class KeyboardViewController: UIInputViewController {

    private let statusLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let nextButton = UIButton(type: .system)

    private let ccKey = "lastInsertedPasteChangeCount"

    override func viewDidLoad() {
        super.viewDidLoad()
        // Custom Keyboards MÜSSEN ihre Höhe setzen, sonst sind Buttons nicht tappbar.
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
        view.backgroundColor = .secondarySystemBackground

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        insertButton.setTitle("Diktat einfügen", for: .normal)
        insertButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        insertButton.backgroundColor = .systemBlue
        insertButton.setTitleColor(.white, for: .normal)
        insertButton.layer.cornerRadius = 12
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)

        hintLabel.text = "So geht’s: Action Button drücken → sprechen → hierher zurückwischen. Dein Diktat wird automatisch eingesetzt."
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        nextButton.setTitle("⌨︎  Tastatur wechseln", for: .normal)
        nextButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [statusLabel, insertButton, hintLabel, nextButton])
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
            statusLabel.text = "⚠️ „Vollzugriff“ fehlt — Einstellungen → Allgemein → Tastatur → Tastaturen → HermesVoice → Vollzugriff erlauben."
            insertButton.isEnabled = false
            insertButton.alpha = 0.4
            return
        }
        let has = UIPasteboard.general.hasStrings   // prüft ohne Paste-Banner
        insertButton.isEnabled = has
        insertButton.alpha = has ? 1 : 0.4
        statusLabel.text = has ? "Bereit." : "Noch kein Diktat — Action Button drücken & sprechen."
    }

    /// Setzt das frische Diktat automatisch ein, sobald die Tastatur erscheint —
    /// aber nur EINMAL pro neuem Pasteboard-Inhalt (changeCount), damit es sich nicht
    /// bei jedem Erscheinen wiederholt.
    private func autoInsertIfFresh() {
        guard hasFullAccess else { return }
        let cc = UIPasteboard.general.changeCount
        guard cc != UserDefaults.standard.integer(forKey: ccKey) else { return }
        performInsert(changeCount: cc, auto: true)
    }

    @objc private func insertTapped() {
        guard hasFullAccess else { statusLabel.text = "Vollzugriff nötig (siehe oben)."; return }
        performInsert(changeCount: UIPasteboard.general.changeCount, auto: false)
    }

    private func performInsert(changeCount cc: Int, auto: Bool) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            if !auto { statusLabel.text = "Zwischenablage leer — erst diktieren." }
            return
        }
        textDocumentProxy.insertText(text)
        UserDefaults.standard.set(cc, forKey: ccKey)   // nicht nochmal automatisch einsetzen
        statusLabel.text = "Eingefügt ✓ (\(text.count) Zeichen)"
    }

    @objc private func nextTapped() {
        advanceToNextInputMode()
    }
}
