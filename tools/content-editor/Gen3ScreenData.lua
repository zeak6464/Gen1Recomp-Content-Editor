-- Original FireRed USA 1.0 data. Graphics matched byte-for-byte against pret assets.
local M={}
M.areas={
  {id="altering_cave",name="Altering Cave",gfx=4445028,pal=4444964,map=4449816},
  {id="berry_forest",name="Berry Forest",gfx=4430360,pal=4430296,map=4437028},
  {id="cerulean_cave",name="Cerulean Cave",gfx=4411464,pal=4411400,map=4416536},
  {id="digletts_cave",name="Digletts Cave",gfx=4417620,pal=4417556,map=4423552},
  {id="dotted_hole",name="Dotted Hole",gfx=4405860,pal=4405796,map=4410564},
  {id="icefall_cave",name="Icefall Cave",gfx=4438084,pal=4438020,map=4443972},
  {id="lost_cave",name="Lost Cave",gfx=4424612,pal=4424548,map=4429296},
  {id="monean_chamber",name="Monean Chamber",gfx=4399628,pal=4399564,map=4404936},
  {id="mt_ember",name="Mt Ember",gfx=4386524,pal=4386460,map=4392336},
  {id="mt_moon",name="Mt Moon",gfx=4362556,pal=4362492,map=4369000},
  {id="pokemon_mansion",name="Pokemon Mansion",gfx=4344772,pal=4344708,map=4351180},
  {id="pokemon_tower",name="Pokemon Tower",gfx=4352232,pal=4352168,map=4356140},
  {id="power_plant",name="Power Plant",gfx=4339192,pal=4339128,map=4343760},
  {id="rock_tunnel",name="Rock Tunnel",gfx=4329904,pal=4329840,map=4335444},
  {id="rocket_hideout",name="Rocket Hideout",gfx=4336516,pal=4336452,map=4338524},
  {id="rocket_warehouse",name="Rocket Warehouse",gfx=4376480,pal=4376416,map=4378824},
  {id="safari_zone",name="Safari Zone",gfx=4393308,pal=4393244,map=4398700},
  {id="seafoam_islands",name="Seafoam Islands",gfx=4369984,pal=4369920,map=4375400},
  {id="silph_co",name="Silph Co",gfx=4356992,pal=4356928,map=4361564},
  {id="victory_road",name="Victory Road",gfx=4379588,pal=4379524,map=4385504},
  {id="viridian_forest",name="Viridian Forest",gfx=4322580,pal=4322516,map=4328856},
}
M.creditArt={
 {id="blastoise_1",name="Blastoise 1",gfx=4256320,species=9,width=80,height=80},
 {id="blastoise_2",name="Blastoise 2",gfx=4258116,species=9,width=80,height=96},
 {id="charizard_1",name="Charizard 1",gfx=4246412,species=6,width=80,height=80},
 {id="charizard_2",name="Charizard 2",gfx=4248104,species=6,width=96,height=104},
 {id="pikachu_1",name="Pikachu 1",gfx=4260248,species=25,width=80,height=80},
 {id="pikachu_2",name="Pikachu 2",gfx=4261300,species=25,width=96,height=96},
 {id="venusaur_1",name="Venusaur 1",gfx=4251992,species=3,width=80,height=80},
 {id="venusaur_2",name="Venusaur 2",gfx=4253956,species=3,width=96,height=80},
 {id="venusaur_unused",name="Venusaur Unused",gfx=4250636,species=3,width=64,height=64},
 {id="copyright",name="Copyright",gfx=15394120,pal=4203104,width=88,height=56},
 {id="ground_city",name="Ground City",gfx=4275640,pal=4275608,width=64,height=256},
 {id="ground_dirt",name="Ground Dirt",gfx=4274292,pal=4274260,width=64,height=256},
 {id="ground_grass",name="Ground Grass",gfx=4272952,pal=4272920,width=64,height=256},
 {id="player_female",name="Player Female",gfx=4267032,pal=4263440,width=64,height=384},
 {id="player_male",name="Player Male",gfx=4263472,pal=4263440,width=64,height=384},
 {id="pokeball",name="Pokeball",gfx=15379352,pal=15379224,width=128,height=128},
 {id="rival",name="Rival",gfx=4270528,pal=4270496,width=64,height=384},
 {id="the_end",name="The End",gfx=4262688,pal=4203104,width=112,height=8},
}
-- Full-screen tilemaps used by the cinematic, rather than raw tile sheets.
for _,r in ipairs({
 {id="circle_screen",gfx=0x40c650,map=0x40ca54,bpp=8},
 {id="copyright_screen",gfx=15394120,pal=4203104,map=0xeae900},
 {id="the_end_screen",gfx=4262688,pal=4203104,map=0x410b94},
 {id="ball_charizard",gfx=15379352,pal=0xeaab18,map=0xeab30c},
 {id="ball_venusaur",gfx=15379352,pal=0xeaab38,map=0xeab30c},
 {id="ball_blastoise",gfx=15379352,pal=0xeaab58,map=0xeab30c},
 {id="ball_pikachu",gfx=15379352,pal=0xeaab78,map=0xeab30c},
}) do r.name=r.id:gsub("_"," ");r.width=r.bpp==8 and 256 or 240;r.height=r.bpp==8 and 256 or 160;r.paletteBase=0;M.creditArt[#M.creditArt+1]=r end
for id,species in pairs({charizard=6,venusaur=3,blastoise=9,pikachu=25}) do
 M.creditArt[#M.creditArt+1]={id=id.."_front",name=id.." normal pose",frontSpecies=species,species=species,width=64,height=64}
end
local function u16(b,p) return b:byte(p+1)+b:byte(p+2)*256 end
local function u32(b,p) return u16(b,p)+u16(b,p+2)*65536 end
function M.image(S,kind,id)
 local cache=S.data._g3ScreenImages or {};S.data._g3ScreenImages=cache
 local key=kind..id;if cache[key] then return cache[key] end
 local rec;for _,r in ipairs(kind=="areas" and M.areas or M.creditArt) do if r.id==id then rec=r end end
 if not rec then return nil,"Choose an image" end
 local b,err=require("Gen3Rom").open(S);if not b then return nil,err end
 local ok,img=pcall(function()
  local lz=require("src.import.gba.lz77")
  local function read(p) return assert(b:byte(p+1),"Image outside ROM") end
  local pal=rec.species and lz.decompress(read,u32(b,0x23730c+rec.species*8)-0x8000000)
  local tiles=lz.decompress(read,rec.frontSpecies and u32(b,0x2350ac+rec.frontSpecies*8)-0x8000000 or rec.gfx);local map=rec.map and lz.decompress(read,rec.map)
  local w,h=rec.width or 240,rec.height or 160;local image=love.image.newImageData(w,h)
  if rec.bpp==8 then
   for y=0,h-1 do for x=0,w-1 do
    local tile=map[math.floor(y/8)*32+math.floor(x/8)+1]
    local v=tiles[tile*64+(y%8)*8+x%8+1]==255 and 1 or 0
    image:setPixel(x,y,v,v,v,1)
   end end
   return image
  end
  for y=0,h-1 do for x=0,w-1 do
   local tx,ty=x%8,y%8;local bank=0;local tile=math.floor(y/8)*(w/8)+math.floor(x/8)
   if map then
    local at=(math.floor(y/8)*32+math.floor(x/8))*2+1;local entry=map[at]+map[at+1]*256
    tile=entry%1024;bank=math.floor(entry/4096)-(rec.paletteBase or 13)
    if math.floor(entry/1024)%2==1 then tx=7-tx end
    if math.floor(entry/2048)%2==1 then ty=7-ty end
   end
   if bank<0 then image:setPixel(x,y,0,0,0,1) else
    local v=assert(tiles[tile*32+ty*4+math.floor(tx/2)+1],"Invalid image tile")
    local color=tx%2==0 and v%16 or math.floor(v/16);local rgb
    if pal then rgb=pal[color*2+1]+pal[color*2+2]*256 else rgb=u16(b,rec.pal+(bank*16+color)*2) end
    image:setPixel(x,y,rgb%32/31,math.floor(rgb/32)%32/31,math.floor(rgb/1024)%32/31,(map or color~=0) and 1 or 0)
   end
  end end
  return image
 end)
 if not ok then return nil,tostring(img) end;cache[key]=img;return img
end
function M.credits(S)
 if S.data._g3CreditPages then return S.data._g3CreditPages end
 local b,err=require("Gen3Rom").open(S);if not b then return nil,err end
 local chars=require("src.core.game3.scripting.text_ir").CHARMAP
 local function text(p)
  local out={};for i=p,p+4096 do local c=b:byte(i+1);if c==255 then break end;out[#out+1]=c==254 and "\n" or chars[c] or "" end
  return table.concat(out)
 end
 local rows={}
 for i=0,41 do
  local at=0x4145bc+i*12
  local headings,names={},{}
  for line in (text(u32(b,at)-0x8000000).."\n"):gmatch("(.-)\n") do headings[#headings+1]=line end
  for line in (text(u32(b,at+4)-0x8000000).."\n"):gmatch("(.-)\n") do names[#names+1]=line end
  local lines={}
  for j=1,math.max(#headings,#names) do
   if headings[j] and headings[j]:match("%S") then lines[#lines+1]=headings[j] end
   if names[j] and names[j]:match("%S") then lines[#lines+1]=names[j] end
  end
  local title=table.remove(lines,1) or "Credits"
  rows[#rows+1]={title=title,text=table.concat(lines,"\n"),seconds=6,art="none"}
 end
 local ordered={}
 for _,c in ipairs(require("Gen3CreditsSequence").commands) do if c.op=="text" and rows[c.page] then
  local row=rows[c.page];row.seconds=c.frames/60;ordered[#ordered+1]=row
 end end
 rows=ordered
 rows[#rows+1]={title="THE END",text="",seconds=6,art="the_end"}
 S.data._g3CreditPages=rows;return rows
end
return M
