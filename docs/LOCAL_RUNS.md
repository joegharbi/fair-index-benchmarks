# Local runs (reproducibility)

Two scripts run the **same fair servers** and the **same parameters** as the cloud, on a local
machine, through each tool — so the three environments (cloud GMT, local GMT, local framework) are
directly comparable.

| Script | Tool | Output |
|--------|------|--------|
| `scripts/run_local_framework.sh` | our framework (Scaphandre + `measure_docker.py` / `measure_websocket.py`) | `results/local-framework/<ts>/*.csv` + `run.log` |
| `scripts/run_local_gmt.sh` | local Green Metrics Tool (`runner.py`) | GMT database (view by `--name` prefix) + `run.log` |

Shared parameters (match the cloud): HTTP = 100 client workers over the 13-point load sweep
(100…80000); WebSocket = burst **and** stream across {5, 50, 100} clients, 64 KB messages.

## Prerequisites
- Local images built: `PUSH=0 ./scripts/build_and_push.sh` (or pass `--build` to the framework script).
- **Framework:** Docker + Scaphandre + sudo, and the `BEAM-web-server-benchmarks` checkout
  (set `FRAMEWORK_ROOT` if it is not a sibling folder).
- **GMT:** a working local GMT install (set `GMT_ROOT`). On this laptop, RAPL energy filtering may
  stop GMT's RAPL providers — rerun with `IGNORE_RAPL_FILTER=1` and treat those RAPL numbers as
  caveated. (The cloud run is the clean physical-meter reference.)

## Run
```bash
# our framework (builds local images, then HTTP + WebSocket)
FRAMEWORK_ROOT=/path/to/BEAM-web-server-benchmarks ./scripts/run_local_framework.sh --build

# local GMT (commit first — GMT reads the repo at --uri)
GMT_ROOT=/path/to/green-metrics-tool ./scripts/run_local_gmt.sh
```
Both accept `--http-only` / `--ws-only`, and the env overrides documented at the top of each script.

## Why both, on the same machine
Running our framework **and** local GMT on the *same* laptop with the *same* images isolates the
**tool / attribution difference** from any machine difference. The cloud (metered Esprimo) provides
physical ground truth; the laptop provides the framework-vs-GMT head-to-head.
