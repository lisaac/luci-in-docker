-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local os    = require "os"
local util  = require "luci.util"
-- local table = require "table"
local xuci   = require "uci"
local SYSROOT = os.getenv("LUCI_SYSROOT")

local setmetatable, rawget, rawset = setmetatable, rawget, rawset
local require, getmetatable, assert = require, getmetatable, assert
local error, pairs, ipairs, select = error, pairs, ipairs, select
local type, tostring, tonumber, unpack = type, tostring, tonumber, unpack

-- The typical workflow for UCI is:  Get a cursor instance from the
-- cursor factory, modify data (via Cursor.add, Cursor.delete, etc.),
-- save the changes to the staging area via Cursor.save and finally
-- Cursor.commit the data to the actual config files.
-- LuCI then needs to Cursor.apply the changes so daemons etc. are
-- reloaded.
module "luci.model.uci"
local config_dir="/etc/config"
local save_dir = "/tmp/.uci"
local xcursor = xuci.cursor(config_dir, save_dir)

local session_id = nil

-- Return a list of initscripts affected by configuration changes.
function _affected(self, configlist)
	configlist = type(configlist) == "table" and configlist or {configlist}

	local c = uci.cursor()
	c:load("ucitrack")

	-- Resolve dependencies
	local reloadlist = {}

	local function _resolve_deps(name)
		local reload = {name}
		local deps = {}

		c:foreach("ucitrack", name,
			function(section)
				if section.affects then
					for i, aff in ipairs(section.affects) do
						deps[#deps+1] = aff
					end
				end
			end)

		for i, dep in ipairs(deps) do
			for j, add in ipairs(_resolve_deps(dep)) do
				reload[#reload+1] = add
			end
		end

		return reload
	end

	-- Collect initscripts
	for j, config in ipairs(configlist) do
		for i, e in ipairs(_resolve_deps(config)) do
			if not util.contains(reloadlist, e) then
				reloadlist[#reloadlist+1] = e
			end
		end
	end

	return reloadlist
end

function cursor()
	return _M
end

function cursor_state()
	return _M
end

function substate(self)
	return self
end


function get_confdir(self)
	return config_dir
end

function get_savedir(self)
	return save_dir
end

function get_session_id(self)
	return session_id
end

function set_confdir(self, directory)
	return false
end

function set_savedir(self, directory)
	return false
end

function set_session_id(self, id)
	session_id = id
	return true
end


function load(self, config)
	return true
end

function save(self, config)
	return true
end

function unload(self, config)
	return true
end


function changes(self, config)
	if config then
		return xcursor:changes(config)
	else
		return xcursor:changes()
	end
end

function revert(self, config)
	return xcursor:revert(config)
end

function commit(self, config)
	return xcursor:commit(config)
end

function _apply(self, configlist, command)
	configlist = self:_affected(configlist)
	if command then
		return { SYSROOT .. "/sbin/luci-reload", unpack(configlist) }
	else
		return os.execute( SYSROOT .. "/sbin/luci-reload %s >/dev/null 2>&1"
			% table.concat(configlist, " "))
	end
end

function apply(self, rollback)
	local _, err

	if rollback then
		local sys = require "luci.sys"
		local conf = require "luci.config"
		local timeout = tonumber(conf and conf.apply and conf.apply.rollback or 30) or 0

		_, err = call("apply", {
			timeout = (timeout > 30) and timeout or 30,
			rollback = true
		})

		if not err then
			local now = os.time()
			local token = sys.uniqueid(16)

			util.ubus("session", "set", {
				ubus_rpc_session = "00000000000000000000000000000000",
				values = {
					rollback = {
						token   = token,
						session = session_id,
						timeout = now + timeout
					}
				}
			})

			return token
		end
	else
		_, err = self:changes()
		local configlist = {}
		if not err then
			if type(_) == "table" then
				local k, v
				for k, v in pairs(_) do
					_, err = self:commit(k)
					configlist[#configlist+1]=k
					if err then
						break
					end
				end
			end
		end

		if not err then
			_, err = self:_apply(configlist)
		end
	end

	return (err == nil), err
end

function confirm(self, token)
	local is_pending, time_remaining, rollback_sid, rollback_token = self:rollback_pending()

	if is_pending then
		if token ~= rollback_token then
			return false, "Permission denied"
		end

		local _, err = util.ubus("uci", "confirm", {
			ubus_rpc_session = rollback_sid
		})

		if not err then
			util.ubus("session", "set", {
				ubus_rpc_session = "00000000000000000000000000000000",
				values = { rollback = {} }
			})
		end

		return (err == nil), err
	end

	return false, "No data"
end

function rollback(self)
	local is_pending, time_remaining, rollback_sid = self:rollback_pending()

	if is_pending then
		local _, err = util.ubus("uci", "rollback", {
			ubus_rpc_session = rollback_sid
		})

		if not err then
			util.ubus("session", "set", {
				ubus_rpc_session = "00000000000000000000000000000000",
				values = { rollback = {} }
			})
		end

end

	return false, "No data"
end

function rollback_pending(self)
	local rv, err = util.ubus("session", "get", {
		ubus_rpc_session = "00000000000000000000000000000000",
		keys = { "rollback" }
	})

	local now = os.time()

	if type(rv) == "table" and
	   type(rv.values) == "table" and
	   type(rv.values.rollback) == "table" and
	   type(rv.values.rollback.token) == "string" and
	   type(rv.values.rollback.session) == "string" and
	   type(rv.values.rollback.timeout) == "number" and
	   rv.values.rollback.timeout > now
	then
		return true,
			rv.values.rollback.timeout - now,
			rv.values.rollback.session,
			rv.values.rollback.token
	end

	return false, err
end


function foreach(self, config, stype, callback)
	if type(callback) == "function" then
		return xcursor:foreach(config, stype, callback)
	else
		return false, "Invalid argument"
	end
end

local function _get(self, operation, config, section, option)
	if section == nil then
		return nil
	elseif type(option) == "string" and option:byte(1) ~= 46 then
    return xcursor:get(config, section, option)
	elseif option == nil then
		local values = self:get_all(config, section)
		if values then
			return values[".type"], values[".name"]
		else
			return nil
		end
	else
		return false, "Invalid argument"
	end
end

function get(self, ...)
	return _get(self, "get", ...)
end

function get_state(self, ...)
	return _get(self, "state", ...)
end

function get_all(self, config, section)
	return xcursor:get_all(config, section)
end

function get_bool(self, ...)
	local val = self:get(...)
	return (val == "1" or val == "true" or val == "yes" or val == "on")
end

function get_first(self, config, stype, option, default)
	local rv = default

	self:foreach(config, stype, function(s)
		local val = not option and s[".name"] or s[option]

		if type(default) == "number" then
			val = tonumber(val)
		elseif type(default) == "boolean" then
			val = (val == "1" or val == "true" or
			       val == "yes" or val == "on")
		end

		if val ~= nil then
			rv = val
			return false
		end
	end)

	return rv
end

function get_list(self, config, section, option)
	if config and section and option then
		local val = self:get(config, section, option)
		return (type(val) == "table" and val or { val })
	end
	return { }
end

function section(self, config, stype, name, values)
	local rv, err, typed_name
  if name then
		rv,err = xcursor:set(config, name, type)
	else
    name,err = xcursor:add(config, type)
    rv = name and true
	end

	if name and values then
		rv,err = self:tset(config, name, values)
	end

	if rv then
		return name
	elseif err then
		return false, err
	else
		return nil
	end
end


function add(self, config, stype)
	return self:section(config, stype)
end

function set(self, config, section, option, ...)
	if select('#', ...) == 0 then
		local sname, err = self:section(config, option, section)
		return (not not sname), err
	else
    local rv, err = xcursor:set(config, section, option, select(1, ...))
		return rv, err
	end
end

function set_list(self, config, section, option, value)
	if section == nil or option == nil then
		return false
	elseif value == nil or (type(value) == "table" and #value == 0) then
		return self:delete(config, section, option)
	elseif type(value) == "table" then
		return self:set(config, section, option, value)
	else
		return self:set(config, section, option, { value })
	end
end

function tset(self, config, section, values)
	local rv = true, err
	for k, v in pairs(values) do
		if k:sub(1, 1) ~= "." then
      rv, err= rv and xcursor:set(config, section, k, v)
      if not rv then return rv, err end
		end
	end
	return rv
end

function reorder(self, config, section, index)
  if type(section) == "string" and type(index) == "number" then
    return xcursor:reorder(config, section, index)
	else
		return false, "Invalid argument"
	end
end

function delete(self, config, section, option)
	return xcursor:delete(config, section, option)
end

function delete_all(self, config, stype, comparator)
	local _, err
	if type(comparator) == "table" then
		_, err = call("delete", {
			config = config,
			type   = stype,
			match  = comparator
		})
	elseif type(comparator) == "function" then
		local rv = call("get", {
			config = config,
			type   = stype
		})

		if type(rv) == "table" and type(rv.values) == "table" then
			local sname, section
			for sname, section in pairs(rv.values) do
				if comparator(section) then
					_, err = call("delete", {
						config  = config,
						section = sname
					})
				end
			end
		end
	elseif comparator == nil then
		_, err = call("delete", {
			config  = config,
			type    = stype
		})
	else
		return false, "Invalid argument"
	end

	return (err == nil), err
end