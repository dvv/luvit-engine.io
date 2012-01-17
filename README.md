[engine.io](https://github.com/learnboost/engine.io) port for [Luvit](https://github.com/luvit/luvit)
====

`Engine` is the implementation of transport-based cross-browser/cross-device
bi-directional communication layer between systems.

## Hello World

### Server

#### Listening on a port

```lua
local engine = require('engine')
local server = engine.listen(80)

server:on('connection', function(socket)
  socket.send('utf 8 string')
end)
```

#### Intercepting requests for a http.Server

```lua
local engine = require('engine')
local http = require('server'):listen(3000)
local server = engine:attach(http)

server:on('connection', function(client)
  client:on('message', function() end)
  client:on('close', function() end)
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

Check [here](engine/license.txt).
