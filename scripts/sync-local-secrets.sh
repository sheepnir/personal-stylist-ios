#!/usr/bin/env bash
# Write the engine base URL (and optionally your Apple Team ID) into the untracked
# Config/LocalSecrets.xcconfig, which Debug.xcconfig / Release.xcconfig include.
#
# DEVICE_TOKEN / ENROLLMENT_SECRET are NEVER written into xcconfig / Info.plist / the IPA (#168).
# Seed the Simulator Keychain via Xcode scheme environment variables instead:
#   DEVICE_TOKEN=<existing opaque token>
#   or ENROLLMENT_SECRET=<wrangler secret> (Debug auto-enrolls against HTTPS)
#
# Inputs (environment variables, or a KEY=VALUE env file named by PS_ENV_FILE):
#   OUTFIT_ENGINE_BASE_URL       required, e.g. https://<your-worker-host>
#   DEVELOPMENT_TEAM             optional, your 10-character Apple Team ID
#   PRODUCT_BUNDLE_IDENTIFIER    optional, overrides the placeholder com.example.PersonalStylist
#                                (release builds: must match the App Store Connect record)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Config/LocalSecrets.xcconfig"
ENV_FILE="${PS_ENV_FILE:-}"

read_env_key() {
  # Prints the value of KEY from the env file, if any. Never echoes other keys.
  local key="$1"
  [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]] || return 0
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '"' || true
}

BASE_URL="${OUTFIT_ENGINE_BASE_URL:-$(read_env_key OUTFIT_ENGINE_BASE_URL)}"
TEAM="${DEVELOPMENT_TEAM:-$(read_env_key DEVELOPMENT_TEAM)}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-$(read_env_key PRODUCT_BUNDLE_IDENTIFIER)}"

if [[ -z "$BASE_URL" ]]; then
  echo "Set OUTFIT_ENGINE_BASE_URL (or PS_ENV_FILE pointing at a file that defines it)." >&2
  exit 1
fi
if [[ "$BASE_URL" != https://* ]]; then
  echo "OUTFIT_ENGINE_BASE_URL must be an https:// URL for device builds." >&2
  exit 1
fi

mkdir -p "$ROOT/Config"
# Xcode xcconfig: escape // in https:// as https:/$()/
XC_BASE="${BASE_URL/https:\/\//https:\/\$()\/}"
{
  echo "// GENERATED — do not commit"
  echo "// Do not put DEVICE_TOKEN or ENROLLMENT_SECRET here — they must not enter Info.plist."
  echo "OUTFIT_ENGINE_BASE_URL = ${XC_BASE}"
  if [[ -n "$TEAM" ]]; then
    echo "DEVELOPMENT_TEAM = ${TEAM}"
  fi
  if [[ -n "$BUNDLE_ID" ]]; then
    echo "PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}"
  fi
} > "$OUT"
echo "Wrote Config/LocalSecrets.xcconfig"
echo "Reminder: set Xcode scheme env DEVICE_TOKEN or ENROLLMENT_SECRET for Debug Keychain bootstrap (never baked into the IPA)."
