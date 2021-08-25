local json = require "luci.jsonc"
local fs = require "nixio.fs"

local fubus = {}
local SYSROOT = os.getenv("LUCI_SYSROOT") or ""
local p

for p in fs.dir("%s/usr/lib/lua/luci/model/fubus" % SYSROOT) do
	p = p:match("(.-).lua")
	fubus[p] = require("luci.model.fubus.%s" % p)
end

local function parseInput()
	local parse = json.new()
	local done, err

	while true do
		local chunk = io.read(4096)
		if not chunk then
			break
		elseif not done and not err then
			done, err = parse:parse(chunk)
		end
	end

	if not done then
		return(json.stringify({ error = err or "Incomplete input" }))
	end

	return parse:get()
end

local function validateArgs(obj, func, uargs)
	local method = fubus[obj] and fubus[obj][func] or nil
	if not method then
		return {error = "Method not found"}
	end

	if type(uargs) ~= "table" then
		return {error = "Invalid arguments"}
	end

	local k, v
	local margs = method.args or {}
	for k, v in pairs(uargs) do
		if k ~= "ubus_rpc_session" and (margs[k] == nil or (v ~= nil and type(v) ~= type(margs[k]))) then
			return {error = "Invalid arguments"}
		end
	end

	return method
end

fubus.fake = function(method, obj, func, args)
	local fs = require "nixio.fs"
	if fubus[obj] then
		if method == "list" then
			local _, f, rv = nil, nil, {}
			if obj then
				for _, f in pairs(fubus[obj]) do
					rv[_] = f.args or {}
				end
			else
				-- global query
				for f, _ in pairs(fubus) do
					if type(_) == "table" then
						table.insert( rv, f )
					end
				end
			end
			return rv
		elseif method == "call" then
			-- local args = parseInput()
			local f = validateArgs(obj, func, args)
			if f and f.call and type(f.call) == "function" then
				local result,	code = f.call(args)
				-- return (json.stringify(result):gsub("^%[%]$", "{}"))
				return result
			else
				return f
			end
		end
	elseif fs.access("%s/usr/libexec/rpcd/%s" % {SYSROOT, obj}) then
		local jsonc = require "luci.jsonc"
		local res = luci.util.exec("echo %s | %s/usr/libexec/rpcd/%s %s %s " % {luci.util.shellquote(jsonc.stringify(args or {})), SYSROOT or "", obj, method or "list", func or ""} )
		return jsonc.parse(res)
	end
end

return fubus
