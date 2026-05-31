import UIKit

/// Hermes-Tastatur (Stage 2). Hält bewusst KEIN Whisper-Modell (77-MB-RAM-Limit der
/// Tastatur). Aufgenommen + transkribiert wird in der Haupt-App; die App legt den Text
/// in die System-Zwischenablage. Die Tastatur liest ihn von dort und fügt ihn mit EINEM
/// Tipp in die gerade aktive App ein — ohne dass du das Paste-Menü brauchst.
/// (Zwischenablage statt App-Group → kein Sonder-Provisioning; braucht „Vollzugriff".)
final class KeyboardViewController: UIInputViewController {

    private let statusLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let recordButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        // WICHTIG: Custom Keyboards MÜSSEN ihre Höhe selbst festlegen. Ohne diese
        // Constraint ist die echte Touch-/Hit-Fläche der Tastatur kleiner als die
        // sichtbaren Buttons → man sieht sie, aber Tipps gehen ins Leere. Priority < 1000,
        // damit es nicht mit System-Constraints kollidiert.
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 240)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
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

        configure(insertButton, title: "Letztes Diktat einfügen", filled: true, action: #selector(insertTapped))
        configure(recordButton, title: "🎙  Neu aufnehmen", filled: false, action: #selector(recordTapped))
        configure(nextButton, title: "⌨︎  Tastatur wechseln", filled: false, action: #selector(nextTapped))

        let stack = UIStackView(arrangedSubviews: [statusLabel, insertButton, recordButton, nextButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            insertButton.heightAnchor.constraint(equalToConstant: 50),
            recordButton.heightAnchor.constraint(equalToConstant: 42),
            nextButton.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    private func configure(_ b: UIButton, title: String, filled: Bool, action: Selector) {
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .preferredFont(forTextStyle: filled ? .headline : .subheadline)
        b.layer.cornerRadius = 11
        if filled {
            b.backgroundColor = .systemBlue
            b.setTitleColor(.white, for: .normal)
        } else {
            b.backgroundColor = .tertiarySystemBackground
            b.setTitleColor(.label, for: .normal)
        }
        b.addTarget(self, action: action, for: .touchUpInside)
    }

    private func refresh() {
        guard hasFullAccess else {
            statusLabel.text = "⚠️ „Vollzugriff“ fehlt — Einstellungen → Allgemein → Tastatur → Tastaturen → HermesVoice → Vollzugriff erlauben."
            insertButton.isEnabled = false
            insertButton.alpha = 0.4
            return
        }
        // `hasStrings` prüft OHNE die „Eingefügt aus …"-Banner-Meldung auszulösen.
        let has = UIPasteboard.general.hasStrings
        insertButton.isEnabled = has
        insertButton.alpha = has ? 1 : 0.4
        statusLabel.text = has
            ? "Tippe „Einfügen“, um dein letztes Diktat hier einzusetzen."
            : "Nichts in der Zwischenablage.\nIn HermesVoice diktieren, dann hier einfügen."
    }

    @objc private func insertTapped() {
        guard hasFullAccess else { statusLabel.text = "Vollzugriff nötig (siehe oben)."; return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            statusLabel.text = "Zwischenablage leer — erst in HermesVoice diktieren."
            return
        }
        textDocumentProxy.insertText(text)
        statusLabel.text = "Eingefügt ✓ — \(text.count) Zeichen"
    }

    @objc private func recordTapped() {
        statusLabel.text = "Öffne HermesVoice …"
        openMainApp(urlString: "hermes://record")
    }

    @objc private func nextTapped() {
        advanceToNextInputMode()
    }

    /// Öffnet die Haupt-App. Tastatur-Erweiterungen haben kein `extensionContext.open`,
    /// daher der bewährte Responder-Chain-Weg über `openURL:`.
    private func openMainApp(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }
}
