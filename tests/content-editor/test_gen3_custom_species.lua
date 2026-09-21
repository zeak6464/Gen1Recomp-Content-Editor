return function(data,root,mount)
  local IO,G=require("ModIO"),require("Gen3")
  local S=require("State").new();S.data=data;S.version="firered"
  S.project=require("State").blankProject("custom_species_test");S.project.game="firered"
  local Adapter=require("Gen3ContentAdapter");Adapter.prepare(S)
  local rec=Adapter.newRecord(S,"pokemon","CUSTOM_LEAF")
  assert(rec.index>439,"Custom species overlaps reserved Unown slots")
  rec.name="CUSTOM LEAF";rec.learnset={{level=1,move="TACKLE"}}
  S.project.pokemon.CUSTOM_LEAF=rec
  S.path=root.."/tests/content-editor/gen3-smoke/custom-species-project"
  assert(IO.ensureDirectory(S.path.."/assets"))
  local pixels=love.image.newImageData(64,64)
  pixels:mapPixel(function() return .2,.8,.3,1 end)
  assert(IO.writeText(S.path.."/assets/front.png",pixels:encode("png"):getString()))
  rec.spriteFront="assets/front.png";rec.spriteBack=rec.spriteFront
  pixels:mapPixel(function() return .9,.2,.4,1 end)
  assert(IO.writeText(S.path.."/assets/shiny.png",pixels:encode("png"):getString()))
  rec.spriteShinyFront="assets/shiny.png";rec.spriteShinyBack=rec.spriteShinyFront
  assert(require("Gen3Forms").spritePath(rec,false,true)==rec.spriteShinyFront)
  S.project.encounters.FR_ROUTE_1=require("src.mods.Merge").deepCopy(data.encounters.FR_ROUTE_1)
  for _,slot in ipairs(S.project.encounters.FR_ROUTE_1.land.slots) do slot.species=rec.id;slot.minLevel=8;slot.maxLevel=8 end
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"custom_species_test","name":"Custom species test","version":"1.0.0","entry":"main.lua","games":["firered"]}'))
  assert(IO.save(S.path,S.project))
  assert(not next(S.project.gen3Forms or {}),"Test must exercise standalone species")
  assert(mount(S.path,"mods/custom_species_test",1)~=0)
  local fresh={};G.load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local P=require("src.core.game3.pokemon")
  -- A second application must not reuse a corrupt cached numeric-name index.
  loader.events:emit("mods.loaded",{loader=loader})
  P.install(P._cache)
  assert(P.name(rec.index)==rec.name,"Reload lost custom species name")
  assert(P.speciesFromName(P.keyName(rec.index))==rec.index,"Custom ID did not round trip")
  local E=require("src.core.game3.encounters")
  E._tables=fresh.gen3Encounters;E._loaded=true;E.ensureLoaded()
  assert(E._tables.FR_ROUTE_1.land.slots[1].species==rec.index,"Encounter lost custom species ID")
  local front=assert(P.frontPic(rec.index),"Custom front sprite missing")
  assert(front.image:getWidth()==64 and P.backPic(rec.index).image:getHeight()==64)
  assert(P.frontPic(rec.index,0,true)~=front,"Shiny front uses normal artwork")
  assert(P.backPic(rec.index,0,true)~=P.backPic(rec.index),"Shiny back uses normal artwork")
  local Battle=require("src.core.game3.battle")
  local player={species=25,level=10,moves={33},pp={35}};P.applyStats(player)
  Battle.start({headless=true,wild=true,autoFight=false,playerParty={player},foe={species=rec.index,level=8}})
  local enemy=Battle.getState().enemy.mon
  assert(enemy.species==rec.index and enemy.moves[1]==33,"Battle lost species or learnset")
  Battle.abort("test")
  require("src.mods.Runtime").reset()
end
