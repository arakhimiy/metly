#!/usr/bin/env python3
"""Merge docs/l10n-pending/*.json into Metly/Localizable.xcstrings.

Agents never edit the shared catalog (conflict hotspot). Each writes
docs/l10n-pending/<area>.json:  { "English source key": {"uz": "...", "ru": "..."}, ... }
Keys use the exact String(localized:)/Text literal, with %@ / %lld for interpolations.
"""
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parent.parent
catalog_path = root / "Metly/Localizable.xcstrings"
catalog = json.loads(catalog_path.read_text())
added = updated = 0
for pending in sorted((root / "docs/l10n-pending").glob("*.json")):
    for key, langs in json.loads(pending.read_text()).items():
        entry = catalog["strings"].setdefault(key, {})
        locs = entry.setdefault("localizations", {})
        for lang, value in langs.items():
            if lang not in ("uz", "ru"):
                continue
            new = {"stringUnit": {"state": "translated", "value": value}}
            if locs.get(lang) != new:
                updated += lang in locs
                added += lang not in locs
                locs[lang] = new
    print(f"merged {pending.name}")
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
print(f"added {added}, updated {updated} translations")
