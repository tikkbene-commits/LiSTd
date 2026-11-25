import SwiftUI
import AppKit
import AVFoundation

// Limehead · Mix: renders the artwork and checks landmark colours at the reference's
// own coordinates, then drives the real controls with mouse events using silent
// generated files and muted decks.
@main struct LimeheadCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        typealias G = LimeGeometry

        // MARK: Artwork landmarks
        let renderer = ImageRenderer(content: LimeArtwork().frame(width: G.width, height: G.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { fatalError("Limehead artwork did not render") }
        precondition(image.width == 935 && image.height == 498)
        let pixels = NSBitmapImageRep(cgImage: image)
        func rgb(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            let c = pixels.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        func green(_ x: Int, _ y: Int, _ what: String) {
            let c = rgb(x, y)
            precondition(c.a > 0.9 && c.g > c.r * 1.25 && c.g > c.b * 1.5, "\(what) should be lime green at \(x),\(y): \(c)")
        }
        green(520, 78, "Top of the head")
        green(470, 395, "Nose")
        green(200, 119, "Left wing bevel")
        green(735, 119, "Right wing bevel")
        let screen = rgb(470, 190)
        precondition(screen.r > 0.4 && screen.r > screen.g * 3, "Screen should be red: \(screen)")
        let socket = rgb(410, 346)
        precondition(socket.r + socket.g + socket.b < 0.35, "Eye socket should be near black: \(socket)")
        let panel = rgb(150, 210)
        precondition(panel.g > panel.r * 1.5 && panel.g < 0.5, "Mixer panel should be dark green: \(panel)")
        let cone = rgb(48, 162)
        precondition(abs(cone.r - cone.b) < 0.12 && cone.r > 0.6, "Speaker cone should be silver: \(cone)")
        let purple = rgb(395, 54)
        precondition(purple.r > purple.g * 1.1 && purple.b > purple.g * 1.1, "Transport button should be purple: \(purple)")
        precondition(rgb(2, 2).a < 0.05 && rgb(932, 495).a < 0.05, "Corners must stay transparent")
        try? FileManager.default.createDirectory(atPath: ".music-sorter/build", withIntermediateDirectories: true)
        try pixels.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".music-sorter/build/limehead-preview.png"))

        // Constant-power crossfade.
        let centre = LimeMixer.gains(0.5)
        precondition(abs(centre.a - centre.b) < 1e-9 && abs(centre.a - 0.7071) < 0.001, "Centre gains: \(centre)")
        precondition(LimeMixer.gains(0).b < 1e-9 && abs(LimeMixer.gains(0).a - 1) < 1e-9, "Hard left plays only deck A")
        precondition(LimeMixer.gains(1).a < 1e-9, "Hard right plays only deck B")

        // MARK: Live controls
        func silence(_ name: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("limehead-\(name)-\(UUID().uuidString).wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 20)!
            buffer.frameLength = 44100 * 20
            try file.write(from: buffer)
            return url
        }
        let urlA = try silence("a"), urlB = try silence("b")
        defer { try? FileManager.default.removeItem(at: urlA); try? FileManager.default.removeItem(at: urlB) }
        func track(_ id: String, _ url: URL) -> LibraryTrack {
            let json = #"{"id":"\#(id)","artist":"Check","title":"Track \#(id)","genre":"Test","vibe":"","bpm":124,"path":"\#(url.path)"}"#
            return try! JSONDecoder().decode(LibraryTrack.self, from: Data(json.utf8))
        }
        let tracks = [track("A", urlA), track("B", urlB)]

        let a = CratePlayer(), b = CratePlayer()
        a.toggleMute(); b.toggleMute()
        let mixer = LimeMixer()
        mixer.attach(a, b)
        var focusB = false
        var steps: [String] = []
        var drawer = 0
        let size = CGSize(width: G.width, height: G.height)
        let view = LimePlayer(a: a, b: b, mixer: mixer, focusB: Binding(get: { focusB }, set: { focusB = $0 }), tracks: tracks,
                              load: { deck, t in deck.play(path: t.path, title: t.title, artist: t.artist, autoplay: false) },
                              step: { deck, offset, play in steps.append("\(deck === a ? "A" : "B") \(offset) \(play)") },
                              showTracks: { drawer += 1 })
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -4000, y: -4000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()

        func pump(_ seconds: Double = 0.08) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x, y: size.height - point.y),
                                           modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        func click(_ p: CGPoint) { send(.leftMouseDown, p); send(.leftMouseUp, p); pump() }
        func drag(from: CGPoint, to: CGPoint) {
            send(.leftMouseDown, from); pump(0.03)
            for step in 1...6 {
                let f = CGFloat(step) / 6
                send(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)); pump(0.02)
            }
            send(.leftMouseUp, to); pump()
        }
        pump(0.3)

        // Empty deck: play loads the first collection track into the focused deck.
        click(G.playPause)
        precondition(steps == ["A 1 true"], "Play on an empty deck A: \(steps)")

        // Playlist: first row loads into deck A; the dropdown switches the target to deck B.
        let firstRow = CGPoint(x: G.list.midX, y: G.list.minY + 8)
        click(firstRow); pump(0.3)
        precondition(a.path == urlA.path && !a.isPlaying, "Playlist row loads deck A paused")
        click(CGPoint(x: G.dropdown.midX, y: G.dropdown.midY))
        click(CGPoint(x: G.list.midX, y: G.list.minY + 8 + 17)); pump(0.3)
        precondition(b.path == urlB.path, "Second row loads deck B after switching the dropdown")

        // Head focus: the gold/blue pill buttons pick which deck the head drives.
        click(G.playPause); precondition(a.isPlaying && !b.isPlaying, "Head transport drives deck A")
        click(G.focusB); precondition(focusB, "Blue button focuses deck B")
        click(G.playPause); precondition(b.isPlaying, "Head transport now drives deck B")
        click(G.stop); precondition(!b.isPlaying && b.position == 0, "Stop deck B")
        click(G.next); click(G.previous)
        precondition(steps.suffix(2) == ["B 1 false", "B -1 false"], "Next/previous step deck B: \(steps)")
        click(G.focusA); precondition(!focusB, "Gold button focuses deck A")
        let spectrum = a.spectrumVisible
        click(G.visualiser); precondition(a.spectrumVisible == !spectrum, "Asterisk toggles the visualiser")
        click(G.drawerIcon); precondition(drawer == 1, "Drawer icon toggles Tracks & imports")

        // Seek deck A to about the middle of the 20 s file.
        let middle = (G.seekStart + G.seekEnd) / 2
        drag(from: CGPoint(x: G.seekStart, y: G.seekY), to: CGPoint(x: middle, y: G.seekY))
        precondition(abs(a.position - 10) < 0.7, "Seek drag: \(a.position)")

        // Mixer: crossfader hard left silences B, hard right silences A.
        drag(from: CGPoint(x: (G.crossfade.from.x + G.crossfade.to.x) / 2, y: 144), to: G.crossfade.from)
        precondition(mixer.crossfade == 0 && b.volume < 0.001 && a.volume > 0.6, "Crossfader left: \(mixer.crossfade) A \(a.volume) B \(b.volume)")
        drag(from: G.crossfade.from, to: G.crossfade.to)
        precondition(mixer.crossfade == 1 && a.volume < 0.001 && b.volume > 0.6, "Crossfader right: \(mixer.crossfade)")
        drag(from: G.master.to, to: CGPoint(x: (G.master.from.x + G.master.to.x) / 2, y: 144))
        precondition(abs(mixer.master - 0.5) < 0.051 && abs(b.volume - mixer.master * mixer.levelB) < 0.01, "Master: \(mixer.master) B \(b.volume)")

        // Deck faders: A level to the bottom, B pitch to the top, A low EQ fully cut.
        drag(from: CGPoint(x: G.faderX[0], y: G.faderTop), to: CGPoint(x: G.faderX[0], y: G.faderBottom))
        precondition(mixer.levelA == 0 && a.volume == 0, "Deck A level fader: \(mixer.levelA)")
        drag(from: CGPoint(x: G.faderX[6], y: (G.faderTop + G.faderBottom) / 2), to: CGPoint(x: G.faderX[6], y: G.faderTop))
        precondition(abs(b.rate - 1.08) < 0.0001, "Deck B pitch fader: \(b.rate)")
        drag(from: CGPoint(x: G.faderX[2], y: G.faderTop), to: CGPoint(x: G.faderX[2], y: G.faderBottom))
        precondition(a.bass == -24, "Deck A low EQ fader: \(a.bass)")

        click(G.reset)
        precondition(mixer.crossfade == 0.5 && mixer.levelA == 0.85 && b.rate == 1 && a.bass == 0, "Reset restores the mix")

        // Wings: the wing's X hides the mixer and the mixer icon brings it back.
        click(G.leftWingClose); pump()
        drag(from: CGPoint(x: G.faderX[0], y: G.faderTop), to: CGPoint(x: G.faderX[0], y: G.faderBottom))
        precondition(mixer.levelA == 0.85, "A hidden mixer must not respond")
        click(G.mixerIcon); pump()
        drag(from: CGPoint(x: G.faderX[0], y: G.faderTop), to: CGPoint(x: G.faderX[0], y: G.faderBottom))
        precondition(mixer.levelA == 0, "Mixer icon reopens the mixer")

        mixer.detach()
        precondition(a.volume == mixer.master && b.volume == mixer.master, "Leaving the skin restores deck volumes")
        print("Limehead checks passed")
    }
}
