-- Map-first event editing: context on the left, actions and settings on the right.
local M={}
local groups={objects={"Characters", "mapObjectIndex"},signs={"Signs", "mapSignIndex"},coordEvents={"Step-on events", "g3CoordIndex"},warps={"Exits","mapWarpIndex"}}
function M.events(map)
  local ids,labels,events={},{},{}
  for _,kind in ipairs({"objects","signs","coordEvents","warps"}) do
    for i,event in ipairs((map or {})[kind] or {}) do
      local id=kind.."/"..i;ids[#ids+1]=id
      labels[id]=(kind=="objects" and "Character " or kind=="signs" and "Sign " or kind=="warps" and "Exit " or "Step-on event ")
        ..tostring(event.localId or i).." at "..tostring(event.x)..", "..tostring(event.y)
      events[id]={kind=kind,index=i,event=event}
    end
  end
  return ids,labels,events
end
function M.copyScript(S,mapId,kind,index)
  local copy=require("src.mods.Merge").deepCopy
  local T=setmetatable({project=copy(S.project)},{__index=S})
  local ok,result=pcall(function()
    local converted,err=require("Gen3Workspace").convert(T,mapId);assert(converted,err)
    local event=assert((T.project.maps[mapId][kind] or {})[index],"Choose a map event")
    local catalog=require("Gen3").catalog(S.data,"map_scripts")
    local p=T.project;p.gen3=p.gen3 or {};p.gen3.map_scripts=p.gen3.map_scripts or {}
    local source=p.gen3.map_scripts[event.scriptKey] or catalog[event.scriptKey]
    local base="EditorEvent_"..tostring(p.id):gsub("[^%w_]","_").."_";local n=1
    while p.gen3.map_scripts[base..n] or catalog[base..n] do n=n+1 end
    local id=base..n;p.gen3.map_scripts[id]=copy(source or {{op="end"}})
    p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
    p.gen3Modes.map_scripts[id]="register";event.scriptKey=id
    return id
  end)
  if not ok then return nil,tostring(result) end
  for k in pairs(S.project) do S.project[k]=nil end
  for k,v in pairs(T.project) do S.project[k]=v end
  return result
end
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local P=require("ChoicePicker");local L=require("RegList");local s=K.scale
  local left=math.min(290*s,w*.25);local fx=x+left+20*s;local fw=w-left-20*s
  local baseMaps=require("Generation").dataMaps(S)
  local maps=L.mergeIds(S.project.maps or {},baseMaps);local names={}
  for _,id in ipairs(maps) do names[id]=require("Gen3Names").map(id) end
  S.g3EventMap=S.g3EventMap or S.mapId or maps[1]
  local top,view=require("FormPane").begin(S,"g3EventContext",x,y,left,h);local yy=top;local width=view.contentW
  local function caption(label)
    K.text("small",K.ellipsize("small",label,width),x,yy,require("Theme").PAL.text)
    K.offerTooltip(x,yy,width,24*s,label);yy=yy+26*s
  end
  caption("MAP")
  if S._eventWindowTarget then caption(names[S.g3EventMap] or S.g3EventMap)
  else
    P.field(S,{x=x,y=yy,w=width,h=29*s,ids=maps,labels=names,current=S.g3EventMap,title="CHOOSE MAP",
      onPick=function(id) S.g3EventMap=id;S.g3MapEventId=nil end});yy=yy+42*s
  end
  local map=(S.project.maps or {})[S.g3EventMap] or baseMaps[S.g3EventMap]
  local ids,labels,events=M.events(map)
  if not events[S.g3MapEventId] then S.g3MapEventId=ids[1] end
  caption("EVENT")
  if S._eventWindowTarget then caption(labels[S.g3MapEventId] or "Event missing")
  else
    P.field(S,{x=x,y=yy,w=width,h=29*s,ids=ids,labels=labels,current=S.g3MapEventId,title="CHOOSE EVENT",
      emptyLabel="No events on this map",onPick=function(id) S.g3MapEventId=id end});yy=yy+43*s
  end
  local selected=events[S.g3MapEventId]
  if selected then
    local ev=selected.event
    local eventScript=ev.scriptKey and (((S.project.gen3 or {}).map_scripts or {})[ev.scriptKey] or require("Gen3").catalog(S.data,"map_scripts")[ev.scriptKey])
    local pickup=selected.kind=="objects" and require("Gen3EventStory").itemPickup(eventScript)
    caption("STARTS WHEN")
    caption(pickup and "Player picks up this Poké Ball" or selected.kind=="objects" and "Player talks to this character" or selected.kind=="signs" and "Player interacts with this sign" or "Player steps on this tile")
    yy=yy+10*s;caption("CONDITIONS")
    if selected.kind=="objects" then
      caption((ev.flag or 0)==0 and "Always visible" or pickup and "Disappears after the player picks it up" or "Hidden when switch "..ev.flag.." is ON")
    elseif selected.kind=="coordEvents" then caption("Variable "..tostring(ev.var or 0).." equals "..tostring(ev.value or 0))
    else caption(selected.kind=="warps" and "Uses the exit's map settings" or "Uses the sign's map settings") end
    yy=yy+10*s
    if K.button(x,yy,width,29*s,S.g3InlineEventSettings and "Hide event settings" or "Edit appearance / conditions",{}) then S.g3InlineEventSettings=not S.g3InlineEventSettings end
    yy=yy+40*s
    if S.g3InlineEventSettings then
      yy=require("Gen3MapEventForm").draw(S,ev,selected.kind,groups[selected.kind][2],x,yy,width,App,
        {mapId=S.g3EventMap,index=selected.index})
      yy=yy+10*s
    elseif selected.kind=="objects" then
      caption(pickup and "ITEM ON MAP" or "CHARACTER")
      if require("Gen3MapSprites").draw(S,ev,x+16*s,yy+24*s) then yy=yy+58*s
      else caption("Sprite "..tostring(ev.graphicsId or ev.graphics or "not set")) end
      if pickup then
        local name=require("Gen3EventStory").itemName(S,pickup.item)
        caption((pickup.quantity>1 and pickup.quantity.." × " or "")..name)
      else
        local movement=({[0]="Stay in place",[1]="Look around",[2]="Walk around",[7]="Face up",[8]="Face down",[9]="Face left",[10]="Face right"})[ev.movementType]
        caption(movement or "Movement set on map")
      end
    end
    if not S._eventWindowTarget and K.button(x,yy,width,29*s,"Open event window",{}) then
      require("Gen3EventWindow").request(S,S.g3EventMap,selected.kind,selected.index)
    end
    if not S._eventWindowTarget then yy=yy+40*s end
    if not S._eventWindowTarget and K.button(x,yy,width,29*s,"Show on map",{}) then
      S.mapId=S.g3EventMap;S.mapSection=selected.kind;S[groups[selected.kind][2]]=selected.index
      S.mapEditMode="events";S.tab="maps"
    end
    yy=yy+44*s
    if not S._eventWindowTarget and selected.kind=="objects" and K.button(x,yy,width,29*s,"Create conversation / reward",{kind="good"}) then
      S.g3EventMode="builder";S._eventBuilderProject=S.project
      S.eventBuilder={kind="dialog",map=S.g3EventMap,npc=selected.kind=="objects" and tostring(selected.index) or nil,
        text="Hello!",item="POTION",quantity="1",success="Here you go!",done="Enjoy your reward!"}
    end
    yy=yy+40*s
    if selected.kind~="warps" and K.button(x,yy,width,29*s,ev.scriptKey and "Make unique copy" or "Add command list",{}) then
      local id,err=M.copyScript(S,S.g3EventMap,selected.kind,selected.index)
      if id then S.gen3Id=id;App.markDirty();S.status="Separate command list attached to this event." else S.status=err end
    end
    yy=yy+38*s
    caption("Other events may share this script.")
    caption("A unique copy gets its own actions.")
  else
    caption("Place a character, sign or trigger")
    caption("using Maps > Add events.")
    if K.button(x,yy,width,29*s,"Open map",{}) then S.mapId=S.g3EventMap;S.mapEditMode="events";S.tab="maps" end
    yy=yy+40*s
  end
  require("FormPane").finish(S,"g3EventContext",top,yy,view)
  if selected then
    local ev=(((S.project.maps or {})[S.g3EventMap] or map)[selected.kind] or {})[selected.index]
    if selected.kind=="warps" then K.caption(fx,y,"Choose the destination in the event settings.")
    elseif ev.scriptKey then require("Gen3Events").drawScript(S,ev.scriptKey,fx,y,fw,h,App)
    else K.caption(fx,y,"Add a command list to choose what happens.") end
  else K.caption(fx,y,"Choose a map event to edit its actions.") end
end
return M
