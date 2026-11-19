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
        print("Silverwave and blue/red boombox render checks passed.")
    }
}
