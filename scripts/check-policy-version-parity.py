#!/usr/bin/env python3
"""Enforce parity between shared/privacy-policy-version.json, Swift mirror, and contract goldens."""

from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "shared" / "privacy-policy-version.json"
SWIFT_PATH = ROOT / "App" / "PrivacyPolicyVersion.swift"
POLICY_TS = ROOT / "backend" / "workers" / "src" / "policy.ts"
VERIFY_SCRIPT = ROOT / "scripts" / "verify-openapi-contract-examples.py"
ONBOARDING_LITERAL = re.compile(r"onboarding-privacy-", re.IGNORECASE)


def load_json_version() -> str | None:
    with JSON_PATH.open(encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict) or "policyVersion" not in data:
        raise ValueError(f"{JSON_PATH}: expected object with policyVersion")
    pv = data["policyVersion"]
    if pv is not None and (not isinstance(pv, str) or not pv.strip()):
        raise ValueError(f"{JSON_PATH}: policyVersion must be null or non-empty string")
    return pv


def swift_mirror_value() -> str | None:
    text = SWIFT_PATH.read_text(encoding="utf-8")
    if re.search(r"currentPrivacyPolicyVersion:\s*String\?\s*=\s*nil\b", text):
        return None
    m = re.search(
        r'currentPrivacyPolicyVersion:\s*String\?\s*=\s*"([^"]+)"',
        text,
    )
    if m:
        return m.group(1)
    raise ValueError(f"{SWIFT_PATH}: could not parse currentPrivacyPolicyVersion")


def policy_ts_uses_json_import() -> bool:
    text = POLICY_TS.read_text(encoding="utf-8")
    if "privacy-policy-version.json" not in text:
        return False
    if re.search(r"CURRENT_PRIVACY_POLICY_VERSION\s*:\s*[^=]+=\s*['\"]", text):
        return False
    if re.search(r"CURRENT_PRIVACY_POLICY_VERSION\s*=\s*null\b", text):
        return False
    return "canonical.policyVersion" in text or "privacyPolicy" in text


def load_verify_module(verify_script: Path = VERIFY_SCRIPT):
    spec = importlib.util.spec_from_file_location(
        "verify_openapi_contract_examples_parity",
        verify_script,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {verify_script}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def golden_policy_version_errors(verify_script: Path = VERIFY_SCRIPT) -> list[str]:
    """Every golden with policyVersion must match the canonical JSON (null today)."""
    errors: list[str] = []
    canonical = load_json_version()
    mod = load_verify_module(verify_script)

    for name, ref_path, payload in mod.GOLDEN:
        if not isinstance(payload, dict) or "policyVersion" not in payload:
            continue
        pv = payload["policyVersion"]
        if pv != canonical:
            errors.append(
                f"golden:{name} policyVersion={pv!r} != canonical {canonical!r}"
            )

    model_config_goldens = [
        (name, payload)
        for name, ref_path, payload in mod.GOLDEN
        if ref_path.endswith("ModelConfigResponse")
    ]
    if not model_config_goldens:
        errors.append("no ModelConfigResponse entries found in GOLDEN")
    return errors


def repo_has_onboarding_privacy_literal() -> list[str]:
    hits: list[str] = []
    skip_dirs = {".git", "node_modules", "DerivedData"}
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in skip_dirs for part in path.parts):
            continue
        if path.name.endswith((".png", ".jpg", ".webp", ".svg", ".ico")):
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if ONBOARDING_LITERAL.search(content):
            rel = path.relative_to(ROOT)
            if rel.as_posix() == "scripts/check-policy-version-parity.py":
                continue
            hits.append(str(rel))
    return hits


def run_checks(verify_script: Path = VERIFY_SCRIPT) -> list[str]:
    errors: list[str] = []
    json_pv = load_json_version()
    swift_pv = swift_mirror_value()
    if json_pv != swift_pv:
        errors.append(
            f"JSON/Swift mismatch: json={json_pv!r} swift={swift_pv!r}"
        )
    if not policy_ts_uses_json_import():
        errors.append(f"{POLICY_TS}: must import policy version from JSON, not a literal")
    errors.extend(golden_policy_version_errors(verify_script))
    hits = repo_has_onboarding_privacy_literal()
    if hits:
        errors.append(f"onboarding-privacy-* literals found in: {', '.join(hits)}")
    return errors


def self_test() -> int:
    """Synthetic checks that the script rejects obvious violations."""
    good = run_checks()
    if good:
        print("self-test: repo checks failed before mutation (unexpected):", good, file=sys.stderr)
        return 1

    policy_text = POLICY_TS.read_text(encoding="utf-8")
    mutated_policy = policy_text.replace(
        "canonical.policyVersion",
        '"onboarding-privacy-bad"',
    )
    POLICY_TS.write_text(mutated_policy, encoding="utf-8")
    try:
        bad = run_checks()
        if not bad:
            print("self-test: mutated policy.ts should fail but passed", file=sys.stderr)
            return 1
    finally:
        POLICY_TS.write_text(policy_text, encoding="utf-8")

    verify_text = VERIFY_SCRIPT.read_text(encoding="utf-8")
    mutated_verify = re.sub(
        r'(\(\s*\n\s*"ModelConfigResponse-configured-mock"[\s\S]*?"policyVersion":\s*)SERVED_POLICY_VERSION',
        r'\1"bad-non-null-policy"',
        verify_text,
        count=1,
    )
    if mutated_verify == verify_text:
        print("self-test: could not mutate verify-openapi-contract-examples.py", file=sys.stderr)
        return 1

    VERIFY_SCRIPT.write_text(mutated_verify, encoding="utf-8")
    try:
        bad_golden = golden_policy_version_errors()
        if not bad_golden:
            print(
                "self-test: mismatched ModelConfigResponse golden should fail but passed",
                file=sys.stderr,
            )
            return 1
    finally:
        VERIFY_SCRIPT.write_text(verify_text, encoding="utf-8")

    print("check-policy-version-parity: self-test OK")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()

    errors = run_checks()
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        print(f"check-policy-version-parity: FAIL ({len(errors)} error(s))", file=sys.stderr)
        return 1
    print("check-policy-version-parity: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
