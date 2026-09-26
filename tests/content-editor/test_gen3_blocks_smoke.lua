-- GFX > Blocks end to end: edit blocks and paint tiles in the editor, save the
-- mod, load it through the real mod loader, and check the game's atlas.
return function(data,root,game)
  local L,G,B,IO=require("LayeredMap"),require("Gen3Workspace"),require("Gen3Blocks"),require("ModIO")
  local T=require("src.core.game3.tileset_native")
  local S={data=data,version=game,project=require("State").blankProject("block_test")};S.project.game=game;G.prepare(S)
  S.path=root.."/tests/content-editor/blocks-smoke/project";IO.ensureDirectory(S.path.."/assets")
  local P=data.maps.FR_PALLET_TOWN.pair
  assert(B.pack(S,P),"Game cache not readable")
  local tiles=B.gameTiles(S,P);assert(#tiles>100,"Too few tiles found in the saved blocks")

  -- Your own tile, a painted copy of a game tile, and blocks using them.
  local good={}
  for i=1,8 do good[i]=tiles[i*9].key end
  local mine=assert(B.newTile(S,P,nil))
  for i=1,64 do B.setPixel(S,P,mine,i,(i%8<4) and 6 or 1) end
  local newMid=assert(B.newBlock(S,P,{layerType="covered",behavior=0x02,slots={
    {tile=mine},{tile=good[3],pal=2,hflip=true},{tile=mine,vflip=true},{tile=good[4],pal=1},
    {tile=good[5],pal=3},{tile=false},{tile=false},{tile=good[6],pal=4}}}))
  local tree=B.definition(S,P,20)
  local copy=assert(B.newTile(S,P,tree.slots[2].tile))
  for i=1,8 do B.setPixel(S,P,copy,i*8,5) end
  tree.slots[2].tile=copy;tree.slots[1].hflip=not tree.slots[1].hflip;tree.slots[4].pal=5
  assert(B.store(S,P,20,tree))
  local b1=B.definition(S,P,1);b1.behavior=0x13;assert(B.store(S,P,1,b1))
  -- A tile number from the first, ROM-based version can't be drawn now.
  local badMid=assert(B.newBlock(S,P,{slots={{tile=245}}}))
  assert(#B.problems(S,P,badMid)==1,"Old tile number not flagged")
  assert(B.customTile(S.project,P,copy).px:gsub("%.",""):len()==8,"A painted copy must store only the painted pixels")

  -- The map editor lists and draws them.
  local ids=L.uniqueTiles(S,{nativePair=P});local listed=false
  for _,id in ipairs(ids) do if id==newMid then listed=true end end
  assert(listed,"New block missing from the map editor's picker")
  assert(G.descriptor(S,P).count>badMid,"Assembly sheet doesn't reach new blocks")

  local source,map=L.createMap(S,"BLOCK_TEST",4,4,P)
  for y=0,3 do for x=0,3 do L.setCell(source,1,x,y,{source=L.runtimeSourceId(P),tile=21});L.setCollision(source,x,y,"walk") end end
  L.setCell(source,1,1,1,{source=L.runtimeSourceId(P),tile=newMid})
  L.setCell(source,1,2,1,{source=L.runtimeSourceId(P),tile=20})

  assert(IO.writeText(S.path.."/manifest.json",'{"id":"block_test","name":"Block test","version":"1.0.0","entry":"main.lua","games":["'..game..'"]}'))
  assert(L.compileProject(S));assert(IO.save(S.path,S.project))
  local reopened=assert(IO.load(S.path))
  assert(reopened.gen3Blocks[P][tostring(newMid)] and reopened.gen3Tiles[P][tostring(copy)],"Blocks or tiles not saved")
  local rt=assert(reopened.gen3BlockRuntime,"Runtime data not saved")
  assert(rt.pairs[P][newMid].slots and rt.pairs[P][20].slots,"Rebuildable blocks lost their slots")
  assert(rt.pairs[P][1].slots==nil and rt.pairs[P][badMid].slots==nil,"Blocks the game keeps or can't build must not carry slots")
  -- Recipes only: numbers, flags and names. The one long string allowed is
  -- a tile the modder painted.
  local function walk(v,path)
    if type(v)=="table" then for k,x in pairs(v) do walk(k,path);walk(x,path.."."..tostring(k)) end
    elseif type(v)=="string" then assert(#v<=64,"Long string in runtime data at "..path)
    else assert(type(v)=="number" or type(v)=="boolean") end
  end
  walk(rt,"gen3BlockRuntime")

  -- Load it the way the game does.
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local g={data=fresh};for _,entry in ipairs(loader.events.listeners["game.ready"] or {}) do entry.callback({game=g}) end
  for _,message in ipairs(loader:status().errors or {}) do error(tostring(message)) end

  local ts=assert(T.get(P));assert(ts._g3Blocks,"Tileset not patched")
  local NativePack=require("src.import.gba.native_pack")
  local rgb=NativePack.palsToRgb8(ts.bgr)
  local function expect(v,transparentZero)
    if transparentZero and v==0 then return 0,0,0,0 end
    local c=rgb[math.floor(v/16)][v%16];return c[1],c[2],c[3],255
  end
  local function same(image,sx,sy,idx,transparentZero)
    for i=1,256 do
      local x,y=sx+(i-1)%16,sy+math.floor((i-1)/16)
      local r,gg,b,a=image:getPixel(x,y)
      local R,G2,B2,A=expect(idx[i] or 0,transparentZero)
      if math.floor(r*255+.5)~=R or math.floor(gg*255+.5)~=G2 or math.floor(b*255+.5)~=B2 or math.floor(a*255+.5)~=A then return false end
    end
    return true
  end
  for _,mid in ipairs({newMid,20}) do
    local slot=assert(ts.midToSlot[mid],"Block "..mid.." missing from the atlas")
    local u,o=B.composeBlock(S,P,B.definition(S,P,mid))
    local sx,sy=slot%ts.cols*16,math.floor(slot/ts.cols)*16
    assert(same(ts.imageData,sx,sy,u,false),"Block "..mid.." under-layer differs in game")
    assert(same(ts.overImageData,sx,sy,o,true),"Block "..mid.." over-layer differs in game")
  end
  assert(ts.midToSlot[badMid]==nil,"Unbuildable block was drawn")
  local I=require("src.core.game3.scripting.interaction_scripts")
  assert(I.behaviors[P][1]==0x13 and I.behaviors[P][newMid]==0x02,"Behaviours not applied")

  -- The editor-built map draws the new block from the patched atlas.
  local def=fresh.maps[map.id];local lts=T.get(def.pair)
  local slot=T.slotFor(lts,def.midLayout:midAt(1,1))
  local u=B.composeBlock(S,P,B.definition(S,P,newMid))
  assert(same(lts.image:newImageData(),slot%lts.cols*16,math.floor(slot/lts.cols)*16,u,false),"Layered map lost the new block")

  -- Reloading tilesets keeps the blocks.
  T.invalidate();local again=assert(T.get(P));assert(again._g3Blocks and again.midToSlot[newMid],"Blocks lost after a tileset reload")

  -- The Blocks screen draws with a block, a slot of your tile and the pixel editor open.
  require("src.mods.Runtime").reset()
  S.g3GfxMode="blocks";S.g3BlockPair=P;S._g3BlockLastPair=P;S.g3BlockId=20;S.g3BlockSlot=2
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,960)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,960);K.beginFrame(0,0,false,0)
  require("Gen3GfxWorkspace").draw(S,20,20,1320,920,{markDirty=function() end,beginEditBatch=function() end,endEditBatch=function() end,pickFile=function() end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/blocks-smoke/editor.png",canvas:newImageData():encode("png"):getString()))
end
