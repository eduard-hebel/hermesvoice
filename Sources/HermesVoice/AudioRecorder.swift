import AVFoundation

actor AudioRecorder {
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var outputURL: URL?

    func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermesvoice-\(UUID().uuidString).wav")

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
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
