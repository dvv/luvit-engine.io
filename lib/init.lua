local Table = require('table')
local Utils = require('utils')
local OS = require('os')

--
-- handle requests to sockets
--

local function handler(options)

  ---
  -- Socket interface
  --
  -- should expose:
  --   Socket.new(options, request, response) -- returns an instance of Socket
  --   Socket.get(id) -- returns existsing Socket instance by its identifier
  --   Socket.parse_req(request) -- returns tuple { id, transport }
  --
  --
  -- Socket instance should expose:
  --   Socket#register(request, response) -- bind incoming and outgoung channels to this socket. Pass 'open' packet if socket is not open
  --   Socket#onmessage(text) -- text string is received
  --   Socket#send(text) -- send given text string
  --   Socket#close() -- orderly close the socket, and unregister this socket
  --

  local Socket = options.socket

  return function (req, res)

    -- any error in req closes the request
    req:once('error', function (err)
      if not req.closed then req.closed = true ; req:close() end
    end)

    -- turn chunking mode off
    res.auto_chunked = false

    -- CORS
    res:set_header('Access-Control-Allow-Credentials', 'true')
    local origin = req.headers.origin or '*'
    res:set_header('Access-Control-Allow-Origin', origin)
    header = req.headers['access-control-request-headers']
    if header then res:set_header('Access-Control-Allow-Headers', header) end

    -- given request, get socket id, transport and other parameters
    local id, transport = Socket.parse_req(req)
    if not transport then
      res:set_code(404)
      res:finish()
      return
    end

    -- given socket id, try to get the socket
    local socket = Socket.get(id)

    --
    -- INCOMING DATA, for XHR/JSONP transports
    --

    if req.method == 'POST' then

      -- no such socket?
      if not socket then
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
        socket:onmessage(buffer)
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

      -- verify connection
      transport.handshake(req, res, function ()
        -- no such socket
        if not socket then
          -- it's not found?
          if id then
            res:set_code(404)
            res:finish()
            return
          end
          -- create new socket
          socket = Socket.new(options, req, res)
          -- failed to create?
          if not socket then
            res:set_code(500)
            res:finish()
            return
          end
        end
        -- attach sender, if none attached by handshake procedure
        if not res.send then res.send = transport.send end
        -- attach receiver
        req:on('message', Utils.bind(socket, socket.message))
        -- bind request and response to the socket
        socket:register(req, res)
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

-- module
return handler
