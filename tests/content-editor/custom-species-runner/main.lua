local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*,const char*,int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
local cache=os.getenv("APPDATA"):gsub("\\","/").."/LOVE/pokemon-love2d/firered"
assert(lib.PHYSFS_mount(cache,"firered",1)~=0)
local function report(s) local f=assert(io.open(root.."/tests/content-editor/custom-species-runner/result.txt","w"));f:write(s);f:close() end
love.errorhandler=function(e) report(debug.traceback(tostring(e)));return function() return 1 end end
function love.load()
 require("src.core.GameVersion").set("firered")
 local data={};require("Gen3").load(data,function(p) return love.filesystem.read("firered/"..p) end)
 dofile(root.."/tests/content-editor/test_gen3_custom_species.lua")(data,root,lib.PHYSFS_mount)
 local fresh={};require("Gen3").load(fresh,function(p) return love.filesystem.read("firered/"..p) end)
 require("Gen3ContentAdapter").prepare({data=fresh,project=require("State").blankProject("forms_test"),version="firered"})
 dofile(root.."/tests/content-editor/test_gen3_forms.lua")(fresh,root,lib.PHYSFS_mount)
 report("PASS custom species export/reload/identity/encounters/sprites/battle; existing forms regression")
 love.event.quit()
end





