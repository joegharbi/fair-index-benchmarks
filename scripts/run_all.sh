#!/usr/bin/env bash
# One command for the full final campaign on this machine, one tool at a time:
#   1. Framework  — one-by-one  (HTTP per-load + WebSocket {5,50,100})   [needs sudo + venv]
#   2. GMT bulk   — HTTP sweep  (all loads in one measurement per image)
#   3. GMT one-by-one — HTTP per-load
#   4. GMT one-by-one — WebSocket {5,50,100}
# Then build the comparison with:  python3 scripts/collect_results.py
#
# The framework runs FIRST so its single sudo prompt is up front; its keep-alive then holds the
# credential, and the GMT legs need no sudo — so after one password the whole campaign is unattended.
#
# This is long (several hours; the WebSocket bursts dominate). Trim with env vars if needed, e.g.
#   HTTP_LOADS="1000 20000 80000"  WS_CLIENTS="50"  WS_BURSTS=500  ./scripts/run_all.sh
#
# Env overrides are passed through to the underlying scripts (see their --help).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$HERE/.env" ]; then set -a; . "$HERE/.env"; set +a; fi
FRAMEWORK_ROOT="${FRAMEWORK_ROOT:-$(cd "$HERE/.." && pwd)/web-server-benchmarks}"

echo "############################################################"
echo "# FINAL FULL RUN — framework (one-by-one) + GMT (bulk + one-by-one)"
echo "# Run on a quiet machine (Wi-Fi off, NTP off, screen dimmed)."
echo "############################################################"

# 1) Framework (one-by-one HTTP + WebSocket). Activate its venv so WebSocket's `websockets` is found.
if [ -f "$FRAMEWORK_ROOT/venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$FRAMEWORK_ROOT/venv/bin/activate"
fi
echo ">>> [1/4] Framework — one-by-one (HTTP + WebSocket)"
"$HERE/scripts/run_local_framework.sh"

# 2) GMT bulk — HTTP sweep (default HTTP mode is the sweep).
echo ">>> [2/4] GMT bulk — HTTP sweep"
"$HERE/scripts/run_local_gmt.sh" --http-only

# 3) GMT one-by-one — HTTP per load.
echo ">>> [3/4] GMT one-by-one — HTTP per load"
"$HERE/scripts/run_local_gmt.sh" --per-load --http-only

# 4) GMT one-by-one — WebSocket {5,50,100} clients, burst + stream.
echo ">>> [4/4] GMT one-by-one — WebSocket {5,50,100}"
"$HERE/scripts/run_local_gmt.sh" --ws-only

echo "############################################################"
echo "# ALL RUNS DONE. Build the comparison tables with:"
echo "#   python3 scripts/collect_results.py"
echo "############################################################"
