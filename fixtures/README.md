# Personal Stylist — QA fixtures (M0-12 / M0-13)

Offline evaluation fixtures for outfit task **T2** (PRD §10.2).
Built for Milestone 0 exit: deterministic builder must produce each scenario's
expected outcome with zero model calls [D-29].

## Layout

```
fixtures/
  README.md                 ← this file
  profile/
    founder-seed.json       ← synthetic sample persona (historical file name)
  wardrobe/
    garments.json           ← all garments (array)
    sets.json               ← keepTogether membership [D-22, D-30]
    images/*.svg            ← synthetic placeholders (no real photos)
  scenarios/
    index.json              ← scenario id list + wardrobe paths
    T2-*.json               ← one file per scenario
    index-m1.json           ← swap re-rank scenario id list
    M1-*.json               ← swap re-rank (alternatives) scenario
```

## One synthetic persona

`profile/founder-seed.json` and the `profile` object embedded in every scenario describe the
same invented sample user (age, profession, work environment, experimentation level). It is
not a real person. The engine does not read these persona fields; they exist for payload
realism only.

## Images are synthetic

Every file under `wardrobe/images/` is a hand-generated SVG: solid colour fill,
slot label, garment name, and a `SYNTHETIC` footer. **No real photographs,**
no network URLs, no stock imagery. Relative paths only (`images/<key>.svg`).

## Provisional schema notes

Garments align with OpenAPI `GarmentSummary` for generation payloads, plus
fixture-only fields needed for offline loading and draft/availability tests:

| Field | Source | Notes |
|---|---|---|
| `id`, `displayName`, `slot`, `category`, `colorPrimary`, `pattern`, `surface`, `formality`, `warmth`, `seasons`, `fit`, `lastWornOn`, `daysSinceIntake`, `isFavorite`, `wantToWearMore`, `comfortIssue`, `setId`, `keepTogether` | OpenAPI `GarmentSummary` | Required readiness fields are null only for drafts |
| `availability` | PRD §6.2 / §6.3 | Fixture-only here (client filters before send); values: AVAILABLE, LAUNDRY, … |
| `readiness` | PRD §6.1 / D-23 | DRAFT \| READY — derived; drafts excluded from scenario `wardrobe` arrays |
| `displayNameSource` | D-31 | USER \| DERIVED |
| `imagePath` | Fixture | Relative path under `wardrobe/` |
| `attributeConfidence` | App. B / §10.2 #16 | Optional map for low-confidence cases |

`sets.json` mirrors PRD `GarmentSet`: `id`, `displayName`, `keepTogether`, `memberGarmentIds`.

Scenario `expected.kind` is either `complete_outfit` (slot→garment id map + set
atomicity notes) or `gap` (slot/reason, optionally `problem_code` SET_CONFLICT /
LOCK_CONFLICT).

## Wardrobe summary

- **Garment count:** 28
- **Slots covered:** ACCESSORY, BOTTOM, FOOTWEAR, JACKET, MID_LAYER, OUTERWEAR, TOP
- **Per-slot counts:** ACCESSORY=4, BOTTOM=5, FOOTWEAR=4, JACKET=4, MID_LAYER=2, OUTERWEAR=2, TOP=7
- **keepTogether sets:** 1 — `Navy Suit` (jacket + trousers), see `sets.json`
- **Drafts:** 1 (`Untitled TOP`) — excluded from generation wardrobes

## Scenario index

26 outfit (T2) scenarios are listed in `scenarios/index.json` and 1 swap re-rank scenario in
`scenarios/index-m1.json`.

| ID | Purpose |
|---|---|
| `T2-01-sportcoat-mild-work` | Sport-coat anchor, standard work day, mild weather |
| `T2-02-footwear-gap` | Every FOOTWEAR item unavailable → named gap |
| `T2-03-suit-anchor-atomic` | Suit-jacket anchor: keepTogether set used whole with a shirt |
| `T2-04-set-conflict-partner-laundry` | Suit-jacket anchor with trousers in LAUNDRY → SET_CONFLICT |
| `T2-05-dislike-olive` | Active DISLIKE on olive colour family |
| `T2-06-combination-rule` | Combination rule: sport coat + jeans pair forbidden; each alone eligible |
| `T2-07-draft-excluded` | Image-only draft in wardrobe never enters generation |
| `T2-08-cold-two-layer` | Sport-coat anchor on COLD day requires OUTERWEAR |
| `T2-09-jeans-client-formality` | Jeans anchor at client meeting — formality bridging |
| `T2-10-lock-conflict` | Lock conflicting with anchor slot → LOCK_CONFLICT |
| `T2-11-half-laundry` | Half the wardrobe in LAUNDRY — complete outfit, zero unavailable |
| `T2-12-set-shortlist-over-cap` | Suit jacket shortlists; trousers below BOTTOM cutoff still pulled in (D-30) |
| `T2-13-sportcoat-hot` | Sport-coat anchor, hot weather — warmth caution |
| `T2-14-tee-important-meeting` | T-shirt anchor, important meeting — under-formal caution |
| `T2-15-footwear-anchor` | Footwear anchor — non-top anchors |
| `T2-16-accessory-anchor` | Accessory anchor — edge slot |
| `T2-17-daily-cold` | No-anchor daily, COLD — layer requirement |
| `T2-18-daily-hot` | No-anchor daily, HOT — no outer layer |
| `T2-19-minimum-wardrobe` | Wardrobe at the exact generation minimum |
| `T2-20-repeat-sportcoat-mild-work` | Repeat of T2-01 with the same input — deterministic identity |
| `T2-21-twin-white-shirts` | Two near-identical white shirts — rationale disambiguation |
| `T2-22-low-confidence` | Low-confidence attributes on the used anchor |
| `T2-24-try-another-last` | Try another with one alternative left on the free slot |
| `T2-24-try-another-exhausted` | Try another exhausted — noAlternativeReason rather than a repeat |
| `T2-28-nine-locks` | Nine valid locks (six positions + three accessories) |
| `T2-28-tenth-lock-conflict` | Tenth lock in the anchor slot → LOCK_CONFLICT |
| `M1-F05-07-swap-rerank` | After one FOOTWEAR swap, TOP alternatives re-rank against updated outfit (D-33 / A-STALE / A29) |

### D-30 atomic-set coverage

| Scenario | What it asserts |
|---|---|
| `T2-03-suit-anchor-atomic` | Suit jacket anchor → trousers locked/selected together; shirt in TOP; refuse partial |
| `T2-04-set-conflict-partner-laundry` | Partner in LAUNDRY → `SET_CONFLICT` pre-generation; no half set |
| `T2-12-set-shortlist-over-cap` | Weak-scoring trousers still shortlisted over cap when jacket shortlists [§10.2 #26] |

## M0 exit coverage map

M0 exit [D-29 / backlog]: for every **outfit (T2)** scenario, the deterministic
builder produces the stated expected outcome (complete outfit or specified gap)
with zero model calls.

| Gate / backlog | Satisfied by |
|---|---|
| **M0-12** Fixture wardrobe (JSON + images) checked in | `wardrobe/garments.json`, `sets.json`, `images/*.svg` |
| **M0-13** Evaluation set encoded against fixture wardrobe | `scenarios/T2-*.json` (26 scenarios) |
| Slot coverage (PRD §6 / D-22) | All 7 slots present in wardrobe |
| keepTogether / atomic sets (D-22, D-30) | `T2-03`, `T2-04`, `T2-12` |
| Availability never relaxed / gap (D-25, §10.2 #12) | `T2-02`, `T2-11` |
| Preference DISLIKE (§10.2 #13) | `T2-05` |
| Combination rules (D-26, §10.2 #21) | `T2-06` |
| Drafts excluded (D-23, §10.2 #25) | `T2-07` |
| COLD two-layer (D-22, §10.2 #23) | `T2-08` |
| Formality bridging (§10.2 #5) | `T2-09` |
| Lock conflict (D-32, §10.2 #28) | `T2-10` |
| Happy-path core (§10.2 #1–3) | `T2-01` |

Attribution (T1), selfie (T5), and infrastructure (#31–34) scenarios are **out of
scope** for this M0-12/M0-13 drop (M0 gate is outfit/T2 only).

## How to load offline

```python
import json
from pathlib import Path

root = Path('fixtures')
garments = json.loads((root / 'wardrobe/garments.json').read_text())
sets = json.loads((root / 'wardrobe/sets.json').read_text())
index = json.loads((root / 'scenarios/index.json').read_text())
scenarios = [
    json.loads((root / 'scenarios' / f'{sid}.json').read_text())
    for sid in index['scenario_ids']
]
# Resolve images relative to wardrobe/:
#   (root / 'wardrobe' / g['imagePath']).read_text()
```

No network access is required. Scenario `inputs.wardrobe` already embeds the
eligible GarmentSummary subset for that case; use `fixture_overrides` plus
`garments.json` when testing client-side availability filtering.

## Validation

```bash
python3 -c "
import json, pathlib
r = pathlib.Path('fixtures')
g = json.loads((r/'wardrobe/garments.json').read_text())
s = [json.loads(p.read_text()) for p in sorted((r/'scenarios').glob('T2-*.json'))]
print(len(g), 'garments;', len(s), 'scenarios')
"
```

