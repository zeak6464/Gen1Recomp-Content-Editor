local M={}
local Kit=require("Kit")
local PAL=require("Theme").PAL
local function form(rec,mutate,App,x,y,w,fh,s)
  local F={}
  function F.row(label,draw)
    Kit.text("small",label,x,y+6*s,PAL.caption)
    draw(x+190*s,y,math.max(80*s,w-198*s));y=y+fh+8*s
  end
  function F.number(key,label,lo,hi)
    F.row(label,function(xx,yy,ww)
      local cur=tonumber(rec[key]) or lo or 0
      local value=require("RegList").num(App,"g3_"..key,xx,yy,math.min(120*s,ww),fh,cur)
      value=math.floor(math.max(lo or 0,math.min(hi or 65535,value)))
      if value~=cur then rec=mutate();rec[key]=value;App.markDirty() end
    end)
  end
  function F.text(key,label)
    F.row(label,function(xx,yy,ww)
      local cur=tostring(rec[key] or "")
      local shown=key=="description" and cur:gsub("\n","\\n") or cur
      local value=Kit.textfield("g3_"..key,xx,yy,ww,fh,shown,"")
      if key=="description" then value=value:gsub("\\n","\n") end
      if value~=cur then rec=mutate();rec[key]=value;App.markDirty() end
    end)
  end
  function F.choice(S,key,label,ids,labels)
    F.row(label,function(xx,yy,ww)
      require("ChoicePicker").field(S,{x=xx,y=yy,w=ww,h=fh,current=rec[key],ids=ids,labels=labels,title=label,
        onPick=function(id) rec=mutate();rec[key]=id;App.markDirty() end})
    end)
  end
  function F.enum(S,key,label,labels)
    local ids={};for id in pairs(labels) do ids[#ids+1]=tostring(id) end
    local cur=tostring(rec[key] or 0);if not labels[cur] then ids[#ids+1]=cur;labels[cur]="Other ("..cur..")" end
    table.sort(ids,require("Gen3Labels").natural)
    F.row(label,function(xx,yy,ww)
      require("ChoicePicker").field(S,{x=xx,y=yy,w=ww,h=fh,current=cur,ids=ids,labels=labels,title=label,
        onPick=function(id) rec=mutate();rec[key]=tonumber(id);App.markDirty() end})
    end)
  end
  function F.finish() return y,rec end
  return F
end
function M.pokemon(S,mon,mutate,App,x,y,w,fh,s)
  local F=form(mon,mutate,App,x,y,w,fh,s)
  local abilities={};for _,name in pairs(S.data.gen3Pokemon.abilityNames or {}) do
    abilities[#abilities+1]=require("src.mods.Schemas").gen3View.idOf(name)
  end
  table.sort(abilities)
  local abilityLabels={};for _,id in ipairs(abilities) do abilityLabels[id]=require("Gen3Abilities").name(id) end
  for _,rec in pairs(S.project.gen3Behaviors or {}) do
    if rec.kind=="ability" then abilities[#abilities+1]=tostring(rec.index);abilityLabels[tostring(rec.index)]=rec.name end
  end
  for slot=1,2 do
    F.row("Ability "..slot,function(xx,yy,ww)
      require("ChoicePicker").field(S,{x=xx,y=yy,w=ww,h=fh,current=(mon.abilities or {})[slot] and tostring(mon.abilities[slot]),ids=abilities,labels=abilityLabels,
        title="ABILITY",allowClear=slot==2,onPick=function(id)
          mon=mutate();local a={unpack(mon.abilities or {})};a[slot]=id~="" and (tonumber(id) or id) or nil;mon.abilities=a;App.markDirty()
        end})
    end)
  end
  F.enum(S,"genderRatio","Gender",{["0"]="Male only",["31"]="Female 12.5% / Male 87.5%",["63"]="Female 25% / Male 75%",
    ["127"]="Female 50% / Male 50%",["191"]="Female 75% / Male 25%",["254"]="Female only",["255"]="Genderless"})
  F.number("eggCycles","Egg cycles",0,255)
  F.number("friendship","Friendship",0,255)
  for _,key in ipairs({"itemCommon","itemRare"}) do
    F.row(key=="itemCommon" and "Common held item" or "Rare held item",function(xx,yy,ww)
      require("ItemPicker").field(S,{x=xx,y=yy,w=ww,h=fh,current=mon[key],allowClear=true,
        onPick=function(id) mon=mutate();mon[key]=id and id~="" and id or "0";App.markDirty() end})
    end)
  end
  for slot=1,2 do
    F.row("Egg group "..slot,function(xx,yy,ww)
      local cur=(mon.eggGroups or {})[slot] or 0
      local names={"Monster","Water 1","Bug","Flying","Field","Fairy","Grass","Human-like","Water 3","Mineral","Amorphous","Water 2","Ditto","Dragon","Cannot breed"}
      local ids,labels={"0"},{["0"]="Not specified"}
      for i,name in ipairs(names) do ids[#ids+1]=tostring(i);labels[tostring(i)]=name end
      require("ChoicePicker").field(S,{x=xx,y=yy,w=ww,h=fh,current=tostring(cur),ids=ids,labels=labels,title="Egg group",
        onPick=function(id) mon=mutate();local a={unpack(mon.eggGroups or {})};a[slot]=tonumber(id);mon.eggGroups=a;App.markDirty() end})
    end)
  end
  for _,side in ipairs({"Front","Back","ShinyFront","ShinyBack"}) do
    F.row(side:gsub("Shiny", "Shiny ").." sprite",function(xx,yy,ww)
      if Kit.button(xx,yy,ww,fh,"Import 64 × 64 PNG",{}) then
        local species=mon.id
        App.pickFile("Import battle sprite","PNG|*.png",function(path)
          local bytes=require("ModIO").readText(path)
          local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"sprite.png")) end)
          if not ok or img:getWidth()~=64 or img:getHeight()~=64 then S.status="Battle sprites must be 64 × 64 PNGs";return end
          App.importToMod(path,"assets/gen3/pokemon/"..species:lower().."_"..side:lower()..".png",function(rel)
            local rec=S.project.pokemon[species] or require("src.mods.Merge").deepCopy(S.data.pokemon[species])
            S.project.pokemon[species]=rec;rec["sprite"..side]=rel;rec.trueColor=true;require("Preview").invalidate();App.markDirty()
          end)
        end)
      end
    end)
  end
  F.row(S.pokemonShinyPreview and "Shiny party icon" or "Normal party icon",function(xx,yy,ww)
    require("Gen3PokemonIcons").drawControls(S,mon.index,App,xx,yy,ww,fh,s,S.pokemonShinyPreview)
  end)
  F.row("Icon PNG size",function(xx,yy)
    Kit.text("micro","32 × 32, or 32 × 64 (two stacked frames)",xx,yy+6*s,PAL.faint)
  end)
  return F.finish()
end
function M.dex(S,mon,mutate,App,x,y,w,fh,s)
  local function own() mon=mutate();mon.dexEntry=mon.dexEntry or {};return mon.dexEntry end
  local F=form(mon.dexEntry or {},own,App,x,y,w,fh,s)
  F.text("kind","Category")
  F.number("height","Height (decimeters)",0,65535)
  F.number("weight","Weight (hectograms)",0,65535)
  local yy=F.finish();return yy,mon
end
function M.items(S,item,mutate,App,x,y,w,fh,s)
  require("Preview").drawItemIcon(S,item,x,y,64*s,64*s)
  if Kit.button(x+80*s,y,180*s,fh,"Import 24 × 24 icon",{}) then
    local index=item.index
    App.pickFile("Import item icon","PNG|*.png",function(path)
      local IO=require("ModIO")
      local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(IO.readText(path),"icon.png")) end)
      if not ok or img:getWidth()~=24 or img:getHeight()~=24 then S.status="Item icons must be 24 × 24 PNGs";return end
      local rel="assets/gen3/items/"..index..".rgba"
      IO.ensureDirectory(S.path.."/assets/gen3/items")
      local written,err=IO.writeText(S.path.."/"..rel,img:getString())
      if not written then S.status=tostring(err);return end
      S.project.gen3Assets=S.project.gen3Assets or {}
      S.project.gen3Assets["data/generated/gba/items/bag/icons/"..index..".rgba"]={file=rel,width=24,height=24}
      App.markDirty()
    end)
  end
  if ((S.project.gen3Assets or {})["data/generated/gba/items/bag/icons/"..item.index..".rgba"])
      and Kit.button(x+270*s,y,130*s,fh,"Revert icon",{}) then
    S.project.gen3Assets["data/generated/gba/items/bag/icons/"..item.index..".rgba"]=nil;App.markDirty()
  end
  y=y+80*s
  local F=form(item,mutate,App,x,y,w,fh,s)
  F.row("Copy settings from",function(xx,yy,ww)
    require("ItemPicker").field(S,{x=xx,y=yy,w=ww,h=fh,current="",emptyLabel="Choose an existing item as a starting point",onPick=function(id)
      local src=S.project.items[id] or S.data.items[id];if not src then return end
      local dest=mutate()
      for _,key in ipairs({"pocket","fieldUse","holdEffect","holdEffectParam","importance","registrability","battleUsage","secondaryId","description"}) do dest[key]=src[key] end
      App.markDirty()
    end})
  end)
  F.text("name","Display name");F.number("index","Item number",1,1023);F.number("price","Shop price",0,999999)
  local function choices(key)
    local seen,ids={},{}
    for _,rec in pairs(S.data.items or {}) do
      local value=rec[key];if value and not seen[value] then seen[value]=true;ids[#ids+1]=value end
    end
    table.sort(ids);return ids
  end
  F.choice(S,"pocket","Pocket",choices("pocket"))
  F.choice(S,"fieldUse","Use outside battle",choices("fieldUse"),{none="Cannot use from the Bag",heal="Medicine (healing / status)",status="Cure status",revive="Revive fainted Pokemon",pp="Restore move PP",evo="Evolution item",level="Raise level",tm="Teach a move",repel="Repel wild Pokemon"});F.text("description","Description")
  local held={["0"]="None"}
  for name,id in pairs(require("src.core.game3.battle.held_items").HOLD) do held[tostring(id)]=name:gsub("_"," ") end
  F.enum(S,"holdEffect","When held",held)
  F.number("holdEffectParam","Effect amount",0,255)
  F.enum(S,"importance","Can discard / sell",{["0"]="Yes (ordinary item)",["1"]="No (important item)",["2"]="No (special key item)"})
  F.enum(S,"registrability","Register to SELECT",{["0"]="No",["1"]="Yes"})
  F.enum(S,"battleUsage","Use in battle",{["0"]="Not usable",["1"]="Choose a party Pokemon",["2"]="Use directly"})
  F.number("secondaryId","Variant / secondary ID",0,65535)
  return F.finish()
end
function M.moves(S,move,mutate,App,x,y,w,fh,s)
  local F=form(move,mutate,App,x,y,w,fh,s)
  local effects={}
  for name,id in pairs(require("src.core.game3.battle.effect_ids")) do if type(id)=="number" then effects[tostring(id)]=name:gsub("_"," ") end end
  effects["0"]="Deal damage";effects["3"]="Drain HP (Absorb)";effects["1"]="Put target to sleep"
  F.enum(S,"effect","What the move does",effects)
  F.number("secondaryChance","Extra effect chance %",0,100)
  F.enum(S,"target","Who it targets",{["0"]="One selected Pokemon",["1"]="Determined by the effect",["2"]="User or selected Pokemon",["4"]="Random opponent",["8"]="Both opponents",["16"]="The user",["32"]="Everyone except the user",["64"]="Opponent's side of the field"})
  local priorities={};for i=-7,7 do priorities[tostring(i)]=i==0 and "Normal turn order (0)" or (i>0 and "Acts earlier (+"..i..")" or "Acts later ("..i..")") end
  F.enum(S,"priority","Turn order",priorities)
  for _,flag in ipairs({{1,"Makes contact"},{2,"Blocked by Protect"},{4,"Reflected by Magic Coat"},{8,"Can be stolen by Snatch"},{16,"Copied by Mirror Move"},{32,"Affected by King's Rock"}}) do
    F.row(flag[2],function(xx,yy,ww)
      local enabled=math.floor((move.flags or 0)/flag[1])%2==1
      require("ChoicePicker").field(S,{x=xx,y=yy,w=ww,h=fh,current=enabled and "yes" or "no",ids={"yes","no"},labels={yes="Yes",no="No"},title=flag[2],onPick=function(id)
        local want=id=="yes";if want~=enabled then move=mutate();move.flags=(move.flags or 0)+(want and flag[1] or -flag[1]);App.markDirty() end
      end})
    end)
  end
  F.choice(S,"category","Category",{"physical","special","status"})
  F.row("Battle animation",function(xx,yy,ww)
    if Kit.button(xx,yy,ww,fh,"Edit animation",{}) then S.tab="anims";S.g3AnimId="moves/"..tostring(move.index);S._g3AnimId=nil end
  end)
  return F.finish()
end
return M
