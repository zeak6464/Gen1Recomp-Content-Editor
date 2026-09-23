local M={}
local K,C=require("Kit"),require("ChoicePicker")
function M.defaults()
  local maps={};for i=1,25 do maps[#maps+1]=i==21 and "FR_ROUTE21_NORTH" or (i<=2 and "FR_ROUTE_" or "FR_ROUTE")..i end
  return {id="kanto_beast",name="Kanto roaming legendary",enabled=true,selection="starter",species="ENTEI",
    starters={bulbasaur="ENTEI",charmander="SUICUNE",squirtle="RAIKOU"},level=50,chance=25,
    unlock="postgame",flag=0x844,flee="attempt",defeat="stop",maps=maps}
end
function M.add(S)
  local rows=S.project.gen3Roamers or {};S.project.gen3Roamers=rows
  local used={};for _,row in ipairs(rows) do used[row.id]=true end
  local i=1;while used["roamer_"..i] do i=i+1 end
  local row=M.defaults();row.id="roamer_"..i;row.name="New roaming Pokemon";row.selection="fixed";row.unlock="always"
  rows[#rows+1]=row;return row
end
function M.validate(rows)
  local seen={}
  for _,row in ipairs(rows) do
    assert(type(row.id)=="string" and row.id~="" and not seen[row.id],"Roamers need unique IDs");seen[row.id]=true
    assert(type(row.name)=="string" and row.name:match("%S"),"Give each roamer a name")
    assert(row.selection=="fixed" or row.selection=="starter","Choose how the roaming Pokemon is selected")
    assert(type(row.species)=="string" and row.species~="","Choose a roaming Pokemon")
    if row.selection=="starter" then for _,k in ipairs({"bulbasaur","charmander","squirtle"}) do assert(type(row.starters[k])=="string" and row.starters[k]~="","Choose all three starter-dependent roamers") end end
    assert(type(row.level)=="number" and row.level%1==0 and row.level>=1 and row.level<=100,"Roamer level must be 1 to 100")
    assert(type(row.chance)=="number" and row.chance%1==0 and row.chance>=1 and row.chance<=100,"Roamer chance must be 1 to 100 percent")
    assert(row.unlock=="always" or row.unlock=="postgame" or row.unlock=="flag","Choose when roaming starts")
    if row.unlock=="flag" then assert(type(row.flag)=="number" and row.flag%1==0 and row.flag>0,"Choose a story flag") end
    assert(row.flee=="attempt" or row.flee=="fight","Choose roaming battle behavior")
    assert(row.defeat=="stop" or row.defeat=="return","Choose what happens after defeat")
    assert(type(row.maps)=="table" and #row.maps>0,"Choose at least one roaming map")
    local maps={};for _,id in ipairs(row.maps) do assert(type(id)=="string" and id~="" and not maps[id],"Roaming maps must be unique");maps[id]=true end
  end
end
function M.draw(S,x,y,w,h,App)
  local s=K.scale;local fh=30*s;local rows=S.project.gen3Roamers
  if not rows then
    K.caption(x,y,"Roaming Pokemon travel between maps and remember their remaining HP and status.")
    if K.button(x,y+42*s,300*s,fh,"Set up roaming legendary",{kind="good"}) then S.project.gen3Roamers={M.defaults()};App.markDirty() end
    if K.button(x,y+84*s,300*s,fh,"Create a custom roaming Pokemon",{}) then M.add(S);App.markDirty() end
    return
  end
  local ids,names={},{};for i,row in ipairs(rows) do ids[i]=tostring(i);names[tostring(i)]=row.name end
  S.g3RoamerIndex=math.max(1,math.min(S.g3RoamerIndex or 1,#rows))
  C.field(S,{x=x,y=y,w=w-230*s,h=fh,current=tostring(S.g3RoamerIndex),ids=ids,labels=names,title="Roaming Pokemon",onPick=function(id) S.g3RoamerIndex=tonumber(id) end})
  if K.button(x+w-220*s,y,210*s,fh,"Add roaming Pokemon",{kind="good"}) then M.add(S);S.g3RoamerIndex=#rows;App.markDirty() end
  local row=rows[S.g3RoamerIndex];if not row then return end
  local Pane=require("FormPane");local top=y+45*s
  Pane.track(S,"roamerScroll",row.id);local first,view=Pane.begin(S,"roamerScroll",x,top,w,h-45*s);y=first;w=view.contentW
  local function choice(label,key,options,labels,tip)
    K.caption(x,y,label);C.field(S,{x=x+210*s,y=y,w=w-220*s,h=fh,current=row[key],ids=options,labels=labels,title=label,tooltip=tip,onPick=function(id) row[key]=id;App.markDirty() end});y=y+42*s
  end
  K.caption(x,y,"Name");local name=K.textfield("roamerName",x+210*s,y,w-220*s,fh,row.name,"Roamer name","An editor label, such as Kanto legendary or Wandering Mew.")
  if name~=row.name then row.name=name;App.markDirty() end;y=y+42*s
  choice("Choose Pokemon","selection",{"fixed","starter"},{fixed="Always the same Pokemon",starter="Depends on the starter choice"},"Starter choice means the original left/middle/right choice in Oak's lab, even if you replace the starter species.")
  local function species(label,bag,key)
    K.caption(x,y,label);require("SpeciesPicker").field(S,{x=x+210*s,y=y,w=w-220*s,h=fh,current=bag[key],onPick=function(id) bag[key]=id;App.markDirty() end});y=y+44*s
  end
  if row.selection=="starter" then
    species("Bulbasaur choice",row.starters,"bulbasaur");species("Charmander choice",row.starters,"charmander");species("Squirtle choice",row.starters,"squirtle")
  else species("Pokemon",row,"species") end
  for _,v in ipairs({{"Level","level"},{"Encounter chance %","chance"}}) do
    K.caption(x,y,v[1]);K.offerTooltip(x,y,w,fh,v[2]=="level" and "The level used when this roamer is first created in a save." or "Chance of replacing a normal grass encounter while this roamer is on the same map. Multiple roamers share the roll.")
    local n=require("RegList").num(App,"roamer_"..v[2],x+210*s,y,130*s,fh,row[v[2]]);n=math.max(1,math.min(100,math.floor(n)))
    if n~=row[v[2]] then row[v[2]]=n;App.markDirty() end;y=y+42*s
  end
  choice("Starts roaming","unlock",{"postgame","always","flag"},{postgame="After Celio's Ruby / Sapphire quest",always="As soon as the mod is active",flag="When a story flag is set"})
  if row.unlock=="flag" then
    local flags,labels={},{};for id,name in pairs(require("src.core.game3.scripting.flags").NAMES or {}) do if type(id)=="number" and id>0 then flags[#flags+1]=id;labels[id]=name:gsub("^FLAG_",""):gsub("_"," ") end end;table.sort(flags)
    choice("Story flag","flag",flags,labels)
  end
  choice("Battle behavior","flee",{"attempt","fight"},{attempt="Fight, then flee after a turn unless trapped",fight="Stay and fight"})
  choice("After being defeated","defeat",{"stop","return"},{stop="Stop roaming permanently",["return"]="Recover and continue roaming"})
  K.caption(x,y,"Catching always stops this roamer. HP and status are remembered after escape.");y=y+30*s
  K.caption(x,y,"Moves to another allowed map when you change maps or its battle ends.");y=y+36*s
  local maps,mapNames={},{};local seen={}
  for _,bag in ipairs({S.data.maps or {},S.project.maps or {},S.project.gen3Maps or {}}) do for id in pairs(bag) do if not seen[id] then seen[id]=true;maps[#maps+1]=id;mapNames[id]=require("Gen3Labels").map(id) end end end;table.sort(maps)
  K.caption(x,y,"Allowed roaming maps (grass encounters)");y=y+30*s
  for i,id in ipairs(row.maps) do
    C.field(S,{x=x,y=y,w=w-110*s,h=fh,current=id,ids=maps,labels=mapNames,title="Roaming map",onPick=function(value)
      for j,other in ipairs(row.maps) do if j~=i and other==value then S.status="That map is already included";return end end
      row.maps[i]=value;App.markDirty()
    end})
    if K.button(x+w-100*s,y,90*s,fh,"Remove",{}) and #row.maps>1 then table.remove(row.maps,i);App.markDirty();break end;y=y+38*s
  end
  C.field(S,{x=x,y=y,w=w,h=fh,current="",ids=maps,labels=mapNames,title="Add a roaming map",emptyLabel="Add a roaming map",onPick=function(id)
    for _,value in ipairs(row.maps) do if value==id then S.status="That map is already included";return end end
    row.maps[#row.maps+1]=id;App.markDirty()
  end});y=y+44*s
  if K.button(x,y,190*s,fh,row.enabled==false and "Enable roamer" or "Disable roamer",{}) then row.enabled=row.enabled==false;App.markDirty() end
  if K.button(x+200*s,y,190*s,fh,"Remove roamer",{kind="danger"}) then table.remove(rows,S.g3RoamerIndex);App.markDirty() end
  y=y+44*s;Pane.finish(S,"roamerScroll",first,y,view)
end
function M.emit(p,encode,out)
  if not p.gen3Roamers then return end;M.validate(p.gen3Roamers)
  out[#out+1]="local roamers=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3RoamersRuntime.lua")).."\nend)()\nroamers.install(mod,"..encode(p.gen3Roamers)..")"
end
return M
