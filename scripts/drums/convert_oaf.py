"""Converts the Magenta Onsets and Frames Drums (E-GMD) checkpoint to ONNX and writes the test fixtures.

Usage: convert_oaf.py CHECKPOINT_PREFIX OUT.onnx FIXTURES_DIR [MAGENTA_COMMIT]
Needs the environment built by scripts/convert-drums.sh. Never run at app run time.

The reference for every number is the original TensorFlow graph (oaf_reference.py) restored from the same checkpoint,
fed with librosa's log-mel spectrogram exactly as magenta's data.py computes it.
"""
import sys
import warnings
from pathlib import Path

import librosa
import numpy as np
import onnx
import onnxruntime as ort
import torch

warnings.filterwarnings("ignore")
HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
checkpoint, out_path, fixtures = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
commit = sys.argv[4] if len(sys.argv) > 4 else "unknown"

import drum_clip  # noqa: E402
import oaf_model as om  # noqa: E402
import oaf_reference as ref  # noqa: E402

out_path.parent.mkdir(parents=True, exist_ok=True)
fixtures.mkdir(parents=True, exist_ok=True)
net = om.load_checkpoint(om.DrumsOaF(), checkpoint)

torch.onnx.export(net, torch.randn(1, 44100 * 2) * 0.1, str(out_path), opset_version=17, input_names=["waveform"],
                  output_names=["onset_probs", "velocity"],
                  dynamic_axes={"waveform": {1: "samples"}, "onset_probs": {1: "frames"}, "velocity": {1: "frames"}},
                  do_constant_folding=True)
model = onnx.load(str(out_path))
for key, value in {
    "source": f"magenta/magenta @ {commit}, onsets_frames_transcription, E-GMD checkpoint model.ckpt-569400",
    "license": "Apache-2.0 (code and checkpoint), E-GMD data CC BY 4.0",
    "input": "waveform [1, samples] float32, mono 44.1 kHz, [-1, 1], at least 2049 samples; librosa-style log-mel is part of the graph",
    "output": "onset_probs and velocity [1, samples // 441 + 1, 8] at 100 fps",
    "pitches": ",".join(str(p) for p in om.PITCHES),
}.items():
    entry = model.metadata_props.add()
    entry.key, entry.value = key, value
onnx.checker.check_model(model)
onnx.save(model, str(out_path))
session = ort.InferenceSession(str(out_path), providers=["CPUExecutionProvider"])


def reference_outputs(clip):
    mel = librosa.feature.melspectrogram(y=clip, sr=om.SAMPLE_RATE, hop_length=om.HOP, fmin=om.FMIN, n_mels=om.N_MELS,
                                         htk=True, pad_mode="reflect").astype(np.float32).T
    probs, velocity = ref.run(checkpoint, librosa.power_to_db(mel))
    return probs[:, om.COLUMNS], velocity[:, om.COLUMNS]


def decode(onset, velocity):
    """magenta's drum inference with runs of active frames merged to their strongest frame (see DrumNotes.decodeOaF)."""
    hits = []
    for column, pitch in enumerate(om.PITCHES):
        row = 0
        while row < len(onset):
            if not onset[row, column] > 0.5:
                row += 1
                continue
            best, nxt = row, row
            while nxt < len(onset) and onset[nxt, column] > 0.5:
                if onset[nxt, column] > onset[best, column]:
                    best = nxt
                nxt += 1
            hits.append((best / 100.0, pitch, max(1, int(max(min(float(velocity[best, column]), 1.0), 0.0) * 127.0))))
            row = nxt
    return sorted(hits)


def write_hits(path, hits):
    path.write_text("time_s,pitch,velocity\n" + "".join(f"{t!r},{p},{v}\n" for t, p, v in hits))


# 1. the clip: ONNX Runtime against the original graph
clip = drum_clip.make_clip()
drum_clip.write_wav(fixtures / "drums_synthetic.wav", clip)
pcm = (np.clip(clip, -1, 1) * 32767).astype("<i2")
samples = pcm.astype(np.float32) / 32768  # what the app feeds: 16-bit audio as floats
onset_ref, velocity_ref = reference_outputs(samples)
onset_got, velocity_got = (a[0] for a in session.run(None, {"waveform": samples[None]}))
assert onset_got.shape == onset_ref.shape, (onset_got.shape, onset_ref.shape)
print(f"clip: {len(onset_ref)} frames, max |ONNX - reference| onset {np.abs(onset_got - onset_ref).max():.2e}, "
      f"velocity {np.abs(velocity_got - velocity_ref).max():.2e}")
assert np.abs(onset_got - onset_ref).max() < 1e-3 and np.abs(velocity_got - velocity_ref).max() < 1e-3
onset_ref.astype("<f4").tofile(fixtures / "oaf_clip_onset.f32")
velocity_ref.astype("<f4").tofile(fixtures / "oaf_clip_velocity.f32")
clip_hits = decode(onset_ref, velocity_ref)
write_hits(fixtures / "oaf_clip_hits.csv", clip_hits)
print("clip hits:", len(clip_hits))

# 2. the decoder: random bumps including multi-frame runs, decoded by the python reference
rs = np.random.RandomState(13)
rows = 1500
onset = np.abs(rs.randn(rows, 8)) * 0.03
for column in range(8):
    for _ in range(50):
        centre, width, height = rs.randint(0, rows), rs.randint(0, 4), rs.uniform(0.3, 0.99)
        for k in range(-width, width + 1):
            if 0 <= centre + k < rows:
                onset[centre + k, column] = max(onset[centre + k, column], height * np.exp(-(k / max(width, 1)) ** 2))
onset = np.round(np.clip(onset, 0, 1), 3).astype(np.float32)
velocity = np.round(rs.uniform(-0.2, 1.2, size=(rows, 8)), 3).astype(np.float32)  # out of range on purpose: it is clipped
onset.astype("<f4").tofile(fixtures / "oaf_decoder_onset.f32")
velocity.astype("<f4").tofile(fixtures / "oaf_decoder_velocity.f32")
decoded = decode(onset, velocity)
write_hits(fixtures / "oaf_decoder_hits.csv", decoded)
print("decoder fixture:", len(decoded), "hits")
print(f"wrote {out_path} ({out_path.stat().st_size / 1e6:.2f} MB)")
