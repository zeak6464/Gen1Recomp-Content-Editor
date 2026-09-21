local M={}
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
    require("SpeciesPicker").field(S,{x=x,y=y,w=w*.6,h=30*s,current=S.g3DexSpecies,onPick=function(id) S.g3DexSpecies=id end})
    C.field(S,{x=x+w*.62,y=y,w=w*.38,h=30*s,current=S.g3DexScreen or "data",ids={"data","area","size"},labels={data="Entry card",area="Habitat map",size="Size comparison"},onPick=function(id) S.g3DexScreen=id end})
    local mon=S.project.pokemon[S.g3DexSpecies] or S.data.pokemon[S.g3DexSpecies]
    canvas(S,x,y+45*s,w,h-100*s,function()
      local P=require("src.ui.game3.pokedex");local keys={"open","screen","selectedSpecies","_regSpecies","_dex"};local old={}
      for _,key in ipairs(keys) do old[key]=P[key] end
      P.open=true;P.screen=S.g3DexScreen or "data";P.selectedSpecies=mon.index;P._regSpecies=nil;P._dex={seen={},caught={}}
      for i=1,411 do P._dex.seen[i]=true;P._dex.caught[i]=true end
      local ok,err=pcall(P.draw);for _,key in ipairs(keys) do P[key]=old[key] end;if not ok then error(err) end
    end)
    if K.button(x,y+h-35*s,220*s,30*s,"Edit Pokemon / Dex data",{}) then S.pokemonId=S.g3DexSpecies;S.tab="pokemon" end
  else
    if K.button(x,y,150*s,28*s,"Town Map artwork",{}) then S.g3TownFly=false end
    if K.button(x+160*s,y,150*s,28*s,"Fly destinations",{}) then S.g3TownFly=true end
    if S.g3TownFly then require("Gen3Fly").draw(S,x,y+40*s,w,h-40*s,App);return end
    local Rom=require("Gen3Rom");local region=S.g3TownRegion or "kanto"
    require("ChoicePicker").field(S,{x=x,y=y+36*s,w=w,h=30*s,current=region,ids=Rom.townMapKeys,labels=Rom.townMapNames,title="Town Map region",onPick=function(id) S.g3TownRegion=id end})
    local key="data/generated/gba/region_map/"..region.."_map.png"
    local function mapImage()
      local asset=(S.project.gen3Assets or {})[key]
      local img
      if asset then
        local bytes=assert(require("ModIO").readText(S.path.."/"..asset.file))
        img=love.graphics.newImage(love.filesystem.newFileData(bytes,"map.png"))
      else
        local pixels,err=Rom.townMap(S,region);assert(pixels,err)
        S._g3TownMapImages=S._g3TownMapImages or {}
        S._g3TownMapImages[region]=S._g3TownMapImages[region] or love.graphics.newImage(pixels);img=S._g3TownMapImages[region]
      end
      return img
    end
    canvas(S,x,y+78*s,w,h-162*s,function()
      local img=mapImage()
      img:setFilter("nearest","nearest");love.graphics.setColor(1,1,1,1);love.graphics.draw(img,0,0)
    end)
    K.caption(x,y+h-78*s,"Original "..Rom.townMapNames[region].." artwork is read directly from your FireRed ROM.")
    K.caption(x,y+h-55*s,region=="kanto" and "Kanto artwork is used by the in-game Town Map." or "Artwork editing only: in-game Sevii navigation and Fly destinations are not yet supported.")
    if K.button(x,y+h-30*s,200*s,28*s,"Import 240 x 160 map PNG",{}) then
      App.pickFile("Town Map image","PNG|*.png",function(path)
        local IO=require("ModIO");local bytes=IO.readText(path)
        local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"map.png")) end)
        if not ok or img:getWidth()~=240 or img:getHeight()~=160 then S.status="Town Map must be 240 x 160 pixels";return end
        IO.ensureDirectory(S.path.."/assets/gen3/region_map")
        local rel="assets/gen3/region_map/"..region.."_map.png";local saved,err=IO.writeText(S.path.."/"..rel,bytes)
        if not saved then S.status=tostring(err);return end
        S.project.gen3Assets=S.project.gen3Assets or {};S.project.gen3Assets[key]={file=rel,width=240,height=160};App.markDirty()
      end)
    end
    if K.button(x+350*s,y+h-30*s,120*s,28*s,"Export PNG",{}) then
      local IO=require("ModIO");local dest=S.path.."/assets/gen3-export/region_map/"..region.."_map.png"
      IO.ensureDirectory(dest:match("^(.*)/"))
      local asset=(S.project.gen3Assets or {})[key]
      local bytes=asset and IO.readText(S.path.."/"..asset.file) or Rom.townMap(S,region):encode("png"):getString()
      local ok,err=IO.writeText(dest,bytes);S.status=ok and ("Exported "..dest) or tostring(err)
    end
    if K.button(x+215*s,y+h-30*s,120*s,28*s,"Revert image",{}) then if S.project.gen3Assets then S.project.gen3Assets[key]=nil;App.markDirty() end end
  end
end
return M
