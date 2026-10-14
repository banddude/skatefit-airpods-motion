import AVFoundation
import Foundation

/// Explicit user-triggered audio wake-up. AirPods motion may stay dormant while
/// the earbud is off-ear even though CMHeadphoneMotionManager is active.
/// The user selects the AirPods audio route using the system route picker.
@MainActor
final class AirPodAudioWake {
    private var player: AVAudioPlayer?

    static func audioOutputDescription() -> String {
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs
        guard !ports.isEmpty else { return "No active audio output" }
        return ports.map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
    }

    /// Play a short quiet sine-wave tone to wake the currently selected audio route.
    func wake() throws -> String {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        let output = Self.audioOutputDescription()
        let data = Self.makeToneWAV()
        let sound = try AVAudioPlayer(data: data)
        sound.volume = 0.22
        sound.prepareToPlay()
        guard sound.play() else {
            return "Audio could not start. Current route: \(output)"
        }
        player = sound
        return "Played short wake tone to \(output). Check for AirPod readings."
    }

    nonisolated static func makeToneWAV() -> Data {
        let rate: UInt32 = 22_050
        let sampleCount = Int(rate) / 2
        let rawBytes = UInt32(sampleCount * 2)
        var wave = Data()
        func chars(_ text: String) { wave.append(contentsOf: text.utf8) }
        func u16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) }
        }
        chars("RIFF")
        u32(36 + rawBytes)
        chars("WAVEfmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(rate)
        u32(rate * 2)
        u16(2)
        u16(16)
        chars("data")
        u32(rawBytes)
        for n in 0..<sampleCount {
            let amplitude = sin(Double(n) * 2 * Double.pi * 520 / Double(rate))
            let sample = Int16((amplitude * 8500).rounded())
            u16(UInt16(bitPattern: sample))
        }
        return wave
    }
}
