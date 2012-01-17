local Table = require('table')
local OS = require('os')
local parse_url = require('url').parse
local parse_qs = require('querystring').parse

return function (options)

  local function parse_req(req)
    -- engine.io way
    local uri = parse_url(req.url)
    local q = parse_qs(uri.query)
    return q.sid, q.transport
  end

  local function new_connection(res)
    local conn = options.new(res, options)
    res:on('message', function (payload)
p('INCOME', payload)
      conn:_message(payload)
    end)
  end

  local function get_connection(id)
    return options.get(id)
  end

  local hixie76 = require('websocket/lib/hixie76').handshake
  local hybi10 = require('websocket/lib/hybi10').handshake

  local function websocket_handler(req, res, register)

    -- request looks like WebSocket one?
    if (req.headers.upgrade or ''):lower() ~= 'websocket' then
      return respond(res, 400)
    end
    if not (',' .. (req.headers.connection or ''):lower() .. ','):match('[^%w]+upgrade[^%w]+') then
      return respond(res, 400)
    end

    -- request has come from allowed origin?
    local origin = req.headers.origin
    --[[if not verify_origin(origin, options.origins) then
      return respond(res, 401)
    end]]--

    -- guess the protocol
    local location = origin and origin:sub(1, 5) == 'https' and 'wss' or 'ws'
    location = location .. '://' .. req.headers.host .. req.url
    -- determine protocol version
    local ver = req.headers['sec-websocket-version']
    local shaker = hixie76
    if ver == '7' or ver == '8' or ver == '13' then
      shaker = hybi10
    end

    -- disable buffering
    res:nodelay(true)
    -- ??? timeout(0)?

    -- handshake, then register
    shaker(req, res, origin, location, register)

  end

  return function (req, res)

    -- any error in req closes the request
    req:once('error', function (err)
d('ERRINREQ!!!', err)
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

    -- given connection id, try to get the connection
    local conn = get_connection(id)

    --
    -- INCOMING DATA
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
      local data = ''
      req:on('data', function (chunk)
        -- TODO: consider streaming parser, to defeat concat
        data = data .. chunk
      end)
      -- data collected
      req:on('end', function ()
        -- send data to parser
        conn:_message(data)
        --res:emit('message', data)
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

      -- define XHR sender
      -- TODO: extract, to not proliferate closures
      res.send = function (self, data, callback)
        self:finish(data, callback)
      end

      -- for existing connection...
      if conn then

        -- WebSocket?
        if req.headers.upgrade then
          -- delegate to websocket handler
          websocket_handler(req, res, function (res)
            res:on('message', function (payload)
p('INCOME', payload)
              conn:_message(payload)
            end)
            conn:_bind(res)
          end)
        else
          -- send response headers
          res:write_head(200, {
            ['Content-Type'] = 'text/plain; charset=UTF-8'
          })
          -- bind response to the connection
          conn:_bind(res)
        end

      -- for new connection...
      elseif not id then

        -- WebSocket?
        if req.headers.upgrade then
          -- delegate to websocket handler
          websocket_handler(req, res, new_connection)
        else
          -- turn chunking mode on
          res.auto_chunked = true
          -- bind response to the connection
          -- TODO: generalize
          conn = new_connection(res)
        end

      -- no such connection...
      else

        -- bail out
        res:set_code(404)
        res:finish()

      end

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
