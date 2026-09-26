package.path='tools/content-editor/?.lua;'..package.path
local C=require('Gen3Collision')
local original=package.loaded.Gen3Map
local cells={{mid=10,coll=255},{mid=11,coll=0x29},{mid=12,coll=0},{mid=12,coll=255}}
package.loaded.Gen3Map={layout=function() return {
  width=4,height=1,cellAt=function(_,x) return cells[x+1] end,
} end}
local data={gen3Native={layouts={TEST={pair='sea'}}}}
assert(C.forRef(data,{source='@runtime:sea',tile=10})=='solid','Blocked sea rock must paint as wall')
assert(C.forRef(data,{source='@runtime:sea',tile=11})=='water','Open sea must stay water')
assert(C.forRef(data,{source='@runtime:sea',tile=12})==nil,'Mixed permissions must not be guessed')
assert(C.forRef(data,{source='@runtime:sea',tile=13})==nil,'Unseen tiles must not be guessed')
assert(C.forRef(data,{source='custom',tile=10})==nil)
package.loaded.Gen3Map=original
print('PASS: blocked tiles, water, ambiguous tiles, unseen tiles, custom art')
