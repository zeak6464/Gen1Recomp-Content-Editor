-- Content editor app shell.  Launch with `love . --content-editor`.
-- Reuses the save-editor Kit/Theme via the shared require path.

local Data = require("src.core.Data")
-- Pin the editor's Loader before DataSource mounts a linked Recomp. That
-- mount prepends the Recomp tree, and a later require would otherwise load
-- the newer Loader against this process's SaveData.
require("src.mods.Loader")
local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local ModIO = require("ModIO")
local History = require("History")
local DataSource = require("DataSource")
local PlaytestPaths = require("PlaytestPaths")
local LuaJitTool = require("LuaJitTool")
local GameVersion = require("src.core.GameVersion")
local PAL = Theme.PAL

local Project = require("Project")
local Manifest = require("Manifest")
local Code = require("Code")
local Pokemon = require("Pokemon")
local Items = require("Items")
local Moves = require("Moves")
local MoveEffects = require("MoveEffects")
local Types = require("Types")
local LayeredMap = require("LayeredMap")
local Maps = require("Maps")
local MapsWorkspace = require("MapsWorkspace")
local Encounters = require("Encounters")
local Dialog = require("Dialog")
local Trainers = require("Trainers")
local Events = require("Events")
local Trades = require("Trades")
local Shops = require("Shops")
local Breeding = require("Breeding")
local Audio = require("Audio")
local Gfx = require("Gfx")
local AiClasses = require("AiClasses")
local BattleAnims = require("BattleAnims")
local BattleAnimPreview = require("BattleAnimPreview")
local Player = require("Player")
local Ui = require("Ui")
local UiPreview = require("UiPreview")
local PalettePicker = require("PalettePicker")
local SpeciesPicker = require("SpeciesPicker")
local ItemPicker = require("ItemPicker")
local ChoicePicker = require("ChoicePicker")
local Autocomplete = require("Autocomplete")
local ColorWheel = require("ColorWheel")
local PaletteEdit = require("PaletteEdit")
local RegList = require("RegList")

local App = {}
local S
local mouseClicked = false
local clickX, clickY
local wheelY = 0

App.dataVersion = nil

function App.session()
  return S
end

local TABS = {
  { id = "project",  label = "PROJECT",
    tip = "Create / open mod, boot & constants, validate / playtest" },
  { id = "manifest", label = "MANIFEST",
    tip = "Edit mods/<id>/manifest.json" },
  { id = "code",     label = "CODE",
    tip = "Browse and edit Lua files under mods/" },
  { id = "maps",     label = "MAPS",
    tip = "Unified 16x16 terrain, events, encounters, and map settings" },
  { id = "encounters", label = "ENCOUNTERS",
    tip = "Wild tables and Special gifts/battles (DVs, moves)" },
  { id = "dialog",   label = "DIALOG",
    tip = "NPC / sign TEXT_* strings and bindings" },
  { id = "shops",    label = "SHOPS",
    tip = "Poké Mart inventories (Gen1 TEXT_* / Gold MART_* shelves)" },
  { id = "trades",   label = "TRADES",
    tip = "In-game trades (Gen1 field.trades / Gold NPC trades)" },
  { id = "trainers", label = "TRAINERS",
    tip = "Trainer classes, parties, and battle headers" },
  { id = "ai",       label = "AI",
    tip = "Gen1 AI classes / Gold scoring layers (BASIC, SMART, …)" },
  { id = "player",   label = "PLAYER",
    tip = "Gen1 Red / Gold Chris: OW sheets, remaps, battle & intro pics" },
  { id = "ui",       label = "UI",
    tip = "Title/splash, theme, fonts, strings, town map, badge icons" },
  { id = "items",    label = "ITEMS",
    tip = "Items and bag effect templates" },
  { id = "pokemon",  label = "POKEMON",
    tip = "Species stats, sprites, icons, learnsets" },
  { id = "breeding", label = "BREEDING",
    tip = "Gold: egg groups / steps / moves and Day-Care knobs" },
  { id = "moves",    label = "MOVES",
    tip = "Move power, accuracy, effects, advanced flags" },
  { id = "anims",    label = "ANIMS",
    tip = "Battle move animations, subanims, tilesheets" },
  { id = "effects",  label = "EFFECTS",
    tip = "Author move_effects from templates" },
  { id = "types",    label = "TYPES",
    tip = "Type chart and matchup multipliers" },
  { id = "audio",    label = "AUDIO",
    tip = "Music, cries, SFX, and map songs" },
  { id = "gfx",      label = "GFX",
    tip = "Palettes, overworld sprites, tilesets" },
  { id = "events",   label = "EVENTS",
    tip = "Talk scripts, flags, and save-flag tester" },
}

local PANELS = {
  project = Project,
  manifest = Manifest,
  code = Code,
  pokemon = Pokemon,
  breeding = Breeding,
  items = Items,
  moves = Moves,
  anims = BattleAnims,
  effects = MoveEffects,
  types = Types,
  maps = MapsWorkspace,
  encounters = Encounters,
  dialog = Dialog,
  shops = Shops,
  trades = Trades,
  trainers = Trainers,
  ai = AiClasses,
  player = Player,
  ui = Ui,
  audio = Audio,
  gfx = Gfx,
  events = Events,
}

local function anyDirty(state)
  return state and (state.dirty or state.manifestDirty or state.codeDirty)
end

local function say(msg)
  if S then S.status = tostring(msg) end
end

function App.getState()
  return S
end

local function snapshotVanillaCatalog()
  -- Capture ROM ids before mods:load merges this project's maps into Data.
  -- Save uses this so custom maps (PALLET_CAVE) register instead of MK103-patch.
  -- Live Data can still hold editor records from a previous compile; drop those.
  local Generation = require("Generation")
  local maps, tilesets = {}, {}
  for id, rec in pairs(Generation.maps(Data) or {}) do
    if type(rec) ~= "table" or rec._isNew == true
        or (type(rec.index) == "number" and rec.index >= 1000) then
      -- editor / mod-authored, not a ROM id
    else
      maps[id] = true
    end
  end
  for id, rec in pairs(Generation.tilesets(Data) or {}) do
    if type(rec) ~= "table" or rec._isNew == true or rec._layeredGenerated then
      -- editor / mod-authored, not a ROM id
    else
      tilesets[id] = true
    end
  end
  if S.project then
    for id, rec in pairs(S.project.maps or {}) do
      if type(rec) == "table" and (rec._isNew == true
          or (type(rec.index) == "number" and rec.index >= 1000)) then
        maps[id] = nil
      end
    end
    for id, rec in pairs(S.project.tilesets or {}) do
      if type(rec) == "table" and (rec._isNew == true or rec._layeredGenerated) then
        tilesets[id] = nil
      end
    end
  end
  S._vanillaMapIds = maps
  S._vanillaTilesetIds = tilesets
end

local function refreshModsAndEvents()
  snapshotVanillaCatalog()
  local ModLoader = require("src.mods.Loader")
  local mods = ModLoader.new()
  mods:load(Data)
  S.data = Data
  S.mods = mods
  local okCat, Catalog = pcall(require, "Catalog")
  if okCat and Catalog.scrapeEvents then
    local modRoots = {}
    for _, mod in ipairs(mods:status().loaded or {}) do
      modRoots[#modRoots + 1] = mod.path
    end
    local okEv, events = pcall(Catalog.scrapeEvents,
      "data/scripts", "data/generated/trainer_headers.lua", nil, modRoots)
    S.events = okEv and events or {}
  else
    S.events = {}
  end
end

function App.reloadData(opts)
  opts = opts or {}
  if not S then return false end
  -- Stop chip preview + drop programs.bin bank cache before remount; Red and
  -- Gold share the same virtual path with different bank sets.
  pcall(function() Audio.stopPreview(S) end)
  pcall(function() require("src.core.ChipAudio").invalidate() end)
  local version = opts.version or S.version or App.dataVersion
  local source, prefs, status = DataSource.apply({ version = version })
  version = (prefs and prefs.lastVersion) or version or "red"
  S.version = version
  App.dataVersion = version
  S.dataSource = source
  S.dataPrefs = prefs
  if prefs and prefs.useGbcPalettes ~= nil then
    S.useGbcPalettes = prefs.useGbcPalettes and true or false
  elseif S.useGbcPalettes == nil then
    S.useGbcPalettes = true
  end
  refreshModsAndEvents()
  do
    local okP, Preview = pcall(require, "Preview")
    if okP and Preview then
      if Preview.installAssetCacheFallback then
        Preview.installAssetCacheFallback()
      end
      if Preview.syncGbcWorldRuntime then
        Preview.syncGbcWorldRuntime(S)
      end
    end
  end
  say(status or DataSource.label(source))
  return true
end

local function firstSortedId(tbl)
  if type(tbl) ~= "table" then return nil end
  local ids = {}
  for id in pairs(tbl) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids[1]
end

local function firstItemId(items)
  if type(items) ~= "table" then return nil end
  local State = require("State")
  local ids = {}
  for id, rec in pairs(items) do
    if State.isItemRecord(id, rec) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids[1]
end

-- Rebind list selections after a game switch so panels don't keep Red ids
-- while S.data is Gold (or the reverse).
function App.resetCatalogSelection()
  if not S or not S.data then return end
  local previousMapId = S.mapId or S.builderMapId
  S._liveTilesets = nil
  S._vanillaMapBackup = nil
  S._mapCenteredFor = nil
  S._g2MapBaker = nil
  S.mapListOffset = 0
  S.pokemonListOffset = 0
  S.itemListOffset = 0
  S.moveListOffset = 0
  S.typeListOffset = 0
  S.scrollY = 0
  do
    local ids = {}
    for id, rec in pairs(S.data.pokemon or {}) do
      if State.isPokemonRecord(id, rec) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    S.pokemonId = ids[1]
  end
  S.itemId = firstItemId(S.data.items)
  do
    local ids = {}
    for id, rec in pairs(S.data.moves or {}) do
      if State.isMoveRecord(id, rec) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    S.moveId = ids[1]
  end
  local liveMaps = require("Generation").dataMaps(S)
  local mapStillExists = previousMapId and (
    (S.project and S.project.maps and S.project.maps[previousMapId])
    or liveMaps[previousMapId])
  S.mapId = mapStillExists and previousMapId or firstSortedId(liveMaps)
  S.builderMapId = S.mapId
  S.dialogMapId = S.mapId
  S.dialogTextId = nil
  local trainers = S.data.trainers
  if type(trainers) == "table" and type(trainers.classes) == "table" then
    S.trainerId = firstSortedId(trainers.classes)
  else
    S.trainerId = firstSortedId(trainers)
  end
  do
    local Generation = require("Generation")
    if Generation.isGen2(S) then
      local Ai = select(2, pcall(require, "src.battle.gen2.Ai"))
      S.aiClassId = (Ai and Ai.LAYER_ORDER and Ai.LAYER_ORDER[1]) or "BASIC"
    else
      S.aiClassId = firstSortedId(S.data.ai_classes)
    end
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.TYPES then
    S.typeId = firstSortedId(TypeChart.TYPES)
  end
end

-- Switch active game (Red/Blue/Yellow/Gold/Silver): remount cache + reload Data.
function App.setGameVersion(version)
  local GameVersion = require("src.core.GameVersion")
  if not (GameVersion.VERSIONS and GameVersion.VERSIONS[version]) then
    say("Unknown game: " .. tostring(version))
    return false
  end
  DataSource.setLastVersion(version)
  GameVersion.set(version)
  S.version = version
  App.dataVersion = version
  pcall(function() require("src.world.MapLoader").invalidateAll() end)
  App.reloadData({ version = version })
  App.resetCatalogSelection()
  local info = GameVersion.info(version)
  local src = S.dataSource or "?"
  say("Game: " .. ((info and info.displayName) or version)
    .. " (Gen " .. tostring(GameVersion.generation(version)) .. ") — "
    .. DataSource.label(src))
  return true
end

function App.generation()
  local GameVersion = require("src.core.GameVersion")
  return GameVersion.generation(S and S.version or App.dataVersion or "red")
end

function App.load(modPath, opts)
  opts = opts or {}
  S = State.new()
  local prefsPeek = DataSource.loadPrefs()
  -- main.lua always passes version="red" unless POKEPORT_VERSION is set.
  -- Keep the last game chip the user actually selected.
  local version = os.getenv("POKEPORT_VERSION")
    or prefsPeek.lastVersion or opts.version or "red"
  S.version = version
  App.dataVersion = version
  local source, prefs, status = DataSource.apply({ version = version })
  S.version = (prefs and prefs.lastVersion) or version
  App.dataVersion = S.version
  S.dataSource = source
  S.dataPrefs = prefs
  S.useGbcPalettes = (prefs and prefs.useGbcPalettes ~= nil)
    and (prefs.useGbcPalettes and true or false)
    or true
  S.status = status
  refreshModsAndEvents()
  do
    local okP, Preview = pcall(require, "Preview")
    if okP and Preview then
      if Preview.installAssetCacheFallback then
        Preview.installAssetCacheFallback()
      end
      if Preview.syncGbcWorldRuntime then
        Preview.syncGbcWorldRuntime(S)
      end
    end
  end

  if modPath and modPath ~= "" then
    App.openMod(modPath)
  elseif not S.status or S.status == "Open or create a mod to begin" then
    say(status or "Create a mod or Open an existing mods/ folder")
  end
end

function App.linkRecompFolder(path)
  if not path or path == "" then return false end
  local prefs, err = DataSource.linkRecomp(path)
  if not prefs then
    say(err or "Link failed")
    return false
  end
  App.reloadData()
  say("Linked Gen1Recomp: " .. path)
  return true
end

function App.useFixturesData()
  DataSource.useFixtures()
  App.reloadData()
  say("Using fixture stub data (no ROM cache)")
  return true
end

function App.useImportedData()
  local version = S and S.version or App.dataVersion or "red"
  if not DataSource.hasImportedCache(version) then
    say("No imported ROM cache for " .. tostring(version))
    return false
  end
  DataSource.setMode("imported")
  App.reloadData()
  say("Using imported ROM cache for " .. tostring(version))
  return true
end

function App.importRomFile(path)
  if not path or path == "" then return false end
  if S and S._romImporter and S._romImporter.workState == "working" then
    say("ROM import already in progress…")
    return false
  end
  local RomImporter = require("src.import.RomImporter")
  local importer = RomImporter.new(function(version)
    DataSource.setMode("imported")
    DataSource.setLastVersion(version)
    if S then S._romImporter = nil end
    App.dataVersion = version
    S.version = version
    require("src.core.GameVersion").set(version)
    require("src.import.CacheFs").mountVersion(version)
    App.reloadData({ version = version })
    say("ROM imported (" .. tostring(version) .. ") — cache in save directory")
  end, { launcher = false })
  S._romImporter = importer
  say("Importing ROM…")
  importer:startPath(path)
  if importer.workState == "working" then
    return true
  end
  if importer.notice and importer.notice.text then
    say(importer.notice.text)
  elseif importer.status then
    say(tostring(importer.status))
  end
  S._romImporter = nil
  return false
end

-- Drop save-directory ROM cache + editor image caches, then reload data.
function App.clearCache()
  if S and S._romImporter and S._romImporter.workState == "working" then
    say("ROM import in progress — wait before clearing cache")
    return false
  end
  local n = DataSource.clearImportedCache() or 0
  pcall(function() require("Preview").invalidate() end)
  pcall(function() require("src.render.Assets").invalidate() end)
  pcall(function() require("src.world.MapLoader").invalidateAll() end)
  pcall(function() require("src.battle.BattleState").invalidate() end)
  pcall(function() require("src.render.SpriteRenderer").invalidate() end)
  if S then
    S._liveTilesets = nil
    S._mapNeedsRebuild = S.mapId
    S._vanillaMapBackup = nil
    S._vanillaTilesetBackup = nil
    S._g2MapBaker = nil
  end
  -- Imported mode is gone after a wipe; fall back to linked Recomp or fixtures.
  local prefs = DataSource.loadPrefs()
  if prefs.mode == "imported" then
    if prefs.recompRoot and DataSource.isValidRecompRoot(prefs.recompRoot) then
      DataSource.setMode("recomp", prefs.recompRoot)
    else
      DataSource.useFixtures()
    end
  end
  App.reloadData()
  say(string.format(
    "Cleared cache (%d entries) — %s",
    n, DataSource.label(S and S.dataSource)))
  return true
end

function App.unload()
  if S and S._romImporter then S._romImporter = nil end
  pcall(function() require("DataSource").unmountLinked() end)
  S = nil
  App.dataVersion = nil
  Kit.blur()
  Kit.blockClicks = false
end

function App.openMod(path)
  if not path or path == "" then return false end
  -- strip trailing slash
  path = path:gsub("[/\\]+$", "")
  local project, note = ModIO.load(path)
  if not project then
    say("Open failed: " .. tostring(note))
    return false
  end
  S.path = path
  S.project = State.ensureProjectFields(project)
  S.dirty = false
  local game = ModIO.authoringGame(S.project, path)
  if game then
    S.project.game = game
    if game ~= (S.version or App.dataVersion) then
      App.setGameVersion(game)
    end
  end
  S._liveTilesets = nil
  S.browseModId = path:match("[/\\]([^/\\]+)$") or S.browseModId
  S._manifestFor = nil
  S._codeFor = nil
  S.manifestDirty = false
  S.codeDirty = false
  S.pokemonId = next(project.pokemon)
  if not S.pokemonId and S.data and S.data.pokemon then
    local ids = {}
    for id, rec in pairs(S.data.pokemon) do
      if State.isPokemonRecord(id, rec) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    S.pokemonId = ids[1]
  end
  S.itemId = next(project.items)
  if not S.itemId and S.data and S.data.items then
    S.itemId = firstItemId(S.data.items)
  end
  S.moveId = next(project.moves)
  if not S.moveId and S.data and S.data.moves then
    local ids = {}
    for id, rec in pairs(S.data.moves) do
      if State.isMoveRecord(id, rec) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    S.moveId = ids[1]
  end
  S.typeId = next(project.types)
  if not S.typeId then
    local ok, TypeChart = pcall(require, "src.battle.TypeChart")
    if ok and TypeChart and TypeChart.TYPES then
      local ids = {}
      for id in pairs(TypeChart.TYPES) do ids[#ids + 1] = id end
      table.sort(ids)
      S.typeId = ids[1]
    end
  end
  local projectMapIds = {}
  for id in pairs(project.maps or {}) do projectMapIds[#projectMapIds + 1] = id end
  table.sort(projectMapIds)
  S.mapId = projectMapIds[1]
  if not S.mapId then
    S.mapId = firstSortedId(require("Generation").dataMaps(S))
  end
  S.builderMapId = S.mapId
  S.dialogMapId = S.mapId
  S._mapCenteredFor = nil
  S.trainerId = next(project.trainers)
  S.eventScriptKey = next(project.talkScripts)
  History.clear(S)
  do
    local okP, Preview = pcall(require, "Preview")
    if okP and Preview then
      if Preview.installAssetCacheFallback then
        Preview.installAssetCacheFallback()
      end
      if Preview.syncGbcWorldRuntime then
        Preview.syncGbcWorldRuntime(S)
      end
    end
  end
  say((note and (note .. " — ") or "") .. "Opened " .. path)
  return true
end

function App.createMod(id)
  id = id or S.newModId
  local path, projectOrErr = ModIO.create(id, nil, S and S.version)
  if not path then
    say("Create failed: " .. tostring(projectOrErr))
    return false
  end
  S.path = path
  S.project = projectOrErr
  S.dirty = false
  S.browseModId = id
  S._manifestFor = nil
  S._codeFor = nil
  S.manifestDirty = false
  S.codeDirty = false
  History.clear(S)
  say("Created " .. path)
  return true
end

function App.save()
  if not S or not S.path or not S.project then
    say("No mod open")
    return false
  end
  -- Layered maps are editor source. Compile them into normal map and tileset
  -- records before ModWriter serializes the portable mod.
  local okLayered, layeredResult, layeredErr = pcall(function()
    return LayeredMap.compileProject(S)
  end)
  if not okLayered then
    say("Save failed: " .. tostring(layeredResult))
    return false
  end
  if layeredResult == false then
    say("Save failed: " .. tostring(layeredErr))
    return false
  end

  -- Custom maps/tilesets must keep _isNew so Save emits :register (MK103).
  -- Live S.data.maps is polluted with project records after compile.
  local function markNewRecords(bag, vanillaIds)
    if type(bag) ~= "table" then return end
    for id, rec in pairs(bag) do
      if type(rec) == "table" then
        if rec._layeredGenerated or rec._isNew == true
            or (type(rec.index) == "number" and rec.index >= 1000) then
          rec._isNew = true
        elseif type(vanillaIds) == "table" then
          rec._isNew = vanillaIds[id] ~= true
        end
      end
    end
  end
  markNewRecords(S.project.maps, S._vanillaMapIds)
  markNewRecords(S.project.tilesets, S._vanillaTilesetIds)

  -- Base ROM data so move/item/tileset patches emit diffs + prefer :patch.
  -- Terrain paint aliases project.tilesets into S.data.tilesets, so diff must
  -- compare against the pristine clone in _vanillaTilesetBackup.
  local base = S.data
  local vts = S._vanillaTilesetBackup
  if type(vts) == "table" and next(vts) and type(S.data) == "table" then
    base = {}
    for k, v in pairs(S.data) do base[k] = v end
    local tilesets = {}
    for tid, rec in pairs(S.data.tilesets or {}) do
      tilesets[tid] = vts[tid] or rec
    end
    for tid, rec in pairs(vts) do
      if tilesets[tid] == nil then tilesets[tid] = rec end
    end
    base.tilesets = tilesets
  end
  if S._vanillaMapIds or S._vanillaTilesetIds then
    if base == S.data then
      local copy = {}
      for k, v in pairs(S.data) do copy[k] = v end
      base = copy
    end
    base._vanillaMapIds = S._vanillaMapIds
    base._vanillaTilesetIds = S._vanillaTilesetIds
  end
  if S.manifestDirty then
    if not Manifest.save(S, App) then return false end
  end
  ModIO._emitBaseData = base
  local ok, err = ModIO.save(S.path, S.project)
  ModIO._emitBaseData = nil
  if ok then
    S.dirty = false
    if err == "kept-main" then
      say("Saved " .. S.path
        .. " (editor_project.lua + editor_apply.lua; left hand-written main.lua)")
    else
      say("Saved " .. S.path .. " (editor_project.lua + main.lua)")
    end
    return true
  else
    say("Save failed: " .. tostring(err))
    return false
  end
end

local function repoRoot()
  local src = love.filesystem.getSource()
  if src and src ~= "" then return src end
  return "."
end

local function runShell(cmd)
  local ok, handle = pcall(io.popen, cmd .. " 2>&1")
  if not ok or not handle then
    return false, "shell unavailable: " .. tostring(handle)
  end
  local out = handle:read("*a") or ""
  local okClose, _, code = handle:close()
  local exit = (type(code) == "number" and code)
    or (okClose and 0 or 1)
  return exit == 0, out
end

local function engineHasLoader(root)
  if not root or root == "" then return false end
  local sep = package.config:sub(1, 1)
  local f = io.open(root .. sep .. "src" .. sep .. "mods" .. sep .. "Loader.lua", "rb")
  if f then f:close(); return true end
  return false
end

local function linkedRecompRoot()
  local prefs = (S and S.dataPrefs) or DataSource.loadPrefs()
  local recomp = (prefs and prefs.recompRoot)
    or DataSource.mountedRecompRoot()
  if recomp and recomp ~= "" and DataSource.isValidRecompRoot(recomp) then
    return recomp:gsub("[/\\]+$", "")
  end
  return nil
end

local function validationEngineRoot()
  local sep = package.config:sub(1, 1)
  local linked = linkedRecompRoot()
  if engineHasLoader(linked) then return linked end
  local source = repoRoot()
  if engineHasLoader(source) then return source end
  local nested = source .. sep .. "runtime" .. sep .. "gen1recomp"
  if engineHasLoader(nested) then return nested end
  local content = os.getenv("POKEPORT_CONTENT_ROOT")
  if content and content ~= "" then
    nested = content .. sep .. "runtime" .. sep .. "gen1recomp"
    if engineHasLoader(nested) then return nested end
    nested = content .. sep .. ".content-editor-runtime" .. sep
      .. "runtime" .. sep .. "gen1recomp"
    if engineHasLoader(nested) then return nested end
  end
  return source
end

function App.validateMod()
  if not S or not S.project or not S.project.id then
    return say("No mod open")
  end
  if S.dirty then
    if not App.save() then return false end
  end
  local id = S.project.id
  local sep = package.config:sub(1, 1)
  local root = ModIO.repoRoot()
  local script = root .. sep .. "tools" .. sep .. "modkit.py"
  local probe = io.open(script, "rb")
  if probe then
    probe:close()
  else
    root = repoRoot()
    script = root .. sep .. "tools" .. sep .. "modkit.py"
  end

  say("Checking LuaJIT (" .. LuaJitTool.platformLabel() .. ")…")
  local luajit, libDir, ljErr, installed = LuaJitTool.ensure()
  if not luajit then
    S.validateOutput = "MK100 ERROR " .. tostring(ljErr or "LuaJIT missing")
    return say("Validate needs LuaJIT — see log on Project tab")
  end
  if installed then
    say("Installed LuaJIT — validating…")
  end

  local dataDir, base = DataSource.validationDataDir({
    version = S.version,
    source = S.dataSource,
    prefs = S.dataPrefs,
    repoRoot = root,
  })
  local extraEnv = {}
  extraEnv.MODKIT_VERSION = S.version or "red"
  local engine = validationEngineRoot()
  extraEnv.POKEPORT_RECOMP = engine
  if dataDir then
    extraEnv.POKEPORT_DATA_DIR = dataDir
  end
  if base == "fixture" then
    say("No ROM cache — validating structure with fixtures (vanilla references skipped)")
  end

  local function runValidate(py)
    local modPath = S.path or ModIO.modDir(id)
    local ver = tostring(S.version or "red"):lower()
    if not (GameVersion.VERSIONS and GameVersion.VERSIONS[ver]) then
      ver = "red"
    end
    local inner = string.format(
      '%s "%s" validate "%s" --base %s --version %s --repo "%s"',
      py, script, modPath, base, ver, engine)
    local cmd = LuaJitTool.wrapCommand(inner, luajit, libDir, extraEnv)
    return runShell(cmd)
  end

  local ok, out = runValidate("python")
  if (not ok and (out or ""):find("python")) or (out or ""):find("not recognized") then
    ok, out = runValidate("python3")
  end
  S.validateOutput = tostring(out or "")
  if ok then
    say("Validate OK — " .. id)
  else
    say("Validate failed — see log on Project tab")
  end
end

local function fileOk(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function runningLoveExe()
  if love and love.filesystem and love.filesystem.getExecutablePath then
    local p = love.filesystem.getExecutablePath()
    if fileOk(p) then return p end
  end
  if arg and fileOk(arg[-2]) then return arg[-2] end
  local pf = os.getenv("ProgramFiles")
  if pf and fileOk(pf .. "\\LOVE\\love.exe") then return pf .. "\\LOVE\\love.exe" end
  local pf86 = os.getenv("ProgramFiles(x86)")
  if pf86 and fileOk(pf86 .. "\\LOVE\\love.exe") then return pf86 .. "\\LOVE\\love.exe" end
  return nil
end

local function resolveLoveExe(searchRoots)
  local sep = package.config:sub(1, 1)
  for _, root in ipairs(searchRoots or {}) do
    if root and root ~= "" then
      local candidates = {
        -- Fused portable distribution (does not take a source-folder arg).
        { root .. sep .. "gen1recomp.exe", true },
        -- Windows portable / checkout
        { root .. sep .. "love" .. sep .. "love.exe", false },
        { root .. sep .. "love" .. sep .. "love-11.5-win64" .. sep .. "love.exe", false },
        { root .. sep .. "love.exe", false },
        -- Linux portable AppImage / binary
        { root .. sep .. "love" .. sep .. "love-11.5-x86_64.AppImage", false },
        { root .. sep .. "love" .. sep .. "love", false },
        -- macOS portable pack (love/love.app)
        { root .. sep .. "love" .. sep .. "love.app" .. sep
          .. "Contents" .. sep .. "MacOS" .. sep .. "love", false },
      }
      for _, candidate in ipairs(candidates) do
        local path, fused = candidate[1], candidate[2]
        local f = io.open(path, "rb")
        if f then f:close(); return path, fused end
      end
    end
  end
  local macApp = "/Applications/love.app/Contents/MacOS/love"
  local f = io.open(macApp, "rb")
  if f then f:close(); return macApp, false end
  return "love", false
end

local playtestArmed = 0

function App.playtestMod()
  if not S or not S.project or not S.project.id then
    return say("No mod open")
  end
  local now = (love.timer and love.timer.getTime and love.timer.getTime())
    or os.time()
  if now - playtestArmed < 1.5 then
    return say("Playtest is already launching")
  end
  playtestArmed = now
  -- Hand-written mods need a fresh editor_apply.lua even when the project
  -- is not marked dirty (first playtest after a Save-format change).
  if (anyDirty(S) or S.project._protectMain) and not App.save() then return false end
  local id = S.project.id
  -- Older editor saves can already contain the Map Builder transform without
  -- its required filesystem capability.  Repair that manifest before either
  -- launching locally or copying it into a linked Recomp install, even when
  -- the project had no dirty edits for App.save() to rewrite.
  if S.project.layeredTransform then
    local wired, wireErr = ModIO.setMapBuilderTransform(
      S.path or ModIO.modDir(id), S.project.layeredTransform)
    if not wired then
      return say("Playtest manifest update failed: " .. tostring(wireErr))
    end
  end
  local sep = package.config:sub(1, 1)
  local recomp = linkedRecompRoot()
  if not recomp then
    return say("Playtest requires a Linked Recomp folder. "
      .. "Use Project > Link Recomp, then try again.")
  end

  local dest = recomp .. sep .. "mods" .. sep .. id
  local src = S.path or (ModIO.modsRoot() .. sep .. id)
  -- Fused portable builds do not consistently expose Windows junctions to
  -- PhysFS, even when symlinks are enabled.  Synchronize the open project to
  -- the selected runtime's real mods directory so its loader always sees it.
  local okSync, syncErr = DataSource.copyTree(src, dest)
  if not okSync then
    return say("Playtest sync failed: " .. tostring(syncErr))
  end

  local version = S.version or "red"
  if not (GameVersion.VERSIONS and GameVersion.VERSIONS[version]) then
    version = "red"
  end

  -- A Playtest is an isolated run of the project open in the editor.  Do not
  -- inherit mods the player enabled in an earlier normal game session.
  local okEnable, errEnable = pcall(function()
    local SaveData = require("src.core.SaveData")
    local options = SaveData.loadOptions()
    options.mods = options.mods or {}
    for otherId in pairs(options.mods) do
      options.mods[otherId] = false
    end
    options.mods[id] = true
    options.modsByVersion = options.modsByVersion or {}
    -- Latest Recomp reads per-game enablement. Turn this mod on for every
    -- supported game so Playtest works after switching Red/Blue/Yellow/Gold/Silver.
    for _, vid in ipairs(GameVersion.ORDER or { version }) do
      local bucket = options.modsByVersion[vid] or {}
      options.modsByVersion[vid] = bucket
      for otherId in pairs(bucket) do
        bucket[otherId] = false
      end
      bucket[id] = true
    end
    SaveData.saveOptions(options)
  end)
  if not okEnable then
    say("Could not enable mod in options: " .. tostring(errEnable))
    return
  end

  local loveExe, fused = resolveLoveExe({
    recomp,
    repoRoot(),
    os.getenv("POKEPORT_CONTENT_ROOT"),
  })
  if not fused then
    local running = runningLoveExe()
    if running then loveExe = running end
  end
  local cmd
  if sep == "\\" then
    if fused then
      cmd = string.format('start "Gen1RecompPlaytest" /D "%s" "%s" --game=%s',
        recomp, loveExe, version)
    else
      cmd = PlaytestPaths.windowsLaunch(loveExe, recomp, version)
    end
    cmd = PlaytestPaths.windowsDetach(cmd)
  else
    if fused then
      cmd = string.format('cd "%s" && "%s" --game=%s &',
        recomp, loveExe, version)
    else
      cmd = string.format('"%s" "%s" --game=%s &',
        loveExe, recomp, version)
    end
  end
  local ok, err = pcall(os.execute, cmd)
  if not ok then
    return say("Playtest launch failed: " .. tostring(err))
  end
  say("Playtest launched " .. version .. " with selected editor mod: " .. id)
end

function App.markDirty()
  if not S then return end
  History.noteDirty(S)
  S.dirty = true
  S._quitArmed = nil
end

function App.beginEditBatch()
  if S then History.beginBatch(S) end
end

function App.endEditBatch()
  if S then History.endBatch(S) end
end

function App.undo()
  if not S then return say("Nothing to undo") end
  if S.tab == "code" and Code.undo and Code.undo(S) then
    return say("Code undo")
  end
  if not S.project then return say("Nothing to undo") end
  if History.undo(S) then
    say("Undo (" .. #(S.undoStack or {}) .. " left)")
  else
    say("Nothing to undo")
  end
end

function App.redo()
  if not S then return say("Nothing to redo") end
  if S.tab == "code" and Code.redo and Code.redo(S) then
    return say("Code redo")
  end
  if not S.project then return say("Nothing to redo") end
  if History.redo(S) then
    say("Redo (" .. #(S.redoStack or {}) .. " left)")
  else
    say("Nothing to redo")
  end
end

function App.close()
  if S then
    pcall(function() Audio.stopPreview(S) end)
    pcall(function() BattleAnimPreview.stop(S) end)
    pcall(function() UiPreview.stop(S) end)
  end
  if anyDirty(S) then
    if not S._quitArmed then
      S._quitArmed = true
      say("Unsaved changes — Close again to quit without saving")
      return
    end
  end
  love.event.quit()
end

local TAB_GAP = 6

local function measureTabs(s)
  local widths, total = {}, 0
  local gap = TAB_GAP * s
  for i, t in ipairs(TABS) do
    local tw = math.max(72 * s, Kit.textWidth("micro", t.label) + 18 * s)
    widths[i] = tw
    total = total + tw + (i > 1 and gap or 0)
  end
  return widths, total, gap
end

local function tabOffsetOf(widths, gap, index)
  local x = 0
  for i = 1, index - 1 do
    x = x + (widths[i] or 0) + gap
  end
  return x
end

local function ensureTabVisible(s, viewW)
  if not S or viewW <= 0 then return end
  local widths, contentW, gap = measureTabs(s)
  local maxOff = math.max(0, contentW - viewW)
  local idx = 1
  for i, t in ipairs(TABS) do
    if t.id == S.tab then idx = i; break end
  end
  local left = tabOffsetOf(widths, gap, idx)
  local right = left + (widths[idx] or 0)
  local scroll = Theme.clamp(S.tabBarScroll or 0, 0, maxOff)
  if left < scroll then
    scroll = left
  elseif right > scroll + viewW then
    scroll = right - viewW
  end
  S.tabBarScroll = Theme.clamp(scroll, 0, maxOff)
end

-- Horizontal scrollbar under the tab strip. Returns updated pixel offset.
-- hitY/hitH (optional) expand the arrow-key hover target (e.g. whole tab strip).
local function tabHScrollbar(x, y, w, h, offset, contentW, viewW, hitY, hitH)
  local maxOff = math.max(0, (contentW or 0) - math.max(0, viewW or 0))
  local s = Kit.scale
  local keyOpts = {
    axis = "x", kind = "pixels",
    step = math.max(40 * s, 64 * s),
    page = math.max(40 * s, (viewW or w) * 0.6),
  }
  offset = Kit.getScrollOffset("tabBarH", offset, maxOff)
  if maxOff <= 0 or w <= 0 or h <= 0 then return 0 end
  local thumbW = math.max(28 * s, w * viewW / math.max(1, contentW))
  local travel = math.max(1, w - thumbW)
  local tx = x + travel * (offset / maxOff)
  local drag = S and S._tabBarDrag

  if not Kit.mouseDown then
    if S then S._tabBarDrag = nil end
  elseif drag and drag.mode == "thumb" then
    local rel = Theme.clamp(Kit.mouseX - drag.grab, 0, travel)
    offset = Theme.clamp(rel / travel * maxOff, 0, maxOff)
  elseif Kit.mouseClicked and not Kit.blockClicks and Kit.hit(x, y, w, h) then
    if Kit.hit(tx, y, thumbW, h) then
      if S then
        S._tabBarDrag = { mode = "thumb", grab = Kit.mouseX - tx }
      end
    else
      local page = math.max(40 * s, viewW * 0.6)
      if Kit.mouseX < tx then
        offset = Theme.clamp(offset - page, 0, maxOff)
      else
        offset = Theme.clamp(offset + page, 0, maxOff)
      end
    end
  end

  offset = Kit.rememberScroll("tabBarH", x, hitY or y, w, hitH or h,
    offset, maxOff, keyOpts)
  tx = x + travel * (offset / math.max(1, maxOff))

  if love and love.graphics then
    Theme.col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", x, y, w, h, h / 2, h / 2)
    local hot = Kit.hover(tx, y, thumbW, h)
      or (drag and drag.mode == "thumb")
    Theme.col(PAL.green, hot and 0.9 or 0.65)
    love.graphics.rectangle("fill", tx, y, thumbW, h, h / 2, h / 2)
  end
  return offset
end

local function cycleTab(delta)
  local idx = 1
  for i, t in ipairs(TABS) do
    if t.id == S.tab then idx = i; break end
  end
  idx = ((idx - 1 + delta) % #TABS) + 1
  local prev = S.tab
  S.tab = TABS[idx].id
  if prev == "audio" and S.tab ~= "audio" then
    pcall(function() Audio.stopPreview(S) end)
  end
  if (prev == "moves" or prev == "anims")
      and S.tab ~= "moves" and S.tab ~= "anims" then
    pcall(function() BattleAnimPreview.stop(S) end)
  end
  if prev == "ui" and S.tab ~= "ui" then
    pcall(function() UiPreview.stop(S) end)
  end
  S._tabBarNeedsReveal = true
  say("Tab: " .. TABS[idx].label)
end

-- Queue a native file dialog.  Must not run inside love.draw: on Windows the
-- PowerShell OpenFileDialog + mid-frame image decode freezes the LOVE window
-- ("Not Responding") after Browse.  Processed once from App.update.
function App.pickFile(title, filter, onPicked)
  if not S then return end
  S._filePick = {
    kind = "file",
    title = title or "Choose a file",
    filter = filter or "All files (*.*)|*.*",
    cb = onPicked,
  }
end

function App.pickFolder(title, onPicked, startPath)
  if not S then return end
  S._filePick = {
    kind = "folder",
    title = title or "Choose a folder",
    startPath = startPath,
    cb = onPicked,
  }
end

-- Sanitize a picked filename for use under mod assets/.
function App.assetBaseName(picked, fallback)
  local base = tostring(picked or ""):match("[^/\\]+$") or fallback or "file.bin"
  base = base:gsub("[^%w%._%-]", "_")
  if base == "" or base == "." or base == ".." then
    base = fallback or "file.bin"
  end
  return base
end

-- Copy a picked file into the open mod's assets/ keeping its real filename
-- (e.g. abrab.png → assets/abrab.png).  destRel is ignored when present as a
-- legacy prefix; the basename of `picked` always wins.
-- onDone(destRel, sourceName) is optional.
function App.importToMod(picked, destRel, onDone)
  if not (S and S.path and picked) then return false end
  local sourceName = App.assetBaseName(picked, "file.bin")
  local rel = "assets/" .. sourceName
  -- Optional explicit destination only if caller passed a full path with ext.
  if type(destRel) == "string" and destRel:match("%.[%w]+$") then
    rel = destRel:match("^assets/") and destRel or ("assets/" .. destRel)
  end
  local sep = package.config:sub(1, 1)
  local dest = S.path .. sep .. rel:gsub("/", sep)
  local ok, err = ModIO.copyFile(picked, dest)
  if not ok then
    say("Copy failed: " .. tostring(err))
    return false
  end
  local Preview = require("Preview")
  if Preview.invalidatePath then
    Preview.invalidatePath(rel)
  else
    Preview.invalidate()
  end
  App.markDirty()
  if onDone then onDone(rel, sourceName) end
  say("Imported " .. sourceName .. " → " .. rel)
  local perr = Preview.lastError and Preview.lastError()
  if perr then say("Imported " .. rel .. " — preview: " .. perr) end
  return true
end

function App.update(dt)
  if not S then return end
  if Kit.scrollUpdate then
    pcall(function() Kit.scrollUpdate(dt or 0) end)
  end
  if S.audioPreview or S.tab == "audio" then
    pcall(function() Audio.update(S, dt or 0) end)
  end
  if S.battleAnimPreview
      or S.tab == "moves" or S.tab == "anims" then
    pcall(function() BattleAnimPreview.update(S, dt or 0) end)
  end
  if S.uiPreview or S.tab == "ui" then
    pcall(function() UiPreview.update(S, dt or 0) end)
  end
  if S.tab == "maps" and MapsWorkspace.update then
    pcall(function() MapsWorkspace.update(S, dt or 0) end)
  end
  -- Arrow-key list nav (hold-to-repeat) for every panel that bindNav'd.
  pcall(function() RegList.update(S, dt or 0) end)
  if S._romImporter then
    local imp = S._romImporter
    pcall(function() imp:update(dt or 0) end)
    if imp.status and imp.workState == "working" then
      local pct = imp.progress and math.floor((imp.progress or 0) * 100) or 0
      S.status = string.format("Importing ROM… %s (%d%%)",
        tostring(imp.status), pct)
    end
    if imp.workState ~= "working" and not imp.worker then
      if imp.workState ~= "complete" and S._romImporter == imp then
        local msg = (imp.notice and imp.notice.text) or imp.status
        if msg and tostring(msg) ~= "" then say(tostring(msg)) end
        S._romImporter = nil
      end
    end
  end
  if not S._filePick then return end
  local req = S._filePick
  S._filePick = nil
  local path, status
  if req.kind == "folder" then
    path, status = ModIO.chooseFolder(req.title, req.startPath)
  else
    path, status = ModIO.chooseFile(req.title, req.filter)
  end
  if path then
    if req.cb then
      local ok, err = pcall(req.cb, path)
      if not ok then
        say("Import failed: " .. tostring(err))
      end
    end
    return
  end

  -- Cancelling a working native picker is final. The manual path prompt is
  -- only a fallback for systems where no native picker could be opened.
  if status == "cancel" then
    say("Open cancelled")
    return
  end

  -- Native dialogs often fail silently (Linux AppImage / Windows dialog
  -- buried under LÖVE). Always offer an in-app path box instead of only
  -- "Open cancelled".
  local osName = (love.system.getOS and love.system.getOS()) or ""
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  S._pathPrompt = {
    title = req.title or "Enter path",
    kind = req.kind or "file",
    value = req.startPath or home,
    cb = req.cb,
    hint = req.kind == "folder"
      and "Paste the Gen1Recomp folder path, then OK"
      or "Paste the full .gb / file path, then OK",
  }
  if osName == "Linux" and status == "unavailable" then
    say("No file dialog — paste a path below (or: sudo apt install zenity)")
  else
    say("Paste a path below if the file dialog did not appear, or Cancel")
  end
end

local function finishPathPrompt(accepted)
  if not S or not S._pathPrompt then return end
  local prompt = S._pathPrompt
  S._pathPrompt = nil
  if not accepted then
    say("Open cancelled")
    return
  end
  local path = tostring(prompt.value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if path == "" then
    say("Open cancelled")
    return
  end
  if prompt.cb then
    local ok, err = pcall(prompt.cb, path)
    if not ok then
      say("Import failed: " .. tostring(err))
    end
  end
end

local function drawPathPrompt(W, H, s)
  local prompt = S._pathPrompt
  if not prompt then return end
  Kit.blockClicks = true
  Theme.col({ 0, 0, 0 }, 0.72)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local boxW = math.min(640 * s, W - 40 * s)
  local boxH = 170 * s
  local bx = (W - boxW) / 2
  local by = (H - boxH) / 2
  Kit.card(bx, by, boxW, boxH, 12 * s)
  Kit.text("small", tostring(prompt.title or "Enter path"),
    bx + 16 * s, by + 16 * s, PAL.heading)
  Kit.text("micro", tostring(prompt.hint or "Paste an absolute path"),
    bx + 16 * s, by + 40 * s, PAL.muted)
  local fieldH = 34 * s
  local edited = Kit.textfield("path_prompt", bx + 16 * s, by + 68 * s,
    boxW - 32 * s, fieldH, prompt.value or "", "/path/to/...")
  if edited ~= nil then prompt.value = edited end
  local btnW = 100 * s
  if Kit.button(bx + boxW - 16 * s - btnW * 2 - 10 * s, by + boxH - 48 * s,
      btnW, 32 * s, "Cancel", { kind = "ghost" }) then
    finishPathPrompt(false)
  end
  if Kit.button(bx + boxW - 16 * s - btnW, by + boxH - 48 * s,
      btnW, 32 * s, "OK", { kind = "primary" }) then
    finishPathPrompt(true)
  end
  Kit.blockClicks = false
end

function App.draw()
  if not S then return end
  local W, H = love.graphics.getDimensions()
  local s = Kit.layout(W, H)
  local mx, my = love.mouse.getPosition()
  if clickX then mx, my = clickX, clickY end
  Kit.beginFrame(mx, my, mouseClicked, wheelY)
  mouseClicked = false
  clickX, clickY = nil, nil
  Autocomplete.beginFrame(S)

  Theme.field(W, H)

  -- version rail
  local railH = 6 * s
  Theme.versionRail(0, 0, W, railH)

  local titleY = railH + 10 * s
  local btnH = 32 * s
  Kit.text("title", "CONTENT EDITOR", 20 * s, titleY, PAL.heading)
  local chip = S.path and (S.path:match("[/\\]([^/\\]+)$") or S.path)
    or S.browseModId or "(no mod)"
  if anyDirty(S) then chip = chip .. " *" end
  Kit.text("small", chip, 20 * s, titleY + 28 * s, PAL.muted)

  local bx = W - 20 * s
  local function rbtn(label, kind, fn, enabled, tip)
    local bw = Kit.textWidth("button", label) + 28 * s
    bx = bx - bw - 8 * s
    local opts = { kind = kind, tooltip = tip }
    if enabled == false then opts.enabled = false end
    if Kit.button(bx, titleY, bw, btnH, label, opts) then fn() end
  end
  rbtn("Close", "ghost", function() App.close() end, true,
    "Quit the content editor (Esc)")
  rbtn("Save", "primary", function() App.save() end, true,
    "Write editor_project.lua + main.lua (or editor_apply.lua) (Ctrl+S)")
  rbtn("Redo", "ghost", function() App.redo() end, History.canRedo(S),
    "Redo (Ctrl+Y)")
  rbtn("Undo", "ghost", function() App.undo() end, History.canUndo(S),
    "Undo last content edit (Ctrl+Z)")
  rbtn("Open", "ghost", function()
    App.pickFolder("Choose a mod folder", function(path)
      App.openMod(path)
    end, ModIO.modsRoot())
  end, true, "Open an existing mods/ folder")

  local tabY = railH + 70 * s
  local tabH = 36 * s
  local tabPadX = 20 * s
  local tabViewX = tabPadX
  local tabViewW = math.max(40 * s, W - tabPadX * 2)
  local widths, contentW, gap = measureTabs(s)
  local maxOff = math.max(0, contentW - tabViewW)
  local showBar = maxOff > 0
  local barH = showBar and math.max(6 * s, 8 * s) or 0
  local barGap = showBar and 4 * s or 0

  if S._tabBarNeedsReveal then
    S._tabBarNeedsReveal = nil
    ensureTabVisible(s, tabViewW)
  end
  S.tabBarScroll = Theme.clamp(S.tabBarScroll or 0, 0, maxOff)

  -- Wheel / drag-scroll over the tab strip (and its scrollbar).
  local hitH = tabH + (showBar and (barGap + barH) or 0)
  if showBar and Kit.hit(tabViewX, tabY, tabViewW, hitH) and not Kit.blockClicks then
    if (Kit.wheelY or 0) ~= 0 then
      local notch = 80 * s
      local delta = (Kit.wheelY > 0) and -notch or notch
      S.tabBarScroll = Theme.clamp((S.tabBarScroll or 0) + delta, 0, maxOff)
      Kit.wheelY = 0
    end
    if Kit.mouseDown then
      if not S._tabBarStripDrag and Kit.hit(tabViewX, tabY, tabViewW, tabH)
          and not (S._tabBarDrag and S._tabBarDrag.mode == "thumb") then
        S._tabBarStripDrag = {
          x = Kit.mouseX, off = S.tabBarScroll or 0,
        }
      elseif S._tabBarStripDrag then
        S.tabBarScroll = Theme.clamp(
          S._tabBarStripDrag.off + (S._tabBarStripDrag.x - Kit.mouseX),
          0, maxOff)
      end
    else
      S._tabBarStripDrag = nil
    end
  else
    S._tabBarStripDrag = nil
  end

  Kit.pushClip(tabViewX, tabY, tabViewW, tabH)
  local tx = tabViewX - (S.tabBarScroll or 0)
  for i, t in ipairs(TABS) do
    local tw = widths[i]
    local on = S.tab == t.id
    if Kit.chip(tx, tabY, tw, tabH, t.label, on, PAL.green, PAL.steel, t.tip) then
      if S.tab == "audio" and t.id ~= "audio" then
        pcall(function() Audio.stopPreview(S) end)
      end
      if (S.tab == "moves" or S.tab == "anims")
          and t.id ~= "moves" and t.id ~= "anims" then
        pcall(function() BattleAnimPreview.stop(S) end)
      end
      if S.tab == "ui" and t.id ~= "ui" then
        pcall(function() UiPreview.stop(S) end)
      end
      S.tab = t.id
      S._tabBarNeedsReveal = true
    end
    tx = tx + tw + gap
  end
  Kit.popClip()

  if showBar then
    local barY = tabY + tabH + barGap
    S.tabBarScroll = tabHScrollbar(
      tabViewX, barY, tabViewW, barH,
      S.tabBarScroll or 0, contentW, tabViewW,
      tabY, tabH + barGap + barH)
  else
    S.tabBarScroll = 0
  end

  local contentY = tabY + tabH + barGap + barH + 16 * s
  local contentH = H - contentY - 44 * s
  History.beginFrame(S)
  -- Block underlying panel hits while a modal is up.
  if ColorWheel.isOpen(S) or PaletteEdit.isOpen(S) or PalettePicker.isOpen(S)
      or SpeciesPicker.isOpen(S) or ItemPicker.isOpen(S)
      or ChoicePicker.isOpen(S)
      or BattleAnims.isPickerOpen(S) or S._pathPrompt or S.mapTilesetPicker then
    Kit.blockClicks = true
  end
  RegList.clearNav(S)
  local panel = PANELS[S.tab]
  if panel and panel.draw then
    panel.draw(S, 20 * s, contentY, W - 40 * s, contentH, App)
  end
  History.endFrame(S)

  -- Inline autocomplete over panel fields (before status / full-screen modals).
  if not (ColorWheel.isOpen(S) or PaletteEdit.isOpen(S) or PalettePicker.isOpen(S)
      or SpeciesPicker.isOpen(S) or ItemPicker.isOpen(S)
      or ChoicePicker.isOpen(S)
      or BattleAnims.isPickerOpen(S) or S._pathPrompt or S.mapTilesetPicker) then
    Autocomplete.draw(S)
  end

  -- status bar
  local statusH = 38 * s
  local statusY = H - statusH
  Theme.col(PAL.cardBody, 0.85)
  love.graphics.rectangle("fill", 0, statusY, W, statusH)
  local statusTy = statusY + (statusH - Kit.textHeight("micro")) / 2
  Kit.text("micro", S.status or "", 20 * s, statusTy, PAL.detail)
  Kit.textRight("micro", "Undo Ctrl+Z   Redo Ctrl+Y   Save Ctrl+S   Esc",
    W - 20 * s, statusTy, PAL.faint)

  -- Re-enable hits so modals themselves can receive clicks.
  -- Upper modals (color wheel / custom-palette ask) block the ones below.
  if PalettePicker.isOpen(S) then
    Kit.blockClicks = ColorWheel.isOpen(S) or PaletteEdit.isOpen(S)
    PalettePicker.draw(S, 0, 0, W, H)
  end
  if SpeciesPicker.isOpen(S) then
    Kit.blockClicks = false
    SpeciesPicker.draw(S, 0, 0, W, H)
  end
  if ItemPicker.isOpen(S) then
    Kit.blockClicks = false
    ItemPicker.draw(S, 0, 0, W, H)
  end
  if ChoicePicker.isOpen(S) then
    Kit.blockClicks = false
    ChoicePicker.draw(S, 0, 0, W, H)
  end
  if BattleAnims.isPickerOpen(S) then
    Kit.blockClicks = false
    BattleAnims.drawPicker(S, 0, 0, W, H)
  end
  if S.mapTilesetPicker and Maps.drawTilesetPicker then
    Kit.blockClicks = false
    Maps.drawTilesetPicker(S, 0, 0, W, H, App)
  end
  if S._pathPrompt then
    Kit.blockClicks = false
    drawPathPrompt(W, H, s)
  end
  if ColorWheel.isOpen(S) then
    Kit.blockClicks = PaletteEdit.isOpen(S)
    ColorWheel.draw(S, 0, 0, W, H)
  end
  if PaletteEdit.isOpen(S) then
    Kit.blockClicks = false
    PaletteEdit.draw(S, 0, 0, W, H)
  end

  Kit.endFrame()
  wheelY = 0
end

function App.keypressed(key)
  if not S then return end
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  -- undo/redo before Kit steals keystrokes from focused fields
  if ctrl and (key == "z" or key == "y") then
    Kit.blur()
    if key == "y" or (key == "z" and shift) then
      return App.redo()
    end
    return App.undo()
  end
  if S._pathPrompt then
    if key == "return" or key == "kpenter" then
      finishPathPrompt(true)
      return
    end
    if key == "escape" then
      finishPathPrompt(false)
      return
    end
  end
  if PaletteEdit.isOpen(S) and PaletteEdit.keypressed(S, key) then return end
  if ColorWheel.isOpen(S) and ColorWheel.keypressed(S, key) then return end
  -- Autocomplete claims Up/Down/Enter/Tab/Esc before the textfield.
  if Autocomplete.keypressed(S, key) then return end
  if Kit.keypressed(key) then return end
  if key == "escape" then
    if PalettePicker.keypressed(S, key) then return end
    if SpeciesPicker.keypressed(S, key) then return end
    if ItemPicker.keypressed(S, key) then return end
    if ChoicePicker.keypressed(S, key) then return end
    if BattleAnims.pickerKeypressed(S, key) then return end
    if S.mapTilesetPicker then
      S.mapTilesetPicker = nil
      Kit.blur()
      return
    end
    if S.warpDestPick then
      S.warpDestPick = nil
      S.status = "Set destination cancelled"
      return
    end
    if S.tab == "maps" and MapsWorkspace.keypressed
        and MapsWorkspace.keypressed(S, key, App) then
      return
    end
    return App.close()
  end
  if key == "s" and ctrl then
    return App.save()
  end
  -- Tab cycles tabs only when autocomplete did not claim it.
  if key == "]" or key == "tab" then return cycleTab(1) end
  if key == "[" then return cycleTab(-1) end
  -- Modals own keyboard (except Kit textfields / Esc above).
  if ColorWheel.isOpen(S) or PaletteEdit.isOpen(S) or PalettePicker.isOpen(S)
      or SpeciesPicker.isOpen(S) or ItemPicker.isOpen(S)
      or ChoicePicker.isOpen(S)
      or BattleAnims.isPickerOpen(S) or S.mapTilesetPicker or S._pathPrompt then
    return
  end
  -- Hovered scrollbar first; otherwise list selection / panel keys.
  if Kit.scrollKeypressed and Kit.scrollKeypressed(key) then return end
  if RegList.keypressed(S, key) then return end
  if S.tab == "maps" and MapsWorkspace.keypressed then
    MapsWorkspace.keypressed(S, key, App)
  elseif S.tab == "events" and Events.keypressed then
    Events.keypressed(S, key, App)
  elseif S.tab == "code" and Code.keypressed then
    Code.keypressed(S, key)
  end
end

function App.textinput(text)
  Kit.textinput(text)
end

function App.mousepressed(x, y, button)
  if button == 1 then
    mouseClicked = true
    clickX, clickY = x, y
  end
end

function App.mousereleased(_, _, button)
  -- A paint stroke may end between draw frames or after the pointer leaves
  -- the canvas, so close its history transaction from the mouse event too.
  if button == 1 and S and S._builderStroke then
    App.endEditBatch()
    S._builderStroke = nil
  end
end

function App.wheelmoved(x, y)
  -- Tileset / palette modals need Kit.wheelY for their lists; never zoom maps.
  if S and (S.mapTilesetPicker or PalettePicker.isOpen(S)
      or SpeciesPicker.isOpen(S) or ItemPicker.isOpen(S)
      or ChoicePicker.isOpen(S)
      or ColorWheel.isOpen(S) or PaletteEdit.isOpen(S) or S._pathPrompt) then
    wheelY = wheelY + (y or 0)
    return
  end
  if S and S.tab == "maps" and MapsWorkspace.wheelmoved
      and MapsWorkspace.wheelmoved(S, y, x) then
    return
  end
  wheelY = wheelY + (y or 0)
end

function App.filedropped(file)
  if not (file and S) then return end
  local path = file.getFilename and file:getFilename() or nil
  if not path then return end
  if path:lower():match("%.tmx$") then
    S.tab = "maps"
    S.builderPane = "details"
    if Maps.importTmx then Maps.importTmx(S, path, App) end
    return
  end
  -- treat as mod folder if it looks like one
  if ModIO.exists(path .. "/manifest.json") or ModIO.exists(path .. "\\manifest.json") then
    App.openMod(path)
  else
    say("Drop a mod folder or a .tmx map")
  end
end

function App.quit()
  if anyDirty(S) and not S._quitArmed then
    S._quitArmed = true
    say("Unsaved changes — quit again to discard")
    return true
  end
  return false
end

return App
