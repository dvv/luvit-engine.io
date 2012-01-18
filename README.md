[engine.io](https://github.com/learnboost/engine.io) port for [Luvit](https://github.com/luvit/luvit)
====

`Engine` is the implementation of transport-based cross-browser/cross-device
bi-directional communication layer between systems.

## Hello World

### Server

#### As a middleware layer

```lua
local engine_handler = require('engine.io')({
  onopen = function (conn)
  end,
  onclose = function (conn)
  end,
  onmessage = function (conn, message)
    -- repeater
    conn:send(message)
  end,
  -- other options
  -- ...
})
require('http').create_server('0.0.0.0', 8080, function (req, res)
  if req.url:sub(1, 11) == '/engine.io?' then
    engine_handler(req, res)
  else
    -- ...
    res:set_code(404)
    res:finish()
  end
end)
```

### Client

```html
<script src="/path/to/engine.js"></script>
<script>
  var socket = new engine.Socket({ host: 'localhost', port: 80 });
  socket.on('open', function () {
    socket.on('message', function (data) { });
    socket.on('close', function () { });
  });
</script>
```

For more information on the client refer to the
[engine-client](http://github.com/learnboost/engine.io-client) repository.

License
-------

[MIT](engine.io/license.txt)
