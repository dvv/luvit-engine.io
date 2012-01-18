local Utils = require('utils')
local Crypto = require('crypto')

local Bit = require('bit')
local band, bor, bxor, rshift, lshift = Bit.band, Bit.bor, Bit.bxor, Bit.rshift, Bit.lshift

local String = require('string')
local sub, gsub, match, byte, char = String.sub, String.gsub, String.match, String.byte, String.char

local base64_table = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(data)
  return ((gsub(data, '.', function(x)
    local r, b = '', byte(x)
    for i = 8, 1, -1 do
      r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0')
    end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then
      return ''
    end
    local c = 0
    for i = 1, 6 do
      c = c + (sub(x, i, i) == '1' and 2 ^ (6 - i) or 0)
    end
    return sub(base64_table, c + 1, c + 1)
  end) .. ({
    '',
    '==',
    '='
  })[#data % 3 + 1])
end

local Table = require('table')
local push = Table.insert

--
-- verify connection secret
--

local function verify_secret(key)
  local data = (match(key, '(%S+)')) .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  return Crypto.sha1(data, true)
end

-- Lua has no mutable string. Workarounds are slow too.
-- Let's employ C power.
local Codec = require('../build/hybi10.luvit')

--
-- send payload
--

local function sender(self, payload, callback)
  local plen = #payload
  -- compose the out buffer
  local str = (' '):rep(plen < 126 and 6 or (plen < 65536 and 8 or 14)) .. payload
  -- encode the payload
  -- TODO: knowing plen we can create prelude separately from payload
  -- hence avoid concat
  Codec.encode(str, plen)
  -- put data on wire
  self:write(str, callback)
end

local function sender_test(self, payload, callback)
  local plen = #payload
  -- write prelude
  local prelude = (' '):rep(plen < 126 and 6 or (plen < 65536 and 8 or 14))
  Codec.encode(prelude, 0)
  self:write(prelude)
  -- mask and write payload
  Codec.mask(payload, sub(prelude, -4, -1), plen)
  self:write(payload, callback)
end

--
-- extract complete message frames from incoming data
--

local receiver
receiver = function (req, chunk)

  -- collect data chunks
  if chunk then req.buffer = req.buffer .. chunk end
  -- wait for data
  if #req.buffer < 2 then return end
  local buf = req.buffer

  -- full frame should have 'finalized' flag set
  local first = band(byte(buf, 2), 0x7F)
  if band(byte(buf, 1), 0x80) ~= 0x80 then
    return
  end

  -- get frame type
  local opcode = band(byte(buf, 1), 0x0F)

  -- reject too lenghty close frames
  if opcode == 8 and first >= 126 then
    req:emit('error', 1002, 'Wrong length for close frame')
    return
  end

  local l = 0
  local length = 0
  -- is message masked?
  local masking = band(byte(buf, 2), 0x80) ~= 0

  -- get the length of payload.
  -- wait for additional data chunks if amount of data is insufficient
  if first < 126 then
    length = first
    l = 2
  else
    if first == 126 then
      if #buf < 4 then
        return 
      end
      length = bor(lshift(byte(buf, 3), 8), byte(buf, 4))
      l = 4
    else
      if first == 127 then
        if #buf < 10 then
          return 
        end
        length = 0
        for i = 3, 10 do
          length = bor(length, lshift(byte(buf, i), (10 - i) * 8))
        end
        l = 10
      end
    end
  end

  -- message masked?
  if masking then
    -- frame should contain 4-octet mask
    if #buf < l + 4 then
      return 
    end
    l = l + 4
  end
  -- frame should be completely available
  if #buf < l + length then
    return 
  end

  -- extract payload
  -- TODO: buffers can save much time here
  local payload = sub(buf, l + 1, l + length)
  -- unmask if masked
  if masking then
    payload = Codec.mask(payload, sub(buf, l - 3, l), length)
  end
  -- consume data
  req.buffer = sub(buf, l + length + 1)

  -- message frame?
  if opcode == 1 then
    -- emit 'message' event
    if #payload > 0 then
      req:emit('message', payload)
    end
    -- and start over
    receiver(req)
  -- close frame
  elseif opcode == 8 then
    local status = nil
    local reason = nil
    -- contains 2-octet status
    if #payload >= 2 then
      status = bor(lshift(byte(payload, 1), 8), byte(payload, 2))
    end
    -- and textual reason
    if #payload > 2 then
      reason = sub(payload, 3)
    end
    -- report error. N.B. close is handled by error handler
    req:emit('error', status, reason)
  end

end

--
-- initialize the channel
--

local function handshake(req, res, origin, location, callback)

  -- ack connection
  local protocol = req.headers['sec-websocket-protocol']
  if protocol then protocol = (match(protocol, '[^,]*')) end
  res:write_head(101, {
    ['Upgrade'] = 'WebSocket',
    ['Connection'] = 'Upgrade',
    ['Sec-WebSocket-Accept'] = base64(verify_secret(req.headers['sec-websocket-key'])),
    ['Sec-WebSocket-Protocol'] = protocol
  })
  res.has_body = true

  -- setup receiver
  req.buffer = ''
  req:on('data', Utils.bind(req, receiver))
  -- setup sender
  res.send = sender

  -- register connection
  if callback then callback(req, res) end

end

-- module
return {
  sender = sender,
  receiver = receiver,
  handshake = handshake,
}
