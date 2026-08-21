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
    return GameVersion.generation(Generation.id(S))
  end
  local id = Generation.id(S)
  return (id == "gold" or id == "silver") and 2 or 1
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
    local key = tostring(token or ""):lower()
    if key == "all" or key == "gen2" or key == "gold" or key == "silver" then
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
  alias("title", "gen2Title")
  alias("intro", "gen2Intro")
  alias("landmarks", "gen2Landmarks")
  alias("events", "gen2EventTables")
  alias("std_scripts", "gen2StdScripts")
  alias("initial_events", "gen2InitialEvents")
  return data
end

return Generation
