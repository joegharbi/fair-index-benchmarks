#!/usr/bin/env python3
"""List GMT runs for a URI via the public API (so we can find the fair-* runs).

The GMT /v2/runs endpoint returns each run as an ARRAY (not an object), wrapped in
{"success": ..., "data": [[...], ...]}. Columns are positional.

Usage:
  python3 scripts/pull_results.py                 # all runs for uri=joegharbi
  python3 scripts/pull_results.py joegharbi fair- # only runs whose name starts with 'fair-'

Prints: <run_id> | <name> | <machine> | <created>
"""
import json
import sys
import urllib.request

API = "https://api.green-coding.io"

# Positions within each /v2/runs row.
COL_ID, COL_NAME, COL_CREATED, COL_MACHINE = 0, 1, 4, 8


def get(path):
    req = urllib.request.Request(API + path, headers={"User-Agent": "fair-index/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def rows_of(payload):
    if isinstance(payload, dict):
        return payload.get("data") or payload.get("runs") or []
    return payload if isinstance(payload, list) else []


def main():
    uri = sys.argv[1] if len(sys.argv) > 1 else "joegharbi"
    prefix = sys.argv[2] if len(sys.argv) > 2 else ""
    n = 0
    for row in rows_of(get(f"/v2/runs?uri={uri}")):
        if not isinstance(row, (list, tuple)) or len(row) <= COL_NAME:
            continue
        name = row[COL_NAME] or ""
        if prefix and not name.startswith(prefix):
            continue
        machine = row[COL_MACHINE] if len(row) > COL_MACHINE else "?"
        created = row[COL_CREATED] if len(row) > COL_CREATED else "?"
        print(f"{row[COL_ID]} | {name} | {machine} | {created}")
        n += 1
    print(f"\n{n} run(s) matched.", file=sys.stderr)


if __name__ == "__main__":
    main()
