import contextlib
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import crate_backend as crate
import music_sorter as sorter


class ParallelImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root/'downloads').mkdir()
        (self.root/'juan music').mkdir()

    def make_job(self, lines):
        return crate.create_job(self.root, 'Artist,Title\n' + ''.join(f'{a},{t}\n' for a, t in lines),
                                'Parallel import', 'artist-title', 320)

    def run_with_fake_search(self, job, search):
        engine = contextlib.nullcontext('http://127.0.0.1:1')
        with patch.object(crate, 'managed_engine', return_value=engine), \
                patch.object(crate, 'existing_track', return_value=None), \
                patch.object(crate, 'search_candidates', side_effect=search), \
                patch.object(crate.shutil, 'which', return_value='/bin/true'):
            return crate.run_job(self.root, job['id'])

    def test_tracks_search_in_parallel_up_to_the_limit(self):
        job = self.make_job([(f'Artist {i}', f'Title {i}') for i in range(12)])
        lock, active, peak, seen = threading.Lock(), [0], [0], []
        def search(root, job_state, index, cancel):
            with lock:
                active[0] += 1
                peak[0] = max(peak[0], active[0])
                seen.append(index)
            time.sleep(0.2)
            with lock:
                active[0] -= 1
            return []
        result = self.run_with_fake_search(job, search)
        self.assertEqual(peak[0], crate.PARALLEL_TRACKS)
        self.assertEqual(sorted(seen), list(range(12)))
        self.assertEqual(result['status'], 'finished')
        self.assertTrue(all(r['status'] == 'unavailable' for r in result['tracks']))
        self.assertEqual(result['_finished'], 12)
        saved = crate.load_job(self.root, job['id'])
        self.assertTrue(all(r['status'] == 'unavailable' for r in saved['tracks']))

    def test_duplicate_tracks_share_one_lane(self):
        job = self.make_job([('Same', 'Song'), ('Other', 'Song'), ('same', 'SONG')])
        lock, running = threading.Lock(), set()
        def search(root, job_state, index, cancel):
            key = crate.normalize(job_state['tracks'][index]['artist'])
            with lock:
                self.assertNotIn(key, running)
                running.add(key)
            time.sleep(0.15)
            with lock:
                running.discard(key)
            return []
        self.run_with_fake_search(job, search)

    def test_one_failing_track_does_not_stop_the_others(self):
        job = self.make_job([('A', 'One'), ('B', 'Two'), ('C', 'Three')])
        def search(root, job_state, index, cancel):
            if index == 1:
                raise RuntimeError('boom')
            return []
        result = self.run_with_fake_search(job, search)
        self.assertIn('boom', result['tracks'][1]['note'])
        self.assertEqual(result['status'], 'finished')

    def test_daemon_runs_with_matching_search_concurrency(self):
        commands = []
        class Process:
            pid = 0
            def poll(self):
                return 0
        def popen(command, **kwargs):
            commands.append(command)
            return Process()
        (self.root/'.music-sorter/crate').mkdir(parents=True)
        with patch.object(crate.subprocess, 'Popen', side_effect=popen), self.assertRaises(ValueError):
            with crate.managed_engine(self.root):
                pass
        command = commands[0]
        self.assertEqual(command[command.index('--concurrent-searches')+1], str(crate.PARALLEL_TRACKS))

    def test_organizer_waits_for_a_parallel_track_to_release_the_catalog(self):
        job = self.make_job([('A', 'One')])
        calls = []
        real = sorter.catalog
        @contextlib.contextmanager
        def busy_once(root):
            calls.append(1)
            if len(calls) == 1:
                raise ValueError('Another music-sorter command is running. Try again when it finishes.')
            with real(root) as state:
                yield state
        with patch.object(crate, 'verify', return_value={'lossless': True, 'measured_kbps': 900}), \
                patch.object(crate.sorter, 'catalog', side_effect=busy_once), \
                patch.object(crate.sorter, 'sockseek_hook', side_effect=ValueError('stop after lock')):
            with self.assertRaisesRegex(ValueError, 'stop after lock'):
                crate.finish_track(self.root, job, job['tracks'][0], self.root/'x.flac')
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
