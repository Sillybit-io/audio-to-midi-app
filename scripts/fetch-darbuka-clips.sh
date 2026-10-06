#!/bin/zsh
# Downloads two solo darbuka recordings for the end-to-end hand percussion tests, as 44.1 kHz mono WAV in build/percussion.
# They are CC BY-SA 4.0 recordings from Wikimedia Commons (Maksum and Saidi, the two Egyptian rhythms), used only as
# test input and not part of the app or the repository. Converting needs uv (https://docs.astral.sh/uv/).
# Usage: scripts/fetch-darbuka-clips.sh [destination]   default: build/percussion
set -euo pipefail

root="${0:A:h:h}"
dest="${1:-$root/build/percussion}"
base=https://upload.wikimedia.org/wikipedia/commons
mkdir -p "$dest"

for clip in a/a7/Maksum_Ejemplo 9/98/Saidi_Ejemplo; do
  name="${clip:t}"
  [[ -f "$dest/$name.wav" ]] && continue
  curl -fsL --retry 3 -A "silly-midi-tools-tests/1.0" "$base/$clip.ogg" -o "$dest/$name.ogg"
  uvx --with soundfile --with numpy --with scipy python - "$dest/$name.ogg" "$dest/$name.wav" <<'PY'
import sys, numpy as np, soundfile as sf
from math import gcd
from scipy.signal import resample_poly
x, sr = sf.read(sys.argv[1], dtype="float32")
if x.ndim > 1: x = x.mean(axis=1)
if sr != 44100:
    g = gcd(44100, sr); x = resample_poly(x, 44100 // g, sr // g).astype("float32")
sf.write(sys.argv[2], x, 44100, subtype="PCM_16")
PY
  rm -f "$dest/$name.ogg"
done
echo "darbuka clips ready in $dest"
