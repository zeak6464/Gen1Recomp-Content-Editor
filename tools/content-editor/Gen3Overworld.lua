-- Additional native overworld sheets, using an existing sheet as the layout template.
local M={}
function M.import(S,picked,templatePath)
  local IO=require("ModIO")
  local R=require("Gen3Resources")
  local template=R.assets(S.data,S.project)[templatePath]
  if not template or not template.frameWidth or not template.frameHeight or not template.frameCount then
    return nil,"Select an overworld sprite as the frame layout template"
  end
  local bytes,err=IO.readText(picked)
  if not bytes then return nil,err end
  local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"overworld.png")) end)
  local width,height=template.frameWidth,template.frameHeight*template.frameCount
  if not ok or img:getWidth()~=width or img:getHeight()~=height then
    return nil,"Use a "..width.." x "..height.." PNG with "..template.frameCount.." frames stacked vertically, matching the selected sprite"
  end
  local catalog=R.assets(S.data,S.project)
  local id,path,rel
  -- 240..255 are variable-driven graphics IDs, not ordinary sprite slots.
  for n=0,239 do
    local key="data/generated/gba/ow/"..n
    local file="assets/gen3/ow/"..n
    if not catalog[key..".rgba"] and not (S.data._gen3Read and (S.data._gen3Read(key..".rgba") or S.data._gen3Read(key..".meta")))
        and not IO.exists(S.path.."/"..file..".rgba") and not IO.exists(S.path.."/"..file..".meta") then
      id,path,rel=n,key..".rgba",file;break
    end
  end
  if not id then return nil,"No unused overworld sprite IDs below 240 remain" end
  local meta={graphicsId=id,width=width,height=template.frameHeight,frameCount=template.frameCount,
    inanimate=template.inanimate==true,paletteTag=template.paletteTag or 0,atlasW=width,atlasH=height}
  local encoded=require("src.import.gba.ow_extract").encodeMeta(meta)
  local saved,why=IO.ensureDirectory(S.path.."/assets/gen3/ow")
  if not saved then return nil,why end
  saved,why=IO.writeText(S.path.."/"..rel..".rgba",img:getString())
  if not saved then return nil,why end
  saved,why=IO.writeText(S.path.."/"..rel..".meta",encoded)
  if not saved then return nil,why end
  S.project.gen3Assets=S.project.gen3Assets or {}
  S.project.gen3Assets[path]={file=rel..".rgba",metaFile=rel..".meta",width=width,height=height,ow=meta}
  return id,path
end
return M
