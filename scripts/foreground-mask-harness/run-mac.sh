#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
command -v xcodegen >/dev/null
# Every run gets its own generated project/evidence; existing local signing edits survive.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/foreground-mask-harness.XXXXXX")"
cp "$SOURCE/project.yml" "$WORK/project.yml"
cp -R "$SOURCE/Sources" "$SOURCE/Tests" "$WORK/"
printf 'Harness project and evidence: %s\n' "$WORK"
cd "$WORK"
xcodegen generate
destination="${HARNESS_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
xcodebuild build test -project ForegroundMaskHarness.xcodeproj \
  -scheme ForegroundMaskHarness -destination "$destination" \
  -derivedDataPath "$WORK/DerivedData" \
  -resultBundlePath "$WORK/HarnessTests.xcresult" \
  CODE_SIGNING_ALLOWED=NO -only-testing:ForegroundMaskHarnessTests \
  2>&1 | tee "$WORK/build-test.log"
