-- Parse cache tables in an isolated Lua state; never execute generated Lua.
local channel, request = ...
local ok, result = pcall(function()
  require("love.filesystem")
  love.filesystem.setRequirePath(request.requirePath)
  package.path = request.packagePath
  local Decode = require("Gen3Decode")
  for _, name in ipairs(request.tables) do
    local path = "data/generated/" .. name .. ".lua"
    local rel = request.prefix .. path
    local bytes
    if request.root then
      local f = io.open(request.root .. "/" .. rel, "rb")
      if f then bytes = f:read("*a"); f:close() end
    end
    bytes = bytes or love.filesystem.read(rel)
    if bytes then
      channel:push({progress = name})
      local value = Decode.decode(bytes, {allowArray=true, allowComments=true,
        maxBytes=16*1024*1024, maxNodes=1000000, maxTableEntries=500000,
        maxDepth=64, maxStringBytes=4*1024*1024})
      if type(value) == "table" then channel:push({path=path, bytes=bytes, value=value}) end
    end
  end
end)
channel:push(ok and {complete=true} or {error=tostring(result)})
