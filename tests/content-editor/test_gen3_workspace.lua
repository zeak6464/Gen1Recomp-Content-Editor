-- Run inside the real-cache LÖVE harness: exercise shared authoring + runtime.
return function(data,root)
  local L=require("LayeredMap")
  local G=require("Gen3Workspace")
  local S={data=data,version="firered",project=require("State").blankProject("native_integration")}
  S.project.game="firered"
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
  local dir=root.."/tests/content-editor/gen3-smoke/native-project"
  assert(IO.save(dir,S.project))
  local reopened=assert(IO.load(dir))
  assert(reopened.layeredMaps.FR_PALLET_TOWN.layers[layer].cells[2*source.cellWidth+3].tile==ref.tile)
  assert(reopened.gen3Audio.songs["300"]==301)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,dir);assert(loader,err)
  loader.events:emit("game.ready",{game={data=fresh}})
  for _,e in ipairs(loader:status().errors or {}) do error(tostring(e)) end
  local layout=assert(fresh.maps.FR_PALLET_TOWN.midLayout)
  assert(layout.width==source.cellWidth and layout:cellAt(x,y).elev==cell.elev)
  assert(fresh.maps.FR_WORKSPACE_TEST.midLayout.width==8)
  assert(#fresh.maps.FR_PALLET_TOWN.objects==count+1)
  local T=require("src.core.game3.tileset_native")
  local ts=assert(T.get(fresh.maps.FR_WORKSPACE_TEST.pair))
  assert(ts.image:getWidth()>0 and ts.overImage)
  local mid=fresh.maps.FR_WORKSPACE_TEST.midLayout:midAt(2,2)
  local slot=T.slotFor(ts,mid)
  local r,g,b=ts.image:newImageData():getPixel(slot%ts.cols*16,math.floor(slot/ts.cols)*16)
  assert(r==1 and g==0 and b==1,"Imported PNG pixels did not reach the native atlas")
  require("src.mods.Runtime").reset()
end
