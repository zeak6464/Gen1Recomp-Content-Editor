local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE"))
local data={}
require("src.core.GameVersion").set("firered")
require("Gen3").load(data,function(path)
  local f=io.open(cache.."/"..path,"rb");if not f then return end
  local s=f:read("*a");f:close();return s
end)
local C=require("Gen3Collision")
local S={data=data,project={maps={},layeredMaps={}},version="firered"}
local maps,cells,repairs=0,0,0
for id in pairs(data.maps) do
  local layout=assert(require("Gen3Map").layout(data,id))
  for _ in pairs(layout._editorWaterRepairs or {}) do repairs=repairs+1 end
  local source=assert(require("Gen3Workspace").source(S,id))
  for i=1,layout.width*layout.height do
    local cell=layout:cellAt((i-1)%layout.width,math.floor((i-1)/layout.width))
    assert(source.collision[i]==C.mode(cell.coll),id..":"..i)
    assert(C.resolve(source.collision[i],source.gen3Collision[i],123)==cell.coll)
    assert(source.gen3Elevation[i]==cell.elev)
    cells=cells+1
  end
  maps=maps+1
end
-- Execute the actual exported runtime with rendering stubbed out.
local behaviors={native={[0]=0x10}}
package.loaded["src.core.game3.scripting.interaction_scripts"]={behaviors=behaviors}
package.loaded["src.core.game3.tileset_native"]={_pairs={},get=function() return {} end}
package.loaded["src.core.game3.field_view"]={draw=function() end}
package.loaded["src.core.game3.collision"]={installWarps=function() end}
package.loaded["src.mods.Runtime"]={}
local canvas={setFilter=function() end}
love={graphics=setmetatable({newCanvas=function() return canvas end},{__index=function() return function() end end})}
local source={cellWidth=11,cellHeight=1,layers={{cells={[11]={source="@runtime:native",tile=1}}}},baseTileset="native",
  gen3Border={width=0,height=0,mids={}},
  collision={"water","grass","ledge_right","ledge_left","ledge_up","ledge_down","door","walk","solid","water","walk"},
  gen3Collision={[10]=0x29,[11]=0},gen3Elevation={[10]=7},gen3Behavior={[11]=0x66}}
local expected={0x29,0x18,0xA0,0xA1,0xA2,0xA3,0x71,0,255,0x29,0}
local expectedBeh={0x10,2,0x38,0x39,0x3A,0x3B,0x69,0,0,0,0x66}
local mod={id="test",events={on=function(_,_,fn) fn({game={data={maps={TEST={}}}}}) end},hooks={wrap=function() end}}
local captured
local Layout=require("src.core.game3.layout_native")
package.loaded["src.core.game3.layout_native"]={fromDecoded=function(d) captured=d;return Layout.fromDecoded(d) end}
local fn=assert(loadstring("return function(mod,layered) "..require("Gen3LayeredRuntime").." end"))()
fn(mod,{maps={TEST=source},sources={},animations={}})
for i,c in ipairs(captured.cells) do
  assert(c.coll==expected[i],"Export collision "..i)
  assert(behaviors.editor_test_TEST[c.mid]==expectedBeh[i],"Export behavior "..i)
end
assert(captured.cells[10].elev==7)
local L=require("LayeredMap")
-- Painting uses this shared lookup for single tiles and multi-tile stamps.
local sea=assert(require("Gen3Map").layout(data,"FR_ROUTE_21_NORTH"))
local blocked,water=0,0
for i=1,sea.width*sea.height do
  local cell=sea:cellAt((i-1)%sea.width,math.floor((i-1)/sea.width))
  local mode=L.collisionForRef(S,{source="@runtime:"..sea.pair,tile=cell.mid})
  if mode=="solid" then blocked=blocked+1;assert(C.mode(cell.coll)=="solid") end
  if mode=="water" then water=water+1;assert(cell.coll==0x29) end
end
assert(blocked>0 and water>0,"Sea route needs distinct blocked and surfable defaults")
assert(L.setCollision(source,9,0,"walk"))
assert(source.gen3Collision[10]==nil,"Explicit paint must replace native passage")
assert(C.resolve("walk",nil,0x10)==0)
print(string.format("PASS: %d FireRed maps / %d cells preserve collision and elevation; painted runtime collisions and directions verified",maps,cells))
print("Blocked water cells recovered from raw ROM permissions: "..repairs)

