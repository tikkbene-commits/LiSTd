"""Audit both runtimes, then exercise the shipped pipeline without host dependencies."""
import array
import contextlib
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch
import wave

ARCHITECTURES = ('arm64', 'x86_64')
MAGIC = (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca')


def audit(app):
    plist = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert plist['LiSTdStandalone'] and plist['LSMinimumSystemVersion'] == '14.0'
    for path in app.rglob('*'):
        assert path.name not in {'sockseek.conf', 'catalog.json', 'job.json', '.DS_Store'}, path
        if path.is_symlink():
            assert path.resolve().is_relative_to(app), path
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as f:
            magic = f.read(4)
        if magic not in MAGIC:
            continue
        dependencies = subprocess.check_output(['/usr/bin/otool', '-L', str(path)], text=True)
        for line in dependencies.splitlines()[1:]:
            if ' (compatibility version' not in line:
                continue
            dependency = line.strip().split(' (compatibility')[0]
            assert dependency.startswith(('/System/', '/usr/lib/', '@')), (path, dependency)
        versions = subprocess.check_output(['/usr/bin/vtool', '-show-build', str(path)], text=True)
        for version in re.findall(r'(?:minos\s+|cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version\s+)(\d+(?:\.\d+)*)', versions):
            assert int(version.split('.')[0]) <= 14, (path, version)
        architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(path)], text=True).split()
        relative = path.relative_to(app).parts
        expected = (relative[3],) if relative[:3] == ('Contents', 'Resources', 'backend') else ARCHITECTURES
        assert set(expected).issubset(architectures), (path, architectures, expected)


def exercise(app, architecture, folder, original_app):
    backend = app/'Contents/Resources/backend'/architecture
    binary = backend/'listd-backend'
    home = folder/('Clean user '+architecture)
    home.mkdir()
    root = home/'Music/LiSTd'
    workspace = Path(__file__).resolve().parents[1]
    denied = [str(original_app), str(workspace), str(Path.home()), '/opt/homebrew', '/usr/local',
              '/Library/Developer', '/Library/Frameworks/Python.framework',
              str(Path.home()/'Library/Python')]
    policy = '(version 1)(allow default)(deny file-write* (subpath '+json.dumps(str(app), ensure_ascii=False)+'))'
    policy += '(deny network-outbound)(allow network-outbound (remote ip "localhost:*"))'
    policy += ''.join('(deny file-read* (subpath '+json.dumps(path, ensure_ascii=False)+'))' for path in denied)
    prefix = ['/usr/bin/sandbox-exec', '-p', policy, '/usr/bin/arch', '-'+architecture]
    env = dict(HOME=str(home), PATH=str(backend)+':/usr/bin:/bin', TMPDIR=str(folder), LANG='en_US.UTF-8',
               NUMBA_CACHE_DIR=str(root/'.music-sorter/numba-cache'),
               DOTNET_BUNDLE_EXTRACT_BASE_DIR=str(root/'.music-sorter/sockseek-runtime'))
    probe = app/'.qa-write-probe'
    assert subprocess.run(prefix+['/usr/bin/touch', str(probe)], env=env, capture_output=True).returncode != 0 and not probe.exists(), 'Bundle write protection is not active'
    assert subprocess.run(prefix+['/bin/cat', str(workspace/'APP_CONTEXT.md')], env=env, capture_output=True).returncode != 0, 'Host source isolation is not active'

    def request(*args, text=None):
        result = subprocess.run(prefix+[str(binary), '--root', str(root), *map(str, args)],
                                input=text, text=True, capture_output=True, env=env, cwd=home, timeout=120)
        assert result.returncode == 0, (architecture, args, result.stdout, result.stderr)
        return result.stdout

    state = json.loads(request('snapshot'))
    assert state['ready'] and not state['configured'] and not state['jobs'] and not state['library'], state
    job = json.loads(request('import', '--name', 'Offline fixture', text='Artist,Title,Duration,Extra\nFixture Artist,Fixture Title,30,keep\n'))
    with (root/'.music-sorter/crate/jobs'/job['id']/'input.csv').open() as f:
        assert list(csv.DictReader(f))[0] == {'Artist': 'Fixture Artist', 'Title': 'Fixture Title', 'Duration': '30', 'Extra': 'keep'}
    fixtures = home/'Local mock peer'
    fixtures.mkdir()
    source = fixtures/'Fixture Artist - Fixture Title.wav'
    samples = array.array('h', (int(16000*math.sin(2*math.pi*110*i/44100)*math.exp(-((i % 22050)/650))) for i in range(30*44100)))
    with wave.open(str(source), 'wb') as f:
        f.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
        f.writeframes(samples.tobytes())
    original = hashlib.sha256(source.read_bytes()).digest()
    analysis = json.loads(request('deck-analysis', source, '--bpm', '120'))
    assert analysis['bpm'] == 120 and hashlib.sha256(source.read_bytes()).digest() == original, analysis

    # Inject only a local mock peer; run the shipped worker, daemon, CLI and frozen callback.
    sys.path.insert(0, str(app/'Contents/Resources/Sources'))
    sys.dont_write_bytecode = True
    import crate_backend as crate
    config = home/'local-mock.conf'
    config.write_text('mock-files-dir = "'+str(fixtures)+'"\n')
    popen = subprocess.Popen
    commands = []

    def isolated_process(command, *args, **kwargs):
        commands.append(command)
        command = [str(backend/command[0]), *command[1:]]
        kwargs['env'] = env
        kwargs['cwd'] = root
        return popen(prefix+command, *args, **kwargs)

    with patch.object(crate, 'account_config', return_value=contextlib.nullcontext(config)), \
            patch.object(crate.sys, 'executable', str(binary)), patch.object(crate.sys, 'frozen', True, create=True), \
            patch.object(crate.subprocess, 'Popen', side_effect=isolated_process):
        result = crate.run_job(root, job['id'])
    row = result['tracks'][0]
    assert result['status'] == 'finished' and row['status'] == 'ready', result
    assert any('daemon' in command for command in commands), commands
    assert any('--remote' in command and '--on-complete' in command and '--no-config' in command for command in commands), commands
    path = Path(row['path'])
    assert hashlib.sha256(path.read_bytes()).digest() == original
    assert hashlib.sha256(source.read_bytes()).digest() == original
    job_folder = root/'.music-sorter/crate/jobs'/job['id']
    hook = json.loads((job_folder/'hook-0.json').read_text())
    assert hook['status'] == 'ready' and hook['path'] == str(path), hook
    with (job_folder/'index-0.csv').open() as f:
        assert any(entry['filepath'] == str(path) for entry in csv.DictReader(f)), 'Sockseek index did not receive the organized path'
    labeled = json.loads(request('label', row['track_id'], '--genre', 'House', '--vibe', 'Groove'))
    assert Path(labeled['path']).is_file() and not path.exists()
    snapshot = json.loads(request('snapshot'))
    assert snapshot['library'][0]['id'] == row['track_id']
    assert snapshot['jobs'][0]['tracks'][0]['path'] == labeled['path']
    assert snapshot['library'][0]['genre'] == 'House'
    with (job_folder/'index-0.csv').open() as f:
        assert any(entry['filepath'] == labeled['path'] for entry in csv.DictReader(f))
    version = subprocess.check_output(prefix+[str(backend/'sockseek'), '--version'], env=env, text=True)
    assert version.strip() == '3.0.6', version
    print(architecture+': read-only relocated bundle, clean HOME, blocked host tools/network, analysis, mock transfer, frozen callback, sorting, relabel/index update and restart passed.', flush=True)


def main():
    app = Path(sys.argv[1]).resolve()
    audit(app)
    with tempfile.TemporaryDirectory(prefix='listd-standalone-') as directory:
        folder = Path(directory).resolve()
        moved = folder/'Moved app with spaces – LiSTd.app'
        shutil.copytree(app, moved, symlinks=True)
        for architecture in ARCHITECTURES:
            exercise(moved, architecture, folder, app)
    print('Universal standalone bundle audit and both architecture checks passed.')


if __name__ == '__main__':
    main()
