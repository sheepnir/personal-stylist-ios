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
    # #45 / #46 (spec R10): never surface promptVersion or raw fallbackReason values.
    re.compile(r"promptVersion"),
    re.compile(r"\bfallbackReason\b"),
]

# #46: fallback notice copy — Designer strings present, no implementation language (#24).
FALLBACK_NOTICE = ROOT / "Design/FallbackNoticeCopy.swift"
FALLBACK_NOTICE_REQUIRED = [
    "Built without the AI stylist",
    "The AI stylist wasn't available, so the app put this one together from your wardrobe.",
    "The AI stylist couldn't come up with a usable outfit this time, so the app put this one together from your wardrobe.",
    "The AI stylist reached its usage limit, so the app put this one together from your wardrobe.",
    "It'll be back after the limit resets.",
    "This time the app put this outfit together from your wardrobe on its own.",
]
FALLBACK_NOTICE_FORBIDDEN_WORDS = re.compile(
    r"fallback|provider|deterministic|engine|model|http|openrouter|_", re.IGNORECASE
)


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
    notice = FALLBACK_NOTICE.read_text(encoding="utf-8")
    for needle in FALLBACK_NOTICE_REQUIRED:
        if f'"{needle}"' not in notice:
            errors.append(f"FallbackNoticeCopy.swift: missing Designer string {needle!r}")
    for literal in re.findall(r'static let \w+ = "([^"]*)"', notice):
        if FALLBACK_NOTICE_FORBIDDEN_WORDS.search(literal):
            errors.append(f"FallbackNoticeCopy.swift: implementation language in {literal!r}")
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        return 1
    print("verify-generate-failure-copy: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
