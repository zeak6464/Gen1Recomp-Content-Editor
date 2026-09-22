local M={}
local Kit=require("Kit")
local List=require("RegList")
local Writer=require("ModWriter")
local PAL=require("Theme").PAL
local Commands=require("Gen3EventCommands")
local Actions=require("Gen3EventActions")
function M.draw(S,key,steps,templates,x,y,w,h,changed,context)
  local s=Kit.scale
  S._g3StepSelection=S._g3StepSelection or {}
  local nativeKey="g3NativeCommands/"..key
  local lw=math.min(370*s,w*.43)
  local native=S[nativeKey]==true
  if Kit.button(x,y,lw,26*s,native and "Show simple actions" or "Show native commands",{}) then
    S[nativeKey]=not native;S._g3StepSelection[key]=1;return
  end
  local rows=Actions.rows(steps,native)
  local selected=math.min(S._g3StepSelection[key] or 1,math.max(1,#rows))
  local yy=y+35*s
  local rh=34*s;local listH=math.max(rh,h-122*s);local page=math.max(1,math.floor(listH/rh))
  local scrollKey="g3StepScroll/"..key
  S[scrollKey]=Kit.scroll(x,yy,lw,listH,S[scrollKey] or 0,#rows,page)
  local first=S[scrollKey] or 0
  for i=first+1,math.min(#rows,first+page) do
    if Kit.row(x,yy,lw-18*s,rh-2*s,i==selected,PAL.blue) then selected=i;S._g3StepSelection[key]=i end
    local label=native and tostring(rows[i].step.op) or Commands.summary(rows[i].step,S)
    Kit.offerTooltip(x,yy,lw-18*s,rh,label)
    Kit.text("micro",Kit.ellipsize("micro",i.."  "..label,lw-35*s),x+7*s,yy+8*s,PAL.text)
    yy=yy+rh
  end
  if #rows==0 then Kit.caption(x,yy,"Add an action to begin.") end
  S[scrollKey]=Kit.scrollbar(x,y+35*s,lw,listH,S[scrollKey],#rows,page)
  local by=y+h-75*s
  local function action(label,col,op)
    local bw=(lw-12*s)/4
    if Kit.button(x+col*(bw+4*s),by,bw,27*s,label,{enabled=#rows>0}) then
      local nextIndex,edited=Actions.edit(steps,rows,selected,op)
      if edited then S._g3StepSelection[key]=nextIndex;changed();return true end
    end
  end
  if action("Up",0,"up") or action("Down",1,"down") or action("Copy",2,"copy") or action("Delete",3,"delete") then return end
  local ops=native and List.sortedKeys(templates) or Actions.choices
  local labels={};for _,op in ipairs(ops) do labels[op]=Commands.label(op) end
  require("ChoicePicker").field(S,{x=x,y=by+35*s,w=lw,h=28*s,ids=ops,labels=native and labels or Actions.labels,current="",emptyLabel=native and "Add native command" or "Add action",title=native and "NATIVE COMMAND (SAMPLE VALUES)" or "WHAT SHOULD HAPPEN?",
    onPick=function(op)
      local sequence=native and {templates[op]} or Actions.create(S,op)
      local at=Actions.insert(steps,rows,selected,sequence)
      for i,row in ipairs(Actions.rows(steps,native)) do if row.first==at then S._g3StepSelection[key]=i;S[scrollKey]=math.max(0,i-page);break end end
      changed()
    end})
  local step=rows[selected] and rows[selected].step
  if not step then return end
  local fx=x+lw+16*s;local fw=w-lw-16*s
  Kit.caption(fx,y,Kit.ellipsize("micro","ACTION "..selected.." / "..Commands.label(step.op),fw))
  local rawKey="g3CommandRaw/"..key
  if Kit.button(fx,y+25*s,180*s,26*s,S[rawKey] and "Simple settings" or "Advanced fields",{}) then S[rawKey]=not S[rawKey] end
  if step.op=="applymovement" and type(step.movement)=="table" then
    if not S[rawKey] then
      require("Gen3MovementEditor").draw(S,key.."/"..selected,step,fx,y+60*s,fw,h-60*s,changed)
      return
    end
  end
  if not S[rawKey] then
    local Pane=require("FormPane");local pk="g3FriendlyFields/"..key
    Pane.track(S,pk,step)
    local top,view=Pane.begin(S,pk,fx,y+64*s,fw,math.max(40*s,h-64*s))
    local inputs
    if context and (step.op=="special" or step.op=="specialvar" or step.op=="setwildbattle" or step.op=="dowildbattle") then
      for _,row in ipairs(require("Gen3EventStory").rows(S,context.id,context.catalog)) do
        if row.script==context.id and row.index==rows[selected].first then inputs=row.inputs;break end
      end
    end
    local handled,ending
    if inputs then
      ending=require("Gen3ActionInputs").draw(S,key.."/"..selected,inputs,context.catalog,fx,top,view.contentW,context.onInputChanged)
      handled=true
    else handled,ending=Commands.draw(S,key.."/"..selected,step,fx,top,view.contentW,changed) end
    Pane.finish(S,pk,top,ending or top,view)
    if handled then return end
  end
  Kit.caption(fx,y+60*s,"Technical command settings: "..tostring(step.op))
  local draft={value=Writer.encodeLua(step)}
  S._g3Expanded=S._g3Expanded or {};S._g3Expanded.value=true
  local top,view=require("FormPane").begin(S,"g3StepFields/"..key,fx,y+90*s,fw,h-90*s)
  local ending=require("Gen3Fields").draw(S,key.."/"..selected,fx,top,view.contentW,draft,{value={kind="any"}})
  require("FormPane").finish(S,"g3StepFields/"..key,top,ending,view)
  if draft.value~=Writer.encodeLua(step) then
    local box=require("Gen3Decode").decode("return {value="..draft.value.."}",{allowArray=true})
    if box and type(box.value)=="table" and type(box.value.op)=="string" and Writer.encodeLua(box.value)~=Writer.encodeLua(step) then steps[rows[selected].first]=box.value;changed() end
  end
end
function M.templates(catalog)
  local result={end_={op="end"}}
  result["end"]=result.end_;result.end_=nil
  for _,script in pairs(catalog) do
    if type(script)=="table" then
      for _,step in ipairs(script) do
        if type(step)=="table" and type(step.op)=="string" and not result[step.op] then
          result[step.op]=require("src.mods.Merge").deepCopy(step)
        end
      end
    end
  end
  if result.applymovement then
    result.applymovement={op="applymovement",localId=255,movement={254}}
    result.waitmovement={op="waitmovement",localId=0}
  end
  return result
end
return M
