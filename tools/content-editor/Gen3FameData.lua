-- FireRed USA 1.0 tables from fame_checker.c. Gen3Rom.open verifies the ROM hash.
local M={}
M.names={"Professor Oak","Daisy","Brock","Misty","Lt. Surge","Erika","Koga","Sabrina","Blaine","Lorelei","Bruno","Agatha","Lance","Bill","Mr. Fuji","Giovanni"}
local function word(b,p) local a,c=b:byte(p+1,p+2);return a+c*256 end
local function pointer(b,p) return word(b,p)+word(b,p+2)*65536-0x8000000 end
local function text(b,at)
  assert(at>=0 and at<#b,"Fame Checker text pointer outside ROM")
  local ir=require("src.core.game3.scripting.text_ir").decode(b:sub(at+1,at+4096));local out={}
  for _,v in ipairs(ir) do
    if v.t=="text" then out[#out+1]=v.s
    elseif v.t=="nl" or v.t=="scroll" then out[#out+1]="\n"
    elseif v.t=="para" then out[#out+1]="\f"
    elseif v.t=="player" then out[#out+1]="{PLAYER}"
    elseif v.t=="rival" then out[#out+1]="{RIVAL}" end
  end
  return table.concat(out)
end
local function portrait(b,at)
  local image=love.image.newImageData(64,64)
  for y=0,63 do for x=0,63 do
    local off=(math.floor(y/8)*8+math.floor(x/8))*32+y%8*4+math.floor(x%8/2)
    local v=b:byte(at+off+1);local idx=x%2==0 and v%16 or math.floor(v/16)
    local c=word(b,at+2048+idx*2)
    image:setPixel(x,y,c%32/31,math.floor(c/32)%32/31,math.floor(c/1024)%32/31,idx==0 and 0 or 1)
  end end
  return love.data.encode("string","base64",image:encode("png"):getString())
end
local function background(b)
  local img=love.image.newImageData(240,160)
  for y=0,159 do for x=0,239 do
    local color=0
    for _,map in ipairs({0xea0700,0xea0f00}) do
      local e=word(b,map+(math.floor(y/8)*32+math.floor(x/8))*2)
      local px,py=x%8,y%8
      if math.floor(e/1024)%2==1 then px=7-px end
      if math.floor(e/2048)%2==1 then py=7-py end
      local v=b:byte(0xe9f260+e%1024*32+py*4+math.floor(px/2)+1)
      local idx=px%2==0 and v%16 or math.floor(v/16)
      if idx~=0 or map==0xea0700 then color=word(b,0xe9f220+(math.floor(e/4096)*16+idx)*2) end
    end
    img:setPixel(x,y,color%32/31,math.floor(color/32)%32/31,math.floor(color/1024)%32/31,1)
  end end
  return love.data.encode("string","base64",img:encode("png"):getString())
end
function M.load(S)
  if S.data._g3Fame then return S.data._g3Fame end
  local b,err=require("Gen3Rom").open(S);if not b then return nil,err end
  local originals={[1]=0x45ed80,[2]=0x45e560,[14]=0x45dd40,[15]=0x45d520}
  local rows={}
  for i,name in ipairs(M.names) do
    local r={name=name,message=text(b,pointer(b,0x45f63c+(i+15)*4)),facts={},portrait=b:byte(0x45f61c+i),unlock="original"}
    if originals[i] then r.image=portrait(b,originals[i]) end
    for j=1,6 do
      local index=(i-1)*6+j-1;local body=text(b,pointer(b,0x45f6bc+index*4))
      local question,detail=body:match("^(.-)\f(.*)$")
      r.facts[j]={question=question or "About this person",text=detail or body,
        location=text(b,pointer(b,0x45f89c+index*4)),source=text(b,pointer(b,0x45fa1c+index*4)),graphics=b:byte(0x45f83c+index+1),unlock="original"}
    end
    rows[i]=r
  end
  rows[1].background=background(b)
  S.data._g3Fame=rows;return rows
end
-- Upgrade metadata for existing projects without replacing edited text/artwork.
function M.enrich(rows,defaults)
  local copy=require("src.mods.Merge").deepCopy(rows)
  if defaults then
    copy[1].background=copy[1].background or defaults[1].background
    for i,r in ipairs(copy) do for j,f in ipairs(r.facts) do if f.graphics==nil then f.graphics=defaults[i].facts[j].graphics end end end
  end
  return copy
end
return M
