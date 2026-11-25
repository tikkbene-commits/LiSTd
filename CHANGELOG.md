# LiStD change history

Append dated entries after future app changes. Include what changed, relevant
decisions, validation performed and any checks skipped. Keep this history factual;
the initial entries below summarize retained source, local records and this session,
rather than reconstruct every past chat message.

## 2026-11-25 — Save password checkbox; stay signed in after relaunch

- User request: stop asking for the Soulseek login every time the app opens, and save
  it securely only when the user ticks "Save password".
- Cause: the account was already in Keychain, but the ad-hoc signature's designated
  requirement is a cdhash, which changes on every rebuild. Each rebuilt app was a new
  identity to the entry's access list, so the silent startup read failed and the user
  retyped the password.
- The account sheet has a **Save password** checkbox (`listd.savePassword`, default on).
  Ticked: the account is stored in Keychain (service unchanged). Unticked: the
  account stays in memory for this session only, and any saved entry is removed.
- `SoulseekKeychain.save` now deletes and re-adds the entry, so the build that signed
  in owns it and later launches of that build read it without a prompt.
- When the silent startup read fails and Save password is on, the app asks macOS once
  on a background task (choose Always Allow), instead of requiring a retyped password.
  The window stays usable; the manual Unlock saved account button remains.
- Validation: `./build-crate` rebuilt the app; `tests/check_keychain_startup.swift`
  passed (the non-interactive read returned -25293 immediately and restored the UI
  policy). Not tested: a live sign-in, the macOS prompt, or a relaunch, since those
  need the user at the Mac.

## 2026-11-25 — Limehead merged; README, guide and screenshots; alpha label

- Pull request #6 (Limehead · Mix) was merged into `main` on the user's instruction.
- Limehead is an **alpha** skin: the Skin menu now reads "Limehead · Mix (alpha)"
  (`CrateSkin.title`), and the README, CRATE.md and APP_CONTEXT.md say so. It was not
  labelled before; keep the label until the user says otherwise.
- README: six skins, a Limehead table row, a new `docs/images/limehead.png` with a short
  how-to and an alpha notice, and the preview-regeneration command now lists the files
  Limehead needs. CRATE.md gained a Limehead section and its check command.
- `scripts/render_readme.swift` now also renders Limehead with both example decks playing
  silently (muted, so the screen shows a live oscilloscope trace) and six example
  playlist rows; no account or collection is read. Signal and Amped previews re-rendered
  byte-identical in size to the existing ones.
- Validation: skin and Limehead checks passed; `./build-crate` rebuilt the app. The
  preview was rendered offscreen, not captured from the running app; the rebuilt app was
  not relaunched because an import was running in the open copy.

## 2026-11-25 — Limehead · Mix: traced face, jaw, wings and speakers; old-Windows visualiser

- User feedback: the face looked sad not strict, the visualiser should look like the
  old Windows one, the speakers should face outward, and every line of the face and
  the jaw outline should be copied exactly.
- New `scripts/trace_limehead.py` traces the reference screenshot into
  `native/LimeheadTrace.swift`: full head outline (dome, sides, jaw), 31 green
  brightness layers for head and face (app controls painted out first), the screen
  outline, both wings (stripes and X marks kept) and six speakers (26 grey layers each,
  ellipse rims fitted to the traced edge, rms 0.6 px; tilts 56°/49°/45°). Measurements
  found the reference head centred at x ≈ 464 and ~17 px wider than the hand-drawn one,
  and the screen's top edge at y ≈ 90 under the pill; geometry now uses those values.
  Pill, pill buttons (r 10), panels and the drawer icon were re-measured. Drop shadows
  removed (the reference has none). `LimeArtwork` is `Equatable` so the detailed paths
  redraw only when a wing toggles or the size changes.
- Visualiser rebuilt as an oscilloscope: jagged white traces across and down from raw
  samples (`AudioSpectrum.wave`, new), zooming red trails, centre hot spot; clipped
  out of the pill.
- Validation: `check_limehead` (landmark colours re-checked against the reference
  pixels), spectrum, player, skin and Cyber checks passed; `./build-crate` built both
  architectures. Offscreen renders compared side by side with the reference at 2–4×.
  The rebuilt app was not relaunched: an import was running in the open copy.

## 2026-11-25 — Limehead · Mix skin

- New skin recreating the supplied green head media-player screenshot as vector
  artwork (935 × 498 reference crop, sampled colours, Catmull-Rom head outline,
  soft-shaded face, silver speakers, red glow visualiser driven by the live
  spectrum). The player's own controls were kept in their reference positions.
- Requested change from the reference: the left wing mixes two tracks. Decks A and
  B (the existing `player`/`deckB`) get a constant-power crossfader, master volume,
  and per-deck level, pitch (±8%) and low/mid/high cut faders, plus play buttons
  and a reset. The right wing lists the collection's visible tracks and loads into
  deck A or B. The head's pill arrows pick which deck the head controls.
- `CrateSkin.isDualDeck` (Signal + Limehead) now drives A/B load buttons and
  whether deck B pauses on a skin change; collection stepping takes a deck.
- Validation: new `tests/check_limehead.swift` passed (landmark colours,
  crossfade gains, and real mouse events on transport, focus, playlist, seek,
  crossfader/master, level/pitch/EQ faders, reset, wing hide/show, volume hand-back).
  `./build-crate` built both architectures; existing skin and Cyber control checks
  passed. Python suite not rerun (no backend change). The rebuilt app was not
  launched for a visual inspection of the real window in this session; the
  artwork and live view were compared offscreen against the reference instead.

## 2026-11-23 — Backend review: label fix and small optimisations

- Reviewed `crate_backend.py` for optimisation. Measured on the real library (156
  catalog tracks): snapshot ≈0.08 s; verifying one MP3 ≈0.9 s (probe 0.24 s, packet
  bitrate 0.12 s, full test decode 0.5 s). Soulseek search/transfer time dominates;
  no large backend bottleneck was found.
- Fix: the genre/vibe label command saved jobs taken from `snapshot()`, whose
  display-only statuses (e.g. "File moved or missing" → review) could be written
  back to disk and cause needless re-searches. It now edits the stored jobs.
- Bitrate measurement reads ffprobe packets in compact text instead of JSON
  (output 1.26 MB → 0.46 MB for one track; time unchanged at ≈0.1 s). Unknown
  `N/A` values are skipped.
- An import run lists `juan music` audio once instead of once per row. The catalog
  is still re-read per row so tracks organized earlier in the same run count as
  existing.
- Validation: three new regression tests (label status preserved — fails on the old
  code; supplied library listing; 192 kbps MP3 measured within 8 kbps). Full suite
  with `.music-sorter/audio-env/bin/python`: 40 passed. One baseline run before the
  change had a single failure that did not reproduce in two reruns (flaky; not
  investigated). No Swift change, so no rebuild; app not relaunched.

## 2026-11-21 — Cyber · Lilac end-to-end testing

- Ran the real `CrateView` (real model, backend snapshot and fixture collection)
  offscreen in a throwaway test bundle with its own bundle ID, root = the worktree's
  three generated test tones. Clicks went to the skin's reference coordinates and
  state was read back from rendered pixels with on-device text recognition. 20
  checks passed: Play on an empty deck loads the first collection track; the clock
  advances; next keeps playing; previous within 3 s steps back, after 3 s restarts;
  next stops at the last track; paused stepping stays paused; stop; drawer open and
  close (skin rescales and still plays); play at the 800 × 720 minimum window, at
  45% Player size and at 1600 × 1050; Amped → Cyber round trip keeps the deck. The
  harness is scratch tooling and is not committed (it strips `@main` from a copy of
  `Crate.swift`).
- Fix: at small Player sizes the screen and field text fell to about 3 pt and could
  not be read. Screen title/artist/status and the field text now keep minimum
  legible sizes (9/8/7.5/7 pt).
- `check_cyber_player` now also checks arrow keys on the focused volume ring (+5%)
  and seek knob (+5 s); passed. Skin and collection checks and both-architecture
  `./build-crate` passed again. The rebuilt LiStD.app launched on the Cyber skin,
  stayed running for 8 s and quit with no crash report; the saved skin was restored
  to Original.
- Test-only incident: during harness setup, a titled test window was moved onto the
  visible screen by macOS for a few seconds before it was made transparent and
  pinned offscreen. Harness crash reports in DiagnosticReports are from early
  harness runs (`fatalError` timeouts and an invalid key), not from LiStD.
- Final rerun: 21 checks passed, including an assertion that the test window was
  never visible on any screen (transparent and pinned offscreen from creation). The
  crash-report count stayed at the three early harness reports, so neither the final
  harness nor the rebuilt LiStD.app produced any.
- Still not done: clicking in the visible app window (no Screen Recording or
  Accessibility permission for this session); the user chose to do that click-through
  themselves. Pushing the branch was blocked by a permission check.

## 2026-11-21 — Cyber · Lilac skin

- Added **Cyber · Lilac** (`native/CyberSkin.swift`), a fifth skin recreating the
  user-supplied lilac media-player image. Outlines were traced from the image's own
  545 × 448 pixels (region spans per row) and colours sampled from it; the artwork
  is vector, so it stays sharp at any Player size. The reference's brand text was
  replaced with a LiStD wordmark at the user's request.
- Every element works: live spectrum screen (eye toggles it), seek knob, volume
  ball on the pink ring with +/− marks and speaker mute, speed arrows and reset mark,
  scrolling title field, elapsed/remaining time field, Tracks & imports and open-file
  buttons, minimize/close, and a seven-control transport ring. Previous/next step
  through the collection pane's visible order (new `CollectionBrowser.neighbour`);
  decisions on prev/next, screen content, branding and control mapping were
  confirmed with the user before implementation.
- Cyber uses the light appearance and Amped's taller player minimum (shared via
  `CrateSkin.isArtwork`); the Player size row is now one shared view for both.
- Validation: new `tests/check_cyber_player.swift` sends real mouse clicks/drags to
  every Cyber control in an offscreen window (muted player, generated silence) and
  passed; `check_crate_skin` gained Cyber landmark-colour, transparency and
  volume-ring round-trip checks and passed; `check_collection` gained stepping checks
  and passed. A side-by-side/overlay comparison with the reference was used to tune
  the ring path and shading (ring within about 5 px; horn shading within a few
  levels). Player, dual-deck, slider, spectrum and no-UI Keychain checks passed; the
  Python suite passed (37 tests). Both architectures built with `./build-crate` in
  the worktree, using generated test tones there, never the real collection.
- Not verified: the rebuilt app window could not be screenshotted or clicked from
  this session (no Screen Recording permission or desktop control), so the skin was
  checked through offscreen renders and the hosted-control test, not in the visible
  app window. No downloads were started.

## 2026-11-21 — Final rebuilt-binary verification

- Confirmed the final rebuilt LiStD binary refreshes the real collection after
  macOS file access approval: all 155 tracks and the existing import history are
  present. Signal's collection A/B buttons remain visible at the narrow window
  size, and the mixer/import divider changes the real layout independently.
- Corrected AppKit's final mouse-tracking value restoration by sending the snapped
  slider value after tracking returns. Actual waveform-zoom clicking now keeps
  the native thumb/accessibility value and the displayed value equal; arrow-key
  stepping also passed. Left Signal selected with its 36-second waveform window.
- The complete prescribed Python suite passed (37 tests), as did focused native
  slider, collection, reverse-sync, playback, spectrum, skin/fader and no-UI Keychain
  checks. Both architectures rebuilt. Offline deep-search tests used simulated
  Soulseek results and generated audio; no live downloads were started.
- Final catalog and all three original import-record hashes match the pre-UI
  manifest; the temporary progress fixture is gone. Diff whitespace checks passed.
  Strict bundle-signature verification passed after removing Desktop-added
  FinderInfo metadata, without re-signing or rebuilding again.
- The initial transient jump was not captured frame by frame, and the UI driver's
  final custom vertical-fader drag failed; its hosted focus/accessibility regression
  passed. Physical Intel/macOS 14 and a newly packaged standalone ZIP were not
  tested. The saved account remains available through Unlock saved account; no
  credentials were changed. No release was published or replaced.

## 2026-11-20 — Final UI access and control follow-up

- After the user approved macOS access, confirmed the actual app displayed all 155
  existing collection tracks and original import history. Inspected final Amped,
  Silverwave and Original layouts at the narrow window size; artwork/headers now
  remain inside their panes, with full-size native transport available.
- Made the collection title column follow its pane width explicitly: native table
  autosizing had retained an oversized column after shrinking and clipped A/B.
  Selection, row file-URL providers and context menus are retained. Also applied the
  measured top inset consistently to the player and removed the lower drawer's
  inherited window-top inset.
- Reused TrackingSlider for the custom vertical pitch fader. Its hosted native
  regression verifies the chrome cell, first-responder acceptance and actual
  accessibility increment/decrement updating the binding. Native skin/fader checks
  passed, and both app architectures rebuilt successfully. Player-size clicking,
  keyboard stepping and Fill window were verified in the app. The UI driver's final
  coordinate drag attempt returned noWindowsAvailable, so it is not claimed as a
  successful final vertical-fader drag test.
- Restored Signal. The final rebuilt app may need renewed macOS Desktop approval;
  its latest snapshot is waiting on file access. Earlier access approval restored
  the real data without any recovery or catalog changes. No live downloads, account
  changes, public release work or protected-library moves were performed.

## 2026-11-20 — LiStD 1.5 collection, mixer and import workspace

- Renamed current app branding, native artwork, bundle/display/executable and future
  package output to **LiStD**, exactly. Kept bundle/Keychain identifiers, preferences,
  standalone marker, per-user data/cache roots and catalog/import paths stable.
  Regenerated the two README player previews with generated local audio. Existing
  public release assets, repository name and remote state were not changed.
- Replaced horizontal SwiftUI sliders with one shared native NSSlider implementation:
  native tracking coordinates, current bindings, original step sizes, explicit
  keyboard focus/arrows and accessibility increments/decrements. Snapped the native
  thumb/AX value together with the binding. Removed player-size-wide layout animation;
  retained the native vertical pitch fader's actual dimensions and all skin artwork.
  The initial capture did not catch the original transient upper-left jump; its
  precise SwiftUI internal cause remains an inference. Native clicking/dragging
  remained stationary during the observed checks.
- Added **Sync A to B** beside **Sync B to A**, with explicit help describing the
  changed deck. Both call the existing guarded tempo/phase implementation. Generalized
  the end-of-track error text and added paused/running reverse-sync checks that
  assert B's settings remain unchanged.
- Collection defaults to All tracks, with folder, import/tracklist, genre and artist
  views, scoped search and title/artist/BPM/newest sorting. Preserved A/B loading,
  selection, file-URL providers, Finder reveal, playback and explicit label editing.
  Display metadata comes from current catalog paths/import records; browsing never
  organizes audio. New catalog entries record added time, with documented read-only
  import/file-date fallbacks for old catalogs. Duplicate import names get short IDs.
- Replaced Signal's modal Tracks & imports workspace and fixed column ratios with
  common native horizontal/vertical split panes across all four skins. Collection,
  player and the collapsible import drawer remain visible together, with draggable
  dividers, independent scrolling, responsive control grids and wrapping import rows.
  New import opens the drawer directly. Root-owned players/model/selection preserve
  playback and queue state during changes. Amped clips its artwork, has a sensible
  player minimum and keeps full-size native transport controls available at reduced
  artwork sizes. Silverwave and Original retain their styling and player controls.
- Added opt-in individual/batch deep search through the existing download lock,
  owned loopback daemon, sequential queue, cancel file and verification-first hook.
  At most six normalized/reordered/title/release/catalog/omitted-word queries run
  sequentially per missing row. Original fields, full duration and cue separation
  stay intact. Results/inspection/log sizes and transfer attempts are bounded.
  Accepted tracks/staged review files are excluded. Exact evidence can proceed;
  spelling variants/conflicting or unexplained metadata are shown as review
  candidates, with explicit download-and-verify actions. Unrequested version words
  and supplied-duration conflicts are excluded. Codec, packet bitrate, full decode
  and local identity checks still gate organizing. No audio fingerprinting was added.
- Found a real restart hang after ad-hoc signing: a process sample showed the main
  thread waiting in SecItemCopyMatching for Keychain authorization. Startup now
  suppresses legacy login-Keychain authentication UI and exposes Unlock saved account;
  the explicit interactive read runs off the main thread. Existing credentials are
  neither deleted nor migrated. Modern no-UI flags did not prevent the wait for this
  legacy store, so the compatibility guard uses deprecated SecKeychain UI-policy
  APIs and restores the prior process policy. The noninteractive check returned
  immediately with authorization status -25293 and the final window opened.
- Automated validation: all 37 Python tests passed in the prescribed isolated audio
  environment; new tests cover matching/version/typo safety, bounded query selection,
  CSV preservation, cancellation, missing-only retries, candidate selection guards,
  deep local verification and read-only collection metadata. Native player, reverse
  dual-deck, actual rendered pulse/EQ, spectrum, collection and slider checks passed;
  Silverwave/Amped render checks passed. An additional generated-WAV end-to-end test
  used the actual mock Sockseek daemon/CLI, fallback CSV, exact transfer, completion
  hook, verification and real sorter; the mock source hash stayed unchanged.
- Graphical validation: rebuilt/restarted and observed LiStD branding, default All
  tracks, all browse/sort options, scoped search, two local tracks loaded through A/B,
  both sync actions, native slider clicking/dragging, EQ/level controls after resizing,
  and waveform zoom keyboard focus/steps. Dragged both dividers and checked the
  1280-point and 800-point window layouts. Playback continued through drawer changes.
  A temporary offline job showed changing progress with the drawer resized/closed/
  reopened while local playback and selection persisted; the exact fixture was
  removed afterward. All original catalog/job JSON hashes remained unchanged.
- Build validation: both arm64/x86_64 slices built for macOS 14+. Strict codesign
  verification passed after removing the generated bundle's FinderInfo attribute;
  Desktop sync can restore it, as in prior builds. Intermediate builds invalidated by
  in-flight source edits were rebuilt. The initial slider unit fixture needed an
  NSApplication instance for target/action dispatch; the corrected check passed.
- No live downloads, global account/config edits, protected-library moves, push,
  publication, release replacement or standalone package rebuild occurred. A final
  renamed-app backend launch waited in Python file-open during startup; macOS file
  access approval is pending while the CLI snapshot confirms the original 155-track /
  three-import workspace. System permission dialogs require the user's action. The native inspection
  service subsequently returned cgWindowNotFound on the last restart; the final
  safe-area/minimum-height adjustment compiled but its visual recheck is pending.
  Physical Intel/macOS 14 and external-device testing remain outstanding.

## 2026-11-19 — LiSTd 1.4.1 stability, resource use and GitHub history

- Reproduced the reported Python SIGSEGV in librosa beat tracking with the app's
  existing compiled cache; the same generated-audio tests passed with a fresh cache
  and on reuse. Isolated compiled caches by executable, Python, CPU architecture
  and numerical dependency versions, and moved the default outside the synced Desktop.
  Kept the beat estimator and its accuracy checks. Added cold/warm subprocess coverage
  and package checks so testing uses separate backend launches, as the GUI does.
- Replaced the development environment's inherited user/system packages with an
  isolated venv and pinned NumPy/Numba/llvmlite alongside librosa. Retained the old
  environment for rollback. New builds also create isolated environments; frozen
  builds explicitly include dependency metadata used to separate caches.
- Reused spectral onset computation within deck analysis. Cancelled obsolete waveform
  readers, including repeated loads of the same file. Idle snapshot polling changes
  from two to ten seconds (80% fewer launches); active imports retain two seconds,
  app activation/local actions refresh immediately. Avoided republishing unchanged
  library/job arrays. All skins, analysis precision and playback controls remain.
- Fixed interrupted imports without a positive process ID appearing to run forever.
- Created the private tikkbene-commits/LiSTd GitHub repository with a source baseline
  before fixes. Excluded music, personal playlists, state, config/credentials,
  environments, generated app bundles and releases.
- Validation: all 30 Python tests passed in the isolated environment with the old
  app-cache parent explicitly supplied (the new runtime partition avoided the
  reproducible crash). Separate cold/warm backend launches passed; deck analysis
  computes onset strength once. Pip dependency validation passed. Native player,
  dual-deck, spectrum and Silverwave/boombox render suites passed on this Mac.
  Built both native architectures. Observed three snapshot processes in 24 idle
  seconds. A strict root-app signature check initially failed when Desktop sync
  restored FinderInfo; removing that generated-bundle attribute and resigning passed.
- Graphical validation: restarted the rebuilt app, loaded Black Russian into A
  and Blah Blah into B through the local file pickers, and observed both analyses
  complete with fitted cues and enabled sync. The first native inspection attempt
  timed out; a later attempt succeeded. CLI analyses of the same two files also
  passed and their SHA-256 hashes were unchanged. Catalog and job JSON hashes were
  unchanged after GUI analysis; the existing 147-track library remains intact.
- A final concurrency check reproduced SIGSEGV with the original NumPy 2.0.2
  runtime despite cache isolation. Kept the NumPy 1.26.4 pin: concurrent cold/warm
  analysis of both real tracks and repeated GUI analysis passed. Added concurrent
  generated-audio subprocess regression coverage; all 30 tests passed again in
  30.49 seconds. An attempted smaller NumPy 2 package rebuild was stopped and is
  not the delivery artifact. The stable archive is larger (300,186,557 bytes);
  reduced background launches/work are the optimization, not archive size.
- The stable universal 1.4.1 ZIP passed both architecture dependency/minimum-OS
  audits and relocated/read-only clean-HOME sandbox pipelines: cold/warm analysis,
  mock daemon/transfer/frozen callback, verification, sorting, relabel/index update
  and state reload. The final ZIP passed CRC, embedded source/version comparison
  and strict deep codesign verification after extraction. SHA-256 is recorded in
  STANDALONE_QA.md. The source baseline and final version have Git tags.
- No new live downloads, global
  Soulseek configuration changes or protected collection moves were performed.
  External audio devices, another physical Mac and notarization were not checked.

## 2026-11-18 — LiSTd, modular player, live spectrum and motion

- Renamed the app bundle/executable, window, menus and visible branding to LiSTd.
  Kept the existing bundle identifier, preference namespace, backend filenames and
  catalog/import paths so saved data survives. Archived the previous app under
  `.music-sorter/build/before-listd/Crate.app`; the normal app is now `LiSTd.app`.
- Amped now fills most of the window by default. Added a saved 45–100% Player size
  slider, Fill window reset and expandable Tracks & imports drawer. New import and
  the LiSTd logo open the workspace. Existing skins and import workflows remain.
- Made the top mute/minimize/close switches, side volume controls, speaker seek
  areas, pitch vents, logo and LCD functional, alongside the central transport and
  fader. The shell plays/pauses or opens audio when empty. Added tooltips/labels.
- Added a real 32-band spectrum behind the title, using a post-varispeed audio tap,
  a Hann-windowed Accelerate DFT and green/yellow/orange/red LED bars with reflection.
  The LCD toggles it; pause/stop blank it. It analyzes the playing signal before
  output volume/mute. There are no random/demo bars or tone-adjusting EQ controls.
- Added spring press feedback, surface highlights, title fades and animated drawer
  and size transitions. Motion respects macOS Reduce Motion. Rendered the artwork
  at its final size to avoid enlarging a low-resolution canvas; gave the native
  fader its real dimensions for calibrated tracking and a matching chrome thumb.
- Validation: all 20 Python tests passed. Native spectrum tests passed for silence,
  220/1000/4000 Hz, a silent left/loud right channel, amplitude response, bounds and
  LED rendering. Native player checks passed, including the real tap, frequency-band
  shifts at 0.5×/1.5×, mute, seeking, completion/replay and source-byte preservation.
  Silverwave and blue/red artwork render checks passed. Builds completed successfully.
  A temporary compile using the older DFT API warned about deprecation; the final
  implementation uses DiscreteFourierTransform and compiles without that warning.
  The existing stereo-WAV fixture still emits its harmless AVFoundation setting warning.
- Checked the running app's large layout, live bars during local FLAC playback,
  player-size/drawer persistence after restart, spectrum toggle, volume/pitch/seek
  controls and native fader dragging. No live downloads, scans, catalog moves or
  credential/configuration changes were performed.
  Final checks confirmed proportional full-size fader tracking (a partial drag
  produced 1.28×), reset to 1×, working minimize/restore and close from the skin,
  and reopening with the player at 100% and the workspace drawer closed.
- Not checked: external audio-device switching, all supported codecs, a new live
  import or formal frame-time benchmarking. Reduce Motion guards were reviewed in
  source; the system accessibility preference was not changed for a separate run.

## 2026-11-18 — Ear icon, Amped boombox and internal playback

- Added the supplied `EarIcon.icns` as a durable source asset and the Finder/Dock
  icon for every skin. The bundle icon matches the supplied file's SHA-256.
- Added Amped · Blue / Red: native vector artwork at the reference's proportions,
  with the green body changed to blue, red Amped lettering, chrome rims/controls,
  mesh speakers and a working track/time/speed display. Kept Silverwave and Original.
- Added internal AVFoundation playback from Library, accepted import rows and an
  Open audio file button. Includes play/pause, stop, seeking, volume, ±10-second
  boombox transport and linked pitch/speed from 0.5× to 1.5× with a reset/readout.
  The center fader and shared slider control the same player across skin changes.
- Playback reads files without changing their bytes, tags, locations or catalog.
  No backend download/verification rules changed; no live downloads were started.
- Validation: all 20 Python tests passed. Native muted generated-audio checks passed
  for playback timing at 1×/0.5×/1.5×, pause/resume, seek bounds, end/replay, stop,
  switching sample rates/channels, invalid paths and unchanged source bytes.
  Silverwave and blue/red boombox render checks passed, including no green pixels.
  Visually inspected Amped and Silverwave; checked Original's retained controls.
  Played an existing MP3 in the real app at low volume, sought to 1:00, changed speed
  to 1.18×/0.85×, paused and switched skins with the player state retained.
  Verified the final native vertical fader by dragging up to 1.5× and down to 0.5×,
  then reset to 1×. Rechecked Library playback in the final build and left it paused.
- Build/signing: rebuilt the local app and restarted it. Strict signature verification
  initially failed when the synced Desktop restored `com.apple.FinderInfo`; clearing
  that generated-bundle attribute allowed verification to pass. One intermediate
  compile was invalidated by an artwork edit during compilation and was rerun.
  No security settings were changed. Native stereo-WAV fixture creation emits an
  AVFoundation non-interleaved-setting warning but all playback assertions pass.
- Not checked: every macOS-supported codec, external audio-device changes or a new
  live import. Artwork is a vector recreation of the supplied small reference, not
  the original skin asset or an audio visualizer.

## 2026-11-18 — Persistent project handoff

- Added `APP_CONTEXT.md` with architecture, source/caller map, user preferences,
  state locations, build/test commands, known limits and the current sample-import
  snapshot. Included the Silverwave work present in the current source.
- Added a read-first section to `AGENTS.md` requiring future app edits to maintain
  the handoff and append their changes/validation here.
- Validation: inspected current source, build script, usage docs and saved test log;
  confirmed the retained 15-track import has 15 ready rows with existing files.
  Documentation references and command/file paths were checked.
- No application behavior, audio files or credentials changed. No rebuild, test-suite
  run, audio analysis or live downloads were needed for this documentation edit.

## 2026-11-18 — Retained app changes at handoff

- Built the local command-line organizer with incremental analysis, genre/vibe/BPM
  filtering, manual labels, preview/apply sorting, watch mode and reversible moves.
- Added the native Crate window with file/text import, automatic Sockseek downloads,
  a durable per-track queue, quality/identity checks, library search and New arrivals.
- Replaced per-track Sockseek reconnections with one loopback-only session per import
  after connection errors in the first live test. Added local librosa tempo analysis,
  original-version filtering, alternate-peer retry and full-file decoding checks.
- Renamed automatic vibe folders to Warm-Up, Groove, Driving, Peak Time and Needs
  Review. Migrated the supplied set's folders and app-owned indexes without audio
  copies, preserving manual overrides and the original collection.
- Current files also include the selectable Silverwave / Crate · Original skins,
  saved skin preference, matching Dock icons, Silverwave Finder icon and a native
  emblem-render check. See `native/CrateSkin.swift` and `CRATE.md`.
- Retained validation: the 15 supplied tracks completed the live import and measured
  quality/full-decode checks; the Python log records 20 passing tests. The handoff
  verified the files still exist, but did not repeat those historical checks or claim
  to have rerun the skin render check.

## 2026-11-18 — Signal dark dual-deck skin and 60 fps waveforms

- Added Signal · Dual Deck alongside Amped, Silverwave and Original. Uses near-black
  panels, thin dividers, monospaced readouts and stacked green waveforms inspired by
  the supplied WavePad reference. Library A/B buttons and per-deck local file pickers
  load paused. The existing import workspace remains accessible in a sheet.
- Reused the AVFoundation player for independent decks A/B. Added per-deck bass,
  mid and high cuts (0 to −24 dB), EQ reset, level/mute, seek, beat cue, tap/manual BPM
  and ±20 ms nudges. Moved the spectrum tap after EQ, before listening volume.
- Added read-only local beat analysis using the existing librosa dependency and
  spectral estimator, with catalog BPM reuse, silence rejection and manual fallback.
  Analysis uses the first 90 seconds; corrections stay in the playback session and
  stale responses cannot overwrite a newly loaded file or manual BPM/cue changes.
- Sync B → A matches effective BPM and beat phase with host-time scheduling; Play
  both starts the decks at one host timestamp. Rejects speeds outside 0.5×–1.5×.
  This is a one-time fixed-tempo alignment; estimated cues/BPM need listening checks,
  and live drums can drift. Pitch follows speed. No key lock, cue output or export.
- Signal starts with 50% levels for headroom; leaving it pauses B and retains A.
  Existing audio, downloads, protected library, catalog and Sockseek settings remain
  untouched. No live downloads were started.
- On the user's smoothness feedback, replaced the 24 Hz waveform clock with a 60 fps
  animation timeline isolated to the waveforms. The playhead interpolates the audio
  render timestamp against the host clock; source-anchored waveform bins scroll
  continuously. Transport labels update at 10 Hz. Reduce Motion uses stationary pages.
- Validation: all 21 Python tests passed, including new generated-pulse tempo/
  beat-anchor detection, silence, invalid BPM and unchanged source bytes. Native
  generated-audio checks passed for simultaneous playback, paused/running beat-phase
  sync, independent stopping, measured attenuation of each EQ band, EQ isolation/reset,
  invalid sync ranges and unchanged sources. Existing player, spectrum, Silverwave
  and boombox render checks passed. The stereo WAV fixture emits its existing harmless
  non-interleaved setting warning.
- Initial compilation exposed an overly complex Swift numeric expression; split it
  into typed intermediate values. An initial native sync-range assertion had not
  restored the master BPM/cue after an EQ fixture reload; corrected the fixture and
  reran successfully. These were resolved before delivery.
- Visually checked the actual dark window, real waveforms, library A/B loading, local
  beat estimates, both decks playing at matched BPM, independent three-band control,
  resetting EQ, B stopping while A continues, and opening/closing Tracks & imports.
  Rebuilt and restarted the final 60 fps revision; rechecked both real tracks playing,
  tempo/phase sync, waveform drawing, saved Signal selection and a Silverwave round
  trip with A continuing and B paused. Left Signal selected with both decks paused.
  Reran the native player and dual-deck suites after audio-clock interpolation; both
  passed. Strict signing verification passed after clearing the generated bundle’s
  FinderInfo attribute, which Desktop sync had restored after the build.
- Not checked: external audio devices, every supported codec, headphone/controller
  integration, a new live import, long-session drift or formal compositor frame-time
  profiling. A 60 fps schedule is not a measured guarantee under every system load.


## 2026-11-18 — Correct reversed imports, usable review and compact Signal waveforms

- Diagnosed the Vienna Scientists III import as artist/title reversed, rather than
  relaxing identity validation. Added a local Swap artist / title & recheck action
  before any tracks are accepted. Original source text and original row fields stay
  intact; corrected search CSV retains duration/extra columns. Checks take the import
  lock and do not start Sockseek or any new network transfers.
- Review badges and row menus now open a panel with file tags, codec/duration,
  filename, rejection reason, independent listening preview and Finder reveal.
  Expected artist/title can be edited or swapped and rechecked. All normal metadata,
  supplied-duration, measured bitrate and decode requirements remain enforced;
  file tags are never rewritten. Updated hook outcomes and app-owned indexes after
  accepted staged files move through the existing organizer.
- Repaired saved import cf100cc63f74 through the new graphical action: nine review
  files passed full decoding and measured 320.01 kbps checks and were organized.
  Three unavailable rows remain unavailable; no retry/download was started.
  Compared device/inode/size/mtime signatures before and after every accepted move;
  all matched. Backed up job/input/hooks/indexes under
  .music-sorter/build/before-review-fix-cf100cc63f74/ before applying the correction.
  The protected juan music library was not changed.
- Signal detail lanes shrink from 76 to 44 points, overview from 22 to 18, and
  detail amplitude to 55%. Shared View zoom defaults to 60 seconds instead of 12,
  ranges from 12 to 120 seconds, and persists as listd.waveformSeconds. Replaced
  scrolling thin bars with a filled source-anchored envelope and clipped drawing to
  each lane to address subpixel shimmer; retained the 60 fps animation timeline.
- Added native table-row file URL dragging and file URL drops on either waveform,
  with single local audio-file validation and paused loading through CratePlayer.
  Existing A/B buttons and file pickers are retained. Initial cell-only drag wiring
  was replaced with native row item providers and selection; the drop handler now
  uses the existing file-URL decoding pattern instead of URL Transferable handling.
- Validation: all 25 Python tests passed, covering correction/source/CSV/index/hook
  preservation, staged path/symlink guards, import locking, per-row correction and
  retained identity/duration/quality rejection. Native generated-audio dual-deck
  checks passed, including the compact waveform render and amplitude bounds,
  simultaneous playback, sync, independent stopping/EQ and unchanged source bytes.
  Render artifact: .music-sorter/build/signal-waveform-preview.png.
- Rebuilt and restarted LiSTd; inspected the review panel and listened/paused its
  preview, applied the whole-import correction, saw 9/12 ready, opened Signal,
  loaded two real tracks with A/B, adjusted View, and checked muted dual playback
  with actual filled waveforms. Final strict codesign verification passed after
  removing the generated bundle FinderInfo attribute restored by Desktop sync.
- Limits: repeated automated native drag gestures did not produce a confirmed deck
  load. The NSItemProvider exposes public.file-url/public.url, file URL decoding and
  FLAC audio-type conformance were verified separately, but an end-to-end UI drop
  remains unverified. No formal compositor frame-time/flicker profiling, external
  device checks, or new live imports/downloads were run. Original/Amped/Silverwave
  source artwork was preserved; their separate render suite was not rerun.


## 2026-11-18 — Signal left collection / right mixer and more accurate beatmatch

- Changed Signal to a proportional horizontal split: collection/search take the left
  third at full height, decks and EQ take the right two thirds. Two-line title/artist/
  genre rows retain BPM, A/B buttons, selection and file URL dragging. The right side
  scrolls independently at short window heights. Split header, transport and tempo
  controls into separate rows so the narrower mixer column remains usable. Retained
  compact waveform heights and all other skins.
- Reproduced coarse tempo error with generated 123.45 BPM pulses: the earlier
  spectral bin gave approximately 122.45 BPM. Deck-only analysis now refines period
  and anchor across many beats instead of using that bin and the first detected beat.
  Local period estimates, strong-onset fitting and reassigned grid numbers tolerate
  extra/missing detections around breakdowns. Uncertain grids keep sync disabled until
  a manual cue is supplied. No catalog BPM, file tags or audio are rewritten.
- Added --refine-bpm for estimated/catalog seeds. Manual BPM, Tap and half/double
  controls mark BPM as manual, preserve its exact value during analysis, and invalidate
  an in-flight estimate's ability to overwrite it. Display two decimals while retaining
  full precision for sync. Half/double controls address octave errors explicitly.
- Sync now projects the master to the exact shared future host timestamp used to
  start B, instead of adding a relative delay before scheduling later. Scheduled
  playback clocks remain stationary until that timestamp and avoid stale pre-start
  render times. Existing paused sync, varispeed, EQ and independent playback remain.
- Validation: all 26 Python tests passed, including fractional tempo/anchor accuracy
  through 120 beats, a spurious detection regression, manual BPM preservation,
  uncertain-grid rejection and read-only source checks. Native player and dual-deck
  suites passed. Added scheduled-clock assertions and generated-pulse detection from
  actual audio taps, checking pulse steadiness and relative phase within 65 ms for
  the fixture, beyond displayed BPM/position assertions. Existing stereo fixture
  emits its known non-interleaved-setting warning and passes.
- An initial one-to-one pulse-edge assertion failed because spectrum snapshots can
  skip individual pulses; replaced it with circular phase over detected beats and a
  separate pulse steadiness requirement. An initial whole-sequence fit rejected
  Westworld's breakdown; local period fitting and reassigned grid numbers corrected
  this, covered by the extra-detection regression.
- Rebuilt/restarted LiSTd and inspected the actual 1:2 layout, full-height list,
  search/A/B loading, two real waveforms and running B-to-A sync. Reanalyzed the
  user's Westworld / Blah Blah pair locally: estimated 126.90 / 130.00 BPM; sync
  produced matching effective 129.56 BPM with A's 1.021 speed retained. Also checked
  Black Russian's local fit. These are estimates, not independently verified musical
  ground truth. Strict codesign verification passed after clearing the synced
  generated bundle's FinderInfo attribute. Updated APP_CONTEXT.md and CRATE.md.
- No new downloads, credentials, protected library or organizer catalog changes.
  Not checked: long-session live-music drift, external devices, every codec, separate
  Amped/Silverwave artwork/spectrum suites or end-to-end drag gestures in the new
  layout. Beatmatch still uses a fixed tempo and has no downbeat/phrase detection,
  continuous lock or key lock; unusual rhythms can need manual BPM/cue/nudges.

## 2026-11-18 — Deferred slider animation report

- Recorded the user's report in APP_CONTEXT.md for the next project session:
  clicking sliders briefly makes them animate/jump from the top of the screen.
  Exact affected controls/skins and cause remain unverified.
- Documentation only, as requested. No investigation, source changes, rebuild,
  app restart, tests, audio analysis or downloads were performed.

## 2026-11-18 — Shareable LiSTd 1.3 and personal Soulseek sign-in

- Added first-launch Soulseek sign-in and an account button in the shared toolbar.
  Successful print-only login checks save the account with Security.framework in
  this Mac's Keychain. Imports pass credentials over stdin; Sockseek receives a
  temporary mode-600 config in a mode-700 system-temp directory, cleaned on normal
  success/failure. Account changes are blocked during imports. Sign-out removes
  only the LiSTd Keychain item; playback remains available without login.
- Preserved global Sockseek configuration, the development MUSIC workspace, all
  four skins, quality/identity/duration checks and protected collection. App remote
  CLI commands now ignore global config, with account settings owned by the daemon.
  CLI runs without a stdin account retain the legacy global-config behavior.
- Added package-crate, requirements-package.txt and package/audit/license scripts.
  The separate release/LiSTd-Apple-Silicon.zip bundles the native app, frozen Python
  runtime/librosa dependencies, pinned Sockseek 3.0.6, minimal FFmpeg/FFprobe 8.0,
  notices and build sources. It includes no account, saved jobs, catalog or music.
  The release uses ~/Music/LiSTd; its frozen completion hook relaunches itself.
- Homebrew FFmpeg declares macOS 26 minimum, so release tools are built from source
  with macOS 14 minimum and no external codec libraries/network. An initial offline
  check caught incorrect raw muxer configure names; corrected to pcm_s16le/pcm_f32le
  and added cached-build flag checking before the final successful package run.
- Desktop sync restored FinderInfo during signing and caused one strict signature
  check to fail. Packaging now signs/verifies/zips in system temporary storage,
  copying only the completed archive into release/. Final strict deep verification
  also passed after extracting the actual ZIP outside the synced Desktop.
- Added optional Developer ID/hardened-runtime signing and notarytool submission /
  stapling via Keychain identity/profile names. No signing identity is installed
  here, so the produced archive is ad-hoc signed and not notarized. Documented
  recipient Open Anyway approval and supported Apple Silicon/macOS 14+ target in
  SHARING.md. Updated APP_CONTEXT.md, CRATE.md and THIRD_PARTY.md.
- Validation: rebuilt native LiSTd 1.3; all 29 Python tests passed. Tests cover config
  injection rejection, permissions and success/error cleanup, print-only login and
  sanitized failures, frozen callback invocation, and account forwarding through a
  fake peer to the real sorter. Bundle dependency/minimum-OS audit and isolated
  HOME/no-Homebrew offline CSV, generated-audio analysis and actual frozen callback
  passed. Opened the exact ZIP's app, visually inspected first-launch login and its
  empty personal workspace, then restored the development build. Existing library
  still contains 147 tracks; no live downloads or credential/config changes.
- Not checked: successful live Soulseek authentication, actual Keychain save/reload,
  another physical Mac or macOS 14 installation, quarantined Gatekeeper first-open,
  Developer ID/notarization, separate player/spectrum/skin render suites. Forced
  process termination can leave a private temporary account file until OS cleanup.

## 2026-11-18 — LiSTd 1.3.1: accept successful login when the test search is empty

- Reproduced the reported sign-in failure with the user-authorized account:
  Sockseek explicitly authenticated, then its print-only probe found no files and
  exited with WorkFailed (1). LiSTd incorrectly required exit code 0 as well as
  authentication, so a valid account was rejected before Keychain storage.
- The shared backend login check now uses the explicit logged-in confirmation.
  Empty search results do not invalidate successful authentication; missing login
  confirmation still rejects credentials/network failures. Added a regression
  fixture matching the real exit-1/logged-in/no-results output. No quality,
  download, global Sockseek configuration or music-library behavior changed.
- Validation: all 29 Python tests passed; real graphical sign-in succeeded,
  the sheet closed and the account appeared in the toolbar. After quitting and
  relaunching LiSTd, the saved account loaded without re-entering credentials,
  verifying actual Keychain save/reload. No passwords were written to project files
  or command arguments; the live test made only the print-only search, no downloads.
- Raised the app version to 1.3.1/build 5 and rebuilt/restarted the native app; it
  retained the saved account and displayed the existing 147-track library. Rebuilt
  release/LiSTd-Apple-Silicon.zip; the isolated dependency/CSV/audio-analysis/
  organizer checks passed. Extracted that exact archive, verified version 1.3.1
  and its strict deep signature, and ran its frozen login command with the real
  authorized account and bundled Sockseek: exit 0, authenticated true.
- No new downloads or global configuration/collection changes. Other physical Macs,
  Developer ID/notarization and separate skin/player render suites were not retested.

## 2026-11-18 — LiSTd 1.4 universal standalone package

- Expanded the native build to arm64/x86_64 and package-crate to bundle independent
  Python/audio, Sockseek and FFmpeg/FFprobe runtimes for both in one LiSTd-Mac.zip.
  The Swift slice selects its matching backend. A release-only Info.plist marker
  controls the personal workspace; missing release tools report reinstall instead
  of attempting to use development source/system Python. Sockseek's .NET extraction
  cache now lives in the writable workspace alongside the existing Numba cache.
- Added strict architecture checks and a relocated/read-only, clean-HOME sandbox
  test that denies the developer home, external tools and outbound internet. It
  probes the denial rules and exercises the shipped worker with a generated local
  mock peer through the actual daemon/remote CLI/frozen callback/index protocol,
  sorting, relabeling and subsequent state reload. No live music is downloaded.
- Native player tests now accept generated codec fixtures and verify playback and
  source preservation. All 29 Python tests passed. Player, dual-deck, spectrum and
  skin suites passed on arm64 and x86_64 under Rosetta, including all nine generated
  codec fixtures in both players.
- Updated SHARING.md, CRATE.md, APP_CONTEXT.md, THIRD_PARTY.md and STANDALONE_QA.md.
  No Developer ID identity is installed; notarization and physical Intel/macOS 14
  acceptance remain unavailable here.
- Release build output under the synced Desktop acquired 52 duplicate compiled
  library conflict files after freezing, and copying one stalled. Stopped that
  staging run; moved release environments/output/tool caches to
  ~/Library/Caches/LiSTdBuild and rebuilt both runtimes cleanly. The shipped outputs
  have zero such conflict copies. Release templates now copy only the known native
  executable, plist and icons; sources/tool runtimes follow explicit build inputs.
- Initial audit attempts caught checker issues: universal otool architecture headers
  were misread as dependencies, and noncanonical /var temporary paths did not enforce
  the intended write denial. Corrected parsing/canonical paths, added denial probes,
  and ran the full checks successfully. These fixes did not weaken the isolation.
- Final universal package passed both sandboxed pipelines through the actual mock
  daemon/remote CLI/frozen callback, sorting, index updates, relabeling and state
  reload. Added an accessible top-level READ ME FIRST.txt. The exact ZIP passed
  CRC/layout, architecture and strict deep signature checks. Both exact-ZIP runtimes
  passed real Soulseek login and verified/sorted all nine generated codec fixtures.
  A tagless AIFF with a generic filename was correctly rejected; accepted fixtures
  used matching filename evidence. Native startup checks observed both slices
  choosing their correct packaged backend and a fresh per-user workspace.
- Native UI inspection failed to start on three attempts, including after reset.
  Final visual click-through and the missing-tools alert were not UI-verified.
  Physical Intel/macOS 14 acceptance remains outstanding. spctl rejected the ad-hoc
  build as expected; no Developer ID certificate is installed, so default Gatekeeper
  acceptance/notarization are not achieved. Recipients need documented Open Anyway.
  The user explicitly accepted that one-time first-open approval route.
- No live music downloads, global Sockseek configuration changes, original catalog
  changes or protected collection moves were made. Existing library remains 147 tracks.
- Reran the complete sandbox pipeline on the final extracted delivery ZIP: both
  arm64/x86_64 passed. Embedded runtime/build sources and README match the project.
  Restored the development app and removed only the generated temporary acceptance
  bundles/fixtures. Delivery ZIP SHA-256 is recorded in STANDALONE_QA.md.

## 2026-11-19 — Public-repository presentation and installation documentation

- Added a README with centered Amped artwork, real Signal preview, feature/skin
  overview, friend installation steps, tracklist examples, limitations, storage,
  privacy, developer commands and links to the detailed guides.
- Added INSTALL.md with download/extraction/Applications steps, first-open approval,
  sign-in/local playback, imports, updates and troubleshooting. Verified the macOS
  approval flow against Apple's current support guide. Clarified that the Mac ZIP
  already bundles Sockseek; linked upstream and the tested 3.0.6 Mac archives for
  source/CLI use, including an install command after extraction and a version check.
  Upstream's current README documents release downloads, not a shell-installer command.
- Added the MIT license for original LiSTd code at the user's request. Kept bundled
  dependency licenses separate and updated sharing/recipient documentation links
  and cache locations. The recipient text template changes apply to future builds.
- Added scripts/render_readme.swift to render actual SwiftUI/AppKit player views
  using generated example audio in temporary files. Native controls use NSHostingView
  rendering; ImageRenderer omitted those controls in the first preview attempt.
  The final Amped and Signal PNGs were visually inspected and contain example data.
- Created a v1.4.1 GitHub release with the unchanged tested Mac ZIP, its checksum and
  LICENSE; updated repository description/topics. Kept the repository private and
  preserved Git history. Checked all three prior commits/38 historical paths for
  excluded music/account/state/bundle files and credential-like tokens; none matched.
  Existing developer attribution and local-path documentation remain in history.
- Validation: both guides rendered through GitHub's GFM API; checked local links,
  heading anchors, image alt text/dimensions, expandable sections and shell syntax.
  The initial static check assumed heading IDs in API output; changed it to check
  rendered heading elements and source anchors, then it passed. GitHub's uploaded
  asset digest matches the previously validated ZIP SHA-256. No app/runtime source
  changed; no app rebuild, full playback/audio suite, library scan, credential change
  or live download was needed for this documentation/release work.

## 2026-11-21 — Skin switch appearance fix

- Fixed mixed dark/light colours after leaving **Signal · Dual Deck** for
  **LiStD · Original**. Signal forced dark mode through SwiftUI
  `preferredColorScheme(.dark)`; Original passed `nil`, which SwiftUI on macOS does
  not apply, so AppKit-backed views (collection table, sliders, toolbar) stayed dark
  while SwiftUI text followed the light system scheme. The root view now sets
  `NSApp.appearance` per skin on launch and on every skin change (Signal dark, Amped
  and Silverwave light, Original follows the system) and clears per-window overrides.
- Affected skin: Original only. Amped and Silverwave passed an explicit light value
  and already reset correctly; Signal itself was unaffected.
- Validation: `./build-crate` succeeded (both slices); native skin check passed.
  Manual visual check of the skin switch in the running app was not performed by the
  agent; it is left to the user.

## 2026-11-21 — Single view: one Load track button and deck drag-and-drop

- In single-deck skins (Original, Silverwave, Amped), collection rows and import results
  now show one **Load track** button that loads into the visible deck, replacing A/B.
- Dropping one audio file onto the single deck panel loads it paused. Non-audio,
  folders, remote URLs and multi-file drops are ignored. The drop logic is now shared
  with Signal (`CratePlayer.loadDroppedAudio`); Signal's A/B behavior is unchanged.
- Validation: `./build-crate` succeeded; check-player (new drop, rejected-drop,
  independent-deck and corrupt-file cases), check-dual-deck and check-skin passed.
  Manual in-app click/drag testing was not performed by the agent.

## 2026-11-25 — Parallel imports: up to five tracks at once

- Imports now search, download and verify up to five tracks at the same time
  (`PARALLEL_TRACKS` in `crate_backend.py`) instead of one. Each row is still its own
  Sockseek command with the same quality, duration and identity checks.
- The app's Sockseek daemon now starts with `--concurrent-searches 5`; its default of 2
  silently queued parallel searches. Soulseek's ban limiter (34 searches / 220 s) is kept.
- Safety for parallel work: thread- and process-locked job.json writes, duplicate
  artist/title rows processed in one lane, completion hooks wait for the catalog lock,
  `.incomplete` cleanup limited to the track's own folders, one failing row no longer
  stops the rest. Search timeouts raised to 240 s to cover limiter waits.
- Stress test (search-only, no downloads, live Soulseek, 42 searches total):
  daemon default (2 concurrent): 1 → 11.3 s, 3 → 20.7 s, 5 → 33.6 s, 8 → 53.1 s,
  10 → 63.6 s. Daemon at 10 concurrent: 5 → 18.9 s, 10 → 18.0 s. All 42 searches
  returned without errors or ban signs.
- Validation: 45 unit tests passed (5 new in `tests/test_parallel_import.py`). No live
  download or full in-app import was run.
