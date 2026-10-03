#!/bin/zsh
# Regenerates Tests/Fixtures/BasicPitch from the reference Python implementation (basic-pitch at commit fa5997a),
# run on the vendored Core ML model with CPU-only compute units. Needs uv. Never run at app run time.
set -euo pipefail

root="${0:A:h:h}"
out="$root/Tests/Fixtures/BasicPitch"
venv="$root/build/bp-venv"
mkdir -p "$out" "$root/build"

uv venv --clear --python 3.10 "$venv" >/dev/null
uv pip install --python "$venv/bin/python" "basic-pitch @ git+https://github.com/spotify/basic-pitch@fa5997af0a8210982619003269994a1be25eddf3" "setuptools<81" "numba==0.60.0" "llvmlite==0.43.0" "numpy<2" >/dev/null

"$venv/bin/python" - "$root" "$out" <<'PY'
import csv, json, sys, wave
from pathlib import Path
import numpy as np
from basic_pitch.inference import predict

root, out = Path(sys.argv[1]), Path(sys.argv[2])
model = root / "App/Resources/BasicPitch/BasicPitch.mlpackage"
fixture = root / "Engine/muscriptor.cpp/testdata/audio/fixture_3chunks_16k.wav"

# Synthetic clip: C4, E4, G4 sines, one second each, 22050 Hz mono, 16-bit.
sr = 22050
samples = []
for hz in (261.6256, 329.6276, 391.9954):
    t = np.arange(sr) / sr
    wave_ = 0.5 * np.sin(2 * np.pi * hz * t)
    fade = np.minimum(1, np.minimum(t, 1 - t) / 0.01)
    samples.append(wave_ * fade)
pcm = (np.concatenate(samples) * 32767).astype("<i2")
synth = out / "synthetic.wav"
with wave.open(str(synth), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())

def write_csv(path, notes):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["start_s", "end_s", "pitch", "amplitude", "bends"])
        for s, e, p, a, b in sorted(notes, key=lambda n: (n[0], n[2])):
            w.writerow([repr(float(s)), repr(float(e)), int(p), repr(float(a)), ";".join(str(int(x)) for x in b) if b else ""])

output, _, notes = predict(synth, model)
write_csv(out / "synthetic_notes.csv", notes)
shapes = {}
for key in ("note", "onset", "contour"):
    arr = np.ascontiguousarray(output[key], dtype="<f4")
    arr.tofile(out / f"synthetic_{key}.f32")
    shapes[key] = list(arr.shape)

_, _, fixture_notes = predict(fixture, model)
write_csv(out / "fixture_notes.csv", fixture_notes)

(out / "manifest.json").write_text(json.dumps({
    "reference": "basic-pitch fa5997a, vendored nmp.mlpackage, CPU_ONLY",
    "sample_rate": sr, "shapes": shapes,
    "onset_threshold": 0.5, "frame_threshold": 0.3, "min_note_len_frames": 11,
}, indent=2) + "\n")
print("notes", len(notes), len(fixture_notes), shapes)
PY
