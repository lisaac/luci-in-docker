-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Licensed to the public under the Apache License 2.0.

local os    = require "os"
local util  = require "luci.util"
local table = require "table"
local xuci   = require "uci"

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

local ERRSTR = {
	"Invalid command",
	"Invalid argument",
	"Method not found",
	"Entry not found",
	"No data",
	"Permission denied",
	"Timeout",
	"Not supported",
	"Unknown error",
	"Connection failed"
}

local session_id = nil

local function call(cmd, arg1, arg2, arg3, arg4)
	local xcursor = xuci.cursor()
	if not arg1 then
		return xcursor[cmd]()
	elseif not arg2 then
		return xcursor[cmd](arg1)
	elseif not arg3 then
		return xcursor[cmd](arg1, arg2)
	elseif not arg4 then
		return xcursor[cmd](arg1, arg2, arg3)
	else
		return xcursor[cmd](arg1, arg2, arg3, arg4)
	end
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
	return call("get_confdir")
end

function get_savedir(self)
	return call("get_savedir")
end

function get_session_id(self)
	return session_id
end

function set_session_id(self, id)
	session_id = id
	return true
end

function set_confdir(self, directory)
	return call("set_confdir", directory)
end

function set_savedir(self, directory)
	return call("set_savedir", directory)
end

function load(self, config)
	return call("load", config)
end

function save(self, config)
	return call("save", config)
end

function unload(self, config)
	return call("unload", config)
end

function changes(self, config)
	return call("changes", config)
end

function revert(self, config)
	return call("revert", config)
end

function commit(self, config)
	return call("commit", config)
end

function get_all(self, config, section)
	return call("get_all", config, section)
end

function add(self, config, stype)
	return call("add", config, stype)
end

function delete(self, config, section, option)
	return call("delete",  config, section, option)
end

local function _get(self, operation, config, section, option)
	if section == nil then
		return nil
	elseif type(option) == "string" and option:byte(1) ~= 46 then
		return call(operation, config, section, option)
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

function get_bool(self, ...)
	local val = self:get(...)
	return (val == "1" or val == "true" or val == "yes" or val == "on")
end

function foreach(self, config, stype, callback)
	return call("foreach",  config, stype, callback)
end

function get_first(self, config, stype, option, default)
	local rv = default

	local _, err = self:foreach(config, stype, function(s)
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

	return rv, err
end

function get_list(self, config, section, option)
	if config and section and option then
		local val, err = self:get(config, section, option)
		return (type(val) == "table" and val or { val }), err
	end
	return { }
end

function section(self, config, stype, name, values)
	local stat = true
	if name then
		stat = call("set", config, name, stype)
	else
		name = self:add(config, stype)
		stat = name and true
	end

	if stat and values then
		stat = self:tset(config, name, values)
	end

	return stat and name
end

function set(self, config, section, option, values)
	if not values then
		local sname, err = self:section(config, option, section)
		return (not not sname), err
	else
		return call("set", config, section, option, values )
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

function tset(self, config, section, v)
	local stat = true
	for k, v in pairs(v) do
		if k:sub(1, 1) ~= "." then
			stat = stat and call("set", config, section, k, v)
		end
	end
	return stat
end

function reorder(self, config, section, index)
	local stat = true
	if type(section) == "string" and type(index) == "number" then
		return call("reorder", config, section, index)
	elseif type(section) == "table" then
		local sid, idx
		for idx , sid in pairs(section) do
			stat = stat and call("reorder", config, sid, idx)
		end
	else
		return false, "Invalid argument"
	end
	return stat
end

function delete_all(self, config, stype, comparator)
	local del = {}

	if type(comparator) == "table" then
		local tbl = comparator
		comparator = function(section)
			for k, v in pairs(tbl) do
				if section[k] ~= v then
					return false
				end
			end
			return true
		end
	end

	local function helper (section)

		if not comparator or comparator(section) then
			del[#del+1] = section[".name"]
		end
	end

	self:foreach(config, stype, helper)

	for i, j in ipairs(del) do
		self:delete(config, j)
	end
end

-- Return a list of initscripts affected by configuration changes.
local function _affected(self, configlist)
	configlist = type(configlist) == "table" and configlist or {configlist}

	local c = xuci.cursor()
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

-- Applies UCI configuration changes
-- @param configlist		List of UCI configurations
-- @param command			Don't apply only return the command
local function _apply(self, configlist, command)
	local SYSROOT = os.getenv("LUCI_SYSROOT")
	configlist = _affected(configlist)
	if command then
		return { SYSROOT .. "/sbin/luci-reload", unpack(configlist) }
	else
		os.execute( SYSROOT .. "/sbin/luci-reload %s >/dev/null 2>&1"
			% table.concat(configlist, " "))
			return 0
	end
end

function apply(self, rollback)
	local rv, err
	local configlist = {}
	rv, err = self:changes()

	if not err then
		if type(rv) == "table" then
			local k
			for k in pairs(rv) do
				rv, err = call("commit", k)
				configlist[#configlist+1] = k
				if err then break	end
			end
		end
	end

	if not err then
		if #configlist > 0 then
			err = _apply(configlist)
		end
		if err == 0 then
			err = "No data"
		else
			err = "Apply command failed"
		end
	end

	return (err == nil), err
end

function confirm(self, token)
	return true
end

function rollback(self)
	return true
end

function rollback_pending(self)
	return true
end