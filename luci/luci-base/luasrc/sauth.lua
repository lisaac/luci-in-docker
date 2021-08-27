--[[
LuCI - Lua Configuration Interface
Copyright 2021 lisaac <https://github.com/lisaac/luci-in-docker>
Session authentication(c) 2008 Steven Barth <steven@midlink.org>
]]--

--- LuCI session library.
module("luci.sauth", package.seeall)
require("luci.util")
require("luci.sys")
require("luci.config")
local nixio = require "nixio", require "nixio.util"
local fs = require "nixio.fs"
local json = require "luci.jsonc"

luci.config.sauth = luci.config.sauth or {}
sessionpath = luci.config.sauth.sessionpath
sessiontime = tonumber(luci.config.sauth.sessiontime) or 15 * 60

--- Prepare session storage by creating the session directory.
function prepare()
	fs.mkdir(sessionpath, 700)
	if not sane() then
		error("Security Exception: Session path is not sane!")
	end
end

local function _read(id)
	local blob = fs.readfile(sessionpath .. "/" .. id)
	return blob
end

local function _write(id, data)
	local f = nixio.open(sessionpath .. "/" .. id, "w", 600)
	f:writeall(data)
	f:close()
end

local function _checkid(id)
	return not (not (id and #id == 32 and id:match("^[a-fA-F0-9]+$")))
end

--- Write session data to a session file.
-- @param id	Session identifier
-- @param data	Session data table
function write(id, data)
	if not sane() then
		prepare()
	end

	assert(_checkid(id), "Security Exception: Session ID is invalid!")
	assert(type(data) == "table", "Security Exception: Session data invalid!")

	data.atime = luci.sys.uptime()
	_write(id, json.stringify(data))
end

--- Read a session and return its content.
-- @param id	Session identifier
-- @return		Session data table or nil if the given id is not found
function read(id)
	if not id or #id == 0 then
		return nil
	end
	if id ~= "00000000000000000000000000000000" then
		assert(_checkid(id), "Security Exception: Session ID is invalid!")
		if not sane(sessionpath .. "/" .. id) then
			return nil
		end
	end
	local sess = json.parse(_read(id) or "")
	if id ~= "00000000000000000000000000000000" then
		if sess.atime and sess.atime + sessiontime < luci.sys.uptime() then
			kill(id)
			return nil
		end
		-- refresh atime in session
		write(id, sess)
	end

	return sess
end

--- Check whether Session environment is sane.
-- @return Boolean status
function sane(file)
	return luci.sys.process.info("uid") == fs.stat(file or sessionpath, "uid") and
		fs.stat(file or sessionpath, "modestr") == (file and "rw-------" or "rwx------")
end

--- Kills a session
-- @param id	Session identifier
function kill(id)
	assert(_checkid(id), "Security Exception: Session ID is invalid!")
	fs.unlink(sessionpath .. "/" .. id)
end

--- Remove all expired session data files
function reap()
	if sane() then
		local id
		for id in nixio.fs.dir(sessionpath) do
			if _checkid(id) then
				-- reading the session will kill it if it is expired
				read(id)
			end
		end
	end
end

function merge_table(a, b)
	local flag, k, v
	if type(a) == "table" and type(b) == "table" then
		for k, v in pairs(b) do
			flag = false
			if type(v) == "table" then
				if not a[k] and type(a[k]) ~= "table" then
					a[k] = v
				else
					merge_table(a[k], v)
				end
			else
				for key, value in pairs(a) do
					if value == v then
						flag = true
					end
				end
				if flag == false then
					table.insert(a, v)
				end
			end
		end
	end
	return a
end

function merge_acls(a, option, b)
	local k,v,x,y
	if type(a) == "table" and type(b) == "table" then
		for k, v in pairs(b)do
			if type(v) == "table" then
				if type(a[k]) ~= "table" then
					a[k] = {}
				end
					for x, y in pairs(v) do
						if type(y) ~= "table" then
							y = {[y] = {option}}
							if type(a[k]) ~= "table" then
								a[k]= y
							else
								merge_table(a[k], y)
							end
						elseif type(a[k][x]) ~= "table" then
							a[k][x] = y
						else
							merge_table(a[k][x], y)
						end
					end
			end
		end
	end
end

function gen_acls(user)
	local file
	local acl_files = {}
	local acls = {}
	local access_groups = {}

	for file in (fs.glob(os.getenv("LUCI_SYSROOT") .. "/usr/share/rpcd/acl.d/*.json") or function()
		end) do
		acl_files[#acl_files + 1] = file
	end

	for _, file in ipairs(acl_files) do
		local data = json.parse(fs.readfile(file) or "")
		if type(data) == "table" then
			for app, spec in pairs(data) do
				access_groups[app] = {}
				if type(spec) == "table" then
					for option, read_or_write_object in pairs(spec) do
						if type(read_or_write_object) == "table" then
							table.insert(access_groups[app], option)
							merge_acls(acls, option, read_or_write_object)
						end
					end
				end
			end
		end
	end
	acls["access-group"] = access_groups
	acls["access-group"]["allow-full-uci-access"] = {"write", "read"}
	acls["access-group"]["unauthenticated"] = {"read"}
	-- TODO: ADD USER ACCESS CONTROL
	return acls
end

function setup(user, pass)
	if luci.sys.user.checkpasswd(user, pass) then
		local sid = luci.sys.uniqueid(16)
		local token = luci.sys.uniqueid(16)
		reap()
		write(
			sid,
			{
				session = sid,
				acls = gen_acls(user),
				data = {
					username = user,
					token = token
				}
			}
		)
		return sid
	end
	return nil
end

function access(sid, scope, obj, func)
	local sess = read(sid)
	if sess then
		if scope and obj and func then
			if sess.acls[scope] and sess.acls[scope][obj] and type(sess.acls[scope][obj]) == "table" then
				for _, v in ipairs(sess.acls[scope][obj]) do
					if func == v then
						return {access = true}
					end
				end
			else
				return
			end
		else
			return sess.acls
		end
	else
		return
	end
end
