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
    let candidates: [SearchCandidate]?
    var id: Int { index }
}

struct SearchCandidate: Decodable, Identifiable, Equatable {
    let filename: String
    let username: String
    let reason: String
    let number: Int
    var id: Int { number }
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
    @Published var accountNeedsUnlock = false
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
            account = try SoulseekKeychain.load(allowInteraction: false)
            accountUsername = account?.username ?? ""
            configured = account != nil
        } catch {
            accountNeedsUnlock = true
            accountError = "macOS needs permission to read the saved account. Choose Unlock saved account; your existing Keychain entry is preserved."
        }
    }

    func unlockAccount() {
        guard !signingIn else { return }
        signingIn = true
        Task.detached {
            let result = Result { try SoulseekKeychain.load() }
            await MainActor.run {
                self.signingIn = false
                do {
                    self.account = try result.get()
                    self.accountUsername = self.account?.username ?? ""
                    self.configured = self.account != nil
                    self.accountNeedsUnlock = false
                    self.accountError = nil
                    if self.configured { self.showAccount = false; self.refresh() }
                } catch { self.accountError = error.localizedDescription }
            }
        }
    }

    func request(_ arguments: [String], input: String? = nil, done: @escaping (Result<Data, Error>) -> Void) {
        let project = root
        Task.detached {
            do {
                let process = Process()
                let audioPython = project.appendingPathComponent(".music-sorter/audio-env/bin/python")
                let bundled = Self.bundledBackend
                if Bundle.main.object(forInfoDictionaryKey: "LiSTdStandalone") as? Bool == true && bundled == nil {
                    throw NSError(domain: "Crate", code: 1, userInfo: [NSLocalizedDescriptionKey: "LiStD’s bundled tools are missing. Extract the complete app from the ZIP and try again."])
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

    func start(_ id: String, deep: Bool = false, index: Int? = nil, candidate: Int? = nil) {
        guard let account else {
            if deep { error = "Sign in, then choose Deep search again."; showAccount = true; return }
            if !pending.contains(id) { pending.append(id) }
            showAccount = true
            return
        }
        guard !working && !jobs.contains(where: { $0.status == "running" }) else {
            if deep { error = "Wait for the current import or stop it before deep searching."; return }
            if !pending.contains(id) { pending.append(id) }
            return
        }
        working = true
        let input = String(data: try! JSONEncoder().encode(account), encoding: .utf8)!
        var arguments = ["run", id]
        if deep { arguments.append("--deep") }
        if let index { arguments += ["--index", String(index)] }
        if let candidate { arguments += ["--candidate", String(candidate)] }
        request(arguments, input: input) { result in
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
                self.accountNeedsUnlock = false
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
    @State private var collectionView = "All tracks"
    @State private var collectionGroup = ""
    @State private var collectionSort = "Track title"
    @State private var folderJobID: String?
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var selectedJob: ImportJob? { model.jobs.first { $0.id == model.selection } }

    var body: some View {
        GeometryReader { geometry in
        HSplitView {
            technicalCollection.frame(minWidth: 310, idealWidth: 390, maxWidth: 650)
            VSplitView {
                mixer.padding(.top, geometry.safeAreaInsets.top)
                    .frame(minWidth: 440, minHeight: skin == .boombox ? 400 : skin == .silverwave ? 340 : 230, maxHeight: .infinity)
                if showWorkspace {
                    importDrawer.ignoresSafeArea(.container, edges: .top)
                        .frame(minWidth: 440, minHeight: 240, idealHeight: 340)
                        .transition(.move(edge: .bottom))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        }
        .tint(skin.accent)
        .preferredColorScheme(skin == .technical ? .dark : skin == .classic ? nil : .light)
        .frame(minWidth: 800, minHeight: skin == .boombox ? 720 : skin == .silverwave ? 680 : 620)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { model.showAccount = true } label: { Label(model.configured ? model.accountUsername : "Sign in to Soulseek", systemImage: "person.crop.circle") }
                .disabled(model.working || model.signingIn || model.jobs.contains(where: { $0.status == "running" }))
            }
            ToolbarItem(placement: .automatic) { skinPicker }
            ToolbarItem(placement: .automatic) {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showWorkspace.toggle() } } label: {
                    Label("Tracks & imports", systemImage: "sidebar.trailing")
                }.help("Show or collapse the resizable import drawer")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.selection = "import"; showWorkspace = true } label: { Label("New import", systemImage: "plus") }
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
        .alert("LiStD needs your attention", isPresented: Binding(get: { model.error != nil || player.error != nil || deckB.error != nil }, set: { if !$0 { model.error = nil; player.error = nil; deckB.error = nil } })) {
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

    @ViewBuilder var mixer: some View {
        if skin == .technical {
            ScrollView(.vertical) { TechnicalPlayer(a: player, b: deckB, analyze: analyzeDeck).frame(maxWidth: .infinity) }
        } else if skin == .boombox { boombox }
        else if skin == .silverwave {
            VStack(spacing: 12) {
                SilverwaveDisplay(title: player.title, subtitle: player.artist, count: "LiStD · SILVERWAVE")
                Spacer(minLength: 0)
                PlaybackStrip(player: player)
            }.padding(14).modifier(MetalPanel(radius: 18))
        } else {
            VStack {
                Text("LiStD").font(.largeTitle)
                Text(player.title).font(.title2).lineLimit(2)
                Text(player.artist).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                PlaybackStrip(player: player)
            }.padding()
        }
    }

    var importDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tracks & imports").font(.headline)
                Spacer()
                Button("Collapse") { showWorkspace = false }
            }.padding(12)
            HStack {
                Picker("Show", selection: $model.selection) {
                    Text("New import").tag("import")
                    Text("New arrivals").tag("folders")
                    ForEach(model.jobs) { job in
                        Text("\(job.name) · \(job.ready)/\(job.tracks.count)").tag(job.id)
                    }
                }.labelsHidden().frame(maxWidth: .infinity)
                if model.jobs.contains(where: { $0.status == "running" }) { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            workspace
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    var browser: CollectionBrowser {
        CollectionBrowser(tracks: model.library, collectionView: collectionView, collectionGroup: collectionGroup,
                          collectionSort: collectionSort, search: search)
    }

    var technicalCollection: some View {
        let filtered = browser.visibleTracks
        let groupNames = Array(Set(model.library.flatMap { browser.groups(for: $0) })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return GeometryReader { geometry in
        VStack(spacing: 8) {
            HStack {
                Text("COLLECTION").tracking(2).font(.system(size: 10, weight: .medium, design: .monospaced))
                Spacer()
                Text("\(filtered.count) / \(model.library.count)").font(.caption).foregroundStyle(.secondary)
            }
            Picker("View", selection: $collectionView) {
                ForEach(["All tracks", "Download folder", "Import / tracklist", "Genre", "Artist"], id: \.self) { Text($0) }
            }.onChange(of: collectionView) { _, _ in collectionGroup = "" }
            if collectionView != "All tracks" {
                Picker(collectionView, selection: $collectionGroup) {
                    Text("All groups").tag("")
                    ForEach(groupNames, id: \.self) { Text($0).tag($0) }
                }.help("Filter the collection by \(collectionView.lowercased()); files stay in place")
            }
            Picker("Sort", selection: $collectionSort) {
                ForEach(["Track title", "Artist", "BPM", "Most recently added"], id: \.self) { Text($0) }
            }
            TextField("Search this view", text: $search).textFieldStyle(.roundedBorder)
            Table(of: LibraryTrack.self, selection: $technicalSelection) {
                TableColumn("Track") { track in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).lineLimit(1)
                        Text("\(track.artist.isEmpty ? "Unknown artist" : track.artist) · \(track.genre)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 5).help("\(track.artist) — \(track.title) / \(track.genre)")
                }.width(max(80, geometry.size.width - 200))
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
                        .contextMenu {
                            Button("Show in Finder") { model.reveal(track.path) }
                            Button("Play in LiStD") { player.play(path: track.path, title: track.title, artist: track.artist) }
                            Button("Edit genre & vibe…") { model.editing = EditTrack(id: track.id, title: track.title, genre: track.genre, vibe: track.vibe) }
                                .disabled(model.working || model.jobs.contains { $0.status == "running" })
                        }
                }
            }.font(.system(size: 11)).tableStyle(.inset(alternatesRowBackgrounds: false))
            if filtered.isEmpty { Text("No tracks in this view").font(.caption).foregroundStyle(.secondary) }
        }.padding(12).frame(maxHeight: .infinity)
        }
    }

    func loadDeck(_ deck: CratePlayer, track: LibraryTrack) {
        deck.play(path: track.path, title: track.title, artist: track.artist, autoplay: false, bpm: track.bpm)
        analyzeDeck(deck)
    }

    var skinPicker: some View {
        Picker("Skin", selection: $skin) {
            ForEach(CrateSkin.allCases) { option in Text(option.title).tag(option) }
        }.pickerStyle(.menu).fixedSize().accessibilityLabel("Skin").help("Change LiStD’s skin")
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
                else if model.selection == "library" { importView }
                else if model.selection == "folders" { foldersView(job: model.jobs.first(where: { $0.id == folderJobID }) ?? model.jobs.first) }
                else if let job = selectedJob { jobView(job) }
                else { importView }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }.sheet(item: $model.reviewing) { review in
            TrackReviewPanel(model: model, player: player, review: review)
        }
    }

    var boombox: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                BoomboxPlayer(player: player, showTracks: { showWorkspace.toggle() })
                    .frame(width: geometry.size.width * playerSize, height: geometry.size.height * playerSize)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }.frame(minHeight: 211).clipped()
            PlaybackStrip(player: player)
            HStack {
                Text("Player size").font(.caption)
                StableSlider(value: $playerSize, in: 0.45...1).frame(minWidth: 60, maxWidth: 160).accessibilityLabel("Player size")
                Text("\(Int(playerSize * 100))%").monospacedDigit().frame(width: 38)
                Button("Fill window") { playerSize = 1 }
            }.padding(.horizontal).padding(.bottom, 8)
        }.background(LinearGradient(colors: [Color(red: 0.90, green: 0.94, blue: 0.97), .white, Color(red: 0.59, green: 0.68, blue: 0.78)], startPoint: .top, endPoint: .bottom))
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Download and organize automatically", isOn: $automatic).toggleStyle(.checkbox)
                    Spacer()
                    Button(automatic ? "Download & organize" : "Import for review") {
                        model.importText(text, name: name, order: order, minimum: minimum, automatic: automatic)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.ready)
                }
                Text("CSV artist, title and duration fields are preserved. Set timestamps are cue points, not track lengths.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 1050, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.name).font(.headline).lineLimit(1).help(job.name)
                    Text("\(job.ready) / \(job.tracks.count) ready · \(job.minimum) kbps or lossless")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if job.status == "running" {
                    Button("Stop") { model.stop(job.id) }
                } else {
                    Menu("Import actions") {
                        Button(job.status == "queued" ? "Download & organize" : "Retry unfinished") { model.start(job.id) }
                        Button("Deep search all missing") { model.start(job.id, deep: true) }
                            .disabled(!job.tracks.contains { ["unavailable", "stopped", "review"].contains($0.status) && $0.path.isEmpty })
                        if job.ready == 0 {
                            Button("Swap artist / title & recheck") { model.correctImport(["swap-order", job.id]) }
                        }
                        Button("Show new folders") { folderJobID = job.id; model.selection = "folders" }
                        if let url = URL(string: job.source), !job.source.isEmpty { Link("View source set", destination: url) }
                    }.disabled(model.working || model.jobs.contains { $0.status == "running" })
                }
            }.padding(.horizontal, 12).padding(.top, 8)
            if job.status == "running" {
                ProgressView(value: Double(job.ready + job.attention), total: Double(max(1, job.tracks.count))).padding(.horizontal, 12)
                Text(job.message).font(.caption).lineLimit(2).padding(.horizontal, 12)
            }
            List(job.tracks) { track in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(track.cue.isEmpty ? String(format: "%02d", track.index + 1) : track.cue)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).fontWeight(.medium).lineLimit(2)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        StatusPill(status: track.status)
                    }
                    Text(track.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                        if ["ready", "existing"].contains(track.status), !track.path.isEmpty {
                            Button("Load A") { player.play(path: track.path, title: track.title, artist: track.artist, autoplay: false, bpm: track.bpm) }
                            Button("Load B") { deckB.play(path: track.path, title: track.title, artist: track.artist, autoplay: false, bpm: track.bpm) }
                            Button("Show in Finder") { model.reveal(track.path) }
                            Text(track.quality ?? "").font(.caption)
                            if let id = track.track_id {
                                Button("Genre & vibe…") { model.editing = EditTrack(id: id, title: track.title, genre: track.genre, vibe: track.vibe) }
                                    .disabled(model.working || model.jobs.contains { $0.status == "running" })
                            }
                        }
                        if track.status == "review", !track.path.isEmpty {
                            Button("Review file…") { model.reviewing = ReviewTrack(jobID: job.id, track: track) }
                        }
                        if ["unavailable", "stopped", "review"].contains(track.status), track.path.isEmpty {
                            Button("Deep search") { model.start(job.id, deep: true, index: track.index) }
                                .disabled(model.working || model.jobs.contains { $0.status == "running" })
                        }
                    }.buttonStyle(.bordered).controlSize(.small)
                    if let candidates = track.candidates, !candidates.isEmpty {
                        DisclosureGroup("\(candidates.count) candidates need review") {
                            ForEach(candidates) { candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.filename).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    Text("\(candidate.username) · \(candidate.reason)").font(.caption).foregroundStyle(.secondary)
                                    Button("Download & verify this candidate") {
                                        model.start(job.id, deep: true, index: track.index, candidate: candidate.number)
                                    }.disabled(model.working || model.jobs.contains { $0.status == "running" } || !track.path.isEmpty || ["ready", "existing"].contains(track.status))
                                }.padding(.vertical, 5)
                            }
                            Text("Selection still requires the original identity, duration, measured quality and complete decode. Uncertain files remain staged for review.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.vertical, 6)
            }.listStyle(.inset)
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

    var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(model.ready && model.configured ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(!model.ready ? "Download tools unavailable" : model.configured ? "Soulseek account saved" : "Sign in to Soulseek")
            Spacer()
            Text("Genre tags · estimated vibes").lineLimit(1)
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
            if model.accountNeedsUnlock {
                Button("Unlock saved account") { model.unlockAccount() }
                    .help("Ask macOS to authorize this rebuilt app to read the existing Soulseek account. Does not change or remove the account.")
            }
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
        WindowGroup("LiStD") { CrateView() }
            .defaultSize(width: 1280, height: 920)
            .windowStyle(.titleBar)
    }
}
