import SwiftUI
import AppKit

final class PitchFaderCell: NSSliderCell {
    var scale: CGFloat = 1
    override func drawBar(inside rect: NSRect, flipped: Bool) {}
    override func drawKnob(_ knobRect: NSRect) {
        let rect = NSRect(x: knobRect.midX - 5 * scale, y: knobRect.midY - 3 * scale, width: 10 * scale, height: 6 * scale)
        let knob = NSBezierPath(roundedRect: rect, xRadius: 3 * scale, yRadius: 3 * scale)
        NSGradient(starting: .white, ending: .gray)?.draw(in: knob, angle: -90)
        NSColor.black.setStroke()
        knob.lineWidth = 0.6 * scale
        knob.stroke()
    }
}

// A native vertical slider keeps mouse tracking aligned with the narrow skin slot.
struct VerticalPitchSlider: NSViewRepresentable {
    @Binding var value: Double
    var scale: CGFloat = 1
    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = TrackingSlider(frame: NSRect(x: 0, y: 0, width: 14 * scale, height: 36 * scale))
        slider.cell = PitchFaderCell()
        slider.minValue = 0.5
        slider.maxValue = 1.5
        slider.controlSize = .mini
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel("Pitch fader")
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.doubleValue = value
        (slider.cell as? PitchFaderCell)?.scale = scale
        slider.needsDisplay = true
    }
    final class Coordinator: NSObject {
        @Binding var value: Double
        init(value: Binding<Double>) { _value = value }
        @objc func changed(_ slider: NSSlider) { value = (slider.doubleValue * 100).rounded() / 100 }
    }
}

// Drawn at the reference's 358 × 211 proportions; controls share its physical layout.
struct BoomboxArtwork: View {
    var muted = false
    static let blue = Color(red: 0.02, green: 0.36, blue: 0.92)
    static let red = Color(red: 0.84, green: 0.025, blue: 0.055)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 358, y: size.height / 211)
            func paint(_ path: Path, _ colors: [Color], _ from: CGPoint, _ to: CGPoint, width: CGFloat = 1, edge: Color = .black) {
                context.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to))
                context.stroke(path, with: .color(edge), lineWidth: width)
            }
            let chrome: [Color] = [.white, Color(white: 0.78), .white, Color(white: 0.36)]
            let blue: [Color] = [Color(red: 0.65, green: 0.9, blue: 1), Self.blue, Color(red: 0.015, green: 0.16, blue: 0.53), Self.blue]
            let shell = Path { p in
                p.move(to: CGPoint(x: 8, y: 119))
                p.addCurve(to: CGPoint(x: 41, y: 63), control1: CGPoint(x: 10, y: 88), control2: CGPoint(x: 24, y: 57))
                p.addCurve(to: CGPoint(x: 61, y: 69), control1: CGPoint(x: 50, y: 61), control2: CGPoint(x: 54, y: 64))
                p.addCurve(to: CGPoint(x: 77, y: 39), control1: CGPoint(x: 65, y: 49), control2: CGPoint(x: 66, y: 40))
                p.addLine(to: CGPoint(x: 99, y: 36))
                p.addCurve(to: CGPoint(x: 114, y: 23), control1: CGPoint(x: 100, y: 25), control2: CGPoint(x: 102, y: 24))
                p.addLine(to: CGPoint(x: 131, y: 21))
                p.addCurve(to: CGPoint(x: 148, y: 11), control1: CGPoint(x: 133, y: 11), control2: CGPoint(x: 144, y: 11))
                p.addQuadCurve(to: CGPoint(x: 210, y: 11), control: CGPoint(x: 179, y: 8))
                p.addQuadCurve(to: CGPoint(x: 228, y: 21), control: CGPoint(x: 225, y: 11))
                p.addLine(to: CGPoint(x: 244, y: 23))
                p.addQuadCurve(to: CGPoint(x: 259, y: 36), control: CGPoint(x: 257, y: 24))
                p.addLine(to: CGPoint(x: 280, y: 40))
                p.addQuadCurve(to: CGPoint(x: 297, y: 69), control: CGPoint(x: 293, y: 40))
                p.addQuadCurve(to: CGPoint(x: 320, y: 63), control: CGPoint(x: 306, y: 57))
                p.addCurve(to: CGPoint(x: 351, y: 133), control1: CGPoint(x: 338, y: 70), control2: CGPoint(x: 351, y: 105))
                p.addCurve(to: CGPoint(x: 311, y: 201), control1: CGPoint(x: 359, y: 167), control2: CGPoint(x: 336, y: 198))
                p.addCurve(to: CGPoint(x: 239, y: 186), control1: CGPoint(x: 285, y: 207), control2: CGPoint(x: 252, y: 201))
                p.addQuadCurve(to: CGPoint(x: 179, y: 200), control: CGPoint(x: 216, y: 199))
                p.addQuadCurve(to: CGPoint(x: 120, y: 186), control: CGPoint(x: 144, y: 200))
                p.addCurve(to: CGPoint(x: 48, y: 201), control1: CGPoint(x: 102, y: 202), control2: CGPoint(x: 74, y: 206))
                p.addCurve(to: CGPoint(x: 8, y: 119), control1: CGPoint(x: 12, y: 199), control2: CGPoint(x: 1, y: 160))
                p.closeSubpath()
            }
            paint(shell, blue, CGPoint(x: 130, y: 12), CGPoint(x: 210, y: 200), width: 2, edge: Color(red: 0.01, green: 0.22, blue: 0.52))
            var bevel = context
            bevel.clip(to: shell)
            bevel.stroke(shell, with: .linearGradient(Gradient(colors: [.white, Self.blue, .white, Color(red: 0, green: 0.12, blue: 0.4)]), startPoint: CGPoint(x: 0, y: 35), endPoint: CGPoint(x: 0, y: 205)), lineWidth: 7)
            context.stroke(shell, with: .color(.white.opacity(0.7)), lineWidth: 0.6)

            let fascia = Path { p in
                p.move(to: CGPoint(x: 112, y: 27))
                p.addQuadCurve(to: CGPoint(x: 245, y: 27), control: CGPoint(x: 179, y: 18))
                p.addCurve(to: CGPoint(x: 252, y: 66), control1: CGPoint(x: 259, y: 29), control2: CGPoint(x: 258, y: 58))
                p.addQuadCurve(to: CGPoint(x: 214, y: 100), control: CGPoint(x: 249, y: 85))
                p.addQuadCurve(to: CGPoint(x: 205, y: 151), control: CGPoint(x: 210, y: 127))
                p.addLine(to: CGPoint(x: 195, y: 190))
                p.addQuadCurve(to: CGPoint(x: 163, y: 190), control: CGPoint(x: 179, y: 198))
                p.addLine(to: CGPoint(x: 153, y: 151))
                p.addQuadCurve(to: CGPoint(x: 143, y: 100), control: CGPoint(x: 147, y: 123))
                p.addQuadCurve(to: CGPoint(x: 106, y: 66), control: CGPoint(x: 109, y: 83))
                p.addQuadCurve(to: CGPoint(x: 112, y: 27), control: CGPoint(x: 98, y: 40))
                p.closeSubpath()
            }
            paint(fascia, [.white.opacity(0.9), Self.blue, Color(red: 0.15, green: 0.57, blue: 1), Color(red: 0, green: 0.16, blue: 0.52)], CGPoint(x: 160, y: 24), CGPoint(x: 194, y: 196), edge: .white.opacity(0.75))
            // Handle and three tiny chrome switches.
            paint(Path(roundedRect: CGRect(x: 136, y: 12, width: 86, height: 18), cornerRadius: 7), chrome, CGPoint(x: 0, y: 12), CGPoint(x: 0, y: 30), edge: Self.blue)
            for (x, symbol) in [(147.0, muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), (171.0, "minus"), (195.0, "xmark")] {
                paint(Path(roundedRect: CGRect(x: x, y: 15, width: 19, height: 10), cornerRadius: 2), chrome, CGPoint(x: 0, y: 15), CGPoint(x: 0, y: 25))
                context.draw(Text(Image(systemName: symbol)).font(.system(size: 6, weight: .black)).foregroundColor(.black), at: CGPoint(x: x + 9.5, y: 20))
            }
            // The asymmetrical teardrop grilles and their chrome rims mirror each other.
            for mirrored in [false, true] {
                var speaker = context
                if mirrored { speaker.translateBy(x: 358, y: 0); speaker.scaleBy(x: -1, y: 1) }
                let rim = Path { p in
                    p.move(to: CGPoint(x: 37, y: 78))
                    p.addCurve(to: CGPoint(x: 116, y: 112), control1: CGPoint(x: 54, y: 83), control2: CGPoint(x: 87, y: 102))
                    p.addCurve(to: CGPoint(x: 120, y: 176), control1: CGPoint(x: 130, y: 126), control2: CGPoint(x: 129, y: 154))
                    p.addCurve(to: CGPoint(x: 47, y: 196), control1: CGPoint(x: 105, y: 198), control2: CGPoint(x: 69, y: 205))
                    p.addCurve(to: CGPoint(x: 15, y: 132), control1: CGPoint(x: 20, y: 190), control2: CGPoint(x: 9, y: 162))
                    p.addQuadCurve(to: CGPoint(x: 37, y: 78), control: CGPoint(x: 20, y: 88))
                    p.closeSubpath()
                }
                speaker.fill(rim, with: .linearGradient(Gradient(colors: chrome), startPoint: CGPoint(x: 0, y: 80), endPoint: CGPoint(x: 120, y: 195)))
                speaker.stroke(rim, with: .color(Color(white: 0.14)), lineWidth: 1.5)
                let grille = rim.applying(CGAffineTransform(translationX: -70, y: -139).concatenating(CGAffineTransform(scaleX: 0.88, y: 0.88)).concatenating(CGAffineTransform(translationX: 70, y: 139)))
                speaker.fill(grille, with: .radialGradient(Gradient(colors: [Color(white: 0.19), .black, Color(white: 0.12)]), center: CGPoint(x: 70, y: 147), startRadius: 0, endRadius: 70))
                speaker.stroke(grille, with: .color(.black), lineWidth: 2)
                var mesh = speaker
                mesh.clip(to: grille)
                let cone = Path(ellipseIn: CGRect(x: 29, y: 104, width: 88, height: 84))
                mesh.stroke(cone, with: .color(.white.opacity(0.11)), lineWidth: 3)
                var holes = Path()
                for y in stride(from: 84.0, through: 199, by: 2.5) {
                    for x in stride(from: 12.0, through: 132, by: 2.5) {
                        holes.addEllipse(in: CGRect(x: x, y: y, width: 0.7, height: 1))
                    }
                }
                mesh.fill(holes, with: .color(.white.opacity(0.24)))
                speaker.fill(Path(roundedRect: CGRect(x: 74, y: 45, width: 18, height: 29), cornerRadius: 5), with: .linearGradient(Gradient(colors: chrome), startPoint: CGPoint(x: 74, y: 45), endPoint: CGPoint(x: 92, y: 74)))
                speaker.stroke(Path(roundedRect: CGRect(x: 74, y: 45, width: 18, height: 29), cornerRadius: 5), with: .color(.black), lineWidth: 1.2)
                speaker.stroke(Path(ellipseIn: CGRect(x: 79, y: 51, width: 8, height: 16)), with: .color(.black), lineWidth: 1.2)
                let logoX: CGFloat = mirrored ? 286 : 72
                context.draw(Text("X-SOUND").font(.custom("Arial Black", size: 14)).italic().foregroundColor(Color(white: 0.59)), at: CGPoint(x: logoX, y: 147))
                context.draw(Text("S T E R E O").font(.system(size: 4, weight: .bold)).foregroundColor(Color(white: 0.65)), at: CGPoint(x: logoX, y: 161))
            }
            // Bottom vents, central fader socket and black LCD bezel.
            for side in [0, 1] {
                for row in 0..<5 {
                    var vent = Path()
                    let x: CGFloat = side == 0 ? 138 : 201
                    let y = CGFloat(157 + row * 6)
                    vent.move(to: CGPoint(x: x, y: y))
                    vent.addLine(to: CGPoint(x: x + 19, y: y + (side == 0 ? 5 : -5)))
                    context.stroke(vent, with: .color(Color(red: 0, green: 0.07, blue: 0.22)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            paint(Path(roundedRect: CGRect(x: 170, y: 149, width: 18, height: 43), cornerRadius: 8), chrome, CGPoint(x: 170, y: 149), CGPoint(x: 189, y: 190))
            paint(Path(roundedRect: CGRect(x: 175, y: 155, width: 8, height: 29), cornerRadius: 4), [.black, Color(white: 0.2), .black], CGPoint(x: 175, y: 155), CGPoint(x: 183, y: 184))
            paint(Path(roundedRect: CGRect(x: 105, y: 31, width: 148, height: 32), cornerRadius: 12), [Color(white: 0.35), .black, .black], CGPoint(x: 0, y: 31), CGPoint(x: 0, y: 63), width: 2)
            let shine = Path(roundedRect: CGRect(x: 111, y: 35, width: 135, height: 13), cornerRadius: 7)
            context.fill(shine, with: .linearGradient(Gradient(colors: [.white.opacity(0.25), .white.opacity(0.01)]), startPoint: CGPoint(x: 0, y: 35), endPoint: CGPoint(x: 0, y: 48)))
            context.draw(Text("LiStD").font(.custom("Arial Black", size: 25)).italic().foregroundColor(.white), at: CGPoint(x: 180, y: 80))
            context.draw(Text("LiStD").font(.custom("Arial Black", size: 23)).italic().foregroundColor(Self.red), at: CGPoint(x: 180, y: 79))
            context.draw(Text("P I T C H   C O N T R O L").font(.system(size: 4, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: 179, y: 96))
        }.accessibilityHidden(true)
    }
}

struct ChromeTransport: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(white: 0.17))
            .background(configuration.isPressed ? AnyShapeStyle(Color(white: 0.56)) : AnyShapeStyle(CrateSkin.metal), in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1).padding(2))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.2 : 0.55), radius: configuration.isPressed ? 0 : 1, y: configuration.isPressed ? 0 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .offset(y: configuration.isPressed ? 0.7 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct BoomboxPlayer: View {
    @ObservedObject var player: CratePlayer
    var showTracks: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var playerWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }
    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 358, proxy.size.height / 211)
            ZStack {
                // Render the vector canvas at its final size rather than enlarging a small raster.
                BoomboxArtwork(muted: player.muted).frame(width: 358 * scale, height: 211 * scale)
                    .onTapGesture { if player.loaded { player.toggle() } else { player.openFile() } }
                    .help("Click the shell to play or pause")
                ZStack {
                hit("Mute / unmute", width: 19, height: 10) { player.toggleMute() }.position(x: 156.5, y: 20)
                hit("Minimize LiStD", width: 19, height: 10) { playerWindow?.miniaturize(nil) }.position(x: 180.5, y: 20)
                hit("Close LiStD", width: 19, height: 10) { playerWindow?.performClose(nil) }.position(x: 204.5, y: 20)
                hit("Volume down", width: 18, height: 29) { player.volume = max(0, player.volume - 0.05) }.position(x: 83, y: 59.5)
                hit("Volume up", width: 18, height: 29) { player.volume = min(1, player.volume + 0.05) }.position(x: 275, y: 59.5)
                hit("Back 10 seconds · left speaker", width: 100, height: 100) { player.seek(to: player.position - 10) }.position(x: 70, y: 144)
                hit("Forward 10 seconds · right speaker", width: 100, height: 100) { player.seek(to: player.position + 10) }.position(x: 288, y: 144)
                hit("Slower · left vents", width: 24, height: 36) { player.rate = max(0.5, player.rate - 0.01) }.position(x: 146, y: 170)
                hit("Faster · right vents", width: 24, height: 36) { player.rate = min(1.5, player.rate + 0.01) }.position(x: 212, y: 170)
                hit("Show tracks and imports", width: 128, height: 25, action: showTracks).position(x: 179, y: 80)
                if player.spectrumVisible {
                    SpectrumDisplay(analyzer: player.spectrum, playing: player.isPlaying)
                        .frame(width: 134, height: 25).opacity(0.75)
                        .clipShape(RoundedRectangle(cornerRadius: 7)).position(x: 179, y: 47)
                        .allowsHitTesting(false)
                }
                VStack(spacing: 1) {
                    Text(player.title).font(.system(size: 8, weight: .bold, design: .monospaced)).lineLimit(1)
                    Text(player.loaded ? "\(player.isPlaying ? "PLAY" : "PAUSE")  \(CratePlayer.clock(player.position))  \(String(format: "%.2f", player.rate))×" : "OPEN AUDIO  /  SELECT A TRACK")
                        .font(.system(size: 5, weight: .medium, design: .monospaced)).lineLimit(1)
                }.foregroundStyle(.white).shadow(color: .black, radius: 1.2)
                    .frame(width: 126, height: 22).position(x: 179, y: 47).allowsHitTesting(false)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: player.title)
                hit("Toggle live spectrum", width: 138, height: 28) { player.spectrumVisible.toggle() }.position(x: 179, y: 47)
                transport("gobackward.10", label: "Back 10 seconds", size: 23) { player.seek(to: player.position - 10) }.position(x: 155, y: 113)
                transport(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play", size: 29) { player.toggle() }.position(x: 179, y: 113)
                transport("goforward.10", label: "Forward 10 seconds", size: 23) { player.seek(to: player.position + 10) }.position(x: 203, y: 113)
                transport("stop.fill", label: "Stop", size: 19) { player.stop() }.position(x: 166, y: 137)
                transport("folder.fill", label: "Open audio file", size: 19, needsTrack: false) { player.openFile() }.position(x: 192, y: 137)
            }.frame(width: 358, height: 211)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: player.spectrumVisible)
                .scaleEffect(scale, anchor: .center)
                // Give AppKit its real size so dragging is calibrated at every player scale.
                VerticalPitchSlider(value: $player.rate, scale: scale)
                    .frame(width: 14 * scale, height: 36 * scale)
                    .accessibilityLabel("Pitch fader")
                    .help("Drag up to play faster and higher; down for slower and lower")
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2 + 63.5 * scale)
            }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    func hit(_ label: String, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.white.opacity(0.001).frame(width: width, height: height)
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }.buttonStyle(SkinSurfacePress()).accessibilityLabel(label).help(label)
    }

    func transport(_ symbol: String, label: String, size: CGFloat, needsTrack: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .bold)).frame(width: size, height: size)
        }.buttonStyle(ChromeTransport()).disabled(needsTrack && !player.loaded).accessibilityLabel(label).help(label)
    }
}

struct SkinSurfacePress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0), in: RoundedRectangle(cornerRadius: 4))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
