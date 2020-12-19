-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2008-2011 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.

module("luci.controller.admin.system", package.seeall)

function index()
	entry({"admin", "system"}, alias("admin", "system", "system"), _("System"), 30).index = true
	entry({"admin", "system", "system"}, cbi("admin_system/system"), _("System"), 1)
	entry({"admin", "system", "clock_status"}, post_on({ set = true }, "action_clock_status"))
	entry({"admin", "system", "admin"}, cbi("admin_system/admin"), _("Administration"), 2)
	entry({"admin", "system", "plugin"}, form("admin_system/plugin"), _("Plugin Management"), 45)
	entry({"admin", "system", "plugin_rename"}, call("action_plugin_rename"))
	entry({"admin", "system", "plugin_install"}, call("action_plugin_install"))
	-- entry({"admin", "system", "crontab"}, form("admin_system/crontab"), _("Scheduled Tasks"), 46)
	entry({"admin", "system", "reboot"}, template("admin_system/reboot"), _("Restart LuCI"), 90)
	entry({"admin", "system", "reboot", "call"}, post("action_reboot"))
end

function action_plugin_install()
	local upload_filename = luci.http.formvalue("upload-filename")
	local filepath = "/tmp/.upload_plugins/"..upload_filename
	luci.util.exec("mkdir -p /tmp/.upload_plugins && rm /tmp/.upload_plugins/*")
	local fp
	luci.http.setfilehandler(
		function(meta, chunk, eof)
			if not fp and meta and meta.name == "upload-archive" then
				fp = io.open(filepath, "w")
			end
			if fp and chunk then
				fp:write(chunk)
			end
			if fp and eof then
				fp:close()
			end
		end
	)
	luci.util.exec("unzip -o %s -d /external/plugin/ && rm %s" %{filepath, filepath})
	luci.http.status(200, msg)
	luci.http.prepare_content("application/json")
	luci.http.write_json({})
end

function action_plugin_rename()
	local o = luci.http.formvalue("o_name")
	local n = luci.http.formvalue("new_name")
	local plugin_dir = "/external/plugin/"
	if o ~= n and nixio.fs.access("%s/%s" %{plugin_dir, o}) then
		luci.util.exec("mv %s/%s %s/%s" %{plugin_dir, o, plugin_dir, n})
		code = 200
		msg = "ok"
	else
		code = 400
		msg = "no plugin or need NOT to rename"
	end
	luci.http.status(code, msg)
	luci.http.prepare_content("application/json")
  luci.http.write_json({code = code, msg = msg})
end

function action_clock_status()
	local set = tonumber(luci.http.formvalue("set"))
	if set ~= nil and set > 0 then
		local date = os.date("*t", set)
		if date then
			luci.sys.call("date -s '%04d-%02d-%02d %02d:%02d:%02d'" %{
				date.year, date.month, date.day, date.hour, date.min, date.sec
			})
		end
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json({ timestring = os.date("%c") })
end

function action_passwd()
	local p1 = luci.http.formvalue("pwd1")
	local p2 = luci.http.formvalue("pwd2")
	local stat = nil

	if p1 or p2 then
		if p1 == p2 then
			stat = luci.sys.user.setpasswd("root", p1)
		else
			stat = 10
		end
	end

	luci.template.render("admin_system/passwd", {stat=stat})
end

function action_reboot()
	local dsp = require "luci.dispatcher"
	local utl = require "luci.util"
	local sauth = require "luci.sauth"
	local sid = dsp.context.authsession
	
	if sid then
		sauth.kill(sid)
	end
	utl.copcall(luci.sys.exec, "kill -9 1")
	-- luci.sys.exec("/init.sh")
end

function fork_exec(command)
	local pid = nixio.fork()
	if pid > 0 then
		return
	elseif pid == 0 then
		-- change to root dir
		nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		local null = nixio.open("/dev/null", "w+")
		if null then
			nixio.dup(null, nixio.stderr)
			nixio.dup(null, nixio.stdout)
			nixio.dup(null, nixio.stdin)
			if null:fileno() > 2 then
				null:close()
			end
		end

		-- replace with target command
		nixio.exec("/bin/sh", "-c", command)
	end
end

function ltn12_popen(command)

	local fdi, fdo = nixio.pipe()
	local pid = nixio.fork()

	if pid > 0 then
		fdo:close()
		local close
		return function()
			local buffer = fdi:read(2048)
			local wpid, stat = nixio.waitpid(pid, "nohang")
			if not close and wpid and stat == "exited" then
				close = true
			end

			if buffer and #buffer > 0 then
				return buffer
			elseif close then
				fdi:close()
				return nil
			end
		end
	elseif pid == 0 then
		nixio.dup(fdo, nixio.stdout)
		fdi:close()
		fdo:close()
		nixio.exec("/bin/sh", "-c", command)
	end
end
