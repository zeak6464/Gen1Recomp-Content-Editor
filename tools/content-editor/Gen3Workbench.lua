local M={}
function M.prepare(S)
  require("Gen3ContentAdapter").prepare(S)
  S.project.gen3Workbench=true
  local T=require("src.core.game3.battle.types")
  if not S.data._g3TypeChart then
    local chart={types={},matchups={}}
    for name,index in pairs(T.ID) do
      chart.types[name]={id=name,name=name,index=index,category=T.isPhysical(index) and "physical" or "special"}
      for defender,di in pairs(T.ID) do
        chart.matchups[#chart.matchups+1]={attacker=name,defender=defender,multiplier=T.effectiveness(index,di)*10}
      end
    end
    S.data._g3TypeChart=chart
  end
  S.data.type_chart=S.data._g3TypeChart
end
function M.shops(S)
  M.prepare(S)
  local pack=require("Gen3Resources").readTable(S.data,"data/generated/gba/scripts/marts.lua")
  local items={};for id,item in pairs(S.data.items or {}) do items[item.index]=id end
  if not S.data._g3ShopLocations then
    local usage={};local maps=require("Gen3Labels").scriptMaps(S)
    for script,rows in pairs(require("Gen3").catalog(S.data,"map_scripts")) do
      for _,row in ipairs(rows) do if row.op=="pokemart" then
        local key=row.items or row.ptr or row[1];usage[key]=usage[key] or {}
        for map in pairs(maps[script] or {}) do usage[key][require("Gen3Labels").map(map)]=true end
      end end
    end
    S.data._g3ShopLocations=usage
  end
  local keys,rows={},{}
  for _,rec in pairs(pack.marts or {}) do
    local key=rec.key or tostring(rec.ptr)
    if not rows[key] then
      local stock={};for i,id in ipairs(rec.items or {}) do stock[i]=items[id] or tostring(id) end
      local edit=(S.project.marts or {})[key]
      local locations=require("RegList").sortedKeys(S.data._g3ShopLocations[key] or {})
      rows[key]={key=key,label=#locations>0 and table.concat(locations," / ") or key,textId=key,mart=edit or stock,base=stock,ptr=rec.ptr,owned=edit~=nil,kind="list"}
      keys[#keys+1]=key
    end
  end
  table.sort(keys);return keys,rows
end
function M.used(p)
  return p.gen3Workbench and (next(p.boot or {}) or next(p.marts or {}) or next(p.types or {}) or next(p.type_matchups or {}))
end
function M.emit(p,encode,out)
  if not M.used(p) then return end
  local T=require("src.core.game3.battle.types")
  for id,rec in pairs(p.types or {}) do
    assert(T.ID[id]~=nil,"FireRed type IDs cannot be added or renamed")
    assert(rec.category=="physical" or rec.category=="special","Invalid type category")
  end
  for key,mult in pairs(p.type_matchups or {}) do
    local a,d=key:match("^([^>]+)>([^>]+)$")
    assert(T.ID[a] and T.ID[d] and (mult==0 or mult==5 or mult==10 or mult==20),"Invalid FireRed matchup")
  end
  out[#out+1]="  local workbench="..encode({boot=p.boot or {},shops=p.marts or {},types=p.types or {},matchups=p.type_matchups or {}})
  out[#out+1]=M.source
end
M.source=[=[
  local Runtime=require("src.mods.Runtime")
  mod.hooks:wrap("save.new_game",function(proceed,session)
    session=proceed(session)
    local b=workbench.boot
    for from,to in pairs({startMap="map",startX="x",startY="y",startFacing="facing",startMoney="money",playerName="name",rivalName="rivalName"}) do
      if b[from]~=nil then session[to]=b[from] end
    end
    for from,to in pairs({map="healMap",x="healX",y="healY"}) do
      if b.lastHeal and b.lastHeal[from]~=nil then session[to]=b.lastHeal[from] end
    end
    local function itemId(id)
      local rec=mod.content.items:get(id)
      return assert((rec and rec.index) or tonumber(id),"Unknown starting item "..id)
    end
    if b.startItems then
      local Bag=require("src.core.game3.bag");session.bag=Bag.new()
      for _,row in ipairs(b.startItems) do Bag.add(session.bag,itemId(row.id),row.count or 1) end
    end
    if b.startPcItems then
      session.storage.items={}
      for i,row in ipairs(b.startPcItems) do session.storage.items[i]={id=itemId(row.id),qty=row.count or 1} end
    end
    return session
  end)
  local Marts=require("src.core.game3.marts")
  local Types=require("src.core.game3.battle.types")
  if not Marts._editorWorkbench then
    Marts._editorWorkbench=true
    local base=Marts.itemsFor
    Marts.itemsFor=function(...) return Runtime.call("editor.gen3.mart",base,...) end
  end
  mod.hooks:wrap("editor.gen3.mart",function(proceed,key)
    local items,rec=proceed(key)
    local stock=workbench.shops[tostring(key)] or (rec and workbench.shops[rec.key])
    if not stock then return items,rec end
    local output={}
    for i,id in ipairs(stock) do
      local item=mod.content.items:get(id)
      output[i]=assert((item and item.index) or tonumber(id),"Unknown shop item "..id)
    end
    return output,rec
  end)
  if not Types._editorWorkbench then
    Types._editorWorkbench=true
    for _,method in ipairs({"name","isPhysical","typeCalc","effectiveness"}) do
      local base=Types[method]
      Types[method]=function(...) return Runtime.call("editor.gen3.types."..method,base,...) end
    end
  end
  for _,method in ipairs({"name","isPhysical"}) do
    mod.hooks:wrap("editor.gen3.types."..method,function(proceed,id)
      local rec=workbench.types[Types.NAME[tonumber(id)]]
      if rec then
        if method=="name" then return rec.name end
        return rec.category=="physical"
      end
      return proceed(id)
    end)
  end
  mod.hooks:wrap("editor.gen3.types.typeCalc",function(proceed,...)
    if not next(workbench.matchups) then return proceed(...) end
    local original=Types.TABLE
    local chart,seen={},{}
    local function append(a,d,m) chart[#chart+1]=a;chart[#chart+1]=d;chart[#chart+1]=m end
    -- Keep the Foresight sentinel and immunity rows in their original order.
    local tail={};local after=false
    for i=1,#original,3 do
      local a,d,m=original[i],original[i+1],original[i+2]
      if a==-1 then after=true end
      if after then tail[#tail+1]={a,d,m}
      else
        local key=Types.NAME[a]..">"..Types.NAME[d]
        append(a,d,workbench.matchups[key] or m);seen[key]=true
      end
    end
    local tailKeys={}
    for _,row in ipairs(tail) do
      if row[1]~=-1 then tailKeys[Types.NAME[row[1]]..">"..Types.NAME[row[2]]]=true end
    end
    for key,m in pairs(workbench.matchups) do
      if not seen[key] and not tailKeys[key] then
        local a,d=key:match("^([^>]+)>([^>]+)$");append(Types.ID[a],Types.ID[d],m)
      end
    end
    for _,row in ipairs(tail) do
      local key=row[1]~=-1 and (Types.NAME[row[1]]..">"..Types.NAME[row[2]])
      append(row[1],row[2],(key and workbench.matchups[key]) or row[3])
    end
    Types.TABLE=chart
    local result={pcall(proceed,...)}
    Types.TABLE=original
    if not result[1] then error(result[2]) end
    return result[2],result[3],result[4]
  end)
  mod.hooks:wrap("editor.gen3.types.effectiveness",function(proceed,a,d1,d2)
    if not next(workbench.matchups) then return proceed(a,d1,d2) end
    local _,_,product=Types.typeCalc(a,d1,d2)
    return product
  end)
]=]
return M
