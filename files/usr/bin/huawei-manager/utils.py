#!/usr/bin/env python3
"""
Utility functions for Huawei Manager.
"""
import subprocess
import urllib.request
import urllib.parse
import urllib.error
import socket
import time
import random
import json
import ssl

UCI_PACKAGE = "huawei-manager"

def uci_get(section, option, default=None):
    """Get a UCI option value."""
    try:
        result = subprocess.run(
            ["uci", "-q", "get", f"{UCI_PACKAGE}.{section}.{option}"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return default

def uci_get_list(section, option):
    """Get a UCI list option."""
    try:
        result = subprocess.run(
            ["uci", "-q", "get", f"{UCI_PACKAGE}.{section}.{option}"],
            capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return [v.strip() for v in result.stdout.strip().split('\n') if v.strip()]
    except Exception:
        pass
    return []

def check_internet_connectivity(timeout=5, logger=None):
    """
    Check if internet is available before attempting Telegram send.
    Tries multiple reliable endpoints.
    
    Args:
        timeout: Connection timeout in seconds
        logger: Optional logger instance
    
    Returns:
        bool: True if internet is available
    """
    test_hosts = [
        ("8.8.8.8", 53),      # Google DNS
        ("1.1.1.1", 53),      # Cloudflare DNS
        ("208.67.222.222", 53) # OpenDNS
    ]
    
    for host, port in test_hosts:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            sock.connect((host, port))
            sock.close()
            return True
        except (socket.timeout, socket.error, OSError):
            continue
    
    if logger:
        logger.warning("Internet connectivity check failed")
    return False


def send_telegram(bot_token, chat_id, message, max_retries=8, logger=None,
                  initial_delay=0, timeout=20, check_connection=True):
    """
    Send a Telegram notification with improved retry logic.
    
    Features:
    - Pre-connection check before first attempt
    - Exponential backoff with jitter
    - Specific error handling for different failure types
    - Rate limit (429) compliance with Retry-After header
    - Differentiated handling for client vs server errors
    - Configurable initial delay for post-reconnect scenarios
    
    Args:
        bot_token: Telegram bot token
        chat_id: Target chat ID
        message: Message text (HTML supported)
        max_retries: Maximum number of retry attempts (default: 8)
        logger: Optional logger instance for detailed logging
        initial_delay: Seconds to wait before first attempt (default: 0)
        timeout: HTTP request timeout in seconds (default: 20)
        check_connection: Check internet connectivity first (default: True)
    
    Returns:
        bool: True if message sent successfully, False otherwise
    """
    if not bot_token or not chat_id:
        return False
    
    def log_info(msg):
        if logger:
            logger.info(msg)
    
    def log_warning(msg):
        if logger:
            logger.warning(msg)
    
    def log_error(msg):
        if logger:
            logger.error(msg)
    
    def log_debug(msg):
        if logger:
            logger.debug(msg)
    
    def calculate_backoff(attempt, base=2, max_delay=45):
        """Exponential backoff with jitter. Max delay reduced to 45s."""
        delay = min(base ** attempt + random.uniform(0, 2), max_delay)
        return delay
    
    # Initial delay for post-reconnect scenarios
    if initial_delay > 0:
        log_debug(f"Waiting {initial_delay}s before sending Telegram notification")
        time.sleep(initial_delay)
    
    # Pre-connection check
    if check_connection:
        connectivity_retries = 3
        for i in range(connectivity_retries):
            if check_internet_connectivity(timeout=3, logger=logger):
                break
            if i < connectivity_retries - 1:
                log_warning(f"No internet connectivity, waiting 5s... ({i+1}/{connectivity_retries})")
                time.sleep(5)
        else:
            log_error("Internet connectivity not available after retries")
            # Continue anyway, the main retry loop will handle it
    
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = urllib.parse.urlencode({
        'chat_id': chat_id,
        'text': message,
        'parse_mode': 'HTML'
    }).encode()

    for attempt in range(max_retries):
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            
            req = urllib.request.Request(url, data=data, method='POST')
            req.add_header('Content-Type', 'application/x-www-form-urlencoded')
            
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                if resp.status == 200:
                    if attempt > 0:
                        log_info(f"Telegram sent successfully after {attempt + 1} attempts")
                    return True
                    
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry_after = int(e.headers.get('Retry-After', 30))
                log_warning(f"Telegram rate limited. Waiting {retry_after}s")
                time.sleep(retry_after)
                continue
            elif e.code >= 500:
                delay = calculate_backoff(attempt)
                log_warning(f"Telegram server error {e.code}, retry {attempt+1}/{max_retries} in {delay:.1f}s")
                time.sleep(delay)
                continue
            else:
                log_error(f"Telegram client error {e.code}: {e.reason}")
                return False
                
        except urllib.error.URLError as e:
            reason_str = str(e.reason)
            if isinstance(e.reason, socket.timeout):
                delay = calculate_backoff(attempt)
                log_warning(f"Telegram timeout, retry {attempt+1}/{max_retries} in {delay:.1f}s")
                time.sleep(delay)
            elif 'Connection refused' in reason_str:
                # Reduced max from 120s to 60s for connection refused
                delay = min(5 + (3 ** attempt), 60)
                log_warning(f"Connection refused, retry {attempt+1}/{max_retries} in {delay:.1f}s")
                time.sleep(delay)
            elif 'Name or service not known' in reason_str or 'getaddrinfo failed' in reason_str:
                delay = calculate_backoff(attempt, base=3, max_delay=45)
                log_warning(f"DNS error, retry {attempt+1}/{max_retries} in {delay:.1f}s")
                time.sleep(delay)
            elif 'SSL' in reason_str or 'ssl' in reason_str:
                delay = calculate_backoff(attempt)
                log_warning(f"SSL error: {reason_str}, retry {attempt+1}/{max_retries} in {delay:.1f}s")
                time.sleep(delay)
            else:
                delay = calculate_backoff(attempt)
                log_warning(f"URL error: {reason_str}, retry {attempt+1}/{max_retries} in {delay:.1f}s")
                time.sleep(delay)
                
        except socket.timeout:
            delay = calculate_backoff(attempt)
            log_warning(f"Socket timeout, retry {attempt+1}/{max_retries} in {delay:.1f}s")
            time.sleep(delay)
            
        except Exception as e:
            log_error(f"Unexpected Telegram error: {e}")
            if attempt < max_retries - 1:
                time.sleep(5)
    
    log_error(f"Telegram send failed after {max_retries} attempts")
    return False

def format_bytes(bytes_val):
    """Format bytes to human readable string."""
    if not bytes_val:
        return "0 B"
    
    try:
        bytes_val = int(bytes_val)
    except (ValueError, TypeError):
        return "0 B"
    
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(bytes_val) < 1024.0:
            return f"{bytes_val:.2f} {unit}"
        bytes_val /= 1024.0
    return f"{bytes_val:.2f} PB"

def format_duration(seconds):
    """Format seconds to human readable duration."""
    if not seconds:
        return "-"

    try:
        seconds = int(seconds)
    except (ValueError, TypeError):
        return "-"

    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        m = seconds // 60
        s = seconds % 60
        return f"{m}m {s}s"
    else:
        h = seconds // 3600
        m = (seconds % 3600) // 60
        if h < 24:
            return f"{h}h {m}m"
        else:
            d = h // 24
            h = h % 24
            return f"{d}d {h}h"

def check_ip_prefix(ip, prefixes):
    """
    Check if IP matches any of the target prefixes.
    Supports:
    - Simple prefix matching: '10.1' matches '10.1.x.x'
    - Range matching: '10.1-10.19' matches IPs from 10.1.0.0 to 10.19.255.255
    """
    import ipaddress
    
    if not ip:
        return False
    
    try:
        current_ip_int = int(ipaddress.IPv4Address(ip))
    except (ValueError, ipaddress.AddressValueError):
        return False

    for prefix in prefixes:
        prefix = prefix.strip()
        if not prefix:
            continue
        
        if '-' in prefix:
            try:
                start_str, end_str = prefix.split('-', 1)
                
                def to_int(ip_str, fill_val):
                    parts = ip_str.strip().split('.')
                    for p in parts:
                        if not p.isdigit():
                            raise ValueError(f"Invalid IP part: {p}")
                    while len(parts) < 4:
                        parts.append(str(fill_val))
                    return int(ipaddress.IPv4Address(".".join(parts)))
                
                s_int = to_int(start_str, 0)
                e_int = to_int(end_str, 255)
                if s_int <= current_ip_int <= e_int:
                    return True
            except Exception:
                continue
        else:
            if ip.startswith(prefix):
                return True
    
    return False
