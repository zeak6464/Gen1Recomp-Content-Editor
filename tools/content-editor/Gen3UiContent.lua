local M={}
-- Ids match the cache file names (<id>_map.png) the game reads.
M.townMapKeys={"kanto","sevii123","sevii45","sevii67"}
M.townMapNames={kanto="Kanto",sevii123="Sevii Islands 1-3",sevii45="Sevii Islands 4-5",sevii67="Sevii Islands 6-7"}

--- The Town Map pictures the editor can show: the game's own, then the other
-- game's from the player's import when there is one. `source` is that import.
function M.townArts(S)
  local out={}
  local function add(id,label,path,source,editable) out[#out+1]={id=id,label=label,path=path,source=source,editable=editable} end
  local function sevii(source,editable)
    for _,k in ipairs(M.townMapKeys) do add(k,M.townMapNames[k],"data/generated/gba/region_map/"..k.."_map.png",source,editable) end
  end
  if require("Generation").id(S)=="emerald" then
    add("hoenn","Hoenn","data/generated/gba/rse/region_map/map.png",nil,false)
    local fr=require("Gen3FrLink")
    if fr.editor() then sevii(setmetatable({NAME=fr.NAME or "FireRed",read=function(p) return fr.editor().read(p) end},{}),false) end
  else
    sevii(nil,true)
    local em=require("Gen3EmLink")
    if em.editor() then add("hoenn","Hoenn","data/generated/gba/rse/region_map/map.png",{NAME=em.NAME or "Emerald",read=function(p) return em.editor().read(p) end},false) end
  end
  return out
end
local K=require("Kit")
local R=require("Gen3Resources")
local C=require("ChoicePicker")
local function canvas(S,x,y,w,h,draw)
  S._g3ContentCanvas=S._g3ContentCanvas or love.graphics.newCanvas(240,160)
  local old=love.graphics.getCanvas();love.graphics.push("all")
  love.graphics.setCanvas(S._g3ContentCanvas);love.graphics.origin();love.graphics.setScissor();love.graphics.clear(1,1,1,1)
  local ok,err=xpcall(draw,debug.traceback)
  love.graphics.setCanvas(old);love.graphics.pop()
  S.g3UiContentError=not ok and tostring(err) or nil
  if not ok then K.caption(x,y,tostring(err));return end
  local scale=math.min(w/240,h/160,4);love.graphics.setColor(1,1,1,1)
  S._g3ContentCanvas:setFilter("nearest","nearest");love.graphics.draw(S._g3ContentCanvas,x,y,0,scale,scale)
end
-- The PokeNav's map entry on the Kanto maps of an Emerald mod (FireRed Maps).
-- Empty = the default wording.
function M.drawNav(S,x,y,w,h,App)
  local s=K.scale
  local Fr=require("Gen3FrLink")
  local PAL=require("Theme").PAL
  K.caption(x,y,"POKENAV ON THE KANTO MAPS")
  K.text("small","On the Kanto maps (FireRed Maps), the PokeNav's first entry opens FireRed's Town Map. Its wording is yours:",x,y+26*s,PAL.muted)
  if not Fr.enabled(S.project) then
    K.text("small","FireRed Maps is off, so this has no effect yet (GAME PATCHES > FireRed Maps).",x,y+48*s,PAL.yellow)
  end
  local fields={
    {id="nav_label",which="label",title="Entry (up to 10 letters)",key="gen3FrNavLabel"},
    {id="nav_desc",which="desc",title="Description under it (up to 40 letters)",key="gen3FrNavDesc"},
  }
  local fy=y+80*s
  local bw=math.min(w,640*s)
  for _,f in ipairs(fields) do
    K.text("small",f.title,x,fy,PAL.heading)
    local shown=S.project[f.key] or ""
    local v=K.textfield(f.id,x,fy+22*s,bw-100*s,28*s,shown,Fr.NAV_DEFAULT[f.which],"Leave it empty for: "..Fr.NAV_DEFAULT[f.which])
    if v~=shown and Fr.setNavText(S,f.which,v) then App.markDirty();S.status="PokeNav text changed" end
    if K.button(x+bw-90*s,fy+22*s,90*s,28*s,"Default",{kind="ghost",font="micro",enabled=shown~="",tooltip="Back to: "..Fr.NAV_DEFAULT[f.which]}) then
      if Fr.setNavText(S,f.which,"") then App.markDirty();S.status="PokeNav text changed" end
    end
    fy=fy+76*s
  end
  K.caption(x,fy,"Written into the mod when it is exported: the PokeNav shows it on the Kanto maps.")
end
-- Regions you define: a name, a colour, the maps in it.
function M.drawRegions(S,x,y,w,h,App)
  local s=K.scale
  local Regions=require("Gen3Regions")
  local RegList=require("RegList")
  local PAL=require("Theme").PAL
  local p=S.project
  if not p then K.caption(x,y,"Create or open a mod first");return end
  local list=Regions.list(p)
  local ids={};for _,r in ipairs(list) do ids[#ids+1]=r.id end
  if not Regions.find(p,S.g3RegionId) then S.g3RegionId=ids[1] end
  local names={};for _,r in ipairs(list) do names[r.id]=r.name end
  local suggest=Regions.suggest(S)
  local top=y
  if #suggest>0 then
    local labels={};for _,g in ipairs(suggest) do labels[#labels+1]=g.name end
    if K.button(x+230*s,y,360*s,28*s,"Add the regions in use ("..table.concat(labels,", ")..")",{kind="ghost",font="micro",tooltip="Regions for the map name prefixes this mod already has"}) then
      if Regions.addSuggested(S)>0 then App.markDirty();S.status="Regions added" end
    end
  end
  K.caption(x,y+4*s,"REGIONS")
  top=y+36*s
  local fx,fw,ly=RegList.drawList(S,App,x,top,w,h-(top-y),"Your regions",ids,{
    selKey="g3RegionId",queryKey="g3RegionQuery",offsetKey="g3RegionOffset",listW=200*s,
    label=function(id) return names[id] or id end,
    marker=function(id) local r=Regions.find(p,id);if not r then return nil end;local a,b,c=Regions.rgb(r.color);return {a,b,c} end,
    footerLabel="Add region",
    onFooter=function()
      local n=#list+1;local name="Region "..n
      while true do local taken=false;for _,r in ipairs(list) do if r.name==name then taken=true end end;if not taken then break end;n=n+1;name="Region "..n end
      local r=Regions.add(S,name);if r then S.g3RegionId=r.id;App.markDirty() end
    end,
  })
  local region=Regions.find(p,S.g3RegionId)
  if not region then
    K.text("small","No regions yet. Add one, or add the ones this mod's maps already use.",fx,ly+8*s,PAL.muted)
    K.text("small","A region is a name, a colour and the maps in it, with nothing imported or linked behind it.",fx,ly+30*s,PAL.muted)
    return
  end
  -- buffers: text typed in a field is kept as typed until it is valid
  if S._g3RegionFor~=region.id then
    S._g3RegionFor=region.id;S.g3RegionName=region.name;S.g3RegionPrefixes=Regions.prefixText(region);S.g3RegionAdd="";S.g3RegionDelete=nil
  end
  local fy=ly
  K.text("small","Name",fx,fy,PAL.heading)
  local nv=K.textfield("g3_region_name",fx,fy+20*s,math.min(fw,360*s),28*s,S.g3RegionName,"Region name")
  if nv~=S.g3RegionName then S.g3RegionName=nv;if Regions.set(S,region.id,"name",nv) then App.markDirty() end end
  local taken=nv~=region.name and nv:match("%S")
  if taken then K.text("micro","That name is empty or already used",fx+370*s,fy+28*s,PAL.yellow) end
  -- colour
  fy=fy+60*s
  K.text("small","Colour",fx,fy,PAL.heading)
  for i,hex in ipairs(Regions.COLORS) do
    local sx,sy,sw=fx+(i-1)*34*s,fy+22*s,28*s
    local r,g,b=Regions.rgb(hex)
    love.graphics.setColor(r,g,b,1);love.graphics.rectangle("fill",sx,sy,sw,sw,6*s,6*s)
    if region.color==hex then love.graphics.setColor(1,1,1,1);love.graphics.setLineWidth(2*s);love.graphics.rectangle("line",sx-2*s,sy-2*s,sw+4*s,sw+4*s,8*s,8*s);love.graphics.setLineWidth(1) end
    love.graphics.setColor(1,1,1,1)
    if K.hit(sx,sy,sw,sw) and K.mouseClicked and not K.blockClicks then if Regions.set(S,region.id,"color",hex) then App.markDirty() end end
  end
  fy=fy+66*s
  -- maps in it
  K.text("small","Maps with these name beginnings are in it (comma between)",fx,fy,PAL.heading)
  local pv=K.textfield("g3_region_prefixes",fx,fy+20*s,math.min(fw,520*s),28*s,S.g3RegionPrefixes,"EM_HOENN_, FR_HOENN_")
  if pv~=S.g3RegionPrefixes then S.g3RegionPrefixes=pv;if Regions.set(S,region.id,"prefixes",pv) then App.markDirty() end end
  local all=Regions.allMapIds(S)
  fy=fy+54*s
  local count=Regions.count(p,region,all)
  K.text("micro",(count==1 and "1 map is" or count.." maps are").." in this region. Add a map by name, whatever it is called:",fx,fy,PAL.muted)
  local add=RegList.suggestField(App,S,"g3_region_add",fx,fy+18*s,math.min(fw,360*s),28*s,S.g3RegionAdd,"map id",function() return all end)
  S.g3RegionAdd=add
  local inList=false;for _,id in ipairs(all) do if id==add then inList=true;break end end
  if K.button(fx+math.min(fw,360*s)+10*s,fy+18*s,150*s,28*s,"Put in region",{kind="ghost",font="micro",enabled=inList}) then
    if Regions.assign(S,add,region.id) then App.markDirty();S.status=add.." is in "..region.name end
    S.g3RegionAdd=""
  end
  fy=fy+56*s
  if #(region.include or {})>0 then
    K.text("micro","Added by hand:",fx,fy,PAL.muted)
    local ix,iy=fx,fy+18*s
    for i,id in ipairs(region.include) do
      if i>8 then K.text("micro","... and "..(#region.include-8).." more",ix,iy+4*s,PAL.muted);break end
      local label=K.ellipsize and K.ellipsize("mono",id,230*s) or id
      K.text("mono",label,ix,iy+4*s,PAL.text)
      if K.button(ix+240*s,iy,70*s,22*s,"Remove",{kind="ghost",font="micro"}) then Regions.assign(S,id,nil);App.markDirty() end
      iy=iy+26*s
      if i==4 then ix,iy=fx+340*s,fy+18*s end
    end
    fy=fy+18*s+26*s*math.min(4,#region.include)+8*s
  end
  -- Emerald: PokeNav wording on this region's maps
  if require("Generation").id(S)=="emerald" then
    K.text("small","PokeNav on this region's maps (empty = Hoenn's own wording)",fx,fy,PAL.heading)
    for _,f in ipairs({{"navLabel","Entry, up to 10 letters","REGION MAP"},{"navDesc","Description under it, up to 40 letters","Check the map of the region."}}) do
      fy=fy+22*s
      local shown=region[f[1]] or ""
      local v=K.textfield("g3_region_"..f[1],fx,fy,math.min(fw,520*s),26*s,shown,f[2])
      if v~=shown and Regions.set(S,region.id,f[1],v) then App.markDirty();S.status="PokeNav text changed" end
      fy=fy+30*s
    end
    K.text("micro","Shown in the game on these maps once the mod is exported.",fx,fy-2*s,PAL.muted)
    fy=fy+22*s
  end
  -- the region's maps, laid out by their connections (MAPS > World View)
  if K.button(fx,fy,200*s,28*s,"Preview the maps",{kind="primary",font="micro",enabled=Regions.count(p,region,all)>0,
      tooltip="Open this region's maps in the World view"}) then
    local first
    for _,id in ipairs(all) do if Regions.ownerOf(p,id)==region then first=id;break end end
    S.tab="maps";S.mapViewMode="world";S.worldScope="region";S.worldRegionId=region.id;S._worldFitKey=nil
    S.mapId,S.builderMapId,S.g3MapId=first,first,first
  end
  fy=fy+40*s
  local want=S.g3RegionDelete==region.id
  if K.button(fx,fy,want and 240*s or 160*s,28*s,want and "Click again to delete" or "Delete region",{kind=want and "danger" or "ghost",font="micro",tooltip="The maps stay; only the region goes"}) then
    if want then Regions.remove(S,region.id);S.g3RegionDelete=nil;S.g3RegionId=nil;S._g3RegionFor=nil;App.markDirty();S.status="Region deleted"
    else S.g3RegionDelete=region.id end
  end
end
function M.draw(S,x,y,w,h,App,mode)
  local s=K.scale
  if mode=="help" then
    local pack=R.readTable(S.data,"data/generated/gba/help/pack.lua")
    local ids,rows={},{}
    for group,entries in pairs(pack.entries or {}) do for id,row in pairs(entries) do
      local key=group..":"..id;ids[#ids+1]=key;rows[key]=row
    end end
    table.sort(ids,require("Gen3Labels").natural);S.g3HelpId=S.g3HelpId or ids[1]
    local labels={};for key,row in pairs(rows) do labels[key]=row.question end
    C.field(S,{x=x,y=y,w=w,h=30*s,current=S.g3HelpId,ids=ids,labels=labels,title="Help topic",onPick=function(id) S.g3HelpId=id end})
    local original=rows[S.g3HelpId];if not original then K.caption(x,y+40*s,"No Help topics in this extract");return end
    local rec=(S.project.gen3Help or {})[S.g3HelpId] or original
    for i,key in ipairs({"question","answer"}) do
      local yy=y+(45+(i-1)*70)*s
      K.caption(x,yy,key=="question" and "Question" or "Answer (use \\n for a new line)")
      local current=rec[key]:gsub("\n","\\n")
      local text=K.textfield("g3help_"..key,x,yy+22*s,w,30*s,current,"")
      if text~=current then
        S.project.gen3Help=S.project.gen3Help or {};S.project.gen3Help[S.g3HelpId]=require("src.mods.Merge").deepCopy(rec)
        rec=S.project.gen3Help[S.g3HelpId];rec[key]=text:gsub("\\n","\n");App.markDirty()
      end
    end
    canvas(S,x,y+200*s,w,h-245*s,function()
      love.graphics.setColor(.13,.25,.48,1);love.graphics.rectangle("fill",0,0,240,160)
      require("src.ui.game3.frlg_font").draw(rec.answer,8,8,{maxWidth=224,color={1,1,1,1},linePitch=16})
    end)
    if K.button(x,y+h-32*s,150*s,28*s,"Revert topic",{}) then if S.project.gen3Help then S.project.gen3Help[S.g3HelpId]=nil;App.markDirty() end end
  elseif mode=="dex" then
    require("Gen3ContentAdapter").prepare(S);S.g3DexSpecies=S.g3DexSpecies or "BULBASAUR"
    local rse=require("Generation").id(S)=="emerald"
    require("SpeciesPicker").field(S,{x=x,y=y,w=w*.6,h=30*s,current=S.g3DexSpecies,onPick=function(id) S.g3DexSpecies=id end})
    C.field(S,{x=x+w*.62,y=y,w=w*.38,h=30*s,current=rse and "data" or S.g3DexScreen or "data",ids=rse and {"data"} or {"data","area","size"},labels={data="Entry card",area="Habitat map",size="Size comparison"},onPick=function(id) S.g3DexScreen=id end})
    local mon=S.project.pokemon[S.g3DexSpecies] or S.data.pokemon[S.g3DexSpecies]
    canvas(S,x,y+45*s,w,h-100*s,function()
      if rse then
        -- Emerald's own entry page, stepped here rather than on the game's UI stack.
        local P=require("src.ui.game3.rse.pokedex");local view=S._g3RseDex
        if not view or view.species~=mon.index then
          view=P.newView({});view.species=mon.index
          view.caught={dexNum=require("src.core.game3.pokemon").national(mon.index) or mon.index}
          view.fn="caught";view.state=0;view.detached=true;S._g3RseDex=view
        end
        P.frame(view,{});P.draw(view);return
      end
      local P=require("src.ui.game3.pokedex");local keys={"open","screen","selectedSpecies","_regSpecies","_dex"};local old={}
      for _,key in ipairs(keys) do old[key]=P[key] end
      P.open=true;P.screen=S.g3DexScreen or "data";P.selectedSpecies=mon.index;P._regSpecies=nil;P._dex={seen={},caught={}}
      for i=1,411 do P._dex.seen[i]=true;P._dex.caught[i]=true end
      local ok,err=pcall(P.draw);for _,key in ipairs(keys) do P[key]=old[key] end;if not ok then error(err) end
    end)
    if K.button(x,y+h-35*s,220*s,30*s,"Edit Pokemon / Dex data",{}) then S.pokemonId=S.g3DexSpecies;S.tab="pokemon" end
  else
    local emerald=require("Generation").id(S)=="emerald"
    if K.button(x,y,150*s,28*s,"Town Map artwork",{}) then S.g3TownView="art" end
    if K.button(x+160*s,y,150*s,28*s,"Fly destinations",{}) then S.g3TownView="fly" end
    local rx=x+320*s
    if emerald then
      if K.button(rx,y,150*s,28*s,"PokeNav text",{}) then S.g3TownView="nav" end
      rx=rx+160*s
    end
    if K.button(rx,y,150*s,28*s,"Regions",{}) then S.g3TownView="regions" end
    if S.g3TownView=="fly" then require("Gen3Fly").draw(S,x,y+40*s,w,h-40*s,App);return end
    if emerald and S.g3TownView=="nav" then M.drawNav(S,x,y+40*s,w,h-40*s,App);return end
    if S.g3TownView=="regions" then M.drawRegions(S,x,y+40*s,w,h-40*s,App);return end
    local arts=M.townArts(S)
    local art=arts[1]
    for _,a in ipairs(arts) do if a.id==S.g3TownRegion then art=a end end
    local ids,labels={},{}
    for _,a in ipairs(arts) do ids[#ids+1]=a.id;labels[a.id]=a.label..(a.source and (" (from "..a.source.NAME..")") or "") end
    require("ChoicePicker").field(S,{x=x,y=y+36*s,w=w,h=30*s,current=art.id,ids=ids,labels=labels,title="Town Map region",onPick=function(id) S.g3TownRegion=id end})
    local key=art.path
    local function bytesOf()
      local asset=art.editable and (S.project.gen3Assets or {})[key]
      if asset then return assert(require("ModIO").readText(S.path.."/"..asset.file)) end
      if art.source then return art.source.read(key) end
      return S.data._gen3Read(key)
    end
    local function mapImage()
      local asset=art.editable and (S.project.gen3Assets or {})[key]
      if asset then
        local img=love.graphics.newImage(love.filesystem.newFileData(bytesOf(),"map.png"));img:setFilter("nearest","nearest");return img
      end
      S._g3TownMapImages=S._g3TownMapImages or {}
      local ck=(art.source and "import:" or "own:")..art.id
      if not S._g3TownMapImages[ck] then
        local bytes=bytesOf()
        if not bytes then return nil end
        S._g3TownMapImages[ck]=love.graphics.newImage(love.filesystem.newFileData(bytes,"map.png"))
        S._g3TownMapImages[ck]:setFilter("nearest","nearest")
      end
      return S._g3TownMapImages[ck]
    end
    canvas(S,x,y+78*s,w,h-162*s,function()
      local img=mapImage()
      if not img then return end
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(img,love.graphics.newQuad(0,0,240,160,img:getWidth(),img:getHeight()),0,0)
    end)
    local game=require("src.core.GameVersion").VERSIONS[require("Generation").id(S)].label
    if art.source then
      K.caption(x,y+h-78*s,art.label.." artwork is read from your imported "..(art.source.NAME or art.source.game or "other game").." cache.")
      K.caption(x,y+h-55*s,"View only: in the game this picture is that game's own Town Map.")
    elseif not art.editable then
      K.caption(x,y+h-78*s,art.label.." artwork is read from your imported "..game.." cache.")
      K.caption(x,y+h-55*s,"View only: replacing the Emerald Town Map is not supported yet.")
    else
      K.caption(x,y+h-78*s,"Original "..art.label.." artwork is read from your imported "..game.." cache.")
      K.caption(x,y+h-55*s,art.id=="kanto" and "Kanto artwork is used by the in-game Town Map." or "Artwork editing only: in-game Sevii navigation and Fly destinations are not yet supported.")
    end
    if art.editable then
      if K.button(x,y+h-30*s,200*s,28*s,"Import 240 x 160 map PNG",{}) then
        App.pickFile("Town Map image","PNG|*.png",function(path)
          local IO=require("ModIO");local bytes=IO.readText(path)
          local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"map.png")) end)
          if not ok or img:getWidth()~=240 or img:getHeight()~=160 then S.status="Town Map must be 240 x 160 pixels";return end
          IO.ensureDirectory(S.path.."/assets/gen3/region_map")
          local rel="assets/gen3/region_map/"..art.id.."_map.png";local saved,err=IO.writeText(S.path.."/"..rel,bytes)
          if not saved then S.status=tostring(err);return end
          S.project.gen3Assets=S.project.gen3Assets or {};S.project.gen3Assets[key]={file=rel,width=240,height=160};App.markDirty()
        end)
      end
      if K.button(x+215*s,y+h-30*s,120*s,28*s,"Revert image",{}) then if S.project.gen3Assets then S.project.gen3Assets[key]=nil;App.markDirty() end end
    end
    if K.button(x+(art.editable and 350*s or 0),y+h-30*s,120*s,28*s,"Export PNG",{}) then
      local IO=require("ModIO");local dest=S.path.."/assets/gen3-export/region_map/"..art.id.."_map.png"
      IO.ensureDirectory(dest:match("^(.*)/"))
      local bytes=bytesOf()
      local ok,err=IO.writeText(dest,bytes)
      S.status=ok and ("Exported "..dest) or tostring(err)
    end
  end
end
return M
