#!/usr/bin/env python3
"""Verify the design asset library is consistent.

Checks (exit 1 on any failure):
  * every colorset / imageset under Assets.xcassets parses and names its files correctly;
  * asset names follow `<group>.<camelCase>` (AppIcon excepted);
  * image sets use vector template images with no <text> or raster references;
  * every name referenced by Design/AssetLibrary.swift exists in the catalog;
  * every catalog asset is referenced by Design/AssetLibrary.swift (no orphans).
Run from the repo root: python3 scripts/check-asset-library.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Assets.xcassets"
ACCESSOR = ROOT / "Design" / "AssetLibrary.swift"
NAME_RE = re.compile(r"^[a-z]+\.[a-z][A-Za-z0-9]*$")
EXEMPT = {"AppIcon"}

problems: list[str] = []
catalog_colors: set[str] = set()
catalog_images: set[str] = set()


def load(p: Path) -> dict | None:
    try:
        return json.loads(p.read_text())
    except Exception as e:  # noqa: BLE001
        problems.append(f"{p.relative_to(ROOT)}: invalid JSON ({e})")
        return None


for d in sorted(CATALOG.rglob("*.colorset")):
    name = d.name.removesuffix(".colorset")
    catalog_colors.add(name)
    if not NAME_RE.match(name):
        problems.append(f"{name}: colour name must look like group.camelCase")
    data = load(d / "Contents.json")
    if not data:
        continue
    appearances = {tuple(sorted((a.get("appearance"), a.get("value")) for a in c.get("appearances", []))) for c in data.get("colors", [])}
    if () not in appearances or (("luminosity", "dark"),) not in appearances:
        problems.append(f"{name}: needs both a default (light) and a dark colour")

for d in sorted(CATALOG.rglob("*.imageset")):
    name = d.name.removesuffix(".imageset")
    catalog_images.add(name)
    if name not in EXEMPT and not NAME_RE.match(name):
        problems.append(f"{name}: image name must look like group.camelCase")
    data = load(d / "Contents.json")
    if not data:
        continue
    props = data.get("properties", {})
    if not props.get("preserves-vector-representation"):
        problems.append(f"{name}: set preserves-vector-representation")
    if props.get("template-rendering-intent") != "template":
        problems.append(f"{name}: set template-rendering-intent = template")
    for img in data.get("images", []):
        fn = img.get("filename")
        if not fn:
            problems.append(f"{name}: image entry without filename")
            continue
        f = d / fn
        if not f.exists():
            problems.append(f"{name}: missing file {fn}")
            continue
        if f.suffix.lower() != ".svg":
            problems.append(f"{name}: {fn} is not an SVG (library images are vector)")
            continue
        body = f.read_text()
        if "<text" in body or "<image" in body:
            problems.append(f"{name}: {fn} contains <text>/<image>, unsupported in catalog SVGs")

for d in sorted(CATALOG.rglob("*.appiconset")):
    data = load(d / "Contents.json")
    if data:
        for img in data.get("images", []):
            if img.get("filename") and not (d / img["filename"]).exists():
                problems.append(f"{d.name}: missing file {img['filename']}")

src = ACCESSOR.read_text()
ref_colors = set(re.findall(r'Color\("([^"]+)"\)', src))
ref_images = set(re.findall(r'Image\("([^"]+)"\)', src))

for n in sorted(ref_colors - catalog_colors):
    problems.append(f"AssetLibrary.swift references colour '{n}' which is not in the catalog")
for n in sorted(ref_images - catalog_images):
    problems.append(f"AssetLibrary.swift references image '{n}' which is not in the catalog")
for n in sorted(catalog_colors - ref_colors):
    problems.append(f"catalog colour '{n}' is not exposed by AssetLibrary.swift")
for n in sorted(catalog_images - ref_images - EXEMPT):
    problems.append(f"catalog image '{n}' is not exposed by AssetLibrary.swift")

# Availability tokens must have a palette colour each.
tokens = re.findall(r'case (\w+) = "[A-Z]+"', (ROOT / "Design" / "AvailabilityToken.swift").read_text())
for t in tokens:
    if f"availability.{t}" not in catalog_colors:
        problems.append(f"no palette colour for availability token '{t}'")

if problems:
    print("Asset library check FAILED:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print(f"Asset library OK: {len(catalog_colors)} colours, {len(catalog_images)} images, {len(tokens)} availability tokens covered.")
