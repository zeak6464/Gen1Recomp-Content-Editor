-- Exported into the mod. No editor dependency or filesystem access at runtime.
return function(config, mod, deps)
  deps=deps or {}
  local P=deps.Pokemon or require("src.core.game3.pokemon")
  local Party=deps.Party or require("src.core.game3.party")
  local rng=deps.random or math.random
  local B={}
  local function copy(v) if type(v)~="table" then return v end;local r={};for k,c in pairs(v) do r[k]=copy(c) end;return r end
  function B.state(session)
    session.modData=session.modData or {};session.modData[mod.id]=session.modData[mod.id] or {}
    local bucket=session.modData[mod.id]
    bucket.daycare=bucket.daycare or {parents={},steps=0}
    return bucket.daycare
  end
  local function species(mon) return P.speciesOf(mon) end
  local function groups(mon) local m=P.speciesMeta(species(mon)) or {};return m.eggGroups or {m.eggGroup1 or 0,m.eggGroup2 or 0} end
  local function has(t,n) for _,v in ipairs(t) do if v==n then return true end end;return false end
  local function gender(mon) return mon.gender or P.gender(species(mon),mon.personality) end
  function B.parents(a,b)
    if not a or not b or P.isEgg(a) or P.isEgg(b) then return nil end
    local ga,gb=groups(a),groups(b)
    if has(ga,15) or has(gb,15) or #ga==0 or #gb==0 then return nil end
    local da,db=has(ga,13),has(gb,13)
    if da and db then return nil end
    if da then return b,a elseif db then return a,b end
    if gender(a)==gender(b) or gender(a)=="U" or gender(b)=="U" then return nil end
    local shared=false;for _,g in ipairs(ga) do if g>0 and has(gb,g) then shared=true end end
    if not shared then return nil end
    if gender(a)=="F" then return a,b end;return b,a
  end
  function B.compatibility(a,b)
    if not B.parents(a,b) then return 0 end
    local same=species(a)==species(b)
    local different=(a.otId or 0)~=(b.otId or 0)
    return same and (different and 70 or 50) or (different and 50 or 20)
  end
  function B.deposit(session,slot)
    local st=B.state(session);local party=session.party or {};local mon=party[slot]
    if #st.parents>=2 then return false,"We already have two Pokemon." end
    if not mon or P.isEgg(mon) then return false,"Choose a Pokemon, not an Egg." end
    local usable=false
    for i,m in ipairs(party) do if i~=slot and not P.isEgg(m) and (m.hp or 0)>0 then usable=true end end
    if not usable then return false,"Keep a healthy Pokemon with you." end
    local entry={mon=copy(mon),level=mon.level or 1,overlay=copy((session.move_overlay or {})[slot])}
    for i,row in pairs(entry.overlay or {}) do
      if type(row)=="table" and row.frlgMoveId then
        entry.mon.moves=entry.mon.moves or {};entry.mon.moves[i]=row.frlgMoveId
      end
    end
    st.parents[#st.parents+1]=entry;table.remove(party,slot)
    if session.move_overlay then for i=slot,6 do session.move_overlay[i]=session.move_overlay[i+1] end end
    st.steps=0
    return true,"Your Pokemon is safe with us."
  end
  function B.fee(entry) return (config.fee or 100)+math.max(0,(entry.mon.level or 1)-entry.level)*(config.feePerLevel or 100) end
  function B.withdraw(session,slot)
    local st=B.state(session);local entry=st.parents[slot]
    if not entry then return false,"No Pokemon in that place." end
    if #(session.party or {})>=6 then return false,"Make room in your party first." end
    local fee=B.fee(entry)
    if (session.money or 0)<fee then return false,"You need "..fee.." money." end
    session.party=session.party or {};session.party[#session.party+1]=entry.mon
    session.move_overlay=session.move_overlay or {};session.move_overlay[#session.party]=entry.overlay
    session.money=(session.money or 0)-fee;table.remove(st.parents,slot);st.steps=0
    return true,"Here is your Pokemon. Paid "..fee.."."
  end
  function B.makeEgg(session,mother,father)
    local sp=species(mother)
    local reverse={}
    for id=1,(config.maxSpecies or 411) do for _,evo in ipairs(P.evolutions(id)) do
      local target=evo.target or evo.species;if type(target)=="number" then reverse[target]=id end
    end end
    local seen={};while reverse[sp] and not seen[sp] do seen[sp]=true;sp=reverse[sp] end
    sp=(config.offspring or {})[species(mother)] or sp
    local special=((config.incense or {})[sp])
    local azurill=P.speciesFromName("AZURILL");local wynaut=P.speciesFromName("WYNAUT")
    if not special and sp==azurill then special={item=220,fallback=P.speciesFromName("MARILL")} end
    if not special and sp==wynaut then special={item=221,fallback=P.speciesFromName("WOBBUFFET")} end
    if special and mother.heldItem~=special.item and father.heldItem~=special.item then sp=special.fallback end
    local pair=(config.splitSpecies or {})[sp]
    local nf,nm=P.speciesFromName("NIDORAN_F"),P.speciesFromName("NIDORAN_M")
    local il,vo=P.speciesFromName("ILLUMISE"),P.speciesFromName("VOLBEAT")
    if not pair and sp==nf then pair={nf,nm} end
    if not pair and sp==il then pair={il,vo} end
    if pair then sp=pair[rng(1,2)] end
    local temporary={party={},name=session.name,trainerId=session.trainerId}
    assert(Party.giveMon(temporary,sp,config.eggLevel or 5),"Could not create Egg")
    local egg=temporary.party[1]
    -- Three distinct inherited IVs; preserve the random IVs in the other stats.
    local keys={"hp","atk","def","spe","spa","spd"}
    local aliases={atk="attack",def="defense",spe="speed",spa="spAtk",spd="spDef"}
    for _=1,3 do local at=rng(1,#keys);local key=table.remove(keys,at);local parent=rng(1,2)==1 and mother or father
      local iv=parent.ivs or {};egg.ivs[key]=iv[key] or iv[aliases[key]] or egg.ivs[key] end
    local moves={};local function learn(move)
      if not move or move==0 then return end
      for _,id in ipairs(moves) do if id==move then return end end
      if #moves==4 then table.remove(moves,1) end;moves[#moves+1]=move
    end
    for _,move in ipairs(egg.moves or {}) do learn(move) end
    local learned={};for _,row in ipairs(P.learnset(sp)) do learned[row.move or row[2]]=true end
    local machines={}
    for n=0,57 do if P.canLearnTmIndex(sp,n) then machines[#machines+1]=P.moveFromTmItem(289+n) end end
    -- Male or genderless partners of Ditto donate the paternal moves.
    if has(groups(father),13) and gender(mother)~="F" then mother,father=father,mother end
    -- FireRed applies these in separate passes; order matters with four slots.
    for _,move in ipairs(father.moves or {}) do
      if has((config.eggMoves or {})[sp] or {},move) then learn(move) end
    end
    for _,move in ipairs(father.moves or {}) do if has(machines,move) then learn(move) end end
    for _,move in ipairs(father.moves or {}) do
      if learned[move] and has(mother.moves or {},move) then learn(move) end
    end
    egg.moves=moves;egg.pp={};egg.maxPp={}
    for i,move in ipairs(moves) do egg.pp[i]=P.movePp(move);egg.maxPp[i]=egg.pp[i] end
    P.applyStats(egg);egg.hp=egg.maxHp
    egg.isEgg=true;egg.egg=true;egg.friendship=(P.speciesMeta(sp) or {}).eggCycles or 20;egg.eggCycles=egg.friendship
    return egg
  end
  function B.step(session)
    if not config.enabled or not session then return end
    local st=B.state(session)
    if config.expPerStep and config.expPerStep>0 then
      local Summary=deps.Summary or require("src.core.game3.summary_data")
      for _,entry in ipairs(st.parents) do local m=entry.mon
        if (m.level or 1)<100 then
          m.exp=(m.exp or Summary.expForLevel(m.growthRate or 0,m.level or 1))+config.expPerStep
          while m.level<100 and m.exp>=Summary.expForLevel(m.growthRate or 0,m.level+1) do
            m.level=m.level+1
            for _,row in ipairs(P.learnset(species(m))) do
              local level,move=row.level or row[1],row.move or row[2]
              if level==m.level and not has(m.moves or {},move) then
                m.moves=m.moves or {};m.pp=m.pp or {};m.maxPp=m.maxPp or {}
                if #m.moves>=4 then table.remove(m.moves,1);table.remove(m.pp,1);table.remove(m.maxPp,1) end
                m.moves[#m.moves+1]=move;m.pp[#m.moves]=P.movePp(move);m.maxPp[#m.moves]=P.movePp(move)
                -- Keep the native move overlay consistent after Day-Care learns a move.
                entry.overlay={};for i,id in ipairs(m.moves) do entry.overlay[i]={frlgMoveId=id,pp=m.pp[i] or P.movePp(id)} end
              end
            end
          end
          P.applyStats(m)
        end
      end
    end
    if st.egg or #st.parents~=2 then return end
    st.steps=(st.steps or 0)+1;if st.steps<(config.steps or 256) then return end;st.steps=0
    local a,b=st.parents[1].mon,st.parents[2].mon
    if rng(1,100)>B.compatibility(a,b) then return end
    local mother,father=B.parents(a,b)
    st.egg=B.makeEgg(session,mother,father)
  end
  function B.collect(session)
    local st=B.state(session)
    if not st.egg then return false,"There is no Egg yet." end
    if #(session.party or {})>=6 then return false,"Make room in your party first." end
    session.party=session.party or {};session.party[#session.party+1]=st.egg;st.egg=nil
    return true,"Take good care of this Egg!"
  end
  function B.install()
    mod.events:on("world.stepped",function() B.step(require("src.core.game3.runtime").getSession()) end)
    mod.hooks:wrap("script.command",function(proceed,ctx,op,row)
      if op~="editor_daycare" or row.owner~=mod.id then return proceed(ctx,op,row) end
      local vm=ctx.vm or ctx.runner;local session=ctx.session or ctx.save
      if not vm or not session then return false end
      local Choice=require("src.ui.game3.choice")
      require("src.ui.game3.hud").ensure(ctx.game,"message")
      local done=false;vm.ctx.mode="native";vm.ctx.status="waiting";vm.ctx.nativePoll=function() return done end
      local function finish() done=true;vm:tick() end
      local function say(text) vm.adapters.openMessageAsync(text,finish) end
      local function choose(options,callback) Choice.multi(options,0,callback,{left=1,top=1,maxRight=29}) end
      choose({"Leave a Pokemon","Take a Pokemon","Collect Egg","Check parents","Cancel"},function(sel)
        if sel==0 then
          local names={};for i,m in ipairs(session.party or {}) do names[i]=m.nickname and m.nickname~="" and m.nickname or P.name(species(m)) end;names[#names+1]="Cancel"
          choose(names,function(n) if n<0 or n>=#names-1 then finish();return end;local _,msg=B.deposit(session,n+1);say(msg) end)
        elseif sel==1 then
          local st=B.state(session);local names={}
          for i,e in ipairs(st.parents) do names[i]=P.name(species(e.mon)).." - "..B.fee(e) end;names[#names+1]="Cancel"
          choose(names,function(n) if n<0 or n>=#names-1 then finish();return end;local _,msg=B.withdraw(session,n+1);say(msg) end)
        elseif sel==2 then local _,msg=B.collect(session);say(msg)
        elseif sel==3 then local st=B.state(session);local chance=#st.parents==2 and B.compatibility(st.parents[1].mon,st.parents[2].mon) or 0
          say(st.egg and "An Egg is ready for you!" or (chance>0 and "Your Pokemon can have an Egg.\nKeep walking and come back." or "Leave two compatible Pokemon\nwith us to receive an Egg."))
        else finish() end
      end)
      return true
    end)
  end
  return B
end
