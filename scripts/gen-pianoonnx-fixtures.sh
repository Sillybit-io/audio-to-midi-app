#!/bin/zsh
# Regenerates Tests/Fixtures/PianoOnnx from the reference post-processing of qiuqiangkong/piano_transcription_inference
# (pinned commit), run unmodified on the raw outputs of the LanOss ONNX model with onnxruntime on CPU.
# Needs uv and network access. Never run at app run time.
set -euo pipefail

root="${0:A:h:h}"
out="$root/Tests/Fixtures/PianoOnnx"
work="$root/build/piano-onnx"
model="${SILLYMIDI_PIANO_ONNX:-$HOME/.cache/sillymidi/models/piano_transcription.onnx}"
commit=0226e74cbc805660e34bbd6a8fed2083890ebb88
sha=6ec4f07640837df2fcd2cede9c540865acff341def93fbd6432548dee169195a
url=https://huggingface.co/LanOss/mobimml-piano-transcription/resolve/7dff58faf160d4c0bf13be48e30e614faecdba72/piano_transcription.onnx

mkdir -p "$out" "$work/pti/piano_transcription_inference" "${model:h}"

if [[ ! -f "$model" ]]; then curl -fL "$url" -o "$model"; fi
[[ "$(shasum -a 256 "$model" | cut -d' ' -f1)" == "$sha" ]] || { echo "model checksum mismatch" >&2; exit 1; }

raw="https://raw.githubusercontent.com/qiuqiangkong/piano_transcription_inference/$commit/piano_transcription_inference"
for f in config.py piano_vad.py utilities.py inference.py; do
  curl -fsSL "$raw/$f" -o "$work/pti/piano_transcription_inference/$f"
done
: > "$work/pti/piano_transcription_inference/__init__.py"
cat > "$work/pti/piano_transcription_inference/models.py" <<'PY'
Regress_onset_offset_frame_velocity_CRNN = Note_pedal = None
PY
cat > "$work/pti/piano_transcription_inference/pytorch_utils.py" <<'PY'
move_data_to_device = forward = None
PY

uv venv --clear --python 3.10 "$work/venv" >/dev/null
uv pip install --python "$work/venv/bin/python" "onnxruntime==1.19.2" "numpy<2" soundfile >/dev/null

"$work/venv/bin/python" - "$root" "$out" "$work/pti" "$model" <<'PY'
import csv, json, sys, wave
from pathlib import Path
from unittest.mock import MagicMock
import numpy as np
import onnxruntime as ort
import soundfile as sf

root, out, pkg, model = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
for name in ("torch", "librosa", "audioread", "mido", "matplotlib", "torchlibrosa"):
    sys.modules[name] = MagicMock()
sys.path.insert(0, pkg)
from piano_transcription_inference.inference import PianoTranscription
from piano_transcription_inference.utilities import RegressionPostProcessor

SEGMENT = 160000
KEYS = ["reg_onset_output", "reg_offset_output", "frame_output", "velocity_output",
        "reg_pedal_onset_output", "reg_pedal_offset_output", "pedal_frame_output"]
options = ort.SessionOptions()
options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_DISABLE_ALL  # 1.19.2 mis-fuses this graph
session = ort.InferenceSession(model, options, providers=["CPUExecutionProvider"])
helper = object.__new__(PianoTranscription)

def raw_outputs(audio):
    audio = audio[None, :]
    audio_len = audio.shape[1]
    pad = int(np.ceil(audio_len / SEGMENT)) * SEGMENT - audio_len
    audio = np.concatenate((audio, np.zeros((1, pad))), axis=1)
    segments = helper.enframe(audio, SEGMENT)
    parts = {k: [] for k in KEYS}
    for segment in segments:
        result = session.run(KEYS, {"waveform": segment[None, :].astype(np.float32)})
        for k, v in zip(KEYS, result):
            parts[k].append(v)
    merged = {k: helper.deframe(np.concatenate(v, axis=0))[0:audio_len] for k, v in parts.items()}
    return merged, len(segments)

def post(output_dict):
    processor = RegressionPostProcessor(100, classes_num=88, onset_threshold=0.3, offset_threshold=0.3,
                                        frame_threshold=0.1, pedal_offset_threshold=0.2)
    notes, _ = processor.output_dict_to_midi_events({k: v.copy() for k, v in output_dict.items()})
    return sorted(notes, key=lambda n: (n["onset_time"], n["midi_note"]))

def write_csv(path, notes):
    with open(path, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["onset_s", "offset_s", "pitch", "velocity"])
        for n in notes:
            w.writerow([repr(float(n["onset_time"])), repr(float(n["offset_time"])), n["midi_note"], n["velocity"]])

# Synthetic piano-like clip: decaying harmonic tones, 16 kHz mono 16-bit, 6 seconds.
rate = 16000
clip = np.zeros(6 * rate)
def tone(pitch, start, length):
    f = 440 * 2 ** ((pitch - 69) / 12)
    t = np.arange(int(length * rate)) / rate
    wave_ = sum((0.6 / h) * np.sin(2 * np.pi * f * h * t) for h in range(1, 7)) * np.exp(-1.6 * t)
    wave_ *= np.minimum(1, t / 0.01)
    a = int(start * rate)
    clip[a:a + len(wave_)] += wave_
for pitch, start, length in [(60, 0.3, 1.6), (64, 1.2, 1.6), (67, 2.1, 1.6), (48, 2.1, 1.6), (72, 3.4, 1.2)]:
    tone(pitch, start, length)
clip = 0.5 * clip / np.abs(clip).max()
with wave.open(str(out / "piano_synthetic.wav"), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes((clip * 32767).astype("<i2").tobytes())
synthetic = sf.read(str(out / "piano_synthetic.wav"), dtype="float32")[0]

outputs, segments = raw_outputs(synthetic)
write_csv(out / "piano_synthetic_notes.csv", post(outputs))

CROP = 400
for key in ("reg_onset_output", "reg_offset_output", "frame_output", "velocity_output"):
    np.ascontiguousarray(outputs[key][:CROP], dtype="<f4").tofile(out / f"piano_{key}.f32")
cropped = {k: v[:CROP] for k, v in outputs.items()}
write_csv(out / "piano_matrices_notes.csv", post(cropped))

fixture = sf.read(str(root / "Engine/muscriptor.cpp/testdata/audio/fixture_3chunks_16k.wav"), dtype="float32")[0]
fixture_outputs, fixture_segments = raw_outputs(fixture)
write_csv(out / "piano_fixture_notes.csv", post(fixture_outputs))

(out / "piano_manifest.json").write_text(json.dumps({
    "reference": "piano_transcription_inference " + Path(pkg).parent.name + " pinned commit, LanOss ONNX, onnxruntime 1.19.2 CPU",
    "sample_rate": rate, "segment_samples": SEGMENT, "matrix_frames": CROP, "classes": 88,
    "onset_threshold": 0.3, "offset_threshold": 0.3, "frame_threshold": 0.1,
}, indent=2) + "\n")
print("synthetic notes", len(post(outputs)), "segments", segments, "| cropped", len(post(cropped)),
      "| fixture notes", len(post(fixture_outputs)), "segments", fixture_segments)
PY
