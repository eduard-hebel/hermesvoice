import Foundation

struct SharedImportEnvelope: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let originalFilename: String
    let fileURL: URL
}

struct SharedImportInbox {
    static let appGroupIdentifier = "group.de.hermes.voice.shared"

    private let rootURL: URL
    private let filesURL: URL
    private let readyURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        filesURL = rootURL.appendingPathComponent("Files", isDirectory: true)
        readyURL = rootURL.appendingPathComponent("Ready", isDirectory: true)
    }

    static func appGroupInbox(fileManager: FileManager = .default) -> SharedImportInbox? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        return SharedImportInbox(rootURL: container.appendingPathComponent("HermesShareInbox", isDirectory: true))
    }

    func enqueue(fileURL: URL, originalFilename providedOriginalFilename: String? = nil) throws -> SharedImportEnvelope {
        try prepareDirectories()
        let id = UUID()
        let source = Self.resolvedSource(
            for: fileURL,
            providedOriginalFilename: providedOriginalFilename
        )
        let originalFilename = Self.originalFilename(
            for: source.fileURL,
            providedOriginalFilename: source.originalFilename
        )
        let fileExtension = Self.fileExtension(
            for: source.fileURL,
            originalFilename: originalFilename
        )
        let storedFilename = fileExtension.isEmpty ? id.uuidString : "\(id.uuidString).\(fileExtension)"
        let finalFileURL = filesURL.appendingPathComponent(storedFilename)
        let partialFileURL = finalFileURL.appendingPathExtension("partial")
        let manifestURL = readyURL.appendingPathComponent("\(id.uuidString).json")
        let partialManifestURL = manifestURL.appendingPathExtension("partial")
        let hasSecurityAccess = source.fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { source.fileURL.stopAccessingSecurityScopedResource() }
        }

        do {
            try FileManager.default.copyItem(at: source.fileURL, to: partialFileURL)
            try FileManager.default.moveItem(at: partialFileURL, to: finalFileURL)
            let envelope = SharedImportEnvelope(
                id: id,
                createdAt: .now,
                originalFilename: originalFilename,
                fileURL: finalFileURL
            )
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: partialManifestURL, options: .atomic)
            try FileManager.default.moveItem(at: partialManifestURL, to: manifestURL)
            return envelope
        } catch {
            try? FileManager.default.removeItem(at: partialFileURL)
            try? FileManager.default.removeItem(at: finalFileURL)
            try? FileManager.default.removeItem(at: partialManifestURL)
            throw error
        }
    }

    func pending() throws -> [SharedImportEnvelope] {
        try prepareDirectories()
        let manifestURLs = try FileManager.default.contentsOfDirectory(
            at: readyURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        return manifestURLs.compactMap { manifestURL in
            guard let data = try? Data(contentsOf: manifestURL),
                  let envelope = try? JSONDecoder().decode(SharedImportEnvelope.self, from: data),
                  FileManager.default.fileExists(atPath: envelope.fileURL.path)
            else { return nil }
            return envelope
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func remove(_ envelope: SharedImportEnvelope) throws {
        let manifestURL = readyURL.appendingPathComponent("\(envelope.id.uuidString).json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        try? FileManager.default.removeItem(at: envelope.fileURL)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readyURL, withIntermediateDirectories: true)
    }

    private static func resolvedSource(
        for fileURL: URL,
        providedOriginalFilename: String?
    ) -> (fileURL: URL, originalFilename: String?) {
        guard let resolvedFileURL = fileURLPointerTarget(in: fileURL),
              FileManager.default.fileExists(atPath: resolvedFileURL.path)
        else {
            return (fileURL, providedOriginalFilename)
        }

        let provided = sanitizedFilename(providedOriginalFilename)
        if let provided,
           !URL(fileURLWithPath: provided).pathExtension.isEmpty,
           !isGenericFileURLName(provided)
        {
            return (resolvedFileURL, provided)
        }

        return (resolvedFileURL, resolvedFileURL.lastPathComponent)
    }

    private static func fileURLPointerTarget(in fileURL: URL) -> URL? {
        guard (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <= 8_192,
              let data = try? Data(contentsOf: fileURL),
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              )
        else {
            return nil
        }

        return firstFileURL(in: propertyList)
    }

    private static func firstFileURL(in value: Any) -> URL? {
        if let url = value as? URL, url.isFileURL {
            return url
        }

        if let string = value as? String,
           let url = URL(string: string),
           url.isFileURL
        {
            return url
        }

        if let array = value as? [Any] {
            for element in array {
                if let url = firstFileURL(in: element) {
                    return url
                }
            }
        }

        if let dictionary = value as? [AnyHashable: Any] {
            for element in dictionary.values {
                if let url = firstFileURL(in: element) {
                    return url
                }
            }
        }

        return nil
    }

    private static func originalFilename(
        for fileURL: URL,
        providedOriginalFilename: String?
    ) -> String {
        if let filename = sanitizedFilename(providedOriginalFilename) {
            return filename
        }
        if let filename = sanitizedFilename(fileURL.lastPathComponent) {
            return filename
        }
        return "Import"
    }

    private static func fileExtension(for fileURL: URL, originalFilename: String) -> String {
        let originalExtension = URL(fileURLWithPath: originalFilename).pathExtension
        if !originalExtension.isEmpty {
            return originalExtension
        }
        return fileURL.pathExtension
    }

    private static func isGenericFileURLName(_ filename: String) -> Bool {
        let normalized = filename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "datei-url"
            || normalized == "file-url"
            || normalized == "file url"
    }

    private static func sanitizedFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastPathComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !lastPathComponent.isEmpty, lastPathComponent != "." else { return nil }
        return lastPathComponent
    }
}
