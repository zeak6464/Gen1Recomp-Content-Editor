local M={}
local K,C=require("Kit"),require("ChoicePicker")
function M.defaults()
  -- FireRed heal_locations.json outdoor arrival tiles (not whiteout rooms).
  local towns={{"PALLET_TOWN",6,8},{"VIRIDIAN_CITY",26,27},{"PEWTER_CITY",17,26},{"CERULEAN_CITY",22,20},{"LAVENDER_TOWN",6,6},{"VERMILION_CITY",15,7},{"CELADON_CITY",48,12},{"FUCHSIA_CITY",25,32},{"CINNABAR_ISLAND",14,12},{"INDIGO_PLATEAU",11,7},{"SAFFRON_CITY",24,39},{"ROUTE4",12,6},{"ROUTE10",13,21}}
  local result={};local grid=require("src.import.gba.region_map_extract")
  for _,t in ipairs(towns) do
    local loc=grid.resolveLocation(t[1]:gsub("ROUTE(%d)","ROUTE_%1"));result[#result+1]={name=t[1]:gsub("_"," "),map="FR_"..(t[1]=="INDIGO_PLATEAU" and "INDIGO_PLATEAU_EXTERIOR" or t[1]),x=t[2],y=t[3],mapX=loc.x,mapY=loc.y,unlock="visited",enabled=true}
  end
  return result
end
function M.validate(rows)
  for _,r in ipairs(rows) do
    assert(type(r.name)=="string" and r.name:match("%S"),"Give each Fly destination a name")
    assert(type(r.map)=="string" and r.map~="","Choose a landing map")
    for _,key in ipairs({"x","y","mapX","mapY"}) do assert(type(r[key])=="number" and r[key]>=0 and r[key]%1==0,"Fly coordinates must be whole, non-negative numbers") end
    assert(r.mapX<=21 and r.mapY<=14,"Fly marker is outside the Town Map")
    assert(r.unlock=="visited" or r.unlock=="always" or r.unlock=="flag","Choose when Fly becomes available")
    if r.unlock=="flag" then assert(type(r.flag)=="number" and r.flag>0 and r.flag%1==0,"Choose a valid unlock flag") end
  end
end
function M.draw(S,x,y,w,h,App)
  local s=K.scale;local fh=30*s
  if not S.project.gen3Fly then
    K.caption(x,y,"Set where Fly takes the player, and when each location unlocks.")
    if K.button(x,y+40*s,260*s,fh,"Set up Fly destinations",{kind="good"}) then S.project.gen3Fly=M.defaults();App.markDirty() end
    return
  end
  local rows=S.project.gen3Fly;local ids,labels={},{}
  for i,r in ipairs(rows) do ids[i]=tostring(i);labels[tostring(i)]=r.name end
  S.g3FlyIndex=math.max(1,math.min(S.g3FlyIndex or 1,#rows))
  C.field(S,{x=x,y=y,w=w-230*s,h=fh,current=tostring(S.g3FlyIndex),ids=ids,labels=labels,title="Fly destination",onPick=function(id) S.g3FlyIndex=tonumber(id) end})
  if K.button(x+w-220*s,y,210*s,fh,"Add destination",{kind="good"}) then rows[#rows+1]={name="New destination",map="FR_PALLET_TOWN",x=6,y=8,mapX=4,mapY=11,unlock="visited",enabled=true};S.g3FlyIndex=#rows;App.markDirty() end
  local r=rows[S.g3FlyIndex];if not r then return end
  y=y+45*s
  local function text(label,key)
    K.caption(x,y,label);local v=K.textfield("fly_"..key,x+160*s,y,w-170*s,fh,r[key] or "","")
    if v~=r[key] then r[key]=v;App.markDirty() end;y=y+40*s
  end
  local function choice(label,key,options,names,after)
    K.caption(x,y,label);C.field(S,{x=x+160*s,y=y,w=w-170*s,h=fh,current=r[key],ids=options,labels=names,title=label,onPick=function(id) r[key]=id;if after then after(id) end;App.markDirty() end});y=y+40*s
  end
  text("Location name","name")
  local maps,mapNames={},{};local seen={}
  for _,bag in ipairs({S.data.maps or {},S.project.maps or {},S.project.gen3Maps or {}}) do for id in pairs(bag) do if not seen[id] then seen[id]=true;maps[#maps+1]=id;mapNames[id]=require("Gen3Labels").map(id) end end end;table.sort(maps)
  choice("Landing map","map",maps,mapNames)
  local function number(label,key,max)
    K.caption(x,y,label);local v=require("RegList").num(App,"fly_"..key,x+160*s,y,130*s,fh,r[key]);v=math.max(0,math.min(max or 65535,math.floor(v)))
    if v~=r[key] then r[key]=v;App.markDirty() end;y=y+40*s
  end
  number("Landing tile X","x");number("Landing tile Y","y")
  choice("Available when","unlock",{"visited","always","flag"},{visited="After visiting the landing map",always="Always available",flag="A story flag is set"},function(id) if id=="flag" then r.flag=r.flag or 1 end end)
  if r.unlock=="flag" then
    local flags,names={},{};for id,name in pairs(require("src.core.game3.scripting.flags").NAMES or {}) do if type(id)=="number" and id>0 then flags[#flags+1]=id;names[id]=name:gsub("^FLAG_",""):gsub("_"," ") end end;table.sort(flags)
    choice("Story flag","flag",flags,names)
  end
  number("Town Map column","mapX",21);number("Town Map row","mapY",14)
  if K.button(x,y,180*s,fh,r.enabled==false and "Enable destination" or "Disable destination",{}) then r.enabled=r.enabled==false;App.markDirty() end
  if K.button(x+190*s,y,180*s,fh,"Remove destination",{kind="danger"}) then table.remove(rows,S.g3FlyIndex);App.markDirty() end
  y=y+42*s;K.caption(x,y,"Tiles start at 0. Choose a clear outdoor tile. Fly still requires the Thunder Badge.")
  K.caption(x,y+24*s,"Visited locations are remembered from when this mod is enabled.")
end
function M.emit(p,encode,out)
  if not p.gen3Fly then return end
  M.validate(p.gen3Fly)
  out[#out+1]="local fly=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FlyRuntime.lua")).."\nend)()\nfly.install(mod,"..encode(p.gen3Fly)..")"
end
return M
