return function(data,root,mount,game)
  local L,G,B,IO=require("LayeredMap"),require("Gen3Workspace"),require("Gen3Bridges"),require("ModIO")
  local S={data=data,version=game,project=require("State").blankProject("bridge_test")};S.project.game=game;G.prepare(S)
  S.path=root.."/tests/content-editor/bridges-smoke/project";IO.ensureDirectory(S.path.."/assets")
  local pixels=love.image.newImageData(32,16)
  pixels:mapPixel(function(x) if x<16 then return 0,1,0,1 else return 1,.5,0,1 end end)
  assert(IO.writeText(S.path.."/assets/bridge.png",pixels:encode("png"):getString()))
  S.project.mapTileSources.bridge={id="bridge",image="assets/bridge.png",columns=2,count=2,colorMode="true_color"}
  local source,map=L.createMap(S,"BRIDGE_TEST",8,8,data.maps.FR_PALLET_TOWN.pair)
  assert(require("Gen3Map").tileset(data,source.baseTileset))
  for y=0,7 do for x=0,7 do L.setCell(source,1,x,y,{source="bridge",tile=0});L.setCollision(source,x,y,"walk") end end
  for x=2,5 do assert(B.paint(source,x,3,"deck_horizontal",{source="bridge",tile=1})) end
  assert(B.paint(source,1,3,"entrance_horizontal"));assert(B.paint(source,6,3,"entrance_horizontal"))
  L.setCollision(source,3,3,"water")
  assert(source.layers[1].cells[3*8+4].tile==0 and source.collision[3*8+4]=="water","Bridge changed underlying terrain")
  local copy=require("src.mods.Merge").deepCopy(source)
  assert(B.paint(copy,3,3,"remove"));assert(copy.layers[1].cells[28].tile==0 and copy.collision[28]=="water")
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"bridge_test","name":"Bridge test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(L.compileProject(S));assert(IO.save(S.path,S.project));assert(mount(S.path,"mods/bridge_test",1)~=0)
  local reopened=assert(IO.load(S.path));assert(reopened.layeredMaps[map.id].gen3Bridges[28].tile.tile==1)
  local fresh={};require("Gen3").load(fresh,data._gen3Read);local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local g={data=fresh};for _,entry in ipairs(loader.events.listeners["game.ready"] or {}) do entry.callback({game=g}) end
  for _,message in ipairs(loader:status().errors or {}) do error(tostring(message)) end
  local def=fresh.maps[map.id];assert(def._editorBridges and def.midLayout,table.concat(fresh._editorGen3Report.messages," | "))
  local T=require("src.core.game3.tileset_native");local ts=T.get(def.pair);local mid=def.midLayout:midAt(3,3);local slot=T.slotFor(ts,mid)
  local x,y=slot%ts.cols*16,math.floor(slot/ts.cols)*16
  local r,green,b=ts.image:newImageData():getPixel(x,y);assert(r==0 and green==1 and b==0,"Lower terrain was flattened into deck")
  r,green,b=ts.overImage:newImageData():getPixel(x,y);assert(r==1 and green>.49 and green<.51 and b==0,"Deck missing from overhead atlas")
  local C,P=require("src.core.game3.collision"),require("src.core.game3.player")
  C.bindMap(g,map.id,def);P.surfing=false
  local function can(fx,fy,tx,ty,high)
    P.cellX=fx;P.cellY=fy;P.elevation=high and 4 or 3
    return C.canEnter(g,tx,ty,{fromX=fx,fromY=fy,dir=tx<fx and "left" or tx>fx and "right" or ty<fy and "up" or "down"})
  end
  assert(can(0,3,1,3,false),"Entrance blocked")
  assert(C.elevationAt(1,3)==4,"Entrance did not select upper level")
  assert(can(1,3,2,3,true));assert(can(2,3,3,3,true),"Upper deck used lower water collision")
  assert(C.elevationAt(3,3)==4)
  assert(not can(3,3,3,2,true),"Player walked off the bridge edge")
  assert(can(5,3,6,3,true));assert(can(6,3,7,3,true));assert(C.elevationAt(7,3)==3)
  assert(can(4,2,4,3,false),"Lower passage blocked");assert(C.elevationAt(4,3)==3)
  assert(can(4,3,4,4,false),"Cannot leave underpass")
  assert(not can(3,2,3,3,false),"Lower water lost surf requirement")
  P.surfing=true;assert(can(3,2,3,3,false));P.surfing=false
  assert(not can(2,3,1,3,false),"Underpass climbed onto bridge entrance")
  assert(not can(1,2,1,3,false),"Entrance side was climbable")
  local savedGame={save={position={}}};P.cellX=4;P.cellY=3;P.elevation=4;P.syncSavePosition(savedGame)
  local restored=assert(require("src.core.SaveSerializer").decode(require("src.core.SaveSerializer").encode(savedGame.save)))
  restored.x=4;restored.y=3;P.elevation=3;P.syncFromSession(restored);assert(P.elevation==4,"Save reload put upper player underneath")
  P.elevation=3;P.syncSavePosition(savedGame);restored.meta=savedGame.save.meta;P.elevation=4;P.syncFromSession(restored)
  assert(P.elevation==3,"Save reload put lower player on top")
  -- Walk with the actual player step loop: entrances select height on arrival.
  P.cellX=0;P.cellY=3;P.elevation=3;P.moving=false;P.turnTimer=0;P.turnArmed=false;P.boulderPush=nil;P.facing="right"
  for xx=1,7 do
    P.tryMove("right",g,false);assert(P.moving,"Player could not start bridge step "..xx)
    for tick=1,16 do P.tick(g) end
    assert(P.cellX==xx and P.cellY==3,"Player did not finish bridge step")
    assert(P.elevation==(xx==7 and 3 or 4),"Player height did not follow entrance/deck/exit")
  end
  -- Same guards for a vertical deck.
  def._editorBridges={};for yy=2,5 do def._editorBridges[yy*8+4]={kind="deck",axis="vertical"} end
  def._editorBridges[1*8+4]={kind="entrance",axis="vertical"};def._editorBridges[6*8+4]={kind="entrance",axis="vertical"}
  assert(can(3,0,3,1,false));assert(can(3,1,3,2,true));assert(not can(3,3,4,3,true))
  assert(not can(3,2,3,1,false))
  assert(L.resizeMap(S.project,map.id,10,10));assert(source.gen3Bridges[3*10+4].kind=="deck","Resize lost bridge metadata")
  -- Render a compact demonstration directly from the exported planes.
  local canvas=love.graphics.newCanvas(384,224);love.graphics.setCanvas(canvas);love.graphics.clear(.05,.07,.12,1)
  for i,label in ipairs({"UNDERPASS","ON THE BRIDGE"}) do
    local ox=(i-1)*192;love.graphics.setColor(1,1,1,1);love.graphics.print(label,ox+8,8)
    love.graphics.draw(ts.image,T.quad(ts,slot),ox+40,60,0,6,6)
    if i==1 then love.graphics.setColor(1,0,1,1);love.graphics.rectangle("fill",ox+76,85,20,40) end
    love.graphics.setColor(1,1,1,1);love.graphics.draw(ts.overImage,T.overQuad(ts,slot),ox+40,60,0,6,6)
    if i==2 then love.graphics.setColor(1,0,1,1);love.graphics.rectangle("fill",ox+76,85,20,40) end
  end
  love.graphics.setCanvas();assert(IO.writeText(root.."/tests/content-editor/bridges-smoke/planes.png",canvas:newImageData():encode("png"):getString()))
  require("src.mods.Runtime").reset()
  S.builderMapId=map.id;S.mapId=map.id;S.builderTool="bridge";S.builderSourceId="bridge";S.builderTile=1
  local K=require("Kit");local editor=love.graphics.newCanvas(1360,960)
  love.graphics.setCanvas({editor,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,960);K.beginFrame(0,0,false,0)
  require("MapBuilder").draw(S,20,20,1320,920,{markDirty=function() end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/bridges-smoke/editor.png",editor:newImageData():encode("png"):getString()))
end
