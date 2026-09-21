#!/usr/bin/env python3
"""Sanity-check WearLogging rules (mirrors Persistence/StubModels.swift).

Not a substitute for XCTest / Simulator. Exits non-zero on mismatch.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Optional
from uuid import uuid4


@dataclass
class Event:
    id: str
    garment_ids: frozenset
    worn_on: datetime
    voided_at: Optional[datetime] = None
    source_outfit_id: Optional[str] = None

    @property
    def is_voided(self) -> bool:
        return self.voided_at is not None


def same_day(a: datetime, b: datetime) -> bool:
    return a.date() == b.date()


def active_same_day(events: list[Event], day: datetime) -> list[Event]:
    return [e for e in events if not e.is_voided and same_day(e.worn_on, day)]


def counts(events: list[Event]) -> dict[str, int]:
    out: dict[str, int] = {}
    for e in events:
        if e.is_voided:
            continue
        for gid in e.garment_ids:
            out[gid] = out.get(gid, 0) + 1
    return out


def last_worn(events: list[Event]) -> dict[str, datetime]:
    out: dict[str, datetime] = {}
    for e in events:
        if e.is_voided:
            continue
        for gid in e.garment_ids:
            if gid not in out or e.worn_on > out[gid]:
                out[gid] = e.worn_on
    return out


def confirm(existing: list[Event], garment_ids: set[str], worn_on: datetime) -> tuple[Optional[Event], list[Event], str]:
    today = active_same_day(existing, worn_on)
    incoming = frozenset(garment_ids)
    if any(e.garment_ids == incoming for e in today):
        return None, [], "Already logged today"
    voided = [replace(e, voided_at=worn_on) for e in today]
    event = Event(id=str(uuid4()), garment_ids=incoming, worn_on=worn_on)
    if not voided:
        return event, [], "logged"
    return event, voided, "Replaced this morning's log"


def undo_today(events: list[Event], now: datetime) -> list[Event]:
    today = active_same_day(events, now)
    if not today:
        return []
    latest = max(today, key=lambda e: e.worn_on)
    latest = replace(latest, voided_at=now)
    prev = sorted(
        [
            e
            for e in events
            if e.is_voided and e.id != latest.id and e.voided_at == latest.worn_on
        ],
        key=lambda e: e.voided_at or datetime.min,
        reverse=True,
    )
    updated = [latest]
    if prev:
        updated.append(replace(prev[0], voided_at=None))
    return updated


def apply(events: list[Event], updates: list[Event]) -> list[Event]:
    by_id = {e.id: e for e in events}
    for u in updates:
        by_id[u.id] = u
    return list(by_id.values())


def main() -> int:
    a, b, c = "g-a", "g-b", "g-c"
    t0 = datetime(2026, 9, 19, 9, 0)
    t1 = datetime(2026, 9, 19, 10, 0)
    events: list[Event] = []

    ev1, voided, msg = confirm(events, {a, b}, t0)
    assert ev1 and not voided and msg == "logged"
    events.append(ev1)
    assert counts(events) == {a: 1, b: 1}

    # Done → Return → Wear again
    ev2, voided, msg = confirm(events, {a, b}, t1)
    assert ev2 is None and not voided and msg == "Already logged today"
    assert counts(events) == {a: 1, b: 1}

    # Wore something else
    ev3, voided, msg = confirm(events, {b, c}, t1)
    assert ev3 and msg == "Replaced this morning's log"
    events = apply(events, voided + [ev3])
    assert counts(events) == {b: 1, c: 1}
    assert a not in counts(events)
    lw = last_worn(events)
    assert set(lw) == {b, c}
    assert lw[b].date() == t1.date()

    # Undo restore morning
    events = apply(events, undo_today(events, t1))
    assert counts(events) == {a: 1, b: 1}
    assert c not in counts(events)

    # Undo first confirm
    events = apply(events, undo_today(events, t1))
    assert counts(events) == {}
    assert last_worn(events) == {}

    # Next day is a new log
    t2 = t0 + timedelta(days=1)
    ev4, voided, msg = confirm(events, {a}, t2)
    assert ev4 and not voided
    events.append(ev4)
    assert counts(events) == {a: 1}

    print("check-wear-logging: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
