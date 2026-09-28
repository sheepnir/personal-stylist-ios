# Profile field preservation

Issue #112 covers unintended profile writes during photo-only visits.

## Reproduction

Hosted navigation tests opened a synthetic profile, waited for its fields to render,
then dismissed it without editing. Both confirmed and draft cases failed on the
original implementation: nine assertions detected profile mutation. A confirmed
profile advanced from version 1 to 2, a custom environment label disappeared,
unanswered experimentation became 3, and separate custom goals were combined.

## Change

The editor compares raw field values against the values loaded on entry. Hydration,
unchanged Save, and edit-then-revert do not write. A real edit updates only its field
group, preserving unrelated custom labels and unanswered values. Explicit draft
confirmation remains available without rewriting untouched answers.

## Verification

- Independent code review found the unrelated-field normalization issue during
  real edits; the final change addresses that finding.
- Repository checks pass: sample literals, wear logging, asset library,
  cost-per-wear copy, and generate-failure copy.
- Four hosted tests pass: untouched confirmed/draft visits, a real profession edit
  preserving all unrelated fields, and an edit followed by a revert.
- The full iOS suite passes: 394 tests, one existing skip, zero failures.
- Save/Confirm button activation was reviewed in code but was not independently
  exercised by these hosted tests.

This evidence does not establish physical-device acceptance. Operational release
and installed-app preservation records remain private.
