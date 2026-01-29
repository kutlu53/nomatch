#!/usr/bin/env python3
"""
Generate assets/questions/questions_manifest.json by scanning assets/questions.

Rules:
- Supported extensions: .webp .png .jpg .jpeg .avif
- qid is the leading integer in the filename:
    "12brunch.webp" -> qid=12
    "8night-walking.webp" -> qid=8
- Group files by qid
- Only include qids that have exactly 2 files
- If 2 files exist: sort alphabetically, first=top, second=bottom
- Output is sorted by qid ascending

Usage:
  python tools/generate_manifest.py
  py tools/generate_manifest.py   (Windows)
"""

from __future__ import annotations

import json
import re
from pathlib import Path


SUPPORTED_EXTS = {".webp", ".png", ".jpg", ".jpeg", ".avif"}
QID_RE = re.compile(r"^(\d+)")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    questions_dir = repo_root / "assets" / "questions"
    out_path = questions_dir / "questions_manifest.json"

    if not questions_dir.exists():
        print(f"[manifest] missing dir: {questions_dir}")
        return 1

    groups: dict[int, list[Path]] = {}
    skipped: list[str] = []

    for p in sorted(questions_dir.iterdir()):
        if not p.is_file():
            continue
        if p.name == "questions_manifest.json":
            continue
        if p.suffix.lower() not in SUPPORTED_EXTS:
            continue

        m = QID_RE.match(p.stem)
        if not m:
            skipped.append(f"{p.name} (no leading qid)")
            continue

        qid = int(m.group(1))  # leading zeros removed by int()
        groups.setdefault(qid, []).append(p)

    manifest: list[dict[str, object]] = []
    for qid in sorted(groups.keys()):
        files = groups[qid]
        if len(files) != 2:
            skipped.append(f"qid={qid} has {len(files)} files")
            continue

        files_sorted = sorted(files, key=lambda x: x.name.casefold())
        top, bottom = files_sorted[0], files_sorted[1]
        manifest.append(
            {
                "qid": qid,
                "top": f"assets/questions/{top.name}",
                "bottom": f"assets/questions/{bottom.name}",
            }
        )

    out_path.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    print(f"[manifest] wrote {len(manifest)} items -> {out_path}")

    if skipped:
        print("[manifest] skipped (not included):")
        for s in skipped:
            print(f"  - {s}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

