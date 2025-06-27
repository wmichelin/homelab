from prometheus_client import start_http_server, Gauge
import psutil
import time
import speedtest
import threading
import logging

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

def get_network_stats():
    """Get basic network statistics using psutil"""
    net_io = psutil.net_io_counters()
    NETWORK_BYTES_SENT.set(net_io.bytes_sent)
    NETWORK_BYTES_RECV.set(net_io.bytes_recv)
    NETWORK_PACKETS_SENT.set(net_io.packets_sent)
    NETWORK_PACKETS_RECV.set(net_io.packets_recv)
    NETWORK_ERRORS_IN.set(net_io.errin)
    NETWORK_ERRORS_OUT.set(net_io.errout)

def run_speedtest():
    """Run speedtest and update metrics"""
    while True:
        try:
            logger.info("Running speedtest...")
            st = speedtest.Speedtest()
            st.get_best_server()
            
            download_speed = st.download() / 1_000_000  # Convert to Mbps
            upload_speed = st.upload() / 1_000_000  # Convert to Mbps
            latency = st.results.ping
            
            NETWORK_SPEED_DOWNLOAD.set(download_speed)
            NETWORK_SPEED_UPLOAD.set(upload_speed)
            NETWORK_LATENCY.set(latency)
            
            logger.info(f"Speedtest results - Download: {download_speed:.2f} Mbps, Upload: {upload_speed:.2f} Mbps, Latency: {latency:.2f} ms")
        except Exception as e:
            logger.error(f"Error running speedtest: {e}")
        
        time.sleep(300)  # Run speedtest every 5 minutes

def main():
    # Start the HTTP server
    start_http_server(9101)
    logger.info("Network metrics exporter started on port 9101")
    
    # Start speedtest in a separate thread
    speedtest_thread = threading.Thread(target=run_speedtest)
    speedtest_thread.daemon = True
    speedtest_thread.start()
    
    # Main loop for basic network stats
    while True:
        get_network_stats()
        time.sleep(15)  # Update basic stats every 15 seconds

if __name__ == '__main__':
    main() 