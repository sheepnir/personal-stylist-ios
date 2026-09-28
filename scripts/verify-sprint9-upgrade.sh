#!/usr/bin/env bash
# Sprint 9 installed-app upgrade proof (ADR-0004, #119).
#
# Builds the accepted baseline from BASELINE_REF in a separate worktree, installs it on a
# dedicated Simulator, lets it seed the synthetic fixture wardrobe and write the debug probe
# data (garment with a user photo, price, profile, wear event; the baseline's clean start
# does not seed the fixture wardrobe), adds a synthetic profile
# picture, then builds the current checkout and installs it OVER the baseline without
# uninstalling. It compares store rows (ids, names, photo references, prices, currency,
# sets, wear events, memberships, profile versions) and photo file hashes before and after,
# checks the clean-start key, the new gallery table, and a second relaunch.
#
# Synthetic Simulator evidence only: not a device or TestFlight check. It refuses any
# Simulator that already has the app installed, and never uninstalls or erases anything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SIM_ID:?Set SIM_ID to a dedicated Simulator with no existing install of the app}"
BUNDLE="${BUNDLE:-com.example.PersonalStylist}"
BASELINE_REF="${BASELINE_REF:-bf20abe9c958539a90a19566ebdce5a2aaa24f65}"
BASE_BUILD="${BASE_BUILD:-2026092703}"
NEXT_BUILD="${NEXT_BUILD:-2026092801}"
WORK="${WORK:-$(mktemp -d /tmp/ps-sprint9-upgrade.XXXXXX)}"
OUT="${OUT:-$WORK/evidence}"
FROZEN_KEY="baseline.2026092602.cleanStartCompleted"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$OUT"

log() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }

refuse_existing_install() {
  if xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data >/dev/null 2>&1 \
    || xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" app >/dev/null 2>&1; then
    echo "Refusing: $BUNDLE is already installed on $SIM_ID. Use a dedicated Simulator." >&2
    exit 1
  fi
}

build_app() { # <source dir> <derived dir> <build number>
  # set -e is off inside $(...) on bash 3.2: start clean and fail explicitly.
  rm -rf "$2"
  xcodebuild \
    -project "$1/PersonalStylist.xcodeproj" \
    -scheme PersonalStylist \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=${SIM_ID}" \
    -derivedDataPath "$2" \
    CURRENT_PROJECT_VERSION="$3" \
    CODE_SIGNING_ALLOWED=NO \
    build > "$OUT/build-$3.log" 2>&1 || return 1
  find "$2" -path '*Build/Products/Debug-iphonesimulator/PersonalStylist.app' -type d | head -1
}

wait_for_result() { # <container> <regex>
  local file="$1/Documents/baseline-upgrade-result.txt" _i
  for _i in $(seq 1 60); do
    if [[ -f "$file" ]] && grep -Eq "$2" "$file"; then cat "$file"; return 0; fi
    sleep 0.5
  done
  echo "timed out waiting for $2" >&2
  if [[ -f "$file" ]]; then cat "$file" >&2; fi
  return 1
}

snapshot() { # <container> <label>
  local container="$1" label="$2" copy="$WORK/store-$2"
  local store
  store="$(find "$container/Library/Application Support" -name 'PersonalStylistLocal.store' -type f | head -1)"
  [[ -n "$store" && -s "$store" ]] || { echo "no store for $label" >&2; return 1; }
  # Query a copy so reading never touches the app's store.
  mkdir -p "$copy"
  cp "$store"* "$copy/"
  local db="$copy/$(basename "$store")"
  sqlite3 -readonly "$db" <<'SQL' > "$OUT/rows-$label.txt"
.headers off
.mode list
SELECT 'garment', hex(ZID), ZDISPLAYNAME, ZSLOTRAW, ZREADINESSRAW, ZAVAILABILITY, ZIMAGEPATH,
       ZPURCHASEPRICE, ZPURCHASECURRENCY, hex(ZSETID), ZCREATEDAT FROM ZGARMENTENTITY ORDER BY 2;
SELECT 'image', ZORIGINALURI, ZPROCESSEDURI, ZISPRIMARY FROM ZGARMENTIMAGEENTITY ORDER BY 2, 3;
SELECT 'wear', hex(ZID), ZWORNON, ZVOIDEDAT, hex(ZGARMENTIDSDATA), hex(ZSOURCEOUTFITID) FROM ZWEAREVENTENTITY ORDER BY 2;
SELECT 'membership', hex(ZEVENTID), hex(ZGARMENTID), ZVOIDED FROM ZWEARMEMBERSHIPENTITY ORDER BY 2, 3;
SELECT 'set', hex(ZID), ZDISPLAYNAME, ZKEEPTOGETHER, hex(ZMEMBERGARMENTIDSDATA) FROM ZGARMENTSETENTITY ORDER BY 2;
SELECT 'profile', hex(ZID), ZVERSION, ZPROFESSION, ZCONFIRMEDAT FROM ZSTYLEPROFILEENTITY ORDER BY 2;
SELECT 'outfit', hex(ZID) FROM ZOUTFITENTITY ORDER BY 2;
SQL
  ( cd "$container" && find Documents/GarmentPhotos "Library/Application Support/ProfilePhoto" -type f -name '*.jpg' -print0 2>/dev/null \
      | sort -z | xargs -0 shasum -a 256 ) > "$OUT/photos-$label.txt" || true
  # Preferences reach the plist asynchronously after the app exits. Every build here sets the
  # clean-start key at launch, so wait (bounded) until it is on disk before reading.
  local prefs="$container/Library/Preferences/${BUNDLE}.plist" key _i
  for _i in $(seq 1 40); do
    if /usr/libexec/PlistBuddy -c "Print :${FROZEN_KEY}" "$prefs" >/dev/null 2>&1; then break; fi
    sleep 0.5
  done
  : > "$OUT/settings-$label.txt"
  for key in "$FROZEN_KEY" styling.selectedModel styling.acceptedPolicyVersion styling.lunaAcceptedPolicyVersion; do
    printf '%s=%s\n' "$key" "$(/usr/libexec/PlistBuddy -c "Print :${key}" "$prefs" 2>/dev/null || echo '<absent>')" \
      >> "$OUT/settings-$label.txt"
  done
  grep "^${FROZEN_KEY}=" "$OUT/settings-$label.txt" | cut -d= -f2- > "$OUT/clean-start-$label.txt"
}

refuse_existing_install
xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null

log "baseline ${BASELINE_REF} as build ${BASE_BUILD}; next $(git -C "$ROOT" rev-parse HEAD) as build ${NEXT_BUILD}"
git -C "$ROOT" worktree add --detach "$WORK/baseline" "$BASELINE_REF" >/dev/null
trap 'git -C "$ROOT" worktree remove --force "$WORK/baseline" >/dev/null 2>&1 || true' EXIT

BASE_APP="$(build_app "$WORK/baseline" "$WORK/derived-base" "$BASE_BUILD")"
[[ -d "$BASE_APP" ]] || { echo "baseline build failed; see $OUT/build-$BASE_BUILD.log" >&2; exit 1; }
refuse_existing_install
xcrun simctl install "$SIM_ID" "$BASE_APP"
xcrun simctl launch "$SIM_ID" "$BUNDLE" -BaselineUpgradeWrite >/dev/null
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data)"
wait_for_result "$CONTAINER" '^wrote$' >/dev/null
xcrun simctl terminate "$SIM_ID" "$BUNDLE" >/dev/null 2>&1 || true

# Synthetic profile picture: the probe's own generated garment photo (no real image).
mkdir -p "$CONTAINER/Library/Application Support/ProfilePhoto"
cp "$CONTAINER/Documents/GarmentPhotos/B1000001-0000-4000-8000-000000000001.jpg" \
   "$CONTAINER/Library/Application Support/ProfilePhoto/profile.jpg"
snapshot "$CONTAINER" before
# An empty "before" would make every later comparison pass trivially.
if (( $(grep -c '^garment|' "$OUT/rows-before.txt") < 1 || $(grep -c '^wear|' "$OUT/rows-before.txt") < 1 \
   || $(grep -c 'user-photo' "$OUT/rows-before.txt") < 1 || $(wc -l < "$OUT/photos-before.txt") < 2 )); then
  echo "baseline store is not populated enough to prove anything" >&2
  exit 1
fi
log "baseline populated: $(grep -c '^garment|' "$OUT/rows-before.txt") garments, $(grep -c '^wear|' "$OUT/rows-before.txt") wear events, $(wc -l < "$OUT/photos-before.txt" | tr -d ' ') photo files"

NEXT_APP="$(build_app "$ROOT" "$WORK/derived-next" "$NEXT_BUILD")"
[[ -d "$NEXT_APP" ]] || { echo "next build failed; see $OUT/build-$NEXT_BUILD.log" >&2; exit 1; }
xcrun simctl install "$SIM_ID" "$NEXT_APP"   # in place: no uninstall, same bundle id
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data)"
# The baseline left "wrote" in the result file; clear it so only the new verify is read.
rm -f "$CONTAINER/Documents/baseline-upgrade-result.txt"
xcrun simctl launch "$SIM_ID" "$BUNDLE" -BaselineUpgradeVerify >/dev/null
VERIFY="$(wait_for_result "$CONTAINER" '^(ok [0-9]+|[a-z-]+(,[a-z-]+)*)$')"
xcrun simctl terminate "$SIM_ID" "$BUNDLE" >/dev/null 2>&1 || true
log "probe verify: ${VERIFY}"
# macOS /bin/bash 3.2 does not stop on a failing bare [[ ]], so every check exits explicitly.
[[ "$VERIFY" == "ok ${NEXT_BUILD}" ]] || { log "probe verify failed: ${VERIFY}"; exit 1; }
snapshot "$CONTAINER" after

# Second relaunch of the new build, then compare again.
xcrun simctl launch "$SIM_ID" "$BUNDLE" >/dev/null
sleep 8
xcrun simctl terminate "$SIM_ID" "$BUNDLE" >/dev/null 2>&1 || true
snapshot "$CONTAINER" relaunch

STORE_COPY="$(find "$WORK/store-relaunch" -name 'PersonalStylistLocal.store' | head -1)"
GALLERY_ROWS="$(sqlite3 -readonly "$STORE_COPY" 'SELECT COUNT(*) FROM ZWEARINGPHOTOENTITY;' 2>&1 || true)"

fail=0
for label in after relaunch; do
  if diff -u "$OUT/rows-before.txt" "$OUT/rows-$label.txt" > "$OUT/rows-diff-$label.txt"; then
    log "rows unchanged ($label)"
  else
    log "ROWS CHANGED ($label): see rows-diff-$label.txt"; fail=1
  fi
  if diff -u "$OUT/photos-before.txt" "$OUT/photos-$label.txt" > "$OUT/photos-diff-$label.txt"; then
    log "photo hashes unchanged ($label)"
  else
    log "PHOTOS CHANGED ($label): see photos-diff-$label.txt"; fail=1
  fi
  [[ "$(cat "$OUT/clean-start-$label.txt")" == "true" ]] || { log "clean-start key not preserved ($label)"; fail=1; }
  if diff -u "$OUT/settings-before.txt" "$OUT/settings-$label.txt" > "$OUT/settings-diff-$label.txt"; then
    log "model choice and consent unchanged ($label)"
  else
    log "SETTINGS CHANGED ($label): see settings-diff-$label.txt"; fail=1
  fi
done
[[ "$GALLERY_ROWS" == "0" ]] || { log "unexpected gallery rows: $GALLERY_ROWS"; fail=1; }
log "gallery table present, rows=${GALLERY_ROWS}; clean-start key $(cat "$OUT/clean-start-after.txt")"
[[ $fail -eq 0 ]] || { log "upgrade proof FAILED; evidence in $OUT"; exit 1; }
log "upgrade proof ok ${BASE_BUILD} -> ${NEXT_BUILD}; evidence in $OUT"
