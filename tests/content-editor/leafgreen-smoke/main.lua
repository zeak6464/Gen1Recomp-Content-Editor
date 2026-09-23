local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0);assert(lib.PHYSFS_mount(cache,"leafgreen",1)~=0)
local function report(text)
  local f=assert(io.open(root.."/tests/content-editor/leafgreen-smoke/result.txt","wb"));f:write(text);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local Version=require("src.core.GameVersion");Version.set("leafgreen")
  assert(Version.generation()==3 and Version.cachePrefix()=="leafgreen/")
  local Generation=require("Generation")
  assert(Generation.num({version="leafgreen"})==3 and Generation.engine({version="leafgreen"})=="game3")
  assert(Generation.manifestGames({version="leafgreen"})[1]=="leafgreen")
  local IO=require("ModIO");local Json=require("src.link.Json")
  local data={};require("Gen3").load(data,function(path) return IO.readText(cache.."/"..path) end)
  local map=assert(data.maps.FR_PALLET_TOWN)
  assert(map.width==24 and map.height==20)
  local mon=assert(require("Gen3").catalog(data,"pokemon").BULBASAUR)
  assert(mon.baseStats.hp==45)
  local dir=root.."/tests/content-editor/leafgreen-smoke/project"
  assert(IO.ensureDirectory(dir))
  assert(IO.writeText(dir.."/manifest.json",Json.encode({id="leafgreen_test",name="LeafGreen test",version="1.0.0",entry="main.lua",games={"leafgreen"}})))
  local p=require("State").blankProject("leafgreen_test");p.game="leafgreen";p.gen3={pokemon={BULBASAUR={baseStats={hp=47}}}}
  local S={version="leafgreen",project=p,data=data,path=dir}
  require("Gen3Workspace").prepare(S)
  assert(require("Gen3Workspace").convert(S,"FR_PALLET_TOWN"))
  assert(require("LayeredMap").compileProject(S))
  assert(IO.save(dir,p,"leafgreen"))
  local loaded=assert(IO.load(dir));assert(loaded.game=="leafgreen")
  assert(IO.authoringGame(loaded,dir)=="leafgreen")
  local loader,err=require("Gen3Mod").load(data,dir);assert(loader,err)
  assert(require("Gen3").catalog(data,"pokemon").BULBASAUR.baseStats.hp==47)
  local flags={modsByVersion={firered={old=true},leafgreen={old=true}}}
  require("PlaytestOptions").selectOnly(flags,"leafgreen_test","leafgreen")
  assert(flags.modsByVersion.leafgreen.leafgreen_test and flags.modsByVersion.firered.old)
  assert(require("PlaytestPaths").windowsLaunch("love.exe",runtime,"leafgreen"):find("--game=leafgreen",1,true))
  local found=false;for _,id in ipairs(require("Cartkit").BASES) do if id=="leafgreen" then found=true end end;assert(found)
  local bytes,reason=require("Gen3Rom").open(S);assert(bytes==nil and reason:find("supplementary",1,true))
  data._g3RomBytes="FireRed cached bytes"
  assert(require("Gen3Rom").open(S)==nil,"LeafGreen used cached FireRed bytes")
  data._g3RomBytes=nil
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  S.dataPrefs={mode="recomp",recompRoot=runtime};S.dataSource="recomp"
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Project").draw(S,20,20,1320,800,{dataVersion="leafgreen",markDirty=function() error("Viewing changed project") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/leafgreen-smoke/project.png",canvas:newImageData():encode("png"):getString()))
  local DS=require("DataSource")
  local loadPrefs,savePrefs=DS.loadPrefs,DS.savePrefs
  DS.loadPrefs=function() return {mode="recomp",recompRoot=runtime,lastVersion="leafgreen"} end
  DS.savePrefs=function() end -- exercise loading without changing user settings
  local source=DS.apply({version="leafgreen"})
  DS.loadPrefs,DS.savePrefs=loadPrefs,savePrefs
  assert(source=="recomp","LeafGreen linked-cache fallback failed: "..tostring(source))
  assert(require("src.core.Data").maps.FR_PALLET_TOWN)
  report("PASS: real LeafGreen cache/maps/species; Gen 3 map compile; save/reopen; native mod loader HP edit; version-specific playtest; cart base; ROM edition guard; Project UI")
  love.event.quit()
end
