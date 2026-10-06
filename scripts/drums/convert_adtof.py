"""Converts the ADTOF Frame_RNN checkpoint to ONNX and writes the test fixtures from the authors' own pipeline.

Usage: convert_adtof.py ADTOF_SOURCE_DIR OUT.onnx FIXTURES_DIR
Needs the environment built by scripts/convert-drums.sh. Never run at app run time.

The reference for every number is the authors' code (MZehren/ADTOF, pinned commit): their Keras model loaded from their
checkpoint, madmom's feature extraction (`mir.openMadmom`) and madmom's `NotePeakPickingProcessor`.
"""
import sys
import warnings
from pathlib import Path
from unittest.mock import MagicMock

import numpy as np
import onnx
import onnxruntime as ort
import torch

warnings.filterwarnings("ignore")
HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
source, out_path, fixtures = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
commit = sys.argv[4] if len(sys.argv) > 4 else "unknown"

import adtof_model as am  # noqa: E402
import drum_clip  # noqa: E402

for name in ("jellyfish", "pyunpack", "ffmpeg", "pretty_midi", "tapcorrect", "bs4", "adtof.io.ccDownloader", "librosa"):
    sys.modules[name] = MagicMock()  # imported by the authors' package but unused for inference
sys.path.insert(0, str(source))
from adtof.io import mir  # noqa: E402
from adtof.model.model import Model  # noqa: E402
import madmom  # noqa: E402

PITCHES = [36, 38, 47, 42, 49]
THRESHOLDS = [0.22, 0.24, 0.32, 0.22, 0.30]
out_path.parent.mkdir(parents=True, exist_ok=True)
fixtures.mkdir(parents=True, exist_ok=True)

reference, hparams = Model.modelFactory(modelName="Frame_RNN", scenario="adtofAll", fold=0)
assert reference.weightLoadedFlag, "the checkpoint did not load"
assert [round(t, 2) for t in hparams["peakThreshold"]] == THRESHOLDS
net = am.load_checkpoint(am.FrameRNN(), str(source / "adtof/models/Frame_RNN_adtofAll_0"))

torch.onnx.export(net, torch.randn(1, 44100 * 2) * 0.1, str(out_path), opset_version=17, input_names=["waveform"],
                  output_names=["activations"], dynamic_axes={"waveform": {1: "samples"}, "activations": {1: "frames"}},
                  do_constant_folding=True)
model = onnx.load(str(out_path))
for key, value in {
    "source": f"MZehren/ADTOF @ {commit}, Frame_RNN_adtofAll_0",
    "license": "CC BY-NC-SA 4.0",
    "input": "waveform [1, samples] float32, mono 44.1 kHz, [-1, 1]; log-filtered spectrogram (madmom) is part of the graph",
    "output": "activations [1, ceil(samples / 441), 5] sigmoid at 100 fps: bass drum, snare, toms, hi-hat, cymbals and ride",
    "pitches": "36,38,47,42,49",
    "thresholds": ",".join(str(t) for t in THRESHOLDS),
}.items():
    entry = model.metadata_props.add()
    entry.key, entry.value = key, value
onnx.checker.check_model(model)
onnx.save(model, str(out_path))
session = ort.InferenceSession(str(out_path), providers=["CPUExecutionProvider"])


def ort_activations(pcm):
    return session.run(None, {"waveform": (pcm.astype(np.float32) / 32768)[None]})[0][0]


def reference_hits(activations):
    hits = []
    for column, (pitch, threshold) in enumerate(zip(PITCHES, THRESHOLDS)):
        picker = madmom.features.notes.NotePeakPickingProcessor(
            threshold=threshold, smooth=0, pre_avg=0.1, post_avg=0.01, pre_max=0.02, post_max=0.01, combine=0.02, fps=100)
        found = picker.process(np.ascontiguousarray(activations[:, [column]]))
        hits += [(float(t), pitch) for t, _ in found]
    return sorted(hits)


def write_hits(path, hits):
    path.write_text("time_s,pitch\n" + "".join(f"{t!r},{p}\n" for t, p in hits))


# 1. the clip: ONNX Runtime against the authors' Keras model on madmom features
clip = drum_clip.make_clip()
wav = fixtures / "drums_synthetic.wav"
drum_clip.write_wav(wav, clip)
pcm = (np.clip(clip, -1, 1) * 32767).astype("<i2")
ref = np.asarray(reference.model.predict_on_batch(mir.openMadmom(str(wav))[None].astype(np.float32)))[0]
got = ort_activations(pcm)
frames = ref.shape[0]
assert got.shape[0] == frames, (got.shape, ref.shape)
diff = float(np.abs(got - ref).max())
print(f"clip: {frames} frames, max |ONNX - reference| = {diff:.2e}")
assert diff < 1e-4, "ONNX activations drifted from the reference"
ref.astype("<f4").tofile(fixtures / "adtof_clip_activations.f32")
write_hits(fixtures / "adtof_clip_hits.csv", reference_hits(ref))
print("clip hits:", len(reference_hits(ref)), "at the reference thresholds")

# 2. the decoder: random bumps, near-duplicates and plateaus, decoded by madmom
rs = np.random.RandomState(11)
rows = 1500
matrix = np.abs(rs.randn(rows, 5)) * 0.03
for column in range(5):
    for _ in range(60):
        centre = rs.randint(0, rows)
        width = rs.randint(1, 5)
        height = rs.uniform(0.2, 0.95)
        for k in range(-width, width + 1):
            if 0 <= centre + k < rows:
                matrix[centre + k, column] = max(matrix[centre + k, column], height * np.exp(-(k / width) ** 2))
        if rs.rand() < 0.4 and centre + 2 < rows:  # a second peak one to three frames later
            matrix[centre + rs.randint(1, 4), column] = max(matrix[centre, column] * rs.uniform(0.8, 1.1), 0)
matrix = np.round(np.clip(matrix, 0, 1), 3).astype(np.float32)  # rounding makes plateaus and ties likely
matrix.astype("<f4").tofile(fixtures / "adtof_decoder_activations.f32")
decoded = reference_hits(matrix)
write_hits(fixtures / "adtof_decoder_hits.csv", decoded)
print("decoder fixture:", len(decoded), "hits")
print(f"wrote {out_path} ({out_path.stat().st_size / 1e6:.2f} MB)")
