# Board photo touches and typed-decision diagnostics

Issue #114 tracks unresponsive outfit-board controls and ambiguous decision rejection.

## Reproduction and change

A hosted board with synthetic fixture swatches delivered visible center hits to
Swap and Keep. With persisted 1200 × 4000 synthetic portrait photos, the same
points resolved to a SwiftUI scroll container. Both photo tests failed before
button actions could run. Accessibility activation alone did not reveal this bug.

`FixtureImageView` now constrains hit testing to its visible layout rectangle.
Clipping still handles drawing; the explicit content shape prevents scaled image
content from intercepting nearby controls. Image accessibility labels remain.

The backend retains its existing output acceptance rules. Rejections now log one
fixed validation category alongside the existing model/version/outcome/latency
fields. No request, response, identifiers, confidence values, or garment data are
logged. The client still receives `INVALID_OUTPUT`; billing reconciliation still
runs before validation. This provides diagnosis without weakening validation.

## Verification

- Original touch regression: three hosted tests, two photo-case failures; fixture
  case passes.
- Worker typecheck and 482 tests pass, including seven diagnostic/redaction cases.
- Sample-literal, wear-logging, asset, cost-copy and failure-copy checks pass.
- Fixed touch regression: all three tests pass. Full iOS suite: 397 tests, one
  Keychain skip, zero failures; xcodebuild exits successfully.
- Independent code review found no issues. CI is required before merge.
- Weather Menu and rain touch interaction still require manual UI verification.

A successful provider HTTP request proves model execution, not acceptance of its
answer. The exact cause of the reported decision fallback remains unconfirmed.
No new physical-device acceptance or styling-quality claim is made here.
