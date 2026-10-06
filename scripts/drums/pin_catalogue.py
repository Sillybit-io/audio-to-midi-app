#!/usr/bin/env python3
"""Points App/Models/ModelCatalog.swift at the uploaded drum models.

Usage: pin_catalogue.py CATALOGUE.swift HF_USER ADTOF_REVISION OAF_REVISION MODELS_DIR

Rewrites every line that carries a `// drum-models:<marker>` comment: the owner, one revision per repository, and the size
and SHA-256 of the files in MODELS_DIR. Called by scripts/publish-drum-models.sh after the upload.
"""
import hashlib
import pathlib
import re
import sys

MARKERS = ("owner", "adtof-revision", "oaf-revision", "adtof-size", "adtof-sha", "oaf-size", "oaf-sha")


def pin(text, user, adtof_revision, oaf_revision, models):
    def digest(name):
        path = pathlib.Path(models) / name
        return hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_size

    adtof_sha, adtof_size = digest("adtof_frame_rnn.onnx")
    oaf_sha, oaf_size = digest("oaf_drums.onnx")
    lines = {
        "owner": f'private static let drumsOwner = "{user}"',
        "adtof-revision": f'private static let drumsAdtofRevision = "{adtof_revision}"',
        "oaf-revision": f'private static let drumsOafRevision = "{oaf_revision}"',
        "adtof-size": f"byteSize: {adtof_size:_},",
        "adtof-sha": f'sha256: "{adtof_sha}",',
        "oaf-size": f"byteSize: {oaf_size:_},",
        "oaf-sha": f'sha256: "{oaf_sha}",',
    }
    for marker in MARKERS:
        pattern = re.compile(r"^([ \t]*)\S.*// drum-models:" + re.escape(marker) + r".*$", re.M)
        if len(pattern.findall(text)) != 1:
            raise SystemExit(f"expected exactly one line marked drum-models:{marker}")
        text = pattern.sub(lambda m: m.group(1) + lines[marker] + " // drum-models:" + marker, text)
    return text


if __name__ == "__main__":
    catalogue, user, adtof_revision, oaf_revision, models = sys.argv[1:6]
    for revision in (adtof_revision, oaf_revision):
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise SystemExit(f"{revision!r} is not a 40-character commit hash")
    path = pathlib.Path(catalogue)
    path.write_text(pin(path.read_text(), user, adtof_revision, oaf_revision, models))
