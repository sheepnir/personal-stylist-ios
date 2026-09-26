#!/usr/bin/env python3
"""Validate OpenAPI examples + iOS-facing golden payloads against docs/openapi.yaml (#220).

Pin spirit matches backend CI: same contract file, fail closed on schema drift.
Uses PyYAML + jsonschema (stdlib-adjacent; both available on CI ubuntu runners with
pip install if needed — we vendor the check to require only PyYAML+jsonschema).
"""

from __future__ import annotations

import json
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    print("verify-openapi-contract-examples: need PyYAML (`pip install pyyaml`)", file=sys.stderr)
    raise SystemExit(2)

try:
    from jsonschema import Draft202012Validator
except ImportError:  # pragma: no cover
    print(
        "verify-openapi-contract-examples: need jsonschema (`pip install jsonschema`)",
        file=sys.stderr,
    )
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[1]
OPENAPI = ROOT / "docs" / "openapi.yaml"
POLICY_JSON = ROOT / "shared" / "privacy-policy-version.json"


def load_served_policy_version() -> Any:
    with POLICY_JSON.open(encoding="utf-8") as f:
        data = json.load(f)
    return data.get("policyVersion")


SERVED_POLICY_VERSION = load_served_policy_version()

# Synthetic golden payloads (no photographic assets). Consent + AttributeRequest
# shapes are pinned so later wire adapters (#201 / #206) share this check.
GOLDEN: list[tuple[str, str, dict[str, Any]]] = [
    (
        "PrivacyConsent",
        "components/schemas/PrivacyConsent",
        {
            "wardrobeImagesAcceptedAt": "2026-09-20T12:00:00Z",
            "policyVersion": None,
        },
    ),
    (
        "AttributeRequest",
        "components/schemas/AttributeRequest",
        {
            "image": {
                "mediaType": "image/jpeg",
                "data": "AA==",
            },
            "privacyConsent": {
                "wardrobeImagesAcceptedAt": "2026-09-20T12:00:00Z",
                "policyVersion": None,
            },
            "slotHint": "TOP",
            "requestId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        },
    ),
    (
        "GenerateRequest-minimal-image-free",
        "components/schemas/GenerateRequest",
        {
            "profile": {
                "version": 1,
                "summaryText": "Fixture profile for contract checks.",
                "experimentationLevel": 2,
                "activeRules": [],
            },
            "context": {
                "occasion": "WORK_STANDARD",
                "occasionFormality": 3,
                "temperatureBand": "MILD",
                "precipitation": False,
            },
            "wardrobe": [
                {
                    "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
                    "displayName": "Navy Oxford Shirt",
                    "slot": "TOP",
                    "colorPrimary": {"family": "navy"},
                    "pattern": "SOLID",
                    "surface": "SMOOTH",
                    "formality": 3,
                    "warmth": 2,
                    "seasons": ["SPRING", "SUMMER", "FALL", "WINTER"],
                },
                {
                    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                    "displayName": "Charcoal Trousers",
                    "slot": "BOTTOM",
                    "colorPrimary": {"family": "charcoal"},
                    "pattern": "SOLID",
                    "surface": "SMOOTH",
                    "formality": 3,
                    "warmth": 2,
                    "seasons": ["SPRING", "SUMMER", "FALL", "WINTER"],
                },
                {
                    "id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
                    "displayName": "Black Derby",
                    "slot": "FOOTWEAR",
                    "colorPrimary": {"family": "black"},
                    "pattern": "SOLID",
                    "surface": "SMOOTH",
                    "formality": 3,
                    "warmth": 2,
                    "seasons": ["SPRING", "SUMMER", "FALL", "WINTER"],
                },
            ],
            "anchorGarmentId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
            "options": {"requireSlots": ["TOP", "BOTTOM", "FOOTWEAR"]},
        },
    ),
    (
        "ModelConfigResponse-unconfigured",
        "components/schemas/ModelConfigResponse",
        {
            "primary": None,
            "secondary": None,
            "promptVersion": "none",
            "policyVersion": SERVED_POLICY_VERSION,
            "dataPolicy": {
                "excludesTrainingProviders": True,
                "verifiedOn": None,
                "note": None,
            },
        },
    ),
    (
        "ModelConfigResponse-configured-mock",
        "components/schemas/ModelConfigResponse",
        {
            "primary": {
                "slug": "mock/stylist-v0",
                "displayName": None,
                "supportsVision": False,
                "supportsStructuredOutput": False,
                "contextWindow": 32000,
            },
            "secondary": None,
            "promptVersion": "none",
            "policyVersion": SERVED_POLICY_VERSION,
            "dataPolicy": {
                "excludesTrainingProviders": True,
                "verifiedOn": None,
                "note": None,
            },
        },
    ),
    (
        "UsageResponse-ledger-reset",
        "components/schemas/UsageResponse",
        {
            "last7DaysUSD": 0,
            "last30DaysUSD": 0,
            "dailyCapUSD": 1,
            "softThresholdUSD": 0.5,
            "spentTodayUSD": 0,
            "reservedTodayUSD": 0,
            "softThresholdReached": False,
            "hardCapReached": False,
            "ledgerDayEndsAt": "2026-09-27T00:00:00.000Z",
            "resetsAt": "2026-09-27T00:00:00.000Z",
        },
    ),
    (
        "Problem-lockConflict",
        "components/schemas/Problem",
        {
            "title": "Lock conflict",
            "status": 400,
            "code": "LOCK_CONFLICT",
            "detail": "One or more locked assignments cannot be honoured.",
            "dataPreserved": True,
            "conflicts": [
                {
                    "garmentId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
                    "reason": "Locked TOP occupies the same slot as the anchor garment.",
                }
            ],
        },
    ),
]


NEGATIVE_GOLDEN: list[tuple[str, str, dict[str, Any]]] = [
    (
        "ModelConfigResponse-empty-policyVersion",
        "components/schemas/ModelConfigResponse",
        {
            "primary": None,
            "promptVersion": "none",
            "policyVersion": "",
            "dataPolicy": {
                "excludesTrainingProviders": True,
                "verifiedOn": None,
            },
        },
    ),
]


def load_spec() -> dict[str, Any]:
    with OPENAPI.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_ref(spec: dict[str, Any], ref: str) -> dict[str, Any]:
    assert ref.startswith("#/")
    node: Any = spec
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def iter_media_examples(spec: dict[str, Any]) -> list[tuple[str, dict[str, Any], Any]]:
    """Collect (label, schema, example_value) from path response examples."""
    out: list[tuple[str, dict[str, Any], Any]] = []
    paths = spec.get("paths") or {}
    for path, item in paths.items():
        if not isinstance(item, dict):
            continue
        for method, op in item.items():
            if method.startswith("x-") or not isinstance(op, dict):
                continue
            responses = op.get("responses") or {}
            for status, resp in responses.items():
                if not isinstance(resp, dict):
                    continue
                content = resp.get("content") or {}
                for media, media_obj in content.items():
                    if not isinstance(media_obj, dict):
                        continue
                    schema = media_obj.get("schema")
                    examples = media_obj.get("examples") or {}
                    for name, ex in examples.items():
                        if not isinstance(ex, dict) or "value" not in ex:
                            continue
                        if not schema:
                            continue
                        label = f"{method.upper()} {path} {status} {media} example:{name}"
                        out.append((label, schema, ex["value"]))
    return out


def schema_to_jsonschema(spec: dict[str, Any], schema: dict[str, Any]) -> dict[str, Any]:
    """Shallow OpenAPI → JSON Schema: keep $ref, drop OpenAPI-only keywords that break Draft 2020-12."""
    s = deepcopy(schema)
    # jsonschema RefResolver needs the full document as store root.
    return s


def deep_resolve(
    node: Any,
    spec: dict[str, Any],
    stack: set[str] | None = None,
    cache: dict[str, Any] | None = None,
) -> Any:
    """Inline OpenAPI $ref nodes so Draft202012Validator needs no remote resolver."""
    if stack is None:
        stack = set()
    if cache is None:
        cache = {}
    if isinstance(node, dict):
        ref = node.get("$ref")
        if isinstance(ref, str):
            # OpenAPI may attach sibling keys; for validation we follow the ref.
            if ref in cache:
                return cache[ref]
            if ref in stack:
                return {"type": "object"}
            stack.add(ref)
            resolved = deep_resolve(resolve_ref(spec, ref), spec, stack, cache)
            stack.remove(ref)
            cache[ref] = resolved
            return resolved
        return {k: deep_resolve(v, spec, stack, cache) for k, v in node.items()}
    if isinstance(node, list):
        return [deep_resolve(v, spec, stack, cache) for v in node]
    return node


def validate(label: str, schema: dict[str, Any], instance: Any, spec: dict[str, Any]) -> list[str]:
    while "$ref" in schema:
        schema = resolve_ref(spec, schema["$ref"])
    resolved = deep_resolve(schema, spec)
    validator = Draft202012Validator(resolved)
    errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.path))
    return [f"{label}: {e.message} (path={list(e.path)})" for e in errors]


def main() -> int:
    if not OPENAPI.is_file():
        print(f"missing {OPENAPI}", file=sys.stderr)
        return 1

    spec = load_spec()
    errors: list[str] = []

    # 1) Spec-embedded examples (Problem lock/set conflicts, etc.)
    for label, schema, value in iter_media_examples(spec):
        errors.extend(validate(label, schema_to_jsonschema(spec, schema), value, spec))

    # 2) Golden iOS-facing payloads
    for name, ref_path, payload in GOLDEN:
        # ref_path like components/schemas/X → #/components/schemas/X
        ref = "#/" + ref_path
        schema = {"$ref": ref}
        errors.extend(validate(f"golden:{name}", schema, payload, spec))

    negative_failures = 0
    for name, ref_path, payload in NEGATIVE_GOLDEN:
        ref = "#/" + ref_path
        schema = {"$ref": ref}
        ne = validate(f"negative:{name}", schema, payload, spec)
        if not ne:
            errors.append(f"negative:{name}: expected schema rejection but instance validated")
        else:
            negative_failures += 1

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        print(
            f"verify-openapi-contract-examples: FAIL ({len(errors)} error(s))",
            file=sys.stderr,
        )
        return 1

    example_count = len(iter_media_examples(spec))
    print(
        f"verify-openapi-contract-examples: OK "
        f"({example_count} embedded examples, {len(GOLDEN)} golden payloads, "
        f"{negative_failures} negative case(s) rejected as expected)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
