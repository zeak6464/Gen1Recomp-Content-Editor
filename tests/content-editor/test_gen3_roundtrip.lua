local data,_,read=dofile("tests/content-editor/test_gen3_real.lua")
local target=assert(os.getenv("POKEPORT_GEN3_TEST_MOD"),"Set a disposable copied mod path")
local IO=require("ModIO")
local original=assert(IO.readText(target.."/main.lua"))
local Json=require("src.link.Json")
local manifest=assert(Json.decode(assert(IO.readText(target.."/manifest.json"))))
local project=require("State").blankProject(manifest.id,manifest.name)
project.game="firered"
project._protectMain=true
project._originalEntry="main.lua"
project.gen3={pokemon={MEW={baseStats={specialAttack=113},spriteFront="assets/mew_front_inverted_64.png"}},map_scripts={EDITOR_TEST={{op="end"}}}}
project.gen3Modes={map_scripts={EDITOR_TEST="register"}}
project.gen3Starters={{map="FR_OAKS_LAB",matchSpecies={"CHARMANDER","MEW"},species="MEW",level=28,nickname="EDITOR",onlyFirst=true,variable=0x4002}}
project.gen3Terrain={FR_PALLET_TOWN={[1025]={mid=1,coll=0,elev=3}}}
assert(IO.save(target,project))
assert(IO.save(target,project))
assert(IO.readText(target.."/main.lua")==original,"original entry changed")
local mf=assert(Json.decode(assert(IO.readText(target.."/manifest.json"))))
assert(mf.entry=="editor_entry.lua")
assert(table.concat(mf.games,",")==table.concat(manifest.games,","),"compatibility changed")
local reopened=assert(IO.load(target))
assert(reopened._originalEntry=="main.lua")
local G=require("Gen3")
local fresh={};G.load(fresh,read)
fresh.maps.FR_PALLET_TOWN.midLayout=assert(require("Gen3Map").layout(fresh,"FR_PALLET_TOWN"))
local loader,err=require("Gen3Mod").load(fresh,target);assert(loader,err)
assert(G.catalog(fresh,"pokemon").MEW.baseStats.specialAttack==113)
assert(G.catalog(fresh,"pokemon").MEW.spriteFront=="mods/"..manifest.id.."/assets/mew_front_inverted_64.png")
assert(G.catalog(fresh,"map_scripts").EDITOR_TEST[1].op=="end")
local ctx={overworld={map={id="OAKS_LAB"}},save={flags={},party={}}}
local gift={species="CHARMANDER",level=5,ctx=ctx}
loader.events:emit("pokemon.before_give",gift)
assert(gift.species=="MEW" and gift.level==28 and gift.nickname=="EDITOR")
local vanillaRow={var=0x4002,value=4}
local row=loader.hooks:call("script.command",function(_,_,r) return r end,ctx,"setvar",vanillaRow)
assert(row.value==151 and vanillaRow.value==4)
loader.events:emit("game.ready",{game={data=fresh}})
local layout=fresh.maps.FR_PALLET_TOWN.midLayout
assert(layout:midAt(1,1)==1 and layout:elevAt(1,1)==3)
local unrelated={species="PIKACHU",level=5,ctx=ctx}
loader.events:emit("pokemon.before_give",unrelated)
assert(unrelated.species=="PIKACHU" and unrelated.level==5)
print("ok Mew mod wrapper, original source, compatibility, save/reopen, sprite paths, script registration, gift+script hooks, native terrain")
return fresh,project
