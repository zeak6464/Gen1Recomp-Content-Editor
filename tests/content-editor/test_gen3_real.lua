local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;"..runtime.."/?.lua;"..package.path
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE"))
local function read(rel)
  local f=io.open(cache.."/"..rel,"rb");if not f then return end
  local b=f:read("*a");f:close();return b
end
local data={}
local G=require("Gen3")
require("src.core.GameVersion").set("firered")
G.load(data,read)
assert(data.maps.FR_PALLET_TOWN)
local layout=assert(require("Gen3Map").layout(data,"FR_PALLET_TOWN"))
assert(layout.width==24 and layout.height==20)
local pokemon=G.catalog(data,"pokemon")
assert(pokemon.MEW and pokemon.MEW.baseStats.hp==100)
local mod=assert(os.getenv("POKEPORT_GEN3_MOD"))
local loader,err=require("Gen3Mod").load(data,mod)
assert(loader,err)
local mew=G.catalog(data,"pokemon").MEW
assert(mew.spriteFront:find("inverted",1,true),mew.spriteFront)
assert(mew.spriteFront64:find("64",1,true))
local gift={species="CHARMANDER",level=5,ctx={overworld={map={id="OAKS_LAB"}},save={flags={},party={}}}}
loader.events:emit("pokemon.before_give",gift)
assert(gift.species=="MEW" and gift.level==20 and gift.nickname=="HOGHEAD")
print("ok real FireRed cache/native maps/Mew sprite override/starter event")
return data,loader,read
