local m, s, o

-- Create map without title (title is in config_header template)
m = Map("huawei-manager")
m.pageaction = true

-- Render title and navigation at the top
m.on_init = function(self)
    luci.template.render("huawei-manager/config_header")
end

-- ============ Device Configuration ============
s = m:section(TypedSection, "device", "Modem Devices", 
    "Add your Huawei modems here. Each device will be monitored independently. Click 'Add' to create a new device.")
s.anonymous = true
s.addremove = true
s.novaluetext = "No modem devices configured yet. Click 'Add' button below to add one."

-- Create tabs
s:tab("general", "Settings")
s:tab("ipagent", "IP Agent")
s:tab("telegram", "Telegram")

-- ============ General Settings Tab ============

-- Name
o = s:taboption("general", Value, "name", "Device Name", "Friendly name for this device (e.g., 'Orbit Max', 'Modem Lantai 1')")
o.placeholder = "My Modem"
o.rmempty = false

-- Modem URL
o = s:taboption("general", Value, "modem_url", "Modem URL")
o.placeholder = "http://192.168.8.1/ or https://192.168.7.1/"
o.rmempty = true

-- Username
o = s:taboption("general", Value, "modem_username", "Modem Username")
o.placeholder = "admin"
o.rmempty = true

-- Password
o = s:taboption("general", Value, "modem_password", "Modem Password")
o.password = true
o.rmempty = true

-- ============ IP Agent Tab ============

-- Enable IP Agent
o = s:taboption("ipagent", Flag, "ipagent_enabled", "Enable IP Agent", "Enable automatic IP monitoring and reconnection for this device")
o.default = "0"
o.rmempty = false

-- Target IP Prefixes
o = s:taboption("ipagent", DynamicList, "target_prefixes", "Target IP Prefixes", "Enter IP prefixes (e.g., 10.1) or ranges (e.g., 10.1-10.19)")
o.placeholder = "10.0-10.255"
o.rmempty = true


-- Check Interval
o = s:taboption("ipagent", Value, "check_interval", "Check Interval (seconds)")
o.datatype = "uinteger"
o.default = "10"
o.placeholder = "10"
o.rmempty = true


-- Reconnect Method
o = s:taboption("ipagent", ListValue, "reconnect_method", "Reconnection Method", "Try 'Network Mode Switch' if Data Toggle fails to change IP")
o:value("data", "Mobile Data Toggle (Faster)")
o:value("netmode", "Network Mode Switch (4G -> 3G -> 4G)")
o:value("profile", "Profile Switch (APN Toggle)")
o.default = "data"
o.rmempty = true


-- ============ Telegram Notifications Tab ============

-- Enable Telegram
o = s:taboption("telegram", Flag, "telegram_enabled", "Enable Telegram Notifications")
o.default = "0"
o.rmempty = false

-- Bot Token
o = s:taboption("telegram", Value, "telegram_bot_token", "Bot Token", "Get from <a href='https://t.me/BotFather' target='_blank' style='color:#4CAF50;'>@BotFather</a>")
o.placeholder = "123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
o.password = true


-- Chat ID
o = s:taboption("telegram", Value, "telegram_chat_id", "Chat ID", "Get from <a href='https://t.me/userinfobot' target='_blank' style='color:#4CAF50;'>@userinfobot</a>")
o.placeholder = "123456789"


-- Notify on Success
o = s:taboption("telegram", Flag, "telegram_notify_success", "Notify on Target IP Found")
o.default = "1"


-- Notify on Reconnect
o = s:taboption("telegram", Flag, "telegram_notify_reconnect", "Notify on Reconnect")
o.default = "1"


-- Notify on Error
o = s:taboption("telegram", Flag, "telegram_notify_error", "Notify on Errors")
o.default = "0"

function m.on_after_commit(map)
    luci.sys.call("/etc/init.d/huawei-manager restart >/dev/null 2>&1")
end

return m
