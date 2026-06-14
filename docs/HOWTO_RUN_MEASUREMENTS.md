# How to run the measurements

This guide describes how to run the fair web-server benchmarks in all three measurement
environments and how to collect the results from each:

1. **Cloud GMT** — the hosted Green Metrics Tool cluster (hardware power meter, reference data).
2. **Local GMT** — a Green Metrics Tool installation on your own machine (RAPL).
3. **Local dedicated framework** — the Scaphandre-based web-server benchmarking framework.

The same six images and the same workload parameters are used in every environment, so results can
be compared on equal footing. The point of the comparison is **the tools**, not the languages: the
identical Erlang and Elixir servers are the controlled subject.

| Workload | Images |
|---|---|
| static HTTP | `fair-erlang-index`, `fair-elixir-index` |
| dynamic HTTP | `fair-erlang-dynamic`, `fair-elixir-dynamic` |
| WebSocket | `fair-erlang-websocket`, `fair-elixir-websocket` |

---

## Configuration (`.env`)

The scripts read machine-specific settings (tool paths, registry namespace, database
credentials) from a `.env` file in the repository root, so nothing about your machine is
hard-coded or committed. Set it up once:

```bash
cp .env.example .env
# then edit .env and set GMT_ROOT, FRAMEWORK_ROOT, GHCR_USER, etc.
```

`.env` is git-ignored. Every command below assumes it is filled in; where a value matters it is
shown as `$GMT_ROOT`, `$FRAMEWORK_ROOT`, and so on.

---

## 0. Before every measurement run (controlled conditions)

Energy readings are sensitive to background activity. For the cleanest data, prepare the machine
before each local run (cloud runs are isolated on the cluster, so this applies mainly to local GMT
and the framework):

- Close browsers and background applications; quit anything syncing or indexing.
- Turn off Wi-Fi (or unplug Ethernet) if the workload does not need the network.
- Dim the screen and disable automatic brightness.
- Keep the power source consistent (always on AC, or always on battery — do not switch mid-campaign).
- Reduce timing noise that GMT warns about:
  ```bash
  sudo timedatectl set-ntp false     # re-enable later with: sudo timedatectl set-ntp true
  ```
- Confirm nothing else is using the machine: `docker ps` should show only the GMT stack
  (`green-coding-*`) and no leftover benchmark containers.
- Let the machine idle for about a minute so it settles before you start.

Run **one** environment at a time. Never run local GMT and the framework simultaneously — they
contend for the same cores and pollute each other's energy numbers.

---

## 1. Build the images

```bash
cd fair-index-benchmarks

# Local tags only (for local GMT and the framework):
PUSH=0 ./scripts/build_and_push.sh

# Build and push public images to the registry (for cloud GMT):
GHCR_USER=joegharbi TAG=v1 ./scripts/build_and_push.sh
```

After a push, open GitHub → your profile → **Packages** and set each of the six packages to
**public** so the cloud workers can pull them anonymously. Verify a pull works without credentials:

```bash
docker pull ghcr.io/joegharbi/fair-erlang-index:v1
```

---

## 2. Cloud GMT (hosted cluster)

The hosted cluster measures whole-machine energy with a physical power meter, which is the reference
("ground truth") for the comparison.

### Submit a run
1. Make sure the six images are pushed and **public** (section 1).
2. Commit and push this repository so the cluster can check it out:
   ```bash
   git add -A && git commit -m "measurement run" && git push
   ```
3. Open the hosted GMT interface (`https://metrics.green-coding.io`) and add a new run with:
   - **Repository URL**: `https://github.com/joegharbi/fair-index-benchmarks`
   - **Branch**: `main`
   - **Usage scenario file**: one of
     - `gmt/usage_scenario_full_sweep.yml` (HTTP sweep, 100→80000)
     - `gmt/usage_scenario_websocket.yml` (WebSocket burst)
     - `gmt/usage_scenario_websocket_stream.yml` (WebSocket stream)
   - **Variables**: enter only the middle of each placeholder name.
     - `BEAM_IMAGE` = the public image ref, for example `ghcr.io/joegharbi/fair-erlang-index:v1`
     - `NUM_REQUESTS` = the request count (only for the single-load `usage_scenario.yml`)
4. Submit, then repeat for each image + scenario you want.

Tip: short, very bursty WebSocket runs can flake on the cluster's validity threshold. Use the
burst (2000 bursts) and stream scenarios rather than a long multi-config sweep.

### Collect cloud results
```bash
# List your hosted runs (run_id | name | machine | created):
python3 scripts/pull_results.py joegharbi fair-
```
Per-run energy is available from the public API (energy is in microjoules):
`https://api.green-coding.io/v1/phase_stats/single/<run_id>`. The dashboard view for a run is
`https://metrics.green-coding.io/stats.html?id=<run_id>`.

---

## 3. Local GMT

Runs the same scenarios on a local GMT install. Energy comes from RAPL (CPU package + DRAM).

### Prerequisites
- A working GMT installation, with `GMT_ROOT` set in your `.env`. Its database stack must be up.
  Use the same path everywhere (the scripts read `GMT_ROOT` from `.env`):
  ```bash
  GMT_ROOT="/path/to/green-metrics-tool"        # your value from .env
  cd "$GMT_ROOT/docker" && docker compose up -d  # start the GMT database stack
  ```
  If `$GMT_ROOT` is empty in your shell, this `cd` fails with `/docker: No such file or
  directory` — export the variable (or use the literal path) first.
- The script passes registry-qualified image refs (`ghcr.io/joegharbi/<name>:v1`) so GMT pulls
  cleanly. The images must therefore be public (section 1), or already present locally.

### Run
```bash
cd fair-index-benchmarks
./scripts/run_local_gmt.sh          # GMT_ROOT and registry are read from .env
```
- All eight runs take roughly 45–50 minutes (4 HTTP sweeps + WebSocket burst/stream for both runtimes).
- Subsets: `--http-only`, `--ws-only`.
- Output streams live to the terminal and is also saved to
  `results/local-gmt/<timestamp>/run.log`.

Each run ends with `>>>> MEASUREMENT SUCCESSFULLY COMPLETED <<<<`. The
`Cannot calculate the total network carbon consumption ...` message is **not** a failure — it only
means no carbon-intensity provider is configured, so the SCI/carbon step is skipped. Energy is still
measured and stored. (To silence it, add a `carbon_intensity_static_machine` provider to the GMT
`config.yml`; energy values are unaffected.)

### Collect local GMT results
- **Dashboard**: `http://metrics.green-coding.internal:9142/` (filter by the `local-` name prefix).
  Each run also prints its own `stats.html?id=...` link.
- **Database** (authoritative; GMT runs Postgres on a custom port). The connection details come
  from your `.env` (`GMT_DB_PASSWORD`, `GMT_DB_PORT`, `GMT_DB_NAME`, `GMT_DB_CONTAINER`); the
  password is in your GMT install's `config.yml` (postgres section). Load `.env` first:
  ```bash
  set -a; . .env; set +a

  # list runs
  docker exec -e PGPASSWORD="$GMT_DB_PASSWORD" "$GMT_DB_CONTAINER" \
    psql -h 127.0.0.1 -p "$GMT_DB_PORT" -U postgres -d "$GMT_DB_NAME" -c \
    "select name, failed, to_char(created_at,'YYYY-MM-DD HH24:MI') t
       from runs where name like 'local-fair-%' order by created_at desc limit 12;"

  # RUNTIME energy in joules (latest run per workload)
  docker exec -e PGPASSWORD="$GMT_DB_PASSWORD" "$GMT_DB_CONTAINER" \
    psql -h 127.0.0.1 -p "$GMT_DB_PORT" -U postgres -d "$GMT_DB_NAME" -c \
    "with latest as (select distinct on (name) id, name from runs
        where name like 'local-fair-%' and failed=false order by name, created_at desc)
     select l.name,
            round(sum(case when ps.metric='cpu_energy_rapl_msr_component' then ps.value end)/1e6,1) as cpu_j,
            round(sum(case when ps.metric='memory_energy_rapl_msr_component' then ps.value end)/1e6,1) as dram_j
       from latest l join phase_stats ps on ps.run_id=l.id
      where ps.phase like '%RUNTIME%' group by l.name order by l.name;"
  ```

### Note on local RAPL
On laptops with OEM power limits, RAPL energy filtering can stop GMT's RAPL providers. This install
bypasses that check with `skip_check: true` on the two RAPL providers in the GMT `config.yml`. This
only lets the providers run; it does not change the measured values. Treat local RAPL as caveated and
use the cloud (hardware-metered) numbers as the reference.

---

## 4. Local dedicated framework

Runs the Scaphandre-based framework (`measure_docker.py` / `measure_websocket.py`) on the same images.

### Prerequisites
- Docker, Scaphandre, and `sudo` (Scaphandre needs root — the script caches sudo at the start).
- A checkout of the framework at `web-server-benchmarks` (set `FRAMEWORK_ROOT` if it is not a
  sibling folder of this repo).
- The framework's Python dependencies on the **host** Python. Unlike GMT (which installs its load
  client inside a container), the framework runs `measure_docker.py` / `measure_websocket.py`
  directly with `python3`. The WebSocket leg imports `websockets`; without it the run stops at the
  first WebSocket step with `ModuleNotFoundError: No module named 'websockets'`. On Debian and other
  PEP-668 "externally managed" systems, install into a virtual environment and activate it before
  running (the script calls bare `python3`, so the active venv is used):
  ```bash
  cd /path/to/web-server-benchmarks
  python3 -m venv venv && source venv/bin/activate
  pip install -r requirements.txt          # includes websockets
  ```
- Local images built (section 1, `PUSH=0`), or pass `--build`.

### Run
```bash
cd fair-index-benchmarks
./scripts/run_local_framework.sh    # FRAMEWORK_ROOT is read from .env
```
- It asks for your sudo password once, then runs HTTP (13-point load sweep, 100 workers) and
  WebSocket (burst + stream across {5, 50, 100} clients, 64 KB).
- Subsets: `--http-only`, `--ws-only`. Rebuild images first with `--build`.
- Output: one CSV per image plus `run.log` in `results/local-framework/<timestamp>/`.

### Collect framework results
The per-image CSVs in `results/local-framework/<timestamp>/` carry energy **and** the
successful/failed request counts in the same rows, so delivered work sits next to energy.

---

## Quick reference

| | Cloud GMT | Local GMT | Framework |
|---|---|---|---|
| Command | hosted web form | `./scripts/run_local_gmt.sh` | `./scripts/run_local_framework.sh` |
| Images | public `ghcr.io/...:v1` | public/local | local tags |
| Energy source | physical power meter | RAPL (caveated) | Scaphandre (RAPL, per-container) |
| Needs sudo | no | no | yes |
| Results | `pull_results.py` + API | local DB / dashboard | CSV files |

Run order for a clean comparison on one machine: local GMT first, then the framework (separately),
with the cloud runs as the hardware-metered reference.
