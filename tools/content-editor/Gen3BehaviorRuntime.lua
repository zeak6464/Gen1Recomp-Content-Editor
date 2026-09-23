-- A small, data-only behavior language shared by custom abilities and status moves.
return function(records,mod,assignments)
  local B={}
  function B.matches(rec,ad,user,target,ctx)
    local c=rec.condition or "always"
    local hp,max=ad:hp(user),ad:maxHp(user)
    if c=="always" then return true end
    if c=="lowHp" then return hp<=max/2 end
    if c=="fullHp" then return hp>=max end
    if c=="hpBelow" then return hp*100<=max*(rec.hpPercent or 50) end
    if c=="hpAbove" then return hp*100>max*(rec.hpPercent or 50) end
    if c=="foeLowHp" then return target and ad:hp(target)>0 and ad:hp(target)<=ad:maxHp(target)/2 end
    if c=="foeStatus" then return target and ad:status(target)~=nil end
    if c=="status" then return ad:status(user)~=nil end
    if c=="healthy" then return not ad:status(user) end
    local status=({burned="BRN",paralyzed="PAR",asleep="SLP",frozen="FRZ"})[c]
    if status then return ad:status(user)==status end
    if c=="poisoned" then local s=ad:status(user);return s=="PSN" or s=="TOX" end
    if c=="confused" then return (user.confusionTurns or 0)>0 end
    if c=="boosted" or c=="lowered" then
      for _,v in pairs(user.stages or {}) do if c=="boosted" and v>0 or c=="lowered" and v<0 then return true end end
      return false
    end
    local weather=ad._st and ad._st.weather
    if c=="noWeather" then return weather==nil or weather=="NONE" or weather==0 end
    local needed=({sun="SUN",rain="RAIN",sand="SANDSTORM",hail="HAIL"})[c]
    if needed then return weather==needed end
    if c=="contact" then return ctx and (tonumber(ctx.move and ctx.move.flags) or 0)%2==1 end
    if c=="physical" or c=="special" then
      local move=ctx and ctx.move
      if not move then return false end
      local category=move.category
      if not category then category=require("src.core.game3.battle.types").isPhysical(move.type) and "physical" or "special" end
      return category==c
    end
    return false
  end
  function B.apply(rec,ad,user,target,moveCtx,afterDamage)
    if not user or ad:hp(user)<=0 then return false end
    if not B.matches(rec,ad,user,target,moveCtx) then return false end
    local victim=rec.target=="opponent" and target or user
    if not afterDamage and moveCtx and moveCtx.accuracyCheck and not moveCtx:accuracyCheck("normal",true) then return true end
    if ad:roll(1,100)>(rec.chance or 100) then return false end
    if not afterDamage and moveCtx and moveCtx.attackAnimation then moveCtx:attackAnimation() end
    local changed=false
    for _,action in ipairs(rec.actions or {}) do
      local recipient=action.target=="self" and user or action.target=="opponent" and target or victim
      local victim=recipient
      if victim and ad:hp(victim)>0 and (victim==user or (victim.substituteHP or 0)<=0) then
      if action.kind=="heal" and ad:hp(victim)<ad:maxHp(victim) then
        ad:heal(victim,math.max(1,math.floor(ad:maxHp(victim)*action.amount/100)));changed=true
      elseif action.kind=="damage" then
        local lost=ad:applyHpLoss(victim,math.max(1,math.floor(ad:maxHp(victim)*action.amount/100)))
        changed=lost>0 or changed
      elseif action.kind=="resetStats" then
        for stat,value in pairs(victim.stages or {}) do if value~=0 then victim.stages[stat]=0;changed=true end end
      elseif action.kind=="clearNegative" or action.kind=="clearPositive" or action.kind=="invertStats" then
        for stat,value in pairs(victim.stages or {}) do
          if action.kind=="clearNegative" and value<0 or action.kind=="clearPositive" and value>0 or action.kind=="invertStats" and value~=0 then
            victim.stages[stat]=action.kind=="invertStats" and -value or 0;changed=true
          end
        end
      elseif action.kind=="setStat" then
        victim.stages=victim.stages or {};changed=(victim.stages[action.stat] or 0)~=action.amount or changed;victim.stages[action.stat]=action.amount
      elseif action.kind=="copyStats" or action.kind=="swapStats" then
        local other=victim==user and target or user
        if other and other~=victim then
          victim.stages=victim.stages or {};other.stages=other.stages or {}
          for _,stat in ipairs({"attack","defense","speed","spAtk","spDef","accuracy","evasion"}) do
            local a,b=victim.stages[stat] or 0,other.stages[stat] or 0
            victim.stages[stat]=b;if action.kind=="swapStats" then other.stages[stat]=a end;changed=a~=b or changed
          end
        end
      elseif action.kind=="drain" or action.kind=="recoil" then
        local damage=moveCtx and moveCtx.hpDealt or 0
        if damage>0 then
          local amount=math.max(1,math.floor(damage*action.amount/100))
          local before=ad:hp(victim)
          if action.kind=="drain" then ad:heal(victim,amount) else ad:applyHpLoss(victim,amount) end
          changed=ad:hp(victim)~=before or changed
        end
      elseif action.kind=="clearConfusion" then
        changed=(victim.confusionTurns or 0)>0 or changed;victim.confusionTurns=0
      elseif action.kind=="clearFlinch" then changed=victim.flinched or changed;victim.flinched=nil
      elseif action.kind=="clearTrap" then
        for _,key in ipairs({"expTrapTurns","expTrapMove","expTrapSource","wrapped","expTrapped","escapePrevention","expTrappedBy","trapped"}) do
          changed=victim[key]~=nil or changed;victim[key]=nil
        end
      elseif action.kind=="clearWeather" then
        if ad._st and ad._st.weather then ad:setWeather(nil,0);changed=true end
      elseif action.kind=="status" or action.kind=="confusion" or action.kind=="flinch" then
        local ctx={adapter=ad,user=user,target=victim}
        local effect=action.kind=="status" and action.status or action.kind:upper()
        local applied=require("src.core.game3.battle.effects.secondary").set(ctx,effect,false,true,victim==user)
        changed=applied or changed
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
    end
    if changed then ad:say(rec.name.." took effect!") elseif moveCtx then ad:sayFail() end
    return changed or moveCtx~=nil
  end
  function B.install()
    local Runtime=require("src.mods.Runtime")
    local Abilities=require("src.core.game3.battle.abilities")
    local P=require("src.core.game3.pokemon")
    local Effects=require("src.core.game3.battle.effects")
    local function ability(event,ad,holder,other,ctx)
      if not holder or ad:hp(holder)<=0 then return false end
      local name=ad:abilityOf(holder)
      for _,rec in pairs(records) do
        if rec.kind=="ability" and rec.trigger==event and name==rec.name:upper():gsub("%s+","_") then
          return B.apply(rec,ad,holder,other,ctx,true)
        end
      end
      return false
    end
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
    for _,trigger in ipairs({"switchIn","endTurn","switchOut"}) do
      local event=trigger
      bridge(Abilities,event,"editor.gen3.custom."..event)
      mod.hooks:wrap("editor.gen3.custom."..event,function(proceed,ad,b)
        local name=ad:abilityOf(b)
        for _,rec in pairs(records) do
          if rec.kind=="ability" and name==rec.name:upper():gsub("%s+","_") then
            if rec.trigger==event then return B.apply(rec,ad,b,ad.foeOf and ad:foeOf(b) or nil) end
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
        local userHp,targetHp=ctx.adapter:hp(ctx.user),ctx.adapter:hp(ctx.target)
        local knockedOut=ctx.target and ctx.adapter:hp(ctx.target)<=0
        ability("receiveHit",ctx.adapter,ctx.target,ctx.user,ctx)
        if (tonumber(ctx.move and ctx.move.flags) or 0)%2==1 then ability("receiveContact",ctx.adapter,ctx.target,ctx.user,ctx) end
        ability("dealHit",ctx.adapter,ctx.user,ctx.target,ctx)
        if knockedOut then ability("knockout",ctx.adapter,ctx.user,ctx.target,ctx) end
        for _,rec in pairs(records) do
          if rec.kind=="move" and rec.mode=="damage" and rec.moveIndex==tonumber(ctx.moveId) then
            B.apply(rec,ctx.adapter,ctx.user,ctx.target,ctx,true)
            break
          end
        end
        if userHp>0 and ctx.adapter:hp(ctx.user)<=0 and ctx.tryFaintUser then ctx:tryFaintUser() end
        if targetHp>0 and ctx.adapter:hp(ctx.target)<=0 and ctx.tryFaintTarget then ctx:tryFaintTarget() end
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
