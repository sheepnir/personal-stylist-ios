#!/usr/bin/env python3
"""Fail when the iOS client's image-payload guard drifts from the Worker's.

The Worker (backend/workers/src/validation.ts) rejects bodies carrying image-bearing
keys or image-looking values with 415 IMAGE_NOT_ALLOWED. The client
(App/OutfitEngineClient.swift) strips the same keys and values before posting, so
the two token lists must stay identical. Both are extracted with a regex and compared
after ASCII lowercasing (the Worker's patterns use the JS `i` flag; the Swift patterns
are written lowercase and the input is folded by hand).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKER = ROOT / "backend/workers/src/validation.ts"
CLIENT = ROOT / "App/OutfitEngineClient.swift"

WORKER_KEYS = re.compile(r"IMAGE_KEY_PATTERN\s*=\s*/\(\^\|\[\^a-z\]\)\(([^)]+)\)\(\[\^a-z\]\|\$\)/i")
WORKER_VALUES = re.compile(r"IMAGE_VALUE_PATTERN\s*=\s*/([^/]*(?:\\/[^/]*)*)/i")
CLIENT_KEYS = re.compile(r'imageKeyPattern\s*=\s*try!\s*NSRegularExpression\(\s*pattern:\s*"\(\^\|\[\^a-z\]\)\(([^)]+)\)\(\[\^a-z\]\|\$\)"')
CLIENT_VALUES = re.compile(r'imageValuePattern\s*=\s*try!\s*NSRegularExpression\(\s*pattern:\s*"([^"]+)"')


def extract(path: Path, pattern: re.Pattern, what: str) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not find the {what} pattern (regex extraction failed)")
    return [token.replace("\\/", "/").lower() for token in match.group(1).split("|")]


def main() -> int:
    ok = True
    for what, worker_re, client_re in (
        ("image-key token list", WORKER_KEYS, CLIENT_KEYS),
        ("image-value prefix list", WORKER_VALUES, CLIENT_VALUES),
    ):
        worker = extract(WORKER, worker_re, what)
        client = extract(CLIENT, client_re, what)
        if worker != client:
            ok = False
            print(f"MISMATCH {what}:\n  worker: {worker}\n  client: {client}")
        else:
            print(f"OK {what}: {len(worker)} entries match")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
