local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
local function report(text)
  local f=assert(io.open(root.."/tests/content-editor/tile-dedup-smoke/result.txt","wb"));f:write(text);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local D=require("TileDedup");local L=require("LayeredMap");local IO=require("ModIO")
  local H=require("History");local encode=require("ModWriter").encodeLua
  local dir=root.."/tests/content-editor/tile-dedup-smoke/project"
  assert(IO.ensureDirectory(dir.."/assets"))
  assert(IO.writeText(dir.."/manifest.json",'{"id":"dedup_test","name":"Tile dedup test","version":"1.0.0","entry":"main.lua"}'))
  local function sheet(name,colors)
    local data=love.image.newImageData(#colors*16,16)
    for i,c in ipairs(colors) do for y=0,15 do for x=0,15 do data:setPixel((i-1)*16+x,y,unpack(c)) end end end
    assert(IO.writeText(dir.."/assets/"..name..".png",data:encode("png"):getString()))
    return data
  end
  local red,green,blue={1,0,0,1},{0,1,0,1},{0,0,1,1}
  sheet("a",{red,green,red,blue,red,red});sheet("b",{red,green,blue});sheet("palette",{red,red})
  local p=require("State").blankProject("dedup_test")
  local S={project=p,path=dir,version="red",data={maps={},tilesets={}},builderMapId="A",mapId="A"}
  for _,info in ipairs({{"A","a",6},{"B","b",3},{"P","palette",2}}) do
    local src=assert(L.addTileSource(p,info[1],"assets/"..info[2]..".png",info[3]*16,16))
    src.colorMode=info[1]=="P" and "palette" or "true_color"
  end
  p.mapTileSources.A.animations[4]={{tile=0,duration=100},{tile=1,duration=200}}
  p.mapTileSources.A.animations[5]={{tile=2,duration=100},{tile=1,duration=200}}
  local ref={source="A",tile=2}
  p.layeredMaps.A={id="A",cellWidth=2,cellHeight=2,layers={{cells={ref,ref,{source="A",tile=4},{source="P",tile=0}}},
    {visible=false,export=false,opacity=.5,cells={{source="B",tile=0}}}},collision={"walk","solid","water","grass"},gen3Elevation={1,2,3,4}}
  p.layeredMaps.B={id="B",cellWidth=2,cellHeight=2,layers={{cells={{source="B",tile=0},{source="B",tile=2}}}},collision={"door","walk"}}
  p.maps.A={id="A",width=1,height=1,_borderExplicit=true,_borderSource="A",_borderTile=2,_borderTile2=1,_borderCells={{dx=0,dy=0,tile=2}},objects={{x=1,y=1,script="hi"}},warps={{x=0,y=1}}}
  p.mapStamps={{source="A",cells={{dx=0,dy=0,tile=2},{dx=1,dy=0,tile=1}}}}
  p.mapAssemblies={{source="B",cells={{dx=0,dy=0,tile=0}}}}
  H.clear(S)
  local App={beginEditBatch=function() H.beginBatch(S) end,endEditBatch=function() H.endBatch(S) end,
    markDirty=function() H.noteDirty(S) end}
  local before=encode(p)
  local plan=D.scan(S,D.sourcesForMaps(p,{A=true}))
  assert(encode(p)==before,"Scan mutated project")
  assert(plan.before==11 and plan.after==5 and plan.saved==6,"Incorrect dedup counts")
  assert(plan.remap.A[0].tile==plan.remap.A[2].tile)
  assert(plan.remap.A[4].tile==plan.remap.A[5].tile)
  assert(plan.remap.A[4].tile~=plan.remap.A[0].tile,"Animated tile merged into static")
  assert(plan.remap.P[0].group~=plan.remap.A[0].group,"Color modes merged")
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  S.tileDedup={selected={A=true},offset=0,plan=plan}
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("TileDedupPanel").draw(S,20,30,1320,790,App)
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/tile-dedup-smoke/preview.png",canvas:newImageData():encode("png"):getString()))
  assert(D.apply(S,plan,App)==6)
  local combined=S.project.mapTileSources[plan.remap.A[0].group.id]
  assert(combined and not S.project.mapTileSources.A)
  assert(ref.source=="A" and ref.tile==2,"Interned reference mutated")
  assert(S.project.layeredMaps.B.layers[1].cells[1].source==combined.id,"Shared source outside selection not remapped")
  assert(S.project.maps.A._borderTile==plan.remap.A[2].tile)
  assert(S.project.mapStamps[1].cells[1].tile==plan.remap.A[2].tile)
  assert(S.project.mapAssemblies[1].source==combined.id)
  assert(encode(S.project.layeredMaps.A.collision)==encode(p.layeredMaps.A.collision))
  assert(encode(S.project.maps.A.objects)==encode(p.maps.A.objects))
  assert(encode(S.project.maps.A.warps)==encode(p.maps.A.warps))
  assert(encode(S.project.layeredMaps.A.gen3Elevation)==encode(p.layeredMaps.A.gen3Elevation))
  -- Compare every tile and every animation frame against its original RGBA.
  local function load(path) return love.image.newImageData(love.filesystem.newFileData(assert(IO.readText(dir.."/"..path)),"tile.png")) end
  for oldId,mapping in pairs(plan.remap) do
    local old=p.mapTileSources[oldId];local original=load(old.image)
    for tile,r in pairs(mapping) do
      local dest=S.project.mapTileSources[r.group.id];local image=load(dest.image)
      for yy=0,15 do for xx=0,15 do
        local a={original:getPixel(tile%old.columns*16+xx,math.floor(tile/old.columns)*16+yy)}
        local b={image:getPixel(r.tile%dest.columns*16+xx,math.floor(r.tile/dest.columns)*16+yy)}
        for c=1,4 do assert(a[c]==b[c],"Pixels changed") end
      end end
      for i,frame in ipairs((old.animations or {})[tile] or {}) do
        local output=dest.animations[r.tile][i]
        assert(output.duration==frame.duration and output.tile==mapping[frame.tile].tile)
      end
    end
  end
  H.endFrame(S);assert(H.undo(S));assert(encode(S.project.mapTileSources)==encode(p.mapTileSources))
  assert(IO.readText(dir.."/"..combined.image),"Undo removed atlas needed for redo")
  assert(H.redo(S));assert(S.project.mapTileSources[combined.id])
  assert(IO.readText(dir.."/assets/a.png"),"Redo deleted original source")
  local reopened=assert(loadstring("return "..encode(S.project)))()
  assert(reopened.mapTileSources[combined.id] and reopened.mapTileSourceArchive.A)
  for _,version in ipairs({"red","gold","firered"}) do
    local export=assert(loadstring("return "..encode(reopened)))()
    export.game=version
    export.maps.B={id="B",width=1,height=1,tileset="BASIC",blocks={0}}
    for _,map in pairs(export.maps) do map.tileset="BASIC";map.blocks={0} end
    export.maps.A.warps={};export.maps.A.objects={}
    for _,map in pairs(export.layeredMaps) do map.baseTileset="BASIC" end
    local data={maps={},tilesets={BASIC={id="BASIC",blocks={{}},image="assets/a.png"}}}
    local state={version=version,project=export,path=dir,data=data}
    require("src.core.GameVersion").set(version)
    if version=="firered" then export.gen3Workspace=1;export.gen3={maps={}};data._gen3Read=function() end end
    local ok,err=L.compileProject(state);assert(ok,version..": "..tostring(err))
    local saved,saveErr=IO.save(dir,export,version);assert(saved,version..": "..tostring(saveErr))
    local loaded=assert(IO.load(dir))
    assert(loaded.mapTileSources[combined.id],version.." lost combined source on reopen")
  end
  -- Missing pixels and out-of-range references must fail without project edits.
  S.project.mapTileSources[combined.id].count=999999
  local ok=pcall(D.scan,S,{combined.id});assert(not ok)
  report("PASS: exact PNG dedup; animation/color separation; map, border and brush references; pixel equality; undo/redo assets; Gen 1/2/3 compile, save and reopen; UI render")
  love.event.quit()
end
