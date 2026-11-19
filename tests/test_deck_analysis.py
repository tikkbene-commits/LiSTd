import math
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import crate_backend as crate


class DeckAnalysisTests(unittest.TestCase):
    def test_fractional_tempo_and_grid_do_not_accumulate_quantization_drift(self):
        import numpy as np
        bpm, cue, rate = 123.45, 0.173, 8000
        times = np.arange(rate * 80) / rate
        phase = (times - cue) % (60 / bpm)
        samples = (np.sin(2 * np.pi * 85 * phase) * np.exp(-phase * 70)
                   * (phase < 0.1) * 24000).astype('<i2')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'fractional.wav'
            with wave.open(str(path), 'wb') as output:
                output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
                output.writeframes(samples.tobytes())
            before = path.read_bytes()
            for hint in (None, 122.4):
                result = crate.deck_analysis(path, hint, refine_bpm=True)
                self.assertAlmostEqual(result['bpm'], bpm, delta=0.02)
                self.assertIsNotNone(result['cue'])
                for beat in (0, 120):
                    predicted = result['cue'] + beat * 60 / result['bpm']
                    self.assertAlmostEqual(predicted, cue + beat * 60 / bpm, delta=0.03)
            manual = crate.deck_analysis(path, 123.5)
            self.assertEqual(manual['bpm'], 123.5)
            uncertain = crate.deck_analysis(path, 120)
            self.assertIsNone(uncertain['cue'])
            import librosa
            detect = librosa.beat.beat_track
            def extra_beat(**kwargs):
                tempo, beats = detect(**kwargs)
                middle = len(beats) // 2
                extra = (beats[middle] + beats[middle+1]) // 2
                return tempo, np.sort(np.append(beats, extra))
            with patch.object(librosa.beat, 'beat_track', side_effect=extra_beat):
                corrected = crate.deck_analysis(path, 122.4, refine_bpm=True)
            self.assertAlmostEqual(corrected['bpm'], bpm, delta=0.02)
            self.assertAlmostEqual(corrected['cue'] + 120 * 60 / corrected['bpm'], cue + 120 * 60 / bpm, delta=0.03)
            self.assertEqual(path.read_bytes(), before)

    def test_pulses_and_silence_are_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'beats.wav'
            rate = 8000
            samples = []
            for frame in range(rate * 24):
                t = frame / rate
                phase = (t - 0.2) % 0.5
                value = math.sin(2 * math.pi * 90 * phase) * math.exp(-phase * 50) if phase < 0.12 else 0
                samples.append(round(value * 24000))
            with wave.open(str(path), 'wb') as output:
                output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
                output.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
            before = path.read_bytes()
            result = crate.deck_analysis(path)
            self.assertAlmostEqual(result['bpm'], 120, delta=1)
            self.assertIsNotNone(result['cue'])
            phase = (result['cue'] - 0.2) % 0.5
            self.assertLess(min(phase, 0.5 - phase), 0.08)
            self.assertEqual(path.read_bytes(), before)
            self.assertAlmostEqual(crate.deck_analysis(path, 120)['bpm'], 120)
            with self.assertRaises(ValueError):
                crate.deck_analysis(path, float('nan'))
            with wave.open(str(path), 'wb') as output:
                output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
                output.writeframes(bytes(rate * 5 * 2))
            silent = crate.deck_analysis(path)
            self.assertIsNone(silent['bpm'])
            self.assertIsNone(silent['cue'])


if __name__ == '__main__':
    unittest.main()
