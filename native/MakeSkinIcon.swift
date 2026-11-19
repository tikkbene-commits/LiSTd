import SwiftUI
import AppKit

@main struct MakeSkinIcon {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let size = CGFloat(points * scale)
                let renderer = ImageRenderer(content:
                    ZStack {
                        RoundedRectangle(cornerRadius: size * 0.22).fill(CrateSkin.metal)
                        CrateEmblem().padding(size * 0.12)
                    }.frame(width: size, height: size))
                renderer.scale = 1
                guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
                assert(cgImage.width == Int(size) && cgImage.height == Int(size))
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                let suffix = scale == 2 ? "@2x" : ""
                try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
    }
}
