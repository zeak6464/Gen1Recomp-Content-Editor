return function(data,root,mount,game)
  local IO=require("ModIO");local copy=require("src.mods.Merge").deepCopy
  local S=require("State").new();S.data=data;S.version=game
  S.project=require("State").blankProject("form_rules_test");S.project.game=game
  require("Gen3Workbench").prepare(S)
  local F=require("Gen3Forms")
  local _,rec=F.add(S,"PIKACHU","Attack form");rec.baseStats.attack=180
  local f=S.project.gen3Forms.PIKACHU;f.mode="rules"
  f.rules={{trigger="move_hit",move="TACKLE",target=2,from=1,duration="switch"},{trigger="move_hit",move="TACKLE",target=1,from=2,duration="switch"}}
  local _,known=F.add(S,"EEVEE","Known move form")
  S.project.gen3Forms.EEVEE.mode="rules";S.project.gen3Forms.EEVEE.rules={{trigger="knows_move",move="GROWL",target=2}}
  local _,itemform=F.add(S,"CHARMANDER","Item form")
  S.project.gen3Forms.CHARMANDER.mode="rules";S.project.gen3Forms.CHARMANDER.rules={{trigger="item_use",item="POTION",target=2,consume=true},{trigger="item_use",item="ANTIDOTE",target=1}}
  local _,hpform=F.add(S,"SQUIRTLE","Low HP form")
  S.project.gen3Forms.SQUIRTLE.mode="rules";S.project.gen3Forms.SQUIRTLE.rules={{trigger="hp_below",percent=50,target=2,duration="battle"},{trigger="hp_above",percent=50,target=1,duration="battle"}}
  local _,hero=F.add(S,"BULBASAUR","Switch form")
  S.project.gen3Forms.BULBASAUR.mode="rules";S.project.gen3Forms.BULBASAUR.rules={{trigger="switch_out",target=2,duration="battle"}}
  local _,turnform=F.add(S,"MEOWTH","Turn form")
  S.project.gen3Forms.MEOWTH.mode="rules";S.project.gen3Forms.MEOWTH.rules={{trigger="turn_end",from=1,target=2},{trigger="turn_end",from=2,target=1}}
  local _,weatherform=F.add(S,"JIGGLYPUFF","Sunny form")
  S.project.gen3Forms.JIGGLYPUFF.mode="rules";S.project.gen3Forms.JIGGLYPUFF.rules={{trigger="weather",weather="SUN",target=2},{trigger="weather",weather="NONE",target=1}}
  local _,stance=F.add(S,"ZUBAT","Attack stance")
  S.project.gen3Forms.ZUBAT.mode="rules";S.project.gen3Forms.ZUBAT.rules={{trigger="damaging_move",target=2},{trigger="move_used",move="GROWL",target=1}}
  local _,hurt=F.add(S,"GEODUDE","Damaged form")
  S.project.gen3Forms.GEODUDE.mode="rules";S.project.gen3Forms.GEODUDE.rules={{trigger="damage_taken",target=2}}
  local _,koform=F.add(S,"RATTATA","KO form")
  S.project.gen3Forms.RATTATA.mode="rules";S.project.gen3Forms.RATTATA.rules={{trigger="knockout",target=2,duration="battle"}}
  S.path=root.."/tests/content-editor/form-rules-smoke/project";IO.ensureDirectory(S.path)
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"form_rules_test","name":"Form rules test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(IO.save(S.path,S.project));assert(mount(S.path,"mods/form_rules_test",1)~=0)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  assert(#fresh._editorGen3Report.rejected==0,"Export rejected")
  local P=require("src.core.game3.pokemon");P.install(P._cache)
  local function mon(species,moves)
    local m={species=species,level=40,personality=1,moves=moves or {33},pp={35},ivs={},evs={}}
    P.applyStats(m);return m
  end
  local eevee=mon(133,{45});assert(eevee.species==known.index)
  assert(require("src.core.game3.move_learn").forgetMove(eevee,0));assert(eevee.species==133)
  assert(P.teachMove(eevee,45));assert(eevee.species==known.index)
  assert(P.replaceMove(eevee,1,33));assert(eevee.species==133)
  local Bag=require("src.core.game3.bag");local Use=require("src.core.game3.item_use")
  local bag=Bag.new();Bag.add(bag,data.items.POTION.index,2);Bag.add(bag,data.items.ANTIDOTE.index,1)
  local char=mon(4);local session={party={char},bag=bag}
  assert(Use.useField(session,bag,data.items.POTION.index,1));assert(char.species==itemform.index)
  assert(not Bag.has(bag,data.items.POTION.index,2));assert(Use.useField(session,bag,data.items.ANTIDOTE.index,1));assert(char.species==4)
  local State=require("src.core.game3.battle.state");local Engine=require("src.core.game3.battle.engine")
  local Adapter=require("src.core.game3.battle.adapter");local Runtime=require("src.mods.Runtime")
  local function battle(species)
    local st=State.new({playerParty={mon(species),mon(1)},foeMon=mon(113),wild=true,rng=function(a,b) return a end})
    st.enemy.mon.hp=999;st.enemy.mon.maxHp=999
    return st,Adapter.new(st,function() end)
  end
  local st,ad=battle(25);local attack=st.player.mon.attack;local hp=st.player.mon.maxHp
  Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  assert(st.player.species==rec.index,"Successful move did not transform")
  assert(st.player.mon.attack>attack and st.player.mon.species==25 and st.player.mon.maxHp==hp)
  assert(st.player.mon.pp[1]==34,"Move PP changed incorrectly")
  Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  assert(st.player.species==25,"Second successful move did not toggle")
  Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  Engine.performSwitch(st,ad,0,2);Engine.performSwitch(st,ad,0,1)
  assert(st.player.species==25,"Switch did not revert form")
  st.enemy.type1=7;st.enemy.type2=nil -- Ghost immunity: Tackle must not trigger.
  Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  assert(st.player.species==25,"Immune move triggered form")
  st,ad=battle(7);st.player.mon.hp=math.floor(st.player.mon.maxHp/2)
  Engine.battleStartEffects(st,ad);assert(st.player.species==hpform.index)
  st.player.mon.hp=st.player.mon.maxHp;Runtime.emit("battle.turn_ended",{battle=st,turn=1});assert(st.player.species==7)
  st,ad=battle(1);Engine.performSwitch(st,ad,0,2);Engine.performSwitch(st,ad,0,1);assert(st.player.species==hero.index)
  Runtime.emit("battle.ended",{battle=st});assert(st.player.species==1)
  st,ad=battle(52);Runtime.emit("battle.turn_ended",{battle=st,turn=1});assert(st.player.species==turnform.index)
  Runtime.emit("battle.turn_ended",{battle=st,turn=2});assert(st.player.species==52)
  st,ad=battle(39);st.weather="SUN";Engine.battleStartEffects(st,ad);assert(st.player.species==weatherform.index)
  st.weather=nil;Engine.afterAction(st,ad);assert(st.player.species==39)
  st,ad=battle(41);Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{});assert(st.player.species==stance.index)
  st.player.mon.moves={45};Engine.resolveMove(st.player,st.enemy,45,1,ad,st,{},{});assert(st.player.species==41)
  st,ad=battle(74);Engine.resolveMove(st.enemy,st.player,33,1,ad,st,{},{});assert(st.player.species==hurt.index)
  st,ad=battle(19);st.enemy.mon.hp=1;Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{});assert(st.player.species==koform.index)
  local Battle=require("src.core.game3.battle")
  local original=mon(25);local completed=false
  assert(Battle.start({playerParty={original},foe=mon(113),wild=true,headless=true,autoFight=false,onDone=function()
    completed=true;assert(original.species==25);assert(original.attack==P.calcStats(25,40,{}, {},1).attack,"Cleanup left form stats")
  end}))
  local live=Battle.getState();live.rng=function(a,b) return a end;local liveAd=Adapter.new(live,function() end)
  Engine.resolveMove(live.player,live.enemy,33,1,liveAd,live,{},{});assert(live.player.species==rec.index,"Live form="..tostring(live.player.species).." hp="..tostring(live.enemy.mon.hp))
  Battle.abort("run");assert(completed,"Battle completion not called")
  local invalid=copy(f);invalid.rules[1].target=999;assert(not pcall(require("Gen3FormRules").validate,invalid))
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,1500)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,1500);K.beginFrame(0,0,false,0)
  S.g3FormSelection={PIKACHU=2};F.draw(S,data.pokemon.PIKACHU,20,20,1280,{markDirty=function() error("Browsing edited rules") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/form-rules-smoke/forms.png",canvas:newImageData():encode("png"):getString()))
  Runtime.reset()
end


