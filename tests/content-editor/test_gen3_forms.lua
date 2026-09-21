return function(data,root,mount)
  local State,IO=require("State"),require("ModIO")
  local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("forms_test");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  S.path=root.."/tests/content-editor/gen3-smoke/forms-project"
  IO.ensureDirectory(S.path);assert(IO.writeText(S.path.."/manifest.json",'{"id":"forms_test","name":"Forms test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  local Forms=require("Gen3Forms")
  local K,C=require("Kit"),require("ChoicePicker")
  local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});K.layout(1360,860);K.beginFrame(0,0,false,0)
  for i=1,28 do
    S.g3NativeUnown=i
    Forms.draw(S,data.pokemon.UNOWN,20,20,1320,{markDirty=function() error("Browsing native forms changed the project") end})
    assert(S._nativeUnownPictures[i] and #S._nativeUnownPictures[i]==4,"Missing native Unown artwork")
  end
  for i=1,4 do
    S.g3NativeForms.CASTFORM=i;Forms.draw(S,data.pokemon.CASTFORM,20,20,1320,{markDirty=function() error("Browsing changed project") end})
    assert(S._nativeFormPictures["CASTFORM"..i] and #S._nativeFormPictures["CASTFORM"..i]==4,"Missing Castform sprites")
  end
  for i=1,2 do
    S.g3NativeForms.DEOXYS=i;Forms.draw(S,data.pokemon.DEOXYS,20,20,1320,{markDirty=function() error("Browsing changed project") end})
    assert(S._nativeFormPictures["DEOXYS"..i] and #S._nativeFormPictures["DEOXYS"..i]==4,"Missing Deoxys frame")
  end
  assert(not S.project.gen3Forms,"Browsing forms created overrides")
  local originalRow=K.row;local count=0
  K.row=function(...) count=count+1;return false end
  C.open(S,{ids={1,2,3},labels={[1]="Oak",[2]="Daisy",[3]="Brock"}})
  C.draw(S,0,0,1360,860);assert(count==3,"Numeric dropdown entries disappeared")
  count=0;S.choicePicker.query="daisy";C.draw(S,0,0,1360,860);assert(count==1,"Numeric dropdown label search failed")
  K.row=originalRow;C.close(S);K.endFrame();love.graphics.setCanvas()
  local unown=Forms.template(S,"UNOWN");assert(#unown.forms==28)
  local cast=Forms.template(S,"CASTFORM");assert(#cast.forms==4)
  local deoxys=Forms.template(S,"DEOXYS");assert(#deoxys.forms==4)
  for _,family in ipairs({unown,cast,deoxys}) do
    for _,row in ipairs(family.forms) do
      local rec=S.project.pokemon[row.species] or S.data.pokemon[row.species]
      assert(Forms.spritePath(rec,false,true) and Forms.spritePath(rec,true,true),"Form lost shiny artwork")
      if row.species~=family.forms[1].species and not row.needsArtwork then
        assert(IO.readText(S.path.."/"..rec.spriteShinyFront),"Missing saved shiny front")
        assert(IO.readText(S.path.."/"..rec.spriteShinyBack),"Missing saved shiny back")
      end
    end
  end
  local custom,rec=Forms.add(S,"PIKACHU","Winter");rec.baseStats.attack=110
  rec.learnset={{level=1,move="TACKLE"}}
  S.project.gen3Forms.PIKACHU.default=2
  local choices,labels=Forms.encounterChoices(S,"UNOWN");assert(#choices==29 and labels["28"]=="?")
  local fixedA=Forms.encounterSpecies(S,"UNOWN","1")
  assert(fixedA~="UNOWN" and Forms.encounterSpecies(S,"UNOWN","1")==fixedA)
  assert(Forms.encounterSpecies(S,"UNOWN","2")==unown.forms[2].species)
  assert(Forms.encounterSpecies(S,"UNOWN","automatic")=="UNOWN")
  S.project.encounters.FR_ROUTE_1=require("src.mods.Merge").deepCopy(S.data.encounters.FR_ROUTE_1)
  S.project.encounters.FR_ROUTE_1.land.slots[1]={species=fixedA,minLevel=10,maxLevel=10}
  S.project.encounters.FR_ROUTE_1.land.slots[2]={species=unown.forms[2].species,minLevel=11,maxLevel=11}
  assert(rec.index>439 and rec.dex==data.pokemon.PIKACHU.dex)
  assert(require("SpeciesPicker").displayName(S,custom.species)=="PIKACHU - Winter")
  assert(IO.save(S.path,S.project));assert(#IO.load(S.path).gen3Forms.UNOWN.forms==29)
  assert(mount(S.path,"mods/forms_test",1)~=0)
  local fresh={};require("Gen3").load(fresh,data._gen3Read);local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local wild=loader.content.encounters:get("FR_ROUTE_1").land.slots
  assert(wild[1].species==fixedA and wild[2].species==unown.forms[2].species,"Encounter form selection did not survive export")
  local P=require("src.core.game3.pokemon");local BS=require("src.core.game3.battle.state")
  -- Reproduce the game's ROM-table reload after mods have registered forms.
  -- Do not manually write the registry here: exported runtime must restore it.
  P.install(P._cache)
  local E=require("src.core.game3.encounters")
  E._tables=fresh.gen3Encounters;E._loaded=true
  E.ensureLoaded()
  assert(E._tables.FR_ROUTE_1.land.slots[2].species==S.project.pokemon[unown.forms[2].species].index,"Encounter exported an invalid form ID")
  local Rng=require("src.core.game3.rng");local random,wildRandom=Rng.Random,Rng.WildEncounterRandom;Rng.Random=function() return 0 end;Rng.WildEncounterRandom=function() return 0 end
  local rolled=assert(E.rollLand("FR_ROUTE_1"))
  Rng.Random=random;Rng.WildEncounterRandom=wildRandom
  assert(rolled.species==S.project.pokemon[fixedA].index,"Wild encounter lost selected form")
  assert(P.speciesFromName(P.keyName(rolled.species))==rolled.species,"Encounter hook conversion lost form identity")
  local Battle=require("src.core.game3.battle")
  local player={species=25,level=10,moves={33},pp={35}};P.applyStats(player)
  Battle.start({headless=true,autoFight=false,wild=true,playerParty={player},foe=rolled})
  local enemy=Battle.getState().enemy.mon
  assert(enemy.moves[1]==237 and #enemy.moves==1,"Wild Unown did not receive Hidden Power")
  assert(enemy.pp[1]==P.movePp(237),"Wild form has incorrect PP")
  Battle.abort("test")
  Battle.start({headless=true,autoFight=false,playerParty={player},foe={species=rolled.species,level=10,moves={33},pp={12}}})
  assert(Battle.getState().enemy.mon.moves[1]==33,"Explicit trainer moves were overwritten")
  Battle.abort("test")
  assert(P.name(rec.index)=="PIKACHU","ROM reload lost custom form name")
  assert(P.name(S.project.pokemon[unown.forms[2].species].index)=="UNOWN","ROM reload lost Unown name")
  local fixedWild={species=S.project.pokemon[fixedA].index,personality=1,level=10}
  P.applyStats(fixedWild);assert(fixedWild.species==S.project.pokemon[fixedA].index,"Explicit Unown A was randomized")
  assert(P.frontPic(fixedWild.species),"Fixed encounter form has no sprite")
  local mon={species=201,personality=1,level=20};P.applyStats(mon)
  assert(mon.species==S.project.pokemon[unown.forms[2].species].index)
  local front=P.frontPic(mon.species);assert(front and front.image and front.image:getWidth()==64)
  assert(P.backPic(mon.species).image:getHeight()==64)
  local expected=love.image.newImageData("mods/forms_test/assets/forms/"..unown.forms[2].species.."/spriteFront.png")
  local actual=love.graphics.newCanvas(64,64)
  love.graphics.setCanvas(actual);love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1);love.graphics.draw(front.image);love.graphics.setCanvas()
  local rendered=actual:newImageData()
  for y=0,63 do for x=0,63 do
    local r,g,b,a=expected:getPixel(x,y);local rr,gg,bb,aa=rendered:getPixel(x,y)
    assert(math.abs(a-aa)<.01 and (a==0 or (math.abs(r-rr)<.01 and math.abs(g-gg)<.01 and math.abs(b-bb)<.01)),"Battle sprite does not match selected form")
  end end
  local pika={species=25,personality=0,level=50};P.applyStats(pika)
  assert(pika.species==rec.index and pika.attack==115,"Custom form stats were not used")
  assert(P.frontPic(rec.index).image:getWidth()==64,"Copied form artwork unavailable")
  assert(P.icon(rec.index),"Custom form lost the parent party icon")
  local gift={party={}};assert(require("src.core.game3.party").giveMon(gift,25,5))
  assert(gift.party[1].species==rec.index and gift.party[1].moves[1]==33,"Default form gift did not use its learnset")
  local battler=BS.makeBattler({species=385,personality=0,level=20},"player")
  local ad={_st={weather="RAIN"},hp=function(_,b) return b.mon.hp end,abilityOf=function() return "FORECAST" end}
  local A=require("src.core.game3.battle.abilities");A.castformChange(ad,battler)
  assert(battler.species==S.project.pokemon[cast.forms[3].species].index)
  assert(battler.mon.species==385,"Weather form changed saved species")
  assert(battler.type1==require("src.core.game3.battle.types").ID.WATER)
  ad._st.weather=nil;A.castformChange(ad,battler);assert(battler.species==385)
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  S.g3FormSelection={CASTFORM=3};Forms.draw(S,data.pokemon.CASTFORM,20,20,1320,{markDirty=function() end})
  K.endFrame();love.graphics.setCanvas();assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/forms-editor.png",canvas:newImageData():encode("png"):getString()))
  require("src.mods.Runtime").reset();local ordinary={species=25,level=50};P.applyStats(ordinary);assert(ordinary.species==25)
end
