--[[
LuCI - Lua Configuration Interface
Copyright 2021 lisaac <https://github.com/lisaac/luci-in-docker>
]]--

local fs = require "nixio.fs"
local fubus_system = {
	board = {
		args = {},
		call = function(args)
			local cpuinfo = fs.readfile("/proc/cpuinfo")
			local unameinfo = nixio.uname() or {}
			return {
				kernel = unameinfo.release or "?",
				hostname = luci.sys.hostname() or "?",
				system = unameinfo.machine or "?",
				model = cpuinfo:match("system type\t+: ([^\n]+)") or
					cpuinfo:match("Processor\t+: ([^\n]+)") or
					cpuinfo:match("model name\t+: ([^\n]+)"),
				board_name = "Luci-in-docker",
				release = {
					distribution = "LuCI in Docker",
					version = "21.02",
					revision = "21.02",
					target = unameinfo.machine or "?",
					description = "LuCI in Docker"
				}
			}
		end
	},
	hostname = {
		args = {hostname = ""},
		call = function(args)
			local sys = require 'luci.sys'
			return sys.hostname(args.hostname)
		end
	},
	info = {
		args = {},
		call = function(args)
			local sysinfo = nixio.sysinfo()
			
			return {
				localtime = os.time(),
				uptime = sysinfo.uptime,
				load = {
					sysinfo.loads[1]*65535,
					sysinfo.loads[2]*65535,
					sysinfo.loads[3]*65535

				},
				memory = {
					total = sysinfo.totalram,
					free = sysinfo.freeram,
					shared = sysinfo.sharedram,
					buffered = sysinfo.bufferram,
					cached = sysinfo.bufferram
				},
				swap = {
					total = sysinfo.totalswap,
					free = sysinfo.freeswap
				}
			}
		end
	},
	reboot = {
		args = {},
		call = function(args)
			luci.util.exec("/init.sh")
		end
	}
}

return fubus_system
