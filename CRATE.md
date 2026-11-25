# LiStD

For development in a new chat, start with `AGENTS.md` and `APP_CONTEXT.md`.
`CHANGELOG.md` records changes and their validation; keep both handoff files current
after editing the app.

Double-click **LiStD.app** in this MUSIC folder. This is a native macOS window,
not a browser or a terminal skin. This development build stays alongside
`crate_backend.py` and `music_sorter.py` and uses this folder as its workspace.
Future sharing builds use **release/LiStD-Mac.zip**. This source update has not
replaced the existing public 1.4.1 archive; see
[SHARING.md](SHARING.md). The sharing build is self-contained and uses each user's
`~/Music/LiSTd` folder. It supports Intel and Apple Silicon Macs with macOS 14+;
no recipient Python, Homebrew or Rosetta installation is needed.

## Sign in to Soulseek

On first launch, enter your Soulseek username and password. The account button in
the toolbar is available in every skin for changing the account or signing out.
LiStD verifies sign-in using a print-only search, then saves the account in macOS
Keychain. After replacing an ad-hoc build, macOS may need permission to read the
saved entry. Choose **Unlock saved account** and complete macOS’s prompt. Startup
never waits on that permission, and your saved entry is preserved.
It does not download music during sign-in. Playback works without login.
Close other Soulseek clients using that account before signing in or importing.

## Skins

Use the **Skin** menu in the toolbar to switch between **Amped · Blue / Red**,
**Silverwave**, **LiStD · Original**, **Signal · Dual Deck**, **Cyber · Lilac** and **Limehead · Mix (alpha)**. Amped recreates the supplied boombox reference:
blue shell, red lettering, chrome controls and black speaker grilles. It is the initial
skin for new preferences; your choice is saved. Skin changes preserve playback and
imports. All skins use your supplied ear icon in Finder and the Dock. The speaker
grilles preserve the reference's mesh appearance; the title display contains a live
LED spectrum. Silverwave's purple display remains decorative.

The player fills most of the window by default. **Player size** changes the complete
boombox's size; **Fill window** restores 100%. Size and drawer visibility are saved.
Use **Tracks & imports** (or click the LiStD logo) to expand the workspace. **New import**
opens it automatically. Drag the vertical divider to resize the collection and the
horizontal divider to resize the player and import drawer. Each area scrolls as
needed; collapsing the drawer keeps playback, selection and import progress.
Drawer transitions respect macOS Reduce Motion.

## Listen and change pitch / speed

Use the collection or accepted import row’s **A / B** loading buttons, then the
deck’s Play button. **Play in LiStD** is also in the collection row’s context menu. The player's folder button opens
a local audio file directly, without importing or moving it.

Use play/pause, stop, the progress slider to seek and the volume slider. **Pitch / speed**
ranges from 0.5× to 1.5×: slowing down lowers pitch; speeding up raises it, like a
turntable. The readout shows percentage and semitone changes. **Reset** returns to
the original speed and pitch. Amped also has back/forward 10-second buttons and a
vertical pitch fader in the center of the boombox (up = faster/higher).

The top switches mute, minimize and close the window. The side controls lower/raise
volume. Clicking the left/right speaker seeks backward/forward 10 seconds; the vents
lower/raise pitch by 1%. Clicking the shell plays/pauses, or opens audio when empty.
Every control has a tooltip and an accessibility label.

### Limehead · Mix (alpha)

Limehead recreates a supplied green “head” media player, and is an **alpha** skin: it
works, but its look and controls may still change. It plays **two decks at once**, so the
library and import lists show **A** / **B** (or **Load A** / **Load B**) buttons.

* **Left wing — mixer.** *Crossfade* blends the decks (all the way left is only deck A,
  the middle plays both, all the way right is only deck B); *Master* sets the overall
  level. Under each *DECK* label, five faders: **V** level, **P** pitch (±8%, which also
  changes tempo), and **L / M / H** low/mid/high cut (top is flat, bottom cuts 24 dB).
  The small purple button starts or pauses that deck; **reset** returns the crossfader to
  the centre, levels to 85%, pitch to 1.00 and EQ to flat. Faders also take the arrow keys.
* **Right wing — playlist.** Lists the collection pane’s current view, filter and sort.
  Click a row to load it, paused, into the deck named in the box at the top; click that
  box to switch between deck A and B.
* **Head.** The gold ◀ and blue ▶ buttons in the title bar choose which deck the screen,
  title, seek groove and transport (|◀◀ ‖/▶ ■ ▶▶|) control; the ✕ beside them opens an
  audio file into that deck. The asterisk turns the oscilloscope screen on or off. The
  bars icon and page icon (and the ✕ / tab on each wing) hide or show the mixer and
  playlist; the icon under the seek groove opens **Tracks & imports**.

The screen draws jagged white traces from the focused deck’s live audio over red trails.
There is no shared playback strip, because its volume slider would fight the mixer.

### Cyber · Lilac

Cyber recreates the supplied lilac media-player design. The black screen shows the
live spectrum with the title, artist and play status; the eye button beside it turns
the spectrum on or off, and the small ◀ ▶ arrows lower/raise speed by 1%. Click the
tri-colour mark to reset speed. Drag the bronze knob under the screen to seek. Drag the
ball along the pink ring to set volume; click **+** or **–** to step it by 5%, or the
speaker mark to mute. The title field scrolls long names; click the time field to switch
between elapsed and remaining time. The document button opens **Tracks & imports**, the
folder button opens an audio file, and _ / X minimize or close the window.

On the transport ring, |◀◀ and ▶▶| load the previous or next track from the
collection pane, in its current view, filter and sort, and stop at the ends. Previous
restarts the song once it has played for more than 3 seconds. A playing track keeps
playing when you step; a paused one loads paused. ◀◀ / ▶▶ jump 10 seconds, ‖ pauses,
■ stops, and ▶ plays. With nothing loaded, ▶ starts the first track in the collection
view, or asks for a file when the view is empty. The ball and seek knob also respond
to the arrow keys when focused.

During playback, real audio-frequency bars appear behind the title, in green, yellow
and red with a faint reflection like the supplied reference. Click the display to hide
or show them. Pausing or stopping clears them. This is a visual spectrum analyzer,
not a tone-adjusting equalizer. It measures the signal before listening volume/mute.

Playback is local and leaves the source file unchanged. There is no key lock,
automatic next-track queue or export. Supported audio formats depend on macOS
AVFoundation; an unreadable file shows a playback error.

## Signal · Dual Deck

Choose **Skin → Signal · Dual Deck** for the dark technical mixer. The
decks and mixer occupy a resizable pane beside the full-height collection.
The optional import drawer stays usable below the mixer. A/B buttons load tracks without leaving the list.
The right side scrolls independently when the window is short. The
waveforms use a 60 fps animation timeline and default to a shared 60-second time scale,
with a full-track overview beneath each. **View** zooms both decks from 12 to 120 seconds
and remembers your choice. Waveforms are shorter and use a filled envelope to reduce
scrolling shimmer. Reduce Motion keeps the waveform stationary in pages.
Click a waveform to seek. Use **A** / **B** beside a library track, or a deck’s **Open
file** button, to load a track paused. You can also drag a collection row or a single
audio file from Finder onto either deck’s waveform to load it paused.
**Play both** starts the decks together;
each deck also has independent play/pause, stop, level and mute.

Beat analysis runs locally when a deck loads and refines the initial tempo over many
beats to avoid drift from coarse BPM estimates. Uncertain grids ask for a manual
cue. **Sync A to B** changes A to match B’s effective tempo and beat phase;
**Sync B to A** changes B to match A. The second deck stays unchanged. If that
deck is playing, the changed deck starts aligned; otherwise it aligns paused. Sync is a one-time match: use it again after changing tempo or seeking.
Check the estimated beats by ear. Correct **BPM** (or **Tap** it), click a kick in the
waveform and use **Set beat** to anchor the grid. **½ / ×2** correct half/double BPM
estimates. BPM displays two decimals; manual values are preserved during analysis.
The **−20 ms / +20 ms** buttons nudge
alignment. These corrections last for the current session. The speed readout button
returns a deck to 1×; tempo changes also change pitch.

Each mixer independently cuts **BASS**, **MID** and **HIGH** from 0 to −24 dB. **Reset EQ**
restores a flat response. Both decks start at 50% level for mixing headroom; raising
both levels can clip the combined output. Leaving Signal pauses deck B; deck A keeps
its current playback, EQ and level across skins. **Tracks & imports** opens the existing
workspace. Loading audio and analyzing beats never downloads or changes your files.

Beat analysis uses an excerpt from the first 90 seconds and can miss the pulse or
choose half/double tempo. Sync uses a fixed BPM, without downbeat/phrase detection
or a continuous tempo lock. It can drift on live drums; correct it by listening and
re-syncing. There is no headphone cue routing, key lock or recording/export.

## Browse your collection

**All tracks** is the default. Use **View** to browse Download folder, Import /
tracklist, Genre or Artist, then choose a group. **Sort** offers Track title, Artist,
BPM (unknown last) and Most recently added. Search stays within the selected group.
These controls only change the display; they never move or copy music. Folder groups
use current catalog paths; import groups use available history. Missing fields show
Unknown artist, Unsorted or No import record. Older files use import/file creation
time as an approximate added date.

## Drop a tracklist

Drop a UTF-8 CSV or text file into the import area, choose a file, or paste text.
With **Download and organize automatically** enabled, dropping a file starts the
workflow. Disable it to import and inspect the rows first. CSV headers determine
artist and title automatically. For text, choose **Title - Artist** or **Artist - Title**
before importing. Title-first is selected initially to match the supplied set.

Examples:

```text
0:00:00 Easy - Freedom Satellite
0:04:31 Smoke - Vienna D.C.
```

```csv
Artist,Title,Length
Freedom Satellite,Easy,271
```

CSV artist, title, duration and extra fields are preserved. SetStart values and
text timestamps are set cue positions, never assumed to be full track lengths.
The default quality is 320 kbps or lossless; lower thresholds are selectable.
Imports queue within the running app. Stop cancels the current import. Closing
the last window quits the app and requests cancellation of running imports.
Interrupted imports remain available for Retry unfinished on reopening.

## What happens automatically

1. Reuse a matching, qualifying file already in the local catalog or `juan music`.
   Existing collection files are never moved by the import workflow.
2. Start one private Sockseek session on a loopback port for the import. Searches
   run per CSV row, with up to five rows searching/downloading at once. Sockseek's
   search limiter still applies, so very long imports pause briefly to avoid a
   Soulseek search ban.
3. Inspect search results for artist/title evidence and exclude obvious alternate
   versions unless requested in the original title. Download an exact peer file;
   if it cannot complete, try up to two other exact peers.
4. Decode the full local file to check for audio errors, and independently inspect
   its codec, duration, tags and measured audio packet
   bitrate. Conflicting tags or insufficient bitrate stay in staging for review.
   Full-track identity is not established by audio fingerprinting in this version.
5. Use the existing organizer to move each accepted track into
   `downloads/organized/<genre>/<vibe>/`. No audio copy is created. Sockseek receives
   the new path using its supported completion/index-update mechanism.
6. Show the result per track, plus a New arrivals view with folder names, new track
   counts and Open folder buttons. The row menu can play or reveal a file, or edit
   its genre/vibe and move it into the corrected folder.

The downloaded source files remain untouched apart from their paths. Incomplete
transfers are never counted as tracks. Only incomplete remnants for the finished
import are removed. Files awaiting verification live under `downloads/.incoming/`;
the ordinary organizer excludes that hidden staging area.

## Review a downloaded file

Click an orange **Review** badge (or **… → Review file**) to see the file’s tags,
filename, codec, duration and reason for rejection. **Listen to file** previews it;
**Show in Finder** reveals the staged file. Correct the expected artist/title if the
tracklist was wrong, then **Save & recheck file**. This reruns all identity, duration,
bitrate and decode checks; it does not bypass quality requirements or edit file tags.

If an entire import has artist and title reversed, use **Swap artist / title & recheck**
before any tracks have been accepted. It corrects the search fields and checks the
already-downloaded review files locally. Original source text/CSV fields are retained.
Neither review action downloads anything. **Retry unfinished** starts a new search
for the remaining tracks using the corrected order.

## Deep search missing tracks

The normal search runs first. For a Not found / Stopped row, choose **Deep search**.
Use **Import actions → Deep search all missing** for the selected import. Accepted
tracks and staged files awaiting review are preserved. **Stop** cancels the current
search; each track shows query progress and its result.

Deep search tries up to six sequential queries: normalized artist/title, reversed
order, title only, supplied album/release/catalog details, and a query omitting one
long word for small spelling differences. Original CSV fields, duration and mix cue
positions remain intact. Format and bitrate requirements stay selected.

Exact evidence can continue to download and full verification. Uncertain results
expand under **candidates need review**, showing the filename/path, peer and reason.
**Download & verify this candidate** requests a transfer; it still requires identity,
duration, measured quality and complete decode before filing. A spelling difference
or conflicting tags can therefore leave the file staged for Review file. Unrequested
alternate versions are rejected. Deep search does not fingerprint audio and cannot
guarantee that a peer has the requested recording.

## Genre and vibe limits

Genre comes from the file's genre tag or your manual correction. Missing or
ambiguous genre tags remain **Unsorted**. The app does not invent a genre from an
artist name or a peer's folder name. Use the row menu's Edit genre & vibe to fix it.

Tempo estimation uses three 24-second excerpts and the local
[librosa spectral-onset tempo estimator](https://librosa.org/doc/0.11.0/generated/librosa.feature.tempo.html).
The app requires agreement between excerpts and a usable repeating pulse.
Valid BPM tags take priority. The command-line organizer can fall back to a
simple bass-amplitude estimator if the optional audio environment is unavailable.
Vibes remain broad tempo/crest-factor estimates: Warm-Up, Groove,
Driving, Peak Time, or Needs Review. They are not trained mood/genre predictions
or calibrated DJ beat grids; tempo can still be half/double the musical beat.

The provided YouTube URL is a source link for the imported tracklist. The app
downloads the listed songs through Soulseek; it does not download the YouTube mix
or perform recognition/fingerprinting on that mix.

## Files and credentials

- `LiStD.app`: universal native window for Intel/Apple Silicon (macOS 14+).
- `native/Crate.swift`: window source.
- `crate_backend.py`: parsing, queue, Sockseek integration, verification and folder results.
- `music_sorter.py`: existing organizer, catalog and reversible move journal.
- `tracklists/YouTube set bNSesW8h94I.csv`: the supplied 15-track list.
- `.music-sorter/crate/jobs/`: durable imports, original tracklists, indexes and local logs.
- `.music-sorter/audio-env/`: isolated audio-analysis environment using librosa 0.11.0.
- `~/Library/Caches/LiSTd/numba/`: compiled analysis kernels, separated by runtime and
  dependency versions. The first analysis after an update can take longer.

The library refreshes every ten seconds while idle, every two seconds during imports,
and immediately when LiStD becomes active or a local action completes.

The app stores its account in macOS Keychain and passes it privately over stdin to
the backend. Sockseek uses a mode-600 temporary config within a mode-700 temporary
directory during sign-in/import; normal completion/failure removes it. A forced kill
or crash can leave that private file until OS cleanup. No password is put in process
arguments or the sharing archive. Global `~/.config/sockseek/sockseek.conf` is never
changed or copied. The CLI retains its existing global-config behavior.
The owned Sockseek daemon listens only on 127.0.0.1 and stops after the import.
Audio analysis is local; artist/title searches are sent to Soulseek.

Do not run the command-line watcher during an import, or another Soulseek client
using the same account. The organizer's catalog lock prevents simultaneous moves.
Keep `.music-sorter/catalog.json`: it contains manual labels and move recovery data.
The existing command-line `undo` commands described in MUSIC_SORTER.md can restore
the most recent moves. Each completed track is one move batch.

## Build and checks

The app is already built. To rebuild after changing its source:

```sh
./build-crate
```

Build a separate self-contained sharing archive with `./package-crate`. It audits
runtime dependencies and runs an offline import/analysis/completion smoke check
under a temporary HOME without Homebrew on PATH. Distribution/signing instructions
are in [SHARING.md](SHARING.md).

This uses the installed Apple command-line tools and, on first setup, installs the
pinned audio dependency from `requirements-crate.txt` in the local environment.
It does not change global Python packages.

Run deterministic checks without making real downloads:

```sh
.music-sorter/audio-env/bin/python -m unittest discover -s tests -v
```

Check the native skin/logo render after visual changes:

```sh
swiftc -parse-as-library native/CrateSkin.swift native/CratePlayer.swift native/BoomboxSkin.swift native/AudioSpectrum.swift native/CyberSkin.swift tests/check_crate_skin.swift -o .music-sorter/build/check-skin
.music-sorter/build/check-skin
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift native/CyberSkin.swift tests/check_cyber_player.swift -o .music-sorter/build/check-cyber-player
.music-sorter/build/check-cyber-player
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift native/CyberSkin.swift native/Collection.swift native/LimeheadSkin.swift native/LimeheadTrace.swift tests/check_limehead.swift -o .music-sorter/build/check-limehead
.music-sorter/build/check-limehead

# Playback checks (muted, generated temporary audio; no downloads).
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift tests/check_crate_player.swift -o .music-sorter/build/check-player
.music-sorter/build/check-player
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift native/TechnicalSkin.swift tests/check_dual_deck.swift -o .music-sorter/build/check-dual-deck
.music-sorter/build/check-dual-deck
swiftc -parse-as-library native/SoulseekAccount.swift tests/check_keychain_startup.swift -o .music-sorter/build/check-keychain-startup
.music-sorter/build/check-keychain-startup
swiftc -parse-as-library native/Collection.swift tests/check_collection.swift -o .music-sorter/build/check-collection
.music-sorter/build/check-collection
swiftc -parse-as-library native/CratePlayer.swift native/AudioSpectrum.swift tests/check_sliders.swift -o .music-sorter/build/check-sliders
.music-sorter/build/check-sliders
swiftc -parse-as-library native/AudioSpectrum.swift tests/check_audio_spectrum.swift -o .music-sorter/build/check-spectrum
.music-sorter/build/check-spectrum
```

Tests use generated audio, temporary folders and fake peer transfers to exercise
parsing, cue/duration separation, bitrate/identity rejection, the real sorter,
collision handling, undo and library preservation. The provided set is also used
for the separate live end-to-end test; its per-track results are visible in the app.
