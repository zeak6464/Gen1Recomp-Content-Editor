-- Logical actions are views over native rows; no rewriting on selection or draw.
local M={}
local copy=require("src.mods.Merge").deepCopy
function M.rows(steps,native)
  local rows={};local i=1
  while i<=#steps do
    local last=i
    if not native and steps[i].op=="message" and steps[i+1] and steps[i+1].op=="waitmessage"
      and steps[i+2] and steps[i+2].op=="waitbuttonpress" and steps[i+3] and steps[i+3].op=="closemessage" then
      last=i+3
    end
    rows[#rows+1]={first=i,last=last,step=steps[i]};i=last+1
  end
  return rows
end
function M.edit(steps,rows,index,action)
  local row=rows[index];if not row then return index,false end
  if action=="copy" then
    for i=row.last,row.first,-1 do table.insert(steps,row.last+1,copy(steps[i])) end
    return index+1,true
  elseif action=="delete" then
    for _=row.first,row.last do table.remove(steps,row.first) end
    return math.max(1,math.min(index,#rows-1)),true
  elseif action=="up" or action=="down" then
    local other=action=="up" and index-1 or index+1
    if not rows[other] then return index,false end
    local first=math.min(index,other);local a,b=rows[first],rows[first+1];local out={}
    for i=b.first,b.last do out[#out+1]=steps[i] end
    for i=a.first,a.last do out[#out+1]=steps[i] end
    for i,v in ipairs(out) do steps[a.first+i-1]=v end
    return other,true
  end
  return index,false
end
function M.insert(steps,rows,index,sequence)
  local row=rows[index];local at=row and row.last+1 or #steps+1
  if row and (row.step.op=="end" or row.step.op=="return") then at=row.first end
  for i=#sequence,1,-1 do table.insert(steps,at,copy(sequence[i])) end
  return at
end
function M.text(S,step)
  local ptr=step.op=="loadword" and (step.value or step[2]) or (step.ptr or step[1])
  local ir=((S.project or {}).text or {})[ptr] or ((S.data or {}).text or {})[ptr]
  return ir and require("Gen3Dialog").display(ir),ptr
end
function M.setText(S,step,text)
  -- Give this command its own text entry, so shared vanilla dialogue stays intact.
  local p=S.project;local base="EditorText_"..tostring(p.id):gsub("[^%w_]","_").."_"
  local n=1;p.text=p.text or {}
  while p.text[base..n] or (S.data.text or {})[base..n] do n=n+1 end
  local ptr=base..n
  p.text[ptr]=require("Gen3Dialog").encode(text)
  if step.op=="loadword" then step.value=ptr;if step[2]~=nil then step[2]=ptr end
  elseif step.ptr~=nil or step[1]==nil then step.ptr=ptr else step[1]=ptr end
  return ptr
end
M.choices={"text","face","wait","move","pause","resume","end"}
M.labels={text="Text / Show text",face="Character / Face the player",wait="Timing / Wait",
  move="Character / Move a character",pause="Character / Pause movement",resume="Character / Resume movement",["end"]="Flow / End event"}
function M.create(S,id)
  if id=="text" then
    local step={op="message"};M.setText(S,step,"Hello!")
    return {step,{op="waitmessage"},{op="waitbuttonpress"},{op="closemessage"}}
  end
  local presets={face={{op="faceplayer"}},wait={{op="delay",frames=60}},
    move={{op="applymovement",localId=255,movement={254}},{op="waitmovement",localId=0}},
    pause={{op="lockall"}},resume={{op="releaseall"}},["end"]={{op="end"}}}
  local preset=assert(presets[id],"Unknown event action")
  return copy(preset)
end
return M
