#!/usr/bin/env python3
"""
Device info script for Huawei Manager.
Get WAN IP from Huawei modem using huawei-lte-api.
"""
import sys
from argparse import ArgumentParser
from huawei_lte_api.Client import Client
from huawei_lte_api.AuthorizedConnection import AuthorizedConnection
import requests
import urllib3
import traceback
from urllib.parse import urlparse

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def get_wan_ip(url, username=None, password=None):
    """
    Get WAN IP from Huawei modem using multiple fallback methods.
    Returns the IP address string or None if failed.
    """
    try:
        # Ensure HTTPS is used for some modems
        if url.startswith('http://') and '192.168.7.1' in url:
            url = url.replace('http://', 'https://')
            print(f"DEBUG: Converted to HTTPS: {url}", file=sys.stderr)
        
        print(f"DEBUG: Connecting to {url} with user {username}...", file=sys.stderr)
        connection_url = f"{url.rstrip('/')}"
        
        # Create a custom session with SSL verification disabled
        session = requests.Session()
        session.verify = False
        
        with AuthorizedConnection(connection_url, username=username, password=password, requests_session=session) as connection:
            print("DEBUG: AuthorizedConnection initialized. Creating Client...", file=sys.stderr)
            client = Client(connection)
            
            # Method 1: Try monitoring.status() - most reliable
            try:
                status = client.monitoring.status()
                wan_ip = None
                
                for field in ['WanIPAddress', 'WanIpAddress', 'wan_ip_address']:
                    if field in status and status[field]:
                        wan_ip = status[field]
                        break
                
                if wan_ip and wan_ip != '' and not wan_ip.startswith('0.0.0'):
                    return wan_ip
                    
            except Exception as e:
                print(f"Method 1 (monitoring.status) failed: {e}", file=sys.stderr)
            
            # Method 2: Try device.information() as fallback
            try:
                device_info = client.device.information()
                if 'WanIPAddress' in device_info and device_info['WanIPAddress']:
                    wan_ip = device_info['WanIPAddress']
                    if wan_ip and wan_ip != '' and not wan_ip.startswith('0.0.0'):
                        return wan_ip
            except Exception as e:
                print(f"Method 2 (device.information) failed: {e}", file=sys.stderr)
            
            # Method 3: Try dial_up.connection()
            try:
                dialup = client.dial_up.connection()
                if 'IPv4IPAddress' in dialup and dialup['IPv4IPAddress']:
                    wan_ip = dialup['IPv4IPAddress']
                    if wan_ip and wan_ip != '' and not wan_ip.startswith('0.0.0'):
                        return wan_ip
            except Exception as e:
                print(f"Method 3 (dial_up.connection) failed: {e}", file=sys.stderr)
            
            print(f"ERROR: All methods failed to retrieve WAN IP", file=sys.stderr)
            return None
            
    except Exception as e:
        print(f"Connection error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        return None

if __name__ == "__main__":
    parser = ArgumentParser(description="Get WAN IP from Huawei modem")
    parser.add_argument("url", type=str, help="Modem URL")
    parser.add_argument("--username", type=str, default="admin", help="Admin username")
    parser.add_argument("--password", type=str, default="admin", help="Admin password")
    args = parser.parse_args()

    # Parse URL to extract username and password if provided
    parsed_url = urlparse(args.url)
    
    if parsed_url.username:
        username = parsed_url.username
        password = parsed_url.password if parsed_url.password else args.password
        clean_url = f"{parsed_url.scheme}://{parsed_url.hostname}"
        if parsed_url.port:
            clean_url += f":{parsed_url.port}"
        clean_url += parsed_url.path if parsed_url.path else "/"
    else:
        username = args.username
        password = args.password
        clean_url = args.url

    ip = get_wan_ip(clean_url, username, password)
    if ip:
        print(ip)
        sys.exit(0)
    else:
        sys.exit(1)
