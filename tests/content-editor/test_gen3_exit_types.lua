package.path='tools/content-editor/?.lua;tools/content-editor/panels/?.lua;'..package.path
package.loaded.ModIO={};package.loaded.Preview={}
local L=require('LayeredMap')
local C=require('Gen3Collision')
local W=require('ModWriter')
local modes={'door','cave','stairs','panel','carpet_right','carpet_left','carpet_up','carpet_down','fall','escalator_up','escalator_down','stair_up_right','stair_up_left','stair_down_right','stair_down_left'}
local expected={0x69,0x60,0x61,0x67,0x62,0x63,0x64,0x65,0x66,0x6A,0x6B,0x6C,0x6D,0x6E,0x6F}
local source={cellWidth=#modes,cellHeight=1,layers={},collision={},gen3Collision={},gen3Elevation={},gen3Border={width=0,height=0,mids={}}}
for i,mode in ipairs(modes) do
 source.gen3Collision[i]=255
 source.gen3Elevation[i]=7
 assert(L.setCollision(source,i-1,0,mode),mode)
 assert(source.gen3Collision[i]==nil)
end
assert(not L.setCollision(source,0,0,'invalid'))
source=assert(loadstring('return '..W.encodeLua(source)))()
local behaviors={}
package.loaded['src.core.game3.scripting.interaction_scripts']={behaviors=behaviors}
package.loaded['src.core.game3.tileset_native']={_pairs={}}
package.loaded['src.core.game3.field_view']={draw=function() end}
package.loaded['src.core.game3.collision']={installWarps=function() end}
package.loaded['src.mods.Runtime']={}
local captured
package.loaded['src.core.game3.layout_native']={fromDecoded=function(d) captured=d;return d end}
local canvas={setFilter=function() end}
love={graphics=setmetatable({newCanvas=function() return canvas end},{__index=function() return function() end end})}
local mod={id='exits',events={on=function(_,_,fn) fn({game={data={maps={TEST={}}}}}) end},hooks={wrap=function() end}}
assert(loadstring('return function(mod,layered) '..require('Gen3LayeredRuntime')..' end'))()(mod,{maps={TEST=source},sources={},animations={}})
for i,cell in ipairs(captured.cells) do
 assert(behaviors.editor_exits_TEST[cell.mid]==expected[i],modes[i]..' behavior')
 assert(cell.coll==(i<=2 and 0x71 or 0x72),modes[i]..' passage')
 assert(cell.elev==7)
end
for _,name in ipairs({'Kit','Theme','TilesetExport','FormPane','EventScriptEditor','Gen2Talk','SpeciesPicker'}) do package.loaded[name]={PAL={}} end
local M=require('MapBuilder')
for _,version in ipairs({'firered','leafgreen'}) do
 assert(M.supportsTool({version=version},'exits'))
 assert(not M.supportsTool({version=version},'berry'))
 assert(not M.supportsTool({version=version},'path'))
end
print('PASS: 15 FR/LG exit behaviors paint, serialize, and export with correct passage/elevation; tool visibility verified')
