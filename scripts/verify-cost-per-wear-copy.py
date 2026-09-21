#!/usr/bin/env python3
"""Logic check for PRD §7.8 cases implemented in CostPerWearCopy (DEMO, not XCTest)."""

from decimal import Decimal, ROUND_HALF_UP


def money(amount: Decimal) -> str:
    n = amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return f"${n}"


def cpw(price, confirmed, prior):
    if price is None or price <= 0:
        return "No price recorded"
    if prior:
        lifetime = prior + max(0, confirmed)
        per = price / Decimal(lifetime)
        if confirmed == 0:
            return f"{money(per)} per wear (estimated) · not yet worn since you started"
        return (
            f"{money(per)} per wear (estimated lifetime, {lifetime} wears) · "
            f"{confirmed} confirmed in the app"
        )
    if confirmed == 0:
        return f"Wearing this once brings it to {money(price)}"
    per = price / Decimal(confirmed)
    return f"{money(per)} per wear · {confirmed} wears in the app"


cases = [
    (None, 0, None, "No price recorded"),
    (Decimal(340), 0, None, "Wearing this once brings it to $340"),
    (Decimal(336), 6, None, "$56 per wear · 6 wears in the app"),
    (Decimal(342), 6, 13, "$18 per wear (estimated lifetime, 19 wears) · 6 confirmed in the app"),
    (Decimal(78), 0, 3, "$26 per wear (estimated) · not yet worn since you started"),
]

failed = 0
for price, confirmed, prior, expected in cases:
    got = cpw(price, confirmed, prior)
    ok = got == expected
    failed += int(not ok)
    print(("PASS" if ok else "FAIL"), expected if ok else f"expected {expected!r} got {got!r}")

def wear_success_line(name, price, confirmed, prior):
    if price is None or price <= 0 or confirmed <= 0:
        return None
    lifetime = (prior or 0) + confirmed if prior else confirmed
    per = price / Decimal(max(1, lifetime))
    return f"{name} is now {money(per)} per wear"


ws = wear_success_line("Navy Top", Decimal(120), 3, None)
ws_ok = ws == "Navy Top is now $40 per wear"
failed += int(not ws_ok)
print(("PASS" if ws_ok else "FAIL"), "wear success line" if ws_ok else f"expected 'Navy Top is now $40 per wear' got {ws!r}")

raise SystemExit(failed)
