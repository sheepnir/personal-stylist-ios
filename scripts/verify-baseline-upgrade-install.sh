#!/usr/bin/env bash
# Installed-app upgrade proof for the 2026092602 clean-start baseline.
#
# Installs a Debug build of 2026092602, writes a profile, garment, photo, and
# wear event, then installs Debug build 2026092603 over that app without
# uninstalling. The later build number is a command-line override for this
# proof only. Do not commit 2026092603 as CURRENT_PROJECT_VERSION.
#
# Same-process reopen tests are not this proof. Release archives do not include
# the debug probe, so this script is simulator evidence, not a TestFlight check.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SIM_ID:?Set SIM_ID explicitly to a dedicated simulator without an existing app install}"
BUNDLE="${BUNDLE:-com.example.PersonalStylist}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BASE_VERSION="2026092602"
NEXT_VERSION="2026092603"
DERIVED="${DERIVED:-/tmp/ps-upgrade-derived}"
FROZEN_KEY="baseline.2026092602.cleanStartCompleted"

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist"
}

app_path() {
  find "$DERIVED" -path '*Build/Products/Debug-iphonesimulator/PersonalStylist.app' -type d | head -1
}

build_app() {
  local version="$1"
  xcodebuild \
    -project "$ROOT/PersonalStylist.xcodeproj" \
    -scheme PersonalStylist \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${SIM_ID}" \
    -derivedDataPath "$DERIVED" \
    CURRENT_PROJECT_VERSION="$version" \
    build > /tmp/ps-upgrade-build.log 2>&1
}

wait_for_result() {
  local container="$1"
  local expect="$2"
  local file="$container/Documents/baseline-upgrade-result.txt"
  local _i
  for _i in $(seq 1 40); do
    if [[ -f "$file" ]] && grep -q "$expect" "$file"; then
      cat "$file"
      return 0
    fi
    sleep 0.5
  done
  echo "timed out waiting for ${expect}" >&2
  if [[ -f "$file" ]]; then
    cat "$file" >&2
  fi
  return 1
}

# Refuse even an apparently empty existing install: it may contain Keychain or
# other evidence. This proof owns only a previously uninstalled app destination.
refuse_existing_install() {
if xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data >/dev/null 2>&1 \
  || xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" app >/dev/null 2>&1; then
  echo "Refusing existing app/data for $BUNDLE on $SIM_ID. Preserve it; choose a dedicated simulator." >&2
  exit 1
fi
}
refuse_existing_install

xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null

echo "building ${BASE_VERSION}"
build_app "$BASE_VERSION"
BASE_APP="$(app_path)"
[[ "$(plist_get "$BASE_APP" CFBundleIdentifier)" == "$BUNDLE" ]]
[[ "$(plist_get "$BASE_APP" CFBundleVersion)" == "$BASE_VERSION" ]]

refuse_existing_install
xcrun simctl install "$SIM_ID" "$BASE_APP"
xcrun simctl launch "$SIM_ID" "$BUNDLE" -BaselineUpgradeWrite >/dev/null
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data)"
WRITE_RESULT="$(wait_for_result "$CONTAINER" '^wrote$')"
[[ "$WRITE_RESULT" == "wrote" ]]
xcrun simctl terminate "$SIM_ID" "$BUNDLE" >/dev/null 2>&1 || true

STORE="$(find "$CONTAINER/Library/Application Support" -name 'PersonalStylistLocal.store' -type f | head -1)"
[[ -n "$STORE" && -s "$STORE" ]]
STORE_BYTES_BEFORE="$(wc -c < "$STORE" | tr -d ' ')"

echo "building ${NEXT_VERSION} over the installed app"
build_app "$NEXT_VERSION"
NEXT_APP="$(app_path)"
[[ "$(plist_get "$NEXT_APP" CFBundleIdentifier)" == "$BUNDLE" ]]
[[ "$(plist_get "$NEXT_APP" CFBundleVersion)" == "$NEXT_VERSION" ]]

xcrun simctl install "$SIM_ID" "$NEXT_APP"
xcrun simctl launch "$SIM_ID" "$BUNDLE" -BaselineUpgradeVerify >/dev/null
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data)"
VERIFY_RESULT="$(wait_for_result "$CONTAINER" '^ok ')"
printf '%s\n' "$VERIFY_RESULT"
[[ "$VERIFY_RESULT" == "ok ${NEXT_VERSION}" ]]

STORE_AFTER="$(find "$CONTAINER/Library/Application Support" -name 'PersonalStylistLocal.store' -type f | head -1)"
[[ -n "$STORE_AFTER" && -s "$STORE_AFTER" ]]
PREFS="$CONTAINER/Library/Preferences/${BUNDLE}.plist"
KEY_VALUE="$(/usr/libexec/PlistBuddy -c "Print :${FROZEN_KEY}" "$PREFS" 2>/dev/null || true)"
[[ "$KEY_VALUE" == "true" ]]

echo "upgrade-install ok ${BASE_VERSION} -> ${NEXT_VERSION} store-bytes-before=${STORE_BYTES_BEFORE}"
