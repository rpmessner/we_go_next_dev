#!/usr/bin/env python3
"""Fetch spell names from Wowhead tooltip API for all MDT spell IDs."""

import json
import urllib.request
import urllib.error
import time
import sys
import os

DUNGEONS_JSON = os.path.join(os.path.dirname(__file__), "dungeons.json")
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "spell_names.json")
WOWHEAD_URL = "https://nether.wowhead.com/tooltip/spell/{}"

def fetch_spell_name(spell_id):
    url = WOWHEAD_URL.format(spell_id)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "WeGoNext/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("name", None)
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError, TimeoutError) as e:
        print(f"  Failed {spell_id}: {e}", file=sys.stderr)
        return None

def main():
    # Load existing progress if any
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE) as f:
            spell_names = json.load(f)
        print(f"Resuming: {len(spell_names)} spells already fetched")
    else:
        spell_names = {}

    # Get all unique spell IDs
    with open(DUNGEONS_JSON) as f:
        dungeons = json.load(f)

    spell_ids = set()
    for d in dungeons:
        for e in d["enemies"]:
            for s in e["spells"]:
                spell_ids.add(s["spell_id"])

    remaining = sorted(spell_ids - set(int(k) for k in spell_names.keys()))
    print(f"{len(spell_ids)} total spells, {len(remaining)} remaining to fetch")

    for i, spell_id in enumerate(remaining):
        name = fetch_spell_name(spell_id)
        if name:
            spell_names[str(spell_id)] = name
            print(f"  [{i+1}/{len(remaining)}] {spell_id} -> {name}")
        else:
            spell_names[str(spell_id)] = f"Unknown Spell {spell_id}"
            print(f"  [{i+1}/{len(remaining)}] {spell_id} -> UNKNOWN")

        # Save progress every 50 spells
        if (i + 1) % 50 == 0:
            with open(OUTPUT_FILE, "w") as f:
                json.dump(spell_names, f, indent=2, sort_keys=True)
            print(f"  Saved progress ({len(spell_names)} spells)")

        # Rate limit: ~5 requests/sec
        time.sleep(0.2)

    # Final save
    with open(OUTPUT_FILE, "w") as f:
        json.dump(spell_names, f, indent=2, sort_keys=True)

    print(f"\nDone! {len(spell_names)} spell names saved to {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
