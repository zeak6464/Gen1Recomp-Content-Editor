return function(data,root,mount,game)
  local IO=require("ModIO");local copy=require("src.mods.Merge").deepCopy
  local S=require("State").new();S.data=data;S.version=game
  S.project=require("State").blankProject("fusion_test");S.project.game=game
  require("Gen3Workbench").prepare(S)
  local F=require("Gen3Forms")
  -- Existing species serve as fixtures; recipes support custom species identically.
  local white,w=F.add(S,"PIKACHU","White fusion");white.partner="EEVEE";w.baseStats.attack=140
  local black,b=F.add(S,"PIKACHU","Black fusion");black.partner="CHARMANDER";b.baseStats.attack=150
  white.moveChanges={{move="TACKLE",replacement="SCRATCH"}}
  local ultra,u=F.add(S,"PIKACHU","Ultra fusion");ultra.mechanic={kind="ultra",from=2}
  local family=S.project.gen3Forms.PIKACHU;family.mode="fusion"
  family.fusionItem=require("Gen3Fusion").createItem(S)
  local item=S.project.items[family.fusionItem].index
  S.path=root.."/tests/content-editor/fusion-smoke/project";IO.ensureDirectory(S.path)
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"fusion_test","name":"Fusion test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(IO.save(S.path,S.project));assert(mount(S.path,"mods/fusion_test",1)~=0)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  assert(#fresh._editorGen3Report.rejected==0,"Export rejected")
  local P=require("src.core.game3.pokemon");P.install(P._cache)
  local Bag=require("src.core.game3.bag");local bag=Bag.new();assert(Bag.add(bag,item,1))
  local Use=require("src.core.game3.item_use");assert(Use.needsPartyTarget(item))
  local Serializer=require("src.core.SaveSerializer")
  local function mon(species)
    local m={species=species,level=40,personality=1,nickname="Individual",moves={33},pp={12},ivs={hp=21},evs={attack=32},otId=123}
    P.applyStats(m);m.hp=m.maxHp-10;return m
  end
  local base,partner=mon(25),mon(133);partner.item=data.items.POTION.index
  local original=Serializer.encode(partner)
  local overlay={[1]={33},[2]={44}}
  local session={party={partner,base},bag=bag,moveOverlay=overlay,move_overlay=overlay}
  assert(not Use.useField(session,bag,item,2,nil,2));assert(#session.party==2)
  assert(Use.useField(session,bag,item,2,nil,1));assert(#session.party==1 and session.party[1]==base)
  assert(base.species==w.index and base.hp==base.maxHp-10 and base.pp[1]==12)
  assert(base.moves[1]==10,"Fusion signature move not applied")
  local BattleState=require("src.core.game3.battle.state")
  local st=BattleState.new({playerParty=session.party,foeMon=mon(1),wild=true})
  assert(require("src.mods.Runtime").call("editor.gen3.advanced.activate",function() return false end,st,st.player,"ultra"))
  assert(st.player.species==u.index and base._editorFusion.partner.species==133)
  require("src.mods.Runtime").emit("battle.ended",{battle=st});assert(st.player.species==w.index)
  assert(overlay[1][1]==44 and overlay[2]==nil,"Overlay removal failed")
  assert(Bag.has(bag,item,1),"Fusion consumed key item")
  P.applyStats(base);assert(base.species==w.index,"Stats reset fusion")
  session=assert(Serializer.decode(Serializer.encode(session)));base=session.party[1]
  local Trade=require("src.core.game3.scripting.natives_trade")
  assert(not Trade.tradeMons(session,0,mon(4)),"Trading lost partner")
  assert(not require("src.core.game3.daycare").deposit(session,1),"Daycare accepted fusion")
  for i=2,6 do session.party[i]=mon(1) end
  assert(not Use.useField(session,bag,item,1));assert(base._editorFusion)
  for i=6,2,-1 do session.party[i]=nil end
  assert(Use.useField(session,bag,item,1));assert(base.species==25 and not base._editorFusion)
  assert(base.moves[1]==33,"Separation did not restore signature move")
  assert(Serializer.encode(session.party[2])==original,"Partner changed across save/fusion")
  assert(session.moveOverlay[2][1]==33)
  session.party[2]=mon(4)
  assert(Use.useField(session,bag,item,1,nil,2));assert(base.species==b.index)
  assert(Use.useField(session,bag,item,1));assert(session.party[2].species==4)
  session.party[2].isEgg=true
  assert(not Use.useField(session,bag,item,1,nil,2));assert(#session.party==2)
  session.party[2].isEgg=nil;session.party[2].species=1
  assert(not Use.useField(session,bag,item,1,nil,2))
  local invalid=copy(S.project);invalid.gen3Forms.PIKACHU.forms[3].partner="EEVEE"
  assert(not pcall(F.emit,invalid,require("ModWriter").encodeLua,{}))
  session.party={mon(25),mon(133)}
  local Menu=require("src.ui.game3.party_menu")
  local closed=0
  local function show() Menu.show(session.party,nil,{session=session,bag=bag,item=item,mode="use",onClose=function() closed=closed+1 end}) end
  show();Menu._onSelect(1);Menu.dismissMessage()
  assert(Menu.mode=="use" and #session.party==2)
  Menu._onSelect(nil);assert(closed==1 and #session.party==2,"Cancel changed party")
  show();Menu._onSelect(1);Menu.dismissMessage();Menu._onSelect(2);Menu.dismissMessage()
  assert(closed==2 and #session.party==1 and session.party[1].species==w.index)
  assert(require("src.core.game3.evolution").targetSpecies(session.party[1],0)==0)
  local Storage=require("src.core.game3.storage");local storage=Storage.ensure(session)
  storage.boxes[1].mons[1]=session.party[1]
  assert(not Storage.releaseMon(session,1,1),"Release discarded stored partner")
  storage.boxes[1].mons[1]=nil
  show();Menu._onSelect(1);Menu.dismissMessage();assert(closed==3 and #session.party==2)
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,1000)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,1000);K.beginFrame(0,0,false,0)
  S.g3FormSelection={PIKACHU=2};F.draw(S,data.pokemon.PIKACHU,20,20,1280,{markDirty=function() error("Browsing edited forms") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/fusion-smoke/forms.png",canvas:newImageData():encode("png"):getString()))
  require("src.mods.Runtime").reset()
end
