#!/bin/zsh
# Transcribes the engine's bundled fixture with the small model on the CPU.
set -euo pipefail

root="${0:A:h:h}"
engine="$root/Engine/build-$(uname -m)/sillymidi-engine"
model="$("$root/scripts/fetch-gguf.sh" small)"
audio="$root/Engine/muscriptor.cpp/testdata/audio/fixture_3chunks_16k.wav"

last="$("$engine" transcribe --model "$model" --audio "$audio" --device cpu | tail -1)"
count="$(print -r -- "$last" | sed -n 's/.*"type":"done","note_count":\([0-9]*\).*/\1/p')"
if [[ -z "$count" || "$count" -le 0 ]]; then
  echo "smoke failed: $last" >&2
  exit 1
fi
echo "smoke ok: $count"
