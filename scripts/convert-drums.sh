#!/bin/zsh
# Rebuilds the two drum models as ONNX files from the authors' checkpoints, and regenerates Tests/Fixtures/DrumsOnnx from
# the authors' own reference pipelines:
#   build/models/adtof_frame_rnn.onnx   ADTOF Frame_RNN (MZehren/ADTOF, CC BY-NC-SA 4.0)
#   build/models/oaf_drums.onnx         Onsets and Frames Drums, E-GMD checkpoint (magenta/magenta, Apache-2.0)
# Needs uv and network access. TensorFlow 2.15 and PyTorch 2.2 are pinned, so this is tested on Intel macOS with
# Python 3.11. Takes a few minutes the first time. Never run at app run time.
# Usage: scripts/convert-drums.sh
set -euo pipefail

root="${0:A:h:h}"
work="$root/build/drums"
models="$root/build/models"
fixtures="$root/Tests/Fixtures/DrumsOnnx"
adtof_commit=b3968fb332f69b65ee07c089fc62f436503755db
magenta_commit=c15687ebd1c1cc12658cd468c737d3c24c02b918
madmom_commit=27f032e8947204902c675e5e341a3faf5dc86dae
oaf_zip_url=https://storage.googleapis.com/magentadata/models/onsets_frames_transcription/e-gmd_checkpoint.zip
oaf_zip_sha=09765ae0ff19c7d769a3c20e158eba3b9cd279429b02e498b1e911d16f82e2c0
python="$work/venv/bin/python"

mkdir -p "$work" "$models" "$fixtures"

if [[ ! -x "$python" ]]; then
  uv venv --clear --python 3.11 "$work/venv" >/dev/null
  uv pip install --python "$python" "tensorflow==2.15.1" "tf_keras==2.15.1" tf_slim "numpy<2" "ml_dtypes==0.3.2" \
    "torch==2.2.2" "onnx==1.16.2" "onnxruntime==1.19.2" "librosa==0.10.2.post1" "numba==0.58.1" "llvmlite==0.41.1" \
    scipy soundfile pandas matplotlib scikit-learn mir_eval mido "Cython<3" setuptools wheel >/dev/null
  uv pip install --python "$python" --no-build-isolation "madmom @ git+https://github.com/CPJKU/madmom@$madmom_commit" >/dev/null
fi

if [[ ! -d "$work/ADTOF/.git" ]]; then git clone -q https://github.com/MZehren/ADTOF "$work/ADTOF"; fi
git -C "$work/ADTOF" checkout -q "$adtof_commit"

zip="$work/e-gmd_checkpoint.zip"
if [[ ! -f "$zip" || "$(shasum -a 256 "$zip" | cut -d' ' -f1)" != "$oaf_zip_sha" ]]; then
  curl -fL --retry 3 "$oaf_zip_url" -o "$zip.part"
  mv "$zip.part" "$zip"
fi
[[ "$(shasum -a 256 "$zip" | cut -d' ' -f1)" == "$oaf_zip_sha" ]] || { echo "checkpoint checksum mismatch" >&2; exit 1; }
rm -rf "$work/oaf" && mkdir -p "$work/oaf" && unzip -q "$zip" -d "$work/oaf"

quiet() { grep -v -e "^20[0-9][0-9]-" -e AVX -e rebuild -e WARNING -e "Instructions for" -e "Please use" -e "Call initializer" -e "^$" || true; }

# Each converter asserts that the ONNX output matches its reference, and exits non-zero when it does not.
rm -f "$models/adtof_frame_rnn.onnx" "$models/oaf_drums.onnx"
"$python" "$root/scripts/drums/convert_adtof.py" "$work/ADTOF" "$models/adtof_frame_rnn.onnx" "$fixtures" "$adtof_commit" 2> >(quiet >&2)
"$python" "$root/scripts/drums/convert_oaf.py" "$work/oaf/model.ckpt-569400" "$models/oaf_drums.onnx" "$fixtures" "$magenta_commit" 2> >(quiet >&2)

for f in adtof_frame_rnn oaf_drums; do
  [[ -f "$models/$f.onnx" ]] || { echo "$f.onnx was not written" >&2; exit 1; }
  echo "$f.onnx  $(stat -f%z "$models/$f.onnx") bytes  sha256 $(shasum -a 256 "$models/$f.onnx" | cut -d' ' -f1)"
done
