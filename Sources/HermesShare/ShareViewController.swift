import UniformTypeIdentifiers
import UIKit
import UserNotifications

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let doneButton = UIButton(type: .system)
    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Datei wird an HermesVoice übergeben ..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)

        doneButton.setTitle("Fertig", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        activityIndicator.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        receiveSharedMedia()
    }

    private func receiveSharedMedia() {
        guard let provider = extensionContext?.inputItems
            .compactMap({ $0 as? NSExtensionItem })
            .compactMap(\.attachments)
            .flatMap({ $0 })
            .first,
              let typeIdentifier = supportedTypeIdentifier(from: provider.registeredTypeIdentifiers)
        else {
            showResult("Keine unterstützte Audio- oder Videodatei gefunden.")
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
            guard let self else { return }
            do {
                if let error { throw error }
                guard let url else { throw CocoaError(.fileNoSuchFile) }
                guard let inbox = SharedImportInbox.appGroupInbox() else {
                    throw CocoaError(.fileNoSuchFile)
                }
                _ = try inbox.enqueue(
                    fileURL: url,
                    originalFilename: originalFilename(
                        provider: provider,
                        fileURL: url,
                        typeIdentifier: typeIdentifier
                    )
                )
                scheduleOpenAppNotification()
                DispatchQueue.main.async {
                    self.showResult("Übergeben. Öffne HermesVoice; der Import startet dort automatisch.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.showResult("Übergabe fehlgeschlagen: \(error.localizedDescription)")
                }
            }
        }
    }

    private func supportedTypeIdentifier(from identifiers: [String]) -> String? {
        identifiers
            .compactMap { identifier -> (priority: Int, identifier: String)? in
                guard let priority = supportedTypePriority(identifier) else { return nil }
                return (priority, identifier)
            }
            .sorted { lhs, rhs in lhs.priority < rhs.priority }
            .first?
            .identifier
    }

    private func supportedTypePriority(_ identifier: String) -> Int? {
        guard let type = UTType(identifier) else { return nil }
        if type.conforms(to: .audio) { return 0 }
        if type.conforms(to: .movie) { return 1 }
        if type.conforms(to: .audiovisualContent) { return 2 }
        if type.conforms(to: .fileURL) { return 3 }
        if type.conforms(to: .data) { return 4 }
        return nil
    }

    private func originalFilename(
        provider: NSItemProvider,
        fileURL: URL,
        typeIdentifier: String
    ) -> String {
        let filename = provider.suggestedName ?? fileURL.lastPathComponent
        guard URL(fileURLWithPath: filename).pathExtension.isEmpty,
              let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension
        else {
            return filename
        }
        return "\(filename).\(preferredExtension)"
    }

    private func showResult(_ text: String) {
        activityIndicator.stopAnimating()
        statusLabel.text = text
        doneButton.isHidden = false
    }

    private func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Bereit für HermesVoice"
        content.body = "Öffne HermesVoice, um die geteilte Datei lokal zu transkribieren."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
