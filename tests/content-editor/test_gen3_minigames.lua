return function(data,root)
 local S=require("State").new();S.data=data;S.project=require("State").blankProject("mini_preview");S.version="firered"
 local M=require("Gen3MinigameImages");local K=require("Kit")
 for game,rows in pairs(M.assets) do
  for i,rec in ipairs(rows) do local img,err=M.image(S,game,i);assert(img,game.."/"..rec.name..": "..tostring(err));assert(img:getWidth()==rec.width and img:getHeight()==rec.height) end
  S.g3Minigame=game;S.g3MinigameImage="1";S.g3MinigameView="images"
  local canvas=love.graphics.newCanvas(1360,860);love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0);require("Gen3Minigames").draw(S,20,80,1320,740,{});K.endFrame();love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/minigame-"..game..".png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
 end
 local Preview=require("Gen3MinigamePreview")
 S.tab="ui";S.g3UiMode="minigames";S.g3MinigameView="playback"
 local before=require("ModWriter").encodeLua(S.project)
 for _,game in ipairs({"slots","crush","jump","dodrio"}) do
  local p=assert(Preview.start(S,game))
  local first=assert(Preview.render(S)):newImageData():getString()
  local changed=false
  for i=1,90 do Preview.update(S,1/60);local canvas=assert(Preview.render(S));if i==19 then changed=canvas:newImageData():getString()~=first end end
  assert(p.frame==90)
  assert(changed,"Animation stayed still: "..game)
  p.paused=true;Preview.update(S,1);assert(p.frame==90,"Paused preview advanced")
  Preview.step(S);assert(p.frame==91)
  p.paused=false;p.speed=2;Preview.update(S,1/60);assert(p.frame==93)
  p.frame=359;Preview.step(S);assert(p.frame==0)
  p.frame=65;S.g3Minigame=game
  local canvas=love.graphics.newCanvas(1360,860);love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0);require("Gen3Minigames").draw(S,20,80,1320,740,{});K.endFrame()
  assert(love.graphics.getCanvas()==canvas,"Preview lost the editor render target");love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/minigame-play-"..game..".png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
  Preview.stop(S)
 end
 assert(require("ModWriter").encodeLua(S.project)==before,"Playback changed the mod")
 Preview.start(S,"slots");S.tab="maps";Preview.update(S,1/60);assert(S.g3MinigamePreview==nil,"Playback did not stop on tab change")
end