local JSON = require('json')
local Curl = require('curl')

local transports = {

  polling = {

    send = function (self, data, callback)
      self:finish(data, callback)
    end,

    receive = function (req, res, callback)
      Curl.parse_request(req, function (err, data)
        callback(data)
        -- data is consumed OK
        res:write_head(204, {
          ['Content-Type'] = 'text/plain; charset=UTF-8',
        })
        res:finish()
      end)
    end,

    handshake = function (req, res, callback)
      callback()
    end,

  },

  jsonp = {

    send = function (self, data, callback)
      data = '___eio[' .. self.req.uri.query.j .. '](' .. JSON.stringify(data) .. ')'
      self:write_head(200, {
        ['Content-Type'] = 'text/javascript; charset=UTF-8',
        ['Content-Length'] = #data,
        ['Connection'] ='Keep-Alive',
      })
--[[
  // disable XSS protection for IE
  if (/MSIE 8\.0/.test(this.req.headers['user-agent'])) {
    headers['X-XSS-Protection'] = '0';
  }
]]--
      self:finish(data, callback)
    end,

    receive = function (req, res, callback)
      Curl.parse_request(req, function (err, data)
        callback(data.d or '')
        -- data is consumed OK
        res:write_head(204, {
          ['Content-Type'] = 'text/plain; charset=UTF-8',
        })
        res:finish()
      end)
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
