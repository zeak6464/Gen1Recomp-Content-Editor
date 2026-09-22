-- Presentation only: keep native script data intact, including unknown fields.
local M={}
M.definitions={
  lock={"Pause this NPC", "Keep this NPC still during the conversation."},
  lockall={"Pause all NPCs", "Keep everyone still while this event runs."},
  faceplayer={"Face the player", "Turn this NPC toward the player."},
  release={"Resume movement", "Let the player and NPC move again."},
  releaseall={"Resume all movement", "Let everyone move again."},
  message={"Show text", "Write what the player reads.", "ptr", "Dialogue"},
  delay={"Wait", "Pause this event. 60 frames is about one second.", "frames", "Frames", true},
  setvar={"Set a variable", "Store a number, such as a quest's current stage."},
  setorcopyvar={"Set or copy a variable", "Store a number or copy the value of another variable."},
  compare_var_to_value={"Compare a variable", "Compare a stored number before a conditional command."},
  waitmessage={"Wait for text", "Wait until the dialogue has finished appearing."},
  waitbuttonpress={"Wait for a button press", "Let the player read before continuing."},
  closemessage={"Close text box", "Dismiss the dialogue window."},
  setflag={"Turn switch ON", "Remember that something has happened.", "flag", "Switch ID", true},
  clearflag={"Turn switch OFF", "Clear a remembered event state.", "flag", "Switch ID", true},
  checkflag={"Check a switch", "Read a switch for a following conditional command.", "flag", "Switch ID", true},
  ["goto"]={"Go to another event", "Continue from the selected script.", "target", "Event script"},
  call={"Run another event", "Run a script, then return here.", "target", "Event script"},
  ["return"]={"Return to previous event", "Return to the script that called this one."},
  ["end"]={"End event", "Finish this event."},
  applymovement={"Move a character", "Choose the character and their movement route."},
  waitmovement={"Wait for movement", "Wait for a character to finish moving.", "localId", "Character ID (0 = all moving characters)", true},
}
function M.label(op)
  local d=M.definitions[op]
  return d and d[1] or ("Advanced: "..tostring(op))
end
function M.summary(step,S)
  if S and step.op=="message" then
    local text=require("Gen3EventActions").text(S,step)
    if text then return 'Show text: "'..text:gsub("%s+"," ")..'"' end
  end
  local d=M.definitions[step.op]
  return M.label(step.op)..(d and d[3] and step[d[3]]~=nil and (": "..tostring(step[d[3]])) or "")
end
local variableOps={setvar=true,setorcopyvar=true,compare_var_to_value=true}
local function variableFields(step)
  if step.op=="setorcopyvar" then return 1,2 end
  return step.var~=nil and "var" or 1,step.value~=nil and "value" or 2
end
function M.drawVariables(S,key,step,x,y,w,changed)
  local K=require("Kit");local s=K.scale;local a,b=variableFields(step)
  if step[a]==nil or step[b]==nil then return false end
  local help=M.definitions[step.op][2]
  K.text("small",K.ellipsize("small",help,w),x,y,require("Theme").PAL.text)
  K.offerTooltip(x,y,w,24*s,help)
  local fields={{a,"Variable to check or change"},{b,step.op=="setorcopyvar" and "Number or source variable ID" or "Number"}}
  for i,field in ipairs(fields) do
    local yy=y+36*s+(i-1)*68*s;K.text("small",field[2],x,yy,require("Theme").PAL.text)
    local value=K.textfield(key.."/variable/"..i,x,yy+25*s,w,29*s,tostring(step[field[1]]),"")
    local n=tonumber(value)
    if n and n>=0 and n<=65535 and n%1==0 and n~=step[field[1]] then step[field[1]]=n;changed() end
  end
  K.text("small","Variable IDs identify stored game values.",x,y+178*s,require("Theme").PAL.text)
  return true,y+210*s
end
function M.drawText(S,key,step,x,y,w,changed)
  local A=require("Gen3EventActions");local D=require("Gen3Dialog");local K=require("Kit");local s=K.scale
  local text,ptr=A.text(S,step)
  if not text then return false end
  local draft=S._g3MessageDraft
  if not draft or draft.step~=step or draft.source~=text or draft.ptr~=ptr then
    draft={step=step,source=text,ptr=ptr,lines={},page=1};S._g3MessageDraft=draft
    for line in (text.."\n"):gmatch("(.-)\n") do draft.lines[#draft.lines+1]=line end
  end
  K.caption(x,y,"WHAT THE PLAYER READS");y=y+28*s
  for i,line in ipairs(draft.lines) do
    draft.lines[i]=K.textfield(key.."/line/"..i,x,y,w-64*s,28*s,line,"")
    if #draft.lines>1 and K.button(x+w-58*s,y,58*s,28*s,"Delete",{}) then table.remove(draft.lines,i);break end
    y=y+34*s
  end
  if K.button(x,y,110*s,28*s,"Add line",{}) then draft.lines[#draft.lines+1]="" end
  y=y+38*s
  local value=table.concat(draft.lines,"\n")
  K.text("small","{PLAYER} = player name",x,y,require("Theme").PAL.text);y=y+23*s
  K.text("small","{RIVAL} = rival name",x,y,require("Theme").PAL.text);y=y+28*s
  if K.button(x,y,130*s,28*s,"Apply text",{kind="good",enabled=value~=text}) and value~=text then
    A.setText(S,step,value);S._g3MessageDraft=nil;changed()
  end
  if K.button(x+140*s,y,100*s,28*s,"Reset text",{}) then S._g3MessageDraft=nil end
  y=y+38*s
  K.text("small",value~=text and "Apply text to keep these changes." or "Text is up to date.",x,y,require("Theme").PAL.text);y=y+30*s
  local height,info=D.preview(S,value,x,y,w,{page=draft.page});y=y+height+8*s
  if K.button(x,y,50*s,26*s,"<",{}) then draft.page=math.max(1,info.page-1) end
  K.caption(x+60*s,y+4*s,"Preview "..info.page.." / "..info.pageCount)
  if K.button(x+190*s,y,50*s,26*s,">",{}) then draft.page=math.min(info.pageCount,info.page+1) end
  return true,y+36*s
end
function M.draw(S,key,step,x,y,w,changed)
  if step.op=="message" then return M.drawText(S,key,step,x,y,w,changed) end
  if variableOps[step.op] then return M.drawVariables(S,key,step,x,y,w,changed) end
  local d=M.definitions[step.op]
  if not d then return false end
  if d[3] and step[d[3]]==nil then return false end
  local K=require("Kit");local s=K.scale
  K.text("small",K.ellipsize("small",d[2],w),x,y,require("Theme").PAL.text);K.offerTooltip(x,y,w,24*s,d[2])
  if not d[3] then return true,y+32*s end
  K.text("small",K.ellipsize("small",d[4],w),x,y+36*s,require("Theme").PAL.text)
  local old=step[d[3]]
  local function pick(value) if value~=old then step[d[3]]=value;changed() end end
  if d[3]=="ptr" or d[3]=="target" then
    local category=d[3]=="ptr" and "text" or "map_scripts"
    local edits=category=="text" and (S.project.text or {}) or ((S.project.gen3 or {}).map_scripts or {})
    local catalog=category=="text" and (S.data.text or {}) or require("Gen3").catalog(S.data,category)
    require("ChoicePicker").field(S,{x=x,y=y+64*s,w=w,h=29*s,current=old,
      ids=require("RegList").mergeIds(edits,catalog),title=d[4],onPick=pick})
  else
    local value=K.textfield(key.."/friendly/"..d[3],x,y+64*s,w,29*s,tostring(old),"")
    if d[5] then
      local n=tonumber(value)
      if n and n>=0 and n<=65535 and n==math.floor(n) then pick(n) end
    else pick(value) end
  end
  return true,y+106*s
end
return M
