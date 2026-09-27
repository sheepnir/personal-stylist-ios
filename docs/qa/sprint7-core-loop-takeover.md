## Bounded synthetic daily-loop report accepted

Primary target: iPhone 17 Pro simulator, iOS 27.0 (24A434). Existing loop/profile/price evidence uses `e89fff61681dbad1c3f91f69a311f18a5eb6a365`; camera completion uses `5f466e669c510fdae078ceade19f10a918c8c3ae` (same product tree as merged baseline `d4f83c15b62892fe9bdd147f6ccc05b374f304f8`). The intervening change only repairs the DEBUG upgrade-profile verifier; it does not alter the daily loop.

| Step | Result and evidence |
| --- | --- |
| Profile survives relaunch | PASS, #85 |
| Synthetic library photo saved and relaunch | PASS, prior report on this issue and #86 |
| Synthetic camera callback → preview → saved garment → relaunch | PASS, #86 final report |
| Review garment details and deterministic generate | PASS, prior UI loop report |
| Swap a slot | PASS, prior UI loop report |
| Wear history and relaunch | PASS, existing Change what I wore path when today's log already exists |
| Saved price and cost per wear | PASS, #87: price 45 / one wear → exact `$45 per wear · 1 wear in the app`, retained after relaunch |
| Physical phone / distributed build | NOT RUN; separate #83 track |

All public data are synthetic. The local deterministic endpoint was verified; no provider traffic or photo egress. Saved preferences and hard dislikes were **not** treated as influencing recommendations. #89 records the request-field trace: generate sends no profile; alternatives has empty activeRules; real-garment summaries omit some engine inputs; repeated-pair scoring lacks history; explanations may be templates; photos are not sent. This is verification of the currently scoped MVP, not a claim of personalized AI completion.

A later visual pass found collapsed filter labels; tracked under #88 with fix #103, not hidden as a loop pass. It does not invalidate the recorded save/generate/swap/wear results. Parent #28 remains open. Any final candidate change still requires #83's exact-candidate persistence recheck.
## Synthetic intake verification — PASS

Primary target: iPhone 17 Pro simulator, iOS 27.0 (24A434). Product source `5f466e669c510fdae078ceade19f10a918c8c3ae`, tree-equivalent to merged baseline `d4f83c15b62892fe9bdd147f6ccc05b374f304f8`.

Camera: a temporary, isolated DEBUG harness supplies a 64×64 purple image through the real camera picker coordinator callback. The UI then uses the production preview → Use photo → Finish details → Save as draft flow. `CameraEndToEndTests` passed (1 test, 0 failures, 38.711 seconds). Relaunch without the injection flag still finds the garment and its photo. This is synthetic camera-path evidence, not a physical camera result.

The harness was removed from the app source, the unmodified product rebuilt and installed in place, and the saved purple photo independently inspected in its detail screen. Stored captureSource is CAMERA, slot TOP, name QA Camera Purple Top; JPEG is 1501 bytes, SHA-256 `41caa9a88f01c8ff2334b89cb785d64641e5434205a1a1ec408014bfcca49ab7`.

Library: the earlier real system-picker synthetic import and loop continuity pass on `e89fff61681dbad1c3f91f69a311f18a5eb6a365` is recorded in #84. Its Navy Top JPEG remains unchanged after the in-place rebuild (SHA-256 `bf6b841b781b74ffa8fccee645fd88b3e6218e70fde2e66369a3dc18d7af2c10`). The only intervening product change was the DEBUG upgrade-profile verifier; intake source is unchanged.

An initial harness run failed because two buttons were named Top; selecting the intended first match corrected the harness. No camera-save product failure or hosted-camera flake occurred. No real photos, provider calls, upload, reset, reseed or uninstall. Parent #7 remains open; physical-camera and founder-device acceptance remain unverified and separate.
## Additional exact-candidate in-place preservation — PASS (simulator)

Candidate `fc5bf4f7084bff0eeb44a5373e408bcb6030b9d9` (#103), iPhone 17 Pro simulator / iOS 27.0 (24A434). Built with a command-line-only later build-number override. Installed over the existing populated app, launched, terminated and compared before/after snapshots.

All nine photo/database files have identical SHA-256 values before and after. The populated profile, garments, prices and wear history are preserved byte-for-byte in the store; camera/library/probe JPEGs remain. The frozen clean-start key remains true. No uninstall, reset or reseed. Source product version is unchanged.

This follows #100's verifier correction and #102's destructive-script guard. It is a simulator result only, not an upload, physical-device result or milestone completion. The private final-candidate and distribution record remains separate. The phone track stays open.
