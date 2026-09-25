return function(data,root,mount,game)
  local C=require("Gen3Connections");local E=require("Gen3ConnectionEditor");local G=require("Gen3Workspace")
  local id="FR_SIX_ISLAND_WATER_PATH"
  local west=C.list(data.maps[id].connections,"west")
  assert(#west==3 and west[1].offset==0 and west[2].offset==40 and west[3].offset==80,"Stock Water Path recovery failed")
  local S={data=data,version=game,project=require("State").blankProject("connections_test")};S.project.game=game
  G.prepare(S);assert(G.convert(S,id))
  -- Edit only the middle connection, preserving both siblings and return links.
  E.edit(S,id,"west",2,"FR_SIX_ISLAND",42)
  local rows=C.list(S.project.maps[id].connections,"west")
  assert(#rows==3 and rows[1].offset==0 and rows[2].offset==42 and rows[3].offset==80)
  assert(C.list(S.project.maps.FR_SIX_ISLAND.connections,"east")[1].offset==-42)
  E.edit(S,id,"west",2,"FR_SIX_ISLAND",40)
  E.edit(S,id,"west",2,nil,40)
  assert(#C.list(S.project.maps[id].connections,"west")==2)
  assert(#C.list(S.project.maps.FR_SIX_ISLAND.connections,"east")==0)
  E.edit(S,id,"west",3,"FR_SIX_ISLAND",40)
  G.prepare(S);assert(#C.list(S.project.maps[id].connections,"west")==3)
  local Maps=require("Maps");assert(#Maps.directNeighbors(S,S.project.maps[id])==3,"Editor dropped duplicate-direction neighbors")
  local IO=require("ModIO");S.path=root.."/tests/content-editor/connections-smoke/project";IO.ensureDirectory(S.path)
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"connections_test","name":"Connections test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(require("LayeredMap").compileProject(S));assert(IO.save(S.path,S.project))
  local reopened=assert(IO.load(S.path));assert(#C.list(reopened.maps[id].connections,"west")==3)
  assert(mount(S.path,"mods/connections_test",1)~=0)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  loader.events:emit("game.ready",{game={data=fresh}})
  assert(#fresh._editorGen3Report.rejected==0)
  for _,message in ipairs(loader:status().errors or {}) do error(tostring(message)) end
  assert(#C.list(fresh.maps[id].connections,"west")==3,"Export lost connections")
  local Map=require("src.core.game3.map");local Collision=require("src.core.game3.collision")
  Map.loadNeighborsDepth1({data=fresh},fresh.maps[id]);assert(#Map.overscanSlices()==3)
  local world=Map.computeWorld(fresh.maps,id,1,nil,nil,function(key,def) Map.ensureMidLayout({data=fresh},key,def) end)
  assert(#world==3,"Runtime world dropped a west neighbor")
  for _,row in ipairs(C.list(fresh.maps[id].connections,"west")) do
    local dest=fresh.maps[row.map];Map.ensureMidLayout({data=fresh},row.map,dest)
    local mid,pair=Map.worldMidAt(-1,row.offset,fresh.maps[id])
    assert(mid==dest.midLayout:midAt(dest.midLayout.width-1,0) and pair==dest.midLayout.pair,"Wrong Water Path border sample")
  end
  -- Synthetic spans test all directions, exact boundary selection and gaps.
  local Layout=require("src.core.game3.layout_native")
  local function def(name,w,h,mid,coll)
    local cells={};for i=1,w*h do cells[i]={mid=mid,coll=coll or 0,elev=3} end
    return {id=name,pair=name,width=w,height=h,connections={},midLayout=Layout.fromDecoded({width=w,height=h,cells=cells,borderWidth=1,borderHeight=1,borderMids={99}},name,name)}
  end
  local nativeLoad=Map.load;local landed
  Map.load=function(_,g,destination,opts) landed={id=destination,x=opts.x,y=opts.y};Collision._mapDef=g.data.maps[destination] end
  local Player=require("src.core.game3.player");Player.surfing=false
  for _,dir in ipairs(C.directions) do
    local horizontal=dir=="west" or dir=="east"
    local maps={ROOT=def("ROOT",10,10,0),A=def("A",2,2,11),B=def("B",2,2,22),D=def("D",2,2,33)}
    maps.ROOT.connections[dir]={{map="A",offset=0},{map="B",offset=4},{map="D",offset=8}}
    local g={data={maps=maps}};Map.loadNeighborsDepth1(g,maps.ROOT);Map.world={}
    if dir=="east" then
      local found=require("src.core.game3.itemfinder").scan({px=9,py=4,width=10,height=10,neighbors=Map.neighbors,events={},
        eventsFor=function(key) return key=="B" and {{kind=7,x=0,y=0}} or {} end,flagSet=function() return false end})
      assert(found and found.itemX==1 and found.itemY==0,"Itemfinder ignored the second neighbor")
    end
    local move=({north="up",south="down",west="left",east="right"})[dir]
    for i,name in ipairs({"A","B","D"}) do
      local off=(i-1)*4;local x=horizontal and (dir=="west" and 0 or 9) or off
      local y=horizontal and off or (dir=="north" and 0 or 9)
      Collision._mapDef=maps.ROOT;landed=nil
      assert(Collision.tryConnection(g,x,y,move,false),"Native crossing failed: "..dir..name)
      assert(landed.id==name and (horizontal and landed.y==0 or not horizontal and landed.x==0),"Wrong destination or offset")
      assert(Collision._mapDef==maps[name],"Transition lost new collision map")
      local sx=horizontal and (dir=="west" and -1 or 10) or off
      local sy=horizontal and off or (dir=="north" and -1 or 10)
      local mid,pair=Map.worldMidAt(sx,sy,maps.ROOT);assert(mid==i*11 and pair==name,"Wrong neighbor rendering")
    end
    Collision._mapDef=maps.ROOT;landed=nil
    assert(not Collision.tryConnection(g,horizontal and (dir=="west" and 0 or 9) or 3,horizontal and 3 or (dir=="north" and 0 or 9),move,false),"Gap clamped into neighboring map")
    assert(not landed and Collision._mapDef==maps.ROOT)
    -- A valid span still delegates collision to native code.
    for _,cell in ipairs(maps.B.midLayout.cells) do cell.coll=255 end
    assert(not Collision.tryConnection(g,horizontal and (dir=="west" and 0 or 9) or 4,horizontal and 4 or (dir=="north" and 0 or 9),move,false),"Blocked destination was entered")
  end
  Map.load=nativeLoad
  -- Reopening must not recreate a deliberately removed connection.
  E.edit(S,id,"west",3,nil,40);G.prepare(S)
  assert(#C.list(S.project.maps[id].connections,"west")==2)
  assert(require("LayeredMap").compileProject(S));assert(IO.save(S.path,S.project))
  local again={};require("Gen3").load(again,data._gen3Read)
  local reload=assert(require("Gen3Mod").load(again,S.path));reload.events:emit("game.ready",{game={data=again}})
  assert(#C.list(again.maps[id].connections,"west")==2,"Export recreated a deleted link")
  E.edit(S,id,"west",3,"FR_SIX_ISLAND",40)
  S.mapId=id
  local K=require("Kit");local canvas=love.graphics.newCanvas(900,900)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(900,900);K.beginFrame(0,0,false,0)
  E.draw(S,id,20,20,520,850,{markDirty=function() error("Browsing connections changed the project") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/connections-smoke/connections.png",canvas:newImageData():encode("png"):getString()))
  require("src.mods.Runtime").reset()
end
