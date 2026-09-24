local M={}
function M.install(mod,configs)
  local Runtime=require("src.mods.Runtime")
  local P=require("src.core.game3.pokemon")
  local State=require("src.core.game3.battle.state")
  local Engine=require("src.core.game3.battle.engine")
  local Moves=require("src.core.game3.battle.moves")
  local Adapter=require("src.core.game3.battle.adapter")
  local families,items={},{}
  local function bridge(object,name,fn)
    local key="editor.gen3.formrules."..name
    if not object[key] then object[key]=true;local original=object[name];object[name]=function(...) return Runtime.call(key,original,...) end end
    mod.hooks:wrap(key,fn)
  end
  for _,f in ipairs(configs) do
    for _,row in ipairs(f.forms) do row.index=assert(mod.content.pokemon:get(row.species),"Missing rule form "..row.species).index;families[row.index]=f end
    for _,r in ipairs(f.rules or {}) do
      if r.move then r.moveIndex=assert(mod.content.moves:get(r.move),"Missing rule move "..r.move).index end
      if r.item then
        r.itemIndex=assert(mod.content.items:get(r.item),"Missing rule item "..r.item).index
        if r.trigger=="item_use" then items[r.itemIndex]=true;items[r.item]=r.itemIndex end
      end
    end
  end
  local function valid(mon) return mon and not mon.isEgg and not mon.egg end
  local function family(mon) return mon and families[tonumber(mon.species or mon.speciesId)] end
  local function moveNum(value)
    if type(value)=="table" then value=value.id or value.move or value.num or value.moveId or value.name or value[1] end
    return tonumber(value) or Moves.numForName(value)
  end
  local function knows(mon,num)
    for _,v in ipairs(mon.moves or {}) do if moveNum(v)==num then return true end end
    return false
  end
  local function fieldChange(mon,index)
    if mon.species==index then return false end
    local hp,max=mon.hp,mon.maxHp
    mon.species=index;mon.speciesId=index;mon.ability=P.abilityId(index,mon.personality or 0);mon.abilityId=mon.ability
    P.applyStats(mon)
    if hp and max then mon.hp=hp==0 and 0 or math.max(1,math.min(mon.maxHp,mon.maxHp-(max-hp))) end
    return true
  end
  local busy=false
  local function knownForm(mon)
    if busy or not valid(mon) or mon._editorFusion then return end
    local f=family(mon);if not f then return end
    local has,target=false,nil
    for _,r in ipairs(f.rules or {}) do if r.trigger=="knows_move" then
      has=true
      if not target and (mon.level or 1)>=(r.minLevel or 1) and knows(mon,r.moveIndex) then target=f.forms[r.target].index end
    end end
    if has then busy=true;fieldChange(mon,target or f.forms[1].index);busy=false end
  end
  bridge(P,"applyStats",function(proceed,mon,...)
    knownForm(mon);return proceed(mon,...)
  end)
  for _,event in ipairs({"pokemon.move_learned","pokemon.level_up"}) do mod.events:on(event,function(ev) knownForm(ev.mon) end) end
  bridge(require("src.core.game3.move_learn"),"forgetMove",function(proceed,mon,...)
    local result=proceed(mon,...);if result then knownForm(mon) end;return result
  end)
  local function syncAppearance(b,index)
    local t=P.types(index);b.species=index;b.type1=t[1];b.type2=t[2]~=t[1] and t[2] or nil
    b.ability=P.abilityId(index,b.mon.personality or 0)
    local stats=P.calcStats(index,b.mon.level or 5,b.mon.ivs or {},b.mon.evs or {},b.mon.personality or 0)
    -- Battle-only forms retain the individual's HP pool and saved species.
    -- Dedicated giant/HP-changing mechanics are deliberately not approximated.
    for _,k in ipairs({"attack","defense","speed","spAtk","spDef"}) do b.mon[k]=stats[k] end
    for alias,k in pairs({atk="attack",def="defense",spe="speed",spa="spAtk",spd="spDef"}) do b.mon[alias]=stats[k] end
    Runtime.call("editor.gen3.formmoves.battler",function() end,b)
  end
  local function matches(r,b,st,event,ctx,ad)
    if (b.mon.level or 1)<(r.minLevel or 1) then return false end
    if r.ability and r.ability~="" and ad:abilityOf(b)~=r.ability then return false end
    local trigger=r.trigger
    if trigger=="hp_below" or trigger=="hp_above" then
      if event~="battle_start" and event~="turn_end" then return false end
      local below=(b.mon.hp or 0)*100<=(b.mon.maxHp or 1)*(r.percent or 50)
      return (trigger=="hp_below" and below) or (trigger=="hp_above" and not below)
    elseif trigger=="weather" then
      return (event=="battle_start" or event=="refresh" or event=="turn_end") and (require("src.core.game3.battle.rules").weather.effective(st,ad) or "NONE")== (r.weather or "NONE")
    elseif trigger=="held_item" then
      return (event=="battle_start" or event=="refresh" or event=="turn_end") and b.item==r.itemIndex
    elseif trigger=="damaging_move" then return event=="move_used" and (tonumber(ctx.power) or 0)>0
    elseif trigger~=event then return false
    elseif trigger=="move_used" or trigger=="move_hit" then return ctx.moveNum==r.moveIndex end
    return true
  end
  local function evaluate(st,b,event,ctx,ad)
    if not st or not b or b.transformed or b._editorAdvanced or not valid(b.mon) or (b.mon.hp or 0)<=0 then return end
    local f=family(b.mon);if not f then return end
    ad=ad or Adapter.new(st,function() end);ctx=ctx or {}
    for _,r in ipairs(f.rules or {}) do
      local source=not r.from or r.from==0 or f.forms[r.from].index==b.species
      if source and matches(r,b,st,event,ctx,ad) then
        local index=f.forms[r.target].index
        if index~=b.species then
          st._editorRuleForms=st._editorRuleForms or {}
          st._editorRuleForms[b.mon]={index=index,duration=r.duration or "switch"}
          b._editorRuleOriginalAbility=b._editorRuleOriginalAbility or b.ability
          syncAppearance(b,index)
        end
        return
      end
    end
  end
  local function all(st,event,ad)
    for _,b in ipairs(State.present(st)) do evaluate(st,b,event,nil,ad) end
  end
  local function restore(b)
    if not b or not family(b.mon) then return end
    if b._editorRuleOriginalAbility then
      syncAppearance(b,b.mon.species);b.ability=b._editorRuleOriginalAbility;b._editorRuleOriginalAbility=nil
    end
  end
  local function cleanup(st)
    if not st then return end
    for _,b in ipairs(State.present(st)) do restore(b) end
    for mon in pairs(st._editorRuleForms or {}) do P.applyStats(mon) end
    st._editorRuleForms=nil
  end
  bridge(State,"makeBattler",function(proceed,mon,side,opts)
    knownForm(mon)
    local b=proceed(mon,side,opts)
    local saved=opts and opts.st and opts.st._editorRuleForms and opts.st._editorRuleForms[mon]
    if saved then b._editorRuleOriginalAbility=b.ability;syncAppearance(b,saved.index) end
    return b
  end)
  bridge(Engine,"battleStartEffects",function(proceed,st,ad,...)
    local result=proceed(st,ad,...);all(st,"battle_start",ad);return result
  end)
  bridge(Engine,"switchInEffects",function(proceed,st,ad,b,...)
    local result=proceed(st,ad,b,...);evaluate(st,b,"battle_start",nil,ad);return result
  end)
  bridge(Engine,"switchOutEffects",function(proceed,st,ad,b,...)
    local result=proceed(st,ad,b,...)
    local saved=st and st._editorRuleForms and b and st._editorRuleForms[b.mon]
    if saved and saved.duration=="switch" then restore(b);st._editorRuleForms[b.mon]=nil end
    evaluate(st,b,"switch_out",nil,ad)
    return result
  end)
  bridge(Engine,"afterAction",function(proceed,st,ad,...)
    local result=proceed(st,ad,...);all(st,"refresh",ad);return result
  end)
  -- Capture hit events during a move and apply its changes only after resolution,
  -- once per user/target; spread and multihit attacks must not toggle repeatedly.
  local pending={}
  mod.events:on("battle.move_used",function(ev)
    local move=Moves.get(ev.moveNum)
    evaluate(ev.battle,ev.user,"move_used",{moveNum=ev.moveNum,power=move and move.power})
  end)
  mod.events:on("battle.damage_dealt",function(ev)
    if ev.substitute or (ev.damage or 0)<=0 then return end
    local queue=pending[#pending]
    if queue then queue[#queue+1]=ev end
  end)
  local function applyHits(queue,st,ad)
    local seen={}
    for _,ev in ipairs(queue) do
      for _,entry in ipairs({{ev.user,"move_hit"},{ev.target,"damage_taken"},{ev.user,"knockout"}}) do
        local b,event=entry[1],entry[2]
        seen[b]=seen[b] or {}
        if not seen[b][event] and (event~="knockout" or (ev.target.mon.hp or 0)<=0) then
          seen[b][event]=true;evaluate(st,b,event,{moveNum=ev.moveNum},ad)
        end
      end
    end
  end
  bridge(Engine,"resolveMove",function(proceed,user,target,move,slot,ad,st,out,opts)
    local queue={};pending[#pending+1]=queue
    local ok,result=pcall(proceed,user,target,move,slot,ad,st,out,opts)
    pending[#pending]=nil
    if not ok then error(result,0) end
    if st and st.pendingChoice then st.pendingChoice._editorFormHits=queue else applyHits(queue,st,ad) end
    return result
  end)
  bridge(Engine,"resumeChoice",function(proceed,st,ad,...)
    local queue=st and st.pendingChoice and st.pendingChoice._editorFormHits or {}
    pending[#pending+1]=queue
    local ok,result=pcall(proceed,st,ad,...);pending[#pending]=nil
    if not ok then error(result,0) end
    if st and st.pendingChoice then st.pendingChoice._editorFormHits=queue else applyHits(queue,st,ad) end
    return result
  end)
  mod.events:on("battle.turn_ended",function(ev) all(ev.battle,"turn_end") end)
  mod.events:on("battle.ended",function(ev) cleanup(ev.battle) end)
  local Battle=require("src.core.game3.battle")
  bridge(Battle,"start",function(proceed,opts)
    local wrapped={};for k,v in pairs(opts or {}) do wrapped[k]=v end
    local done=wrapped.onDone
    wrapped.onDone=function(...) cleanup(Battle.getState());if done then return done(...) end end
    return proceed(wrapped)
  end)
  local Use=require("src.core.game3.item_use")
  local Bag=require("src.core.game3.bag")
  local function itemId(id) return type(items[id])=="number" and items[id] or (items[tonumber(id)] and tonumber(id)) end
  bridge(Use,"needsPartyTarget",function(proceed,id,...) return itemId(id) and true or proceed(id,...) end)
  bridge(Use,"useField",function(proceed,session,bag,id,slot,...)
    local numeric=itemId(id);if not numeric then return proceed(session,bag,id,slot,...) end
    local mon=session and session.party and session.party[slot]
    local f=family(mon)
    local hasRule=false
    for _,r in ipairs(f and f.rules or {}) do if r.trigger=="item_use" and r.itemIndex==numeric then hasRule=true end end
    if not hasRule then return proceed(session,bag,id,slot,...) end
    if valid(mon) and f and Bag.has(bag,numeric,1) then
      for _,r in ipairs(f.rules or {}) do
        if r.trigger=="item_use" and r.itemIndex==numeric and (mon.level or 1)>=(r.minLevel or 1) and
          (not r.from or r.from==0 or f.forms[r.from].index==mon.species) and f.forms[r.target].index~=mon.species then
          fieldChange(mon,f.forms[r.target].index)
          if r.consume then Bag.remove(bag,numeric,1) end
          return true,"form","The Pokemon changed form!"
        end
      end
    end
    return false,"form","It would have no effect."
  end)
end
return M
