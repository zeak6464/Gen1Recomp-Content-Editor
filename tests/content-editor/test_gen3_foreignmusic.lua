-- Map music from the other Gen 3 game (Gen3ForeignMusic): song numbers, what the
-- imported maps get, what the export carries. Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_gen3_foreignmusic.lua
package.path = "tools/content-editor/?.lua;" .. package.path
-- the editor decodes the import's tables with the engine's serializer; a plain load does here
package.loaded["Gen3Decode"] = { decode = function(bytes) return load(bytes)() end }
local F = require("Gen3ForeignMusic")
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("song numbers: base + the other game's number", function()
  assert(F.encode(362) == F.BASE + 362 and F.nativeId(F.BASE + 362) == 362)
  assert(F.isForeign(F.BASE + 5) and F.isForeign(tostring(F.BASE + 5)))
  assert(not F.isForeign(362) and not F.isForeign(0) and not F.isForeign(nil) and not F.isForeign(F.BASE + F.SPAN) and not F.isForeign(1.5))
end)

-- a stand-in for the other game's import: only songs.lua is read
local function link(songs)
  local rows = {}
  for id, kind in pairs(songs) do rows[#rows + 1] = string.format("[%d] = { kind = %q },", id, kind) end
  local bytes = "return {" .. table.concat(rows) .. "}"
  return { read = function(path) return path == "data/generated/gba/audio/songs.lua" and bytes or nil end }
end

run("fromImport: a map keeps its own song when the import has it as music", function()
  local l = link({ [362] = "bgm", [367] = "fanfare", [12] = "se" })
  assert(F.fromImport(l, 362) == F.BASE + 362)
  assert(F.fromImport(l, 367) == nil and F.fromImport(l, 12) == nil and F.fromImport(l, 999) == nil)
  assert(F.fromImport(l, 0) == nil and F.fromImport(l, nil) == nil and F.fromImport(nil, 362) == nil)
  assert(F.fromImport({ read = function() return nil end }, 362) == nil)
end)

run("mapSongs: maps an import brought in and songs chosen in Audio", function()
  local p = { game = "firered", gen3 = { maps = { FR_HOENN_A = { music = F.BASE + 362 }, FR_B = { music = 300 }, FR_C = {} } },
    gen3Audio = { mapSongs = { FR_D = F.BASE + 1, FR_E = 300 } } }
  local m = F.mapSongs(p)
  assert(m.FR_HOENN_A == F.BASE + 362 and m.FR_D == F.BASE + 1 and m.FR_B == nil and m.FR_C == nil and m.FR_E == nil)
  assert(F.used(p) and not F.used({ game = "firered" }) and not F.used({ gen3Audio = { mapSongs = { X = 300 } } }))
  assert(F.origin(p) == "emerald" and F.origin({ game = "emerald" }) == "firered")
end)

run("emit: only when a map plays the other game's song; the mod carries numbers", function()
  love = { filesystem = { read = function(path) return path:find("Gen3ForeignMusicRuntime", 1, true) and "return {}" or nil end } }
  local out = {}
  F.emit({ game = "emerald" }, function(v) return "CFG" end, out)
  assert(#out == 0)
  local cfgs = {}
  F.emit({ game = "emerald", gen3 = { maps = { EM_KANTO_A = { music = F.BASE + 303 } } } }, function(v) cfgs[#cfgs + 1] = v; return "CFG" end, out)
  assert(#out == 1 and out[1]:find("foreignMusic.install(mod,CFG)", 1, true))
  assert(cfgs[1].base == F.BASE and cfgs[1].origin == "firered")
  assert(not out[1]:find("samples", 1, true))
end)

-- which game's import is "the other one", and the picker lists
local gameNow, haveFr, haveEm = "emerald", true, true
local songsOf = link({ [359] = "bgm", [362] = "bgm", [367] = "fanfare", [12] = "se" })
package.loaded["Generation"] = { id = function() return gameNow end }
package.loaded["Gen3FrLink"] = { editor = function() return haveFr and { game = "firered", read = songsOf.read } or nil end }
package.loaded["Gen3EmLink"] = { editor = function() return haveEm and { game = "emerald", read = songsOf.read } or nil end }

run("other: Emerald reads the FireRed import, FireRed / LeafGreen the Emerald one", function()
  gameNow = "emerald"
  local l, game, name = F.other({})
  assert(l and game == "firered" and name == "FireRed")
  gameNow = "leafgreen"
  l, game, name = F.other({})
  assert(l and game == "emerald" and name == "Emerald")
  haveEm = false
  assert(F.other({}) == nil)
  haveEm = true
end)

run("songs: only music, named with the game, valid only when the import has them", function()
  gameNow = "emerald"
  local S = { data = {} }
  local list = F.songs(S)
  assert(#list == 2 and list[1].id == F.BASE + 359 and list[2].native == 362)
  assert(list[1].name:find("^FireRed: "))
  assert(F.valid(S, F.BASE + 362) and not F.valid(S, F.BASE + 367) and not F.valid(S, 362))
  assert(F.label(S, F.BASE + 362):find("^FireRed: ") and F.label(S, 362) == nil)
  assert(F.label(S, F.BASE + 400) == "Song 400 of the other game")
  haveFr = false; S.data = {}
  assert(#F.songs(S) == 0 and not F.valid(S, F.BASE + 362))
  haveFr = true
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
