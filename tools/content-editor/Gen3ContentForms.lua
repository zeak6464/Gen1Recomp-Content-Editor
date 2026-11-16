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
  F.row("Cry",function(xx,yy,ww)
    require("Gen3Cries").draw(S,mon,App,xx,yy,ww,fh,s)
  end)
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
  local bottom,record=F.finish()
  bottom=require("Gen3PokemonFrames").draw(S,mon.index,App,x,bottom,w,s,S.pokemonShinyPreview)
  return bottom,record
end
function M.dex(S,mon,mutate,App,x,y,w,fh,s)
  local function own() mon=mutate();mon.dexEntry=mon.dexEntry or {};return mon.dexEntry end
  local F=form(mon.dexEntry or {},own,App,x,y,w,fh,s)
  F.text("kind","Category")
  F.number("height","Height (decimeters)",0,65535)
  F.number("weight","Weight (hectograms)",0,65535)
  F.row("Description",function(xx,yy,ww)
    local texts=S.project.gen3DexText or {}
    local cur=texts[mon.index] or M.dexText(S,mon.index)
    local value=(Kit.textfield("g3_description",xx,yy,ww,fh,(cur:gsub("\n","\\n")),""):gsub("\\n","\n"))
    if value~=cur then texts[mon.index]=value;S.project.gen3DexText=texts;App.markDirty() end
  end)
  F.row("",function(xx,yy)
    Kit.text("micro","Type \\n for a new line",xx,yy+6*s,PAL.faint)
  end)
  local yy=F.finish();return yy,mon
end
function M.dexText(S,index)
  if not S.data._g3DexEntries then
    local bytes=S.data._gen3Read("data/generated/gba/pokemon/pokedex/entries.lua")
    S.data._g3DexEntries=bytes and load(bytes,"=entries","t",{})() or {}
  end
  return (S.data._g3DexEntries[index] or {}).description or ""
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
  F.choice(S,"fieldUse","Use outside battle",choices("fieldUse"),{none="Cannot use from the Bag",heal="Medicine (healing / status)",status="Cure status",revive="Revive fainted Pokemon",pp="Restore move PP",evo="Evolution item",level="Raise level",tm="Teach a move",repel="Repel wild Pokemon"})
  local xIds = { X_ATTACK = true, X_DEFEND = true, X_SPEED = true, X_SPECIAL = true, [75] = true, [76] = true, [77] = true, [79] = true }
  if xIds[item.id] or xIds[item.index] then
    F.row("Stages raised", function(xx, yy, ww)
      local cur = S.project.gen3XItem and S.project.gen3XItem.stages or 1
      local n = math.floor(require("RegList").num(App, "g3_x_stage", xx, yy, ww, fh, cur))
      n = math.max(0, math.min(6, n))
      if n ~= cur then
        S.project.gen3XItem = n == 1 and nil or { stages = n }
        App.markDirty()
      end
    end)
  end
  local herbHp = { ENERGY_POWDER = 50, ENERGY_ROOT = 200, [30] = 50, [31] = 200 }
  local herbNum = ({ ENERGY_POWDER = 30, ENERGY_ROOT = 31 })[item.id]
  if herbNum == nil and (item.index == 30 or item.index == 31) then herbNum = item.index end
  if herbNum then
    F.row("HP restored", function(xx, yy, ww)
      local default = herbHp[herbNum]
      local stored = S.project.gen3HerbHeal and S.project.gen3HerbHeal[herbNum]
      local cur = stored ~= nil and stored or default
      local n = math.floor(require("RegList").num(App, "g3_herb_hp", xx, yy, ww, fh, cur))
      n = math.max(0, math.min(9999, n))
      if n ~= cur then
        S.project.gen3HerbHeal = S.project.gen3HerbHeal or {}
        S.project.gen3HerbHeal[herbNum] = n == default and nil or n
        if next(S.project.gen3HerbHeal) == nil then S.project.gen3HerbHeal = nil end
        App.markDirty()
      end
    end)
  end
  local healHp = {
    POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200, MAX_POTION = 9999,
    FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80, MOOMOO_MILK = 100,
    ORAN_BERRY = 10, SITRUS_BERRY = 30,
    [13] = 20, [22] = 50, [21] = 200, [20] = 9999,
    [26] = 50, [27] = 60, [28] = 80, [29] = 100, [139] = 10, [142] = 30,
  }
  local healNum = ({
    POTION = 13, SUPER_POTION = 22, HYPER_POTION = 21, MAX_POTION = 20,
    FRESH_WATER = 26, SODA_POP = 27, LEMONADE = 28, MOOMOO_MILK = 29,
    ORAN_BERRY = 139, SITRUS_BERRY = 142,
  })[item.id]
  if healNum == nil and healHp[item.index] then healNum = item.index end
  if healNum then
    F.row("HP restored", function(xx, yy, ww)
      local default = healHp[healNum]
      local stored = S.project.gen3HealHp and S.project.gen3HealHp[healNum]
      local cur = stored ~= nil and stored or default
      local n = math.floor(require("RegList").num(App, "g3_heal_hp", xx, yy, ww, fh, cur))
      n = math.max(0, math.min(9999, n))
      if n ~= cur then
        S.project.gen3HealHp = S.project.gen3HealHp or {}
        S.project.gen3HealHp[healNum] = n == default and nil or n
        if next(S.project.gen3HealHp) == nil then S.project.gen3HealHp = nil end
        App.markDirty()
      end
    end)
  end
  if item.fieldUse == "vitamin" then
    F.row("Effort gained", function(xx, yy, ww)
      local cur = S.project.gen3Vitamin and S.project.gen3Vitamin.gain or 10
      local n = math.floor(require("RegList").num(App, "g3_vitamin", xx, yy, ww, fh, cur))
      n = math.max(0, math.min(255, n))
      if n ~= cur then
        S.project.gen3Vitamin = n == 10 and nil or { gain = n }
        App.markDirty()
      end
    end)
  end
  if item.fieldUse == "repel" then
    F.row("Repel steps", function(xx, yy, ww)
      local defaults = { REPEL = 100, SUPER_REPEL = 200, MAX_REPEL = 250, [86] = 100, [83] = 200, [84] = 250 }
      local id = item.id
      local stored = S.project.gen3Repel and (S.project.gen3Repel[id] or S.project.gen3Repel[item.index])
      local cur = stored
      if cur == nil then cur = defaults[id] or defaults[item.index] or 100 end
      local n = math.floor(require("RegList").num(App, "g3_repel", xx, yy, ww, fh, cur))
      n = math.max(0, math.min(999, n))
      if n ~= cur then
        S.project.gen3Repel = S.project.gen3Repel or {}
        local vanilla = defaults[id] or defaults[item.index] or 100
        local function put(key)
          if key == nil then return end
          S.project.gen3Repel[key] = n == vanilla and nil or n
        end
        put(id)
        put(item.index)
        if next(S.project.gen3Repel) == nil then S.project.gen3Repel = nil end
        App.markDirty()
      end
    end)
  end
  if item.fieldUse == "pp" then
    F.row("PP restored", function(xx, yy, ww)
      local id = item.id
      local stored = S.project.gen3PpRestore and (S.project.gen3PpRestore[id] or S.project.gen3PpRestore[item.index])
      local cur = stored ~= nil and stored or 10
      local n = math.floor(require("RegList").num(App, "g3_pp_restore", xx, yy, ww, fh, cur))
      n = math.max(0, math.min(63, n))
      if n ~= cur then
        S.project.gen3PpRestore = S.project.gen3PpRestore or {}
        local function put(key)
          if key == nil then return end
          S.project.gen3PpRestore[key] = n == 10 and nil or n
        end
        put(id)
        put(item.index)
        if next(S.project.gen3PpRestore) == nil then S.project.gen3PpRestore = nil end
        App.markDirty()
      end
    end)
  end
  if item.fieldUse == "revive" then
    F.row("Half-revive divisor", function(xx, yy, ww)
      local cur = S.project.gen3Revive and S.project.gen3Revive.div or 2
      local n = math.floor(require("RegList").num(App, "g3_revive_div", xx, yy, ww, fh, cur))
      n = math.max(1, math.min(16, n))
      if n ~= cur then
        S.project.gen3Revive = n == 2 and nil or { div = n }
        App.markDirty()
      end
    end)
  end
  F.text("description","Description")
  local held={["0"]="None"}
  for name,id in pairs(require("src.core.game3.battle.held_items").HOLD) do held[tostring(id)]=name:gsub("_"," ") end
  F.enum(S,"holdEffect","When held",held)
  F.number("holdEffectParam","Effect amount",0,255)
  F.enum(S,"importance","Can discard / sell",{["0"]="Yes (ordinary item)",["1"]="No (important item)",["2"]="No (special key item)"})
  F.enum(S,"registrability","Register to SELECT",{["0"]="No",["1"]="Yes"})
  F.enum(S,"battleUsage","Use in battle",{["0"]="Not usable",["1"]="Choose a party Pokemon",["2"]="Use directly"})
  F.number("secondaryId","Variant / secondary ID",0,65535)
  local yy,rec=F.finish()
  return require("Gen3Berries").draw(S,rec,App,x,yy+8*s,w,fh,s),rec
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
