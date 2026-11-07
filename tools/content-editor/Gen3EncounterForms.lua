local M={}
local Kit=require("Kit")
local List=require("RegList")
local Pane=require("FormPane")
local PAL=require("Theme").PAL
local kinds={{id="land",label="Grass",count=12},{id="water",label="Surf",count=5},
  {id="rocks",label="Rock Smash",count=5},{id="fishing",label="Fishing",count=10}}
local times={{id="all",label="All day"},{id="morning",label="Morning",tip="Its own list in the morning (GFX > Day & night)"},
  {id="day",label="Day",tip="Its own list by day"},{id="night",label="Night",tip="Its own list at night"}}
function M.draw(S,x,y,w,h,App)
  require("Gen3ContentAdapter").prepare(S)
  local s=Kit.scale
  -- GAME PATCHES > Encounter tables: keep Crystal's lists filled in (or
  -- taken back out) even if the switch was flipped somewhere else.
  if require("Gen3DayNight").syncCrystalPopulation(S) then App.markDirty() end
  local nextY=List.modeChips(S,"g3EncounterSection",{{id="wild",label="Wild encounters"},{id="roamers",label="Roaming Pokemon"},{id="settings",label="Settings"}},x,y,s)+8*s
  h=h-(nextY-y);y=nextY
  if S.g3EncounterSection=="settings" then return require("EncounterSettings").draw(S,x,y,w,h,App) end
  if S.g3EncounterSection=="roamers" then return require("Gen3Roamers").draw(S,x,y,w,h,App) end
  local ids=List.mergeIds(S.project.encounters,S.data.encounters)
  local labels=require("Gen3Labels")
  local DN0=require("Gen3DayNight") -- edited tables (all-day or time lists) show bright in the list
  -- one row per map (ROUTE1 / ROUTE_1 / FR_ROUTE_1 / "3:19" are one table);
  -- a project with two records for one map gets them merged first
  if labels.mergeDuplicateEncounters(S.project,S.data.encounters)>0 then
    App.markDirty();ids=List.mergeIds(S.project.encounters,S.data.encounters)
  end
  local preferred=labels.preferredEncounterIds(S.project.encounters,S.data.encounters)
  local function key(id) return labels.encounterKey(id,S.project.encounters,S.data.encounters) end
  local unique={}
  for _,id in ipairs(ids) do if preferred[key(id)]==id then unique[#unique+1]=id end end
  if S.g3EncounterId and preferred[key(S.g3EncounterId)]~=S.g3EncounterId then S.g3EncounterId=preferred[key(S.g3EncounterId)] end
  ids=unique
  table.sort(ids,function(a,b) return labels.natural(labels.map(a)..a,labels.map(b)..b) end)
  S.g3EncounterId=S.g3EncounterId or ids[1]
  local fx,fw=List.drawList(S,App,x,y,w,h,"WILD ENCOUNTERS",ids,
    {selKey="g3EncounterId",queryKey="encounterQuery",offsetKey="encounterOffset",label=labels.map,
    isOwned=function(id) return S.project.encounters[id]~=nil or DN0.hasTimeLists(S.project,id,"land") or DN0.hasTimeLists(S.project,id,"water") or DN0.hasTimeLists(S.project,id,"rocks") or DN0.hasTimeLists(S.project,id,"fishing") end})
  local id=S.g3EncounterId
  local rec=id and (S.project.encounters[id] or S.data.encounters[id])
  if not rec then Kit.caption(fx,y,"Select an encounter table");return end
  local function mutate()
    if not S.project.encounters[id] then S.project.encounters[id]=require("src.mods.Merge").deepCopy(rec) end
    rec=S.project.encounters[id];return rec
  end
  local top=List.modeChips(S,"g3EncounterKind",kinds,fx,y,s)+4*s
  local kind=S.g3EncounterKind or "land"
  local def=kinds[1];for _,v in ipairs(kinds) do if v.id==kind then def=v end end
  -- Time of day (GFX > Day & night): a list of its own for morning, day or
  -- night replaces the usual one then. GAME PATCHES > Encounter tables
  -- fills these in from Pokemon Crystal on FireRed's own tables -- from
  -- there they're just this table's own lists, edited the same as any other.
  local DN=require("Gen3DayNight")
  top=List.modeChips(S,"g3EncounterTime",times,fx,top,s)
  local period=S.g3EncounterTime or "all"
  local function defaultArea()
    local slots={};for i=1,def.count do slots[i]={species="PIDGEY",minLevel=2,maxLevel=5} end
    return {rate=20,slots=slots}
  end
  local area,write
  local timed=DN.hasTimeLists(S.project,id,kind)
  local clockOn=DN.enabled(S.project)
  local timeOn=clockOn and DN.encountersEnabled(S.project)
  local pinned=DN.isAllDay(S.project,id,kind)
  local changes=timed -- does this table change with the time?
  local function hint(text,colour)
    Kit.text("small",text,fx,top,colour or PAL.detail);top=top+24*s
  end
  -- Morning / day / night lists only while the real time clock and its
  -- Encounter tables are on (GAME PATCHES); otherwise the all-day list is
  -- the only one, and the only one you can set.
  if period~="all" and not timeOn then
    hint("Enable Real Time Clock mechanics to set Morning, Day and Night encounter tables",PAL.yellow)
    return
  end
  if timeOn and pinned and (period~="all" or changes) then
    hint("This table keeps its all-day list at every time; the others still change with the time",PAL.yellow)
  end
  -- Keep this one table on its all-day list, whatever the time lists say.
  local function keepAllDayChip()
    if not changes or not timeOn then return end
    local label="Keep the all-day list at every time"
    if Kit.chip(fx,top,Kit.textWidth("micro",label)+24*s,26*s,label,pinned,PAL.yellow,nil,
        "This table ignores its morning / day / night lists; other tables still change with the time")
        then DN.setAllDay(S.project,id,kind,not pinned);pinned=not pinned;App.markDirty() end
    top=top+32*s
  end
  if period=="all" then
    keepAllDayChip()
    if timeOn and timed and not pinned then
      -- Off while morning, day and night have lists of their own.
      Kit.caption(fx,top,"All-day "..def.label.." list is off: morning, day and night have their own lists")
      if Kit.button(fx,top+36*s,260*s,28*s,"Back to one all-day list",{kind="ghost",
          tooltip="Removes the morning, day and night lists"}) then
        DN.clearTimeLists(S.project,id,kind);App.markDirty()
      end
      return
    end
    area=rec[kind]
    write=function(fn) rec=mutate();fn(rec[kind]) end
  else
    local cfg=DN.settings(S.project)
    local after={morning="day",day="night",night="morning"}
    hint(("%s %d:00 to %d:00"):format(period=="morning" and "Morning" or period=="day" and "Day" or "Night",
      cfg[period],cfg[after[period]]))
    area=DN.timeArea(S.project,id,period,kind)
    write=function(fn) fn(DN.timeArea(S.project,id,period,kind)) end
    if not area then
      Kit.caption(fx,top,timed and ("No "..def.label.." list for this time yet")
        or ("Uses the all-day "..def.label.." list"))
      if Kit.button(fx,top+36*s,340*s,28*s,timed and "Give it its own list" or "Give morning, day and night their own lists",{kind="good",
          tooltip="Each starts as a copy of the all-day list, which is then off"}) then
        DN.startTimeLists(S.project,id,kind,rec[kind] or defaultArea());App.markDirty()
      end
      return
    end
  end
  if not area then
    Kit.caption(fx,top,"No "..def.label.." encounters on this map")
    if Kit.button(fx,top+36*s,210*s,28*s,"Add encounter table",{kind="good"}) then
      rec=mutate();rec[kind]=defaultArea();App.markDirty()
    end
    return
  end
  local tag=period..kind
  Kit.caption(fx,top,"Encounter rate")
  local rate=math.max(0,math.min(255,math.floor(List.num(App,"g3_enc_rate"..tag,fx+150*s,top,100*s,28*s,area.rate or 0))))
  if rate~=area.rate then write(function(a) a.rate=rate end);App.markDirty() end
  if Kit.button(fx+270*s,top,150*s,28*s,"Disable table",{}) then
    write(function(a) a.rate=0 end);App.markDirty()
  end
  if period~="all" and Kit.button(fx+426*s,top,220*s,28*s,"Back to one all-day list",{kind="ghost",
      tooltip="Removes the morning, day and night lists; the all-day list is on again"}) then
    DN.clearTimeLists(S.project,id,kind);App.markDirty();return
  end
  top=top+38*s
  Kit.caption(fx,top,kind=="fishing" and "Slots 1–2 Old Rod, 3–5 Good Rod, 6–10 Super Rod" or "Slot order preserves the game's encounter weights")
  top=top+28*s
  Pane.track(S,"g3EncounterScroll",id..tag)
  local first,view=Pane.begin(S,"g3EncounterScroll",fx,top,fw,h-(top-y)-42*s)
  local yy=first
  for i,slot in ipairs(area.slots or {}) do
    Kit.caption(fx,yy,"Slot "..i);yy=yy+22*s
    require("SpeciesPicker").field(S,{x=fx,y=yy,w=view.contentW*.6,h=28*s,current=slot.species,
      onPick=function(species) write(function(a) a.slots[i].species=species end);App.markDirty() end})
    local nx=fx+view.contentW*.62;local nw=view.contentW*.17
    local low=math.max(1,math.min(100,math.floor(List.num(App,"g3_enc_min_"..tag..i,nx,yy,nw,28*s,slot.minLevel or 1))))
    local high=math.max(low,math.min(100,math.floor(List.num(App,"g3_enc_max_"..tag..i,nx+nw+4*s,yy,nw,28*s,slot.maxLevel or low))))
    if low~=slot.minLevel or high~=slot.maxLevel then
      write(function(a) a.slots[i].minLevel=low;a.slots[i].maxLevel=high end);App.markDirty()
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
          S.project=staged.project;write(function(a) a.slots[i].species=species end);App.markDirty()
        end});yy=yy+40*s
    end
  end
  Pane.finish(S,"g3EncounterScroll",first,yy,view)
  if period=="all" and S.project.encounters[id] and Kit.button(fx,y+h-32*s,130*s,28*s,"Revert map",{}) then
    S.project.encounters[id]=nil;App.markDirty()
  end
end
return M
