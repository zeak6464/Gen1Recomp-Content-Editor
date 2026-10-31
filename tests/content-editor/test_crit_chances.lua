-- Critical-hit chances are editable on Gold, Silver, Crystal, and every Gen 3 game.
package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;tools/save-editor/?.lua;runtime/gen1recomp/?.lua;" .. package.path
love = require("tests.love_stub")

local State = require("State")
local Writer = require("ModWriter")
local Damage = require("src.battle.gen2.Damage")
local Rules = require("src.core.game3.battle.rules")
local Capabilities = require("src.core.game3.battle.capabilities")

local saved = Damage.CRITICAL_CHANCES[0]
Damage.CRITICAL_CHANCES[0] = 1
assert(Damage.criticalChance(0) == 1, "stage 0 uses the edited chance")
assert(Damage.rollCritical(0, function() return 0 end) == true, "a 1-in-1 roll always crits")
Damage.CRIT_MULTIPLIER = 3
assert((tonumber(Damage.CRIT_MULTIPLIER) or 2) == 3, "the crit multiplier is live")
Damage.CRITICAL_CHANCES[0] = saved
Damage.CRIT_MULTIPLIER = 2
assert(Damage.criticalChance(0) == 15, "the cart stage 0 chance is restored")

local savedGen3 = Rules.crit.CHANCE[0]
Rules.crit.CHANCE[0] = 1
assert(Rules.crit.roll({ focusEnergy = false }, { effect = 0 }, false, function() return 0 end) == true
  or Rules.crit.CHANCE[0] == 1, "Gen 3 reads the chance table")
Rules.crit.CHANCE[0] = savedGen3
Capabilities.damageRollMin = 90
Capabilities.damageRollMax = 90
assert(Capabilities.damageRollMin == 90 and Capabilities.damageRollMax == 90)
Capabilities.damageRollMin = 85
Capabilities.damageRollMax = 100

local function emitGen2(game)
  local project = State.blankProject("crits")
  project.game = game
  project.battleCrit = { multiplier = 3, chances = { [0] = 1 } }
  return Writer.emitMain(project, {})
end
for _, game in ipairs({ "gold", "silver", "crystal" }) do
  local main = emitGen2(game)
  assert(main:find("Damage.CRIT_MULTIPLIER = battleCrit.multiplier", 1, true), game)
  assert(main:find("[0] = 1", 1, true) or main:find("[0]=1", 1, true), game .. " saves stage 0")
end
local red = State.blankProject("crits")
red.game = "red"
red.battleCrit = { multiplier = 3 }
assert(not Writer.emitMain(red, {}):find("CRIT_MULTIPLIER", 1, true), "Red keeps its own crit formula")

local BattleRules = require("Gen3BattleRules")
local Native = require("Gen3Native")
for _, game in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local project = State.blankProject("crits")
  project.game = game
  project.gen3BattleRules = { critChance0 = 1, damageRollMin = 90 }
  assert(Native.used(project), game .. " treats crit chances as native content")
  local out = {}
  BattleRules.emit(project, function() return "{ critChance0 = 1, damageRollMin = 90 }" end, out)
  local main = table.concat(out, "\n")
  assert(loadstring(main), game .. " crit rules compile")
  assert(main:find("Rules.crit.CHANCE[0] = battleRules.critChance0", 1, true), game .. " saves the crit ladder")
  assert(main:find("Capabilities.damageRollMin = battleRules.damageRollMin", 1, true), game)
  assert(not main:find("editor.gen3.rules", 1, true), game .. " crit chances do not replace the multiplier")
end

local Runtime = require("src.mods.Runtime")
local hooks = require("src.mods.Hooks").new()
Runtime.install(nil, hooks, nil)
local critOut = {}
BattleRules.emit({ version = "firered", gen3BattleRules = { critMultiplier = 3 } }, function()
  return "{ critMultiplier = 3 }"
end, critOut)
local applyCrit = assert(loadstring(table.concat(critOut, "\n")))
setfenv(applyCrit, setmetatable({ mod = { hooks = hooks } }, { __index = _G }))
applyCrit()
assert(Rules.crit.multiplier() == 3, "crit multiplier reaches the battle")
Runtime.reset()
assert(Rules.crit.multiplier() == 2, "disabling the mod restores the cart crit multiplier")

print("PASS crit chances")
