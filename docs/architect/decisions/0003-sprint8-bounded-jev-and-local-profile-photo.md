# 0003: Sprint 8 — local profile photo and bounded Jev decisions

Status: Accepted for implementation by the founder's Sprint 8 instruction, 2026-09-27. Live activation and upload remain separately gated. This advances ADR-0001's mock-only implementation phase for this scope only. Earlier accepted records remain unchanged.

## Scope

A profile picture is selected with the system picker, stored in protected durable local app storage separately from garment photos, and can be replaced or removed. Cancellation and failed preparation preserve the previous file. It is never added to network requests or used for analysis. No new database migration or clean-start key is needed.

The backend may implement the founder-selected `typesafe/jev-1.13` Decisions API. Jev selects an opaque token representing one complete, deterministically validated outfit candidate, or one validated swap option. Whole-candidate choice replaces ADR-0001's per-slot questions for this release: it preserves set and anchor integrity without asking the model to assemble invalid combinations. Existing engine scoring, restrictions and explanation templates remain authoritative. The model does not write explanations.

Only a subset of ADR-0001's structured attribute allowlist is transmitted. No profile inputs, personal names, free text, images, image references, persistent identifiers, prices or wear history reach the provider. Prompt text is versioned and hash checked. The exact disclosure version is accepted locally and sent on each request; missing/mismatched consent takes the deterministic path. Withdrawal stops subsequent eligible requests.

## Safety and activation

Production remains off in committed configuration. A separate live Decisions client must require eligibility and confirmed per-device then application-wide reservations before sending. The historical chat client remains blocked. Unknown outcomes retain their reservation and age conservatively; known outcomes reconcile both ledgers. Model allowlisting and current price bounds precede reservations. Invalid configuration, ledger failure, cap refusal, timeout or invalid typed output yields deterministic fallback with honest provenance. No automatic provider retry or secondary model.

Activation requires founder-authorized budgets recorded privately, real Durable Object concurrency evidence, verified provider policy and key limits, automatic top-up off, a tested runtime kill switch, independent review/QA and authorization naming the exact backend candidate. A separate authorization is required for the exact signed iOS archive. No operational values belong in this repository.

## Delivery and preservation

The founder appoints the current delivery owner for Sprint 8, superseding the Sprint 6 Cursor-only coordination window in ADR-0002 for this sprint. Implementation, independent code review and QA remain distinct passes; record the actual tools and revisions without implying a different model family.

The release starts from the shipped isolated baseline. Changes already on main, including #92, enter that release only as explicitly reviewed necessary dependencies. Unrelated deferred work remains deferred. Existing installations and `baseline.2026092602.cleanStartCompleted` are preserved without uninstall, reseed or another reset. Device acceptance is separate from synthetic Simulator evidence. This decision authorizes neither an unspecified production deployment nor an upload.
