-- Generation helpers for content-editor panels / ModWriter.

local Generation = {}

function Generation.id(S)
  if S and S.version then return S.version end
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.get then return GameVersion.get() end
  return "red"
end

function Generation.num(S)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.generation then
    local gok, n = pcall(GameVersion.generation, Generation.id(S))
    if gok and type(n) == "number" then return n end
  end
  local id = Generation.id(S)
  return (id == "gold" or id == "silver" or id == "crystal") and 2 or 1
end

function Generation.engine(S)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.engine then
    local eok, engine = pcall(GameVersion.engine, Generation.id(S))
    if eok and type(engine) == "string" and engine ~= "" then return engine end
  end
  local id = Generation.id(S)
  if id == "crystal" then return "crystal" end
  if id == "gold" or id == "silver" then return "gs" end
  return "gen1"
end

function Generation.isCrystal(S)
  return Generation.engine(S) == "crystal"
end

function Generation.isGen2ManifestToken(token)
  local key = tostring(token or ""):lower()
  return key == "all" or Generation.isExclusiveGen2Token(key)
end

function Generation.isExclusiveGen2Token(token)
  local key = tostring(token or ""):lower()
  return key == "gen2" or key == "gold" or key == "silver" or key == "crystal"
end

function Generation.dataLooksGen2(data)
  if type(data) ~= "table" then return false end
  if type(data.trainers) == "table" and type(data.trainers.classes) == "table" then
    return true
  end
  if type(data.encounters) == "table" and type(data.encounters.grass) == "table" then
    return true
  end
  if type(data.maps) == "table" and data.maps.NEW_BARK_TOWN then return true end
  if type(data.gen2Maps) == "table" and data.gen2Maps.NEW_BARK_TOWN then
    return true
  end
  return false
end

function Generation.isGen2(S)
  if Generation.num(S) == 2 then return true end
  return Generation.dataLooksGen2(S and S.data)
end

function Generation.mapLooksGen2(def)
  if type(def) ~= "table" then return false end
  if def.generation == 2 then return true end
  local ts = def.tileset
  return type(ts) == "string" and ts:sub(1, 8) == "TILESET_"
end

-- Latest Recomp gates mods per version (`games: ["red"]` will not load on
-- Blue). New editor mods target every game this engine supports.
function Generation.manifestGames(_S)
  return { "all" }
end

function Generation.coversGen2(games)
  if type(games) ~= "table" then return false end
  for _, token in ipairs(games) do
    if Generation.isGen2ManifestToken(token) then
      return true
    end
  end
  return false
end

-- Data:load writes Gold maps/tilesets to the Gen 1 keys; Game2 and the mod
-- merge write gen2Maps / gen2Tilesets. Overlay so both names stay in sync.
local function overlayRecords(base, overlay)
  if not overlay then return base or {} end
  if not base or base == overlay then return overlay end
  local out = {}
  for id, def in pairs(base) do out[id] = def end
  for id, def in pairs(overlay) do
    local prior = out[id]
    if type(def) == "table" and type(prior) == "table" then
      local merged = {}
      for k, v in pairs(prior) do merged[k] = v end
      for k, v in pairs(def) do merged[k] = v end
      out[id] = merged
    else
      out[id] = def
    end
  end
  return out
end

function Generation.maps(data)
  if type(data) ~= "table" then return {} end
  return overlayRecords(data.maps, data.gen2Maps)
end

function Generation.tilesets(data)
  if type(data) ~= "table" then return {} end
  return overlayRecords(data.tilesets, data.gen2Tilesets)
end

function Generation.dataMaps(S)
  return Generation.maps(S and S.data)
end

local function deepClone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[deepClone(key, seen)] = deepClone(child, seen)
  end
  return out
end

function Generation.isEditorMap(rec)
  return type(rec) == "table" and (rec._isNew == true
    or rec._layeredGenerated
    or rec._layeredSource
    or (type(rec.index) == "number" and rec.index >= 1000))
end

function Generation.cloneMapRecord(rec)
  if type(rec) ~= "table" then return rec end
  return deepClone(rec)
end

-- Put ROM copies back for maps this project does not own, so leftover
-- compiles and other loaded mods do not show as "vanilla".
function Generation.restoreUnownedLiveMaps(S)
  if not (S and S.data and type(S._vanillaMapBackup) == "table") then
    return
  end
  local project = (S.project and S.project.maps) or {}
  local layered = (S.project and S.project.layeredMaps) or {}
  S.data.maps = S.data.maps or {}
  for id, bak in pairs(S._vanillaMapBackup) do
    if not project[id] and not layered[id] then
      local copy = deepClone(bak)
      S.data.maps[id] = copy
      if S.data.gen2Maps and S.data.gen2Maps ~= S.data.maps then
        S.data.gen2Maps[id] = copy
      end
    end
  end
  Generation.pruneForeignLiveMaps(S)
end

function Generation.isRomMap(S, id, rec)
  if not id then return false end
  if S and type(S._vanillaMapIds) == "table" then
    return S._vanillaMapIds[id] == true
  end
  rec = rec or Generation.dataMaps(S)[id]
  return type(rec) == "table" and not Generation.isEditorMap(rec)
end

-- Sidebar / pickers: this project's maps plus ROM maps. Leftover compiles
-- and other loaded mods stay out of the list.
function Generation.listedMapIds(S)
  local seen, ids = {}, {}
  local function add(id)
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S and S.project then
    for id in pairs(S.project.maps or {}) do add(id) end
    for id in pairs(S.project.layeredMaps or {}) do add(id) end
  end
  for id, rec in pairs(Generation.dataMaps(S)) do
    if Generation.isRomMap(S, id, rec) then add(id) end
  end
  table.sort(ids)
  return ids
end

function Generation.pruneForeignLiveMaps(S)
  if not (S and S.data) then return end
  local vanilla = S._vanillaMapIds
  local project = (S.project and S.project.maps) or {}
  local layered = (S.project and S.project.layeredMaps) or {}
  local function keep(id, rec)
    if project[id] or layered[id] then return true end
    if type(vanilla) == "table" then return vanilla[id] == true end
    return not Generation.isEditorMap(rec)
  end
  local function strip(bag)
    if type(bag) ~= "table" then return end
    local drop = {}
    for id, rec in pairs(bag) do
      if not keep(id, rec) then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do bag[id] = nil end
  end
  strip(S.data.maps)
  if S.data.gen2Maps and S.data.gen2Maps ~= S.data.maps then
    strip(S.data.gen2Maps)
  end
end

function Generation.dataTilesets(S)
  return Generation.tilesets(S and S.data)
end

function Generation.bindGoldData(data)
  if type(data) ~= "table" then return data end
  if data.maps and data.gen2Maps == nil then data.gen2Maps = data.maps end
  if data.tilesets and data.gen2Tilesets == nil then
    data.gen2Tilesets = data.tilesets
  end
  if data.sprites and data.gen2Sprites == nil then
    data.gen2Sprites = data.sprites
  end
  if data.encounters and data.gen2Encounters == nil then
    data.gen2Encounters = data.encounters
  end
  if data.trainers and data.gen2Trainers == nil then
    data.gen2Trainers = data.trainers
  end
  if data.constants and data.gen2Constants == nil then
    data.gen2Constants = data.constants
  end
  if data.text and data.gen2Text == nil then data.gen2Text = data.text end
  if data.palettes and data.gen2Palettes == nil then
    data.gen2Palettes = data.palettes
  end
  if data.icons and data.gen2Icons == nil then data.gen2Icons = data.icons end
  if data.pokedex and data.gen2Pokedex == nil then
    data.gen2Pokedex = data.pokedex
  end
  if data.gen2Pokedex and data.pokedex == nil then
    data.pokedex = data.gen2Pokedex
  end
  if data.battle_anims and data.gen2BattleAnims == nil then
    data.gen2BattleAnims = data.battle_anims
  end
  -- Game2 writes gen2*; Data:load / panels use the short names. Fill both.
  local function alias(a, b)
    if data[a] and data[b] == nil then data[b] = data[a] end
    if data[b] and data[a] == nil then data[a] = data[b] end
  end
  alias("scripts", "gen2Scripts")
  alias("marts", "gen2Marts")
  alias("roofs", "gen2Roofs")
  alias("menu_gfx", "gen2MenuGfx")
  alias("diploma", "gen2Diploma")
  alias("title", "gen2Title")
  alias("intro", "gen2Intro")
  alias("oakSpeech", "gen2OakSpeech")
  alias("credits", "gen2Credits")
  alias("landmarks", "gen2Landmarks")
  alias("events", "gen2EventTables")
  alias("std_scripts", "gen2StdScripts")
  alias("initial_events", "gen2InitialEvents")
  return data
end

return Generation
