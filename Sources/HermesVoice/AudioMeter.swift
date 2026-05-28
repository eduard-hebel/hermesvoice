import Foundation
import Observation
import AVFoundation

/// Publishes the current audio RMS level for the HUD.
/// Thread-safe report() can be called from any context (typically the
/// audio engine's tap callback) and dispatches onto the main actor.
@MainActor
@Observable
final class AudioMeter {
    static let shared = AudioMeter()
    private(set) var level: Float = 0.0

    private init() {}

    func reset() { level = 0.0 }

    nonisolated func report(buffer: AVAudioPCMBuffer) {
        let rms = Self.computeRMS(buffer)
        Task { @MainActor in
            // Glätten damit der Pegel nicht zu sehr springt.
            self.level = self.level * 0.6 + rms * 0.4
        }
    }

    nonisolated private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Loud-ish speech ≈ 0.1–0.3 RMS, normalize on a soft curve
        return min(1.0, rms * 6.0)
    }
}
