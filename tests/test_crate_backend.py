import csv
import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import crate_backend as crate
import music_sorter as sorter


class AccountTests(unittest.TestCase):
    def test_private_config_preserves_password_and_cleans_up(self):
        credentials = {'username': 'test-user', 'password': '  a="b # c  '}
        with crate.account_config(credentials) as path:
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(path.read_text(), 'username = "test-user"\npassword = "  a="b # c  "\n')
        self.assertFalse(path.exists())
        with self.assertRaises(RuntimeError):
            with crate.account_config(credentials) as failed:
                raise RuntimeError('test')
        self.assertFalse(failed.exists())
        for invalid in ([], {}, {'username': 'a', 'password': 'x\noutput-dir = /tmp'},
                        {'username': '\ra', 'password': 'b'}):
            with self.assertRaises(ValueError):
                with crate.account_config(invalid):
                    self.fail('Invalid credentials accepted')

    def test_login_is_print_only_and_errors_do_not_expose_password(self):
        credentials = {'username': 'test-user', 'password': 'private-test-password'}
        def logged_in(command, **kwargs):
            self.assertNotIn(credentials['password'], command)
            self.assertEqual(command[command.index('--print')+1], 'results')
            self.assertEqual(kwargs['timeout'], 35)
            self.assertTrue(Path(command[command.index('--config')+1]).exists())
            return subprocess.CompletedProcess(command, 0, b'Logged in as test-user', b'')
        with patch.object(crate.subprocess, 'run', side_effect=logged_in):
            self.assertTrue(crate.check_login(credentials)['authenticated'])
        no_results = subprocess.CompletedProcess([], 1,
            b'[debug] [soulseek] Logged in as test-user\nNo results\n', b'')
        with patch.object(crate.subprocess, 'run', return_value=no_results):
            self.assertTrue(crate.check_login(credentials)['authenticated'])
        for result in (subprocess.CompletedProcess([], 1, credentials['password'].encode(), b''),
                       subprocess.CompletedProcess([], 0, b'Logging in as test-user', b'')):
            with patch.object(crate.subprocess, 'run', return_value=result):
                with self.assertRaises(ValueError) as error:
                    crate.check_login(credentials)
                self.assertNotIn(credentials['password'], str(error.exception))

    def test_frozen_completion_relaunches_backend_without_python_script(self):
        root = Path('/tmp/Music with spaces')
        normal = crate.completion_command(root, 'a'*12, 0)
        self.assertIn(str(Path(crate.__file__).resolve()), normal)
        with patch.object(crate.sys, 'frozen', True, create=True):
            frozen = crate.completion_command(root, 'a'*12, 0)
        self.assertNotIn('crate_backend.py', frozen)
        self.assertIn(f'--root "{root}" hook', frozen)
        self.assertTrue(frozen.endswith('"{path}"'))


class ParserTests(unittest.TestCase):
    def test_supplied_set_and_cues_are_not_lengths(self):
        text = (crate.ROOT/'tracklists/YouTube set bNSesW8h94I.csv').read_text()
        rows, fields = crate.parse_tracklist(text)
        self.assertEqual(len(rows), 15)
        self.assertEqual(rows[0]['artist'], 'Freedom Satellite')
        self.assertEqual(rows[-1]['title'], 'Forget About Miami')
        self.assertTrue(all(r['length'] is None for r in rows))
        self.assertEqual(rows[1]['cue'], '0:04:31')

    def test_csv_preserves_fields_and_real_durations(self):
        text = 'Artist,Title,Duration,Extra\n"First, Second","Title, Part 2",04:31,untouched\n'
        rows, fields = crate.parse_tracklist(text)
        self.assertEqual(rows[0]['length'], 271)
        self.assertEqual(rows[0]['original']['Extra'], 'untouched')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            job = crate.create_job(root, text, 'Test', 'artist-title', 320)
            with (crate.job_dir(root, job['id'])/'input.csv').open() as f:
                actual = list(csv.DictReader(f))[0]
            self.assertEqual(actual, rows[0]['original'])
            command = crate.base_command(root, job, 0)
            self.assertIn('--offset', command)
            self.assertEqual(command[command.index('--number')+1], '1')
            self.assertEqual(command[command.index('--length-col')+1], 'Duration')
            self.assertNotIn('--pass', command)

    def test_pasted_markdown_chapters(self):
        text = '([https://www.youtube.com/watch?v=test](https://www.youtube.com/watch?v=test))[0:00:00](https://www.youtube.com/watch?v=test) Easy - Freedom Satellite [0:04:31](https://www.youtube.com/watch?v=test&t=271s) Smoke - Vienna D.C.'
        rows, _ = crate.parse_tracklist(text, 'title-artist')
        self.assertEqual([(r['artist'], r['title'], r['cue']) for r in rows],
                         [('Freedom Satellite', 'Easy', '0:00:00'), ('Vienna D.C.', 'Smoke', '0:04:31')])
        rows, _ = crate.parse_tracklist('Freedom Satellite - Easy')
        self.assertEqual(rows[0]['artist'], 'Freedom Satellite')

    def test_bad_imports_and_remix_rejection(self):
        for text in ('', 'unparseable', 'Artist,Title\nArtist,\n', 'Artist,Title,Duration\nA,T,NaN\n'):
            with self.assertRaises(ValueError):
                crate.parse_tracklist(text)
        row = {'artist': 'Freedom Satellite', 'title': 'Easy'}
        make = lambda name: {'File': {'Filename': 'Music\\Freedom Satellite\\'+name}}
        self.assertTrue(crate.candidate_matches(make('02 - Easy (Original Mix).flac'), row))
        self.assertFalse(crate.candidate_matches(make('02 - Easy (Someone Remix).flac'), row))
        self.assertFalse(crate.candidate_matches(make('02 - Easy (Instrumental Version).flac'), row))
        with self.assertRaises(ValueError):
            crate.job_dir(Path('/tmp'), '../outside')
        self.assertFalse(crate.filename_title_matches(Path('Freedom Satellite - Easy Going.mp3'), row))
        self.assertTrue(crate.filename_title_matches(Path('01 - Freedom Satellite - Easy.mp3'), row))


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg required')
class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root/'downloads').mkdir()
        (self.root/'juan music').mkdir()
        self.job = crate.create_job(self.root, 'Artist,Title\nFixture,Pulse\n', 'Test import', 'artist-title', 320)
        self.staging = self.root/'downloads/.incoming'/self.job['id']
        self.staging.mkdir(parents=True)

    def audio(self, name='Fixture - Pulse.flac', title='Pulse', bitrate=None):
        path = self.staging/name
        command = ['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=100:sample_rate=44100:duration=8',
                   '-metadata', 'artist=Fixture', '-metadata', 'title='+title, '-metadata', 'genre=Tech House', '-metadata', 'BPM=125']
        if bitrate:
            command += ['-b:a', str(bitrate)+'k']
        subprocess.run(command+[str(path)], check=True)
        return path

    def test_verified_audio_is_moved_once_and_catalogued(self):
        path = self.audio()
        before = sorter.signature(path)
        destination = crate.complete_hook(self.root, self.job['id'], 0, path)
        self.assertFalse(path.exists())
        self.assertEqual(sorter.signature(Path(destination)), before)
        result = json.loads((crate.job_dir(self.root, self.job['id'])/'hook-0.json').read_text())
        self.assertEqual(result['status'], 'ready')
        self.assertEqual(result['quality'], 'Lossless')
        self.assertIn('organized/Tech House/Driving', destination)
        self.assertEqual(len(crate.snapshot(self.root)['library']), 1)

    def test_wrong_mix_and_low_bitrate_stay_in_staging(self):
        wrong = self.audio(title='Pulse (Other Remix)')
        crate.complete_hook(self.root, self.job['id'], 0, wrong)
        result = json.loads((crate.job_dir(self.root, self.job['id'])/'hook-0.json').read_text())
        self.assertEqual(result['status'], 'review')
        self.assertTrue(wrong.exists())
        low = self.audio(name='Fixture - Pulse.mp3', bitrate=128)
        with self.assertRaisesRegex(ValueError, 'below 320'):
            crate.verify(low, self.job['tracks'][0], 320)
        with sorter.catalog(self.root) as state:
            result = sorter.scan(self.root, state, min_age=0)
            self.assertEqual(result['tracks_total'] if 'tracks_total' in result else len(state['tracks']), 0)

    def test_existing_library_is_not_moved(self):
        path = self.audio()
        target = self.root/'juan music'/path.name
        path.rename(target)
        before = sorter.signature(target)
        result = crate.existing_track(self.root, self.job['tracks'][0], 320)
        self.assertEqual(result['status'], 'existing')
        self.assertEqual(sorter.signature(target), before)

    def test_reversed_import_is_corrected_locally_with_source_and_indexes_preserved(self):
        job = crate.create_job(self.root, 'Artist,Title,Duration,Extra\nPulse,Fixture,8,keep\n', 'Reversed', 'artist-title', 320)
        path = self.audio()
        staging = self.root/'downloads/.incoming'/job['id']
        staging.mkdir(parents=True)
        path = path.rename(staging/path.name)
        before = sorter.signature(path)
        original = dict(job['tracks'][0]['original'])
        crate.complete_hook(self.root, job['id'], 0, path)
        folder = crate.job_dir(self.root, job['id'])
        job['tracks'][0].update(json.loads((folder/'hook-0.json').read_text()))
        crate.save_job(self.root, job)
        (folder/'index-0.csv').write_text('filepath,title\n'+str(path)+',Fixture\n')
        with patch.object(crate, 'managed_engine', side_effect=AssertionError('Must not download')):
            corrected = crate.correct_import(self.root, job['id'])
        row = corrected['tracks'][0]
        self.assertEqual((row['artist'], row['title'], row['status']), ('Fixture', 'Pulse', 'ready'))
        self.assertEqual(row['original'], original)
        self.assertEqual(row['length'], 8)
        self.assertEqual(sorter.signature(Path(row['path'])), before)
        with (folder/'input.csv').open() as f:
            self.assertEqual(list(csv.DictReader(f))[0], {'Artist': 'Fixture', 'Title': 'Pulse', 'Duration': '8', 'Extra': 'keep'})
        self.assertIn(row['path'], (folder/'index-0.csv').read_text())
        self.assertEqual(json.loads((folder/'hook-0.json').read_text())['path'], row['path'])
        with self.assertRaisesRegex(ValueError, 'before any tracks'):
            crate.correct_import(self.root, job['id'])

    def test_review_corrections_keep_quality_duration_and_path_safeguards(self):
        path = self.audio(name='Fixture - Pulse.mp3', bitrate=128)
        row = self.job['tracks'][0]
        row.update(status='review', path=str(path))
        crate.save_job(self.root, self.job)
        corrected = crate.correct_import(self.root, self.job['id'], 0, 'Fixture', 'Pulse')
        self.assertEqual(corrected['tracks'][0]['status'], 'review')
        self.assertIn('below 320', corrected['tracks'][0]['note'])
        self.assertTrue(path.exists())
        with self.assertRaisesRegex(ValueError, 'Invalid track index'):
            crate.correct_import(self.root, self.job['id'], -1, 'Fixture', 'Pulse')
        with self.assertRaisesRegex(ValueError, 'nonempty'):
            crate.correct_import(self.root, self.job['id'], 0, '', 'Pulse')
        row.update(path=str(self.root/'juan music'/path.name))
        path.rename(row['path'])
        crate.save_job(self.root, self.job)
        with self.assertRaisesRegex(ValueError, 'No staged file'):
            crate.correct_import(self.root, self.job['id'], 0, 'Fixture', 'Pulse')
        link = self.staging/'link.mp3'
        link.symlink_to(row['path'])
        row['path'] = str(link)
        with self.assertRaisesRegex(ValueError, 'No staged file'):
            crate.review_path(self.root, self.job, row)

    def test_review_cannot_race_an_import(self):
        import fcntl
        with (crate.job_dir(self.root, self.job['id']).parent.parent/'download.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, 'Wait until'):
                crate.correct_import(self.root, self.job['id'])

    def test_single_track_review_does_not_bypass_duration_or_identity(self):
        path = self.audio()
        row = self.job['tracks'][0]
        row.update(status='review', path=str(path), length=20)
        crate.save_job(self.root, self.job)
        result = crate.correct_import(self.root, self.job['id'], 0, 'Fixture', 'Pulse')
        self.assertIn('Duration differs', result['tracks'][0]['note'])
        row['length'] = 8
        crate.save_job(self.root, self.job)
        result = crate.correct_import(self.root, self.job['id'], 0, 'Fixture', 'Other track')
        self.assertIn('Title tag differs', result['tracks'][0]['note'])
        result = crate.correct_import(self.root, self.job['id'], 0, 'Fixture', 'Pulse')
        self.assertEqual(result['tracks'][0]['status'], 'ready')
        self.assertTrue(Path(result['tracks'][0]['path']).is_file())

    def test_import_worker_with_fake_peer_reaches_real_sorter(self):
        path = self.audio()
        candidate = {'File': {'Filename': 'Music\\Fixture - Pulse.flac'}, 'User': {'Username': 'fixture-peer'}}
        configs = []
        @contextlib.contextmanager
        def engine(root, config):
            configs.append(config)
            self.assertIn('username = "fixture-account"', config.read_text())
            yield 'http://127.0.0.1:1'
        def transfer(command, log, cancel, timeout=180):
            self.assertTrue(configs[0].exists())
            self.assertIn('--no-config', command)
            self.assertNotIn('fixture-password', command)
            crate.complete_hook(self.root, self.job['id'], 0, path)
            return 0
        with patch.object(crate, 'managed_engine', side_effect=engine), patch.object(crate, 'search_candidates', return_value=[candidate]), patch.object(crate, 'run_process', side_effect=transfer):
            result = crate.run_job(self.root, self.job['id'], {'username': 'fixture-account', 'password': 'fixture-password'})
        self.assertFalse(configs[0].exists())
        self.assertEqual(result['status'], 'finished')
        self.assertEqual(result['tracks'][0]['status'], 'ready')
        self.assertTrue(Path(result['tracks'][0]['path']).is_file())

    def test_graphical_label_action_updates_path_and_job(self):
        path = self.audio()
        destination = crate.complete_hook(self.root, self.job['id'], 0, path)
        folder = crate.job_dir(self.root, self.job['id'])
        result = json.loads((folder/'hook-0.json').read_text())
        self.job['tracks'][0].update(result)
        crate.save_job(self.root, self.job)
        index = folder/'index-0.csv'
        with index.open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['filepath', 'title', 'state'])
            writer.writeheader()
            writer.writerow({'filepath': destination, 'title': 'Pulse', 'state': '1'})
        before = sorter.signature(Path(destination))
        with contextlib.redirect_stdout(io.StringIO()):
            code = crate.main(['--root', str(self.root), 'label', result['track_id'],
                               '--genre', 'Dub Techno', '--vibe', 'Basement Business'])
        self.assertEqual(code, 0)
        changed = crate.load_job(self.root, self.job['id'])['tracks'][0]
        self.assertIn('Dub Techno/Basement Business', changed['path'])
        self.assertEqual(sorter.signature(Path(changed['path'])), before)
        self.assertFalse(Path(destination).exists())
        with index.open() as f:
            indexed = list(csv.DictReader(f))[0]
        self.assertEqual(indexed, {'filepath': changed['path'], 'title': 'Pulse', 'state': '1'})


if __name__ == '__main__':
    unittest.main()
