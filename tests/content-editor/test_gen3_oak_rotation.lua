return function(data,root)
  local State,IO=require("State"),require("ModIO")
  local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("oak_rotation");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  S.path=root.."/tests/content-editor/gen3-smoke/oak-rotation"
  assert(IO.ensureDirectory(S.path));assert(IO.writeText(S.path.."/manifest.json",'{"id":"oak_rotation","name":"Test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  S.project.gen3OakScene={species=25,textSpeed=2,skipGuides=true}
  S.project.gen3Oak={welcome="Welcome, {PLAYER}!\nYour rival is {RIVAL}.\fHave fun!"}
  local L=require("LayeredMap")
  local pixels=love.image.newImageData(32,16)
  pixels:mapPixel(function(x,y) return x/31,y/15,0,1 end)
  assert(IO.writeText(S.path.."/original.png",pixels:encode("png"):getString()))
  local original=assert(L.addTileSource(S.project,"TEST","original.png",32,16));original.colorMode="true_color"
  S.builderSourceId=original.id;S.builderStamp={source=original.id,cells={{dx=0,dy=0,tile=0},{dx=1,dy=0,tile=1}}}
  local rotated=require("TileRotation").rotate(S,1)
  assert(rotated.columns==1 and rotated.count==2 and S.builderStamp.cells[2].dy==1)
  local function read(src) return love.image.newImageData(love.filesystem.newFileData(assert(IO.readText(S.path.."/"..src.image)),"tile.png")) end
  local turned=read(rotated);assert(turned:getWidth()==16 and turned:getHeight()==32)
  for y=0,15 do for x=0,31 do
    local r,g=pixels:getPixel(x,y);local rr,gg=turned:getPixel(15-y,x)
    assert(math.abs(r-rr)<.01 and math.abs(g-gg)<.01,"Rotated pixels differ")
  end end
  local back=require("TileRotation").rotate(S,-1);local restored=read(back)
  for y=0,15 do for x=0,31 do local r,g=pixels:getPixel(x,y);local rr,gg=restored:getPixel(x,y);assert(math.abs(r-rr)<.01 and math.abs(g-gg)<.01) end end
  assert(require("Gen3Workspace").convert(S,"FR_PALLET_TOWN"))
  L.setCell(S.project.layeredMaps.FR_PALLET_TOWN,1,0,0,{source=rotated.id,tile=0})
  local map=S.project.layeredMaps.FR_PALLET_TOWN
  L.setCell(map,1,1,0,{source=original.id,tile=0})
  L.setCell(map,1,2,0,{source=original.id,tile=1})
  L.setCollision(map,1,0,"solid")
  S.builderLayer=1;S.builderSelections={{x0=1,y0=0,x1=1,y1=0}}
  local History=require("History");History.resetBaseline(S)
  local app={beginEditBatch=function() History.beginBatch(S) end,endEditBatch=function() History.endBatch(S) end,markDirty=function() History.noteDirty(S) end}
  local oldBrush=S.builderSourceId
  assert(require("TileRotation").rotateSelection(S,map,1,app)==1)
  local selected=L.getCell(map,1,1,0)
  assert(selected.source~=original.id and L.getCell(map,1,2,0).source==original.id,"Rotation changed an unselected cell")
  assert(S.builderSourceId==oldBrush,"Map rotation changed the brush")
  local rotatedPath=S.project.mapTileSources[selected.source].image
  History.endFrame(S);assert(History.undo(S));assert(L.getCell(S.project.layeredMaps.FR_PALLET_TOWN,1,1,0).source==original.id)
  assert(History.redo(S));assert(L.getCell(S.project.layeredMaps.FR_PALLET_TOWN,1,1,0).source==selected.source)
  assert(IO.readText(S.path.."/"..rotatedPath),"Redo lost rotated graphics")
  assert(require("Gen3Workspace").compile(S))
  assert(IO.save(S.path,S.project));local reopened=assert(IO.load(S.path));assert(reopened.gen3Oak.welcome==S.project.gen3Oak.welcome and reopened.gen3OakScene.species==25)
  assert(reopened.mapTileSources[rotated.id].image==rotated.image)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local Scene=require("src.ui.game3.new_game_scene")
  local scene=setmetatable({section="oak",playerName="RED",rivalName="BLUE",win={},textSpeed=0},{__index=Scene})
  scene:oakPrint("welcome",0)
  assert(scene.printer.pages[1]=="Welcome, RED!\nYour rival is BLUE." and scene.printer.pages[2]=="Have fun!")
  local configured=Scene.new({})
  assert(configured.assets.nidoranFront==require("src.core.game3.pokemon").frontPic(25).image)
  assert(configured.textSpeed==1 and configured.tasks[1].func==Scene.Task_OakSpeech_Init)
  configured:destroy()
  require("src.mods.Runtime").reset();scene:oakPrint("welcome",0)
  assert(scene.printer.pages[1]~="Welcome, RED!\nYour rival is BLUE.","Disabled mod leaked Oak text")
  S.tab="ui";S.g3UiMode="oak"
  local intro=require("Gen3IntroPreview");assert(intro.play(S,"oak"))
  for i=1,300 do
    if i%35==0 then S.g3IntroPreview.keys={a=true} end
    intro.step(S,1/60);assert(not S.g3IntroPreview.error,S.g3IntroPreview.error)
    assert(intro.render(S));assert(not S.g3IntroPreview.error,S.g3IntroPreview.error)
  end
  assert(S.g3IntroPreview.oak.section=="oak")
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Gen3Oak").draw(S,20,20,1320,800,{markDirty=function() end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/oak-intro.png",canvas:newImageData():encode("png"):getString()))
  intro.stop(S)
  local Choice=require("ChoicePicker");local originalField=Choice.field
  local selected={}
  Choice.field=function(state,opts)
    if opts.title=="Level-up move" or opts.title=="TM/HM move" then
      assert(#opts.ids>0);selected[opts.title]=opts
    end
    return originalField(state,opts)
  end
  S.pokemonId="ABRA"
  for _,section in ipairs({"learnset","tmhm"}) do
    S.pokemonSection=section
    love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
    require("Pokemon").draw(S,20,20,1320,800,{markDirty=function() end})
    K.endFrame();love.graphics.setCanvas()
  end
  Choice.field=originalField
  assert(selected["Level-up move"] and selected["TM/HM move"],"Pokemon move dropdown missing")
  selected["Level-up move"].onPick("TACKLE")
  selected["TM/HM move"].onPick(selected["TM/HM move"].ids[1])
  assert(S.project.pokemon.ABRA,"Dropdown edit did not create an editable Pokemon")
  assert(IO.save(S.path,S.project));local saved=assert(IO.load(S.path))
  assert(saved.pokemon.ABRA.learnset[1].move=="TACKLE","Move dropdown did not persist")
end
