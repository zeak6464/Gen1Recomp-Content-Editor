local K=require("Kit")
local P=require("ChoicePicker")
local L=require("RegList")
local Panel={}
-- Named encounters verified against FireRed map scripts.
Panel.gifts={
  {"EEVEE","Celadon Mansion - Eevee","FR_CELADON_CITY_CONDOMINIUMS_ROOF_ROOM",25},
  {"LAPRAS","Silph Co. 7F - Lapras","FR_SILPH_CO_7F",25},
  {"HITMONLEE","Fighting Dojo - Hitmonlee","FR_SAFFRON_CITY_DOJO",25},
  {"HITMONCHAN","Fighting Dojo - Hitmonchan","FR_SAFFRON_CITY_DOJO",25},
  {"OMANYTE","Helix Fossil - Omanyte","FR_CINNABAR_ISLAND_POKEMON_LAB_EXPERIMENT_ROOM",5},
  {"KABUTO","Dome Fossil - Kabuto","FR_CINNABAR_ISLAND_POKEMON_LAB_EXPERIMENT_ROOM",5},
  {"AERODACTYL","Old Amber - Aerodactyl","FR_CINNABAR_ISLAND_POKEMON_LAB_EXPERIMENT_ROOM",5},
  {"TOGEPI","Water Labyrinth - Togepi Egg","FR_FIVE_ISLAND_WATER_LABYRINTH",5,true},
}
function Panel.addGift(S,id)
  for _,g in ipairs(Panel.gifts) do if g[1]==id then
    S.project.gen3Starters=S.project.gen3Starters or {}
    for _,r in ipairs(S.project.gen3Starters) do if r.preset==id then return r end end
    local r={preset=id,label=g[2],map=g[3],matchSpecies={id},species=id,level=g[4],egg=g[5] or false,nickname="",onlyFirst=false}
    table.insert(S.project.gen3Starters,r);return r
  end end
end
function Panel.add(S,kind)
  S.project.gen3Starters=S.project.gen3Starters or {}
  local rows=S.project.gen3Starters
  if kind=="starters" then
    for _,species in ipairs({"BULBASAUR","CHARMANDER","SQUIRTLE"}) do
      local found=false
      for _,r in ipairs(rows) do if r.map=="FR_OAKS_LAB" and r.onlyFirst then for _,v in ipairs(r.matchSpecies or {}) do if v==species then found=true end end end end
      if not found then rows[#rows+1]={map="FR_OAKS_LAB",matchSpecies={species},species=species,level=5,nickname="",onlyFirst=true,variable=0x4002} end
    end
  else return Panel.addGift(S,"EEVEE") end
end
function Panel.draw(S,x,y,w,h,App)
  if not S.project then K.caption(x,y,"Open a Gen 3 mod first");return end
  local s=K.scale
  K.caption(x,y,"Choose starter and gift Pokemon by name. Save your mod to apply changes.")
  if K.button(x,y+28*s,220*s,29*s,"Change starter choices",{kind="good"}) then Panel.add(S,"starters");App.markDirty() end
  local ids,labels={},{};for _,g in ipairs(Panel.gifts) do ids[#ids+1]=g[1];labels[g[1]]=g[2] end
  P.field(S,{x=x+230*s,y=y+28*s,w=math.min(w-230*s,480*s),h=29*s,current="",emptyLabel="Choose a gift Pokemon to edit",ids=ids,labels=labels,title="Gift Pokemon encounter",onPick=function(id) Panel.addGift(S,id);App.markDirty() end})
  local top,view=require("FormPane").begin(S,"g3StarterScroll",x,y+72*s,w,h-72*s)
  y=top;w=view.contentW
  local rules=S.project.gen3Starters or {}
  if #rules==0 then K.caption(x,y,"Start above: edit Oak's three choices, or replace a Pokemon given as a gift.");y=y+35*s end
  local maps=L.mergeIds(S.project.maps or {},S.data.maps or {});local names={}
  for _,id in ipairs(maps) do names[id]=id:gsub("^FR_",""):gsub("_"," ") end
  for i,r in ipairs(rules) do
    K.caption(x,y,r.label or (r.onlyFirst and "Oak starter - "..table.concat(r.matchSpecies or {}," / ") or "Gift Pokemon "..i))
    if K.button(x+w-160*s,y,150*s,27*s,"Remove change",{}) then table.remove(rules,i);App.markDirty();break end
    y=y+36*s
    local function picker(label,draw)
      K.caption(x,y,label);draw(x+210*s,y,w-220*s);y=y+37*s
    end
    picker("Where it is given",function(px,py,pw) P.field(S,{x=px,y=py,w=pw,h=28*s,ids=maps,labels=names,current=r.map,title="CHOOSE MAP",onPick=function(v) r.map=v;App.markDirty() end}) end)
    for j,source in ipairs(r.matchSpecies or {}) do
      if r.onlyFirst and r.map=="FR_OAKS_LAB" then
        picker("Original starter choice",function(px,py,pw) K.caption(px,py,(source:gsub("_"," "))) end)
      else
        picker(j==1 and "Original Pokemon" or "Also replace",function(px,py,pw) require("SpeciesPicker").field(S,{x=px,y=py,w=pw,h=28*s,current=source,onPick=function(v) r.matchSpecies[j]=v;App.markDirty() end}) end)
      end
    end
    picker("Give this Pokemon",function(px,py,pw) require("SpeciesPicker").field(S,{x=px,y=py,w=pw,h=28*s,current=r.species,onPick=function(v) r.species=v;App.markDirty() end}) end)
    picker(r.egg and "Hatching level (1 to 100)" or "Level (1 to 100)",function(px,py,pw)
      local v=K.textfield("starterLevel/"..i,px,py,pw,28*s,tostring(r.level),"");local n=tonumber(v)
      if n and n%1==0 and n>=1 and n<=100 and n~=r.level then r.level=n;App.markDirty() end
    end)
    picker("Nickname (optional)",function(px,py,pw)
      local v=K.textfield("starterName/"..i,px,py,pw,28*s,r.nickname or "","")
      if v~=(r.nickname or "") then r.nickname=v;App.markDirty() end
    end)
    K.caption(x,y,r.onlyFirst and "Applies when choosing the first Pokemon. Edit the NPC's dialogue in Dialog." or "Replaces matching gifts on this map. The original event controls when the gift is given.")
    y=y+44*s
  end
  require("FormPane").finish(S,"g3StarterScroll",top,y,view)
end
return Panel
