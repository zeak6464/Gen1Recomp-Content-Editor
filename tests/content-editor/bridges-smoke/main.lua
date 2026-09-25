local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local game=os.getenv("POKEPORT_VERSION") or "firered"
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local function report(s) local f=assert(io.open(root.."/tests/content-editor/bridges-smoke/result.txt","w"));f:write(s);f:close() end
love.errorhandler=function(e) report(debug.traceback(tostring(e)));return function() return 1 end end
function love.load()
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*,const char*,int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  assert(lib.PHYSFS_mount(cache,game,1)~=0)
  require("src.core.GameVersion").set(game)
  local data={};require("Gen3").load(data,function(p) return love.filesystem.read(game.."/"..p) end)
  dofile(root.."/tests/content-editor/test_gen3_bridges.lua")(data,root,lib.PHYSFS_mount,game)
  report("PASS: bridge entrances, deck edges, underpasses, water, exported drawing planes and persistence")
  love.event.quit()
end



