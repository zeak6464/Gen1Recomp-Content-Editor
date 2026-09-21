-- Run with POKEPORT_RECOMP pointing at a Gen 3-capable checkout.
local root = assert(os.getenv("POKEPORT_RECOMP"), "Set POKEPORT_RECOMP")
package.path = "tools/content-editor/?.lua;" .. root .. "/?.lua;" .. package.path
local G = require("Gen3")
local Generation = require("Generation")
local Schemas = require("src.mods.Schemas")
local Writer = require("ModWriter")
local Version = require("src.core.GameVersion")
assert(Generation.num({version="firered"}) == 3)
assert(not Generation.isGen2({version="firered",data={trainers={classes={}}}}))
assert(Generation.manifestGames({version="firered"})[1] == "firered")
assert(Generation.manifestGames({version="red"})[1] == "all")
local fixtures = {
  maps = {FR_TEST={id="FR_TEST",width=10,height=10}},
  ["gba/pokemon/names"] = {[1]="BULBASAUR"},
  ["gba/pokemon/types"] = {[1]={12,3}},
  ["gba/pokemon/stats"] = {[1]={hp=45,atk=49,def=49,spe=45,spa=65,spd=65}},
  ["gba/pokemon/meta"] = {[1]={catchRate=45,expYield=64,growthRate=3}},
  ["gba/pokemon/move_names"] = {[1]="POUND"},
  ["gba/pokemon/battle_moves"] = {[1]={power=40,type=0,accuracy=100,pp=35}},
  ["gba/items/pack"] = {items={[13]={name="POTION",price=300,pocket="ITEMS"}}},
  ["gba/trainers"] = {trainers={[1]={name="TEST",class=1,party={{species=1,level=5}}}}},
  ["gba/encounters"] = {FR_TEST={land={rate=20,slots={{species=1,minLevel=2,maxLevel=3}}}}},
  ["gba/scripts/text"] = {Text_Test={{t="text",s="Hello"},{t="eos"}}},
  ["gba/scripts/scripts"] = {Script_Test={{op="end"}}},
}
local data = {}
G.load(data, function(path)
  local name = path:match("data/generated/(.*)%.lua")
  return "return " .. Writer.encodeLua(fixtures[name] or {})
end)
assert(G.catalog(data,"pokemon").BULBASAUR.baseStats.specialAttack == 65)
assert(G.catalog(data,"moves").POUND.power == 40)
assert(G.catalog(data,"items").POTION.price == 300)
assert(G.catalog(data,"trainers")["1"].name == "TEST")
assert(G.catalog(data,"encounters").FR_TEST.land.slots[1].species == "BULBASAUR")
assert(G.catalog(data,"maps").FR_TEST.width == 10)
assert(G.catalog(data,"text").Text_Test[1].s == "Hello")
assert(G.catalog(data,"map_scripts").Script_Test[1].op == "end")
assert(not pcall(G.load, {}, function() return nil end), "missing cache accepted")
assert(not pcall(G.load, {}, function() return "return os.execute('bad')" end), "executable cache accepted")
assert(not G.check("pokemon","BULBASAUR",{baseStats={hp=999}}))
local project = {id="gen3_test",game="firered",gen3={
  pokemon={BULBASAUR={baseStats={specialAttack=80}}},
  moves={POUND={power=50}}, items={POTION={price=150}},
  text={Text_Test="Edited text"}, map_scripts={Script_Test={{op="end"}}},
  trainers={["1"]={name="NEW"}}, maps={FR_TEST={width=12}},
  encounters={FR_TEST={land={rate=25}}},
}}
local saved = assert(loadstring(Writer.serializeProject(project)))()
assert(saved.gen3.pokemon.BULBASAUR.baseStats.specialAttack == 80)
local main = Writer.emitMain(saved,data)
local calls = {}
local content = setmetatable({}, {__index=function(_,name)
  return setmetatable({}, {__index=function(_,mode)
    return function(_,id,value)
      assert(G.check(name,id,value))
      calls[name] = {id=id,value=value,mode=mode}
    end
  end})
end})
Version.set("firered")
assert(loadstring(main))()({content=content,generation=3,events={on=function() end}})
for _,name in ipairs(G.registries) do assert(calls[name],name.." missing") end
assert(calls.text.mode == "override" and calls.pokemon.mode == "patch")
local spec = Schemas.shapeFor("pokemon",Schemas.REGISTRIES.pokemon,3)
local merged = G.catalog(data,"pokemon").BULBASAUR
merged.baseStats.specialAttack = 80
spec.write(data.gen3Pokemon,{ops={BULBASAUR=true},get=function() return merged end})
assert(data.gen3Pokemon.stats[1].spa == 80, "runtime did not receive edited stat")
local State = require("State")
local blank = State.blankProject("blank")
blank.game = "firered"
assert(not G.projectError(blank))
blank.pokemon.MEW = {name="legacy"}
assert(G.projectError(blank), "legacy edits would be lost")
saved.game = "red"
assert(not pcall(Writer.emitMain,saved,data), "Gen 3 edits would be lost")
saved.game = "firered"
local ModIO = require("ModIO")
local temp = (os.getenv("TEMP") or "/tmp") .. "/gen3_editor_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000,999999))
assert(ModIO.ensureDirectory(temp))
local success, detail = pcall(function()
  assert(ModIO.save(temp,saved))
  saved.gen3.moves.POUND.power = 60
  assert(ModIO.save(temp,saved))
  assert(not ModIO.exists(temp .. "/editor_apply.lua"), "generated main mistaken for handwritten code")
  local reopened = assert(ModIO.load(temp))
  assert(reopened.gen3.moves.POUND.power == 60)
  assert(ModIO.readText(temp .. "/main.lua"):find("60",1,true))
end)
for _,file in ipairs({"main.lua","editor_project.lua","editor_apply.lua"}) do os.remove(temp .. "/" .. file) end
if package.config:sub(1,1) == "\\" then os.execute('rmdir "' .. temp .. '"')
else os.execute('rmdir "' .. temp .. '"') end
assert(success,detail)
print("ok Gen3 cache, catalogs, validation, serialization, emission and runtime write")

return data, project
