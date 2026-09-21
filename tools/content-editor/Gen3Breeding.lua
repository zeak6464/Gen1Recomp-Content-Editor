local M={}
function M.originalMoves(S)
  if S.data._editorEggMoves then return S.data._editorEggMoves end
  local bytes,err=require("Gen3Rom").open(S);if not bytes then return nil,err end
  local result,current={},nil
  for offset=0x25ef0c,0x26ef0c,2 do
    local a,b=bytes:byte(offset+1,offset+2);assert(a and b,"Egg move table is truncated")
    local v=a+b*256
    if v==65535 then S.data._editorEggMoves=result;return result end
    if v>=20000 then current=v-20000;assert(current<=411,"Invalid egg species");result[current]={}
    else assert(current and v>0 and v<=354,"Invalid egg move");table.insert(result[current],v) end
  end
  error("Egg move terminator not found")
end
function M.ensure(S)
  if S.project.gen3Breeding then return S.project.gen3Breeding end
  local original,err=M.originalMoves(S);assert(original,err)
  local max=411;for _,bag in ipairs({S.data.pokemon,S.project.pokemon}) do for _,mon in pairs(bag or {}) do max=math.max(max,mon.index or 0) end end
  S.project.gen3Breeding={enabled=false,eggMoves=require("src.mods.Merge").deepCopy(original),steps=256,eggLevel=5,expPerStep=1,fee=100,feePerLevel=100,maxSpecies=max}
  return S.project.gen3Breeding
end
function M.attach(S,map,npc)
  local original=S.project;local T=setmetatable({project=require("src.mods.Merge").deepCopy(original)},{__index=S})
  local ok,key=pcall(function()
    local config=M.ensure(T);config.enabled=true
    assert(require("Gen3Workspace").convert(T,map))
    local object=assert((T.project.maps[map].objects or {})[tonumber(npc)],"Choose an NPC")
    local p=T.project;local key="EditorDaycare_"..p.id:gsub("[^%w_]","_")
    p.gen3=p.gen3 or {};p.gen3.map_scripts=p.gen3.map_scripts or {}
    p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
    p.gen3.map_scripts[key]={{op="lock"},{op="faceplayer"},{op="editor_daycare",owner=p.id},{op="release"},{op="end"}}
    p.gen3Modes.map_scripts[key]="register";object.scriptKey=key
    return key
  end)
  if not ok then return nil,tostring(key) end
  for k in pairs(original) do original[k]=nil end;for k,v in pairs(T.project) do original[k]=v end
  return key
end
function M.eggFields(S,mon,x,y,w,App)
  local K,P=require("Kit"),require("ChoicePicker");local s=K.scale
  K.caption(x,y,"Egg moves inherited from the father");y=y+30*s
  local base,err=M.originalMoves(S)
  if not base then K.caption(x,y,err);return y+36*s end
  local list=((S.project.gen3Breeding or {}).eggMoves or base)[mon.index] or {}
  local ids,labels={},{}
  for _,id in ipairs(require("RegList").mergeIds(S.project.moves,S.data.moves)) do
    local move=S.project.moves[id] or S.data.moves[id];ids[#ids+1]=tostring(move.index);labels[tostring(move.index)]=(move.name or id):gsub("_"," ")
  end
  for i,id in ipairs(list) do
    P.field(S,{x=x,y=y,w=w-90*s,h=28*s,ids=ids,labels=labels,current=tostring(id),title="Inherited move",
      onPick=function(value) M.ensure(S).eggMoves[mon.index][i]=tonumber(value);App.markDirty() end})
    if K.button(x+w-84*s,y,84*s,28*s,"Remove",{}) then table.remove(M.ensure(S).eggMoves[mon.index],i);App.markDirty();break end
    y=y+36*s
  end
  P.field(S,{x=x,y=y,w=w,h=28*s,ids=ids,labels=labels,emptyLabel="Add an egg move",title="Add an egg move",onPick=function(value)
    local b=M.ensure(S);b.eggMoves[mon.index]=b.eggMoves[mon.index] or {}
    for _,id in ipairs(b.eggMoves[mon.index]) do if id==tonumber(value) then return end end
    table.insert(b.eggMoves[mon.index],tonumber(value));App.markDirty()
  end});y=y+38*s
  if K.button(x,y,220*s,28*s,"Restore original egg moves",{}) then M.ensure(S).eggMoves[mon.index]=require("src.mods.Merge").deepCopy(base[mon.index] or {});App.markDirty() end
  return y+42*s
end
function M.draw(S,x,y,w,h,App)
  local K,P,L=require("Kit"),require("ChoicePicker"),require("RegList");local s=K.scale
  local top,view=require("FormPane").begin(S,"g3Daycare",x,y,w,h);y=top;w=view.contentW
  K.caption(x,y,"DAY-CARE: two parents, inherited moves, and Eggs");y=y+36*s
  local config=S.project.gen3Breeding or {}
  if K.button(x,y,240*s,28*s,config.enabled and "Pause egg production" or "Enable Day-Care",{}) then
    local ok,err=pcall(function() local b=M.ensure(S);b.enabled=not b.enabled end)
    if ok then App.markDirty() else S.status=tostring(err) end
  end;y=y+40*s
  for _,row in ipairs({{"steps","Steps between egg checks",256,1,65535},{"expPerStep","Experience per step",1,0,100},{"fee","Base withdrawal fee",100,0,99999},{"feePerLevel","Extra fee per level",100,0,99999}}) do
    K.caption(x,y,row[2]);local old=config[row[1]] or row[3]
    local value=math.floor(math.max(row[4],math.min(row[5],L.num(App,"g3_breed_"..row[1],x+330*s,y,120*s,28*s,old))))
    if value~=old then local ok,err=pcall(function() M.ensure(S)[row[1]]=value end);if ok then App.markDirty() else S.status=tostring(err) end end
    y=y+36*s
  end
  K.caption(x,y,"Hatched Pokemon start at level 5, matching FireRed.");y=y+34*s
  K.caption(x,y,"Assign the service to an NPC (replaces that NPC's conversation)");y=y+34*s
  local maps=L.mergeIds(S.project.maps,S.data.maps);local labels={}
  for _,id in ipairs(maps) do labels[id]=require("Gen3Labels").map(id) end
  P.field(S,{x=x,y=y,w=w,h=28*s,ids=maps,labels=labels,current=S.g3DaycareMap,emptyLabel="Choose a map",title="Day-Care map",onPick=function(v) S.g3DaycareMap=v;S.g3DaycareNpc=nil end});y=y+36*s
  local map=S.project.maps[S.g3DaycareMap] or S.data.maps[S.g3DaycareMap] or {}
  local ids,names={},{};for i,obj in ipairs(map.objects or {}) do ids[#ids+1]=tostring(i);names[tostring(i)]="NPC "..i.." ("..tostring(obj.x)..", "..tostring(obj.y)..")" end
  P.field(S,{x=x,y=y,w=w,h=28*s,ids=ids,labels=names,current=S.g3DaycareNpc,emptyLabel="Choose an NPC on that map",title="Day-Care attendant",onPick=function(v) S.g3DaycareNpc=v end});y=y+38*s
  if K.button(x,y,240*s,28*s,"Assign Day-Care attendant",{kind="good"}) then
    local key,err=M.attach(S,S.g3DaycareMap,S.g3DaycareNpc);S.status=key and "Day-Care attendant assigned. Save your mod." or err;if key then App.markDirty() end
  end;y=y+42*s
  K.caption(x,y,"In game: leave two parents, walk, then return to collect the Egg.");y=y+32*s
  K.caption(x,y,"Parents and pending Eggs stay in this mod's save data. Withdraw before disabling it.");y=y+32*s
  require("FormPane").finish(S,"g3Daycare",top,y,view)
end
function M.emit(p,encode,out)
  local b=p.gen3Breeding;if not b then return end
  b=require("src.mods.Merge").deepCopy(b)
  for _,mon in pairs(p.pokemon or {}) do b.maxSpecies=math.max(b.maxSpecies or 411,tonumber(mon.index) or 0) end
  for _,row in ipairs({{"steps",1,65535},{"expPerStep",0,100},{"fee",0,99999},{"feePerLevel",0,99999}}) do
    local v=b[row[1]];assert(type(v)=="number" and v%1==0 and v>=row[2] and v<=row[3],"Invalid Day-Care "..row[1]) end
  for species,moves in pairs(b.eggMoves or {}) do assert(type(species)=="number" and species>0,"Invalid egg species")
    for _,id in ipairs(moves) do assert(type(id)=="number" and id%1==0 and id>0,"Invalid egg move") end end
  local source=assert(love.filesystem.read("tools/content-editor/Gen3BreedingRuntime.lua"))
  out[#out+1]="  local daycare=(function()\n"..source.."\nend)()("..encode(b)..",mod)\n  daycare.install()"
end
return M
