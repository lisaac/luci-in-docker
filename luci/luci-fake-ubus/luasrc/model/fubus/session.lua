local sauth = require "luci.sauth"

local fubus_session = {
  access = {
    args = {scope = "", object = "", ["function"] = "", ubus_rpc_session = ""},
    call = function(args)
      return sauth.access(args)
    end
  }
}
return fubus_session