#!/usr/bin/env python3
"""Fair-comparison HTTP load generator.

Health-wait for the server, then issue parallel GETs with a FIXED worker count.
Deliberately mirrors the BEAM framework's measure_docker.py client semantics
(ThreadPoolExecutor, requests.get timeout=5, success = 2xx) so GMT and the
framework drive identical load. Prints a GMT_HTTP_LOAD_SUMMARY line per load.
"""
import argparse
import os
import time
from concurrent.futures import ThreadPoolExecutor
from threading import Lock

import requests

FULL_COUNTS = (100, 1000, 5000, 8000, 10000, 15000, 20000, 30000,
               40000, 50000, 60000, 70000, 80000)


def wait_for_http_200(url, startup_wait, retries, delay):
    time.sleep(startup_wait)
    for _ in range(retries):
        try:
            if requests.get(url, timeout=10).status_code == 200:
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(delay)
    raise RuntimeError(f"Server did not return HTTP 200 at {url}")


def run_load(url, num_requests, timeout, max_workers, skip_health):
    startup_wait = int(os.environ.get("MEASURE_STARTUP_WAIT", "15"))
    retries = int(os.environ.get("MEASURE_HEALTH_RETRIES", "25"))
    delay = int(os.environ.get("MEASURE_HEALTH_DELAY", "2"))
    if not skip_health:
        wait_for_http_200(url, startup_wait, retries, delay)
        time.sleep(3)

    lock = Lock()
    totals = {"success": 0, "failure": 0, "total": 0}

    def send_one(_n):
        try:
            resp = requests.get(url, timeout=timeout)
            ok = 200 <= resp.status_code < 300
        except requests.exceptions.RequestException:
            ok = False
        with lock:
            totals["total"] += 1
            if ok:
                totals["success"] += 1
            else:
                totals["failure"] += 1

    start = time.time()
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        list(ex.map(send_one, range(num_requests)))
    runtime_s = time.time() - start
    rps = totals["total"] / runtime_s if runtime_s > 0 else 0.0

    print(
        "GMT_HTTP_LOAD_SUMMARY "
        f"num_requests={num_requests} "
        f"max_workers={max_workers if max_workers is not None else 'system'} "
        f"total={totals['total']} success={totals['success']} failure={totals['failure']} "
        f"runtime_s={runtime_s:.3f} rps={rps:.2f}",
        flush=True,
    )


def main():
    p = argparse.ArgumentParser(description="Fair HTTP load generator (health wait + parallel GETs)")
    p.add_argument("--url", required=True)
    p.add_argument("--num_requests", type=int, default=None)
    p.add_argument("--sweep", action="store_true",
                   help=f"Run the full load list in one process: {list(FULL_COUNTS)}")
    p.add_argument("--counts", default=None, metavar="N,N,...",
                   help="With --sweep: comma-separated request counts")
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--max-workers", dest="max_workers", type=int, default=100,
                   help="ThreadPoolExecutor workers (default 100, matching the BEAM framework).")
    args = p.parse_args()

    if args.sweep:
        counts = FULL_COUNTS
        if args.counts:
            counts = tuple(int(x) for x in args.counts.split(",") if x.strip())
        for i, n in enumerate(counts):
            run_load(args.url, n, args.timeout, args.max_workers, skip_health=i > 0)
    else:
        if args.num_requests is None:
            p.error("--num_requests is required unless --sweep")
        run_load(args.url, args.num_requests, args.timeout, args.max_workers, skip_health=False)


if __name__ == "__main__":
    main()
