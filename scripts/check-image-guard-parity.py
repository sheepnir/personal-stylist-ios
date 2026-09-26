#!/usr/bin/env python3
"""Fail when the iOS client's image-payload guard drifts from the Worker's.

Compares forbidden-token lists, consent path segments, RFC 3339 consent regex,
printable-ASCII key bounds, key-separator and ECMAScript-whitespace code points,
image-value regex and prefix lists (Worker vs App/OutfitEngineClient.swift), runs
a legitimate-key sweep (OpenAPI + fixtures + corpus), then runs
fixtures/image-guard/corpus.json through the Worker's vitest harness. Swift corpus
coverage is in Tests/OutfitEngineImagePayloadTests (Xcode CI).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "fixtures/image-guard/corpus.json"
OPENAPI = ROOT / "docs/openapi.yaml"
FIXTURES_WARDROBE = ROOT / "fixtures/wardrobe"
FIXTURES_PROFILE = ROOT / "fixtures/profile"
WORKER_KEY = ROOT / "backend/workers/src/imageGuardKey.ts"
WORKER = ROOT / "backend/workers/src/validation.ts"
WORKER_CONSENT = ROOT / "backend/workers/src/imageGuardConsent.ts"
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
WORKER_CONSENT_SEGMENTS = re.compile(
    r"export const IMAGE_GUARD_CONSENT_FIELD_SEGMENTS = \[([\s\S]*?)\] as const;"
)
CLIENT_CONSENT_SEGMENTS = re.compile(
    r"private static let imageGuardConsentFieldSegments = \[([\s\S]*?)\]"
)
WORKER_RFC3339 = re.compile(
    r"export const WARDROBE_IMAGES_ACCEPTED_AT_RFC3339\s*=\s*\n?\s*/([^/]+)/;"
)
CLIENT_RFC3339 = re.compile(
    r'wardrobeImagesAcceptedAtRfc3339 = try! NSRegularExpression\(\s*pattern: #"([^"]+)"#'
)
WORKER_IMAGE_VALUE = re.compile(r"const IMAGE_VALUE_PATTERN = /(.+?)/i;")
CLIENT_IMAGE_VALUE = re.compile(
    r"imageValuePattern = try! NSRegularExpression\(\s*pattern:\s*\"([^\"]+)\""
)
WORKER_IMAGE_PREFIXES = re.compile(
    r"export const IMAGE_VALUE_PREFIXES = \[([\s\S]*?)\] as const;"
)
CLIENT_IMAGE_PREFIXES = re.compile(
    r"private static let imageValuePrefixes = \[([\s\S]*?)\]"
)
WORKER_WHITESPACE = re.compile(
    r"export const ECMA_SCRIPT_WHITESPACE_CODE_POINTS = \[([\s\S]*?)\] as const;"
)
CLIENT_WHITESPACE = re.compile(
    r"private static let javaScriptWhitespace: Set<UInt32> = \[([\s\S]*?)\]"
)
WORKER_SEPARATORS = re.compile(
    r"export const IMAGE_GUARD_KEY_SEPARATOR_CODE_POINTS = \[([\s\S]*?)\] as const;"
)
CLIENT_SEPARATORS = re.compile(
    r"private static let imageGuardKeySeparatorCodePoints: \[UInt32\] = \[([\s\S]*?)\]"
)
WORKER_ASCII_MIN = re.compile(r"export const IMAGE_GUARD_PRINTABLE_ASCII_MIN = (0x[0-9a-fA-F]+);")
WORKER_ASCII_MAX = re.compile(r"export const IMAGE_GUARD_PRINTABLE_ASCII_MAX = (0x[0-9a-fA-F]+);")
CLIENT_ASCII_MIN = re.compile(r"private static let imageGuardPrintableAsciiMin: UInt32 = (0x[0-9A-Fa-f]+)")
CLIENT_ASCII_MAX = re.compile(r"private static let imageGuardPrintableAsciiMax: UInt32 = (0x[0-9A-Fa-f]+)")

GUARDED_REQUEST_ROOTS = ("GenerateRequest", "AlternativesRequest")

# docs/openapi.yaml → PreferenceRule.subject documented property names (D-26).
PREFERENCE_RULE_SUBJECT_KEYS = (
    "garmentId",
    "color_family",
    "pattern",
    "material",
    "category",
    "pair",
)


def extract_tokens(path: Path, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract forbidden token list")
    raw = match.group(1)
    return [m.group(1).lower() for m in re.finditer(r"""['"]([^'"]+)['"]""", raw)]


def extract_segments(path: Path, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract consent path segments")
    raw = match.group(1)
    return [m.group(1) for m in re.finditer(r"""['"]([^'"]+)['"]""", raw)]


def extract_rfc3339(path: Path, pattern: re.Pattern[str]) -> str:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract RFC 3339 consent regex")
    return match.group(1)


def extract_image_value_pattern(path: Path, pattern: re.Pattern[str]) -> str:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract image value pattern")
    return match.group(1)


def extract_quoted_strings(raw: str) -> list[str]:
    return [m.group(1) for m in re.finditer(r"""['"]([^'"]+)['"]""", raw)]


def extract_hex_list(raw: str) -> list[int]:
    return [int(m.group(1), 16) for m in re.finditer(r"0x([0-9A-Fa-f]+)", raw)]


def extract_ascii_bound(path: Path, pattern: re.Pattern[str]) -> int:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract printable ASCII bound")
    return int(match.group(1), 16)


def extract_image_prefixes(path: Path, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(path.read_text(encoding="utf-8"))
    if not match:
        sys.exit(f"{path.relative_to(ROOT)}: could not extract image value prefixes")
    return [s.lower() for s in extract_quoted_strings(match.group(1))]


def assert_same_lists(label: str, worker: list, client: list) -> bool:
    if worker != client:
        print(f"MISMATCH {label}:\n  worker: {worker}\n  client: {client}")
        return False
    print(f"OK {label}: {len(worker)} entries match")
    return True


def normalize_image_value_pattern(pattern: str) -> str:
    return pattern.lower().replace("\\/", "/")


def load_corpus() -> dict:
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    for key in ("keySegments", "rejectBodies", "allowBodies"):
        if key not in corpus or not isinstance(corpus[key], list):
            sys.exit(f"{CORPUS.relative_to(ROOT)}: missing or invalid {key!r} list")
    return corpus


def json_object_keys(value: Any, keys: set[str]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            keys.add(key)
            json_object_keys(child, keys)
    elif isinstance(value, list):
        for item in value:
            json_object_keys(item, keys)


def schema_property_names(schema: dict[str, Any], components: dict[str, Any], seen_refs: set[str]) -> set[str]:
    if "$ref" in schema:
        ref = schema["$ref"]
        if ref in seen_refs:
            return set()
        name = ref.rsplit("/", 1)[-1]
        return schema_property_names(components["schemas"][name], components, seen_refs | {ref})

    keys: set[str] = set()
    for prop, sub in schema.get("properties", {}).items():
        keys.add(prop)
        keys |= schema_property_names(sub, components, seen_refs)
    if "items" in schema:
        keys |= schema_property_names(schema["items"], components, seen_refs)
    for branch in ("oneOf", "allOf", "anyOf"):
        for sub in schema.get(branch, []):
            keys |= schema_property_names(sub, components, seen_refs)
    if isinstance(schema.get("additionalProperties"), dict):
        keys |= schema_property_names(schema["additionalProperties"], components, seen_refs)
    return keys


def openapi_guarded_request_keys() -> set[str]:
    try:
        import yaml
    except ImportError:
        sys.exit("check-image-guard-parity: need PyYAML (`pip install pyyaml`)")
    doc = yaml.safe_load(OPENAPI.read_text(encoding="utf-8"))
    components = doc["components"]
    keys: set[str] = set()
    for root_name in GUARDED_REQUEST_ROOTS:
        root = components["schemas"][root_name]
        keys |= schema_property_names(root, components, set())
    return keys


def fixture_json_keys() -> set[str]:
    keys: set[str] = set()
    for directory in (FIXTURES_WARDROBE, FIXTURES_PROFILE):
        if not directory.is_dir():
            continue
        for path in directory.glob("*.json"):
            json_object_keys(json.loads(path.read_text(encoding="utf-8")), keys)
    return keys


def corpus_legitimate_keys(corpus: dict) -> set[str]:
    keys = set(corpus.get("allowGuardedEndpointKeys", []))
    for entry in corpus.get("keySegments", []):
        if not entry.get("imageBearing"):
            keys.add(entry["key"])
    for entry in corpus.get("allowBodies", []):
        json_object_keys(entry.get("body", {}), keys)
    return keys


def run_legitimate_key_sweep(corpus: dict) -> None:
    image_bearing = {entry["key"] for entry in corpus.get("keySegments", []) if entry.get("imageBearing")}
    keys = sorted(
        (
            openapi_guarded_request_keys()
            | fixture_json_keys()
            | corpus_legitimate_keys(corpus)
            | set(PREFERENCE_RULE_SUBJECT_KEYS)
        )
        - image_bearing
    )
    payload = json.dumps(keys)
    env = os.environ.copy()
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8") as handle:
        handle.write(payload)
        keys_file = handle.name
    env["LEGITIMATE_IMAGE_GUARD_KEYS_JSON"] = keys_file
    try:
        result = subprocess.run(
            ["npm", "test", "--", "image-guard-legitimate-keys"],
            cwd=WORKERS_DIR,
            capture_output=True,
            text=True,
            env=env,
        )
    finally:
        Path(keys_file).unlink(missing_ok=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        sys.exit("Legitimate-key sweep failed (false positive on guarded OpenAPI/fixture keys)")
    print(f"OK legitimate-key sweep: {len(keys)} property names")


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
    worker_tokens = extract_tokens(WORKER_KEY, WORKER_TOKENS)
    client_tokens = extract_tokens(CLIENT, CLIENT_TOKENS)
    worker_segments = extract_segments(WORKER, WORKER_CONSENT_SEGMENTS)
    client_segments = extract_segments(CLIENT, CLIENT_CONSENT_SEGMENTS)
    worker_rfc = extract_rfc3339(WORKER_CONSENT, WORKER_RFC3339)
    client_rfc = extract_rfc3339(CLIENT, CLIENT_RFC3339)
    worker_image = extract_image_value_pattern(WORKER, WORKER_IMAGE_VALUE)
    client_image = extract_image_value_pattern(CLIENT, CLIENT_IMAGE_VALUE)

    if worker_tokens != client_tokens:
        print(f"MISMATCH forbidden tokens:\n  worker: {worker_tokens}\n  client: {client_tokens}")
        return 1
    print(f"OK forbidden tokens: {len(worker_tokens)} entries match")

    if worker_segments != client_segments:
        print(f"MISMATCH consent segments:\n  worker: {worker_segments}\n  client: {client_segments}")
        return 1
    print(f"OK consent segments: {worker_segments}")

    if worker_rfc != client_rfc:
        print(f"MISMATCH RFC 3339 regex:\n  worker: {worker_rfc}\n  client: {client_rfc}")
        return 1
    print("OK RFC 3339 consent regex")

    if normalize_image_value_pattern(worker_image) != normalize_image_value_pattern(client_image):
        print(
            "MISMATCH IMAGE_VALUE_PATTERN:\n"
            f"  worker: {worker_image}\n"
            f"  client: {client_image}"
        )
        return 1
    print("OK IMAGE_VALUE_PATTERN")

    worker_prefixes = extract_image_prefixes(WORKER, WORKER_IMAGE_PREFIXES)
    client_prefixes = extract_image_prefixes(CLIENT, CLIENT_IMAGE_PREFIXES)
    if not assert_same_lists("IMAGE_VALUE_PREFIXES", worker_prefixes, client_prefixes):
        return 1

    worker_ws_match = WORKER_WHITESPACE.search(WORKER_KEY.read_text(encoding="utf-8"))
    client_ws_match = CLIENT_WHITESPACE.search(CLIENT.read_text(encoding="utf-8"))
    if not worker_ws_match or not client_ws_match:
        sys.exit("could not extract ECMAScript whitespace lists")
    worker_ws = sorted(extract_hex_list(worker_ws_match.group(1)))
    client_ws = sorted(extract_hex_list(client_ws_match.group(1)))
    if not assert_same_lists("ECMAScript whitespace code points", worker_ws, client_ws):
        return 1

    worker_sep_match = WORKER_SEPARATORS.search(WORKER_KEY.read_text(encoding="utf-8"))
    client_sep_match = CLIENT_SEPARATORS.search(CLIENT.read_text(encoding="utf-8"))
    if not worker_sep_match or not client_sep_match:
        sys.exit("could not extract key separator code points")
    worker_sep = extract_hex_list(worker_sep_match.group(1))
    client_sep = extract_hex_list(client_sep_match.group(1))
    if not assert_same_lists("key separator code points", worker_sep, client_sep):
        return 1

    worker_min = extract_ascii_bound(WORKER_KEY, WORKER_ASCII_MIN)
    worker_max = extract_ascii_bound(WORKER_KEY, WORKER_ASCII_MAX)
    client_min = extract_ascii_bound(CLIENT, CLIENT_ASCII_MIN)
    client_max = extract_ascii_bound(CLIENT, CLIENT_ASCII_MAX)
    if worker_min != client_min or worker_max != client_max:
        print(
            "MISMATCH printable ASCII bounds:\n"
            f"  worker: {worker_min:#x}..{worker_max:#x}\n"
            f"  client: {client_min:#x}..{client_max:#x}"
        )
        return 1
    print(f"OK printable ASCII key bounds: {worker_min:#x}..{worker_max:#x}")

    corpus = load_corpus()
    print(
        f"OK corpus loaded: {len(corpus['keySegments'])} key segments, "
        f"{len(corpus.get('allowGuardedEndpointKeys', []))} guarded-endpoint keys, "
        f"{len(corpus['rejectBodies'])} reject bodies, "
        f"{len(corpus['allowBodies'])} allow bodies"
    )

    run_legitimate_key_sweep(corpus)
    run_worker_vitest_corpus()
    print("OK worker vitest image-guard-corpus")
    return 0


if __name__ == "__main__":
    sys.exit(main())
