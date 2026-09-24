local M={}
local function copy(t) local n={};for k,v in pairs(t or {}) do n[k]=v end;return n end
local manual={mega=true,ultra=true,dynamax=true,gigantamax=true,tera=true}
local function giant(kind) return kind=="dynamax" or kind=="gigantamax" end
function M.install(mod,configs,typeIds)
  local Runtime=require("src.mods.Runtime")
  local P=require("src.core.game3.pokemon")
  local State=require("src.core.game3.battle.state")
  local Engine=require("src.core.game3.battle.engine")
  local Moves=require("src.core.game3.battle.moves")
  local Types=require("src.core.game3.battle.types")
  local Adapter=require("src.core.game3.battle.adapter")
  local Hit=require("src.core.game3.battle.effects.hit")
  local Rules=require("src.core.game3.battle.rules")
  local Bag=require("src.core.game3.bag")
  local families,contexts={},{}
  local function bridge(object,name,fn)
    local key="editor.gen3.advanced."..name
    if not object[key] then object[key]=true;local original=object[name];object[name]=function(...) return Runtime.call(key,original,...) end end
    mod.hooks:wrap(key,fn)
  end
  for _,f in ipairs(configs) do
    for _,row in ipairs(f.forms) do row.index=assert(mod.content.pokemon:get(row.species)).index;families[row.index]=f end
    for _,row in ipairs(f.forms) do
      local c=row.mechanic
      if c and c.kind and c.kind~="none" then
        c.index=row.index;c.source=f.forms[c.from or 1].index;c.name=row.name
        for _,key in ipairs({"item","keyItem"}) do if c[key] then c[key.."Index"]=assert(mod.content.items:get(c[key]),"Missing mechanic item "..c[key]).index end end
        for _,key in ipairs({"move","maxMove","swapFrom","swapTo","teraBlast"}) do if c[key] then c[key.."Index"]=assert(mod.content.moves:get(c[key]),"Missing mechanic move "..c[key]).index end end
        if c.teraType and c.teraType~="STELLAR" then c.teraIndex=assert(typeIds[c.teraType],"Unknown Tera type") end
        if c.maxType then c.maxTypeIndex=assert(typeIds[c.maxType],"Unknown G-Max type") end
      end
    end
  end
  local function state(st)
    st._editorAdvanced=st._editorAdvanced or {mons={},used={},requests={}}
    return st._editorAdvanced
  end
  local function candidates(b)
    local f=b and b.mon and families[tonumber(b.mon.species)]
    local result={}
    for _,row in ipairs(f and f.forms or {}) do if row.mechanic and row.mechanic.kind~="none" then result[#result+1]=row.mechanic end end
    return result
  end
  local function allowed(st,b,c,ad)
    if not b or not b.mon or b.mon.isEgg or b.mon.egg or b.transformed or b.mon.hp<=0 or st.over or st.link or st.safari then return false end
    if b.species~=c.source or b._editorAdvanced then return false end
    if c.itemIndex and b.item~=c.itemIndex then return false end
    if c.ability and c.ability~="" and ad:abilityOf(b)~=c.ability then return false end
    if c.keyItemIndex and b.side=="player" and not Bag.has(st.session and (st.session.bag or st.session.inventory),c.keyItemIndex,1) then return false end
    if c.kind=="tera" and b.side=="player" and st.session and st.session.meta and st.session.meta.editorTeraSpent then return false end
    local bucket=giant(c.kind) and "dynamax" or c.kind
    if manual[c.kind] and ((state(st).used[b.side] or {})[bucket]) then return false end
    return true
  end
  local function stats(b,index)
    local v=P.calcStats(index,b.mon.level or 5,b.mon.ivs or {},b.mon.evs or {},b.mon.personality or 0)
    for _,k in ipairs({"attack","defense","speed","spAtk","spDef"}) do b.mon[k]=v[k] end
    for alias,k in pairs({atk="attack",def="defense",spe="speed",spa="spAtk",spd="spDef"}) do b.mon[alias]=v[k] end
    return v
  end
  local function appearance(b,index,ability)
    b.species=index;local t=P.types(index);b.type1=t[1];b.type2=t[2]~=t[1] and t[2] or nil
    b.ability=ability or P.abilityId(index,b.mon.personality or 0);stats(b,index)
  end
  local function swapMoves(b,c,record)
    if not c.swapFromIndex then return end
    record.swaps=record.swaps or {}
    for i,id in ipairs(b.mon.moves or {}) do if tonumber(id)==c.swapFromIndex then
      record.swaps[i]={from=id,to=c.swapToIndex};b.mon.moves[i]=c.swapToIndex
    end end
  end
  local function restoreMoves(mon,record)
    for slot,s in pairs(record.swaps or {}) do if mon.moves and mon.moves[slot]==s.to then mon.moves[slot]=s.from end end
  end
  local function apply(b,record)
    local c=record.config
    appearance(b,c.index,c.kind=="tera" and record.ability or nil)
    b._editorAdvanced=record
    if c.kind=="tera" then
      if c.teraType=="STELLAR" then b.type1=record.type1;b.type2=record.type2 else b.type1=c.teraIndex;b.type2=nil end
    end
    swapMoves(b,c,record)
    Runtime.call("editor.gen3.formmoves.battler",function() end,b)
  end
  local function activate(st,b,c,ad,automatic)
    ad=ad or Adapter.new(st,function() end)
    if not allowed(st,b,c,ad) then return false,"This transformation is not available." end
    local s=state(st);local record={config=c,original=b.species,ability=b.ability,type1=b.type1,type2=b.type2,maxHp=b.mon.maxHp,turn=st.turn or 0}
    if giant(c.kind) then
      local level=math.max(0,math.min(10,tonumber(b.mon.dynamaxLevel) or 10))
      record.factor=1.5+level*.05;record.turns=3
      if b.mon.maxHp==1 then record.factor=1 end
      b.mon.maxHp=math.floor(record.maxHp*record.factor);b.mon.hp=math.ceil(b.mon.hp*record.factor)
      b.mon.hp=math.min(b.mon.maxHp,b.mon.hp)
    elseif c.kind=="power_construct" or c.kind=="boss" then
      local newHp=P.calcStats(c.index,b.mon.level,b.mon.ivs or {},b.mon.evs or {},b.mon.personality or 0).maxHp
      b.mon.hp=math.max(1,b.mon.hp+newHp-b.mon.maxHp);b.mon.maxHp=newHp;record.hpChanged=true
    end
    s.mons[b.mon]=record;apply(b,record)
    record.changedMax=b.mon.maxHp
    if c.kind=="ice_face" then record.lastWeather=Rules.weather.effective(st,ad) end
    if manual[c.kind] then
      s.used[b.side]=s.used[b.side] or {};s.used[b.side][giant(c.kind) and "dynamax" or c.kind]=true
      if c.kind=="tera" and b.side=="player" and st.session then st.session.meta=st.session.meta or {};st.session.meta.editorTeraSpent=true end
    end
    ad:say((c.name or "Pokemon").." activated!")
    ad:playAnim("general","CASTFORM_CHANGE",b,b,0)
    if c.kind=="mega" or c.kind=="primal" or c.kind=="ultra" then require("src.core.game3.battle.abilities").switchIn(ad,b) end
    return true
  end
  local function revert(st,b,record)
    record=record or b._editorAdvanced;if not record then return end
    local hp,max=b.mon.hp,b.mon.maxHp
    if record.factor then b.mon.hp=hp==0 and 0 or math.max(1,math.ceil(hp/record.factor));b.mon.maxHp=record.maxHp
    elseif record.hpChanged then b.mon.hp=hp==0 and 0 or math.max(1,hp-(max-record.maxHp));b.mon.maxHp=record.maxHp end
    b.mon.hp=math.min(b.mon.maxHp,b.mon.hp)
    restoreMoves(b.mon,record);appearance(b,record.original,record.ability);b._editorAdvanced=nil
    Runtime.call("editor.gen3.formmoves.battler",function() end,b)
    state(st).mons[b.mon]=nil
  end
  local function cleanup(st)
    if not st or not st._editorAdvanced then return end
    for _,b in ipairs(State.present(st)) do revert(st,b) end
    for mon,record in pairs(st._editorAdvanced.mons) do
      local b={mon=mon};revert(st,b,record)
    end
    st._editorAdvanced=nil
  end
  mod.hooks:wrap("editor.gen3.advanced.activate",function(_,st,b,kind)
    for _,c in ipairs(candidates(b)) do if c.kind==kind then return activate(st,b,c) end end
    return false,"No matching transformation."
  end)
  local function entry(st,b,ad)
    if not b or not b.mon then return end
    local record=state(st).mons[b.mon]
    if record then apply(b,record) end
    if record and record.config.kind=="ice_face" and Rules.weather.effective(st,ad)=="HAIL" then revert(st,b) end
    for _,c in ipairs(candidates(b)) do if c.kind=="primal" then activate(st,b,c,ad,true) end end
  end
  bridge(Engine,"battleStartEffects",function(proceed,st,ad,...)
    for _,b in ipairs(State.present(st)) do entry(st,b,ad) end
    return proceed(st,ad,...)
  end)
  bridge(State,"makeBattler",function(proceed,mon,side,opts)
    local hp,max=mon and mon.hp,mon and mon.maxHp
    local b=proceed(mon,side,opts);local record=opts and opts.st and state(opts.st).mons[mon]
    if record then
      if record.hpChanged or record.factor then b.mon.maxHp=max;b.mon.hp=hp end
      apply(b,record)
    end;return b
  end)
  bridge(Engine,"switchInEffects",function(proceed,st,ad,b,...)
    entry(st,b,ad);return proceed(st,ad,b,...)
  end)
  bridge(Engine,"switchOutEffects",function(proceed,st,ad,b,...)
    local result=proceed(st,ad,b,...)
    local rec=b and b._editorAdvanced
    if rec and (giant(rec.config.kind) or rec.config.kind=="gulp") then revert(st,b) end
    return result
  end)
  local function commitRequests(st,ad,chosen)
    local s=state(st)
    for id=0,3 do
      local b=State.battler(st,id);local act=chosen[id];local c=s.requests[id]
      if act and act.kind=="move" and b then
        if not c and b.side=="enemy" then
          for _,candidate in ipairs(candidates(b)) do if manual[candidate.kind] and allowed(st,b,candidate,ad) then c=candidate;break end end
        end
        if c then activate(st,b,c,ad) end
      end
      s.requests[id]=nil
    end
  end
  bridge(Engine,"planTurnActions",function(proceed,st,ad,chosen,...)
    commitRequests(st,ad,chosen or {});return proceed(st,ad,chosen,...)
  end)
  bridge(Engine,"planTurnFromActions",function(proceed,st,ad,player,enemy,...)
    if not st.double then commitRequests(st,ad,{[0]=player,[1]=enemy}) end
    return proceed(st,ad,player,enemy,...)
  end)
  local Ui=require("src.core.game3.battle.ui")
  local drawing=false
  bridge(Ui,"handleInput",function(proceed,input)
    if input and Ui._mode=="moves" and Ui.waitingForCommand() and input:wasPressed("select") then
      local st=Ui._st;local b=State.battler(st,Ui._active or 0);local ad=Adapter.new(st,function() end)
      local options={};for _,c in ipairs(candidates(b)) do if manual[c.kind] and allowed(st,b,c,ad) then options[#options+1]=c end end
      local s=state(st);local current=s.requests[b.id];local nextIndex=1
      for i,c in ipairs(options) do if c==current then nextIndex=i+1 end end
      s.requests[b.id]=options[nextIndex];return true
    end
    local result=proceed(input)
    if Ui._mode=="menu" and Ui._st then state(Ui._st).requests[Ui._active or 0]=nil end
    return result
  end)
  bridge(Ui,"draw",function(proceed,w,h)
    drawing=true;local ok,result=pcall(proceed,w,h);drawing=false;if not ok then error(result,0) end
    if Ui._mode=="moves" and Ui._st then
      local b=State.battler(Ui._st,Ui._active or 0);local available=false;local ad=Adapter.new(Ui._st,function() end)
      for _,c in ipairs(candidates(b)) do if manual[c.kind] and allowed(Ui._st,b,c,ad) then available=true;break end end
      if available then
        local c=state(Ui._st).requests[b.id]
        love.graphics.push("all");love.graphics.setColor(0,0,0,.85);love.graphics.rectangle("fill",0,0,240,13)
        require("src.ui.game3.frlg_font").draw("SELECT: "..(c and c.name or "Transform"),3,1,{small=true,colors=require("src.ui.game3.frlg_font").COLOR.WHITE});love.graphics.pop()
      end
    end
    return result
  end)
  bridge(require("src.core.game3.battle.anim"),"present",function(proceed,key,...)
    local result=proceed(key,...)
    local b=drawing and Ui._st and State.battler(Ui._st,type(key)=="number" and key or key=="player" and 0 or 1)
    if b and b._editorAdvanced then
      result=copy(result)
      if giant(b._editorAdvanced.config.kind) then result.scale=(result.scale or 1)*1.35
      elseif b._editorAdvanced.config.kind=="tera" then result.blendCoeff=math.max(result.blendCoeff or 0,.15);result.blendColor={.6,.9,1} end
    end
    return result
  end)
  local maxNames={[0]="Max Strike",[1]="Max Knuckle",[2]="Max Airstream",[3]="Max Ooze",[4]="Max Quake",[5]="Max Rockfall",[6]="Max Flutterby",[7]="Max Phantasm",[8]="Max Steelspike",[10]="Max Flare",[11]="Max Geyser",[12]="Max Overgrowth",[13]="Max Lightning",[14]="Max Mindstorm",[15]="Max Hailstorm",[16]="Max Wyrmwind",[17]="Max Darkness",[18]="Max Starfall"}
  if typeIds.FAIRY~=18 then maxNames[18]=nil end;if typeIds.FAIRY then maxNames[typeIds.FAIRY]="Max Starfall" end
  local function maxPower(power,t)
    local low=(t==1 or t==3)
    if power<=40 then return low and 70 or 90 elseif power<=50 then return low and 75 or 100 elseif power<=60 then return low and 80 or 110 elseif power<=70 then return low and 85 or 120 elseif power<=100 then return low and 90 or 130 elseif power<=140 then return low and 95 or 140 end
    return low and 100 or 150
  end
  local function effectiveMove(b,base)
    local record=b and b._editorAdvanced
    if record and record.config.kind=="tera" and base.numId==record.config.teraBlastIndex then
      local out=copy(base);out.type=record.config.teraIndex or 64;out.power=record.config.teraType=="STELLAR" and 100 or 80;out.effect=0;out.accuracy=100
      out._editorPhysical=(b.mon.attack or 0)>(b.mon.spAtk or 0);out._editorTeraBlast=true;return out
    end
    if not record or not giant(record.config.kind) then return base end
    local c=record.config;local move=copy(base)
    if (base.power or 0)==0 then
      local protect=Moves.get(182);move.effect=protect.effect;move.priority=4;move.target=protect.target;move.flags=protect.flags;move.id="MAX_GUARD";move.name="Max Guard"
    elseif c.kind=="gigantamax" and base.type==c.maxTypeIndex then
      move=copy(Moves.get(c.maxMoveIndex));move.numId=base.numId
    else
      move.power=maxPower(base.power,base.type);move.effect=0;move.secondaryChance=0;move.accuracy=100;move.target=0;move.priority=0;move.flags=0
      move.id=(maxNames[base.type] or "Max Move"):upper():gsub(" ","_");move.name=maxNames[base.type] or "Max Move"
    end
    move.numId=base.numId;move._editorMax=true;return move
  end
  local previewing=false
  bridge(Moves,"get",function(proceed,id)
    local ctx=contexts[#contexts];local numeric=tonumber(type(id)=="table" and (id.numId or id.id) or id) or Moves.numForName(id)
    if ctx and numeric==ctx.num then return ctx.move end
    local result=proceed(id)
    if not ctx and not previewing and Ui._mode=="moves" and Ui._st then
      local b=State.battler(Ui._st,Ui._active or 0)
      for _,known in ipairs(b and b.mon.moves or {}) do if tonumber(known)==numeric then
        previewing=true;result=effectiveMove(b,result);previewing=false;break
      end end
    end
    return result
  end)
  bridge(P,"moveName",function(proceed,id,...)
    local ctx=contexts[#contexts]
    if ctx and tonumber(id)==ctx.num and ctx.move._editorMax then return ctx.move.name or ctx.move.id:gsub("_"," ") end
    if not ctx and Ui._mode=="moves" and tonumber(id) then
      local move=Moves.get(id);if move._editorMax then return move.name or move.id:gsub("_"," ") end
    end
    return proceed(id,...)
  end)
  mod.hooks:wrap("battle.accuracy",function(proceed,c)
    local ctx=contexts[#contexts];if ctx and ctx.move._editorMax then return true end
    return proceed(c)
  end)
  bridge(Types,"isPhysical",function(proceed,t)
    local ctx=contexts[#contexts]
    if ctx and ctx.move._editorPhysical~=nil and t==ctx.move.type then return ctx.move._editorPhysical end
    return proceed(t)
  end)
  local function maxEffect(st,b,t,ad)
    local weather={[5]="SAND",[10]="SUN",[11]="RAIN",[15]="HAIL"}
    if weather[t] then ad:setWeather(weather[t],5);return end
    local own={[1]="attack",[2]="speed",[3]="spAtk",[4]="spDef",[8]="defense"}
    local foe={[0]="speed",[6]="spAtk",[7]="defense",[16]="attack",[17]="spDef"}
    if own[t] then for _,a in ipairs(State.allies(st,b)) do ad:changeStages(a,{[own[t]]=1}) end
    elseif foe[t] then for _,a in ipairs(State.foes(st,b)) do ad:changeStages(a,{[foe[t]]=-1}) end
    elseif t==12 or t==13 or t==14 or t==typeIds.FAIRY then st._editorTerrain={type=t,turns=5} end
  end
  mod.events:on("battle.damage_dealt",function(ev)
    local ctx=contexts[#contexts];if ctx and ev.user==ctx.user and ev.damage>0 then ctx.hit=true end
  end)
  bridge(Engine,"resolveMove",function(proceed,user,target,move,slot,ad,st,out,opts)
    user=State.occupant(st,user);target=State.occupant(st,target)
    local base=Moves.get(move);local ctx={user=user,num=base.numId,move=effectiveMove(user,base)}
    local targetRecord=target and target._editorAdvanced
    if targetRecord and giant(targetRecord.config.kind) and (base.effect==38 or base.effect==196 or base.effect==28) and not ctx.move._editorMax then
      ctx.move=copy(base);ctx.move.effect=85;ctx.move.effectId="EXP_SPLASH_EFFECT";ctx.move.power=0
    end
    if st._editorTerrain and st._editorTerrain.type==14 and target and target.side~=user.side and (ctx.move.priority or 0)>0 and target.type1~=2 and target.type2~=2 and ad:abilityOf(target)~="LEVITATE" then
      ctx.move=copy(base);ctx.move.effect=85;ctx.move.effectId="EXP_SPLASH_EFFECT";ctx.move.power=0
    end
    if user._editorAdvanced and giant(user._editorAdvanced.config.kind) then user.flinched=nil end
    if ctx.move._editorMax and ctx.move.power>0 and target and target._editorMaxGuard then ctx.move.flags=2 end
    contexts[#contexts+1]=ctx
    local ok,result=pcall(proceed,user,target,move,slot,ad,st,out,opts)
    contexts[#contexts]=nil
    if not ok then error(result,0) end
    local r=user._editorAdvanced
    if ctx.hit and r and r.config.kind=="tera" and r.config.teraType=="STELLAR" then
      r.stellarUsed=r.stellarUsed or {};r.stellarUsed[ctx.move.type]=true
      if ctx.move._editorTeraBlast then ad:changeStages(user,{attack=-1,spAtk=-1}) end
    end
    if ctx.move._editorMax then
      if ctx.move.power==0 then user._editorMaxGuard=user.expProtected and true or nil
      elseif ctx.hit and user._editorAdvanced and user._editorAdvanced.config.kind=="dynamax" then maxEffect(st,user,ctx.move.type,ad)
      elseif ctx.hit and user._editorAdvanced and ctx.move.type~=user._editorAdvanced.config.maxTypeIndex then maxEffect(st,user,ctx.move.type,ad) end
    end
    return result
  end)
  local damageContexts={}
  local function teraStab(record,t,ad,b)
    local original=t==record.type1 or t==record.type2
    if record.config.teraType=="STELLAR" then
      if not (record.stellarUsed or {})[t] then return original and 2 or 1.2 end
      return original and 1.5 or 1
    end
    if t==record.config.teraIndex then
      if ad and ad:abilityOf(b)=="ADAPTABILITY" then return original and 2.25 or 2 end
      return original and 2 or 1.5
    end
    return original and 1.5 or 1
  end
  bridge(Types,"typeCalc",function(proceed,t,d1,d2,damage,...)
    local c=damageContexts[#damageContexts]
    if c and damage then damage=math.floor(damage*teraStab(c.record,t,c.ad,c.user)) end
    local dmg,flags,eff=proceed(t,d1,d2,damage,...)
    if c and c.stellarBlast and c.target._editorAdvanced and c.target._editorAdvanced.config.kind=="tera" then
      if dmg then dmg=dmg*2 end;eff=2;flags=copy(flags);flags.super=true;flags.notVery=false;flags.immune=false
    end
    return dmg,flags,eff
  end)
  bridge(require("src.core.game3.battle.damage"),"calc",function(proceed,user,target,move,opts)
    local record=user and user._editorAdvanced
    local def=type(move)=="table" and move.effect~=nil and move or Moves.get(move)
    local options=copy(opts)
    if record and record.config.kind=="tera" and def.type==record.config.teraIndex and def.power>0 and def.power<60 and (def.priority or 0)<=0 and def.effect==0 then options.power=60 end
    local calcUser=user;local tera=record and record.config.kind=="tera"
    if tera then
      calcUser=copy(user);calcUser.type1=nil;calcUser.type2=nil
      damageContexts[#damageContexts+1]={record=record,ad=options.adapter,user=user,target=target,stellarBlast=def._editorTeraBlast and record.config.teraType=="STELLAR"}
    end
    local ok,damage,info=pcall(proceed,calcUser,target,move,options)
    if tera then damageContexts[#damageContexts]=nil end
    if not ok then error(damage,0) end
    if damage>0 and info and not info.setDamage then
      if record and record.config.kind=="tera" then
        info.stab=teraStab(record,info.moveType or def.type,options.adapter,user)
      end
      local ctx=contexts[#contexts]
      if ctx and ctx.move._editorMax and target.expProtected then damage=math.max(1,math.floor(damage/4)) end
      local st=options.adapter and options.adapter._st;local terrain=st and st._editorTerrain
      if terrain then
        local userGround=user.type1~=2 and user.type2~=2 and options.adapter:abilityOf(user)~="LEVITATE"
        local targetGround=target.type1~=2 and target.type2~=2 and options.adapter:abilityOf(target)~="LEVITATE"
        if terrain.type==def.type and userGround and terrain.type~=typeIds.FAIRY then damage=math.floor(damage*1.3) end
        if targetGround and ((terrain.type==typeIds.FAIRY and def.type==16) or (terrain.type==12 and (def.numId==89 or def.numId==222))) then damage=math.max(1,math.floor(damage/2)) end
      end
    end
    return damage,info
  end)
  bridge(Adapter,"new",function(proceed,...)
    local ad=proceed(...);local old=ad.canApplyStatus
    ad.canApplyStatus=function(self,b,status,...)
      local terrain=self._st and self._st._editorTerrain
      if terrain and b.type1~=2 and b.type2~=2 and self:abilityOf(b)~="LEVITATE" then
        if terrain.type==typeIds.FAIRY or (terrain.type==13 and (status=="SLP" or status=="SLEEP")) then return false,"terrain" end
      end
      return old(self,b,status,...)
    end
    return ad
  end)
  local function shield(st,b,ad)
    for _,c in ipairs(candidates(b)) do if (c.kind=="disguise" or c.kind=="ice_face") and allowed(st,b,c,ad) then return c end end
  end
  bridge(Hit,"dealDamage",function(proceed,ctx,damage,info)
    local b,ad=ctx.target,ctx.adapter;local c=shield(ctx.st,b,ad)
    local ab=ad:abilityOf(ctx.user);local bypass=ab=="MOLD_BREAKER" or ab=="TERAVOLT" or ab=="TURBOBLAZE"
    local physical=info and info.physical;if physical==nil then physical=Types.isPhysical(ctx.moveType or ctx.move.type) end
    if c and not bypass and damage>0 and (b.substituteHP or 0)<=0 and (c.kind=="disguise" or physical) then
      activate(ctx.st,b,c,ad,true)
      ctx.hpDealt=0;ctx.hitsLanded=(ctx.hitsLanded or 0)+1
      if c.kind=="disguise" and (c.disguiseCost or 8)>0 then ad:applyHpLoss(b,math.max(1,math.floor(b.mon.maxHp/(c.disguiseCost or 8)))) end
      return 0
    end
    local result=proceed(ctx,damage,info)
    local record=b._editorAdvanced
    if record and record.config.kind=="gulp" and result>0 and not ctx.hitSubstitute then
      local payload=record.config.payload;revert(ctx.st,b)
      ad:applyHpLoss(ctx.user,math.max(1,math.floor(ctx.user.mon.maxHp/4)))
      if payload=="paralysis" then ad:applyStatus(ctx.user,"PAR",b) else ad:changeStages(ctx.user,{defense=-1}) end
    end
    return result
  end)
  mod.events:on("battle.move_used",function(ev)
    local b=ev.user;local ad=Adapter.new(ev.battle,function() end)
    for _,c in ipairs(candidates(b)) do if c.kind=="gulp" and c.moveIndex==ev.moveNum then
      local hp=b.mon.hp/b.mon.maxHp
      if not c.hpCondition or c.hpCondition=="any" or (c.hpCondition=="below" and hp<=.5) or (c.hpCondition=="above" and hp>.5) then activate(ev.battle,b,c,ad,true);break end
    end end
  end)
  local function refresh(st,ad,entered)
    for _,b in ipairs(State.present(st)) do
      local r=b._editorAdvanced
      if r and r.config.kind=="ice_face" then
        local w=Rules.weather.effective(st,ad)
        if w=="HAIL" and (entered==b or r.lastWeather~="HAIL") then revert(st,b) else r.lastWeather=w end
      end
    end
  end
  bridge(Engine,"afterAction",function(proceed,st,ad,...)
    local result=proceed(st,ad,...);refresh(st,ad);return result
  end)
  mod.events:on("battle.turn_started",function(ev) for _,b in ipairs(State.present(ev.battle)) do b._editorMaxGuard=nil end end)
  mod.events:on("battle.turn_ended",function(ev)
    local st=ev.battle;local ad=Adapter.new(st,function() end)
    for _,b in ipairs(State.present(st)) do
      local r=b._editorAdvanced
      if r and r.turns then r.turns=r.turns-1;if r.turns<=0 or b.mon.hp<=0 then revert(st,b) end end
      for _,c in ipairs(candidates(b)) do if (c.kind=="power_construct" or c.kind=="boss") and b.mon.hp*100<=b.mon.maxHp*(c.percent or 50) then activate(st,b,c,ad,true) end end
    end
    local terrain=st._editorTerrain
    if terrain then
      if terrain.type==12 then for _,b in ipairs(State.present(st)) do if b.mon.hp>0 and b.type1~=2 and b.type2~=2 and ad:abilityOf(b)~="LEVITATE" then ad:heal(b,math.max(1,math.floor(b.mon.maxHp/16))) end end end
      terrain.turns=terrain.turns-1;if terrain.turns<=0 then st._editorTerrain=nil end
    end
  end)
  local Battle=require("src.core.game3.battle")
  bridge(Battle,"start",function(proceed,opts)
    local wrapped=copy(opts);local done=wrapped.onDone
    wrapped.onDone=function(...) cleanup(Battle.getState());if done then return done(...) end end
    return proceed(wrapped)
  end)
  mod.events:on("battle.ended",function(ev) cleanup(ev.battle) end)
  bridge(require("src.core.game3.party"),"healAll",function(proceed,party,...)
    local result=proceed(party,...);local rt=package.loaded["src.core.game3.runtime"];local s=rt and rt.getSession and rt.getSession()
    if s and s.party==party and s.meta then s.meta.editorTeraSpent=nil end;return result
  end)
end
return M
