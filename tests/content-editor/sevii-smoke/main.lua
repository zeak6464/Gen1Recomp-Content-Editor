local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cacheRoot=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi")
ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0)
assert(lib.PHYSFS_mount(runtime,"",1)~=0)
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/sevii-smoke/result.txt","wb"));f:write(message);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local IO=require("ModIO")
  local function read(path) return IO.readText(cacheRoot.."/"..path) end
  local cache={read=function(_,path) return read(path) end,exists=function(_,path) return read(path)~=nil end}
  require("src.core.GameVersion").set("firered")
  local T=require("src.core.game3.tileset_native")
  T.install(cache)
  local Animation=require("src.core.game3.tileset_anim")
  local Collision=require("src.core.game3.collision")
  local hooks={}
  package.loaded["src.mods.Runtime"]={call=function(name,proceed,...) return hooks[name] and hooks[name](proceed,...) or proceed(...) end}
  package.loaded["src.core.game3.doors"]={}
  local View={draw=function() end}
  package.loaded["src.core.game3.field_view"]=View
  local Map={current="FR_CINNABAR_ISLAND",neighbors={},world={{id="FR_ROUTE_49"}},ensureMidLayout=function() end}
  local landing
  Map.load=function(_,_,id,opts) landing={id=id,x=opts.x,y=opts.y} end
  package.loaded["src.core.game3.map"]=Map
  package.loaded["src.core.game3.ghosts"]={blocksOn=function() return false end}
  local Player={surfing=true,elevation=1,syncSavePosition=function() end}
  package.loaded["src.core.game3.player"]=Player
  local p=dofile(root.."/mods/Sevii-Routes/editor_project.lua")
  local maps=require("src.mods.Merge").deepCopy(p.gen3.maps)
  local game={data={maps=maps}}
  local mod={id="sevii_test",events={on=function(_,_,fn) fn({game=game}) end},hooks={wrap=function(_,key,fn) hooks[key]=fn end}}
  local run=assert(loadstring("return function(mod,layered) "..require("Gen3LayeredRuntime").." end"))()
  run(mod,{maps=p.gen3Layered,sources=p.gen3TileSources or {},animations=p.gen3TileAnimations or {}})
  Collision.bindMap(game,"FR_CINNABAR_ISLAND",maps.FR_CINNABAR_ISLAND)
  assert(Collision.tryConnection(game,14,19,"down",false),"Surfing south into Route 49 was blocked")
  assert(landing.id=="FR_ROUTE_49" and landing.x==14 and landing.y==0)
  Collision.bindMap(game,"FR_ROUTE_49",maps.FR_ROUTE_49)
  assert(Collision.tryConnection(game,14,0,"up",false),"Surfing north back to Cinnabar was blocked")
  assert(landing.id=="FR_CINNABAR_ISLAND")
  assert(maps.FR_ROUTE_49.midLayout:elevAt(14,0)==0)
  Player.surfing=false
  Collision.bindMap(game,"FR_CINNABAR_ISLAND",maps.FR_CINNABAR_ISLAND)
  assert(not Collision.tryConnection(game,14,19,"down",false),"Water became walkable")
  local clock=love.timer.getTime
  love.timer.getTime=function() return 1 end
  View.draw(game)
  local before={}
  for _,id in ipairs({"FR_CINNABAR_ISLAND","FR_ROUTE_49"}) do before[id]=T._pairs[maps[id].pair].image:newImageData():getString() end
  -- FieldView normally marks only the compiled pairs visible. Native sources
  -- must catch up to the same animation counter when the compositor reads them.
  Animation.setVisiblePairs({[maps.FR_CINNABAR_ISLAND.pair]={},[maps.FR_ROUTE_49.pair]={}})
  for i=1,17 do Animation.step() end
  love.timer.getTime=function() return 2 end
  View.draw(game)
  for id,bytes in pairs(before) do
    assert(bytes~=T._pairs[maps[id].pair].image:newImageData():getString(),id.." water did not animate")
  end
  local function tilePixels(id,x,y)
    local ts=T._pairs[maps[id].pair]
    local slot=maps[id].midLayout:midAt(x,y)
    local img=ts.image:newImageData();local tile=love.image.newImageData(16,16)
    tile:paste(img,0,0,slot%ts.cols*16,math.floor(slot/ts.cols)*16,16,16)
    return tile:getString()
  end
  -- Find the same native water metatile on both maps and compare composed pixels.
  local a,b=p.gen3Layered.FR_CINNABAR_ISLAND,p.gen3Layered.FR_ROUTE_49
  local checked=false
  for i,ref in ipairs(a.layers[1].cells) do
    if a.collision[i]=="water" then
      for j,other in ipairs(b.layers[1].cells) do
        if b.collision[j]=="water" and ref.source==other.source and ref.tile==other.tile then
          assert(tilePixels("FR_CINNABAR_ISLAND",(i-1)%a.cellWidth,math.floor((i-1)/a.cellWidth))==tilePixels("FR_ROUTE_49",(j-1)%b.cellWidth,math.floor((j-1)/b.cellWidth)),"Neighbor water is out of sync")
          checked=true;break
        end
      end
    end
    if checked then break end
  end
  assert(checked,"No matching water tiles to compare")
  love.timer.getTime=clock
  local dir=root.."/tests/content-editor/sevii-smoke/output"
  assert(IO.ensureDirectory(dir))
  local png=love.image.newImageData(64,64)
  png:mapPixel(function() return 1,0,1,1 end)
  assert(IO.writeText(dir.."/trainer.png",png:encode("png"):getString()))
  local unique=IO.uniqueAssetPath(dir,"trainer.png")
  assert(unique~="trainer.png" and not IO.exists(dir.."/"..unique),"Import would overwrite an existing file")
  local data={_gen3Read=read}
  local S={data=data,project={game="firered",audio={songs={},sfx={}},gen3Assets={}},path=dir}
  local R=require("Gen3Resources")
  local id,path=assert(R.importTrainerPic(S,dir.."/trainer.png"))
  -- assert() preserves all returns.
  assert(not read(path),"New sprite reused a native slot")
  local id2,path2=R.importTrainerPic(S,dir.."/trainer.png")
  assert(id2>id and path2~=path)
  assert(R.assets(data,S.project)[path] and not R.assets(data)[path],"Custom assets leaked into the base catalog")
  local Writer=require("ModWriter")
  local reopened=assert(loadstring(Writer.serializeProject(S.project)))()
  assert(reopened.gen3Assets[path].width==64)
  local Pic=require("src.core.game3.trainer_pic")
  Pic.install({read=function(_,key) local rec=reopened.gen3Assets[key];return rec and IO.readText(dir.."/"..rec.file) or read(key) end})
  assert(Pic.front(id) and Pic.front(id2),"New trainer sprites were not loadable by the game")
  local Audio=require("Gen3AudioAdapter")
  data.audio={songs={}}
  local song=assert(Audio.nextId(S))
  S.project.audio.songs[song]={file="assets/test.ogg",name="New song"}
  assert(tonumber(Audio.nextId(S))>tonumber(song))
  S.project.audio.mapSongs={FR_ROUTE_49=song};S.project.gen3AudioWorkspace=1
  Audio.compile(S.project)
  assert(S.project.gen3Audio.mapSongs.FR_ROUTE_49==tonumber(song))
  assert(S.project.gen3Audio.songs[song].file=="assets/test.ogg")
  assert(Audio.label(S,"music",song)==song.." · New song")
  assert(not R.nextTrainerPic(data,{gen3Assets={["data/generated/gba/trainers/front/255.rgba"]={width=64,height=64}}}),"Sprite allocator exceeded the runtime schema")
  local templatePath="data/generated/gba/ow/21.rgba"
  local owTemplate=assert(R.assets(data)[templatePath])
  local owPng=love.image.newImageData(owTemplate.width,owTemplate.height)
  owPng:mapPixel(function(x,y) return x/owTemplate.width,(math.floor(y/owTemplate.frameHeight)%3)/2,1,1 end)
  assert(IO.writeText(dir.."/overworld.png",owPng:encode("png"):getString()))
  local OW=require("Gen3Overworld")
  assert(not OW.import(S,dir.."/trainer.png",templatePath),"Wrong overworld sheet dimensions accepted")
  local owId,owPath=OW.import(S,dir.."/overworld.png",templatePath)
  assert(owId and owId<240 and not read(owPath),tostring(owPath))
  local owId2=assert(OW.import(S,dir.."/overworld.png",owPath))
  assert(owId2~=owId and owId2<240)
  local assets=assert(loadstring(Writer.serializeProject(S.project)))().gen3Assets
  assert(assets[owPath].ow.frameCount==owTemplate.frameCount and assets[owPath].metaFile)
  assert(loadstring(require("Gen3").emit({game="firered",gen3Assets=assets},Writer.encodeLua)))
  local Cache=require("src.import.CacheFs")
  Cache.read=read;Cache._contentEditorBridge=nil
  local nativeMod={hooks=mod.hooks,events={on=function() end},read=function(_,rel) return IO.readText(dir.."/"..rel) end}
  assert(loadstring("return function(mod,native) "..require("Gen3Native").source.." end"))()(nativeMod,{assets=assets,items={},help={},animations={},audio={}})
  local Space=require("src.core.game3.scripting.space")
  assert(Space.resolveObjectGraphicsId({graphics=owId})==owId,"Map character still clamps custom graphics to the fallback")
  assert(Space.resolveObjectGraphicsId({graphics=21})==21)
  local Flags=require("src.core.game3.scripting.flags")
  local neighbor={store=Flags.newStore()}
  neighbor.store.vars[0x4010]=owId
  assert(Space.resolveObjectGraphicsId({graphics=240},neighbor)==owId,"Variable-driven custom graphics did not resolve")
  assert(Space.resolveObjectGraphicsId({graphics=21,graphicsVar=0x4010},neighbor)==owId)
  assert(Space.resolveObjectGraphicsId({graphics=240},{store=Flags.newStore()})==nil,"Unset neighbor graphics variables changed behavior")
  local owCache={read=function(_,key) return Cache.read(key) end}
  local OwSprites=require("src.core.game3.ow_sprites")
  OwSprites.install(owCache)
  local sprite=assert(OwSprites.get(owId),"Exported overworld sprite was not loadable by the runtime")
  assert(sprite.width==owTemplate.frameWidth and sprite.height==owTemplate.frameHeight and sprite.frameCount==owTemplate.frameCount)
  assert(sprite.quads[8] and OwSprites.get(21),"New sheet lost walk frames or replaced the original")
  assert(OwSprites._manifest.sprites[owId] and OwSprites._manifest.sprites[owId2])
  local hook,resolveHook=hooks["editor.gen3.cache"],hooks["editor.gen3.ow.resolve"]
  hooks["editor.gen3.cache"]=nil;hooks["editor.gen3.ow.resolve"]=nil
  OwSprites.install(owCache)
  assert(not OwSprites.get(owId) and OwSprites.get(21),"Removing the mod did not restore native sprites")
  assert(Space.resolveObjectGraphicsId({graphics=owId})==16,"Removing the mod did not restore the native resolver")
  hooks["editor.gen3.cache"]=hook
  hooks["editor.gen3.ow.resolve"]=resolveHook
  require("Gen3").load(data,read)
  S.project=require("State").ensureProjectFields(S.project);S.version="firered"
  local Kit=require("Kit")
  local App={markDirty=function() end,pickFile=function(_,_,callback) callback(dir.."/trainer.png") end}
  local canvas=love.graphics.newCanvas(1360,860)
  local trainer={pic=id,name="TEST",class=0,gender=0,items={}}
  for _,panel in ipairs({"Trainer","Audio","Gen3Assets","Overworld"}) do
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.06,.07,.1,1)
    Kit.layout(1360,860);Kit.beginFrame(0,0,false,0)
    if panel=="Trainer" then
      require("Gen3TrainerForms").draw(S,trainer,function() return trainer end,App,30,30,600,"basics")
    elseif panel=="Overworld" then
      S.g3AssetId=owPath;S.g3GfxMode="ow"
      require("Gen3GfxWorkspace").draw(S,20,50,1320,780,App)
      assert(require("Gen3MapSprites").draw(S,{graphicsId=owId},1250,80,{scale=2}),"New sprite missing from map preview")
    else
      S.g3AssetId=path;S.audioMode="music";S.audioId_music=song
      require(panel).draw(S,20,50,1320,780,App)
    end
    Kit.endFrame();love.graphics.setCanvas()
    assert(IO.writeText(dir.."/"..panel..".png",canvas:newImageData():encode("png"):getString()))
  end
  report("PASS: Sevii surf crossings and synchronized water; new trainer and overworld sprites allocate separate slots, survive serialization, and load in the runtime; overworld metadata, walk frames, map previews, and mod removal verified; new music IDs compile and assign to maps; panels render.")
  love.event.quit()
end
