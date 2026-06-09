#!/usr/bin/env bash
# Local measurements with the web-server benchmarking framework (Scaphandre +
# measure_docker.py / measure_websocket.py) of the fair index/dynamic/websocket servers.
#
# Uses the same parameters as a hosted run (100 HTTP workers; WebSocket burst+stream across
# {5,50,100} clients, 64 KB) so results are directly comparable across environments.
#
# Writes one CSV per image + a full log into results/local-framework/<timestamp>/.
#
# Usage:
#   FRAMEWORK_ROOT=/path/to/web-server-benchmarks ./scripts/run_local_framework.sh
#   ./scripts/run_local_framework.sh --build       # (re)build local images first
#   ./scripts/run_local_framework.sh --http-only   # skip WebSocket
#   ./scripts/run_local_framework.sh --ws-only     # only WebSocket
#
# Env overrides: FRAMEWORK_ROOT, WORKERS, PORT, HTTP_LOADS, HTTP_IMAGES,
#                WS_IMAGES, WS_CLIENTS, WS_SIZE_KB, WS_BURSTS, WS_RATE, WS_DURATION
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FRAMEWORK_ROOT="${FRAMEWORK_ROOT:-$(cd "$HERE/.." && pwd)/web-server-benchmarks}"
WORKERS="${WORKERS:-100}"
PORT="${PORT:-8001}"
HTTP_LOADS="${HTTP_LOADS:-100 1000 5000 8000 10000 15000 20000 30000 40000 50000 60000 70000 80000}"
HTTP_IMAGES="${HTTP_IMAGES:-fair-erlang-index fair-elixir-index fair-erlang-dynamic fair-elixir-dynamic}"
WS_IMAGES="${WS_IMAGES:-fair-erlang-websocket fair-elixir-websocket}"
WS_CLIENTS="${WS_CLIENTS:-5 50 100}"
WS_SIZE_KB="${WS_SIZE_KB:-64}"
WS_BURSTS="${WS_BURSTS:-100}"
WS_RATE="${WS_RATE:-50}"
WS_DURATION="${WS_DURATION:-20}"

DO_HTTP=1; DO_WS=1; DO_BUILD=0
for a in "$@"; do
  case "$a" in
    --http-only) DO_WS=0 ;;
    --ws-only) DO_HTTP=0 ;;
    --build) DO_BUILD=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 1 ;;
  esac
done

MD="$FRAMEWORK_ROOT/tools/measure_docker.py"
MW="$FRAMEWORK_ROOT/tools/measure_websocket.py"
[[ -f "$MD" ]] || { echo "ERROR: measure_docker.py not found at $MD — set FRAMEWORK_ROOT" >&2; exit 1; }
[[ -f "$MW" ]] || { echo "ERROR: measure_websocket.py not found at $MW — set FRAMEWORK_ROOT" >&2; exit 1; }

TS="$(date +%Y-%m-%d_%H%M%S)"
OUT="$HERE/results/local-framework/$TS"
mkdir -p "$OUT"
exec > >(tee -a "$OUT/run.log") 2>&1

echo "=== Local framework run $TS ==="
echo "FRAMEWORK_ROOT=$FRAMEWORK_ROOT"
echo "WORKERS=$WORKERS PORT=$PORT  HTTP=[$DO_HTTP] WS=[$DO_WS]"
echo "Output dir: $OUT"

if [[ "$DO_BUILD" == "1" ]]; then
  echo ">>> building local images"
  PUSH=0 "$HERE/scripts/build_and_push.sh"
fi

echo ">>> caching sudo (Scaphandre needs it)"
sudo -v

cd "$OUT"   # Scaphandre JSON + any default outputs land here, tidy per run

if [[ "$DO_HTTP" == "1" ]]; then
  for IMG in $HTTP_IMAGES; do
    TYPE=static; [[ "$IMG" == *dynamic* ]] && TYPE=dynamic
    echo ">>> [HTTP/$TYPE] $IMG"
    for n in $HTTP_LOADS; do
      echo "    load=$n workers=$WORKERS"
      python3 "$MD" --server_image "$IMG" --measurement_type "$TYPE" \
        --num_requests "$n" --max_workers "$WORKERS" --port_mapping "${PORT}:80" \
        --output_csv "$OUT/${IMG}.csv"
    done
  done
fi

if [[ "$DO_WS" == "1" ]]; then
  for IMG in $WS_IMAGES; do
    echo ">>> [WebSocket] $IMG"
    for c in $WS_CLIENTS; do
      echo "    burst clients=$c size_kb=$WS_SIZE_KB bursts=$WS_BURSTS"
      python3 "$MW" --server_image "$IMG" --pattern burst --clients "$c" \
        --size_kb "$WS_SIZE_KB" --bursts "$WS_BURSTS" \
        --port_mapping "${PORT}:80" --url "ws://localhost:${PORT}/" --output_csv "$OUT/${IMG}.csv"
      echo "    stream clients=$c size_kb=$WS_SIZE_KB rate=$WS_RATE duration=$WS_DURATION"
      python3 "$MW" --server_image "$IMG" --pattern stream --clients "$c" \
        --size_kb "$WS_SIZE_KB" --rate "$WS_RATE" --duration "$WS_DURATION" \
        --port_mapping "${PORT}:80" --url "ws://localhost:${PORT}/" --output_csv "$OUT/${IMG}.csv"
    done
  done
fi

echo "=== done. CSVs + log in $OUT ==="
