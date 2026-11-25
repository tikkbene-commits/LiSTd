import SwiftUI
import AVFoundation
import Accelerate

// The audio thread writes one snapshot; the display reads it without publishing UI work from the tap.
final class AudioSpectrum: @unchecked Sendable {
    static let size = 2048
    static let bands = 32
    private let transform = try! vDSP.DiscreteFourierTransform<Float>(count: size, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private let window = (0..<size).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(size - 1))) }
    private let lock = NSLock()
    private var snapshot = Array(repeating: Float(0), count: bands)
    /// Raw samples spread across one analysis window, for oscilloscope-style displays.
    static let wavePoints = 96
    private var waveSnapshot = Array(repeating: Float(0), count: wavePoints)

    var wave: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return waveSnapshot
    }

    var levels: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength >= Self.size else { return }
        // Follow the louder channel so a silent or phase-inverted channel cannot hide the spectrum.
        let channel = (0..<Int(buffer.format.channelCount)).max { a, b in
            vDSP.sumOfSquares(UnsafeBufferPointer(start: channels[a], count: Self.size)) <
            vDSP.sumOfSquares(UnsafeBufferPointer(start: channels[b], count: Self.size))
        } ?? 0
        let samples = (0..<Self.size).map { channels[channel][$0] * window[$0] }
        let output = transform.transform(real: samples, imaginary: Array(repeating: 0, count: Self.size))
        let magnitudes = (0..<(Self.size / 2)).map { hypot(output.real[$0], output.imaginary[$0]) / Float(Self.size / 2) }
        let nyquist = buffer.format.sampleRate / 2
        let high = min(16000, nyquist)
        let values: [Float] = (0..<Self.bands).map { band in
            let lowFrequency = 40 * pow(high / 40, Double(band) / Double(Self.bands))
            let highFrequency = 40 * pow(high / 40, Double(band + 1) / Double(Self.bands))
            let low = min(magnitudes.count - 1, max(1, Int(lowFrequency / buffer.format.sampleRate * Double(Self.size))))
            let upper = min(magnitudes.count, max(low + 1, Int(highFrequency / buffer.format.sampleRate * Double(Self.size))))
            let peak = magnitudes[low..<upper].max() ?? 0
            return min(1, max(0, (20 * log10(max(peak, 0.000001)) + 65) / 65))
        }
        let wave = (0..<Self.wavePoints).map { channels[channel][$0 * Self.size / Self.wavePoints] }
        lock.lock()
        snapshot = values
        waveSnapshot = wave
        lock.unlock()
    }
}

struct SpectrumDisplay: View {
    let analyzer: AudioSpectrum
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !playing || reduceMotion)) { _ in
            let levels = playing ? analyzer.levels : Array(repeating: 0, count: AudioSpectrum.bands)
            SpectrumBars(levels: levels)
        }.accessibilityLabel(playing ? "Live audio spectrum" : "Audio spectrum paused")
    }
}

struct SpectrumBars: View {
    let levels: [Float]
    var body: some View {
        Canvas { context, size in
            let rows = 16
            let height = size.height * 0.83
            let cellWidth = size.width / CGFloat(max(1, levels.count))
            let cellHeight = height / CGFloat(rows)
            for (band, level) in levels.enumerated() {
                for row in 0..<min(rows, max(0, Int(level * Float(rows)))) {
                    let color: Color = row < 7 ? .green : row < 11 ? .yellow : row < 14 ? .orange : .red
                    let rect = CGRect(x: CGFloat(band) * cellWidth, y: height - CGFloat(row + 1) * cellHeight,
                                      width: max(0.2, cellWidth - 0.4), height: max(0.2, cellHeight - 0.35))
                    context.fill(Path(rect), with: .color(color))
                    let reflection = CGRect(x: rect.minX, y: height + CGFloat(row) * cellHeight * 0.18,
                                            width: rect.width, height: rect.height * 0.18)
                    context.fill(Path(reflection), with: .color(color.opacity(0.18)))
                }
            }
        }
    }
}
