local M={}
local function copy(v) return require("src.mods.Merge").deepCopy(v) end
function M.available(row,session)
  if row.enabled==false then return false end
  local F=require("src.core.game3.scripting.flags")
  return row.unlock=="always" or F.getFlag(session,nil,row.unlock=="postgame" and 0x844 or row.flag)
end
function M.species(row,session)
  if row.selection~="starter" then return row.species end
  local starter=require("src.core.game3.scripting.flags").getVar(session,nil,0x4031)
  return row.starters[starter==0 and "bulbasaur" or starter==2 and "charmander" or "squirtle"]
end
function M.move(row,state,rng)
  local choices={};for _,id in ipairs(row.maps) do if id~=state.map then choices[#choices+1]=id end end
  if #choices==0 then choices=row.maps end
  state.map=choices[(rng()%#choices)+1]
end
function M.install(mod,rows)
  local Runtime=require("src.mods.Runtime")
  local Field=require("src.core.game3.field")
  local E=require("src.core.game3.encounters")
  local Bridge=require("src.core.game3.battle_bridge")
  local Rng=require("src.core.game3.rng")
  local byId={};for _,row in ipairs(rows) do byId[row.id]=row end
  local function bridge(object,name,key)
    if object[key] then return end;object[key]=true;local original=object[name]
    object[name]=function(...) return Runtime.call(key,original,...) end
  end
  local function states(session)
    session.modData=session.modData or {};session.modData[mod.id]=session.modData[mod.id] or {}
    local data=session.modData[mod.id];data.roamers=data.roamers or {};return data.roamers
  end
  local function stateFor(session,row)
    local data=states(session);local state=data[row.id]
    if not state then state={};data[row.id]=state;M.move(row,state,Rng.Random) end
    local valid=false;for _,id in ipairs(row.maps) do if id==state.map then valid=true end end
    if not valid then M.move(row,state,Rng.Random) end
    return state
  end
  local lastSession,lastMap
  mod.events:on("map.entered",function(e)
    local session=Field.getSession();if not session then return end
    if lastSession==session and lastMap==e.mapId then return end
    lastSession,lastMap=session,e.mapId
    for _,row in ipairs(rows) do if M.available(row,session) then
      local state=stateFor(session,row);if not state.finished then M.move(row,state,Rng.Random) end
    end end
  end)
  bridge(E,"onStep","editor.gen3.roamers.step")
  mod.hooks:wrap("editor.gen3.roamers.step",function(proceed,mapId,terrain,opts)
    local encounter=proceed(mapId,terrain,opts)
    local session=Field.getSession()
    if not session or not encounter or terrain~="land" then return encounter end
    local candidates={}
    for _,row in ipairs(rows) do if M.available(row,session) then
      local state=stateFor(session,row)
      if not state.finished and state.map==mapId then candidates[#candidates+1]={row=row,state=state} end
    end end
    if #candidates==0 then return encounter end
    local candidate=candidates[Rng.Random()%#candidates+1];local row=candidate.row
    if Rng.Random()%100>=row.chance then return encounter end
    local F=require("src.core.game3.scripting.flags")
    if F.getVar(session,nil,0x4020)>0 then
      for _,mon in ipairs(session.party or {}) do if not mon.isEgg and (mon.hp or 0)>0 then
        if (mon.level or 1)>row.level then return encounter end;break
      end end
    end
    local species=M.species(row,session);local rec=mod.content.pokemon:get(species)
    if not rec then return encounter end
    return {species=rec.index,level=row.level,_editorRoamer={owner=mod.id,id=row.id}}
  end)
  local pending
  bridge(Bridge,"startWild","editor.gen3.roamers.start")
  mod.hooks:wrap("editor.gen3.roamers.start",function(proceed,host,game,encounter,opts)
    local tag=encounter and encounter._editorRoamer
    if not tag or tag.owner~=mod.id then return proceed(host,game,encounter,opts) end
    local session=Field.getSession();local row=byId[tag.id]
    if not session or not row then return proceed(host,game,encounter,opts) end
    local state=stateFor(session,row)
    if not state.mon then
      local temp={party={},name=session.name,trainerId=session.trainerId}
      assert(require("src.core.game3.party").giveMon(temp,encounter.species,row.level))
      state.mon=copy(temp.party[1])
    end
    pending={session=session,row=row,state=state}
    local ok,err=proceed(host,game,copy(state.mon),opts)
    if not ok then pending=nil end
    return ok,err
  end)
  local active=setmetatable({},{__mode="k"})
  mod.events:on("battle.started",function(e)
    if not pending or e.kind~="wild" or not e.battle then return end
    active[e.battle]=pending;pending=nil
  end)
  local Engine=require("src.core.game3.battle.engine")
  bridge(Engine,"collectResidualEvents","editor.gen3.roamers.flee")
  mod.hooks:wrap("editor.gen3.roamers.flee",function(proceed,battle,adapter)
    local events=proceed(battle,adapter);local a=active[battle]
    if a and a.row.flee=="attempt" and not battle.over and (battle.enemy.mon.hp or 0)>0
        and (battle.player.mon.hp or 0)>0 and Engine.canRun(battle,adapter,battle.enemy) then
      battle.over=true;battle.result="run";battle.endReason="roamer_fled"
      events[#events+1]={msgs={adapter:displayName(battle.enemy).." fled!"}}
    end
    return events
  end)
  mod.events:on("pokemon.caught",function(e)
    local a=e.battle and active[e.battle];if a then a.state.finished="caught" end
  end)
  mod.events:on("battle.ended",function(e)
    local a=e.battle and active[e.battle];if not a then return end
    local enemy=e.battle.enemy and e.battle.enemy.mon
    if enemy then
      -- Keep the original identity, moves and IVs. Only HP/status carry over.
      a.state.mon.hp=enemy.hp;a.state.mon.status=enemy.status
      if (enemy.hp or 0)<=0 then
        if a.row.defeat=="stop" then a.state.finished="defeated" else a.state.mon.hp=a.state.mon.maxHp;a.state.mon.status=nil end
      end
    end
    if e.result=="caught" or e.result=="catch" then a.state.finished="caught" end
    if not a.state.finished then M.move(a.row,a.state,Rng.Random) end
    active[e.battle]=nil
  end)
end
return M
