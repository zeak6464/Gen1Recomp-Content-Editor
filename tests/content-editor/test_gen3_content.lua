return function(data,root)
  local A=require("Gen3ContentAdapter")
  local S=require("State").new()
  S.data=data;S.version="firered";S.path=root.."/tests/content-editor/gen3-smoke/native-project"
  S.project=require("State").blankProject("native_integration");S.project.game="firered"
  S.project.gen3={pokemon={BULBASAUR={baseStats={hp=81}}}}
  A.prepare(S)
  assert(S.project.pokemon.BULBASAUR.baseStats.attack==data.pokemon.BULBASAUR.baseStats.attack,"Migration lost unedited stats")
  S.trainerId="326";S.trainerSection="basics";S.g3EncounterId="FR_ROUTE_1";S.g3EncounterKind="land"
  S.pokemonId="BULBASAUR";S.itemId="POTION";S.moveId="TACKLE"
  local Kit=require("Kit")
  local original=Kit.textfield
  Kit.textfield=function(id,x,y,w,h,value,...)
    if id=="pk_st_specialAttack" then return "123" end
    if id=="g3_price" then return "75" end
    if id=="mv_pow" then return "70" end
    if id=="g3_tr_name" then return "Test Rival" end
    if id=="g3_enc_rate" then return "33" end
    if id=="pl_boot_money" then return "12345" end
    if id=="g3_rule_critMultiplier" then return "3" end
    if id=="br_eggs" then return "12" end
    return original(id,x,y,w,h,value,...)
  end
  local app={markDirty=function() S.dirty=true end}
  local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true})
  for _,name in ipairs({"Pokemon","Items","Moves","Trainers","Encounters","Player","Rules","Breeding"}) do
    Kit.layout(1360,860);Kit.beginFrame(0,0,false,0)
    require(name).draw(S,20,80,1320,740,app);Kit.endFrame()
  end
  Kit.textfield=original
  S.gen3Id="EDITOR_TEST_STEPS";S.g3EventMode="scripts"
  S.project.gen3.map_scripts={[S.gen3Id]={{op="setvar",var=0x4000,value=5},{op="end"}}}
  S.project.gen3Modes={map_scripts={[S.gen3Id]="register"}}
  S.dirty=false
  Kit.beginFrame(0,0,false,0)
  require("Gen3Events").draw(S,20,80,1320,740,app);Kit.endFrame()
  assert(not S.dirty,"Browsing native commands dirtied the mod")
  Kit.textfield=function(id,x,y,w,h,value,...)
    if id=="g3field/event/EDITOR_TEST_STEPS/1/value/value" then return "17" end
    return original(id,x,y,w,h,value,...)
  end
  Kit.beginFrame(0,0,false,0)
  require("Gen3Events").draw(S,20,80,1320,740,app);Kit.endFrame()
  Kit.textfield=original
  assert(S.project.gen3.map_scripts.EDITOR_TEST_STEPS[1].value==17,"Command argument UI did not commit")
  for _,section in ipairs({"learnset","evolutions","trees","tmhm","dex"}) do
    S.pokemonSection=section;Kit.beginFrame(0,0,false,0)
    require("Pokemon").draw(S,20,80,1320,740,app);Kit.endFrame()
  end
  love.graphics.setCanvas()
  assert(S.project.pokemon.BULBASAUR.baseStats.specialAttack==123)
  assert(S.project.items.POTION.price==75 and S.project.moves.TACKLE.power==70)
  assert(data.pokemon.BULBASAUR.baseStats.specialAttack~=123,"Editor mutated original species")
  S.project.pokemon.BULBASAUR.learnset={}
  S.project.pokemon.BULBASAUR.abilities={"OVERGROW"}
  S.project.pokemon.BULBASAUR.evolutions={{method="EVO_LEVEL",level=22,species="IVYSAUR"}}
  S.project.items.EDITOR_POTION=A.newRecord(S,"items","EDITOR_POTION")
  S.project.items.EDITOR_POTION.price=99
  S.project.moves.EDITOR_TACKLE=A.newRecord(S,"moves","EDITOR_TACKLE")
  S.project.pokemon.EDITOR_MON=A.newRecord(S,"pokemon","EDITOR_MON")
  assert(S.project.trainers["326"].name=="Test Rival")
  assert(S.project.encounters.FR_ROUTE_1.land.rate==33)
  local trainer=S.project.trainers["326"]
  trainer.party={{species="MEW",level=42,heldItem="POTION",moves={"TACKLE","0","0","0"}}}
  S.project.encounters.FR_ROUTE_1.land.slots[1]={species="MEW",minLevel=7,maxLevel=9}
  local D=require("Gen3Dialog")
  local ir={{t="text",s="Before "},{t="player"},{t="ext",code=4,args={1}},{t="nl"},{t="rival"},{t="eos"}}
  local changed=D.encode(D.display(ir):gsub("Before","After"),ir)
  assert(changed[1].s=="After " and changed[2].t=="player" and changed[3].code==4)
  local shifted=D.encode("Extra\n"..D.display(ir),ir)
  local second=D.encode("Extra again\n"..D.display(ir),shifted)
  local found=false;for _,token in ipairs(second) do if token.t=="ext" and token.code==4 then found=true end end
  assert(found,"Editing before a control changed its identity")
  S.project.text.Text_BootedUpPC=changed
  assert(S.project.boot.startMoney==12345)
  assert(S.project.gen3BattleRules.critMultiplier==3)
  assert(S.project.pokemon[S.breedingSpeciesId].eggCycles==12)
  S.project.gen3Trades={TEST={give="BULBASAUR",get="IVYSAUR",nickname="LEAF",otName="NPC",otId=88}}
  S.g3TradeId="TEST"
  local button=Kit.button
  Kit.button=function(x,y,w,h,label,...) if label=="Create / open NPC script" then return true end;return false end
  Kit.beginFrame(0,0,false,0);require("Trades").draw(S,20,80,1320,740,app);Kit.endFrame()
  Kit.button=button
  assert(S.project.gen3.map_scripts.EditorTrade_native_integration_TEST[6].op=="editor_trade")
  S.project.gen3Effects={EXP_POISON_EFFECT="EXP_BURN_EFFECT"}
  S.project.boot.startPcItems={{id="POTION",count=3}}
  local W=require("Gen3Workbench")
  local keys,shops=W.shops(S)
  local shop=keys[1];S.project.marts={[shop]={"POTION","POKE_BALL"}}
  S.project.types.FIRE={name="FLAME",category="physical"}
  S.project.type_matchups["FIRE>WATER"]=20
  local maker=require("Gen3Create")
  local madeMove=maker.create(S,"moves","ABSORB")
  assert(madeMove.effect==3 and madeMove.id~="ABSORB" and S.project.gen3Animations["moves/"..madeMove.index])
  local madeItem=maker.create(S,"items","POTION")
  assert(madeItem.holdEffectParam==20 and madeItem.index~=13)
  local IO=require("ModIO")
  S.project.gen3Help={["1:1"]={question="Editor question",answer="Editor answer"}}
  assert(IO.save(S.path,S.project))
  local reopened=assert(IO.load(S.path))
  assert(reopened.pokemon.BULBASAUR.baseStats.specialAttack==123)
  assert(reopened.gen3.items.POTION.price==75)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  assert(reopened.gen3Help["1:1"].answer=="Editor answer")
  local helpBytes=loader.hooks:call("editor.gen3.cache",function(path) return data._gen3Read(path) end,"data/generated/gba/help/pack.lua")
  local helpPack=assert(loadstring(helpBytes))();assert(helpPack.entries[1][1].answer=="Editor answer")
  local G=require("Gen3")
  local mons=G.catalog(fresh,"pokemon");local items=G.catalog(fresh,"items");local moves=G.catalog(fresh,"moves")
  assert(mons.BULBASAUR.baseStats.specialAttack==123 and mons.BULBASAUR.baseStats.hp==81)
  assert(fresh.gen3Pokemon.stats[1].spa==123,"Stat change did not reach native tables")
  assert(fresh.gen3Items.items[13].price==75,"Price change did not reach native tables")
  assert(#mons.BULBASAUR.learnset==0,"Cleared learnset was restored during export")
  assert(mons.BULBASAUR.evolutions[1].level==22)
  assert(items.POTION.price==75 and moves.TACKLE.power==70)
  assert(items.EDITOR_POTION.price==99 and moves.EDITOR_TACKLE and mons.EDITOR_MON)
  assert(G.catalog(fresh,"map_scripts").EditorTrade_native_integration_TEST[6].owner=="native_integration")
  assert(G.catalog(fresh,"map_scripts").EDITOR_TEST_STEPS[1].value==17)
  local trainers=G.catalog(fresh,"trainers");local encounters=G.catalog(fresh,"encounters")
  assert(trainers["326"].name=="Test Rival" and trainers["326"].party[1].species=="MEW")
  assert(trainers["326"].party[1].heldItem=="POTION")
  assert(encounters.FR_ROUTE_1.land.rate==33 and encounters.FR_ROUTE_1.land.slots[1].maxLevel==9)
  assert(G.catalog(fresh,"text").Text_BootedUpPC[3].code==4)
  local effects=require("src.core.game3.battle.effects")
  assert(effects.get("EXP_POISON_EFFECT")==effects.get("EXP_BURN_EFFECT"))
  local P=require("src.core.game3.pokemon")
  P.install({read=function(_,path) return data._gen3Read(path) end})
  local party={};for i=1,6 do party[i]={species=1,level=7,hp=20} end
  local offered=party[1]
  local trading={party=party,move_overlay={[1]={{frlgMoveId=1}}}}
  local vm={store={vars={}},ctx={specialVars={[0x800D]=0}}}
  local tc={session=trading,vm=vm}
  local row={op="editor_trade",owner="native_integration",trade="TEST"}
  loader.hooks:call("script.command",function() error("Trade command fell through") end,tc,row.op,row)
  assert(trading.party[1]==offered,"Canceled trade changed party")
  vm.ctx.specialVars[0x800D]=1
  loader.hooks:call("script.command",function() error("Trade command fell through") end,tc,row.op,row)
  assert(#trading.party==6 and trading.party[1].species==2 and trading.party[1].level==7)
  assert(trading.party[1].nickname=="LEAF" and trading.party[1].otId==88)
  assert(trading.move_overlay[1]==nil and trading.dex.owned[2])
  local received=trading.party[1]
  vm.ctx.specialVars[0x800D]=1
  loader.hooks:call("script.command",function() end,tc,row.op,row)
  assert(trading.party[1]==received and trading.party[2].species==1,"One-time trade ran twice")
  local createdItem=G.catalog(fresh,"items")[madeItem.id]
  assert(createdItem and createdItem.holdEffectParam==20)
  require("src.core.game3.items_data").install()
  local patient={hp=10,maxHp=100}
  local healed,amount=require("src.core.game3.item_use").healMon({},patient,madeItem.index)
  assert(healed and amount==20 and patient.hp==30,"New medicine did not heal in runtime")
  assert(G.catalog(fresh,"moves")[madeMove.id].effect==3)
  local schema=require("src.core.game3.save_schema_firered")
  local session=schema.newGame({rngSeed=42})
  assert(session.money==12345 and session.storage.items[1].qty==3)
  local rules=require("src.core.game3.battle.rules")
  assert(rules.crit.multiplier()==3)
  local T=require("src.core.game3.battle.types")
  local _,_,mult=T.typeCalc(T.ID.FIRE,T.ID.WATER,T.ID.GRASS,100)
  assert(mult==4 and T.effectiveness(T.ID.FIRE,T.ID.WATER,T.ID.GRASS)==4)
  assert(T.isPhysical(T.ID.FIRE) and T.name(T.ID.FIRE)=="FLAME")
  local marts=require("src.core.game3.marts")
  marts.install(require("Gen3Resources").readTable(data,"data/generated/gba/scripts/marts.lua"))
  local stock=marts.itemsFor(shops[shop].ptr)
  assert(stock[1]==13 and stock[2]==4,"Shop stock did not reach native consumer")
  S.project.items.POTION=nil;A.compile(S.project)
  assert(not S.project.gen3.items.POTION,"Revert left stale native edits")
  require("src.mods.Runtime").reset()
  assert(effects.get("EXP_POISON_EFFECT")~=effects.get("EXP_BURN_EFFECT"))
  assert(rules.crit.multiplier()==2 and schema.newGame({rngSeed=42}).money==3000)
  assert(T.effectiveness(T.ID.FIRE,T.ID.WATER)==0.5 and not T.isPhysical(T.ID.FIRE))
  assert(T.name(T.ID.FIRE)~="FLAME")
  local original=marts.itemsFor(shops[shop].ptr)
  assert(#original==#shops[shop].base,"Disabling mod retained shop override")
end


