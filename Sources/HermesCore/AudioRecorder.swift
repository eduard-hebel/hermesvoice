import AVFoundation

actor AudioRecorder {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Voice Processing (AGC + Noise Suppression + Echo Cancellation) ist eine
        // macOS-Optimierung. Auf iOS verbiegt es das Eingangs-Format der AVAudioEngine
        // und lässt `installTap` beim Aufnahmestart HART crashen (App fliegt zum
        // Homescreen). Darum NUR auf macOS aktivieren.
        #if os(macOS)
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            // Hardware unterstützt es nicht, weiter mit rohem Audio
        }
        #endif

        // Auf iOS das ECHTE Hardware-Eingangsformat des Input-Node nehmen — exakt das,
        // was `installTap` erwartet (sonst Format-Mismatch → Crash). Auf macOS ist
        // outputFormat == inputFormat, daher identisch.
        let format = input.inputFormat(forBus: 0)

        // In den persistenten Recordings-Ordner schreiben (nicht temp), damit die
        // Aufnahme als Sicherheitsnetz erhalten bleibt und neu transkribiert werden kann.
        let url = RecordingStore.newRecordingURL()

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Kleiner Puffer = ~4× mehr Pegel-Updates/Sekunde → flüssigere, reaktivere Waveform.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
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
