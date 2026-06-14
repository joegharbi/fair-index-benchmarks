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

# Load local configuration (paths, registry) if present — see .env.example.
if [ -f "$HERE/.env" ]; then set -a; . "$HERE/.env"; set +a; fi

GMT_ROOT="${GMT_ROOT:-$(cd "$HERE/.." && pwd)/green-metrics-tool}"
PY="${PY:-${GMT_ROOT}/venv/bin/python}"
[[ -x "$PY" ]] || PY="python3"
# Force unbuffered Python output. GMT prints an interactive (y/N) prompt on a failed
# docker pull; with stdout piped to tee, a buffered prompt is invisible and the run
# looks hung while it blocks on stdin. Unbuffered output makes any prompt visible.
export PYTHONUNBUFFERED=1
TAG="${TAG:-local}"
# Registry-qualified refs so `docker pull` succeeds (a bare local tag resolves to
# Docker Hub, fails, and drops GMT into the hanging prompt above).
REG="${REG:-${REGISTRY:-ghcr.io}/${GHCR_USER:-joegharbi}}"
TAGV="${TAGV:-${TAG:-v1}}"
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
  # A short image name (no slash) is expanded to a registry ref; a full ref is used as-is.
  local ref="$img"
  [[ "$img" == *"/"* ]] || ref="${REG}/${img}:${TAGV}"
  echo ">>> $name  (scenario=$scenario image=$ref)"
  "$PY" "$RUNNER" --uri "$HERE" --filename "$scenario" \
    --name "$name" --variable "__GMT_VAR_BEAM_IMAGE__=${ref}"
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
