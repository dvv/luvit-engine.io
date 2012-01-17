#!/usr/bin/env luvit

local Timer = require('timer')

local WS = {
  new = function (res, options)
    p('NEW', res and res.req.url)
    local conn = require('./lib/connection').new(res, options)
    return conn
  end,
  onopen = function (conn)
    p('OPEN', conn.id)
  end,
  onclose = function (conn)
    p('CLOSE', conn.id)
  end,
  onerror = function (conn, code, reason)
    p('ERROR', conn.id, code, reason)
  end,
  onmessage = function (conn, message)
    p('<<<', conn.id, message)
    -- repeater
    conn:send(message)
    p('>>>', conn.id, message)
    -- close if 'quit' is got
    if message == 'quit' then
      conn:close(1002, 'Forced closure')
    end
  end,
}

local handle_engine = require('./lib/xhr')(WS)

local handle_static = require('static')('/', {
  directory = __dirname .. '/example',
  is_cacheable = function (file) return false end,
})

require('http').create_server('0.0.0.0', 8080, function (req, res)
  --p('REQ', req.method, req.url, req.headers)
  if req.url:sub(1, 11) == '/engine.io?' then
    handle_engine(req, res)
  else
    handle_static(req, res, function ()
      res:set_code(404)
      res:finish()
    end)
  end
end)
print('Open http://localhost:8080/index.html')
