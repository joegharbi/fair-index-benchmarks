#!/usr/bin/env python3
"""Fair WebSocket echo load generator.

Mirrors the BEAM framework's measure_websocket.py semantics: N concurrent async
clients, burst or stream pattern, fixed payload size, echo + verify. Prints a
GMT_WS_LOAD_SUMMARY line (messages, success/failure, latency, throughput).
"""
import argparse
import asyncio
import os
import statistics
import time

import websockets


async def burst_client(url, size_kb, bursts, interval, res):
    payload = os.urandom(size_kb * 1024)
    try:
        async with websockets.connect(url, max_size=None, ping_interval=None) as ws:
            for _ in range(bursts):
                t0 = time.perf_counter()
                await ws.send(payload)
                r = await ws.recv()
                lat = (time.perf_counter() - t0) * 1000
                res["total"] += 1
                if r == payload:
                    res["success"] += 1
                    res["lat"].append(lat)
                else:
                    res["fail"] += 1
                if interval > 0:
                    await asyncio.sleep(interval)
    except Exception:
        res["total"] += 1
        res["fail"] += 1


async def stream_client(url, size_kb, rate, duration, res):
    payload = os.urandom(size_kb * 1024)
    try:
        async with websockets.connect(url, max_size=None, ping_interval=None) as ws:
            end = time.time() + duration
            while time.time() < end:
                t0 = time.perf_counter()
                await ws.send(payload)
                r = await ws.recv()
                lat = (time.perf_counter() - t0) * 1000
                res["total"] += 1
                if r == payload:
                    res["success"] += 1
                    res["lat"].append(lat)
                else:
                    res["fail"] += 1
                await asyncio.sleep(1.0 / rate)
    except Exception:
        res["total"] += 1
        res["fail"] += 1


async def run(a):
    res = {"total": 0, "success": 0, "fail": 0, "lat": []}
    tasks = []
    for _ in range(a.clients):
        if a.pattern == "burst":
            tasks.append(burst_client(a.url, a.size_kb, a.bursts, a.interval, res))
        else:
            tasks.append(stream_client(a.url, a.size_kb, a.rate, a.duration, res))
    t0 = time.time()
    await asyncio.gather(*tasks)
    rt = time.time() - t0
    lat = res["lat"]
    mps = res["total"] / rt if rt > 0 else 0.0
    mbps = (res["total"] * a.size_kb / 1024) / rt if rt > 0 else 0.0
    print(
        "GMT_WS_LOAD_SUMMARY "
        f"pattern={a.pattern} clients={a.clients} size_kb={a.size_kb} "
        f"total={res['total']} success={res['success']} failure={res['fail']} "
        f"runtime_s={rt:.3f} msg_s={mps:.2f} throughput_mb_s={mbps:.3f} "
        f"avg_ms={statistics.mean(lat) if lat else 0:.3f} "
        f"min_ms={min(lat) if lat else 0:.3f} max_ms={max(lat) if lat else 0:.3f}",
        flush=True,
    )


def main():
    p = argparse.ArgumentParser(description="Fair WebSocket echo load generator")
    p.add_argument("--url", required=True)
    p.add_argument("--pattern", choices=["burst", "stream"], default="burst")
    p.add_argument("--clients", type=int, default=50)
    p.add_argument("--size_kb", type=int, default=64)
    p.add_argument("--bursts", type=int, default=100)
    p.add_argument("--interval", type=float, default=0.0)
    p.add_argument("--rate", type=int, default=10)
    p.add_argument("--duration", type=int, default=30)
    p.add_argument("--startup_wait", type=int, default=int(os.environ.get("MEASURE_STARTUP_WAIT", "15")))
    a = p.parse_args()
    time.sleep(a.startup_wait)  # let the server container boot
    asyncio.run(run(a))


if __name__ == "__main__":
    main()
