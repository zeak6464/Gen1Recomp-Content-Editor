-- Leech Seed, Wrap, Nightmare, Curse, and Leftovers stay on the cart
-- fractions until they are edited.

package.path = table.concat({
  "tools/content-editor/?.lua",
  "tools/content-editor/panels/?.lua",
  "tools/save-editor/?.lua",
  "runtime/gen1recomp/?.lua",
  "runtime/gen1recomp/?/init.lua",
  package.path,
}, ";")

dofile("tests/love_stub.lua")

local function assertEq(actual, expected, label)
  if actual ~= expected then
    error(label .. ": got " .. tostring(actual) .. " expected " .. tostring(expected))
  end
end

local Effects = require("src.battle.gen2.Effects")
assertEq(Effects.portion(80, Effects.LEECH_DIV, 8), 10, "gen2 leech")
assertEq(Effects.wrapTurns(function() return 0 end), 3, "gen2 wrap")
Effects.WRAP_MIN = 1
assertEq(Effects.wrapTurns(function() return 0 end), 1, "gen2 wrap edited")
Effects.WRAP_MIN = 3
Effects.LEECH_DIV = 4
local Battle = require("src.battle.gen2.Battle")
local mon = { hp = 80, maxHp = 80 }
local state = { leechSeed = true }
Battle.tickSeedAndCurse({
  volatile = function() return state end,
  emit = function() end,
  sideOf = function() return "player" end,
  monName = function() return "A" end,
  player = { hp = 80, maxHp = 80 },
  enemy = mon,
  heal = function(_, _, amount) return amount end,
}, mon)
assertEq(mon.hp, 60, "gen2 seed tick")
Effects.LEECH_DIV = 8

local MoveEffects = require("src.battle.MoveEffects")
local user = {}
MoveEffects.full.TRAPPING_EFFECT.afterDamage({
  user = user,
  move = { id = "BIND" },
  rng = function(_, hi) return hi end,
})
assertEq(user.trappingTurns, 4, "gen1 trap")
user = {}
MoveEffects.TRAP_TURNS = { 9 }
MoveEffects.full.TRAPPING_EFFECT.afterDamage({
  user = user,
  move = { id = "BIND" },
  rng = function() return 0 end,
})
assertEq(user.trappingTurns, 9, "gen1 trap edited")
MoveEffects.TRAP_TURNS = nil
user = { isPlayer = true }
MoveEffects.full.THRASH_PETAL_DANCE_EFFECT.beforeAccuracy({
  user = user,
  rng = function(_, hi) return hi end,
  battle = { animBeforeMove = function() end },
})
assertEq(user.thrashTurns, 3, "gen1 thrash")
user = { isPlayer = true }
MoveEffects.THRASH_HI = 5
MoveEffects.full.THRASH_PETAL_DANCE_EFFECT.beforeAccuracy({
  user = user,
  rng = function(_, hi) return hi end,
  battle = { animBeforeMove = function() end },
})
assertEq(user.thrashTurns, 5, "gen1 thrash edited")
MoveEffects.THRASH_HI = 3

local Rules = require("src.core.game3.battle.rules")
local Capabilities = require("src.core.game3.battle.capabilities")
assertEq(Rules.residual.amount(80, "leechDiv", 8), 10, "gen3 leech")
assertEq(Rules.weather.chipAmount(80), 5, "gen3 weather chip")
assertEq(Rules.partialTrap.rollTurns(function() return 0 end), 3, "gen3 wrap")
Rules.residual.leechDiv = 4
assertEq(Rules.residual.amount(80, "leechDiv", 8), 20, "gen3 leech edited")
Rules.residual.leechDiv = 8
Capabilities.partialTrapMinTurns = 1
Capabilities.partialTrapMaxTurns = 1
assertEq(Rules.partialTrap.rollTurns(function() return 0 end), 1, "gen3 wrap edited")
Capabilities.partialTrapMinTurns = 3
Capabilities.partialTrapMaxTurns = 6

local Writer = require("ModWriter")
local red = Writer.emitMain({ version = "red", generation = 1, residualRules = {
  trapTurns = { 9, 1, 1, 2, 2, 2, 3, 4 }, thrashHi = 5,
} })
assert(red:find("MoveEffects.TRAP_TURNS = { 9, 1, 1, 2, 2, 2, 3, 4 }", 1, true), "red trap")
assert(red:find("MoveEffects.THRASH_HI = 5", 1, true), "red thrash")
assert(not red:find("src.battle.gen2.Effects", 1, true), "red stays off gen2")
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local main = Writer.emitMain({ version = version, generation = 2, residualRules = {
    leechDiv = 4, wrapMin = 1, leftoversDiv = 8,
  } })
  assert(main:find("Effects.LEECH_DIV = 4", 1, true), version .. " leech")
  assert(main:find("Effects.WRAP_MIN = 1", 1, true), version .. " wrap")
  assert(main:find("Effects.LEFTOVERS_DIV = 8", 1, true), version .. " leftovers")
end

local Gen3BattleRules = require("Gen3BattleRules")
local Gen3Native = require("Gen3Native")
for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local p = { version = version, generation = 3, gen3Residual = {
    leechDiv = 4, weatherTurns = 8, leftoversDiv = 8,
  } }
  assert(Gen3Native.used(p), version .. " native")
  local out = {}
  Gen3BattleRules.emitResiduals(p, function() return "" end, out)
  local chunk = table.concat(out, "\n")
  assert(loadstring(chunk), version .. " compiles")
  assert(chunk:find("Rules.residual.leechDiv = 4", 1, true), version)
  assert(chunk:find("Capabilities.weatherDefaultTurns = 8", 1, true), version)
  assert(chunk:find("Rules.residual.leftoversDiv = 8", 1, true), version)
end

local saved = {
  weather = Capabilities.weatherChipDenom,
  chip = Capabilities.partialTrapChipDenom,
  minTurns = Capabilities.partialTrapMinTurns,
  maxTurns = Capabilities.partialTrapMaxTurns,
  crit = Rules.crit.multiplier,
}
local wired = {}
Gen3BattleRules.emit({ version = "firered", generation = 3, gen3BattleRules = {
  shinyBelow = 9, weatherChipDenom = 8, partialTrapChipDenom = 4,
  partialTrapMinTurns = 2, partialTrapMaxTurns = 2,
} }, function()
  return "{ shinyBelow = 9, weatherChipDenom = 8, partialTrapChipDenom = 4, partialTrapMinTurns = 2, partialTrapMaxTurns = 2 }"
end, wired)
local wiredChunk = table.concat(wired, "\n")
assert(not wiredChunk:find("editor.gen3.rules", 1, true), "weather and trap stay on the cart functions")
assert(wiredChunk:find("Capabilities.weatherChipDenom = battleRules.weatherChipDenom", 1, true), "weather divisor is saved")
assert(wiredChunk:find("Capabilities.partialTrapChipDenom = battleRules.partialTrapChipDenom", 1, true), "trap divisor is saved")
assert(wiredChunk:find("Capabilities.partialTrapMinTurns = battleRules.partialTrapMinTurns", 1, true), "trap minimum is saved")
assert(wiredChunk:find("Capabilities.partialTrapMaxTurns = battleRules.partialTrapMaxTurns", 1, true), "trap maximum is saved")
local apply = assert(loadstring(wiredChunk))
setfenv(apply, setmetatable({ mod = { hooks = { wrap = function() end } } }, { __index = _G }))
apply()
assertEq(Rules.weather.chipAmount(80), 10, "weather divisor reaches the battle")
assertEq(Rules.partialTrap.chipAmount(80), 20, "trap divisor reaches the battle")
assertEq(Rules.partialTrap.rollTurns(function() return 99 end), 2, "trap turns reach the battle")
assert(Rules.crit.multiplier == saved.crit, "a non-crit edit does not replace the crit function")
Capabilities.weatherChipDenom = saved.weather
Capabilities.partialTrapChipDenom = saved.chip
Capabilities.partialTrapMinTurns = saved.minTurns
Capabilities.partialTrapMaxTurns = saved.maxTurns

require("Rules")
print("PASS residuals")
