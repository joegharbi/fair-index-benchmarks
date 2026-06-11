#!/usr/bin/env bash
# Local GMT measurements of the fair servers — the same scenarios used for hosted runs,
# with local image tags and a local Green Metrics Tool install.
#
# GMT stores results in its own database; view them in the dashboard by the --name prefix.
# A full console log is also written to results/local-gmt/<timestamp>/run.log.
#
# Usage:
#   GMT_ROOT=/path/to/green-metrics-tool ./scripts/run_local_gmt.sh
#   ./scripts/run_local_gmt.sh --http-only | --ws-only
#   IGNORE_RAPL_FILTER=1 ./scripts/run_local_gmt.sh   # bypass RAPL energy-filtering check (RAPL caveated)
#
# Env overrides: GMT_ROOT, PY, TAG, HTTP_IMAGES, WS_IMAGES
# NOTE: commit pending changes first — GMT uses the repo at --uri.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GMT_ROOT="${GMT_ROOT:-$(cd "$HERE/.." && pwd)/green-metrics-tool}"
PY="${PY:-python3}"
TAG="${TAG:-local}"
HTTP_IMAGES="${HTTP_IMAGES:-fair-erlang-index fair-elixir-index fair-erlang-dynamic fair-elixir-dynamic}"
WS_IMAGES="${WS_IMAGES:-fair-erlang-websocket fair-elixir-websocket}"

DO_HTTP=1; DO_WS=1
for a in "$@"; do
  case "$a" in
    --http-only) DO_WS=0 ;;
    --ws-only) DO_HTTP=0 ;;
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
echo "GMT_ROOT=$GMT_ROOT  repo(--uri)=$HERE  TAG=$TAG  HTTP=[$DO_HTTP] WS=[$DO_WS]"

run_one () {
  local img="$1" scenario="$2" name="$3"
  echo ">>> $name  (scenario=$scenario image=$img)"
  "$PY" "$RUNNER" --uri "$HERE" --filename "$scenario" \
    --name "$name" --variable "__GMT_VAR_BEAM_IMAGE__=${img}"
}

if [[ "$DO_HTTP" == "1" ]]; then
  for IMG in $HTTP_IMAGES; do
    run_one "$IMG" "gmt/usage_scenario_full_sweep.yml" "${TAG}-${IMG}-sweep"
  done
fi
if [[ "$DO_WS" == "1" ]]; then
  for IMG in $WS_IMAGES; do
    run_one "$IMG" "gmt/usage_scenario_websocket.yml"        "${TAG}-${IMG}-ws-burst"
    run_one "$IMG" "gmt/usage_scenario_websocket_stream.yml" "${TAG}-${IMG}-ws-stream"
  done
fi

echo "=== done. View runs in the GMT dashboard filtered by name prefix '${TAG}-'. Log: $OUT/run.log ==="
