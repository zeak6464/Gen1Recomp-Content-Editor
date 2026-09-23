local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0);assert(lib.PHYSFS_mount(cache,"firered",1)~=0)
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/teachy-smoke/result.txt","wb"));f:write(message);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local function read(path) local f=io.open(cache.."/"..path,"rb");if not f then return end;local b=f:read("*a");f:close();return b end
  local data={};require("src.core.GameVersion").set("firered");require("Gen3").load(data,read)
  local IO=require("ModIO");local E=require("Gen3TeachyTv")
  local S={data=data,version="firered",project=require("State").blankProject("teachy_test"),g3UiMode="teachy"}
  S.project.game="firered";require("Gen3ContentAdapter").prepare(S)
  local count=0
  for _,rows in pairs(E.lines) do for _,row in ipairs(rows) do assert(data.text[row[1]],row[1]);count=count+1 end end
  assert(count==23)
  local id="gTeachyTvText_BattleScript1"
  E.setText(S,id,"Test lesson.\fSecond page for {PLAYER}.")
  E.setText(S,"gTeachyTvString_TeachBattle","Test title")
  local path=root.."/tests/content-editor/teachy-smoke/project"
  assert(IO.ensureDirectory(path));assert(IO.writeText(path.."/manifest.json",'{"id":"teachy_test","name":"Teachy test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  assert(IO.save(path,S.project));local restored=assert(IO.load(path));assert(restored.text[id][1].s=="Test lesson.")
  local fresh={};require("Gen3").load(fresh,read);assert(require("Gen3Mod").load(fresh,path))
  local TV=require("src.core.game3.teachy_tv")
  assert(TV.introPages(0)[1]:find("Test lesson.",1,true))
  assert(TV.menuItems({})[1].label=="Test title")
  require("src.mods.Runtime").reset()
  assert(not TV.introPages(0)[1]:find("Test lesson.",1,true),"Text remained after mod unload")
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  S.g3TeachyDialogue=true
  for _,section in ipairs(E.sections) do
    S.g3TeachySection=section
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
    K.layout(1360,860);K.beginFrame(0,0,false,0)
    require("Gen3UiWorkspace").draw(S,20,50,1320,790,{markDirty=function() error("Viewing changed text") end})
    K.endFrame();love.graphics.setCanvas()
  end
  assert(IO.writeText(root.."/tests/content-editor/teachy-smoke/editor.png",canvas:newImageData():encode("png"):getString()))
  S.g3TeachyDialogue=false
  for _,name in ipairs({"screen","title","end","bg3","static"}) do
    local path="data/generated/gba/teachy_tv/"..name..".rgba"
    S.g3AssetId=path
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
    K.beginFrame(0,0,false,0)
    require("Gen3UiWorkspace").draw(S,20,50,1320,790,{markDirty=function() error("Viewing changed artwork") end})
    K.endFrame();love.graphics.setCanvas()
    assert(S._g3AssetImage,"Missing Teachy TV image: "..name)
    local sizes={screen={240,160},title={240,160},["end"]={240,160},bg3={256,256},static={32,8}}
    assert(S._g3AssetImage:getWidth()==sizes[name][1] and S._g3AssetImage:getHeight()==sizes[name][2])
    assert(IO.writeText(root.."/tests/content-editor/teachy-smoke/"..name..".png",canvas:newImageData():encode("png"):getString()))
  end
  report("PASS: 23 cache-backed lines; save/reload; native lesson and menu overrides; unload; all seven editor sections render")
  love.event.quit()
end
