# Fair Index Benchmarks — Erlang vs Elixir (tool-comparison re-run)

Behaviourally **identical** Erlang and Elixir "index" static HTTP servers, so an energy/performance
comparison reflects the **language/runtime**, not implementation accidents. Used to re-run the same
workload through three measurement paths and compare fairly:

1. **GMT cloud** (Green Coding hosted measurement cluster) — *start here*
2. **GMT locally** (your laptop)
3. **Your BEAM web-server framework locally** (Scaphandre)

> Standalone project — it does not modify `web-server-benchmarks`, `beam-gmt-benchmarks`, or
> `BEAM-web-server-benchmarks`.

## Why these are "fair"

Both servers are identical in behaviour; only the language runtime differs:

| Property | Both servers |
|---|---|
| Structure | OTP **application + supervisor + acceptor** |
| Transport | raw `gen_tcp`, `backlog: 1024`, `nodelay`, `active:false` |
| Request | **reads the full request** (recv until `\r\n\r\n`, 5 s timeout) |
| Response | `200` + `Content-Type` + **`Content-Length`** + `Connection: close` (GET→index.html); `204` (POST) |
| Index file | read **once** at boot, cached in memory |
| Connection | closed per request (no keep-alive) — identical on both |
| Packaging | built and run as a **release** (no `mix run`/dev tooling resident) |

This removes the asymmetries diagnosed in the old index servers (Erlang didn't read the request and
sent no `Content-Length`; Elixir did; Erlang ran bare `erl` vs Elixir `mix run`; both used the tiny
default backlog of 5).

## Layout

```
servers/erlang-index/   # rebar3 release: src/*.erl, rebar.config, Dockerfile, index.html
servers/elixir-index/   # mix release: lib/fair_index/*.ex, mix.exs, Dockerfile, index.html
gmt/usage_scenario.yml             # single load (vars: BEAM_IMAGE, NUM_REQUESTS)
gmt/usage_scenario_full_sweep.yml  # all 13 loads in one run (var: BEAM_IMAGE)
gmt/tools/http_load.py             # load generator (100 workers, mirrors measure_docker.py)
scripts/build_and_push.sh          # build (+push to ghcr)
scripts/pull_results.py            # list your GMT runs via the API
```

## Step 1 — Build + smoke-test the images

```bash
docker build -t fair-erlang-index servers/erlang-index
docker build -t fair-elixir-index servers/elixir-index
# smoke test (expect: HTTP/1.1 200, Content-Length, Connection: close)
docker run -d --rm -p 8001:80 --name t fair-erlang-index && sleep 2 && curl -i localhost:8001/ ; docker stop t
```

## Step 2 (CLOUD) — push images + repo, then submit

**A. Push images** to a registry the cloud can pull:
```bash
docker login ghcr.io
GHCR_USER=joegharbi TAG=v1 ./scripts/build_and_push.sh
# then: GitHub > your profile > Packages > set BOTH packages to PUBLIC
```
**B. Push this folder** to GitHub (the cloud runner clones it for the loadgen):
```bash
git init && git add -A && git commit -m "fair index benchmarks" && git branch -M main
git remote add origin https://github.com/joegharbi/fair-index-benchmarks.git
git push -u origin main
```
**C. Submit** at <https://metrics.green-coding.io/request.html> — once per image (full sweep = 1 run, all 13 loads):

| Field | Erlang run | Elixir run |
|---|---|---|
| Repository URL | `https://github.com/joegharbi/fair-index-benchmarks` | same |
| Branch | `main` | `main` |
| Filename | `gmt/usage_scenario_full_sweep.yml` | same |
| Name | `fair-erlang-index-sweep` | `fair-elixir-index-sweep` |
| Variable key | `BEAM_IMAGE` | `BEAM_IMAGE` |
| Variable value | `ghcr.io/joegharbi/fair-erlang-index:v1` | `ghcr.io/joegharbi/fair-elixir-index:v1` |

> In the key box type only `BEAM_IMAGE` (not the `__GMT_VAR_...__` wrapper).
> Cleaner but heavier alternative: use `gmt/usage_scenario.yml` with `BEAM_IMAGE` + `NUM_REQUESTS`,
> one submission per (image × load) = 26 submissions, giving isolated per-load runs.

**D. Wait** for the result email; runs show up at
<https://metrics.green-coding.io/runs.html?&uri=joegharbi&show_other_users=true>.

## Step 3 — Hand results back to me

```bash
python3 scripts/pull_results.py joegharbi fair-
```
Send me the run IDs (or just say they're done). I'll pull energy + the `GMT_HTTP_LOAD_SUMMARY`
success/failure via the API and build the comparison: **joules per successful request**, ranking,
and the success-rate overlay.

## Step 4 (LATER) — GMT locally, same images

```bash
PUSH=0 ./scripts/build_and_push.sh          # local tags: fair-erlang-index, fair-elixir-index
source /path/to/beam-gmt-benchmarks/scripts/_lib_env.sh   # or export GMT_ROOT, PY, RUNNER
git add -A && git commit -m wip             # GMT clones the repo for the loadgen
for IMG in fair-erlang-index fair-elixir-index; do
  for n in 100 1000 5000 8000 10000 15000 20000 30000 40000 50000 60000 70000 80000; do
    "$PY" "$RUNNER" --uri "$(pwd)" --filename gmt/usage_scenario.yml --name "fair-local-${IMG}-n${n}" \
      --variable "__GMT_VAR_BEAM_IMAGE__=${IMG}" --variable "__GMT_VAR_NUM_REQUESTS__=${n}"
  done
done
```

## Step 5 (LATER) — your framework locally, same images (no edits to your repo)

```bash
cd /path/to/BEAM-web-server-benchmarks
for IMG in fair-erlang-index fair-elixir-index; do
  for n in 100 1000 5000 8000 10000 15000 20000 30000 40000 50000 60000 70000 80000; do
    python3 tools/measure_docker.py --server_image "$IMG" --measurement_type static \
      --num_requests "$n" --max_workers 100 --port_mapping 8001:80 --output_csv "compare/${IMG}.csv"
  done
done
```

## Fairness reminders (for the paper)
- Same machine, same idle baseline, AC power, repeat **≥10×**, compare **medians**.
- Cloud runs land on the Esprimo P956 (physical meter); local is your laptop — compare **rankings /
  relative** differences, **not absolute joules** across machines.
- Always report **success rate next to energy** (joules per *successful* request).

## Division of labour
I can build all of this and **pull/analyse results via the API**, but I can't click the hosted form,
push to your `ghcr.io`, or run Scaphandre/sudo locally — those steps are yours. Send me run IDs when
the cloud runs finish.
