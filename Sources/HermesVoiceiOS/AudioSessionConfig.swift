import AVFoundation

/// iOS-spezifische AVAudioSession-Verwaltung — auf dem Mac existiert das nicht
/// (dort startet AudioRecorder die AVAudioEngine ohne Session). Auf iOS MUSS die
/// Session vor der Aufnahme aktiviert werden, sonst liefert das Mikro nichts.
enum AudioSessionConfig {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Mikrofon-Berechtigung sicherstellen (iOS 17+ AVAudioApplication-API).
    static func ensurePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        @unknown default:
            return false
        }
    }
}
