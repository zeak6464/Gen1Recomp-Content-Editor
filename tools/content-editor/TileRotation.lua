-- Bake a rotated brush as a reusable source; existing painted cells stay intact.
local M={}
function M.rotate(S,direction)
  assert(S.path and S.project,"Open a mod before rotating tiles")
  local L,IO=require("LayeredMap"),require("ModIO")
  local stamp=S.builderStamp
  local cells=stamp and stamp.cells or {{dx=0,dy=0,tile=S.builderTile or 0}}
  local sourceId=stamp and stamp.source or S.builderSourceId
  local source=assert(L.sourceDescriptor(S,sourceId),"Choose a tile first")
  local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
  for _,c in ipairs(cells) do minX=math.min(minX,c.dx);minY=math.min(minY,c.dy);maxX=math.max(maxX,c.dx);maxY=math.max(maxY,c.dy) end
  local cols,rows=maxX-minX+1,maxY-minY+1
  assert(cols>0 and rows>0 and cols<=128 and rows<=128,"Choose a brush no larger than 128 by 128 tiles")
  local canvas=love.graphics.newCanvas(rows*16,cols*16)
  local previous=love.graphics.getCanvas();love.graphics.push("all")
  local ok,err=xpcall(function()
    love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.setScissor();love.graphics.setShader();love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1)
    if direction==1 then love.graphics.translate(rows*16,0);love.graphics.rotate(math.pi/2)
    else love.graphics.translate(0,cols*16);love.graphics.rotate(-math.pi/2) end
    for _,c in ipairs(cells) do assert(L.drawSourceTile(S,source,c.tile,(c.dx-minX)*16,(c.dy-minY)*16,16,1,S.builderMapId),"Cannot render selected tile") end
  end,debug.traceback)
  love.graphics.setCanvas(previous);love.graphics.pop();assert(ok,err)
  -- Generated assets survive history pruning so redo can restore their references.
  local n=S.project.nextRotatedTile or 1;local rel
  repeat rel="assets/mapbuilder/rotations/rotated_"..n..".png";n=n+1 until not IO.readText(S.path.."/"..rel)
  assert(IO.ensureDirectory(S.path.."/assets/mapbuilder/rotations"))
  assert(IO.writeText(S.path.."/"..rel,canvas:newImageData():encode("png"):getString()))
  local result=assert(L.addTileSource(S.project,"ROTATED_"..(n-1),rel,rows*16,cols*16));result.colorMode="true_color"
  local rotated={}
  for _,c in ipairs(cells) do
    local x,y=c.dx-minX,c.dy-minY;local nx,ny
    if direction==1 then nx,ny=rows-1-y,x else nx,ny=y,cols-1-x end
    rotated[#rotated+1]={dx=nx,dy=ny,tile=ny*rows+nx}
  end
  S.project.nextRotatedTile=n;S.builderSourceId=result.id;S.builderTile=rotated[1].tile
  S.builderStamp={source=result.id,cells=rotated};S.builderTool="pencil"
  return result
end
function M.rotateSelection(S,map,direction,App)
  assert(direction==1 or direction==-1,"Choose left or right")
  local L=require("LayeredMap")
  local layer=math.max(1,math.min(S.builderLayer or 1,#map.layers))
  local changes,seen={},{}
  for _,rect in ipairs(S.builderSelections or {}) do
    for y=math.max(0,rect.y0),math.min(map.cellHeight-1,rect.y1) do
      for x=math.max(0,rect.x0),math.min(map.cellWidth-1,rect.x1) do
        local key=y*map.cellWidth+x
        local ref=L.getCell(map,layer,x,y)
        if ref and not seen[key] then changes[#changes+1]={x=x,y=y,ref=ref};seen[key]=true end
      end
    end
  end
  assert(#changes>0,"Use Select to choose a placed tile on the active layer first")
  -- Prepare graphics before changing the map, so a failed render leaves cells intact.
  local staged={};for k,v in pairs(S) do staged[k]=v end
  staged.project=require("src.mods.Merge").deepCopy(S.project)
  local refs={}
  for _,change in ipairs(changes) do
    local key=change.ref.source..":"..change.ref.tile
    if not refs[key] then
      staged.builderStamp=nil;staged.builderSourceId=change.ref.source;staged.builderTile=change.ref.tile
      local source=M.rotate(staged,direction);refs[key]={source=source.id,tile=0}
    end
    change.after=refs[key]
  end
  App.beginEditBatch()
  S.project.mapTileSources=staged.project.mapTileSources
  S.project.nextRotatedTile=staged.project.nextRotatedTile
  for _,change in ipairs(changes) do L.setCell(map,layer,change.x,change.y,change.after) end
  App.markDirty();App.endEditBatch()
  S.status="Rotated "..#changes.." selected map tile(s)"
  return #changes
end
return M
