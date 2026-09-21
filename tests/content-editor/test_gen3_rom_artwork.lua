package.path = "tools/content-editor/?.lua;" .. package.path
local Rom = require("Gen3Rom")
local originalOpen = Rom.open
local pixels = 0
love = {image={newImageData=function(w,h)
  assert(w==64 and h==64)
  return {setPixel=function(_,x,y,r,g,b,a)
    assert(x>=0 and x<64 and y>=0 and y<64)
    assert(r>=0 and r<=1 and g>=0 and g<=1 and b>=0 and b<=1 and (a==0 or a==1))
    pixels=pixels+1
  end}
end}}
local function fails(species,pattern)
  local image,err=Rom.shiny({},species,false)
  assert(not image and err:find(pattern,1,true),tostring(err))
end
Rom.open=function() error("Invalid species must not read ROM") end
for _,id in ipairs({-1,440,1000,1.5,"25"}) do fails(id,"no native FireRed") end
Rom.open=function() return nil,"Missing ROM" end
fails(25,"Missing ROM")
Rom.open=function() return string.rep("\0",0x238100) end
fails(25,"pointer outside ROM")
Rom.open=function() return "" end
fails(25,"table outside ROM")
Rom.open=originalOpen
-- Optional integration against the installed runtime decoder and a local ROM.
local path=os.getenv("POKEPORT_GEN3_ROM")
if path then
  local f=assert(io.open(path,"rb"));local bytes=f:read("*a");f:close()
  local S={data={_g3RomBytes=bytes}}
  for species=0,439 do
    for _,back in ipairs({false,true}) do
      local image,err=Rom.shiny(S,species,back)
      assert(image,"species "..species..": "..tostring(err))
    end
  end
  assert(pixels==440*2*4096)
  -- Point a table entry at a valid header with a truncated compressed stream.
  local at=0x2350ac+25*8
  local offset=#bytes
  local pointer=offset+0x8000000
  local packed={}
  for i=1,4 do packed[i]=string.char(pointer%256);pointer=math.floor(pointer/256) end
  local broken=bytes:sub(1,at)..table.concat(packed)..bytes:sub(at+5)..string.char(0x10,0,8,0)
  local failed,reason=Rom.shiny({data={_g3RomBytes=broken}},25,false)
  assert(not failed and reason:find("Artwork read outside ROM",1,true))
  local image,err=Rom.formPicture(S,25,false,999,0,true)
  assert(not image and err:find("not present",1,true))
  print("PASS: all 440 native species, front/back shiny decoding")
end
print("PASS: ROM artwork validation and graceful failures")
