local root=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;tools/save-editor/?.lua;"..root.."/?.lua;"..package.path
local G,Writer=require("Gen3"),require("ModWriter")
-- Large route data must not overflow the entry function's early-return jump.
local large = {game="firered",gen3Layered={}}
for n=1,3 do
  local cells={}
  for i=1,16000 do cells[i]={source="@runtime:test",tile=i%512} end
  large.gen3Layered["FR_LARGE_"..n]={cellWidth=80,cellHeight=200,
    layers={{cells=cells,export=true}}}
end
local entry=assert(loadstring(G.emit(large,Writer.encodeLua)))()
entry({generation=2})
local layered
entry({generation=3,events={on=function(_,name,callback)
  if name=="game.ready" then
    for i=1,100 do
      local key,value=debug.getupvalue(callback,i)
      if not key then break end
      if key=="layered" then layered=value end
    end
  end
end}})
assert(layered and layered.maps.FR_LARGE_3.layers[1].cells[16000].tile==16000%512)
assert(#layered.maps.FR_LARGE_1.layers[1].cells==16000)
print("ok large Gen3 layered export compiles and preserves map cells")

