import Foundation
import AVFoundation

@main struct CratePlayerCheck {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441000)!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100) * 0.1)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let original = try Data(contentsOf: url)
        let player = CratePlayer()
        player.volume = 0
        player.play(path: url.path, title: "Test tone", artist: "Generated locally")
        precondition(player.error == nil && player.isPlaying && player.loaded)
        precondition(abs(player.duration - 10) < 0.01)
        try await Task.sleep(for: .milliseconds(400))
        player.updatePosition()
        let start = player.position
        precondition((player.spectrum.levels.max() ?? 0) > 0.3, "Live audio tap did not receive the playing tone")
        try await Task.sleep(for: .milliseconds(500))
        player.updatePosition()
        let normal = player.position - start
        precondition(normal > 0.35 && normal < 0.7, "Playback clock failed: \(normal)")
        player.rate = 1.5
        try await Task.sleep(for: .milliseconds(200))
        player.updatePosition()
        let fastStart = player.position
        try await Task.sleep(for: .milliseconds(500))
        player.updatePosition()
        let fast = player.position - fastStart
        precondition(fast > normal * 1.25 && fast < normal * 1.8, "Faster playback failed: \(fast) / \(normal)")
        let fastSpectrum = player.spectrum.levels
        let fastBand = fastSpectrum.indices.max(by: { fastSpectrum[$0] < fastSpectrum[$1] })!
        precondition((13...16).contains(fastBand), "Spectrum did not follow the raised pitch: \(fastBand)")
        precondition(abs(player.semitones - 7.01955) < 0.01)
        player.rate = 0.5
        try await Task.sleep(for: .milliseconds(200))
        player.updatePosition()
        let slowStart = player.position
        try await Task.sleep(for: .milliseconds(500))
        player.updatePosition()
        let slow = player.position - slowStart
        precondition(slow > normal * 0.3 && slow < normal * 0.7, "Slower playback failed: \(slow) / \(normal)")
        let slowSpectrum = player.spectrum.levels
        let slowBand = slowSpectrum.indices.max(by: { slowSpectrum[$0] < slowSpectrum[$1] })!
        precondition((8...10).contains(slowBand), "Spectrum did not follow the lowered pitch: \(slowBand)")
        precondition(player.semitones == -12)
        player.toggleMute()
        precondition(player.muted)
        player.volume = 0.2
        precondition(player.muted && player.volume == 0.2)
        player.toggleMute()
        precondition(!player.muted)
        player.volume = 0
        player.toggle()
        let paused = player.position
        try await Task.sleep(for: .milliseconds(150))
        player.updatePosition()
        precondition(!player.isPlaying && player.position == paused)
        player.seek(to: 4)
        precondition(!player.isPlaying && abs(player.position - 4) < 0.01)
        player.toggle()
        precondition(player.isPlaying)
        player.seek(to: -10)
        precondition(player.position == 0)
        player.seek(to: .nan)
        precondition(player.position == 0)
        player.rate = 1
        player.seek(to: 9.8)
        try await Task.sleep(for: .milliseconds(600))
        precondition(!player.isPlaying && player.position == player.duration, "End of track did not stop")
        player.toggle()
        precondition(player.isPlaying && player.position == 0)
        player.stop()
        precondition(!player.isPlaying && player.position == 0)
        let stereoURL = directory.appendingPathComponent("stereo.wav")
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let stereoBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: 96000)!
        stereoBuffer.frameLength = stereoBuffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(stereoBuffer.frameLength) { stereoBuffer.floatChannelData![channel][frame] = 0 }
        }
        do {
            let file = try AVAudioFile(forWriting: stereoURL, settings: stereoFormat.settings)
            try file.write(from: stereoBuffer)
        }
        player.play(path: url.path, title: "First", artist: "")
        player.play(path: stereoURL.path, title: "Replacement", artist: "")
        try await Task.sleep(for: .milliseconds(250))
        player.updatePosition()
        precondition(player.isPlaying && player.title == "Replacement" && abs(player.duration - 2) < 0.01)
        precondition(player.position > 0, "Changed sample rate / channels did not play")
        player.stop()
        player.play(path: directory.appendingPathComponent("missing.wav").path, title: "Missing", artist: "")
        precondition(player.error != nil && !player.isPlaying)
        precondition(CratePlayer.clock(125.9) == "2:05")
        let after = try Data(contentsOf: url)
        precondition(original == after, "Playback modified the source audio")
        if CommandLine.arguments.count > 1 {
            let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
            for audio in try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                let bytes = try Data(contentsOf: audio)
                player.rate = 1
                player.volume = 0
                player.play(path: audio.path, title: audio.lastPathComponent, artist: "Generated fixture")
                precondition(player.error == nil && player.isPlaying && player.duration > 2, "Cannot play \(audio.lastPathComponent): \(player.error ?? "unknown error")")
                try await Task.sleep(for: .milliseconds(200))
                player.updatePosition()
                precondition(player.position > 0, "Playback did not advance: \(audio.lastPathComponent)")
                player.stop()
                let playedBytes = try Data(contentsOf: audio)
                precondition(playedBytes == bytes, "Playback modified \(audio.lastPathComponent)")
                print("Format playback passed: \(audio.lastPathComponent)")
            }
        }
        print("Player checks passed: load, play/pause, seek, 0.5×/1.5× rate, pitch, end/replay, stop, channel/sample-rate switch, invalid path, unchanged source.")
    }
}
