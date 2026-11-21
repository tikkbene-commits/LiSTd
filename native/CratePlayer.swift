import SwiftUI
import AVFoundation

// SwiftUI's macOS slider can animate its tracking overlay from the hosting origin.
// Keep the control and its tracking in one native coordinate space at every size.
struct StableSlider: NSViewRepresentable {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    var step: Double? = nil
    var editing: (Bool) -> Void = { _ in }
    @Environment(\.isEnabled) private var enabled

    init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double? = nil,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value; self.bounds = bounds; self.step = step; editing = onEditingChanged
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider()
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }
    func updateNSView(_ slider: TrackingSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = bounds.lowerBound; slider.maxValue = bounds.upperBound
        slider.doubleValue = value; slider.isEnabled = enabled
        slider.increment = step ?? (bounds.upperBound - bounds.lowerBound) / 100
        slider.editing = editing
    }
    final class Coordinator: NSObject {
        var parent: StableSlider
        init(_ parent: StableSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) {
            let raw = slider.doubleValue
            let value = parent.step.map { parent.bounds.lowerBound + ((raw - parent.bounds.lowerBound) / $0).rounded() * $0 } ?? raw
            let snapped = min(parent.bounds.upperBound, max(parent.bounds.lowerBound, value))
            slider.doubleValue = snapped
            parent.value = snapped
        }
    }
}

final class TrackingSlider: NSSlider {
    var editing: (Bool) -> Void = { _ in }
    var increment = 0.01
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        editing(true)
        super.mouseDown(with: event)
        // AppKit can restore its raw tracking value after the last continuous action.
        sendAction(action, to: target)
        editing(false)
    }
    private func adjust(_ delta: Double) -> Bool {
        guard isEnabled else { return false }
        editing(true)
        doubleValue = min(maxValue, max(minValue, doubleValue + delta))
        sendAction(action, to: target)
        editing(false)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if [123, 124, 125, 126].contains(event.keyCode) {
            _ = adjust(([123, 125].contains(event.keyCode) ? -1 : 1) * increment)
        } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformIncrement() -> Bool { adjust(increment) }
    override func accessibilityPerformDecrement() -> Bool { adjust(-increment) }
}

// Varispeed couples tempo and pitch, like changing a turntable's speed.
@MainActor final class CratePlayer: ObservableObject {
    @Published private(set) var title = "Choose a track"
    @Published private(set) var artist = "Play from your library or open an audio file"
    @Published private(set) var path = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published var error: String?
    @Published var spectrumVisible = true
    @Published private(set) var muted = false
    @Published var bass: Double = 0 { didSet { equalizer.bands[0].gain = Float(min(0, max(-24, bass))) } }
    @Published var mid: Double = 0 { didSet { equalizer.bands[1].gain = Float(min(0, max(-24, mid))) } }
    @Published var high: Double = 0 { didSet { equalizer.bands[2].gain = Float(min(0, max(-24, high))) } }
    @Published var bpm = 0.0
    var bpmIsEstimate = true
    @Published var beatCue: Double?
    @Published var analyzing = false
    @Published var analysisNote = "Load a track to analyze its beats"
    @Published private(set) var waveform: [Float] = []
    var analysisID = UUID()
    @Published var rate: Double = 1 { didSet { speed.rate = Float(rate) } }
    @Published var volume: Double = 0.7 { didSet { engine.mainMixerNode.outputVolume = muted ? 0 : Float(volume) } }
    let spectrum = AudioSpectrum()
    private let engine = AVAudioEngine()
    private let source = AVAudioPlayerNode()
    private let speed = AVAudioUnitVarispeed()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 3)
    private var waveformTask: Task<[Float], Never>?
    private var file: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var generation = 0
    private var hasTap = false
    private var scheduledHostTime: UInt64?

    init() {
        engine.attach(source)
        engine.attach(speed)
        engine.attach(equalizer)
        for (index, frequency) in [Float(250), 1000, 4000].enumerated() {
            let band = equalizer.bands[index]
            band.filterType = index == 0 ? .lowShelf : index == 1 ? .parametric : .highShelf
            band.frequency = frequency
            band.bandwidth = 2
            band.bypass = false
        }
        engine.mainMixerNode.outputVolume = Float(volume)
    }

    var loaded: Bool { file != nil }
    var semitones: Double { 12 * log2(rate) }
    var speedLabel: String { String(format: "%+.0f%%  /  %+.1f st", (rate - 1) * 100, semitones) }

    func play(path: String, title: String, artist: String, autoplay: Bool = true, bpm: Double? = nil) {
        do {
            let audio = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            guard audio.length > 0, audio.length <= AVAudioFramePosition(UInt32.max), audio.processingFormat.sampleRate > 0 else {
                throw NSError(domain: "CratePlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "This audio file is empty or too long to play."])
            }
            generation += 1
            source.stop()
            isPlaying = false
            position = 0
            duration = 0
            startFrame = 0
            file = nil
            self.path = ""
            engine.stop()
            if hasTap { equalizer.removeTap(onBus: 0); hasTap = false }
            engine.disconnectNodeOutput(source)
            engine.disconnectNodeOutput(speed)
            engine.disconnectNodeOutput(equalizer)
            engine.connect(source, to: speed, format: audio.processingFormat)
            engine.connect(speed, to: equalizer, format: audio.processingFormat)
            engine.connect(equalizer, to: engine.mainMixerNode, format: audio.processingFormat)
            let analyzer = spectrum
            equalizer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(AudioSpectrum.size), format: audio.processingFormat) { buffer, _ in
                analyzer.process(buffer)
            }
            hasTap = true
            try engine.start()
            file = audio
            self.path = path
            self.title = title.isEmpty ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent : title
            self.artist = artist
            error = nil
            duration = Double(audio.length) / audio.processingFormat.sampleRate
            self.bpm = bpm.flatMap { $0.isFinite && (40...250).contains($0) ? $0 : nil } ?? 0
            bpmIsEstimate = true
            analysisID = UUID()
            beatCue = nil
            analysisNote = "Analyze beats, or enter BPM and set a beat cue"
            analyzing = false
            waveform = []
            waveformTask?.cancel()
            let task = Task.detached(priority: .utility) { Self.readWaveform(path) }
            waveformTask = task
            Task { [weak self] in
                let points = await task.value
                guard !task.isCancelled, let self, self.path == path else { return }
                self.waveform = points
            }
            schedule(at: 0, playing: autoplay)
        } catch {
            self.error = "Couldn’t play this file: \(error.localizedDescription)"
        }
    }

    private func schedule(at seconds: Double, playing: Bool, hostTime: UInt64? = nil) {
        guard let file else { return }
        generation += 1
        let token = generation
        source.stop()
        startFrame = min(max(0, AVAudioFramePosition(seconds * file.processingFormat.sampleRate)), file.length - 1)
        position = Double(startFrame) / file.processingFormat.sampleRate
        source.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(file.length - startFrame), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.isPlaying = false
                self.position = self.duration
            }
        }
        isPlaying = playing
        scheduledHostTime = playing ? hostTime : nil
        if playing { source.play(at: hostTime.map { AVAudioTime(hostTime: $0) }) }
    }

    var effectiveBPM: Double { bpm * rate }
    var canSync: Bool { loaded && bpm.isFinite && (40...250).contains(bpm) && beatCue != nil }

    func setBeatCue() {
        updatePosition()
        beatCue = position
        analysisNote = "Manual beat cue"
    }

    func resetEQ() { bass = 0; mid = 0; high = 0 }

    func start(atHostTime time: UInt64) {
        guard loaded else { return }
        updatePosition()
        schedule(at: position >= duration ? 0 : position, playing: true, hostTime: time)
    }

    func sync(to master: CratePlayer) {
        guard canSync, master.canSync, master !== self else { return }
        let matchedRate = master.effectiveBPM / bpm
        guard (0.5...1.5).contains(matchedRate) else {
            error = "Matching these tempos needs more than the 0.5×–1.5× speed range. Check the BPM or halve/double it."
            return
        }
        let hostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.12)
        updatePosition()
        let masterBeat = (master.position(atHostTime: hostTime) - master.beatCue!) * master.bpm / 60
        let phase = masterBeat - floor(masterBeat)
        let beatLength = 60 / bpm
        let nearestBeat = ((position - beatCue!) / beatLength - phase).rounded()
        var target = beatCue! + (nearestBeat + phase) * beatLength
        if target < 0 { target += beatLength }
        guard target < duration else { error = "Seek the deck being synced away from the end, then sync again."; return }
        rate = matchedRate
        schedule(at: target, playing: master.isPlaying,
                 hostTime: hostTime)
    }

    nonisolated private static func readWaveform(_ path: String) -> [Float] {
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            guard file.length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else { return [] }
            let count = min(120000, max(1600, Int(Double(file.length) / file.processingFormat.sampleRate * 100)))
            var peaks = [Float](repeating: 0, count: count)
            while file.framePosition < file.length {
                if Task.isCancelled { return [] }
                let start = file.framePosition
                try file.read(into: buffer)
                guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
                for frame in 0..<Int(buffer.frameLength) {
                    let bin = min(count - 1, Int((start + Int64(frame)) * Int64(count) / file.length))
                    for channel in 0..<Int(buffer.format.channelCount) {
                        peaks[bin] = max(peaks[bin], abs(channels[channel][frame]))
                    }
                }
            }
            return peaks
        } catch { return [] }
    }

    func toggle() {
        guard loaded else { return }
        if isPlaying {
            updatePosition()
            source.pause()
            isPlaying = false
            scheduledHostTime = nil
        } else if position >= duration {
            schedule(at: 0, playing: true)
        } else {
            do {
                if !engine.isRunning { try engine.start() }
            } catch {
                self.error = "Couldn’t resume playback: \(error.localizedDescription)"
                return
            }
            source.play()
            scheduledHostTime = nil
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        schedule(at: min(max(seconds, 0), duration), playing: isPlaying)
    }

    func toggleMute() {
        muted.toggle()
        engine.mainMixerNode.outputVolume = muted ? 0 : Float(volume)
    }

    func stop() {
        generation += 1
        source.stop()
        isPlaying = false
        position = 0
        startFrame = 0
        // Keep the selected file ready to play again.
        if file != nil { schedule(at: 0, playing: false) }
    }

    var currentPosition: Double {
        position(atHostTime: mach_absolute_time())
    }

    func position(atHostTime hostTime: UInt64) -> Double {
        if isPlaying, let start = scheduledHostTime {
            if hostTime < start { return position }
            if source.lastRenderTime.map({ $0.hostTime < start }) ?? true {
                let base = file.map { Double(startFrame) / $0.processingFormat.sampleRate } ?? position
                return min(duration, base + AVAudioTime.seconds(forHostTime: hostTime - start) * rate)
            }
        }
        guard isPlaying, let file, let render = source.lastRenderTime, let time = source.playerTime(forNodeTime: render) else { return position }
        let elapsed = AVAudioTime.seconds(forHostTime: hostTime) - AVAudioTime.seconds(forHostTime: render.hostTime)
        let played = max(0, Double(time.sampleTime) / time.sampleRate + elapsed * rate)
        return min(duration, Double(startFrame) / file.processingFormat.sampleRate + played)
    }

    func updatePosition() {
        if isPlaying { position = currentPosition }
    }

    func openFile(autoplay: Bool = true) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        play(path: url.path, title: url.deletingPathExtension().lastPathComponent, artist: "Local audio", autoplay: autoplay)
    }

    static func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct PlaybackStrip: View {
    @ObservedObject var player: CratePlayer
    var compact = false
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            if !compact {
                HStack(spacing: 12) {
                    Button { player.openFile() } label: { Image(systemName: "folder") }.help("Open audio file")
                    Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                        .disabled(!player.loaded).accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button { player.stop() } label: { Image(systemName: "stop.fill") }.disabled(!player.loaded).help("Stop")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.title).fontWeight(.semibold).lineLimit(1)
                        Text(player.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 8) {
                Text(CratePlayer.clock(scrubbing ? scrubPosition : player.position)).monospacedDigit().frame(width: 42)
                StableSlider(value: Binding(get: { scrubbing ? scrubPosition : player.position }, set: { scrubPosition = $0 }),
                       in: 0...max(1, player.duration), onEditingChanged: { editing in
                    if editing { scrubPosition = player.position }
                    scrubbing = editing
                    if !editing { player.seek(to: scrubPosition) }
                }).disabled(!player.loaded).accessibilityLabel("Track position")
                Text(CratePlayer.clock(player.duration)).monospacedDigit().frame(width: 42)
                Image(systemName: "speaker.wave.2.fill").accessibilityHidden(true)
                StableSlider(value: $player.volume, in: 0...1).frame(minWidth: 45, maxWidth: 85).accessibilityLabel("Volume")
            }
            HStack(spacing: 12) {
                Text("PITCH / SPEED").font(.system(size: 10, weight: .bold, design: .monospaced))
                StableSlider(value: $player.rate, in: 0.5...1.5, step: 0.01).frame(maxWidth: 250).accessibilityLabel("Pitch and speed")
                Text(player.speedLabel).monospacedDigit().frame(width: 115)
                Button("Reset") { player.rate = 1 }.help("Reset pitch and speed to the original recording")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).padding(.vertical, 12)
        .onReceive(clock) { _ in if !scrubbing { player.updatePosition() } }
    }
}
