#!/bin/zsh
# Downloads the pinned piano transcription ONNX model for the end-to-end tests (the app downloads it itself).
# Usage: scripts/fetch-piano-onnx.sh [destination]   default: build/models/piano_transcription.onnx
set -euo pipefail

root="${0:A:h:h}"
dest="${1:-$root/build/models/piano_transcription.onnx}"
url=https://huggingface.co/LanOss/mobimml-piano-transcription/resolve/7dff58faf160d4c0bf13be48e30e614faecdba72/piano_transcription.onnx
sha=6ec4f07640837df2fcd2cede9c540865acff341def93fbd6432548dee169195a

mkdir -p "${dest:h}"
if [[ ! -f "$dest" || "$(shasum -a 256 "$dest" | cut -d' ' -f1)" != "$sha" ]]; then
  curl -fL --retry 3 "$url" -o "$dest.part"
  mv "$dest.part" "$dest"
fi
[[ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" == "$sha" ]] || { rm -f "$dest"; echo "checksum mismatch" >&2; exit 1; }
echo "piano model ready: $dest"
