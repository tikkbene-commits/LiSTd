"""Native Crate app backend. Local JSON state; one Sockseek track at a time."""
import argparse
import csv
import contextlib
import difflib
import fcntl
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unicodedata
import uuid
from urllib.parse import quote

import music_sorter as sorter

ROOT = Path(__file__).resolve().parent
LOSSLESS = {'flac', 'alac', 'wavpack'}


@contextlib.contextmanager
def account_config(credentials):
    """Sockseek needs a config file; keep Keychain input outside the workspace."""
    if credentials is None:
        yield None
        return
    if not isinstance(credentials, dict):
        raise ValueError('Enter a Soulseek username and password.')
    for key in ('username', 'password'):
        value = credentials.get(key)
        if not isinstance(value, str) or not value.strip() or len(value) > 1024 or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError('Enter a Soulseek username and password without control characters.')
    with tempfile.TemporaryDirectory(prefix='listd-account-') as folder:
        path = Path(folder)/'sockseek.conf'
        with path.open('x', encoding='utf-8') as config:
            os.chmod(path, 0o600)
            for key in ('username', 'password'):
                config.write(f'{key} = "{credentials[key]}"\n')
        try:
            yield path
        finally:
            path.unlink(missing_ok=True)


def check_login(credentials):
    with account_config(credentials) as config:
        # A print-only search exercises Sockseek's real login without transferring audio.
        command = ['sockseek', 'LiStD connection check', '-s', '--config', str(config),
                   '--print', 'results', '--search-timeout', '1', '--connect-timeout', '15000',
                   '--no-listen', '--verbose', '--no-progress']
        try:
            result = subprocess.run(command, capture_output=True, timeout=35)
        except subprocess.TimeoutExpired:
            raise ValueError('Soulseek did not respond. Check your connection and try again.') from None
        output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
        # A print-only search can exit 1 for no matches after authenticating successfully.
        if f'Logged in as {credentials["username"]}' not in output:
            raise ValueError('Could not sign in to Soulseek. Check your username, password and connection. Close any other client using this account.')
    return {'authenticated': True}


def completion_command(root, job_id, index):
    executable = f'"{sys.executable}"'
    if not getattr(sys, 'frozen', False):
        executable += f' "{Path(__file__).resolve()}"'
    return (f'when=success scope=track lock update-index -- {executable} '
            f'--root "{root}" hook {job_id} {index} "{{path}}"')


def atomic_json(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=path.parent, delete=False, encoding='utf-8') as f:
        temporary = Path(f.name)
        try:
            json.dump(data, f, ensure_ascii=False, allow_nan=False)
            f.flush()
            os.fsync(f.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def job_dir(root, job_id):
    if not re.fullmatch(r'[0-9a-f]{12}', job_id):
        raise ValueError('Invalid import ID.')
    return root/'.music-sorter/crate/jobs'/job_id


def load_job(root, job_id):
    return json.loads((job_dir(root, job_id)/'job.json').read_text())


def save_job(root, job):
    job['updated'] = time.time()
    atomic_json(job_dir(root, job['id'])/'job.json', job)


def write_job_input(root, job):
    """Keep corrected search fields separate from the untouched source rows."""
    fields = list(job['tracks'][0]['original'])
    with tempfile.NamedTemporaryFile('w', dir=job_dir(root, job['id']), delete=False,
                                     newline='', encoding='utf-8') as f:
        temporary = Path(f.name)
        try:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            for row in job['tracks']:
                raw = dict(row['original'])
                for field in fields:
                    if field.strip().casefold() in ('artist', 'title'):
                        raw[field] = row[field.strip().casefold()]
                writer.writerow(raw)
            f.flush()
            os.fsync(f.fileno())
            os.replace(temporary, job_dir(root, job['id'])/'input.csv')
        finally:
            temporary.unlink(missing_ok=True)


def update_owned_indexes(folder, old_path, new_path):
    for path in folder.glob('*index*.csv'):
        with path.open(newline='', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            fields, rows = reader.fieldnames, list(reader)
        if not fields or 'filepath' not in fields:
            continue
        changed = False
        for row in rows:
            if row['filepath'] == old_path:
                row['filepath'], changed = new_path, True
        if changed:
            with tempfile.NamedTemporaryFile('w', dir=folder, delete=False, newline='', encoding='utf-8') as f:
                temporary = Path(f.name)
                try:
                    writer = csv.DictWriter(f, fieldnames=fields)
                    writer.writeheader()
                    writer.writerows(rows)
                    f.flush()
                    os.fsync(f.fileno())
                    os.replace(temporary, path)
                finally:
                    temporary.unlink(missing_ok=True)


def seconds(value):
    if not value or str(value).strip() in ('-1', '0'):
        return None
    parts = str(value).strip().split(':')
    try:
        result = sum(float(n)*60**i for i, n in enumerate(reversed(parts)))
    except ValueError:
        raise ValueError('Track durations must be seconds or mm:ss / hh:mm:ss.')
    if not math.isfinite(result) or result < 0:
        raise ValueError('Invalid track duration.')
    return result


def parse_tracklist(text, order='artist-title'):
    if len(text) > 2_000_000:
        raise ValueError('Tracklist is too large (maximum 2 MB).')
    text = text.lstrip('\ufeff').strip()
    if not text:
        raise ValueError('Drop a CSV/text file or paste a tracklist first.')
    first = text.splitlines()[0]
    delimiter = next((d for d in (',', '\t', ';')
                      if {'artist', 'title'}.issubset({x.strip().casefold().strip('"') for x in first.split(d)})), None)
    rows, fields = [], []
    if delimiter:
        reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
        fields = list(reader.fieldnames or [])
        names = {f.strip().casefold(): f for f in fields}
        if len(names) != len(fields):
            raise ValueError('CSV column names must be unique.')
        for line, raw in enumerate(reader, 2):
            if None in raw:
                raise ValueError(f'CSV row {line} has extra fields. Quote titles containing commas.')
            artist, title = raw[names['artist']], raw[names['title']]
            if not artist or not title or not artist.strip() or not title.strip():
                raise ValueError(f'CSV row {line} needs an artist and a title.')
            length = next((raw[names[k]] for k in ('length', 'duration') if k in names), '')
            rows.append({'artist': artist, 'title': title, 'length': seconds(length),
                         'cue': raw.get(names.get('setstart', ''), '') or '', 'original': raw})
    else:
        text = re.sub(r'\[([^\]]+)\]\(https?://[^)]+\)', r'\1', text)
        text = re.sub(r'https?://[^\s)\]]+', '', text)
        # Pasted YouTube chapters can arrive as a single line.
        text = re.sub(r'(?<!\d)(\[?\d{1,2}:\d{2}(?::\d{2})?\]?)', r'\n\1', text)
        fields = ['Artist', 'Title', 'SetStart']
        for line, value in enumerate(text.splitlines(), 1):
            value = value.strip()
            if not value or not any(c.isalnum() for c in value):
                continue
            match = re.match(r'^\[?(\d{1,2}:\d{2}(?::\d{2})?)\]?\s*(.*)', value)
            cue, content = match.groups() if match else ('', value)
            pair = re.split(r'\s+[-–—]\s+', content, maxsplit=1)
            if len(pair) != 2 or not all(x.strip() for x in pair):
                raise ValueError(f'Line {line}: use Artist - Title or choose Title - Artist.')
            artist, title = pair if order == 'artist-title' else pair[::-1]
            raw = {'Artist': artist.strip(), 'Title': title.strip(), 'SetStart': cue}
            rows.append({'artist': raw['Artist'], 'title': raw['Title'], 'length': None,
                         'cue': cue, 'original': raw})
    if not rows or len(rows) > 500:
        raise ValueError('Import between 1 and 500 tracks at a time.')
    for index, row in enumerate(rows):
        if any(ord(c) < 32 for c in row['artist']+row['title']):
            raise ValueError('Artist and title fields cannot contain control characters.')
        row.update(index=index, status='queued', note='Waiting to search', path='', genre='', vibe='', bpm=None)
    return rows, fields


def create_job(root, text, name, order, minimum):
    rows, fields = parse_tracklist(text, order)
    job = {'id': uuid.uuid4().hex[:12], 'name': name.strip() or 'Untitled import',
           'created': time.time(), 'status': 'queued', 'minimum': minimum, 'tracks': rows,
           'message': 'Ready to download', 'source': next((r['original'].get('SourceURL', '') for r in rows), '')}
    folder = job_dir(root, job['id'])
    folder.mkdir(mode=0o700, parents=True)
    (folder/'original.txt').write_text(text, encoding='utf-8')
    # Preserve every CSV field, including supplied durations; chapter cues are never durations.
    write_job_input(root, job)
    save_job(root, job)
    return job


def normalize(value):
    value = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode().casefold()
    return ' '.join(re.findall(r'[a-z0-9]+', value.replace('&', ' and ')))


def title_key(value):
    value = re.sub(r'(?i)[\[(]\s*original(?: mix| version)?\s*[\])]', '', value)
    return normalize(value)


def filename_title_matches(path, row):
    title, artist = title_key(row['title']), normalize(row['artist'])
    key = title_key(path.stem)
    allowed = {title, artist+' '+title, title+' '+artist}
    return key in allowed or re.sub(r'^(?:\d+\s+)+', '', key) in allowed


def probe(path):
    raw = sorter.run_media(['ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe',
                           '-show_format', '-show_streams', '-of', 'json', str(path)])
    data = json.loads(raw)
    stream = next((s for s in data.get('streams', []) if s.get('codec_type') == 'audio'), None)
    if stream is None:
        raise ValueError('No audio stream.')
    fmt = data.get('format', {})
    tags = {k.casefold(): str(v) for source in (stream.get('tags', {}), fmt.get('tags', {})) for k, v in source.items()}
    duration = float(fmt.get('duration') or stream.get('duration') or 0)
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('Missing audio duration.')
    return {'codec': stream.get('codec_name', ''), 'duration': duration, 'tags': tags}


def verify(path, row, minimum):
    data = probe(path)
    tags = data['tags']
    if data['codec'] not in LOSSLESS | {'mp3'} and not data['codec'].startswith('pcm_'):
        raise ValueError('Audio codec is outside the selected MP3/lossless formats.')
    if row.get('deep_search'):
        evidence = deep_identity(str(path), row, tags)
        if evidence != 'confident':
            raise ValueError('Deep-search identity needs review: filename/tags do not establish the original artist, title and version.')
    elif tags.get('title') and title_key(tags['title']) != title_key(row['title']):
        raise ValueError(f'Title tag differs: {tags["title"]}')
    if not row.get('deep_search') and tags.get('artist') and normalize(tags['artist']) != normalize(row['artist']):
        raise ValueError(f'Artist tag differs: {tags["artist"]}')
    name = normalize(path.stem)
    if not row.get('deep_search') and not tags.get('title') and not filename_title_matches(path, row):
        raise ValueError('No matching title tag or filename evidence.')
    if not row.get('deep_search') and not tags.get('artist') and normalize(row['artist']) not in name:
        raise ValueError('No matching artist tag or filename evidence.')
    if row.get('length') and abs(data['duration']-row['length']) > 3:
        raise ValueError('Duration differs from the supplied track duration.')
    lossless = data['codec'] in LOSSLESS or data['codec'].startswith('pcm_')
    measured = None
    if not lossless:
        raw = sorter.run_media(['ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe',
            '-select_streams', 'a:0', '-show_entries', 'packet=size,duration_time', '-of', 'json', str(path)])
        packets = json.loads(raw).get('packets', [])
        duration = sum(float(p.get('duration_time', 0)) for p in packets)
        size = sum(int(p.get('size', 0)) for p in packets)
        if duration <= 0 or size <= 0:
            raise ValueError('Cannot measure the audio bitrate.')
        measured = round(size*8/duration/1000, 2)
        if measured < minimum:
            raise ValueError(f'Measured bitrate {measured:g} kbps is below {minimum} kbps.')
    data.update(lossless=lossless, measured_kbps=measured)
    sorter.run_media(['ffmpeg', '-v', 'error', '-xerror', '-nostdin', '-protocol_whitelist', 'file,pipe',
                      '-i', str(path), '-map', '0:a:0', '-f', 'null', '-'])
    return data


def finish_track(root, job, row, path):
    checked = verify(path, row, job['minimum'])
    # Quality and identity checks happen before the existing organizer may move audio.
    with sorter.catalog(root) as state:
        destination = sorter.sockseek_hook(root, state, path)
        track = next(t for t in state['tracks'].values() if str(root/t['path']) == destination)
        genre, vibe = sorter.labels(track)
    return {'status': 'ready', 'path': destination, 'track_id': track['id'], 'genre': genre,
            'vibe': vibe, 'bpm': track['bpm'], 'bpm_source': track['bpm_source'],
            'note': 'Genre needs review' if genre == 'Unsorted' else 'Downloaded and organized',
            'quality': 'Lossless' if checked['lossless'] else f'{checked["measured_kbps"]:g} kbps',
            'verification': {k: v for k, v in checked.items() if k != 'tags'}}


def complete_hook(root, job_id, index, path):
    job = load_job(root, job_id)
    row = job['tracks'][index]
    path = path.resolve()
    staging = root/'downloads/.incoming'/job_id
    if not path.is_relative_to(staging) or not path.is_file() or path.is_symlink():
        raise ValueError('Completion path is outside this import.')
    row.update(status='checking', note='Checking file quality and tags')
    save_job(root, job)
    result_path = job_dir(root, job_id)/f'hook-{index}.json'
    try:
        result = finish_track(root, job, row, path)
    except (ValueError, OSError) as error:
        result = {'status': 'review', 'note': str(error), 'path': str(path)}
    atomic_json(result_path, result)
    # A rejected file stays in the staging area. It never counts as organized.
    return result.get('path', str(path))


def review_path(root, job, row):
    path = Path(row['path'])
    staging = root/'downloads/.incoming'/job['id']
    if (not row['path'] or path.is_symlink() or not path.is_file()
            or not path.resolve().is_relative_to(staging)):
        raise ValueError('No staged file to review for this track.')
    return path


def recheck_track(root, job, row):
    path = review_path(root, job, row)
    try:
        result = finish_track(root, job, row, path)
    except (ValueError, OSError) as error:
        result = {'status': 'review', 'note': str(error), 'path': str(path)}
    row.update(result)
    folder = job_dir(root, job['id'])
    atomic_json(folder/f'hook-{row["index"]}.json', result)
    update_owned_indexes(folder, str(path), result['path'])
    save_job(root, job)


def correct_import(root, job_id, index=None, artist=None, title=None):
    # Use the import lock so a UI correction cannot race a transfer or its hook.
    with (root/'.music-sorter/crate/download.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Wait until the current import finishes before reviewing tracks.')
        job = load_job(root, job_id)
        if index is None:
            if any(r['status'] in ('ready', 'existing') for r in job['tracks']):
                raise ValueError('Only swap an import before any tracks have been accepted.')
            rows = job['tracks']
            for row in rows:
                row['artist'], row['title'] = row['title'], row['artist']
        else:
            if not 0 <= index < len(job['tracks']):
                raise ValueError('Invalid track index.')
            row = job['tracks'][index]
            review_path(root, job, row)
            if row['status'] != 'review':
                raise ValueError('This track is no longer awaiting review.')
            if not artist.strip() or not title.strip() or any(ord(c) < 32 for c in artist+title):
                raise ValueError('Artist and title must be nonempty and contain no control characters.')
            row.update(artist=artist.strip(), title=title.strip())
            rows = [row]
        save_job(root, job)
        write_job_input(root, job)
        for row in rows:
            if row['status'] == 'review' and row.get('path'):
                try:
                    recheck_track(root, job, row)
                except ValueError as error:
                    row['note'] = str(error)
                    save_job(root, job)
        return job


def existing_track(root, row, minimum):
    path = root/'.music-sorter/catalog.json'
    cached = json.loads(path.read_text()).get('tracks', {}) if path.exists() else {}
    candidates = [root/t['path'] for t in cached.values()
                  if normalize(t.get('artist', '')) == normalize(row['artist'])
                  and title_key(t.get('title', '')) == title_key(row['title'])]
    library = root/'juan music'
    if library.is_dir():
        candidates += [p for p in library.rglob('*') if p.suffix.casefold() in sorter.AUDIO
                       and normalize(row['artist']) in normalize(p.stem)
                       and title_key(row['title']) in normalize(p.stem)]
    for candidate in candidates:
        if candidate.is_file() and not candidate.is_symlink():
            try:
                checked = verify(candidate, row, minimum)
                return {'status': 'existing', 'path': str(candidate), 'note': 'Already in your library',
                        'quality': 'Lossless' if checked['lossless'] else f'{checked["measured_kbps"]:g} kbps'}
            except (ValueError, OSError):
                continue
    return None


def base_command(root, job, index):
    folder = job_dir(root, job['id'])
    command = ['sockseek', str(folder/'input.csv'), '--input-type', 'csv', '--offset', str(index), '--number', '1',
               '--concurrent-jobs', '1', '--concurrent-searches', '1', '--skip-music-dir', str(root/'juan music'),
               '--format', 'mp3,flac,wav,aif,aiff,alac', '--min-bitrate', str(job['minimum']),
               '--strict-conditions', '--strict-title', '--strict-artist', '--search-timeout', '8000',
               '--max-stale-time', '15000', '--max-retries', '2', '--unknown-error-retries', '1',
               '--no-progress', '--progress-json']
    # CSV headers are kept verbatim. Tell Sockseek the duration column when it is named Duration.
    fields = job['tracks'][index]['original']
    headers = {key.strip().casefold(): key for key in fields}
    command += ['--artist-col', headers['artist'], '--title-col', headers['title']]
    key = next((headers[k] for k in ('length', 'duration') if k in headers), None)
    if key:
        command += ['--length-col', key]
        if ':' in str(fields[key]):
            command += ['--time-format', 'h:m:s' if str(fields[key]).count(':') == 2 else 'm:s']
    if job.get('_remote'):
        command += ['--remote', job['_remote'], '--no-config']
    return command


@contextlib.contextmanager
def managed_engine(root, config=None):
    # One owned session avoids reconnecting Soulseek and rebuilding peer sockets per row.
    with socket.socket() as available:
        available.bind(('127.0.0.1', 0))
        port = available.getsockname()[1]
    with (root/'.music-sorter/crate/engine.log').open('w') as log:
        command = ['sockseek', 'daemon', '--server-ip', '127.0.0.1', '--server-port', str(port)]
        if config is not None:
            command += ['--config', str(config)]
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            started = time.monotonic()
            while True:
                if process.poll() is not None or time.monotonic()-started > 30:
                    raise ValueError('Sockseek could not start. Check its local configuration and connection.')
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.3):
                        break
                except OSError:
                    time.sleep(0.25)
            yield f'http://127.0.0.1:{port}'
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


def run_process(command, log_path, cancel_path, timeout=180):
    with log_path.open('w') as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        started = time.monotonic()
        while process.poll() is None:
            oversized = log_path.stat().st_size > 8_000_000
            if cancel_path.exists() or oversized or time.monotonic()-started > timeout:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                return 'cancelled' if cancel_path.exists() else 'too many results' if oversized else 'timeout'
            time.sleep(0.25)
        return process.returncode


def candidate_matches(candidate, row):
    filename = candidate.get('File', {}).get('Filename', '')
    leaf = filename.replace('\\', '/').rsplit('/', 1)[-1].rsplit('.', 1)[0]
    leaf_key = title_key(leaf)
    title, artist = title_key(row['title']), normalize(row['artist'])
    if title not in leaf_key or artist not in normalize(filename):
        return False
    extras = set(leaf_key.split()) - set(title.split()) - set(artist.split())
    return not extras.intersection({'remix', 'mix', 'edit', 'instrumental', 'version', 'dub', 'live', 'radio'})


# Version words are never discarded by normalization or spelling matching.
VERSION_WORDS = {'remix', 'mix', 'edit', 'instrumental', 'version', 'dub', 'live', 'radio',
                 'extended', 'bootleg', 'rework', 'remaster', 'remastered', 'acapella', 'vip', 'vocal'}
MISSING = {'unavailable', 'stopped'}


def release_terms(row):
    return [normalize(str(value)) for key, value in row.get('original', {}).items()
            if normalize(key) in {'album', 'release', 'catalog', 'catalogue', 'catalog number', 'catalogue number', 'catno'} and value]


def phrase_in(phrase, text):
    return bool(phrase) and f' {phrase} ' in f' {text} '


def deep_identity(filename, row, tags=None):
    """Broader placement is OK; fuzzy spelling and unexplained words require review."""
    tags = tags or {}
    leaf = filename.replace('\\', '/').rsplit('/', 1)[-1].rsplit('.', 1)[0]
    title, artist = title_key(row['title']), normalize(row['artist'])
    leaf_key = title_key(leaf)
    title_tag, artist_tag = title_key(tags.get('title', '')), normalize(tags.get('artist', ''))
    evidence = ' '.join([title_key(filename), title_tag, artist_tag])
    # A version word absent from the requested title cannot be excused by album evidence.
    requested_versions = set(title.split()) & VERSION_WORDS
    for source in (leaf_key, title_tag):
        without_artist = (' ' + source + ' ').replace(' ' + artist + ' ', ' ', 1)
        extras = (set(without_artist.split()) & VERSION_WORDS) - requested_versions
        if extras:
            return 'reject'
    title_sources = [leaf_key, title_tag, artist_tag]
    exact_title = any(phrase_in(title, source) for source in title_sources)
    exact_artist = phrase_in(artist, evidence)
    allowed = set((title + ' ' + artist + ' ' + ' '.join(release_terms(row))).split())
    def unexplained(source):
        return {word for word in source.split() if not word.isdigit()} - allowed
    # Conflicting tags stay uncertain even when a peer filename looks exact.
    if exact_title and exact_artist and not any(unexplained(source) for source in (leaf_key, title_tag, artist_tag)):
        return 'confident'
    def similar_phrase(expected, source):
        words, actual = expected.split(), source.split()
        if not words:
            return False
        for offset in range(max(0, len(actual) - len(words) + 1)):
            differences = 0
            for wanted, found in zip(words, actual[offset:offset+len(words)]):
                if wanted == found:
                    continue
                if (wanted in VERSION_WORDS or found in VERSION_WORDS or min(len(wanted), len(found)) < 5
                        or abs(len(wanted)-len(found)) > 1
                        or difflib.SequenceMatcher(None, wanted, found).ratio() < 0.88):
                    break
                differences += 1
            else:
                if differences <= 1:
                    return True
        return False
    if ((exact_title or any(similar_phrase(title, source) for source in title_sources))
            and (exact_artist or similar_phrase(artist, evidence))):
        return 'review'
    return 'reject'


def deep_queries(row):
    artist, title = normalize(row['artist']), normalize(row['title'])
    queries = [artist + ' ' + title, title + ' ' + artist, title]
    for release in release_terms(row):
        queries.extend([title + ' ' + release, artist + ' ' + release])
    # One omitted long word can retrieve a one-character misspelling; identity still needs review.
    words = (artist + ' ' + title).split()
    if len(words) >= 3:
        longest = max(range(len(words)), key=lambda i: len(words[i]))
        queries.append(' '.join(words[:longest] + words[longest+1:]))
    return list(dict.fromkeys(q for q in queries if q.strip()))[:6]


def deep_search_candidates(root, job, index, cancel):
    row, folder = job['tracks'][index], job_dir(root, job['id'])
    found, uncertain, seen = [], [], set()
    queries = deep_queries(row)
    row['candidates'], row['candidate_results'] = [], []
    for number, query in enumerate(queries):
        if cancel.exists():
            break
        row.update(status='searching', note=f'Deep search {number+1}/{len(queries)} · {query}')
        job['message'] = f'{index+1}/{len(job["tracks"])} · {row["artist"]} — {row["title"]} · {row["note"]}'
        save_job(root, job)
        search_file = folder/f'deep-{index}.csv'
        with search_file.open('w', newline='', encoding='utf-8') as handle:
            writer = csv.writer(handle)
            writer.writerow(['Artist', 'Title', 'Length'])
            writer.writerow(['', query, row.get('length') or ''])
        command = base_command(root, job, index)
        command[1] = str(search_file)
        for option, value in [('--offset', '0'), ('--artist-col', 'Artist'), ('--title-col', 'Title')]:
            command[command.index(option)+1] = value
        for option in ('--length-col', '--time-format'):
            if option in command:
                position = command.index(option)
                del command[position:position+2]
        command += ['--length-col', 'Length', '--time-format', 's', '--strict-title', 'false',
                    '--strict-artist', 'false', '--no-write-index', '--print', 'json-all']
        log = folder/f'deep-{index}-{number}.jsonlog'
        result = run_process(command, log, cancel, timeout=45)
        if cancel.exists():
            break
        data = read_candidates(log, result)
        for candidate in data[:200]:
            filename = candidate.get('File', {}).get('Filename', '')
            username = candidate.get('User', {}).get('Username', '')
            key = (username, filename)
            if not filename or not username or key in seen:
                continue
            seen.add(key)
            length = candidate['File'].get('Length')
            if (row.get('length') and isinstance(length, (int, float)) and math.isfinite(length)
                    and length > 0 and abs(length - row['length']) > 3):
                continue
            identity = deep_identity(filename, row)
            if identity == 'confident':
                found.append(candidate)
            elif identity == 'review' and len(uncertain) < 20:
                uncertain.append(candidate)
        if len(found) >= 3:
            break
    row['candidate_results'] = uncertain
    row['candidates'] = [dict(number=i, filename=c['File']['Filename'], username=c['User']['Username'],
                              reason='Spelling, extra words or metadata placement need confirmation')
                         for i, c in enumerate(uncertain)]
    return found[:3]


def retry_rows(job, deep=False, index=None, candidate=None):
    if not deep:
        if index is not None or candidate is not None:
            raise ValueError('Track/candidate selection requires Deep search.')
        return job['tracks']
    rows = job['tracks']
    if index is not None:
        if not 0 <= index < len(rows):
            raise ValueError('Invalid track index.')
        rows = [rows[index]]
    elif candidate is not None:
        raise ValueError('Select an individual track before choosing a candidate.')
    rows = [r for r in rows if not (r.get('path') and Path(r['path']).is_file()) and
            (r['status'] in MISSING or (r['status'] == 'review' and not r.get('path') and r.get('candidates')))]
    if candidate is not None:
        if not rows or not 0 <= candidate < len(rows[0].get('candidate_results', [])):
            raise ValueError('Candidate no longer available. Deep search again.')
    if not rows:
        raise ValueError('No missing tracks to deep search. Accepted and staged review files are preserved.')
    return rows


def read_candidates(log, result):
    if log.stat().st_size > 8_000_000:
        raise ValueError('Search returned too many results. Try a more specific title or release.')
    text = log.read_text(errors='replace')
    for line in text.splitlines():
        if line.startswith('[{') or line == '[]':
            data = json.loads(line)
            if isinstance(data, list):
                return data
    if 'exception' in text.casefold() or 'error' in text.casefold() or result not in (0, 1):
        raise ValueError('The Soulseek connection failed. Retry when the network settles.')
    return []


def search_candidates(root, job, index, cancel):
    log = job_dir(root, job['id'])/f'search-{index}.jsonlog'
    result = run_process(base_command(root, job, index) + ['--print', 'json-all'], log, cancel, timeout=60)
    return [c for c in read_candidates(log, result) if candidate_matches(c, job['tracks'][index])]


def run_job(root, job_id, credentials=None, deep=False, index=None, candidate=None):
    folder = job_dir(root, job_id)
    with (root/'.music-sorter/crate/download.lock').open('a') as lock, contextlib.ExitStack() as stack:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Another import is downloading. Wait for it or stop it first.')
        job = load_job(root, job_id)
        rows = retry_rows(job, deep, index, candidate)
        selected_candidate = rows[0]['candidate_results'][candidate] if candidate is not None else None
        if not shutil.which('sockseek') or not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
            raise ValueError('Sockseek and FFmpeg must be installed.')
        config = stack.enter_context(account_config(credentials))
        job['_remote'] = stack.enter_context(managed_engine(root, config))
        cancel = folder/'cancel'
        cancel.unlink(missing_ok=True)
        job.update(status='running', message='Searching Soulseek', pid=os.getpid())
        save_job(root, job)
        for row in rows:
            if cancel.exists():
                break
            if row['status'] in ('ready', 'existing') and Path(row['path']).is_file():
                continue
            existing = existing_track(root, row, job['minimum'])
            if existing:
                row.update(existing)
                save_job(root, job)
                continue
            index = row['index']
            if not deep:
                row.update(candidates=[], candidate_results=[])
            row.update(status='searching', note='Searching for an exact match', deep_search=deep)
            job['message'] = f'{index+1} of {len(job["tracks"])} · {row["artist"]} — {row["title"]}'
            save_job(root, job)
            try:
                candidates = ([selected_candidate] if selected_candidate else deep_search_candidates(root, job, index, cancel)) if deep else search_candidates(root, job, index, cancel)
            except ValueError as error:
                row.update(status='unavailable', note=str(error))
                save_job(root, job)
                continue
            if cancel.exists():
                row.update(status='stopped', note='Stopped')
                save_job(root, job)
                break
            if not candidates:
                row.update(status='review' if row.get('candidates') else 'unavailable', note='Deep search found candidates needing review.' if row.get('candidates') else 'No exact original-version match at this quality. Try Deep search or supply release information.')
                save_job(root, job)
                continue
            row.update(status='downloading', note='Downloading an exact candidate')
            save_job(root, job)
            hook_result = folder/f'hook-{index}.json'
            hook = completion_command(root, job_id, index)
            row.update(status='unavailable', note='No peer completed the transfer. Retry to search again.')
            for attempt, candidate in enumerate(candidates[:3]):
                hook_result.unlink(missing_ok=True)
                remote = candidate['File']['Filename'].replace('\\', '/')
                link = 'slsk://' + quote(candidate['User']['Username'], safe='') + '/' + quote(remote, safe='/')
                command = ['sockseek', link, '-s', '--concurrent-jobs', '1', '--concurrent-searches', '1',
                           '--remote', job['_remote'], '--no-config',
                           '--skip-music-dir', str(root/'juan music'), '--max-stale-time', '15000',
                           '--max-retries', '1', '--unknown-error-retries', '1', '--no-progress', '--progress-json',
                           '-o', str(root/'downloads/.incoming'/job_id/f'{index}-{attempt}'), '--index-path', str(folder/f'index-{index}.csv'),
                           '--on-complete', hook]
                result = run_process(command, folder/f'track-{index}-{attempt}.log', cancel)
                if hook_result.exists():
                    row.update(json.loads(hook_result.read_text()))
                    if row['status'] == 'ready':
                        row.update(candidates=[], candidate_results=[])
                        break
                if result == 'cancelled':
                    row.update(status='stopped', note='Stopped')
                    break
            save_job(root, job)
            # Only incomplete transfers from this job are disposable, after its process exits.
            for remnant in (root/'downloads/.incoming'/job_id).rglob('*.incomplete'):
                if remnant.is_file() and not remnant.is_symlink():
                    remnant.unlink()
        job.update(status='stopped' if cancel.exists() else 'finished', message='Stopped' if cancel.exists() else 'Import finished')
        save_job(root, job)
        return job


def snapshot(root):
    jobs = []
    for path in (root/'.music-sorter/crate/jobs').glob('*/job.json'):
        job = json.loads(path.read_text())
        if job['status'] == 'running':
            try:
                pid = job.get('pid')
                if not isinstance(pid, int) or pid <= 0:
                    raise ProcessLookupError
                os.kill(pid, 0)
            except (ProcessLookupError, PermissionError):
                job['status'], job['message'] = 'stopped', 'Interrupted. Retry to continue.'
        jobs.append(job)
    jobs.sort(key=lambda j: j['created'], reverse=True)
    path = root/'.music-sorter/catalog.json'
    data = json.loads(path.read_text()) if path.exists() else {'tracks': {}}
    library = []
    for track in data['tracks'].values():
        if (root/track['path']).is_file():
            genre, vibe = sorter.labels(track)
            audio = root/track['path']
            membership = [job for job in jobs if any(
                row.get('track_id') == track['id'] or row.get('path') == str(audio)
                for row in job['tracks'])]
            parent = audio.parent
            download_folder = str(parent.relative_to(root/'downloads')) if parent.is_relative_to(root/'downloads') else 'Outside downloads'
            if download_folder == '.':
                download_folder = 'Downloads root'
            stat = audio.stat()
            # Old catalogs have no insertion time; import records, then file birth time are read-only fallbacks.
            added = track.get('added_at') or min((job['created'] for job in membership), default=getattr(stat, 'st_birthtime', stat.st_mtime))
            library.append(dict(track, genre=genre, vibe=vibe, path=str(audio),
                                download_folder=download_folder, imports=[f'{job["name"]} · {job["id"][:6]}' for job in membership], added_at=added))
    current = {t['id']: t for t in library}
    for job in jobs:
        for row in job['tracks']:
            track = current.get(row.get('track_id'))
            if track and row['status'] == 'ready':
                row.update({k: track[k] for k in ('path', 'genre', 'vibe', 'bpm')})
                if not Path(track['path']).is_relative_to(root/'downloads/organized'):
                    row.update(status='review', note='Moved outside organized folders. Check the file location.')
            elif row['status'] in ('ready', 'existing') and not Path(row['path']).is_file():
                row.update(status='review', note='File moved or missing. Retry to check the library.')
    return {'jobs': jobs, 'library': library, 'root': str(root),
            'ready': bool(shutil.which('sockseek') and shutil.which('ffmpeg') and shutil.which('ffprobe')),
            'configured': (Path.home()/'.config/sockseek/sockseek.conf').is_file()}


def deck_analysis(path, bpm=None, refine_bpm=False):
    """Read-only beat estimate for auditioning; never updates the organizer catalog."""
    import array
    if bpm is not None and (not math.isfinite(bpm) or not 40 <= bpm <= 250):
        raise ValueError('BPM must be between 40 and 250.')
    raw = sorter.run_media([
        'ffmpeg', '-v', 'error', '-nostdin', '-protocol_whitelist', 'file,pipe',
        '-i', str(path.resolve()), '-t', '90', '-map', '0:a:0', '-vn', '-ac', '1',
        '-ar', '8000', '-f', 's16le', 'pipe:1'])
    samples = array.array('h')
    samples.frombytes(raw)
    if sys.byteorder != 'little':
        samples.byteswap()
    if len(samples) < 8000:
        return {'bpm': bpm, 'cue': None, 'note': 'Too short to estimate beats; set a beat cue manually'}
    librosa, np = sorter.audio_modules()
    onset = librosa.onset.onset_strength(y=np.asarray(samples, dtype=np.float32)/32768,
                                        sr=8000, hop_length=80, n_fft=512, n_mels=64)
    automatic_bpm = bpm is None or refine_bpm
    if bpm is None:
        bpm, _ = sorter.spectral_tempo([samples], onset_envelopes=[onset])
    if bpm is None:
        return {'bpm': None, 'cue': None, 'note': 'No steady pulse found; enter BPM and set a beat cue'}
    if float(onset.max()) < 0.01:
        return {'bpm': bpm, 'cue': None, 'note': 'No clear beat found; set a beat cue manually'}
    _, beats = librosa.beat.beat_track(onset_envelope=onset, sr=8000, hop_length=80, bpm=bpm, trim=True)
    if len(beats) < 16:
        return {'bpm': bpm, 'cue': None, 'note': 'Too few steady beats; set BPM and a beat cue manually'}
    times = beats.astype(float) * 0.01
    # Breakdowns can add/drop a detected beat: estimate locally, then assign grid numbers.
    periods = [float(np.polyfit(np.arange(16), times[start:start+16], 1)[0])
               for start in range(0, len(times)-15, 8)]
    period = float(np.median(periods))
    refined = 60 / period
    if automatic_bpm and 40 <= refined <= 250 and abs(refined / bpm - 1) < 0.05:
        bpm = float(refined)
    strengths = onset[beats]
    strong = strengths >= np.median(strengths)
    anchor = times[int(np.argmax(strengths))]
    period = 60 / bpm
    for _ in range(2):
        indices = np.rint((times - anchor) / period)
        cue = float(np.median(times[strong] - indices[strong] * period))
        residual = np.abs(times - (cue + indices * period))
        good = strong & (residual < 0.06)
        if automatic_bpm and np.count_nonzero(good) >= 8:
            fitted_period, fitted_cue = np.polyfit(indices[good], times[good], 1)
            if abs(fitted_period / period - 1) < 0.05:
                period, cue = float(fitted_period), float(fitted_cue)
    residual = np.abs(times - (cue + np.rint((times - cue) / period) * period))
    if float(np.percentile(residual[strong], 90)) > 0.06:
        return {'bpm': bpm, 'cue': None, 'note': 'Beat grid is uncertain; check BPM and set a beat cue manually'}
    if automatic_bpm:
        bpm = 60 / period
    # shortcut: this is a fixed-tempo grid; live drums still need manual nudging or re-sync.
    cue %= period
    return {'bpm': float(bpm), 'cue': cue,
            'note': 'Fitted beat grid · check by ear'}


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, default=ROOT)
    sub = p.add_subparsers(dest='command', required=True)
    sub.add_parser('snapshot')
    sub.add_parser('login')
    analysis = sub.add_parser('deck-analysis')
    analysis.add_argument('path', type=Path)
    analysis.add_argument('--bpm', type=float)
    analysis.add_argument('--refine-bpm', action='store_true')
    imp = sub.add_parser('import')
    imp.add_argument('--file', type=Path)
    imp.add_argument('--name', default='New import')
    imp.add_argument('--order', choices=('artist-title', 'title-artist'), default='artist-title')
    imp.add_argument('--minimum', type=int, choices=(150, 192, 256, 320), default=320)
    for name in ('run', 'stop'):
        cmd = sub.add_parser(name)
        cmd.add_argument('id')
        if name == 'run':
            cmd.add_argument('--deep', action='store_true')
            cmd.add_argument('--index', type=int)
            cmd.add_argument('--candidate', type=int)
    cmd = sub.add_parser('swap-order')
    cmd.add_argument('id')
    for name in ('review-info', 'review-track'):
        cmd = sub.add_parser(name)
        cmd.add_argument('id')
        cmd.add_argument('index', type=int)
        if name == 'review-track':
            cmd.add_argument('--artist', required=True)
            cmd.add_argument('--title', required=True)
    cmd = sub.add_parser('hook')
    cmd.add_argument('id')
    cmd.add_argument('index', type=int)
    cmd.add_argument('path', type=Path)
    cmd = sub.add_parser('label')
    cmd.add_argument('id')
    cmd.add_argument('--genre', required=True)
    cmd.add_argument('--vibe', required=True)
    args = p.parse_args(argv)
    root = args.root.resolve()
    (root/'.music-sorter/crate').mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        if args.command == 'snapshot':
            result = snapshot(root)
        elif args.command == 'login':
            result = check_login(json.loads(sys.stdin.read()))
        elif args.command == 'deck-analysis':
            result = deck_analysis(args.path, args.bpm, args.refine_bpm)
        elif args.command == 'import':
            if args.file and args.file.stat().st_size > 2_000_000:
                raise ValueError('Tracklist is too large (maximum 2 MB).')
            text = args.file.read_text(encoding='utf-8-sig') if args.file else sys.stdin.read()
            result = create_job(root, text, args.name, args.order, args.minimum)
        elif args.command == 'run':
            credentials = sys.stdin.read() if not sys.stdin.isatty() else ''
            result = run_job(root, args.id, json.loads(credentials) if credentials.strip() else None, args.deep, args.index, args.candidate)
        elif args.command == 'swap-order':
            result = correct_import(root, args.id)
        elif args.command == 'review-track':
            result = correct_import(root, args.id, args.index, args.artist, args.title)
        elif args.command == 'review-info':
            job = load_job(root, args.id)
            if not 0 <= args.index < len(job['tracks']):
                raise ValueError('Invalid track index.')
            row = job['tracks'][args.index]
            result = probe(review_path(root, job, row))
        elif args.command == 'stop':
            (job_dir(root, args.id)/'cancel').touch()
            result = {'stopping': True}
        elif args.command == 'hook':
            destination = complete_hook(root, args.id, args.index, args.path)
            print('success;' + destination)
            return 0
        else:
            if not args.genre.strip() or not args.vibe.strip():
                raise ValueError('Genre and vibe labels cannot be empty.')
            if any(j['status'] == 'running' for j in snapshot(root)['jobs']):
                raise ValueError('Wait until the current import finishes before editing labels.')
            with sorter.catalog(root) as state:
                if args.id not in state['tracks']:
                    raise ValueError('Track no longer exists in the catalog.')
                track = state['tracks'][args.id]
                old_path = str(root/track['path'])
                track['overrides'] = {'genre': sorter.component(args.genre), 'vibe': sorter.component(args.vibe)}
                changes = sorter.plan(root, {'tracks': {args.id: track}}, state['layout'])
                sorter.apply_plan(root, state, changes, state['layout'])
                sorter.save(root, state)
                result = dict(track, path=str(root/track['path']))
            for job in snapshot(root)['jobs']:
                changed = False
                for row in job['tracks']:
                    if row.get('track_id') == args.id:
                        row.update(path=result['path'], genre=args.genre, vibe=args.vibe, note='Labels updated')
                        changed = True
                if changed:
                    save_job(root, job)
                folder = job_dir(root, job['id'])
                update_owned_indexes(folder, old_path, result['path'])
                for path in folder.glob('hook-*.json'):
                    hook = json.loads(path.read_text())
                    if hook.get('path') == old_path:
                        hook.update(path=result['path'], genre=args.genre, vibe=args.vibe)
                        atomic_json(path, hook)
        print(json.dumps(result, ensure_ascii=False, allow_nan=False))
        return 0
    except (ValueError, OSError, KeyError, IndexError) as error:
        print(json.dumps({'error': str(error)}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
