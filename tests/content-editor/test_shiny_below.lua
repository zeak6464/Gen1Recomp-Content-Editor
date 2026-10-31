-- A check of 0 is shiny and a check of 8 is not. A line of 0 makes
-- the 0 check ordinary. A line of 9 makes the 8 check shiny. The
-- Frontier reroll uses the same line. Every Gen 3 game emits it.
-- Gold does not.

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

local Pokemon = require("src.core.game3.pokemon")
local D = require("src.core.game3.rse.frontier.trainers")
assertEq(Pokemon.isShiny({ personality = 0, otId = 0, otSecretId = 0 }), true, "a check of 0 is shiny")
assertEq(Pokemon.isShiny({ personality = 8, otId = 0, otSecretId = 0 }), false, "a check of 8 is not shiny")
assertEq(D.isShiny(0, 0), true, "the Frontier check of 0 is shiny")
assertEq(D.isShiny(0, 8), false, "the Frontier check of 8 is not shiny")
Pokemon.SHINY_BELOW = 0
assertEq(Pokemon.isShiny({ personality = 0, otId = 0, otSecretId = 0 }), false, "a line of 0 is never shiny")
assertEq(D.isShiny(0, 0), false, "the Frontier line of 0 is never shiny")
Pokemon.SHINY_BELOW = 9
assertEq(Pokemon.isShiny({ personality = 8, otId = 0, otSecretId = 0 }), true, "a line of 9 makes 8 shiny")
Pokemon.SHINY_BELOW = 8

local Rules = require("Gen3BattleRules")
for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local out = {}
  Rules.emit({ version = version, gen3BattleRules = { shinyBelow = 0 } }, function()
    return "{ shinyBelow = 0 }"
  end, out)
  local chunk = table.concat(out, "\n")
  assert(chunk:find("SHINY_BELOW = battleRules.shinyBelow", 1, true), version)
  assert(not chunk:find("editor.gen3.rules", 1, true), version .. " shiny edit leaves crit, weather, and trap functions alone")
end
local Writer = require("ModWriter")
local gold = Writer.emitMain({ version = "gold", generation = 2, gen3BattleRules = { shinyBelow = 0 } })
assert(not gold:find("SHINY_BELOW", 1, true), "gold")

print("PASS shiny below")
