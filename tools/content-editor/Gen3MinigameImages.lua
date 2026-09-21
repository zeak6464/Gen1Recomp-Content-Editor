-- FireRed USA 1.0 mini-game graphics. Offsets matched byte-for-byte against
-- pret/pokefirered graphics and graphics_file_rules.mk; Gen3Rom verifies SHA-1.
local M={}
M.assets={
 slots={
  {name="Slot machine background",gfx=0x4659D0,pal=4610352,map=0x4661D4,width=240,height=160,mapWidth=32},
  {name="Winning combinations",gfx=0x466620,pal=4613568,map=0x466998,width=240,height=160,mapWidth=32},
  {name="Reel symbols",gfx=4606484,pal=4606324,width=32,height=224,banks={2,2,0,0,2,4,3},frameHeight=32},
  {name="Clefairy animation frames",gfx=4608108,pal=4608076,width=32,height=192},
  {name="Pressed button",gfx=4613436,pal=4610352,width=16,height=16},
 },
 crush={
  {name="Berry Crush background",gfx=15400896,pal=15400608,map=0x46F058,width=240,height=160,mapWidth=32},
  {name="Crusher graphics",gfx=4646096,pal=4646000,width=64,height=64},
  {name="Impact animation frames",gfx=4646908,pal=4646032,width=32,height=224},
  {name="Powder sparkles",gfx=4647800,pal=4646032,width=16,height=224},
  {name="Timer numbers",gfx=4648132,pal=4646064,width=8,height=176},
 },
 jump={
  {name="Pokemon Jump background",gfx=0x46B7D4,pal=4634548,map=0x46BA00,width=240,height=160,mapWidth=32},
  {name="Venusaur graphics",gfx=4635600,pal=4635568,width=64,height=128},
  {name="Bonus graphics",gfx=4638968,pal=4638936,width=80,height=136},
  {name="Vine animation 1",gfx=4643364,pal=4643300,width=16,height=192},
  {name="Vine animation 2",gfx=4643652,pal=4643300,width=32,height=192},
  {name="Vine animation 3",gfx=4644120,pal=4643300,width=32,height=96},
  {name="Vine animation 4",gfx=4644424,pal=4643300,width=32,height=96},
  {name="Star animation",gfx=4644676,pal=4643300,width=16,height=64},
 },
 dodrio={
  {name="Berry Picking background",gfx=4676412,pal=0x47214C,map=0x478590,width=240,height=160,mapWidth=32},
  {name="Dodrio animation frames",gfx=4682612,pal=4661644,width=64,height=384},
  {name="Berries",gfx=4675944,pal=4661740,width=16,height=144},
  {name="Cloud",gfx=4682284,pal=4662208,width=64,height=32},
  {name="Status icons",gfx=4682136,pal=4661708,width=16,height=48},
  {name="Tree border tiles",gfx=4678604,pal=0x47216C,width=128,height=104},
 },
}
function M.image(S,game,index)
 local b,err=require("Gen3Rom").open(S);if not b then return nil,err end
 local rec=assert(M.assets[game] and M.assets[game][index],"Unknown mini-game image")
 local cache=S.data._miniGameImages or {};S.data._miniGameImages=cache
 local key=game.."/"..index;if cache[key] then return cache[key] end
 local ok,img=pcall(function()
  local lz=require("src.import.gba.lz77")
  local function read(at) return assert(b:byte(at+1),"Mini-game graphics outside ROM") end
  local tiles=lz.decompress(read,rec.gfx)
  local map=rec.map and lz.decompress(read,rec.map)
  local image=love.image.newImageData(rec.width,rec.height)
  for y=0,rec.height-1 do for x=0,rec.width-1 do
   local tx,ty=x%8,y%8;local bank=0
   local tile=math.floor(y/8)*(rec.width/8)+math.floor(x/8)
   if map then
    local at=(math.floor(y/8)*rec.mapWidth+math.floor(x/8))*2+1
    local entry=assert(map[at])+assert(map[at+1])*256
    tile=entry%1024;bank=math.floor(entry/4096)
    if math.floor(entry/1024)%2==1 then tx=7-tx end
    if math.floor(entry/2048)%2==1 then ty=7-ty end
   elseif rec.banks then bank=rec.banks[math.floor(y/rec.frameHeight)+1] or 0 end
   local v=assert(tiles[tile*32+ty*4+math.floor(tx/2)+1],"Mini-game tile index outside graphics")
   local color=tx%2==0 and v%16 or math.floor(v/16)
   local at=rec.pal+(bank*16+color)*2
   local rgb=read(at)+read(at+1)*256
   image:setPixel(x,y,rgb%32/31,math.floor(rgb/32)%32/31,math.floor(rgb/1024)%32/31,(map or color~=0) and 1 or 0)
  end end
  return image
 end)
 if not ok then return nil,tostring(img) end
 cache[key]=img;return img
end
return M
