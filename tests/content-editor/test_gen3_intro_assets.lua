return function(data,root)
  local IO,State=require("ModIO"),require("State");local p=State.blankProject("intro_assets_test");p.game="firered"
  local path=root.."/tests/content-editor/gen3-smoke/intro-assets-project";assert(IO.ensureDirectory(path.."/assets"))
  assert(IO.writeText(path.."/manifest.json",'{"id":"intro_assets_test","name":"Intro assets test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  local fixture=love.image.newImageData(240,160)
  fixture:mapPixel(function(x,y) if y>=30 and y<114 then return 1,.2,.8,1 end;return 0,0,0,1 end)
  local bytes=fixture:encode("png"):getString()
  assert(IO.writeText(path.."/assets/border.png",bytes))
  p.gen3Assets={["data/generated/gba/intro/title_border_bg.png"]={file="assets/border.png",width=240,height=160}}
  assert(IO.save(path,p))
  local Boot=require("src.ui.game3.boot");local before=Boot.new()
  local fresh={};require("Gen3").load(fresh,data._gen3Read);assert(require("Gen3Mod").load(fresh,path))
  local state=Boot.new();assert(state.titleBorder==state.assets.titleBorder)
  local canvas=love.graphics.newCanvas(240,160);love.graphics.setCanvas(canvas);love.graphics.clear();love.graphics.setColor(1,1,1,1);love.graphics.draw(state.titleBorder);love.graphics.setCanvas()
  local expected=love.image.newImageData(love.filesystem.newFileData(bytes,"expected.png"))
  local pixels=canvas:newImageData();for _,pos in ipairs({{20,20},{100,80},{210,140}}) do
    local a,b,c=pixels:getPixel(unpack(pos));local x,y,z=expected:getPixel(unpack(pos));assert(math.abs(a-x)<.01 and math.abs(b-y)<.01 and math.abs(c-z)<.01,"Boot ignored mod image")
  end
  -- Boot state created before mod loading also gets the replacement.
  require("src.ui.game3.title_screen").enter(before);assert(before.titleBorder==state.titleBorder)
  local Title=require("src.ui.game3.title_screen");local Audio=require("src.core.game3.audio");local song=Audio.playSong;Audio.playSong=function() end
  for i=1,360 do Title.update(before,nil,1/60) end
  Audio.playSong=song
  love.graphics.setCanvas(canvas);love.graphics.clear();Title.draw(before);love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/title-replacement.png",canvas:newImageData():encode("png"):getString()))
  local rendered=canvas:newImageData();local pink=0
  for y=30,113 do for x=0,239 do local r,g,b=rendered:getPixel(x,y);if r>.8 and g<.5 and b>.6 then pink=pink+1 end end end
  assert(pink>1000,"Title renderer ignored replacement")
  Title.leave(before)
  require("src.mods.Runtime").reset();local reset=Boot.new();assert(reset.titleBorder~=state.titleBorder)
end
