-- Emerald link (Gen3EmLink / Gen3EmLinkRuntime / Gen3Link): Emerald tilesets
-- and map layouts in FireRed / LeafGreen mods, read from the player's Emerald
-- import. Plain LuaJIT, no LOVE. Run from the repository root:
--   luajit tests/content-editor/test_gen3_emlink.lua
package.path = "tools/content-editor/?.lua;" .. package.path
package.loaded["src.core.GameVersion"] = {
  cachePrefix = function(game) return game .. "/" end,
  revisions = function(game)
    return ({ emerald = { { sha1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7" } },
      firered = { { sha1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" } } })[game] or {}
  end,
}
local R = require("Gen3EmLinkRuntime")
local L = require("Gen3EmLink")
local Link = require("Gen3Link")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("Emerald tileset folders are sent to the import", function()
  assert(R.redirect("data/generated/gba/native/em__general__petalburg/mids.idx") == "data/generated/gba/native/general__petalburg/mids.idx")
  assert(R.redirect("data/generated/gba/native/em__building__pokemon_center/palettes.bin")
    == "data/generated/gba/native/building__pokemon_center/palettes.bin")
  assert(R.redirect("data/generated/gba/native/frlg__pallet_outdoor/mids.idx") == nil)
  assert(R.redirect(nil) == nil)
end)

run("only a finished Emerald import of a known dump counts", function()
  local files = {}
  local function readAt(p) return files[p] end
  assert(R.find(readAt) == nil)
  files["emerald/rom-cache.complete"] = "rom-cache-v3-emerald:0000"
  assert(R.find(readAt) == nil)
  files["emerald/rom-cache.complete"] = "rom-cache-v3-emerald:F3AE088181BF583E55DAF962A92BB46F4F1D07B7"
  local prefix, game = R.find(readAt)
  assert(prefix == "emerald/" and game == "emerald")
  files = { ["emerald/rom-cache.complete"] = "rom-cache-v21-firered:f3ae088181bf583e55daf962a92bb46f4f1d07b7" }
  assert(R.find(readAt) == nil)
end)

run("names and labels", function()
  assert(L.isPair("em__general__petalburg") and not L.isPair("frlg__pallet_outdoor") and not L.isPair(nil))
  assert(L.isMap("em:EM_LITTLEROOT_TOWN") and not L.isMap("frlg:FR_PALLET_TOWN"))
  assert(L.label("em__general__petalburg") == "Emerald: general / petalburg")
  assert(L.label("pallet_outdoor") == "pallet_outdoor")
  -- the dispatcher tells the two games apart
  assert(Link.isPair("em__general__petalburg") and Link.isPair("frlg__pallet_outdoor") and not Link.isPair("general__petalburg"))
  assert(Link.isMap("em:EM_ROUTE101") and Link.isMap("frlg:FR_ROUTE_1") and not Link.isMap("EM_ROUTE101"))
  assert(Link.redirect("data/generated/gba/native/em__x__y/a") and Link.redirect("data/generated/gba/native/frlg__x/a"))
  assert(Link.templateName("em:EM_ROUTE101") == "ROUTE101" and Link.templateName("frlg:FR_ROUTE_1") == "ROUTE_1")
end)

run("used() finds Emerald layouts, tilesets, borders and painted tiles", function()
  assert(not L.used({}))
  assert(L.used({ gen3MapLayouts = { FR_A = { source = "em:EM_ROUTE101", width = 1, height = 1 } } }))
  assert(L.used({ gen3MapLayouts = { FR_A = { source = "FR_PALLET_TOWN", pair = "em__general__petalburg" } } }))
  assert(not L.used({ gen3MapLayouts = { FR_A = { source = "FR_PALLET_TOWN", width = 1, height = 1 } } }))
  assert(L.used({ gen3Borders = { FR_A = { borderPair = "em__general__petalburg" } } }))
  assert(L.used({ gen3VoidMaps = { FR_A = { cells = { [1] = { m = 3, p = "em__general__petalburg" } } } } }))
  assert(L.used({ layeredMaps = { FR_A = { baseTileset = "em__general__petalburg", layers = {} } } }))
  assert(not L.used({ layeredMaps = { FR_A = { baseTileset = "pallet_outdoor", layers = {} } } }))
  assert(Link.used({ gen3EmRegion = true }) and not Link.used({}))
end)

run("the GAME PATCHES switch is FireRed / LeafGreen's; Import region names", function()
  for _, game in ipairs({ "firered", "leafgreen" }) do
    local p = { game = game }
    assert(not L.enabled(p) and L.setEnabled(p, true) and L.enabled(p) and not L.setEnabled(p, true))
    assert(Link.host(p) == L and Link.name(p) == "Emerald")
    assert(L.setEnabled(p, false) and p.gen3EmLink == nil and not L.enabled(p))
  end
  assert(not L.enabled({ game = "emerald", gen3EmLink = true }))
  assert(L.regionId("EM_LITTLEROOT_TOWN") == "FR_HOENN_LITTLEROOT_TOWN")
  assert(L.used({ gen3EmRegion = true }))
  assert(not L.templateMaps({ game = "firered" })[1])
end)

run("Wild Pokemon is on unless turned off", function()
  assert(L.wildEnabled({}) and L.wildEnabled({ gen3EmWild = true }) and not L.wildEnabled({ gen3EmWild = false }))
  local S = { project = {} }
  assert(not L.setWild(S, true) and L.setWild(S, false) and S.project.gen3EmWild == false)
  assert(L.setWild(S, true) and S.project.gen3EmWild == nil)
end)

run("people: talkers, mart clerks and nurses as steps; story people stay out", function()
  local function msg(t) return { { op = "loadword", dest = 0, value = t }, { op = "callstd", std = 2 }, { op = "end" } } end
  L._scripts = {
    ["g3:talk"] = msg("g3:t1"),
    ["g3:clerk"] = { { op = "lock" }, { op = "faceplayer" }, { op = "compare_var_to_value" }, { op = "goto_if", target = "g3:x" },
      { op = "message", ptr = "g3:hi" }, { op = "waitmessage" }, { op = "pokemart", items = "g3:list" },
      { op = "loadword", dest = 0, value = "g3:bye" }, { op = "callstd", std = 4 }, { op = "release" }, { op = "end" } },
    ["g3:nurse"] = { { op = "setvar", var = 0x800B, value = 3 }, { op = "call", target = "g3:heal" }, { op = "waitmessage" },
      { op = "waitbuttonpress" }, { op = "release" }, { op = "end" } },
    ["g3:heal"] = { { op = "special" }, { op = "return" } },
    ["g3:gift"] = { { op = "giveitem" }, { op = "end" } },
    ["g3:trainer"] = msg("g3:t1"),
    ["g3:var"] = msg("g3:t1"),
  }
  L._texts = { ["g3:t1"] = "Hi", ["g3:hi"] = "May I help you?", ["g3:bye"] = "Please come again!" }
  L._events = { EM_OLDALE_TOWN_POKEMON_CENTER_1F = { objects = { { localId = 3, scriptKey = "g3:nurse" } } },
    EM_TEST = { objects = {
    { localId = 1, x = 1, y = 2, graphicsId = 16, flag = 0, trainerType = 0, movementType = 8, scriptKey = "g3:talk" },
    { localId = 2, x = 3, y = 4, graphicsId = 83, flag = 0, trainerType = 0, movementType = 10, scriptKey = "g3:clerk" },
    { localId = 3, x = 5, y = 6, graphicsId = 58, flag = 0, trainerType = 0, movementType = 8, scriptKey = "g3:nurse" },
    { localId = 4, x = 7, y = 8, graphicsId = 16, flag = 0, trainerType = 0, scriptKey = "g3:gift" },
    { localId = 5, x = 9, y = 9, graphicsId = 16, flag = 0, trainerType = 1, scriptKey = "g3:trainer" },
    { localId = 6, x = 9, y = 1, graphicsId = 16, flag = 120, trainerType = 0, scriptKey = "g3:talk" },
    { localId = 7, x = 9, y = 2, graphicsId = 240, flag = 0, trainerType = 0, scriptKey = "g3:var" },
  } } }
  L._nurse = nil
  local p = {}
  local objects, left = L.peopleFor(p, "EM_TEST")
  for _, k in ipairs({ "g3:talk", "g3:clerk", "g3:nurse" }) do local st, why = L.personSteps(k); assert(st, k .. ": " .. tostring(why)) end
  assert(#objects == 3 and left == 4, #objects .. " " .. left)
  assert(objects[1].scriptKey == "em:g3:talk" and objects[1].emGfx == 16 and objects[1].flag == 0)
  assert(objects[3].emGfx == 58 and objects[3].graphicsId == objects[3].graphics)
  local clerk = p.gen3EmTalk["em:g3:clerk"]
  assert(clerk[1][1] == "say" and clerk[2][1] == "mart" and clerk[2][2] == "g3:list" and clerk[3][1] == "text")
  local nurse = p.gen3EmTalk["em:g3:nurse"]
  assert(#nurse == 1 and nurse[1][1] == "nurse" and nurse[1][2] == 3)
  -- signs don't take shops or nurses
  assert(L.signSteps("g3:clerk") == nil and L.signSteps("g3:talk"))
  L._scripts, L._texts, L._events, L._nurse = nil, nil, nil, nil
  assert(L.peopleEnabled({}) and not L.peopleEnabled({ gen3EmPeople = false }))
  local S = { project = {} }
  assert(not L.setPeople(S, true) and L.setPeople(S, false) and S.project.gen3EmPeople == false)
  assert(L.setPeople(S, true) and S.project.gen3EmPeople == nil)
end)

run("signs and people become FireRed scripts (game and editor share them)", function()
  local sign = R.signOps({ { "text", "g3:t1" }, { "braille", "g3:b" } })
  assert(sign[1].op == "lockall" and sign[2].op == "loadword" and sign[2].value == "em:g3:t1" and sign[#sign].op == "end")
  local clerk = R.personOps({ { "say", "g3:hi" }, { "mart", "g3:list" }, { "text", "g3:bye" } })
  assert(clerk[1].op == "lock" and clerk[3].op == "message" and clerk[5].op == "pokemart" and clerk[5].items == "em:g3:list")
  assert(R.personOps({ { "nurse", 3 } }) == nil)
  local nurse = R.personOps({ { "nurse", 3 } }, "g3:heal")
  assert(nurse[1].op == "setvar" and nurse[1].value == 3 and nurse[2].target == "g3:heal")
end)

run("export: the mod gets names, wild keys and nurse spots only", function()
  L._events, L._slots = nil, { EM_ROUTE101 = { slot = "0_16", header = {} }, EM_OLDALE_TOWN_POKEMON_CENTER_1F = { slot = "4_5", header = {} } }
  local fakeFs = { read = function() return "return {}" end }
  _G.love = { filesystem = fakeFs }
  local out = {}
  local p = { game = "firered", gen3EmRegion = true,
    gen3MapLayouts = { FR_HOENN_ROUTE101 = { source = "em:EM_ROUTE101" }, FR_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F = { source = "em:EM_OLDALE_TOWN_POKEMON_CENTER_1F" } },
    gen3EmTalk = { ["em:g3:nurse"] = { { "nurse", 1 } } },
    gen3 = { maps = { FR_HOENN_ROUTE101 = { objects = {} }, FR_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F = {
      objects = { { x = 7, y = 2, localId = 1, emGfx = 58, scriptKey = "em:g3:nurse" } } } } } }
  local cfg
  -- the import's own tile interactions: a vase (Emerald-only), a book shelf
  -- (FireRed has it), a cable box (needs the player to face it)
  L._furniture, L._pack = nil, { interactions = { [483] = { script = "EventScript_Vase" },
    [129] = { script = "EventScript_BookShelf" }, [487] = { facing = "up", script = "EventScript_CableBoxResults" } } }
  L._scripts = { ["g3:vase"] = { { op = "loadword", 0, "g3:vt" }, { op = "callstd", 3 }, { op = "end" } } }
  L._texts = { ["g3:vt"] = "Just a vase." }
  L._events = {}
  L.editor = function()
    return { read = function(path)
      if path:find("labels.lua", 1, true) then return 'return {EventScript_Vase="g3:vase",EventScript_BookShelf="g3:book"}' end
    end }
  end
  -- Emerald's own map scripts: Route 101 sets the ash-grass step callback (1)
  -- from onResume; the Pokemon Center sets nothing
  L._scripts["g3:resume"] = { { op = "setstepcallback", 1 }, { op = "end" } }
  L._events = { EM_ROUTE101 = { mapScripts = { onResume = "g3:resume" } } }
  local cfgs = {}
  package.preload["src.core.game3.constants"] = function()
    return { of = function() return { flag = function() return 2152 end } end }
  end
  L.emit(p, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  package.preload["src.core.game3.constants"], package.loaded["src.core.game3.constants"] = nil, nil
  cfg = cfgs[1]
  L._furniture, L._pack, L._scripts, L._texts, L._events = nil, nil, nil, nil, nil
  _G.love = nil
  assert(cfg.furniture["483"] == "em:furn:483" and cfg.furniture["129"] == nil and cfg.furniture["487"] == nil)
  assert(cfg.signs["em:furn:483"][1][1] == "text" and cfg.signs["em:furn:483"][1][2] == "g3:vt")
  assert(#out == 3 and out[1]:find("emLink.install(mod,CFG)", 1, true))
  -- Hoenn's own tile behaviours, run by the game's Emerald code
  assert(out[2]:find("regionTiles.install(mod,CFG)", 1, true) and cfgs[2].host == "frlg"
    and cfgs[2].steps.FR_HOENN_ROUTE101 == "ash" and cfgs[2].steps.FR_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F == nil)
  -- Town Map and Fly: Emerald's own screen, run by the game
  assert(out[3]:find("regionMap.install(mod,CFG)", 1, true) and cfgs[3].host == "frlg" and cfgs[3].origin == "emerald"
    and cfgs[3].cross == true and cfgs[3].region == "FR_HOENN_" and cfgs[3].secBase == 1000 and type(cfgs[3].visits) == "table")
  assert(cfg.wild.FR_HOENN_ROUTE101 == "0:16" and cfg.wild.FR_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F == "4:5")
  local spot = cfg.respawn.FR_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F
  assert(spot.x == 7 and spot.y == 4 and spot.healer == 1)
  assert(cfg.message == L.MESSAGE)
end)

run("only FireRed / LeafGreen mods can carry it", function()
  local p = { game = "emerald", gen3MapLayouts = { EM_A = { source = "em:EM_ROUTE101" } } }
  local ok, err = pcall(L.emit, p, tostring, {})
  assert(not ok and tostring(err):find("FireRed", 1, true))
  local out = {}
  L.emit({ game = "firered" }, tostring, out)
  assert(#out == 0)
end)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
