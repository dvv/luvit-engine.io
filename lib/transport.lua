
local transports = {

  polling = {

    send = function (self, data, callback)
      self:finish(data, callback)
    end,

    handshake = function (req, res, callback)
      callback()
    end,

  },

  websocket = {

    -- send = should be during WebSocket handshake

    handshake = require('websocket'),

  },

}

-- module
return transports
