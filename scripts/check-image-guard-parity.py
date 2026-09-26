#!/usr/bin/env python3
"""Fail when the iOS client's image-payload guard drifts from the Worker's.

Compares forbidden-token lists and the consent-field path extracted from
backend/workers/src/validation.ts and App/OutfitEngineClient.swift, then runs
fixtures/image-guard/corpus.json through the Worker's vitest harness (the
canonical evaluation — no duplicated guard logic in this script).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "fixtures/image-guard/corpus.json"
WORKER = ROOT / "backend/workers/src/validation.ts"
CLIENT = ROOT / "App/OutfitEngineClient.swift"
WORKERS_DIR = ROOT / "backend/workers"

FORBIDDEN_LEGACY_SUBSTRINGS = (
    "WORKER_KEYS = re.compile",
    "CLIENT_KEYS = re.compile",
)

WORKER_TOKENS = re.compile(
    r"export const FORBIDDEN_IMAGE_KEY_TOKENS = \[([\s\S]*?)\] as const;",
    re.MULTILINE,
)
CLIENT_TOKENS = re.compile(
    r"private static let forbiddenImageKeyTokens = \[([\s\S]*?)\]",
    re.MULTILINE,
)
WORKER_CONSENT_PATH = re.compile(
    r"export const IMAGE_GUARD_CONSENT_FIELD_PATH = '([^']+)';"
)
CLIENT_CONSENT_PATH = re.compile(
    r'private static let imageGuardConsentFieldPath = "([^"]+)"'
)


def extract_tokens(path: Path, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract forbidden token list")
    raw = match.group(1)
    return [m.group(1).lower() for m in re.finditer(r"""['"]([^'"]+)['"]""", raw)]


def extract_consent_path(path: Path, pattern: re.Pattern[str]) -> str:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract consent field path")
    return match.group(1)


def assert_no_legacy_pattern_copy(source: str) -> None:
    for marker in FORBIDDEN_LEGACY_SUBSTRINGS:
        if marker in source:
            sys.exit(
                "scripts/check-image-guard-parity.py must not embed legacy regex "
                f"pattern copies (found {marker!r}); use the shared corpus + Worker vitest only."
            )


def load_corpus() -> dict:
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    for key in ("keySegments", "rejectBodies", "allowBodies"):
        if key not in corpus or not isinstance(corpus[key], list):
            sys.exit(f"{CORPUS.relative_to(ROOT)}: missing or invalid {key!r} list")
    return corpus


def run_worker_vitest_corpus() -> None:
    result = subprocess.run(
        ["npm", "test", "--", "image-guard-corpus"],
        cwd=WORKERS_DIR,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        sys.exit("Worker vitest corpus check failed")


def main() -> int:
    script_source = Path(__file__).read_text(encoding="utf-8")
    assert_no_legacy_pattern_copy(script_source)

    worker_tokens = extract_tokens(WORKER, WORKER_TOKENS)
    client_tokens = extract_tokens(CLIENT, CLIENT_TOKENS)
    worker_consent = extract_consent_path(WORKER, WORKER_CONSENT_PATH)
    client_consent = extract_consent_path(CLIENT, CLIENT_CONSENT_PATH)

    if worker_tokens != client_tokens:
        print(f"MISMATCH forbidden tokens:\n  worker: {worker_tokens}\n  client: {client_tokens}")
        return 1
    print(f"OK forbidden tokens: {len(worker_tokens)} entries match")

    if worker_consent != client_consent:
        print(f"MISMATCH consent path:\n  worker: {worker_consent}\n  client: {client_consent}")
        return 1
    print(f"OK consent path: {worker_consent}")

    corpus = load_corpus()
    print(
        f"OK corpus loaded: {len(corpus['keySegments'])} key segments, "
        f"{len(corpus.get('allowGuardedEndpointKeys', []))} guarded-endpoint keys, "
        f"{len(corpus['rejectBodies'])} reject bodies, "
        f"{len(corpus['allowBodies'])} allow bodies"
    )

    run_worker_vitest_corpus()
    print("OK worker vitest image-guard-corpus")
    return 0


if __name__ == "__main__":
    sys.exit(main())
