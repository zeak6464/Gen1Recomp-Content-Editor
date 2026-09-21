local Kit = require("Kit")
local RegList = require("RegList")
local Gen3 = require("Gen3")
local Preview = require("Preview")
local Panel = {}

local function picture(S,path)
  if type(path) ~= "string" then return end
  if path:match("%.rgba$") then
    S._g3Images=S._g3Images or {}
    if S._g3Images[path] then return S._g3Images[path] end
    local bytes=S.data._gen3Read and S.data._gen3Read(path)
    if bytes and #bytes==64*64*4 then
      local image=love.graphics.newImage(love.image.newImageData(64,64,"rgba8",bytes))
      image:setFilter("nearest","nearest");S._g3Images[path]=image;return image
    end
  else return Preview.image(S,path) end
end

function Panel.draw(S,x,y,w,h,App)
  if not S.project then Kit.caption(x,y,"Open a mod to edit battle sprites");return end
  require("Gen3ContentAdapter").prepare(S)
  local s=Kit.scale
  S._gen3Catalog=S._gen3Catalog or {}
  local catalog=S._gen3Catalog.pokemon or Gen3.catalog(S.data,"pokemon")
  S._gen3Catalog.pokemon=catalog
  local patches=S.project.pokemon
  local ids=RegList.mergeIds(patches,catalog)
  S.g3SpriteId=S.g3SpriteId or (catalog.MEW and "MEW") or ids[1]
  local fx,fw=RegList.drawList(S,App,x,y,w,h,"Battle sprites",ids,
    {selKey="g3SpriteId",queryKey="g3SpriteQuery",offsetKey="g3SpriteOffset"})
  local id=S.g3SpriteId
  if not id or (not catalog[id] and not patches[id]) then return end
  local patch=patches[id] or {}
  local rec={};for k,v in pairs(catalog[id] or {}) do rec[k]=v end;for k,v in pairs(patch) do rec[k]=v end
  Kit.caption(fx,y,id .. " — FireRed 64 x 64 battle sprites")
  for i,side in ipairs({"Front","Back"}) do
    local xx=fx+(i-1)*fw/2
    local key="sprite"..side
    local path=rec[key.."64"] or rec[key]
    Kit.caption(xx,y+35*s,side)
    local img=picture(S,path)
    local size=math.min(192*s,fw/2-20*s)
    Kit.card(xx,y+65*s,size,size)
    if img then
      love.graphics.setColor(1,1,1,1)
      local iw,ih=img:getDimensions();local scale=math.min(size/iw,size/ih)
      love.graphics.draw(img,xx+(size-iw*scale)/2,y+65*s+(size-ih*scale)/2,0,scale,scale)
    end
    if Kit.button(xx,y+80*s+size,size,30*s,"Import "..side.." PNG",{kind="primary"}) then
      App.pickFile("Choose 64 x 64 "..side.." sprite","PNG (*.png)|*.png",function(picked)
        local bytes=require("ModIO").readText(picked)
        local ok, imageData=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"sprite.png")) end)
        if not ok or imageData:getWidth()~=64 or imageData:getHeight()~=64 then
          S.status="FireRed battle sprites must be 64 x 64 PNGs";return
        end
        App.importToMod(picked,"assets/"..id:lower().."_"..side:lower().."_gen3.png",function(rel)
          local value=require("src.mods.Merge").deepCopy(rec)
          value[key],value[key.."64"]=rel,rel
          S.project.gen3=S.project.gen3 or {};S.project.gen3.pokemon=S.project.gen3.pokemon or {}
          S.project.pokemon[id]=value
          S.project.gen3Modes=S.project.gen3Modes or {};S.project.gen3Modes.pokemon=S.project.gen3Modes.pokemon or {}
          S.project.gen3Modes.pokemon[id]="override"
          Preview.invalidate();App.markDirty()
        end)
      end)
    end
  end
  Kit.caption(fx,y+310*s,"Imports are copied into this mod. Save to apply in game.")
end

return Panel
