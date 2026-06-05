#!/usr/bin/env python3
"""List GMT runs for a URI via the public API (so we can find the new fair-* runs).

Usage:
  python3 scripts/pull_results.py                 # all runs for uri=joegharbi
  python3 scripts/pull_results.py joegharbi fair- # only runs whose name starts with 'fair-'

Prints: <run_id> | <name> | <machine> | <created>
Give the run IDs to your analysis step to fetch energy + the GMT_HTTP_LOAD_SUMMARY.
"""
import json
import sys
import urllib.request

API = "https://api.green-coding.io"


def get(path):
    req = urllib.request.Request(API + path, headers={"User-Agent": "fair-index/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def as_list(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        return payload.get("data") or payload.get("runs") or []
    return []


def main():
    uri = sys.argv[1] if len(sys.argv) > 1 else "joegharbi"
    prefix = sys.argv[2] if len(sys.argv) > 2 else ""
    runs = as_list(get(f"/v2/runs?uri={uri}"))
    n = 0
    for run in runs:
        name = run.get("name", "") or ""
        if prefix and not name.startswith(prefix):
            continue
        print(run.get("id"), "|", name, "|", run.get("machine"), "|", run.get("created"))
        n += 1
    print(f"\n{n} run(s) matched.", file=sys.stderr)


if __name__ == "__main__":
    main()
