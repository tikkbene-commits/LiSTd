# MUSIC folder instructions

## Start here in a new chat

- This folder contains the **LiSTd** macOS app (formerly Crate) and the existing music collection. Before editing the app, read `APP_CONTEXT.md`, the recent entries in `CHANGELOG.md`, and the relevant sections of `CRATE.md` / `MUSIC_SORTER.md`. These files are the project handoff; do not assume a new chat has the old conversation.
- Inspect the current source before changing it. The live code and saved state take precedence over dated handoff snapshots. Preserve unrelated work, including the Silverwave and Original skins.
- After each app change, update `APP_CONTEXT.md` when behavior, architecture, preferences, setup or known limitations change, and append a dated entry to `CHANGELOG.md` describing the change and its validation. Record checks that were skipped or failed honestly. Do not place secrets, credentials or full chat transcripts in these notes.
- Edit source files, not generated files inside `LiSTd.app`. Rebuild after Swift/icon changes and restart the app to load the new binary. Documentation-only changes need no build, audio scan or download. App maintenance alone never authorizes a new live download.

## Soulseek downloads

- Use the installed `sockseek` command for Soulseek searches and downloads requested from this folder. It reads the account configuration from `~/.config/sockseek/sockseek.conf`; never ask for, print, or copy those credentials into project files or command arguments.
- Save downloads to `./downloads`. The existing collection is `./juan music`; pass `--skip-music-dir "./juan music"` to avoid downloading tracks already in that library, and do not alter the collection unless asked.
- For a single track use `-s`. For an album use `-t` so the user can choose a match. Use the exact query, playlist, or file supplied by the user; ask only when the request lacks enough information to search reliably.
- Run a download only when the user requests one. For a request to inspect or preview matches, use Sockseek's print options and do not download.

## Search and quality workflow

- For a CSV playlist, preserve its artist, title, and duration fields. Search one row at a time with `--input-type csv --offset N --number 1`; `N` is the zero-based row offset, excluding the header. This avoids losing duration matching and makes each result easy to verify.
- For alternate searches, retry one CSV row at a time with its exact duration. Search the full artist and title, then the release or album title and catalog number when known; title-only searches can surface matches when artist metadata differs. `--artist-maybe-wrong` scans broadly and may exhaust memory on a large CSV, so use it only for a single row (or small batch), and inspect `--print results-full` and confirm the title and duration before downloading.
- For a minimum quality threshold, set `--format` to accepted codecs, `--min-bitrate` to the user's lossy threshold, and `--strict-conditions` so unknown bitrate metadata is not treated as a pass. Lossless formats such as FLAC and WAV are acceptable when the user says so.
- Do not treat Sockseek's displayed or nominal bitrate as final verification. After a download, inspect the local file with `ffprobe` (codec, measured bitrate, duration, and tags). A nominal 150 kbps MP3 can average below 150 kbps; count it only if the user's threshold allows that or a qualifying alternative is found.
- Search results are candidates, not proof of a correct match. Reject near-duration false positives, alternate mixes, and unrelated titles even when the bitrate qualifies. If tags conflict with the filename/release evidence, flag that uncertainty instead of silently asserting an exact match.
- Prefer one-track Sockseek jobs (`--concurrent-jobs 1 --concurrent-searches 1`) for long playlists: this keeps each result tied to its CSV row and avoids the broad search fan-out that can exhaust memory. A listed result may still be unavailable: stale transfers mean the peer sent no data. Retry another exact peer if available, then remove only failed `.incomplete` remnants; never count them as downloads.

## Local genre and vibe organizer

- The standalone organizer is `./music-sorter`; usage and evidence limits are in `MUSIC_SORTER.md`. It uses local FFmpeg, requires no API keys, and never downloads music itself.
- When asked to organize, run `./music-sorter sync` to inspect the plan, then `./music-sorter sync --apply` to move tracks into `downloads/organized/<genre>/<vibe>/`. Use `--by genre` or `--by vibe` when requested. Files are moved, not copied. Preserve `.music-sorter/catalog.json` for manual labels and undo history.
- Genre is based on file tags or manual labels; audio vibe/BPM results are estimates. Do not claim that a genre or mood was identified by a trained audio model. Missing or ambiguous genres remain `Unsorted`; unclear rhythms remain `Needs Review`. Use professional DJ terminology for folder names, with no emoji.
- For future requested Sockseek downloads, add `--on-complete 'when=success scope=track lock update-index -- "/Users/tikkbene/Desktop/MUSIC/music-sorter" sockseek-hook "{path}"'` so each completed audio file is organized and Sockseek receives its new index path. Preserve all existing query, CSV duration, quality and library-skip requirements above. The hook does not replace post-download `ffprobe` quality verification; inspect the catalog/new path for that verification.
- Do not change Sockseek credentials/configuration or start downloads to test the hook. Do not start a persistent watcher unless asked; `./music-sorter watch --apply` runs in the foreground until Ctrl-C. Avoid running watch and the completion hook simultaneously.
- The organizer excludes `delete_review`, `.incomplete` files, hidden folders and symlinks. It never touches `juan music`. `./music-sorter list` supports genre, vibe and BPM filters for set selection. Use `label TRACK_ID --genre ... --vibe ...` for corrections and `undo` / `undo --apply` for reversal.

## LiSTd graphical app

- `LiSTd.app` is the native macOS front end; source is `native/Crate.swift`, backend is `crate_backend.py`, and usage is in `CRATE.md`. Run `./build-crate` to rebuild it. Keep the app in this folder. The app/backend use `.music-sorter/audio-env/bin/python` for local librosa tempo analysis; use that interpreter for the complete test suite.
- A user importing/dropping a tracklist with automatic downloads enabled requests downloads. Respect the import's selected quality (initially 320 kbps or lossless). Preserve CSV fields; text timestamps and SetStart are mix cue positions, not full-track durations. Text order is explicit; the supplied example is Title - Artist.
- Crate owns one loopback-only Sockseek daemon for the duration of an import and still searches CSV rows individually. Its custom completion hook verifies codec, packet-measured bitrate, supplied duration and title/artist evidence before calling the organizer and updating Sockseek's index path. Do not add a second organizer hook or watcher to Crate's commands.
- Only accepted files move from `downloads/.incoming/<import-id>/` into organized folders. Failed or uncertain files stay in staging and are shown as review/unavailable; never count them as successful songs. Do not relax quality or substitute alternate mixes silently. Existing qualifying tracks are reused; `juan music` is never moved.
- Automatic genre comes only from tags, vibe/tempo is approximate, and the app does not fingerprint the YouTube mix. The provided set/tracklist is `tracklists/YouTube set bNSesW8h94I.csv`.
