-- RPG Maker-style event window: page/settings at left, command list at right.
local M={}
local K=require("Kit")
local PAL=require("Theme").PAL
local copy=require("src.mods.Merge").deepCopy
local groups={objects="Character",signs="Sign",coordEvents="Trigger",warps="Exit"}
local movementNames={[0]="Fixed",[1]="Look around",[2]="Walk around",[7]="Face up",[8]="Face down",[9]="Face left",[10]="Face right"}
local function mutateEvent(S,target,App,key,value)
  assert(require("Gen3Workspace").convert(S,target.mapId))
  local row=S.project.maps[target.mapId][target.kind][target.index]
  row[key]=value
  if key=="graphicsId" then row.graphics=value end
  if key=="movementType" then
    local m=require("src.core.game3.scripting.gfx_ids").hostMovement(value,row.rangeX,row.rangeY)
    row.movement,row.range,row.radius=m.movement,m.range,m.radius
  end
  App.markDirty()
end
local function box(x,y,w,h,title)
  K.card(x,y,w,h,5);K.caption(x+10*K.scale,y+8*K.scale,title);return y+34*K.scale
end
local function choice(S,x,y,w,current,ids,labels,title,onPick,extra)
  extra=extra or {};require("ChoicePicker").field(S,{x=x,y=y,w=w,h=28*K.scale,current=tostring(current or ""),ids=ids,labels=labels,title=title,onPick=onPick,
    rowHeight=extra.rowHeight,drawRow=extra.drawRow})
end
local function scriptFor(S,event)
  local catalog=require("Gen3").catalog(S.data,"map_scripts")
  local key=event.scriptKey or event.touchScriptKey
  return key and (((S.project.gen3 or {}).map_scripts or {})[key] or catalog[key]),catalog,key
end
local function saveScript(S,id,rows,App)
  S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
  S.project.gen3.map_scripts[id]=copy(rows);S._g3ScriptSource=nil;App.markDirty()
end
local function editItem(S,row,eventId,catalog,x,y,w,App)
  K.caption(x,y,"Item");y=y+23*K.scale
  require("ItemPicker").field(S,{x=x,y=y,w=w,h=28*K.scale,current=row.itemId or "",title="CHOOSE ITEM",onPick=function(id)
    local index=require("ItemPicker").indexForId(S,id);if not index then return end
    local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script]
    local rows=copy(source);rows[row.index][2]=index;if rows[row.index].value~=nil then rows[row.index].value=index end
    saveScript(S,row.script,rows,App)
  end});y=y+39*K.scale
  K.caption(x,y,"Quantity");y=y+23*K.scale
  local value=K.textfield("rpg/item/"..row.script.."/"..row.index,x,y,120*K.scale,28*K.scale,tostring(row.quantity),"")
  local n=tonumber(value)
  if n and n==math.floor(n) and n>=1 and n<=999 and n~=row.quantity then
    local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script]
    local rows=copy(source);rows[row.index+1][2]=n;if rows[row.index+1].value~=nil then rows[row.index+1].value=n end
    saveScript(S,row.script,rows,App)
  end
end
local function editDialogue(S,row,catalog,x,y,w,App)
  local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script]
  local step=source and source[row.index];if not step then return end
  local text=require("Gen3EventActions").text(S,step) or row.text or ""
  local key=row.script.."/"..row.index
  if not S._g3RpgText or S._g3RpgText.key~=key or S._g3RpgText.source~=text then
    S._g3RpgText={key=key,source=text,value=text}
  end
  local draft=S._g3RpgText
  K.caption(x,y,"What the player reads");y=y+23*K.scale
  draft.value=K.textfield("rpg/text/"..key,x,y,w,29*K.scale,draft.value,"")
  y=y+39*K.scale
  if K.button(x,y,110*K.scale,28*K.scale,"Apply text",{kind="good",enabled=draft.value~=text}) and draft.value~=text then
    local rows=copy(source);require("Gen3EventActions").setText(S,rows[row.index],draft.value)
    saveScript(S,row.script,rows,App);S._g3RpgText=nil
  end
  K.text("small","Use \\n for a new line.",x+124*K.scale,y+6*K.scale,PAL.faint)
end
local function editWildBattle(S,row,catalog,x,y,w,App)
  K.caption(x,y,"Wild Pokémon");y=y+23*K.scale
  require("SpeciesPicker").field(S,{x=x,y=y,w=w,h=29*K.scale,current=row.speciesId or "",title="CHOOSE WILD POKÉMON",onPick=function(id)
    local index=require("SpeciesPicker").indexForId(S,id);if not index then return end
    local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script];local rows=copy(source);local step=rows[row.index]
    step[1]=index;step.species=index;saveScript(S,row.script,rows,App)
  end});y=y+40*K.scale
  K.caption(x,y,"Level");y=y+23*K.scale
  local value=K.textfield("rpg/wildLevel/"..row.script.."/"..row.index,x,y,120*K.scale,28*K.scale,tostring(row.level),"")
  local level=tonumber(value)
  if level and level==math.floor(level) and level>=1 and level<=100 and level~=row.level then
    local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script];local rows=copy(source);local step=rows[row.index]
    step[2]=level;step.level=level;saveScript(S,row.script,rows,App)
  end
end
local function editTrainerBattle(S,row,catalog,x,y,w,App)
  K.caption(x,y,"Trainer");y=y+23*K.scale
  local ids,labels={},{}
  for id,rec in pairs(S.data.trainers or {}) do
    if type(rec)=="table" and type(rec.index)=="number" then local key=tostring(rec.index);ids[#ids+1]=key;labels[key]=tostring(rec.name or rec.trainerName or id).."  ("..key..")" end
  end
  for id,rec in pairs(S.project.trainers or {}) do
    if type(rec)=="table" and type(rec.index)=="number" then local key=tostring(rec.index);if not labels[key] then ids[#ids+1]=key end;labels[key]=tostring(rec.name or id).."  ("..key..")" end
  end
  table.sort(ids,require("Gen3Labels").natural)
  choice(S,x,y,w,row.trainer,ids,labels,"CHOOSE TRAINER",function(id)
    local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script];local rows=copy(source);local step=rows[row.index];local trainer=tonumber(id)
    step[1]=trainer;step.trainer=trainer;saveScript(S,row.script,rows,App)
  end)
end
local function triggerOwner(target,event)
  return target.kind.."/"..tostring(event.localId or target.index)
end
local function setTrigger(S,target,event,want,App)
  if target.kind~="objects" and target.kind~="signs" then return end
  assert(require("Gen3Workspace").convert(S,target.mapId))
  local map=S.project.maps[target.mapId];event=map[target.kind][target.index]
  local owner=triggerOwner(target,event);map.coordEvents=map.coordEvents or {}
  local found
  for i,row in ipairs(map.coordEvents) do if row._editorTriggerOwner==owner then found=i;break end end
  if event.trigger=="player_touch" and want~="player_touch" then
    local trigger=found and map.coordEvents[found]
    event.scriptKey=event.touchScriptKey or (trigger and trigger.scriptKey);event.touchScriptKey=nil
    if found then table.remove(map.coordEvents,found);found=nil end
  end
  if want=="player_touch" and event.trigger~="player_touch" then
    local script=event.scriptKey or event.touchScriptKey
    if not found then map.coordEvents[#map.coordEvents+1]={x=event.x,y=event.y,elevation=event.elevation,var=nil,value=0,scriptKey=script,_editorTriggerOwner=owner}
    else map.coordEvents[found].scriptKey=script end
    event.touchScriptKey=script;event.scriptKey=nil;event.trigger="player_touch"
  elseif want~="player_touch" then
    if want=="action_button" then event.trigger=nil else event.trigger=want end
  end
  App.markDirty()
end
M.setTrigger=setTrigger
function M.draw(S,x,y,w,h,App)
  local s=K.scale;local target=assert(S._eventWindowTarget);local base=require("Generation").dataMaps(S)
  local map=(S.project.maps or {})[target.mapId] or base[target.mapId]
  local event=assert((map[target.kind] or {})[target.index]);local rows,catalog,eventScriptKey=scriptFor(S,event)
  local name=event.editorName or (groups[target.kind] or "Event").." "..target.index
  K.caption(x,y,"Name:")
  local entered=K.textfield("rpgEventName",x+58*s,y-5*s,230*s,28*s,name,"")
  if entered~=name and entered:match("%S") then mutateEvent(S,target,App,"editorName",entered);event.editorName=entered end
  local bx=x+310*s
  if K.button(bx,y-6*s,90*s,32*s,"New Page",{enabled=false,tooltip="FireRed map events use one event page"}) then end
  if K.button(bx+98*s,y-6*s,92*s,32*s,"Copy Page",{enabled=rows~=nil}) and rows then S._g3CopiedEventPage=copy(rows) end
  if K.button(bx+198*s,y-6*s,96*s,32*s,"Paste Page",{enabled=S._g3CopiedEventPage~=nil and eventScriptKey~=nil}) then saveScript(S,eventScriptKey,S._g3CopiedEventPage,App) end
  if K.button(bx+302*s,y-6*s,96*s,32*s,"Clear Page",{enabled=rows~=nil}) then saveScript(S,eventScriptKey,{{op="end"}},App) end
  y=y+42*s
  K.button(x,y,44*s,25*s,"1",{kind="accent"});y=y+32*s
  local left=340*s;local gap=14*s;local rx=x+left+gap;local rw=w-left-gap
  local conditionH=165*s;local cy=box(x,y,left,conditionH,"Conditions")
  if target.kind=="objects" then
    local enabled=(event.flag or 0)~=0
    local checked=K.checkbox(x+12*s,cy,left-24*s,25*s,enabled,"Hide when saved switch is ON")
    if checked~=enabled then
      local flag=0
      if checked then local used=require("Gen3Quests").usedFlags(S);for n=0x900,0xFFF do if not used[n] then flag=n;break end end end
      mutateEvent(S,target,App,"flag",flag);event.flag=flag
    end
    cy=cy+33*s;K.caption(x+30*s,cy,"Switch")
    local fv=K.textfield("rpgEventFlag",x+105*s,cy-5*s,left-120*s,27*s,tostring(event.flag or 0),"0")
    local fn=tonumber(fv);if enabled and fn and fn>=32 and fn<=4095 and fn==math.floor(fn) and fn~=event.flag then mutateEvent(S,target,App,"flag",fn);event.flag=fn end
  elseif target.kind=="coordEvents" then
    K.caption(x+12*s,cy,"Saved value");local vv=K.textfield("rpgEventVar",x+100*s,cy-5*s,left-115*s,27*s,tostring(event.var or 0),"")
    cy=cy+36*s;K.caption(x+12*s,cy,"equals");local value=K.textfield("rpgEventValue",x+100*s,cy-5*s,left-115*s,27*s,tostring(event.value or 0),"")
    local vn=tonumber(vv);if vn and vn==math.floor(vn) and vn~=event.var then mutateEvent(S,target,App,"var",vn);event.var=vn end
    local n=tonumber(value);if n and n==math.floor(n) and n~=event.value then mutateEvent(S,target,App,"value",n);event.value=n end
  else K.text("small","No start condition",x+14*s,cy,PAL.text) end
  local gy=y+conditionH+10*s;local half=(left-10*s)/2
  local inside=box(x,gy,half,160*s,"Appearance")
  if target.kind=="objects" then
    require("Gen3MapSprites").draw(S,event,x+half/2-8*s,inside+42*s)
    local ids,labels={},{};for path in pairs(require("Gen3Resources").assets(S.data)) do local id=path:match("/ow/(%d+)%.rgba$");if id then ids[#ids+1]=id;labels[id]="Sprite "..id end end;table.sort(ids,require("Gen3Labels").natural)
    choice(S,x+10*s,gy+120*s,half-20*s,event.graphicsId or event.graphics,ids,labels,"CHOOSE GRAPHIC",function(id) mutateEvent(S,target,App,"graphicsId",tonumber(id)) end,
      {rowHeight=48,drawRow=function(state,id,px,py,pw,ph,label,on)
        require("Gen3MapSprites").draw(state,{graphicsId=tonumber(id)},px+8*s,py+8*s,{scale=2})
        K.text("small",K.ellipsize("small",label,pw-58*s),px+52*s,py+(ph-K.textHeight("small"))/2,on and PAL.heading or PAL.text)
      end})
  else K.text("small",target.kind=="warps" and "Map exit" or "No graphic",x+12*s,inside,PAL.text) end
  local mx=x+half+10*s;local my=box(mx,gy,half,160*s,"Idle movement")
  if target.kind=="objects" then
    K.caption(mx+10*s,my,"Type")
    local ids,labels={},{};for id,label in pairs(movementNames) do ids[#ids+1]=tostring(id);labels[tostring(id)]=label end
    choice(S,mx+10*s,my+24*s,half-20*s,event.movementType or 0,ids,labels,"MOVEMENT TYPE",function(id) mutateEvent(S,target,App,"movementType",tonumber(id)) end)
    K.caption(mx+10*s,my+64*s,"Position")
    K.text("small",tostring(event.x)..", "..tostring(event.y),mx+10*s,my+87*s,PAL.text)
  end
  local oy=gy+170*s;local oh=math.max(100*s,h-(oy-y));local optW=(left-10*s)/2
  local opy=box(x,oy,optW,oh,"Options")
  local moveAnimation=event.moveAnimation~=false
  local value,changed=K.checkbox(x+4*s,opy-2*s,optW-8*s,27*s,moveAnimation,"Animate walking")
  if changed then mutateEvent(S,target,App,"moveAnimation",value);event.moveAnimation=value end
  local directionFix=event.directionFix==true
  value,changed=K.checkbox(x+4*s,opy+27*s,optW-8*s,27*s,directionFix,"Keep facing")
  if changed then mutateEvent(S,target,App,"directionFix",value);event.directionFix=value end
  local through=event.passable==true
  value,changed=K.checkbox(x+4*s,opy+56*s,optW-8*s,27*s,through,"Walk through")
  if changed then mutateEvent(S,target,App,"passable",value);event.passable=value end
  local tx=x+optW+10*s;local ty=box(tx,oy,optW,oh,"Trigger")
  local triggerNames={action_button="Action Button",player_touch="Player Touch",event_touch="Event Touch",autorun="Autorun",parallel="Parallel Process"}
  local triggerLabels={['Action Button']="Press to talk",['Player Touch']="Player steps here",['Event Touch']="Touches player",Autorun="Start on its own",['Parallel Process']="Run in background"}
  local triggerHelp={['Action Button']="Start when the player presses the talk button while facing this event.",['Player Touch']="Start when the player steps onto this event's tile.",['Event Touch']="Start when this character moves into the player.",Autorun="Start automatically and keep control until the event finishes.",['Parallel Process']="Run while the player can continue moving."}
  local trigger=(target.kind=="objects" or target.kind=="signs") and (triggerNames[event.trigger] or "Action Button")
    or (target.kind=="warps" or target.kind=="coordEvents") and "Player Touch" or "Action Button"
  for i,label in ipairs({"Action Button","Player Touch","Event Touch","Autorun","Parallel Process"}) do
    local on=label==trigger;local yy=ty+(i-1)*27*s
    local editable=target.kind=="objects" or target.kind=="signs"
    local available=editable and (label~="Event Touch" or target.kind=="objects")
    local ids={['Action Button']="action_button",['Player Touch']="player_touch",['Event Touch']="event_touch",Autorun="autorun",['Parallel Process']="parallel"}
    if available and K.row(tx+6*s,yy-4*s,optW-12*s,25*s,on,PAL.blue,3) then setTrigger(S,target,event,ids[label],App) end
    K.text("small",K.ellipsize("small",(on and "* " or "  ")..triggerLabels[label],optW-20*s),tx+12*s,yy,on and PAL.heading or available and PAL.text or PAL.faint)
    K.offerTooltip(tx+8*s,yy-3*s,optW-16*s,24*s,available and triggerHelp[label]
      or "Event Touch requires a character that can move into the player.")
  end
  K.card(rx,y,rw,h-32*s,5);K.caption(rx+10*s,y+8*s,"What happens:")
  if eventScriptKey and K.button(rx+rw-332*s,y+5*s,150*s,27*s,"Add action...",{kind="good"}) then
    require("Gen3EventStory").openAddMenu(S,eventScriptKey,catalog,App)
  end
  if K.button(rx+rw-170*s,y+5*s,158*s,27*s,"All actions / details",{enabled=eventScriptKey~=nil}) then S["g3StoryAdvanced/"..eventScriptKey]=true;S._g3RpgAdvanced=true end
  if S._g3RpgAdvanced then
    if K.button(rx+10*s,y+40*s,120*s,27*s,"Back to list",{}) then S._g3RpgAdvanced=nil end
    require("Gen3Events").drawScript(S,eventScriptKey,rx+10*s,y+76*s,rw-20*s,h-118*s,App);return
  end
  local story=eventScriptKey and require("Gen3EventStory").rows(S,eventScriptKey,catalog) or {}
  local listY=y+39*s;local detailH=math.min(330*s,h*.48);local listH=math.max(120*s,h-32*s-39*s-detailH)
  local page=math.max(1,math.floor(listH/(31*s)));local sk="rpgEventScroll";S[sk]=K.scroll(rx+8*s,listY,rw-16*s,listH,S[sk] or 0,#story,page)
  local first=S[sk] or 0;local selected=math.min(S._g3RpgRow or 1,math.max(1,#story))
  K.pushClip(rx+8*s,listY,rw-28*s,listH)
  local yy=listY
  for i=first+1,math.min(#story,first+page) do
    local row=story[i];if K.row(rx+10*s,yy,rw-38*s,28*s,i==selected,PAL.blue,2) then selected=i;S._g3RpgRow=i;S._g3MessageDraft=nil end
    local prefix=row.depth>0 and string.rep("  ",math.min(row.depth,4)).."- " or "> "
    K.text("small",K.ellipsize("small",prefix..row.label,rw-58*s),rx+18*s,yy+5*s,PAL.text)
    K.offerTooltip(rx+18*s,yy,rw-58*s,28*s,row.label);yy=yy+31*s
  end
  if first+#story<page then K.text("small","@>",rx+18*s,yy+5*s,PAL.text) end
  K.popClip();S[sk]=K.scrollbar(rx+8*s,listY,rw-16*s,listH,S[sk],#story,page)
  local dy=listY+listH+8*s;local row=story[selected]
  if row then
    K.caption(rx+12*s,dy,"Selected action");dy=dy+25*s
    K.text("small",K.ellipsize("small",row.label,rw-28*s),rx+12*s,dy,PAL.heading);dy=dy+27*s
    if row.inputs then
      local P=require("FormPane");local pk="rpgActionInputs/"..row.script.."/"..row.index
      local top,view=P.begin(S,pk,rx+12*s,dy,rw-24*s,math.max(35*s,y+h-40*s-dy))
      local bottom=require("Gen3ActionInputs").draw(S,pk,row.inputs,catalog,rx+12*s,top,view.contentW,function() App.markDirty() end)
      P.finish(S,pk,top,bottom,view)
    elseif row.kind=="item" then editItem(S,row,eventScriptKey,catalog,rx+12*s,dy,rw-24*s,App)
    elseif row.kind=="wild_battle" then editWildBattle(S,row,catalog,rx+12*s,dy,rw-24*s,App)
    elseif row.text then editDialogue(S,row,catalog,rx+12*s,dy,rw-24*s,App)
    elseif row.script and row.index then
      local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script]
      local edits=copy(source);local step=edits[row.index]
      local P=require("FormPane");local pk="rpgActionDetails/"..row.script.."/"..row.index
      local top,view=P.begin(S,pk,rx+12*s,dy,rw-24*s,math.max(35*s,y+h-40*s-dy))
      local function changed() saveScript(S,row.script,edits,App) end
      local bottom
      if step.op=="applymovement" then
        local route=step.movement or step[2]
        local bytes=type(route)=="table" and route or (S.data._g3StoryMovements or {})[route]
        if bytes then
          local movement={localId=step.localId or step[1],movement=copy(bytes)}
          require("Gen3MovementEditor").draw(S,pk,movement,rx+12*s,top,view.contentW,380*s,function()
            step.localId=movement.localId;step.movement=movement.movement
            if step[1]~=nil then step[1]=movement.localId end
            if step[2]~=nil then step[2]=movement.movement end
            changed()
          end)
          bottom=top+380*s
        end
      end
      if not bottom then local handled;handled,bottom=require("Gen3EventCommands").draw(S,pk,step,rx+12*s,top,view.contentW,changed) end
      if row.conditionIndex and edits[row.conditionIndex] then
        local handled;handled,bottom=require("Gen3EventCommands").draw(S,pk.."/condition",edits[row.conditionIndex],rx+12*s,(bottom or top)+12*s,view.contentW,changed)
      end
      P.finish(S,pk,top,bottom or top,view)
    else K.text("small","This line explains which actions happen next.",rx+12*s,dy,PAL.faint) end
  else K.text("small","@>",rx+16*s,listY+8*s,PAL.text) end
end
return M
