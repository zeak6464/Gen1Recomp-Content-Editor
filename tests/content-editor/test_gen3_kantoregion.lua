-- Kanto Region (Gen3KantoRegion / Gen3KantoRegionRuntime): FireRed's own maps
-- brought into a FireRed / LeafGreen mod as FR_KANTO_ maps. Plain LuaJIT, no
-- LOVE. Run from the repository root:
--   luajit tests/content-editor/test_gen3_kantoregion.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local function deep(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep(x) end
  return out
end
package.loaded["src.mods.Merge"] = { deepCopy = deep }
package.loaded["Generation"] = { isRomMap = function(S, id) return not (S.project.maps or {})[id] end }
package.loaded["Gen3Workspace"] = { prepare = function() end }
local K = require("Gen3KantoRegion")
local R = require("Gen3KantoRegionRuntime")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local function msg(text) return { { op = "loadword", 0, text }, { op = "callstd", 2 }, { op = "end" } } end
local function data()
  return { gen3Scripts = {
    ["g3:nurse"] = { { op = "lock" }, { op = "faceplayer" }, { op = "call", target = "g3:heal" }, { op = "release" }, { op = "end" } },
    ["g3:talk"] = msg("g3:t1"),
    ["g3:clerk"] = { { op = "special", id = 391 }, { op = "compare_var_to_value", 0x800D, 2 }, { op = "goto_if", target = "g3:ql" },
      { op = "lock" }, { op = "faceplayer" }, { op = "message", ptr = "g3:hi" }, { op = "waitmessage" },
      { op = "pokemart", items = "g3:list" }, { op = "loadword", 0, "g3:bye" }, { op = "callstd", 4 }, { op = "release" }, { op = "end" } },
    ["g3:gift"] = { { op = "setflag", 5 }, { op = "end" } },
    ["g3:tv"] = { { op = "special", id = 12 }, { op = "end" } },
    ["g3:story"] = { { op = "setvar", 0x4050, 1 }, { op = "end" } },
  }, maps = {
    FR_VIRIDIAN_CITY_POKEMON_CENTER_1F = { objects = { { localId = 1, sprite = "SPRITE_NURSE", graphicsId = 64, scriptKey = "g3:nurse" } } },
  } }
end

run("ids: FR_ maps and the Sevii Islands", function()
  assert(K.regionId("FR_PALLET_TOWN") == "FR_KANTO_PALLET_TOWN")
  assert(K.regionId("SEVII_ONE_ISLAND") == "FR_KANTO_SEVII_ONE_ISLAND")
  assert(K.isRegionId("FR_KANTO_ROUTE_1") and not K.isRegionId("FR_ROUTE_1"))
  assert(R.original("FR_KANTO_ROUTE_1", function(k) return k == "FR_ROUTE_1" end) == "FR_ROUTE_1")
  assert(R.original("FR_KANTO_SEVII_ONE_ISLAND", function(k) return k == "SEVII_ONE_ISLAND" end) == "SEVII_ONE_ISLAND")
  assert(R.original("FR_ROUTE_1") == nil)
  assert(R.regionId("FR_ROUTE_1") == "FR_KANTO_ROUTE_1" and R.regionId("SEVII_X") == "FR_KANTO_SEVII_X")
end)

run("people: talkers, mart clerks and nurses stay; machines and story people don't", function()
  local S = { data = data(), project = { game = "firered" } }
  assert(K.personKind(S, "g3:talk") == "talk")
  assert(K.personKind(S, "g3:nurse") == "nurse")
  assert(K.personKind(S, "g3:clerk") == "mart")
  assert(K.personKind(S, "g3:gift") == nil)
  assert(K.personKind(S, "g3:tv") == nil)
  assert(K.personKind(S, "g3:story") == nil)
end)

run("maps: the game's own only (not FR_HOENN_, not already imported)", function()
  local S = { data = { maps = { FR_ROUTE_1 = { width = 1 }, SEVII_ONE_ISLAND = { width = 1 }, FR_HOENN_ROUTE101 = { width = 1 },
    FR_KANTO_ROUTE_2 = { width = 1 }, EM_ROUTE101 = { width = 1 } } }, project = { game = "firered", maps = {} } }
  local ids = K.maps(S)
  assert(#ids == 2 and ids[1] == "FR_ROUTE_1" and ids[2] == "SEVII_ONE_ISLAND", table.concat(ids, ","))
end)

run("only FireRed / LeafGreen projects", function()
  assert(K.imported({ game = "firered", gen3KantoRegion = true }) and K.imported({ game = "leafgreen", gen3KantoRegion = true }))
  assert(not K.imported({ game = "emerald", gen3KantoRegion = true}))
  local S = { data = { maps = {} }, project = { game = "emerald" } }
  local added, why = K.importRegion(S)
  assert(added == nil and why:find("FireRed", 1, true))
end)

run("Import region: maps, warps, connections, signs, people, wild", function()
  local d = data()
  d.maps.FR_PALLET_TOWN = { width = 24, height = 20, pair = "frlg__pallet", music = 300,
    warps = { { x = 1, y = 2, destMap = "FR_PLAYERS_HOUSE_1F", destWarp = 0 } },
    connections = { north = { map = "FR_ROUTE_1", offset = 0 } },
    bgEvents = { { type = "sign", x = 3, y = 4, scriptKey = "g3:talk", scriptPtr = 1 }, { type = "hidden_item", x = 1, y = 1 } },
    objects = {} }
  d.maps.FR_ROUTE_1 = { width = 24, height = 40, pair = "frlg__route", warps = {}, connections = { south = { map = "FR_PALLET_TOWN", offset = 0 } },
    bgEvents = {}, objects = {} }
  d.maps.FR_PLAYERS_HOUSE_1F = { width = 4, height = 4, pair = "frlg__house", warps = {}, connections = {}, bgEvents = {}, objects = {} }
  d.maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F.width = 8
  d.maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F.height = 8
  d.maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F.objects = {
    { localId = 1, sprite = "SPRITE_NURSE", graphicsId = 64, scriptKey = "g3:nurse", flag = 0, trainerType = 0 },
    { localId = 2, scriptKey = "g3:story", flag = 0, trainerType = 0 }, { localId = 3, scriptKey = "g3:talk", flag = 7, trainerType = 0 } }
  d.maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F.warps, d.maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F.connections = {}, {}
  d.maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F.bgEvents = {}
  d._gen3EditorContent = { encounters = { FR_ROUTE_1 = { mapGroup = 3, mapNum = 19, variants = {}, grass = { rate = 20 } } } }
  local S = { data = d, project = { game = "firered", maps = {} } }
  local added, skipped, signs, people = K.importRegion(S)
  assert(added == 4 and skipped == 0 and signs == 1 and people == 1, tostring(added) .. " " .. tostring(skipped) .. " " .. tostring(signs) .. " " .. tostring(people))
  local p = S.project
  local town = p.gen3.maps.FR_KANTO_PALLET_TOWN
  assert(p.gen3MapLayouts.FR_KANTO_PALLET_TOWN.source == "FR_PALLET_TOWN" and p.gen3Modes.maps.FR_KANTO_PALLET_TOWN == "register")
  assert(town.warps[1].destMap == "FR_KANTO_PLAYERS_HOUSE_1F" and town.connections.north.map == "FR_KANTO_ROUTE_1")
  assert(#town.bgEvents == 1 and town.bgEvents[1].scriptPtr == nil and town.music == 300)
  local center = p.gen3.maps.FR_KANTO_VIRIDIAN_CITY_POKEMON_CENTER_1F
  assert(#center.objects == 1 and center.objects[1].scriptKey == "g3:nurse")
  local wild = d._gen3EditorContent.encounters.FR_KANTO_ROUTE_1
  assert(wild and wild.mapGroup == nil and wild._editorKantoWild and wild.id == "FR_KANTO_ROUTE_1")
  assert(p.gen3KantoRegion == true)
  -- again: nothing new is added
  local again = K.importRegion(S)
  assert(again == 0)
  -- People off takes the game's people back out; on brings them back
  assert(K.setPeople(S, false) and #center.objects == 0 and K.setPeople(S, true) and #p.gen3.maps.FR_KANTO_VIRIDIAN_CITY_POKEMON_CENTER_1F.objects == 1)
  assert(K.setWild(S, false) and d._gen3EditorContent.encounters.FR_KANTO_ROUTE_1 == nil)
  assert(K.setWild(S, true) and d._gen3EditorContent.encounters.FR_KANTO_ROUTE_1)
end)

run("export: only when imported, names only", function()
  local out = {}
  _G.love = { filesystem = { read = function() return "return {}" end } }
  K.emit({ game = "firered" }, tostring, out)
  assert(#out == 0)
  local cfgs = {}
  K.emit({ game = "firered", gen3KantoRegion = true }, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  local before = #out
  K.emit({ game = "firered", gen3KantoRegion = true, gen3KantoWild = false, gen3KantoPeople = false }, tostring, out)
  _G.love = nil
  assert(before == 3 and out[1]:find("kantoRegion.install(mod,CFG)", 1, true) and cfgs[1].wild == true and cfgs[1].respawn == true)
  -- the maps' own step callback (Icefall Cave ice) comes from FireRed's onResume scripts in the game
  assert(out[2]:find("regionTiles.install(mod,CFG)", 1, true) and cfgs[2].host == "frlg" and cfgs[2].origin == "firered"
    and cfgs[2].region == "FR_KANTO_" and cfgs[2].derive == true)
  assert(out[3]:find("regionMap.install(mod,CFG)", 1, true) and cfgs[3].host == "frlg" and cfgs[3].origin == "firered"
    and cfgs[3].cross == false and cfgs[3].region == "FR_KANTO_" and cfgs[3].prefix == "FR_" and cfgs[3].derive == true)
  -- with wild and people off only the tile behaviours and the maps are left
  assert(#out == 5 and out[4]:find("regionTiles.install", 1, true) and out[5]:find("regionMap.install", 1, true)
    and not out[4]:find("kantoRegion", 1, true) and not out[5]:find("kantoRegion", 1, true))
end)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
