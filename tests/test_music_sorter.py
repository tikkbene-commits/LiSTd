import contextlib
import io
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import music_sorter as sorter


class AudioTests(unittest.TestCase):
    def test_pulse_tempo_and_silence(self):
        for bpm in (80, 100, 125, 140, 160):
            envelope = [math.exp(-((i % (12000/bpm))/4)) for i in range(4800)]
            estimated, strength = sorter.estimate_tempo([envelope])
            self.assertIsNotNone(estimated)
            self.assertLess(abs(estimated - bpm), 1.5, (bpm, estimated))
            self.assertGreater(strength, 0.12)
        self.assertEqual(sorter.estimate_tempo([[0.0]*1200]), (None, 0.0))

    def test_genres_and_safe_names(self):
        self.assertEqual(sorter.genre_from_tags('Electronic / Tech House'), ('Tech House', 'file tag'))
        self.assertEqual(sorter.genre_from_tags('Techno / Dub Techno'), ('Dub Techno', 'file tag'))
        self.assertEqual(sorter.genre_from_tags('House / Techno')[0], 'Unsorted')
        self.assertEqual(sorter.genre_from_tags('Unknown')[0], 'Unsorted')
        self.assertNotIn('/', sorter.component('../../evil'))
        self.assertEqual(sorter.vibe_from_features(None, 0, 8), 'Needs Review')
        self.assertEqual(sorter.vibe_from_features(105, 0.7, 10), 'Warm-Up')
        self.assertEqual(sorter.vibe_from_features(120, 0.7, 12), 'Groove')
        self.assertEqual(sorter.vibe_from_features(135, 0.7, 12), 'Driving')
        self.assertEqual(sorter.vibe_from_features(155, 0.7, 12), 'Peak Time')
        legacy = {'genre': 'Techno', 'vibe': 'Pocket Grooves', 'overrides': {}}
        self.assertEqual(sorter.labels(legacy), ('Techno', 'Groove'))
        legacy['overrides']['vibe'] = 'Pocket Grooves'
        self.assertEqual(sorter.labels(legacy), ('Techno', 'Pocket Grooves'))

    def test_bass_pulse_ignores_faster_hi_hats(self):
        samples = []
        for i in range(8000*24):
            t = i/8000
            kick = math.exp(-(t % (60/90))*40)*math.sin(2*math.pi*80*t)
            hat = math.exp(-(t % (60/180))*100)*math.sin(2*math.pi*3000*t)
            samples.append(10000*kick + 20000*hat)
        bpm, strength = sorter.estimate_tempo([sorter.bass_envelope(samples)])
        self.assertLess(abs(bpm-90), 1.5)
        self.assertGreater(strength, 0.12)


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg required')
class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('a', 'b', 'delete_review'):
            (self.root/'downloads'/folder).mkdir(parents=True)
        raw = self.root/'pulse.wav'
        with wave.open(str(raw), 'wb') as wav:
            wav.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
            samples = []
            for i in range(8000*12):
                phase = (i/8000) % (60/125)
                amplitude = math.exp(-phase*60)
                samples.append(int(24000*amplitude*math.sin(2*math.pi*120*i/8000)))
            wav.writeframes(struct.pack('<'+'h'*len(samples), *samples))
        target = self.root/'downloads/a/track.flac'
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(raw), '-metadata', 'genre=Tech House',
                        '-metadata', 'artist=Fixture', '-metadata', 'title=Pulse',
                        '-metadata', 'BPM=125', str(target)], check=True)
        shutil.copy2(target, self.root/'downloads/b/track.flac')
        (self.root/'downloads/delete_review/ignore.mp3').write_bytes(b'not audio')
        (self.root/'downloads/unfinished.flac.incomplete').write_bytes(b'not audio')
        for path in (self.root/'downloads').rglob('*.flac'):
            os.utime(path, (time.time()-120, time.time()-120))

    def cli(self, *arguments, expect=0):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = sorter.main(['--root', str(self.root), '--json', *arguments])
        self.assertEqual(code, expect, output.getvalue())
        return json.loads(output.getvalue())

    def test_preview_apply_incremental_label_and_undo(self):
        preview = self.cli('sync')
        self.assertEqual(len(preview['changes']), 2)
        self.assertEqual(preview['scan']['analyzed'], 2)
        originals = [self.root/c['from'] for c in preview['changes']]
        self.assertTrue(all(p.exists() for p in originals))
        applied = self.cli('sync', '--apply')
        self.assertEqual(applied['scan']['cached'], 2)
        self.assertEqual(len({c['to'] for c in applied['changes']}), 2)
        self.assertTrue(all(not p.exists() for p in originals))
        for change in applied['changes']:
            self.assertEqual(sorter.signature(self.root/change['to']), change['signature'])
        self.assertEqual(self.cli('sync', '--apply')['changes'], [])
        tracks = self.cli('list', '--genre', 'house', '--min-bpm', '124', '--max-bpm', '126')['tracks']
        self.assertEqual(len(tracks), 2)
        self.cli('label', tracks[0]['id'], '--genre', 'Dub Techno', '--vibe', 'Basement Business')
        relabel = self.cli('sync', '--apply')
        self.assertEqual(len(relabel['changes']), 1)
        self.assertIn('Dub Techno/Basement Business', relabel['changes'][0]['to'])
        self.assertFalse(self.cli('undo')['applied'])
        self.cli('undo', '--apply')
        self.cli('undo', '--apply')
        self.assertTrue(all(p.exists() for p in originals))
        self.assertEqual(self.cli('undo')['changes'], [])
        self.assertTrue((self.root/'downloads/unfinished.flac.incomplete').exists())
        self.assertTrue((self.root/'downloads/delete_review/ignore.mp3').exists())

    def test_new_download_and_fresh_file_deferral(self):
        self.cli('sync', '--apply')
        new = self.root/'downloads/new.flac'
        shutil.copyfile(next((self.root/'downloads/organized').rglob('*.flac')), new)
        self.assertEqual(self.cli('sync')['scan']['waiting'], 1)
        self.assertTrue(new.exists())
        result = self.cli('sync', '--apply', '--min-age', '0')
        self.assertEqual(len(result['changes']), 1)
        self.assertFalse(new.exists())

    def test_existing_destination_and_modified_undo(self):
        preview = self.cli('sync')
        target = self.root/preview['changes'][0]['to']
        target.parent.mkdir(parents=True)
        target.write_bytes(b'keep me')
        self.cli('sync', '--apply')
        self.assertEqual(target.read_bytes(), b'keep me')
        moves = self.cli('undo')['changes']
        self.assertTrue(moves)
        moved = self.root/moves[0]['from']
        moved.write_bytes(moved.read_bytes()+b'changed')
        self.cli('undo', '--apply', expect=1)
        self.assertTrue(moved.exists())

    def test_interrupt_recovery_and_path_boundaries(self):
        self.cli('scan')
        with sorter.catalog(self.root) as state:
            change = sorter.plan(self.root, state, 'both')[0]
            change['status'] = 'pending'
            state['batches'].append({'id': 'crash-test', 'moves': [change]})
            sorter.save(self.root, state)
            target = self.root/change['to']
            target.parent.mkdir(parents=True)
            os.link(self.root/change['from'], target)
        self.cli('sync', '--apply', expect=1)
        self.cli('undo', '--apply')
        self.assertTrue((self.root/change['from']).exists())
        self.assertFalse(target.exists())
        with self.assertRaises(ValueError):
            sorter.local_path(self.root, 'downloads/../pulse.wav')
        (self.root/'downloads/escape').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            sorter.local_path(self.root, 'downloads/escape/pulse.wav')

    def test_audio_decode_and_untagged_estimate(self):
        result = sorter.inspect_audio(self.root/'downloads/a/track.flac')
        self.assertEqual(result['genre'], 'Tech House')
        self.assertEqual(result['bpm_source'], 'file tag')
        self.assertEqual(result['bpm'], 125)
        untagged = sorter.inspect_audio(self.root/'pulse.wav')
        self.assertLess(abs(untagged['bpm']-125), 1.5)
        self.assertEqual(untagged['genre'], 'Unsorted')

    def test_sockseek_completion_protocol(self):
        path = self.root/'downloads/a/track.flac'
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = sorter.main(['--root', str(self.root), 'sockseek-hook', str(path)])
        self.assertEqual(code, 0)
        protocol, destination = output.getvalue().strip().split(';', 1)
        self.assertEqual(protocol, 'success')
        self.assertTrue(Path(destination).exists())
        self.assertIn('organized/Tech House/', destination)
        self.assertFalse(path.exists())

    def test_watch_picks_up_new_arrival_and_preserves_old_id(self):
        cycles = []
        def next_cycle(_):
            cycles.append(True)
            if len(cycles) == 2:
                raise KeyboardInterrupt
            # Reuse an incoming filename after its original track has been sorted.
            source = next((self.root/'downloads/organized').rglob('*.flac'))
            shutil.copy2(source, self.root/'downloads/a/track.flac')
        with patch.object(sorter.time, 'sleep', side_effect=next_cycle), contextlib.redirect_stderr(io.StringIO()):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = sorter.main(['--root', str(self.root), '--json', 'watch', '--apply', '--min-age', '0'])
            self.assertEqual(code, 130)
        tracks = self.cli('list')['tracks']
        self.assertEqual(len(tracks), 3)
        self.assertEqual(len({t['id'] for t in tracks}), 3)

    def test_exclusive_move_and_changed_file_guards(self):
        source = self.root/'downloads/a/track.flac'
        target = self.root/'downloads/occupied.flac'
        target.write_bytes(b'keep me')
        before = sorter.signature(source)
        with self.assertRaises(FileExistsError):
            sorter.move_exclusive(source, target, before)
        self.assertTrue(source.exists())
        self.assertEqual(target.read_bytes(), b'keep me')
        source.write_bytes(source.read_bytes()+b'modified')
        with self.assertRaises(ValueError):
            sorter.move_exclusive(source, self.root/'downloads/new.flac', before)
        self.assertTrue(source.exists())


if __name__ == '__main__':
    unittest.main()
