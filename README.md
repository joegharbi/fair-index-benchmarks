# Fair Web-Server Benchmarks

Behaviourally identical web-server implementations across BEAM runtimes (Erlang and Elixir), so that
energy and performance comparisons reflect the **language and runtime** rather than incidental
implementation differences. The suite covers three workload families — **static HTTP**, **dynamic
HTTP**, and **WebSocket** — and is built to be measured by both the
[Green Metrics Tool](https://github.com/green-coding-solutions/green-metrics-tool) and a
Scaphandre-based [web-server benchmarking framework](https://github.com/joegharbi/web-server-benchmarks),
so results from different tools and environments can be compared on equal footing.

## Why "fair"

When comparing the energy of servers written in different languages, implementation details (HTTP
correctness, connection handling, runtime packaging) can dominate the result and mask the actual
language/runtime cost. Every server here is implemented to the **same specification**; only the
language runtime differs.

| Property | All servers |
|---|---|
| Structure | OTP application + supervisor + acceptor |
| Transport | raw `gen_tcp` — `backlog: 1024`, `nodelay`, `active: false` |
| HTTP request | fully read (recv until `\r\n\r\n`, 5 s timeout) |
| HTTP response | `200` with `Content-Type` + `Content-Length` + `Connection: close` (`GET`); `204` (`POST`) |
| WebSocket | RFC 6455 handshake + frame echo; unmasked server frames |
| Packaging | compiled and run as a release (no build/dev tooling resident) |
| Concurrency | one lightweight process per connection |

## Workloads and images

Two runtimes × three workloads = six images:

| Workload | Description | Images |
|---|---|---|
| `static` | serves a small HTML file, read once at startup | `fair-erlang-index`, `fair-elixir-index` |
| `dynamic` | generates the response body per request (current time) | `fair-erlang-dynamic`, `fair-elixir-dynamic` |
| `websocket` | RFC 6455 echo server | `fair-erlang-websocket`, `fair-elixir-websocket` |

## Layout

```
servers/
  erlang-index/      elixir-index/        # static file server (release)
  erlang-dynamic/    elixir-dynamic/      # dynamic (generated body) server
  erlang-websocket/  elixir-websocket/    # RFC 6455 echo server
gmt/
  usage_scenario.yml                       # single HTTP load (vars: BEAM_IMAGE, NUM_REQUESTS)
  usage_scenario_full_sweep.yml            # HTTP load sweep in one run (var: BEAM_IMAGE)
  usage_scenario_websocket.yml             # single WebSocket burst run
  usage_scenario_websocket_full_sweep.yml  # WebSocket burst+stream across {5,50,100} clients
  tools/http_load.py                       # HTTP load generator
  tools/ws_load.py                         # WebSocket load generator
scripts/
  build_and_push.sh                        # build all images (and optionally push to a registry)
  run_local_gmt.sh                         # run the GMT scenarios on a local GMT install
  run_local_framework.sh                   # run the benchmarking framework locally
  pull_results.py                          # list hosted GMT runs via the public API
docs/LOCAL_RUNS.md                         # local-run instructions
```

## Requirements

- Docker
- A [Green Metrics Tool](https://github.com/green-coding-solutions/green-metrics-tool) installation
  (local or hosted) for the GMT measurements
- [Scaphandre](https://github.com/hubblo-org/scaphandre) and the
  [web-server benchmarking framework](https://github.com/joegharbi/web-server-benchmarks)
  for the framework measurements
- A container registry (only needed when running on a hosted GMT cluster)

## Build

```bash
# all six images, local tags only
PUSH=0 ./scripts/build_and_push.sh
# or a single image
docker build -t fair-erlang-index servers/erlang-index
```

Quick check (expect `HTTP/1.1 200`, `Content-Length`, `Connection: close`):

```bash
docker run -d --rm -p 8001:80 --name t fair-erlang-index && sleep 2 && curl -i localhost:8001/ ; docker stop t
```

## Running on a hosted GMT cluster

1. Build and push the images, then make the packages public:
   ```bash
   docker login ghcr.io
   GHCR_USER=<owner> TAG=v1 ./scripts/build_and_push.sh
   ```
2. Push this repository to a Git host the runner can clone.
3. Submit one measurement per image, providing the scenario filename and the `BEAM_IMAGE` variable —
   e.g. scenario `gmt/usage_scenario_full_sweep.yml` with
   `BEAM_IMAGE = ghcr.io/<owner>/fair-erlang-index:v1`. WebSocket uses
   `gmt/usage_scenario_websocket_full_sweep.yml`.
4. List finished runs: `python3 scripts/pull_results.py <uri-filter>`.

## Running locally

Both legs use the same images and the same parameters — HTTP: 100 client workers over a 13-point load
sweep (100…80000); WebSocket: burst and stream across {5, 50, 100} clients.

```bash
# Green Metrics Tool (local install)
GMT_ROOT=/path/to/green-metrics-tool ./scripts/run_local_gmt.sh

# Benchmarking framework (Scaphandre)
FRAMEWORK_ROOT=/path/to/BEAM-web-server-benchmarks ./scripts/run_local_framework.sh --build
```

See [docs/LOCAL_RUNS.md](docs/LOCAL_RUNS.md) for options and prerequisites.

## Interpreting results

- Report **success/failure alongside energy**: a server that drops requests can appear more efficient
  if only energy is considered.
- Compare **rankings and relative differences** across machines; absolute energy is only comparable
  within the same hardware.
- Prefer a **hardware power meter** as the reference where available; component RAPL readings may be
  filtered on machines with OEM power limits.

## Related

- BEAM-web-server-benchmarks: <https://github.com/joegharbi/BEAM-web-server-benchmarks>
- Green Metrics Tool: <https://github.com/green-coding-solutions/green-metrics-tool> ·
  <https://metrics.green-coding.io>
- Scaphandre: <https://github.com/hubblo-org/scaphandre>

## License

MIT — see [LICENSE](LICENSE).
