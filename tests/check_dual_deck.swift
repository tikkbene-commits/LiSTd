import Foundation
import AVFoundation
import SwiftUI
import AppKit

@main struct DualDeckCheck {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        func tone(_ hz: Double) throws -> URL {
            let url = directory.appendingPathComponent("tone-\(hz).wav")
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 20)!
            buffer.frameLength = buffer.frameCapacity
            for frame in 0..<Int(buffer.frameLength) {
                buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * hz / 44100) * 0.2)
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        let low = try tone(80)
        let middle = try tone(1000)
        let high = try tone(10000)
        let before = try Data(contentsOf: low)
        let a = CratePlayer(), b = CratePlayer()
        a.volume = 0; b.volume = 0
        a.play(path: low.path, title: "A", artist: "Fixture", autoplay: false, bpm: 120)
        b.play(path: middle.path, title: "B", artist: "Fixture", autoplay: false, bpm: 125)
        precondition(a.loaded && b.loaded && !a.isPlaying && !b.isPlaying)
        a.seek(to: 1); a.setBeatCue(); a.seek(to: 5.15)
        b.seek(to: 0.2); b.setBeatCue(); b.seek(to: 7)
        a.rate = 1.04
        b.sync(to: a)
        precondition(!b.isPlaying && abs(b.effectiveBPM - a.effectiveBPM) < 0.001)
        func phase(_ player: CratePlayer) -> Double {
            let beat = (player.position - player.beatCue!) * player.bpm / 60
            return beat - floor(beat)
        }
        func phaseDistance() -> Double {
            let distance = abs(phase(a) - phase(b))
            return min(distance, 1 - distance)
        }
        precondition(phaseDistance() < 0.001, "Paused beat phase did not align")
        let unchangedB = (b.path, b.position, b.rate, b.volume, b.bass, b.beatCue)
        a.rate = 0.9; a.seek(to: 4.31)
        a.sync(to: b)
        precondition(!a.isPlaying && !b.isPlaying && phaseDistance() < 0.001, "Reverse paused sync failed")
        precondition(abs(a.effectiveBPM - b.effectiveBPM) < 0.001)
        precondition(b.path == unchangedB.0 && b.position == unchangedB.1 && b.rate == unchangedB.2 && b.volume == unchangedB.3 && b.bass == unchangedB.4 && b.beatCue == unchangedB.5, "Reverse sync modified master B")
        let time = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.15)
        a.start(atHostTime: time); b.start(atHostTime: time)
        precondition(abs(a.currentPosition - a.position) < 0.0001, "Scheduled playback clock advanced before its host start")
        precondition(abs(a.position(atHostTime: time + AVAudioTime.hostTime(forSeconds: 1)) - (a.position + a.rate)) < 0.001)
        try await Task.sleep(for: .milliseconds(600))
        a.updatePosition(); b.updatePosition()
        precondition(a.isPlaying && b.isPlaying && a.position > 4.4 && b.position > 7)
        precondition(phaseDistance() < 0.10, "Shared host-time start lost phase: \(phaseDistance())")
        b.seek(to: b.position + 0.2)
        b.sync(to: a)
        try await Task.sleep(for: .milliseconds(700))
        a.updatePosition(); b.updatePosition()
        precondition(phaseDistance() < 0.10, "Running sync failed: \(phaseDistance())")
        a.seek(to: a.position + 0.2)
        let masterRate = b.rate, masterStart = b.position
        a.sync(to: b)
        precondition(b.rate == masterRate && b.position == masterStart && b.isPlaying, "Running reverse sync changed B")
        try await Task.sleep(for: .milliseconds(700))
        a.updatePosition(); b.updatePosition()
        precondition(phaseDistance() < 0.10, "Running reverse sync lost beat phase")
        precondition(!a.waveform.isEmpty && (a.waveform.max() ?? 0) > 0.19, "Actual waveform was not read")
        a.toggle()
        let renderer = ImageRenderer(content: SignalWaveform(player: a, overview: false).frame(width: 800, height: 44))
        guard let image = renderer.cgImage else { fatalError("Signal waveform did not render") }
        let pixels = NSBitmapImageRep(cgImage: image)
        var greenPixels = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent > 0.5 && color.greenComponent > color.redComponent * 1.5 {
                    greenPixels += 1
                    precondition((10..<34).contains(y), "Detail waveform exceeds its reduced amplitude")
                }
            }
        }
        precondition(greenPixels > 500, "Filled waveform is missing")
        try pixels.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".music-sorter/build/signal-waveform-preview.png"))
        a.toggle()
        let aPosition = a.position
        b.stop()
        try await Task.sleep(for: .milliseconds(200))
        a.updatePosition()
        precondition(a.isPlaying && a.position > aPosition && !b.isPlaying, "Decks are not independent")
        a.stop()
        func pulses(_ bpm: Double, cue: Double) throws -> URL {
            let url = directory.appendingPathComponent("pulses-\(bpm).wav")
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 24)!
            buffer.frameLength = buffer.frameCapacity
            let period = 60 / bpm
            for frame in 0..<Int(buffer.frameLength) {
                let time = Double(frame) / 44100 - cue
                let phase = time - floor(time / period) * period
                buffer.floatChannelData![0][frame] = phase < 0.10 ? Float(sin(2 * .pi * 90 * phase) * exp(-phase * 70) * 0.7) : 0
            }
            let audio = try AVAudioFile(forWriting: url, settings: format.settings)
            try audio.write(from: buffer)
            return url
        }
        let pulseA = try pulses(120, cue: 0.2), pulseB = try pulses(123.45, cue: 0.173)
        a.rate = 1.04
        a.play(path: pulseA.path, title: "Pulse A", artist: "Fixture", bpm: 120)
        a.beatCue = 0.2; a.seek(to: 1.1)
        b.play(path: pulseB.path, title: "Pulse B", artist: "Fixture", autoplay: false, bpm: 123.45)
        b.beatCue = 0.173; b.seek(to: 5.14)
        try await Task.sleep(for: .milliseconds(250))
        b.sync(to: a)
        try await Task.sleep(for: .milliseconds(300))
        var edgesA: [Double] = [], edgesB: [Double] = []
        var wasA = true, wasB = true
        for _ in 0..<300 {
            let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            let onA = (a.spectrum.levels.max() ?? 0) > 0.35
            let onB = (b.spectrum.levels.max() ?? 0) > 0.35
            if onA && !wasA { edgesA.append(now) }
            if onB && !wasB { edgesB.append(now) }
            wasA = onA; wasB = onB
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(edgesA.count >= 4 && edgesB.count >= 4, "Audio taps did not detect generated beat pulses")
        let beatPeriod = 60 / a.effectiveBPM
        func renderedPhase(_ edges: [Double]) -> Double {
            let angles = edges.map { ($0 - edgesA[0]) / beatPeriod * 2 * Double.pi }
            let x = angles.map { cos($0) }.reduce(0, +)
            let y = angles.map { sin($0) }.reduce(0, +)
            // The spectrum snapshot can miss a pulse; compare phase across all detected beats.
            precondition(hypot(x, y) / Double(edges.count) > 0.8, "Rendered pulse tempo is unstable")
            return atan2(y, x)
        }
        let angle = renderedPhase(edgesA) - renderedPhase(edgesB)
        let difference = abs(atan2(sin(angle), cos(angle))) / (2 * .pi) * beatPeriod
        precondition(difference < 0.065, "Actual rendered beat phases differ by \(difference)s")
        a.stop(); b.stop()
        for (index, url) in [low, middle, high].enumerated() {
            a.resetEQ()
            a.rate = 1
            a.play(path: url.path, title: "EQ", artist: "Fixture")
            try await Task.sleep(for: .milliseconds(450))
            let neutral = a.spectrum.levels.max() ?? 0
            if index == 0 { a.bass = -24 }
            if index == 1 { a.mid = -24 }
            if index == 2 { a.high = -24 }
            try await Task.sleep(for: .milliseconds(450))
            let cut = a.spectrum.levels.max() ?? 0
            precondition(neutral - cut > 0.22, "EQ band \(index) did not attenuate actual audio: \(neutral) → \(cut)")
            precondition(b.bass == 0 && b.mid == 0 && b.high == 0, "EQ leaked to the other deck")
            a.stop()
        }
        a.resetEQ()
        precondition(a.bass == 0 && a.mid == 0 && a.high == 0)
        a.bpm = 250; a.beatCue = 0; b.bpm = 40; b.beatCue = 0
        let oldRate = b.rate
        b.sync(to: a)
        precondition(b.error != nil && b.rate == oldRate, "Out-of-range sync was silently clamped")
        let unchangedA = a.rate
        a.sync(to: b)
        precondition(a.error != nil && a.rate == unchangedA, "Reverse out-of-range sync was silently clamped")
        b.bpm = .nan
        precondition(!b.canSync)
        let after = try Data(contentsOf: low)
        precondition(before == after, "Deck playback changed the source file")
        print("Dual-deck checks passed: scheduled clock, rendered pulse beatmatch, compact waveform render, simultaneous playback, tempo/phase sync, independent stop, actual three-band EQ attenuation, reset, invalid BPM/rate, source preservation.")
    }
}
