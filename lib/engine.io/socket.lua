local d = process.env.DEBUG and debug or function () end

--
-- Connection
--

local Table = require('table')
local Utils = require('utils')
local Timer = require('timer')

local transports = require('./transport')

--
-- connection states
--

local Connection = {
  CONNECTING = 0,
  OPEN = 1,
  CLOSING = 2,
  CLOSED = 3,
}

Utils.inherits(Connection, { })

local default_options = {
  onopen = function (self) end,
  onclose = function (self) end,
  onerror = function (self, error) end,
  onmessage = function (self, message) end,
  codec = require('./codec'),
  upgrades = { },--'websocket' },
  ping_timeout = 60000,
  ping_interval = 25000,
  disconnect_delay = 5000,
}

--
-- connections table
--

local connections = { }
-- TODO: strip
_G.c = connections
_G.cl = function (...)
  connections['1']:close(...)
end
_G.s = function (...)
  for _, co in pairs(connections) do
    co:send(...)
  end
end
local nconn = 0

--
-- create new connection
--

function Connection.new(options, req, res)
  self = Connection.new_obj()
  -- TODO: add entropy
  nconn = nconn + 1
  self.id = tostring(nconn)
  self.options = setmetatable(options or { }, { __index = default_options })
  self.readyState = Connection.CONNECTING
  connections[self.id] = self
  self._send_queue = { }
  return self
end

--
-- get existing connection by id
--

function Connection.get(id)
  return connections[id]
end

function Connection.parse_req(req)
  -- engine.io way
  local q = req.uri.query
  local transport = q.j and 'jsonp' or q.transport
  return q.sid, transports[transport]
end

--
-- send a message to remote end
--

function Connection.prototype:send(message)
  -- can only send to open connection
  if self.readyState ~= Connection.OPEN then return false end
  self:_packet('message', message)
  return true
end

--
-- orderly close the connection
--

function Connection.prototype:close(code, reason)
  -- can close only open[ing] connection
  if self.readyState < Connection.CLOSING then
    -- stop ping
    if self._ping_timer then Timer.clear_timer(self._ping_timer) end
    -- try to flush
    self:_flush()
    -- mark connection as closing
    self.readyState = Connection.CLOSING
    -- upon sending close frame...
    self:_packet('close', self:_close_packet(), function ()
      -- finish the response
      -- N.B. this will trigger res:on('closed') which will
      -- unbind response from connection,
      -- mark connection as in closed state
      -- and report application of connection closure
      if self.res then self.res:finish() end
    end)
  end
end

--
-- bind channels to this connection and register this connection
--

function Connection.prototype:register(request, response)

  -- disallow binding more than one response
  if self.res then
    response:finish()
    return
  end

d('BIND', self.id)

  -- bind response
  self.res = response

  -- unbind the client when response is closed
  response:once('closed', function ()
    self:_unbind()
  end)

  -- any error in res closes the response,
  -- causing client unbind
  local function onerror(err, reason)
d('LOCALONERR', err)
    -- number errors are soft WebSocket protocol errors
    -- N.B. no error here means connection is closed orderly
    if type(err) == 'number' and err ~= 1000 then
      self.options.onerror(self, err, reason)
    -- hard error
    elseif err then
d('ERR', err)
      -- TODO: implement?
    end
    --if not request.closed then request.closed = true ; request:close() end
    response:finish()
  end

  request:once('error', onerror)
  response:once('error', onerror)

  -- send opening frame for new connections
  if self.readyState == Connection.CONNECTING then
    self:_packet('open', self:_open_packet(), function ()
      -- and report connection is open
      self.readyState = Connection.OPEN
      self.options.onopen(self)
    end)
  end

  -- try to flush the buffer
  if self.readyState == Connection.OPEN then
    self:_flush()
  end

  -- start ping
  if self.options.ping_interval then
    self._ping_timer = Timer.set_interval(self.options.ping_interval, self._ping, self)
  end

end

--
-- handle incoming messages
--

function Connection.prototype:onmessage(payload)
d('DEC?', payload)
  local status, result = pcall(self.options.codec.decode, payload)
d('DEC!', status, result)
  if status then
    for _, packet in ipairs(result) do
      if packet.type == 'pong' then
        --self.options.onheartbeat(self)
      elseif packet.type == 'message' then
        self.options.onmessage(self, packet.data)
      elseif packet.type == 'error' then
        self.options.onerror(self, packet.data)
      elseif packet.type == 'close' then
        self:disconnect(packet.data)
      else
        -- ???
      end
    end
  else
d('DECERR', result, payload)
    self.options.onerror(self, result)
  end
end

--
-- disconnect the connection
--

function Connection.prototype:disconnect()
  -- mark connection as closing
  self.readyState = Connection.CLOSING
  if self.res then self.res:finish() end
end

--
-- unbind the response
--

function Connection.prototype:_unbind()
  -- stop ping
  if self._ping_timer then Timer.clear_timer(self._ping_timer) end
  --
  if self.res then
d('UNBIND', self.id)
    self.res = nil
    Timer.set_timeout(self.options.disconnect_delay, self._purge, self)
  end
end

--
-- purge the connection
--

function Connection.prototype:_purge()
  if self.res or self.readyState > Connection.CLOSING then
    -- FIXME: this should not happen
    return
  end
--d('PURGE', self.id)
  self.readyState = Connection.CLOSED
  self.options.onclose(self)
  if self.id then
    connections[self.id] = nil
    self.id = nil
  end
end

--
-- flush outgoing buffer
--

function Connection.prototype:_flush()
d('FLUSH?', self._send_queue, self._flushing)
  if self._flushing then return end
  local nmessages = #self._send_queue
  if nmessages > 0 and self.res then
    self._flushing = true
    self:_send(self._send_queue)
    -- TODO: consider resetting in callback to `send`
    self._send_queue = { }
    self._flushing = nil
  end
end

--
-- send low-level frame.
--

function Connection.prototype:_packet(ptype, pdata, callback)
  -- put message in outgoing buffer
d('PACKET', ptype, pdata)
  Table.insert(self._send_queue, { type = ptype, data = pdata })
  -- try to flush the buffer
  self:_flush()
  if callback then callback() end
end

--
-- sender
--

function Connection.prototype:_send(packets)
  local payload = self.options.codec.encode(packets)
d('FLUSH', payload)
  self.res:send(payload)
end

--
-- send ping
--

function Connection.prototype:_ping(...)
  self:_packet('ping', ...)
end

--
-- compose open packet
--

function Connection.prototype:_open_packet()
  -- TODO: send various options
  local HZ = require('json').stringify({
    sid = self.id,
    upgrades = self.options.upgrades,
    pingTimeout = self.options.ping_timeout,
  })
  return HZ
end

--
-- compose close packet
--

function Connection.prototype:_close_packet()
  return nil
end

-- module
return Connection
