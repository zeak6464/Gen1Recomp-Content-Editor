-- Hoenn Region (Gen3HoennRegion / Gen3HoennRegionRuntime): Emerald's own maps
-- brought into an Emerald mod as EM_HOENN_ maps. Plain LuaJIT, no LOVE. Run
-- from the repository root:
--   luajit tests/content-editor/test_gen3_hoennregion.lua
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
local H = require("Gen3HoennRegion")
local R = require("Gen3HoennRegionRuntime")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local function msg(text) return { { op = "loadword", 0, text }, { op = "callstd", 2 }, { op = "end" } } end
local function data()
  return { gen3Scripts = {
    ["g3:nurse"] = { { op = "setvar", 0x800B, 1 }, { op = "call", target = "g3:heal" }, { op = "end" } },
    ["g3:talk"] = msg("g3:t1"),
    ["g3:clerk"] = { { op = "lock" }, { op = "faceplayer" }, { op = "message", ptr = "g3:hi" }, { op = "waitmessage" },
      { op = "pokemart", items = "g3:list" }, { op = "release" }, { op = "end" } },
    ["g3:gift"] = { { op = "setflag", 5 }, { op = "end" } },
  }, maps = {
    EM_OLDALE_TOWN_POKEMON_CENTER_1F = { width = 8, height = 8, pair = "building__pokemon_center", warps = {}, connections = {}, bgEvents = {},
      objects = { { localId = 1, scriptKey = "g3:nurse", flag = 0, trainerType = 0 }, { localId = 2, scriptKey = "g3:talk", flag = 0, trainerType = 0 },
        { localId = 3, scriptKey = "g3:gift", flag = 0, trainerType = 0 }, { localId = 4, scriptKey = "g3:talk", flag = 9, trainerType = 0 } } },
    EM_OLDALE_TOWN = { width = 20, height = 20, pair = "general__oldale", music = 400, mapType = 1, warps = { { x = 1, y = 2, destMap = "EM_OLDALE_TOWN_POKEMON_CENTER_1F", destWarp = 0 } },
      connections = { south = { map = "EM_ROUTE102", offset = 0 } },
      bgEvents = { { type = "sign", x = 3, y = 4, scriptKey = "g3:talk", scriptPtr = 1 }, { type = "hidden_item", x = 1, y = 1 } }, objects = {} },
    EM_ROUTE102 = { width = 30, height = 20, pair = "general__route", warps = {}, connections = { north = { map = "EM_OLDALE_TOWN", offset = 0 } }, bgEvents = {}, objects = {} },
    EM_KANTO_ROUTE_1 = { width = 1, height = 1 }, FR_PALLET_TOWN = { width = 1, height = 1 },
  } }
end

run("ids and who it is for", function()
  assert(H.regionId("EM_ROUTE101") == "EM_HOENN_ROUTE101" and H.isRegionId("EM_HOENN_ROUTE101") and not H.isRegionId("EM_ROUTE101"))
  assert(R.original("EM_HOENN_ROUTE101") == "EM_ROUTE101" and R.original("EM_ROUTE101") == nil)
  assert(H.imported({ game = "emerald", gen3HoennRegion = true }) and not H.imported({ game = "firered", gen3HoennRegion = true }))
  local S = { data = { maps = {} }, project = { game = "firered" } }
  local added, why = H.importRegion(S)
  assert(added == nil and why:find("Emerald", 1, true))
end)

run("people: talkers, mart clerks and nurses stay; story people don't", function()
  local S = { data = data(), project = { game = "emerald" } }
  assert(H.personKind(S, "g3:talk") == "talk" and H.personKind(S, "g3:nurse") == "nurse" and H.personKind(S, "g3:clerk") == "mart")
  assert(H.personKind(S, "g3:gift") == nil)
end)

run("maps: Emerald's own only (not Kanto's, not already imported)", function()
  local S = { data = data(), project = { game = "emerald", maps = {} } }
  local ids = H.maps(S)
  assert(#ids == 3 and ids[1] == "EM_OLDALE_TOWN" and ids[3] == "EM_ROUTE102", table.concat(ids, ","))
end)

run("Import region: maps, warps, connections, signs, people, wild", function()
  local d = data()
  d._gen3EditorContent = { encounters = { EM_ROUTE102 = { mapGroup = 0, mapNum = 17, variants = {}, grass = { rate = 20 } } } }
  local S = { data = d, project = { game = "emerald", maps = {} } }
  local added, skipped, signs, people = H.importRegion(S)
  assert(added == 3 and skipped == 0 and signs == 1 and people == 2, tostring(added) .. " " .. tostring(skipped) .. " " .. tostring(signs) .. " " .. tostring(people))
  local p = S.project
  local town = p.gen3.maps.EM_HOENN_OLDALE_TOWN
  assert(p.gen3MapLayouts.EM_HOENN_OLDALE_TOWN.source == "EM_OLDALE_TOWN" and p.gen3Modes.maps.EM_HOENN_OLDALE_TOWN == "register")
  assert(town.warps[1].destMap == "EM_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F" and town.connections.south.map == "EM_HOENN_ROUTE102")
  assert(#town.bgEvents == 1 and town.bgEvents[1].scriptPtr == nil and town.music == 400)
  assert(#p.gen3.maps.EM_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F.objects == 2)
  local wild = d._gen3EditorContent.encounters.EM_HOENN_ROUTE102
  assert(wild and wild.mapGroup == nil and wild._editorHoennWild)
  assert(H.importRegion(S) == 0)
  assert(H.setPeople(S, false) and #p.gen3.maps.EM_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F.objects == 0)
  assert(H.setPeople(S, true) and #p.gen3.maps.EM_HOENN_OLDALE_TOWN_POKEMON_CENTER_1F.objects == 2)
end)

run("export: only when imported, names only", function()
  local out = {}
  _G.love = { filesystem = { read = function() return "return {}" end } }
  H.emit({ game = "emerald" }, tostring, out)
  assert(#out == 0)
  local cfgs = {}
  H.emit({ game = "emerald", gen3HoennRegion = true }, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  _G.love = nil
  assert(#out == 3 and out[1]:find("hoennRegion.install(mod,CFG)", 1, true) and cfgs[1].wild == true and cfgs[1].respawn == true)
  -- the maps' own step callbacks come from Emerald's onResume scripts in the game
  assert(out[2]:find("regionTiles.install(mod,CFG)", 1, true) and cfgs[2].host == "rse" and cfgs[2].region == "EM_HOENN_" and cfgs[2].derive == true)
  -- Town Map and Fly work on the copies
  assert(out[3]:find("regionMap.install(mod,CFG)", 1, true) and cfgs[3].host == "rse" and cfgs[3].origin == "emerald"
    and cfgs[3].cross == false and cfgs[3].region == "EM_HOENN_" and cfgs[3].prefix == "EM_" and cfgs[3].derive == true)
end)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
