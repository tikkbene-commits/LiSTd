# LiSTd project handoff

Read this before editing the app in a new chat. This is durable project context,
not a copy of the conversation. Update it when the implementation or decisions change;
record individual edits and their validation in `CHANGELOG.md`. Inspect current source
and state before relying on the snapshot below.

## Purpose and user preferences

LiSTd (formerly Crate) is a native macOS app for turning a supplied DJ-set tracklist into downloaded,
verified tracks organized for selecting music for future sets. The intended flow is
drop a tracklist, download through Sockseek, verify, sort, then show which folders
received new tracks. Keep that flow as automatic as practical and available through
the graphical window, without requiring routine Terminal use.

- The development workspace is `/Users/tikkbene/Desktop/MUSIC`; its root app stays
  beside Python source. `./package-crate` builds a separate self-contained sharing
  universal archive at `release/LiSTd-Mac.zip`, for Intel/Apple Silicon and macOS 14+.
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

## Current interface

The native window has Import tracklist, New arrivals and Library views, an import
history, per-track outcomes, Finder reveal/open-folder actions, internal audio
playback, and manual genre/vibe corrections. Automatic import can be
turned off to inspect a queue before starting downloads.

The current source includes four selectable skins:

- **Amped · Blue / Red**, the initial skin: a vector recreation of the user's boombox
  reference, with its green shell changed to blue and blue lettering changed to red.
  It has chrome rims, black mesh speakers, a black LCD with live LEDs, central transport buttons and a
  draggable pitch fader. Implemented in `native/BoomboxSkin.swift`.

- **Signal · Dual Deck**: a dark, minimal technical view with stacked green waveforms,
  independent A/B playback, three-band cut EQ, beat analysis and B-to-A tempo/phase sync.
  Implemented in `native/TechnicalSkin.swift`.

- **Silverwave**: silver/purple styling inspired by early Windows
  Media Player, implemented in `native/CrateSkin.swift`.
- **LiSTd · Original**, the original native macOS presentation.

The toolbar Skin picker saves its selection with `@AppStorage("crate.skin")`. Changing
the skin changes the window without interrupting playback or imports. All skins use
the user's supplied ear icon in the Dock and Finder; its durable source is
`native/Assets/EarIcon.icns`. Retained icon generators still build the earlier resources.
The Silverwave purple display remains decorative. The boombox LCD has a real
32-band logarithmic audio spectrum behind the title: green/yellow/orange/red LED
segments and a faint reflection, based on the playing audio rather than random bars.
Click the LCD to toggle it. It is blank when paused/stopped and respects Reduce Motion.
Preserve all four skins during unrelated edits.

Amped now gives most of the window to the player by default. A saved **Player size**
slider scales the whole device from 45% to 100%; **Fill window** restores 100%.
**Tracks & imports** opens/closes a drawer with the existing workspace. New import
opens it automatically; clicking the LiSTd logo also toggles it. The drawer and size
preferences use `listd.showWorkspace` / `listd.playerSize`. Button presses have short
spring/highlight feedback; resize and drawer transitions animate with Reduce Motion
respected. All visible control areas have actions and accessibility/help labels:
top switches = mute, minimize, close; side controls = volume down/up; speakers =
back/forward 10 seconds; vents = pitch down/up; shell = play/pause (or open audio when
empty); LCD = spectrum toggle; center = transport, open file and pitch fader.
The artwork canvas renders at its final size to stay sharp. The native pitch fader
also receives its actual rendered dimensions instead of a transformed small view,
keeping mouse tracking calibrated as the player is resized. Its chrome thumb is an
NSSliderCell drawing; the native control retains keyboard/accessibility behavior.

The displayed brand, app bundle and executable are now LiSTd. Source filenames,
`build-crate`, the `local.music.crate` bundle identifier, `crate.skin` preference and
`.music-sorter/crate` data paths deliberately remain stable, preserving saved imports
and skin selection. The previous app was archived in
`.music-sorter/build/before-listd/Crate.app`; use the root `LiSTd.app` for normal use.

Playback uses AVAudioEngine → AVAudioPlayerNode → AVAudioUnitVarispeed → AVAudioUnitEQ → mixer/output
in `native/CratePlayer.swift`. A tap after EQ and before the output volume feeds
`native/AudioSpectrum.swift`: a Hann-windowed 2048-point Accelerate DFT, 40 Hz–16 kHz
log bands, a lock-protected snapshot and a 24 fps display. The louder channel is used
so channel cancellation or a silent left channel cannot hide the spectrum. Volume and
mute affect listening; the pre-volume spectrum continues to show the playing signal.
Library and accepted import rows play directly inside
LiSTd; Open audio file also plays a local file without importing, sorting or copying it.
Controls include play/pause, stop, seek, volume and 0.5×–1.5× speed. Pitch follows speed
like a turntable; the UI displays the percentage and semitone change. Reset restores
1×. The boombox additionally has ±10-second buttons and a vertical pitch fader.
All skins share deck A for the window; Signal adds an independent deck B. Rate/volume persist across skin changes
within the session. Playback does not modify audio files, tags or the organizer catalog.
There is no automatic next-track queue, independent key lock or audio export.

## Signal dual-deck auditioning

Signal is a fourth skin, selected with the existing Skin menu. Load a library track
with its A/B button, or use the deck’s Open file button; these load paused and do
not import, move, download or edit the source. The collection occupies the left third
of the window at full height, with search, two-line title/artist/genre rows, BPM and
A/B loading. The decks and EQ occupy the right two thirds in an independent vertical
scroll view. Header/transport/tempo controls use separate rows to fit the narrower
column; the ratio follows window resizing. Waveforms stream from AVAudioFile
on a background task, with bounded peak storage (up to 120,000 bins). Compact stacked
windows default to 60 seconds on the same wall-clock scale; the shared View slider
zooms from 12 to 120 seconds and persists as `listd.waveformSeconds`. Detail/overview
heights are 44/18 points, with reduced detail amplitude. Overviews seek anywhere in each file. Waveforms
use a 60 fps SwiftUI animation timeline and interpolate the audio render timestamp
against the host clock. Transport labels publish at 10 Hz so the collection table
is not rebuilt 60 times per second. Waveform bins stay anchored to the audio while
scrolling, rendered as a filled envelope instead of moving thin bars to reduce subpixel
shimmer; drawing is clipped to each lane. Reduce Motion uses stationary
waveform pages with a moving playhead.

Signal collection rows export file URLs through native table row item providers,
with native row selection enabled.
Drop one local audio file (from the collection or Finder) onto either waveform lane
to load that deck paused; this triggers the existing read-only beat analysis.
Unsupported/nonlocal/multiple-file drops are rejected. A/B buttons and file pickers
remain available.
The file-URL provider and audio type checks were verified, but automated native
drag gestures did not confirm an end-to-end drop in this session. A/B loading was
verified in the actual app; do not describe drag-and-drop as UI-verified yet.

Each deck has play/pause, stop, seek, ±20 ms nudges, original BPM entry, tap tempo,
0.5×–1.5× varispeed, beat cue and independent level/mute. Separate low-shelf (250 Hz),
parametric mid (1 kHz, two octaves) and high-shelf (4 kHz) filters cut from 0 to −24 dB.
Reset EQ restores all three bands. First opening Signal caps A at 50% and starts B at
50% for mixing headroom; raising both levels can clip their combined output.

Loading a deck in Signal requests the read-only backend
`deck-analysis PATH [--bpm N] [--refine-bpm]`. Catalog BPM or the existing spectral
estimator provides an initial tempo. Local librosa detects beats in the first 90
seconds, then short-window period estimates and strong onsets fit a fractional BPM
and grid anchor. Grid numbers are reassigned during fitting so a spurious/missing
beat in a breakdown cannot shift every later beat. Uncertain grids leave the cue
unset instead of enabling misleading sync. The estimate remains a fixed tempo.
It writes no audio,
catalog, tags or beat grid. Analysis failures leave manual BPM/tap and Set beat usable.
A newly loaded file invalidates stale analysis responses; manual BPM/cue edits are not
overwritten by an in-flight analysis. Manual BPM entry, Tap and half/double buttons
mark BPM as manual (`bpmIsEstimate = false`); later analysis preserves that exact BPM
and checks/fits only its cue. BPM readouts show two decimals, while sync uses the full
precision. Beat cues and BPM corrections are session-only.

Sync B → A applies A’s effective BPM to B and seeks B to the nearest matching beat
phase, starting it at a host timestamp 120 ms ahead when A is playing. The master’s
position is projected to that exact timestamp, including pending scheduled starts;
the playback clock stays stationary until its scheduled host start. With A paused,
it aligns B without starting either deck. Play both schedules the two decks at one
host timestamp. Sync is a one-time alignment, not a continuously locked or downbeat/
phrase-aware grid. BPM and the estimated cue can be wrong, including half/double tempo;
fixed-tempo alignment can drift on live drums. Check by ear, adjust BPM, Set beat on a
kick, nudge or re-sync. Pitch follows tempo; no key lock, headphone cue routing, DJ
controller integration, recording or export was added.

Leaving Signal pauses B so a hidden deck cannot keep playing; A continues and retains
its EQ, rate and level. Returning preserves both loaded tracks within the session.
Tracks & imports opens the existing workspace in a sheet, and New import opens it at
the import form. No download starts merely by opening the sheet or switching skins.

## Source map and callers

| File | Responsibility |
| --- | --- |
| `native/Crate.swift` | SwiftUI window, state polling, import controls, queue/folder/library views, label actions, process launch and skin selection |
| `native/SoulseekAccount.swift` | Codable account and native Security.framework Keychain storage |
| `native/CrateSkin.swift` | Skin enum, Silverwave panels, emblem and decorative display |
| `native/BoomboxSkin.swift` | Blue/red boombox vector artwork and central playback/fader controls |
| `native/CratePlayer.swift` | Local AVFoundation playback engine, mute, spectrum tap and shared seek/speed/volume strip |
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
| `tests/check_crate_skin.swift` | Silverwave emblem and blue/red boombox render checks |
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

Source history is in the private repository https://github.com/tikkbene-commits/LiSTd.
The baseline precedes the 1.4.1 stability changes. Music, personal root playlists,
credentials/config, state, environments, generated app bundles and releases are
excluded from Git. The supplied sample tracklist remains a source fixture.

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

- Deferred UI bug, user-reported 2026-11-18: clicking sliders briefly makes them
  animate/jump down from the top of the screen for about a second. Record this for
  the next project session; the user explicitly requested no investigation or fix
  now. Affected sliders/skins and the cause have not been verified.
- Genre is a file tag or manual label. Missing/conflicting genre tags remain `Unsorted`.
  No trained audio genre/mood model is installed.
- Librosa estimates tempo from three 24-second excerpts, with agreement/pulse checks;
  valid BPM tags take priority. A simple bass-amplitude fallback exists. Half/double
  tempo and other beat errors remain possible. Vibe is a broad tempo/crest-factor
  heuristic, not a guaranteed musical judgment or a DJ beat grid.
- The YouTube URL is a source link for the provided list. The app does not recognize
  tracks by fingerprinting the set or download the YouTube mix itself.
- Share only `release/LiSTd-Mac.zip`, not the development root app or MUSIC
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
swiftc -parse-as-library native/CrateSkin.swift native/CratePlayer.swift native/BoomboxSkin.swift native/AudioSpectrum.swift tests/check_crate_skin.swift -o .music-sorter/build/check-skin
.music-sorter/build/check-skin

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
