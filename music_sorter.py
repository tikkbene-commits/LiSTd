"""Local, on-demand DJ library sorting. Only FFmpeg and Python are required."""

import argparse
import array
import contextlib
import fcntl
import json
import math
import statistics
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from collections import Counter
from functools import lru_cache


ROOT = Path(__file__).resolve().parent
AUDIO = {'.mp3', '.flac', '.wav', '.aif', '.aiff', '.m4a', '.aac', '.ogg', '.opus'}
ANALYSIS_VERSION = 3
VIBES = ('Warm-Up', 'Groove', 'Driving', 'Peak Time', 'Needs Review')
LEGACY_VIBES = {'Slow Burn': 'Warm-Up', 'Pocket Grooves': 'Groove',
                'Afterburners': 'Driving', 'Redline': 'Peak Time', 'Needs a Listen': 'Needs Review'}


def signature(path):
    st = path.stat()
    return [st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns]


def save(root, state):
    directory = root / '.music-sorter'
    with tempfile.NamedTemporaryFile('w', dir=directory, delete=False, encoding='utf-8') as f:
        temporary = Path(f.name)
        try:
            json.dump(state, f, ensure_ascii=False, indent=2, allow_nan=False)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
            os.replace(temporary, directory / 'catalog.json')
        finally:
            temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def catalog(root):
    directory = root / '.music-sorter'
    directory.mkdir(mode=0o700, exist_ok=True)
    with (directory / 'lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another music-sorter command is running. Try again when it finishes.')
        path = directory / 'catalog.json'
        state = json.loads(path.read_text()) if path.exists() else {
            'version': 1, 'tracks': {}, 'batches': [], 'layout': 'both'}
        if not isinstance(state, dict) or state.get('version') != 1 or not isinstance(state.get('tracks'), dict):
            raise ValueError('Unsupported catalog. Keep the catalog file for recovery; do not delete it.')
        yield state


def local_path(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or '..' in Path(relative).parts:
        raise ValueError('Catalog path must be relative to this folder.')
    if not path.resolve().is_relative_to((root / 'downloads').resolve()):
        raise ValueError('Refusing to access a track outside downloads.')
    # A symlink in a directory could redirect a move outside the intended tree.
    if any(p.is_symlink() for p in [path, *path.parents] if p != root and p.is_relative_to(root)):
        raise ValueError('Symlinked music paths are excluded.')
    return path


def component(value):
    value = re.sub(r'[\x00-\x1f\x7f/\\:*?"<>|]', '-', str(value))
    value = re.sub(r'\s+', ' ', value).strip(' .')
    return value[:80].rstrip(' .') or 'Unsorted'


def genre_from_tags(value):
    genres = list(dict.fromkeys(g.strip() for g in re.split(r'[/;|,]', value) if g.strip()))
    genres = [g for g in genres if g.casefold() not in {'unknown', 'other', 'none', 'unclassified'}]
    if len(genres) > 1:
        specific = [g for g in genres if g.casefold() not in {'electronic', 'dance', 'electronica'}]
        genres = specific or genres
        genres = [g for g in genres if not any(
            h != g and h.casefold().endswith(' ' + g.casefold()) for h in genres)]
    if len(genres) == 1:
        return component(genres[0]), 'file tag'
    return 'Unsorted', 'ambiguous genre tags' if genres else 'missing genre tag'


def run_media(command):
    try:
        result = subprocess.run(command, capture_output=True, timeout=90)
    except subprocess.TimeoutExpired:
        raise ValueError('Audio inspection timed out.')
    if result.returncode:
        # Decoder output can be very long; keep failures readable.
        error = result.stderr.decode(errors='replace').strip().splitlines()
        raise ValueError(error[-1][:300] if error else 'Audio inspection failed.')
    return result.stdout


def estimate_tempo(envelopes):
    """Autocorrelation of bass amplitude changes, at 200 frames/second."""
    scores = {}
    usable = []
    for envelope in envelopes:
        if len(envelope) < 400:
            continue
        onset = [max(0.0, b - a) for a, b in zip(envelope, envelope[1:])]
        mean = sum(onset) / len(onset)
        onset = [x - mean for x in onset]
        power = sum(x*x for x in onset)
        if power > 1e-12:
            usable.append((onset, power))
    if not usable:
        return None, 0.0
    for lag in range(59, 222):
        scores[lag] = sum(sum(a*b for a, b in zip(onset[lag:], onset)) / power
                          for onset, power in usable) / len(usable)
    peaks = [lag for lag in range(60, 221)
             if scores[lag] > scores[lag-1] and scores[lag] >= scores[lag+1]]
    if not peaks:
        return None, 0.0
    # Favor the first strong pulse; avoid selecting a weak hi-hat subdivision.
    strongest = max(scores[lag] for lag in peaks)
    lag = min(lag for lag in peaks if scores[lag] >= max(0.12, strongest * 0.85)) if strongest >= 0.12 else max(peaks, key=scores.get)
    strength = scores[lag]
    if strength < 0.12:
        return None, round(max(0, strength), 3)
    left, center, right = scores[lag-1], scores[lag], scores[lag+1]
    denominator = left - 2*center + right
    adjustment = 0.5 * (left - right) / denominator if denominator else 0
    return round(12000 / (lag + adjustment), 1), round(strength, 3)


def bass_envelope(samples):
    fast = slow = 0.0
    fast_alpha = 1-math.exp(-2*math.pi*180/8000)
    slow_alpha = 1-math.exp(-2*math.pi*30/8000)
    envelope, power, count = [], 0.0, 0
    for sample in samples:
        fast += fast_alpha*(sample-fast)
        slow += slow_alpha*(sample-slow)
        power += (fast-slow)**2
        count += 1
        if count == 40:
            envelope.append(math.sqrt(power/40))
            power, count = 0.0, 0
    return envelope


@lru_cache(maxsize=1)
def audio_modules():
    import hashlib
    from importlib.metadata import version
    import platform
    # Compiled caches must not cross Python environments, dependency upgrades or architectures.
    runtime = [sys.executable, sys.version, platform.machine()]
    runtime += [version(name) for name in ('librosa', 'numpy', 'numba', 'llvmlite')]
    key = hashlib.sha256('\n'.join(runtime).encode()).hexdigest()[:20]
    cache = Path(os.environ.get('NUMBA_CACHE_DIR', Path.home()/'Library/Caches/LiSTd/numba'))
    os.environ['NUMBA_CACHE_DIR'] = str(cache/key)
    import librosa
    import numpy as np
    return librosa, np


def spectral_tempo(clips, *, onset_envelopes=None):
    try:
        librosa, np = audio_modules()
    except ImportError:
        return None
    estimates = []
    if onset_envelopes is None:
        onset_envelopes = [librosa.onset.onset_strength(
            y=np.asarray(samples, dtype=np.float32)/32768, sr=8000, hop_length=80, n_fft=512, n_mels=64)
            for samples in clips]
    for onset in onset_envelopes:
        if len(onset) < 400 or float(onset.max()) < 0.01:
            continue
        bpm = float(librosa.feature.tempo(onset_envelope=onset, sr=8000, hop_length=80, max_tempo=190).item())
        centered = onset-onset.mean()
        lag = round(6000/bpm)
        power = float(np.dot(centered, centered))
        strength = float(np.dot(centered[lag:], centered[:-lag]))/max(power, 1e-9)
        estimates.append((bpm, strength))
    if not estimates:
        return None, 0.0
    median = statistics.median(b for b, _ in estimates)
    agreeing = [(b, s) for b, s in estimates if abs(b-median)/median < 0.05]
    strength = statistics.mean(s for _, s in agreeing)
    if len(agreeing) < min(2, len(clips)) or strength < 0.12:
        return None, round(max(0, strength), 3)
    return round(statistics.median(b for b, _ in agreeing), 1), round(strength, 3)


def vibe_from_features(bpm, confidence, crest):
    if bpm is None or confidence < 0.12:
        return 'Needs Review'
    if bpm < 110:
        return 'Warm-Up'
    if bpm >= 145:
        return 'Peak Time'
    if bpm >= 130 or (bpm >= 123 and crest < 9):
        return 'Driving'
    return 'Groove'


def inspect_audio(path):
    metadata = json.loads(run_media([
        'ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe',
        '-show_format', '-show_streams', '-of', 'json', str(path)]))
    audio = next((s for s in metadata.get('streams', []) if s.get('codec_type') == 'audio'), None)
    if audio is None:
        raise ValueError('No audio stream.')
    fmt = metadata.get('format', {})
    duration = float(fmt.get('duration') or audio.get('duration') or 0)
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('No usable duration.')
    tags = {k.casefold(): str(v) for source in (audio.get('tags', {}), fmt.get('tags', {}))
            for k, v in source.items()}
    genre, genre_source = genre_from_tags(tags.get('genre', ''))
    tagged_bpm = None
    try:
        candidate = float(tags.get('bpm', tags.get('tbpm', '')))
        if math.isfinite(candidate) and 40 <= candidate <= 250:
            tagged_bpm = candidate
    except ValueError:
        pass
    # shortcut: three 24-second excerpts can miss breakdowns; use full-track analysis
    # when calibrated genre/mood models or accurate beat grids become necessary.
    seconds = min(24.0, duration)
    starts = sorted({round(max(0.0, min(duration-seconds, duration*f-seconds/2)), 2)
                     for f in (0.2, 0.5, 0.8)})
    envelopes, crests, clips = [], [], []
    for start in starts:
        raw = run_media([
            'ffmpeg', '-v', 'error', '-nostdin', '-protocol_whitelist', 'file,pipe',
            '-ss', str(start), '-i', str(path),
            '-t', str(seconds), '-map', '0:a:0', '-vn', '-ac', '1', '-ar', '8000',
            '-f', 's16le', 'pipe:1'])
        samples = array.array('h')
        samples.frombytes(raw)
        if sys.byteorder != 'little':
            samples.byteswap()
        if len(samples) < 800:
            raise ValueError('Not enough decodable audio.')
        squares = sum(float(x)*x for x in samples)
        rms = math.sqrt(squares / len(samples))
        peak = max(abs(x) for x in samples)
        if rms > 1:
            crests.append(20 * math.log10(max(peak, 1)/rms))
        envelopes.append(bass_envelope(samples))
        clips.append(samples)
    spectral = spectral_tempo(clips) if tagged_bpm is None else None
    bpm, confidence = spectral if spectral is not None else estimate_tempo(envelopes)
    bpm_source = 'audio estimate' if bpm is not None else 'unavailable'
    if tagged_bpm is not None:
        bpm, confidence, bpm_source = tagged_bpm, 1.0, 'file tag'
    crest = sum(crests)/len(crests) if crests else 99.0
    vibe = vibe_from_features(bpm, confidence, crest)
    return {
        'artist': tags.get('artist', ''), 'title': tags.get('title', path.stem),
        'duration': round(duration, 2), 'codec': audio.get('codec_name', ''),
        'genre_tag': tags.get('genre', ''), 'genre': genre, 'genre_source': genre_source,
        'vibe': vibe, 'vibe_source': 'tempo/crest heuristic', 'bpm': bpm,
        'bpm_source': bpm_source, 'pulse_strength': confidence,
        'tempo_method': 'file tag' if tagged_bpm is not None else ('librosa spectral onset' if spectral is not None else 'bass amplitude autocorrelation'),
        'bpm_warning': 'Approximate; half/double tempo and beat-grid errors are possible.' if bpm_source == 'audio estimate' else '',
        'crest_db': round(crest, 2), 'analysis_version': ANALYSIS_VERSION,
    }


def scan(root, state, min_age=30):
    source = root / 'downloads'
    if not source.is_dir() or source.is_symlink():
        raise ValueError('Expected a real downloads folder in the project root.')
    by_path = {t['path']: t for t in state['tracks'].values()}
    errors, analyzed, cached, waiting = [], 0, 0, 0
    for directory, folders, files in os.walk(source, followlinks=False):
        folders[:] = sorted(d for d in folders if not d.startswith('.')
                            and d.casefold() != 'delete_review'
                            and not (Path(directory)/d).is_symlink())
        for filename in sorted(files):
            path = Path(directory)/filename
            if path.suffix.casefold() not in AUDIO or path.is_symlink() or filename.startswith('.'):
                continue
            relative = str(path.relative_to(root))
            try:
                before = signature(path)
                if time.time() - before[3]/1e9 < min_age:
                    waiting += 1
                    continue
                old = by_path.get(relative)
                if old and old['signature'] == before and old.get('analysis_version') == ANALYSIS_VERSION:
                    cached += 1
                    continue
                data = inspect_audio(path)
                if signature(path) != before:
                    waiting += 1
                    continue
                track_id = old['id'] if old else uuid.uuid4().hex[:12]
                data.update(id=track_id, path=relative, signature=before,
                            overrides=old.get('overrides', {}) if old else {})
                state['tracks'][track_id] = data
                analyzed += 1
            except (ValueError, OSError, json.JSONDecodeError) as error:
                errors.append({'path': relative, 'error': str(error)})
    save(root, state)
    return {'analyzed': analyzed, 'cached': cached, 'waiting': waiting, 'errors': errors}


def live_tracks(root, state):
    return [t for t in state['tracks'].values()
            if local_path(root, t['path']).is_file()]


def labels(track):
    override = track.get('overrides', {})
    return override.get('genre', track['genre']), override.get('vibe', LEGACY_VIBES.get(track['vibe'], track['vibe']))


def plan(root, state, layout):
    changes, reserved = [], set()
    for track in sorted(live_tracks(root, state), key=lambda t: t['path']):
        genre, vibe = labels(track)
        parts = [component(genre), component(vibe)] if layout == 'both' else [component(genre if layout == 'genre' else vibe)]
        source = local_path(root, track['path'])
        target = root / 'downloads' / 'organized' / Path(*parts) / source.name
        if target == source:
            reserved.add(str(target).casefold())
            continue
        if target.exists() or target.is_symlink() or str(target).casefold() in reserved:
            target = target.with_name(f'{source.stem[:160]} [{track["id"]}]{source.suffix}')
        if target.exists() or target.is_symlink() or str(target).casefold() in reserved:
            raise ValueError(f'Destination already exists: {target.relative_to(root)}')
        reserved.add(str(target).casefold())
        changes.append({'id': track['id'], 'from': track['path'],
                        'to': str(target.relative_to(root)), 'signature': track['signature']})
    return changes


def move_exclusive(source, target, expected):
    if signature(source) != expected:
        raise ValueError(f'File changed; rescan before moving: {source.name}')
    target.parent.mkdir(parents=True, exist_ok=True)
    # Hardlink+unlink is an exclusive same-filesystem move: never overwrite a file.
    os.link(source, target, follow_symlinks=False)
    try:
        if signature(source) != expected or not os.path.samefile(source, target):
            raise ValueError('File changed during move.')
        source.unlink()
    except BaseException:
        target.unlink()
        raise


def apply_plan(root, state, changes, layout):
    # Preflight the entire batch before changing any music.
    for change in changes:
        source, target = local_path(root, change['from']), local_path(root, change['to'])
        if signature(source) != change['signature'] or target.exists() or target.is_symlink():
            raise ValueError('Files changed since preview. Run sync again.')
    state['layout'] = layout
    if not changes:
        save(root, state)
        return None
    batch = {'id': uuid.uuid4().hex[:12], 'created': time.time(), 'moves': []}
    state['batches'].append(batch)
    for change in changes:
        record = dict(change, status='pending')
        batch['moves'].append(record)
        save(root, state)  # Persist recovery information before touching the source.
        move_exclusive(local_path(root, change['from']), local_path(root, change['to']), change['signature'])
        record['status'] = 'moved'
        state['tracks'][change['id']]['path'] = change['to']
        save(root, state)
    return batch['id']


def undo(root, state, apply):
    batch = next((b for b in reversed(state['batches'])
                  if any(m['status'] != 'undone' for m in b['moves'])), None)
    if batch is None:
        return {'batch': None, 'changes': [], 'applied': False}
    moves = [m for m in reversed(batch['moves']) if m['status'] != 'undone']
    for m in moves:
        source, target = local_path(root, m['from']), local_path(root, m['to'])
        if target.exists():
            if signature(target) != m['signature']:
                raise ValueError(f'Cannot undo a modified file: {m["to"]}')
            if source.exists() and not os.path.samefile(source, target):
                raise ValueError(f'Undo would overwrite: {m["from"]}')
        elif not source.exists() or signature(source) != m['signature']:
            raise ValueError(f'Cannot locate the unchanged track: {m["from"]}')
    if apply:
        for m in moves:
            source, target = local_path(root, m['from']), local_path(root, m['to'])
            if target.exists():
                if source.exists():
                    target.unlink()  # Recover a crash between link and unlink.
                else:
                    move_exclusive(target, source, m['signature'])
            state['tracks'][m['id']]['path'] = m['from']
            m['status'] = 'undone'
            save(root, state)
    return {'batch': batch['id'], 'changes': [
        {'id': m['id'], 'from': m['to'], 'to': m['from']} for m in moves], 'applied': apply}


def sockseek_hook(root, state, path):
    path = path if path.is_absolute() else Path.cwd()/path
    if any(p.is_symlink() and p.parent.resolve().is_relative_to(root)
           for p in (path, *path.parents)):
        raise ValueError('Symlinked music paths are excluded.')
    relative = str(path.resolve().relative_to(root))
    path = local_path(root, relative)
    if path.suffix.casefold() not in AUDIO:
        raise ValueError('Completion hook expects a finished audio file.')
    if any(part.casefold() == 'delete_review' for part in Path(relative).parts):
        return str(path)
    if any(m['status'] == 'pending' for b in state['batches'] for m in b['moves']):
        raise ValueError('Recover the interrupted move with undo --apply first.')
    before = signature(path)
    old = next((t for t in state['tracks'].values() if t['path'] == relative), None)
    track_id = old['id'] if old else uuid.uuid4().hex[:12]
    data = inspect_audio(path)
    if signature(path) != before:
        raise ValueError('Download is still changing; try sync after it finishes.')
    data.update(id=track_id, path=relative, signature=before,
                overrides=old.get('overrides', {}) if old else {})
    state['tracks'][track_id] = data
    save(root, state)
    changes = plan(root, dict(tracks={track_id: data}), state['layout'])
    apply_plan(root, state, changes, state['layout'])
    return str(local_path(root, state['tracks'][track_id]['path']))


def emit(data, as_json):
    if as_json:
        print(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False))
        return
    if 'tracks' in data:
        for t in data['tracks']:
            bpm = f'{t["bpm"]:g}' if t['bpm'] is not None else '?'
            print(f'{t["id"]}  {t["genre"]} / {t["vibe"]}  {bpm} BPM  {t["artist"]} - {t["title"]}')
        print(f'{len(data["tracks"])} track(s).')
    elif 'changes' in data:
        for c in data['changes']:
            print(f'{c["from"]}\n  -> {c["to"]}')
        verb = 'Applied' if data.get('applied') else 'Preview only'
        print(f'{verb}: {len(data["changes"])} move(s).')
        if data.get('batch'):
            print(f'Batch: {data["batch"]}')
        if 'scan' in data:
            s = data['scan']
            print(f'Analysis: {s["analyzed"]} new, {s["cached"]} cached, {s["waiting"]} waiting, {len(s["errors"])} error(s).')
            for e in s['errors']:
                print(f'  Skipped {e["path"]}: {e["error"]}')
    else:
        print(json.dumps(data, ensure_ascii=False, indent=2))


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise argparse.ArgumentTypeError('Expected a finite, nonnegative number.')
    return number


def parser():
    p = argparse.ArgumentParser(description='Sort downloaded DJ tracks into genre/vibe folders without copying them.')
    p.add_argument('--root', type=Path, default=ROOT, help='Project folder (default: the tool location)')
    p.add_argument('--json', action='store_true', help='Machine-readable results and errors')
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('doctor', help='Check local dependencies and catalog status')
    hook = sub.add_parser('sockseek-hook', help='Sort one completed track; emit the Sockseek update-index protocol')
    hook.add_argument('path', type=Path)
    for name in ('scan', 'sync', 'watch'):
        cmd = sub.add_parser(name, help={'scan': 'Analyze completed downloads without moving music',
                                        'sync': 'Preview or apply folder organization',
                                        'watch': 'Keep sorting new downloads until Ctrl-C'}[name])
        cmd.add_argument('--min-age', type=positive, default=60 if name == 'watch' else 30,
                         help='Ignore files modified more recently than this many seconds')
        if name != 'scan':
            cmd.add_argument('--by', choices=('genre', 'vibe', 'both'), help='Folder layout (default: previous layout, initially both)')
            cmd.add_argument('--apply', action='store_true', help='Actually move files; default is preview')
        if name == 'watch':
            cmd.add_argument('--interval', type=positive, default=30, help='Seconds between scans (minimum 5)')
    cmd = sub.add_parser('list', help='Find tracks for a set from the catalog')
    cmd.add_argument('--genre')
    cmd.add_argument('--vibe')
    cmd.add_argument('--min-bpm', type=positive)
    cmd.add_argument('--max-bpm', type=positive)
    cmd = sub.add_parser('label', help='Correct a track label using its ID from list')
    cmd.add_argument('id')
    cmd.add_argument('--genre')
    cmd.add_argument('--vibe')
    cmd.add_argument('--reset', action='store_true', help='Clear manual labels')
    cmd = sub.add_parser('undo', help='Preview or undo the last sorting batch')
    cmd.add_argument('--apply', action='store_true')
    return p


def execute(args):
    root = args.root.resolve()
    if not root.is_dir():
        raise ValueError('Project root does not exist.')
    with catalog(root) as state:
        if args.command == 'doctor':
            return {'ffmpeg': shutil.which('ffmpeg'), 'ffprobe': shutil.which('ffprobe'),
                    'auth': 'not required; offline', 'download_folder': (root/'downloads').is_dir(),
                    'catalog_tracks': len(state['tracks']), 'layout': state['layout'],
                    'pending_moves': [m for b in state['batches'] for m in b['moves'] if m['status'] == 'pending'],
                    'vibes': VIBES}
        if args.command == 'sockseek-hook':
            return {'sockseek_path': sockseek_hook(root, state, args.path)}
        if args.command in ('scan', 'sync', 'watch'):
            if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
                raise ValueError('ffmpeg and ffprobe must be installed and on PATH.')
            if any(m['status'] == 'pending' for b in state['batches'] for m in b['moves']):
                raise ValueError('An interrupted move needs recovery. Run undo, then undo --apply.')
            result = scan(root, state, args.min_age)
            if args.command == 'scan':
                tracks = live_tracks(root, state)
                return dict(result, tracks_total=len(tracks),
                            genres=dict(Counter(labels(t)[0] for t in tracks)),
                            vibes=dict(Counter(labels(t)[1] for t in tracks)))
            layout = args.by or state['layout']
            changes = plan(root, state, layout)
            batch = apply_plan(root, state, changes, layout) if args.apply else None
            return {'changes': changes, 'applied': args.apply, 'batch': batch, 'scan': result}
        if args.command == 'list':
            if args.min_bpm is not None and args.max_bpm is not None and args.min_bpm > args.max_bpm:
                raise ValueError('Minimum BPM must not exceed maximum BPM.')
            tracks = []
            for t in live_tracks(root, state):
                genre, vibe = labels(t)
                if args.genre and args.genre.casefold() not in genre.casefold():
                    continue
                if args.vibe and args.vibe.casefold() not in vibe.casefold():
                    continue
                if args.min_bpm is not None and (t['bpm'] is None or t['bpm'] < args.min_bpm):
                    continue
                if args.max_bpm is not None and (t['bpm'] is None or t['bpm'] > args.max_bpm):
                    continue
                tracks.append(dict(t, genre=genre, vibe=vibe,
                                   genre_source='manual' if 'genre' in t['overrides'] else t['genre_source'],
                                   vibe_source='manual' if 'vibe' in t['overrides'] else t['vibe_source']))
            return {'tracks': sorted(tracks, key=lambda t: (t['genre'], t['vibe'], t['bpm'] or 0, t['title']))}
        if args.command == 'label':
            if args.id not in state['tracks']:
                raise ValueError('Unknown track ID. Use list to find it.')
            if not (args.genre or args.vibe or args.reset):
                raise ValueError('Supply --genre, --vibe, or --reset.')
            overrides = state['tracks'][args.id]['overrides']
            if args.reset:
                overrides.clear()
            for key in ('genre', 'vibe'):
                value = getattr(args, key)
                if value is not None:
                    if not value.strip():
                        raise ValueError('Labels cannot be empty.')
                    overrides[key] = component(value)
            save(root, state)
            return {'id': args.id, 'labels': overrides, 'next': 'sync to preview the updated location'}
        return undo(root, state, args.apply)


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.command == 'watch':
            if not args.json:
                print(f'Watching downloads every {max(5, args.interval):g}s ({"moving files" if args.apply else "preview only"}). Ctrl-C to stop.', file=sys.stderr)
            while True:
                result = execute(args)
                if result['changes'] or result['scan']['analyzed'] or result['scan']['errors']:
                    emit(result, args.json)
                sys.stdout.flush()
                time.sleep(max(5, args.interval))
        else:
            result = execute(args)
            if args.command == 'sockseek-hook':
                print('success;' + result['sockseek_path'])
            else:
                emit(result, args.json)
            if args.command == 'doctor' and (not result['ffmpeg'] or not result['ffprobe'] or not result['download_folder']):
                return 1
            if result.get('errors') or result.get('scan', {}).get('errors'):
                return 1
    except KeyboardInterrupt:
        print('Stopped.' if not args.json else '{"stopped": true}')
        return 130
    except (OSError, ValueError, KeyError) as error:
        if args.json:
            print(json.dumps({'error': str(error)}))
        else:
            print(f'Error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
