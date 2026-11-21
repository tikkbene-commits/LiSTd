"""Offline search/retry coverage: never contacts Soulseek."""
import contextlib
import csv
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import crate_backend as crate


class DeepSearchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.job = crate.create_job(self.root,
            'Artist,Title,Duration,Album,Catalog,SetStart,Extra\nFréedom Satellite,Easy,271,Vienna Scientists III,VS003,0:04:31,keep\n',
            'Fixture', 'artist-title', 320)
        self.row = self.job['tracks'][0]
        self.folder = crate.job_dir(self.root, self.job['id'])
        self.cancel = self.folder/'cancel'

    def candidate(self, name, user='peer'):
        return {'File': {'Filename': 'Music\\'+name, 'Length': 271, 'BitRate': 320}, 'User': {'Username': user}}

    def test_combined_fields_accents_and_version_safety(self):
        confident = [
            'Freedom Satellite - Easy.flac',
            '01 Easy - Freedom Satellite - Vienna Scientists III VS003.flac',
            'Freedom Satellite/Easy.flac',
            'Easy - Freedom Satellite (Original Mix).flac',
        ]
        for filename in confident:
            self.assertEqual(crate.deep_identity(filename, self.row), 'confident', filename)
        tags = {'artist': 'Easy - Freedom Satellite', 'title': 'Vienna Scientists III - Easy - Freedom Satellite'}
        self.assertEqual(crate.deep_identity('Easy.flac', self.row, tags), 'confident')
        for filename in ('Freedom Satellite - Easy (Club Remix).flac', 'Freedom Satellite - Easy Live.flac',
                         'Freedom Satellite - Easy Radio Edit.flac', 'Freedom Satellite - Easy Dub.flac',
                         'Freedom Satellite - Easier.flac', 'Unrelated Artist - Easy.flac'):
            self.assertEqual(crate.deep_identity(filename, self.row), 'reject', filename)
        self.assertEqual(crate.deep_identity('Freedom Satelite - Easy.flac', self.row), 'review')
        self.assertEqual(crate.deep_identity('Dub Trio - Easy.flac', dict(self.row, artist='Dub Trio')), 'confident')
        self.assertEqual(crate.deep_identity('Dub Trio - Easy Dub.flac', dict(self.row, artist='Dub Trio')), 'reject')
        self.assertEqual(crate.deep_identity('Freedom Satellite - Easy Street.flac', self.row), 'review')
        self.assertEqual(crate.deep_identity('Freedom Satellite - Easy.flac', self.row,
                                            {'title': 'Another track', 'artist': 'Someone else'}), 'review')
        remix = dict(self.row, title='Easy (Club Remix)')
        self.assertEqual(crate.deep_identity('Freedom Satellite - Easy (Club Remix).flac', remix), 'confident')

    def test_bounded_queries_preserve_original_csv_and_duration(self):
        before = (self.folder/'input.csv').read_bytes()
        original = json.loads(json.dumps(self.row))
        queries = crate.deep_queries(self.row)
        self.assertLessEqual(len(queries), 6)
        self.assertIn('freedom satellite easy', queries)
        self.assertIn('easy freedom satellite', queries)
        self.assertIn('easy', queries)
        self.assertIn('easy vienna scientists iii', queries)
        self.assertIn('easy vs003', queries)
        commands = []
        def search(command, log, cancel, timeout):
            commands.append(command)
            self.assertEqual(command[command.index('--number')+1], '1')
            self.assertEqual(command[command.index('--offset')+1], '0')
            self.assertIn('--strict-conditions', command)
            self.assertEqual(command[command.index('--min-bitrate')+1], '320')
            self.assertIn('--skip-music-dir', command)
            self.assertEqual(command[-2:], ['--print', 'json-all'])
            with Path(command[1]).open() as handle:
                row = next(csv.DictReader(handle))
                self.assertEqual(row['Length'], '271.0')
                self.assertNotEqual(row['Length'], self.row['cue'])
            log.write_text(json.dumps([self.candidate('Freedom Satelite - Easy.flac'),
                                       self.candidate('Freedom Satellite - Easy Remix.flac')])+'\n')
            return 0
        with patch.object(crate, 'run_process', side_effect=search):
            self.assertEqual(crate.deep_search_candidates(self.root, self.job, 0, self.cancel), [])
        self.assertEqual(len(commands), len(queries))
        self.assertEqual(len(self.row['candidates']), 1)  # Deduplicated across queries; remix excluded.
        self.assertEqual(self.row['original'], original['original'])
        self.assertEqual((self.folder/'input.csv').read_bytes(), before)
        self.assertEqual(self.row['length'], original['length'])

    def test_batch_retry_selection_preserves_accepted_and_staged_files(self):
        accepted = dict(self.row, index=1, status='ready', path='/accepted.flac')
        existing = dict(self.row, index=2, status='existing', path='/library.flac')
        staged = self.root/'review.flac'; staged.touch()
        review = dict(self.row, index=3, status='review', path=str(staged))
        queued = dict(self.row, index=4, status='queued')
        self.row['status'] = 'unavailable'
        self.job['tracks'] += [accepted, existing, review, queued]
        self.assertEqual(crate.retry_rows(self.job, True), [self.row])
        for index in (1, 2, 3, 4, -1, 20):
            with self.assertRaises(ValueError):
                crate.retry_rows(self.job, True, index)
        for args in ((False, 0, None), (True, None, 0), (True, 0, 0)):
            with self.assertRaises(ValueError):
                crate.retry_rows(self.job, *args)
        self.row.update(status='review', candidates=[{}], candidate_results=[self.candidate('Freedom Satelite - Easy.flac')])
        self.assertEqual(crate.retry_rows(self.job, True, 0, 0), [self.row])

    def test_cancel_stops_fallbacks_and_worker_preserves_other_rows(self):
        self.row['status'] = 'unavailable'
        accepted = dict(self.row, index=1, status='ready', path='/accepted.flac')
        self.job['tracks'].append(accepted)
        crate.save_job(self.root, self.job)
        calls = []
        def search(command, log, cancel, timeout):
            calls.append(command)
            cancel.touch()
            log.write_text('[]\n')
            return 'cancelled'
        with patch.object(crate, 'managed_engine', return_value=contextlib.nullcontext('http://127.0.0.1:1')), \
                patch.object(crate, 'existing_track', return_value=None), \
                patch.object(crate, 'run_process', side_effect=search):
            result = crate.run_job(self.root, self.job['id'], deep=True)
        self.assertEqual(len(calls), 1)
        self.assertEqual(result['status'], 'stopped')
        self.assertEqual(result['tracks'][0]['status'], 'stopped')
        self.assertEqual(result['tracks'][1], accepted)

    def test_search_results_are_bounded_and_timeouts_are_not_matches(self):
        log = self.folder/'search.log'
        log.write_text('')
        with self.assertRaisesRegex(ValueError, 'connection'):
            crate.read_candidates(log, 'timeout')
        with log.open('wb') as handle:
            handle.truncate(8_000_001)
        with self.assertRaisesRegex(ValueError, 'too many'):
            crate.read_candidates(log, 0)


if __name__ == '__main__':
    unittest.main()
