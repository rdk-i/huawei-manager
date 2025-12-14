module("luci.controller.huawei-manager", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/huawei-manager") then
        return
    end

    -- Main Entry - Redirect to Dashboard
    entry({"admin", "modem", "huawei-manager"}, alias("admin", "modem", "huawei-manager", "dashboard"), _("Huawei Manager"), 90).dependent = true

    -- 1. Dashboard Page
    entry({"admin", "modem", "huawei-manager", "dashboard"}, template("huawei-manager/page_dashboard"), nil).leaf = true

    -- 2. IP Agent Page
    entry({"admin", "modem", "huawei-manager", "ipagent"}, template("huawei-manager/page_ipagent"), nil).leaf = true

    -- 3. Network Page (Band/APN/USSD)
    entry({"admin", "modem", "huawei-manager", "network"}, template("huawei-manager/page_network"), nil).leaf = true

    -- 4. SMS Page
    entry({"admin", "modem", "huawei-manager", "sms"}, template("huawei-manager/page_sms"), nil).leaf = true

    -- 5. Configuration Page - CBI Model with navigation template
    entry({"admin", "modem", "huawei-manager", "config"}, cbi("huawei-manager", {hideapplybtn=false, hidesavebtn=false, hideresetbtn=false}), nil).leaf = true

    -- 6. Logs Page
    entry({"admin", "modem", "huawei-manager", "logs"}, template("huawei-manager/page_logs"), nil).leaf = true

    -- 7. About Page
    entry({"admin", "modem", "huawei-manager", "about"}, template("huawei-manager/page_about"), nil).leaf = true

    -- API Endpoints
    entry({"admin", "modem", "huawei-manager", "api", "status"}, call("action_status")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "metrics"}, call("action_metrics")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "logs"}, call("action_logs")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "clear_logs"}, call("action_clear_logs")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "reconnect"}, call("action_reconnect")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "devices"}, call("action_devices")).leaf = true
    
    -- Modem API endpoints
    entry({"admin", "modem", "huawei-manager", "api", "modem", "info"}, call("action_modem_info")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "reboot"}, call("action_modem_reboot")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "toggle_data"}, call("action_modem_toggle_data")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "bands"}, call("action_modem_bands")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "bands_list"}, call("action_modem_bands_list")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "apn"}, call("action_modem_apn")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "apn_create"}, call("action_modem_apn_create")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "apn_delete"}, call("action_modem_apn_delete")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "apn_default"}, call("action_modem_apn_default")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "ussd"}, call("action_modem_ussd")).leaf = true
    
    -- SMS API endpoints
    entry({"admin", "modem", "huawei-manager", "api", "modem", "sms_list"}, call("action_modem_sms_list")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "sms_send"}, call("action_modem_sms_send")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "sms_delete"}, call("action_modem_sms_delete")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "sms_read"}, call("action_modem_sms_read")).leaf = true
    entry({"admin", "modem", "huawei-manager", "api", "modem", "sms_count"}, call("action_modem_sms_count")).leaf = true
end

-- ===== Helper Functions =====

local function escape_shell(s)
    if s == nil then return "''" end
    s = string.gsub(tostring(s), "'", "'\\''")
    return "'" .. s .. "'"
end

local function get_device_config(section_id)
    local uci = require "luci.model.uci".cursor()
    return uci:get_all("huawei-manager", section_id)
end

local function exec_modem_api(section_id, action, data_json)
    local config = get_device_config(section_id)
    if not config then
        return {success = false, error = "Device not found"}
    end
    
    local url = config.modem_url or "http://192.168.8.1/"
    local username = config.modem_username or "admin"
    local password = config.modem_password or "admin"
    
    data_json = data_json or "{}"
    
    local cmd = string.format(
        "python3 /usr/bin/huawei-manager/modem_api.py %s --username %s --password %s --action %s --data %s 2>&1",
        escape_shell(url),
        escape_shell(username),
        escape_shell(password),
        escape_shell(action),
        escape_shell(data_json)
    )
    
    local output = luci.util.exec(cmd)
    
    -- Parse JSON output
    local json = require "luci.jsonc"
    local result = json.parse(output)
    
    if result then
        return result
    else
        return {success = false, error = "Failed to parse response", raw = output}
    end
end

-- ===== Status API =====

function action_status()
    local file = io.open("/tmp/huawei-manager.status", "r")
    local status = "{}"
    if file then
        status = file:read("*all")
        file:close()
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write(status)
end

function action_metrics()
    local file = io.open("/tmp/huawei-manager.metrics", "r")
    local metrics = "{}"
    if file then
        metrics = file:read("*all")
        file:close()
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write(metrics)
end

function action_logs()
    local logs = {}
    local file = io.open("/var/log/huawei-manager.log", "r")
    
    if not file then
        file = io.open("/tmp/huawei-manager.log", "r")
    end
    
    if file then
        local lines = {}
        for line in file:lines() do
            table.insert(lines, line)
            if #lines > 100 then
                table.remove(lines, 1)
            end
        end
        file:close()
        logs = lines
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({logs = logs})
end

function action_clear_logs()
    os.execute("echo '' > /var/log/huawei-manager.log 2>/dev/null")
    os.execute("echo '' > /tmp/huawei-manager.log 2>/dev/null")
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({success = true})
end

function action_devices()
    local uci = require "luci.model.uci".cursor()
    local devices = {}
    
    uci:foreach("huawei-manager", "device", function(s)
        table.insert(devices, {
            id = s[".name"],
            name = s.name or s[".name"],
            enabled = s.enabled == "1",
            url = s.modem_url or ""
        })
    end)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({devices = devices})
end

function action_reconnect()
    local section_id = luci.http.formvalue("section_id")
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing section_id"})
        return
    end
    
    if not section_id:match("^[%w_@%[%]]+$") then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Invalid section_id format"})
        return
    end

    local config = get_device_config(section_id)
    if not config then
        luci.http.status(404, "Not Found")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Section not found"})
        return
    end

    local url = config.modem_url or "http://192.168.8.1/"
    local username = config.modem_username or "admin"
    local password = config.modem_password or "admin"
    local method = config.reconnect_method or "data"
    local prefixes = config.target_prefixes or ""
    
    local valid_methods = {data = true, netmode = true, reboot = true, profile = true}
    if not valid_methods[method] then
        method = "data"
    end
    
    if type(prefixes) == "table" then
        prefixes = table.concat(prefixes, " ")
    end
    
    local cmd = string.format(
        "python3 /usr/bin/huawei-manager/reconnect_dialup.py %s --username %s --password %s --method %s --prefixes %s 2>&1",
        escape_shell(url), escape_shell(username), escape_shell(password), escape_shell(method), escape_shell(prefixes)
    )
    
    local output = luci.util.exec(cmd)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({
        success = true,
        output = output,
        method = method
    })
end

-- ===== Modem API =====

function action_modem_info()
    local section_id = luci.http.formvalue("device")
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end
    
    -- Optimization: Try to read from daemon cache first
    local cache_file = "/tmp/huawei-manager-status_" .. section_id .. ".json"
    local stat = nixio.fs.stat(cache_file)
    
    -- If cache exists and is fresh (< 20 seconds)
    if stat and (os.time() - stat.mtime < 20) then
        local file = io.open(cache_file, "r")
        if file then
            local cached_json = file:read("*all")
            file:close()
            if cached_json and #cached_json > 0 then
                luci.http.prepare_content("application/json")
                luci.http.write(cached_json)
                return
            end
        end
    end
    
    -- Fallback/Slow Path: Execute python script
    local result = exec_modem_api(section_id, "info", nil)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end


function action_modem_reboot()
    local section_id = luci.http.formvalue("device")
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end
    
    local result = exec_modem_api(section_id, "reboot", nil)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_toggle_data()
    local section_id = luci.http.formvalue("device")
    local enable = luci.http.formvalue("enable") == "true"
    
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end
    
    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "toggle_data", json.stringify({enable = enable}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_bands()
    local section_id = luci.http.formvalue("device")
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end
    
    local network_mode = luci.http.formvalue("network_mode")
    local network_band = luci.http.formvalue("network_band")
    local lte_band = luci.http.formvalue("lte_band")
    
    local result
    if network_mode or network_band or lte_band then
        local json = require "luci.jsonc"
        result = exec_modem_api(section_id, "bands", json.stringify({
            network_mode = network_mode,
            network_band = network_band,
            lte_band = lte_band
        }))
    else
        result = exec_modem_api(section_id, "bands", nil)
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_bands_list()
    local section_id = luci.http.formvalue("device")
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end
    
    local result = exec_modem_api(section_id, "bands_list", nil)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_apn()
    local section_id = luci.http.formvalue("device")
    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end
    
    local result = exec_modem_api(section_id, "apn_list", nil)
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_apn_create()
    local section_id = luci.http.formvalue("device")
    local name = luci.http.formvalue("name")
    local apn = luci.http.formvalue("apn")
    local username = luci.http.formvalue("username") or ""
    local password = luci.http.formvalue("password") or ""
    local auth_type = luci.http.formvalue("auth_type") or "0"
    
    if not section_id or not name or not apn then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end
    
    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "apn_create", json.stringify({
        name = name,
        apn = apn,
        username = username,
        password = password,
        auth_type = auth_type
    }))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_apn_delete()
    local section_id = luci.http.formvalue("device")
    local profile_id = luci.http.formvalue("profile_id")
    
    if not section_id or not profile_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end
    
    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "apn_delete", json.stringify({profile_id = profile_id}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_apn_default()
    local section_id = luci.http.formvalue("device")
    local profile_id = luci.http.formvalue("profile_id")
    
    if not section_id or not profile_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end
    
    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "apn_default", json.stringify({profile_id = profile_id}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_ussd()
    local section_id = luci.http.formvalue("device")
    local code = luci.http.formvalue("code")

    if not section_id or not code then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end

    -- Validate USSD code format (security measure)
    if not code:match("^[%*#%d]+$") then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Invalid USSD code format. Only *, #, and digits allowed."})
        return
    end

    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "ussd", json.stringify({code = code}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

-- ===== SMS API Actions =====

function action_modem_sms_list()
    local section_id = luci.http.formvalue("device") or luci.http.formvalue("section_id")
    local page = luci.http.formvalue("page") or 1
    local count = luci.http.formvalue("count") or 20

    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end

    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "sms_list", json.stringify({page = tonumber(page), count = tonumber(count)}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_sms_send()
    local section_id = luci.http.formvalue("device") or luci.http.formvalue("section_id")
    local phone = luci.http.formvalue("phone")
    local message = luci.http.formvalue("message")

    if not section_id or not phone or not message then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end

    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "sms_send", json.stringify({phone = phone, message = message}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_sms_delete()
    local section_id = luci.http.formvalue("device") or luci.http.formvalue("section_id")
    local message_id = luci.http.formvalue("message_id")

    if not section_id or not message_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end

    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "sms_delete", json.stringify({message_id = message_id}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_sms_read()
    local section_id = luci.http.formvalue("device") or luci.http.formvalue("section_id")
    local message_id = luci.http.formvalue("message_id")

    if not section_id or not message_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing required parameters"})
        return
    end

    local json = require "luci.jsonc"
    local result = exec_modem_api(section_id, "sms_read", json.stringify({message_id = message_id}))
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_modem_sms_count()
    local section_id = luci.http.formvalue("device") or luci.http.formvalue("section_id")

    if not section_id then
        luci.http.status(400, "Bad Request")
        luci.http.prepare_content("application/json")
        luci.http.write_json({error = "Missing device parameter"})
        return
    end

    local result = exec_modem_api(section_id, "sms_count", "{}")
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end
