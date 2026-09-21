#!/usr/bin/env python3
"""Fail if #112 product UI exposes raw HTTP/URL errors or Technical details disclosure."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "Features/Board/OutfitBoardView.swift"

FORBIDDEN_IN_BOARD = [
    re.compile(r"DisclosureGroup\s*\(\s*\"Technical details\""),
    re.compile(r"Engine HTTP"),
    re.compile(r"timeoutInterval"),
]


def main() -> int:
    text = BOARD.read_text(encoding="utf-8")
    errors: list[str] = []
    for pat in FORBIDDEN_IN_BOARD:
        if pat.search(text):
            errors.append(f"{BOARD.relative_to(ROOT)}: matched {pat.pattern!r}")
    dressing = (ROOT / "Design/DressingCopy.swift").read_text(encoding="utf-8")
    for needle in ("generateFailureRetryWithOutfit", "generateFailureRetryNoOutfit"):
        if needle not in dressing:
            errors.append(f"DressingCopy.swift: missing {needle}")
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        return 1
    print("verify-generate-failure-copy: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
