return function(data,root,mount,game)
  local IO=require("ModIO");local S=require("State").new();S.data=data;S.version=game
  S.project=require("State").blankProject("advanced_forms_test");S.project.game=game;require("Gen3Workbench").prepare(S)
  local F=require("Gen3Forms");local forms={}
  local function add(id,kind,extra)
    local row,rec=F.add(S,id,kind.." form");row.mechanic=extra or {};row.mechanic.kind=kind;row.mechanic.from=1
    S.project.gen3Forms[id].mode="rules";forms[kind]=rec;return rec,row
  end
  add("PIKACHU","mega",{item="POTION",swapFrom="TACKLE",swapTo="SCRATCH"}).baseStats.attack=180
  add("EEVEE","dynamax")
  add("CHARMANDER","tera",{teraType="WATER"})
  add("SQUIRTLE","disguise")
  add("BULBASAUR","ice_face")
  add("MEOWTH","gulp",{move="SURF",payload="paralysis"})
  add("GEODUDE","power_construct").baseStats.hp=200
  add("ZUBAT","primal",{item="POTION"})
  add("RATTATA","ultra")
  add("JIGGLYPUFF","gigantamax",{maxType="NORMAL",maxMove="SCRATCH"})
  add("SANDSHREW","tera",{teraType="STELLAR",teraBlast="SWIFT"})
  local fieldForms={}
  for _,v in ipairs({{"ODDISH","map",{map="TEST_MAP"}},{"PSYDUCK","hour",{startHour=20,endHour=6}},{"POLIWAG","season",{season=3}},{"ABRA","nature",{nature=1}},{"MACHOP","personality",{modulus=100,remainder=1}},{"PONYTA","flag",{flag=99}},{"SLOWPOKE","grooming",{item="ANTIDOTE",days=5}}}) do
    local row,rec=F.add(S,v[1],v[2].." form");row.fieldRule=v[3];row.fieldRule.kind=v[2];fieldForms[v[2]]=rec
  end
  local high=require("Gen3ContentAdapter").newRecord(S,"pokemon","HIGH_SPECIES");high.index=2048;S.project.pokemon.HIGH_SPECIES=high
  S.path=root.."/tests/content-editor/advanced-forms-smoke/project";IO.ensureDirectory(S.path)
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"advanced_forms_test","name":"Advanced forms test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(IO.save(S.path,S.project));assert(mount(S.path,"mods/advanced_forms_test",1)~=0)
  local fresh={};require("Gen3").load(fresh,data._gen3Read);local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  assert(#fresh._editorGen3Report.rejected==0,"Export rejected")
  local P=require("src.core.game3.pokemon");P.install(P._cache)
  local State=require("src.core.game3.battle.state");local Engine=require("src.core.game3.battle.engine");local Adapter=require("src.core.game3.battle.adapter")
  local Runtime=require("src.mods.Runtime");local Damage=require("src.core.game3.battle.damage")
  local function mon(id,moves)
    local m={species=id,level=40,personality=1,moves=moves or {33},pp={35},ivs={},evs={}};P.applyStats(m);return m
  end
  local function battle(id)
    local st=State.new({playerParty={mon(id),mon(id)},foeMon=mon(113),wild=true,rng=function(a,b) return a end})
    st.enemy.mon.hp=999;st.enemy.mon.maxHp=999;return st,Adapter.new(st,function() end)
  end
  local function activate(st,kind) return Runtime.call("editor.gen3.advanced.activate",function() error("Missing activation hook") end,st,st.player,kind) end
  local highMon=mon(2048);assert(highMon.species==2048 and highMon.maxHp>0,"Expanded species index failed")
  local env={party={mon(43),mon(54),mon(60),mon(63),mon(66),mon(77)},editorFormEnvironment={map="TEST_MAP",hour=23,season=3,now=1000},flags={[99]=true}}
  Runtime.call("editor.gen3.forms.environment",function() error("Missing environment hook") end,env)
  for i,kind in ipairs({"map","hour","season","nature","personality","flag"}) do assert(env.party[i].species==fieldForms[kind].index,"Field rule failed: "..kind) end
  env.editorFormEnvironment.map="OTHER";env.editorFormEnvironment.hour=12;env.editorFormEnvironment.season=1;env.flags[99]=nil
  Runtime.call("editor.gen3.forms.environment",function() end,env);assert(env.party[1].species==43 and env.party[2].species==54 and env.party[3].species==60 and env.party[6].species==77)
  local Bag=require("src.core.game3.bag");local bag=Bag.new();Bag.add(bag,data.items.ANTIDOTE.index,1)
  local groom={party={mon(79)},bag=bag,editorFormEnvironment={now=1000}}
  assert(require("src.core.game3.item_use").useField(groom,bag,data.items.ANTIDOTE.index,1));assert(groom.party[1].species==fieldForms.grooming.index)
  local serial=require("src.core.SaveSerializer");groom=assert(serial.decode(serial.encode(groom)))
  groom.editorFormEnvironment.now=1000+5*86400;Runtime.call("editor.gen3.forms.environment",function() end,groom);assert(groom.party[1].species==79,"Grooming did not expire")
  local st,ad=battle(25);assert(not activate(st,"mega"),"Held prerequisite ignored")
  st.player.item=data.items.POTION.index;assert(activate(st,"mega"));assert(st.player.species==forms.mega.index and st.player.mon.moves[1]==10)
  Engine.performSwitch(st,ad,0,2);st.player.item=data.items.POTION.index;assert(not activate(st,"mega"),"Second Mega allowed")
  Engine.performSwitch(st,ad,0,1);assert(st.player.species==forms.mega.index)
  Runtime.emit("battle.ended",{battle=st});assert(st.player.species==25 and st.player.mon.moves[1]==33)
  st,ad=battle(133);local max,hp=st.player.mon.maxHp,st.player.mon.hp;assert(activate(st,"dynamax"));assert(st.player.mon.maxHp==max*2)
  local result=Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  assert(st.enemy.stages.speed==-1,"Max Strike effect missing: "..table.concat(result," | ").." hp="..tostring(st.enemy.mon.hp));assert(st.player.mon.pp[1]==34,"Max move PP not deducted")
  st.player.mon.hp=st.player.mon.hp-11
  for turn=1,3 do Runtime.emit("battle.turn_ended",{battle=st,turn=turn}) end
  assert(st.player.species==133 and st.player.mon.maxHp==max and st.player.mon.hp==math.ceil((hp*2-11)/2),"Dynamax expiration incorrect")
  assert(not activate(st,"dynamax"),"Second Dynamax allowed")
  st,ad=battle(4);st.session={};assert(activate(st,"tera"));assert(st.player.type1==11 and st.player.type2==nil and st.session.meta.editorTeraSpent)
  local _,info=Damage.calc(st.player,st.enemy,52,{adapter=ad,noRandom=true,noCrit=true});assert(info.stab==1.5,"Lost original Fire STAB")
  _,info=Damage.calc(st.player,st.enemy,55,{adapter=ad,noRandom=true,noCrit=true});assert(info.stab==1.5,"Missing new Water STAB")
  Runtime.emit("battle.ended",{battle=st});assert(st.player.species==4 and st.player.type1==10)
  st,ad=battle(27);assert(activate(st,"tera"));assert(st.player.type1==4,"Stellar changed defensive typing")
  _,info=Damage.calc(st.player,st.enemy,89,{adapter=ad,noRandom=true,noCrit=true});assert(info.stab==2,"Missing initial Stellar original-type boost")
  st.player.mon.moves={89};Engine.resolveMove(st.player,st.enemy,89,1,ad,st,{},{})
  _,info=Damage.calc(st.player,st.enemy,89,{adapter=ad,noRandom=true,noCrit=true});assert(info.stab==1.5,"Stellar boost was not consumed")
  st,ad=battle(27);assert(activate(st,"tera"));st.player.mon.moves={129};local stellarLog=Engine.resolveMove(st.player,st.enemy,129,1,ad,st,{},{})
  assert(st.player.stages.attack==-1 and st.player.stages.spAtk==-1,"Stellar Tera Blast stat drops missing: "..table.concat(stellarLog," | ").." hp="..st.enemy.mon.hp.." atk="..tostring(st.player.stages.attack).." spa="..tostring(st.player.stages.spAtk))
  st,ad=battle(133);assert(activate(st,"dynamax"));st.enemy.expProtected=true
  local before=st.enemy.mon.hp;Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  assert(st.enemy.mon.hp<before and st.player.mon.pp[1]==34,"Max attack failed through ordinary Protect")
  st.enemy._editorMaxGuard=true;before=st.enemy.mon.hp;Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{})
  assert(st.enemy.mon.hp==before and st.player.mon.pp[1]==33,"Max Guard did not block while consuming PP")
  st,ad=battle(7);hp=st.player.mon.hp;max=st.player.mon.maxHp
  Engine.resolveMove(st.enemy,st.player,33,1,ad,st,{},{})
  assert(st.player.species==forms.disguise.index and st.player.mon.hp==hp-math.max(1,math.floor(max/8)),"Disguise did not intercept hit")
  hp=st.player.mon.hp;Engine.resolveMove(st.enemy,st.player,33,1,ad,st,{},{});assert(st.player.mon.hp<hp,"Disguise blocked twice")
  st,ad=battle(1);hp=st.player.mon.hp;Engine.resolveMove(st.enemy,st.player,33,1,ad,st,{},{});assert(st.player.species==forms.ice_face.index and st.player.mon.hp==hp)
  st.weather="HAIL";Engine.afterAction(st,ad);assert(st.player.species==1,"Ice Face did not restore in new hail")
  st,ad=battle(52);st.player.mon.moves={57};Engine.resolveMove(st.player,st.enemy,57,1,ad,st,{},{});assert(st.player.species==forms.gulp.index)
  hp=st.enemy.mon.hp;Engine.resolveMove(st.enemy,st.player,33,1,ad,st,{},{});assert(st.player.species==52 and st.enemy.mon.hp<hp and st.enemy.status=="PAR")
  st,ad=battle(74);max=st.player.mon.maxHp;st.player.mon.hp=math.floor(max/2);hp=st.player.mon.hp
  Runtime.emit("battle.turn_ended",{battle=st,turn=1});assert(st.player.species==forms.power_construct.index and st.player.mon.hp==hp+st.player.mon.maxHp-max)
  Engine.performSwitch(st,ad,0,2);Engine.performSwitch(st,ad,0,1);assert(st.player.mon.maxHp>max,"Lost transformed maximum HP on switch")
  Runtime.emit("battle.ended",{battle=st});assert(st.player.mon.maxHp==max)
  st,ad=battle(41);st.player.item=data.items.POTION.index;Engine.battleStartEffects(st,ad);assert(st.player.species==forms.primal.index)
  st,ad=battle(19);assert(activate(st,"ultra"));assert(st.player.species==forms.ultra.index)
  st,ad=battle(39);assert(activate(st,"gigantamax"));Engine.resolveMove(st.player,st.enemy,33,1,ad,st,{},{});assert(st.player.mon.pp[1]==34)
  local Ui=require("src.core.game3.battle.ui");st,ad=battle(19);Ui._st=st;Ui._mode="moves";Ui._active=0;Ui._showing=false
  Ui.handleInput({wasPressed=function(_,key) return key=="select" end});assert(st._editorAdvanced.requests[0],"SELECT did not queue transformation")
  Engine.planTurnFromActions(st,ad,{kind="move",move=33,slot=1},{kind="move",move=33,slot=1});assert(st.player.species==forms.ultra.index)
  local Battle=require("src.core.game3.battle");local original=mon(133);local originalMax=original.maxHp;local completed=false
  assert(Battle.start({playerParty={original},foe=mon(113),wild=true,headless=true,autoFight=false,onDone=function()
    completed=true;assert(original.maxHp==originalMax and original.hp<=originalMax,"Giant HP leaked into completion callback")
  end}))
  local live=Battle.getState();assert(activate(live,"dynamax"));assert(original.maxHp==originalMax*2)
  Battle.abort("run");assert(completed,"Advanced cleanup callback not reached")
  for _,rule in ipairs({{kind="hour",startHour=24},{kind="season",season=5},{kind="nature",nature=-1},{kind="grooming",item="POTION",days=0}}) do
    assert(not pcall(require("Gen3FieldForms").validate,{forms={{fieldRule=rule}}}),"Invalid field rule accepted")
  end
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,1800)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,1800);K.beginFrame(0,0,false,0)
  S.g3FormSelection={CHARMANDER=2};F.draw(S,data.pokemon.CHARMANDER,20,20,1280,{markDirty=function() error("Browsing edited advanced forms") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/advanced-forms-smoke/forms.png",canvas:newImageData():encode("png"):getString()))
  Runtime.reset()
end

