--[[
LuCI - Lua Configuration Interface
Copyright 2021 lisaac <https://github.com/lisaac/luci-in-docker>
]]--

local fs = require "nixio.fs"

local function readfile(path)
	local s = fs.readfile(path)
	return s and (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local fubus_file = {
	read = {
		args = {path = "", base64 = false},
		call = function(args)
			if args.path and args.path ~= "" and fs.access(args.path) then
				if args.base64 then
					return {data = luci.util.exec("base64 " .. args.path)}
				else
					return {data = readfile(args.path)}
				end
			end
		end
	},
	write = {
		args = {path = "", data = "", append = false, mode = 0666, base64 = false},
		call = function(args)
			if args.path and args.path ~= "" then
				local f
				if append then
					f = io.open(args.path, "a+")
				else
					f = io.open(args.path, "w+")
				end
				f:write(args.data)
				f:close()
			end
		end
	},
	list = {
		args = {path = ""},
		call = function(args)
			if args.path and args.path ~= "" and fs.access(args.path) then
				local f, res = nil, {}
				local file_type = {
					reg = "file",
					dir = "directory",
					chr = "char", 
					blk = "block", 
					fifio = "fifo", 
					lnk = "link", 
					sock = "socket"
				}
				for f in (fs.dir(args.path) or function() end) do
					local stat = fs.stat(args.path .. "/" .. f)
					stat.name = fs.basename(f)
					stat.type = file_type[stat.type]
					table.insert(res, stat)
				end
				return { entries = res }
			end
		end
	},
	stat = {
		args = {path = ""},
		call = function(args)
			if args.path and args.path ~= "" and fs.access(args.path) then
				return fs.stat(args.path)
			end
		end
	},
	md5 = {
		args = {path = ""},
		call = function(args)
			if args.path and args.path ~= "" and fs.access(args.path) then
				return luci.util.exec("md5 " .. args.path .. " | awk '{print $NF}'")
			end
		end
	},
	remove = {
		args = {path = ""},
		call = function(args)
			if args.path and args.path ~= "" and fs.access(args.path) then
				return fs.remove(args.path)
			end
		end
	},
	exec = {
		args = {command = "", params = {}, env = {}},
		call = function(args)
			if args.command and args.command ~= "" then
				if type(args.params) == "table" then
					local p = table.concat(args.params, " ")
					-- fix for rpcErrors
					return nil, os.execute(args.command .. " " .. p)
				else
					return nil, os.execute(args.command)
				end
			end
		end
	}
}

return fubus_file
