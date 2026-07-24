#!/usr/bin/env python3
"""Export host NIC byte counters to node-exporter's textfile directory.

node-exporter's netdev collector reads counters via netlink, which is scoped to
the container network namespace. Host interface stats under sysfs remain correct
when /sys is bind-mounted, so we publish them as textfile metrics the dashboard
already queries (node_network_*_bytes_total).
"""

from __future__ import annotations

import os
import time
from pathlib import Path

TEXTFILE_DIR = Path(os.environ.get("TEXTFILE_DIR", "/textfile"))
SYSFS = Path(os.environ.get("SYSFS", "/sys"))
DEVICES = [d.strip() for d in os.environ.get("DEVICES", "enp3s0,proton0").split(",") if d.strip()]
INTERVAL = int(os.environ.get("SCRAPE_INTERVAL", "15"))
OUT = TEXTFILE_DIR / "host_netdev.prom"


def read_counter(device: str, name: str) -> int | None:
    path = SYSFS / "class" / "net" / device / "statistics" / name
    try:
        return int(path.read_text().strip())
    except (FileNotFoundError, OSError, ValueError):
        return None


def write_metrics() -> None:
    lines = [
        "# HELP node_network_receive_bytes_total Network device statistic receive_bytes.",
        "# TYPE node_network_receive_bytes_total counter",
    ]
    tx_lines = [
        "# HELP node_network_transmit_bytes_total Network device statistic transmit_bytes.",
        "# TYPE node_network_transmit_bytes_total counter",
    ]
    for device in DEVICES:
        rx = read_counter(device, "rx_bytes")
        tx = read_counter(device, "tx_bytes")
        if rx is not None:
            lines.append(f'node_network_receive_bytes_total{{device="{device}"}} {rx}')
        if tx is not None:
            tx_lines.append(f'node_network_transmit_bytes_total{{device="{device}"}} {tx}')

    payload = "\n".join(lines + tx_lines) + "\n"
    TEXTFILE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".prom.tmp")
    tmp.write_text(payload)
    tmp.replace(OUT)


def main() -> None:
    while True:
        try:
            write_metrics()
        except Exception as exc:  # noqa: BLE001 — keep loop alive
            print(f"host-netdev-exporter error: {exc}", flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
