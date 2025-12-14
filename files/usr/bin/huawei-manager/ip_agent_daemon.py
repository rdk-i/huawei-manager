#!/usr/bin/env python3
"""
IP Agent Daemon for Huawei Manager.
Multi-device IP monitoring and auto-reconnect service.
"""
import sys
import os
import time
import json
import subprocess
import ipaddress
import logging
import urllib.request
import urllib3
import requests
from urllib.parse import urlparse
from huawei_lte_api.Client import Client
from huawei_lte_api.AuthorizedConnection import AuthorizedConnection

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
import urllib.parse
import threading
import queue
import signal
import tempfile
from logging.handlers import RotatingFileHandler

# Import shared utility
import sys
try:
    from utils import check_ip_prefix, send_telegram as utils_send_telegram
except ImportError:
    check_ip_prefix = None
    utils_send_telegram = None

# Configure logging
logger = logging.getLogger("huawei-manager")
logger.setLevel(logging.INFO)

# Console handler
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_formatter = logging.Formatter('%(levelname)s - %(message)s')
console_handler.setFormatter(console_formatter)

# File handler with rotation
file_handler = None
try:
    file_handler = RotatingFileHandler(
        '/var/log/huawei-manager.log',
        maxBytes=1024*1024,
        backupCount=3
    )
    file_handler.setLevel(logging.INFO)
    file_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)
except Exception as e:
    try:
        file_handler = RotatingFileHandler(
            '/tmp/huawei-manager.log',
            maxBytes=1024*1024,
            backupCount=3
        )
        file_handler.setLevel(logging.INFO)
        file_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)
    except Exception as fallback_err:
        logger.warning(f"Could not create log file handler: {fallback_err}")

logger.addHandler(console_handler)

# Constants
UCI_PACKAGE = "huawei-manager"
STATUS_FILE = "/tmp/huawei-manager.status"
STATUS_FILE_TMP = "/tmp/huawei-manager.status.tmp"
METRICS_FILE = "/tmp/huawei-manager.metrics"
METRICS_FILE_TMP = "/tmp/huawei-manager.metrics.tmp"
STATUS_FILE_DIR = "/tmp"

# Global state
status_lock = threading.Lock()
metrics_lock = threading.Lock()
global_statuses = {}
global_metrics = {}
notification_q = queue.Queue()
shutdown_event = threading.Event()

def get_dashboard_data(url, username, password):
    """Get all dashboard information via eternal script (isolated process)."""
    try:
        cmd = [
            "python3", "/usr/bin/huawei-manager/modem_api.py",
            url, "--username", username, "--password", password,
            "--action", "info"
        ]
        
        # Timeout after 30s to prevent hangs
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            logger.warning(f"Modem API failed (code {result.returncode}): {result.stderr}")
            return None

        # Parse output
        output = result.stdout.strip()
        response = json.loads(output)
        
        if response.get("success"):
            return response.get("data")
        else:
            logger.warning(f"Modem API error: {response.get('error')}")
            return None
            
    except json.JSONDecodeError:
        logger.error(f"Failed to parse Modem API output: {result.stdout[:100]}...")
        return None
    except subprocess.TimeoutExpired:
        logger.error("Modem API timed out")
        return None
    except Exception as e:
        logger.error(f"Error calling Modem API: {e}")
        return None

def save_dashboard_status(section_id, data):
    """Save dashboard status to JSON file."""
    try:
        filepath = f"{STATUS_FILE_DIR}/huawei-manager-status_{section_id}.json"
        # Create temp file then rename for atomic write
        tmp_path = f"{filepath}.tmp"
        with open(tmp_path, 'w') as f:
            json.dump({"success": True, "data": data, "cached": True, "timestamp": time.time()}, f)
        os.replace(tmp_path, filepath)
    except Exception as e:
        logger.error(f"Error saving dashboard status: {e}")

def extract_wan_ip(data):
    """Extract WAN IP from dashboard data using fallback methods."""
    # Method 1: Monitoring Status
    if data.get('status'):
        status = data['status']
        for field in ['WanIPAddress', 'WanIpAddress', 'wan_ip_address']:
            if field in status and status[field]:
                ip = status[field]
                if ip and ip != '' and not ip.startswith('0.0.0'):
                    return ip

    # Method 2: Device Info
    if data.get('device'):
        dev = data['device']
        if 'WanIPAddress' in dev and dev['WanIPAddress']:
            ip = dev['WanIPAddress']
            if ip and ip != '' and not ip.startswith('0.0.0'):
                return ip

    # Method 3: Dialup
    if data.get('dialup'):
        dial = data['dialup']
        if 'IPv4IPAddress' in dial and dial['IPv4IPAddress']:
            ip = dial['IPv4IPAddress']
            if ip and ip != '' and not ip.startswith('0.0.0'):
                return ip

    return None

def get_today_date():
    from datetime import datetime
    return datetime.now().strftime("%Y-%m-%d")

def load_metrics():
    global global_metrics
    try:
        if os.path.exists(METRICS_FILE):
            with open(METRICS_FILE, "r") as f:
                data = json.load(f)
                global_metrics = data.get("devices", {})
                logger.debug(f"Loaded metrics for {len(global_metrics)} devices")
    except Exception as e:
        logger.warning(f"Could not load metrics file: {e}")
        global_metrics = {}

def save_metrics():
    with metrics_lock:
        try:
            metrics_content = json.dumps({
                "devices": global_metrics,
                "last_save": int(time.time())
            }, indent=2)
            with open(METRICS_FILE_TMP, "w") as f:
                f.write(metrics_content)
                f.flush()
                os.fsync(f.fileno())
            os.replace(METRICS_FILE_TMP, METRICS_FILE)
        except Exception as e:
            logger.error(f"Error saving metrics file: {e}")

def init_device_metrics(device_id, device_name):
    with metrics_lock:
        today = get_today_date()
        if device_id not in global_metrics:
            global_metrics[device_id] = {
                "name": device_name,
                "reconnects_today": 0,
                "reconnects_date": today,
                "target_found_at": None,
                "ip_history": [],
                "current_ip_since": None,
                "total_reconnects": 0
            }
        else:
            global_metrics[device_id]["name"] = device_name
            if global_metrics[device_id].get("reconnects_date") != today:
                global_metrics[device_id]["reconnects_today"] = 0
                global_metrics[device_id]["reconnects_date"] = today

def record_reconnect(device_id):
    with metrics_lock:
        if device_id in global_metrics:
            today = get_today_date()
            if global_metrics[device_id].get("reconnects_date") != today:
                global_metrics[device_id]["reconnects_today"] = 0
                global_metrics[device_id]["reconnects_date"] = today
            global_metrics[device_id]["reconnects_today"] += 1
            global_metrics[device_id]["total_reconnects"] = global_metrics[device_id].get("total_reconnects", 0) + 1
            global_metrics[device_id]["target_found_at"] = None
    save_metrics()

def record_target_found(device_id, ip):
    with metrics_lock:
        if device_id in global_metrics:
            now = int(time.time())
            metrics = global_metrics[device_id]
            
            if metrics.get("target_found_at") is None:
                metrics["target_found_at"] = now
            
            current_ip = metrics.get("current_ip")
            if current_ip != ip:
                if current_ip and metrics.get("current_ip_since"):
                    duration = now - metrics["current_ip_since"]
                    history_entry = {
                        "ip": current_ip,
                        "start": metrics["current_ip_since"],
                        "end": now,
                        "duration": duration
                    }
                    if "ip_history" not in metrics:
                        metrics["ip_history"] = []
                    metrics["ip_history"].append(history_entry)
                    metrics["ip_history"] = metrics["ip_history"][-20:]
                
                metrics["current_ip"] = ip
                metrics["current_ip_since"] = now
    save_metrics()

def update_status(device_id, status_data):
    with status_lock:
        global_statuses[device_id] = status_data
        global_statuses[device_id]["last_update"] = int(time.time())
        
        # Include metrics
        if device_id in global_metrics:
            global_statuses[device_id]["metrics"] = global_metrics[device_id]
        
        try:
            status_content = json.dumps({"devices": global_statuses}, indent=2)
            with open(STATUS_FILE_TMP, "w") as f:
                f.write(status_content)
                f.flush()
                os.fsync(f.fileno())
            os.replace(STATUS_FILE_TMP, STATUS_FILE)
        except Exception as e:
            logger.error(f"Error writing status file: {e}")

def uci_get(section, option, default=None):
    try:
        result = subprocess.run(
            ["uci", "-q", "get", f"{UCI_PACKAGE}.{section}.{option}"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception as e:
        logger.error(f"UCI get error: {e}")
    return default

def uci_get_list(section, option):
    try:
        # Use 'uci show' because 'uci get' only returns last item for list options
        result = subprocess.run(
            ["uci", "-q", "show", f"{UCI_PACKAGE}.{section}.{option}"],
            capture_output=True, text=True
        )
        items = []
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if '=' in line:
                    # format: package.section.option='value'
                    val = line.split('=', 1)[1].strip("'\"")
                    if val: items.append(val)
            return items
    except Exception as e:
        logger.error(f"UCI get list error: {e}")
    return []

def get_device_sections():
    sections = []
    try:
        result = subprocess.run(
            ["uci", "show", UCI_PACKAGE],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if '.name=' in line or '=device' in line:
                    parts = line.split('=')[0]
                    section = parts.split('.')[1] if '.' in parts else None
                    if section and section not in sections and section != 'globals':
                        sections.append(section)
    except Exception as e:
        logger.error(f"Error getting device sections: {e}")
    return sections

def check_prefix(ip, prefixes):
    """Check if IP matches target prefixes with verbose logging."""
    if not ip: return False
    
    # Normalize prefixes to list if string, and handle malformed quotes/spaces
    raw_prefixes = prefixes if isinstance(prefixes, list) else [prefixes]
    prefixes = []
    for p in raw_prefixes:
        # aggressive cleanup: replace all quotes with space, then split
        # helps with input like: "'10.1-10.19' '10.130-10.159'"
        cleaned = str(p).replace("'", " ").replace('"', " ")
        prefixes.extend(cleaned.split())

    if not prefixes: return False

    try:
        current_ip_int = int(ipaddress.IPv4Address(ip))
    except ValueError:
        logger.error(f"Invalid current IP format: {ip}")
        return False

    logger.debug(f"Checking IP {ip} against targets: {prefixes}")

    for prefix in prefixes:
        try:
            prefix = prefix.strip()
            if not prefix: continue
            
            # Handle Ranges: 10.130-10.159
            if '-' in prefix:
                parts = prefix.split('-')
                if len(parts) != 2: continue
                
                start_str, end_str = parts[0].strip(), parts[1].strip()
                
                def to_int(ip_str, fill_val):
                    # Handle "10.130" -> "10.130.0.0"
                    ip_parts = [p.strip() for p in ip_str.split('.') if p.strip()]
                    while len(ip_parts) < 4: ip_parts.append(str(fill_val))
                    return int(ipaddress.IPv4Address(".".join(ip_parts)))
                
                s_int = to_int(start_str, 0)
                e_int = to_int(end_str, 255)
                
                if s_int <= current_ip_int <= e_int:
                    logger.debug(f"MATCH: {ip} is within range {start_str}-{end_str}")
                    return True

            # Handle CIDR: 10.120.0.0/16
            elif '/' in prefix:
                if ipaddress.IPv4Address(ip) in ipaddress.IPv4Network(prefix, strict=False):
                    logger.debug(f"MATCH: {ip} matches CIDR {prefix}")
                    return True
                    
            # Handle Simple Prefix: 10.130
            else:
                if ip.startswith(prefix):
                    logger.debug(f"MATCH: {ip} starts with {prefix}")
                    return True
                    
        except Exception as e:
            logger.warning(f"Error checking prefix '{prefix}': {e}")
            continue

    logger.info(f"MISMATCH: {ip} not found in {prefixes}")
    return False

def send_telegram(bot_token, chat_id, message, initial_delay=0):
    """Send Telegram notification using improved utils function."""
    if utils_send_telegram is not None:
        return utils_send_telegram(
            bot_token, chat_id, message,
            max_retries=8,
            logger=logger,
            initial_delay=initial_delay,
            timeout=20,
            check_connection=True
        )
    
    # Fallback if utils import failed
    logger.warning("utils.send_telegram not available, using basic fallback")
    try:
        import urllib.request
        import urllib.parse
        import ssl
        
        if initial_delay > 0:
            time.sleep(initial_delay)
        
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        data = urllib.parse.urlencode({
            'chat_id': chat_id,
            'text': message,
            'parse_mode': 'HTML'
        }).encode()
        
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        
        req = urllib.request.Request(url, data=data, method='POST')
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
        
        with urllib.request.urlopen(req, timeout=20, context=ctx) as resp:
            return resp.status == 200
    except Exception as e:
        logger.error(f"Fallback Telegram send failed: {e}")
        return False

class DeviceMonitor(threading.Thread):
    def __init__(self, section_id, config):
        super().__init__(daemon=True)
        self.section_id = section_id
        self.config = config
        self.name = config.get('name', section_id)
        self.ipagent_enabled = config.get('ipagent_enabled', False)
        self.running = True
        self.stop_event = threading.Event()
        
    def run(self):
        logger.info(f"[{self.name}] Starting monitor (IP Agent: {self.ipagent_enabled})")
        init_device_metrics(self.section_id, self.name)
        
        url = self.config.get('modem_url', '')
        username = self.config.get('modem_username', '')
        password = self.config.get('modem_password', '')
        interval = int(self.config.get('check_interval', '10') or '10')
        method = self.config.get('reconnect_method', 'data')
        prefixes = self.config.get('target_prefixes', [])
        
        if isinstance(prefixes, str):
            prefixes = [prefixes] if prefixes else []
            
        telegram_enabled = self.config.get('telegram_enabled') == '1'
        telegram_bot_token = self.config.get('telegram_bot_token', '')
        telegram_chat_id = self.config.get('telegram_chat_id', '')
        
        update_status(self.section_id, {
            "name": self.name,
            "status": "Starting",
            "current_ip": None,
            "config": {
                "target_prefixes": ", ".join(prefixes) if prefixes else "None"
            }
        })
        
        consecutive_errors = 0
        last_ip = None
        client = None
        connection = None
        
        while self.running and not shutdown_event.is_set():
            loop_start = time.time()
            
            try:
                # 1. Fetch Dashboard Data (via Subprocess)
                data = get_dashboard_data(url, username, password)
                
                if data:
                    save_dashboard_status(self.section_id, data)
                else:
                    logger.warning(f"[{self.name}] Failed to get dashboard data")
                    time.sleep(5)
                    continue

                # 3. IP Agent Logic (Only if enabled)
                if self.ipagent_enabled:
                    current_ip = extract_wan_ip(data)
                    
                    if current_ip:
                        consecutive_errors = 0
                        
                        # Check if IP matches target
                        if prefixes and check_prefix(current_ip, prefixes):
                            update_status(self.section_id, {
                                "name": self.name,
                                "status": "Connected (Target)",
                                "current_ip": current_ip,
                                "config": {"target_prefixes": ", ".join(prefixes)}
                            })
                            record_target_found(self.section_id, current_ip)
                            
                            if last_ip != current_ip:
                                logger.info(f"[{self.name}] Target IP found: {current_ip}")
                                
                                if telegram_enabled:
                                    msg = f"🎯 <b>{self.name}</b>\nTarget IP found: <code>{current_ip}</code>"
                                    if last_ip:
                                        msg += f"\nPrevious: <code>{last_ip}</code>"
                                    
                                    if send_telegram(telegram_bot_token, telegram_chat_id, msg, initial_delay=5):
                                        logger.info(f"[{self.name}] Telegram notification sent")
                                    else:
                                        logger.warning(f"[{self.name}] Failed to send Telegram notification")
                            
                            last_ip = current_ip
                        else:
                            # Reconnect Logic
                            update_status(self.section_id, {
                                "name": self.name,
                                "status": "Reconnecting...",
                                "current_ip": current_ip,
                                "config": {"target_prefixes": ", ".join(prefixes)}
                            })
                            logger.info(f"[{self.name}] IP {current_ip} mismatch, reconnecting...")
                            last_ip = current_ip
                            record_reconnect(self.section_id)
                            
                            # Use subprocess for reconnect action
                            prefixes_str = " ".join(prefixes)
                            reconnect_cmd = [
                                "python3", "/usr/bin/huawei-manager/reconnect_dialup.py",
                                url, "--username", username, "--password", password,
                                "--method", method, "--prefixes", prefixes_str
                            ]
                            
                            logger.debug(f"[{self.name}] Executing reconnect: {' '.join(reconnect_cmd)}")
                            result = subprocess.run(reconnect_cmd, capture_output=True, text=True, timeout=120)
                            
                            # Log the output for debugging
                            if result.stdout:
                                for line in result.stdout.splitlines():
                                    logger.debug(f"[{self.name}] Reconnect Output: {line}")
                            if result.stderr:
                                for line in result.stderr.splitlines():
                                    logger.debug(f"[{self.name}] Reconnect Error: {line}")
                                    
                            if result.returncode != 0:
                                 logger.warning(f"[{self.name}] Reconnect script failed with code {result.returncode}")
                            
                            # Wait for modem to stabilize (20s) + interval
                            # This prevents rapid reconnect loops
                            wait_time = 20 + interval
                            logger.debug(f"[{self.name}] Reconnect triggered. Waiting {wait_time}s for stabilization...")
                            self.stop_event.wait(wait_time)
                            continue
                    else:
                        consecutive_errors += 1
                        update_status(self.section_id, {
                            "name": self.name,
                            "status": f"No IP ({consecutive_errors})",
                            "current_ip": None,
                            "config": {"target_prefixes": ", ".join(prefixes)}
                        })
                else:
                    # Just monitoring - update status text
                    update_status(self.section_id, {
                        "name": self.name,
                        "status": "Monitoring",
                        "current_ip": extract_wan_ip(data) or "Unknown",
                        "config": {"target_prefixes": "Disabled"}
                    })

            except Exception as e:
                logger.error(f"[{self.name}] Unexpected error: {e}")
                time.sleep(5)

            # Wait for next interval
            elapsed = time.time() - loop_start
            wait_time = max(0, interval - elapsed)
            time.sleep(wait_time)

        
        logger.info(f"[{self.name}] Monitor stopped")
    
    def stop(self):
        self.running = False

def main():
    global global_log_level_set
    
    logger.info("Huawei Manager daemon starting...")
    
    # Load saved metrics
    load_metrics()
    
    # Get device sections
    sections = get_device_sections()
    if not sections:
        logger.warning("No device sections found in UCI config")
    
    # Set log level from global config
    log_level = uci_get("globals", "log_level", "INFO")
    numeric_level = getattr(logging, log_level.upper(), logging.INFO)
    logger.setLevel(numeric_level)
    if file_handler:
        file_handler.setLevel(numeric_level)
    console_handler.setLevel(numeric_level)
    logger.info(f"Log level set to: {log_level}")
    
    monitors = []
    
    for section_id in sections:
        # Check if IP Agent is enabled for this device
        raw_enabled = uci_get(section_id, "ipagent_enabled", "0")
        logger.info(f"[{section_id}] Raw ipagent_enabled value: '{raw_enabled}'")
        ipagent_enabled = raw_enabled in ["1", "true", "on", "yes", "True"]
        device_name = uci_get(section_id, "name", section_id)
        
        config = {
            'name': device_name,
            'ipagent_enabled': ipagent_enabled,
            'modem_url': uci_get(section_id, "modem_url", ""),
            'modem_username': uci_get(section_id, "modem_username", ""),
            'modem_password': uci_get(section_id, "modem_password", ""),
            'check_interval': uci_get(section_id, "check_interval", "10"),
            'reconnect_method': uci_get(section_id, "reconnect_method", "data"),
            'target_prefixes': uci_get_list(section_id, "target_prefixes"),
            'telegram_enabled': uci_get(section_id, "telegram_enabled", "0"),
            'telegram_bot_token': uci_get(section_id, "telegram_bot_token", ""),
            'telegram_chat_id': uci_get(section_id, "telegram_chat_id", ""),
        }
        
        # Skip if modem URL is not configured
        if not config['modem_url']:
            logger.warning(f"Device {section_id} has no modem URL configured, skipping")
            update_status(section_id, {
                "name": device_name,
                "status": "Not Configured",
                "current_ip": None,
                "config": {"target_prefixes": "N/A"}
            })
            continue
        
        if not ipagent_enabled:
            logger.info(f"IP Agent disabled for {device_name} ({section_id}), starting in Monitoring Mode")
        else:
            logger.info(f"Starting IP Agent monitor for {config['name']} ({section_id})")
            
        monitor = DeviceMonitor(section_id, config)
        monitor.start()
        monitors.append(monitor)
    
    if not monitors:
        logger.warning("No enabled devices found, daemon will idle")
    
    # Signal handlers
    def signal_handler(signum, frame):
        logger.info("Shutdown signal received")
        shutdown_event.set()
        for m in monitors:
            m.stop()
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Main loop
    try:
        while not shutdown_event.is_set():
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
        shutdown_event.set()
    
    # Wait for monitors to stop
    for m in monitors:
        m.join(timeout=5)
    
    # Save final metrics
    save_metrics()
    logger.info("Huawei Manager daemon stopped")

if __name__ == "__main__":
    main()
