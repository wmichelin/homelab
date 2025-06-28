#!/usr/bin/env python3

import socket
import time
import re
import json
from prometheus_client import start_http_server, Gauge, Counter
from threading import Thread
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
jail_banned_current = Gauge('fail2ban_jail_banned_current', 'Currently banned IPs', ['jail'])
jail_banned_total = Counter('fail2ban_jail_banned_total', 'Total banned IPs', ['jail'])
jail_failed_current = Gauge('fail2ban_jail_failed_current', 'Currently failed attempts', ['jail'])
fail2ban_up = Gauge('fail2ban_up', 'Fail2ban service status')

class Fail2banExporter:
    def __init__(self, socket_path='/var/run/fail2ban/fail2ban.sock'):
        self.socket_path = socket_path
        self.jails = []
        
    def send_command(self, command):
        """Send command to fail2ban socket and return response"""
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(self.socket_path)
            sock.send(command.encode() + b'\n')
            
            response = b''
            while True:
                data = sock.recv(1024)
                if not data:
                    break
                response += data
                if response.endswith(b'\n'):
                    break
            
            sock.close()
            return response.decode().strip()
        except Exception as e:
            logger.error(f"Failed to send command {command}: {e}")
            return None

    def get_jails(self):
        """Get list of active jails"""
        response = self.send_command('status')
        if not response:
            return []
        
        # Parse jail list from status output
        jails = []
        lines = response.split('\n')
        for line in lines:
            if 'Jail list:' in line:
                jail_part = line.split('Jail list:')[1].strip()
                if jail_part:
                    jails = [j.strip() for j in jail_part.split(',')]
                break
        
        return jails

    def get_jail_stats(self, jail):
        """Get statistics for a specific jail"""
        response = self.send_command(f'status {jail}')
        if not response:
            return None
        
        stats = {}
        lines = response.split('\n')
        
        for line in lines:
            line = line.strip()
            if 'Currently banned:' in line:
                stats['banned'] = int(line.split(':')[1].strip())
            elif 'Currently failed:' in line:
                stats['failed'] = int(line.split(':')[1].strip())
            elif 'Total banned:' in line:
                stats['total_banned'] = int(line.split(':')[1].strip())
        
        return stats

    def update_metrics(self):
        """Update Prometheus metrics"""
        try:
            # Check if fail2ban is responding
            jails = self.get_jails()
            if jails is None:
                fail2ban_up.set(0)
                logger.warning("Fail2ban not responding")
                return
            
            fail2ban_up.set(1)
            logger.info(f"Found jails: {jails}")
            
            # Update metrics for each jail
            for jail in jails:
                stats = self.get_jail_stats(jail)
                if stats:
                    jail_banned_current.labels(jail=jail).set(stats.get('banned', 0))
                    jail_failed_current.labels(jail=jail).set(stats.get('failed', 0))
                    
                    # Counter should only increase, so we track totals
                    total = stats.get('total_banned', 0)
                    current_total = jail_banned_total.labels(jail=jail)._value._value
                    if total > current_total:
                        jail_banned_total.labels(jail=jail).inc(total - current_total)
                    
                    logger.info(f"Jail {jail}: banned={stats.get('banned', 0)}, failed={stats.get('failed', 0)}")
                
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")
            fail2ban_up.set(0)

    def run(self):
        """Main loop"""
        logger.info("Starting fail2ban exporter")
        while True:
            self.update_metrics()
            time.sleep(30)  # Update every 30 seconds

if __name__ == '__main__':
    # Start Prometheus HTTP server
    start_http_server(9191)
    logger.info("Prometheus exporter started on port 9191")
    
    # Start exporter
    exporter = Fail2banExporter()
    exporter.run()