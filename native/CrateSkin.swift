import SwiftUI

enum CrateSkin: String, CaseIterable, Identifiable {
    case boombox, silverwave, classic, technical, cyber, limehead
    var id: String { rawValue }
    var title: String { self == .limehead ? "Limehead · Mix" : self == .cyber ? "Cyber · Lilac" : self == .technical ? "Signal · Dual Deck" : self == .boombox ? "Amped · Blue / Red" : self == .silverwave ? "Silverwave" : "LiStD · Original" }
    var icon: String { self == .silverwave ? "CrateSilverwave" : "Crate" }
    var accent: Color { self == .limehead ? Color(red: 0.24, green: 0.55, blue: 0.0) : self == .cyber ? Color(red: 0.38, green: 0.40, blue: 0.63) : self == .technical ? Color(red: 0.34, green: 0.84, blue: 0.53) : self == .boombox ? Color(red: 0.84, green: 0.025, blue: 0.055) : self == .silverwave ? Color(red: 0.39, green: 0.25, blue: 0.66) : .blue }
    /// Skins drawn as full-size vector artwork that need a taller player pane.
    var isArtwork: Bool { self == .boombox || self == .cyber || self == .limehead }
    /// Skins that play two decks at once; the collection offers A/B loading.
    var isDualDeck: Bool { self == .technical || self == .limehead }

    static let metal = LinearGradient(colors: [Color(red: 0.97, green: 0.97, blue: 1),
        Color(red: 0.76, green: 0.77, blue: 0.84), Color(red: 0.88, green: 0.89, blue: 0.94),
        Color(red: 0.60, green: 0.62, blue: 0.71)], startPoint: .top, endPoint: .bottom)
    static let ink = Color(red: 0.15, green: 0.16, blue: 0.24)
}

struct MetalPanel: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(CrateSkin.metal, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.85), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.black.opacity(0.28), lineWidth: 1).padding(1))
            .shadow(color: .black.opacity(0.17), radius: 2, y: 2)
    }
}

struct CrateEmblem: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(CrateSkin.metal)
                    .overlay(Circle().strokeBorder(Color(red: 0.32, green: 0.34, blue: 0.46), lineWidth: size * 0.025))
                    .shadow(color: .black.opacity(0.35), radius: size * 0.035, y: size * 0.025)
                Circle().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.10, blue: 0.27),
                    Color(red: 0.53, green: 0.36, blue: 0.77), Color(red: 0.23, green: 0.16, blue: 0.43)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(size * 0.12)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.67, green: 0.76, blue: 1)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.5), radius: size * 0.015, y: size * 0.025)
                Ellipse().stroke(LinearGradient(colors: [.white, Color(red: 0.64, green: 0.51, blue: 0.83), .white],
                    startPoint: .top, endPoint: .bottom), lineWidth: size * 0.045)
                    .frame(width: size * 1.04, height: size * 0.34).rotationEffect(.degrees(-35))
                Ellipse().fill(.white.opacity(0.18)).frame(width: size * 0.52, height: size * 0.17).offset(y: -size * 0.25)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

// A static screen motif, not an audio visualizer or playback indicator.
struct SilverwaveDisplay: View {
    let title: String
    let subtitle: String
    let count: String
    var body: some View {
        HStack(spacing: 22) {
            CrateEmblem().frame(width: 80, height: 80).padding(.leading, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("LiStD  /  SILVERWAVE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(Color(red: 0.75, green: 0.66, blue: 0.91))
                Text(title).font(.custom("Trebuchet MS Bold", size: 23)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(red: 0.78, green: 0.83, blue: 0.91)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(count).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(red: 0.76, green: 0.95, blue: 0.88)).padding(.trailing, 16)
        }
        .padding(18).frame(height: 130)
        .background {
            ZStack {
                Color(red: 0.04, green: 0.035, blue: 0.09)
                GeometryReader { proxy in
                    Path { path in
                        for line in 0..<8 {
                            let y = CGFloat(line) * 8
                            path.move(to: CGPoint(x: 0, y: 95 + y))
                            path.addCurve(to: CGPoint(x: proxy.size.width, y: 30 + y),
                                control1: CGPoint(x: proxy.size.width * 0.48, y: -90 + y),
                                control2: CGPoint(x: proxy.size.width * 0.56, y: 210 + y))
                        }
                    }.stroke(Color(red: 0.52, green: 0.31, blue: 0.80).opacity(0.3), lineWidth: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.black.opacity(0.8), lineWidth: 3))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.75)).padding(-2))
    }
}
