local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/map-templates-smoke/result.txt","wb"));f:write(message);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  assert(lib.PHYSFS_mount(cache,"event-cache",1)~=0)
  require("src.core.game3.items_data").installPack(dofile(cache.."/data/generated/gba/items/pack.lua"))
  require("src.core.GameVersion").set(os.getenv("POKEPORT_VERSION") or "firered")
  local data={}
  require("Gen3").load(data,function(path)
    local f=io.open(cache.."/"..path,"rb");if not f then return end
    local bytes=f:read("*a");f:close();return bytes
  end,function(path)
    local entries={}
    for _,name in ipairs(love.filesystem.getDirectoryItems("event-cache/"..path)) do
      entries[#entries+1]={name=name,type=love.filesystem.getInfo("event-cache/"..path.."/"..name).type}
    end
    return entries
  end)
  local output=root.."/tests/content-editor/map-templates-smoke"
  dofile(root.."/tests/content-editor/test_gen3_map_templates.lua")(data,root,output,os.getenv("POKEPORT_VERSION") or "firered")
  report("PASS: map templates, native pickup VM, atomic failures, save/reopen and sidebar rendering")
  love.event.quit()
end
