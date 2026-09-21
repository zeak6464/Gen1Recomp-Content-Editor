local M={}
local controlIds,controls={},{}
local function value(S,id) return S.project.text[id] or S.data.text[id] end
-- Use stable control IDs: editing earlier prose can change IR token positions
-- while the text field still holds its previous placeholder strings.
function M.display(ir)
  if type(ir)=="string" then return ir end
  local out={}
  for i,t in ipairs(ir or {}) do
    if t.t=="text" then out[#out+1]=t.s or ""
    elseif t.t=="nl" then out[#out+1]="\n"
    elseif t.t=="para" then out[#out+1]="\n\n"
    elseif t.t=="player" then out[#out+1]="{PLAYER}"
    elseif t.t=="rival" then out[#out+1]="{RIVAL}"
    elseif t.t~="eos" then
      local key=require("ModWriter").encodeLua(t)
      local id=controlIds[key]
      if not id then id=#controls+1;controlIds[key]=id;controls[id]=require("src.mods.Merge").deepCopy(t) end
      out[#out+1]="{CONTROL:"..id.."}"
    end
  end
  return table.concat(out)
end
function M.encode(text,old)
  local out={};local at=1
  local function prose(s)
    local ir=require("src.mods.Schemas").gen3View.textIr(s)
    for _,t in ipairs(ir) do if t.t~="eos" then out[#out+1]=t end end
  end
  while at<=#text do
    local a,b,token=text:find("{([^{}]+)}",at)
    if not a then prose(text:sub(at));break end
    prose(text:sub(at,a-1))
    if token=="PLAYER" or token=="RIVAL" then out[#out+1]={t=token:lower()}
    else
      local index=tonumber(token:match("^CONTROL:(%d+)$"))
      if index and controls[index] then
        out[#out+1]=require("src.mods.Merge").deepCopy(controls[index])
      else prose(text:sub(a,b)) end
    end
    at=b+1
  end
  out[#out+1]={t="eos"};return out
end
function M.pins(S,mapId)
  local pins,seen,visited={},{},{}
  local texts=S.data.text or {}
  local scripts=require("Gen3").catalog(S.data,"map_scripts")
  local function add(id,script)
    if seen[id] or value(S,id)==nil then return end
    seen[id]=true;pins[#pins+1]={textId=id,strId=id,label=require("Gen3Names").dialog(id,M.display(value(S,id))),scriptKey=script,
      preview=M.display(value(S,id)):gsub("\n"," ")}
  end
  local function walk(key,depth)
    if depth>32 or visited[key] then return end
    visited[key]=true
    local script=((S.project.gen3 or {}).map_scripts or {})[key] or scripts[key]
    local function scan(v)
      if type(v)=="table" then for _,c in pairs(v) do scan(c) end
      elseif type(v)=="string" then
        if texts[v] or S.project.text[v] then add(v,key)
        elseif scripts[v] or ((S.project.gen3 or {}).map_scripts or {})[v] then walk(v,depth+1) end
      end
    end
    scan(script)
  end
  if mapId=="ALL DIALOG" then
    for id in pairs(texts) do add(id) end
    for id in pairs(S.project.text) do add(id) end
  else
    local map=S.project.maps[mapId] or require("Generation").dataMaps(S)[mapId] or {}
    for _,kind in ipairs({"objects","bgEvents","coordEvents","signs"}) do
      for _,event in ipairs(map[kind] or {}) do walk(event.script or event.scriptKey or "",0) end
    end
    local function scan(v)
      if type(v)=="table" then for _,c in pairs(v) do scan(c) end
      elseif type(v)=="string" and scripts[v] then walk(v,0) end
    end
    scan(map.mapScripts)
  end
  table.sort(pins,function(a,b) return a.textId<b.textId end)
  return pins
end
local function pages(text)
  local result={};text=text:gsub("{PLAYER}","RED"):gsub("{RIVAL}","BLUE"):gsub("{CONTROL:%d+}","[value]")
  for page in (text.."\f"):gmatch("(.-)\f") do
    local lines={};local line=""
    for token in (page.."\n"):gmatch("(.-)\n") do
      for word in token:gmatch("%S+") do
        if #line+#word+1>34 and #line>0 then lines[#lines+1]=line;line="" end
        line=line=="" and word or line.." "..word
      end
      lines[#lines+1]=line;line=""
    end
    for i=1,#lines,2 do result[#result+1]=(lines[i] or "").."\n"..(lines[i+1] or "") end
  end
  return result
end
function M.preview(S,text,x,y,w,opts)
  local ps=pages(text);local page=math.max(1,math.min(#ps,opts.page or 1))
  local scale=math.min(3,w/240);local h=52*scale
  love.graphics.push("all");love.graphics.translate(x,y);love.graphics.scale(scale)
  love.graphics.setColor(.25,.3,.4,1);love.graphics.rectangle("fill",0,0,240,52,3,3)
  love.graphics.setColor(1,1,1,1);love.graphics.rectangle("fill",3,3,234,46,2,2)
  local count=require("src.ui.game3.frlg_font").draw(ps[page],10,8,{maxWidth=220,linePitch=18})
  if not count or count==0 then
    love.graphics.setColor(.15,.15,.15,1);love.graphics.setFont(love.graphics.newFont(10));love.graphics.printf(ps[page],10,8,220)
  end
  love.graphics.pop()
  return h,{page=page,pageCount=#ps,lineStart=1,canPrev=page>1,canNext=page<#ps,hasMore=page<#ps}
end
function M.step(text,page,dir) return math.max(1,math.min(#pages(text),(page or 1)+dir)),1 end
return M

