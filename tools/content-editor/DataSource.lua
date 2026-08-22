-- Content-editor data source: local cache, linked Gen1Recomp, imported ROM
-- (save-dir), or ROM-free fixtures. Prefs live in the LÖVE save directory so
-- a redistributable editor pack never accumulates Nintendo data.

local Json = require("src.link.Json")
local Data = require("src.core.Data")
local CacheFs = require("src.import.CacheFs")

local DataSource = {}
local ProcessRunner = require("ProcessRunner")

local PREFS_FILE = "content_editor_data.json"
local SEP = package.config:sub(1, 1)

local mountedRecomp = nil

local function join(a, b)
  a, b = tostring(a or ""), tostring(b or "")
  b = b:gsub("[/\\]", SEP):gsub("^[/\\]+", "")
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. SEP .. b
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

-- True when a version's generated cache is readable under its cachePrefix
-- (or legacy un-prefixed root for Red only).  Do not treat another game's
-- mounted data/generated as this version's cache.
function DataSource.hasLocalCache(version)
  version = version or "red"
  local GameVersion = require("src.core.GameVersion")
  local prefix = GameVersion.cachePrefix and GameVersion.cachePrefix(version) or ""
  local candidates = {
    prefix .. "data/generated/maps.lua",
    prefix .. "data/generated/constants.lua",
  }
  -- Legacy root cache is Red only (migrateLegacyRedCache); Blue/Yellow/Gold/Silver
  -- must live under their prefix or a wrong Kanto table wins the switch.
  if version == "red" or prefix == "" then
    candidates[#candidates + 1] = "data/generated/maps.lua"
    candidates[#candidates + 1] = "data/generated/constants.lua"
  end
  if love and love.filesystem and love.filesystem.getInfo then
    for _, rel in ipairs(candidates) do
      if love.filesystem.getInfo(rel, "file") then return true end
    end
  end
  local root = love and love.filesystem and love.filesystem.getSource
    and love.filesystem.getSource()
  if root and root ~= "" then
    local prefixes = { prefix }
    if version == "red" or prefix == "" then
      prefixes[#prefixes + 1] = ""
    end
    for _, pfx in ipairs(prefixes) do
      local sub = (pfx or ""):gsub("/+$", ""):gsub("/", SEP)
      local maps = sub ~= ""
        and join(root, join(sub, join("data", join("generated", "maps.lua"))))
        or join(root, join("data", join("generated", "maps.lua")))
      if fileExists(maps) then return true end
    end
  end
  return false
end

local function hasGeneratedMaps(root, prefix)
  if prefix and prefix ~= "" then
    if fileExists(join(root, prefix .. SEP .. "data" .. SEP .. "generated"
      .. SEP .. "maps.lua")) then
      return true
    end
  end
  return fileExists(join(root, "data" .. SEP .. "generated" .. SEP .. "maps.lua"))
end

-- Linked Gen1Recomp folder has an on-disk cache for this version (not merely
-- a Red/legacy data/generated at the root).
-- Latest Recomp checkouts often only extract Red at data/generated. Blue and
-- Yellow share that Gen 1 table shape, so they may use the Red/root extract.
-- Gold and Silver must have their own gold/ or silver/ tree.
function DataSource.recompHasVersion(root, version)
  if type(root) ~= "string" or root == "" then return false end
  root = root:gsub("[/\\]+$", "")
  version = version or "red"
  local GameVersion = require("src.core.GameVersion")
  local prefix = (GameVersion.cachePrefix and GameVersion.cachePrefix(version) or "")
    :gsub("/+$", ""):gsub("/", SEP)
  if prefix ~= "" then
    if fileExists(join(root, prefix .. SEP .. "data" .. SEP .. "generated"
      .. SEP .. "maps.lua")) then
      return true
    end
    if version == "red" or (GameVersion.generation(version) == 1) then
      return hasGeneratedMaps(root, "red")
    end
    return false
  end
  return fileExists(join(root, "data" .. SEP .. "generated" .. SEP .. "maps.lua"))
end

-- After Data:load(), confirm we did not silently pick up another generation
-- (e.g. Linked Recomp Red cache while the UI says Gold).
local function loadedDataMatches(version)
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.generation(version) == 2 then
    if type(Data.maps) == "table" and Data.maps.NEW_BARK_TOWN then return true end
    if type(Data.pokemon) == "table" and Data.pokemon.CHIKORITA then return true end
    if type(Data.encounters) == "table" and Data.encounters.grass then return true end
    if type(Data.trainers) == "table" and Data.trainers.classes then return true end
    if type(Data.maps) == "table" and Data.maps.PALLET_TOWN then return false end
    return type(Data.maps) == "table" and type(Data.pokemon) == "table"
  end
  if type(Data.encounters) == "table" and Data.encounters.grass then return false end
  if type(Data.trainers) == "table" and Data.trainers.classes then return false end
  if type(Data.maps) == "table" and Data.maps.NEW_BARK_TOWN
      and not Data.maps.PALLET_TOWN then
    return false
  end
  return type(Data.maps) == "table" and type(Data.pokemon) == "table"
end

function DataSource.isValidRecompRoot(path)
  if type(path) ~= "string" or path == "" then return false end
  path = path:gsub("[/\\]+$", "")
  -- A fused Windows distribution is a complete Playtest runtime even though
  -- it has no visible main.lua (the game source is fused into the executable).
  if fileExists(join(path, "gen1recomp.exe")) then return true end
  -- A linked Recomp is also the Playtest runtime.  Its ROM cache may live in
  -- the shared LÖVE save directory, so a genuine source checkout remains a
  -- valid link even when it has no generated data inside the repository.
  if fileExists(join(path, "main.lua"))
      and fileExists(join(path, "src" .. SEP .. "mods" .. SEP .. "Loader.lua"))
      and fileExists(join(path, "src" .. SEP .. "core" .. SEP .. "LaunchOptions.lua")) then
    return true
  end
  -- Legacy un-prefixed cache, or any GameVersion cachePrefix tree
  -- (red/, blue/, yellow/, gold/, silver/).
  if fileExists(join(path, "data" .. SEP .. "generated" .. SEP .. "maps.lua")) then
    return true
  end
  local GameVersion = require("src.core.GameVersion")
  for _, version in ipairs(GameVersion.ORDER or { "red" }) do
    local prefix = GameVersion.cachePrefix and GameVersion.cachePrefix(version) or ""
    prefix = prefix:gsub("/+$", ""):gsub("/", SEP)
    if prefix ~= "" then
      local maps = join(path, prefix .. SEP .. "data" .. SEP .. "generated"
        .. SEP .. "maps.lua")
      if fileExists(maps) then return true end
    end
  end
  return false
end

function DataSource.loadPrefs()
  local raw = love.filesystem.read(PREFS_FILE)
  if type(raw) ~= "string" or raw == "" then
    return { mode = "auto", recompRoot = nil, useGbcPalettes = true, lastVersion = "red" }
  end
  local ok, data = pcall(Json.decode, raw)
  if not ok or type(data) ~= "table" then
    return { mode = "auto", recompRoot = nil, useGbcPalettes = true, lastVersion = "red" }
  end
  local useGbc = data.useGbcPalettes
  if useGbc == nil then useGbc = true end
  local GameVersion = require("src.core.GameVersion")
  local lastVersion = data.lastVersion or "red"
  if not (GameVersion.VERSIONS and GameVersion.VERSIONS[lastVersion]) then
    lastVersion = "red"
  end
  return {
    mode = data.mode or "auto",
    recompRoot = data.recompRoot,
    useGbcPalettes = useGbc and true or false,
    lastVersion = lastVersion,
  }
end

function DataSource.savePrefs(prefs)
  prefs = prefs or DataSource.loadPrefs()
  local useGbc = prefs.useGbcPalettes
  if useGbc == nil then useGbc = true end
  local body = Json.encode({
    mode = prefs.mode or "auto",
    recompRoot = prefs.recompRoot,
    useGbcPalettes = useGbc and true or false,
    lastVersion = prefs.lastVersion or "red",
  })
  love.filesystem.write(PREFS_FILE, body)
  return prefs
end

function DataSource.setLastVersion(version)
  local GameVersion = require("src.core.GameVersion")
  if not (GameVersion.VERSIONS and GameVersion.VERSIONS[version]) then
    version = "red"
  end
  local prefs = DataSource.loadPrefs()
  prefs.lastVersion = version
  DataSource.savePrefs(prefs)
  return prefs
end

function DataSource.unmountLinked()
  if mountedRecomp then
    if type(CacheFs.unmountExternal) == "function" then
      pcall(CacheFs.unmountExternal, mountedRecomp)
    end
    mountedRecomp = nil
  end
end

function DataSource.mountRecomp(path)
  if not DataSource.isValidRecompRoot(path) then
    return false, "Not a Gen1Recomp folder with data/generated (or red|blue|yellow|gold|silver/)"
  end
  path = path:gsub("[/\\]+$", "")
  DataSource.unmountLinked()
  -- Prepend so linked cache wins over missing local generated files.
  if type(CacheFs.mountExternal) ~= "function" then
    return false, "CacheFs.mountExternal unavailable"
  end
  local ok, mounted = pcall(CacheFs.mountExternal, path, false)
  if not ok or not mounted then
    return false, "Could not mount folder (PHYSFS unavailable?)"
  end
  mountedRecomp = path
  return true
end

local function loadFixtures()
  local root = love.filesystem.getSource()
  local fixtures = join(root, "tests" .. SEP .. "fixture_data")
  local getenv = os.getenv
  os.getenv = function(k)
    if k == "POKEPORT_DATA_DIR" then return fixtures end
    return getenv(k)
  end
  local ok, err = pcall(function() Data:load() end)
  os.getenv = getenv
  return ok, err
end

local function hasImportedCache(version)
  version = version or "red"
  local ok, RomImporter = pcall(require, "src.import.RomImporter")
  if ok and RomImporter and RomImporter.isReady then
    return RomImporter.isReady(version)
  end
  local GameVersion = require("src.core.GameVersion")
  local prefix = GameVersion.cachePrefix and GameVersion.cachePrefix(version) or ""
  if love.filesystem.getInfo(prefix .. "data/generated/maps.lua", "file") then
    return true
  end
  -- Legacy un-prefixed import is Red only.
  if version == "red" or prefix == "" then
    return love.filesystem.getInfo("data/generated/maps.lua", "file") ~= nil
  end
  return false
end

function DataSource.hasImportedCache(version)
  return hasImportedCache(version)
end

local mountedVersion = nil

local function remountVersion(version)
  if mountedVersion and mountedVersion ~= version then
    pcall(CacheFs.unmountVersion, mountedVersion)
  end
  pcall(CacheFs.mountVersion, version)
  mountedVersion = version
  local GameVersion = require("src.core.GameVersion")
  pcall(GameVersion.set, version)
end

-- Data:load is Gen 1-shaped (maps/text/pokemon/…). Game2.lua fills the rest
-- (marts/scripts/events) as gen2* keys; the editor never runs Game2, so Gold
-- Shops / Trades / Dialog / Events stay empty unless we load them here.
local GOLD_EXTRAS = {
  { file = "marts", keys = { "marts", "gen2Marts" } },
  { file = "scripts", keys = { "scripts", "gen2Scripts" } },
  { file = "text", keys = { "text", "gen2Text" } },
  { file = "std_scripts", keys = { "std_scripts", "gen2StdScripts" } },
  { file = "events", keys = { "events", "gen2EventTables" } },
  { file = "initial_events", keys = { "initial_events", "gen2InitialEvents" } },
  { file = "title", keys = { "title", "gen2Title" } },
  { file = "intro", keys = { "intro", "gen2Intro" } },
  { file = "landmarks", keys = { "landmarks", "gen2Landmarks" } },
  { file = "menu_gfx", keys = { "menu_gfx", "gen2MenuGfx" } },
  { file = "pokedex", keys = { "pokedex", "gen2Pokedex" } },
}

local function loadGoldGenerated(name)
  package.loaded["data.generated." .. name] = nil
  local path = "data/generated/" .. name .. ".lua"
  local bytes = CacheFs.readActive(path)
  if type(bytes) == "string" then
    local GameVersion = require("src.core.GameVersion")
    local chunk = loadstring(bytes, "@" .. (GameVersion.cachePrefix() or "") .. path)
    if chunk then
      local ok, res = pcall(chunk)
      if ok and type(res) == "table" then return res end
    end
  end
  if love and love.filesystem and love.filesystem.load then
    local chunk = love.filesystem.load(path)
    if chunk then
      local ok, res = pcall(chunk)
      if ok and type(res) == "table" then return res end
    end
  end
  return nil
end

local function loadGoldEditorTables()
  for i = 1, #GOLD_EXTRAS do
    local spec = GOLD_EXTRAS[i]
    local tbl = loadGoldGenerated(spec.file)
    if tbl then
      for j = 1, #spec.keys do
        Data[spec.keys[j]] = tbl
      end
    end
  end
end

local function finishLoad(version)
  local ok, err = pcall(function() Data:load() end)
  if not ok then return false, err end
  if not loadedDataMatches(version) then
    if Data._pristineKeys then pcall(function() Data:unloadGenerated() end) end
    return false, "cache does not match " .. tostring(version)
  end
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.generation(version) == 2 then
    loadGoldEditorTables()
    local okBind, Generation = pcall(require, "Generation")
    if okBind and Generation and Generation.bindGoldData then
      Generation.bindGoldData(Data)
    end
  end
  return true
end

local GEN2_SHELL = {
  "constants", "maps", "tilesets", "sprites", "pokemon", "moves", "items",
  "type_chart", "trainers", "encounters", "font", "audio", "palettes",
  "icons", "text", "scripts", "marts", "roofs", "battle_anims", "pokedex",
  "landmarks", "menu_gfx", "events", "initial_events", "std_scripts",
  "title", "intro", "field", "text_pointers", "trainer_headers",
}

local function loadEmptyGen2(version)
  remountVersion(version or "gold")
  if Data._pristineKeys then pcall(function() Data:unloadGenerated() end) end
  local ok, err = pcall(function()
    for i = 1, #GEN2_SHELL do Data[GEN2_SHELL[i]] = {} end
    Data.trainers = { classes = {} }
    Data.encounters = { grass = {}, water = {}, fishing = {}, swarm = {} }
    Data.field = { boot = {
      startMap = "PLAYERS_HOUSE_2F", startX = 3, startY = 3,
      startFacing = "down", playerName = "CHRIS", rivalName = "???",
      startMoney = 3000,
    } }
    Data.constants = Data.constants or {}
    if Data.constants.dexSize == nil then Data.constants.dexSize = 251 end
    if Data.constants.dexDigits == nil then Data.constants.dexDigits = 3 end
    if Data.constants.partyMax == nil then Data.constants.partyMax = 6 end
    if Data.constants.levelCap == nil then Data.constants.levelCap = 100 end
    local okBind, Generation = pcall(require, "Generation")
    if okBind and Generation and Generation.bindGoldData then
      Generation.bindGoldData(Data)
    end
    local pristine = {}
    Data._pristineKeys = pristine
    for key in pairs(Data) do pristine[key] = true end
  end)
  return ok, err
end

local function tryLocal(version)
  if not DataSource.hasLocalCache(version) then return false end
  remountVersion(version)
  return finishLoad(version)
end

local function tryRecomp(prefs, version)
  if not prefs.recompRoot then return false, "no linked folder" end
  if not DataSource.recompHasVersion(prefs.recompRoot, version) then
    return false, "linked folder has no " .. tostring(version) .. " cache"
  end
  local mok, merr = DataSource.mountRecomp(prefs.recompRoot)
  if not mok then return false, merr end
  remountVersion(version)
  local ok, err = finishLoad(version)
  if ok then return true end
  DataSource.unmountLinked()
  return false, err
end

local function tryImported(version)
  if not hasImportedCache(version) then return false end
  -- Imported Gold/Silver lives in the save dir; keep a Red-only linked Recomp from
  -- shadowing gold/data/generated or silver/data/generated via a root data/generated mount.
  DataSource.unmountLinked()
  remountVersion(version)
  return finishLoad(version)
end

-- Resolve and load data. Returns source id: "local"|"recomp"|"imported"|"fixtures"
-- Explicit Project-tab choices (recomp / imported / fixtures) win over auto.
function DataSource.apply(opts)
  opts = opts or {}
  local prefs = DataSource.loadPrefs()
  local version = opts.version or prefs.lastVersion or "red"
  local GameVersion = require("src.core.GameVersion")
  if not (GameVersion.VERSIONS and GameVersion.VERSIONS[version]) then
    version = "red"
  end
  prefs.lastVersion = version
  DataSource.savePrefs(prefs)

  if Data._pristineKeys then Data:unloadGenerated() end
  DataSource.unmountLinked()

  local mode = prefs.mode or "auto"
  local verLabel = (GameVersion.info(version) and GameVersion.info(version).label)
    or version

  if mode == "fixtures" then
    remountVersion(version)
    if GameVersion.generation(version) == 2 then
      local okEmpty, emptyErr = loadEmptyGen2(version)
      if not okEmpty then
        error("content editor Gen 2 shell failed:\n" .. tostring(emptyErr))
      end
      return "empty", prefs,
        "No " .. verLabel .. " fixtures — Import a " .. verLabel
          .. " ROM or Link a Recomp with "
          .. (GameVersion.cachePrefix(version) or "")
    end
    local ok, err = loadFixtures()
    if not ok then
      error("content editor fixtures failed:\n" .. tostring(err))
    end
    return "fixtures", prefs,
      "Loaded fixture data (" .. verLabel
        .. ") — Link Recomp or Import ROM for full data"
  end

  if mode == "recomp" then
    local ok = tryRecomp(prefs, version)
    if ok then
      return "recomp", prefs,
        "Linked Gen1Recomp (" .. verLabel .. "): " .. tostring(prefs.recompRoot)
    end
  elseif mode == "imported" then
    local ok = tryImported(version)
    if ok then
      return "imported", prefs,
        "Loaded imported " .. verLabel .. " ROM cache (save directory)"
    end
  end

  -- auto (or failed explicit mode): local → linked → imported → fixtures
  do
    local ok = tryLocal(version)
    if ok then
      return "local", prefs,
        "Loaded local " .. verLabel .. " ROM cache (dev / pack data/generated)"
    end
  end
  do
    local ok = tryRecomp(prefs, version)
    if ok then
      return "recomp", prefs,
        "Linked Gen1Recomp (" .. verLabel .. "): " .. tostring(prefs.recompRoot)
    end
  end
  do
    local ok = tryImported(version)
    if ok then
      return "imported", prefs,
        "Loaded imported " .. verLabel .. " ROM cache (save directory)"
    end
  end

  remountVersion(version)
  if GameVersion.generation(version) == 2 then
    local okEmpty, emptyErr = loadEmptyGen2(version)
    if not okEmpty then
      error("content editor needs a " .. verLabel
        .. " cache (Import a " .. verLabel .. " ROM or Link a Recomp with "
        .. (GameVersion.cachePrefix(version) or "") .. "):\n"
        .. tostring(emptyErr))
    end
    return "empty", prefs,
      "No " .. verLabel .. " cache — Import a " .. verLabel
        .. " ROM or Link a Recomp with "
        .. (GameVersion.cachePrefix(version) or "")
  end
  local ok, err = loadFixtures()
  if not ok then
    error("content editor needs an imported ROM cache, linked Recomp, or fixtures:\n"
      .. tostring(err))
  end
  return "fixtures", prefs,
    "Loaded fixture data (" .. verLabel
      .. ") — Link Recomp or Import ROM for full data"
end

function DataSource.linkRecomp(path)
  if not DataSource.isValidRecompRoot(path) then
    return nil, "Folder is not a Gen1Recomp checkout or generated-data folder"
  end
  path = path:gsub("[/\\]+$", "")
  local prefs = DataSource.setMode("recomp", path)
  return prefs
end

function DataSource.label(source)
  if source == "local" then return "Local cache (data/generated)" end
  if source == "recomp" then return "Linked Gen1Recomp folder" end
  if source == "imported" then return "Imported ROM (save directory)" end
  if source == "fixtures" then return "Fixtures (stub data)" end
  if source == "empty" then return "Empty Gen 2 shell (no cache)" end
  return tostring(source or "?")
end

function DataSource.setMode(mode, recompRoot)
  local prefs = DataSource.loadPrefs()
  prefs.mode = mode or "auto"
  if recompRoot ~= nil then prefs.recompRoot = recompRoot end
  if prefs.mode ~= "recomp" and prefs.mode ~= "auto" then
    -- keep path for later re-link, but mode wins
  end
  DataSource.savePrefs(prefs)
  return prefs
end

function DataSource.useFixtures()
  return DataSource.setMode("fixtures", nil)
end

function DataSource.clearToAuto()
  local prefs = DataSource.loadPrefs()
  prefs.mode = "auto"
  DataSource.savePrefs(prefs)
  return prefs
end

-- Remove imported ROM cache trees from the LÖVE save directory only.
-- Never deletes a linked Gen1Recomp install or the game source tree.
-- Returns how many top-level cache roots were removed.
function DataSource.clearImportedCache()
  if not (love and love.filesystem and love.filesystem.getSaveDirectory) then
    return 0
  end
  local saveDir = love.filesystem.getSaveDirectory()
  local function removeTree(path)
    local info = love.filesystem.getInfo(path)
    if not info then return end
    if love.filesystem.getRealDirectory
        and love.filesystem.getRealDirectory(path) ~= saveDir then
      return
    end
    if info.type == "directory" then
      for _, child in ipairs(love.filesystem.getDirectoryItems(path) or {}) do
        removeTree(path .. "/" .. child)
      end
    end
    pcall(love.filesystem.remove, path)
  end
  local GameVersion = require("src.core.GameVersion")
  local cleared = 0
  for _, version in ipairs(GameVersion.ORDER or { "red" }) do
    local prefix = GameVersion.cachePrefix and GameVersion.cachePrefix(version) or ""
    local roots = {
      prefix .. "data/generated",
      prefix .. "assets/generated",
      prefix .. "rom-cache.complete",
    }
    for _, rel in ipairs(roots) do
      if love.filesystem.getInfo(rel) then
        removeTree(rel)
        cleared = cleared + 1
      end
    end
  end
  return cleared
end

function DataSource.mountedRecompRoot()
  return mountedRecomp
end

-- Resolve the generated-data directory used by external tools such as
-- modkit. Cache layout knowledge belongs here, alongside mounting/importing,
-- rather than in the application shell.
function DataSource.validationDataDir(opts)
  opts = opts or {}
  local version = opts.version or "red"
  local source = opts.source or "fixtures"
  local prefs = opts.prefs or {}
  local repoRoot = opts.repoRoot
  local GameVersion = require("src.core.GameVersion")
  local prefix = GameVersion.cachePrefix(version) or ""

  local function generated(root, versioned)
    if not root or root == "" then return nil end
    local base = root
    if versioned and prefix ~= "" then base = join(base, prefix) end
    local candidate = join(join(base, "data"), "generated")
    if fileExists(join(candidate, "pokemon.lua")) then return candidate end
    return nil
  end

  local function versionedGenerated(root)
    local candidate = generated(root, true)
    if not candidate and version == "red" then
      candidate = generated(root, false)
    end
    return candidate
  end

  local recompRoot = prefs.recompRoot or mountedRecomp
  if source == "recomp" then
    -- Current caches are versioned. An unversioned cache is a legacy Red
    -- cache and must never be used to validate Blue, Yellow, or Gold.
    local candidate = versionedGenerated(recompRoot)
    if candidate then return candidate, "imported" end
  elseif source == "local" then
    local candidate = versionedGenerated(repoRoot)
    if candidate then return candidate, "imported" end
  end

  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local saveRoot = love.filesystem.getSaveDirectory()
    local candidate = versionedGenerated(saveRoot)
    if candidate then return candidate, "imported" end
  end

  local localFallback = versionedGenerated(repoRoot)
  if localFallback then return localFallback, "imported" end
  local recompFallback = versionedGenerated(recompRoot)
  if recompFallback then return recompFallback, "imported" end
  return nil, "fixture"
end

local function ensureDir(path)
  local sep = SEP
  if sep == "\\" then
    ProcessRunner.run('mkdir "' .. path .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function copyFileRaw(src, dest)
  local inf = io.open(src, "rb")
  if not inf then return false, "cannot read " .. tostring(src) end
  local data, readErr = inf:read("*a")
  inf:close()
  if data == nil then
    return false, "cannot read " .. tostring(src) .. ": "
      .. tostring(readErr or "unknown read error")
  end
  local parent = dest:match("^(.*)[/\\][^/\\]+$")
  if parent then ensureDir(parent) end
  local out = io.open(dest, "wb")
  if not out then return false, "cannot write " .. tostring(dest) end
  local written, writeErr = out:write(data)
  local closed, closeErr = out:close()
  if not written then
    return false, "cannot write " .. tostring(dest) .. ": "
      .. tostring(writeErr or "unknown write error")
  end
  if not closed then
    return false, "cannot close " .. tostring(dest) .. ": "
      .. tostring(closeErr or "unknown close error")
  end
  return true
end

local function listDir(path)
  local out = {}
  local platform = (love and love.system and love.system.getOS
    and love.system.getOS()) or ""
  local cmd
  if platform == "Windows" or SEP == "\\" then
    cmd = string.format('cmd /c dir /b "%s"', path)
  else
    cmd = string.format('ls -1 "%s"', path)
  end
  local ok, output = ProcessRunner.run(cmd)
  if not ok then return out end
  for line in output:gmatch("[^\r\n]+") do
    line = line:gsub("%s+$", "")
    if line ~= "" and line ~= "." and line ~= ".." then
      out[#out + 1] = line
    end
  end
  return out
end

local function isDir(path)
  -- Test directory semantics before io.open. On Linux, opening a directory in
  -- binary read mode can succeed; treating that handle as a file makes *a
  -- return nil and used to crash copyFileRaw with write(nil).
  local platform = (love and love.system and love.system.getOS
    and love.system.getOS()) or ""
  if platform == "Windows" or SEP == "\\" then
    local _, r = ProcessRunner.run(string.format(
      'if exist "%s\\" (echo DIR) else (echo NO)', path))
    return r:find("DIR") ~= nil
  end
  local p = io.popen(string.format('test -d "%s" && echo DIR', path), "r")
  if not p then return false end
  local r = p:read("*l") or ""
  p:close()
  return r:find("DIR") ~= nil
end

function DataSource.copyTree(src, dest)
  src = src:gsub("[/\\]+$", "")
  dest = dest:gsub("[/\\]+$", "")
  if not isDir(src) then
    return copyFileRaw(src, dest)
  end
  ensureDir(dest)
  for _, name in ipairs(listDir(src)) do
    local from = join(src, name)
    local to = join(dest, name)
    local ok, err = DataSource.copyTree(from, to)
    if not ok then return false, err end
  end
  return true
end

return DataSource
