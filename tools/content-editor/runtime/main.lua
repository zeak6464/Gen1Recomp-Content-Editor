-- Standalone Content Editor entry point. The surrounding source tree is
-- assembled from the pinned Gen1Recomp checkout; only tools/ is editor-owned.
local EditorApp

local function mountPinnedRuntime()
  if not require("tools.content-editor.RuntimeMount").mount() then
    error("Could not find Gen1Recomp.\n\n"
      .. "Use a bundled runtime/gen1recomp folder, set POKEPORT_RECOMP, "
      .. "or choose your Gen1Recomp checkout when asked.\n"
      .. "That folder must contain src/core/GameVersion.lua.")
  end
end

local function addEditorRequirePath()
  local paths = table.concat({
    "tools/content-editor/?.lua",
    "tools/content-editor/panels/?.lua",
    "tools/save-editor/?.lua",
    "tools/save-editor/panels/?.lua",
  }, ";") .. ";"
  if love.filesystem.setRequirePath and love.filesystem.getRequirePath then
    love.filesystem.setRequirePath(paths .. love.filesystem.getRequirePath())
  else
    package.path = love.filesystem.getSource() .. "/" .. paths .. package.path
  end
end

local function packLog(msg)
  local path = (os.getenv("TEMP") or ".") .. "\\pokemonium_pack.log"
  local f = io.open(path, "a")
  if not f then return end
  f:write(tostring(msg) .. "\n")
  f:close()
end

local function argumentAfter(args, wanted)
  local function scan(t)
    if type(t) ~= "table" then return nil end
    for i = -5, 40 do
      if t[i] == wanted then return t[i + 1] end
    end
  end
  return scan(args) or scan(arg)
end

function love.load(args)
  love.graphics.setDefaultFilter("nearest", "nearest")
  mountPinnedRuntime()
  addEditorRequirePath()
  local packRoot = argumentAfter(args, "--pokemonium-pack")
  if packRoot then packLog("packRoot=" .. tostring(packRoot)) end
  local version = os.getenv("POKEPORT_VERSION")
    or (packRoot and "gold") or "red"
  require("src.core.GameVersion").set(version)
  require("src.import.CacheFs").mountVersion(version)
  EditorApp = require("App")
  EditorApp.load(argumentAfter(args, "--mod"), { version = version })
  if packRoot and packRoot ~= "" then
    local ok, err = xpcall(function()
      local pok, perr = require("PokemoniumPack").run(EditorApp, {
        root = packRoot,
        maps = argumentAfter(args, "--pokemonium-maps"),
      })
      if not pok then error(tostring(perr or "Pokemonium pack failed"), 0) end
    end, debug.traceback)
    if not ok then
      packLog("PACK FAILED\n" .. tostring(err))
      error(tostring(err or "Pokemonium pack failed"))
    end
    packLog("pack ok, quitting")
    love.event.quit()
  end
end

function love.update(dt)
  return EditorApp.update(dt)
end
function love.draw() return EditorApp.draw() end
function love.keypressed(key) return EditorApp.keypressed(key) end
function love.textinput(value) return EditorApp.textinput(value) end
function love.mousepressed(x, y, button)
  return EditorApp.mousepressed(x, y, button)
end
function love.mousereleased(x, y, button)
  return EditorApp.mousereleased(x, y, button)
end
function love.wheelmoved(x, y) return EditorApp.wheelmoved(x, y) end
function love.filedropped(file) return EditorApp.filedropped(file) end
function love.quit() return EditorApp.quit() end
