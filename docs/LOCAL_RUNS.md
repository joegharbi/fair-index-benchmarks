# Local runs

Two scripts run the same server images and the same parameters as a hosted run, through each tool,
so the measurement environments can be compared directly.

| Script | Tool | Output |
|--------|------|--------|
| `scripts/run_local_framework.sh` | the benchmarking framework (Scaphandre + `measure_docker.py` / `measure_websocket.py`) | `results/local-framework/<ts>/*.csv` + `run.log` |
| `scripts/run_local_gmt.sh` | a local Green Metrics Tool install (`runner.py`) | GMT database (view by `--name` prefix) + `run.log` |

Shared parameters: HTTP = 100 client workers over the 13-point load sweep (100…80000);
WebSocket = burst and stream across {5, 50, 100} clients, 64 KB messages.

## Prerequisites
- Local images built: `PUSH=0 ./scripts/build_and_push.sh` (or pass `--build` to the framework script).
- Framework: Docker, Scaphandre, sudo, and a checkout of the
  [web-server benchmarking framework](https://github.com/joegharbi/web-server-benchmarks)
  (set `FRAMEWORK_ROOT` if it is not a sibling folder).
- GMT: a working local installation (set `GMT_ROOT`). On machines with OEM power limits (common on
  laptops), RAPL energy filtering can stop GMT's RAPL providers — rerun with `IGNORE_RAPL_FILTER=1`
  and treat those RAPL numbers as caveated. A hardware-metered machine gives the cleanest energy.

## Run
```bash
# framework (builds local images, then HTTP + WebSocket)
FRAMEWORK_ROOT=/path/to/web-server-benchmarks ./scripts/run_local_framework.sh --build

# local GMT (commit first — GMT reads the repository at --uri)
GMT_ROOT=/path/to/green-metrics-tool ./scripts/run_local_gmt.sh
```
Both accept `--http-only` / `--ws-only`; further options are documented at the top of each script.

## Running both on one machine
Running the framework and a local GMT on the same machine with the same images isolates the
tool/attribution difference from any hardware difference. A hardware-metered machine (for example a
hosted GMT cluster node) additionally provides a physical-power reference.
