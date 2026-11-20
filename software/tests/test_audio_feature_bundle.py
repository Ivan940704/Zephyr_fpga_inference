import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from software.audio_feature_bundle import (
    FeatureBundleError,
    build_feature_bundle,
    load_feature_bundle,
    magnitude_for_accelerator,
    pack_magnitude_frames_q12,
    pack_spectrum_frames_int8,
    read_pcm16,
    stft_centered,
)
from software.pynq.run_accelerator_inference import write_pcm16


class AudioFeatureBundleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        time_axis = np.arange(4096, dtype=np.float32) / np.float32(16000.0)
        self.input_wav = self.root / "input.wav"
        write_pcm16(
            self.input_wav,
            (0.2 * np.sin(2.0 * np.pi * 440.0 * time_axis)).astype(np.float32),
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_round_trip_is_exact_and_source_bound(self):
        bundle_dir = self.root / "bundle"
        record = build_feature_bundle(self.input_wav, bundle_dir)
        samples = read_pcm16(self.input_wav)
        expected_spectrum = stft_centered(samples)
        expected_magnitude = magnitude_for_accelerator(expected_spectrum)
        loaded = load_feature_bundle(
            bundle_dir, source_wav=self.input_wav, source_samples=samples.size
        )
        self.assertEqual(record["frame_count"], expected_spectrum.shape[1])
        self.assertTrue(np.array_equal(loaded.spectrum, expected_spectrum))
        self.assertTrue(np.array_equal(loaded.magnitude, expected_magnitude))
        self.assertEqual(loaded.magnitude.dtype, np.float32)
        self.assertEqual(loaded.spectrum.dtype, np.complex64)
        self.assertTrue(
            np.array_equal(
                loaded.magnitude_q12,
                pack_magnitude_frames_q12(expected_magnitude),
            )
        )
        self.assertTrue(
            np.array_equal(
                loaded.spectrum_q,
                pack_spectrum_frames_int8(expected_spectrum),
            )
        )
        self.assertEqual(loaded.magnitude_q12.shape, (expected_spectrum.shape[1], 512))
        self.assertEqual(loaded.spectrum_q.shape, (expected_spectrum.shape[1], 512))

    def test_legacy_bundle_loads_without_prepacked_dma_arrays(self):
        bundle_dir = self.root / "bundle"
        build_feature_bundle(self.input_wav, bundle_dir)
        metadata_path = bundle_dir / "metadata.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metadata["schema"] = "zephyr.audio-feature-bundle.v1"
        metadata.pop("packed_abi")
        metadata.pop("magnitude_q12")
        metadata.pop("spectrum_q")
        metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
        loaded = load_feature_bundle(bundle_dir, source_wav=self.input_wav)
        self.assertIsNone(loaded.magnitude_q12)
        self.assertIsNone(loaded.spectrum_q)

    def test_stale_source_is_rejected(self):
        bundle_dir = self.root / "bundle"
        build_feature_bundle(self.input_wav, bundle_dir)
        metadata_path = bundle_dir / "metadata.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metadata["source_sha256"] = "0" * 64
        metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
        with self.assertRaisesRegex(FeatureBundleError, "input-wav SHA-256"):
            load_feature_bundle(bundle_dir, source_wav=self.input_wav)


if __name__ == "__main__":
    unittest.main()
