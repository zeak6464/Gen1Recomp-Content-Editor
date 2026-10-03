-- FireRed link (Gen3FrLink / Gen3FrLinkRuntime): FireRed tilesets and map
-- layouts in Emerald mods, read from the player's FireRed / LeafGreen import.
-- Plain LuaJIT, no LOVE. Run from the repository root:
--   luajit tests/content-editor/test_gen3_frlink.lua
package.path = "tools/content-editor/?.lua;" .. package.path
package.loaded["src.core.GameVersion"] = {
  cachePrefix = function(game) return game .. "/" end,
  revisions = function(game)
    return ({ firered = { { sha1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" }, { sha1 = "dd5945db9b930750cb39d00c84da8571feebf417" } },
      leafgreen = { { sha1 = "574fa542ffebb14be69902d1d36f1ec0a4afd71e" } } })[game] or {}
  end,
}
local R = require("Gen3FrLinkRuntime")
local L = require("Gen3FrLink")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("FireRed tileset folders are sent to the import", function()
  assert(R.redirect("data/generated/gba/native/frlg__pallet_outdoor/mids.idx") == "data/generated/gba/native/pallet_outdoor/mids.idx")
  assert(R.redirect("data/generated/gba/native/frlg__building__rom_082d4bcc/palettes.bin")
    == "data/generated/gba/native/building__rom_082d4bcc/palettes.bin")
  assert(R.redirect("data/generated/gba/native/general__petalburg/mids.idx") == nil)
  assert(R.redirect(nil) == nil)
end)

run("only a finished FireRed or LeafGreen import of a known dump counts", function()
  local files = {}
  local function readAt(p) return files[p] end
  assert(R.find(readAt) == nil)
  files["firered/rom-cache.complete"] = "rom-cache-v21-firered:0000"
  assert(R.find(readAt) == nil)
  files["leafgreen/rom-cache.complete"] = "rom-cache-v21-leafgreen:574FA542FFEBB14BE69902D1D36F1EC0A4AFD71E"
  local prefix, game = R.find(readAt)
  assert(prefix == "leafgreen/" and game == "leafgreen")
  files["firered/rom-cache.complete"] = "rom-cache-v21-firered:dd5945db9b930750cb39d00c84da8571feebf417"
  prefix, game = R.find(readAt)
  assert(prefix == "firered/" and game == "firered")
  files = { ["firered/rom-cache.complete"] = "rom-cache-v3-emerald:41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" }
  assert(R.find(readAt) == nil)
end)

run("names and labels", function()
  assert(L.isPair("frlg__pallet_outdoor") and not L.isPair("general__petalburg") and not L.isPair(nil))
  assert(L.isMap("frlg:FR_PALLET_TOWN") and not L.isMap("EM_LITTLEROOT_TOWN"))
  assert(L.label("frlg__pallet_outdoor") == "FireRed: pallet_outdoor")
  assert(L.label("frlg__building__rom_082d4bcc") == "FireRed: building_ / 082d4bcc")
  assert(L.label("general__petalburg") == "general__petalburg")
end)

run("used() finds FireRed layouts, tilesets, borders and painted tiles", function()
  assert(not L.used({}))
  assert(L.used({ gen3MapLayouts = { EM_A = { source = "frlg:FR_ROUTE_1", width = 1, height = 1 } } }))
  assert(L.used({ gen3MapLayouts = { EM_A = { source = "EM_LITTLEROOT_TOWN", pair = "frlg__pallet_outdoor" } } }))
  assert(not L.used({ gen3MapLayouts = { EM_A = { source = "EM_LITTLEROOT_TOWN", width = 1, height = 1 } } }))
  assert(L.used({ gen3Borders = { EM_A = { borderPair = "frlg__pallet_outdoor" } } }))
  assert(L.used({ gen3VoidMaps = { EM_A = { pair = "frlg__pallet_outdoor" } } }))
  assert(L.used({ gen3VoidMaps = { EM_A = { cells = { [1] = { m = 3, p = "frlg__viridian_outdoor" } } } } }))
  assert(L.used({ layeredMaps = { EM_A = { baseTileset = "frlg__pallet_outdoor", layers = {} } } }))
  assert(L.used({ layeredMaps = { EM_A = { baseTileset = "general__petalburg",
    layers = { { cells = { [4] = { source = "@runtime:frlg__pallet_outdoor", tile = 7 } } } } } } }))
  assert(not L.used({ layeredMaps = { EM_A = { baseTileset = "general__petalburg",
    layers = { { cells = { [4] = { source = "@runtime:general__petalburg", tile = 7 } } } } } } }))
end)

run("the GAME PATCHES switch is Emerald's; Import region names", function()
  local p = { game = "emerald" }
  assert(not L.enabled(p) and L.setEnabled(p, true) and L.enabled(p) and not L.setEnabled(p, true))
  assert(L.setEnabled(p, false) and p.gen3FrLink == nil and not L.enabled(p))
  assert(not L.enabled({ game = "firered", gen3FrLink = true }))
  assert(L.regionId("FR_PALLET_TOWN") == "EM_KANTO_PALLET_TOWN")
  assert(L.regionId("SEVII_ONE_ISLAND") == "EM_KANTO_SEVII_ONE_ISLAND")
  assert(L.used({ gen3FrRegion = true }))
  assert(not L.templateMaps({ game = "emerald" })[1])
end)

run("Wild Pokemon is on unless turned off", function()
  assert(L.wildEnabled({}) and L.wildEnabled({ gen3FrWild = true }) and not L.wildEnabled({ gen3FrWild = false }))
  local S = { project = {} }
  assert(not L.setWild(S, true) and L.setWild(S, false) and S.project.gen3FrWild == false)
  assert(L.setWild(S, true) and S.project.gen3FrWild == nil)
end)

run("people: talkers, mart clerks and nurses as steps; story people stay out", function()
  local function msg(t) return { { op = "loadword", dest = 0, value = t }, { op = "callstd", std = 2 }, { op = "end" } } end
  L._scripts = {
    ["g3:talk"] = msg("g3:t1"),
    ["g3:clerk"] = { { op = "lock" }, { op = "faceplayer" }, { op = "compare_var_to_value" }, { op = "goto_if", target = "g3:x" },
      { op = "message", ptr = "g3:hi" }, { op = "waitmessage" }, { op = "pokemart", items = "g3:list" },
      { op = "loadword", dest = 0, value = "g3:bye" }, { op = "callstd", std = 4 }, { op = "release" }, { op = "end" } },
    ["g3:nurse"] = { { op = "lock" }, { op = "faceplayer" }, { op = "call", target = "g3:heal" }, { op = "release" }, { op = "end" } },
    ["g3:heal"] = { { op = "special" }, { op = "return" } },
    ["g3:gift"] = { { op = "giveitem" }, { op = "end" } },
    ["g3:trainer"] = msg("g3:t1"),
  }
  L._texts = { ["g3:t1"] = "Hi", ["g3:hi"] = "May I help you?", ["g3:bye"] = "Please come again!" }
  L._events = { FR_TEST = { objects = {
    { localId = 1, x = 1, y = 2, graphicsId = 5, sprite = "SPRITE_BOY", flag = 0, trainerType = 0, movementType = 8, scriptKey = "g3:talk" },
    { localId = 2, x = 3, y = 4, graphicsId = 68, sprite = "SPRITE_CLERK", flag = 0, trainerType = 0, movementType = 10, scriptKey = "g3:clerk" },
    { localId = 3, x = 5, y = 6, graphicsId = 64, sprite = "SPRITE_NURSE", flag = 0, trainerType = 0, movementType = 8, scriptKey = "g3:nurse" },
    { localId = 4, x = 7, y = 8, graphicsId = 5, sprite = "SPRITE_BOY", flag = 0, trainerType = 0, scriptKey = "g3:gift" },
    { localId = 5, x = 9, y = 9, graphicsId = 5, sprite = "SPRITE_BOY", flag = 0, trainerType = 1, scriptKey = "g3:trainer" },
    { localId = 6, x = 9, y = 1, graphicsId = 5, sprite = "SPRITE_BOY", flag = 120, trainerType = 0, scriptKey = "g3:talk" },
  } } }
  L._nurse = nil
  local p = {}
  local objects, left = L.peopleFor(p, "FR_TEST")
  for _, k in ipairs({ "g3:talk", "g3:clerk", "g3:nurse" }) do local st, why = L.personSteps(k); assert(st, k .. ": " .. tostring(why)) end
  assert(#objects == 3 and left == 3, #objects .. " " .. left)
  assert(objects[1].scriptKey == "frlg:g3:talk" and objects[1].frlgGfx == 5 and objects[1].flag == 0)
  local clerk = p.gen3FrTalk["frlg:g3:clerk"]
  assert(clerk[1][1] == "say" and clerk[2][1] == "mart" and clerk[2][2] == "g3:list" and clerk[3][1] == "text")
  local nurse = p.gen3FrTalk["frlg:g3:nurse"]
  assert(#nurse == 1 and nurse[1][1] == "nurse" and nurse[1][2] == 3)
  -- signs don't take shops or nurses
  assert(L.signSteps("g3:clerk") == nil and L.signSteps("g3:talk"))
  L._scripts, L._texts, L._events, L._nurse = nil, nil, nil, nil
  assert(L.peopleEnabled({}) and not L.peopleEnabled({ gen3FrPeople = false }))
  local S = { project = {} }
  assert(not L.setPeople(S, true) and L.setPeople(S, false) and S.project.gen3FrPeople == false)
  assert(L.setPeople(S, true) and S.project.gen3FrPeople == nil)
end)

run("signs and people become Emerald scripts (game and editor share them)", function()
  local sign = R.signOps({ { "text", "g3:t1" }, { "braille", "g3:b" } })
  assert(sign[1].op == "lockall" and sign[2].op == "loadword" and sign[2].value == "frlg:g3:t1" and sign[#sign].op == "end")
  local clerk = R.personOps({ { "say", "g3:hi" }, { "mart", "g3:list" }, { "text", "g3:bye" } })
  assert(clerk[1].op == "lock" and clerk[3].op == "message" and clerk[5].op == "pokemart" and clerk[5].items == "frlg:g3:list")
  assert(R.personOps({ { "nurse", 3 } }) == nil)
  local nurse = R.personOps({ { "nurse", 3 } }, "g3:heal")
  assert(nurse[1].op == "setvar" and nurse[1].value == 3 and nurse[2].target == "g3:heal")
end)

run("only Emerald mods can carry it", function()
  local p = { game = "firered", gen3MapLayouts = { EM_A = { source = "frlg:FR_ROUTE_1" } } }
  local ok, err = pcall(L.emit, p, tostring, {})
  assert(not ok and tostring(err):find("Emerald", 1, true))
  local out = {}
  L.emit({ game = "emerald" }, tostring, out)
  assert(#out == 0)
end)

run("export: FireRed's own step callback (Icefall Cave ice) is named per map", function()
  L._scripts = { ["g3:resume"] = { { op = "setstepcallback", 4 }, { op = "end" } } }
  L._texts, L._events = {}, { FR_ICEFALL = { mapScripts = { onResume = "g3:resume" } }, FR_ROUTE_1 = { mapScripts = {} } }
  _G.love = { filesystem = { read = function() return "return {}" end } }
  local p = { game = "emerald", gen3 = { maps = { EM_KANTO_ICEFALL = {}, EM_KANTO_ROUTE_1 = {} } },
    gen3MapLayouts = { EM_KANTO_ICEFALL = { source = "frlg:FR_ICEFALL" }, EM_KANTO_ROUTE_1 = { source = "frlg:FR_ROUTE_1" } } }
  local out, cfgs = {}, {}
  L.emit(p, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  L._scripts, L._texts, L._events, L._furniture, L._pack = nil, nil, nil, nil, nil
  _G.love = nil
  local last = cfgs[#cfgs]
  assert(out[#out]:find("regionTiles.install(mod,CFG)", 1, true) and last.host == "rse" and last.origin == "firered")
  assert(last.steps.EM_KANTO_ICEFALL == "ice" and last.steps.EM_KANTO_ROUTE_1 == nil)
end)

run("export: Town Map and Fly, with the towns each map marks as visited", function()
  L._scripts = { ["g3:enter"] = { { op = "setworldmapflag", 2192 }, { op = "end" } }, ["g3:none"] = { { op = "end" } } }
  L._texts = {}
  L._events = { FR_PALLET_TOWN = { mapScripts = { onTransition = "g3:enter" } }, FR_ROUTE_1 = { mapScripts = { onTransition = "g3:none" } } }
  _G.love = { filesystem = { read = function() return "return {}" end } }
  local p = { game = "emerald", gen3FrRegion = true, gen3 = { maps = { EM_KANTO_PALLET_TOWN = {}, EM_KANTO_ROUTE_1 = {} } },
    gen3MapLayouts = { EM_KANTO_PALLET_TOWN = { source = "frlg:FR_PALLET_TOWN" }, EM_KANTO_ROUTE_1 = { source = "frlg:FR_ROUTE_1" } } }
  local out, cfgs = {}, {}
  L.emit(p, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  L._scripts, L._texts, L._events, L._furniture, L._pack = nil, nil, nil, nil, nil
  _G.love = nil
  local last = cfgs[#cfgs]
  assert(out[#out]:find("regionMap.install(mod,CFG)", 1, true) and last.host == "rse" and last.origin == "firered" and last.cross == true)
  assert(last.prefix == "FR_" and last.secBase == 0 and last.visits.EM_KANTO_PALLET_TOWN[1] == 2192 and last.visits.EM_KANTO_ROUTE_1 == nil)
end)

run("PokeNav text: defaults, limits, and what the export carries", function()
  local S = { project = { game = "emerald" } }
  assert(L.navText(S.project, "label") == "REGION MAP" and L.navText(S.project, "desc") == "Check the map of the region.")
  assert(L.setNavText(S, "label", "kanto map") and L.navText(S.project, "label") == "KANTO MAP")
  assert(not L.setNavText(S, "label", "kanto map"))
  assert(L.setNavText(S, "label", "a very long label indeed") and #L.navText(S.project, "label") == 10)
  assert(L.setNavText(S, "desc", ("x"):rep(80)) and #L.navText(S.project, "desc") == 40)
  -- empty or the default itself clears it
  assert(L.setNavText(S, "label", "") and S.project.gen3FrNavLabel == nil and L.navText(S.project, "label") == "REGION MAP")
  assert(L.setNavText(S, "desc", "Hi") and L.setNavText(S, "desc", L.NAV_DEFAULT.desc) and S.project.gen3FrNavDesc == nil)
  assert(not L.setNavText({}, "label", "x"))
  L._scripts, L._texts, L._events = {}, {}, {}
  _G.love = { filesystem = { read = function() return "return {}" end } }
  L.setNavText(S, "label", "Kanto")
  local p = { game = "emerald", gen3FrRegion = true, gen3FrNavLabel = S.project.gen3FrNavLabel, gen3 = { maps = {} }, gen3MapLayouts = {} }
  local out, cfgs = {}, {}
  L.emit(p, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  L._scripts, L._texts, L._events, L._furniture, L._pack = nil, nil, nil, nil, nil
  _G.love = nil
  local last = cfgs[#cfgs]
  assert(last.nav.label == "KANTO" and last.nav.desc == "Check the map of the region.")
end)

run("furniture: FireRed's shelves and signs read in Emerald", function()
  local scripts = { EventScript_Dresser = { { op = "loadword", 0, "g3:dr" }, { op = "callstd", 3 }, { op = "end" } },
    EventScript_PokecenterSign = { { op = "loadword", 0, "g3:pc" }, { op = "callstd", 3 }, { op = "end" } },
    EventScript_Cabinet = { { op = "setflag", 5 }, { op = "end" } } }
  L._furniture, L._pack = nil, { scripts = scripts, text = { ["g3:dr"] = { { t = "text", s = "A dresser." } }, ["g3:pc"] = { { t = "text", s = "Heal!" } } } }
  L._scripts, L._texts = {}, setmetatable({}, { __index = function(_, k) return L._pack.text[k] end })
  local rows, steps = L.furniture()
  L._furniture, L._pack, L._scripts, L._texts = nil, nil, nil, nil
  assert(rows["139"].script == "frlg:furn:139" and rows["139"].facing == nil)
  assert(rows["135"].script == "frlg:furn:135" and rows["135"].facing == "up")
  assert(rows["137"] == nil, "a script that isn't a message stays out")
  assert(steps["frlg:furn:139"][1][1] == "text" and steps["frlg:furn:139"][1][2] == "g3:dr")
end)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
