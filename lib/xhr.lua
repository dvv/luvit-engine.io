local Table = require('table')
local Utils = require('utils')
local OS = require('os')
local parse_url = require('url').parse
local parse_qs = require('querystring').parse
local transports = require('./transport')

local function parse_req(req)
  -- engine.io way
  local uri = parse_url(req.url)
  local q = parse_qs(uri.query)
  return q.sid, q.transport
end

return function (options)

  local function new_connection(req, res, callback)
    local conn = options.new(options)
    if callback then
      callback(conn)
    else
      return conn
    end
  end

  local function get_connection(id)
    return options.get(id)
  end

  return function (req, res)

    -- any error in req closes the request
    req:once('error', function (err)
      req:close()
    end)

    -- turn chunking mode off
    res.auto_chunked = false

    -- CORS
    res:set_header('Access-Control-Allow-Credentials', 'true')
    local origin = req.headers.origin or '*'
    res:set_header('Access-Control-Allow-Origin', origin)
    header = req.headers['access-control-request-headers']
    if header then res:set_header('Access-Control-Allow-Headers', header) end

    -- given request, get connection id, transport and other parameters
    local id, transport = parse_req(req)

    -- determine transport, bail out if not found
    transport = transports[transport]
    if not transport then
      res:set_code(404)
      res:finish()
      return
    end

    -- given connection id, try to get the connection
    local conn = get_connection(id)

    --
    -- INCOMING DATA, for XHR transports
    --

    if req.method == 'POST' then

      -- no such connection?
      if not conn then
        -- bail out
        res:set_code(404)
        res:finish()
        return
      end

      -- collect passed data
      local buffer = ''
      req:on('data', function (chunk)
        -- TODO: consider streaming parser, to defeat concat
        buffer = buffer .. chunk
      end)
      -- data collected
      req:on('end', function ()
        -- send data to parser
        conn:_message(buffer)
        -- and tell client that data is consumed OK
        res:write_head(204, {
          ['Content-Type'] = 'text/plain; charset=UTF-8',
        })
        res:finish()
      end)

    --
    -- OUTGOING DATA
    --

    elseif req.method == 'GET' then

      transport.handshake(req, res, function ()
        -- no such connection
        if not conn then
          -- it's not found?
          if id then
            res:set_code(404)
            res:finish()
            return
          end
          -- create new connection
          conn = new_connection(req, res)
          -- failed to create?
          if not conn then
            res:set_code(500)
            res:finish()
            return
          end
        end
        -- attach sender
        if not res.send then res.send = transport.send end
        -- attach receiver
        req:on('message', Utils.bind(conn, conn._message))
        -- bind connection
        conn:_bind(req, res)
      end)

    --
    -- OPTIONS, to allow CORS preflight
    --

    elseif req.method == 'OPTIONS' then

      local cache_age = 365*24*60*60*1000
      res:set_header('Allow-Control-Allow-Methods', 'OPTIONS, POST')
      res:set_header('Cache-Control', 'public, max-age=' .. 365*24*60*60*1000)
      res:set_header('Expires', OS.date('%c', OS.time() + cache_age))
      res:set_header('Access-Control-Max-Age', tostring(cache_age))
      res:set_code(204)
      res:finish()

    --
    -- INVALID VERB
    --

    else

      res:set_code(405)
      res:finish()

    end

  end

end
