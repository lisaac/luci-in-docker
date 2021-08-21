local fs = require "nixio.fs"
local uci = (require "luci.model.uci").cursor()

local fubus_uci = {
  configs = {
    args = {},
    call = function(args)
      local d, res = nil, {}
      for d in fs.dir(uci:get_confdir()) do
        table.insert( res, d )
      end
      return res
    end
  },
  get = {
    args = {config = "", section = "", type = "", option = "", match = {}},
    call = function(args)
      if args.option then
        return { values = uci:get(args.config, args.section, args.option) }
      else
        local values = uci:get_all(args.config, args.section)
        if args.type then
          local res, k, v = {}, nil, nil
          for k, v in pairs(values) do
            if v[".type"] == args.type then
              res[k] = v
            end
          end
          return { values = res }
        else
          return { values = values}
        end
      end
    end
  },
  add = {
    args = {config = "", type = "", name = "", value = {}},
    call = function(args)
      return uci:section( args.config, args.type, args.name, args.value )
    end
  },
  --todo
  state = {
    args = {config = "", section = "", option = "", type = "", match = {}},
    call = function(args)
      return uci:get_state(args.config, args.section, args.option, args.type, args.match)
    end
  },
  set = {
    args = {config = "", section = "", type = "", match = {}, values = {}},
    call = function(args)
      if type(args.values) ~= "table" then return end
      local k, v
      for k, v in pairs(args.values) do
        uci:set(args.config, args.section, k, v)
      end
      uci:save(args.config)
    end
  },
  delete = {
    args = {config = "", section = "", type = "", match = {}, option = "", options = {}},
    call = function(args)
      if type(args.options) == "table" then
        local _, v
        for _, v in ipairs(args.options) do
          uci:delete(args.config, args.section, v)
        end
      elseif type(args.option) == "string" then
        uci:delete(args.config, args.section, args.option)
      end
      uci:save(args.config)
    end
  },
  --TODO
  rename = {
    args = {config = "", secition = "", option = "", name = ""},
    call = function(args)
      return { rename = "Not support" }
    end
  },
  order = {
    args = {config = "", sections = {}},
    call = function(args)
      local i, v
      for i, v in ipairs(args.sections) do
        uci:reorder(args.config, v, i)
        uci:save(args.config)
      end
    end
  },
  changes = {
    args = {config = ""},
    call = function(args)
      return { changes = uci:changes() }
    end
  },
  revert = {
    args = {config = "", ubus_rpc_session = ""},
    call = function(args)
      return uci:revert() 
    end
  },
  commit = {
    args = {config = "", ubus_rpc_session = ""},
    call = function(args)
      return uci:commit(args.config)
    end
  },
  apply = {
    args = {rollback = false, timeout = 60, ubus_rpc_session = ""},
    call = function(args)
      return uci:apply(args.rollback, args.ubus_rpc_session, args.timeout)
    end
  },
  confirm = {
    args = {ubus_rpc_session = ""},
    call = function(args)
      return uci:confirm(args.ubus_rpc_session)
    end
  },
  rollback = {
    args = {ubus_rpc_session = ""},
    call = function(args)
      return uci:rollback()
    end
  },
  reload_config = {
    args = {bus_rpc_session = ""},
    call = function(args)
      return { reload_config = "Not support" }
    end
  }
}

return fubus_uci