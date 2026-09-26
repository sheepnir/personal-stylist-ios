# 0002: Sprint 6 delivery coordination

| | |
|---|---|
| Owner | Founder, for this product repository |
| Status | **Accepted** by the founder, 2026-09-26, in the Sprint 6 takeover instruction |
| Date | 2026-09-26 |
| Decided by | Founder |
| Supersedes | Only the previous Sprint 6 dispatch and coordination arrangement. It does **not** supersede ADR-0001 or any other accepted product decision. |
| Issue | sheepnir/personal-stylist-ios#75 |
| Path | `docs/architect/decisions/0002-sprint-6-cursor-coordination.md` |

> **Append-only.** From merge of the pull request that adds this file, the text above the "Amendment log" is frozen. A later change goes in a dated amendment or in a new decision that supersedes this one. This record is public: no secrets, account identifiers, production hosts, cap amounts, or private operational details.

---

## Decision

Cursor coordinates Personal Stylist Sprint 6 delivery in this repository.

- Cursor dispatches bounded implementation, independent review, and QA. Those are separate agents. The coordinator may do an integration check, and that check does not replace independent review or QA.
- For this coordination window, those agents use only **Cursor Grok** and **Cursor Composer**. Each change records the model that actually produced it. This constraint is founder instruction for this window. It does not amend ADR-0001, and it does not adopt any unrelated process proposal.
- Implementation of routine fixes uses Composer. Independent review of a Composer change uses Grok, and independent review of a Grok change uses Composer. A third model family is not available in this window; say so on the pull request instead of implying one was used.
- Merges stay on the existing `main` ruleset: pull request, squash merge, linear history, and the required checks. This decision does not bypass branch protection, dismiss a blocking review, or grant a production deploy.
- Unfinished provider behavior stays off. ADR-0001 remains the product rule: mocked provider only, no live provider calls from code or tests, the AI feature flag stays off, no provider image uploads, no AI profile summarization, and wardrobe data stays on the device.
- The overall application spending cap (issue #73) stays a prerequisite for any future paid-AI phase. This decision sets no cap amount and enables no paid call.
- Production deploys and migrations still need a separate founder approval for the concrete release candidate.

## What stays in force

ADR-0001 and the acceptance criteria on the open Sprint 6 issues. Closing an issue, or a green subset of checks, is not acceptance.

## Amendment log

| Date | Change |
|---|---|
| 2026-09-26 | Initial record. |
