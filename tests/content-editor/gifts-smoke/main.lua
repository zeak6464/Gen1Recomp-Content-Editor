local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0);assert(lib.PHYSFS_mount(cache,"firered",1)~=0)
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/gifts-smoke/result.txt","wb"));f:write(message);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local function read(path) local f=io.open(cache.."/"..path,"rb");if not f then return end;local b=f:read("*a");f:close();return b end
  local data={};require("src.core.GameVersion").set("firered");require("Gen3").load(data,read)
  dofile(root.."/tests/content-editor/test_gen3_offline_gifts.lua")(data,root)
  dofile(root.."/tests/content-editor/test_gen3_safari.lua")(data,root)
  local S={version="gold",data={items={},pokemon={},maps={}},project=require("State").blankProject("decorations_test")}
  require("src.core.GameVersion").set("gold")
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  local App={markDirty=function() error("Viewing decorations changed the project") end}
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Gen2Decorations").draw(S,20,50,1320,790,App);K.endFrame();love.graphics.setCanvas()
  assert(require("ModIO").writeText(root.."/tests/content-editor/gifts-smoke/decorations.png",canvas:newImageData():encode("png"):getString()))
  S.project.trainerHouse=require("TrainerHouseEditor").defaults();S.eventsMode="trainerhouse"
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.beginFrame(0,0,false,0)
  require("Events").draw(S,20,50,1320,790,App);K.endFrame();love.graphics.setCanvas()
  assert(require("ModIO").writeText(root.."/tests/content-editor/gifts-smoke/trainer-house.png",canvas:newImageData():encode("png"):getString()))
  S.version="red";S.project.game="red";S.project.trainerHouse=nil;S.project.safariSettings=require("SafariSettings").defaults(1);S.rulesMode="safari"
  require("src.core.GameVersion").set("red")
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.beginFrame(0,0,false,0)
  require("Rules").draw(S,20,50,1320,790,App);K.endFrame();love.graphics.setCanvas()
  assert(require("ModIO").writeText(root.."/tests/content-editor/gifts-smoke/safari-gen1.png",canvas:newImageData():encode("png"):getString()))
  report("PASS: real FireRed loader/VM gifts; Safari load/unload and saved allowances; gift, decoration, Safari and Trainer House UI renders")
  love.event.quit()
end
