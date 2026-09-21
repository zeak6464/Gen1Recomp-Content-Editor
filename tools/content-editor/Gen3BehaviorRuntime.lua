-- A small, data-only behavior language shared by custom abilities and status moves.
return function(records,mod,assignments)
  local B={}
  function B.apply(rec,ad,user,target,moveCtx,afterDamage)
    if not user or ad:hp(user)<=0 then return false end
    local victim=rec.target=="opponent" and target or user
    if not victim or ad:hp(victim)<=0 then return false end
    if not afterDamage and moveCtx and moveCtx.accuracyCheck and not moveCtx:accuracyCheck("normal",true) then return true end
    if victim~=user and (victim.substituteHP or 0)>0 then ad:sayFail();return true end
    if ad:roll(1,100)>(rec.chance or 100) then return false end
    if not afterDamage and moveCtx and moveCtx.attackAnimation then moveCtx:attackAnimation() end
    local changed=false
    for _,action in ipairs(rec.actions or {}) do
      if action.kind=="heal" and ad:hp(victim)<ad:maxHp(victim) then
        ad:heal(victim,math.max(1,math.floor(ad:maxHp(victim)*action.amount/100)));changed=true
      elseif action.kind=="cure" and ad:status(victim) then
        ad:clearStatus(victim);changed=true
      elseif action.kind=="stat" then
        local before=(victim.stages or {})[action.stat] or 0
        require("src.core.game3.battle.effects.secondary").changeStat(ad,victim,action.stat,action.amount,{user=victim==user,allowPtr=true})
        changed=changed or ((victim.stages or {})[action.stat] or 0)~=before
      elseif action.kind=="weather" then
        ad:setWeather(action.weather,action.turns);changed=true
      end
    end
    if changed then ad:say(rec.name.." took effect!") elseif moveCtx then ad:sayFail() end
    return changed or moveCtx~=nil
  end
  function B.install()
    local Runtime=require("src.mods.Runtime")
    local Abilities=require("src.core.game3.battle.abilities")
    local P=require("src.core.game3.pokemon")
    local Effects=require("src.core.game3.battle.effects")
    local function bridge(object,method,key)
      local mark="_editorCustom_"..method
      if not object[mark] then object[mark]=true;local base=object[method]
        object[method]=function(...) return Runtime.call(key,base,...) end end
    end
    bridge(P,"abilities","editor.gen3.custom.abilities")
    mod.hooks:wrap("editor.gen3.custom.abilities",function(proceed,species)
      local a=(assignments or {})[tonumber(species)]
      if a then
        local function number(value)
          if tonumber(value) then return tonumber(value) end
          for id,name in pairs(require("src.core.game3.battle.adapter").ABILITY_BY_ID) do
            if name==tostring(value):upper():gsub("%s+","_") then return id end
          end
          return 0
        end
        return {number(a[1]),number(a[2])}
      end
      return proceed(species)
    end)
    bridge(P,"abilityName","editor.gen3.custom.abilityName")
    mod.hooks:wrap("editor.gen3.custom.abilityName",function(proceed,id)
      for _,rec in pairs(records) do if rec.kind=="ability" and rec.index==tonumber(id) then return rec.name end end
      return proceed(id)
    end)
    for _,trigger in ipairs({"switchIn","endTurn"}) do
      local event=trigger
      bridge(Abilities,event,"editor.gen3.custom."..event)
      mod.hooks:wrap("editor.gen3.custom."..event,function(proceed,ad,b)
        local name=ad:abilityOf(b)
        for _,rec in pairs(records) do
          if rec.kind=="ability" and name==rec.name:upper():gsub("%s+","_") then
            if rec.trigger==event then return B.apply(rec,ad,b,b) end
            return false
          end
        end
        return proceed(ad,b)
      end)
    end
    local Moves=require("src.core.game3.battle.moves")
    bridge(Moves,"get","editor.gen3.custom.moveData")
    mod.hooks:wrap("editor.gen3.custom.moveData",function(proceed,id)
      local base=proceed(id)
      local number=tonumber(id) or (base and base.numId) or Moves.numForName(id)
      for _,rec in pairs(records) do
        if rec.kind=="move" and rec.moveIndex and rec.moveIndex==number then
          local result={};for k,v in pairs(base or {}) do result[k]=v end
          result.power=rec.mode=="damage" and rec.power or 0
          result.effect=0;result.effectId=nil;result.afterHit=nil;result.hits=nil;result.secondaryChance=0
          result.target=rec.mode=="damage" and 0 or (rec.target=="self" and 16 or 0)
          result.category=result.power==0 and "status" or (require("src.core.game3.battle.types").isPhysical(result.type) and "physical" or "special")
          return result
        end
      end
      return base
    end)
    local Hit=require("src.core.game3.battle.effects.hit")
    bridge(Hit,"run","editor.gen3.custom.hit")
    mod.hooks:wrap("editor.gen3.custom.hit",function(proceed,ctx)
      local result=proceed(ctx)
      if ctx.targetDamaged and not ctx.noEffect and not ctx.failed and not ctx.hitSubstitute and (ctx.hpDealt or 0)>0 then
        for _,rec in pairs(records) do
          if rec.kind=="move" and rec.mode=="damage" and rec.moveIndex==tonumber(ctx.moveId) then
            B.apply(rec,ctx.adapter,ctx.user,ctx.target,ctx,true)
            break
          end
        end
      end
      return result
    end)
    bridge(Effects,"runForMove","editor.gen3.custom.move")
    mod.hooks:wrap("editor.gen3.custom.move",function(proceed,ad,user,target,id,moveCtx)
      for _,rec in pairs(records) do
        if rec.kind=="move" and rec.mode~="damage" and rec.moveIndex==tonumber(id) then B.apply(rec,ad,user,target,moveCtx);return true end
      end
      return proceed(ad,user,target,id,moveCtx)
    end)
  end
  return B
end
