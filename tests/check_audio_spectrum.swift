import SwiftUI
import AVFoundation

@main struct AudioSpectrumCheck {
    @MainActor static func main() {
        let analyzer = AudioSpectrum()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(AudioSpectrum.size))!
        buffer.frameLength = buffer.frameCapacity
        func fill(_ frequency: Double, amplitude: Double = 0.5) {
            for frame in 0..<AudioSpectrum.size {
                buffer.floatChannelData![0][frame] = 0
                buffer.floatChannelData![1][frame] = Float(amplitude * sin(Double(frame) * 2 * .pi * frequency / 44100))
            }
            analyzer.process(buffer)
        }
        fill(0)
        precondition(analyzer.levels.allSatisfy { $0 == 0 }, "Silence must produce no bars")
        for frequency in [220.0, 1000, 4000] {
            fill(frequency)
            let levels = analyzer.levels
            let peak = levels.indices.max(by: { levels[$0] < levels[$1] })!
            let expected = Int(log(frequency / 40) / log(16000.0 / 40) * Double(AudioSpectrum.bands))
            precondition(abs(peak - expected) <= 1, "Wrong frequency band for \(frequency): \(peak), expected \(expected)")
            precondition(levels[peak] > 0.6 && levels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        }
        fill(1000)
        let loud = analyzer.levels.max()!
        fill(1000, amplitude: 0.005)
        precondition(analyzer.levels.max()! < loud - 0.4, "Bars must follow actual audio level")
        let bars = SpectrumBars(levels: (0..<32).map { Float($0 + 1) / 32 }).frame(width: 640, height: 160).background(.black)
        let renderer = ImageRenderer(content: bars)
        guard let rendered = renderer.cgImage else { fatalError("Spectrum did not render") }
        let pixels = NSBitmapImageRep(cgImage: rendered)
        try! pixels.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".music-sorter/build/spectrum-preview.png"))
        print("Spectrum checks passed: silence, 220/1000/4000 Hz, right-channel audio, amplitude response, bounds and LED render.")
    }
}
