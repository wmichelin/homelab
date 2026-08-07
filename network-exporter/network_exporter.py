from prometheus_client import start_http_server, Gauge
import logging
import os
import psutil
import speedtest
import threading
import time
import urllib.request
from typing import Tuple

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Define metrics
NETWORK_SPEED_DOWNLOAD = Gauge('network_speed_download', 'Download speed in Mbps')
NETWORK_SPEED_UPLOAD = Gauge('network_speed_upload', 'Upload speed in Mbps')
NETWORK_LATENCY = Gauge('network_latency', 'Network latency in ms')
NETWORK_BYTES_SENT = Gauge('network_bytes_sent', 'Total bytes sent')
NETWORK_BYTES_RECV = Gauge('network_bytes_recv', 'Total bytes received')
NETWORK_PACKETS_SENT = Gauge('network_packets_sent', 'Total packets sent')
NETWORK_PACKETS_RECV = Gauge('network_packets_recv', 'Total packets received')
NETWORK_ERRORS_IN = Gauge('network_errors_in', 'Total incoming errors')
NETWORK_ERRORS_OUT = Gauge('network_errors_out', 'Total outgoing errors')

# Cap payload + run rarely. Mbps = (bytes * 8 / elapsed) — short sample, extrapolated rate.
SPEEDTEST_INTERVAL_SEC = int(os.environ.get("SPEEDTEST_INTERVAL_SEC", "3600"))
SPEEDTEST_SAMPLE_BYTES = int(os.environ.get("SPEEDTEST_SAMPLE_BYTES", str(8 * 1024 * 1024)))
SPEEDTEST_TIMEOUT_SEC = int(os.environ.get("SPEEDTEST_TIMEOUT_SEC", "20"))


def get_network_stats():
    """Get basic network statistics using psutil"""
    net_io = psutil.net_io_counters()
    NETWORK_BYTES_SENT.set(net_io.bytes_sent)
    NETWORK_BYTES_RECV.set(net_io.bytes_recv)
    NETWORK_PACKETS_SENT.set(net_io.packets_sent)
    NETWORK_PACKETS_RECV.set(net_io.packets_recv)
    NETWORK_ERRORS_IN.set(net_io.errin)
    NETWORK_ERRORS_OUT.set(net_io.errout)


def _mbps(num_bytes: int, elapsed: float) -> float:
    if elapsed <= 0 or num_bytes <= 0:
        return 0.0
    return (num_bytes * 8) / elapsed / 1_000_000


def sample_download_mbps(best_url: str, sample_bytes: int, timeout: int) -> Tuple[float, int]:
    """Pull up to sample_bytes from the Ookla server and extrapolate Mbps."""
    base = best_url.rsplit("/", 1)[0]
    # 4000x4000 random JPEG is large enough to fill an 8MiB sample on one connection.
    url = f"{base}/random4000x4000.jpg"
    req = urllib.request.Request(url, headers={"User-Agent": "homelab-network-exporter/1.0"})
    total = 0
    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        while total < sample_bytes:
            chunk = resp.read(min(64 * 1024, sample_bytes - total))
            if not chunk:
                break
            total += len(chunk)
    elapsed = time.perf_counter() - start
    return _mbps(total, elapsed), total


def sample_upload_mbps(best_url: str, sample_bytes: int, timeout: int) -> Tuple[float, int]:
    """POST a fixed buffer to the Ookla upload endpoint and extrapolate Mbps."""
    payload = os.urandom(sample_bytes)
    req = urllib.request.Request(
        best_url,
        data=payload,
        method="POST",
        headers={
            "User-Agent": "homelab-network-exporter/1.0",
            "Content-Type": "application/octet-stream",
            "Content-Length": str(len(payload)),
        },
    )
    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        resp.read()
    elapsed = time.perf_counter() - start
    return _mbps(len(payload), elapsed), len(payload)


def run_speedtest():
    """Pick a nearby Ookla server, transfer a small fixed sample, publish Mbps."""
    while True:
        try:
            logger.info(
                "Running capped speed sample (%s bytes, timeout=%ss)...",
                SPEEDTEST_SAMPLE_BYTES,
                SPEEDTEST_TIMEOUT_SEC,
            )
            st = speedtest.Speedtest()
            best = st.get_best_server()
            latency = float(best.get("latency") or st.results.ping or 0)
            best_url = best["url"]

            download_speed, dl_bytes = sample_download_mbps(
                best_url, SPEEDTEST_SAMPLE_BYTES, SPEEDTEST_TIMEOUT_SEC
            )
            upload_speed, ul_bytes = sample_upload_mbps(
                best_url, SPEEDTEST_SAMPLE_BYTES, SPEEDTEST_TIMEOUT_SEC
            )

            NETWORK_SPEED_DOWNLOAD.set(download_speed)
            NETWORK_SPEED_UPLOAD.set(upload_speed)
            NETWORK_LATENCY.set(latency)

            logger.info(
                "Speed sample - Download: %.2f Mbps (%s bytes), Upload: %.2f Mbps (%s bytes), Latency: %.2f ms",
                download_speed,
                dl_bytes,
                upload_speed,
                ul_bytes,
                latency,
            )
        except Exception as e:
            logger.error("Error running speedtest: %s", e)

        time.sleep(SPEEDTEST_INTERVAL_SEC)


def main():
    start_http_server(9101)
    logger.info("Network metrics exporter started on port 9101")

    speedtest_thread = threading.Thread(target=run_speedtest)
    speedtest_thread.daemon = True
    speedtest_thread.start()

    while True:
        get_network_stats()
        time.sleep(15)


if __name__ == "__main__":
    main()
