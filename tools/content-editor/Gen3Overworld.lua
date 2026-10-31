-- Custom overworld sprites.
--  * Any sheet layout: one frame, a column, a row or a grid of 16x16, 16x32,
--    32x32 or 64x64 frames (auto-detected, or picked by the modder).
--  * Every import is registered in project.gen3Assets (that record is what
--    the game reads), and files left on disk without a record are relinked.
--  * IDs: free slots below 240 first, then 256 and up. 240-255 are the game's
--    script-controlled sprite slots and are never used. The exported runtime
--    hands custom IDs to the game before Emerald / FR-LG clamp them.
local M={}
local ROOT="data/generated/gba/ow/"
local DIR="assets/gen3/ow"
M.SIZES={{16,16},{16,32},{32,32},{64,64}}
M.SIZE_CHOICES={{id="auto",label="Auto"},{id="16x16",label="16 x 16"},{id="16x32",label="16 x 32"},
  {id="32x32",label="32 x 32"},{id="64x64",label="64 x 64"}}
M.MAX_FRAMES=512
M.MAX_ID=65535

function M.validId(id)
  id=tonumber(id)
  return id~=nil and id%1==0 and id>=0 and id<=M.MAX_ID and not (id>=240 and id<=255)
end

function M.isCustom(rec) return type(rec)=="table" and type(rec.ow)=="table" and rec.metaFile~=nil end

-- 9 frames is the walking set, 3 the surfing / mount set, 1 a still sprite.
local function rank(c) return c.count==9 and 0 or c.count==1 and 1 or c.count==3 and 2 or 3 end

--- Work out the frames of a w x h sheet. sizeId: "auto" or "16x32" etc.
-- Returns {fw,fh,cols,rows,count,mode} or nil, message.
function M.layout(w,h,sizeId)
  local explicit=sizeId and sizeId~="auto"
  local sizes=M.SIZES
  if explicit then
    local a,b=tostring(sizeId):match("^(%d+)x(%d+)$")
    if not a then return nil,"Unknown frame size "..tostring(sizeId) end
    sizes={{tonumber(a),tonumber(b)}}
  end
  local cands={}
  for _,sz in ipairs(sizes) do
    local fw,fh=sz[1],sz[2]
    if w>=fw and h>=fh and w%fw==0 and h%fh==0 then
      local cols,rows=w/fw,h/fh
      local mode=(cols==1 and rows==1) and "single" or (cols==1 and "column") or (rows==1 and "row") or "grid"
      local c={fw=fw,fh=fh,cols=cols,rows=rows,count=cols*rows,mode=mode}
      -- A grid is only guessed when it makes the standard 9 frames.
      if c.count<=M.MAX_FRAMES and (explicit or mode~="grid" or c.count==9) then cands[#cands+1]=c end
    end
  end
  if #cands==0 then
    if explicit then return nil,w.." x "..h.." doesn't split into "..sizeId.." frames" end
    return nil,"Couldn't find the frames in a "..w.." x "..h.." image. Pick the frame size above (16x16, 16x32, 32x32 or 64x64)."
  end
  table.sort(cands,function(a,b)
    local ra,rb=rank(a),rank(b)
    if ra~=rb then return ra<rb end
    if a.fh~=b.fh then return a.fh>b.fh end -- 16x32 people before 16x16
    return a.fw>b.fw
  end)
  return cands[1]
end

M.MODE_TEXT={single="a single frame",column="a column",row="a row",grid="a grid (left to right, top to bottom)"}

--- Restack the frames into the game's layout: one column, frame 0 at the top.
function M.stack(img,L)
  local out=love.image.newImageData(L.fw,L.fh*L.count,"rgba8")
  for i=0,L.count-1 do
    local sx=(i%L.cols)*L.fw
    local sy=math.floor(i/L.cols)*L.fh
    local dy=i*L.fh
    for yy=0,L.fh-1 do
      for xx=0,L.fw-1 do
        out:setPixel(xx,dy+yy,img:getPixel(sx+xx,sy+yy))
      end
    end
  end
  return out
end

--- Read a PNG into ImageData.
function M.readPng(picked)
  local IO=require("ModIO")
  local bytes,err=IO.readText(picked)
  if not bytes then return nil,err or "Couldn't read the file" end
  local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"overworld.png")) end)
  if not ok then return nil,"That file isn't a PNG the editor can read" end
  return img
end

local function taken(S,catalog,n)
  local IO=require("ModIO")
  local key=ROOT..n
  local file=S.path.."/"..DIR.."/"..n
  return catalog[key..".rgba"]~=nil
    or (S.data._gen3Read and (S.data._gen3Read(key..".rgba") or S.data._gen3Read(key..".meta")))
    or IO.exists(file..".rgba") or IO.exists(file..".meta")
end

function M.freeId(S)
  local catalog=require("Gen3Resources").assets(S.data,S.project)
  for n=0,239 do if not taken(S,catalog,n) then return n end end
  for n=256,M.MAX_ID do if not taken(S,catalog,n) then return n end end
  return nil
end

--- Save stacked frames as sprite `opts.id` (replace) or a new ID.
function M.save(S,stacked,L,opts)
  opts=opts or {}
  local IO=require("ModIO")
  local id=opts.id or M.freeId(S)
  if not M.validId(id) then return nil,"No free overworld sprite ID is left" end
  local path=ROOT..id..".rgba"
  local rel=DIR.."/"..id
  local width,height=L.fw,L.fh*L.count
  local meta={graphicsId=id,width=L.fw,height=L.fh,frameCount=L.count,inanimate=L.count==1,
    paletteTag=0,atlasW=width,atlasH=height}
  local encoded=require("src.import.gba.ow_extract").encodeMeta(meta)
  local ok,why=IO.ensureDirectory(S.path.."/"..DIR)
  if not ok then return nil,why end
  ok,why=IO.writeText(S.path.."/"..rel..".rgba",stacked:getString())
  if not ok then return nil,why end
  ok,why=IO.writeText(S.path.."/"..rel..".meta",encoded)
  if not ok then return nil,why end
  S.project.gen3Assets=S.project.gen3Assets or {}
  local old=S.project.gen3Assets[path]
  local name=opts.name and opts.name:match("^%s*(.-)%s*$")
  if not name or name=="" then name=(old and old.name) or ("Custom sprite "..id) end
  S.project.gen3Assets[path]={file=rel..".rgba",metaFile=rel..".meta",width=width,height=height,ow=meta,name=name}
  return id,path
end

--- Remove a custom sprite: its record and its files.
function M.delete(S,path)
  local rec=S.project.gen3Assets and S.project.gen3Assets[path]
  if not M.isCustom(rec) then return false end
  S.project.gen3Assets[path]=nil
  os.remove(S.path.."/"..rec.file)
  os.remove(S.path.."/"..rec.metaFile)
  return true
end

--- Register sprite files in assets/gen3/ow that have no record in the
-- project (e.g. an import that was never saved). Game sprites are skipped.
function M.relink(S)
  local IO=require("ModIO")
  local dir=S.path.."/"..DIR
  if not (S.project and IO.isDirectory and IO.isDirectory(dir)) then return 0 end
  local OwX=require("src.import.gba.ow_extract")
  S.project.gen3Assets=S.project.gen3Assets or {}
  local count=0
  for _,file in ipairs(IO.directoryNames(dir)) do
    local id=tonumber(file:match("^(%d+)%.meta$"))
    local path=id and ROOT..id..".rgba"
    if id and M.validId(id) and not S.project.gen3Assets[path]
        and not (S.data._gen3Read and S.data._gen3Read(path)) then
      local meta=OwX.decodeMeta(IO.readText(dir.."/"..file) or "")
      local bytes=IO.readText(dir.."/"..id..".rgba")
      if meta and bytes and meta.width>0 and meta.height>0 and meta.frameCount>0
          and #bytes==meta.width*meta.height*meta.frameCount*4 then
        local w,h=meta.width,meta.height*meta.frameCount
        S.project.gen3Assets[path]={file=DIR.."/"..id..".rgba",metaFile=DIR.."/"..id..".meta",width=w,height=h,
          ow={graphicsId=id,width=meta.width,height=meta.height,frameCount=meta.frameCount,
            inanimate=meta.inanimate==true,paletteTag=meta.paletteTag or 0,atlasW=w,atlasH=h},
          name="Custom sprite "..id}
        count=count+1
      end
    end
  end
  return count
end

-- Kept for older callers: import with a template's frame size.
function M.import(S,picked,templatePath)
  local img,err=M.readPng(picked)
  if not img then return nil,err end
  local t=require("Gen3Resources").assets(S.data,S.project)[templatePath]
  local size=t and t.frameWidth and (t.frameWidth.."x"..t.frameHeight) or "auto"
  local L,why=M.layout(img:getWidth(),img:getHeight(),size)
  if not L then L,why=M.layout(img:getWidth(),img:getHeight(),"auto") end
  if not L then return nil,why end
  return M.save(S,M.stack(img,L),L,{name=picked:match("([^/\\]+)%.[^.]+$")})
end

return M
