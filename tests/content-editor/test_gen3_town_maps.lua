return function(data,root)
  local State=require("State");local S=State.new()
  S.data=data;S.version="firered";S.project=State.blankProject("town_maps_test")
  local Rom=require("Gen3Rom");local seen={};local sheet=love.graphics.newCanvas(480,320)
  local K=require("Kit")
  for i,region in ipairs(Rom.townMapKeys) do
    local pixels=assert(Rom.townMap(S,region));assert(pixels:getWidth()==240 and pixels:getHeight()==160)
    local bytes=pixels:encode("png"):getString();assert(not seen[bytes],"Duplicate region artwork");seen[bytes]=true
    love.graphics.setCanvas(sheet);love.graphics.setColor(1,1,1,1)
    love.graphics.draw(love.graphics.newImage(pixels),((i-1)%2)*240,math.floor((i-1)/2)*160)
    S.g3TownRegion=region;love.graphics.setCanvas();love.graphics.clear(.04,.06,.12,1)
    K.beginFrame(0,0,false,0)
    require("Gen3UiContent").draw(S,20,20,1320,850,{markDirty=function() end},"town")
    K.endFrame();assert(not S.g3UiContentError,S.g3UiContentError)
  end
  love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/town-maps.png","wb"))
  f:write(sheet:newImageData():encode("png"):getString());f:close()
end

