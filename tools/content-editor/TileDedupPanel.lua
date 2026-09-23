local M={}
local Kit=require("Kit")
local PAL=require("Theme").PAL
local Dedup=require("TileDedup")
function M.open(S)
  S.tileDedup={selected={[S.builderMapId or S.mapId or ""]=true},offset=0}
end
function M.draw(S,x,y,w,h,App)
  local d=S.tileDedup;local s=Kit.scale
  Kit.card(x,y,w,h,10*s)
  x,y,w,h=x+16*s,y+16*s,w-32*s,h-32*s
  Kit.text("small","Combine duplicate tiles",x,y,PAL.heading)
  if Kit.button(x+w-90*s,y,90*s,26*s,"Back",{kind="ghost"}) then S.tileDedup=nil;return end
  y=y+36*s;h=h-36*s
  Kit.text("micro","Choose maps whose imported PNG sources should share a compact tileset.",x,y,PAL.muted)
  y=y+22*s;h=h-22*s
  local ids={}
  for id in pairs(S.project.layeredMaps or {}) do
    if #Dedup.sourcesForMaps(S.project,{[id]=true})>0 then ids[#ids+1]=id end
  end
  table.sort(ids)
  local lw=math.min(300*s,w*.4);local rx=x+lw+20*s;local rw=w-lw-20*s
  if Kit.button(x,y,80*s,25*s,"All maps",{kind="ghost"}) then
    d.selected={};for _,id in ipairs(ids) do d.selected[id]=true end;d.plan=nil
  end
  if Kit.button(x+84*s,y,80*s,25*s,"Clear",{kind="ghost"}) then d.selected={};d.plan=nil end
  local listY=y+32*s;local listH=math.max(28*s,h-78*s);local rowH=28*s
  local perPage=math.max(1,math.floor(listH/rowH))
  d.offset=Kit.scroll(x,listY,lw,listH,d.offset,#ids,perPage,1,"tileDedupMaps")
  Kit.pushClip(x,listY,lw,listH)
  for row=1,perPage do
    local id=ids[row+d.offset];if not id then break end
    local yy=listY+(row-1)*rowH
    if Kit.row(x,yy,lw-14*s,rowH-2*s,d.selected[id],PAL.blue,4*s) then
      d.selected[id]=not d.selected[id] or nil;d.plan=nil
    end
    Kit.text("micro",Kit.ellipsize("micro",(d.selected[id] and "[x] " or "[ ] ")..id,lw-26*s),x+6*s,yy+6*s,PAL.heading)
  end
  Kit.popClip()
  d.offset=Kit.scrollbar(x+lw-10*s,listY,10*s,listH,d.offset,#ids,perPage,"tileDedupMaps")
  if #ids==0 then Kit.text("micro","No image-based maps yet.",x,listY,PAL.muted) end
  if Kit.button(x,y+h-32*s,lw,28*s,"Scan selected maps",{kind="accent",enabled=next(d.selected)~=nil and #ids>0}) then
    local ok,result=pcall(Dedup.scan,S,Dedup.sourcesForMaps(S.project,d.selected))
    d.plan=ok and result or nil;d.error=not ok and tostring(result) or nil
  end
  if d.error then
    Kit.text("micro",Kit.ellipsize("micro",d.error,rw),rx,y,PAL.red)
    Kit.offerTooltip(rx,y,rw,40*s,d.error)
  elseif d.plan then
    local p=d.plan
    Kit.text("small",string.format("%d tiles  >  %d unique",p.before,p.after),rx,y,PAL.heading)
    Kit.text("micro",string.format("%d duplicates removed (%.1f%%) | %d source(s)",p.saved,100*p.saved/p.before,#p.ids),rx,y+28*s,PAL.green)
    Kit.text("micro","Exact pixels only. Animation timing and color modes are preserved.",rx,y+52*s,PAL.muted)
    Kit.text("micro","All uses of these sources update, including other maps and brushes.",rx,y+72*s,PAL.muted)
    Kit.text("micro","Original images are retained. Undo / Redo restores the change.",rx,y+92*s,PAL.muted)
    local yy=y+122*s
    for _,dup in ipairs(p.duplicates) do
      if yy+38*s>y+h-48*s then break end
      local L=require("LayeredMap")
      L.drawSourceTile(S,S.project.mapTileSources[dup.source],dup.tile,rx,yy,32*s,1)
      L.drawSourceTile(S,S.project.mapTileSources[dup.kept.source],dup.kept.tile,rx+42*s,yy,32*s,1)
      local label=dup.source.." #"..dup.tile.." = "..dup.kept.source.." #"..dup.kept.tile
      Kit.text("micro",Kit.ellipsize("micro",label,rw-90*s),rx+86*s,yy+10*s,PAL.heading)
      Kit.offerTooltip(rx,yy,rw,36*s,label);yy=yy+38*s
    end
    if Kit.button(rx,y+h-32*s,math.min(rw,260*s),28*s,"Apply combined tileset",{kind="good",enabled=p.saved>0 or #p.ids>#p.groups}) then
      local ok,result=pcall(Dedup.apply,S,p,App)
      if ok then S.tileDedup=nil;S.status="Combined tilesets: removed "..result.." duplicate tiles. Undo is available."
      else d.error=tostring(result) end
    end
  else
    Kit.text("micro","Scan to preview the tile reduction and duplicate examples.",rx,y,PAL.muted)
  end
end
return M
