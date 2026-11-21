import SwiftUI
import AppKit

@main struct CrateSkinCheck {
    @MainActor static func main() {
        let renderer = ImageRenderer(content: CrateEmblem().frame(width: 128, height: 128))
        guard let image = renderer.cgImage else { fatalError("Logo did not render") }
        precondition(image.width == 128 && image.height == 128)
        let pixels = NSBitmapImageRep(cgImage: image)
        var purplePixels = 0
        var chromePixels = 0
        for y in 0..<128 {
            for x in 0..<128 {
                guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.9 else { continue }
                if color.blueComponent > color.redComponent * 1.2 && color.redComponent > color.greenComponent * 1.1 { purplePixels += 1 }
                if color.redComponent > 0.7 && color.greenComponent > 0.7 && color.blueComponent > 0.7 { chromePixels += 1 }
            }
        }
        precondition(purplePixels > 1500, "Logo lost its purple face")
        precondition(chromePixels > 1500, "Logo lost its chrome bezel and mark")
        precondition(CrateSkin.silverwave.icon != CrateSkin.classic.icon)
        let boombox = ImageRenderer(content: BoomboxArtwork().frame(width: 716, height: 422))
        guard let boxImage = boombox.cgImage else { fatalError("Boombox did not render") }
        let boxPixels = NSBitmapImageRep(cgImage: boxImage)
        var bluePixels = 0
        var redPixels = 0
        var greenPixels = 0
        for y in 0..<boxImage.height {
            for x in 0..<boxImage.width {
                guard let color = boxPixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.9 else { continue }
                if color.blueComponent > color.redComponent * 1.5 && color.blueComponent > color.greenComponent * 1.2 { bluePixels += 1 }
                if color.redComponent > 0.5 && color.redComponent > color.greenComponent * 2 && color.redComponent > color.blueComponent * 2 { redPixels += 1 }
                if color.greenComponent > 0.4 && color.greenComponent > color.blueComponent * 1.4 && color.greenComponent > color.redComponent * 1.4 { greenPixels += 1 }
            }
        }
        precondition(bluePixels > 30000, "Boombox lost its blue shell")
        precondition(redPixels > 400, "Boombox lost its red lettering")
        precondition(greenPixels == 0, "Reference green must become blue")
        let png = boxPixels.representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: ".music-sorter/build/boombox-preview.png"))
        // Cyber · Lilac: sample landmarks at the reference's own pixel coordinates.
        let cyber = ImageRenderer(content: CyberArtwork().frame(width: CyberGeometry.width, height: CyberGeometry.height))
        cyber.scale = 1
        guard let cyberImage = cyber.cgImage else { fatalError("Cyber artwork did not render") }
        precondition(cyberImage.width == 545 && cyberImage.height == 448)
        let cyberPixels = NSBitmapImageRep(cgImage: cyberImage)
        func rgb(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            let c = cyberPixels.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        let screen = rgb(160, 120)
        precondition(screen.a > 0.99 && screen.r + screen.g + screen.b < 0.05, "Cyber screen must be black")
        let lilac = rgb(300, 200)
        precondition(lilac.b > lilac.r && lilac.b > lilac.g && lilac.r > 0.55, "Cyber body lost its lilac")
        let ring = rgb(522, 150)
        precondition(ring.r > ring.g + 0.08 && ring.b > ring.g + 0.04, "Cyber volume ring lost its pink")
        let lowerRing = rgb(170, 340)
        precondition(lowerRing.r > lowerRing.g + 0.08, "Cyber lower ring lost its pink")
        let band = rgb(251, 316)
        precondition(band.r > band.b + 0.06 && band.g > band.b + 0.03, "Cyber transport band lost its cream")
        let bowl = rgb(343, 375)
        precondition(bowl.b > bowl.r + 0.05 && bowl.g > bowl.r + 0.03, "Cyber bowl lost its teal")
        for (x, y) in [(343, 285), (320, 300), (5, 5), (510, 250), (120, 300)] {
            precondition(rgb(x, y).a < 0.05, "Cyber artwork must stay transparent at \(x),\(y)")
        }
        precondition(CrateSkin.cyber.title == "Cyber · Lilac" && CrateSkin.cyber.isArtwork && !CrateSkin.classic.isArtwork)
        // The volume ball follows the ring: "+" at full, "−" at silent, monotonic in between.
        let loud = CyberGeometry.volumePoint(1), quiet = CyberGeometry.volumePoint(0)
        precondition(hypot(loud.x - 400, loud.y - 44) < 6 && hypot(quiet.x - 518, quiet.y - 140) < 6)
        for volume in stride(from: 0.0, through: 1.0, by: 0.05) {
            precondition(abs(CyberGeometry.volume(at: CyberGeometry.volumePoint(volume)) - volume) < 0.01)
        }
        try! cyberPixels.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: ".music-sorter/build/cyber-preview.png"))
        var pitch = 1.0
        let host = NSHostingView(rootView: VerticalPitchSlider(value: Binding(get: { pitch }, set: { pitch = $0 }), scale: 2)
            .frame(width: 28, height: 72))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 28, height: 72), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func fader(in view: NSView) -> TrackingSlider? {
            (view as? TrackingSlider) ?? view.subviews.lazy.compactMap { fader(in: $0) }.first
        }
        guard let control = fader(in: host) else { fatalError("Native pitch fader is missing") }
        precondition(control.cell is PitchFaderCell && control.acceptsFirstResponder)
        precondition(window.makeFirstResponder(control) && window.firstResponder === control)
        precondition(control.accessibilityPerformIncrement() && abs(pitch - 1.01) < 0.0001)
        precondition(control.accessibilityPerformDecrement() && abs(pitch - 1) < 0.0001)
        print("Silverwave/Amped/Cyber render, Cyber volume ring and native vertical fader focus/accessibility checks passed.")
    }
}
