local Server = require('server')
local Engine = require('../')

local http_stack_layers
http_stack_layers = function()
  return {
    Server.use('route')({
      {
        'GET /$',
        function(self, nxt)
          return self:render('public/index.html', self.req.context)
        end
      }
    }),
    Engine('/echo', {
      onconnection = function(conn)
        p('CONNECTED TO /echo', conn.id)
        conn:on('message', function(m)
          conn:send(m)
        end)
        conn:on('close', function()
          p('DISCONNECTED FROM /echo', conn.id)
        end)
      end
    }),
    Server.use('static')('/', 'public/', { }),
  }
end

local s1 = Server.run(http_stack_layers(), 3000, '0.0.0.0')
print('Server listening at http://localhost:3000/')
