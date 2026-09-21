return function(data,root)
  local State,IO=require("State"),require("ModIO")
  local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("fly_test");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  S.path=root.."/tests/content-editor/gen3-smoke/fly-project"
  assert(IO.ensureDirectory(S.path));assert(IO.writeText(S.path.."/manifest.json",'{"id":"fly_test","name":"Fly test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  local Fly=require("Gen3Fly");S.project.gen3Fly=Fly.defaults();Fly.validate(S.project.gen3Fly)
  for _,row in ipairs(S.project.gen3Fly) do assert(data.maps[row.map],"Missing default Fly map "..row.map) end
  S.project.gen3Fly[1].unlock="always";S.project.gen3Fly[1].x=7
  assert(IO.save(S.path,S.project));assert(IO.load(S.path).gen3Fly[1].x==7)
  local fresh={};require("Gen3").load(fresh,data._gen3Read);local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local F=require("src.core.game3.field");local Region=require("src.ui.game3.region_map")
  local session={map="FR_ROUTE1",flags={},party={}};local oldSession,oldGame=F._session,F._game;F._session=session
  local Runtime=require("src.mods.Runtime")
  Runtime.emit("map.entered",{mapId="FR_VIRIDIAN_CITY"})
  assert(session.modData.fly_test.flyVisited.FR_VIRIDIAN_CITY)
  F.executeFieldMove({action="fly"});assert(Region.isOpen());assert(Region.currentLocationName()=="PALLET TOWN")
  local function key(k) return {wasPressed=function(_,v) return v==k end} end
  Region.handleInput(key("right"));assert(Region.currentLocationName()=="VIRIDIAN CITY")
  Region.handleInput(key("b"));assert(not Region.isOpen())
  local Map,Player=require("src.core.game3.map"),require("src.core.game3.player")
  local load,reset,sync=Map.load,Player.reset,Player.syncToHost;local destination
  Map.load=function(_,_,id,opts) destination={id=id,x=opts.x,y=opts.y,via=opts.via} end
  Player.reset=function(x,y) assert(x==7 and y==8) end;Player.syncToHost=function() end
  F.executeFieldMove({action="fly"});Region.handleInput(key("a"))
  Map.load,Player.reset,Player.syncToHost=load,reset,sync
  assert(destination.id=="FR_PALLET_TOWN" and destination.x==7 and destination.y==8 and destination.via=="fly")
  local available=require("Gen3FlyRuntime").available
  assert(not available({enabled=false,unlock="always"},session,{}))
  assert(not available({unlock="flag",flag=123},session,{}));session.flags[123]=true;assert(available({unlock="flag",flag=123},session,{}))
  Runtime.reset();F.executeFieldMove({action="fly"});assert(not Region.isOpen(),"Disabled mod left Fly hooks active")
  F._session,F._game=oldSession,oldGame
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  S.g3TownFly=true;require("Gen3UiContent").draw(S,20,20,1320,800,{markDirty=function() end},"town")
  K.endFrame();love.graphics.setCanvas();assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/fly-editor.png",canvas:newImageData():encode("png"):getString()))
end
