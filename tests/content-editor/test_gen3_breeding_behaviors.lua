return function(data,root)
  local State,IO=require("State"),require("ModIO")
  local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("breeding_behaviors");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  local Breed=require("Gen3Breeding");local config=Breed.ensure(S)
  assert(config.eggMoves[1][1]==113,"ROM egg-move table did not decode")
  config.enabled=true;config.steps=1;config.expPerStep=0
  local P=require("src.core.game3.pokemon");local Party=require("src.core.game3.party")
  P.install({read=function(_,path) return data._gen3Read(path) end})
  local runtime=require("Gen3BreedingRuntime")(config,{id=S.project.id},{random=function(a) return a end})
  local session={party={},money=1000,trainerId=111,name="Test"}
  for _=1,3 do assert(Party.giveMon(session,1,5)) end
  session.party[1].gender="F";session.party[2].gender="M";session.party[2].moves={113,33};session.party[2].otId=222
  local eggParent=P.speciesOf(session.party[1]);assert(eggParent==1)
  assert(runtime.compatibility(session.party[1],session.party[2])==70)
  assert(runtime.deposit(session,1));assert(runtime.deposit(session,1))
  assert(#session.party==1 and #runtime.state(session).parents==2)
  runtime.step(session);assert(runtime.state(session).egg and runtime.state(session).egg.isEgg)
  local egg=runtime.state(session).egg;local inherited=false;for _,m in ipairs(egg.moves) do if m==113 then inherited=true end end
  assert(inherited,"Father's egg move was not inherited")
  assert(#egg.moves<=4 and egg.pp[1]>0)
  local dex=next(session.dex.owned);assert(dex==1)
  -- Pending Eggs and deposited parents survive the actual native save conversion.
  local schema=require("src.core.game3.save_schema_firered")
  local saved=schema.toSaveTable(session);local restored=schema.fromSaveTable(require("src.mods.Merge").deepCopy(saved))
  assert(#runtime.state(restored).parents==2 and runtime.state(restored).egg.isEgg)
  while #restored.party<6 do assert(Party.giveMon(restored,1,5)) end
  assert(not runtime.collect(restored) and runtime.state(restored).egg)
  table.remove(restored.party);assert(runtime.collect(restored));assert(not runtime.state(restored).egg)
  assert(not runtime.collect(restored),"Egg collected twice")
  assert(not runtime.withdraw(restored,1),"Withdrawal must respect party limit")
  table.remove(restored.party);restored.money=0
  assert(not runtime.withdraw(restored,1));assert(#runtime.state(restored).parents==2)
  restored.money=1000;assert(runtime.withdraw(restored,1));assert(restored.money==900)
  local single={party={session.party[1]}}
  assert(not runtime.deposit(single,1),"Cannot deposit last usable Pokemon")
  local pa=runtime.state(session).parents[1].mon;local pb=runtime.state(session).parents[2].mon
  local old=pb.gender;pb.gender="F";assert(runtime.compatibility(pa,pb)==0);pb.gender=old
  local oldEgg=pa.isEgg;pa.isEgg=true;assert(runtime.compatibility(pa,pb)==0);pa.isEgg=oldEgg
  local key,err=Breed.attach(S,"FR_PALLET_TOWN",1);assert(key,err)
  local C=require("Gen3Behaviors")
  local aid=C.new(S,"ability");local ability=S.project.gen3Behaviors[aid]
  ability.name="Restoring Breeze";ability.actions={{kind="heal",amount=25},{kind="weather",weather="RAIN",turns=3}}
  local mon=require("src.mods.Merge").deepCopy(data.pokemon.BULBASAUR);mon.abilities={ability.index,"OVERGROW"};S.project.pokemon.BULBASAUR=mon
  local mid=C.new(S,"move");S.project.gen3Behaviors[mid].name="Restoring Light";S.project.gen3Behaviors[mid].actions={{kind="heal",amount=50}}
  C.assignMove(S,mid,"TACKLE")
  C.assignMove(S,mid,"SPLASH")
  assert(S.project.moves.TACKLE.power==data.moves.TACKLE.power,"Reassignment changed the previous move")
  local did=C.new(S,"move");local damaging=S.project.gen3Behaviors[did]
  damaging.name="Healing Strike";damaging.mode="damage";damaging.power=55;damaging.target="self"
  damaging.actions={{kind="heal",amount=25}}
  C.assignMove(S,did,"TACKLE")
  assert(S.project.moves.TACKLE.power==55 and S.project.moves.TACKLE.target==0)
  local valid=pcall(C.validate,{bad={kind="ability",name="Overgrow",index=79,target="self",chance=100,trigger="endTurn",actions={{kind="heal",amount=10}}}})
  assert(not valid,"Native ability name collision accepted")
  local dir=root.."/tests/content-editor/gen3-smoke/breeding-behaviors"
  assert(IO.ensureDirectory(dir));assert(IO.writeText(dir.."/manifest.json",'{"id":"breeding_behaviors","name":"Test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  assert(IO.save(dir,S.project));local reopened=assert(IO.load(dir));assert(reopened.gen3Breeding.eggMoves[1][1]==113 and reopened.gen3Behaviors[aid].index==78)
  local G=require("Gen3");local fresh={};G.load(fresh,data._gen3Read)
  local loader,errorText=require("Gen3Mod").load(fresh,dir);assert(loader,errorText)
  assert(P.abilityName(78)=="Restoring Breeze","Custom ability name did not reach the game")
  assert(G.catalog(fresh,"pokemon").BULBASAUR.abilities[1]==78)
  assert(P.abilities(1)[1]==78 and P.abilities(1)[2]==65,"Custom ability assignment did not reach native Pokemon data")
  -- Execute the exported attendant in the native VM and native choice UI.
  local Compat=require("src.mods.Gen3Compat");local oldCtx=Compat.scriptCtx
  local Choice=require("src.ui.game3.choice")
  local Vm=require("src.core.game3.scripting.vm")
  local adapters=require("src.core.game3.scripting.adapters").stub({})
  Compat.scriptCtx=function(vm) return {vm=vm,session=restored,game={}} end
  local vm=Vm.new({scripts=G.catalog(fresh,"map_scripts"),adapters=adapters})
  assert(vm:startTalk(key,1,1));vm:tick()
  assert(vm:isRunning() and vm.ctx.mode=="native","Day-Care did not wait for menu input")
  Choice.cancel();vm:tick();assert(not vm:isRunning(),"Cancel left Day-Care script running")
  assert(next(adapters.frozen)==nil,"Cancel left NPCs frozen")
  assert(vm:startTalk(key,1,1));vm:tick();Choice.confirm();Choice.cancel();vm:tick()
  assert(not vm:isRunning(),"Party selection cancel left script running")
  local menuSession={party={},money=1000}
  for _=1,3 do assert(Party.giveMon(menuSession,1,5)) end
  Compat.scriptCtx=function(v) return {vm=v,session=menuSession,game={}} end
  assert(vm:startTalk(key,1,1));vm:tick();Choice.confirm();Choice.confirm();vm:tick()
  assert(#menuSession.party==2 and #menuSession.modData.breeding_behaviors.daycare.parents==1,"Attendant did not deposit the selected Pokemon")
  assert(not vm:isRunning() and next(adapters.frozen)==nil,"Deposit left script locked")
  Compat.scriptCtx=oldCtx
  local Moves=require("src.core.game3.battle.moves")
  assert(Moves.get(data.moves.TACKLE.index).power==55,"Power did not reach native battle data")
  local StateBattle=require("src.core.game3.battle.state")
  local function battleMon(hp)
    return {species=1,level=50,hp=hp,maxHp=100,attack=50,defense=50,spAtk=50,spDef=50,speed=50,ability=0,
      moves={data.moves.TACKLE.index},pp={20},nickname="TEST"}
  end
  local battle=StateBattle.new({wild=true,playerParty={battleMon(20)},foeParty={battleMon(100)}})
  battle.player.type1=0;battle.enemy.type1=0;battle.rng=function(lo) return lo end
  local nativeAdapter=require("src.core.game3.battle.adapter").new(battle)
  require("src.core.game3.battle.engine").resolveMove(battle.player,battle.enemy,data.moves.TACKLE.index,1,nativeAdapter,battle,{})
  assert(nativeAdapter:hp(battle.enemy)<100,"Custom damaging move dealt no damage")
  assert(nativeAdapter:hp(battle.player)==45,"Native battle did not apply post-hit healing")
  -- The damage hook leaves native hit resolution in charge and never rerolls accuracy.
  local hitContext={adapter=nil,user=nil,target=nil,moveId=data.moves.TACKLE.index,
    accuracyCheck=function() error("Accuracy checked twice") end,
    attackAnimation=function() error("Animation played twice") end}
  local b={hp=20,maxHp=100,ability=78,stages={}};local ad={}
  function ad:hp(m) return m.hp end;function ad:maxHp(m) return m.maxHp end
  function ad:heal(m,n) m.hp=math.min(m.maxHp,m.hp+n) end
  function ad:roll() return 1 end;function ad:say() end;function ad:sayFail() end
  function ad:setWeather(kind,turns) self.weather=kind;self.turns=turns end
  function ad:abilityOf(m) return P.abilityName(m.ability):upper():gsub("%s+","_") end
  hitContext.adapter=ad;hitContext.user=b;hitContext.target={hp=50,maxHp=100}
  local RT=require("src.mods.Runtime")
  local function runHit(flags)
    b.hp=20;hitContext.targetDamaged=nil;hitContext.noEffect=nil;hitContext.failed=nil;hitContext.hitSubstitute=nil;hitContext.hpDealt=nil
    RT.call("editor.gen3.custom.hit",function(ctx) for k,v in pairs(flags) do ctx[k]=v end;return "native" end,hitContext)
    return b.hp
  end
  assert(runHit({targetDamaged=true,hpDealt=20})==45,"Damaging move did not heal after a hit")
  assert(runHit({})==20,"Miss triggered extra actions")
  assert(runHit({targetDamaged=true,hpDealt=20,noEffect=true})==20,"Immunity triggered extra actions")
  assert(runHit({targetDamaged=true,hpDealt=20,hitSubstitute=true})==20,"Substitute triggered extra actions")
  b.hp=20
  local Ab=require("src.core.game3.battle.abilities")
  assert(Ab.endTurn(ad,b));assert(b.hp==45 and ad.weather=="RAIN" and ad.turns==3)
  b.hp=0;assert(not Ab.endTurn(ad,b));assert(b.hp==0,"Ability revived a fainted Pokemon")
  b.hp=20
  local Effects=require("src.core.game3.battle.effects")
  local mc={accuracyCheck=function() return true end,attackAnimation=function() end}
  assert(Effects.runForMove(ad,b,b,data.moves.SPLASH.index,mc));assert(b.hp==70)
  b.hp=20;mc.accuracyCheck=function() return false end
  assert(Effects.runForMove(ad,b,b,data.moves.SPLASH.index,mc));assert(b.hp==20,"Missed custom move still healed")
  for _,e in ipairs(loader:status().errors or {}) do error(tostring(e)) end
  require("src.mods.Runtime").reset();assert(P.abilities(1)[1]~=78,"Disabled mod leaked ability assignment");assert(P.abilityName(78)~="Restoring Breeze","Disabled mod leaked ability names")
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  for _,panel in ipairs({"daycare","custom","damage"}) do
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
    if panel=="daycare" then Breed.draw(S,20,20,1320,800,{markDirty=function() end})
    else S.g3BehaviorId=panel=="damage" and did or aid;C.draw(S,20,20,1320,800,{markDirty=function() end}) end
    K.endFrame();love.graphics.setCanvas()
    local png=canvas:newImageData():encode("png");assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/"..panel.."-builder.png",png:getString()))
  end
end
