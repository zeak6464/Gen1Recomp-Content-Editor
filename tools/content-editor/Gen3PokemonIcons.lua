local M={}
local IO=require("ModIO")
function M.path(index,shiny)
  assert(type(index)=="number" and index>=0 and index%1==0,"Invalid species index")
  return "data/generated/gba/pokemon/icons/"..(shiny and "shiny/" or "")..index..".rgba"
end
function M.sourceIndex(S,index)
  for parent,family in pairs((S.project or {}).gen3Forms or {}) do
    local base=(S.project.pokemon or {})[parent] or (S.data.pokemon or {})[parent]
    for i,row in ipairs(family.forms) do
      local rec=(S.project.pokemon or {})[row.species] or (S.data.pokemon or {})[row.species]
      if rec and rec.index==index and row.species~=parent then
        return parent=="UNOWN" and i<=28 and (411+i) or (base and base.index),base and base.index
      end
    end
  end
end
function M.read(S,index,shiny,inheritedOnly)
  local path=M.path(index,shiny)
  local asset=((S.project or {}).gen3Assets or {})[path]
  if asset then return IO.readText(S.path.."/"..asset.file) end
  local bytes=S.data._gen3Read and S.data._gen3Read(path)
  if bytes then return bytes end
  local source,base=M.sourceIndex(S,index)
  -- Native Unown artwork slots can be previewed without a custom family.
  if not source and index>=413 and index<=439 then source=201 end
  if source and source~=index then
    local inherited=((S.project or {}).gen3Assets or {})[M.path(source,shiny)]
    if inherited then return IO.readText(S.path.."/"..inherited.file) end
    local inheritedBytes=S.data._gen3Read and S.data._gen3Read(M.path(source,shiny))
    if inheritedBytes then return inheritedBytes end
    if base and base~=source and base~=index then
      local baseBytes=M.read(S,base,shiny,true);if baseBytes then return baseBytes end
    end
  end
  if shiny and not inheritedOnly then return M.read(S,index,false) end
end
function M.import(S,index,picked,shiny)
  if not S.path then return nil,"Save the project before importing an icon" end
  local ok,img=pcall(function()
    return love.image.newImageData(love.filesystem.newFileData(assert(IO.readText(picked)),"icon.png"))
  end)
  if not ok or img:getWidth()~=32 or (img:getHeight()~=32 and img:getHeight()~=64) then
    return nil,"Party icons must be 32 × 32 or 32 × 64 PNGs (two stacked frames)"
  end
  local path=M.path(index,shiny)
  local dir="assets/gen3/pokemon/icons/"..(shiny and "shiny/" or "")
  local rel=dir..index..".rgba"
  IO.ensureDirectory(S.path.."/"..dir)
  local saved,err=IO.writeText(S.path.."/"..rel,img:getString())
  if not saved then return nil,err end
  S.project.gen3Assets=S.project.gen3Assets or {}
  S.project.gen3Assets[path]={file=rel,width=32,height=img:getHeight()}
  S.data._g3IconImages=nil
  return true
end
function M.export(S,index,shiny)
  if not S.path then return nil,"Save the project before exporting an icon" end
  local bytes,err=M.read(S,index,shiny)
  if not bytes then return nil,err or "Party icon is missing" end
  if #bytes~=32*32*4 and #bytes~=32*64*4 then return nil,"Invalid party icon data" end
  local img=love.image.newImageData(32,#bytes/128,"rgba8",bytes)
  local dest=S.path.."/assets/gen3-export/pokemon/icons/"..(shiny and "shiny/" or "")..index..".png"
  IO.ensureDirectory(dest:match("^(.*)/"))
  local saved,writeErr=IO.writeText(dest,img:encode("png"):getString())
  if not saved then return nil,writeErr end
  return dest
end
function M.revert(S,index,shiny)
  if S.project.gen3Assets then S.project.gen3Assets[M.path(index,shiny)]=nil end
  S.data._g3IconImages=nil
end
function M.drawControls(S,index,App,x,y,w,h,s,shiny)
  local K=require("Kit")
  local bw=(w-16*s)/3
  if K.button(x,y,bw,h,"Import icon",{tooltip="32 × 32 PNG, or 32 × 64 with two stacked frames"}) then
    App.pickFile("Import "..(shiny and "shiny " or "").."party icon (32 × 32 or 32 × 64)","PNG (*.png)|*.png",function(picked)
      if not picked then return end
      local ok,err=M.import(S,index,picked,shiny)
      if ok then App.markDirty();S.status=shiny and "Imported shiny preview icon; Save to keep it in this project" or "Imported party icon; Save to apply in game"
      else S.status=tostring(err) end
    end)
  end
  if K.button(x+bw+8*s,y,bw,h,"Export icon",{}) then
    local dest,err=M.export(S,index,shiny)
    S.status=dest and ("Exported "..dest) or tostring(err)
  end
  if K.button(x+2*(bw+8*s),y,bw,h,"Revert icon",{
    enabled=(S.project.gen3Assets or {})[M.path(index,shiny)]~=nil,
  }) then
    M.revert(S,index,shiny);App.markDirty();S.status="Restored original "..(shiny and "shiny " or "").."party icon"
  end
end
return M
