#!/usr/bin/env bash
# Synthetic installed-app Sprint 9 -> Sprint 10 gate. Mac/Xcode only.
# Adds fixture-only DEBUG code to a disposable baseline source export; the accepted
# baseline schema, migration and app startup stay unchanged. No existing install is
# removed. Older upgrade coverage in verify-sprint9-upgrade.sh stays frozen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SIM_ID:?Set SIM_ID to a dedicated Simulator with no existing install of the app}"
BUNDLE="${BUNDLE:-com.example.PersonalStylist}"
BASELINE_REF="${BASELINE_REF:-13e851ac822f44df9ebac2feb10d6e5414436113}"
BASE_BUILD="${BASE_BUILD:-2026092801}"
NEXT_BUILD="${NEXT_BUILD:?Set NEXT_BUILD to an increasing synthetic test build number}"
WORK="${WORK:-$(mktemp -d /tmp/ps-sprint10-upgrade.XXXXXX)}"
OUT="${OUT:-$WORK/evidence}"
FROZEN_KEY="baseline.2026092602.cleanStartCompleted"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ "$NEXT_BUILD" =~ ^[0-9]+$ && "$NEXT_BUILD" -gt "$BASE_BUILD" ]] || { echo "NEXT_BUILD must increase over BASE_BUILD" >&2; exit 1; }
[[ ! -e "$OUT/summary.txt" ]] || { echo "Refusing stale evidence directory" >&2; exit 1; }
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
  [[ ! -e "$2" ]] || { echo "Refusing existing derived output: $2" >&2; return 1; }
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
  python3 - "$db" "$container" "$OUT" "$label" <<'PYSNAPSHOT'
import hashlib, json, pathlib, sqlite3, sys
path, container, out, label = sys.argv[1:]
out = pathlib.Path(out); root = pathlib.Path(container)
db = sqlite3.connect('file:' + path + '?mode=ro', uri=True)
tables = ['ZGARMENTENTITY', 'ZGARMENTIMAGEENTITY', 'ZWEARINGPHOTOENTITY', 'ZWEAREVENTENTITY',
          'ZWEARMEMBERSHIPENTITY', 'ZGARMENTSETENTITY', 'ZSTYLEPROFILEENTITY', 'ZOUTFITENTITY',
          'ZOUTFITASSIGNMENTENTITY', 'ZPRIVACYCONSENTENTITY']
def encode(v):
    return {'hex': v.hex()} if isinstance(v, bytes) else v
columns_path = out / 'baseline-columns.json'
if label == 'before':
    cols = {t: [r[1] for r in db.execute('PRAGMA table_info(' + t + ')') if r[1] not in ('Z_PK','Z_ENT','Z_OPT')] for t in tables}
    assert all(cols.values()), 'missing baseline table'
    columns_path.write_text(json.dumps(cols, sort_keys=True))
    def count(sql): return db.execute(sql).fetchone()[0]
    assert count("SELECT COUNT(*) FROM ZGARMENTENTITY WHERE ZREADINESSRAW='READY'") >= 2
    assert count("SELECT COUNT(*) FROM ZGARMENTENTITY WHERE ZREADINESSRAW='DRAFT'") >= 2
    assert count("SELECT COUNT(*) FROM (SELECT ZGARMENTID FROM ZWEARINGPHOTOENTITY GROUP BY ZGARMENTID HAVING COUNT(*)>=2)") >= 2
    assert count("SELECT COUNT(*) FROM ZWEARINGPHOTOENTITY WHERE ZSOURCEFILEID IS NOT NULL") >= 4
    for state in ('SAVED', 'FAILED'):
        assert count("SELECT COUNT(*) FROM ZWEARINGPHOTOENTITY WHERE ZPHOTOSEXPORTRAW='" + state + "'") >= 1
    for source in ('CAMERA', 'LIBRARY'):
        assert count("SELECT COUNT(*) FROM ZWEARINGPHOTOENTITY WHERE ZSOURCERAW='" + source + "'") >= 1
    assert count('SELECT COUNT(*) FROM ZWEAREVENTENTITY WHERE ZVOIDEDAT IS NULL AND ZSOURCEOUTFITID IS NOT NULL') >= 1
    assert count('SELECT COUNT(*) FROM ZWEAREVENTENTITY WHERE ZVOIDEDAT IS NOT NULL') >= 1
    assert count('SELECT COUNT(*) FROM ZWEARMEMBERSHIPENTITY WHERE ZVOIDED=1') >= 1
    assert count('SELECT COUNT(*) FROM ZGARMENTENTITY WHERE ZPURCHASEDATE IS NOT NULL AND ZPRIORWEARESTIMATE>0') >= 4
    for table in ('ZGARMENTSETENTITY','ZOUTFITASSIGNMENTENTITY','ZSTYLEPROFILEENTITY','ZPRIVACYCONSENTENTITY'):
        assert count('SELECT COUNT(*) FROM ' + table) >= 1
else:
    cols = json.loads(columns_path.read_text())
rows = []
for table in tables:
    for row in db.execute('SELECT ' + ','.join(cols[table]) + ' FROM ' + table):
        rows.append(json.dumps([table, dict(zip(cols[table], map(encode, row)))], sort_keys=True))
(out / ('rows-' + label + '.txt')).write_text('\n'.join(sorted(rows)) + '\n')
photos = []
for directory in ('Documents/GarmentPhotos', 'Documents/WearingPhotos', 'Library/Application Support/ProfilePhoto'):
    d = root / directory
    assert d.is_dir(), 'missing photo directory: ' + directory
    for file in sorted(d.rglob('*')):
        if file.is_file():
            data = file.read_bytes(); assert data, 'empty photo file'
            photos.append(hashlib.sha256(data).hexdigest() + '  ' + str(file.relative_to(root)))
# Validate every gallery display/source reference, not only file totals.
import uuid
for display, source in db.execute('SELECT ZDISPLAYFILEID, ZSOURCEFILEID FROM ZWEARINGPHOTOENTITY'):
    for value in (display, source):
        assert value is not None, 'missing gallery source'
        photo = root / 'Documents/WearingPhotos' / (str(uuid.UUID(bytes=value) if isinstance(value, bytes) else uuid.UUID(value)).upper() + '.jpg')
        assert photo.is_file() and photo.stat().st_size > 0, 'missing referenced gallery file'
retained = 0
for (path,) in db.execute('SELECT ZIMAGEPATH FROM ZGARMENTENTITY'):
    if path and path.startswith('user-photo:'):
        photo_id = str(uuid.UUID(path.split(':', 1)[1])).upper()
        assert (root / 'Documents/GarmentPhotos' / (photo_id + '.jpg')).is_file(), 'missing garment display'
        if (root / 'Documents/GarmentPhotos/Sources' / (photo_id + '.jpg')).is_file():
            retained += 1
assert retained >= 4, 'missing linked garment sources'
assert len(list((root / 'Documents/GarmentPhotos/Sources').glob('*.jpg'))) >= 4
assert (root / 'Library/Application Support/ProfilePhoto/profile-source.jpg').is_file()
(out / ('photos-' + label + '.txt')).write_text('\n'.join(sorted(photos)) + '\n')
PYSNAPSHOT
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
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]] || { log "Refusing dirty candidate: commit reviewed source first"; exit 1; }
[[ ! -e "$WORK/baseline" ]] || { log "Refusing stale baseline output"; exit 1; }
mkdir -p "$WORK/baseline"
git -C "$ROOT" archive "$BASELINE_REF" | tar -x -C "$WORK/baseline"
# Only fixture write path is augmented, in this disposable export.
python3 - "$WORK/baseline/App/BaselineUpgradeProbe.swift" <<'PYFIX'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
needle = '            let photoURL = try photoFileURL()'
assert s.count(needle) == 1
p.write_text(s.replace(needle, '            try await (store as! SwiftDataPersistenceStore).writeSprint10Fixture()\n' + needle))
store = p.parent.parent / 'Persistence/SwiftData/SwiftDataPersistenceStore.swift'
store.write_text('import UIKit\n' + store.read_text())
PYFIX
cat >> "$WORK/baseline/Persistence/SwiftData/SwiftDataPersistenceStore.swift" <<'SWIFT'

#if DEBUG
@MainActor
extension SwiftDataPersistenceStore {
    func writeSprint10Fixture() throws {
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_758_000_000)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { c in
            UIColor.systemBlue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        guard let bytes = image.jpegData(compressionQuality: 0.8), !bytes.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let profile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ProfilePhoto")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try bytes.write(to: profile.appendingPathComponent("profile.jpg"))
        try bytes.write(to: profile.appendingPathComponent("profile-source.jpg"))
        var garments: [GarmentEntity] = []
        let setID = UUID()
        for i in 0..<4 {
            let id = UUID()
            let path = try UserGarmentPhotoStore.persistJPEG(from: bytes, garmentId: id)
            try UserGarmentPhotoStore.writeSource(bytes, forPhotoId: id)
            let g = GarmentEntity(id: id, displayName: "Synthetic upgrade garment \(i)", slotRaw: "TOP", setId: setID,
                readinessRaw: i < 2 ? "READY" : "DRAFT", colorFamily: "blue", formality: 2, warmth: 2,
                purchasePrice: Decimal(40 + i), purchaseCurrency: i % 2 == 0 ? "USD" : "EUR",
                purchaseDate: date, priorWearEstimate: i + 3, priorWearBucket: "KNOWN", imagePath: path)
            context.insert(g); GarmentIndexSync.upsert(entity: g, in: context); garments.append(g)
            context.insert(GarmentImageEntity(originalURI: path, processedURI: path, processingResultRaw: "CROPPED", garment: g))
            for j in 0..<3 {
                let display = UUID(), source = UUID()
                let dir = docs.appendingPathComponent("WearingPhotos")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try bytes.write(to: dir.appendingPathComponent("\(display.uuidString).jpg"))
                try bytes.write(to: dir.appendingPathComponent("\(source.uuidString).jpg"))
                context.insert(WearingPhotoEntity(garmentId: id, displayFileId: display, sourceFileId: source,
                    addedAt: date.addingTimeInterval(Double(i * 10 + j)), sourceRaw: j == 2 ? "LIBRARY" : "CAMERA",
                    photosExportRaw: j == 0 ? "SAVED" : j == 1 ? "FAILED" : nil))
            }
        }
        context.insert(GarmentSetEntity(id: setID, displayName: "Synthetic upgrade set", keepTogether: true, memberGarmentIds: garments.map(\.id)))
        let outfit = OutfitEntity(rationaleSummary: "Synthetic retained provenance", statusRaw: "WORN", contextJSON: Data("{}".utf8), generationJSON: Data("{}".utf8))
        context.insert(outfit)
        context.insert(OutfitAssignmentEntity(slotRaw: "TOP", garmentId: garments[0].id, isAnchor: true, isLocked: true, outfit: outfit))
        for voided in [false, true] {
            let event = WearEventEntity(wornOn: date, garmentIds: garments.map(\.id), sourceOutfitId: outfit.id,
                sessionId: outfit.sessionId, selectedAt: date, voidedAt: voided ? date : nil)
            context.insert(event); WearMembershipSync.replace(event: event, in: context)
        }
        context.insert(PrivacyConsentEntity(policyVersion: "synthetic-upgrade", wardrobeImagesAcceptedAt: date, decidedAt: date))
        UserDefaults.standard.set(StylingModel.luna.rawValue, forKey: StylingModel.defaultsKey)
        UserDefaults.standard.set(StylingConsent.policyVersion, forKey: StylingConsent.defaultsKey)
        UserDefaults.standard.set(StylingModel.lunaPolicyVersion, forKey: StylingModel.lunaConsentKey)
        try context.save()
    }
}
#endif
SWIFT
shasum -a 256 "$WORK/baseline/App/BaselineUpgradeProbe.swift" "$WORK/baseline/Persistence/SwiftData/SwiftDataPersistenceStore.swift" > "$OUT/fixture-overlay.sha256"
git -C "$ROOT" rev-parse "$BASELINE_REF" > "$OUT/baseline-source-sha.txt"
git -C "$ROOT" rev-parse HEAD > "$OUT/candidate-source-sha.txt"

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
log "rich synthetic baseline captured and validated"

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
[[ "$GALLERY_ROWS" =~ ^[0-9]+$ && "$GALLERY_ROWS" -ge 4 ]] || { log "unexpected gallery rows: $GALLERY_ROWS"; fail=1; }
log "gallery table present, rows=${GALLERY_ROWS}; clean-start key $(cat "$OUT/clean-start-after.txt")"
[[ $fail -eq 0 ]] || { log "upgrade proof FAILED; evidence in $OUT"; exit 1; }
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(cat "$OUT/candidate-source-sha.txt")" && -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]] || { log "candidate changed during proof"; exit 1; }
log "upgrade proof ok ${BASE_BUILD} -> ${NEXT_BUILD}; evidence in $OUT"
