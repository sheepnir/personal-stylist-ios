#!/usr/bin/env python3
"""Enforce the exact version the app shows and sends; no policy override."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'shared/privacy-policy-version.json').read_text())['policyVersion']
assert isinstance(version, str) and 0 < len(version) <= 64
assert f'static let policyVersion = "{version}"' in (root / 'App/StylingConsent.swift').read_text()
assert "policy.policyVersion" in (root / 'backend/workers/src/jev.ts').read_text()
print('Styling policy parity passed')

import tomllib
config = tomllib.loads((root / 'backend/workers/wrangler.toml').read_text())
for block in [config, *config.get('env', {}).values()]:
    assert block.get('vars', {}).get('PROVIDER_GENERATION') == 'off'
print('Committed provider flags are off')
