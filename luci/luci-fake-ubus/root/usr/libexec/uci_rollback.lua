local uci = (require "luci.model.uci").cursor()
local fs = require "nixio.fs"
local util = require "luci.util"

local bak_configs = "/tmp/luci-config-bak"
local bak_changes = "/tmp/luci-uci-bak"
local rollback_confirm = "/tmp/luci-uci-confirm"
local token = arg[1]
local action = arg[2]

local function cleanup_baks(dir, token, clear)
  util.exec("rm -fr " .. dir .. "/" .. token)
  if not clear then
    util.exec("mkdir -p  " .. dir .. "/" .. token)
  end
end

local function restore_configs(token)
  if fs.access(bak_configs .. "/" .. token) then
	  util.exec("cp -Rf ".. bak_configs .. "/" .. token .. "/* " .. uci:get_confdir())
  end
end

local function restore_changes(token)
  if fs.access(bak_changes .. "/" .. token) then
	  util.exec("cp -Rf " .. bak_changes .. "/" .. token .. "/* /tmp/.uci")
  end
end

local function roll_back(token)
  if fs.access(bak_configs .. "/" .. token) then
    restore_configs(token)
    local config_list, d = {}, nil
    for d in fs.dir(bak_configs .. '/' .. token) do
      table.insert( config_list, d )
    end
    uci:_apply(config_list)
  end
  restore_changes(token)
  cleanup_baks(bak_configs, token, true)
  cleanup_baks(bak_changes, token, true)
  util.exec("rm " .. rollback_confirm .. '/' .. token)
end

if option == "rollback" then
  roll_back(token)
else
  local rollback_time = uci:get("luci", "apply", "rollback")
  util.exec("sleep " .. rollback_time)
  if not fs.access(rollback_confirm .. '/' .. token) then
    cleanup_baks(bak_configs, token)
    cleanup_baks(bak_changes, token)
  else
    roll_back(token)
  end
end