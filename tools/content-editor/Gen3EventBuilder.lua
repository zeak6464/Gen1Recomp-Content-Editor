local M={}
local copy=require("src.mods.Merge").deepCopy
function M.create(S,d)
  -- Stage the complete change so validation failures cannot leave half an event.
  local original=S.project
  local T=setmetatable({project=copy(original)},{__index=S})
  local ok,key=pcall(function()
    assert(d.kind=="dialog" or d.kind=="item" or d.kind=="pickup","Choose an event action")
    if d.kind~="pickup" then assert(type(d.text)=="string" and d.text:match("%S"),"Enter dialogue first") end
    require("Gen3ContentAdapter").prepare(T)
    local source=assert(require("Gen3Workspace").convert(T,d.map))
    local map=T.project.maps[d.map]
    local npc=tonumber(d.npc)
    if d.place then
      assert(type(d.x)=="number" and type(d.y)=="number" and d.x%1==0 and d.y%1==0
        and d.x>=0 and d.y>=0 and d.x<source.cellWidth and d.y<source.cellHeight,"Choose a tile inside the map")
      map.objects=map.objects or {};npc=#map.objects+1
      local localId=0;for _,row in ipairs(map.objects) do localId=math.max(localId,row.localId or row.index or 0) end
      local graphics=d.kind=="pickup" and 92 or 1
      map.objects[npc]={x=d.x,y=d.y,localId=localId+1,index=localId+1,graphicsId=graphics,graphics=graphics,
        movement="STAY",movementType=8,flag=0,elevation=(source.gen3Elevation or {})[d.y*source.cellWidth+d.x+1] or 3}
    end
    local object=assert((map.objects or {})[npc],"Choose an NPC on this map")
    local p=T.project;local script
    if d.kind=="pickup" then
      local rec=(p.items or {})[d.item] or (S.data.items or {})[d.item]
      local quantity=tonumber(d.quantity)
      assert(rec and type(rec.index)=="number","Choose an item")
      assert(quantity and quantity==math.floor(quantity) and quantity>=1 and quantity<=999,"Item quantities must be 1 to 999")
      local used=require("Gen3Quests").usedFlags(T);local flag
      for candidate=0x900,0xFFF do if not used[candidate] then flag=candidate;break end end
      assert(flag,"No unused event switch is available")
      p.gen3=p.gen3 or {};p.gen3.map_scripts=p.gen3.map_scripts or {}
      p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
      local base="EditorPickup_"..tostring(p.id):gsub("[^%w_]","_").."_";local n=1
      local catalog=require("Gen3").catalog(S.data,"map_scripts")
      repeat script=base..n;n=n+1 until not p.gen3.map_scripts[script] and not catalog[script]
      p.gen3.map_scripts[script]={{op="setorcopyvar",[1]=0x8000,[2]=rec.index},
        {op="setorcopyvar",[1]=0x8001,[2]=quantity},{op="callstd",std=1},{op="end"}}
      p.gen3Modes.map_scripts[script]="register";object.flag=flag
    elseif d.kind=="item" then
      local Q=require("Gen3Quests");local id,err=Q.new(T);assert(id,err)
      local q=p.gen3Quests[id];q.offer=d.text;q.reward=d.item;q.quantity=tonumber(d.quantity)
      q.success=d.success;q.done=d.done
      script,err=Q.build(T,id);assert(script,err)
    else
      p.gen3=p.gen3 or {};p.gen3.map_scripts=p.gen3.map_scripts or {}
      p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
      p.text=p.text or {}
      local base="EditorTalk_"..tostring(p.id):gsub("[^%w_]","_").."_"
      local catalog=require("Gen3").catalog(S.data,"map_scripts");local n=1
      repeat script=base..n;n=n+1 until not p.gen3.map_scripts[script] and not catalog[script] and not p.text[script.."_Text"]
      p.text[script.."_Text"]=require("Gen3Dialog").encode(d.text)
      p.gen3.map_scripts[script]={{op="lock"},{op="faceplayer"},{op="message",ptr=script.."_Text"},{op="waitmessage"},{op="waitbuttonpress"},{op="closemessage"},{op="release"},{op="end"}}
      p.gen3Modes.map_scripts[script]="register"
    end
    object.scriptKey=script
    return script
  end)
  if not ok then return nil,tostring(key) end
  -- Preserve the project identity used by the editor's save/undo machinery.
  for k in pairs(original) do original[k]=nil end
  for k,v in pairs(T.project) do original[k]=v end
  return key
end
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local P=require("ChoicePicker");local L=require("RegList");local s=K.scale
  if S._eventBuilderProject~=S.project then S._eventBuilderProject=S.project;S.eventBuilder=nil end
  S.eventBuilder=type(S.eventBuilder)=="table" and S.eventBuilder or {kind="dialog",text="Hello! Welcome to town.",item="POTION",quantity="1",success="Here is your reward!",done="Enjoy your reward!"}
  local d=S.eventBuilder
  local top,view=require("FormPane").begin(S,"eventBuilder",x,y,w,h);y=top;w=view.contentW
  local function caption(t) K.caption(x,y,t);y=y+29*s end
  local function text(key,label)
    caption(label);d[key]=K.textfield("eventBuilder/"..key,x,y,w,29*s,d[key] or "","");y=y+40*s
  end
  caption("1. What happens when the player talks to this NPC?")
  P.field(S,{x=x,y=y,w=w,h=29*s,ids={"dialog","pickup","item"},current=d.kind,
    labels={dialog="Conversation",pickup="Ground item / Poké Ball",item="Offer a reward once (Yes / No)"},title="EVENT TYPE",onPick=function(v) d.kind=v;d.created=nil end});y=y+43*s
  if d.kind~="pickup" then text("text",d.kind=="item" and "Ask the player" or "What the NPC says") end
  if d.kind=="item" or d.kind=="pickup" then
    caption("Reward item")
    require("ItemPicker").field(S,{x=x,y=y,w=w,h=29*s,current=d.item,onPick=function(v) d.item=v end});y=y+40*s
    text("quantity","How many? (1 to 999)")
    if d.kind=="item" then
      text("success","After receiving the item");text("done","When the player returns")
      caption("The reward is given once. A full Bag leaves it available for later.")
    else caption("The object disappears after pickup. A full Bag leaves it on the map.") end
  end
  caption("2. Choose where this conversation happens")
  local maps=L.mergeIds(S.project.maps or {},S.data.maps or {});local labels={}
  for _,id in ipairs(maps) do labels[id]=id:gsub("^FR_",""):gsub("_"," ") end
  P.field(S,{x=x,y=y,w=w,h=29*s,ids=maps,labels=labels,current=d.map,title="CHOOSE MAP",onPick=function(v) d.map=v;d.npc=nil;d.created=nil end});y=y+40*s
  local map=(S.project.maps or {})[d.map] or (S.data.maps or {})[d.map]
  local ids,names={},{}
  for i,o in ipairs(map and map.objects or {}) do local id=tostring(i);ids[#ids+1]=id;names[id]="NPC "..tostring(o.localId or i).." at ("..tostring(o.x)..", "..tostring(o.y)..")" end
  P.field(S,{x=x,y=y,w=w,h=29*s,ids=ids,labels=names,current=d.npc,title="CHOOSE NPC",onPick=function(v) d.npc=v;d.created=nil end});y=y+40*s
  if #ids==0 then caption("Choose a map with NPCs, or add an Object with Maps > Add events first.") end
  caption("EVENT COMMANDS - runs when the player talks to this NPC")
  if d.kind=="pickup" then
    caption("1. Give "..tostring(d.quantity).." × "..tostring(d.item))
    caption("2. Hide this Poké Ball after a successful pickup")
  else
    caption("1. Face the player")
    caption("2. Show text: "..K.ellipsize("micro",d.text or "",math.max(80*s,w-120*s)))
  end
  if d.kind=="item" then
    caption("3. If the player says Yes: give "..tostring(d.quantity).." x "..tostring(d.item))
    caption("4. Remember the reward; show return dialogue next time")
  elseif d.kind=="dialog" then caption("3. Wait for a button press, then end the conversation") end
  caption("Create and attach, then Save your mod")
  caption("This replaces the chosen NPC's interaction. Its position and appearance stay the same.")
  if K.button(x,y,300*s,30*s,"Create and attach to NPC",{kind="good"}) then
    local key,err=M.create(S,d)
    if key then d.created=key;S.status="Event attached. Save your mod to use it in game.";App.markDirty() else S.status=err end
  end
  y=y+42*s
  if d.created then
    caption("Event attached successfully. Open its actions to edit dialogue and preview it.")
    if K.button(x,y,190*s,29*s,"Show NPC on map",{}) then S.mapId=d.map;S.mapObjectIndex=tonumber(d.npc);S.mapSection="objects";S.mapEditMode="events";S.tab="maps" end
    if K.button(x+200*s,y,190*s,29*s,"Edit event commands",{}) then
      S.gen3Id=d.created;S.g3EventMode="map";S.g3EventMap=d.map;S.g3MapEventId="objects/"..d.npc
    end
    y=y+40*s
  end
  require("FormPane").finish(S,"eventBuilder",top,y,view)
end
return M

