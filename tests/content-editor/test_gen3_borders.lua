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
assert(loadfile('tools/content-editor/panels/Gen3Maps.lua'))
assert(loadfile('tools/content-editor/Gen3.lua'))
assert(loadfile('tools/content-editor/ModIO.lua'))
print('PASS: border editing, persistence, emitted runtime wrapping, validation and syntax')
