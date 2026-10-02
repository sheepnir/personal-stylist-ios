# Sprint 8 local profile picture — implementation evidence

Scope: #106. Development base `bedb443`; no database schema or clean-start changes.

The system Photos picker imports an image into a separate Application Support/ProfilePhoto directory. ImageIO downsamples to an 800-pixel maximum edge and re-encodes to JPEG without source metadata. Protection and backup exclusion are applied before a same-directory atomic rename. Cancellation and preparation failures keep the existing picture; removal addresses only profile.jpg. No photo path or data is added to any network DTO.

Verification: full iOS unit suite on an isolated iPhone 17 Pro Simulator, iOS 27.0: **367 tests, one existing skip, zero failures**. Five profile tests cover add/replace/reopen/remove, sibling data preservation, invalid image, a real filesystem write failure with an existing photo, and image-size/location-metadata removal. An initial full run exposed a migration fixture byte-comparison failure; its isolated rerun and subsequent full run passed without changing migration code or weakening the test.

Independent review found a post-commit load could falsely report the old picture unchanged; replacement now returns the committed bytes directly. Picker task cleanup only clears its own selection, avoiding stale cleanup affecting a later import.

Not yet verified here: interactive picker cancellation/failure on device, exact release-candidate in-place upgrade, or TestFlight acceptance. This is implementation evidence, not Sprint completion.
