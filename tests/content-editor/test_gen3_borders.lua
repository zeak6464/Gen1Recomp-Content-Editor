local runtime=assert(os.getenv('POKEPORT_RECOMP'))
package.path='tools/content-editor/?.lua;'..runtime..'/?.lua;'..package.path
local Map=require('Gen3Map')
local Layout=require('src.core.game3.layout_native')
local base=Layout.fromDecoded({width=1,height=1,cells={{mid=3,coll=0,elev=0}},borderWidth=2,borderHeight=2,borderMids={1,2,3,4}},'FR_TEST')
local project={game='firered'}
assert(Map.paintBorder(project,'FR_TEST',base,1,0,99))
assert(not Map.paintBorder(project,'FR_TEST',base,1,0,99))
assert(not Map.paintBorder(project,'FR_TEST',base,2,0,99))
assert(base.borderMids[2]==2)
assert(Map.borderLayout(project,'FR_TEST',base):cellAt(1,0).mid==99)
local Writer=require('ModWriter')
local reopened=assert(loadstring(Writer.serializeProject(project)))()
assert(reopened.gen3Borders.FR_TEST.borderMids[2]==99)
local function encode(v)
 if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
 local t={};for k,x in pairs(v) do t[#t+1]='['..encode(k)..']='..encode(x) end
 return '{'..table.concat(t,',')..'}'
end
package.loaded['src.core.game3.scripting.space']={}
local out={};Map.emit(reopened,encode,out)
local handler
local run=assert(loadstring('local mod=...\n'..table.concat(out,'\n')))
run({events={on=function(_,event,fn) assert(event=='game.ready');handler=fn end}})
handler({game={data={maps={FR_TEST={midLayout=base}}}}})
assert(base:midAt(-1,0)==99 and base:midAt(3,0)==99)
assert(base:collAt(-1,0)==255 and base:midAt(0,0)==3)
assert(Map.paintBorder(project,'FR_TEST',base,0,0,5))
project.gen3Borders.FR_TEST.borderMids[1]=1024
assert(not pcall(Map.emit,project,encode,{}))
local custom={game='firered',maps={FR_CUSTOM={id='FR_CUSTOM'}},layeredMaps={FR_CUSTOM={id='FR_CUSTOM',cellWidth=2,cellHeight=2,
 baseTileset='PAIR',layers={{cells={
  {tile=7},{tile=8},{tile=9},{tile=10},
 }}},gen3Collision={[1]=24},gen3Elevation={[1]=3},
 gen3Border={width=2,height=1,mids={4,5}}}}}
local customLayout=assert(Map.layout({},'FR_CUSTOM',custom))
assert(customLayout.width==2 and customLayout.height==2 and customLayout.pair=='PAIR')
assert(customLayout:cellAt(0,0).mid==7 and customLayout:cellAt(0,0).coll==24 and customLayout:cellAt(0,0).elev==3)
assert(customLayout.borderWidth==2 and customLayout.borderMids[2]==5)
assert(Map.paintBorder(custom,'FR_CUSTOM',customLayout,1,0,12))
assert(custom.gen3Borders.FR_CUSTOM.borderMids[2]==12)
assert(custom.layeredMaps.FR_CUSTOM.gen3Border.mids[2]==12)
assert(custom.maps.FR_CUSTOM._gen3Border.mids[2]==12)
assert(Map.setBorderTileset(custom,'FR_CUSTOM',customLayout,'OTHER_PAIR'))
assert(Map.borderLayout(custom,'FR_CUSTOM',customLayout).pair=='OTHER_PAIR')
assert(custom.layeredMaps.FR_CUSTOM.baseTileset=='PAIR')
assert(custom.layeredMaps.FR_CUSTOM.gen3Border.pair=='OTHER_PAIR')
assert(custom.maps.FR_CUSTOM._gen3Border.pair=='OTHER_PAIR')
assert(not Map.setBorderTileset(custom,'FR_CUSTOM',customLayout,'OTHER_PAIR'))
local saved=assert(loadstring(Writer.serializeProject(custom)))()
assert(Map.layout({},'FR_CUSTOM',saved).borderPair=='OTHER_PAIR')
assert(Map.resizeBorder(custom,'FR_CUSTOM',customLayout,3,2))
assert(custom.gen3Borders.FR_CUSTOM.borderWidth==3 and custom.gen3Borders.FR_CUSTOM.borderHeight==2)
assert(custom.gen3Borders.FR_CUSTOM.borderMids[1]==4)
assert(custom.gen3Borders.FR_CUSTOM.borderMids[2]==12)
assert(custom.gen3Borders.FR_CUSTOM.borderMids[3]==4)
assert(custom.gen3Borders.FR_CUSTOM.borderMids[5]==12)
assert(custom.layeredMaps.FR_CUSTOM.gen3Border.width==3)
assert(custom.maps.FR_CUSTOM._gen3Border.height==2)
assert(custom.layeredMaps.FR_CUSTOM.gen3Border.pair=='OTHER_PAIR')
assert(not Map.resizeBorder(custom,'FR_CUSTOM',customLayout,0,2))
assert(loadfile('tools/content-editor/panels/Gen3Maps.lua'))
assert(loadfile('tools/content-editor/Gen3.lua'))
assert(loadfile('tools/content-editor/ModIO.lua'))
print('PASS: border editing, persistence, emitted runtime wrapping, validation and syntax')
