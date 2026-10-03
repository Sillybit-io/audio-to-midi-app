#!/bin/zsh
# Usage: fetch-gguf.sh small|medium|large
# Downloads a MuScriptor GGUF from the pinned mirror revision, verifies its SHA-256
# against the sums compiled in below, and prints the verified path.
set -euo pipefail

REPO="DamRsn/muscriptor-gguf"
REVISION="d7045f94e8b19427f4ff9542975035e66596e51c"

size="${1:-}"
case "$size" in
  small)  expected="925f55af65a20ebc4f8b45ceaf095a12b72493d436cb112623cd0041a1af23d4" ;;
  medium) expected="3850cc9e5b436b17a09bd25b8f2615cb3366ab96a71e7b50f73a793a917fdf03" ;;
  large)  expected="35a750fb1ab1e77195cdc2c0b9b4aeea2f4d59f11f729f02af9920c4854ef72e" ;;
  *) echo "usage: $0 small|medium|large" >&2; exit 2 ;;
esac

file="muscriptor-${size}-f16.gguf"
dir="${XDG_CACHE_HOME:-$HOME/.cache}/sillymidi/models"
dest="$dir/$file"
url="https://huggingface.co/$REPO/resolve/$REVISION/v1/$file"
mkdir -p "$dir"

digest() { shasum -a 256 "$1" | cut -d' ' -f1; }

if [[ -f "$dest" && "$(digest "$dest")" == "$expected" ]]; then
  echo "$dest"
  exit 0
fi

rm -f "$dest" "$dest.part"
curl -fL --retry 3 -o "$dest.part" "$url" >&2
if [[ "$(digest "$dest.part")" != "$expected" ]]; then
  rm -f "$dest.part"
  echo "checksum mismatch for $file" >&2
  exit 1
fi
mv "$dest.part" "$dest"
echo "$dest"
