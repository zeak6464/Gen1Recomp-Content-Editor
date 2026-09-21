local M={}
local Kit=require("Kit")
local List=require("RegList")
local Pane=require("FormPane")
local PAL=require("Theme").PAL
local kinds={{id="land",label="Grass",count=12},{id="water",label="Surf",count=5},
  {id="rocks",label="Rock Smash",count=5},{id="fishing",label="Fishing",count=10}}
function M.draw(S,x,y,w,h,App)
  require("Gen3ContentAdapter").prepare(S)
  local s=Kit.scale
  local nextY=List.modeChips(S,"g3EncounterSection",{{id="wild",label="Wild encounters"},{id="roamers",label="Roaming Pokemon"}},x,y,s)+8*s
  h=h-(nextY-y);y=nextY
  if S.g3EncounterSection=="roamers" then return require("Gen3Roamers").draw(S,x,y,w,h,App) end
  local ids=List.mergeIds(S.project.encounters,S.data.encounters)
  local labels=require("Gen3Labels")
  local preferred={}
  for _,id in ipairs(ids) do
    local name=labels.map(id);local old=preferred[name]
    if not old or S.project.encounters[id] or (not S.project.encounters[old] and not id:match("^%d+:")) then preferred[name]=id end
  end
  local unique={}
  for _,id in ipairs(ids) do if preferred[labels.map(id)]==id or S.project.encounters[id] then unique[#unique+1]=id end end
  if S.g3EncounterId and not S.project.encounters[S.g3EncounterId] then S.g3EncounterId=preferred[labels.map(S.g3EncounterId)] end
  ids=unique
  table.sort(ids,function(a,b) return labels.natural(labels.map(a)..a,labels.map(b)..b) end)
  S.g3EncounterId=S.g3EncounterId or ids[1]
  local fx,fw=List.drawList(S,App,x,y,w,h,"WILD ENCOUNTERS",ids,
    {selKey="g3EncounterId",queryKey="encounterQuery",offsetKey="encounterOffset",label=labels.map})
  local id=S.g3EncounterId
  local rec=id and (S.project.encounters[id] or S.data.encounters[id])
  if not rec then Kit.caption(fx,y,"Select an encounter table");return end
  local function mutate()
    if not S.project.encounters[id] then S.project.encounters[id]=require("src.mods.Merge").deepCopy(rec) end
    rec=S.project.encounters[id];return rec
  end
  local top=List.modeChips(S,"g3EncounterKind",kinds,fx,y,s)+8*s
  local kind=S.g3EncounterKind or "land"
  local def=kinds[1];for _,v in ipairs(kinds) do if v.id==kind then def=v end end
  local area=rec[kind]
  if not area then
    Kit.caption(fx,top,"No "..def.label.." encounters on this map")
    if Kit.button(fx,top+36*s,210*s,28*s,"Add encounter table",{kind="good"}) then
      rec=mutate();local slots={};for i=1,def.count do slots[i]={species="PIDGEY",minLevel=2,maxLevel=5} end
      rec[kind]={rate=20,slots=slots};App.markDirty()
    end
    return
  end
  Kit.caption(fx,top,"Encounter rate")
  local rate=math.max(0,math.min(255,math.floor(List.num(App,"g3_enc_rate",fx+150*s,top,100*s,28*s,area.rate or 0))))
  if rate~=area.rate then rec=mutate();rec[kind].rate=rate;App.markDirty() end
  if Kit.button(fx+270*s,top,150*s,28*s,"Disable table",{}) then
    rec=mutate();rec[kind].rate=0;App.markDirty()
  end
  top=top+38*s
  Kit.caption(fx,top,kind=="fishing" and "Slots 1–2 Old Rod, 3–5 Good Rod, 6–10 Super Rod" or "Slot order preserves the game's encounter weights")
  top=top+28*s
  Pane.track(S,"g3EncounterScroll",id..kind)
  local first,view=Pane.begin(S,"g3EncounterScroll",fx,top,fw,h-(top-y)-42*s)
  local yy=first
  for i,slot in ipairs(area.slots or {}) do
    Kit.caption(fx,yy,"Slot "..i);yy=yy+22*s
    require("SpeciesPicker").field(S,{x=fx,y=yy,w=view.contentW*.6,h=28*s,current=slot.species,
      onPick=function(species) rec=mutate();rec[kind].slots[i].species=species;App.markDirty() end})
    local nx=fx+view.contentW*.62;local nw=view.contentW*.17
    local low=math.max(1,math.min(100,math.floor(List.num(App,"g3_enc_min_"..i,nx,yy,nw,28*s,slot.minLevel or 1))))
    local high=math.max(low,math.min(100,math.floor(List.num(App,"g3_enc_max_"..i,nx+nw+4*s,yy,nw,28*s,slot.maxLevel or low))))
    if low~=slot.minLevel or high~=slot.maxLevel then
      rec=mutate();rec[kind].slots[i].minLevel=low;rec[kind].slots[i].maxLevel=high;App.markDirty()
    end
    yy=yy+40*s
    local forms=require("Gen3Forms")
    local formIds,formLabels,currentForm,parent=forms.encounterChoices(S,slot.species)
    if #formIds>1 then
      Kit.caption(fx,yy,"Form");yy=yy+22*s
      require("ChoicePicker").field(S,{x=fx,y=yy,w=view.contentW,h=28*s,current=currentForm,ids=formIds,labels=formLabels,title="Wild Pokemon form",
        tooltip=parent=="CASTFORM" and "Forecast can change Castform's appearance with the weather during battle." or "Choose a specific form, or keep the game's automatic selection.",
        onPick=function(choice)
          local staged=setmetatable({project=require("src.mods.Merge").deepCopy(S.project)},{__index=S})
          local ok,species=pcall(forms.encounterSpecies,staged,parent,choice)
          if not ok then S.status=tostring(species);return end
          S.project=staged.project;rec=mutate();rec[kind].slots[i].species=species;App.markDirty()
        end});yy=yy+40*s
    end
  end
  Pane.finish(S,"g3EncounterScroll",first,yy,view)
  if S.project.encounters[id] and Kit.button(fx,y+h-32*s,130*s,28*s,"Revert map",{}) then
    S.project.encounters[id]=nil;App.markDirty()
  end
end
return M
