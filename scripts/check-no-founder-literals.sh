#!/usr/bin/env bash
# CC-01 — sample wardrobe display names (synthetic fixture data) must not be hard-coded outside fixtures/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAMES=(
  "Navy Oxford Shirt"
  "White Oxford Shirt"
  "Heather Grey Tee"
  "Olive Henley"
  "Khaki Chinos"
  "Brown Leather Derbies"
  "Indigo Jeans"
  "Charcoal Overcoat"
  "Grey Trousers"
  "Silver Watch"
  "Grey Scarf"
)
fail=0
for n in "${NAMES[@]}"; do
  hits=$(find "$ROOT/App" "$ROOT/Features" "$ROOT/Persistence" "$ROOT/Design" -name "*.swift" -print0 2>/dev/null | xargs -0 grep -n -F "$n" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "CC-01 FAIL: sample wardrobe literal in source: $n"
    echo "$hits"
    fail=1
  fi
done
if [[ $fail -ne 0 ]]; then
  exit 1
fi
echo "CC-01 PASS: no sample wardrobe literals outside fixtures/"
