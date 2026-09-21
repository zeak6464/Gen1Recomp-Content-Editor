local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;"..runtime.."/?.lua;"..package.path
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE"))
local function read(path)
  local f=io.open(cache.."/"..path,"rb");if not f then return end
  local b=f:read("*a");f:close();return b
end
local G,Map,IO=require("Gen3"),require("Gen3Map"),require("ModIO")
require("src.core.GameVersion").set("firered")
local data={};G.load(data,read)
for id,value in pairs(require("Gen3Resources").animations(data)) do
  local ok,err=require("Gen3Resources").checkAnimation(id,value);assert(ok,id..": "..tostring(err))
end
data.maps.FR_PALLET_TOWN.midLayout=assert(Map.layout(data,"FR_PALLET_TOWN"))
local project=require("State").blankProject("native_integration")
project.game="firered"
project.gen3={maps={FR_PALLET_TOWN={objects={},mapScripts={onTransition="EDITOR_ENTER"}},FR_EDITOR_TEST={id="FR_EDITOR_TEST",width=8,height=6,objects={},warps={}}},map_scripts={EDITOR_ENTER={{op="end"}}}}
project.gen3Exact={maps={FR_PALLET_TOWN=true}}
project.gen3Modes={maps={FR_EDITOR_TEST="register"},map_scripts={EDITOR_ENTER="register"}}
project.gen3MapLayouts={FR_EDITOR_TEST={source="FR_PALLET_TOWN",width=8,height=6,blank=true}}
project.gen3Terrain={FR_EDITOR_TEST={[1025]={mid=7,coll=0,elev=3}}}
project.gen3Animations={["moves/1"]={{op="delay",frames=9},{op="end"}}}
project.gen3Assets={["data/generated/gba/chrome/std_rgba.rgba"]={file="assets/test.rgba",width=24,height=24}}
project.gen3Audio={songs={["300"]=301},sounds={["5"]=6},mapSongs={FR_EDITOR_TEST=301}}
local dir="tests/content-editor/gen3-smoke/native-project"
assert(IO.ensureDirectory(dir.."/assets"))
assert(IO.writeText(dir.."/assets/test.rgba",string.rep(string.char(0,255,0,255),24*24)))
if love and love.audio then
  local function u(n,count) local out="";for i=1,count do out=out..string.char(n%256);n=math.floor(n/256) end;return out end
  local pcm=string.rep("\0",16000)
  local wav="RIFF"..u(36+#pcm,4).."WAVEfmt "..u(16,4)..u(1,2)..u(1,2)..u(8000,4)..u(16000,4)..u(2,2)..u(16,2).."data"..u(#pcm,4)..pcm
  assert(IO.writeText(dir.."/assets/silence.wav",wav))
  project.gen3Audio.songs["301"]={file="assets/silence.wav",loop=true}
  project.gen3Audio.songs["302"]={file="assets/silence.wav",loop=false}
  project.gen3Audio.sounds["7"]={file="assets/silence.wav"}
  project.gen3Audio.cries={["151"]={file="assets/silence.wav"}}
end
assert(IO.writeText(dir.."/manifest.json",'{"id":"native_integration","name":"Native integration","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
assert(IO.save(dir,project))
local reopened=assert(IO.load(dir));assert(reopened.gen3MapLayouts.FR_EDITOR_TEST.width==8)
local base={};G.load(base,read)
assert(require("Gen3Mod").load(base,dir,{baseOnly=true}))
assert(#base.maps.FR_PALLET_TOWN.objects>0 and not base.maps.FR_EDITOR_TEST,"The editor must load original records before applying project edits")
local Cache=require("src.import.CacheFs")
Cache._contentEditorBridge=nil
Cache.read=function(path) return read((path:gsub("^firered/",""))) end
local Space=require("src.core.game3.scripting.space")
Space.bundle={events={FR_PALLET_TOWN={objects={{localId=1}},mapScripts={}}}}
local loader,err=require("Gen3Mod").load(data,dir);assert(loader,err)
assert(#data.maps.FR_PALLET_TOWN.objects==0,"Clearing the last object must persist")
local asset=Cache.read("firered/data/generated/gba/chrome/std_rgba.rgba")
assert(asset==string.rep(string.char(0,255,0,255),24*24),"Native asset was not replaced")
local pack=assert(loadstring(assert(Cache.read(require("Gen3Resources").animationPath))))()
assert(pack.moves[1][1].frames==9,"Animation edit did not reach the native pack")
local Audio=require("src.core.game3.audio")
local remapped=loader.hooks:call("editor.gen3.audio.playSong",function(id) return id end,300)
assert(remapped==301)
loader.events:emit("game.ready",{game={data=data}})
for _,e in ipairs(loader:status().errors or {}) do error(tostring(e)) end
local layout=assert(data.maps.FR_EDITOR_TEST.midLayout)
assert(layout.width==8 and layout.height==6 and layout:midAt(1,1)==7 and layout:collAt(0,0)==255)
assert(data.maps.FR_EDITOR_TEST.music==301)
assert(Space.bundle.events.FR_PALLET_TOWN.mapScripts.onTransition=="EDITOR_ENTER")
assert(#Space.bundle.events.FR_PALLET_TOWN.objects==0)
assert(require("src.core.game3.battle.anim").scriptForMove(1)[1].frames==9,"Battle animation host did not consume the edited script")
if love and love.audio then
  Audio._bgmVolume=0;Audio._sfxVolume=0
  assert(Audio.playSong(301));assert(Audio._editorMusic and Audio._bgmSource==Audio._editorMusic)
  assert(Audio._currentSong.id==301 and Audio._editorMusic:isLooping())
  Audio.pauseBgm();assert(Audio._bgmPaused);Audio.resumeBgm();assert(not Audio._bgmPaused)
  assert(Audio.playSe(7));assert(Audio._seMeta[Audio._seSources[#Audio._seSources]].id==7)
  assert(Audio.playCry(151));assert(Audio._crySource and Audio._cryUntil)
  assert(Audio.playFanfare(302));assert(Audio._fanfareActive and Audio._bgmPaused)
  Audio.update(1.1);assert(not Audio._fanfareActive and not Audio._bgmPaused)
  Audio.stopAll();assert(Audio._currentSong==nil)
  Audio.endSession();assert(not Audio._editorMusic)
  for _,e in ipairs(loader:status().errors or {}) do error(tostring(e)) end
end
require("src.mods.Runtime").reset()
assert(Cache.read("firered/data/generated/gba/chrome/std_rgba.rgba")==read("data/generated/gba/chrome/std_rgba.rgba"),"Disabled mods must stop intercepting cache reads")
print("ok native animation/asset/audio exports, map creation, event removal/bindings, loader lifecycle")
return data,project
