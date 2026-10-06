#!/bin/zsh
# Uploads the two converted drum models to your Hugging Face account and pins the catalogue to what was uploaded.
#   <user>/adtof-drums-onnx   adtof_frame_rnn.onnx  CC BY-NC-SA 4.0
#   <user>/oaf-drums-onnx     oaf_drums.onnx         Apache-2.0
# Each repository gets the model, its licence text, the attribution notice and a model card. Both stay public and
# ungated: the app asks for the licence terms itself before it downloads.
#
# Run scripts/convert-drums.sh first. Then log in once with a token that can write (huggingface.co/settings/tokens):
#   uvx --from huggingface_hub hf auth login
# Usage: scripts/publish-drum-models.sh HF_USERNAME [--dry-run]
#   --dry-run  stages the repositories under build/drums/publish and prints what would happen; uploads and edits nothing.
set -euo pipefail

root="${0:A:h:h}"
user="${1:?usage: scripts/publish-drum-models.sh HF_USERNAME [--dry-run]}"
dry=false; [[ "${2:-}" == "--dry-run" ]] && dry=true
models="$root/build/models"
stage="$root/build/drums/publish"
catalogue="$root/App/Models/ModelCatalog.swift"
licenses="$root/App/Resources/Licenses"
hfcli() { if whence -p hf >/dev/null; then command hf "$@"; else uvx --from huggingface_hub hf "$@"; fi }

stage_repo() { # name file licence-file notice-file spdx tags-extra
  local name="$1" file="$2" licence="$3" notice="$4" spdx="$5"
  local dir="$stage/$name"
  [[ -f "$models/$file" ]] || { echo "$models/$file is missing; run scripts/convert-drums.sh" >&2; exit 1; }
  rm -rf "$dir" && mkdir -p "$dir"
  cp "$models/$file" "$dir/$file"
  cp "$licenses/$licence" "$dir/LICENSE"
  cp "$licenses/$notice" "$dir/NOTICE.md"
  {
    echo "---"
    echo "license: $spdx"
    echo "library_name: onnxruntime"
    echo "tags: [onnx, onnxruntime, drum-transcription, music-transcription, audio-to-midi]"
    echo "---"
    echo
    cat "$root/scripts/drums/cards/$name.md"
    echo
    echo "See NOTICE.md for the attribution and the changes made, and LICENSE for the licence text."
  } > "$dir/README.md"
}

stage_repo adtof-drums-onnx adtof_frame_rnn.onnx CC-BY-NC-SA-4.0.txt AdtofNotice.md cc-by-nc-sa-4.0
stage_repo oaf-drums-onnx oaf_drums.onnx Apache-2.0.txt OafDrumsNotice.md apache-2.0

if $dry; then
  echo "dry run: staged"; find "$stage" -type f | sort | sed "s|$root/||"
  exit 0
fi

revision() { curl -fsSL "https://huggingface.co/api/models/$1" | python3 -c "import sys, json; print(json.load(sys.stdin)['sha'])"; }
declare -A revisions
for name in adtof-drums-onnx oaf-drums-onnx; do
  hfcli repos create "$user/$name" --repo-type model --public --exist-ok >/dev/null
  hfcli upload "$user/$name" "$stage/$name" . --repo-type model --commit-message "Publish $name" >/dev/null
  revisions[$name]="$(revision "$user/$name")"
  echo "$name pinned at ${revisions[$name]}"
done

# Download each file back from its pinned revision, exactly as the app will, and compare.
check() { # name file
  local url="https://huggingface.co/$user/$1/resolve/${revisions[$1]}/$2" tmp; tmp="$(mktemp)"
  curl -fL --retry 3 -s "$url" -o "$tmp"
  [[ "$(shasum -a 256 "$tmp" | cut -d' ' -f1)" == "$(shasum -a 256 "$models/$2" | cut -d' ' -f1)" ]] \
    || { echo "downloaded $2 differs from the file that was uploaded" >&2; rm -f "$tmp"; exit 1; }
  rm -f "$tmp"; echo "$2 downloads intact from $url"
}
check adtof-drums-onnx adtof_frame_rnn.onnx
check oaf-drums-onnx oaf_drums.onnx

"$root/scripts/drums/pin_catalogue.py" "$catalogue" "$user" "${revisions[adtof-drums-onnx]}" "${revisions[oaf-drums-onnx]}" "$models"
echo "ModelCatalog.swift now points at $user/adtof-drums-onnx and $user/oaf-drums-onnx. Run the tests and commit it."
