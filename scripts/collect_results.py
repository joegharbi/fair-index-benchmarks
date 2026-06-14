#!/usr/bin/env python3
"""Unify local GMT and framework results into clean comparison tables.

Standard library only — run it with plain `python3`, no virtualenv needed.

It reads three sources and joins them per workload configuration:
  * GMT energy            — from the local GMT Postgres database, via `docker exec ... psql`
                            (the database password is read from the postgres container, so there
                            is nothing to configure).
  * GMT success / totals  — parsed from results/local-gmt/<ts>/run.log (the GMT_*_LOAD_SUMMARY
                            lines; GMT keeps request success in the load-generator log, not in its
                            stored metrics — that asymmetry is itself a result).
  * Framework energy/success — from results/local-framework/<ts>/*.csv.

Outputs results/comparison/<ts>/http_perload.csv and websocket.csv, and prints a summary.

Configuration (optional, via .env or environment):
  RUN_PREFIX (default "local"), GMT_DB_CONTAINER, GMT_DB_PORT, GMT_DB_NAME, GMT_DB_PASSWORD.
"""
import csv
import glob
import os
import re
import subprocess
import sys
import time
from collections import defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_env():
    """Minimal .env reader (KEY=VALUE, optional quotes); does not override real env vars."""
    path = os.path.join(HERE, ".env")
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


def cfg(name, default):
    val = os.environ.get(name, "")
    return val if val else default


def db_password(container):
    pw = os.environ.get("GMT_DB_PASSWORD", "")
    if pw:
        return pw
    out = subprocess.run(
        ["docker", "exec", container, "printenv", "POSTGRES_PASSWORD"],
        capture_output=True, text=True, check=False,
    )
    return out.stdout.strip()


def psql(query, container, port, dbname, password):
    cmd = [
        "docker", "exec", "-e", f"PGPASSWORD={password}", container,
        "psql", "-h", "127.0.0.1", "-p", str(port), "-U", "postgres",
        "-d", dbname, "-At", "-F", "\t", "-c", query,
    ]
    out = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if out.returncode != 0:
        sys.stderr.write(f"psql error: {out.stderr}\n")
        return []
    return [line.split("\t") for line in out.stdout.splitlines() if line.strip()]


def gmt_energy(prefix, container, port, dbname, password):
    """Return {run_name: {'cpu_j':float, 'dram_j':float}} for the workload sub-phase."""
    query = (
        "select r.name, ps.metric, ps.value "
        "from runs r join phase_stats ps on ps.run_id = r.id "
        f"where r.name like '{prefix}-fair-%' and r.failed = false "
        "and ps.metric in ('cpu_energy_rapl_msr_component','memory_energy_rapl_msr_component') "
        "and (ps.phase like '%HTTP workload%' or ps.phase like '%WebSocket workload%')"
    )
    energy = defaultdict(lambda: {"cpu_j": 0.0, "dram_j": 0.0})
    for row in psql(query, container, port, dbname, password):
        if len(row) != 3:
            continue
        name, metric, value = row
        try:
            joules = float(value) / 1e6
        except ValueError:
            continue
        energy[name]["cpu_j" if metric.startswith("cpu") else "dram_j"] = joules
    return energy


def gmt_success_from_logs(prefix):
    """Parse GMT_*_LOAD_SUMMARY lines, keyed by the '>>> <name>' that precedes them."""
    success = {}
    for log in sorted(glob.glob(os.path.join(HERE, "results", "local-gmt", "*", "run.log"))):
        current = None
        with open(log, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.match(r"^>>>\s+(\S+)", line)
                if m:
                    current = m.group(1)
                    continue
                m = re.search(r"GMT_(?:HTTP|WS)_LOAD_SUMMARY.*?\bsuccess=(\d+)\b", line)
                if m and current:
                    tot = re.search(r"\btotal=(\d+)\b", line)
                    success[current] = (int(m.group(1)), int(tot.group(1)) if tot else None)
    return success


def read_framework():
    """Gather framework HTTP and WS rows (latest dir wins)."""
    http, ws = {}, {}
    for d in sorted(glob.glob(os.path.join(HERE, "results", "local-framework", "*"))):
        for path in glob.glob(os.path.join(d, "*.csv")):
            with open(path, encoding="utf-8", errors="replace") as fh:
                for r in csv.DictReader(fh):
                    img = (r.get("Container Name") or "").strip()
                    try:
                        energy = float(r.get("Total Energy (J)", "") or "nan")
                    except ValueError:
                        energy = float("nan")
                    if "Total Requests" in r:        # HTTP CSV
                        try:
                            load = int(r["Total Requests"])
                        except (ValueError, TypeError):
                            continue
                        http[(img, load)] = {"energy_j": energy,
                                             "success": int(r.get("Successful Requests") or 0),
                                             "total": load}
                    elif "Total Messages" in r:      # WebSocket CSV
                        try:
                            clients = int(r.get("Num Clients") or 0)
                        except ValueError:
                            continue
                        ws[(img, (r.get("Pattern") or "").strip(), clients)] = {
                            "energy_j": energy,
                            "success": int(r.get("Successful Messages") or 0),
                            "total": int(r.get("Total Messages") or 0)}
    return http, ws


def jper(numer, denom):
    try:
        return round(numer / denom, 6) if denom else ""
    except (TypeError, ZeroDivisionError):
        return ""


def main():
    load_env()
    prefix = cfg("RUN_PREFIX", "local")
    container = cfg("GMT_DB_CONTAINER", "green-coding-postgres-container")
    port = cfg("GMT_DB_PORT", "9573")
    dbname = cfg("GMT_DB_NAME", "green-coding")
    password = db_password(container)

    gmt_e = gmt_energy(prefix, container, port, dbname, password)
    gmt_s = gmt_success_from_logs(prefix)
    fw_http, fw_ws = read_framework()

    gmt_http, gmt_ws = {}, {}
    for name, e in gmt_e.items():
        m = re.match(rf"^{re.escape(prefix)}-(fair-\S+?)-n(\d+)$", name)
        if m:
            gmt_http[(m.group(1), int(m.group(2)))] = {**e, "name": name}
            continue
        m = re.match(rf"^{re.escape(prefix)}-(fair-\S+?)-ws-(burst|stream)-c(\d+)$", name)
        if m:
            gmt_ws[(m.group(1), m.group(2), int(m.group(3)))] = {**e, "name": name}

    out_dir = os.path.join(HERE, "results", "comparison", time.strftime("%Y-%m-%d_%H%M%S"))
    os.makedirs(out_dir, exist_ok=True)

    # ---- HTTP per-load ----
    http_path = os.path.join(out_dir, "http_perload.csv")
    keys = sorted(set(gmt_http) | set(fw_http), key=lambda k: (k[0], k[1]))
    with open(http_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["image", "load", "gmt_cpu_j", "gmt_dram_j", "gmt_total_j", "gmt_success",
                    "gmt_total", "fw_energy_j", "fw_success", "fw_total",
                    "gmt_j_per_req", "fw_j_per_req", "gmt_over_fw"])
        for img, load in keys:
            g, f = gmt_http.get((img, load)), fw_http.get((img, load))
            g_succ, g_total = gmt_s.get(g["name"], ("", "")) if g else ("", "")
            g_tot = g["cpu_j"] + g["dram_j"] if g else None
            w.writerow([
                img, load,
                round(g["cpu_j"], 3) if g else "", round(g["dram_j"], 3) if g else "",
                round(g_tot, 3) if g else "", g_succ, g_total,
                round(f["energy_j"], 3) if f else "", f["success"] if f else "",
                f["total"] if f else "",
                jper(g_tot, g_succ) if (g and isinstance(g_succ, int)) else "",
                jper(f["energy_j"], f["success"]) if f else "",
                round(g_tot / f["energy_j"], 1) if (g and f and f["energy_j"]) else "",
            ])

    # ---- WebSocket (matched at 50 clients) ----
    ws_path = os.path.join(out_dir, "websocket.csv")
    ws_keys = sorted(set(gmt_ws) | set(fw_ws))
    with open(ws_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["image", "pattern", "clients", "gmt_cpu_j", "gmt_dram_j", "gmt_total_j",
                    "gmt_success", "fw_energy_j", "fw_success", "gmt_over_fw"])
        for img, pattern, clients in ws_keys:
            g = gmt_ws.get((img, pattern, clients))
            f = fw_ws.get((img, pattern, clients))
            g_tot = g["cpu_j"] + g["dram_j"] if g else None
            w.writerow([
                img, pattern, clients,
                round(g["cpu_j"], 3) if g else "", round(g["dram_j"], 3) if g else "",
                round(g_tot, 3) if g else "",
                gmt_s.get(g["name"], ("", ""))[0] if g else "",
                round(f["energy_j"], 3) if f else "", f["success"] if f else "",
                round(g_tot / f["energy_j"], 1) if (g and f and f["energy_j"]) else "",
            ])

    # ---- summary ----
    print(f"HTTP per-load rows: {len(keys)}  ->  {http_path}")
    print(f"WebSocket rows:     {len(ws_keys)}  ->  {ws_path}")
    print("\nHTTP per-load (image | load | GMT total J | framework J | GMT/framework):")
    for img, load in keys:
        g, f = gmt_http.get((img, load)), fw_http.get((img, load))
        gt = round(g["cpu_j"] + g["dram_j"], 1) if g else "-"
        fe = round(f["energy_j"], 3) if f else "-"
        ratio = round((g["cpu_j"] + g["dram_j"]) / f["energy_j"], 1) if (g and f and f["energy_j"]) else "-"
        print(f"  {img:<22} {str(load):<7} {str(gt):>10} {str(fe):>10} {str(ratio):>8}")


if __name__ == "__main__":
    main()
