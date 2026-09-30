#!/usr/bin/env python3
"""Render the engine soak's table (#65) from `adb logcat -d` on stdin.

tools/soak.sh pipes the device's log in; every `SOAK {json}` line is one
pair's summary from test_driver/engine_soak.dart. The driver's verdicts
(failures, notes, whether the goldens matched) come from --verdicts. Prints
markdown; exits 1 if the log holds a different set of pairs from the one the
driver ran, since then the table would not be the run's.
"""
from __future__ import annotations

import argparse
import json
import re
import sys

SOAK = re.compile(r"SOAK (\{.*\})\s*$")


def main() -> int:
    ap = argparse.ArgumentParser()
    for name in ("device", "serial", "date", "seconds", "seeds", "verdicts",
                 "model", "android", "abi"):
        ap.add_argument(f"--{name}", required=True)
    a = ap.parse_args()
    verdicts = json.load(open(a.verdicts, encoding="utf-8"))

    rows: dict[tuple[str, str], dict] = {}
    for line in sys.stdin:
        m = SOAK.search(line)
        if m:
            p = json.loads(m.group(1))
            rows[(p["shape"], p["difficulty"])] = p
    ran = {(p["shape"], p["difficulty"]) for p in verdicts["pairs"]}
    if set(rows) != ran:
        print(f"soak: the log holds {sorted(rows)}, the driver ran "
              f"{sorted(ran)}", file=sys.stderr)
        return 1

    exceed = {f for f in verdicts["notes"] if f.startswith("soak-ceiling")}
    out = []
    partial = "" if int(a.seeds) == 20 else \
        f" — {a.seeds} seeds, not the #65 measurement of 20"
    out.append(f"## Engine soak — {a.device}, {a.date}{partial}")
    out.append("")
    out.append(f"{a.model}, Android {a.android}, {a.abi} ({a.serial}); "
               f"seeds 1..{a.seeds} per pair after one untimed warm-up; "
               f"wall clock from request to board, discarded attempts "
               f"included; whole run {a.seconds} s.")
    out.append("")
    out.append("| shape | difficulty | median ms | worst ms | best ms | "
               "median attempts | worst attempts | ceiling |")
    out.append("|---|---|---|---|---|---|---|---|")
    for p in verdicts["pairs"]:
        r = rows[(p["shape"], p["difficulty"])]
        name = f'{r["shape"]}:{r["difficulty"]}'
        if r["worstMs"] <= r["ceilingMs"]:
            verdict = f'within {r["ceilingMs"] // 1000} s'
        elif any(name in n for n in exceed):
            verdict = "**OVER** (accepted)"
        else:
            verdict = f'**OVER** (seed {r["worstSeed"]})'
        out.append(f'| {r["shape"]} | {r["difficulty"]} | {r["medianMs"]} | '
                   f'{r["worstMs"]} | {r["bestMs"]} | {r["attemptsMedian"]} | '
                   f'{r["attemptsWorst"]} | {verdict} |')
    out.append("")
    out.append("Phases, summed over the pair's seeds (the loading screen's "
               "labels mislead where CARVING GIVENS is over half):")
    out.append("")
    out.append("| shape | difficulty | GENERATING ms | CARVING GIVENS ms | "
               "READY ms | carving share |")
    out.append("|---|---|---|---|---|---|")
    for p in verdicts["pairs"]:
        r = rows[(p["shape"], p["difficulty"])]
        flag = " **over half**" if r["carvingPct"] > 50 else ""
        out.append(f'| {r["shape"]} | {r["difficulty"]} | {r["generatingMs"]} '
                   f'| {r["carvingMs"]} | {r["gradingMs"]} | '
                   f'{r["carvingPct"]}%{flag} |')
    out.append("")
    out.append("Determinism: the golden fingerprints computed on the device "
               + ("equal the committed host values."
                  if verdicts["goldensEqual"] else "do NOT all equal the "
                  "committed host values."))
    out.append("")
    if not any(f.startswith("soak-board") for f in verdicts["failures"]):
        out.append("Every board had exactly one solution and graded to the "
                   "band requested.")
    if verdicts["failures"]:
        out.append("")
        out.append("Failures:")
        out.append("")
        out.extend(f"- {f}" for f in verdicts["failures"])
    if verdicts["notes"]:
        out.append("")
        out.append("Notes:")
        out.append("")
        out.extend(f"- {n}" for n in verdicts["notes"])
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
