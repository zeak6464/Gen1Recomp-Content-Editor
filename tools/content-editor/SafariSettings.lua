local M={}
function M.defaults(generation)
  return {fee=500,balls=30,steps=generation==3 and 600 or 500,yellowDiscount=true,
    exitMap="SAFARI_ZONE_GATE",exitX=4,exitY=3,facing="down"}
end
function M.validate(row,generation)
  if not row then return end
  assert(generation==1 or generation==3,"Safari settings require Gen 1 or Gen 3")
  local function integer(key,min,max)
    local v=row[key];assert(type(v)=="number" and v%1==0 and v>=min and v<=max,"Safari "..key.." must be "..min.." to "..max)
  end
  integer("balls",1,99);integer("steps",1,65533)
  if generation==1 then
    integer("fee",0,999999);integer("exitX",0,255);integer("exitY",0,255)
    assert(type(row.exitMap)=="string" and row.exitMap~="","Choose a Safari exit map")
    assert(({up=true,down=true,left=true,right=true})[row.facing],"Choose an exit direction")
    assert(type(row.yellowDiscount)=="boolean","Choose the Yellow discounted-entry setting")
  end
end
function M.emit(p,encode,out,generation)
  if not p.safariSettings then return end;M.validate(p.safariSettings,generation)
  out[#out+1]="local safariSettings=(function()\n"..assert(love.filesystem.read("tools/content-editor/SafariSettingsRuntime.lua")).."\nend)()"
  out[#out+1]="safariSettings.install(mod,"..encode(p.safariSettings)..","..generation..")"
end
function M.draw(S,x,y,w,h,App)
  local K,L,C=require("Kit"),require("RegList"),require("ChoicePicker");local s=K.scale
  local gen=require("Generation").num(S);local row=S.project.safariSettings
  K.caption(x,y,"SAFARI ZONE");y=y+38*s;h=h-38*s
  if not row then
    K.caption(x,y,"Customize the allowance for new Safari visits.")
    if K.button(x,y+40*s,220*s,30*s,"Customize Safari Zone",{kind="good"}) then S.project.safariSettings=M.defaults(gen);App.markDirty() end
    return
  end
  local Pane=require("FormPane");local first,view=Pane.begin(S,"safariSettings",x,y,w,h);y=first;w=view.contentW
  local function number(key,label)
    K.caption(x,y,label);local v=L.num(App,"safari/"..key,x+240*s,y,150*s,30*s,row[key])
    if v~=row[key] then row[key]=v;App.markDirty() end;y=y+45*s
  end
  if gen==1 then number("fee","Entry price") end
  number("balls","Safari Balls (1-99)");number("steps","Steps inside the zone")
  if gen==1 then
    if require("Generation").id(S)=="yellow" then
      if K.button(x,y,330*s,30*s,row.yellowDiscount and "Discounted entry: on" or "Discounted entry: off",{}) then row.yellowDiscount=not row.yellowDiscount;App.markDirty() end;y=y+44*s
      K.caption(x,y,"Yellow can admit players with reduced funds or no money.");y=y+35*s
    end
    local maps=L.mergeIds(S.project.maps or {},S.data.maps or {});local labels={}
    for _,id in ipairs(maps) do labels[id]=id:gsub("_"," ") end
    K.caption(x,y,"Exit map")
    C.field(S,{x=x+240*s,y=y,w=w-250*s,h=30*s,current=row.exitMap,ids=maps,labels=labels,title="Safari exit",onPick=function(id) row.exitMap=id;App.markDirty() end});y=y+45*s
    number("exitX","Exit cell X");number("exitY","Exit cell Y")
    C.field(S,{x=x+240*s,y=y,w=220*s,h=30*s,current=row.facing,ids={"up","down","left","right"},title="Exit facing",onPick=function(id) row.facing=id;App.markDirty() end})
    K.caption(x,y,"Exit facing");y=y+45*s
  else K.caption(x,y,"The native entrance event still controls the entry fee and exit.");y=y+35*s end
  K.caption(x,y,"Changes apply to new visits; an active visit keeps its remaining allowance.");y=y+42*s
  if K.button(x,y,180*s,30*s,"Revert Safari settings",{}) then S.project.safariSettings=nil;App.markDirty() end;y=y+45*s
  Pane.finish(S,"safariSettings",first,y,view)
end
return M
