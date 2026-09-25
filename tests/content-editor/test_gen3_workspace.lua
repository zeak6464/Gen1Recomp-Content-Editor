-- Run inside the real-cache LÖVE harness: exercise shared authoring + runtime.
return function(data,root,game)
  local L=require("LayeredMap")
  local G=require("Gen3Workspace")
  local S={data=data,version=game or "firered",project=require("State").blankProject("native_integration")}
  S.project.game=game or "firered"
  S.path=root.."/tests/content-editor/gen3-smoke/native-project"
  G.prepare(S)
  local source=assert(G.convert(S,"FR_PALLET_TOWN"))
  local original=require("Gen3Map").layout(data,"FR_PALLET_TOWN")
  local x,y=3,4
  local cell=original:cellAt(x,y)
  local ref=L.getCell(source,1,x,y)
  assert(ref.tile==cell.mid and source.gen3Elevation[y*source.cellWidth+x+1]==cell.elev)
  local _,layer=L.addLayer(source,"Details")
  assert(L.setCell(source,layer,2,2,ref))
  assert(L.resizeMap(S.project,"FR_PALLET_TOWN",source.cellWidth+2,source.cellHeight+2))
  assert(source.gen3Elevation[y*source.cellWidth+x+1]==cell.elev,"Resize shifted native elevation")
  local created,map=L.createMap(S,"WORKSPACE_TEST",8,6,source.baseTileset)
  assert(map.id=="FR_WORKSPACE_TEST")
  assert(G.rename(S,map.id,"  Moonlit Grove  "))
  assert(map.name=="Moonlit Grove" and map.label=="Moonlit Grove")
  assert(map.id=="FR_WORKSPACE_TEST" and created.id==map.id)
  assert(not G.rename(S,map.id,"   "))
  local borderPair
  for _,info in pairs(data.gen3Native.layouts) do if info.pair~=created.baseTileset then borderPair=info.pair;break end end
  assert(borderPair,"Need a second native tileset for border regression")
  local Map=require("Gen3Map");local borderBase=assert(Map.layout(data,map.id,S.project))
  assert(Map.setBorderTileset(S.project,map.id,borderBase,borderPair))
  local nativeTs,nativeT=Map.tileset(data,borderPair);assert(nativeTs)
  local borderTile=1
  assert(Map.paintBorder(S.project,map.id,borderBase,0,0,borderTile))
  local expectedCanvas=love.graphics.newCanvas(16,16)
  love.graphics.push("all");love.graphics.setCanvas(expectedCanvas);love.graphics.clear(0,0,0,0);love.graphics.setColor(1,1,1,1)
  love.graphics.draw(nativeTs.image,nativeT.quad(nativeTs,nativeT.slotFor(nativeTs,borderTile)),0,0)
  love.graphics.pop();local expectedBorder=expectedCanvas:newImageData()
  L.setCell(created,1,1,1,ref)
  local IO=require("ModIO")
  IO.ensureDirectory(S.path.."/assets")
  local pixels=love.image.newImageData(16,16)
  pixels:mapPixel(function() return 1,0,1,1 end)
  assert(IO.writeText(S.path.."/assets/workspace.png",pixels:encode("png"):getString()))
  S.project.mapTileSources.test={id="test",image="assets/workspace.png",columns=1,count=1,colorMode="true_color"}
  L.setCell(created,1,2,2,{source="test",tile=0})
  S.mapId="FR_PALLET_TOWN"
  local app={markDirty=function() end}
  local count=#S.project.maps[S.mapId].objects
  assert(require("Gen3MapEvents").place(S,"object",3,4,app))
  assert(require("Gen3MapEvents").place(S,"sign",4,4,app))
  assert(#S.project.maps[S.mapId].objects==count+1,"Placing another event discarded previous edits")
  require("Gen3AudioAdapter").prepare(S)
  S.project.audio.songs["300"]={nativeId=301}
  assert(L.compileProject(S))
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  S.g3MapId=map.id;S.g3MapMode="border"
  require("Gen3Maps").draw(S,20,20,1320,820,app)
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/border-tileset.png",canvas:newImageData():encode("png"):getString()))
  local dir=root.."/tests/content-editor/gen3-smoke/native-project"
  assert(IO.save(dir,S.project))
  local reopened=assert(IO.load(dir))
  assert(reopened.layeredMaps.FR_PALLET_TOWN.layers[layer].cells[2*source.cellWidth+3].tile==ref.tile)
  assert(reopened.gen3Audio.songs["300"]==301)
  assert(reopened.maps.FR_WORKSPACE_TEST.name=="Moonlit Grove")
  assert(reopened.layeredMaps.FR_WORKSPACE_TEST.gen3Border.pair==borderPair,"Border tileset lost on reload")
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,dir);assert(loader,err)
  loader.events:emit("game.ready",{game={data=fresh}})
  for _,e in ipairs(loader:status().errors or {}) do error(tostring(e)) end
  local layout=assert(fresh.maps.FR_PALLET_TOWN.midLayout)
  assert(layout.width==source.cellWidth and layout:cellAt(x,y).elev==cell.elev)
  assert(fresh.maps.FR_WORKSPACE_TEST.midLayout.width==8)
  assert(fresh.maps.FR_WORKSPACE_TEST.name=="Moonlit Grove","Renamed map name was not exported")
  assert(#fresh.maps.FR_PALLET_TOWN.objects==count+1)
  local T=require("src.core.game3.tileset_native")
  local ts=assert(T.get(fresh.maps.FR_WORKSPACE_TEST.pair))
  assert(ts.image:getWidth()>0 and ts.overImage)
  local mid=fresh.maps.FR_WORKSPACE_TEST.midLayout:midAt(2,2)
  local slot=T.slotFor(ts,mid)
  local r,g,b=ts.image:newImageData():getPixel(slot%ts.cols*16,math.floor(slot/ts.cols)*16)
  assert(r==1 and g==0 and b==1,"Imported PNG pixels did not reach the native atlas")
  local borderMid=fresh.maps.FR_WORKSPACE_TEST.midLayout:midAt(-1,-1)
  local borderSlot=T.slotFor(ts,borderMid);local pixels=ts.image:newImageData()
  for yy=0,15 do for xx=0,15 do
    local r,g,b,a=pixels:getPixel(borderSlot%ts.cols*16+xx,math.floor(borderSlot/ts.cols)*16+yy)
    local er,eg,eb,ea=expectedBorder:getPixel(xx,yy)
    assert(r==er and g==eg and b==eb and a==ea,"Exported border used the wrong tileset")
  end end
  require("src.mods.Runtime").reset()
end
