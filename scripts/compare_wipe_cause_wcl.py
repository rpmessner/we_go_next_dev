#!/usr/bin/env python3
"""Compare production wipe-cause output with WCL v1 (cache first, no model).

Input: {"pulls": [{"id", "name", "success", "fight_time_ms", "deciding_deaths":
[{"player_name", "died_at_ms_into_fight", "killing_blow_spell_id"}]}]}.
Use scripts/wipe-cause-export.sql after the dev rebuild for persisted gold output.
Exit 1 lists mismatches; unknown WCL killing blows are reported, not mismatches.
"""
import argparse
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request

REPORT = "aW7mTPNrXwLcM2DR"


def cached(cache, filename, endpoint, params):
    path = cache / filename
    if path.exists():
        return json.loads(path.read_text())
    key = os.environ.get("WARCRAFT_LOGS_V1_API_KEY")
    if not key:
        raise ValueError(f"Missing cache entry {filename}; live fetch requires WARCRAFT_LOGS_V1_API_KEY")
    query = urllib.parse.urlencode({**params, "api_key": key})
    # Never expose request URLs or exceptions that could contain the key.
    try:
        with urllib.request.urlopen(f"https://www.warcraftlogs.com/v1/report/{endpoint}/{REPORT}?{query}") as response:
            data = json.load(response)
    except Exception:
        raise ValueError("WCL live request failed (URL redacted)") from None
    cache.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))
    return data


def compare(facts, cache):
    fights = [f for f in cached(cache, "wcl-v1-fights.json", "fights", {}).get("fights", []) if f.get("boss", 0) > 0]
    pulls = [p for p in facts["pulls"] if p["fight_time_ms"] >= 10000]
    results = []
    for pull in pulls:
        candidates = [f for f in fights if f["name"] == pull["name"] and f["kill"] == pull["success"]
                      and abs(f["end_time"] - f["start_time"] - pull["fight_time_ms"]) <= 250]
        if len(candidates) != 1:
            results.append({"pull": pull["id"], "mismatches": ["No unique WCL name/outcome/duration match"]})
            continue
        fight = candidates[0]
        entries = cached(cache, f"wcl-deaths-{fight['id']}.json", "tables/deaths",
                         {"start": fight["start_time"], "end": fight["end_time"]})["entries"]
        deaths = [] if pull["success"] else sorted(
            [d for d in entries if d["timestamp"] < fight["end_time"] - 30000],
            key=lambda d: (d["timestamp"], d["name"]))[:3]
        actual = pull["deciding_deaths"]
        mismatches, unknown, normalizations = [], [], []
        if len(actual) != len(deaths):
            mismatches.append(f"deciding death count: gold {len(actual)}, WCL {len(deaths)}")
        for rank, (a, w) in enumerate(zip(actual, deaths), 1):
            if a["player_name"] != w["name"] or a["died_at_ms_into_fight"] != w["timestamp"] - fight["start_time"]:
                mismatches.append(f"rank {rank}: player/time gold {a['player_name']} {a['died_at_ms_into_fight']}, WCL {w['name']} {w['timestamp'] - fight['start_time']}")
            blow = w.get("killingBlow", {}).get("guid")
            if blow is None:
                unknown.append({"rank": rank, "player": w["name"], "reason": "WCL names no killing blow"})
            else:
                # WCL synthetic melee=1; our parser's synthetic melee/environment=0.
                if blow == 1 and a["killing_blow_spell_id"] == 0:
                    normalizations.append({"rank": rank, "gold": 0, "wcl": 1, "reason": "synthetic melee id"})
                elif a["killing_blow_spell_id"] != blow:
                    mismatches.append(f"rank {rank} {w['name']}: gold spell {a['killing_blow_spell_id']}, WCL {blow} ({w['killingBlow'].get('name')}); different recorded killing-blow spell IDs")
        results.append({"pull": pull["id"], "fight": fight["id"], "deciding_deaths": len(actual),
                        "mismatches": mismatches, "unknown_wcl_blows": unknown, "normalizations": normalizations})
    if len(pulls) != len(fights):
        results.append({"pull": None, "mismatches": [f"shared pull coverage: gold {len(pulls)}, WCL {len(fights)}"]})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--facts", type=Path, required=True)
    args = parser.parse_args()
    try:
        results = compare(json.loads(args.facts.read_text()), args.cache)
    except (ValueError, KeyError) as error:
        parser.exit(2, f"{error}\n")
    print(json.dumps(results, indent=2, ensure_ascii=False))
    return int(any(r["mismatches"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
