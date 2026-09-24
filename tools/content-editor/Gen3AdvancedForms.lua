local M={}
M.kinds={"none","mega","primal","ultra","dynamax","gigantamax","tera","disguise","ice_face","gulp","power_construct","boss"}
M.labels={none="No special mechanic",mega="Mega Evolution",primal="Primal Reversion",ultra="Ultra Burst",dynamax="Dynamax",gigantamax="Gigantamax",tera="Terastallization",disguise="Disguise: absorb one hit",ice_face="Ice Face: absorb physical hit",gulp="Gulp Missile: load and retaliate",power_construct="Power Construct: gain form HP",boss="Boss phase: HP-triggered form"}
function M.validate(f)
  local kinds={};for _,k in ipairs(M.kinds) do kinds[k]=true end
  for i,row in ipairs(f.forms) do
    local c=row.mechanic
    if c and c.kind and c.kind~="none" then
      assert(kinds[c.kind],"Unknown advanced form mechanic")
      assert(f.forms[c.from or 1],"Choose the source form for "..row.name)
      assert(c.kind=="dynamax" or c.kind=="tera" or i~=(c.from or 1),"Choose a different result form for "..row.name)
      if c.kind=="tera" then assert(c.teraType and c.teraType~="","Choose a Tera type") end
      if c.kind=="gulp" then assert(c.move and c.move~="","Choose a loading move") end
      if c.kind=="gigantamax" then assert(c.maxMove and c.maxMove~="" and c.maxType,"Choose a G-Max move and its type") end
      if c.percent then assert(type(c.percent)=="number" and c.percent>=0 and c.percent<=100,"Invalid form HP threshold") end
      if c.swapFrom or c.swapTo then assert(c.swapFrom and c.swapTo,"Choose both signature moves") end
    end
  end
end
function M.draw(S,f,selection,x,y,w,App)
  local K,C=require("Kit"),require("ChoicePicker");local H=require("Gen3FormHelp");local s=K.scale;local row=f.forms[selection]
  row.mechanic=row.mechanic or {kind="none"};local c=row.mechanic
  local function field(key,ids,labels,title,default)
    K.caption(x,y,title);y=y+26*s
    C.field(S,{x=x,y=y,w=w,h=30*s,current=c[key] or default,ids=ids,labels=labels,title=title,tooltips=key=="kind" and H.mechanics or nil,tooltip=key=="kind" and H.mechanics[c.kind or "none"] or H.advanced[key],onPick=function(v) c[key]=v;App.markDirty() end});y=y+40*s
  end
  field("kind",M.kinds,M.labels,"Special form mechanic","none")
  if not c.kind or c.kind=="none" then return y end
  local ids,labels={},{};for i,r in ipairs(f.forms) do ids[i]=i;labels[i]=r.name end
  field("from",ids,labels,"Required starting form",1)
  for _,entry in ipairs({{"item","Required held item (optional)"},{"keyItem","Required Key Item (optional)"}}) do
    local key,title=entry[1],entry[2];K.caption(x,y,title);y=y+26*s
    require("ItemPicker").field(S,{x=x,y=y,w=w-100*s,h=30*s,current=c[key],title=title,tooltip=H.advanced[key],onPick=function(v) c[key]=v;App.markDirty() end})
    if K.button(x+w-90*s,y,90*s,30*s,"Clear",{tooltip="Remove this item requirement. The item itself is not deleted."}) then c[key]=nil;App.markDirty() end;y=y+40*s
  end
  local types=require("TypeIds").list(S)
  if c.kind=="tera" then
    types[#types+1]="STELLAR";field("teraType",types,nil,"Tera type")
    field("teraBlast",require("Autocomplete").moveIds(S),nil,"Tera Blast move (optional)")
  end
  if c.kind=="gulp" then
    field("move",require("Autocomplete").moveIds(S),nil,"Move that loads this form")
    field("payload",{"defense","paralysis"},{defense="Lower attacker's Defense",paralysis="Paralyze attacker"},"Retaliation effect","defense")
    field("hpCondition",{"any","below","above"},{any="Any HP",below="At or below half HP",above="Above half HP"},"Load at this HP","any")
  end
  if c.kind=="power_construct" or c.kind=="boss" then
    local values={};for n=0,100 do values[#values+1]=n end
    field("percent",values,nil,"Activate at or below HP %",50)
  end
  if c.kind=="gigantamax" then
    field("maxType",types,nil,"Type replaced by the G-Max move")
    field("maxMove",require("Autocomplete").moveIds(S),nil,"G-Max move (configure its effect in Moves)")
  end
  if c.kind=="disguise" then field("disguiseCost",{0,8},{[0]="Generation 7: no HP cost",[8]="Generation 8+: lose 1/8 maximum HP"},"Disguise HP cost",8) end
  K.caption(x,y,"Required ability ID (optional)");y=y+26*s
  local ability=K.textfield("advancedAbility"..selection,x,y,w,30*s,c.ability or "","Any ability",H.advanced.ability)
  if ability~=(c.ability or "") then c.ability=ability:upper();App.markDirty() end;y=y+40*s
  if K.button(x,y,240*s,28*s,c.signature and "Remove signature move swap" or "Add signature move swap",{tooltip="Configure a temporary move replacement for this transformation. Removing this setting clears the replacement rule, not the move records."}) then c.signature=not c.signature;if not c.signature then c.swapFrom=nil;c.swapTo=nil end;App.markDirty() end;y=y+40*s
  if c.signature then
    field("swapFrom",require("Autocomplete").moveIds(S),nil,"Original move")
    field("swapTo",require("Autocomplete").moveIds(S),nil,"Move while transformed")
  end
  K.caption(x,y,"In battle, press SELECT on the move menu to choose an available transformation.");y=y+28*s
  return y
end
return M
