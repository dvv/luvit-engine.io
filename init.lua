--
-- patch Stack.mount and Stack.errorHandler
--

local Url = require('url')
local Stack = require('stack')

function Stack.mount(mountpoint, ...)
  local stack = Stack.compose(...)
  local mplen = #mountpoint

  return function(req, res, continue)
    local url = req.url
    local uri = req.uri
    if not (url:sub(1, mplen) == mountpoint) then return continue() end
    -- Modify the url
    if not req.real_url then req.real_url = url end
    req.url = url:sub(mplen + 1)
    if req.uri then req.uri = Url.parse(req.url) end
    stack(req, res, function (err)
      req.url = url
      req.uri = uri
      continue(err)
    end)
  end
end

local Debug = require('debug')
function Stack.errorHandler(req, res, err)
  if err then
    res:set_code(500)
    debug(Debug.traceback(err))
    res:finish(Debug.traceback(err) .. "\n")
    return
  end
  res:set_code(404)
  res:finish("Not Found\n")
end

return require('./lib')
