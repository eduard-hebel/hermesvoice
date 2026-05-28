import AVFoundation

actor AudioRecorder {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // macOS Voice Processing aktivieren: AGC + Noise Suppression +
        // Echo Cancellation. Bringt 1–2 % WER bei Mikrofonen mit Nebengeräuschen.
        // Wirft, falls die Hardware das nicht unterstützt — dann fallen wir
        // einfach auf raw audio zurück, kein Crash.
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            // Hardware unterstützt es nicht, weiter mit rohem Audio
        }

        let format = input.outputFormat(forBus: 0)

        // In den persistenten Recordings-Ordner schreiben (nicht temp), damit die
        // Aufnahme als Sicherheitsnetz erhalten bleibt und neu transkribiert werden kann.
        let url = RecordingStore.newRecordingURL()

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
            AudioMeter.shared.report(buffer: buffer)
        }

        try engine.start()
        self.engine = engine
        self.file = file
        self.outputURL = url
    }

    func stop() throws -> URL {
        guard let engine, let url = outputURL else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not recording"])
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.file = nil
        self.outputURL = nil
        return url
    }
}
