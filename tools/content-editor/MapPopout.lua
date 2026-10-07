-- Map builder: "Preview in fullscreen". The map being edited, fullscreen in a
-- window of its own (on the second screen when there is one), following the
-- editor as you work.
--
-- LÖVE draws one window per program, so the preview is another copy of the
-- editor, started the way the event window is, that draws only the map view
-- with the Pan tool. The editor sends it what changes over a local socket:
-- the edits to the project (PopoutSync.diff -- a painted cell is a few bytes)
-- and which map and overlays are showing. Nothing comes back: the preview
-- only looks.
local M = {}
local Sync = require("PopoutSync")

local LIMITS = { allowArray = true, maxBytes = 128 * 1024 * 1024, maxNodes = 8000000,
  maxTableEntries = 4000000, maxDepth = 100, maxStringBytes = 64 * 1024 * 1024 }

-- What the preview shows the same way as the editor: the map, and the overlays.
M.FOLLOWS = { "mapId", "builderMapId", "mapShowGrid", "mapShowCollision", "mapShowNeighbors", "mapShowElevations" }
function M.snapshot(S)
  local out = {}
  for _, key in ipairs(M.FOLLOWS) do out[key] = Sync.plain(S[key]) end
  return out
end

local function now()
  return love and love.timer and love.timer.getTime() or os.clock()
end

-- A socket with whole messages in and out, never waiting.
local Link = {}
Link.__index = Link
local function newLink(sock)
  sock:settimeout(0)
  pcall(sock.setoption, sock, "tcp-nodelay", true)
  return setmetatable({ sock = sock, inbuf = "", out = {}, outAt = 1 }, Link)
end
function Link:send(message)
  if self.closed then return end
  local ok, text = pcall(function() return "return " .. require("ModWriter").encodeLua(message) .. "\n" end)
  if ok then self.out[#self.out + 1] = Sync.frame(text) end
end
function Link:flush()
  while not self.closed and self.out[1] do
    local last, err, partial = self.sock:send(self.out[1], self.outAt)
    if last then
      table.remove(self.out, 1)
      self.outAt = 1
    elseif err == "timeout" then
      self.outAt = (partial or self.outAt - 1) + 1
      return
    else
      self.closed = true
    end
  end
end
function Link:read()
  local messages = {}
  if self.closed then return messages end
  for _ = 1, 64 do
    local data, err, partial = self.sock:receive(65536)
    local chunk = data or partial
    if chunk and chunk ~= "" then self.inbuf = self.inbuf .. chunk end
    if not data then
      if err ~= "timeout" then self.closed = true end
      break
    end
  end
  local texts, rest = Sync.unframe(self.inbuf)
  if not texts then self.closed = true; return messages end
  self.inbuf = rest
  for _, text in ipairs(texts) do
    local ok, message = pcall(require("Gen3Decode").decode, text, LIMITS)
    if ok and type(message) == "table" then messages[#messages + 1] = message end
  end
  return messages
end
function Link:close()
  self.closed = true
  pcall(self.sock.close, self.sock)
end

---------------------------------------------------------------- the editor
local host = nil

function M.available(S)
  return S and S.project ~= nil and require("Generation").isGen3(S)
    and love and love.filesystem and love.filesystem.getExecutablePath ~= nil
end
function M.active(S)
  return host ~= nil and (S == nil or host.S == S)
end

local function tempPath()
  local path = os.tmpname()
  -- The bundled Windows Lua runtime can return a root-relative name (\s123.).
  if package.config:sub(1, 1) == "\\" and not path:match("^%a:") then
    path = (os.getenv("TEMP") or os.getenv("TMP") or love.filesystem.getSaveDirectory())
      .. "/" .. path:match("[^/\\]+$")
  end
  os.remove(path)
  return path
end

--- Open the preview window. Returns true, or false and why.
function M.open(S, App, launch)
  if host then return true end
  if not M.available(S) then return false, "The fullscreen preview needs an open Gen 3 project" end
  local okS, socket = pcall(require, "socket")
  if not okS then return false, "The fullscreen preview needs LuaSocket, which this build doesn't have" end
  local server, err = socket.bind("127.0.0.1", 0)
  if not server then return false, "Could not open a local port: " .. tostring(err) end
  server:settimeout(0)
  local _, port = server:getsockname()
  local token = ("%08x%08x"):format(math.random(0, 0x7fffffff), math.floor(now() * 1000) % 0x7fffffff)
  local path = tempPath()
  -- the other screen, when there is one
  local display = 1
  pcall(function()
    local _, _, mine = love.window.getPosition()
    local count = love.window.getDisplayCount()
    if count > 1 then display = (mine % count) + 1 else display = mine or 1 end
  end)
  local ok, problem = require("Gen3EventWindow").write(path, { project = S.project, path = S.path,
    version = S.version, port = port, token = token, ui = M.snapshot(S), display = display })
  if not ok then server:close(); return false, "Could not prepare the preview: " .. tostring(problem) end
  local args = {}
  if not love.filesystem.isFused() then args[#args + 1] = love.filesystem.getSource() end
  args[#args + 1] = "--map-window"; args[#args + 1] = path
  local called, process, why = pcall(launch or require("EventWindowProcess").start,
    love.filesystem.getExecutablePath(), args)
  if not called or not process then
    server:close(); os.remove(path)
    return false, (tostring(called and why or process):gsub("the event window", "the preview window"))
  end
  host = { S = S, App = App, server = server, token = token, path = path, modPath = S.path,
    process = process, backlog = {}, opened = now(),
    -- what the preview has: changes are found against these
    shadow = Sync.copy(S.project), ui = M.snapshot(S), project = S.project, dirty = false, lastDiff = now(),
    saved = { markDirty = App.markDirty, update = App.update, draw = App.draw, quit = App.quit } }
  local saved = host.saved
  -- a problem in here must never take the editor down with it
  local function guarded(fn)
    local fine, trouble = xpcall(fn, debug.traceback)
    if not fine then
      M.close(S)
      S.status = "Fullscreen preview closed after a problem: " .. tostring(trouble):match("^[^\n]*")
    end
  end
  App.markDirty = function(...)
    if host then host.dirty = true end
    return saved.markDirty(...)
  end
  App.update = function(dt)
    if host then guarded(function() M.pump(S) end) end
    return saved.update(dt)
  end
  App.draw = function()
    local a = saved.draw()
    if host then guarded(function() M.flush(S) end) end
    return a
  end
  App.quit = function()
    local stay = saved.quit()
    if not stay then M.close(S) end
    return stay
  end
  S.status = "Opening the fullscreen preview..."
  return true
end

function M.close(S)
  local h = host
  if not h then return end
  host = nil
  for name, fn in pairs(h.saved) do h.App[name] = fn end
  if h.link then
    h.link:send({ t = "close" })
    h.link:flush()
    h.link:close()
  end
  pcall(h.process.running) -- (lets a finished one be collected)
  pcall(h.process.close)
  pcall(h.server.close, h.server)
  for _, suffix in ipairs({ "", ".tmp" }) do os.remove(h.path .. suffix) end
  if S then S.status = "Fullscreen preview closed" end
end

--- Each frame, before the editor updates: has the preview connected, or gone?
function M.pump(S)
  local h = host
  if S.path ~= h.modPath or not S.project then M.close(S); return end
  if not h.link then
    local sock = h.pending == nil and h.server:accept()
    if sock then h.pending = newLink(sock) end
    local hello = h.pending and h.pending:read()[1]
    if hello then
      if hello.t == "hello" and hello.token == h.token then
        h.link, h.pending = h.pending, nil
        -- what changed here while it was starting
        for _, message in ipairs(h.backlog) do h.link:send(message) end
        h.backlog = nil
        h.ui = M.snapshot(S)
        h.link:send({ t = "ui", ui = h.ui })
        os.remove(h.path)
        S.status = "Fullscreen preview is open. Esc in that window (or Close preview here) closes it."
      else
        h.pending:close(); h.pending = nil
      end
    elseif not h.process.running() or now() - h.opened > 90 then
      M.close(S)
      S.status = "The fullscreen preview did not open"
    end
    return
  end
  h.link:read()
  if h.link.closed then M.close(S) end
end

--- Each frame, after the editor drew: what changed here goes to the preview.
function M.flush(S)
  local h = host
  local function send(message)
    if h.link then h.link:send(message) else h.backlog[#h.backlog + 1] = message end
  end
  local t = now()
  if S.project ~= h.project then h.project, h.dirty = S.project, true end -- (undo swaps the whole project)
  if h.dirty or t - h.lastDiff > 2 then
    local ops = Sync.diff(h.shadow, S.project)
    if #ops > 0 then
      Sync.apply(h.shadow, ops, true)
      send({ t = "ops", ops = ops })
    end
    h.dirty, h.lastDiff = false, t
  end
  local ui = M.snapshot(S)
  if h.link and #Sync.diff(h.ui, ui) > 0 then
    h.ui = ui
    send({ t = "ui", ui = ui })
  end
  if h.link then h.link:flush() end
end

---------------------------------------------------------------- the preview window
local function rebuild(S)
  pcall(function() require("Gen3Workspace").prepare(S) end)
  S._mapNeedsRebuild = S.mapId
  S._liveTilesets = nil
  pcall(function() require("Maps").invalidateCaches(S) end)
  pcall(function() require("SpriteUtil").invalidateIdCache(S) end)
  pcall(function() require("Preview").invalidate() end)
  pcall(function() require("src.world.MapLoader").invalidateAll() end)
end

--- Start the preview window: `path` is what M.open wrote.
function M.load(path)
  local payload = assert(require("Gen3EventWindow").read(path))
  assert(require("Generation").isGen3({ version = payload.version }), "The fullscreen preview needs a Gen 3 project")
  local App = require("App")
  App.load(nil, { version = payload.version, eventWindow = true })
  local S = App.getState()
  S.project = require("State").ensureProjectFields(payload.project)
  S.path, S.version = payload.path, payload.version
  S.tab = "maps"
  S._mapPreviewWindow = true
  require("Gen3ContentAdapter").prepare(S)
  require("Gen3Workspace").prepare(S)
  pcall(function() require("Generation").restoreUnownedLiveMaps(S) end)
  for key, value in pairs(payload.ui or {}) do S[key] = value end

  local link = newLink(assert(require("socket").connect("127.0.0.1", payload.port)))
  link:send({ t = "hello", token = payload.token })
  link:flush()

  -- It only looks: nothing here is an edit, an undo step or a save.
  local History = require("History")
  local function nothing() end
  for _, name in ipairs({ "noteDirty", "beginFrame", "endFrame", "clear", "resetBaseline",
      "beginBatch", "endBatch", "undo", "redo" }) do
    History[name] = nothing
  end
  for _, name in ipairs({ "markDirty", "beginEditBatch", "endEditBatch", "undo", "redo", "save" }) do
    App[name] = nothing
  end
  App.close = function() love.event.quit() end
  App.quit = function() return false end
  require("MapsWorkspace").keypressed = function() return false end

  local update, rebuildAt = App.update, nil
  App.update = function(dt)
    for _, message in ipairs(link:read()) do
      if message.t == "ops" and type(message.ops) == "table" then
        Sync.apply(S.project, message.ops, true)
        S.uiPreviewTick = (S.uiPreviewTick or 0) + 1
        -- more than cells changed: rebuild what the editor derives from the
        -- project, once the burst is over
        if not Sync.cellsOnly(message.ops) then rebuildAt = love.timer.getTime() + 0.12 end
      elseif message.t == "ui" and type(message.ui) == "table" then
        for _, key in ipairs(M.FOLLOWS) do S[key] = message.ui[key] end
      elseif message.t == "close" then
        love.event.quit()
      end
    end
    if link.closed then love.event.quit(); return end
    if rebuildAt and love.timer.getTime() >= rebuildAt then rebuildAt = nil; rebuild(S) end
    return update(dt)
  end
  App.keypressed = function(key)
    if key == "escape" then love.event.quit()
    elseif key == "f11" then love.window.setFullscreen(not love.window.getFullscreen(), "desktop") end
  end

  love.window.setMode(1280, 800, { fullscreen = true, fullscreentype = "desktop", resizable = true,
    minwidth = 480, minheight = 360, vsync = 1, display = tonumber(payload.display) or 1 })
  love.window.setTitle("Map preview - " .. (S.path and (S.path:match("[/\\]([^/\\]+)$") or S.path) or ""))
  S.status = "Map preview: drag to pan, wheel to zoom. F11 leaves fullscreen, Esc closes."
  return App
end

--- What the preview window draws: the map, with the Pan tool.
M.panel = {
  draw = function(S, x, y, w, h, App)
    S.mapWorkspace = true
    S.builderTool, S.mapEditMode = "pan", "map"
    local id = S.mapId or S.builderMapId
    S.mapId, S.builderMapId = id, id
    S.mapPreviewOnly = not (id and S.project.layeredMaps and S.project.layeredMaps[id])
    require("MapBuilder").drawView(S, x, y, w, h, App)
    S.mapPreviewOnly = nil
  end,
}

return M
