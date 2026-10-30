#!/usr/bin/env python3
"""Prove the wipe-cause verifiers reject broken production variants.

Run from any directory. Uses only the isolated test database. Restores each file
byte-for-byte, even on failure. Do not run concurrently with edits or Mix gates.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "we_go_next"
FACT = APP / "lib/we_go_next/gold/fact_wipe_cause.ex"
TOOL = APP / "lib/we_go_next/analysis/tools/wipe_cause.ex"
TESTS = ["test/we_go_next/gold/fact_wipe_cause_test.exs",
         "test/we_go_next/analysis/wipe_cause_wcl_test.exs",
         "test/we_go_next_web/wipe_cause_mcp_test.exs"]
MUTATIONS = [
    ("cutoff_removed", FACT, "encounter.fight_time_ms - 30_000", "encounter.fight_time_ms - 0",
     ["reference set:", "Warcraft Logs:"]),
    ("order_reversed", FACT, "Enum.sort_by(&{&1.died_at_ms_into_fight, &1.target_guid})",
     "Enum.sort_by(&{&1.died_at_ms_into_fight, &1.target_guid}, :desc)",
     ["AI agreement:", "Warcraft Logs:"]),
    ("unknown_avoidable", FACT, 'defp avoidable(%{mechanic_type: :unknown}), do: nil',
     'defp avoidable(%{mechanic_type: :unknown}), do: true',
     ["stamped, idempotent rebuild"]),
    ("model_cost_nonzero", TOOL, "model_calls: 0,", "model_calls: 1,",
     ["cost and binding:"]),
]


def run(output, name):
    env = {**os.environ, "MIX_ENV": "test", "MIX_TEST_PARTITION": "_wipe", "TEST_PORT": "4016"}
    result = subprocess.run(["mix", "test", *TESTS, "--seed", "0"], cwd=APP,
                            env=env, text=True, capture_output=True, timeout=120)
    text = result.stdout + result.stderr
    (output / (name + ".log")).write_text(text)
    return result.returncode, text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    for name, path, before, after, required in MUTATIONS:
        original = path.read_bytes()
        text = original.decode()
        if text.count(before) != 1:
            raise ValueError(f"{name}: expected one mutation site")
        try:
            path.write_text(text.replace(before, after))
            code, log = run(args.output, name)
            failed = re.findall(r"\d+\) test ([^\n]+)", log)
            if code == 0 or not failed or not all(any(marker in test for test in failed) for marker in required):
                raise ValueError(f"{name}: expected behavioral failures not observed; inspect log")
            records.append({"mutation": name, "exit": code, "failing_tests": failed})
        finally:
            path.write_bytes(original)
    code, _ = run(args.output, "restored")
    if code:
        raise ValueError("Restored production code did not pass")
    records.append({"variant": "restored", "exit": code})
    (args.output / "summary.json").write_text(json.dumps(records, indent=2) + "\n")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
