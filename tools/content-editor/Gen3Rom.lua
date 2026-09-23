-- Read-only supplementary datasets missing from the current runtime extract.
local M={}
function M.open(S)
  -- These supplementary decoders still use verified BPRE0 offsets. Never
  -- silently use the global FireRed ROM path while editing LeafGreen.
  if require("Generation").id(S)=="leafgreen" then
    return nil,"This supplementary ROM tool currently requires FireRed USA 1.0; LeafGreen cache editing is supported"
  end
  if S.data._g3RomBytes then return S.data._g3RomBytes end
  local IO=require("ModIO")
  local path=(S.project or {}).gen3RomPath or os.getenv("POKEPORT_GEN3_ROM") or IO.readText("gen3-rom-path.txt")
  if not path then return nil,"Select the original FireRed USA 1.0 ROM" end
  path=path:gsub("%s+$","")
  local bytes,err=IO.readText(path)
  if not bytes then return nil,err end
  if #bytes~=16777216 or bytes:sub(173,176)~="BPRE" or bytes:byte(189)~=0 then return nil,"Supplementary extraction needs FireRed USA 1.0" end
  local hash=love.data.encode("string","hex",love.data.hash("sha1",bytes))
  if hash~="41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" then return nil,"The ROM does not match FireRed USA 1.0; fixed table offsets were not used" end
  S.data._g3RomBytes=bytes;return bytes
end
local function u16(b,p) local a,c=b:byte(p+1,p+2);return a+c*256 end
local function u32(b,p) return u16(b,p)+u16(b,p+2)*65536 end
function M.shiny(S,species,back)
  return M.formPicture(S,species,back,0,0,true)
end
-- A 64x64 form frame; Castform also uses one palette bank per frame.
local function formPicture(S,species,back,frame,paletteFrame,shiny)
  assert(type(species)=="number" and species%1==0 and species>=0 and species<=439,
    "This species has no native FireRed ROM artwork")
  frame=frame or 0;paletteFrame=paletteFrame or 0
  assert(type(frame)=="number" and frame>=0 and frame%1==0
    and type(paletteFrame)=="number" and paletteFrame>=0 and paletteFrame%1==0,
    "Invalid FireRed artwork frame")
  local b,err=M.open(S);if not b then return nil,err end
  local function get(i)
    assert(i>=0 and i<#b,"Artwork read outside ROM")
    return b:byte(i+1)
  end
  local function pointer(at)
    assert(at>=0 and at+4<=#b,"Artwork table outside ROM")
    local offset=u32(b,at)-0x8000000
    assert(offset>=0 and offset+4<=#b,"Artwork pointer outside ROM")
    return offset
  end
  local lz=require("src.import.gba.lz77")
  local pixels=lz.decompress(get,pointer((back and 0x23654c or 0x2350ac)+species*8))
  local pal=lz.decompress(get,pointer((shiny and 0x2380cc or 0x23730c)+species*8))
  assert(#pixels>=(frame+1)*2048 and #pal>=(paletteFrame+1)*32,"This form is not present in the FireRed ROM")
  local colors={}
  for i=0,15 do local at=paletteFrame*32+i*2+1;local c=pal[at]+pal[at+1]*256;colors[i]={c%32/31,math.floor(c/32)%32/31,math.floor(c/1024)%32/31,i==0 and 0 or 1} end
  local image=love.image.newImageData(64,64)
  for y=0,63 do for x=0,63 do
    local at=frame*2048+(math.floor(y/8)*8+math.floor(x/8))*32+(y%8)*4+math.floor(x%8/2)+1
    local byte=pixels[at];local index=x%2==0 and byte%16 or math.floor(byte/16)
    image:setPixel(x,y,unpack(colors[index]))
  end end
  return image
end
-- Preview failures must not escape into the editor draw callback.
function M.formPicture(S,species,back,frame,paletteFrame,shiny)
  local ok,image,err=pcall(formPicture,S,species,back,frame,paletteFrame,shiny)
  if not ok then return nil,"FireRed artwork unavailable: "..tostring(image) end
  return image,err
end
function M.trades(S)
  if S.data._g3RomTrades then return S.data._g3RomTrades end
  local b,err=M.open(S);if not b then return {},err end
  local species={};for id,rec in pairs(require("Gen3").catalog(S.data,"pokemon")) do species[rec.index]=id end
  local function str(p,n)
    local out={};local chars=require("src.core.game3.scripting.text_ir").CHARMAP
    for i=0,n-1 do local c=b:byte(p+i+1);if c==255 then break end;out[#out+1]=chars[c] or "?" end
    return table.concat(out)
  end
  local out={}
  for i=0,8 do
    local p=0x26cf8c+i*60;local ivs={};for j=0,5 do ivs[j+1]=b:byte(p+15+j) end
    out["ROM_"..i]={give=species[u16(b,p+56)],get=species[u16(b,p+12)],nickname=str(p,11),otName=str(p+43,11),
      otId=u32(b,p+24),ivs=ivs,abilityNum=b:byte(p+21),personality=u32(b,p+36),heldItem=u16(b,p+40),otGender=b:byte(p+55),nativeIndex=i}
  end
  S.data._g3RomTrades=out;return out
end
-- BPRE0 pointer locations documented by HexManiacAdvance tableReference.txt,
-- graphics.townmap.map: palette / tileset / tilemap. ROM hash checked above.
M.townMapKeys={"kanto","sevii_123","sevii_45","sevii_67"}
M.townMapNames={kanto="Kanto",sevii_123="Sevii Islands 1-3",sevii_45="Sevii Islands 4-5",sevii_67="Sevii Islands 6-7"}
function M.townMap(S,region)
  region=region or "kanto"
  local pointers={kanto=0xC035C,sevii_123=0xC0370,sevii_45=0xC0388,sevii_67=0xC03A4}
  assert(pointers[region],"Unknown Town Map region")
  S.data._g3TownMaps=S.data._g3TownMaps or {}
  if S.data._g3TownMaps[region] then return S.data._g3TownMaps[region] end
  local b,err=M.open(S);if not b then return nil,err end
  local function ptr(at)
    local off=u32(b,at)-0x8000000
    assert(off>=0 and off<#b,"Town Map pointer outside ROM");return off
  end
  local function get(at) return assert(b:byte(at+1),"Town Map read outside ROM") end
  local lz=require("src.import.gba.lz77")
  local tiles=lz.decompress(get,ptr(0xC0330))
  local map=lz.decompress(get,ptr(pointers[region]))
  local pal=ptr(0xC02EC)
  assert(#map==30*20*2,"Unexpected Town Map layout size")
  local img=love.image.newImageData(240,160)
  for y=0,159 do for x=0,239 do
    local at=(math.floor(y/8)*30+math.floor(x/8))*2+1
    local entry=map[at]+map[at+1]*256
    local tile=entry%1024;local px,py=x%8,y%8
    if math.floor(entry/1024)%2==1 then px=7-px end
    if math.floor(entry/2048)%2==1 then py=7-py end
    local byte=assert(tiles[tile*32+py*4+math.floor(px/2)+1],"Town Map tile outside sheet")
    local index=px%2==0 and byte%16 or math.floor(byte/16)
    local bank=math.floor(entry/4096);assert(bank<5,"Unexpected Town Map palette bank")
    local color=u16(b,pal+(bank*16+index)*2)
    img:setPixel(x,y,color%32/31,math.floor(color/32)%32/31,math.floor(color/1024)%32/31,1)
  end end
  S.data._g3TownMaps[region]=img;return img
end
return M
