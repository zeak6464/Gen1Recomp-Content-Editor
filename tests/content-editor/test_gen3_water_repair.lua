package.path='tools/content-editor/?.lua;'..package.path
package.loaded['src.import.gba.map_catalog']={slotKeyFor=function() return '3_5' end}
local R=require('Gen3WaterCollision')
local function raw(mid,blocked) local n=mid+blocked*1024;return string.char(n%256,math.floor(n/256)) end
local data={_gen3Read=function() return raw(10,1)..raw(11,0)..raw(12,1)..raw(13,1) end}
local layout={width=4,height=1,pair='sea',cells={{mid=10,coll=41},{mid=11,coll=41},{mid=12,coll=255},{mid=13,coll=255}}}
R.repair(data,'TEST',layout)
assert(layout.cells[1].coll==255 and layout.cells[2].coll==41)
package.loaded.Gen3Map={layout=function() return layout end}
local source={cellWidth=4,cellHeight=1,collision={'water','water','water','water'},
  gen3Collision={41,41,41},layers={{cells={}}}}
for i=1,4 do source.layers[1].cells[i]={source='@runtime:sea',tile=9+i} end
R.migrate(data,'TEST',source)
assert(source.collision[1]=='solid','Old cache water was not repaired')
assert(source.collision[2]=='water','Open sea changed')
assert(source.collision[3]=='solid','Old project with refreshed cache was not repaired')
assert(source.collision[4]=='water','Explicit user collision was overwritten')
print('PASS: raw blocked water, old projects, refreshed caches, explicit edits')
