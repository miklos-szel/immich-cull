#!/usr/bin/env python3
"""Renames exported xcresult attachments to the names the test gave them.

`xcresulttool export attachments` writes opaque filenames plus a
manifest.json mapping them back to the attachment names. This flattens that
into `<name>.png` and removes everything else, so docs/screenshots/ holds
nothing but the images the README references.
"""
import json
import shutil
import sys
from pathlib import Path


def main(out_dir: Path) -> int:
    manifest_path = out_dir / "manifest.json"
    if not manifest_path.exists():
        print(f"No manifest at {manifest_path}; nothing renamed.", file=sys.stderr)
        return 1

    manifest = json.loads(manifest_path.read_text())
    renamed = 0
    # The manifest is a list of per-test entries, each with its attachments.
    for entry in manifest:
        for attachment in entry.get("attachments", []):
            exported = attachment.get("exportedFileName")
            suggested = attachment.get("suggestedHumanReadableName") or attachment.get("name")
            if not exported or not suggested:
                continue
            source = out_dir / exported
            if not source.exists():
                continue
            # The exporter appends "_<index>_<uuid>" to the name the test set;
            # keep only the part before it.
            stem = Path(suggested).stem.split("_", 1)[0]
            shutil.move(source, out_dir / f"{stem}.png")
            renamed += 1

    manifest_path.unlink()
    # Drop anything the exporter left behind that isn't one of our images.
    for leftover in out_dir.iterdir():
        if leftover.suffix != ".png":
            shutil.rmtree(leftover) if leftover.is_dir() else leftover.unlink()

    print(f"Renamed {renamed} screenshots.")
    return 0 if renamed else 1


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1])))
