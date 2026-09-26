-- Older extracted COLL_WATER bytes can lose the ROM cell's blocked flag.
local M={}
function M.repair(data,id,layout)
  local ok,catalog=pcall(require,'src.import.gba.map_catalog')
  local slot=ok and catalog.slotKeyFor and catalog.slotKeyFor(id)
  if not slot then return end
  local bytes=data._gen3Read('data/generated/gba/map_tree/maps/'..slot..'/grid.bin')
  local w,h=layout.trueWidth or layout.width,layout.trueHeight or layout.height
  if not bytes or #bytes~=w*h*2 then return end
  for y=0,h-1 do for x=0,w-1 do
    local a,b=bytes:byte((y*w+x)*2+1,(y*w+x)*2+2)
    local word=a+b*256;local mid=word%1024;local blocked=math.floor(word/1024)%4~=0
    local i=y*layout.width+x+1;local cell=layout.cells[i]
    if cell and cell.mid==mid and blocked and (cell.coll==0x29 or cell.coll==255 or cell.coll==7) then
      layout._editorBlockedCells=layout._editorBlockedCells or {}
      layout._editorBlockedCells[i]=mid
      if cell.coll==0x29 then
        cell.coll=255
        layout._editorWaterRepairs=layout._editorWaterRepairs or {}
        layout._editorWaterRepairs[i]=mid
      end
    end
  end end
end
function M.migrate(data,id,source)
  if source._waterCollisionVersion==1 then return end
  local layout=require('Gen3Map').layout(data,id)
  if layout and source.cellWidth==layout.width and source.cellHeight==layout.height then
    for i,mid in pairs(layout._editorBlockedCells or {}) do
      local ref=source.layers and source.layers[1] and source.layers[1].cells[i]
      if ref and ref.source=='@runtime:'..layout.pair and ref.tile==mid
          and source.gen3Collision and source.gen3Collision[i]==0x29
          and (source.collision[i]=='water' or source.collision[i]=='solid') then
        source.gen3Collision[i]=255;source.collision[i]='solid'
      end
    end
  end
  source._waterCollisionVersion=1
end
return M
