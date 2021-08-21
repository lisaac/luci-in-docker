local sauth = require "luci.sauth"

local fubus_session = {
  access = {
    args = {scope = "", object = "", ["function"] = "", ubus_rpc_session = ""},
    call = function(args)
      return sauth.access(args.ubus_rpc_session, args.scope, args.object, args["function"])
    end
  }
}
return fubus_session