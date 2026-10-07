-- Run the real editor and cache with timings, without writing user preferences.
-- Set EDITOR_TEST_ROOT to the checkout; EDITOR_SWITCH_AUTO=1 runs assertions
-- and exits. Launch with love tests/content-editor/game-switch-smoke.
local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=root.."/runtime/gen1recomp"
local automatic=os.getenv("EDITOR_SWITCH_AUTO")=="1"
local log=assert(io.open(root.."/tests/content-editor/game-switch-smoke/"
  ..(automatic and "result-auto.txt" or "result.txt"),"wb"))
local function record(text) log:write(text.."\n");log:flush() end
local function measured(label, fn)
  return function(...)
    local start=love.timer.getTime()
    local values={fn(...)}
    local elapsed=love.timer.getTime()-start
    if elapsed>.005 then record(string.format("%.4f %s",elapsed,label)) end
    return unpack(values)
  end
end
local App
local sequence={"firered","emerald","ruby","sapphire","leafgreen","emerald"}
local index,waiting,started,idleAt=1,false,nil,nil
local maximumUpdate,maximumDraw=0,0
love.errorhandler=function(err)
  record("FAIL "..debug.traceback(tostring(err)))
  return function() return 1 end
end
function love.load()
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
    ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
  love.filesystem.write=function() return true end
  for name,methods in pairs({DataSource={"apply","hasImportedCache","hasLocalCache","recompHasVersion"},
      Gen3={"load"},Gen3Decode={"decode"},Gen3Workspace={"prepare"},
      Gen3ContentAdapter={"prepare"},Catalog={"scrapeEvents"},["src.core.Data"]={"load"},
      ["src.mods.Schemas"]={"bindGen3"},ModIO={"listMods"}}) do
    local module=require(name)
    for _,method in ipairs(methods) do
      if module[method] then module[method]=measured(name.."."..method,module[method]) end
    end
  end
  App=require("App")
  App.setGameVersion=measured("App.setGameVersion",App.setGameVersion)
  App.requestGameVersion=measured("App.requestGameVersion",App.requestGameVersion)
  App.load(nil,{version="emerald",eventWindow=true})
  if automatic then
    local S=App.getState()
    S.project=require("State").blankProject("switch_test");S.project.game=S.version
    -- Drawing must never invoke the full imported-cache validator.
    require("DataSource").hasImportedCache=function() error("Full validation in UI") end
    started=love.timer.getTime()
  end
  record("READY "..tostring(App.getState().status))
end
function love.update(dt)
  local start=love.timer.getTime()
  measured("update",App.update)(dt)
  maximumUpdate=math.max(maximumUpdate,love.timer.getTime()-start)
  if not automatic then return end
  assert(love.timer.getTime()-started<120,"Switch test timed out")
  local S=App.getState()
  if waiting and not S._gameSwitch then
    local version=sequence[index]
    assert(S.version==version and S.project.game==version,"Target selection did not complete")
    local prefix=require("Generation").gen3MapPrefix(S)
    local hometown=(version=="firered" or version=="leafgreen") and "PALLET_TOWN" or "LITTLEROOT_TOWN"
    assert(S.data.maps[prefix..hometown],"Wrong game maps loaded")
    assert(next(S.data.gen3Pokemon.names) and next(S.data.gen3Text) and next(S.data.gen3Scripts),
      "Missing native Pokemon, text or scripts")
    record("SWITCH OK "..version)
    waiting=false;idleAt=love.timer.getTime();index=index+1
  elseif not waiting and (not idleAt or love.timer.getTime()-idleAt>3.5) then
    if idleAt then assert(not require("Kit").blockClicks,"Inputs stayed blocked after switching") end
    if index>#sequence then
      assert(maximumDraw<.5 and maximumUpdate<.5,"Main thread still stalls during switching")
      record(string.format("PASS repeated real-cache switches; max draw %.4f s, max update %.4f s",maximumDraw,maximumUpdate))
      love.event.quit();return
    end
    local version=sequence[index]
    assert(App.requestGameVersion(version))
    assert(S._gameSwitch and S.version~=version,"Switch must prepare without mutating active data")
    assert(not App.requestGameVersion(version),"Duplicate clicks must not start another job")
    waiting=true
  end
end
function love.draw()
  local start=love.timer.getTime()
  measured("draw",App.draw)()
  maximumDraw=math.max(maximumDraw,love.timer.getTime()-start)
end
function love.mousepressed(...) App.mousepressed(...) end
function love.mousereleased(...) App.mousereleased(...) end
function love.wheelmoved(...) App.wheelmoved(...) end
function love.keypressed(...) App.keypressed(...) end
function love.textinput(...) App.textinput(...) end
function love.quit()
  if not automatic and App.quit() then return true end
  log:close();return false
end
