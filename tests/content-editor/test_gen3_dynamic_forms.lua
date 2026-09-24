return function(data,root,mount,game)
  local IO=require("ModIO");local G=require("Gen3");local copy=require("src.mods.Merge").deepCopy
  local S=require("State").new();S.data=data;S.version=game
  S.project=require("State").blankProject("dynamic_forms_test");S.project.game=game
  require("Gen3Workbench").prepare(S)
  local F=require("Gen3Forms")
  local itemRow,itemMon=F.add(S,"PIKACHU","Orb form");itemRow.item="POTION"
  S.project.gen3Forms.PIKACHU.mode="held_item";itemMon.baseStats.attack=120;itemMon.baseStats.hp=80
  local genderRow,genderMon=F.add(S,"EEVEE","Female");genderRow.gender="F";S.project.gen3Forms.EEVEE.mode="gender"
  S.project.types.FAIRY={id="FAIRY",name="Fairy",index=18,category="special",_isNew=true}
  S.project.type_matchups["FAIRY>DRAGON"]=20;S.project.type_matchups["DRAGON>FAIRY"]=0
  itemMon.types={"FAIRY"}
  S.project.moves.TACKLE=copy(data.moves.TACKLE);S.project.moves.TACKLE.type="FAIRY"
  assert(require("Gen3Types").nextIndex(S.project)==19)
  S.path=root.."/tests/content-editor/dynamic-forms-smoke/project";IO.ensureDirectory(S.path)
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"dynamic_forms_test","name":"Dynamic forms test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(IO.save(S.path,S.project));local saved=assert(IO.load(S.path));assert(saved.pokemon[itemRow.species].types[1]=="FAIRY")
  assert(mount(S.path,"mods/dynamic_forms_test",1)~=0)
  local fresh={};G.load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  assert(#fresh._editorGen3Report.rejected==0,"Exported content rejected")
  local P=require("src.core.game3.pokemon");P.install(P._cache)
  local T=require("src.core.game3.battle.types")
  assert(T.name(18)=="Fairy" and not T.isPhysical(18))
  assert(T.effectiveness(18,T.ID.DRAGON)==2 and T.effectiveness(T.ID.DRAGON,18)==0)
  assert(P.types(itemMon.index)[1]==18,"Custom type lost on species reload")
  assert(fresh.gen3Moves.rom.moves[data.moves.TACKLE.index].type==18,"Custom move type lost")
  local mon={species=25,level=40,personality=1,moves={33},pp={12},ivs={},evs={}}
  P.applyStats(mon);local normalMax=mon.maxHp;mon.hp=normalMax-10
  mon.item=data.items.POTION.index;mon.heldItem=mon.item;P.applyStats(mon)
  assert(mon.species==itemMon.index and mon.hp==mon.maxHp-10 and mon.moves[1]==33 and mon.pp[1]==12)
  local formed=copy(mon);P.applyStats(formed);assert(formed.species==itemMon.index)
  mon.item=nil;mon.heldItem=nil;P.applyStats(mon)
  assert(mon.species==25 and mon.maxHp==normalMax and mon.hp==normalMax-10)
  mon.hp=0;mon.item=data.items.POTION.index;P.applyStats(mon);assert(mon.hp==0,"Form revived a fainted Pokemon")
  local female={species=133,level=20,personality=0};P.applyStats(female);assert(female.species==genderMon.index)
  local male={species=133,level=20,personality=255};P.applyStats(male);assert(male.species==133)
  local egg={species=133,level=5,personality=0,isEgg=true};P.applyStats(egg);assert(egg.species==133)
  local Bag=require("src.core.game3.bag");local bag=Bag.new();assert(Bag.add(bag,data.items.POTION.index,1))
  require("src.core.game3.rom_text").overrides=data.text
  local Items=require("src.core.game3.items_data");Items.installPack(require("Gen3Resources").readTable(data,"data/generated/gba/items/pack.lua"))
  local session={party={male},bag=bag};male.species=25;male.hp=nil;P.applyStats(male)
  local Use=require("src.core.game3.item_use")
  assert(Use.giveToMon(session,bag,data.items.POTION.index,1));assert(male.species==itemMon.index)
  assert(Use.takeFromMon(session,bag,1));assert(male.species==25)
  local invalid=copy(S.project);invalid.gen3Forms.EEVEE.forms[2].gender=nil
  assert(not pcall(F.emit,invalid,require("ModWriter").encodeLua,{}),"Missing gender accepted")
  invalid=copy(S.project);invalid.types.OTHER={index=18};assert(not pcall(require("Gen3Types").ids,invalid))
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,1000)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,1000);K.beginFrame(0,0,false,0)
  S.g3FormSelection={PIKACHU=2};F.draw(S,data.pokemon.PIKACHU,20,20,1280,{markDirty=function() error("Browsing edited forms") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/dynamic-forms-smoke/forms.png",canvas:newImageData():encode("png"):getString()))
  local badge=love.graphics.newCanvas(160,60)
  love.graphics.setCanvas(badge);love.graphics.clear(0,0,0,0);love.graphics.push();love.graphics.scale(4,4)
  require("src.ui.game3.summary_chrome").drawTypeBadge(18,2,1)
  love.graphics.pop();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/dynamic-forms-smoke/type-badge.png",badge:newImageData():encode("png"):getString()))
  require("src.mods.Runtime").reset()
end
