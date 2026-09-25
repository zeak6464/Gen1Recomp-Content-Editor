local M={}
M.modes={"deck_horizontal","deck_vertical","entrance_horizontal","entrance_vertical","remove"}
M.labels={deck_horizontal="Deck east/west",deck_vertical="Deck north/south",entrance_horizontal="Entrance east/west",entrance_vertical="Entrance north/south",remove="Remove bridge"}
function M.validate(source)
  for i,c in pairs(source.gen3Bridges or {}) do
    assert(type(i)=="number" and i%1==0 and i>=1 and i<=source.cellWidth*source.cellHeight,"Bridge cell outside map")
    assert(c.kind=="deck" or c.kind=="entrance","Unknown bridge part")
    assert(c.axis=="horizontal" or c.axis=="vertical","Choose a bridge direction")
    if c.kind=="deck" then
      local t=c.tile;assert(t and type(t.source)=="string" and type(t.tile)=="number" and t.tile>=0 and t.tile%1==0,"Choose a bridge deck tile")
    end
  end
end
function M.paint(source,x,y,mode,ref)
  if x<0 or y<0 or x>=source.cellWidth or y>=source.cellHeight then return false end
  local kind,axis=mode:match("^(%a+)_(%a+)$")
  assert(mode=="remove" or ((kind=="deck" or kind=="entrance") and (axis=="horizontal" or axis=="vertical")),"Choose a bridge mode")
  source.gen3Bridges=source.gen3Bridges or {};local index=y*source.cellWidth+x+1
  local old=source.gen3Bridges[index]
  if mode=="remove" then source.gen3Bridges[index]=nil;return old~=nil end
  if kind=="deck" and not ref then return false end
  local tile=kind=="deck" and {source=ref.source,tile=ref.tile} or nil
  if old and old.kind==kind and old.axis==axis and ((not tile and not old.tile) or (tile and old.tile and tile.source==old.tile.source and tile.tile==old.tile.tile)) then return false end
  source.gen3Bridges[index]={kind=kind,axis=axis,tile=tile};return true
end
return M
