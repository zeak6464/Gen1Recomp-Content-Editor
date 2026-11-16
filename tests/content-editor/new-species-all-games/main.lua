local root = assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\", "/")
local game = assert(os.getenv("GAME"))
local runtime = root .. "/runtime/gen1recomp"
local dir = root .. "/tests/content-editor/new-species-all-games/out/" .. game
package.path = root .. "/tools/content-editor/?.lua;" .. root .. "/tools/content-editor/panels/?.lua;"
  .. root .. "/tools/save-editor/?.lua;" .. runtime .. "/?.lua;" .. package.path
local lines = {}
local cryCheck
local render, finished, afterScreenshot
local function log(s) lines[#lines + 1] = s end
local function report(s)
  log(s)
  local f = assert(io.open(dir .. "/result.txt", "wb"))
  f:write(table.concat(lines, "\n")); f:close()
end
love.errorhandler = function(e)
  report("FAIL " .. debug.traceback(tostring(e)))
  return function() return 1 end
end
function love.load()
  local ffi = require("ffi")
  ffi.cdef("int PHYSFS_mount(const char*,const char*,int); int PHYSFS_unmount(const char*);")
  local lib = ffi.load(root .. "/love/love.dll")
  assert(lib.PHYSFS_mount(root, "", 1) ~= 0)
  assert(lib.PHYSFS_mount(runtime, "", 1) ~= 0)
  -- Read the existing caches; do not change the user's settings or saves.
  local cache = os.getenv("APPDATA"):gsub("\\", "/") .. "/LOVE/pokemon-love2d/" .. game
  assert(lib.PHYSFS_mount(cache, game, 0) ~= 0)
  assert(lib.PHYSFS_mount(cache, "", 0) ~= 0)
  love.filesystem.write = function() return true end
  require("src.core.GameVersion").set(game)
  require("src.import.CacheFs").mountVersion(game)
  local App = require("App")
  App.load(nil, {version = game, eventWindow = true})
  local S = App.getState()
  assert(lib.PHYSFS_mount(cache .. "/data", "data", 0) ~= 0)
  lib.PHYSFS_mount(cache .. "/assets", "assets", 0)
  assert(S.version == game)
  S.project = require("State").ensureProjectFields(require("State").blankProject("new_species_check"))
  S.project.game = game; S.path = dir .. "/mod"; S.tab = "pokemon"
  local gen3 = require("Generation").isGen3(S)
  if gen3 then require("Gen3ContentAdapter").prepare(S) end
  local Kit = require("Kit")
  local button, clicked = Kit.button, false
  Kit.button = function(x,y,w,h,label,...)
    if label == "+ New species" and not clicked then clicked = true; return true end
    return button(x,y,w,h,label,...)
  end
  require("Pokemon").draw(S, 0, 0, 1400, 900, App)
  Kit.button = button
  assert(clicked, "New Species button was not exercised")
  local rec = assert(S.project.pokemon.NEW_MON)
  log("PASS New Species button created unchanged template")
  local IO = require("ModIO")
  assert(IO.ensureDirectory(S.path))
  if os.getenv("CRY_CHECK") == "1" then
    cryCheck = dofile(root .. "/tests/content-editor/new-species-all-games/cries.lua")
    cryCheck.prepare(S, IO, log)
  end
  assert(IO.writeText(S.path .. "/manifest.json", require("src.link.Json").encode({
    id="new_species_check",name="New species check",version="1.0.0",api=2,
    entry="main.lua",games={game},permissions={"engine_internals"},profile="content",
  })))
  assert(IO.save(S.path, S.project))
  log("PASS save/export and project reload")
  assert(IO.load(S.path).pokemon.NEW_MON)
  if not gen3 then
    render = dofile(root .. "/tests/content-editor/new-species-all-games/legacy.lua")(S,game,IO,lib.PHYSFS_mount,cryCheck)
    log("PASS runtime capture storage and new-entry screen")
    return
  end
  assert(lib.PHYSFS_mount(S.path, "mods/new_species_check", 0) ~= 0)
  local fresh = {}
  require("Gen3").load(fresh, S.data._gen3Read)
  local loader, err = require("Gen3Mod").load(fresh, S.path)
  assert(loader, err)
  assert(#fresh._editorGen3Report.rejected == 0)
  loader.events:emit("game.ready", {})
  if cryCheck then cryCheck.verify(S, fresh, log) end
  local P = require("src.core.game3.pokemon")
  P.install(P._cache)
  assert(P.speciesFromName("NEW_MON") == rec.index)
  assert(P.national(rec.index) == rec.dex)
  assert(P.speciesFromNational(rec.dex) == rec.index, "dex number resolves to a reserved placeholder")
  assert(P.frontPic(rec.index).image and P.backPic(rec.index).image)
  log("PASS runtime registration, species/dex identity and template sprites")
  local session = {version=game,party={},dex=require("src.core.game3.dex").new(),playerName="TEST",trainerId=1}
  local ok, _, mon = require("src.core.game3.party").giveMon(session, rec.index, 5)
  assert(ok and mon.species == rec.index)
  session.party = {}
  session.dex = require("src.core.game3.dex").new()
  session.dex.nationalUnlocked = true
  local result = require("src.core.game3.battle.catching").storeCaught(session,{mon=mon},4)
  assert(result and result.firstTimeCaught)
  assert(require("src.core.game3.dex").isCaught(session.dex,rec.index))
  log("PASS capture storage and first-catch dex flag")
  if game == "firered" or game == "leafgreen" then
    local Dex = require("src.ui.game3.pokedex")
    Dex.showRegistration(rec.index, {session=session})
    for _=1,120 do Dex.update(1/60); Dex.draw() end
    render = Dex.draw
  else
    local Dex = require("src.ui.game3.rse.pokedex")
    local returned
    Dex.showCaughtMon(rec.index, {session=session,personality=mon.personality,onDone=function(result) returned=result end})
    for _=1,180 do Dex.Host.update(1/60); Dex.Host.draw() end
    local view = assert(Dex.active(), "caught view closed early")
    assert(view.shown and view.fn == "caughtInput", "caught view did not finish opening: " .. tostring(view.fn) .. "/" .. tostring(view.state))
    render = Dex.Host.draw
    afterScreenshot=function()
      Dex.frame(view,{new={b=true}})
      for _=1,90 do Dex.Host.update(1/60) end
      assert(returned and returned.species==rec.index and returned.sprite.img,"registration return lost caught sprite")
      log("PASS registration exit returns custom species and sprite")
    end
  end
end
function love.draw()
  if not render or finished then return end
  love.graphics.setCanvas(); love.graphics.setShader(); love.graphics.setScissor(); love.graphics.origin()
  render(); finished=true
  local IO = require("ModIO")
  love.graphics.captureScreenshot(function(data)
    IO.writeText(dir .. "/caught.png",data:encode("png"):getString())
    if afterScreenshot then afterScreenshot() end
    report("PASS capture Pokédex registration rendered")
    if cryCheck then cryCheck.finish(report) else love.event.quit() end
  end)
end
function love.update(dt)
  if cryCheck then cryCheck.update(dt) end
end
