-- Preview-only adapter for DBK/g9 sprite components. Never writes sprite
-- paths into runtime records: the mod still owns its rendering hooks.
local M={}
local revision=0
function M.invalidate() revision=revision+1 end
local function read(path) return require("ModIO").readText(path) end
local function decode(path)
  local bytes=read(path)
  if not bytes then return end
  return require("Gen3Decode").decode(bytes,{allowComments=true,allowArray=true,
    maxBytes=8*1024*1024,maxNodes=200000,maxTableEntries=100000})
end
local function state(S)
  if not (S and S.path and S.data) then return end
  local c=S.data._modPokemonArt
  if c and c.path==S.path and c.revision==revision then return c end
  c={path=S.path,revision=revision,packs={},sheets={},frames={}}
  S.data._modPokemonArt=c
  local roots={S.path}
  for _,dir in ipairs(require("ModIO").listSubdirs(S.path)) do roots[#roots+1]=S.path.."/"..dir end
  for _,root in ipairs(roots) do
    local sprites=decode(root.."/data/dbk_data.lua")
    local icons=decode(root.."/data/icon_data.lua")
    if type(sprites)=="table" and type(sprites.species)=="table" then
      c.packs[#c.packs+1]={root=root,sprites=sprites,icons=icons}
    end
  end
  return c
end
local function safeName(s) return type(s)=="string" and s:match("^[%w_%-]+$") end
function M.path(S,mon,field)
  local c=state(S)
  if not c or not mon then return end
  -- Explicit editor imports take priority over the mod's original artwork.
  local base=(S.data.pokemon or {})[mon.id]
  local own=mon[field]
  if own and own~="" and not own:match("^data/generated/")
      and (not base or own~=base[field]) then return end
  local side=({spriteFront="front",spriteBack="back",spriteShinyFront="front_shiny",spriteShinyBack="back_shiny"})[field]
  if not side then return end
  for n,pack in ipairs(c.packs) do
    local stem=pack.sprites.species[mon.id]
    if safeName(stem) then
      local path=pack.root.."/assets/"..side.."/"..stem..".png"
      local f=io.open(path,"rb")
      if f then f:close();return "mod-pokemon-art/"..n.."/"..side.."/"..stem end
    end
  end
end
local function sheet(c,path)
  if c.sheets[path]==nil then
    local bytes=read(path)
    local ok,data=pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(assert(bytes),"sprite.png"))
    end)
    c.sheets[path]=ok and data or false
  end
  return c.sheets[path]
end
local function frame(c,path,x,y,size)
  local key=path..":"..x..":"..y..":"..size
  if c.frames[key] then return c.frames[key] end
  local data=sheet(c,path)
  if not data or size<1 or x<0 or y<0 or x+size>data:getWidth() or y+size>data:getHeight() then return end
  local pixels=love.image.newImageData(size,size)
  pixels:paste(data,0,0,x,y,size,size)
  local image=love.graphics.newImage(pixels)
  image:setFilter("nearest","nearest");c.frames[key]=image
  return image
end
function M.image(S,path)
  local n,side,stem=path:match("^mod%-pokemon%-art/(%d+)/([%w_]+)/([%w_%-]+)$")
  local c=state(S);local pack=c and c.packs[tonumber(n)]
  if not pack then return end
  local file=pack.root.."/assets/"..side.."/"..stem..".png"
  local data=sheet(c,file)
  if not data then return end
  local size=data:getHeight()
  local count=math.floor(data:getWidth()/size)
  if count<1 then return end
  local index=math.floor(love.timer.getTime()*8)%count
  return frame(c,file,index*size,0,size)
end
function M.icon(S,mon,id)
  local c=state(S)
  if not c then return end
  if mon and mon.icon then return end
  for _,pack in ipairs(c.packs) do
    local info=pack.icons
    local name=info and info.species and info.species[id or (mon and mon.id)]
    local index=name and info.base and info.base[name]
    if type(index)=="number" then
      local size,cols=info.cell,info.cols
      if type(size)=="number" and type(cols)=="number" and cols>0 then
        index=index+math.floor(love.timer.getTime()*4)%math.max(1,info.frames or 1)
        return frame(c,pack.root.."/assets/icons/party_icons.png",index%cols*size,math.floor(index/cols)*size,size)
      end
    end
  end
end
return M
