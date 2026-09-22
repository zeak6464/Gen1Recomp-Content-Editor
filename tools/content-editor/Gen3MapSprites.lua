-- Draw a native overworld frame at the map cell's feet, at its original size.
local M={}
function M.draw(S,obj,x,y,opts)
  local id=tonumber(obj.graphicsId or obj.graphics)
  if not id then return false end
  local path="data/generated/gba/ow/"..id..".rgba"
  local meta=require("Gen3Resources").assets(S.data)[path]
  if not meta or not meta.frameWidth or not meta.frameHeight then return false end
  local override=S.project and (S.project.gen3Assets or {})[path]
  local cache=S._mapOwSprites
  if not cache or cache.data~=S.data or cache.project~=S.project or cache.path~=S.path then
    cache={data=S.data,project=S.project,path=S.path,images={}};S._mapOwSprites=cache
  end
  local rec=cache.images[id]
  if not rec or rec.override~=override then
    local bytes=override and require("ModIO").readText(S.path.."/"..override.file) or S.data._gen3Read(path)
    if not bytes then return false end
    local width=override and override.width or meta.width
    if not width or #bytes%(width*4)~=0 then return false end
    local height=#bytes/(width*4)
    if width<meta.frameWidth or height<meta.frameHeight then return false end
    local image=love.graphics.newImage(love.image.newImageData(width,height,"rgba8",bytes));image:setFilter("nearest","nearest")
    rec={image=image,override=override,quad=love.graphics.newQuad(0,0,meta.frameWidth,meta.frameHeight,width,height)};cache.images[id]=rec
  end
  love.graphics.setColor(1,1,1,1)
  local scale=opts and opts.scale or 1
  love.graphics.draw(rec.image,rec.quad,x+(16-meta.frameWidth)*scale/2,y+(16-meta.frameHeight)*scale,0,scale,scale)
  return true
end
return M
