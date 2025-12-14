#!/usr/bin/env python3
"""
Reconnect dialup script for Huawei modems.
"""

from argparse import ArgumentParser
import time
import sys
from huawei_lte_api.Client import Client
from huawei_lte_api.AuthorizedConnection import AuthorizedConnection
from huawei_lte_api.enums.client import ResponseEnum
import requests
import urllib3
from urllib.parse import urlparse

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

import ipaddress

# ... (existing imports)

def check_prefix(ip, prefixes):
    if not ip: return False
    try:
        current_ip_int = int(ipaddress.IPv4Address(ip))
    except ValueError: return False

    for prefix in prefixes:
        prefix = prefix.strip()
        if not prefix: continue
        if '-' in prefix:
            try:
                start_str, end_str = prefix.split('-')
                def to_int(ip_str, fill_val):
                    parts = ip_str.strip().split('.')
                    for p in parts:
                        if not p.isdigit(): raise ValueError
                    while len(parts) < 4: parts.append(str(fill_val))
                    return int(ipaddress.IPv4Address(".".join(parts)))
                s_int = to_int(start_str, 0)
                e_int = to_int(end_str, 255)
                if s_int <= current_ip_int <= e_int: return True
            except: continue
        else:
            if ip.startswith(prefix): return True
    return False

def reconnect(url, username, password, method="data", prefixes=[]):
    try:
        # ... (HTTPS check)
        if url.startswith('http://') and '192.168.7.1' in url:
            url = url.replace('http://', 'https://')
            print(f"Converted to HTTPS: {url}", file=sys.stderr)
        
        # Create a custom session with SSL verification disabled
        session = requests.Session()
        session.verify = False
        
        with AuthorizedConnection(url, username=username, password=password, requests_session=session) as connection:
            client = Client(connection)
            
            if method == "reboot":
                # ... (reboot logic)
                print("Rebooting modem...")
                client.device.reboot()
                print("Reboot command sent. Please wait 1-2 minutes for the device to restart.")
                return

            if method == "netmode":
                # ... (netmode logic)
                print("Switching network mode to 3G (WCDMA)...")
                try:
                    client.net.set_net_mode('7FFFFFFFFFFFFFFF', '3FFFFFFF', '02')
                    print("Switched to 3G. Waiting 10 seconds...")
                    time.sleep(10)
                    print("Switching network mode back to 4G (LTE)...")
                    # 03 = 4G only (LTE)
                    client.net.set_net_mode('7FFFFFFFFFFFFFFF', '3FFFFFFF', '03')
                    print("Switched to 4G. Reconnection successful.")
                except Exception as e:
                    print(f"Netmode switch failed: {e}. Trying to revert to Auto...")
                    try:
                        # 00 = Auto mode
                        client.net.set_net_mode('7FFFFFFFFFFFFFFF', '3FFFFFFF', '00')
                    except: pass
                return

            if method == "profile":
                print("Switching APN Profile...")
                try:
                    # Get list of profiles
                    profiles = client.dial_up.profiles()
                    if not profiles or 'Profiles' not in profiles or not profiles['Profiles']:
                        print("No profiles found.")
                        return

                    profile_list = profiles['Profiles']['Profile']
                    if isinstance(profile_list, dict): # Single profile case
                        profile_list = [profile_list]
                    
                    if len(profile_list) < 2:
                        print("Need at least 2 profiles to switch.")
                        return

                    # Find current default
                    current_index = next((p['Index'] for p in profile_list if p.get('Default') == '1'), None)
                    if not current_index:
                        current_index = profile_list[0]['Index'] # Fallback

                    # Find next profile
                    next_profile = next((p for p in profile_list if p['Index'] != current_index), None)
                    if not next_profile:
                        print("Could not find another profile.")
                        return

                    print(f"Switching from Profile {current_index} to {next_profile['Index']} ({next_profile.get('Name', 'Unknown')})...")
                    client.dial_up.set_default_profile(next_profile['Index'])
                    
                    print("Waiting 10 seconds for connection...")
                    time.sleep(10)
                    
                    # Check IP
                    try:
                        info = client.device.information()
                        new_ip = info.get('WanIPAddress')
                        print(f"New IP: {new_ip}")
                        
                        if new_ip and prefixes and check_prefix(new_ip, prefixes):
                            print("✅ Target IP found! Keeping this profile.")
                            return
                        else:
                            print("❌ IP does not match target or no IP obtained.")
                    except Exception as e:
                        print(f"Error checking IP: {e}")

                    print(f"Reverting back to Profile {current_index}...")
                    client.dial_up.set_default_profile(current_index)
                    print("Profile reverted.")
                    
                except Exception as e:
                    print(f"Profile switch failed: {e}")
                return

            # Default: data toggle
            print("Disabling mobile data switch...")
            if client.dial_up.set_mobile_dataswitch(0) == ResponseEnum.OK.value:
                print("Mobile data disabled")
            else:
                print("Error disabling mobile data")
            
            time.sleep(10) # Wait longer to ensure session termination
            
            print("Enabling mobile data switch...")
            if client.dial_up.set_mobile_dataswitch(1) == ResponseEnum.OK.value:
                print("Mobile data enabled - reconnection successful")
            else:
                print("Error enabling mobile data")
    except Exception as e:
        print(f"Reconnect error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument("url", type=str)
    parser.add_argument("--username", type=str, default="admin")
    parser.add_argument("--password", type=str, default="admin")
    parser.add_argument("--method", type=str, default="data", choices=["data", "netmode", "reboot", "profile"], help="Reconnection method: data (default), netmode, reboot, profile")
    parser.add_argument("--prefixes", type=str, default="", help="Target IP prefixes (space separated)")
    args = parser.parse_args()

    # Parse URL to extract username and password if provided
    parsed_url = urlparse(args.url)
    
    # Extract credentials from URL if present
    if parsed_url.username:
        username = parsed_url.username
        password = parsed_url.password if parsed_url.password else args.password
        # Reconstruct URL without credentials
        clean_url = f"{parsed_url.scheme}://{parsed_url.hostname}"
        if parsed_url.port:
            clean_url += f":{parsed_url.port}"
        clean_url += parsed_url.path if parsed_url.path else "/"
    else:
        username = args.username
        password = args.password
        clean_url = args.url

    prefixes_list = args.prefixes.split(" ") if args.prefixes else []
    # Clean up prefixes (strip quotes and whitespace)
    prefixes_list = [p.strip().strip("'").strip('"') for p in prefixes_list if p.strip()]
    reconnect(clean_url, username, password, args.method, prefixes_list)
