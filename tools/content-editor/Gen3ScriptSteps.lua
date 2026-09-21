local M={}
local Kit=require("Kit")
local List=require("RegList")
local Writer=require("ModWriter")
local PAL=require("Theme").PAL
function M.draw(S,key,steps,templates,x,y,w,h,changed)
  local s=Kit.scale
  S._g3StepSelection=S._g3StepSelection or {}
  local selected=math.min(S._g3StepSelection[key] or 1,math.max(1,#steps))
  local lw=math.min(280*s,w*.38)
  Kit.caption(x,y,"COMMANDS ("..#steps..")")
  local yy=y+26*s
  local rh=29*s;local page=math.max(1,math.floor((h-115*s)/rh))
  local scrollKey="g3StepScroll/"..key
  S[scrollKey]=Kit.scroll(x,yy,lw,h-115*s,S[scrollKey] or 0,#steps,page)
  local first=S[scrollKey] or 0
  for i=first+1,math.min(#steps,first+page) do
    if Kit.row(x,yy,lw-18*s,rh-2*s,i==selected,PAL.blue) then selected=i;S._g3StepSelection[key]=i end
    Kit.text("micro",Kit.ellipsize("micro",i.."  "..tostring(steps[i].op),lw-35*s),x+7*s,yy+6*s,PAL.text)
    yy=yy+rh
  end
  S[scrollKey]=Kit.scrollbar(x,y+26*s,lw,h-115*s,S[scrollKey],#steps,page)
  local by=y+h-75*s
  local function action(label,col,fn)
    if Kit.button(x+col*66*s,by,62*s,27*s,label,{}) then fn();changed() end
  end
  action("Up",0,function() if selected>1 then steps[selected],steps[selected-1]=steps[selected-1],steps[selected];S._g3StepSelection[key]=selected-1 end end)
  action("Down",1,function() if selected<#steps then steps[selected],steps[selected+1]=steps[selected+1],steps[selected];S._g3StepSelection[key]=selected+1 end end)
  action("Copy",2,function() if steps[selected] then table.insert(steps,selected+1,require("src.mods.Merge").deepCopy(steps[selected])) end end)
  action("Delete",3,function() table.remove(steps,selected) end)
  local ops=List.sortedKeys(templates)
  require("ChoicePicker").field(S,{x=x,y=by+35*s,w=lw,h=28*s,ids=ops,current="",emptyLabel="Add command",title="ADD COMMAND",
    onPick=function(op)
      local at=math.min(#steps+1,selected+1)
      if steps[selected] and (steps[selected].op=="end" or steps[selected].op=="return") then at=selected end
      table.insert(steps,at,require("src.mods.Merge").deepCopy(templates[op]))
      S._g3StepSelection[key]=at;changed()
    end})
  local step=steps[selected]
  if not step then return end
  local fx=x+lw+16*s;local fw=w-lw-16*s
  Kit.caption(fx,y,"STEP "..selected.." / "..step.op)
  if step.op=="applymovement" and type(step.movement)=="table" then
    local toggle="g3MovementRaw/"..key
    if Kit.button(fx,y+25*s,180*s,26*s,S[toggle] and "Movement designer" or "Raw arguments",{}) then S[toggle]=not S[toggle] end
    if not S[toggle] then
      require("Gen3MovementEditor").draw(S,key.."/"..selected,step,fx,y+60*s,fw,h-60*s,changed)
      return
    end
  end
  Kit.caption(fx,y+24*s,"Arguments use FireRed's native command format")
  local draft={value=Writer.encodeLua(step)}
  S._g3Expanded=S._g3Expanded or {};S._g3Expanded.value=true
  local top,view=require("FormPane").begin(S,"g3StepFields/"..key,fx,y+58*s,fw,h-58*s)
  local ending=require("Gen3Fields").draw(S,key.."/"..selected,fx,top,view.contentW,draft,{value={kind="any"}})
  require("FormPane").finish(S,"g3StepFields/"..key,top,ending,view)
  if draft.value~=Writer.encodeLua(step) then
    local box=require("Gen3Decode").decode("return {value="..draft.value.."}",{allowArray=true})
    if box and type(box.value)=="table" and type(box.value.op)=="string" and Writer.encodeLua(box.value)~=Writer.encodeLua(step) then steps[selected]=box.value;changed() end
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
