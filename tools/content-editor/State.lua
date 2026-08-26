-- Content-editor session state.  The project table is the source of truth;
-- main.lua is regenerated from it on Save.

local State = {}

function State.new()
  return {
    data = nil,          -- loaded Data (ROM cache + other mods)
    version = nil,
    tab = "project",
    status = "Open or create a mod to begin",
    dirty = false,
    path = nil,          -- absolute mod directory
    project = nil,       -- structured editor project
    -- selection ids per tab
    pokemonId = nil,
    pokemonSection = "basics",
    itemId = nil,
    moveId = nil,
    moveEffectId = nil,
    moveEffectListOffset = 0,
    typeId = nil,
    mapId = nil,
    dialogMapId = nil,
    dialogTextId = nil,
    dialogMapOffset = 0,
    dialogPinOffset = 0,
    trainerId = nil,
    eventScriptKey = nil,  -- "MAP/TEXT_*"
    eventsMode = "scripts", -- scripts | saveflags
    -- map editor tool state
    paintBlock = 1,
    mapTool = "paint",   -- paint | erase | pick | select | warp | object | sign | trainer
    mapZoom = 2,
    mapCamX = 0,
    mapCamY = 0,
    mapShowGrid = false,
    mapListOffset = 0,
    pokemonListOffset = 0,
    itemListOffset = 0,
    moveListOffset = 0,
    typeListOffset = 0,
    typeMatchOffset = 0,
    scrollY = 0,
    newModId = "my_content",
    importReport = nil,
    -- save-flag tester
    testSave = nil,
    testSavePath = nil,
    flagFilter = "",
    -- Editor preview: resolve colors from data/palettes_gbc.lua (default ON).
    useGbcPalettes = true,
  }
end

function State.blankProject(id, name)
  return {
    id = id,
    name = name or id,
    profile = "content",
    pokemon = {},   -- id -> record
    items = {},     -- id -> record (+ effectTemplate fields)
    moves = {},     -- id -> record
    moveEffects = {}, -- id -> template draft (emitted as move_effects)
    types = {},     -- id -> { name, category, index? }
    type_matchups = {}, -- "ATK>DEF" -> multiplier (x10)
    -- Gold: foresight-only matchup block (TypeMatchups after $FE)
    type_foresight = {},
    maps = {},      -- id -> record (+ encounters)
    tilesets = {},  -- id -> record (imported or custom)
    layeredMaps = {}, -- id -> native 16x16 layered map source
    mapTileSources = {}, -- id -> imported 16x16 PNG tileset source
    mapStamps = {}, -- saved multi-tile brushes (any tileset)
    mapAssemblies = {}, -- kept Assembly-tab groups
    nextStamp = 1,
    movements = {}, -- Gold applymovement byte streams
    runtimeTileAnims = {}, -- tilesetId -> tile -> frames (Gold sheet animations)
    mapWarpNodes = {}, -- stable directed endpoints compiled to runtime warp indices
    text = {},      -- _LABEL -> string
    text_pointers = {}, -- mapLabel -> TEXT_* -> { text = "_LABEL" }
    marts = {},     -- Gold: MART_* / BARGAIN -> stock lists
    trainers = {},  -- OPP_* -> record
    trainer_headers = {}, -- mapLabel -> { [objIndex] = header }
    map_scripts = {}, -- mapId -> { talk = { TEXT_* = scriptRows } }
    mapHooks = {}, -- mapId -> { onEnter={steps}, onVictory={steps},
                   --   onStepCells={{x,y,steps}}, scripts={ name={steps} } }
    eventFlags = {}, -- shortName -> true (emitted as MOD_<id>_SHORT)
    talkScripts = {}, -- "MAP/TEXT_*" -> { mapId, textId, steps = {...} }
    -- Gold: scriptKey -> { mapId, scriptKey, steps } (compiles to project.scripts)
    scriptSteps = {},
    fishing = {},   -- OLD_ROD / GOOD_ROD overrides (field.fishing)
    hiddenItems = {}, -- mapId -> { { x, y, item }, ... } (field.hiddenItems)
    badgeGates = {},  -- mapId -> gate record (field.badgeGates)
    darkMaps = nil,   -- { maps = { id, ... } } when authored (field.darkMaps)
    trades = nil,     -- { { give, get, dialogset, nickname }, ... } field.trades
    flyOrder = nil,   -- { mapId, ... } field.flyOrder
    flyWarps = {},    -- mapId -> { x, y } field.flyWarps
    ledges = {},      -- added field.ledges hop rules (appended on emit)
    boot = {},        -- field.boot overrides
    constants = {},   -- constants patches (levelCap, badges, …)
    audio = {},       -- songs/cries/sfx/mapSongs
    palettes = {},    -- id -> colors
    -- GBC ADVANCED tileset BG groups: groupColors[tileset] = 8×4×{r,g,b}
    gbcWorld = { groupColors = {} },
    sprites = {},     -- overworld sprite defs
    aiClasses = {},   -- trainer AI class records
    -- Gen1: MOVE / subanim:N / tilesheet:N. Gold: nested moves/scripts/ids/objects/gfx.
    battle_anims = {},
    playerSprites = {}, -- field.playerSprites slot -> sprite id
    playerPics = {},    -- field.playerPics slot -> image path
    title = {},         -- field.title (logo, music, copyright, …)
    intro = {},         -- field.intro (studio splash, skip, …)
    theme = {},         -- field.theme (textBox / choiceBox / cursors)
    font = {},          -- font page overrides
    strings = {},       -- engine Strings() overrides (source -> text)
    townMap = {},       -- field.townMap (Gen1) / landmark overrides (Gold)
    trainerCard = {},   -- Gold: gen2MenuGfx.trainerCard badge/leader sheets
    menuGfx = {},       -- Gen1 field chrome / Gold gen2MenuGfx sheet overrides
    diploma = {},       -- Gold: gen2Diploma sheet
    pokedex = {},       -- Gold: gen2Pokedex.entries overrides (kind/text/…)
    -- Lab ball remap (Oak / Elm): vanillaSpecies -> { species, level }
    starterRemap = {},
    -- Special gifts/battles with DVs + moves (Encounters tab)
    specialEncounters = {},
    deleted = { pokemon = {}, items = {}, trainers = {} },
    nextMapIndex = 1000,
    nextWarpNode = 1,
  }
end

function State.ensureProjectFields(project)
  if not project then return project end
  project.pokemon = project.pokemon or {}
  project.items = project.items or {}
  project.moves = project.moves or {}
  project.moveEffects = project.moveEffects or {}
  project.types = project.types or {}
  project.type_matchups = project.type_matchups or {}
  project.type_foresight = project.type_foresight or {}
  project.maps = project.maps or {}
  project.tilesets = project.tilesets or {}
  project.layeredMaps = project.layeredMaps or {}
  project.mapTileSources = project.mapTileSources or {}
  project.mapStamps = project.mapStamps or {}
  project.mapAssemblies = project.mapAssemblies or {}
  project.nextStamp = project.nextStamp or 1
  project.movements = project.movements or {}
  project.runtimeTileAnims = project.runtimeTileAnims or {}
  project.mapWarpNodes = project.mapWarpNodes or {}
  project.text = project.text or {}
  project.text_pointers = project.text_pointers or {}
  project.marts = project.marts or {}
  project.trainers = project.trainers or {}
  project.trainer_headers = project.trainer_headers or {}
  project.map_scripts = project.map_scripts or {}
  project.mapHooks = project.mapHooks or {}
  project.eventFlags = project.eventFlags or {}
  project.talkScripts = project.talkScripts or {}
  project.scriptSteps = project.scriptSteps or {} -- Gold step bags (scriptKey → steps)
  project.fishing = project.fishing or {}
  project.boot = project.boot or {}
  project.constants = project.constants or {}
  project.breeding = project.breeding or {} -- Gold Day-Care knobs
  project.audio = project.audio or {}
  project.phoneContacts = project.phoneContacts or {}
  project.scripts = project.scripts or {} -- Gold mod talk scripts (scriptKey → ops)
  project.palettes = project.palettes or {}
  project.gbcWorld = project.gbcWorld or { groupColors = {} }
  project.gbcWorld.groupColors = project.gbcWorld.groupColors or {}
  project.sprites = project.sprites or {}
  project.aiClasses = project.aiClasses or {}
  project.statuses = project.statuses or {}
  project.rulesets = project.rulesets or {}
  project.transitions = project.transitions or {}
  project.battle_sprite_scales = project.battle_sprite_scales or {}
  project.apricorns = project.apricorns or {}
  project.radio_channels = project.radio_channels or {}
  project.battle_anims = project.battle_anims or {}
  project.playerSprites = project.playerSprites or {}
  project.playerPics = project.playerPics or {}
  project.title = project.title or {}
  project.intro = project.intro or {}
  project.oakSpeech = project.oakSpeech or {}
  project.credits = project.credits or {}
  project.theme = project.theme or {}
  project.font = project.font or {}
  project.strings = project.strings or {}
  project.townMap = project.townMap or {}
  project.trainerCard = project.trainerCard or {}
  project.menuGfx = project.menuGfx or {}
  project.minigames = project.minigames or {}
  project.diploma = project.diploma or {}
  project.pokedex = project.pokedex or {}
  project.hiddenItems = project.hiddenItems or {}
  project.badgeGates = project.badgeGates or {}
  project.fishGroups = project.fishGroups or {}
  project.treeSets = project.treeSets or {}
  project.trees = project.trees or {}
  project.rocks = project.rocks or {}
  project.flyPoints = project.flyPoints or {}
  project.flyWarps = project.flyWarps or {}
  project.ledges = project.ledges or {}
  project.starterRemap = project.starterRemap or {}
  project.specialEncounters = project.specialEncounters or {}
  project.deleted = project.deleted or {}
  project.deleted.pokemon = project.deleted.pokemon or {}
  project.deleted.items = project.deleted.items or {}
  project.deleted.trainers = project.deleted.trainers or {}
  project.nextMapIndex = project.nextMapIndex or 1000
  project.nextWarpNode = project.nextWarpNode or 1
  return project
end

function State.isDeleted(project, kind, id)
  return project and project.deleted and project.deleted[kind]
    and project.deleted[kind][id] and true or false
end

-- Gold items.lua ships metadata beside class rows (pockets / source /
-- generation). Those are not items — listing them crashes the Items tab.
local ITEM_TABLE_META = {
  pockets = true, source = true, generation = true,
}

function State.isItemRecord(id, rec)
  if type(id) ~= "string" or id == "" or ITEM_TABLE_META[id] then
    return false
  end
  if type(rec) ~= "table" then return false end
  return rec.name ~= nil or rec.price ~= nil or rec.index ~= nil
    or rec.pocket ~= nil or rec.pocketId ~= nil
    or rec.effectTemplate ~= nil or rec._isNew == true
    or rec.teaches ~= nil or rec.machine ~= nil
    or rec.heldEffect ~= nil
end

-- Gold moves.lua prefixes the registry with meta keys (source, generation).
local MOVE_TABLE_META = {
  source = true, generation = true,
}

function State.isMoveRecord(id, rec)
  if type(id) ~= "string" or id == "" or MOVE_TABLE_META[id] then
    return false
  end
  if type(rec) ~= "table" then return false end
  return rec.effect ~= nil or rec.power ~= nil or rec.type ~= nil
    or rec.pp ~= nil or rec.accuracy ~= nil or rec._isNew == true
end

-- Gold pokemon.lua also ships growthRates / tmhmMoves helper tables.
local POKEMON_TABLE_META = {
  growthRates = true, tmhmMoves = true, source = true, generation = true,
}

function State.isPokemonRecord(id, rec)
  if type(id) ~= "string" or id == "" or POKEMON_TABLE_META[id] then
    return false
  end
  if type(rec) ~= "table" then return false end
  return rec.baseStats ~= nil or rec.dex ~= nil or rec.types ~= nil
    or rec.spriteFront ~= nil or rec.levelMoves ~= nil or rec.learnset ~= nil
    or rec._isNew == true
end

-- Drop a project override and, when the id exists in base game data (or was
-- a non-_isNew patch), record a tombstone so Save emits content:remove.
-- kind = "pokemon" | "items" | "trainers"
function State.markDeleted(project, kind, id, rec, baseTable)
  if not project or not id or id == "" then return false end
  State.ensureProjectFields(project)
  local bag = project[kind]
  if bag then bag[id] = nil end
  local isNew = rec and rec._isNew == true
  local inBase = baseTable and baseTable[id] ~= nil
  if isNew and not inBase then
    project.deleted[kind][id] = nil
  else
    project.deleted[kind][id] = true
  end
  return true
end

function State.mapLabel(S, mapId)
  if not mapId then return nil end
  local proj = S.project and S.project.maps and S.project.maps[mapId]
  if proj and proj.label and proj.label ~= "" then return proj.label end
  local base = require("Generation").dataMaps(S)[mapId]
  if base and base.label then return base.label end
  -- fallback: CamelCase from id
  return (mapId:lower():gsub("_(%w)", function(c) return c:upper() end)
    :gsub("^%w", string.upper))
end

function State.modFlag(project, shortName)
  shortName = tostring(shortName or "FLAG"):upper():gsub("%W+", "_")
  -- Pass through vanilla EVENT_* and already-qualified MOD_* names.
  if shortName:match("^EVENT_") or shortName:match("^MOD_") then
    return shortName
  end
  local prefix = "MOD_" .. (project.id or "MOD"):upper():gsub("%W+", "_") .. "_"
  return prefix .. shortName
end

-- Rebuild eventFlags from authored steps / trainer headers so typing a flag
-- name never leaves partials (M, MA, MAP, MAP1) in the project or Save output.
function State.rebuildEventFlags(project)
  if not project then return end
  local flags = {}
  local function add(n)
    if type(n) == "string" and n ~= "" then flags[n] = true end
  end
  local function scrapeSteps(steps)
    for _, step in ipairs(steps or {}) do
      if step.flag then add(State.modFlag(project, step.flag)) end
      if step.choseFlag then add(State.modFlag(project, step.choseFlag)) end
      -- Engine cmd set_flag / clear_flag / check_flag (same MOD_ qualify on Save).
      if (step.kind == "raw" or not step.kind)
          and type(step.note) == "string" and step.note:match("%S") then
        local ok, ModWriter = pcall(require, "ModWriter")
        if ok and ModWriter.parseEngineLine then
          local row = ModWriter.parseEngineLine(step.note)
          local verb = row and row[1]
          if (verb == "set_flag" or verb == "clear_flag" or verb == "check_flag")
              and type(row[2]) == "string" then
            add(State.modFlag(project, row[2]))
          end
        end
      end
    end
  end
  for _, script in pairs(project.talkScripts or {}) do
    scrapeSteps(script.steps)
  end
  for _, hooks in pairs(project.mapHooks or {}) do
    if type(hooks) == "table" then
      if hooks.onEnter then scrapeSteps(hooks.onEnter.steps) end
      if hooks.onVictory then scrapeSteps(hooks.onVictory.steps) end
      for _, cell in ipairs(hooks.onStepCells or {}) do
        scrapeSteps(cell.steps)
      end
      for _, scr in pairs(hooks.scripts or {}) do
        scrapeSteps(scr.steps)
      end
    end
  end
  for _, bucket in pairs(project.trainer_headers or {}) do
    if type(bucket) == "table" then
      for _, h in pairs(bucket) do
        if type(h) == "table" and h.event then add(h.event) end
      end
    end
  end
  project.eventFlags = flags
end

return State
