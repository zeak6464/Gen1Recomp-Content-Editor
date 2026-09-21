return function(data,root)
  local State,IO=require("State"),require("ModIO")
  local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("roamers_test");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  S.path=root.."/tests/content-editor/gen3-smoke/roamers-project"
  assert(IO.ensureDirectory(S.path));assert(IO.writeText(S.path.."/manifest.json",'{"id":"roamers_test","name":"Roamers test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  local R=require("Gen3Roamers");local row=R.defaults();S.project.gen3Roamers={row}
  for _,map in ipairs(row.maps) do assert(data.maps[map],"Missing roamer map: "..map) end
  R.validate(S.project.gen3Roamers)
  local bad=require("src.mods.Merge").deepCopy(row);bad.maps={};assert(not pcall(R.validate,{bad}))
  local rules=require("Gen3RoamersRuntime");local session={map="FR_ROUTE_1",vars={},flags={},party={}}
  assert(not rules.available(row,session));session.flags[0x844]=true;assert(rules.available(row,session))
  for choice,species in pairs({[0]="ENTEI",[1]="RAIKOU",[2]="SUICUNE"}) do session.vars[0x4031]=choice;assert(rules.species(row,session)==species) end
  session.vars[0x4031]=0
  row.maps={"FR_ROUTE_1","FR_ROUTE_2"};row.chance=100
  assert(IO.save(S.path,S.project));assert(IO.load(S.path).gen3Roamers[1].chance==100)
  local fresh={};require("Gen3").load(fresh,data._gen3Read);local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local RT=require("src.mods.Runtime");local F=require("src.core.game3.field");local old=F._session;F._session=session
  local rng=require("src.core.game3.rng");local random=rng.Random;rng.Random=function() return 0 end
  local E=require("src.core.game3.encounters");local land=E.rollLand;E.rollLand=function() return {species=16,level=3} end
  local e=E.onStep("FR_ROUTE_1","land");assert(e._editorRoamer and e.species==244)
  assert(not E.onStep("FR_ROUTE_2","land")._editorRoamer,"Roamer appeared on wrong map")
  local Party=require("src.core.game3.party");assert(Party.giveMon(session,1,60));session.vars[0x4020]=10
  assert(not E.onStep("FR_ROUTE_1","land")._editorRoamer,"Repel ignored higher level lead")
  session.vars[0x4020]=0
  RT.emit("map.entered",{mapId="FR_ROUTE_2"})
  assert(session.modData.roamers_test.roamers.kanto_beast.map=="FR_ROUTE_2")
  local e2=E.onStep("FR_ROUTE_2","land");assert(e2._editorRoamer)
  local battle
  local function start(_,_,foe)
    battle=require("src.core.game3.battle.state").new({wild=true,playerParty=session.party,foeMon=foe})
    RT.emit("battle.started",{battle=battle,kind="wild"});return true
  end
  assert(RT.call("editor.gen3.roamers.start",start,nil,nil,e2,{}))
  local saved=session.modData.roamers_test.roamers.kanto_beast
  local personality=saved.mon.personality;local iv=saved.mon.ivs.atk
  battle.enemy.mon.hp=30;battle.enemy.mon.status="PAR"
  RT.emit("battle.ended",{battle=battle,result="run"})
  assert(saved.mon.hp==30 and saved.mon.status=="PAR" and not saved.finished)
  assert(saved.map=="FR_ROUTE_1")
  local encoded=require("src.link.Json").encode(session.modData)
  session.modData=require("src.link.Json").decode(encoded);saved=session.modData.roamers_test.roamers.kanto_beast
  assert(saved.mon.personality==personality and saved.mon.hp==30,"Save lost roamer state")
  e=E.onStep("FR_ROUTE_1","land");assert(RT.call("editor.gen3.roamers.start",start,nil,nil,e,{}))
  assert(battle.enemy.mon.hp==30 and battle.enemy.mon.personality==personality and battle.enemy.mon.ivs.atk==iv,"Re-encounter rerolled roamer")
  local engine=require("src.core.game3.battle.engine");local ad=require("src.core.game3.battle.adapter").new(battle)
  battle.enemy.escapePrevention=true
  engine.collectResidualEvents(battle,ad);assert(not battle.over,"Trapped roamer escaped")
  battle.enemy.escapePrevention=nil
  engine.collectResidualEvents(battle,ad);assert(battle.over and battle.result=="run","Roamer did not flee after turn")
  RT.emit("pokemon.caught",{battle=battle,mon=battle.enemy.mon})
  RT.emit("battle.ended",{battle=battle,result="caught"});assert(saved.finished=="caught")
  assert(not E.onStep(saved.map,"land")._editorRoamer,"Caught roamer returned")
  saved.finished=nil;saved.map="FR_ROUTE_1"
  assert(RT.call("editor.gen3.roamers.start",start,nil,nil,E.onStep("FR_ROUTE_1","land"),{}))
  battle.enemy.mon.hp=0;RT.emit("battle.ended",{battle=battle,result="win"});assert(saved.finished=="defeated")
  -- Exercise the real start/finish path, including persistence after an actual
  -- headless battle, instead of only testing manually delivered events.
  saved.finished=nil;saved.map="FR_ROUTE_1";saved.mon.hp=saved.mon.maxHp;saved.mon.status=nil
  saved.mon.moves={150};saved.mon.pp={40}
  session.party[1].moves={150};session.party[1].pp={40};session.party[1].hp=session.party[1].maxHp
  local NativeRuntime=require("src.core.game3.runtime");local oldNative=NativeRuntime.session;NativeRuntime.session=session
  local B=require("src.core.game3.battle");local Bridge=require("src.core.game3.battle_bridge")
  assert(Bridge.startWild(nil,{save={},data=fresh},E.onStep("FR_ROUTE_1","land"),{headless=true,fade=false}))
  assert(B.runToEnd()=="run" and not B.isActive(),"Native roaming battle did not finish by fleeing")
  assert(saved.map=="FR_ROUTE_2" and not saved.finished,"Native battle end did not update roamer")
  NativeRuntime.session=oldNative
  RT.reset();assert(not E.onStep("FR_ROUTE_1","land")._editorRoamer,"Disabled mod left roaming hook active")
  E.rollLand=land;rng.Random=random;F._session=old
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  S.g3EncounterSection="roamers";require("Gen3EncounterForms").draw(S,20,20,1320,810,{markDirty=function() end})
  K.endFrame();K.beginFrame(0,0,false,0);love.graphics.clear(.04,.06,.12,1)
  require("Gen3EncounterForms").draw(S,20,20,1320,810,{markDirty=function() end})
  K.endFrame();love.graphics.setCanvas();assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/roamers-editor.png",canvas:newImageData():encode("png"):getString()))
end
