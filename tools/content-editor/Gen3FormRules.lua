local M={}
M.triggers={"move_used","move_hit","damaging_move","knows_move","item_use","battle_start","switch_out","turn_end","hp_below","hp_above","weather","held_item","damage_taken","knockout"}
M.labels={move_used="When a specific move is used",move_hit="After a specific move deals damage",damaging_move="When any damaging move is used",knows_move="While knowing a move (outside battle)",item_use="Use an item outside battle",battle_start="On entering battle",switch_out="When switching out",turn_end="At the end of each turn",hp_below="At or below HP percentage (entry / turn end)",hp_above="Above HP percentage (entry / turn end)",weather="While battle weather matches",held_item="While holding an item in battle",damage_taken="After taking move damage",knockout="After knocking out an opponent"}
function M.validate(f)
  local valid={};for _,id in ipairs(M.triggers) do valid[id]=true end
  local known,usedItem=false,false
  for _,r in ipairs(f.rules or {}) do
    assert(valid[r.trigger],"Choose a form rule trigger")
    assert(type(r.target)=="number" and f.forms[r.target],"Choose a valid target form")
    assert(r.from==nil or r.from==0 or f.forms[r.from],"Choose a valid source form")
    assert(r.duration=="switch" or r.duration=="battle" or r.duration==nil,"Invalid rule duration")
    if r.trigger=="move_used" or r.trigger=="move_hit" or r.trigger=="knows_move" then assert(type(r.move)=="string" and r.move~="","Choose a rule move") end
    known=known or r.trigger=="knows_move";usedItem=usedItem or r.trigger=="item_use"
    if r.trigger=="knows_move" then assert(not r.from or r.from==0,"Known-move rules require Any form as the source") end
    if r.trigger=="item_use" or r.trigger=="held_item" then assert(type(r.item)=="string" and r.item~="","Choose a rule item") end
    if r.trigger=="weather" then assert(({NONE=true,SUN=true,RAIN=true,HAIL=true,SAND=true})[r.weather or "NONE"],"Choose rule weather") end
    if r.trigger=="hp_below" or r.trigger=="hp_above" then assert(r.percent==nil or (type(r.percent)=="number" and r.percent>=0 and r.percent<=100),"HP threshold must be 0 to 100") end
    assert(not r.minLevel or (r.minLevel>=1 and r.minLevel<=100 and r.minLevel%1==0),"Minimum level must be 1 to 100")
  end
  assert(not (known and usedItem),"Use separate form families for known-move and item-use selection")
end
function M.draw(S,f,selection,x,y,w,App)
  local K,C=require("Kit"),require("ChoicePicker");local H=require("Gen3FormHelp");local s=K.scale
  f.rules=f.rules or {}
  K.caption(x,y,"Rules run in order; the first matching rule wins for each event.");y=y+28*s
  K.caption(x,y,"Battle changes keep moves, PP, status, stat stages and maximum HP.");y=y+28*s
  if K.button(x,y,240*s,30*s,"Add rule for this form",{kind="good",tooltip="Add a condition that transforms into the selected form. Earlier matching rules take priority."}) then f.rules[#f.rules+1]={target=selection,from=0,trigger="battle_start",duration="switch",minLevel=1};App.markDirty() end;y=y+42*s
  local ids,labels={0},{[0]="Any form"}
  for i,row in ipairs(f.forms) do ids[#ids+1]=i;labels[i]=row.name end
  local remove
  for i,r in ipairs(f.rules) do if r.target==selection then
    local function field(key,list,names,title,default)
      K.caption(x,y,title);y=y+26*s
      C.field(S,{x=x,y=y,w=w,h=30*s,current=r[key] or default,ids=list,labels=names,title=title,tooltip=H.rules[key],onPick=function(v) r[key]=v;App.markDirty() end});y=y+40*s
    end
    K.caption(x,y,"Rule "..i.." - "..f.forms[selection].name);y=y+28*s
    field("trigger",M.triggers,M.labels,"Transformation trigger","battle_start")
    field("from",ids,labels,"Required current form",0)
    if r.trigger=="move_used" or r.trigger=="move_hit" or r.trigger=="knows_move" then field("move",require("Autocomplete").moveIds(S),nil,"Trigger move") end
    if r.trigger=="item_use" or r.trigger=="held_item" then
      require("ItemPicker").field(S,{x=x,y=y,w=w,h=30*s,current=r.item,title="FORM ITEM",tooltip=H.rules.item,onPick=function(v) r.item=v;App.markDirty() end});y=y+40*s
    end
    if r.trigger=="weather" then field("weather",{"NONE","SUN","RAIN","HAIL","SAND"},nil,"Required weather","NONE") end
    if r.trigger=="hp_below" or r.trigger=="hp_above" then
      local values={};for n=0,100 do values[#values+1]=n end
      field("percent",values,nil,"HP percentage threshold",50)
    end
    local levels={};for n=1,100 do levels[n]=n end
    field("minLevel",levels,nil,"Minimum level",1)
    if r.trigger~="item_use" and r.trigger~="knows_move" then
      K.caption(x,y,"Required ability ID (optional)");y=y+26*s
      local ability=K.textfield("formRuleAbility"..i,x,y,w,30*s,r.ability or "","Any ability","Use the ability's ID, such as FORECAST.")
      if ability~=(r.ability or "") then r.ability=ability:upper();App.markDirty() end;y=y+40*s
    end
    if r.trigger=="item_use" then
      field("consume",{false,true},{[false]="Reusable item",[true]="Consume one item"},"Item consumption",false)
    elseif r.trigger~="knows_move" then
      field("duration",{"switch","battle"},{switch="Revert on switching out / battle end",battle="Keep until battle ends"},"Transformation duration","switch")
    end
    if K.button(x,y,180*s,28*s,"Remove rule "..i,{tooltip="Delete this condition. The target form and its species data remain available."}) then remove=i end;y=y+44*s
  end end
  if remove then table.remove(f.rules,remove);App.markDirty() end
  return y
end
return M
