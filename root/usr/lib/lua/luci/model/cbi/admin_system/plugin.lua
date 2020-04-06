-- Copyright 2008 Steven Barth <steven@midlink.org>
-- Copyright 2010-2012 Jo-Philipp Wich <jow@openwrt.org>
-- Copyright 2010 Manuel Munz <freifunk at somakoma dot de>
-- Licensed to the public under the Apache License 2.0.

local fs  = require "nixio.fs"
local sys = require "luci.sys"

local plugin_dir = "/external/plugin/"
local plugins = { }

local index = 0
for _, name in ipairs(luci.util.execl("ls -1d -- /external/plugin/*")) do
	name = name:match("[^%/]+$")
	local enabled = not name:match("^_") and true or false
	if enabled then
		plugins["%02i.%s" % { index, name }] = {
			index   = tostring(index),
			name    = name,
			enabled = enabled
		}
		index = index + 1
	else
		plugins["%s.%s" % { "NaN", name }] = {
			index   = "NaN",
			name    = name,
			enabled = enabled
		}
	end
end

m = SimpleForm("pluginmgr", translate("Plugin"), translate("You can Enable/Disable/Install/Remove Plugins here. Changes will applied after a next restart.") 
.. "<br />".. translate("For Plugin info, please visit:")
..[[<a href="https://github.com/lisaac/luci-in-docker#插件" target="_blank">]] ..translate("Github") .. [[</a>]])
m.reset = false
m.submit = false
m:append(Template("admin_system/plugin_rename"))

s = m:section(Table, plugins)
n = s:option(DummyValue, "index", translate("Merge priority"))
n = s:option(DummyValue, "name", translate("Plugin"))
local btn_rename = s:option(Button, "rename", translate("Rename"))
btn_rename.inputstyle = "apply"


local btn_endisable = s:option(Button, "endisable", translate("Enable/Disable"))
btn_endisable.render = function(self, section, scope)
	if plugins[section].enabled then
		self.title = translate("Enabled")
		self.inputstyle = "save"
	else
		self.title = translate("Disabled")
		self.inputstyle = "reset"
	end
	Button.render(self, section, scope)
end

btn_endisable.write = function(self, section)
	if plugins[section].enabled then
		luci.util.exec("mv %s/%s %s/%s" %{plugin_dir, plugins[section]["name"], plugin_dir, "_"..plugins[section]["name"]})
	else
		luci.util.exec("mv %s/%s %s/%s" %{plugin_dir, plugins[section]["name"], plugin_dir, plugins[section]["name"]:match("^_(.+)")})
	end
	luci.http.redirect(luci.dispatcher.build_url("admin/system/plugin"))
end

local btn_rm = s:option(Button, "rm", translate("Remove"))
btn_rm.render = function(self, section, scope)
	if plugins[section].enabled then
		self.template = "cbi/dvalue"
		DummyValue.render(self, section, scope)
	else
		self.inputstyle = "reset"
		self.template = "cbi/button"
		Button.render(self, section, scope)
	end
end

btn_rm.write = function(self, section)
	if not plugins[section].enabled then
		luci.util.exec("rm -fr %s/%s" %{plugin_dir, plugins[section]["name"]})
	end
	luci.http.redirect(luci.dispatcher.build_url("admin/system/plugin"))
end

f = SimpleForm("rc", translate("Local Startup"),
	translate("This is the content of /etc/rc.local. Insert your own commands here (in front of 'exit 0') to execute them at the end of the boot process."))

t = f:field(TextValue, "rcs")
t.forcewrite = true
t.rows = 20

function t.cfgvalue()
	return fs.readfile("/etc/rc.local") or ""
end

function f.handle(self, state, data)
	if state == FORM_VALID then
		if data.rcs then
			fs.writefile("/etc/rc.local", data.rcs:gsub("\r\n", "\n"))
		end
	end
	return true
end

return m, f
