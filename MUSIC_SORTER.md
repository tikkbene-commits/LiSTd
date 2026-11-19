# Music Sorter

A local command-line tool for this MUSIC folder. For the graphical window with
integrated downloads, open **LiSTd.app**; see [CRATE.md](CRATE.md).
It reads finished Sockseek downloads,
uses genre tags, estimates a DJ-oriented vibe, and **moves** each track to one folder.
It never makes audio copies, rewrites tags, or downloads music.

Python 3.9+ and FFmpeg (`ffmpeg` and `ffprobe` on PATH) are required. They are installed
on this machine. The launcher uses the local librosa environment when installed,
with a simple standard-library estimator as a fallback. No API keys or subscriptions
are needed. Analysis itself runs offline.
Run `./music-sorter doctor` to check setup.

## Everyday use

From this folder:

```sh
./music-sorter sync                  # Analyze new files and preview moves
./music-sorter sync --apply          # Actually organize the files
./music-sorter watch --apply         # Keep organizing new arrivals until Ctrl-C
```

The default layout is:

```text
downloads/
  organized/
    Tech House/
      Groove/
        Artist - Track.mp3
    Techno/
      Driving/
        Artist - Another Track.flac
    Unsorted/
      Needs Review/
        Untagged Track.wav
```

Each track lives in **one** genre/vibe folder. Choose `sync --by genre --apply` or
`sync --by vibe --apply` for a single layer. `sync --by both --apply` restores the
two-layer layout. An applied layout is remembered for later syncs and hooks.
Preview commands cache analysis in `.music-sorter/catalog.json` but never move music.

The tool recursively scans `downloads`, including its organized subfolder.
`delete_review`, hidden folders, symlinks, non-audio files and `.incomplete` files
are excluded. `juan music` is outside its scope. Original playlist CSVs and Sockseek
index files are left in place. A sync is incremental: unchanged tracks reuse their
cached analysis. Removed files are omitted from results; their history is retained
for recovery.

`watch` runs in the current terminal; it is not an installed background service.
It scans every 30 seconds, ignores files modified within 60 seconds, and checks
again that each file stayed unchanged during analysis. Normal `sync` waits for
30 seconds of file age. `--min-age 0` is available for known completed files.
Use the completion hook below for the strongest indication that a download finished.

## Genre and vibe evidence

**Genre comes from embedded genre tags or your corrections.** Missing or conflicting
genre tags go to `Unsorted`. Generic parent tags are ignored when a more specific
tag is present (Electronic / Tech House becomes Tech House). Several unrelated tags,
such as House / Techno, stay unresolved. A tag is metadata supplied with the file,
not proof of the track's genre. No genre is guessed from its filename or BPM.

**Vibe is an approximate tempo/crest-factor heuristic**, not an AI mood classifier.
The tool decodes three 24-second mono excerpts, centered near 20%, 50% and 80%
of a track (short tracks use shorter excerpts). It estimates a repeating pulse
from spectral onsets using local librosa when available, otherwise from bass-amplitude
changes. The spectral method checks agreement across excerpts. Valid BPM tags take
priority over the estimate.
Crest factor measures peak-to-average amplitude, a rough proxy for density which
can also reflect mastering choices.

| Folder | Rule |
| --- | --- |
| Warm-Up | Below 110 BPM |
| Groove | 110–129 BPM, except the denser case below |
| Driving | 130–144 BPM, or 123–129 BPM with crest factor below 9 dB |
| Peak Time | 145 BPM or faster |
| Needs Review | No usable tempo or weak pulse estimate |

These are starting crates for electronic music, not reliable judgments of mood,
danceability, darkness, groove, musical key, or set compatibility. Audio BPM estimates
can be half/double tempo, can follow hi-hats instead of kicks, and are not DJ beat
grids. Verify important choices by listening or in your DJ software. JSON output
records the label source, original genre tag, estimate strength and BPM warning.
Manual labels survive rescans and moves.

## Find music and correct labels

```sh
./music-sorter list
./music-sorter list --genre house --vibe 'Groove' --min-bpm 120 --max-bpm 128
./music-sorter label TRACK_ID --genre 'Dub Techno' --vibe 'Basement Business'
./music-sorter sync                  # Preview the corrected folder
./music-sorter sync --apply
./music-sorter label TRACK_ID --reset # Return to automatic labels
```

Use the 12-character ID printed by `list`. Filters are case-insensitive partial
matches. Tracks without BPM are excluded when a BPM range is requested. Manual
genre and vibe names can be anything you want; unsafe filename characters are
replaced. Changing a label changes the catalog only until the next applied sync.

Codex can run this when asked to organize downloads or find music for a set.
For example: “Organize my new downloads” or “Find Groove around 125 BPM.”

## Sockseek completion hook

[Sockseek's on-complete actions](https://github.com/fiso64/sockseek#on-complete-actions)
support `update-index`, which reads `success;new_path` from a command's stdout.
This tool's `sockseek-hook` command sorts just that completed track and emits its
new absolute path, so Sockseek can update its index and generated playlist.

Add this argument to an otherwise authorized Sockseek download command:

```sh
--on-complete 'when=success scope=track lock update-index -- "/Users/tikkbene/Desktop/MUSIC/music-sorter" sockseek-hook "{path}"'
```

Keep the existing `-o ./downloads` and `--skip-music-dir './juan music'` options and
all query, duration, codec, bitrate and quality-verification requirements in
`AGENTS.md`. The hook does not replace quality checks. It uses Sockseek's existing
configuration without reading, storing or passing credentials itself. It never
starts a download. No Sockseek configuration has been changed by installing this tool.

Prefer the hook for future Sockseek downloads. Avoid running the watcher at the
same time as the hook: both sort the same files, and the catalog deliberately allows
only one active command. A failed hook leaves recovery information in the catalog;
read its error and use `doctor` / `undo` before retrying if needed.

Bulk sorting existing files or using the watcher cannot update playlists/indexes
held by other programs. Existing DJ playlists and old Sockseek index paths may
need relinking after those files move. New downloads using the hook receive the
updated path through Sockseek's supported mechanism.

## Undo and safety

```sh
./music-sorter undo                  # Preview the last batch in reverse
./music-sorter undo --apply          # Restore the original locations
```

Each applied sync is a batch; each completion hook is a one-track batch. Repeated
undo commands walk backward through batches. Labels are retained; undo restores
paths only. Stop a watcher before undoing, or it will organize the files again.
Keep `.music-sorter/catalog.json`: it contains labels, cached analysis and the
recovery journal. Do not delete it if a move is interrupted.

Moves use an exclusive hardlink followed by unlinking the source, on the same
filesystem. This preserves the file's bytes and inode, uses no extra audio storage,
and refuses to overwrite an existing target. During that brief operation there
can be two directory entries for the same audio data; an interrupted move is
recoverable with `undo --apply`. Cross-filesystem moves fail without copying.
Filename collisions receive a track-ID suffix. The tool does not deduplicate
pre-existing audio files or delete unrelated files or empty folders.

A source must still match its recorded device, inode, size and modification time
before moving. Undo similarly refuses modified files or occupied original paths.
These checks detect ordinary changes, not malicious edits that preserve all file
attributes; this tool is designed for a local, trusted library. Catalog writes are
atomic and move plans are saved before changing files. A failure can leave a
partially completed batch; inspect `undo` before `undo --apply` to recover it.

## Command output and tests

```sh
./music-sorter --json list
./music-sorter --json sync
./music-sorter --json doctor
python3 -m unittest discover -s tests -v
```

`--json` goes before the command. JSON is a command-specific envelope: `list`
returns `{"tracks": [...]}`, sync/undo return `{"changes": [...], "applied": false,
...}`, scan returns counts and errors, and failures return `{"error": "..."}` with
exit status 1. Sync/scan return status 1 if any file could not be analyzed, even if
other files succeeded. `watch --json` emits one JSON object per nonempty cycle
(objects can span lines). `sockseek-hook` always emits Sockseek's plain-text
protocol on success. Ctrl-C exits watch with status 130.

The tool's own location determines the project root, so absolute invocation works
from another directory. `--root PATH` is mainly useful for testing another isolated
MUSIC-style folder. Tests use generated audio and temporary directories, covering
tempo estimation, FFmpeg decoding, collisions, watch arrivals, corrections,
incremental sync, move/undo safeguards, crash recovery and the completion protocol.
