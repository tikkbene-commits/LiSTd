import SwiftUI
import AppKit

// Cyber · Lilac recreates the supplied lilac media-player reference. Everything is
// drawn in the reference image's own 545 × 448 pixel space, and every control uses
// the same coordinates, so the artwork and its hit areas cannot drift apart.
enum CyberGeometry {
    static let width: CGFloat = 545
    static let height: CGFloat = 448

    static func points(_ values: [(CGFloat, CGFloat)]) -> [CGPoint] { values.map { CGPoint(x: $0.0, y: $0.1) } }

    // Catmull-Rom through traced points keeps outlines on the reference's edges.
    static func addSmooth(_ path: inout Path, _ points: [CGPoint], move: Bool) {
        guard points.count > 1 else { return }
        if move { path.move(to: points[0]) } else { path.addLine(to: points[0]) }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)], p1 = points[index]
            let p2 = points[index + 1], p3 = points[min(points.count - 1, index + 2)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
    }

    /// Joins smooth chains with sharp corners where chains meet (tips and cusps).
    static func outline(_ chains: [[CGPoint]]) -> Path {
        var path = Path()
        for (index, chain) in chains.enumerated() { addSmooth(&path, chain, move: index == 0) }
        path.closeSubpath()
        return path
    }

    static func open(_ points: [CGPoint]) -> Path {
        var path = Path()
        addSmooth(&path, points, move: true)
        return path
    }

    // MARK: Body — one silhouette: left lobe, screen panel, centre fin, wing and horn.
    static let bodyLeft = points([(49, 253), (43, 244), (39, 232), (32, 216), (26, 200), (21, 184), (18, 170),
        (17, 156), (20, 140), (29, 128), (41, 120), (51, 116), (56, 111), (59, 100), (59, 90), (56, 80), (51, 72),
        (42, 61), (33, 52), (23, 43), (16, 36), (13, 29), (15, 22), (20, 17), (30, 13), (46, 11), (62, 12), (93, 16),
        (124, 23), (150, 29), (173, 32), (205, 35), (228, 35), (248, 32), (265, 27), (281, 21)])
    static let finRight = points([(281, 21), (278, 31), (275, 40), (272, 48), (268, 56), (265, 65), (262, 76),
        (261, 88), (263, 98), (269, 105), (277, 110), (285, 113)])
    static let wingTop = points([(285, 113), (289, 104), (298, 99.5), (311, 95.5), (334, 88), (355, 80), (374, 72),
        (391, 64), (408, 55), (428, 45), (446, 36), (462, 28), (478, 20), (497, 13)])
    static let hornOuter = points([(497, 13), (498, 22), (496, 30), (493, 38), (489, 46), (485, 55), (479, 66),
        (473, 77), (469, 87), (465, 99), (461, 110), (458, 122), (456, 136), (455, 150), (455, 170), (456, 190),
        (458, 204), (461, 216), (465, 227), (470, 237), (476, 247), (482, 257), (489, 268), (496, 279), (502, 290),
        (507, 301), (510, 311), (512, 321), (511, 331), (508, 341), (505, 352), (501, 363), (494, 376), (486, 389),
        (477, 401), (467, 412), (457, 422), (446, 430), (433, 437)])
    // Up the horn's inner edge, then hidden behind the transport band and bowl.
    static let hornInner = points([(433, 437), (432, 428), (434, 419), (436, 411), (438, 403), (440, 395),
        (442, 385), (443, 374), (444, 364), (446, 353), (449, 342), (452, 331), (449, 318), (444, 304), (437, 288),
        (428, 275), (416, 264), (400, 253), (380, 246), (343, 244), (306, 246), (287, 252), (272, 263), (261, 275),
        (253, 288), (244, 292), (233, 288)])
    static let bodyArch = points([(233, 288), (229, 280), (222, 272), (214, 264), (205, 257), (194, 251),
        (178, 244), (162, 240), (146, 236), (128, 232), (110, 231), (98, 232), (88, 236), (77, 240), (69, 244),
        (62, 248), (49, 253)])
    static let body = outline([bodyLeft, finRight, wingTop, hornOuter, hornInner, bodyArch])

    // MARK: Transport band (the cream horseshoe holding the buttons).
    static let bandOuter = points([(266, 363), (258, 353), (252, 343), (248, 333), (245, 321), (245, 309),
        (247, 299), (250, 290), (255, 281), (261, 273), (269, 265), (279, 258), (291, 250), (304, 245), (320, 243),
        (343, 243), (366, 243), (386, 245), (397, 249), (410, 256), (420, 264), (428, 272), (434, 280), (439, 288),
        (442, 296), (444, 305), (444, 316), (443, 328), (440, 337), (436, 345), (431, 352), (427, 359)])
    static let bandInner = points([(427, 359), (428, 352), (431, 345), (433, 336), (433, 326), (431, 316),
        (428, 308), (423, 300), (415, 292), (406, 284), (391, 276), (370, 271), (343, 270), (320, 271), (299, 276),
        (284, 284), (274, 292), (267, 300), (262, 307), (258, 316), (256, 328), (257, 340), (261, 352), (266, 363)])
    static let band = outline([bandOuter, bandInner])

    // MARK: Bowl — the glossy teal basin with the M-shaped rim.
    static let bowlRim = points([(240.5, 281), (236, 289), (233, 300), (231, 312), (231, 324), (233, 334),
        (236, 342), (240, 349), (245, 356), (251, 364), (259, 372), (269, 380), (283, 388), (302, 396), (322, 400),
        (345, 402), (371, 400), (387, 396), (398, 392), (408, 387), (418, 380), (429, 372), (437, 364), (444, 355),
        (449, 346), (453, 337), (455, 326), (454, 312), (452, 296), (450.5, 281)])
    static let bowlRightHidden = points([(450.5, 281), (440, 288), (429, 299)])
    static let mRight = points([(429, 299), (416, 304), (404, 309), (392, 315), (382, 320), (370, 323), (360, 321),
        (352, 316), (347, 310), (344.5, 303)])
    static let mLeft = points([(344.5, 303), (342, 310), (337, 316), (329, 321), (318, 323), (306, 320), (296, 315),
        (286, 309), (275, 304), (264, 301)])
    static let bowlLeftHidden = points([(264, 301), (252, 290), (240.5, 281)])
    static let bowl = outline([bowlRim, bowlRightHidden, mRight, mLeft, bowlLeftHidden])

    // MARK: Pink ring — a tapered tube behind the body, in front of the wing and horn tip.
    typealias Cubic = (c1: CGPoint, c2: CGPoint, end: CGPoint)
    static let ringBackStart = CGPoint(x: 66, y: 246)
    static let ringBack: [Cubic] = [(CGPoint(x: 90, y: 300), CGPoint(x: 160, y: 345), CGPoint(x: 275, y: 378))]
    static let ringFrontStart = CGPoint(x: 281, y: 122)
    static let ringTop: Cubic = (CGPoint(x: 293, y: 84), CGPoint(x: 335, y: 44), CGPoint(x: 400, y: 41))
    static let ringRight: Cubic = (CGPoint(x: 462, y: 36), CGPoint(x: 518, y: 88), CGPoint(x: 522, y: 152))
    static let ringLower: Cubic = (CGPoint(x: 521, y: 200), CGPoint(x: 500, y: 236), CGPoint(x: 468, y: 258))
    /// Volume runs along `ringRight`: "+" at its start, "−" at this fraction.
    static let volumeEnd: CGFloat = 0.92

    static func cubic(_ start: CGPoint, _ curve: Cubic, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * start.x + b * curve.c1.x + c * curve.c2.x + d * curve.end.x,
                       y: a * start.y + b * curve.c1.y + c * curve.c2.y + d * curve.end.y)
    }

    static func samples(_ start: CGPoint, _ curves: [Cubic], perCurve: Int = 40) -> [CGPoint] {
        var result = [start]
        var from = start
        for curve in curves {
            for step in 1...perCurve { result.append(cubic(from, curve, CGFloat(step) / CGFloat(perCurve))) }
            from = curve.end
        }
        return result
    }

    /// A filled band of varying width around a centre line.
    static func ribbon(_ centre: [CGPoint], width: (CGFloat) -> CGFloat) -> Path {
        guard centre.count > 1 else { return Path() }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for index in centre.indices {
            let a = centre[max(0, index - 1)], b = centre[min(centre.count - 1, index + 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
            let half = width(CGFloat(index) / CGFloat(centre.count - 1)) / 2
            let normal = CGPoint(x: -dy / length * half, y: dx / length * half)
            left.append(CGPoint(x: centre[index].x + normal.x, y: centre[index].y + normal.y))
            right.append(CGPoint(x: centre[index].x - normal.x, y: centre[index].y - normal.y))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    // Perspective: about 7 px where it leaves the body, widening to 19 px by the bowl.
    static let ringBackPath = ribbon(samples(ringBackStart, ringBack)) { u in 7 + 12 * pow(min(1, u / 0.65), 2) }
    static let ringFrontPath: Path = {
        // Tail emerges from the body (1 → 19 px), stays 19 around the top/right,
        // and narrows quickly where it passes behind the horn.
        ribbon(samples(ringFrontStart, [ringTop, ringRight, ringLower])) { u in
            if u < 1.0 / 3 { return 1 + 18 * min(1, u * 3) }
            if u < 2.0 / 3 { return 19 }
            return 19 - 15 * pow((u - 2.0 / 3) * 3, 0.7)
        }
    }()

    /// The ball's resting point for a volume from 0 to 1, slightly inside the ring.
    static func volumePoint(_ volume: Double) -> CGPoint {
        let t = (1 - CGFloat(min(1, max(0, volume)))) * volumeEnd
        let point = cubic(ringTop.end, ringRight, t)
        let ahead = cubic(ringTop.end, ringRight, min(1, t + 0.01))
        let dx = ahead.x - point.x, dy = ahead.y - point.y
        let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return CGPoint(x: point.x - dy / length * 3.5, y: point.y + dx / length * 3.5)
    }

    /// The volume nearest a point on the ring, so the ball follows a drag.
    static func volume(at location: CGPoint) -> Double {
        var best = (distance: CGFloat.infinity, volume: 0.0)
        for step in 0...160 {
            let volume = Double(step) / 160
            let point = volumePoint(volume)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < best.distance { best = (distance, volume) }
        }
        return best.volume
    }

    static var volumeTrack: Path {
        var path = Path()
        path.addLines((0...60).map { volumePoint(Double($0) / 60) })
        return path
    }

    // MARK: Transport tiles: centre, size and tilt along the band.
    struct Tile { let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, angle: Double, symbol: String }
    static let previousTile = Tile(x: 265, y: 288, width: 20, height: 15, angle: -46, symbol: "backward.end.alt.fill")
    static let backTile = Tile(x: 282, y: 268.5, width: 25, height: 16, angle: -27, symbol: "backward.fill")
    static let pauseTile = Tile(x: 309, y: 257.5, width: 29, height: 18, angle: -9, symbol: "pause.fill")
    static let stopTile = Tile(x: 378.5, y: 257.5, width: 29, height: 18, angle: 9, symbol: "stop.fill")
    static let forwardTile = Tile(x: 405, y: 268.5, width: 25, height: 16, angle: 27, symbol: "forward.fill")
    static let nextTile = Tile(x: 424.5, y: 285, width: 20, height: 15, angle: 46, symbol: "forward.end.alt.fill")
    static let tiles = [previousTile, backTile, pauseTile, stopTile, forwardTile, nextTile]
    static let playCentre = CGPoint(x: 343.5, y: 251)
    static let screen = CGRect(x: 70.5, y: 48, width: 180.5, height: 138)
    static let titleField = CGRect(x: 292, y: 130.5, width: 93.5, height: 22)
    static let timeField = CGRect(x: 391.5, y: 130.5, width: 39.5, height: 22)
    /// Seek knob travel along the groove under the screen.
    static let seekStart: CGFloat = 86, seekEnd: CGFloat = 244, seekY: CGFloat = 196
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

// Palette sampled from the reference image.
enum CyberPalette {
    static let lilacLight = Color(hex: 0xdfe3ec)
    static let lilac = Color(hex: 0xc4c8d8)
    static let lilacLow = Color(hex: 0xb6bad2)
    static let lilacRim = Color(hex: 0x7d80b4)
    static let navy = Color(hex: 0x1d1e3c)
    static let ink = Color(hex: 0x3f4275)
    static let glyph = Color(hex: 0x6265a1)
    static let pink = Color(hex: 0xb08daf)
    static let pinkLight = Color(hex: 0xf3dde6)
    static let pinkDark = Color(hex: 0x4f354f)
    static let cream = Color(hex: 0xe6d8c2)
    static let creamLight = Color(hex: 0xf4eee4)
    static let tan = Color(hex: 0xb39a78)
    static let tanEdge = Color(hex: 0xc59d6a)
    static let tealLight = Color(hex: 0xdce9ee)
    static let teal = Color(hex: 0xb6ced8)
    static let tealDeep = Color(hex: 0x3e5162)
    static let field = Color(hex: 0xdfe3ec)
}

struct CyberArtwork: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / CyberGeometry.width, y: size.height / CyberGeometry.height)
            CyberArtwork.draw(in: &context)
        }.accessibilityHidden(true)
    }

    private static let page = Path(CGRect(x: -200, y: -200, width: 945, height: 848))

    /// Darkens (or lightens) the inside of `shape` along the edges facing `offset`.
    private static func innerShade(_ context: inout GraphicsContext, _ shape: Path, offset: CGSize,
                                   color: Color, blur: CGFloat) {
        context.drawLayer { layer in
            layer.clip(to: shape)
            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: blur))
                var outside = page
                outside.addPath(shape.offsetBy(dx: -offset.width, dy: -offset.height))
                soft.fill(outside, with: .color(color), style: FillStyle(eoFill: true))
            }
        }
    }

    private static func softStroke(_ context: inout GraphicsContext, _ path: Path, clip: Path, color: Color,
                                   width: CGFloat, blur: CGFloat) {
        context.drawLayer { layer in
            layer.clip(to: clip)
            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: blur))
                soft.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private static func glow(_ context: inout GraphicsContext, clip: Path, centre: CGPoint, size: CGSize,
                             angle: Double, color: Color = .white, blur: CGFloat) {
        context.drawLayer { layer in
            layer.clip(to: clip)
            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: blur))
                soft.translateBy(x: centre.x, y: centre.y)
                soft.rotate(by: .degrees(angle))
                soft.fill(Path(ellipseIn: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)),
                          with: .color(color))
            }
        }
    }

    private static func drawRing(_ context: inout GraphicsContext, _ ring: Path) {
        context.fill(ring, with: .color(CyberPalette.pink))
        innerShade(&context, ring, offset: CGSize(width: -3, height: -3.5), color: CyberPalette.pinkLight, blur: 2.2)
        innerShade(&context, ring, offset: CGSize(width: 4.5, height: 5), color: CyberPalette.pinkDark, blur: 3)
        context.stroke(ring, with: .color(Color(hex: 0x5a4058, opacity: 0.7)), lineWidth: 0.6)
    }

    static func draw(in context: inout GraphicsContext) {
        typealias G = CyberGeometry
        // Ring first: the body hides the parts that pass behind it.
        drawRing(&context, G.ringBackPath)
        drawRing(&context, G.ringFrontPath)

        // Body: lilac fill, top-left light, all-round rim and a deep bottom-right edge.
        let body = G.body
        context.fill(body, with: .linearGradient(Gradient(stops: [
            .init(color: Color(hex: 0xd3d7e6), location: 0), .init(color: Color(hex: 0xbfc3d6), location: 0.45),
            .init(color: Color(hex: 0xb0b4cf), location: 1)]), startPoint: CGPoint(x: 0, y: 20), endPoint: CGPoint(x: 0, y: 420)))
        innerShade(&context, body, offset: CGSize(width: -6, height: -6), color: .white.opacity(0.75), blur: 5)
        softStroke(&context, body, clip: body, color: Color(hex: 0x6b6eaf), width: 6, blur: 2)
        // Two-stage tube shading: a wide violet falloff, then a near-black lip
        // (sampled as ~25 px from #a8adcb to #13141f on the horn and lower edge).
        innerShade(&context, body, offset: CGSize(width: 18, height: 18), color: Color(hex: 0x4f5290, opacity: 0.7), blur: 11)
        innerShade(&context, body, offset: CGSize(width: 9, height: 9), color: Color(hex: 0x1b1c3c, opacity: 0.85), blur: 6)
        // Shadow recess around the transport band.
        softStroke(&context, G.open(G.bandOuter), clip: body, color: Color(hex: 0x2e2f66, opacity: 0.8), width: 28, blur: 9)
        // Specular highlights sampled from the reference.
        glow(&context, clip: body, centre: CGPoint(x: 45, y: 29), size: CGSize(width: 32, height: 11), angle: 14, blur: 3)
        glow(&context, clip: body, centre: CGPoint(x: 46, y: 140), size: CGSize(width: 50, height: 13), angle: -55, blur: 4)
        glow(&context, clip: body, centre: CGPoint(x: 357, y: 90), size: CGSize(width: 128, height: 18), angle: -26, blur: 4)
        glow(&context, clip: body, centre: CGPoint(x: 458, y: 370), size: CGSize(width: 9, height: 62), angle: 8, blur: 3)
        context.stroke(body, with: .linearGradient(Gradient(colors: [Color(hex: 0x999ec4), Color(hex: 0x13142a)]),
                       startPoint: CGPoint(x: 100, y: 20), endPoint: CGPoint(x: 460, y: 430)), lineWidth: 1.1)

        // Pink ring passes in front of the wing and horn tip.
        context.drawLayer { front in
            front.clip(to: Path(CGRect(x: 283, y: 0, width: 262, height: 160)))
            drawRing(&front, G.ringFrontPath)
        }
        var groove = Path()
        groove.addLines((0...40).map { step -> CGPoint in
            let point = G.volumePoint(1 - Double(step) / 40)
            return CGPoint(x: point.x - 0.6, y: point.y + 0.6)
        })
        context.stroke(groove, with: .color(Color(hex: 0x6d4f6b, opacity: 0.75)), lineWidth: 0.8)
        context.draw(Text("+").font(.system(size: 7, weight: .bold)).foregroundColor(Color(hex: 0x4a3448)), at: CGPoint(x: 401, y: 40))
        context.draw(Text("–").font(.system(size: 7, weight: .bold)).foregroundColor(Color(hex: 0x4a3448)), at: CGPoint(x: 521, y: 140))
        var speaker = Path()
        speaker.move(to: CGPoint(x: 519, y: 157)); speaker.addLine(to: CGPoint(x: 525, y: 153.5))
        speaker.addLine(to: CGPoint(x: 525, y: 160.5)); speaker.closeSubpath()
        context.stroke(speaker, with: .color(Color(hex: 0x483648)), lineWidth: 0.9)
        context.fill(Path(CGRect(x: 525.5, y: 155.5, width: 1.2, height: 3)), with: .color(Color(hex: 0x483648)))

        drawPanel(&context)
        drawBowl(&context)
        drawBand(&context)
    }

    private static func drawPanel(_ context: inout GraphicsContext) {
        typealias G = CyberGeometry
        // Recessed black screen.
        let frame = G.screen.insetBy(dx: -2.5, dy: -2.5)
        var shadowEdge = Path(); shadowEdge.move(to: CGPoint(x: frame.minX, y: frame.maxY))
        shadowEdge.addLine(to: CGPoint(x: frame.minX, y: frame.minY)); shadowEdge.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        var lightEdge = Path(); lightEdge.move(to: CGPoint(x: frame.maxX, y: frame.minY))
        lightEdge.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY)); lightEdge.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        context.stroke(shadowEdge, with: .color(Color(hex: 0x9297bd)), lineWidth: 2.5)
        context.stroke(lightEdge, with: .color(Color(hex: 0xe8ebf5)), lineWidth: 2.5)
        context.fill(Path(roundedRect: G.screen, cornerRadius: 1.5), with: .color(.black))

        // Seek groove.
        var groove = Path(); groove.move(to: CGPoint(x: 91, y: 195.5)); groove.addLine(to: CGPoint(x: 250, y: 195.5))
        context.stroke(groove, with: .color(Color(hex: 0x8a8ba1)), lineWidth: 1.1)
        context.stroke(groove.offsetBy(dx: 0, dy: 1.4), with: .color(Color(hex: 0xeef0f7)), lineWidth: 1)
        context.stroke(groove.offsetBy(dx: 0, dy: -2.2), with: .color(Color(hex: 0xafb3c4, opacity: 0.7)), lineWidth: 0.8)

        // Display fields.
        for field in [G.titleField, G.timeField] {
            let shape = Path(roundedRect: field, cornerRadius: 3)
            context.fill(shape, with: .color(CyberPalette.field))
            innerShade(&context, shape, offset: CGSize(width: -1.5, height: -1.5), color: Color(hex: 0x9ea3c8), blur: 1)
            context.stroke(shape, with: .color(Color(hex: 0xeef0f6, opacity: 0.8)), lineWidth: 0.6)
        }

        // Minimize / close keys.
        for (x, close) in [(408.0, false), (426.0, true)] {
            let key = Path(roundedRect: CGRect(x: x, y: 90, width: 12, height: 12), cornerRadius: 1.5)
            context.fill(key, with: .linearGradient(Gradient(colors: [Color(hex: 0xe8ebf5), Color(hex: 0xbdc1d8)]),
                         startPoint: CGPoint(x: x, y: 90), endPoint: CGPoint(x: x + 12, y: 102)))
            context.stroke(key, with: .color(Color(hex: 0x8a8dbb)), lineWidth: 0.7)
            var mark = Path()
            if close {
                mark.move(to: CGPoint(x: x + 3, y: 93)); mark.addLine(to: CGPoint(x: x + 9, y: 99))
                mark.move(to: CGPoint(x: x + 9, y: 93)); mark.addLine(to: CGPoint(x: x + 3, y: 99))
            } else {
                mark.move(to: CGPoint(x: x + 3, y: 99)); mark.addLine(to: CGPoint(x: x + 9, y: 99))
            }
            context.stroke(mark, with: .color(Color(hex: 0x3c3e5e)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // Round playlist / open buttons.
        for (x, symbol) in [(381.0, "doc.text"), (417.5, "folder")] {
            let centre = CGPoint(x: x, y: 190)
            let outer = Path(ellipseIn: CGRect(x: x - 13.5, y: 176.5, width: 27, height: 27))
            context.fill(outer, with: .linearGradient(Gradient(colors: [Color(hex: 0xf0f2f9), Color(hex: 0x7b7db6)]),
                         startPoint: CGPoint(x: x - 10, y: 178), endPoint: CGPoint(x: x + 10, y: 202)))
            let face = Path(ellipseIn: CGRect(x: x - 11, y: 179, width: 22, height: 22))
            context.fill(face, with: .linearGradient(Gradient(colors: [Color(hex: 0xb3b7d8), Color(hex: 0xdde0f0)]),
                         startPoint: CGPoint(x: x - 8, y: 181), endPoint: CGPoint(x: x + 8, y: 199)))
            context.stroke(outer, with: .color(Color(hex: 0x6265a1, opacity: 0.6)), lineWidth: 0.7)
            context.draw(Text(Image(systemName: symbol)).font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: 0x3f4275)), at: centre)
        }

        // Eye (spectrum) and speed arrows.
        var eye = Path()
        eye.move(to: CGPoint(x: 259, y: 166))
        eye.addQuadCurve(to: CGPoint(x: 275, y: 166), control: CGPoint(x: 267, y: 159))
        eye.addQuadCurve(to: CGPoint(x: 259, y: 166), control: CGPoint(x: 267, y: 173))
        context.stroke(eye, with: .color(Color(hex: 0x7b7eb4)), lineWidth: 1.2)
        context.fill(Path(ellipseIn: CGRect(x: 264.3, y: 163.3, width: 5.4, height: 5.4)), with: .color(CyberPalette.glyph))
        for (tip, base) in [(257.5, 263.0), (272.5, 267.0)] {
            var arrow = Path()
            arrow.move(to: CGPoint(x: tip, y: 177)); arrow.addLine(to: CGPoint(x: base, y: 173.8))
            arrow.addLine(to: CGPoint(x: base, y: 180.2)); arrow.closeSubpath()
            context.fill(arrow, with: .color(CyberPalette.glyph))
        }

        // Tri-colour mark.
        let mark = CGPoint(x: 46, y: 162.5)
        // Three separate strokes: a red hook on top, a lilac slash low left, a peach curl right.
        for (start, end, colour) in [(-145.0, -75.0, Color(hex: 0xc0606a)), (115.0, 170.0, Color(hex: 0x8d91c8)),
                                     (0.0, 60.0, Color(hex: 0xedc29a))] {
            var arc = Path()
            arc.addArc(center: mark, radius: 7.5, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
            context.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    private static func drawBowl(_ context: inout GraphicsContext) {
        typealias G = CyberGeometry
        let bowl = G.bowl
        context.drawLayer { shadow in
            shadow.clip(to: G.body)
            shadow.addFilter(.blur(radius: 5))
            shadow.fill(bowl.offsetBy(dx: 4, dy: 3), with: .color(CyberPalette.navy.opacity(0.55)))
        }
        context.fill(bowl, with: .linearGradient(Gradient(stops: [
            .init(color: CyberPalette.tealLight, location: 0), .init(color: Color(hex: 0xc4d5df), location: 0.4),
            .init(color: CyberPalette.teal, location: 0.65), .init(color: Color(hex: 0x7aa4b6), location: 0.86),
            .init(color: CyberPalette.tealDeep, location: 1)]), startPoint: CGPoint(x: 0, y: 296), endPoint: CGPoint(x: 0, y: 403)))
        innerShade(&context, bowl, offset: CGSize(width: -5, height: -5), color: .white.opacity(0.9), blur: 4)
        softStroke(&context, bowl, clip: bowl, color: Color(hex: 0x5f8aa1), width: 5, blur: 2.5)
        innerShade(&context, bowl, offset: CGSize(width: 7, height: 7), color: Color(hex: 0x1f3040, opacity: 0.85), blur: 6)
        // Gloss under the M rim and a soft spot below the cusp.
        var rim = Path()
        G.addSmooth(&rim, G.mRight, move: true)
        G.addSmooth(&rim, G.mLeft, move: false)   // separate chain keeps the cusp sharp
        softStroke(&context, rim.offsetBy(dx: 0, dy: 5), clip: bowl, color: .white, width: 5, blur: 2.5)
        glow(&context, clip: bowl, centre: CGPoint(x: 300, y: 338), size: CGSize(width: 70, height: 16), angle: 14, blur: 6)
        glow(&context, clip: bowl, centre: CGPoint(x: 389, y: 338), size: CGSize(width: 70, height: 16), angle: -14, blur: 6)
        context.stroke(rim, with: .color(Color(hex: 0x3e5a6b)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .miter))
        context.stroke(bowl, with: .color(Color(hex: 0x22313d, opacity: 0.8)), lineWidth: 1)
        // Wordmark (replaces the reference's brand with LiStD).
        let word = Text("LiStD").font(.system(size: 16, weight: .black, design: .rounded)).italic()
        context.draw(word.foregroundColor(Color(hex: 0x33424e)), at: CGPoint(x: 345.2, y: 362.2))
        context.draw(word.foregroundColor(.white), at: CGPoint(x: 344, y: 361))
    }

    private static func drawBand(_ context: inout GraphicsContext) {
        typealias G = CyberGeometry
        let band = G.band
        context.fill(band, with: .linearGradient(Gradient(colors: [CyberPalette.creamLight, CyberPalette.cream, Color(hex: 0xdccbb0)]),
                     startPoint: CGPoint(x: 0, y: 240), endPoint: CGPoint(x: 0, y: 362)))
        softStroke(&context, G.open(G.bandOuter), clip: band, color: .white, width: 4, blur: 1.5)
        softStroke(&context, G.open(G.bandInner), clip: band, color: CyberPalette.tan, width: 7, blur: 2.5)
        context.stroke(G.open(G.bandInner), with: .color(CyberPalette.tanEdge), lineWidth: 1.3)
        context.stroke(band, with: .color(Color(hex: 0x9e8668, opacity: 0.85)), lineWidth: 0.8)

        for tile in G.tiles {
            var layer = context
            layer.clip(to: band)
            layer.translateBy(x: tile.x, y: tile.y)
            layer.rotate(by: .degrees(tile.angle))
            let rect = CGRect(x: -tile.width / 2, y: -tile.height / 2, width: tile.width, height: tile.height)
            let face = Path(roundedRect: rect, cornerRadius: 2)
            layer.fill(face, with: .linearGradient(Gradient(colors: [Color(hex: 0xf8f2e8), Color(hex: 0xd9c7aa)]),
                       startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            layer.stroke(face, with: .color(Color(hex: 0x8f7756)), lineWidth: 1.1)
            var shine = Path(); shine.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 1))
            shine.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 1))
            layer.stroke(shine, with: .color(.white.opacity(0.9)), lineWidth: 0.8)
            layer.draw(Text(Image(systemName: tile.symbol)).font(.system(size: tile.height * 0.46, weight: .heavy))
                .foregroundColor(Color(hex: 0x6f624f)), at: .zero)
        }

        // Play button and its cream bezel.
        let centre = G.playCentre
        let bezel = Path(ellipseIn: CGRect(x: centre.x - 21, y: centre.y - 21, width: 42, height: 42))
        context.fill(bezel, with: .linearGradient(Gradient(colors: [Color(hex: 0xf6efe4), Color(hex: 0xd3b78f)]),
                     startPoint: CGPoint(x: 0, y: centre.y - 21), endPoint: CGPoint(x: 0, y: centre.y + 21)))
        context.stroke(bezel, with: .color(Color(hex: 0xb0946e)), lineWidth: 1)
        let button = Path(ellipseIn: CGRect(x: centre.x - 16.5, y: centre.y - 16.5, width: 33, height: 33))
        context.fill(button, with: .radialGradient(Gradient(colors: [Color(hex: 0xe2e8ff), Color(hex: 0xa3abdc), Color(hex: 0x5b5f9a)]),
                     center: CGPoint(x: centre.x - 5, y: centre.y - 7), startRadius: 0, endRadius: 24))
        context.stroke(button, with: .color(Color(hex: 0x3f4277)), lineWidth: 1)
        var play = Path()
        play.move(to: CGPoint(x: centre.x - 4.5, y: centre.y - 8.5)); play.addLine(to: CGPoint(x: centre.x + 8.5, y: centre.y))
        play.addLine(to: CGPoint(x: centre.x - 4.5, y: centre.y + 8.5)); play.closeSubpath()
        context.fill(play.offsetBy(dx: 0.6, dy: 0.8), with: .color(.white.opacity(0.45)))
        context.fill(play, with: .color(Color(hex: 0x4b4f82)))
    }
}

// MARK: - Live controls

private struct CyberPress<S: Shape>: ButtonStyle {
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(CyberPalette.navy.opacity(configuration.isPressed ? 0.24 : 0)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A transparent control over the artwork: brightens on hover, darkens when pressed
/// and greys out when unavailable.
private struct CyberHit<S: Shape, Label: View>: View {
    let name: String
    let shape: S
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            ZStack {
                shape.fill(Color.white.opacity(hovering && enabled ? 0.16 : 0.001))
                label()
                if !enabled { shape.fill(CyberPalette.lilac.opacity(0.45)) }
            }.contentShape(shape)
        }
        .buttonStyle(CyberPress(shape: shape))
        .onHover { hovering = $0 }
        .accessibilityLabel(name).help(name)
    }
}

private extension CyberHit where Label == EmptyView {
    init(name: String, shape: S, action: @escaping () -> Void) {
        self.init(name: name, shape: shape, action: action, label: { EmptyView() })
    }
}

private struct CyberVolumeTrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / CyberGeometry.width
        return CyberGeometry.volumeTrack
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .strokedPath(StrokeStyle(lineWidth: 22 * scale, lineCap: .round))
    }
}

struct CyberMarquee: View {
    let text: String
    let font: Font
    let colour: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { box in
            let overflow = textWidth > box.size.width + 0.5
            let scrolling = overflow && !reduceMotion
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !scrolling)) { timeline in
                let gap: CGFloat = 36
                let cycle = Double(textWidth + gap)
                let offset = scrolling ? -CGFloat((timeline.date.timeIntervalSinceReferenceDate * 24).truncatingRemainder(dividingBy: cycle)) : 0
                HStack(spacing: gap) {
                    label(fixed: scrolling)
                    if scrolling { label(fixed: true) }
                }
                .offset(x: offset)
                .frame(width: box.size.width, height: box.size.height, alignment: .leading)
            }
            .clipped()
            .background(label(fixed: true).hidden().background(GeometryReader { measure in
                Color.clear.onAppear { textWidth = measure.size.width }
                    .onChange(of: measure.size.width) { _, width in textWidth = width }
            }))
        }
        .accessibilityElement().accessibilityLabel(text)
    }

    @ViewBuilder func label(fixed: Bool) -> some View {
        let base = Text(text).font(font).foregroundStyle(colour).lineLimit(1)
        if fixed { base.fixedSize() } else { base.truncationMode(.tail) }
    }
}

struct CyberPlayer: View {
    @ObservedObject var player: CratePlayer
    /// True when the collection pane has tracks to step through.
    var canStep: Bool
    /// Loads the track `offset` rows away in the collection; Bool = start playing.
    var step: (Int, Bool) -> Void
    var showTracks: () -> Void
    @State private var showRemaining = false
    @State private var scrub: Double?
    @FocusState private var volumeFocused: Bool
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var playerWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }
    private typealias G = CyberGeometry

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width / G.width, proxy.size.height / G.height)
            ZStack(alignment: .topLeading) {
                CyberArtwork().frame(width: G.width * s, height: G.height * s)
                screen(s)
                fields(s)
                seekBar(s)
                panelKeys(s)
                volumeControl(s)
                volumeKeys(s)
                transport(s)
            }
            .frame(width: G.width * s, height: G.height * s)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onReceive(clock) { _ in if scrub == nil { player.updatePosition() } }
    }

    private func legible(_ size: CGFloat, _ minimum: CGFloat) -> CGFloat { max(size, minimum) }

    private func place<V: View>(_ view: V, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ s: CGFloat) -> some View {
        view.frame(width: width * s, height: height * s).position(x: x * s, y: y * s)
    }

    private func tileHit(_ tile: G.Tile, _ name: String, _ s: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        CyberHit(name: name, shape: RoundedRectangle(cornerRadius: 2 * s), action: action)
            .disabled(!enabled)
            .frame(width: tile.width * s, height: tile.height * s)
            .rotationEffect(.degrees(tile.angle))
            .position(x: tile.x * s, y: tile.y * s)
    }

    // MARK: Screen

    private func screen(_ s: CGFloat) -> some View {
        let box = G.screen
        let status = player.loaded
            ? "\(player.isPlaying ? "PLAY" : "PAUSE")  \(CratePlayer.clock(player.position)) / \(CratePlayer.clock(player.duration))  \(String(format: "%.2f", player.rate))×"
            : "OPEN AUDIO  /  CHOOSE A TRACK"
        return place(ZStack(alignment: .bottom) {
            if player.spectrumVisible {
                SpectrumDisplay(analyzer: player.spectrum, playing: player.isPlaying)
                    .frame(height: box.height * 0.58 * s).padding(.horizontal, 6 * s).padding(.bottom, 4 * s)
                    .opacity(0.9)
            }
            VStack(alignment: .leading, spacing: 2 * s) {
                // Text keeps a legible minimum size when the player is scaled down.
                Text(player.title).font(.system(size: legible((player.spectrumVisible ? 11 : 15) * s, 9), weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xe6e8fb)).lineLimit(player.spectrumVisible ? 1 : 2)
                Text(player.artist).font(.system(size: legible((player.spectrumVisible ? 8 : 10) * s, 8), weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0xa3a8d8)).lineLimit(1)
                Text(status).font(.system(size: legible(6.5 * s, 7.5), weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8f94c8)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(7 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine), box.midX, box.midY, box.width, box.height, s)
    }

    // MARK: Fields

    private func fields(_ s: CGFloat) -> some View {
        let title = G.titleField, time = G.timeField
        let label = player.loaded ? (player.artist.isEmpty ? player.title : "\(player.title) – \(player.artist)") : "Choose a track"
        let position = player.loaded ? (showRemaining ? "-" + CratePlayer.clock(max(0, player.duration - player.position)) : CratePlayer.clock(player.position)) : "0:00"
        return ZStack(alignment: .topLeading) {
            place(CyberMarquee(text: label, font: .system(size: legible(8.5 * s, 7), weight: .semibold, design: .rounded), colour: CyberPalette.ink)
                .padding(.horizontal, 4 * s).allowsHitTesting(false), title.midX, title.midY, title.width, title.height, s)
            place(CyberHit(name: showRemaining ? "Show elapsed time" : "Show remaining time",
                           shape: RoundedRectangle(cornerRadius: 3 * s), action: { showRemaining.toggle() }) {
                Text(position).font(.system(size: legible(9 * s, 7), weight: .semibold, design: .monospaced))
                    .foregroundStyle(CyberPalette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }, time.midX, time.midY, time.width, time.height, s)
        }
    }

    // MARK: Seek

    private func seekBar(_ s: CGFloat) -> some View {
        let left: CGFloat = 80, width: CGFloat = 176, travel = G.seekEnd - G.seekStart
        let fraction = player.duration > 0 ? min(1, max(0, (scrub ?? player.position) / player.duration)) : 0
        return ZStack(alignment: .topLeading) {
            Color.white.opacity(0.001)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xf1e6d2), Color(hex: 0xb6a07f), Color(hex: 0x5a4834)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7 * s))
                .overlay(Circle().strokeBorder(Color(hex: 0x4b3c2c, opacity: 0.8), lineWidth: 0.7 * s))
                .shadow(color: .black.opacity(0.3), radius: 0.8 * s, y: 0.6 * s)
                .frame(width: 13 * s, height: 13 * s)
                .position(x: (G.seekStart - left + travel * fraction) * s, y: 8 * s)
        }
        .frame(width: width * s, height: 16 * s)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard player.loaded else { return }
                let value = min(1, max(0, (drag.location.x / s + left - G.seekStart) / travel))
                scrub = Double(value) * player.duration
            }
            .onEnded { _ in
                if let scrub { player.seek(to: scrub) }
                scrub = nil
            })
        .focusable(player.loaded)
        .onKeyPress(.leftArrow) { player.seek(to: player.position - 5); return .handled }
        .onKeyPress(.rightArrow) { player.seek(to: player.position + 5); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Track position")
        .accessibilityValue("\(CratePlayer.clock(player.position)) of \(CratePlayer.clock(player.duration))")
        .accessibilityAdjustableAction { direction in
            player.seek(to: player.position + (direction == .increment ? 5 : -5))
        }
        .help("Drag to seek")
        .position(x: (left + width / 2) * s, y: G.seekY * s)
    }

    // MARK: Panel keys

    private func panelKeys(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            place(CyberHit(name: "Minimize LiStD", shape: RoundedRectangle(cornerRadius: 1.5 * s)) { playerWindow?.miniaturize(nil) },
                  414, 96, 13, 13, s)
            place(CyberHit(name: "Close LiStD", shape: RoundedRectangle(cornerRadius: 1.5 * s)) { playerWindow?.performClose(nil) },
                  432, 96, 13, 13, s)
            place(CyberHit(name: "Show or hide tracks and imports", shape: Circle(), action: showTracks), 381, 190, 27, 27, s)
            place(CyberHit(name: "Open audio file", shape: Circle()) { player.openFile() }, 417.5, 190, 27, 27, s)
            place(CyberHit(name: player.spectrumVisible ? "Hide live spectrum" : "Show live spectrum", shape: Capsule()) {
                player.spectrumVisible.toggle()
            }, 267, 166, 19, 12, s)
            place(CyberHit(name: "Slower · speed −1%", shape: Rectangle()) { nudgeRate(-0.01) }, 260.5, 177, 9, 9, s)
            place(CyberHit(name: "Faster · speed +1%", shape: Rectangle()) { nudgeRate(0.01) }, 269.5, 177, 9, 9, s)
            place(CyberHit(name: "Reset speed to 1.00×", shape: Circle()) { player.rate = 1 }, 46, 162.5, 26, 24, s)
        }
    }

    private func nudgeRate(_ delta: Double) {
        player.rate = min(1.5, max(0.5, ((player.rate + delta) * 100).rounded() / 100))
    }

    // MARK: Volume ring

    private func volumeControl(_ s: CGFloat) -> some View {
        let ball = G.volumePoint(player.volume)
        return ZStack(alignment: .topLeading) {
            CyberVolumeTrackShape().fill(Color.white.opacity(0.001))
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xd7e6ef), Color(hex: 0x6d8aa0), Color(hex: 0x24364a)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7 * s))
                .overlay(Circle().strokeBorder(Color(hex: 0x1e2c3a, opacity: 0.8), lineWidth: 0.6 * s))
                .overlay(Circle().strokeBorder(Color.white.opacity(volumeFocused ? 0.95 : 0), lineWidth: 1.6 * s).padding(-2.5 * s))
                .shadow(color: .black.opacity(0.35), radius: 1 * s, x: 0.5 * s, y: 0.8 * s)
                .frame(width: 11 * s, height: 11 * s)
                .position(x: ball.x * s, y: ball.y * s)
        }
        .frame(width: G.width * s, height: G.height * s)
        .contentShape(CyberVolumeTrackShape())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            player.volume = G.volume(at: CGPoint(x: drag.location.x / s, y: drag.location.y / s))
        })
        .focusable()
        .focused($volumeFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { player.volume = min(1, player.volume + 0.05); return .handled }
        .onKeyPress(.rightArrow) { player.volume = min(1, player.volume + 0.05); return .handled }
        .onKeyPress(.downArrow) { player.volume = max(0, player.volume - 0.05); return .handled }
        .onKeyPress(.leftArrow) { player.volume = max(0, player.volume - 0.05); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((player.volume * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            player.volume = direction == .increment ? min(1, player.volume + 0.05) : max(0, player.volume - 0.05)
        }
        .help("Drag the ball along the ring to change volume")
    }

    private func volumeKeys(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            place(CyberHit(name: "Volume up", shape: Circle()) { player.volume = min(1, player.volume + 0.05) }, 401, 40, 12, 12, s)
            place(CyberHit(name: "Volume down", shape: Circle()) { player.volume = max(0, player.volume - 0.05) }, 521, 140, 12, 12, s)
            place(CyberHit(name: player.muted ? "Unmute" : "Mute", shape: Circle(), action: { player.toggleMute() }) {
                if player.muted {
                    Path { path in
                        path.move(to: CGPoint(x: 2.5 * s, y: 2.5 * s)); path.addLine(to: CGPoint(x: 9.5 * s, y: 9.5 * s))
                    }.stroke(Color(hex: 0xc0303a), style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
                }
            }, 523, 157, 12, 12, s)
        }
    }

    // MARK: Transport

    private func transport(_ s: CGFloat) -> some View {
        let loaded = player.loaded
        return ZStack(alignment: .topLeading) {
            tileHit(G.previousTile, "Previous track in the collection", s, enabled: canStep) { step(-1, player.isPlaying) }
            tileHit(G.backTile, "Back 10 seconds", s, enabled: loaded) { player.seek(to: player.position - 10) }
            tileHit(G.pauseTile, "Pause", s, enabled: loaded) { if player.isPlaying { player.toggle() } }
            tileHit(G.stopTile, "Stop", s, enabled: loaded) { player.stop() }
            tileHit(G.forwardTile, "Forward 10 seconds", s, enabled: loaded) { player.seek(to: player.position + 10) }
            tileHit(G.nextTile, "Next track in the collection", s, enabled: canStep) { step(1, player.isPlaying) }
            if player.isPlaying {
                Circle().stroke(Color(hex: 0xb9c3ff), lineWidth: 1.6 * s)
                    .shadow(color: Color(hex: 0x8f9cff), radius: 4 * s)
                    .frame(width: 34 * s, height: 34 * s)
                    .position(x: G.playCentre.x * s, y: G.playCentre.y * s)
                    .allowsHitTesting(false)
            }
            place(CyberHit(name: "Play", shape: Circle()) {
                if player.loaded { if !player.isPlaying { player.toggle() } }
                else if canStep { step(1, true) }
                else { player.openFile() }
            }, G.playCentre.x, G.playCentre.y, 33, 33, s)
        }
    }
}
