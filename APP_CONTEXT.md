# LiStD project handoff

Read this before editing the app in a new chat. This is durable project context,
not a copy of the conversation. Update it when the implementation or decisions change;
record individual edits and their validation in `CHANGELOG.md`. Inspect current source
and state before relying on the snapshot below.

## Purpose and user preferences

LiStD (formerly Crate) is a native macOS app for turning a supplied DJ-set tracklist into downloaded,
verified tracks organized for selecting music for future sets. The intended flow is
drop a tracklist, download through Sockseek, verify, sort, then show which folders
received new tracks. Keep that flow as automatic as practical and available through
the graphical window, without requiring routine Terminal use.

- The development workspace is `/Users/tikkbene/Desktop/MUSIC`; its root app stays
  beside Python source. `./package-crate` builds a separate self-contained sharing
  universal archive at `release/LiStD-Mac.zip`, for Intel/Apple Silicon and macOS 14+.
  The release app uses `~/Music/LiSTd` for each recipient's data and downloads.
- Move audio files instead of creating copies. Never change `juan music` without an
  explicit request. Reuse qualifying existing files rather than downloading again.
- Use professional DJ terminology, no emoji, for default vibe folders:
  **Warm-Up, Groove, Driving, Peak Time, Needs Review**.
- Earlier playful defaults were replaced. `LEGACY_VIBES` maps old automatic labels
  to the professional names; explicit manual overrides must remain untouched.
- Preserve supplied artist, title, real duration and extra CSV fields. A set timestamp
  / `SetStart` is a cue in the mix, not the full length of the original song.
- The supplied chapter list is **Title - Artist**. Plain-text import order is explicit;
  CSV artist/title headers determine their meaning independently of that selection.
- The app starts with 320 kbps or lossless as its quality setting; the user can choose
  a different threshold. Never silently lower it or substitute an alternate mix.

## Current interface (LiStD 1.5 source)

The exact public brand is **LiStD**. `build-crate` produces `LiStD.app` and
`package-crate` now targets `LiStD-Mac.zip`. The public 1.4.1 release and remote
repository have not been renamed or replaced by this work. Keep `local.music.crate`,
Keychain service `local.music.crate.soulseek`, `crate.skin`, `listd.*` preferences,
`LiSTdStandalone`, `~/Music/LiSTd`, existing cache roots and `.music-sorter/` paths
stable for compatibility. The bundle/executable spelling was checked on this case-insensitive macOS volume.
Startup reads Keychain with authentication UI disabled. A rebuilt ad-hoc app can
need reauthorization; its account sheet offers **Unlock saved account**, which
requests the same existing entry on a background task. This keeps startup/playback
usable without bypassing macOS approval or changing/deleting stored credentials.

Every skin has the same resizable collection pane on the left, and a player above
a collapsible **Tracks & imports** drawer on the right. Native `HSplitView` and
`VSplitView` dividers resize actual content. The collection has a 310-point minimum;
the player/drawer have a 440-point minimum width, with independently scrolling
collection, Signal mixer and import content. The window minimum is 800 × 620 (800 × 720 for Amped and Cyber, whose player minimum is
400 points; 800 × 680 for Silverwave, whose player minimum is 340 points).
Players honor the window’s measured top safe-area inset; the lower import pane
does not inherit the top window inset. Amped keeps native transport controls available even when its artwork
is deliberately reduced, and clips the artwork to its allocated canvas.
New import opens the drawer directly. The drawer shows the import picker, current
queue, per-track results, progress, Stop, review/retry actions and New arrivals.
It is nonmodal. Account, label and staged-file review dialogs remain sheets.
The root owns both players and the import model, so changing pane sizes or drawer
visibility does not recreate playback or cancel imports. Collection selection,
search, filters and sort live in the root, too.

The six skins are **Amped · Blue / Red**, **Signal · Dual Deck**,
**Silverwave**, **LiStD · Original**, **Cyber · Lilac** and **Limehead · Mix**. Amped retains its vector boombox, live
spectrum, chrome transport, shell/side/speaker/vent actions and vertical pitch
fader. Player size still controls the artwork's fit within its real player pane.
Silverwave retains its silver/purple panel and decorative display; Original uses
native controls. Cyber (`native/CyberSkin.swift`) recreates the user-supplied lilac
media-player reference as vector artwork in the reference's own 545 × 448 pixel space;
outlines were traced from the image and colours sampled from it, and every hit area
uses the same coordinates. Its wordmark reads LiStD (the reference's brand text was
deliberately not copied). Controls: screen = live spectrum + title/artist/status (eye
toggles the spectrum), groove knob = seek, pink ring ball = volume (+/− marks step 5%,
speaker = mute), ◀ ▶ = speed ∓1%, tri-colour mark = speed reset, title field scrolls
(static under Reduce Motion), time field toggles elapsed/remaining, document button =
Tracks & imports, folder = open file, _ / X = minimize/close. Transport: |◀◀ / ▶▶|
step through the collection pane's current filter and sort (`CollectionBrowser.neighbour`,
no wrap at the ends; previous restarts the song after 3 s; a playing deck keeps playing),
◀◀ / ▶▶ = ∓10 s, ‖ pause, ▶ play (empty deck: loads the first visible collection track,
or opens a file when the collection view is empty), ■ stop. Screen and field text keep minimum
legible sizes (9/8/7.5/7 pt) when Player size shrinks the artwork. Cyber keeps the shared
playback strip and Player size row below the artwork, like Amped.
Limehead · Mix (`native/LimeheadSkin.swift`) recreates the user-supplied green
"head" media-player screenshot in the reference crop's own pixel space (934 × 498;
the geometry still calls the width 935). The head and face, screen outline, both
wings and all six speakers are traced from the screenshot by
`scripts/trace_limehead.py` into `native/LimeheadTrace.swift` (generated, ~1 MB of
outline strings; never edit by hand): head outline = dome against the desktop (lime
test that rejects the teal wallpaper stripe) + sides at the head's dark edge line over
the wings (fixed search bands, smoothed) + jaw/chin against the desktop; shading = 31
green-channel brightness layers (marching squares, 0.12 px tolerance, each filled with
the reference's median colour for its band) with the app's own controls painted out
first; speakers = their own 26 grey layers inside an ellipse outline fitted to the
traced rim (centre/tilt from moments, traced area; tilts 56°/49°/45°, mirrored right).
Wings use no anti-noise blur so the tab stripes and X marks survive; desktop icon and
wallpaper exclusions are explicit boxes in the script. The reference screenshot is not
stored in the repo; re-tracing needs it (command in the script docstring). Hand-drawn
on top: screen fill + visualiser, title pill and its buttons, transport, asterisk,
window keys, seek groove, icons and the panel interiors (mixer/playlist). The
reference has no drop shadows, so the skin draws none. `LimeArtwork` is `Equatable`
and redraws only when a wing opens/closes or the size changes. The visualiser is an
old-Windows oscilloscope: jagged white traces across and down the screen from the
focused deck's raw samples (`AudioSpectrum.wave`, 96 points per window), red trails of
the last 12 frames zooming outward, and a centre hot spot that grows with the level;
it is clipped to the screen minus the pill and still under Reduce Motion. It is a dual-deck skin (`CrateSkin.isDualDeck`, shared with
Signal): the collection and import results offer A/B loading. Left wing = mixer:
Crossfade (constant power, `LimeMixer.gains`) and Master sliders; per deck five
vertical faders V level / P pitch ±8% / L M H EQ cut (0 to −24 dB), a play button
and title; **reset** restores crossfader centre, levels 85%, pitch 1.00 and flat EQ.
Each deck's output volume = master × level × crossfade gain (`LimeMixer.apply`);
leaving the skin sets both decks back to the master level, and deck B pauses unless
the new skin is also dual-deck. Right wing = the collection pane's visible tracks
(current filter/sort); clicking a row loads it paused into the deck named in the
dropdown (click it to switch A/B); the loaded row is highlighted. Head: gold/blue
pill buttons choose which deck the screen, title, transport, seek bar and drops
drive; pill X opens a file into that deck; asterisk toggles the visualiser; |◀◀ ▶▶|
step through the collection (same rules as Cyber); bars/page icons and the wings'
X/tabs hide or show the mixer/playlist; the icon under the seek bar toggles Tracks &
imports; _ / X minimize/close. Faders take arrow keys and VoiceOver adjust. Limehead
shows only the Player size row below the artwork (no shared playback strip, whose
volume slider would fight the mixer).
The ear icon remains `native/Assets/EarIcon.icns`.
Appearance is set per skin with `NSApp.appearance` (`applyAppearance` in
`native/Crate.swift`): Signal dark, Amped/Silverwave/Cyber/Limehead light, Original follows the
system. Do not use SwiftUI `preferredColorScheme(nil)` to restore the system
appearance; it leaves a previously forced dark window partly dark.

All horizontal controls use `StableSlider` in `native/CratePlayer.swift`: one native
NSSlider owns drawing and tracking, avoiding SwiftUI's separate tracking overlay
and inherited layout animations. The native vertical boombox fader retains actual
rendered dimensions. No whole-layout animation follows player-size values.
Stepped sliders quantize at their original increments; keyboard arrows and
accessibility increment/decrement work. Seek commits on mouse/keyboard/accessibility
edit completion. The reported transient upper-left jump was not caught in the
initial UI capture; do not claim a frame-by-frame reproduction from that capture.

## Collection browsing

**All tracks** is the default, sorted naturally by **Track title**. View options are
All tracks, Download folder, Import / tracklist, Genre and Artist. Grouped views
expose an All groups / named group picker. Sorting also supports Artist, BPM
(unknown last) and Most recently added (newest first). Search applies inside the
chosen group. A/B loading (Signal dual deck only), file-URL row dragging, Finder reveal,
playback and manual label editing remain available. Single-deck skins (Original, Silverwave,
Amped, Cyber) show one **Load track** button per row/import result instead of A/B, and accept one
audio file dropped onto the deck panel (loads paused; non-audio and multi-file drops ignored). Label editing is still an explicit disk-changing
action; browsing/sorting never invokes the organizer.

`native/Collection.swift` holds the read-only display calculation. Snapshot metadata
derives folder groups from the current parent under downloads (or Outside downloads)
and import groups from matching catalog IDs / recorded paths. Import labels include
a short ID to distinguish identically named lists. Missing membership is No import
record; missing artist/genre is Unknown artist / Unsorted. New catalog entries store
`added_at`; old catalogs fall back to the earliest associated import's creation time,
then file birth time (mtime on platforms without birth time). This is an approximation
for legacy files and does not trigger a scan or mutate the catalog.

## Signal dual-deck auditioning

Both decks have compact stacked detail/overview waveforms, local beat analysis,
independent transport, original BPM/tap/half/double, ±20 ms nudges, beat cue,
0.5–1.5× varispeed and bass/mid/high cut EQ (0 to −24 dB), level and mute.
Control grids wrap as the pane narrows; the mixer scrolls vertically. Waveforms
resize to the available width. View zoom (12–120 seconds) persists in
`listd.waveformSeconds`. The original 60 fps interpolated waveform, bounded
background waveform reader, Reduce Motion paging, 10 Hz position publication,
manual BPM/cue preservation and read-only analysis remain.

**Sync A to B** calls `a.sync(to: b)`; **Sync B to A** calls `b.sync(to: a)`.
The first named deck changes; the second remains unchanged. Both reuse the same
rate bounds, valid BPM/cue checks and shared future host timestamp. With the target
playing, the follower starts aligned; with it paused, the follower aligns paused.
Sync is one-time tempo/beat phase alignment, without continuous locking, downbeat
or phrase detection. Beats are estimates and fixed-tempo tracks can still drift.
Leaving Signal pauses B; A continues with its settings. Loading and analysis do not
modify audio, tags, catalog or folders. There is no key lock, headphone cue routing,
controller integration, automatic next-track queue, recording or export.

## Optional deep searching

The normal first search is unchanged. A missing row offers **Deep search**, and
**Import actions → Deep search all missing** retries the current import's missing
rows. Staged review files and accepted rows are excluded. Candidate review lists can
be searched again; selecting a candidate requests its download through normal
verification, and does not approve its identity or waive quality checks.

`run ID --deep [--index N] [--candidate N]` uses the existing lock, private account
config, one app-owned loopback Sockseek session, cancellation file and sequential
worker. A row has at most six sequential fallback queries (45 seconds per command,
eight-second Soulseek search), at most 200 inspected results/query, 20 review
candidates and three transfer attempts. Logs stop at 8 MB. Queries normalize accents,
punctuation and spacing; vary artist/title order; focus title; use supplied
Album/Release/Catalog fields; and may omit one long word to retrieve spelling
variants. Each query uses a separate one-row CSV with the original full-track
length. `input.csv`, original imported fields and SetStart cues are not rewritten.

`deep_identity` permits exact artist/title/release combinations and unexpected
metadata placement. Unexplained words, conflicting tags and conservative spelling
variants require review. Unrequested remix/edit/live/dub/radio/other version words
are rejected, and never excused by album metadata. Confident results still pass the
completion hook's local identity, supplied duration, accepted codec, measured bitrate
and full decode before sorting. Fuzzy filenames are never automatically accepted.
No audio fingerprinting or automatic spell correction of imported metadata exists.
The real mock daemon/CLI fallback/transfer/hook/sorter path is tested offline;
live peer availability and rate limits remain dependent on Soulseek.

## Source map and callers

| File | Responsibility |
| --- | --- |
| `native/Collection.swift` | Collection metadata model and pure filtering/grouping/sorting |
| `native/Crate.swift` | SwiftUI window, state polling, import controls, queue/folder/library views, label actions, process launch and skin selection |
| `native/SoulseekAccount.swift` | Codable account and native Security.framework Keychain storage |
| `native/CrateSkin.swift` | Skin enum, Silverwave panels, emblem and decorative display |
| `native/BoomboxSkin.swift` | Blue/red boombox vector artwork and central playback/fader controls |
| `native/CratePlayer.swift` | Local AVFoundation playback engine, mute, spectrum tap and shared seek/speed/volume strip |
| `native/CyberSkin.swift` | Cyber · Lilac vector artwork traced from the reference, its geometry/palette and live overlay controls |
| `native/LimeheadSkin.swift` | Limehead · Mix geometry, traced-shape drawing, live controls, red visualiser and `LimeMixer` |
| `native/LimeheadTrace.swift` | Generated by `scripts/trace_limehead.py`: traced head/face, screen, wings and speakers |
| `scripts/trace_limehead.py` | Re-traces the Limehead artwork from the reference screenshot (standard library only) |
| `native/TechnicalSkin.swift` | Signal stacked waveforms, dual-deck transport and EQ controls |
| `native/AudioSpectrum.swift` | Thread-safe audio frequency analysis and live LED spectrum rendering |
| `native/Assets/EarIcon.icns` | User-provided application icon, copied into the bundle by each build |
| `native/MakeIcon.swift` | Original icon generator |
| `native/MakeSkinIcon.swift` | Silverwave icon generator |
| `crate_backend.py` | Tracklist parsing, durable imports, Sockseek session/search/transfer pipeline, verification, app-owned indexes and JSON snapshots |
| `music_sorter.py` | Audio inspection, automatic labels, catalog, move planning, collision safeguards and undo journal |
| `music-sorter` | Terminal launcher; chooses the local audio environment when available |
| `build-crate` | Builds Swift sources, generates legacy icons, copies the ear icon, writes the bundle plist and signs the local app |
| `package-crate` / `scripts/check_package.py` | Release packaging, optional Developer ID/notarization, dependency audit and isolated offline smoke check |
| `scripts/package_licenses.py` / `THIRD_PARTY.md` | Notices and source provenance bundled in the sharing archive |
| `SHARING.md` | Recipient instructions, signing limitations and release build procedure |
| `STANDALONE_QA.md` | Architecture/runtime validation evidence and remaining distribution limits |
| `requirements-crate.txt` | Pinned librosa 0.11.0 and NumPy/Numba/llvmlite runtime |
| `tests/test_crate_backend.py` | Parser, pipeline, quality/identity rejection, library preservation and label/index-update checks |
| `tests/test_music_sorter.py` | Tempo, naming, incremental sorting, collisions, moves, watch and undo checks |
| `tests/check_crate_skin.swift` | Silverwave emblem, blue/red boombox and Cyber landmark-colour/transparency/volume-ring render checks |
| `tests/check_cyber_player.swift` | Real mouse clicks/drags on every Cyber control in an offscreen window (muted, generated silence) |
| `tests/check_limehead.swift` | Limehead landmark colours, crossfade maths and real mouse drags/clicks on its transport, focus, playlist, faders, reset and wings |
| `tests/check_crate_player.swift` | Generated-audio playback, pause/seek/rate/end/replay, live spectrum tap and pitch response, mute and format-switch checks |
| `tests/check_dual_deck.swift` | Generated-audio dual playback, beat-phase sync, independent EQ attenuation and source preservation |
| `tests/test_deck_analysis.py` | Generated-pulse BPM/beat-cue detection, silence and read-only analysis |
| `tests/check_audio_spectrum.swift` | Silence, frequency, amplitude and stereo-channel analysis plus LED render |
| `CRATE.md` / `MUSIC_SORTER.md` | Graphical-app and command-line usage documentation |

The Swift app launches the Python backend with argument arrays, not a shell command.
Development uses `.music-sorter/audio-env/bin/python` when available, otherwise
`/usr/bin/python3`. The universal release uses
`Contents/Resources/backend/<arm64|x86_64>/listd-backend`, frozen with PyInstaller,
and bundled Sockseek/FFmpeg/FFprobe for that architecture first on PATH. The Swift
executable has both slices and selects its runtime at compile-architecture level.
Only release bundles have the `LiSTdStandalone` Info.plist marker. Missing release
tools show a reinstall error rather than falling back to developer source/Python.
The frozen completion hook relaunches that executable directly instead of expecting
a separate Python script. Numba's cache and Sockseek's .NET extraction cache are
kept in the user's writable workspace, so installed bundles need no write access.
Release build environments/output are cached in `~/Library/Caches/LiSTdBuild`,
outside Desktop sync. The native development build still uses `.music-sorter/build`.
Do not recursively copy a synced frozen output directory into a release: Desktop
sync was observed adding conflict copies of compiled libraries to that directory.
Python-only edits are loaded by subsequent backend processes; Swift/icon edits require
a rebuild and app restart. Do not interrupt a running import just to refresh the UI.

As of 1.4.1, development uses an isolated venv (no system/user site packages), with
the numerical runtime pinned in `requirements-crate.txt` (NumPy 1.26.4, Numba 0.60.0,
llvmlite 0.43.0, librosa 0.11.0). NumPy 2.0.2 reproduced a native crash when concurrent
deck analyses populated/reused beat-kernel caches; cache isolation alone was not
sufficient. Keep the pinned stable runtime. It makes the sharing archive larger;
the resource savings are reduced background work, not a smaller download.
The previous environment
is retained at `.music-sorter/audio-env-before-1.4.1` for rollback. Beat-analysis
compiled caches default to `~/Library/Caches/LiSTd/numba/<runtime-key>`, outside the
synced Desktop. The key separates executable, Python, CPU architecture and installed
librosa/NumPy/Numba/llvmlite versions. `NUMBA_CACHE_DIR` can override the parent directory
for isolated tests. Do not reuse the old unpartitioned `.music-sorter/numba-cache`.
First analysis in a fresh runtime takes longer while numerical kernels compile.
Deck analysis reuses the same onset envelope for tempo and beat fitting.
Waveform readers cancel when a deck loads another file. Snapshot polling remains
every two seconds during imports, and runs every ten seconds when idle, with an
immediate refresh on app activation and local actions. Unchanged jobs/library arrays
are not republished, avoiding unnecessary collection redraws.

Source history is in the repository https://github.com/tikkbene-commits/LiSTd.
The baseline precedes the 1.4.1 stability changes. Music, personal root playlists,
credentials/config, state, environments, generated app bundles and releases are
excluded from Git. The supplied sample tracklist remains a source fixture.

Public-facing documentation is in `README.md` and the friend-oriented `INSTALL.md`.
The README has Amped/Signal previews rendered from real views with generated example
audio by `scripts/render_readme.swift`; it does not show a personal library/account.
Original LiStD code is MIT licensed (`LICENSE`, copyright Benedek Tikk); dependency
licenses remain separate. The v1.4.1 GitHub release provides the unchanged tested
Mac ZIP, SHA256SUMS.txt and LICENSE. The user reports the app is now public; this work does not change repository visibility. Download links use GitHub Releases, not source ZIPs.
Separate Sockseek installation is only for source development/standalone CLI use;
README Requirements links upstream and the tested 3.0.6 Mac archives, with a manual
one-line install command after extraction. Do not invent an upstream shell installer:
the upstream Quick Start inspected on 2026-11-19 points to release archives.

When changing behavior, follow its callers across the Swift UI, backend, organizer,
tests and docs. For folder changes, preserve the catalog IDs, manual overrides,
recovery history, import paths and app-owned Sockseek index paths together.

## Download and sorting contract

1. Imports persist their original text/CSV and parsed rows. Check existing qualifying
   tracks before requesting new files.
2. One owned Sockseek daemon runs on `127.0.0.1` for an import and shuts down afterward.
   Keeping a session open avoids repeated reconnections/peer-socket failures seen in
   the first live test. Search CSV rows individually, with one concurrent job/search.
3. Filter obvious alternate versions and try up to three exact candidate peers.
   Search hits and nominal bitrates alone do not prove a successful download.
4. Downloads initially land under `downloads/.incoming/<import-id>/`. The custom Crate
   completion hook checks codec, supplied duration, title/artist evidence, measured
   audio-packet bitrate and full-file decoding before invoking the organizer.
5. Accepted files move into `downloads/organized/<genre>/<vibe>/`, and Sockseek receives
   the new path through its completion/index-update protocol. Rejected/uncertain files
   stay in staging; failed `.incomplete` transfers are never counted as songs.
6. Relabeling updates file paths and app-owned indexes/hook metadata. Label editing
   waits until imports finish to avoid competing writes to job state. Snapshot results
   reconcile catalog paths so a moved/missing file is not blindly shown as ready.

Do not add the generic organizer completion hook to Crate commands: Crate already has
its own verification-first hook. Do not run the terminal watcher alongside an import.
Follow all credential, quality and protected-folder rules in `AGENTS.md`.

## Reviewing imports and correcting order

Review status badges and row menus open a panel showing the file’s tags, filename,
codec, duration and rejection reason, with an independent listening preview and
Finder reveal. Expected artist/title fields can be corrected or swapped, then
**Save & recheck file** reruns the normal identity, supplied-duration, measured-quality
and full-decode checks. It does not override those checks or rewrite tags.

Before any tracks are accepted, **Swap artist / title & recheck** corrects the entire
import and checks the staged review files locally. The original source text and each
row’s `original` fields remain intact; `input.csv` receives the corrected search
fields while preserving duration/extra columns. Accepted files move through the
existing organizer; job paths, hook outcomes and owned indexes update together.
Both correction actions take the download lock. They start no network activity.
Not-found rows still require a user-requested retry to search again.

On 2026-11-18, import `cf100cc63f74` (Vienna Scientists III) was repaired from reversed
artist/title order: all nine staged review files passed full verification at measured
320.01 kbps and were filed; three rows remain unavailable. Source file signatures
(device, inode, size, modification time) were preserved. Pre-correction job/input/hook/
index files are in `.music-sorter/build/before-review-fix-cf100cc63f74/`.

## Data that must survive edits

| Location | Meaning |
| --- | --- |
| `.music-sorter/catalog.json` | Stable track IDs, cached analysis, manual overrides and reversible move history |
| `.music-sorter/crate/jobs/<id>/` | Durable import state, original input, completion outcomes, indexes and local logs |
| `.music-sorter/audio-env/` | Isolated Python audio-analysis environment with pinned numerical dependencies |
| `.music-sorter/build/` | Generated native build/icon artifacts |
| `~/Library/Caches/LiSTdBuild/` | Disposable release-only environments, frozen runtimes and tool-build cache, outside Desktop sync |
| `downloads/.incoming/` | Staging; may include complete files awaiting review, not just disposable partial transfers |
| `downloads/organized/` | Accepted organized audio files |
| `downloads/delete_review/` | Existing review collection; excluded from ordinary organization |
| `juan music/` | Protected existing library; read-only unless the user requests a change |

`.music-sorter/` is gitignored but is still essential local data. Do not delete it to
reset the app or treat all of it as a build cache. Do not copy, print or commit the
Sockseek credentials from `~/.config/sockseek/sockseek.conf`. The graphical app now
has a Soulseek account button in every skin and first-launch sign-in. It verifies
login with a print-only search and stores the account using Security.framework in
macOS Keychain (service `local.music.crate.soulseek`). Subsequent imports send that
account as JSON over stdin, never as process arguments. Backend `login` / `run` use
a temporary mode-600 Sockseek config in a mode-700 system temporary directory,
removed on normal success/failure. A forced kill/crash can leave that private
temporary file until OS cleanup. No global Sockseek configuration is modified or
copied. Remote commands use `--no-config` to avoid inherited global settings.
Changing/signing out accounts is disabled during imports; logout preserves music
and history. Playback works without login. CLI `run` with no stdin account keeps
the legacy global-config behavior; CLI download rules remain in AGENTS.md.
The login result uses Sockseek's explicit logged-in confirmation: a print-only
query that finds no files exits 1 even after successful authentication, and must
not be treated as a failed login.

## Evidence boundaries and known limitations

- A renamed/rebuilt ad-hoc development app may need macOS approval for Desktop files
  and the existing Keychain entry. Startup suppresses legacy Keychain UI, preserving
  the window and stored entry; Unlock saved account requests authorization explicitly.
  The legacy no-UI guard uses deprecated SecKeychain APIs because modern flags did
  not suppress this existing store's authorization prompt; migrate only deliberately.
- macOS file access was approved during the 1.5 UI follow-up. On November 21, the
  final rebuilt binary displayed all 155 existing tracks and the original import
  history in Signal, including visible A/B buttons at the narrow window size and
  an independently resized import drawer. Silverwave, Amped and Original layouts
  were also inspected during the follow-up. No scan/reorganization was needed.
- Native slider tracking sends its final snapped value again after AppKit finishes
  mouse tracking, keeping the thumb, accessibility value and displayed value equal.
  Actual waveform-zoom clicking and keyboard stepping verified this final fix.
- The collection title column now follows its pane's actual width, reserving room
  for BPM and A/B buttons. Amped's vertical fader uses the shared first-responder
  slider class with its original chrome cell; its focus and accessibility increments
  passed a native hosted-control regression check. Final automated pointer dragging
  of that custom fader was blocked by the UI driver's noWindowsAvailable error.

- Genre is a file tag or manual label. Missing/conflicting genre tags remain `Unsorted`.
  No trained audio genre/mood model is installed.
- Librosa estimates tempo from three 24-second excerpts, with agreement/pulse checks;
  valid BPM tags take priority. A simple bass-amplitude fallback exists. Half/double
  tempo and other beat errors remain possible. Vibe is a broad tempo/crest-factor
  heuristic, not a guaranteed musical judgment or a DJ beat grid.
- The YouTube URL is a source link for the provided list. The app does not recognize
  tracks by fingerprinting the set or download the YouTube mix itself.
- Share only `release/LiStD-Mac.zip`, not the development root app or MUSIC
  folder. No Developer ID certificate was available for this build: ad-hoc signing
  cannot remove Gatekeeper first-open approval. See SHARING.md for optional signing
  and notarization. Windows is unsupported. Intel code is checked under Rosetta on
  this Apple Silicon Mac; a physical Intel Mac/macOS 14 acceptance check is separate.
  The user explicitly accepted one-time Open Anyway approval for recipients in this
  sharing workflow. Notarization is optional unless they request warning-free opening.
- The build removes a FinderInfo attribute that the synced Desktop can add to the
  generated bundle before signing. If verification reports that attribute later,
  inspect the generated app's attributes; do not disable macOS security protections.

## Verified project snapshot — 2026-11-18

Checked from the current local catalog/import state when writing this handoff:

- Catalog: 147 entries after the Vienna Scientists repair. This is a snapshot, not a count to hard-code.
- Supplied set: `tracklists/YouTube set bNSesW8h94I.csv`.
- Import ID: `bc37ab91534c`, with 15 rows marked ready and all 15 file paths present.
- Folder counts: Warm-Up 6, Groove 6, Driving 1, Peak Time 2. All are under `Unsorted`
  because these files lack usable genre tags.
- The live test previously verified measured 320 kbps and full decoding for all 15.
  Its detailed record is `.music-sorter/crate/jobs/bc37ab91534c/verification.json`.
- The split-layout/beatmatch revision passed all 26 Python tests, the native player
  suite and dual-deck suite, including actual rendered pulse phase and compact
  waveform render checks. No new live downloads were started.
- Sharing/login revision: all 29 Python tests pass, including private account-config
  lifetime/cleanup, sanitized login failures and account forwarding through a fake
  peer import. The release bundle passes a clean-HOME/no-Homebrew offline CSV,
  generated-audio beat-analysis and frozen completion/organizer check, external
  dependency/minimum-macOS audit, and strict deep codesign verification after ZIP
  extraction. Opened the exact release ZIP's app and inspected its first-launch
  sign-in sheet and empty personal workspace; reopened the development app with
  the existing 147-track library. No real account was entered or saved during QA.
  Initial sharing QA did not test live login/Keychain persistence. The 1.3.1 fix
  subsequently verified successful real Soulseek authentication, graphical sign-in
  and saved-account reload after restart, including the rebuilt 1.3.1 app. The
  exact updated ZIP's frozen backend also passed a real login using its bundled
  Sockseek; strict deep signature verification passed after extraction. Separate physical Macs, Gatekeeper
  approval on a quarantined download and Developer ID/notarization remain untested.
- Universal 1.4: all 29 Python tests and both architecture player/dual-deck/spectrum/
  skin suites passed. Both exact-ZIP runtimes passed the stricter relocated,
  read-only/clean-HOME sandbox pipeline, actual mock transfer/callback/index update,
  relabel/reload, real login and nine-codec verification/organizer checks. Native
  startup/process checks observed both slices selecting their correct bundled
  backend and fresh per-user root. Strict signature and ZIP CRC/layout checks passed.
  The final visual click-through was blocked by the native inspection service
  failing to start; do not describe it as visually verified. Physical Intel/macOS 14
  testing is still outstanding. Gatekeeper assessment rejected the ad-hoc build;
  no Developer ID identity is present. Details are in STANDALONE_QA.md.

Source/state are authoritative over this snapshot. New chats should inspect the job
JSON/catalog rather than assume counts or old test results remain current.

1.4.1 local validation (2026-11-19): 30 Python tests passed, including cold/warm
backend processes with the previous app-cache parent. Native player, dual-deck,
spectrum and skin suites passed; both native slices built. Graphical Signal analysis
completed for Black Russian and Blah Blah with fitted cues and sync enabled. Audio
hashes and catalog/job JSON hashes were unchanged. Idle polling produced three
backend snapshot launches in 24 seconds. See CHANGELOG.md and STANDALONE_QA.md for
standalone-package evidence and checks not performed.
Final concurrent cold/warm generated-audio subprocess tests passed, as did concurrent
Black Russian/Blah Blah analysis and repeated GUI analysis on the pinned runtime.
The stable 1.4.1 ZIP passed both architecture sandbox pipelines, CRC/source equality
and strict deep signature verification after extraction.

## Commands for future edits

```sh
# Build the native app after Swift/icon changes.
./build-crate

# Deterministic tests: generated audio/temp folders, no live downloads.
.music-sorter/audio-env/bin/python -m unittest discover -s tests -v

# Native skin/logo check after visual changes.
swiftc -parse-as-library native/CrateSkin.swift native/CratePlayer.swift native/BoomboxSkin.swift native/AudioSpectrum.swift native/CyberSkin.swift tests/check_crate_skin.swift -o .music-sorter/build/check-skin
.music-sorter/build/check-skin

# Cyber control interaction check (offscreen window, synthetic mouse events).
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift native/CyberSkin.swift tests/check_cyber_player.swift -o .music-sorter/build/check-cyber-player
.music-sorter/build/check-cyber-player

# Limehead render + control check (offscreen window, synthetic mouse events).
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift native/CyberSkin.swift native/Collection.swift native/LimeheadSkin.swift native/LimeheadTrace.swift tests/check_limehead.swift -o .music-sorter/build/check-limehead
.music-sorter/build/check-limehead

# Muted native playback checks using temporary generated WAV files.
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift tests/check_crate_player.swift -o .music-sorter/build/check-player
.music-sorter/build/check-player

swiftc -parse-as-library native/AudioSpectrum.swift tests/check_audio_spectrum.swift -o .music-sorter/build/check-spectrum
.music-sorter/build/check-spectrum

# Read current app state; does not start downloads.
.music-sorter/audio-env/bin/python crate_backend.py snapshot

# Organizer dependency/status check and a read-only catalog listing.
./music-sorter doctor
./music-sorter list
```

For native UI changes, rebuild and visually inspect the actual window, relevant skin
and controls. Do not claim the app was tested by compilation alone. Do not start new
live transfers as a generic smoke test; obtain an actual download request first.
