-- Map music from the other Gen 3 game: FireRed / LeafGreen songs in an Emerald
-- project, Emerald songs in a FireRed / LeafGreen one. A song of the other game
-- is written as BASE + its song number (a plain number, so it goes wherever a
-- song number goes: map music, Map songs in the Audio tab, the maps an import
-- brings in). The mod carries only that number; at run time the game plays the
-- song from the player's own import of the other game (Gen3ForeignMusicRuntime).
local M = {}

M.BASE = 0x4000
M.SPAN = 0x1000
M.GAME = { emerald = "emerald", firered = "firered", leafgreen = "firered" }

function M.isForeign(id)
  local n = tonumber(id)
  return n ~= nil and n % 1 == 0 and n >= M.BASE and n < M.BASE + M.SPAN
end

function M.nativeId(id) return tonumber(id) - M.BASE end
function M.encode(n) return M.BASE + tonumber(n) end

local function hostGame(S)
  local g = require("Generation").id(S)
  return g == "emerald" and "emerald" or "firered"
end

--- The other game's import, or nil: link, its game ("emerald" / "firered" /
-- "leafgreen"), a name to show.
function M.other(S)
  local ok, link, name
  if hostGame(S) == "emerald" then
    local fr = require("Gen3FrLink")
    link = fr.editor()
    name = link and (link.game == "leafgreen" and "LeafGreen" or "FireRed")
  else
    local em = require("Gen3EmLink")
    link = em.editor()
    name = link and "Emerald"
  end
  if not link then return nil end
  return link, link.game, name
end

local function pretty(name)
  local s = tostring(name):gsub("^MUS_", ""):gsub("_", " "):lower()
  return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

-- name by song number for a game, from the engine's own song constants
local function names(game)
  local out = {}
  local ok, Song = pcall(require, "src.core.game3.song_ids")
  if not ok then return out end
  local okT, t = pcall(Song.forVersion, game)
  if not okT or type(t) ~= "table" then return out end
  for k, v in pairs(t) do
    if type(v) == "number" and tostring(k):find("^MUS_") then out[v] = pretty(k) end
  end
  return out
end

local function bgmList(read, game)
  local bytes = read("data/generated/gba/audio/songs.lua")
  if not bytes then return nil end
  local songs = require("Gen3Decode").decode(bytes, { allowArray = true, allowComments = true,
    maxBytes = 16 * 1024 * 1024, maxNodes = 2000000, maxTableEntries = 1000000, maxDepth = 64, maxStringBytes = 4194304 })
  if type(songs) ~= "table" then return nil end
  local label = names(game)
  local out = {}
  for id, info in pairs(songs) do
    id = tonumber(id)
    if id and id > 0 and type(info) == "table" and info.kind == "bgm" then
      out[#out + 1] = { native = id, name = label[id] or ("Song " .. id) }
    end
  end
  table.sort(out, function(a, b) return a.name == b.name and a.native < b.native or a.name < b.name end)
  return out
end

--- The other game's songs for the picker: { { id, native, name (with the game) } }, or {}.
function M.songs(S)
  local link, game, name = M.other(S)
  if not link then return {} end
  S.data = S.data or {}
  local key = tostring(game)
  if S.data._g3ForeignSongs and S.data._g3ForeignSongs.key == key then return S.data._g3ForeignSongs.list end
  local list = {}
  for _, s in ipairs(bgmList(link.read, game) or {}) do
    list[#list + 1] = { id = M.encode(s.native), native = s.native, name = name .. ": " .. s.name }
  end
  S.data._g3ForeignSongs = { key = key, list = list }
  return list
end

--- Is `id` a song of the other game that this project's import has?
function M.valid(S, id)
  if not M.isForeign(id) then return false end
  for _, s in ipairs(M.songs(S)) do
    if s.id == tonumber(id) then return true end
  end
  return false
end

--- A name for a song number of either game ("FireRed: Pallet Town"), or nil.
function M.label(S, id)
  if not M.isForeign(id) then return nil end
  for _, s in ipairs(M.songs(S)) do
    if s.id == tonumber(id) then return s.name end
  end
  return "Song " .. M.nativeId(id) .. " of the other game"
end

--- The host game's own music, named: { { id, name } }.
function M.hostSongs(S)
  local R = require("Gen3Resources")
  local pack = R.audio(S.data)
  local label = names(hostGame(S))
  local out = {}
  for id, info in pairs(pack.songs or {}) do
    id = tonumber(id)
    if id and id > 0 and type(info) == "table" and info.kind == "bgm" then
      out[#out + 1] = { id = id, name = label[id] or ("Song " .. id) }
    end
  end
  table.sort(out, function(a, b) return a.name == b.name and a.id < b.id or a.name < b.name end)
  return out
end

local importKinds = setmetatable({}, { __mode = "k" })

--- The song number to give a map an import brings in so it keeps its own music:
-- `link` is the other game's import, `music` the map header's song number.
-- nil when the import has no such song (the caller then picks a stand-in).
function M.fromImport(link, music)
  local n = tonumber(music)
  if not (link and n and n > 0 and n < M.SPAN) then return nil end
  local kinds = importKinds[link]
  if kinds == nil then
    kinds = false
    local bytes = link.read("data/generated/gba/audio/songs.lua")
    local songs = bytes and require("Gen3Decode").decode(bytes, { allowArray = true, allowComments = true,
      maxBytes = 16 * 1024 * 1024, maxNodes = 2000000, maxTableEntries = 1000000, maxDepth = 64, maxStringBytes = 4194304 })
    if type(songs) == "table" then
      kinds = {}
      for id, info in pairs(songs) do
        if type(info) == "table" and info.kind == "bgm" then kinds[tonumber(id)] = true end
      end
    end
    importKinds[link] = kinds
  end
  if kinds and kinds[n] then return M.encode(n) end
  return nil
end

--- Songs for the Map songs picker: this game's, then the other game's when its
-- import is there. Returns ids (strings) and labels.
function M.pickList(S)
  local _, game = M.other(S)
  local key = tostring(game or "")
  S.data = S.data or {}
  local c = S.data._g3SongPick
  if c and c.key == key then return c.ids, c.labels end
  local ids, labels = {}, {}
  for _, song in ipairs(M.hostSongs(S)) do ids[#ids + 1] = tostring(song.id); labels[tostring(song.id)] = song.name end
  for _, song in ipairs(M.songs(S)) do ids[#ids + 1] = tostring(song.id); labels[tostring(song.id)] = song.name end
  S.data._g3SongPick = { key = key, ids = ids, labels = labels }
  return ids, labels
end

--- The project's foreign map music: every map with a song of the other game
-- (from the maps it brings in, or chosen in Audio > mapSongs). { map = song }
function M.mapSongs(project)
  local out = {}
  for id, def in pairs((project.gen3 or {}).maps or {}) do
    if type(def) == "table" and M.isForeign(def.music) then out[id] = tonumber(def.music) end
  end
  for id, song in pairs((project.gen3Audio or {}).mapSongs or {}) do
    if M.isForeign(song) then out[id] = tonumber(song) end
  end
  return out
end

function M.used(project)
  return next(M.mapSongs(project or {})) ~= nil
end

--- The mod needs the other game's import to play these (Emerald projects read
-- FireRed / LeafGreen, FireRed / LeafGreen projects read Emerald).
function M.origin(project)
  return (project or {}).game == "emerald" and "firered" or "emerald"
end

function M.emit(project, encode, out)
  if not M.used(project) then return end
  out[#out + 1] = "local foreignMusic=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3ForeignMusicRuntime.lua"),
    "Gen3ForeignMusicRuntime.lua missing") .. "\nend)()\nforeignMusic.install(mod," .. encode({ base = M.BASE, origin = M.origin(project) }) .. ")"
end

return M
