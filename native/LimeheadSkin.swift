import SwiftUI
import AppKit

// Limehead · Mix recreates the supplied green "head" media-player reference: a lime head
// with a red visualiser screen, flanked by two speaker wings. The head, face, screen
// outline, wings and speakers are traced from the reference by scripts/trace_limehead.py
// into `LimeTrace` (native/LimeheadTrace.swift), in the reference crop's own pixel space;
// every control here uses the same coordinates. The left wing is a two-deck mixer
// (crossfader, master and per-deck level/pitch/EQ faders); the right wing lists the
// collection pane's visible tracks.
enum LimeGeometry {
    static let width: CGFloat = 935
    static let height: CGFloat = 498

    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    // MARK: Head and screen, traced.
    static let head = LimeTracedShape.path(LimeTrace.head.outline)
    static let screen = LimeTracedShape.path(LimeTrace.screen)
    /// The part of the screen below the title pill, where the visualiser is laid out.
    static let screenView = CGRect(x: 338, y: 114, width: 256, height: 156)

    /// Title pill, measured: it sits on the screen's top edge.
    static let pill = CGRect(x: 359.5, y: 85, width: 212, height: 26.5)
    static let titleText = CGRect(x: 394, y: 88.5, width: 132, height: 20)

    // Head controls (centres).
    static let minimize = p(452, 22), close = p(471, 22)
    static let previous = p(395, 62), playPause = p(426, 62), stop = p(458, 62), next = p(488, 62)
    static let visualiser = p(539, 62)
    static let focusA = p(383, 98.5), focusB = p(537, 98.5), openFile = p(558, 98.5)
    static let mixerIcon = p(352, 284), listIcon = p(581, 284), drawerIcon = p(467, 311)
    static let seekStart: CGFloat = 378, seekEnd: CGFloat = 559, seekY: CGFloat = 285

    // MARK: Wings (traced). Panel interiors, measured, are drawn by the app.
    static let leftPanel = CGRect(x: 107.5, y: 125.5, width: 202.5, height: 170)
    static let rightPanel = CGRect(x: 613.5, y: 126.5, width: 208.5, height: 169)
    static let leftWingClose = p(99.5, 128), rightWingClose = p(833, 128)
    /// Small tabs on the head's edge that reopen a closed wing.
    static let leftHeadTab = Path(ellipseIn: CGRect(x: 311, y: 200, width: 26, height: 72))
    static let rightHeadTab = Path(ellipseIn: CGRect(x: 591, y: 200, width: 26, height: 72))

    // MARK: Mixer layout (left panel)
    static let crossfade = (from: p(125, 144), to: p(198, 144))
    static let master = (from: p(222, 144), to: p(296, 144))
    static let faderX: [CGFloat] = [127, 145, 163, 182, 200, 218, 237, 255, 273, 291]
    static let faderTop: CGFloat = 184, faderBottom: CGFloat = 250
    static let deckRowY: CGFloat = 272
    static let reset = p(290, 288)

    // MARK: Playlist layout (right panel)
    static let dropdown = CGRect(x: 617, y: 129, width: 201, height: 21)
    static let list = CGRect(x: 617, y: 154, width: 201, height: 137)
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

// Palette sampled from the reference image.
enum LimePalette {
    static let lime = Color(hex: 0xa8fe25)
    static let limeBright = Color(hex: 0x7ed00c)
    static let limeMid = Color(hex: 0x5baf03)
    static let shade = Color(hex: 0x387900)
    static let dark = Color(hex: 0x176008)
    static let deep = Color(hex: 0x0a3a02)
    static let bevel = Color(hex: 0xa3e253)
    static let panel = Color(hex: 0x265d03)
    static let panelShadow = Color(hex: 0x143202)
    static let track = Color(hex: 0x518b17)
    static let label = Color(hex: 0x8ed63f)
    static let ink = Color(hex: 0x0b3a00)
    static let reset = Color(hex: 0xdfeed2)
    static let redHot = Color(hex: 0xc60303)
    static let red = Color(hex: 0x7d0000)
    static let redDeep = Color(hex: 0x380100)
    static let redGlow = Color(hex: 0xf36c6c)
    static let pill = Color(hex: 0x51ba09)
    static let pillLight = Color(hex: 0x8be33a)
    static let purpleLight = Color(hex: 0xf6ecff)
    static let purple = Color(hex: 0xcfa1e3)
    static let purpleDeep = Color(hex: 0x8e55a8)
    static let purpleRing = Color(hex: 0x6c4d71)
    static let purpleInk = Color(hex: 0x3a1d48)
    static let seek = Color(hex: 0x7c4e81)
    static let seekKnob = Color(hex: 0xbc87d1)
    static let rowSelected = Color(hex: 0x1d251a)
    static let rowSelectedText = Color(hex: 0x22d81a)
    static let rowText = Color(hex: 0xf0f6ea)
}

// MARK: - Traced artwork

/// A shape from `LimeTrace`, parsed once: its outline, the colour under its layers, and its
/// brightness layers (darkest first), each filled even-odd and clipped to the outline.
struct LimeTracedShape {
    let outline: Path
    let base: Color
    let layers: [(colour: Color, path: Path)]

    init(_ shape: LimeTrace.Shape) {
        outline = Self.path(shape.outline)
        base = Color(hex: shape.base)
        layers = shape.layers.map { (Color(hex: $0.colour), Self.path($0.outlines)) }
    }

    /// Closed polygons from "x,y x,y|x,y ...".
    static func path(_ text: String) -> Path {
        var path = Path()
        for loop in text.split(separator: "|") {
            var started = false
            for pair in loop.split(separator: " ") {
                guard let comma = pair.firstIndex(of: ","), let x = Double(pair[..<comma]),
                      let y = Double(pair[pair.index(after: comma)...]) else { continue }
                if started { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)); started = true }
            }
            if started { path.closeSubpath() }
        }
        return path
    }

    func draw(in context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.clip(to: outline)
            layer.fill(outline, with: .color(base))
            for shade in layers { layer.fill(shade.path, with: .color(shade.colour), style: FillStyle(eoFill: true)) }
        }
    }
}

enum LimeArt {
    static let head = LimeTracedShape(LimeTrace.head)
    static let leftWing = LimeTracedShape(LimeTrace.leftWing)
    static let rightWing = LimeTracedShape(LimeTrace.rightWing)
    static let leftSpeakers = LimeTrace.leftSpeakers.map(LimeTracedShape.init)
    static let rightSpeakers = LimeTrace.rightSpeakers.map(LimeTracedShape.init)
}

// MARK: - Mixer model

/// Two-deck mix: each deck's output = master × deck level × constant-power crossfade gain.
@MainActor final class LimeMixer: ObservableObject {
    @Published var crossfade = 0.5 { didSet { apply() } }
    @Published var master = 0.8 { didSet { apply() } }
    @Published var levelA = 0.85 { didSet { apply() } }
    @Published var levelB = 0.85 { didSet { apply() } }
    private weak var a: CratePlayer?
    private weak var b: CratePlayer?

    /// Constant power: both decks at about 71% in the centre, one deck alone at the ends.
    static func gains(_ crossfade: Double) -> (a: Double, b: Double) {
        let x = min(1, max(0, crossfade)) * .pi / 2
        return (cos(x), sin(x))
    }

    func attach(_ a: CratePlayer, _ b: CratePlayer) { self.a = a; self.b = b; apply() }

    /// Hands volume back to the other skins: each deck at the master level.
    func detach() {
        a?.volume = master; b?.volume = master
        a = nil; b = nil
    }

    func apply() {
        let g = Self.gains(crossfade)
        a?.volume = min(1, max(0, master * levelA * g.a))
        b?.volume = min(1, max(0, master * levelB * g.b))
    }

    func reset(_ decks: [CratePlayer]) {
        crossfade = 0.5; levelA = 0.85; levelB = 0.85
        for deck in decks { deck.rate = 1; deck.resetEQ() }
    }
}

// MARK: - Artwork

/// Redraws only when a wing opens or closes (the traced paths are detailed).
struct LimeArtwork: View, Equatable {
    var leftOpen = true
    var rightOpen = true
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / LimeGeometry.width, y: size.height / LimeGeometry.height)
            LimeArtwork.draw(in: &context, leftOpen: leftOpen, rightOpen: rightOpen)
        }.accessibilityHidden(true)
    }

    private typealias G = LimeGeometry
    private typealias P = LimePalette

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }
    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path { ellipse(c.x, c.y, r * 2, r * 2) }
    static func line(_ points: [CGPoint]) -> Path { var path = Path(); path.addLines(points); return path }

    static func draw(in context: inout GraphicsContext, leftOpen: Bool, rightOpen: Bool) {
        if leftOpen {
            LimeArt.leftWing.draw(in: &context)
            for speaker in LimeArt.leftSpeakers { speaker.draw(in: &context) }
        } else { drawHeadTab(in: &context, G.leftHeadTab, pointingRight: false) }
        if rightOpen {
            LimeArt.rightWing.draw(in: &context)
            for speaker in LimeArt.rightSpeakers { speaker.draw(in: &context) }
        } else { drawHeadTab(in: &context, G.rightHeadTab, pointingRight: true) }
        if leftOpen { drawPanel(in: &context, G.leftPanel); drawMixerTracks(in: &context) }
        if rightOpen { drawPanel(in: &context, G.rightPanel) }
        LimeArt.head.draw(in: &context)
        drawScreen(in: &context)
        drawHeadControls(in: &context)
    }

    static func drawHeadTab(in context: inout GraphicsContext, _ tab: Path, pointingRight: Bool) {
        context.fill(tab, with: .linearGradient(Gradient(colors: [P.bevel, Color(hex: 0x4da517), P.shade]),
                                                startPoint: G.p(tab.boundingRect.minX, 0), endPoint: G.p(tab.boundingRect.maxX, 0)))
        context.stroke(tab, with: .color(P.dark), lineWidth: 1)
    }

    static func drawPanel(in context: inout GraphicsContext, _ rect: CGRect) {
        let shape = Path(roundedRect: rect, cornerRadius: 2)
        context.fill(shape, with: .color(P.panel))
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.addFilter(.blur(radius: 1.5))
            layer.stroke(line([G.p(rect.minX, rect.maxY), G.p(rect.minX, rect.minY), G.p(rect.maxX, rect.minY)]),
                         with: .color(P.panelShadow), lineWidth: 5)
            layer.stroke(line([G.p(rect.maxX, rect.minY), G.p(rect.maxX, rect.maxY), G.p(rect.minX, rect.maxY)]),
                         with: .color(Color(hex: 0x4a9a10).opacity(0.6)), lineWidth: 2)
        }
    }

    static func drawMixerTracks(in context: inout GraphicsContext) {
        func cap(_ c: CGPoint, light: Bool, vertical: Bool) {
            let rect = vertical ? CGRect(x: c.x - 6, y: c.y - 2.2, width: 12, height: 4.4) : CGRect(x: c.x - 2.6, y: c.y - 5, width: 5.2, height: 10)
            let shape = Path(roundedRect: rect, cornerRadius: 2)
            context.fill(shape, with: .linearGradient(Gradient(colors: light ? [Color(hex: 0xf1f8f4), Color(hex: 0xccd9d1), Color(hex: 0x7f8a83)]
                                                                     : [Color(hex: 0x8a948c), Color(hex: 0x3e4a3a), Color(hex: 0x1e271c)]),
                                                      startPoint: G.p(0, rect.minY), endPoint: G.p(0, rect.maxY)))
        }
        func rail(_ a: CGPoint, _ b: CGPoint) {
            context.stroke(line([a, b]), with: .color(Color(hex: 0x1c4a04)), lineWidth: 3.4)
            context.stroke(line([a, b]), with: .color(P.track), lineWidth: 1.4)
        }
        for slider in [G.crossfade, G.master] {
            rail(slider.from, slider.to)
            cap(slider.from, light: false, vertical: false); cap(slider.to, light: false, vertical: false)
        }
        // Centre detent on the crossfader.
        let mid = (G.crossfade.from.x + G.crossfade.to.x) / 2
        context.stroke(line([G.p(mid, 137), G.p(mid, 140)]), with: .color(P.label.opacity(0.8)), lineWidth: 1)
        for x in G.faderX {
            rail(G.p(x, G.faderTop), G.p(x, G.faderBottom))
            cap(G.p(x, G.faderTop), light: true, vertical: true)
            cap(G.p(x, G.faderBottom), light: false, vertical: true)
        }
        // Divider between deck A and deck B fader groups.
        context.stroke(line([G.p(209, 168), G.p(209, 282)]), with: .color(P.panelShadow.opacity(0.9)), lineWidth: 1)
        context.stroke(line([G.p(210, 168), G.p(210, 282)]), with: .color(Color(hex: 0x4a9a10).opacity(0.35)), lineWidth: 1)
    }

    // MARK: Screen and controls

    static func drawScreen(in context: inout GraphicsContext) {
        // The traced head carries the bezel; the screen is the dark red the visualiser glows on.
        context.fill(G.screen, with: .radialGradient(Gradient(colors: [Color(hex: 0x8a0000), Color(hex: 0x5a0000), Color(hex: 0x2a0000)]),
                                                     center: G.p(465, 185), startRadius: 0, endRadius: 165))

        // Title pill (sampled colours, dark rim) and its buttons.
        let pill = Path(roundedRect: G.pill, cornerRadius: G.pill.height / 2)
        context.fill(pill, with: .linearGradient(Gradient(colors: [Color(hex: 0x6ad310), Color(hex: 0x5ec104), Color(hex: 0x4ec100), Color(hex: 0x3e9a00)]),
                                                 startPoint: G.p(0, G.pill.minY), endPoint: G.p(0, G.pill.maxY)))
        context.drawLayer { scan in
            scan.clip(to: pill)
            var y = G.pill.minY + 1.5
            while y < G.pill.maxY { scan.fill(Path(CGRect(x: G.pill.minX, y: y, width: G.pill.width, height: 0.8)), with: .color(Color(hex: 0x3d9900).opacity(0.18))); y += 2 }
        }
        context.stroke(pill, with: .color(Color(hex: 0x212b00)), lineWidth: 1)
        roundButton(in: &context, G.focusA, 10, [Color(hex: 0xfff2a8), Color(hex: 0xe3b521), Color(hex: 0x9a6c08)], ring: Color(hex: 0x5a4006))
        roundButton(in: &context, G.focusB, 10, [Color(hex: 0xd6f4ff), Color(hex: 0x3fa8e0), Color(hex: 0x145a8c)], ring: Color(hex: 0x0c3a5c))
        let a = G.focusA, b = G.focusB
        var left = Path(); left.move(to: G.p(a.x + 2.5, a.y - 5)); left.addLine(to: G.p(a.x - 4.5, a.y)); left.addLine(to: G.p(a.x + 2.5, a.y + 5)); left.closeSubpath()
        var right = Path(); right.move(to: G.p(b.x - 2.5, b.y - 5)); right.addLine(to: G.p(b.x + 4.5, b.y)); right.addLine(to: G.p(b.x - 2.5, b.y + 5)); right.closeSubpath()
        context.fill(left, with: .color(Color(hex: 0x2a1c00)))
        context.fill(right, with: .color(Color(hex: 0x05182a)))
        let x = G.openFile
        context.stroke(line([G.p(x.x - 3.5, x.y - 3.5), G.p(x.x + 3.5, x.y + 3.5)]), with: .color(P.ink), lineWidth: 1.8)
        context.stroke(line([G.p(x.x + 3.5, x.y - 3.5), G.p(x.x - 3.5, x.y + 3.5)]), with: .color(P.ink), lineWidth: 1.8)
    }

    static func roundButton(in context: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ colours: [Color], ring: Color) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.5)); layer.translateBy(x: 0.5, y: 1.5)
            layer.fill(circle(c, r + 1), with: .color(.black.opacity(0.45)))
        }
        context.fill(circle(c, r), with: .radialGradient(Gradient(colors: colours), center: G.p(c.x - r * 0.3, c.y - r * 0.4),
                                                         startRadius: 0, endRadius: r * 1.3))
        context.stroke(circle(c, r - 0.8), with: .color(ring), lineWidth: 1.6)
    }

    static func drawHeadControls(in context: inout GraphicsContext) {
        // Window keys.
        for (index, c) in [G.minimize, G.close].enumerated() {
            let key = Path(roundedRect: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13), cornerRadius: 3)
            context.fill(key, with: .linearGradient(Gradient(colors: [Color(hex: 0xd2ff8a), P.limeBright]), startPoint: G.p(0, c.y - 6.5), endPoint: G.p(0, c.y + 6.5)))
            context.stroke(key, with: .color(Color(hex: 0x3d8a05)), lineWidth: 1)
            if index == 0 {
                context.stroke(line([G.p(c.x - 3.5, c.y + 3), G.p(c.x + 3.5, c.y + 3)]), with: .color(P.ink), lineWidth: 1.8)
            } else {
                context.stroke(line([G.p(c.x - 3, c.y - 3), G.p(c.x + 3, c.y + 3)]), with: .color(P.ink), lineWidth: 1.8)
                context.stroke(line([G.p(c.x + 3, c.y - 3), G.p(c.x - 3, c.y + 3)]), with: .color(P.ink), lineWidth: 1.8)
            }
        }
        // Purple transport buttons; the play/pause glyph is live.
        for c in [G.previous, G.playPause, G.stop, G.next] {
            roundButton(in: &context, c, 12, [P.purpleLight, P.purple, P.purpleDeep], ring: P.purpleRing)
        }
        let ink = GraphicsContext.Shading.color(P.purpleInk)
        func triangle(_ tipX: CGFloat, _ baseX: CGFloat, _ cy: CGFloat) -> Path {
            var t = Path(); t.move(to: G.p(baseX, cy - 4.5)); t.addLine(to: G.p(tipX, cy)); t.addLine(to: G.p(baseX, cy + 4.5)); t.closeSubpath(); return t
        }
        let pr = G.previous
        context.fill(Path(CGRect(x: pr.x - 6, y: pr.y - 4.5, width: 1.8, height: 9)), with: ink)
        context.fill(triangle(pr.x - 4, pr.x + 0.5, pr.y), with: ink)
        context.fill(triangle(pr.x + 0.5, pr.x + 5, pr.y), with: ink)
        let nx = G.next
        context.fill(triangle(nx.x + 0, nx.x - 4.5, nx.y), with: ink)
        context.fill(triangle(nx.x + 4.5, nx.x + 0, nx.y), with: ink)
        context.fill(Path(CGRect(x: nx.x + 4.4, y: nx.y - 4.5, width: 1.8, height: 9)), with: ink)
        let st = G.stop
        context.fill(Path(CGRect(x: st.x - 4, y: st.y - 4, width: 8, height: 8)), with: ink)
        // Gold visualiser button with a black asterisk.
        let v = G.visualiser
        roundButton(in: &context, v, 12, [Color(hex: 0xfff7b0), Color(hex: 0xf2cd2a), Color(hex: 0xb8860b)], ring: .black)
        for angle in stride(from: 0.0, to: 180, by: 45) {
            let a = angle * .pi / 180
            context.stroke(line([G.p(v.x - cos(a) * 6.5, v.y - sin(a) * 6.5), G.p(v.x + cos(a) * 6.5, v.y + sin(a) * 6.5)]),
                           with: .color(.black), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        context.fill(circle(v, 2.4), with: .color(.black))

        // Seek track: a segmented purple groove.
        let groove = Path(roundedRect: CGRect(x: 372, y: G.seekY - 4.5, width: 193, height: 9), cornerRadius: 4.5)
        context.fill(groove, with: .linearGradient(Gradient(colors: [Color(hex: 0x3d2242), P.seek, Color(hex: 0xa77bb0), Color(hex: 0x5a3560)]),
                                                   startPoint: G.p(0, G.seekY - 4.5), endPoint: G.p(0, G.seekY + 4.5)))
        var tick: CGFloat = 396
        while tick < 560 {
            context.stroke(line([G.p(tick, G.seekY - 3.5), G.p(tick, G.seekY + 3.5)]), with: .color(Color(hex: 0x4a2a50).opacity(0.6)), lineWidth: 1)
            tick += 24
        }
        context.stroke(groove, with: .color(Color(hex: 0x2e7a03)), lineWidth: 1)

        // Mixer, playlist and drawer icons.
        let glyph = GraphicsContext.Shading.color(Color(hex: 0x1d5a03))
        let m = G.mixerIcon
        for (index, h) in [6.0, 10, 7, 12, 8].enumerated() {
            context.fill(Path(CGRect(x: m.x - 7 + CGFloat(index) * 3, y: m.y + 5 - h, width: 1.8, height: h)), with: glyph)
        }
        context.fill(Path(CGRect(x: m.x - 8, y: m.y + 5, width: 16, height: 1.4)), with: glyph)
        let d = G.listIcon
        var page = Path()
        page.move(to: G.p(d.x - 5.5, d.y - 7.5)); page.addLine(to: G.p(d.x + 2.5, d.y - 7.5)); page.addLine(to: G.p(d.x + 5.5, d.y - 4.5))
        page.addLine(to: G.p(d.x + 5.5, d.y + 7.5)); page.addLine(to: G.p(d.x - 5.5, d.y + 7.5)); page.closeSubpath()
        context.fill(page, with: .color(Color(hex: 0xd2ff8a).opacity(0.7)))
        context.stroke(page, with: glyph, lineWidth: 1.2)
        for row in 0..<4 { context.fill(Path(CGRect(x: d.x - 3.5, y: d.y - 3.5 + CGFloat(row) * 2.8, width: 7, height: 1)), with: glyph) }
        let w = G.drawerIcon
        let back = Path(roundedRect: CGRect(x: w.x - 12, y: w.y - 12, width: 14, height: 14), cornerRadius: 2)
        let front = Path(roundedRect: CGRect(x: w.x - 2, y: w.y - 2, width: 14, height: 14), cornerRadius: 2)
        context.fill(back, with: .color(Color(hex: 0xd2ff8a).opacity(0.7))); context.stroke(back, with: glyph, lineWidth: 1.5)
        context.fill(front, with: .color(Color(hex: 0xd2ff8a))); context.stroke(front, with: glyph, lineWidth: 1.5)
        context.stroke(line([G.p(w.x - 8, w.y - 8), G.p(w.x + 5, w.y + 5)]), with: glyph, lineWidth: 1.5)
        context.stroke(line([G.p(w.x + 5, w.y), G.p(w.x + 5, w.y + 5), G.p(w.x, w.y + 5)]), with: glyph, lineWidth: 1.5)
    }
}

// MARK: - Red visualiser

/// Recent waveforms, newest last, for the smeared trails.
final class LimeTrails {
    private(set) var frames: [[Float]] = []
    private var last = Date.distantPast
    func push(_ wave: [Float], at date: Date) {
        guard date.timeIntervalSince(last) >= 1.0 / 40 else { return }
        last = date
        frames.append(wave)
        if frames.count > 12 { frames.removeFirst() }
    }
}

/// An old-Windows style visualiser after the reference screen: a jagged white
/// oscilloscope line across the screen and another down the middle, red glowing trails
/// that zoom outward behind them, and a hot spot in the centre that swells with the
/// music. Reads the focused deck's live audio; still under Reduce Motion or when paused.
struct LimeVisualiser: View {
    let analyzer: AudioSpectrum
    let playing: Bool
    @State private var trails = LimeTrails()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion)) { timeline in
            Canvas { context, size in
                trails.push(playing ? analyzer.wave : Array(repeating: 0, count: AudioSpectrum.wavePoints), at: timeline.date)
                let levels = playing ? analyzer.levels : []
                let energy = levels.isEmpty ? 0 : CGFloat(levels.reduce(0, +) / Float(levels.count))
                let s = size.width / LimeGeometry.width
                context.scaleBy(x: s, y: s)
                context.clip(to: LimeGeometry.screen)
                context.clip(to: Path(roundedRect: LimeGeometry.pill, cornerRadius: LimeGeometry.pill.height / 2), options: .inverse)
                let box = LimeGeometry.screenView
                let c = CGPoint(x: box.midX, y: box.midY - 4)
                LimeVisualiser.draw(in: &context, frames: trails.frames, energy: energy, box: box, centre: c)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(playing ? "Live audio visualiser" : "Audio visualiser paused")
    }

    /// Jagged polylines through the raw samples, like the original oscilloscope.
    static func across(_ wave: [Float], _ box: CGRect, _ c: CGPoint) -> Path {
        var path = Path()
        guard wave.count > 1 else { return path }
        for (index, sample) in wave.enumerated() {
            let x = box.minX + box.width * CGFloat(index) / CGFloat(wave.count - 1)
            let y = min(box.maxY, max(box.minY, c.y + CGFloat(sample) * box.height * 0.5))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    static func down(_ wave: [Float], _ box: CGRect, _ c: CGPoint) -> Path {
        var path = Path()
        guard wave.count > 1 else { return path }
        let n = wave.count
        for index in 0..<n {
            let sample = wave[(index + n / 2) % n]
            let y = box.minY + box.height * CGFloat(index) / CGFloat(n - 1)
            let x = min(box.maxX, max(box.minX, c.x + CGFloat(sample) * box.width * 0.22))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    static func draw(in context: inout GraphicsContext, frames: [[Float]], energy: CGFloat, box: CGRect, centre c: CGPoint) {
        // Hot spot.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 16))
            let w = 50 + 110 * energy, h = 40 + 80 * energy
            glow.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)), with: .color(Color(hex: 0xff3030).opacity(0.25 + 0.35 * energy)))
            let core = 18 + 60 * energy
            glow.fill(Path(ellipseIn: CGRect(x: c.x - core / 2, y: c.y - core / 2, width: core, height: core)), with: .color(.white.opacity(0.25 + 0.45 * energy)))
        }
        // Trails: older frames larger and fainter, smeared red.
        context.drawLayer { trail in
            trail.addFilter(.blur(radius: 6))
            for (index, frame) in frames.enumerated() {
                let age = CGFloat(frames.count - 1 - index)
                guard age > 0 else { continue }
                let k = 1 + age * 0.07
                var layer = trail
                layer.translateBy(x: c.x, y: c.y); layer.scaleBy(x: k, y: k); layer.translateBy(x: -c.x, y: -c.y)
                let shade = GraphicsContext.Shading.color(Color(hex: 0xff1a1a).opacity(Double(max(0, 1 - age / 11)) * 0.45))
                layer.stroke(across(frame, box, c), with: shade, lineWidth: 6 / k)
                layer.stroke(down(frame, box, c), with: shade, lineWidth: 6 / k)
            }
        }
        guard let newest = frames.last else { return }
        let lines = [across(newest, box, c), down(newest, box, c)]
        context.drawLayer { smear in
            smear.addFilter(.blur(radius: 6))
            for line in lines { smear.stroke(line, with: .color(Color(hex: 0xff2020).opacity(0.75)), lineWidth: 8) }
        }
        context.drawLayer { halo in
            halo.addFilter(.blur(radius: 2))
            for line in lines { halo.stroke(line, with: .color(Color(hex: 0xff7a7a)), lineWidth: 3.5) }
        }
        for line in lines { context.stroke(line, with: .color(.white.opacity(0.95)), lineWidth: 1.1) }
    }
}

// MARK: - Live controls

private struct LimePress<S: Shape>: ButtonStyle {
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.25 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A transparent control over the artwork: brightens on hover, darkens when pressed and
/// greys out when unavailable.
private struct LimeHit<S: Shape, Label: View>: View {
    let name: String
    let shape: S
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            ZStack {
                shape.fill(Color.white.opacity(hovering && enabled ? 0.22 : 0.001))
                label()
                if !enabled { shape.fill(LimePalette.limeMid.opacity(0.55)) }
            }.contentShape(shape)
        }
        .buttonStyle(LimePress(shape: shape))
        .onHover { hovering = $0 }
        .accessibilityLabel(name).help(name)
    }
}

private extension LimeHit where Label == EmptyView {
    init(name: String, shape: S, action: @escaping () -> Void) {
        self.init(name: name, shape: shape, action: action, label: { EmptyView() })
    }
}

/// A chrome-ball fader along a straight track in artwork coordinates (`from` = lowest
/// value). Drag, arrow keys and VoiceOver adjust it.
private struct LimeFader: View {
    let name: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let from: CGPoint
    let to: CGPoint
    let s: CGFloat
    let describe: (Double) -> String
    @FocusState private var focused: Bool

    private var frame: CGRect {
        CGRect(x: min(from.x, to.x) - 8, y: min(from.y, to.y) - 8,
               width: abs(to.x - from.x) + 16, height: abs(to.y - from.y) + 16)
    }
    private var fraction: CGFloat { CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) }

    private func set(_ raw: Double) {
        let snapped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }

    var body: some View {
        let box = frame
        let f = min(1, max(0, fraction))
        let knob = CGPoint(x: from.x + (to.x - from.x) * f - box.minX, y: from.y + (to.y - from.y) * f - box.minY)
        return ZStack(alignment: .topLeading) {
            Color.white.opacity(0.001)
            Circle()
                .fill(RadialGradient(colors: [.white, Color(hex: 0xc9cfcb), Color(hex: 0x6f726f)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7 * s))
                .overlay(Circle().strokeBorder(Color(hex: 0x2b2e2b, opacity: 0.8), lineWidth: 0.6 * s))
                .overlay(Circle().strokeBorder(Color.white.opacity(focused ? 0.95 : 0), lineWidth: 1.4 * s).padding(-2.5 * s))
                .shadow(color: .black.opacity(0.45), radius: 1 * s, x: 0.5 * s, y: 1 * s)
                .frame(width: 12 * s, height: 12 * s)
                .position(x: knob.x * s, y: knob.y * s)
        }
        .frame(width: box.width * s, height: box.height * s)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            let x = drag.location.x / s + box.minX, y = drag.location.y / s + box.minY
            let dx = to.x - from.x, dy = to.y - from.y
            let t = ((x - from.x) * dx + (y - from.y) * dy) / max(0.0001, dx * dx + dy * dy)
            set(range.lowerBound + Double(min(1, max(0, t))) * (range.upperBound - range.lowerBound))
        })
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { set(value + step); return .handled }
        .onKeyPress(.rightArrow) { set(value + step); return .handled }
        .onKeyPress(.downArrow) { set(value - step); return .handled }
        .onKeyPress(.leftArrow) { set(value - step); return .handled }
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityValue(describe(value))
        .accessibilityAdjustableAction { direction in set(value + (direction == .increment ? step : -step)) }
        .help("\(name): \(describe(value))")
        .position(x: box.midX * s, y: box.midY * s)
    }
}

struct LimePlayer: View {
    @ObservedObject var a: CratePlayer
    @ObservedObject var b: CratePlayer
    @ObservedObject var mixer: LimeMixer
    /// False = the head (screen, title, transport, seek) controls deck A; true = deck B.
    @Binding var focusB: Bool
    /// The collection pane's visible tracks, in its current filter and sort.
    var tracks: [LibraryTrack]
    var load: (CratePlayer, LibraryTrack) -> Void
    /// Loads the track `offset` rows away in the collection into a deck; Bool = start playing.
    var step: (CratePlayer, Int, Bool) -> Void
    var showTracks: () -> Void
    @State private var leftOpen = true
    @State private var rightOpen = true
    @State private var loadIntoB = false
    @State private var scrub: Double?
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var playerWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }
    private typealias G = LimeGeometry
    private typealias P = LimePalette

    private var deck: CratePlayer { focusB ? b : a }
    private var deckName: String { focusB ? "B" : "A" }

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width / G.width, proxy.size.height / G.height)
            ZStack(alignment: .topLeading) {
                LimeArtwork(leftOpen: leftOpen, rightOpen: rightOpen).equatable().frame(width: G.width * s, height: G.height * s)
                screen(s)
                titlePill(s)
                headKeys(s)
                transport(s)
                seekBar(s)
                if leftOpen { mixerPanel(s) }
                if rightOpen { playlist(s) }
                wingKeys(s)
            }
            .frame(width: G.width * s, height: G.height * s)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onReceive(clock) { _ in
            if scrub == nil { a.updatePosition(); b.updatePosition() }
        }
    }

    private func legible(_ size: CGFloat, _ minimum: CGFloat) -> CGFloat { max(size, minimum) }

    private func place<V: View>(_ view: V, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ s: CGFloat) -> some View {
        view.frame(width: width * s, height: height * s).position(x: x * s, y: y * s)
    }

    private func place<V: View>(_ view: V, _ c: CGPoint, _ size: CGFloat, _ s: CGFloat) -> some View {
        place(view, c.x, c.y, size, size, s)
    }

    // MARK: Screen and title

    private func screen(_ s: CGFloat) -> some View {
        let box = G.screen.boundingRect
        let status = deck.loaded
            ? "DECK \(deckName)  \(deck.isPlaying ? "▶" : "‖")  \(CratePlayer.clock(deck.position)) / \(CratePlayer.clock(deck.duration))  \(String(format: "%+.1f%%", (deck.rate - 1) * 100))"
            : "DECK \(deckName)  ·  NO TRACK"
        return ZStack(alignment: .topLeading) {
            if deck.spectrumVisible {
                LimeVisualiser(analyzer: deck.spectrum, playing: deck.isPlaying)
                    .frame(width: G.width * s, height: G.height * s)
            } else {
                place(VStack(spacing: 4 * s) {
                    Text(deck.title).font(.system(size: legible(17 * s, 11), weight: .bold, design: .rounded)).lineLimit(2)
                        .foregroundStyle(Color(hex: 0xffd6d6)).multilineTextAlignment(.center)
                    Text(deck.artist).font(.system(size: legible(11 * s, 9), weight: .medium, design: .rounded)).lineLimit(1)
                        .foregroundStyle(P.redGlow)
                }.padding(.horizontal, 16 * s).allowsHitTesting(false), box.midX, box.midY - 8, box.width, box.height - 40, s)
            }
            place(Text(status).font(.system(size: legible(8 * s, 7.5), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xffb4b4)).lineLimit(1).minimumScaleFactor(0.7)
                    .allowsHitTesting(false), box.midX, 254, 200, 12, s)
        }
        .accessibilityElement(children: .combine)
    }

    private func titlePill(_ s: CGFloat) -> some View {
        let t = G.titleText
        let label = deck.loaded ? "\(deckName) · \(deck.title)" : "Deck \(deckName)"
        return ZStack(alignment: .topLeading) {
            place(CyberMarquee(text: label, font: .system(size: legible(12 * s, 8), weight: .medium), colour: P.ink)
                .allowsHitTesting(false), t.midX, t.midY, t.width, t.height, s)
            place(LimeHit(name: "Show deck A on the head", shape: Circle()) { focusB = false }, G.focusA, 20, s)
            place(LimeHit(name: "Show deck B on the head", shape: Circle()) { focusB = true }, G.focusB, 20, s)
            place(LimeHit(name: "Open audio file into deck \(deckName)", shape: Circle()) { deck.openFile(autoplay: false) }, G.openFile, 13, s)
        }
    }

    // MARK: Head keys and transport

    private func headKeys(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            place(LimeHit(name: "Minimize LiStD", shape: RoundedRectangle(cornerRadius: 3 * s)) { playerWindow?.miniaturize(nil) }, G.minimize, 13, s)
            place(LimeHit(name: "Close LiStD", shape: RoundedRectangle(cornerRadius: 3 * s)) { playerWindow?.performClose(nil) }, G.close, 13, s)
            place(LimeHit(name: deck.spectrumVisible ? "Hide visualiser" : "Show visualiser", shape: Circle()) { deck.spectrumVisible.toggle() },
                  G.visualiser, 24, s)
            place(LimeHit(name: leftOpen ? "Hide mixer" : "Show mixer", shape: RoundedRectangle(cornerRadius: 3 * s)) { leftOpen.toggle() },
                  G.mixerIcon, 18, s)
            place(LimeHit(name: rightOpen ? "Hide playlist" : "Show playlist", shape: RoundedRectangle(cornerRadius: 3 * s)) { rightOpen.toggle() },
                  G.listIcon, 18, s)
            place(LimeHit(name: "Show or hide tracks and imports", shape: RoundedRectangle(cornerRadius: 3 * s), action: showTracks),
                  G.drawerIcon, 28, s)
        }
    }

    private func transport(_ s: CGFloat) -> some View {
        let loaded = deck.loaded
        let canStep = !tracks.isEmpty
        let ink = P.purpleInk
        return ZStack(alignment: .topLeading) {
            place(LimeHit(name: "Previous track in the collection (deck \(deckName))", shape: Circle()) { step(deck, -1, deck.isPlaying) }
                .disabled(!canStep), G.previous, 24, s)
            place(LimeHit(name: deck.isPlaying ? "Pause deck \(deckName)" : "Play deck \(deckName)", shape: Circle(), action: playPause) {
                if deck.isPlaying {
                    HStack(spacing: 2.4 * s) {
                        Rectangle().fill(ink).frame(width: 2.6 * s, height: 9 * s)
                        Rectangle().fill(ink).frame(width: 2.6 * s, height: 9 * s)
                    }
                } else {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 8 * s, y: 4.75 * s))
                        path.addLine(to: CGPoint(x: 0, y: 9.5 * s)); path.closeSubpath()
                    }.fill(ink).frame(width: 8 * s, height: 9.5 * s).offset(x: 1 * s)
                }
            }.disabled(!loaded && !canStep), G.playPause, 24, s)
            place(LimeHit(name: "Stop deck \(deckName)", shape: Circle()) { deck.stop() }.disabled(!loaded), G.stop, 24, s)
            place(LimeHit(name: "Next track in the collection (deck \(deckName))", shape: Circle()) { step(deck, 1, deck.isPlaying) }
                .disabled(!canStep), G.next, 24, s)
        }
    }

    private func playPause() {
        if deck.loaded { deck.toggle() }
        else if !tracks.isEmpty { step(deck, 1, true) }
        else { deck.openFile() }
    }

    // MARK: Seek

    private func seekBar(_ s: CGFloat) -> some View {
        let left: CGFloat = 370, width: CGFloat = 197, travel = G.seekEnd - G.seekStart
        let fraction = deck.duration > 0 ? min(1, max(0, (scrub ?? deck.position) / deck.duration)) : 0
        return ZStack(alignment: .topLeading) {
            Color.white.opacity(0.001)
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0xe8c8f2), P.seekKnob, Color(hex: 0x7c4e81)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Color(hex: 0x3d2242), lineWidth: 0.8 * s))
                .overlay(HStack(spacing: 3 * s) {
                    Image(systemName: "arrowtriangle.left.fill"); Image(systemName: "arrowtriangle.right.fill")
                }.font(.system(size: 4 * s)).foregroundStyle(Color(hex: 0x3d2242)))
                .frame(width: 18 * s, height: 10 * s)
                .position(x: (G.seekStart - left + travel * fraction) * s, y: 8 * s)
        }
        .frame(width: width * s, height: 16 * s)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard deck.loaded else { return }
                let value = min(1, max(0, (drag.location.x / s + left - G.seekStart) / travel))
                scrub = Double(value) * deck.duration
            }
            .onEnded { _ in
                if let scrub { deck.seek(to: scrub) }
                scrub = nil
            })
        .focusable(deck.loaded)
        .onKeyPress(.leftArrow) { deck.seek(to: deck.position - 5); return .handled }
        .onKeyPress(.rightArrow) { deck.seek(to: deck.position + 5); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Deck \(deckName) position")
        .accessibilityValue("\(CratePlayer.clock(deck.position)) of \(CratePlayer.clock(deck.duration))")
        .accessibilityAdjustableAction { direction in deck.seek(to: deck.position + (direction == .increment ? 5 : -5)) }
        .help("Drag to seek deck \(deckName)")
        .position(x: (left + width / 2) * s, y: G.seekY * s)
    }

    // MARK: Mixer (left wing)

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) percent" }

    private func mixerPanel(_ s: CGFloat) -> some View {
        let labelFont = Font.system(size: legible(10 * s, 7.5), weight: .medium)
        let small = Font.system(size: legible(6.5 * s, 6), weight: .bold, design: .monospaced)
        let cf = mixer.crossfade
        return ZStack(alignment: .topLeading) {
            LimeFader(name: "Crossfader", value: $mixer.crossfade, range: 0...1, step: 0.05,
                      from: G.crossfade.from, to: G.crossfade.to, s: s,
                      describe: { $0 < 0.5 ? "toward deck A, \(Int(((0.5 - $0) * 200).rounded())) percent" : $0 > 0.5 ? "toward deck B, \(Int((($0 - 0.5) * 200).rounded())) percent" : "centre" })
            LimeFader(name: "Master volume", value: $mixer.master, range: 0...1, step: 0.05,
                      from: G.master.from, to: G.master.to, s: s, describe: percent)
            place(Text("Crossfade").font(labelFont).foregroundStyle(P.label).allowsHitTesting(false), 161, 159, 80, 12, s)
            place(Text("Master").font(labelFont).foregroundStyle(P.label).allowsHitTesting(false), 259, 159, 80, 12, s)
            place(Text("A").font(small).foregroundStyle(P.label.opacity(cf < 0.5 ? 1 : 0.6)).allowsHitTesting(false), 117, 144, 8, 10, s)
            place(Text("B").font(small).foregroundStyle(P.label.opacity(cf > 0.5 ? 1 : 0.6)).allowsHitTesting(false), 206, 144, 8, 10, s)
            deckFaders(a, name: "A", level: $mixer.levelA, firstX: 0, s: s)
            deckFaders(b, name: "B", level: $mixer.levelB, firstX: 5, s: s)
            ForEach(Array(["V", "P", "L", "M", "H", "V", "P", "L", "M", "H"].enumerated()), id: \.offset) { index, letter in
                place(Text(letter).font(small).foregroundStyle(P.label.opacity(0.85)).allowsHitTesting(false), G.faderX[index], 259, 12, 8, s)
            }
            deckRow(a, name: "A", x: 120, s: s)
            deckRow(b, name: "B", x: 213, s: s)
            place(LimeHit(name: "Reset crossfader, levels, pitch and EQ", shape: RoundedRectangle(cornerRadius: 2 * s)) { mixer.reset([a, b]) } label: {
                Text("reset").font(.system(size: legible(9 * s, 7), weight: .medium)).foregroundStyle(P.reset)
            }, G.reset.x, G.reset.y, 30, 11, s)
        }
    }

    private func deckFaders(_ d: CratePlayer, name: String, level: Binding<Double>, firstX: Int, s: CGFloat) -> some View {
        let x = Array(G.faderX[firstX..<(firstX + 5)])
        func dB(_ value: Double) -> String { value > -0.25 ? "flat" : String(format: "%.0f dB", value) }
        func column(_ i: Int) -> (CGPoint, CGPoint) { (G.p(x[i], G.faderBottom), G.p(x[i], G.faderTop)) }
        return ZStack(alignment: .topLeading) {
            LimeFader(name: "Deck \(name) level", value: level, range: 0...1, step: 0.05,
                      from: column(0).0, to: column(0).1, s: s, describe: percent)
            LimeFader(name: "Deck \(name) pitch", value: Binding(get: { d.rate }, set: { d.rate = $0 }), range: 0.92...1.08, step: 0.005,
                      from: column(1).0, to: column(1).1, s: s, describe: { String(format: "%+.1f percent", ($0 - 1) * 100) })
            LimeFader(name: "Deck \(name) low EQ", value: Binding(get: { d.bass }, set: { d.bass = $0 }), range: -24...0, step: 1,
                      from: column(2).0, to: column(2).1, s: s, describe: dB)
            LimeFader(name: "Deck \(name) mid EQ", value: Binding(get: { d.mid }, set: { d.mid = $0 }), range: -24...0, step: 1,
                      from: column(3).0, to: column(3).1, s: s, describe: dB)
            LimeFader(name: "Deck \(name) high EQ", value: Binding(get: { d.high }, set: { d.high = $0 }), range: -24...0, step: 1,
                      from: column(4).0, to: column(4).1, s: s, describe: dB)
            place(Text("DECK \(name)").font(.system(size: legible(7 * s, 6.5), weight: .bold, design: .rounded)).tracking(1.2 * s)
                    .foregroundStyle(P.label).allowsHitTesting(false), (x[0] + x[4]) / 2, 173, 70, 9, s)
        }
    }

    private func deckRow(_ d: CratePlayer, name: String, x: CGFloat, s: CGFloat) -> some View {
        let canPlay = d.loaded || !tracks.isEmpty
        return ZStack(alignment: .topLeading) {
            place(LimeHit(name: d.isPlaying ? "Pause deck \(name)" : "Play deck \(name)", shape: Circle(), action: {
                if d.loaded { d.toggle() } else if !tracks.isEmpty { step(d, 1, true) }
            }) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [P.purpleLight, P.purple, P.purpleDeep], center: UnitPoint(x: 0.35, y: 0.3),
                                                 startRadius: 0, endRadius: 8 * s))
                    Circle().strokeBorder(P.purpleRing, lineWidth: 1 * s)
                    Image(systemName: d.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 5.5 * s, weight: .bold)).foregroundStyle(P.purpleInk)
                }
            }.disabled(!canPlay), x + 7, G.deckRowY, 13, 13, s)
            place(CyberMarquee(text: d.loaded ? d.title : "Deck \(name) empty",
                               font: .system(size: legible(8 * s, 7), weight: .medium), colour: d.loaded ? P.rowText : P.label.opacity(0.7))
                .allowsHitTesting(false), x + 50, G.deckRowY, 70, 11, s)
        }
    }

    // MARK: Playlist (right wing)

    private func playlist(_ s: CGFloat) -> some View {
        let target = loadIntoB ? b : a
        let dd = G.dropdown, list = G.list
        let rowFont = Font.system(size: legible(11 * s, 9))
        let rowHeight = max(17 * s, 13)
        return ZStack(alignment: .topLeading) {
            place(Button { loadIntoB.toggle() } label: {
                HStack(spacing: 5 * s) {
                    RoundedRectangle(cornerRadius: 1 * s)
                        .fill(LinearGradient(colors: [Color(hex: 0xb6cfc8), Color(hex: 0x6f8c86)], startPoint: .top, endPoint: .bottom))
                        .overlay(Rectangle().fill(Color(hex: 0x2fb36a)).frame(width: 5 * s, height: 2 * s), alignment: .topLeading)
                        .frame(width: 16 * s, height: 8 * s)
                    Text("Load into deck \(loadIntoB ? "B" : "A")").font(.system(size: legible(12 * s, 9))).foregroundStyle(.black).lineLimit(1)
                    Spacer(minLength: 0)
                    ZStack {
                        Rectangle().fill(Color(hex: 0xd4d0c8))
                        Rectangle().strokeBorder(Color(hex: 0x808080), lineWidth: 0.8 * s)
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6 * s)).foregroundStyle(.black)
                    }.frame(width: 17 * s, height: 16 * s)
                }
                .padding(.leading, 4 * s).padding(.trailing, 2 * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .overlay(Rectangle().strokeBorder(Color(hex: 0x404040), lineWidth: 1 * s))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
             .accessibilityLabel("Playlist loads into deck \(loadIntoB ? "B" : "A")")
             .help("Click to switch the playlist between loading into deck A and deck B"),
                  dd.midX, dd.midY, dd.width, dd.height, s)
            place(Group {
                if tracks.isEmpty {
                    Text("No tracks in this view").font(rowFont).foregroundStyle(P.label)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(tracks) { track in
                                let current = track.path == target.path
                                Button { load(target, track) } label: {
                                    HStack(spacing: 4) {
                                        Text(track.title).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(track.bpm.map { String(format: "%.0f", $0) } ?? "—").monospacedDigit()
                                    }
                                    .font(rowFont)
                                    .foregroundStyle(current ? P.rowSelectedText : P.rowText)
                                    .padding(.horizontal, 4 * s)
                                    .frame(height: rowHeight)
                                    .background(current ? P.rowSelected : Color.white.opacity(0.001))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Load \(track.title) into deck \(loadIntoB ? "B" : "A")")
                                .help("\(track.artist.isEmpty ? "Unknown artist" : track.artist) — \(track.title). Click to load into deck \(loadIntoB ? "B" : "A"), paused.")
                            }
                        }
                    }.scrollIndicators(.never)
                }
            }, list.midX, list.midY, list.width, list.height, s)
        }
    }

    // MARK: Wing keys

    private func wingKeys(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if leftOpen {
                place(LimeHit(name: "Hide mixer", shape: RoundedRectangle(cornerRadius: 2 * s)) { leftOpen = false }, G.leftWingClose, 13, s)
                place(LimeHit(name: "Hide mixer", shape: Ellipse()) { leftOpen = false }, 26, 236, 24, 60, s)
            } else {
                place(LimeHit(name: "Show mixer", shape: Ellipse()) { leftOpen = true }, 318, 236, 16, 70, s)
            }
            if rightOpen {
                place(LimeHit(name: "Hide playlist", shape: RoundedRectangle(cornerRadius: 2 * s)) { rightOpen = false }, G.rightWingClose, 13, s)
                place(LimeHit(name: "Hide playlist", shape: Ellipse()) { rightOpen = false }, G.width - 26, 236, 24, 60, s)
            } else {
                place(LimeHit(name: "Show playlist", shape: Ellipse()) { rightOpen = true }, 610, 236, 16, 70, s)
            }
        }
    }
}
