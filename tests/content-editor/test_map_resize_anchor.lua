package.path="tools/content-editor/?.lua;"..package.path
package.loaded.ModIO={}
package.loaded.Preview={}
package.loaded.TilePixels={}
local M=require("LayeredMap")
local function fixture()
  local cells,collision,elevation={},{},{}
  for i=1,16 do cells[i]={tile=i};collision[i]="walk";elevation[i]=i end
  local source={cellWidth=4,cellHeight=4,layers={{cells=cells}},collision=collision,
    gen3Elevation=elevation,visualObjects={{x=1,y=1,width=1,height=1}}}
  return {layeredMaps={TEST=source},maps={TEST={objects={{x=1,y=1}},coordEvents={{x=0,y=0}}}},mapWarpNodes={}}
end
for _,anchor in ipairs({"top-left","top-right","bottom-left","bottom-right"}) do
  local p=fixture();local s=p.layeredMaps.TEST
  local dx=anchor:find("right") and 2 or 0
  local dy=anchor:find("bottom") and 2 or 0
  assert(M.resizeMap(p,"TEST",6,6,anchor))
  assert(s.layers[1].cells[dy*6+dx+1].tile==1)
  assert(s.gen3Elevation[dy*6+dx+1]==1)
  assert(s.collision[dy*6+dx+1]=="walk")
  assert(p.maps.TEST.objects[1].x==1+dx and p.maps.TEST.objects[1].y==1+dy)
  assert(s.visualObjects[1].x==1+dx and s.visualObjects[1].y==1+dy)
  assert(M.resizeMap(p,"TEST",4,4,anchor))
  assert(s.layers[1].cells[1].tile==1 and s.layers[1].cells[16].tile==16)
  assert(p.maps.TEST.objects[1].x==1 and p.maps.TEST.objects[1].y==1)
end
local p=fixture()
local ok,removed=M.resizeMap(p,"TEST",2,2,"bottom-right")
assert(ok and removed==2 and #p.maps.TEST.objects==0 and #p.maps.TEST.coordEvents==0)
assert(p.layeredMaps.TEST.layers[1].cells[1].tile==11)
assert(#p.layeredMaps.TEST.visualObjects==0)
print("Map resize anchor tests passed")
