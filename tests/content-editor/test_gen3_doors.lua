local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local Layout=require("src.core.game3.layout_native")
local Doors=require("src.core.game3.doors")
local cache=os.getenv("POKEPORT_GEN3_CACHE")
if cache then
  Doors._manifest=assert(loadfile(cache.."/data/generated/gba/doors/manifest.lua"))()
  Doors._manifestLoaded=true
end
local Runtime=require("src.mods.Runtime")
local hooks=require("src.mods.Hooks").new()
Runtime.hooks=hooks
local native={image={},cols=8}
package.loaded["src.core.game3.tileset_native"]={_pairs={},get=function() return native end,
  slotFor=function(_,mid) return mid end,quad=function() return {} end}
package.loaded["src.core.game3.scripting.interaction_scripts"]={behaviors={}}
package.loaded["src.core.game3.field_view"]={draw=function() end}
local Collision=require("src.core.game3.collision")
local nativeDoorLookup=Doors.getDoorEntryAt
Doors.getDoorEntryAt=function(mapId,x,y)
  local layout=Doors._layoutCache[mapId]
  if layout then
    Collision.behaviorOn({midLayout=layout,pair=layout.pair},x,y)
  end
  return nativeDoorLookup(mapId,x,y)
end
local canvas={setFilter=function() end}
love={graphics=setmetatable({newCanvas=function() return canvas end},{__index=function() return function() end end})}
local function ref(pair,mid) return {source="@runtime:"..pair,tile=mid} end
local source={cellWidth=5,cellHeight=1,baseTileset="pallet",gen3Border={width=0,height=0,mids={}},
  collision={"door","door","door","walk","door"},layers={
    {cells={ref("pallet",0x2A3),ref("pallet",0x62),ref("viridian",0x299),ref("pallet",0),ref("pallet",0x299)}},
    {export=false,cells={ref("pallet",0)}}}}
local maps={FR_TEST={}}
local vanilla=Layout.fromDecoded({width=1,height=1,cells={{mid=0x2A3,coll=0x71,elev=3}}},"FR_VANILLA","pallet")
maps.FR_VANILLA={midLayout=vanilla,pair="pallet"}
package.loaded["src.core.game3.runtime"]={_game={data={maps=maps}}}
-- This fixture uses the runtime's real fallback door catalog and pair matching.
assert(Doors.getDoorEntryAt("FR_VANILLA",0,0).tile=="Pallet")
local mod={id="door_test",events={on=function(_,_,fn) fn({game={data={maps=maps}}}) end},
  hooks={wrap=function(_,name,fn) hooks:wrap(name,fn,0,"door_test") end}}
local run=assert(loadstring("return function(mod,layered) "..require("Gen3LayeredRuntime").." end"))()
run(mod,{maps={FR_TEST=source},sources={},animations={}})
assert(maps.FR_TEST.midLayout:midAt(0,0)~=0x2A3,"Test must renumber door tiles")
assert(Doors.getDoorEntryAt("FR_TEST",0,0).tile=="Pallet","Renumbered house door lost")
assert(Doors.getDoorEntryAt("TEST",1,0).tile=="SlidingSingle","Sliding door lost")
assert(Doors.getDoorEntryAt("MAP_TEST",2,0).tile=="Viridian","Mixed tileset door lost")
assert(Doors.getSoundForWarp("FR_TEST",1,0,nil,true)==Doors.SOUND_SLIDING)
assert(Doors.getDoorEntryAt("FR_TEST",3,0)==nil,"Ground became a door")
assert(Doors.getDoorEntryAt("FR_TEST",4,0)==nil,"Wrong tileset door accepted")
assert(Doors.getDoorEntryAt("FR_TEST",5,0)==nil)
assert(Doors.getDoorEntryAt("FR_VANILLA",0,0).tile=="Pallet","Unedited door changed")
-- Native door implementations can inspect collision behavior on the lookup
-- layout. A partial cache entry with no width/height crashes behaviorOn.
local behaviors=require("src.core.game3.scripting.interaction_scripts").behaviors
behaviors.pallet={[0x2A3]=0x69,[0x62]=0x69}
behaviors.viridian={[0x299]=0x69}
for key,layout in pairs(Doors._layoutCache) do
  if key:match("^editor_door_") then
    assert(layout.width==1 and layout.height==1,"Door layout lacks bounds")
    local map={midLayout=layout,pair=layout.pair}
    assert(Collision.behaviorOn(map,0,0)==behaviors[layout.pair][layout:midAt(0,0)])
    assert(Collision.behaviorOn(map,1,0)==nil,"Door layout has incorrect bounds")
  end
end
maps.FR_INSIDE={warps={{x=2,y=3,destMap="FR_TEST",destWarp=1}}}
maps.FR_TEST.warps={{x=0,y=0,destMap="FR_INSIDE",destWarp=1}}
local game={currentMap="FR_TEST",data={maps=maps}}
Collision._warps={[0]=maps.FR_TEST.warps[1]}
local entrance=assert(Collision.isDoorWarp(game,0,0),"Edited entrance not recognized")
assert(entrance.destMap=="FR_INSIDE" and entrance.destX==2 and entrance.destY==3)
game.currentMap="FR_INSIDE"
Collision._warps={[3*1024+2]=maps.FR_INSIDE.warps[1]}
local exit=assert(Collision.isExitWarp(game,2,3),"Return to edited door not recognized")
assert(exit.destMap=="FR_TEST" and exit.destX==0 and exit.destY==0)
-- A fresh export can move a door to a different cell without ROM coordinates.
source.layers[1].cells[1],source.layers[1].cells[4]=source.layers[1].cells[4],source.layers[1].cells[1]
hooks:removeOwner("door_test")
run(mod,{maps={FR_TEST=source},sources={},animations={}})
assert(Doors.getDoorEntryAt("FR_TEST",0,0)==nil)
assert(Doors.getDoorEntryAt("FR_TEST",3,0).tile=="Pallet","Moved door lost")
Runtime.reset()
assert(Doors.getDoorEntryAt("FR_VANILLA",0,0).tile=="Pallet","Reset retained mod hook")
print("PASS: exported Gen 3 doors preserve native identity, sound, moved locations, tileset matching and vanilla lookup")
