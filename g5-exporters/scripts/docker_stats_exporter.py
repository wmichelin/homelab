#!/usr/bin/env python3
"""Write docker container stats to a Prometheus textfile every 60s.

Runs inside a container with /var/run/docker.sock mounted, so it does not
depend on the host user's supplementary groups (broken under systemd --user).
"""

from __future__ import annotations

import http.client
import json
import os
import socket
import time
import urllib.request

TEXTFILE_DIR = os.environ.get("TEXTFILE_DIR", "/textfile")
OUT = os.path.join(TEXTFILE_DIR, "docker_stats.prom")
SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
INTERVAL = int(os.environ.get("SCRAPE_INTERVAL", "60"))


class DockerUnixHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(DockerUnixConnection, req)


class DockerUnixConnection(http.client.HTTPConnection):
    def __init__(self, _host, timeout=30):
        super().__init__("localhost", timeout=timeout)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(SOCK)


def docker_get(path: str):
    opener = urllib.request.build_opener(DockerUnixHandler)
    with opener.open(f"http://localhost{path}", timeout=30) as resp:
        return json.load(resp)


def emit(ok: int, lines: list[str]) -> None:
    os.makedirs(TEXTFILE_DIR, exist_ok=True)
    tmp = f"{OUT}.{os.getpid()}"
    body = [
        "# HELP docker_container_running Whether the container is running (1) or not (0)",
        "# TYPE docker_container_running gauge",
        "# HELP docker_container_cpu_percent Approximate CPU usage percent",
        "# TYPE docker_container_cpu_percent gauge",
        "# HELP docker_container_memory_usage_bytes Memory usage in bytes",
        "# TYPE docker_container_memory_usage_bytes gauge",
        "# HELP docker_container_memory_limit_bytes Memory limit in bytes",
        "# TYPE docker_container_memory_limit_bytes gauge",
        "# HELP docker_stats_ok Whether the last docker stats scrape succeeded",
        "# TYPE docker_stats_ok gauge",
        "# HELP docker_stats_last_run_timestamp_seconds Unix time of last scrape",
        "# TYPE docker_stats_last_run_timestamp_seconds gauge",
        *lines,
        f"docker_stats_ok {ok}",
        f"docker_stats_last_run_timestamp_seconds {int(time.time())}",
        "",
    ]
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(body))
    os.replace(tmp, OUT)


def scrape_once() -> None:
    lines: list[str] = []
    try:
        containers = docker_get("/containers/json")
        for c in containers:
            name = (c.get("Names") or ["/unknown"])[0].lstrip("/")
            name = name.replace('"', "")
            cid = c["Id"]
            # One-shot stats (stream=false)
            stats = docker_get(f"/containers/{cid}/stats?stream=false")
            mem = stats.get("memory_stats") or {}
            usage = int(mem.get("usage") or 0)
            limit = int(mem.get("limit") or 0)
            cpu = stats.get("cpu_stats") or {}
            precpu = stats.get("precpu_stats") or {}
            cpu_delta = float((cpu.get("cpu_usage") or {}).get("total_usage") or 0) - float(
                (precpu.get("cpu_usage") or {}).get("total_usage") or 0
            )
            system_delta = float(cpu.get("system_cpu_usage") or 0) - float(
                precpu.get("system_cpu_usage") or 0
            )
            online = float(cpu.get("online_cpus") or len((cpu.get("cpu_usage") or {}).get("percpu_usage") or []) or 1)
            cpu_pct = 0.0
            if system_delta > 0 and cpu_delta >= 0:
                cpu_pct = (cpu_delta / system_delta) * online * 100.0
            lines.extend(
                [
                    f'docker_container_running{{name="{name}"}} 1',
                    f'docker_container_cpu_percent{{name="{name}"}} {cpu_pct:.2f}',
                    f'docker_container_memory_usage_bytes{{name="{name}"}} {usage}',
                    f'docker_container_memory_limit_bytes{{name="{name}"}} {limit}',
                ]
            )
        emit(1, lines)
        print(f"ok: {len(containers)} containers", flush=True)
    except Exception as exc:  # noqa: BLE001 - keep loop alive
        emit(0, lines)
        print(f"error: {exc}", flush=True)


def main() -> None:
    while True:
        scrape_once()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
