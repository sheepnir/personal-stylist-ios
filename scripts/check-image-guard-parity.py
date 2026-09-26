#!/usr/bin/env python3
"""Fail when the iOS client's image-payload guard drifts from the Worker's.

Loads fixtures/image-guard/corpus.json and evaluates each case with the same
normalization + token rules as backend/workers/src/validation.ts and
App/OutfitEngineClient.swift. Constant lists and the consent-field path are
extracted from both sources and must match before the corpus runs.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "fixtures/image-guard/corpus.json"
WORKER = ROOT / "backend/workers/src/validation.ts"
CLIENT = ROOT / "App/OutfitEngineClient.swift"
WORKERS_DIR = ROOT / "backend/workers"

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

IMAGE_VALUE_PREFIXES = ("data:image/", "/9j/", "ivborw0kggo")
ECMA_WHITESPACE = {
    0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0, 0x1680,
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
    0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
}
CONSENT_MAX_LEN = 64


def parse_iso8601_datetime(value: str) -> bool:
    """Match Worker/Swift: ISO-8601 date-time with a time component, real parse."""
    if "T" not in value:
        return False
    normalized = value.replace("Z", "+00:00") if value.endswith("Z") else value
    try:
        datetime.fromisoformat(normalized)
        return True
    except ValueError:
        return False


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


def normalize_key(key: str) -> str:
    out: list[str] = []
    for ch in key:
        o = ord(ch)
        if 65 <= o <= 90:
            out.append(chr(o + 32))
        elif ch not in "_-":
            out.append(ch)
    return "".join(out)


def segment_image_bearing(key: str, tokens: list[str]) -> bool:
    normalized = normalize_key(key)
    return any(token in normalized for token in tokens)


def js_trim_start(value: str) -> str:
    i = 0
    while i < len(value) and ord(value[i]) in ECMA_WHITESPACE:
        i += 1
    return value[i:]


def looks_like_image_data(value: str) -> bool:
    folded = js_trim_start(value).translate(
        str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")
    )
    return folded.startswith(IMAGE_VALUE_PREFIXES)


def allowed_consent_timestamp(value: object) -> bool:
    if not isinstance(value, str):
        return False
    if not value or len(value) > CONSENT_MAX_LEN:
        return False
    return parse_iso8601_datetime(value)


def join_path(parent: str, key: str) -> str:
    return f"{parent}.{key}" if parent else key


def body_contains_image(value: object, consent_path: str, tokens: list[str], path: str = "") -> bool:
    if isinstance(value, str):
        return looks_like_image_data(value)
    if isinstance(value, list):
        return any(body_contains_image(item, consent_path, tokens, path) for item in value)
    if isinstance(value, dict):
        for key, child in value.items():
            key_path = join_path(path, key)
            if key_path == consent_path:
                if not allowed_consent_timestamp(child):
                    return True
                continue
            if segment_image_bearing(key, tokens):
                return True
            if body_contains_image(child, consent_path, tokens, key_path):
                return True
    return False


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
    worker_tokens = extract_tokens(WORKER, WORKER_TOKENS)
    client_tokens = extract_tokens(CLIENT, CLIENT_TOKENS)
    worker_consent = extract_consent_path(WORKER, WORKER_CONSENT_PATH)
    client_consent = extract_consent_path(CLIENT, CLIENT_CONSENT_PATH)

    ok = True
    if worker_tokens != client_tokens:
        ok = False
        print(f"MISMATCH forbidden tokens:\n  worker: {worker_tokens}\n  client: {client_tokens}")
    else:
        print(f"OK forbidden tokens: {len(worker_tokens)} entries match")

    if worker_consent != client_consent:
        ok = False
        print(f"MISMATCH consent path:\n  worker: {worker_consent}\n  client: {client_consent}")
    else:
        print(f"OK consent path: {worker_consent}")

    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    for entry in corpus["keySegments"]:
        key = entry["key"]
        expect = entry["imageBearing"]
        got = segment_image_bearing(key, worker_tokens)
        if got != expect:
            ok = False
            print(f"FAIL keySegments {key!r}: expected imageBearing={expect}, got {got}")

    for key in corpus.get("allowGuardedEndpointKeys", []):
        if segment_image_bearing(key, worker_tokens):
            ok = False
            print(f"FAIL allowGuardedEndpointKeys {key!r}: must not be image-bearing")

    for entry in corpus["rejectBodies"]:
        body = entry["body"]
        if not body_contains_image(body, worker_consent, worker_tokens):
            ok = False
            print(f"FAIL rejectBodies ({entry.get('label', body)}): expected reject, got allow")

    for entry in corpus["allowBodies"]:
        body = entry["body"]
        if body_contains_image(body, worker_consent, worker_tokens):
            ok = False
            print(f"FAIL allowBodies ({entry.get('label', body)}): expected allow, got reject")

    if not ok:
        return 1

    print(f"OK corpus: {len(corpus['keySegments'])} keys, "
          f"{len(corpus.get('allowGuardedEndpointKeys', []))} guarded-endpoint keys, "
          f"{len(corpus['rejectBodies'])} reject bodies, "
          f"{len(corpus['allowBodies'])} allow bodies")

    run_worker_vitest_corpus()
    print("OK worker vitest image-guard-corpus")
    return 0


if __name__ == "__main__":
    sys.exit(main())
