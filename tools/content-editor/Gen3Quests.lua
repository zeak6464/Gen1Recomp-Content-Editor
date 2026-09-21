-- Quest recipes compile into ordinary FireRed scripts, text and persistent flags.
local M={}
local copy=require("src.mods.Merge").deepCopy
local encode=require("ModWriter").encodeLua
local function same(a,b) return encode(a)==encode(b) end
function M.key(p,id) return "EditorQuest_"..p.id:gsub("[^%w_]","_").."_"..id end
function M.usedFlags(S,except)
  local used={}
  local Flags=require("src.core.game3.scripting.flags")
  for _,v in pairs(Flags.IDS) do used[v]=true end
  local function scan(v)
    if type(v)~="table" then return end
    local flag=v.flag
    if v.op=="checkflag" or v.op=="setflag" or v.op=="clearflag" then flag=flag or v[1] end
    if flag then used[tonumber(flag) or Flags.IDS[flag] or flag]=true end
    for _,c in pairs(v) do if type(c)=="table" then scan(c) end end
  end
  scan(require("Gen3").catalog(S.data,"map_scripts"));scan(S.data.maps)
  scan(S.project.maps)
  for id,rows in pairs((S.project.gen3 or {}).map_scripts or {}) do
    if not (except and except._scripts and except._scripts[id]) then scan(rows) end
  end
  for _,q in pairs(S.project.gen3Quests or {}) do if q~=except then used[q.flag]=true end end
  return used
end
function M.new(S)
  local p=S.project;p.gen3Quests=p.gen3Quests or {}
  local n=1;while p.gen3Quests["QUEST_"..n] do n=n+1 end
  local used=M.usedFlags(S);local flag
  for f=0x900,0xFFF do if not used[f] then flag=f;break end end
  if not flag then return nil,"No unused completion flag found" end
  local id="QUEST_"..n
  p.gen3Quests[id]={flag=flag,reward="POTION",quantity=1,requirement="none",requiredItem="POTION",requiredQuantity=1,trainer=1,
    offer="Would you like a reward?",missing="You have not met the requirement yet.",
    success="Here is your reward!",done="Enjoy your reward!",full="Make room in your Bag and come back."}
  return id
end
function M.compile(S,id,q)
  assert(type(q.flag)=="number" and q.flag%1==0 and q.flag>=32 and q.flag<=4095,"Choose a persistent completion flag from 32 to 4095")
  local function item(name)
    local rec=(S.project.items or {})[name] or (S.data.items or {})[name]
    assert(rec and type(rec.index)=="number","Unknown item: "..tostring(name))
    return rec.index
  end
  local function quantity(v) assert(type(v)=="number" and v%1==0 and v>=1 and v<=999,"Item quantities must be 1 to 999");return v end
  local key=M.key(S.project,id);local scripts,text={},{}
  local function finish(label)
    local ptr=key.."_Text_"..label
    assert(type(q[label])=="string" and q[label]~="","Enter "..label.." dialogue")
    text[ptr]=require("Gen3Dialog").encode(q[label])
    return {{op="message",ptr=ptr},{op="waitmessage"},{op="waitbuttonpress"},{op="closemessage"},{op="release"},{op="end"}}
  end
  for _,label in ipairs({"missing","success","done","full"}) do scripts[key.."_"..label]=finish(label) end
  scripts[key.."_cancel"]={{op="closemessage"},{op="release"},{op="end"}}
  assert(type(q.offer)=="string" and q.offer~="","Enter offer dialogue")
  text[key.."_Text_offer"]=require("Gen3Dialog").encode(q.offer)
  local rows={{op="lock"},{op="faceplayer"},{op="checkflag",flag=q.flag},{op="goto_if",cond=1,target=key.."_done"}}
  local function push(row) rows[#rows+1]=row end
  local function requireResult(target)
    push({op="compare_var_to_value",var=0x800D,value=1});push({op="goto_if",cond=5,target=key..target})
  end
  if q.requirement=="item" then
    push({op="checkitem",item=item(q.requiredItem),quantity=quantity(q.requiredQuantity)});requireResult("_missing")
  elseif q.requirement=="trainer" then
    assert(type(q.trainer)=="number" and q.trainer%1==0 and q.trainer>=0 and q.trainer<=1023,"Choose a trainer ID from 0 to 1023")
    assert((S.project.trainers or {})[tostring(q.trainer)] or (S.data.trainers or {})[tostring(q.trainer)],"Choose an existing trainer")
    push({op="checkflag",flag=0x500+q.trainer});push({op="goto_if",cond=0,target=key.."_missing"})
  else assert(q.requirement=="none","Unknown quest requirement") end
  push({op="message",ptr=key.."_Text_offer"});push({op="waitmessage"});push({op="yesnobox",x=20,y=8});requireResult("_cancel")
  push({op="closemessage"})
  push({op="additem",item=item(q.reward),quantity=quantity(q.quantity)});requireResult("_full")
  push({op="setflag",flag=q.flag});push({op="goto",target=key.."_success"})
  scripts[key]=rows
  return scripts,text,key
end
function M.build(S,id,replace)
  local q=S.project.gen3Quests[id]
  local ok,scripts,text,key=pcall(M.compile,S,id,q)
  if not ok then return nil,scripts end
  if M.usedFlags(S,q)[q.flag] then return nil,"Completion flag is already used by the game or another event" end
  local p=S.project;local edits=(p.gen3 or {}).map_scripts or {};local catalog=require("Gen3").catalog(S.data,"map_scripts")
  for name in pairs(scripts) do
    if catalog[name] then return nil,"Script ID already exists in the game: "..name end
    if edits[name] and not same(edits[name],(q._scripts or {})[name]) and not replace then return nil,"Script edited in Events: "..name,true end
  end
  for name in pairs(text) do
    if p.text[name] and not same(p.text[name],(q._text or {})[name]) and not replace then return nil,"Dialogue edited in Dialog: "..name,true end
  end
  p.gen3=p.gen3 or {};p.gen3.map_scripts=edits
  p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
  for name,rows in pairs(scripts) do edits[name]=rows;p.gen3Modes.map_scripts[name]="register" end
  for name,value in pairs(text) do p.text[name]=value end
  q._scripts=copy(scripts);q._text=copy(text)
  return key
end
function M.draw(S,x,y,w,h,App)
  require("Gen3ContentAdapter").prepare(S)
  local K=require("Kit");local L=require("RegList");local s=K.scale
  local quests=S.project.gen3Quests or {};local ids=L.sortedKeys(quests)
  local fx,fw=L.drawList(S,App,x,y,w,h,"ITEM REWARD QUESTS",ids,{selKey="g3QuestId",queryKey="g3QuestQuery",offsetKey="g3QuestOffset",footerLabel="New quest",
    onFooter=function() local id,err=M.new(S);if id then S.g3QuestId=id;App.markDirty() else S.status=err end end})
  local id=S.g3QuestId;local q=id and (S.project.gen3Quests or {})[id]
  if not q then K.caption(fx,y,"Create a quest, build its scripts, then attach the main script to a map NPC.");return end
  K.caption(fx,y,M.key(S.project,id))
  if K.button(fx,y+28*s,150*s,28*s,"Build scripts",{kind="good"}) then
    local key,err,conflict=M.build(S,id)
    S.g3QuestConflict=conflict and id or nil
    if key then App.markDirty();S.status="Built "..key else S.status=err end
  end
  if K.button(fx+160*s,y+28*s,150*s,28*s,"Open script",{}) then
    local key=M.key(S.project,id)
    if ((S.project.gen3 or {}).map_scripts or {})[key] then S.gen3Id=key;S.g3EventMode="scripts"
    else S.status="Build this quest's scripts first" end
  end
  if S.g3QuestConflict==id and K.button(fx+320*s,y+28*s,230*s,28*s,"Replace manual edits",{kind="danger"}) then
    local key,err=M.build(S,id,true);if key then S.g3QuestConflict=nil;App.markDirty();S.status="Rebuilt "..key else S.status=err end
  end
  local top,view=require("FormPane").begin(S,"g3QuestForm",fx,y+70*s,fw,h-70*s)
  local yy=top;local width=view.contentW
  K.caption(fx,yy,"Build scripts after changing this recipe. Save writes the built scripts.");yy=yy+30*s
  local function number(key,label)
    K.caption(fx,yy,label)
    local v=K.textfield("g3Quest/"..key,fx+230*s,yy,width-230*s,27*s,tostring(q[key]),"")
    local n=tonumber(v);if n and n~=q[key] then q[key]=n;App.markDirty() end
    yy=yy+34*s
  end
  number("flag","Completion flag")
  K.caption(fx,yy,"Requirement")
  require("ChoicePicker").field(S,{x=fx+230*s,y=yy,w=width-230*s,h=27*s,ids={"none","item","trainer"},current=q.requirement,
    labels={none="No requirement",item="Carry an item",trainer="Defeat a trainer"},
    title="QUEST REQUIREMENT",onPick=function(v) q.requirement=v;App.markDirty() end});yy=yy+34*s
  local function item(key,label)
    K.caption(fx,yy,label)
    require("ItemPicker").field(S,{x=fx+230*s,y=yy,w=width-230*s,h=27*s,current=q[key],onPick=function(v) q[key]=v;App.markDirty() end});yy=yy+34*s
  end
  if q.requirement=="item" then item("requiredItem","Must carry (kept)");number("requiredQuantity","Required quantity")
  elseif q.requirement=="trainer" then
    K.caption(fx,yy,"Defeat trainer")
    local trainers=L.mergeIds(S.project.trainers or {},S.data.trainers or {});local labels={}
    for _,tid in ipairs(trainers) do local t=S.project.trainers[tid] or S.data.trainers[tid];labels[tid]=tid.." · "..tostring(t.name or "Trainer") end
    require("ChoicePicker").field(S,{x=fx+230*s,y=yy,w=width-230*s,h=27*s,ids=trainers,labels=labels,current=tostring(q.trainer),
      title="DEFEAT TRAINER",onPick=function(tid) q.trainer=tonumber(tid);App.markDirty() end});yy=yy+34*s
  end
  item("reward","Reward item");number("quantity","Reward quantity")
  for _,row in ipairs({{"offer","Offer / Yes-No prompt"},{"missing","Requirement unmet"},{"success","Reward received"},{"done","Already completed"},{"full","Bag full"}}) do
    K.caption(fx,yy,row[2]);yy=yy+23*s
    local value=K.textfield("g3Quest/"..row[1],fx,yy,width,28*s,q[row[1]],"")
    if value~=q[row[1]] then q[row[1]]=value;App.markDirty() end
    yy=yy+36*s
  end
  require("FormPane").finish(S,"g3QuestForm",top,yy,view)
end
return M
