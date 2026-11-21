import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// Signal keeps the waveforms stacked so both beat grids share one visual time scale.
struct TechnicalPlayer: View {
    @ObservedObject var a: CratePlayer
    @ObservedObject var b: CratePlayer
    let analyze: (CratePlayer) -> Void
    @AppStorage("listd.waveformSeconds") private var waveformSeconds = 60.0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    static let green = Color(red: 0.34, green: 0.84, blue: 0.53)
    static let dim = Color(red: 0.52, green: 0.57, blue: 0.55)
    static let line = Color.white.opacity(0.12)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("LiStD").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("/  SIGNAL").tracking(3).foregroundStyle(Self.dim)
            }
            HStack(spacing: 12) {
                Text("VIEW").foregroundStyle(Self.dim)
                StableSlider(value: $waveformSeconds, in: 12...120, step: 12).frame(minWidth: 60, maxWidth: 180)
                    .accessibilityLabel("Waveform time window").help("Show more of each track; smaller values zoom into beats")
                Text("\(Int(waveformSeconds))s").monospacedDigit().frame(width: 34)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                Text("ONE-TIME SYNC").tracking(2).foregroundStyle(Self.dim)
                Button("Pause both") { if a.isPlaying { a.toggle() }; if b.isPlaying { b.toggle() } }
                    .disabled(!a.isPlaying && !b.isPlaying)
                Button("Play both") {
                    let time = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.15)
                    a.start(atHostTime: time); b.start(atHostTime: time)
                }.disabled(!a.loaded || !b.loaded)
                Button("Sync A to B") { a.sync(to: b) }
                    .disabled(!a.canSync || !b.canSync)
                    .help("Change A to match B’s effective tempo and beat phase. B remains unchanged. This is one-time alignment.")
                Button("Sync B to A") { b.sync(to: a) }
                    .disabled(!a.canSync || !b.canSync)
                    .help("Change B to match A’s effective tempo and beat phase. A remains unchanged. Set beat cues or analyze first; this is one-time alignment.")
            }.padding(.top, 10)
            }.padding(.horizontal, 24).padding(.vertical, 17)
            Rectangle().fill(Self.line).frame(height: 1)
            SignalDeck(player: a, name: "A", waveformSeconds: waveformSeconds, analyze: { analyze(a) })
            Rectangle().fill(Self.line).frame(height: 1)
            SignalDeck(player: b, name: "B", waveformSeconds: waveformSeconds, analyze: { analyze(b) })
            Rectangle().fill(Self.line).frame(height: 1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                SignalEQ(player: a, name: "A")
                SignalEQ(player: b, name: "B")
            }.padding(.horizontal, 24).padding(.vertical, 20)
        }
        .font(.system(size: 11, design: .monospaced))
        .buttonStyle(.bordered).controlSize(.small)
        .background(Color(red: 0.055, green: 0.065, blue: 0.061))
        .onReceive(timer) { _ in a.updatePosition(); b.updatePosition() }
    }
}

private struct SignalDeck: View {
    @ObservedObject var player: CratePlayer
    let name: String
    let waveformSeconds: Double
    let analyze: () -> Void
    @State private var taps: [TimeInterval] = []
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text(name).font(.system(size: 24, weight: .light, design: .monospaced)).foregroundStyle(TechnicalPlayer.green)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.loaded ? player.title : "Load a track into deck \(name)")
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(player.loaded ? player.artist : "Drop a track onto the waveform, or open a local file")
                        .font(.system(size: 10)).foregroundStyle(TechnicalPlayer.dim).lineLimit(1)
                }
                Spacer()
                Text("\(CratePlayer.clock(player.position)) / \(CratePlayer.clock(player.duration))")
                    .monospacedDigit().frame(width: 100, alignment: .trailing)
                Button("Open file") { player.openFile(autoplay: false) }.help("Load a local file into deck \(name)")
            }
            VStack(spacing: 5) {
                SignalWaveform(player: player, overview: false, windowSeconds: waveformSeconds).frame(height: 44)
                SignalWaveform(player: player, overview: true, windowSeconds: waveformSeconds).frame(height: 18)
            }
            .overlay(Rectangle().stroke(dropTargeted ? TechnicalPlayer.green : .clear, lineWidth: 2))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
                guard providers.count == 1, let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? URL { url = value }
                    else if let value = item as? String { url = URL(string: value) }
                    else { url = nil }
                    guard let url, url.isFileURL,
                          let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                          type.conforms(to: .audio) else { return }
                    Task { @MainActor in
                        player.play(path: url.path, title: "", artist: "Local audio", autoplay: false)
                    }
                }
                return true
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
                }.tint(TechnicalPlayer.green).disabled(!player.loaded)
                    .accessibilityLabel(player.isPlaying ? "Pause deck \(name)" : "Play deck \(name)")
                Button { player.stop() } label: { Image(systemName: "stop.fill") }
                    .disabled(!player.loaded).help("Stop deck \(name)")
                Button("Set beat") { player.setBeatCue() }.disabled(!player.loaded)
                    .help("Set the beat-grid anchor at the playhead. Click the waveform to find a kick first.")
                Button("−20 ms") { player.seek(to: player.position - 0.02) }.disabled(!player.loaded).help("Nudge deck \(name) backward")
                Button("+20 ms") { player.seek(to: player.position + 0.02) }.disabled(!player.loaded).help("Nudge deck \(name) forward")
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                Text("BPM").foregroundStyle(TechnicalPlayer.dim)
                TextField("BPM", value: Binding(get: { player.bpm }, set: { player.bpm = $0; player.bpmIsEstimate = false }), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder).frame(width: 58)
                    .onChange(of: player.bpm) { _, value in
                        if !value.isFinite || value < 0 || value > 250 { player.bpm = 0 }
                    }.accessibilityLabel("Deck \(name) original BPM")
                Button("½") { player.bpm /= 2; player.bpmIsEstimate = false }
                    .disabled(player.bpm < 80).help("Halve deck \(name) BPM if analysis found double tempo")
                Button("×2") { player.bpm *= 2; player.bpmIsEstimate = false }
                    .disabled(player.bpm == 0 || player.bpm > 125).help("Double deck \(name) BPM if analysis found half tempo")
                Button("Tap") {
                    let now = Date.timeIntervalSinceReferenceDate
                    if let last = taps.last, now - last > 2 { taps = [] }
                    taps.append(now)
                    taps = Array(taps.suffix(8))
                    if taps.count > 2, let first = taps.first {
                        let value = 60 * Double(taps.count - 1) / (now - first)
                        if (40...250).contains(value) { player.bpm = (value * 100).rounded() / 100; player.bpmIsEstimate = false }
                    }
                }.help("Tap the beat to set the original BPM")
                Text(String(format: "→ %.2f", player.effectiveBPM)).foregroundStyle(TechnicalPlayer.green).frame(width: 72)
                StableSlider(value: $player.rate, in: 0.5...1.5, step: 0.001).frame(minWidth: 65)
                    .accessibilityLabel("Deck \(name) tempo and pitch")
                Button(String(format: "%+.1f%%", (player.rate - 1) * 100)) { player.rate = 1 }
                    .frame(width: 62).help("Reset speed to 1×; pitch follows speed")
            }
            HStack(spacing: 8) {
                Text(player.analyzing ? "Analyzing beats…" : player.analysisNote)
                    .foregroundStyle(TechnicalPlayer.dim).lineLimit(1)
                if let cue = player.beatCue { Text(String(format: " / CUE %.2fs", cue)).foregroundStyle(TechnicalPlayer.dim) }
                Spacer()
                Button(player.analyzing ? "Analyzing…" : "Analyze beats", action: analyze)
                    .disabled(!player.loaded || player.analyzing)
            }.font(.system(size: 9))
        }.padding(.horizontal, 24).padding(.vertical, 12)
        .onChange(of: player.path) { _, _ in taps = [] }
    }
}

struct SignalWaveform: View {
    @ObservedObject var player: CratePlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var overview: Bool
    var windowSeconds: Double = 60
    private func start(at position: Double) -> Double {
        if overview { return 0 }
        if reduceMotion { return floor(position / span) * span }
        return position - span / 4
    }
    private var span: Double { overview ? max(1, player.duration) : windowSeconds * player.rate }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.isPlaying)) { _ in
            waveform(at: player.currentPosition)
        }
    }

    private func waveform(at position: Double) -> some View {
        let start = start(at: position)
        return GeometryReader { geometry in
            Canvas { context, size in
                let middle = size.height / 2
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: middle)); baseline.addLine(to: CGPoint(x: size.width, y: middle))
                context.stroke(baseline, with: .color(TechnicalPlayer.line), lineWidth: 0.5)
                if !overview, player.bpm > 0, player.bpm.isFinite, let cue = player.beatCue {
                    let length = 60 / player.bpm
                    let first = Int(floor((start - cue) / length))
                    let count = min(150, Int(ceil(span / length)) + 2)
                    for beat in first..<(first + count) {
                        let x = (cue + Double(beat) * length - start) / span * size.width
                        var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                    }
                }
                let points = player.waveform
                let width = Double(size.width)
                if !points.isEmpty, player.duration > 0 {
                    var wave = Path()
                    let density = Double(points.count) / player.duration
                    let step = max(1, Int(span * density / width * 2))
                    let first = max(0, Int(start * density) / step * step)
                    let last = min(points.count, max(0, Int(ceil((start + span) * density))))
                    var upper: [CGPoint] = []
                    var lower: [CGPoint] = []
                    // A filled, source-anchored envelope avoids subpixel shimmer from thin moving bars.
                    for low in stride(from: max(0, first - step), to: min(points.count, last + step), by: step) {
                        let high = min(points.count, low + step)
                        let amplitude = CGFloat(points[low..<high].max() ?? 0)
                        let height = max(0.5, min(1, amplitude) * (middle - 2) * (overview ? 0.9 : 0.55))
                        let x = (Double(low) / density - start) / span * width
                        upper.append(CGPoint(x: x, y: middle - height))
                        lower.append(CGPoint(x: x, y: middle + height))
                    }
                    wave.addLines(upper + lower.reversed())
                    wave.closeSubpath()
                    context.fill(wave, with: .color(TechnicalPlayer.green.opacity(overview ? 0.45 : 0.95)))
                }
                let x = (position - start) / span * size.width
                var head = Path(); head.move(to: CGPoint(x: x, y: 0)); head.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(head, with: .color(.white.opacity(0.85)), lineWidth: 1)
                if let cue = player.beatCue {
                    let cueX = (cue - start) / span * size.width
                    var marker = Path(); marker.move(to: CGPoint(x: cueX, y: 0)); marker.addLine(to: CGPoint(x: cueX, y: 7))
                    context.stroke(marker, with: .color(.orange), lineWidth: 2)
                }
            }
            .clipped()
            .background(Color.black.opacity(0.6))
            .overlay(alignment: .topLeading) {
                Text(overview ? "" : "\(Int(windowSeconds))s  /  \(nameForWaveform)")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(TechnicalPlayer.dim).padding(5)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                player.seek(to: start + min(1, max(0, value.location.x / max(1, geometry.size.width))) * span)
            })
            .accessibilityElement().accessibilityLabel(overview ? "Track overview" : "Track waveform")
            .accessibilityValue(CratePlayer.clock(position))
            .accessibilityAdjustableAction { direction in
                player.seek(to: player.position + (direction == .increment ? 1 : -1))
            }
            .help(overview ? "Click to seek anywhere in the track" : "Click a beat to seek; Set beat anchors the grid here")
        }
    }

    private var nameForWaveform: String { player.waveform.isEmpty ? "\(player.loaded ? "READING AUDIO" : "NO AUDIO")" : "WAVEFORM" }
}

private struct SignalEQ: View {
    @ObservedObject var player: CratePlayer
    let name: String
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(name) / MIXER").tracking(2).foregroundStyle(TechnicalPlayer.dim)
                Spacer()
                Button("Reset EQ") { player.resetEQ() }
                Button(player.muted ? "Unmute" : "Mute") { player.toggleMute() }
            }
            HStack(spacing: 16) {
                band("BASS", value: $player.bass)
                band("MID", value: $player.mid)
                band("HIGH", value: $player.high)
                VStack(spacing: 5) {
                    Text("LEVEL").font(.system(size: 9)).foregroundStyle(TechnicalPlayer.dim)
                    StableSlider(value: $player.volume, in: 0...1).accessibilityLabel("Deck \(name) level")
                    Text(String(format: "%.0f%%", player.volume * 100)).font(.system(size: 9))
                }
            }
        }
    }
    func band(_ label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 5) {
            Text(label).font(.system(size: 9)).foregroundStyle(TechnicalPlayer.dim)
            StableSlider(value: value, in: -24...0, step: 0.5).accessibilityLabel("Deck \(name) \(label.lowercased()) EQ")
            Text(String(format: "%.1f dB", value.wrappedValue)).font(.system(size: 9))
        }
    }
}
