local Table = require('table')
local OS = require('os')
local parse_url = require('url').parse
local parse_query = require('querystring').parse
local JSON = require('json')

return function (options)

  return function (req, res)

    res.req = req

    -- CORS
    res:set_header('Access-Control-Allow-Credentials', 'true')
    local origin = req.headers.origin or '*'
    res:set_header('Access-Control-Allow-Origin', origin)
    header = req.headers['access-control-request-headers']
    if header then res:set_header('Access-Control-Allow-Headers', header) end

    -- get connection
    -- TODO: FIXXXX
    req.uri = parse_url(req.url)
    req.uri.query = parse_query(req.uri.query)
    local q = req.uri.query
    local id = q.sid
p('GETCONN', id)
    local conn = require('./connection').get(id)

    --
    -- incoming data
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
        data = data .. chunk
      end)
      -- data collected
      req:on('end', function ()
        conn:_message(data)
        res:write_head(204, {
          ['Content-Type'] = 'text/plain; charset=UTF-8',
        })
        res:finish()
      end)

    --
    -- outgoing data
    --

    elseif req.method == 'GET' then

      -- define sender
      res.send = function (self, data, callback)
        self:finish(data, callback)
      end

      -- existing connection
      if conn then

        -- send response headers
        res.auto_chunked = false
        res:write_head(200, {
          ['Content-Type'] = 'text/plain; charset=UTF-8'
        })

        -- bind response to the connection
        conn:_bind(res)

      -- new connection?
      elseif not id then

        -- bind response to the connection
        conn = options.new(res, options)

      -- no such connection
      else

        -- bail out
        res:set_code(404)
        res:finish()

      end

    --
    -- OPTIONS, for CORS
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
    -- invalid verb
    --

    else

      res:set_code(405)
      res:finish()

    end

  end

end
