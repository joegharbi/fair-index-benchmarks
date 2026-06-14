#!/usr/bin/env bash
# Local GMT measurements of the fair servers — the same scenarios used for hosted runs,
# with local image tags and a local Green Metrics Tool install.
#
# GMT stores results in its own database; view them in the dashboard by the --name prefix.
# A full console log is also written to results/local-gmt/<timestamp>/run.log.
#
# Usage:
#   ./scripts/run_local_gmt.sh                 # HTTP as one bulk sweep per image + WebSocket
#   ./scripts/run_local_gmt.sh --per-load      # HTTP as one run PER LOAD (matches the framework's
#                                              # one-by-one structure for a fair tool comparison)
#   ./scripts/run_local_gmt.sh --http-only | --ws-only
#   IGNORE_RAPL_FILTER=1 ./scripts/run_local_gmt.sh   # bypass RAPL energy-filtering check (RAPL caveated)
#
# Env overrides: GMT_ROOT, PY, RUN_PREFIX, HTTP_IMAGES, WS_IMAGES, HTTP_LOADS (image tag = TAG, via .env)
# NOTE: --per-load runs one GMT measurement per load (13 by default), so it is much slower than the
#       sweep because of GMT's fixed per-run overhead. Trim HTTP_LOADS for a quicker pilot.
# NOTE: commit pending changes first — GMT uses the repo at --uri.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load local configuration (paths, registry) if present — see .env.example.
if [ -f "$HERE/.env" ]; then set -a; . "$HERE/.env"; set +a; fi

GMT_ROOT="${GMT_ROOT:-$(cd "$HERE/.." && pwd)/green-metrics-tool}"
PY="${PY:-${GMT_ROOT}/venv/bin/python}"
[[ -x "$PY" ]] || PY="python3"
# Force unbuffered Python output. GMT prints an interactive (y/N) prompt on a failed
# docker pull; with stdout piped to tee, a buffered prompt is invisible and the run
# looks hung while it blocks on stdin. Unbuffered output makes any prompt visible.
export PYTHONUNBUFFERED=1
# Run-name prefix (NOT the image tag). Kept separate so .env's TAG (image tag) does not rename runs.
RUN_PREFIX="${RUN_PREFIX:-local}"
# Registry-qualified refs so `docker pull` succeeds (a bare local tag resolves to
# Docker Hub, fails, and drops GMT into the hanging prompt above).
REG="${REG:-${REGISTRY:-ghcr.io}/${GHCR_USER:-joegharbi}}"
TAGV="${TAGV:-${TAG:-v1}}"
HTTP_IMAGES="${HTTP_IMAGES:-fair-erlang-index fair-elixir-index fair-erlang-dynamic fair-elixir-dynamic}"
WS_IMAGES="${WS_IMAGES:-fair-erlang-websocket fair-elixir-websocket}"
# Per-load grid for --per-load (same loads the framework uses, so the two tools are comparable).
HTTP_LOADS="${HTTP_LOADS:-100 1000 5000 8000 10000 15000 20000 30000 40000 50000 60000 70000 80000}"

DO_HTTP=1; DO_WS=1; PER_LOAD=0
for a in "$@"; do
  case "$a" in
    --http-only) DO_WS=0 ;;
    --ws-only) DO_HTTP=0 ;;
    --per-load) PER_LOAD=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 1 ;;
  esac
done

RUNNER="$GMT_ROOT/runner.py"
[[ -f "$RUNNER" ]] || { echo "ERROR: runner.py not found at $RUNNER — set GMT_ROOT" >&2; exit 1; }

if [[ "${IGNORE_RAPL_FILTER:-0}" == "1" ]]; then
  export GMT_IGNORE_RAPL_ENERGY_FILTERING_CHECK=1
  echo "NOTE: RAPL energy-filtering check disabled — treat local RAPL numbers as caveated."
fi

TS="$(date +%Y-%m-%d_%H%M%S)"
OUT="$HERE/results/local-gmt/$TS"; mkdir -p "$OUT"
exec > >(tee -a "$OUT/run.log") 2>&1

echo "=== Local GMT run $TS ==="
echo "GMT_ROOT=$GMT_ROOT  repo(--uri)=$HERE  prefix=$RUN_PREFIX  HTTP=[$DO_HTTP] WS=[$DO_WS]"

img_ref () {  # short name (no slash) -> registry ref; a full ref is used as-is
  local img="$1"; [[ "$img" == *"/"* ]] && echo "$img" || echo "${REG}/${img}:${TAGV}"
}

run_one () {
  local img="$1" scenario="$2" name="$3" ref; ref="$(img_ref "$img")"
  echo ">>> $name  (scenario=$scenario image=$ref)"
  "$PY" "$RUNNER" --uri "$HERE" --filename "$scenario" \
    --name "$name" --variable "__GMT_VAR_BEAM_IMAGE__=${ref}"
}

run_one_load () {  # single-load scenario with an explicit request count (one-by-one mode)
  local img="$1" name="$2" n="$3" ref; ref="$(img_ref "$img")"
  echo ">>> $name  (scenario=gmt/usage_scenario.yml image=$ref num_requests=$n)"
  "$PY" "$RUNNER" --uri "$HERE" --filename "gmt/usage_scenario.yml" \
    --name "$name" --variable "__GMT_VAR_BEAM_IMAGE__=${ref}" \
    --variable "__GMT_VAR_NUM_REQUESTS__=${n}"
}

if [[ "$DO_HTTP" == "1" ]]; then
  for IMG in $HTTP_IMAGES; do
    if [[ "$PER_LOAD" == "1" ]]; then
      for n in $HTTP_LOADS; do run_one_load "$IMG" "${RUN_PREFIX}-${IMG}-n${n}" "$n"; done
    else
      run_one "$IMG" "gmt/usage_scenario_full_sweep.yml" "${RUN_PREFIX}-${IMG}-sweep"
    fi
  done
fi
if [[ "$DO_WS" == "1" ]]; then
  for IMG in $WS_IMAGES; do
    run_one "$IMG" "gmt/usage_scenario_websocket.yml"        "${RUN_PREFIX}-${IMG}-ws-burst"
    run_one "$IMG" "gmt/usage_scenario_websocket_stream.yml" "${RUN_PREFIX}-${IMG}-ws-stream"
  done
fi

echo "=== done. View runs in the GMT dashboard filtered by name prefix '${RUN_PREFIX}-'. Log: $OUT/run.log ==="
