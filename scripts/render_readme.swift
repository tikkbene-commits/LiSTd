import SwiftUI
import AppKit
import AVFoundation

// Render real player views with generated, silent-to-the-output example audio.
@main struct ReadmePreviews {
    @MainActor static func write<V: View>(_ view: V, to path: URL, width: Int, height: Int) throws {
        // NSHostingView includes the native sliders/text fields ImageRenderer omits.
        let host = NSHostingView(rootView: view.frame(width: CGFloat(width), height: CGFloat(height)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        precondition(bitmap.pixelsWide >= width && bitmap.pixelsHigh >= height)
        try png.write(to: path)
    }

    /// Like `write`, but keeps the view on screen for several frames so live visuals
    /// (the Limehead oscilloscope trails) have history when the picture is taken.
    @MainActor static func writeLive<V: View>(_ view: V, to path: URL, width: Int, height: Int, frames: Int) async throws {
        let host = NSHostingView(rootView: view.frame(width: CGFloat(width), height: CGFloat(height)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        var bitmap: NSBitmapImageRep?
        for _ in 0..<frames {
            try await Task.sleep(for: .milliseconds(70))
            host.layoutSubtreeIfNeeded()
            guard let next = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: next)
            bitmap = next
        }
        guard let bitmap, let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: path)
    }

    @MainActor static func main() async throws {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let a = CratePlayer(), b = CratePlayer()
        for (index, player) in [a, b].enumerated() {
            let bpm = index == 0 ? 128.0 : 126.0
            let rate = 8000.0
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960000)!
            buffer.frameLength = buffer.frameCapacity
            for frame in 0..<Int(buffer.frameLength) {
                let time = Double(frame) / rate
                let beat = time.truncatingRemainder(dividingBy: 60 / bpm)
                buffer.floatChannelData![0][frame] = Float(
                    sin(beat * 2 * .pi * 85) * exp(-beat * 45) * 0.7
                    + sin(time * 2 * .pi * 220) * (0.08 + 0.04 * sin(time * 0.7)))
            }
            let path = temporary.appendingPathComponent("example-\(index).wav")
            do {
                let file = try AVAudioFile(forWriting: path, settings: format.settings)
                try file.write(from: buffer)
            }
            player.volume = 0
            player.play(path: path.path, title: index == 0 ? "After Hours" : "Night Drive",
                        artist: "Example track", autoplay: false, bpm: bpm)
            precondition(player.error == nil && player.loaded && !player.isPlaying)
            player.volume = 0.5
            player.beatCue = 0
            player.analysisNote = "Example beat grid · check by ear"
            player.seek(to: index == 0 ? 42 : 28)
        }
        for _ in 0..<100 {
            if !a.waveform.isEmpty && !b.waveform.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(!a.waveform.isEmpty && !b.waveform.isEmpty)
        try write(BoomboxPlayer(player: a, showTracks: {}).padding(16),
                  to: output.appendingPathComponent("amped.png"), width: 960, height: 579)
        try write(TechnicalPlayer(a: a, b: b, analyze: { _ in }).preferredColorScheme(.dark),
                  to: output.appendingPathComponent("signal.png"), width: 1080, height: 720)

        // Limehead · Mix (alpha): both example decks playing silently (muted) so the screen
        // shows a live trace; example playlist rows; crossfader slightly toward deck B.
        let mixer = LimeMixer()
        mixer.attach(a, b)
        mixer.crossfade = 0.58
        a.toggleMute(); b.toggleMute()
        a.seek(to: 12); b.seek(to: 7)
        a.toggle(); b.toggle()
        precondition(a.isPlaying && b.isPlaying)
        func example(_ id: String, _ title: String, _ artist: String, _ bpm: Double, _ path: String) -> LibraryTrack {
            let json = #"{"id":"\#(id)","artist":"\#(artist)","title":"\#(title)","genre":"Example","vibe":"","bpm":\#(bpm),"path":"\#(path)"}"#
            return try! JSONDecoder().decode(LibraryTrack.self, from: Data(json.utf8))
        }
        let tracks = [example("1", "After Hours", "Example track", 128, a.path), example("2", "Night Drive", "Example track", 126, b.path),
                      example("3", "Slow Burn", "Example track", 122, "/example/3"), example("4", "Glass Rooms", "Example track", 124, "/example/4"),
                      example("5", "Low Tide", "Example track", 118, "/example/5"), example("6", "Paper Moon", "Example track", 120, "/example/6")]
        let limehead = ZStack {
            LinearGradient(colors: [Color(red: 0.62, green: 0.75, blue: 0.89), Color(red: 0.42, green: 0.60, blue: 0.80)], startPoint: .top, endPoint: .bottom)
            LimePlayer(a: a, b: b, mixer: mixer, focusB: .constant(false), tracks: tracks,
                       load: { _, _ in }, step: { _, _, _ in }, showTracks: {}).padding(14)
        }
        try await writeLive(limehead, to: output.appendingPathComponent("limehead.png"), width: 1120, height: 620, frames: 24)
        print("Rendered Amped, Signal and Limehead previews with example data; no account or collection accessed.")
    }
}
