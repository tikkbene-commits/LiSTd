import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Track: Decodable, Identifiable, Equatable {
    let index: Int
    let artist: String
    let title: String
    let cue: String
    let status: String
    let note: String
    let path: String
    let genre: String
    let vibe: String
    let bpm: Double?
    let quality: String?
    let track_id: String?
    var id: Int { index }
}

struct ImportJob: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let minimum: Int
    let message: String
    let source: String
    let tracks: [Track]
    var ready: Int { tracks.filter { ["ready", "existing"].contains($0.status) }.count }
    var attention: Int { tracks.filter { ["unavailable", "review", "stopped"].contains($0.status) }.count }
}

struct LibraryTrack: Decodable, Identifiable, Equatable {
    let id: String
    let artist: String
    let title: String
    let genre: String
    let vibe: String
    let bpm: Double?
    let path: String
}

struct Snapshot: Decodable {
    let jobs: [ImportJob]
    let library: [LibraryTrack]
    let ready: Bool
    let configured: Bool
}

struct EditTrack: Identifiable {
    let id: String
    let title: String
    var genre: String
    var vibe: String
}

struct DeckBeatAnalysis: Decodable {
    let bpm: Double?
    let cue: Double?
    let note: String
}

struct ReviewTrack: Identifiable {
    let jobID: String
    let track: Track
    var id: String { "\(jobID)-\(track.index)" }
}

struct ReviewAudioInfo: Decodable {
    let codec: String
    let duration: Double
    let tags: [String: String]
}

@MainActor final class CrateModel: ObservableObject {
    @Published var jobs: [ImportJob] = []
    @Published var library: [LibraryTrack] = []
    @Published var selection = "import"
    @Published var error: String?
    @Published var ready = false
    @Published var configured = false
    @Published var working = false
    @Published var editing: EditTrack?
    @Published var reviewing: ReviewTrack?
    @Published var showAccount = false
    @Published var signingIn = false
    @Published var accountError: String?
    @Published var accountUsername = ""
    private var account: SoulseekAccount?
    var fetching = false
    var initialized = false
    private var lastRefresh = Date.distantPast
    var pending: [String] = []
    let root: URL

    nonisolated static var bundledBackend: URL? {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return Bundle.main.url(forResource: "listd-backend", withExtension: nil, subdirectory: "backend/\(architecture)")
    }

    init() {
        if Bundle.main.object(forInfoDictionaryKey: "LiSTdStandalone") as? Bool == true {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/LiSTd")
        } else {
            root = Bundle.main.bundleURL.deletingLastPathComponent()
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            account = try SoulseekKeychain.load()
            accountUsername = account?.username ?? ""
            configured = account != nil
        } catch { accountError = error.localizedDescription }
    }

    func request(_ arguments: [String], input: String? = nil, done: @escaping (Result<Data, Error>) -> Void) {
        let project = root
        Task.detached {
            do {
                let process = Process()
                let audioPython = project.appendingPathComponent(".music-sorter/audio-env/bin/python")
                let bundled = Self.bundledBackend
                if Bundle.main.object(forInfoDictionaryKey: "LiSTdStandalone") as? Bool == true && bundled == nil {
                    throw NSError(domain: "Crate", code: 1, userInfo: [NSLocalizedDescriptionKey: "LiSTd’s bundled tools are missing. Extract the complete app from the ZIP and try again."])
                }
                process.executableURL = bundled ?? (FileManager.default.isExecutableFile(atPath: audioPython.path) ? audioPython : URL(fileURLWithPath: "/usr/bin/python3"))
                process.arguments = (bundled == nil ? [project.appendingPathComponent("crate_backend.py").path] : []) + ["--root", project.path] + arguments
                process.currentDirectoryURL = project
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = bundled.map { $0.deletingLastPathComponent().path + ":/usr/bin:/bin" } ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                env["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] = project.appendingPathComponent(".music-sorter/sockseek-runtime").path
                process.environment = env
                let output = Pipe()
                process.standardOutput = output
                process.standardError = output
                let stdin = Pipe()
                process.standardInput = stdin
                try process.run()
                if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
                try stdin.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let message = object?["error"] as? String ?? String(data: data, encoding: .utf8) ?? "The operation failed."
                    throw NSError(domain: "Crate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
                }
                await MainActor.run { done(.success(data)) }
            } catch {
                await MainActor.run { done(.failure(error)) }
            }
        }
    }

    func refresh() {
        guard !fetching else { return }
        fetching = true
        lastRefresh = Date()
        request(["snapshot"]) { result in
            self.fetching = false
            do {
                let state = try JSONDecoder().decode(Snapshot.self, from: result.get())
                if self.jobs != state.jobs { self.jobs = state.jobs }
                if self.library != state.library { self.library = state.library }
                if self.ready != state.ready { self.ready = state.ready }
                if !self.initialized {
                    self.initialized = true
                    if !self.configured { self.showAccount = true }
                    if let first = state.jobs.first { self.selection = first.id }
                }
                if self.configured && !self.working && !state.jobs.contains(where: { $0.status == "running" }) && !self.pending.isEmpty {
                    self.start(self.pending.removeFirst())
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func poll() {
        let busy = working || !pending.isEmpty || jobs.contains { $0.status == "running" }
        if busy || Date().timeIntervalSince(lastRefresh) >= 10 { refresh() }
    }

    func importText(_ text: String, name: String, order: String, minimum: Int, automatic: Bool) {
        importRequest(["import", "--name", name, "--order", order, "--minimum", "\(minimum)"], text: text, automatic: automatic)
    }

    func importFile(_ file: URL, order: String, minimum: Int, automatic: Bool) {
        importRequest(["import", "--file", file.path, "--name", file.deletingPathExtension().lastPathComponent,
                       "--order", order, "--minimum", "\(minimum)"], automatic: automatic)
    }

    func importRequest(_ args: [String], text: String? = nil, automatic: Bool) {
        request(args, input: text) { result in
            do {
                let job = try JSONDecoder().decode(ImportJob.self, from: result.get())
                self.selection = job.id
                if automatic { self.pending.append(job.id) }
                self.refresh()
            } catch { self.error = error.localizedDescription }
        }
    }

    func start(_ id: String) {
        guard let account else {
            if !pending.contains(id) { pending.append(id) }
            showAccount = true
            return
        }
        guard !working && !jobs.contains(where: { $0.status == "running" }) else {
            if !pending.contains(id) { pending.append(id) }
            return
        }
        working = true
        let input = String(data: try! JSONEncoder().encode(account), encoding: .utf8)!
        request(["run", id], input: input) { result in
            self.working = false
            if case .failure(let failure) = result { self.error = failure.localizedDescription }
            self.refresh()
        }
    }

    func stop(_ id: String) {
        pending.removeAll { $0 == id }
        request(["stop", id]) { _ in self.refresh() }
    }

    func stopAll() {
        for job in jobs where job.status == "running" {
            let url = root.appendingPathComponent(".music-sorter/crate/jobs/\(job.id)/cancel")
            try? Data().write(to: url)
        }
    }

    func showExample() {
        if let job = jobs.first(where: { $0.source.contains("bNSesW8h94I") }) {
            selection = job.id
        } else {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("tracklists/YouTube set bNSesW8h94I.csv")
            importFile(bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? root.appendingPathComponent("tracklists/YouTube set bNSesW8h94I.csv"), order: "artist-title", minimum: 320, automatic: false)
        }
    }

    func signIn(username: String, password: String) {
        guard !working && !jobs.contains(where: { $0.status == "running" }) else {
            accountError = "Stop the current import before changing accounts."
            return
        }
        let candidate = SoulseekAccount(username: username, password: password)
        let input = String(data: try! JSONEncoder().encode(candidate), encoding: .utf8)!
        signingIn = true
        accountError = nil
        request(["login"], input: input) { result in
            self.signingIn = false
            do {
                _ = try result.get()
                try SoulseekKeychain.save(candidate)
                self.account = candidate
                self.accountUsername = candidate.username
                self.configured = true
                self.showAccount = false
                self.refresh()
            } catch { self.accountError = error.localizedDescription }
        }
    }

    func signOut() {
        guard !working && !jobs.contains(where: { $0.status == "running" }) else {
            accountError = "Stop the current import before changing accounts."
            return
        }
        do {
            try SoulseekKeychain.remove()
            account = nil
            accountUsername = ""
            configured = false
            pending.removeAll()
            accountError = nil
        } catch { accountError = error.localizedDescription }
    }

    func saveLabels(_ track: EditTrack) {
        request(["label", track.id, "--genre", track.genre, "--vibe", track.vibe]) { result in
            if case .failure(let failure) = result { self.error = failure.localizedDescription }
            self.editing = nil
            self.refresh()
        }
    }

    func correctImport(_ arguments: [String]) {
        working = true
        request(arguments) { result in
            self.working = false
            if case .failure(let failure) = result { self.error = failure.localizedDescription }
            self.refresh()
        }
    }

    func reveal(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

struct StatusPill: View {
    let status: String
    var label: String {
        ["ready": "Filed", "existing": "In library", "searching": "Searching", "downloading": "Downloading",
         "checking": "Checking", "unavailable": "Not found", "review": "Review", "queued": "Queued", "stopped": "Stopped"][status] ?? status.capitalized
    }
    var color: Color {
        if ["ready", "existing"].contains(status) { return .green }
        if ["review", "unavailable", "stopped"].contains(status) { return .orange }
        if ["searching", "downloading", "checking"].contains(status) { return .accentColor }
        return .secondary
    }
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.09), in: Capsule())
        .foregroundStyle(color)
    }
}

struct CrateView: View {
    @StateObject var model = CrateModel()
    @StateObject var player = CratePlayer()
    @StateObject var deckB = CratePlayer()
    @State private var showTechnicalWorkspace = false
    @State private var technicalOpened = false
    @AppStorage("crate.skin") private var skin = CrateSkin.boombox
    @AppStorage("listd.playerSize") private var playerSize = 1.0
    @AppStorage("listd.showWorkspace") private var showWorkspace = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showImporter = false
    @State private var text = ""
    @State private var name = "New set"
    @State private var order = "title-artist"
    @State private var minimum = 320
    @State private var automatic = true
    @State private var targeted = false
    @State private var search = ""
    @State private var technicalSelection: LibraryTrack.ID?
    @State private var folderJobID: String?
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var selectedJob: ImportJob? { model.jobs.first { $0.id == model.selection } }

    var body: some View {
        Group {
            if skin == .boombox {
                boombox
            } else if skin == .technical {
                technical
            } else if skin == .silverwave {
                silverwave
            } else {
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 280)
                } detail: {
                    workspace.background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .tint(skin.accent)
        .preferredColorScheme(skin == .technical ? .dark : skin == .classic ? nil : .light)
        .frame(minWidth: 1080, minHeight: skin == .boombox ? 820 : 780)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { model.showAccount = true } label: { Label(model.configured ? model.accountUsername : "Sign in to Soulseek", systemImage: "person.crop.circle") }
                .disabled(model.working || model.signingIn || model.jobs.contains(where: { $0.status == "running" }))
            }
            ToolbarItem(placement: .automatic) { skinPicker }
            ToolbarItem(placement: .primaryAction) {
                Button { model.selection = "import"; showWorkspace = true; if skin == .technical { showTechnicalWorkspace = true } } label: { Label("New import", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onAppear { model.refresh(); updateDockIcon(); if skin == .technical { prepareTechnical() } }
        .onChange(of: skin) { _, value in
            updateDockIcon()
            if value == .technical { prepareTechnical() }
            else if deckB.isPlaying { deckB.toggle() }
        }
        .onChange(of: player.path) { _, _ in if skin == .technical { analyzeDeck(player) } }
        .onChange(of: deckB.path) { _, _ in if skin == .technical { analyzeDeck(deckB) } }
        .onReceive(timer) { _ in model.poll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stopAll() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
            switch result {
            case .success(let url): model.importFile(url, order: order, minimum: minimum, automatic: automatic)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $model.editing) { edit in LabelEditor(track: edit, save: model.saveLabels) }
        .sheet(isPresented: $model.showAccount) { SoulseekAccountPanel(model: model) }
        .sheet(isPresented: $showTechnicalWorkspace) {
            VStack(spacing: 0) {
                HStack { Text("Tracks & imports").font(.headline); Spacer(); Button("Done") { showTechnicalWorkspace = false } }.padding()
                NavigationSplitView { sidebar } detail: { workspace }
            }.frame(width: 1050, height: 680)
        }
        .alert("LiSTd needs your attention", isPresented: Binding(get: { model.error != nil || player.error != nil || deckB.error != nil }, set: { if !$0 { model.error = nil; player.error = nil; deckB.error = nil } })) {
            Button("OK") { model.error = nil; player.error = nil; deckB.error = nil }
        } message: { Text(model.error ?? player.error ?? deckB.error ?? "") }
    }

    func prepareTechnical() {
        if !technicalOpened {
            player.volume = min(player.volume, 0.5)
            deckB.volume = 0.5
            technicalOpened = true
        }
        if !player.canSync { analyzeDeck(player) }
        if !deckB.canSync { analyzeDeck(deckB) }
    }

    func analyzeDeck(_ deck: CratePlayer) {
        guard deck.loaded, !deck.analyzing else { return }
        let path = deck.path
        let token = UUID()
        deck.analysisID = token
        if deck.bpm == 0, let bpm = model.library.first(where: { $0.path == path })?.bpm { deck.bpm = bpm }
        let originalBPM = deck.bpm
        let originalEstimate = deck.bpmIsEstimate
        let originalCue = deck.beatCue
        deck.analyzing = true
        var arguments = ["deck-analysis", path]
        if (40...250).contains(originalBPM) { arguments += ["--bpm", String(originalBPM)] }
        if originalEstimate { arguments += ["--refine-bpm"] }
        model.request(arguments) { result in
            guard deck.path == path, deck.analysisID == token else { return }
            deck.analyzing = false
            do {
                let analysis = try JSONDecoder().decode(DeckBeatAnalysis.self, from: result.get())
                guard deck.bpm == originalBPM, deck.bpmIsEstimate == originalEstimate else { return }
                deck.bpm = analysis.bpm ?? 0
                if deck.beatCue == originalCue { deck.beatCue = analysis.cue; deck.analysisNote = analysis.note }
            } catch { deck.analysisNote = "Beat analysis unavailable; enter BPM and set a beat cue" }
        }
    }

    var technical: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                technicalCollection.frame(width: (geometry.size.width - 1) / 3)
                Rectangle().fill(TechnicalPlayer.line).frame(width: 1)
                ScrollView(.vertical) {
                    TechnicalPlayer(a: player, b: deckB, analyze: analyzeDeck)
                        .frame(maxWidth: .infinity)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(red: 0.055, green: 0.065, blue: 0.061))
    }

    var technicalCollection: some View {
        let filtered = model.library.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.genre) \($0.vibe)".localizedCaseInsensitiveContains(search) }
        return VStack(spacing: 0) {
            HStack {
                Text("COLLECTION").tracking(2).font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("\(model.library.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(TechnicalPlayer.dim)
                Spacer(minLength: 8)
                Button("Tracks & imports") { showTechnicalWorkspace = true }.controlSize(.small)
            }.padding(.top, 17)
            TextField("Search tracks, artists, genres", text: $search)
                .textFieldStyle(.roundedBorder).padding(.bottom, 12)
            Table(of: LibraryTrack.self, selection: $technicalSelection) {
                TableColumn("Track") { track in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).lineLimit(1)
                        Text("\(track.artist) · \(track.genre)").font(.system(size: 10))
                            .foregroundStyle(TechnicalPlayer.dim).lineLimit(1)
                    }.padding(.vertical, 5).help("\(track.artist) — \(track.title) / \(track.genre)")
                }.width(min: 135, ideal: 230)
                TableColumn("BPM") { track in Text(track.bpm.map { String(format: "%.1f", $0) } ?? "—").monospacedDigit() }.width(44)
                TableColumn("Deck") { track in
                    HStack(spacing: 5) {
                        Button("A") { loadDeck(player, track: track) }.help("Load \(track.title) into deck A, paused").accessibilityLabel("Load \(track.title) into deck A")
                        Button("B") { loadDeck(deckB, track: track) }.help("Load \(track.title) into deck B, paused").accessibilityLabel("Load \(track.title) into deck B")
                    }.buttonStyle(.bordered).controlSize(.small)
                }.width(72)
            } rows: {
                ForEach(filtered) { track in
                    TableRow(track).itemProvider { NSItemProvider(object: URL(fileURLWithPath: track.path) as NSURL) }
                }
            }.font(.system(size: 11)).tableStyle(.inset(alternatesRowBackgrounds: false))
        }.padding(.horizontal, 12).frame(maxHeight: .infinity)
    }

    func loadDeck(_ deck: CratePlayer, track: LibraryTrack) {
        deck.play(path: track.path, title: track.title, artist: track.artist, autoplay: false, bpm: track.bpm)
        analyzeDeck(deck)
    }

    var skinPicker: some View {
        Picker("Skin", selection: $skin) {
            ForEach(CrateSkin.allCases) { option in Text(option.title).tag(option) }
        }.pickerStyle(.menu).fixedSize().accessibilityLabel("Skin").help("Change LiSTd’s skin")
    }

    func updateDockIcon() {
        if let url = Bundle.main.url(forResource: "EarIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var workspace: some View {
        VStack(spacing: 0) {
            Group {
                if model.selection == "import" { importView }
                else if model.selection == "library" { libraryView }
                else if model.selection == "folders" { foldersView(job: model.jobs.first(where: { $0.id == folderJobID }) ?? model.jobs.first) }
                else if let job = selectedJob { jobView(job) }
                else { importView }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if skin != .boombox {
                PlaybackStrip(player: player).background(.regularMaterial)
                Divider()
            }
            footer
        }.sheet(item: $model.reviewing) { review in
            TrackReviewPanel(model: model, player: player, review: review)
        }
    }

    var boombox: some View {
        GeometryReader { geometry in
            let drawerHeight = min(420, max(260, geometry.size.height * 0.42))
            let playerHeight = max(200, geometry.size.height - 125 - (showWorkspace ? drawerHeight : 0))
        VStack(spacing: 0) {
            BoomboxPlayer(player: player, showTracks: { showWorkspace.toggle() })
                .frame(width: geometry.size.width * playerSize, height: playerHeight * playerSize)
                .frame(width: geometry.size.width, height: playerHeight).padding(.top, 4)
                .shadow(color: .black.opacity(0.3), radius: 5, y: 6)
            PlaybackStrip(player: player, compact: true)
                .frame(maxWidth: 920)
            HStack(spacing: 12) {
                Text("PLAYER SIZE").font(.system(size: 10, weight: .bold, design: .monospaced))
                Slider(value: $playerSize, in: 0.45...1).frame(width: 160).accessibilityLabel("Player size")
                Text("\(Int(playerSize * 100))%") .monospacedDigit().frame(width: 38)
                Button("Fill window") { playerSize = 1 }
                Spacer()
                Button { showWorkspace.toggle() } label: {
                    Label(showWorkspace ? "Hide tracks & imports" : "Tracks & imports", systemImage: showWorkspace ? "chevron.down" : "chevron.up")
                }.accessibilityLabel("Toggle tracks and imports")
            }.font(.system(size: 11)).padding(.horizontal, 28).padding(.bottom, 12)
            if showWorkspace {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([("library", "Library", "music.note.list"), ("folders", "New arrivals", "folder.badge.plus"), ("import", "Import tracklist", "square.and.arrow.down")], id: \.0) { item in
                        Button { model.selection = item.0 } label: {
                            Label(item.1, systemImage: item.2).font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .foregroundStyle(model.selection == item.0 ? Color.white : CrateSkin.ink)
                                .background(model.selection == item.0 ? AnyShapeStyle(LinearGradient(colors: [skin.accent, Color(red: 0.34, green: 0, blue: 0.02)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(CrateSkin.metal), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.8)))
                                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        }.buttonStyle(SkinSurfacePress())
                    }
                    Spacer()
                    Menu {
                        ForEach(model.jobs) { job in
                            Button("\(job.name) · \(job.ready)/\(job.tracks.count)") { model.selection = job.id }
                        }
                    } label: { Label(selectedJob?.name ?? "Imports", systemImage: "list.bullet.rectangle") }
                        .frame(maxWidth: 320).disabled(model.jobs.isEmpty)
                }.padding(12).background(CrateSkin.metal)
                Divider()
                workspace.background(Color(red: 0.94, green: 0.96, blue: 0.99))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 0.01, green: 0.24, blue: 0.65), lineWidth: 3))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.8)).padding(3))
            .frame(height: drawerHeight)
            .padding(.horizontal, 18).padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: showWorkspace)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: playerSize)
        .background(LinearGradient(colors: [Color(red: 0.90, green: 0.94, blue: 0.97), .white, Color(red: 0.59, green: 0.68, blue: 0.78)], startPoint: .top, endPoint: .bottom))
        }
    }

    var silverwave: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CrateEmblem().frame(width: 38, height: 38)
                    Text("LiSTd").font(.custom("Trebuchet MS Bold Italic", size: 31)).tracking(-2)
                }.foregroundStyle(CrateSkin.ink).padding(.vertical, 24)
                VStack(spacing: 8) {
                    skinNavigation("Import tracklist", symbol: "square.and.arrow.down", selection: "import")
                    skinNavigation("New arrivals", symbol: "folder.badge.plus", selection: "folders")
                    skinNavigation("Library", symbol: "music.note.list", selection: "library")
                }.padding(.horizontal, 12)
                HStack {
                    Text("IMPORTS").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    Spacer()
                    Text("\(model.jobs.count)").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(CrateSkin.ink.opacity(0.7)).padding(.horizontal, 18).padding(.top, 28).padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(model.jobs) { job in
                            Button { model.selection = job.id } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(job.name).font(.system(size: 12, weight: .semibold)).lineLimit(3).multilineTextAlignment(.leading)
                                    Text("\(job.ready) / \(job.tracks.count) ready").font(.system(size: 10, design: .monospaced)).opacity(0.75)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .foregroundStyle(model.selection == job.id ? .white : CrateSkin.ink)
                                .background(model.selection == job.id ? skin.accent : Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 12)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("SILVERWAVE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    Text("From tracklist to record bag.").font(.system(size: 10))
                }.foregroundStyle(CrateSkin.ink.opacity(0.65)).padding(18)
            }
            .frame(width: 205).modifier(MetalPanel(radius: 18))
            VStack(spacing: 12) {
                SilverwaveDisplay(
                    title: selectedJob?.name ?? (model.selection == "library" ? "Your record collection" : model.selection == "folders" ? "Freshly filed" : "Build your next crate"),
                    subtitle: selectedJob.map { $0.status == "running" ? $0.message : "\($0.ready) filed · \($0.attention) need attention · \($0.minimum) kbps / lossless" } ?? "Tracklists in. Records filed. Ready for the next set.",
                    count: "\(model.library.count) TRACKS")
                workspace
                    .background(Color(red: 0.94, green: 0.94, blue: 0.97))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.black.opacity(0.3)))
            }.padding(12).modifier(MetalPanel(radius: 20))
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(red: 0.38, green: 0.40, blue: 0.51), Color(red: 0.23, green: 0.24, blue: 0.33)], startPoint: .top, endPoint: .bottom))
    }

    func skinNavigation(_ title: String, symbol: String, selection: String) -> some View {
        Button { model.selection = selection } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20)
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if model.selection == selection { Circle().fill(Color(red: 0.75, green: 0.94, blue: 0.89)).frame(width: 5, height: 5) }
            }.padding(.horizontal, 12).frame(height: 44)
                .foregroundStyle(model.selection == selection ? .white : CrateSkin.ink)
                .background {
                    if model.selection == selection {
                        RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [skin.accent, Color(red: 0.20, green: 0.14, blue: 0.34)], startPoint: .top, endPoint: .bottom))
                    } else {
                        RoundedRectangle(cornerRadius: 9).fill(CrateSkin.metal)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.6)))
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }.buttonStyle(.plain).accessibilityAddTraits(model.selection == selection ? .isSelected : [])
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 23)).foregroundStyle(skin.accent)
                Text("LiSTd").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 24)
            List(selection: $model.selection) {
                Section("Workspace") {
                    Label("Import tracklist", systemImage: "square.and.arrow.down").tag("import")
                    Label("New arrivals", systemImage: "folder.badge.plus").tag("folders")
                    Label("Library", systemImage: "music.note.list").tag("library")
                }
                Section("Imports") {
                    ForEach(model.jobs) { job in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            HStack(spacing: 5) {
                                if job.status == "running" { Circle().fill(skin.accent).frame(width: 5, height: 5) }
                                Text("\(job.ready)/\(job.tracks.count) ready").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4).tag(job.id)
                    }
                }
            }.listStyle(.sidebar)
            Spacer(minLength: 0)
            Text("From tracklist to record bag.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(22)
        }
    }

    var importView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Build your next crate.").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Drop a tracklist. We’ll find the tracks and put each one in its place.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Button { showImporter = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 32, weight: .light)).foregroundStyle(skin.accent)
                        Text("Drop your tracklist here").font(.system(size: 17, weight: .medium))
                        Text("CSV or text file · or click to choose").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 155)
                    .background(targeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(targeted ? 0.8 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
                }.buttonStyle(.plain)
                .onDrop(of: [UTType.fileURL.identifier, UTType.plainText.identifier], isTargeted: $targeted, perform: handleDrop)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Or paste a tracklist").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Open provided set", action: model.showExample).font(.system(size: 12))
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10).frame(height: 145)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.16)))
                        .accessibilityLabel("Tracklist text")
                    Text("Example: 0:00:00 Easy - Freedom Satellite").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    TextField("Import name", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 210)
                    Picker("Text order", selection: $order) {
                        Text("Title - Artist").tag("title-artist")
                        Text("Artist - Title").tag("artist-title")
                    }.frame(maxWidth: 240)
                    Picker("Quality", selection: $minimum) {
                        Text("320 kbps / lossless").tag(320)
                        Text("256 kbps / lossless").tag(256)
                        Text("192 kbps / lossless").tag(192)
                        Text("150 kbps / lossless").tag(150)
                    }.frame(maxWidth: 230)
                }.font(.system(size: 12))
                HStack {
                    Toggle("Download and organize automatically", isOn: $automatic).toggleStyle(.checkbox)
                    Spacer()
                    Button(automatic ? "Download & organize" : "Import for review") {
                        model.importText(text, name: name, order: order, minimum: minimum, automatic: automatic)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ready)
                }
                Text("CSV artist, title and duration fields are preserved. Set timestamps are cue points, not track lengths.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(34).frame(maxWidth: 1050, alignment: .leading)
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let value = item as? URL { url = value }
                else if let value = item as? String { url = URL(string: value) }
                else { url = nil }
                guard let url else {
                    Task { @MainActor in model.error = "This drop did not contain a file. Choose a CSV or text file instead." }
                    return
                }
                Task { @MainActor in model.importFile(url, order: order, minimum: minimum, automatic: automatic) }
            }
        } else {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let value = item as? String else { return }
                Task { @MainActor in model.importText(value, name: name, order: order, minimum: minimum, automatic: automatic) }
            }
        }
        return true
    }

    func jobView(_ job: ImportJob) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(job.name).font(.system(size: 25, weight: .semibold, design: .rounded)).lineLimit(2)
                        if let url = URL(string: job.source), !job.source.isEmpty {
                            Link("View source set", destination: url).font(.system(size: 12))
                        }
                    }
                    Spacer()
                    if job.status == "running" {
                        Button("Stop") { model.stop(job.id) }.controlSize(.large)
                    } else {
                        VStack(alignment: .trailing, spacing: 8) {
                        Button(job.ready == job.tracks.count ? "Check again" : (job.status == "queued" ? "Download & organize" : "Retry unfinished")) { model.start(job.id) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        if job.ready == 0 {
                            Button("Swap artist / title & recheck") { model.correctImport(["swap-order", job.id]) }
                                .help("Correct a reversed tracklist and verify downloaded files locally. Does not download.")
                        }
                        }.disabled(model.working || model.jobs.contains { $0.status == "running" })
                    }
                }
                HStack(spacing: 20) {
                    Label("\(job.ready) of \(job.tracks.count) ready", systemImage: "checkmark.circle").foregroundStyle(.green)
                    if job.attention > 0 { Label("\(job.attention) need attention", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                    Spacer()
                    Text("\(job.minimum) kbps or lossless").foregroundStyle(.secondary)
                }.font(.system(size: 12, weight: .medium))
                if job.status == "running" {
                    ProgressView(value: Double(job.ready + job.attention), total: Double(job.tracks.count)).tint(skin.accent)
                    Text(job.message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.padding(28)
            Divider()
            Table(job.tracks) {
                TableColumn("Cue") { track in Text(track.cue.isEmpty ? String(format: "%02d", track.index+1) : track.cue).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }.width(65)
                TableColumn("Track") { track in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 8)
                }.width(min: 170, ideal: 235)
                TableColumn("Status") { track in
                    if track.status == "review", !track.path.isEmpty {
                        Button { model.reviewing = ReviewTrack(jobID: job.id, track: track) } label: {
                            StatusPill(status: track.status)
                        }.buttonStyle(.plain).help("Listen, compare file tags and correct the expected track")
                    } else { StatusPill(status: track.status).help(track.note) }
                }.width(105)
                TableColumn("Quality") { track in Text(track.quality ?? "—").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }.width(95)
                TableColumn("Landed in") { track in
                    if track.status == "ready" {
                        Button { model.reveal(track.path) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder").foregroundStyle(skin.accent)
                                Text("\(track.genre) / \(track.vibe)").font(.system(size: 11)).lineLimit(2)
                            }
                        }.buttonStyle(.plain).help(track.path)
                    } else {
                        Text(track.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).help(track.note)
                    }
                }.width(min: 185, ideal: 260)
                TableColumn("") { track in
                    Button { player.play(path: track.path, title: track.title, artist: track.artist) } label: {
                        Image(systemName: player.path == track.path && player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    }.buttonStyle(.borderless).disabled(!["ready", "existing"].contains(track.status) || track.path.isEmpty).accessibilityLabel("Play \(track.title) in LiSTd").help("Play in LiSTd")
                }.width(26)
                TableColumn("") { track in
                    Menu {
                        if track.status == "review", !track.path.isEmpty {
                            Button("Review file…") { model.reviewing = ReviewTrack(jobID: job.id, track: track) }
                        }
                        Button("Play in LiSTd") { player.play(path: track.path, title: track.title, artist: track.artist) }.disabled(!["ready", "existing"].contains(track.status) || track.path.isEmpty)
                        Button("Show in Finder") { model.reveal(track.path) }.disabled(track.path.isEmpty)
                        if let id = track.track_id {
                            Button("Edit genre & vibe…") { model.editing = EditTrack(id: id, title: track.title, genre: track.genre, vibe: track.vibe) }.disabled(model.jobs.contains { $0.status == "running" })
                        }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                }.width(26)
            }.tableStyle(.inset(alternatesRowBackgrounds: true))
            if job.tracks.contains(where: { $0.status == "ready" }) {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus").foregroundStyle(skin.accent)
                    Text("New music, already filed.").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Show new folders") { folderJobID = job.id; model.selection = "folders" }
                }.padding(.horizontal, 28).padding(.vertical, 16)
            }
        }
    }

    func foldersView(job: ImportJob?) -> some View {
        let tracks = job?.tracks.filter { $0.status == "ready" } ?? []
        let groups = Dictionary(grouping: tracks) { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New arrivals").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(job.map { "Folders receiving tracks from \($0.name)." } ?? "Your next import will appear here.").foregroundStyle(.secondary).font(.system(size: 13))
                }
                if groups.isEmpty {
                    ContentUnavailableView("No new tracks yet", systemImage: "folder", description: Text("Downloaded tracks appear here after their checks pass."))
                } else {
                    ForEach(groups.keys.sorted(), id: \.self) { folder in
                        let items = groups[folder] ?? []
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: "folder.fill").font(.system(size: 36, weight: .light)).foregroundStyle(skin.accent.opacity(0.8))
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\(items.first?.genre ?? "") / \(items.first?.vibe ?? "")").font(.system(size: 16, weight: .semibold))
                                Text(items.map { "\($0.artist) — \($0.title)" }.joined(separator: "\n")).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                            }
                            Spacer()
                            Text("+\(items.count) new").font(.system(size: 11, weight: .semibold)).foregroundStyle(skin.accent).padding(7).background(skin.accent.opacity(0.08), in: Capsule())
                            Button("Open folder") { model.openFolder(folder) }
                        }.padding(22).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }.padding(34).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var libraryView: some View {
        let filtered = model.library.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.genre) \($0.vibe)".localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Library").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(model.library.count) tracks · genre tags and estimated vibes").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Find an artist, genre or vibe", text: $search).textFieldStyle(.roundedBorder).frame(width: 270)
            }.padding(28)
            Table(filtered) {
                TableColumn("Track") { track in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).fontWeight(.medium)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }.width(min: 230, ideal: 330)
                TableColumn("Genre", value: \.genre).width(min: 110, ideal: 160)
                TableColumn("Vibe", value: \.vibe).width(min: 120, ideal: 170)
                TableColumn("BPM") { track in Text(track.bpm.map { String(format: "%.1f", $0) } ?? "—").monospacedDigit() }.width(65)
                TableColumn("") { track in
                    Button { player.play(path: track.path, title: track.title, artist: track.artist) } label: {
                        Image(systemName: player.path == track.path && player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    }.buttonStyle(.borderless).accessibilityLabel("Play \(track.title) in LiSTd").help("Play in LiSTd")
                }.width(28)
                TableColumn("") { track in
                    Menu {
                        Button("Show in Finder") { model.reveal(track.path) }
                        Button("Play in LiSTd") { player.play(path: track.path, title: track.title, artist: track.artist) }
                        Button("Edit genre & vibe…") { model.editing = EditTrack(id: track.id, title: track.title, genre: track.genre, vibe: track.vibe) }.disabled(model.jobs.contains { $0.status == "running" })
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
                }.width(30)
            }.font(.system(size: 12))
        }
    }

    var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(model.ready && model.configured ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(!model.ready ? "Download tools unavailable" : model.configured ? "Soulseek account saved" : "Sign in to Soulseek")
            Spacer()
            Text("Moves files · no copies · genre tags + estimated vibes")
            Button { model.openFolder(model.root.appendingPathComponent("downloads").path) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help("Open downloads")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 11)
    }
}

struct SoulseekAccountPanel: View {
    @ObservedObject var model: CrateModel
    @State private var username = ""
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Soulseek account").font(.title2.bold())
            Text("Sign in with your Soulseek username and password. Your password is saved in this Mac’s Keychain.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Username", text: $username).textContentType(.username)
            SecureField("Password", text: $password).textContentType(.password)
                .onSubmit { signIn() }
            Text("Sign-in checks your connection without downloading music. Close other Soulseek clients using this account.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = model.accountError { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if model.configured { Button("Sign out", role: .destructive) { model.signOut(); password = "" } }
                Spacer()
                Button("Later") { password = ""; dismiss() }
                Button(model.signingIn ? "Signing in…" : "Sign in") { signIn() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder).padding(28).frame(width: 450)
        .disabled(model.signingIn || model.working || model.jobs.contains(where: { $0.status == "running" }))
        .interactiveDismissDisabled(model.signingIn)
        .onAppear { username = model.accountUsername }
        .onDisappear { password = "" }
    }

    func signIn() {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !model.signingIn else { return }
        model.signIn(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
    }
}

struct TrackReviewPanel: View {
    @ObservedObject var model: CrateModel
    @ObservedObject var player: CratePlayer
    let review: ReviewTrack
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = CratePlayer()
    @State private var info: ReviewAudioInfo?
    @State private var artist = ""
    @State private var title = ""
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review downloaded file").font(.title2.weight(.semibold))
            Text(note).foregroundStyle(.secondary).textSelection(.enabled)
            if let info {
                Text("File artist: \(info.tags["artist"] ?? "No artist tag")\nFile title: \(info.tags["title"] ?? "No title tag")\n\(info.codec.uppercased()) · \(CratePlayer.clock(info.duration))")
                    .textSelection(.enabled)
            } else { Text("Reading file tags…").foregroundStyle(.secondary) }
            Text(URL(fileURLWithPath: review.track.path).lastPathComponent)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button(preview.isPlaying ? "Pause preview" : "Listen to file") {
                    if player.isPlaying { player.toggle() }
                    if preview.loaded { preview.toggle() }
                    else { preview.play(path: review.track.path, title: title, artist: artist) }
                }
                Button("Show in Finder") { model.reveal(review.track.path) }
            }
            Form {
                TextField("Expected artist", text: $artist)
                TextField("Expected title", text: $title)
            }.textFieldStyle(.roundedBorder)
            Button("Swap artist / title") { swap(&artist, &title) }
            Text("Correct the expected track if the list was reversed. Recheck still requires matching identity, duration, quality and a complete audio decode before filing the track. File tags stay unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = preview.error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(busy ? "Checking…" : "Save & recheck file") {
                    preview.stop()
                    busy = true
                    model.working = true
                    model.request(["review-track", review.jobID, String(review.track.index), "--artist", artist, "--title", title]) { result in
                        busy = false
                        model.working = false
                        do {
                            let job = try JSONDecoder().decode(ImportJob.self, from: result.get())
                            note = job.tracks[review.track.index].note
                            model.refresh()
                            if job.tracks[review.track.index].status == "ready" { dismiss() }
                        } catch { note = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(info == nil || busy || model.working || model.jobs.contains { $0.status == "running" } || artist.trimmingCharacters(in: .whitespaces).isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(28).frame(width: 520).disabled(busy)
        .onAppear {
            artist = review.track.artist; title = review.track.title; note = review.track.note
            model.request(["review-info", review.jobID, String(review.track.index)]) { result in
                do { info = try JSONDecoder().decode(ReviewAudioInfo.self, from: result.get()) }
                catch { note = error.localizedDescription }
            }
        }
        .onDisappear { preview.stop() }
    }
}

struct LabelEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var track: EditTrack
    var save: (EditTrack) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit genre & vibe").font(.title2.weight(.semibold))
            Text(track.title).foregroundStyle(.secondary)
            Form {
                TextField("Genre", text: $track.genre)
                TextField("Vibe", text: $track.vibe)
            }.textFieldStyle(.roundedBorder)
            Text("The file will move to the matching folder. Your labels are kept on future scans.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save and move") { save(track) }.buttonStyle(.borderedProminent)
                    .disabled(track.genre.trimmingCharacters(in: .whitespaces).isEmpty || track.vibe.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(28).frame(width: 420)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct CrateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("LiSTd") { CrateView() }
            .defaultSize(width: 1280, height: 920)
            .windowStyle(.titleBar)
    }
}
