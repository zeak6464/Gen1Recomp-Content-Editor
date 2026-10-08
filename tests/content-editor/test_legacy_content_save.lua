package.path = "tools/content-editor/?.lua;tools/save-editor/?.lua;runtime/gen1recomp/?.lua;" .. package.path
love = require("tests.love_stub")

local State = require("State")
local Gen3 = require("Gen3")
local Native = require("Gen3Native")
local ModIO = require("ModIO")
local Writer = require("ModWriter")
local root = "tests/content-editor/legacy_save_" .. os.time() .. "_" .. math.random(100000, 999999)
assert(ModIO.ensureDirectory(root))

local ok, err = pcall(function()
  for _, game in ipairs({"red", "blue", "yellow", "gold", "silver", "crystal"}) do
    local p = State.blankProject("legacy_stats")
    p.game = game
    p.pokemon.CHIKORITA = {baseStats = {hp = 80, attack = 49, defense = 65,
      speed = 45, specialAttack = 60, specialDefense = 70}}
    assert(not Gen3.projectError(p), game .. " Pokemon edits rejected")
    p.items.POTION = {price = 123}
    assert(not Gen3.projectError(p), game .. " item edits rejected")
    assert(Native.used(p), "Gen 3 export still needs shared records")
    assert(not Native.used(p, false), "shared records mistaken for native edits")
    assert(ModIO.save(root, p))
    local loaded = assert(ModIO.load(root))
    assert(loaded.game == game)
    assert(loaded.pokemon.CHIKORITA.baseStats.hp == 80)
    assert(loaded.pokemon.CHIKORITA.baseStats.specialDefense == 70)
    assert(loaded.items.POTION.price == 123)
    local main = assert(ModIO.readText(root .. "/main.lua"))
    assert(loadstring(main), "generated mod is invalid Lua")
    assert(main:find("CHIKORITA", 1, true) and main:find("80", 1, true))
    p.gen3BattlePositions = {CHIKORITA = {front = 1}}
    assert(Gen3.projectError(p), "actual native edits accepted for " .. game)
    p.gen3BattlePositions = nil
    p.gen3 = {pokemon = {CHIKORITA = {baseStats = {hp = 90}}}}
    assert(Gen3.projectError(p), "actual Gen 3 content accepted for " .. game)
    assert(not pcall(Writer.emitMain, p), "Gen 3 content would be lost")
  end
end)
for _, file in ipairs({"main.lua", "editor_project.lua", "editor_project.editor.lua", "editor_project.lua.tmp"}) do
  os.remove(root .. "/" .. file)
end
os.remove(ModIO.projectPath(root))
if package.config:sub(1, 1) == "\\" then os.execute('rmdir "' .. root .. '"')
else os.execute('rmdir "' .. root .. '"') end
assert(ok, err)
print("ok legacy Pokemon/item save roundtrip and Gen 3 validation")
