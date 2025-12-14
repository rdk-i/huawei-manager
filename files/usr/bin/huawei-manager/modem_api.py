#!/usr/bin/env python3
"""
Modem API CLI for Huawei Manager.
This script is called by the LuCI controller to interact with the modem.
Returns JSON responses.
"""
import sys
import json
from argparse import ArgumentParser
from huawei_lte_api.Client import Client
from huawei_lte_api.AuthorizedConnection import AuthorizedConnection
import requests
import urllib3
from urllib.parse import urlparse

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def json_response(success, data=None, error=None):
    """Output JSON response and exit."""
    result = {"success": success}
    if data is not None:
        result["data"] = data
    if error is not None:
        result["error"] = error
    print(json.dumps(result))
    sys.exit(0 if success else 1)

def get_client(url, username, password):
    """Create and return a modem client connection."""
    # HTTPS conversion for specific modems
    if url.startswith('http://') and '192.168.7.1' in url:
        url = url.replace('http://', 'https://')
    
    session = requests.Session()
    session.verify = False
    
    connection = AuthorizedConnection(url, username=username, password=password, requests_session=session)
    return Client(connection), connection

def action_info(client):
    """Get all modem information."""
    data = {}
    
    # Device info
    try:
        data['device'] = client.device.information()
    except Exception as e:
        data['device'] = None
    
    # Signal info
    try:
        data['signal'] = client.device.signal()
    except Exception as e:
        data['signal'] = None
    
    # Traffic statistics
    try:
        data['traffic'] = client.monitoring.traffic_statistics()
    except Exception as e:
        data['traffic'] = {}
    
    # Monitoring status
    try:
        data['status'] = client.monitoring.status()
    except Exception as e:
        data['status'] = None
    
    # Network mode
    try:
        data['net_mode'] = client.net.net_mode()
    except:
        data['net_mode'] = None
    
    # Current PLMN (operator)
    try:
        data['plmn'] = client.net.current_plmn()
    except:
        data['plmn'] = None
    
    # Month statistics
    try:
        data['month_stats'] = client.monitoring.month_statistics()
    except:
        data['month_stats'] = None
    
    # Dialup connection
    try:
        data['dialup'] = client.dial_up.connection()
    except:
        data['dialup'] = None
    
    return data

def action_reboot(client):
    """Reboot the modem."""
    client.device.reboot()
    return {"message": "Reboot command sent"}

def action_toggle_data(client, enable):
    """Toggle mobile data on/off."""
    from huawei_lte_api.enums.client import ResponseEnum
    result = client.dial_up.set_mobile_dataswitch(1 if enable else 0)
    return {"enabled": enable, "result": result == ResponseEnum.OK.value}

def action_bands(client, data=None):
    """Get or set network bands."""
    if data:
        # Set bands
        # CORRECT ORDER: lte_band, network_band, network_mode
        network_mode = data.get('network_mode', '00')
        network_band = data.get('network_band', '3FFFFFFF')
        lte_band = data.get('lte_band', '7FFFFFFFFFFFFFFF')
        
        client.net.set_net_mode(lte_band, network_band, network_mode)
        return {"message": "Bands updated"}
    else:
        # Get current bands
        return client.net.net_mode()

def action_bands_list(client):
    """Get available band list."""
    return client.net.net_mode_list()

def action_apn_list(client):
    """Get APN profiles list."""
    return client.dial_up.profiles()

def action_apn_create(client, data):
    """Create a new APN profile."""
    name = data.get('name')
    apn = data.get('apn')
    username = data.get('username', '')
    password = data.get('password', '')
    auth_type = data.get('auth_type', '0')
    
    if not name or not apn:
        return {"error": "Name and APN are required"}
    
    client.dial_up.create_profile(
        name=name,
        apn=apn,
        username=username,
        password=password,
        auth_type=auth_type
    )
    return {"message": "APN created"}

def action_apn_delete(client, data):
    """Delete an APN profile."""
    profile_id = data.get('profile_id')
    if not profile_id:
        return {"error": "Profile ID required"}
    
    client.dial_up.delete_profile(profile_id)
    return {"message": "APN deleted"}

def action_apn_default(client, data):
    """Set default APN profile."""
    profile_id = data.get('profile_id')
    if not profile_id:
        return {"error": "Profile ID required"}
    
    client.dial_up.set_default_profile(profile_id)
    return {"message": "Default APN set"}

# ===== SMS Functions =====

def action_sms_list(client, data=None):
    """Get SMS inbox list."""
    from huawei_lte_api.enums.sms import BoxTypeEnum, SortTypeEnum
    page = data.get('page', 1) if data else 1
    count = data.get('count', 20) if data else 20
    
    return client.sms.get_sms_list(
        page=page,
        box_type=BoxTypeEnum.LOCAL_INBOX,
        read_count=count,
        sort_type=SortTypeEnum.DATE,
        ascending=False,
        unread_preferred=False
    )

def action_sms_send(client, data):
    """Send SMS message."""
    phone = data.get('phone')
    message = data.get('message')
    
    if not phone or not message:
        return {"error": "Phone number and message are required"}
    
    result = client.sms.send_sms([phone], message)
    return {"message": "SMS sent", "result": str(result)}

def action_sms_delete(client, data):
    """Delete SMS message."""
    message_id = data.get('message_id')
    if not message_id:
        return {"error": "Message ID required"}
    
    client.sms.delete_sms(message_id)
    return {"message": "SMS deleted"}

def action_sms_read(client, data):
    """Mark SMS as read."""
    message_id = data.get('message_id')
    if not message_id:
        return {"error": "Message ID required"}
    
    client.sms.set_read(message_id)
    return {"message": "SMS marked as read"}

def action_sms_count(client):
    """Get SMS count info."""
    return client.sms.sms_count()

def main():
    parser = ArgumentParser(description="Modem API CLI")
    parser.add_argument("url", type=str, help="Modem URL")
    parser.add_argument("--username", type=str, default="admin")
    parser.add_argument("--password", type=str, default="admin")
    parser.add_argument("--action", type=str, required=True,
                        choices=["info", "reboot", "toggle_data", "bands", "bands_list",
                                 "apn_list", "apn_create", "apn_delete", "apn_default",
                                 "sms_list", "sms_send", "sms_delete", "sms_read", "sms_count"])
    parser.add_argument("--data", type=str, default="{}", help="JSON data for action")
    args = parser.parse_args()
    
    # Parse URL for credentials
    parsed_url = urlparse(args.url)
    if parsed_url.username:
        username = parsed_url.username
        password = parsed_url.password or args.password
        clean_url = f"{parsed_url.scheme}://{parsed_url.hostname}"
        if parsed_url.port:
            clean_url += f":{parsed_url.port}"
        clean_url += parsed_url.path or "/"
    else:
        username = args.username
        password = args.password
        clean_url = args.url
    
    # Parse data
    try:
        data = json.loads(args.data) if args.data else {}
    except json.JSONDecodeError:
        json_response(False, error="Invalid JSON data")
        return
    
    # Connect and execute action
    try:
        client, connection = get_client(clean_url, username, password)
        
        try:
            if args.action == "info":
                result = action_info(client)
            elif args.action == "reboot":
                result = action_reboot(client)
            elif args.action == "toggle_data":
                enable = data.get('enable', True)
                result = action_toggle_data(client, enable)
            elif args.action == "bands":
                result = action_bands(client, data if data else None)
            elif args.action == "bands_list":
                result = action_bands_list(client)
            elif args.action == "apn_list":
                result = action_apn_list(client)
            elif args.action == "apn_create":
                result = action_apn_create(client, data)
            elif args.action == "apn_delete":
                result = action_apn_delete(client, data)
            elif args.action == "apn_default":
                result = action_apn_default(client, data)
            elif args.action == "sms_list":
                result = action_sms_list(client, data if data else None)
            elif args.action == "sms_send":
                result = action_sms_send(client, data)
            elif args.action == "sms_delete":
                result = action_sms_delete(client, data)
            elif args.action == "sms_read":
                result = action_sms_read(client, data)
            elif args.action == "sms_count":
                result = action_sms_count(client)
            else:
                json_response(False, error=f"Unknown action: {args.action}")
                return
            
            json_response(True, data=result)
            
        finally:
            try:
                connection.close()
            except:
                pass
                
    except Exception as e:
        json_response(False, error=str(e))

if __name__ == "__main__":
    main()
