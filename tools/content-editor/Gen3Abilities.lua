-- Browse existing abilities and assign them without entering internal IDs.
local M={}
function M.name(id) return tostring(id):gsub("_"," "):lower():gsub("%f[%a]%l",string.upper) end
function M.draw(S,x,y,w,h,App)
  local K,L=require("Kit"),require("RegList");local s=K.scale;local bottom=y+h
  local ids,labels={},{}
  for _,name in pairs((S.data.gen3Pokemon or {}).abilityNames or {}) do
    local id=require("src.mods.Schemas").gen3View.idOf(name)
    if id and not labels[id] then ids[#ids+1]=id;labels[id]=M.name(id) end
  end
  for _,r in pairs(S.project.gen3Behaviors or {}) do
    if r.kind=="ability" then ids[#ids+1]=tostring(r.index);labels[tostring(r.index)]=r.name end
  end
  table.sort(ids)
  S.g3AbilityId=S.g3AbilityId or ids[1]
  local fx,fw=L.drawList(S,App,x,y,w,h,"ABILITIES",ids,{selKey="g3AbilityId",queryKey="g3AbilityQuery",offsetKey="g3AbilityOffset",label=function(id) return labels[id] end})
  local id=S.g3AbilityId;if not id then return end
  K.caption(fx,y,labels[id]);y=y+36*s
  K.caption(fx,y,"Give this ability to a Pokemon");y=y+30*s
  require("SpeciesPicker").field(S,{x=fx,y=y,w=fw,h=28*s,current=S.g3AbilitySpecies or "BULBASAUR",
    onPick=function(value) S.g3AbilitySpecies=value end});y=y+36*s
  require("ChoicePicker").field(S,{x=fx,y=y,w=fw,h=28*s,current=S.g3AbilitySlot or "1",ids={"1","2"},
    labels={["1"]="First ability",["2"]="Second ability"},onPick=function(value) S.g3AbilitySlot=value end});y=y+36*s
  if K.button(fx,y,180*s,28*s,"Assign ability",{kind="good"}) then
    local species=S.g3AbilitySpecies or "BULBASAUR"
    local base=S.project.pokemon[species] or S.data.pokemon[species]
    if base then
      local rec=require("src.mods.Merge").deepCopy(base);rec.abilities=rec.abilities or {}
      rec.abilities[tonumber(S.g3AbilitySlot or "1")]=tonumber(id) or id;S.project.pokemon[species]=rec;App.markDirty()
      S.status=labels[id].." assigned to "..M.name(species)
    end
  end
  y=y+42*s
  K.caption(fx,y,"Use Create abilities / effects to build a new behavior.");y=y+32*s
  K.caption(fx,y,"Pokemon with this ability");y=y+30*s
  local top,view=require("FormPane").begin(S,"g3AbilityUsers",fx,y,fw,math.max(60*s,bottom-y))
  -- The parent panel clips this list to its available space.
  local yy=top
  for _,species in ipairs(L.mergeIds(S.project.pokemon,S.data.pokemon)) do
    local rec=S.project.pokemon[species] or S.data.pokemon[species]
    if tostring((rec.abilities or {})[1])==id or tostring((rec.abilities or {})[2])==id then
      if K.button(fx,yy,view.contentW,28*s,M.name(species),{}) then S.g3AbilitySpecies=species end
      yy=yy+34*s
    end
  end
  require("FormPane").finish(S,"g3AbilityUsers",top,yy,view)
end
return M
