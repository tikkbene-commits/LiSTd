import SwiftUI
import AppKit
import AVFoundation

// Drives the real Cyber · Lilac controls with mouse events at the reference
// coordinates, using a silent generated file and a muted player.
@main struct CyberPlayerCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cyber-check-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 20)!
            buffer.frameLength = 44100 * 20   // 20 seconds of silence
            try file.write(from: buffer)
        }

        let player = CratePlayer()
        player.toggleMute()
        var steps: [String] = []
        var drawerToggles = 0
        let size = CGSize(width: CyberGeometry.width, height: CyberGeometry.height)
        let host = NSHostingView(rootView: CyberPlayer(player: player, canStep: true,
                                                       step: { steps.append("\($0) \($1)") },
                                                       showTracks: { drawerToggles += 1 })
            .frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -4000, y: -4000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()

        func pump(_ seconds: Double = 0.08) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            // AppKit window coordinates run bottom-up; the reference runs top-down.
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x, y: size.height - point.y),
                                           modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        func click(_ x: CGFloat, _ y: CGFloat) { send(.leftMouseDown, CGPoint(x: x, y: y)); send(.leftMouseUp, CGPoint(x: x, y: y)); pump() }
        func drag(from: CGPoint, to: CGPoint) {
            send(.leftMouseDown, from); pump(0.03)
            for step in 1...6 {
                let f = CGFloat(step) / 6
                send(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)); pump(0.02)
            }
            send(.leftMouseUp, to); pump()
        }
        pump(0.3)

        // Play with nothing loaded starts the first collection track.
        click(343.5, 251)
        precondition(steps == ["1 true"], "Play on an empty deck must load the first collection track: \(steps)")

        player.play(path: url.path, title: "Lilac Check", artist: "Generated silence", autoplay: false)
        pump(0.3)
        precondition(player.loaded && !player.isPlaying)
        click(343.5, 251); precondition(player.isPlaying, "Play button")
        click(309, 257.5); precondition(!player.isPlaying, "Pause tile")
        click(405, 268.5); precondition(abs(player.position - 10) < 0.5, "Forward 10 seconds: \(player.position)")
        click(282, 268.5); precondition(player.position < 0.5, "Back 10 seconds: \(player.position)")
        click(343.5, 251); click(378.5, 257.5)
        precondition(!player.isPlaying && player.position == 0, "Stop tile")
        click(424.5, 285); click(265, 288)
        precondition(steps == ["1 true", "1 false", "-1 false"], "Next/previous tiles: \(steps)")

        click(381, 190); precondition(drawerToggles == 1, "Playlist button toggles Tracks & imports")
        let spectrum = player.spectrumVisible
        click(267, 166); precondition(player.spectrumVisible == !spectrum, "Eye button toggles the spectrum")
        click(269.5, 177); click(269.5, 177); precondition(abs(player.rate - 1.02) < 0.0001, "Faster arrow")
        click(260.5, 177); precondition(abs(player.rate - 1.01) < 0.0001, "Slower arrow")
        click(46, 162.5); precondition(player.rate == 1, "Logo resets speed")

        player.volume = 0.7
        click(401, 40); precondition(abs(player.volume - 0.75) < 0.0001, "Volume + mark")
        click(521, 140); precondition(abs(player.volume - 0.7) < 0.0001, "Volume − mark")
        drag(from: CyberGeometry.volumePoint(0.7), to: CyberGeometry.volumePoint(0.2))
        precondition(abs(player.volume - 0.2) < 0.03, "Dragging the ball sets volume: \(player.volume)")
        click(523, 157); precondition(!player.muted, "Speaker unmutes")
        click(523, 157); precondition(player.muted, "Speaker mutes again")

        // Seek: drag the knob to the middle of the groove (20 s file → about 10 s).
        let middle = (CyberGeometry.seekStart + CyberGeometry.seekEnd) / 2
        drag(from: CGPoint(x: CyberGeometry.seekStart, y: CyberGeometry.seekY), to: CGPoint(x: middle, y: CyberGeometry.seekY))
        precondition(abs(player.position - 10) < 0.6, "Seek knob drag: \(player.position)")

        // Keyboard: after clicking a control it takes focus, and arrow keys adjust it.
        func key(_ code: UInt16, _ characters: String) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, characters: characters,
                                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
            }
            pump()
        }
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        player.volume = 0.5
        click(CyberGeometry.volumePoint(0.5).x, CyberGeometry.volumePoint(0.5).y)
        key(126, up)
        precondition(abs(player.volume - 0.55) < 0.011, "Up arrow raises volume when the ring is focused: \(player.volume)")
        let before = player.position
        click(CyberGeometry.seekStart + (CyberGeometry.seekEnd - CyberGeometry.seekStart) * CGFloat(before / player.duration), CyberGeometry.seekY)
        let clicked = player.position
        key(124, right)
        precondition(abs(player.position - (clicked + 5)) < 0.6, "Right arrow seeks +5 s when the knob is focused: \(clicked) → \(player.position)")

        // Snapshot of the live controls over the artwork for visual review.
        player.seek(to: 7)
        pump(0.4)
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? FileManager.default.createDirectory(atPath: ".music-sorter/build", withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".music-sorter/build/cyber-live.png"))
        }
        print("Cyber controls passed: play/pause/stop, ±10 s, previous/next, playlist, spectrum eye, speed arrows and reset, volume marks/drag, mute, seek drag and arrow keys on the focused ring/knob.")
    }
}
