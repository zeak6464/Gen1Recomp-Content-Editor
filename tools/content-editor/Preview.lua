-- Draw image previews for content-editor panels (pokemon, trainers, …).

local Theme = require("Theme")
local WorldPaletteOverrides = require("WorldPaletteOverrides")
local PAL = Theme.PAL

local Preview = {}

local cache = {}  -- key -> Image | false
-- Reject huge user-picked imports so decode cannot freeze the LOVE window.
-- Generated mapbuilder atlases from a TMX folder can be larger than this.
local MAX_PREVIEW_BYTES = 8 * 1024 * 1024  -- 8 MiB
local MAX_ATLAS_BYTES = 256 * 1024 * 1024  -- 256 MiB

local function isGeneratedAtlas(path)
  path = tostring(path or ""):gsub("\\", "/")
  return path:find("assets/mapbuilder/", 1, true) ~= nil
    or path:find("save/mod-derived/", 1, true) ~= nil
    or path:find("_cells.png", 1, true) ~= nil
end

local function existsFs(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function join(a, b)
  local sep = package.config:sub(1, 1)
  a = a:gsub("[/\\]+$", "")
  b = b:gsub("^[/\\]+", ""):gsub("/", sep)
  return a .. sep .. b
end

local function cacheKey(S, path)
  return (S and S.path or "") .. "|" .. path
end

local function loadFromDisk(absPath, maxBytes)
  maxBytes = maxBytes or MAX_PREVIEW_BYTES
  local f = io.open(absPath, "rb")
  if not f then return nil, "cannot open" end
  -- Size check without reading the whole file into Lua when possible.
  local size = f:seek("end")
  f:seek("set")
  if type(size) == "number" and size > maxBytes then
    f:close()
    return nil, string.format("image too large (%d bytes; max %d)",
      size, maxBytes)
  end
  local bytes = f:read("*a")
  f:close()
  if not bytes or #bytes == 0 then return nil, "empty file" end
  if #bytes > maxBytes then
    return nil, string.format("image too large (%d bytes; max %d)",
      #bytes, maxBytes)
  end
  local name = absPath:match("[^/\\]+$") or "preview.png"
  local ok, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not ok or not fileData then
    return nil, "FileData failed: " .. tostring(fileData)
  end
  local ok2, img = pcall(love.graphics.newImage, fileData)
  if ok2 and img then return img end
  return nil, "decode failed: " .. tostring(img)
end

function Preview.resolve(S, path)
  if type(path) ~= "string" or path == "" then return nil end
  -- mod-relative first
  if S and S.path then
    local modPath = join(S.path, path)
    if existsFs(modPath) then return modPath, "disk" end
  end
  -- love source (assets/generated/…)
  if love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(path) then
    return path, "love"
  end
  -- Writable save dir. getInfo can miss files that exist on disk (playtest
  -- identity, encode vs PhysFS, OneDrive). Map Builder atlases live here.
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local saveDir = love.filesystem.getSaveDirectory()
    if type(saveDir) == "string" and saveDir ~= "" then
      local full = join(saveDir, path)
      if existsFs(full) then return full, "disk" end
    end
  end
  -- Playtest / linked Recomp write save/mod-derived next to the engine, not
  -- under the editor's LÖVE identity.
  do
    local root
    if S and S.dataPrefs and type(S.dataPrefs.recompRoot) == "string" then
      root = S.dataPrefs.recompRoot
    end
    if not root or root == "" then
      local ok, DataSource = pcall(require, "DataSource")
      if ok and DataSource then
        if DataSource.mountedRecompRoot then
          root = DataSource.mountedRecompRoot()
        end
        if (not root or root == "") and DataSource.loadPrefs then
          local prefs = DataSource.loadPrefs()
          root = prefs and prefs.recompRoot
        end
      end
    end
    if type(root) == "string" and root ~= "" then
      local full = join(root, path)
      if existsFs(full) then return full, "disk" end
    end
  end
  -- Versioned ROM cache (gold/assets/generated/…) when PhysFS has no overlay.
  do
    local ok, CacheFs = pcall(require, "src.import.CacheFs")
    if ok and CacheFs and CacheFs.readActive then
      local bytes = CacheFs.readActive(path)
      if type(bytes) == "string" and bytes ~= "" then
        return path, "love"
      end
    end
  end
  -- absolute / cwd
  if existsFs(path) then return path, "disk" end
  local root = love and love.filesystem and love.filesystem.getSource
    and love.filesystem.getSource()
  if root then
    local full = join(root, path)
    if existsFs(full) then return full, "disk" end
  end
  return nil
end

local function imageFromCacheBytes(path)
  if type(path) ~= "string" or path == "" then return nil end
  if not (love and love.graphics and love.graphics.newImage
      and love.filesystem and love.filesystem.newFileData) then
    return nil
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okC and CacheFs and CacheFs.readActive) then return nil end
  local bytes = CacheFs.readActive(path)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  local name = path:match("[^/\\]+$") or "preview.png"
  local okFd, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not (okFd and fileData) then return nil end
  local okImg, img = pcall(love.graphics.newImage, fileData)
  return okImg and img or nil
end

-- MapPreview / Assets.image go through love.filesystem. Gold (and Blue/Yellow)
-- tiles live under gold/assets/generated/…; if the PhysFS overlay is missing,
-- newImage("assets/generated/…") fails and world view draws an empty box.
local assetsWrapped = false
function Preview.installAssetCacheFallback()
  if assetsWrapped then return end
  local ok, Assets = pcall(require, "src.render.Assets")
  if not (ok and Assets and type(Assets.image) == "function") then return end
  assetsWrapped = true
  local origImage, origData = Assets.image, Assets.imageData
  local imgCache = {}
  function Assets.image(path)
    local okI, img = pcall(origImage, path)
    if okI and img then return img end
    if imgCache[path] ~= nil then return imgCache[path] end
    local loaded = imageFromCacheBytes(path)
    imgCache[path] = loaded
    if loaded then return loaded end
    if not okI then error(img) end
    return img
  end
  if type(origData) == "function" then
    function Assets.imageData(path)
      local okD, data = pcall(origData, path)
      if okD and data then return data end
      local okC, CacheFs = pcall(require, "src.import.CacheFs")
      if okC and CacheFs and CacheFs.readActive then
        local bytes = CacheFs.readActive(path)
        if type(bytes) == "string" and bytes ~= "" then
          local name = tostring(path):match("[^/\\]+$") or "tile.png"
          local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
          if okFd and fd then
            local okId, id = pcall(love.image.newImageData, fd)
            if okId then return id end
          end
        end
      end
      if not okD then error(data) end
      return data
    end
  end
end

function Preview.image(S, path)
  if type(path) ~= "string" or path == "" then return nil end
  local key = cacheKey(S, path)
  if cache[key] ~= nil then
    return cache[key] or nil
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then
    cache[key] = false
    return nil
  end
  local img
  if kind == "love" then
    local ok, Assets = pcall(require, "src.render.Assets")
    if ok and Assets and Assets.image then
      local ok2, result = pcall(Assets.image, resolved)
      if ok2 then img = result end
    end
    if not img then
      img = imageFromCacheBytes(path)
    end
    if not img then
      local ok3, result = pcall(love.graphics.newImage, resolved)
      if ok3 then img = result end
    end
  else
    local cap = isGeneratedAtlas(path) and MAX_ATLAS_BYTES or MAX_PREVIEW_BYTES
    local loaded, err = loadFromDisk(resolved, cap)
    img = loaded
    if not loaded and err then
      Preview._lastError = err .. " (" .. path .. ")"
    end
  end
  cache[key] = img or false
  return img
end

function Preview.invalidate()
  cache = {}
  Preview._rev = (Preview._rev or 0) + 1
end

-- Drop only keys that mention this relative/absolute path (avoids reloading
-- every party icon after one sprite import).
function Preview.invalidatePath(path)
  if type(path) ~= "string" or path == "" then
    Preview.invalidate()
    return
  end
  local needle = path:gsub("\\", "/")
  local base = needle:match("([^/]+)$") or needle
  for key in pairs(cache) do
    local k = tostring(key):gsub("\\", "/")
    if k:find(needle, 1, true) or (base and k:find(base, 1, true)) then
      cache[key] = nil
    end
  end
end

function Preview.lastError()
  return Preview._lastError
end

-- Normalize a palette record / colors table to 4×{r,g,b} 0–255.
local function normalizeColors(rec)
  if type(rec) ~= "table" then return nil end
  local cols = rec.colors or rec
  if type(cols) ~= "table" or type(cols[1]) ~= "table" then return nil end
  local out = {}
  for i = 1, 4 do
    local c = cols[i] or { 0, 0, 0 }
    if c.r then out[i] = { c.r, c.g, c.b }
    else out[i] = { c[1] or 0, c[2] or 0, c[3] or 0 }
    end
  end
  return out
end

-- Editor preview: use pokered-gbc pack colors (default ON). When OFF, resolve
-- from ROM/cache SGB palettes only. Persisted in DataSource prefs.
function Preview.useGbcPalettes(S)
  if S and S.useGbcPalettes ~= nil then
    return S.useGbcPalettes and true or false
  end
  local prefs = S and S.dataPrefs
  if prefs and prefs.useGbcPalettes ~= nil then
    return prefs.useGbcPalettes and true or false
  end
  return true
end

-- Push project.gbcWorld overrides into PaletteFX and sync COLORS mode so
-- map preview uses ADVANCED (redpp) per-tile GBC baking when GBC is ON.
function Preview.syncGbcWorldRuntime(S)
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not (ok and PaletteFX) then return end
  WorldPaletteOverrides.install(PaletteFX)
  local use = Preview.useGbcPalettes(S)
  local pack = use and PaletteFX.gbcPack and PaletteFX.gbcPack()
  local ver = S and S.version
  -- Yellow has no pokered-gbc world pack. ADVANCED/redpp on Yellow whites
  -- out the player and draws opaque boxes behind houses.
  if ver == "yellow" then
    if PaletteFX.setWorldGroupOverrides then
      PaletteFX.setWorldGroupOverrides(nil)
    end
    if PaletteFX.setMode then PaletteFX.setMode(use and "ogred" or "gbc") end
  elseif use and pack then
    if PaletteFX.setMode then PaletteFX.setMode("redpp") end
    local gw = S and S.project and S.project.gbcWorld
    local groups = gw and gw.groupColors
    if PaletteFX.setWorldGroupOverrides then
      PaletteFX.setWorldGroupOverrides(groups)
    end
  else
    if PaletteFX.setWorldGroupOverrides then
      PaletteFX.setWorldGroupOverrides(nil)
    end
    if PaletteFX.setMode then PaletteFX.setMode("gbc") end
  end
  pcall(function() require("src.world.MapLoader").invalidateAll() end)
  Preview.invalidate()
end

function Preview.setUseGbcPalettes(S, on)
  if not S then return end
  on = on and true or false
  S.useGbcPalettes = on
  S.dataPrefs = S.dataPrefs or {}
  S.dataPrefs.useGbcPalettes = on
  local ok, DataSource = pcall(require, "DataSource")
  if ok and DataSource and DataSource.savePrefs then
    local prefs = DataSource.loadPrefs and DataSource.loadPrefs() or {}
    prefs.useGbcPalettes = on
    if S.dataPrefs.mode then prefs.mode = S.dataPrefs.mode end
    if S.dataPrefs.recompRoot then prefs.recompRoot = S.dataPrefs.recompRoot end
    DataSource.savePrefs(prefs)
  end
  Preview.syncGbcWorldRuntime(S)
end

Preview.GBC_GROUP_NAMES = {
  "GRAY", "RED", "GREEN", "BLUE", "YELLOW", "BROWN", "ROOF", "TEXT",
}

function Preview.hasTilesetGbcGroups(S, tilesetId)
  if type(tilesetId) ~= "string" or tilesetId == "" then return false end
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if ok and PaletteFX then WorldPaletteOverrides.install(PaletteFX) end
  return ok and PaletteFX and PaletteFX.hasWorldTileset
    and PaletteFX.hasWorldTileset(tilesetId) and true or false
end

-- Effective 8×4 colors (project override merged over pack vanilla).
function Preview.tilesetGbcGroups(S, tilesetId)
  if not Preview.hasTilesetGbcGroups(S, tilesetId) then return nil end
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not (ok and PaletteFX and PaletteFX.vanillaWorldGroupColors) then
    return nil
  end
  local base = PaletteFX.vanillaWorldGroupColors(tilesetId)
  if not base then return nil end
  local owned = S and S.project and S.project.gbcWorld
    and S.project.gbcWorld.groupColors
    and S.project.gbcWorld.groupColors[tilesetId]
  if type(owned) ~= "table" then return base end
  local out = {}
  for i = 1, 8 do
    local g = owned[i]
    if type(g) == "table" and type(g[1]) == "table" then
      out[i] = normalizeColors({ colors = g }) or base[i]
    else
      out[i] = base[i]
    end
  end
  return out
end

function Preview.tilesetGbcGroupsOwned(S, tilesetId)
  local gw = S and S.project and S.project.gbcWorld
  return gw and gw.groupColors and gw.groupColors[tilesetId] ~= nil
end

-- Clone vanilla (or keep owned) into project so a color slot can be edited.
function Preview.ensureTilesetGbcGroups(S, tilesetId)
  if not S or not S.project or not Preview.hasTilesetGbcGroups(S, tilesetId) then
    return nil
  end
  local State = require("State")
  State.ensureProjectFields(S.project)
  S.project.gbcWorld = S.project.gbcWorld or { groupColors = {} }
  S.project.gbcWorld.groupColors = S.project.gbcWorld.groupColors or {}
  local owned = S.project.gbcWorld.groupColors[tilesetId]
  if owned then return owned end
  local groups = Preview.tilesetGbcGroups(S, tilesetId)
  if not groups then return nil end
  local copy = {}
  for i = 1, 8 do
    local g = groups[i]
    copy[i] = {}
    for c = 1, 4 do
      local col = g[c] or { 0, 0, 0 }
      copy[i][c] = { col[1] or 0, col[2] or 0, col[3] or 0 }
    end
  end
  S.project.gbcWorld.groupColors[tilesetId] = copy
  return copy
end

function Preview.setTilesetGbcGroupColor(S, tilesetId, groupIndex, colorIndex, rgb)
  local owned = Preview.ensureTilesetGbcGroups(S, tilesetId)
  if not owned then return false end
  local gi = tonumber(groupIndex) or 0
  local ci = tonumber(colorIndex) or 0
  if gi < 1 or gi > 8 or ci < 1 or ci > 4 then return false end
  owned[gi] = owned[gi] or {}
  owned[gi][ci] = {
    math.max(0, math.min(255, tonumber(rgb and rgb[1]) or 0)),
    math.max(0, math.min(255, tonumber(rgb and rgb[2]) or 0)),
    math.max(0, math.min(255, tonumber(rgb and rgb[3]) or 0)),
  }
  Preview.syncGbcWorldRuntime(S)
  return true
end

function Preview.clearTilesetGbcGroups(S, tilesetId)
  local gw = S and S.project and S.project.gbcWorld
  if not (gw and gw.groupColors and tilesetId) then return false end
  if gw.groupColors[tilesetId] == nil then return false end
  gw.groupColors[tilesetId] = nil
  Preview.syncGbcWorldRuntime(S)
  return true
end

-- Gold overworld OBJ row for a PAL_OW_* name or 0-based paletteId.
-- Uses project.palettes.objects.DAY when the mod owns that TOD set.
local OW_PALETTE_ID = {
  PAL_OW_RED = 1, PAL_OW_BLUE = 2, PAL_OW_GREEN = 3, PAL_OW_BROWN = 4,
  PAL_OW_PINK = 5, PAL_OW_EMOTE = 6, PAL_OW_TREE = 7, PAL_OW_ROCK = 8,
}

function Preview.gen2ObjectPalette(S, paletteNameOrId)
  local pals = S and S.data and (S.data.palettes or S.data.gen2Palettes)
  local set = pals and pals.objects and pals.objects.DAY
  local projObj = S and S.project and S.project.palettes
    and S.project.palettes.objects
  if type(projObj) == "table" and type(projObj.DAY) == "table" then
    set = projObj.DAY
  end
  if type(set) ~= "table" then return nil end
  local idx
  if type(paletteNameOrId) == "string" and paletteNameOrId ~= "" then
    idx = OW_PALETTE_ID[paletteNameOrId]
  elseif type(paletteNameOrId) == "number" then
    idx = paletteNameOrId + 1
  end
  idx = idx or 1
  local row = set[idx]
  if type(row) ~= "table" then return nil end
  return normalizeColors({ colors = row })
end

-- Sorted palette ids (ROM/cache, optional GBC/Yellow packs, project extras).
-- With useGbcPalettes OFF and no ROM cache, the list may be project-only.
-- Gold: flat SGB names are absent — returns project-only flat keys (Gen2 UI
-- uses context lists instead of this helper).
function Preview.paletteIds(S)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local function addTable(order, pals)
    if type(order) == "table" then
      for _, id in ipairs(order) do add(id) end
    end
    if type(pals) == "table" then
      local extra = {}
      for id in pairs(pals) do
        if not seen[id] then extra[#extra + 1] = id end
      end
      table.sort(extra)
      for _, id in ipairs(extra) do add(id) end
    end
  end
  local data = S and S.data and S.data.palettes
  if Preview.useGbcPalettes(S) then
    local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
    -- Hardware GBC (Red/Blue boot ROM) and Yellow CGBBasePalettes first so
    -- they are pickable without scrolling past SGB / Red++ names.
    add("OG_RED")
    add("OG_BLUE")
    if ok and PaletteFX and PaletteFX.yellowPack then
      local yel = PaletteFX.yellowPack()
      if yel and type(yel.cgbBase) == "table" then
        if type(yel.order) == "table" then
          for _, id in ipairs(yel.order) do
            if yel.cgbBase[id] then add("CGB_" .. id) end
          end
        end
        local extra = {}
        for id in pairs(yel.cgbBase) do
          if type(id) == "string" and not seen["CGB_" .. id] then
            extra[#extra + 1] = id
          end
        end
        table.sort(extra)
        for i = 1, #extra do add("CGB_" .. extra[i]) end
      end
    end
  end
  -- Gen1 nested .palettes map; Gold's table is context-keyed (no .palettes).
  addTable(data and data.order, data and data.palettes)
  if Preview.useGbcPalettes(S) then
    local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
    if ok and PaletteFX and PaletteFX.gbcPack then
      local pack = PaletteFX.gbcPack()
      if pack then addTable(pack.order, pack.palettes) end
    end
    if ok and PaletteFX and PaletteFX.yellowPack then
      local pack = PaletteFX.yellowPack()
      if pack then addTable(pack.order, pack.palettes) end
    end
  end
  if S and S.project and S.project.palettes then
    local extra = {}
    for id in pairs(S.project.palettes) do
      if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do add(id) end
  end
  return ids
end

local function rbyGbcColors(name)
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not (ok and PaletteFX) then return nil end
  if name == "OG_RED" then return normalizeColors(PaletteFX.GBC_BG) end
  if name == "OG_BLUE" then return normalizeColors(PaletteFX.GBC_BG_BLUE) end
  local cgb = name:match("^CGB_(.+)$")
  if not cgb then return nil end
  local pack = PaletteFX.yellowPack and PaletteFX.yellowPack()
  local y = pack and pack.cgbBase and pack.cgbBase[cgb]
  if y then return normalizeColors(y) end
  return nil
end

-- Resolve named palette colors (project override wins).
-- GBC ON: GBC pack before ROM/cache. GBC OFF: ROM/cache only.
function Preview.paletteColors(S, name)
  if type(name) ~= "string" or name == "" then return nil end
  if S and S.project and S.project.palettes and S.project.palettes[name] then
    local cols = normalizeColors(S.project.palettes[name])
    if cols then return cols end
  end
  local rby = rbyGbcColors(name)
  if rby then return rby end
  local useGbc = Preview.useGbcPalettes(S)
  if useGbc then
    local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
    if ok and PaletteFX and PaletteFX.gbcPack then
      local pack = PaletteFX.gbcPack()
      local g = pack and pack.palettes and pack.palettes[name]
      if g then return normalizeColors(g) end
    end
    if ok and PaletteFX and PaletteFX.yellowPack then
      local pack = PaletteFX.yellowPack()
      local y = pack and pack.palettes and pack.palettes[name]
      if y then return normalizeColors(y) end
    end
  end
  local data = S and S.data and S.data.palettes and S.data.palettes.palettes
  if data and data[name] then return normalizeColors(data[name]) end
  return nil
end

local DEFAULT_PAL_COLORS = {
  { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
}

-- Clone a named palette into project.palettes so its four colors can be edited.
-- Returns the owned record (with .colors), or nil if name is empty.
function Preview.ensureProjectPalette(S, name)
  if type(name) ~= "string" or name == "" or not S or not S.project then
    return nil
  end
  S.project.palettes = S.project.palettes or {}
  local owned = S.project.palettes[name]
  if owned then
    local cols = normalizeColors(owned)
    if not cols then
      cols = Preview.paletteColors(S, name) or DEFAULT_PAL_COLORS
      owned.colors = {}
      for i = 1, 4 do
        local c = cols[i] or DEFAULT_PAL_COLORS[i]
        owned.colors[i] = { c[1] or 0, c[2] or 0, c[3] or 0 }
      end
    end
    return owned
  end
  local src = Preview.paletteColors(S, name) or DEFAULT_PAL_COLORS
  local colors = {}
  for i = 1, 4 do
    local c = src[i] or DEFAULT_PAL_COLORS[i]
    colors[i] = { c[1] or 0, c[2] or 0, c[3] or 0 }
  end
  local vanilla = S.data and S.data.palettes and S.data.palettes.palettes
    and S.data.palettes.palettes[name]
  S.project.palettes[name] = { colors = colors, _isNew = not vanilla }
  return S.project.palettes[name]
end

Preview.GEN2_MAP_PALETTES = {
  "PALETTE_AUTO", "PALETTE_DAY", "PALETTE_NITE", "PALETTE_MORN", "PALETTE_DARK",
}
Preview.GEN2_TOD = { "MORN", "DAY", "NITE", "DARK" }

-- Johto/Kanto overworld sheets are authored against TOWN/ROUTE BG slots.
-- Baking them with an INDOOR environment (house maps painted with outdoor
-- tiles) produces the oversaturated grass / pink path look.
local OUTDOOR_TILESETS = {
  TILESET_JOHTO = true,
  TILESET_JOHTO_MODERN = true,
  TILESET_KANTO = true,
  TILESET_PARK = true,
  TILESET_FOREST = true,
  TILESET_BATTLE_TOWER_OUTSIDE = true,
}
local INDOOR_ENV = {
  INDOOR = true, CAVE = true, DUNGEON = true, GATE = true,
}

function Preview.gen2BakeMap(map, tilesetId)
  if type(map) ~= "table" then return map end
  tilesetId = tilesetId or map.tileset
  if OUTDOOR_TILESETS[tilesetId] and INDOOR_ENV[map.environment] then
    return setmetatable({ environment = "TOWN" }, { __index = map })
  end
  return map
end

-- Editor ToD pin for Gold map preview (nil / AUTO = follow map.palette + clock).
-- TileRenderer may call this without S; Maps syncs S.mapPreviewTod onto
-- Preview._gen2PreviewTod before MapLoader.load.
function Preview.syncGen2Preview(S)
  Preview._gen2PreviewTod = S and S.mapPreviewTod or nil
  Preview._gen2PreviewHour = S and S.mapPreviewHour or nil
end

function Preview.gen2PreviewDaytime(S, mapDef)
  local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
  if not (okP and Palettes and Palettes.daytimeFor) then return "DAY" end
  local pin = (S and S.mapPreviewTod) or Preview._gen2PreviewTod
  if type(pin) == "string" and pin ~= "" and pin ~= "AUTO" then
    return pin
  end
  local hour = (S and S.mapPreviewHour) or Preview._gen2PreviewHour
  return Palettes.daytimeFor(mapDef, hour, false) or "DAY"
end

local function cloneRgbRow(row, n)
  local out = {}
  for i = 1, n do
    local c = row and row[i] or { 0, 0, 0 }
    out[i] = { c[1] or 0, c[2] or 0, c[3] or 0 }
  end
  return out
end

-- Project BG / roof patches over the ROM cache tables Palettes.bgSet reads.
function Preview.gen2EffectivePals(S, pals)
  if type(pals) ~= "table" then return pals end
  local proj = S and S.project and S.project.palettes
  if type(proj) ~= "table" then return pals end
  if not proj.bg and not proj.roofs and not proj.environments then
    return pals
  end
  local roofs = pals.roofs
  if type(proj.roofs) == "table" then
    roofs = {}
    if type(pals.roofs) == "table" then
      for k, v in pairs(pals.roofs) do roofs[k] = v end
    end
    for k, v in pairs(proj.roofs) do roofs[k] = v end
  end
  return {
    bg = proj.bg or pals.bg,
    environments = proj.environments or pals.environments,
    roofs = roofs,
    roofSlot = pals.roofSlot,
    objects = pals.objects,
  }
end

function Preview.ensureGen2BgPool(S)
  if not (S and S.project) then return nil end
  S.project.palettes = S.project.palettes or {}
  if type(S.project.palettes.bg) == "table" then return S.project.palettes.bg end
  local pals = S.data and (S.data.palettes or S.data.gen2Palettes)
  local base = pals and pals.bg
  if type(base) ~= "table" then return nil end
  local list = {}
  for i, row in ipairs(base) do
    list[i] = cloneRgbRow(row, 4)
  end
  S.project.palettes.bg = list
  return list
end

local function cloneBgSet(set)
  if type(set) ~= "table" then return nil end
  local out = {}
  for i = 1, 8 do
    out[i] = cloneRgbRow(set[i], 4)
  end
  return out
end

Preview.GEN2_DAYTIMES = { "MORN", "DAY", "NITE", "DARK" }

local function envRefKey(env, daytime)
  return "@" .. tostring(env) .. "/" .. tostring(daytime)
end

local function parseEnvRef(key)
  if type(key) ~= "string" then return nil end
  return key:match("^@([^/]+)/([A-Z]+)$")
end

function Preview.envBgSet(S, env, daytime)
  local pals = S and S.data and (S.data.palettes or S.data.gen2Palettes)
  pals = Preview.gen2EffectivePals(S, pals)
  if type(pals) ~= "table" then return nil end
  local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
  if not (okP and Palettes and Palettes.bgSet) then return nil end
  return Palettes.bgSet(pals, { environment = env, group = 0 }, daytime)
end

function Preview.mapBgAssignKey(S, mapId, daytime)
  local bag = S and S.project and S.project.mapBgAssign
  local rec = bag and mapId and bag[mapId]
  local key = rec and rec[daytime]
  if type(key) == "string" and key ~= "" then return key end
  return nil
end

function Preview.mapBgAssignLabel(S, mapId, daytime)
  local key = Preview.mapBgAssignKey(S, mapId, daytime)
  if not key then
    local legacy = S and S.project and S.project.mapBgSets
    if legacy and legacy[mapId] and type(legacy[mapId][daytime]) == "table" then
      return "Custom (this map)"
    end
    return "Default"
  end
  local env, srcTod = parseEnvRef(key)
  if env then return env .. " · " .. srcTod end
  return key
end

function Preview.setMapBgAssign(S, mapId, daytime, key)
  if not (S and S.project and type(mapId) == "string") then return false end
  S.project.mapBgAssign = S.project.mapBgAssign or {}
  S.project.mapBgAssign[mapId] = S.project.mapBgAssign[mapId] or {}
  if not key or key == "" or key == "default" then
    S.project.mapBgAssign[mapId][daytime] = nil
    if S.project.mapBgSets and S.project.mapBgSets[mapId] then
      S.project.mapBgSets[mapId][daytime] = nil
    end
    return true
  end
  S.project.mapBgAssign[mapId][daytime] = key
  return true
end

function Preview.mapBgOverride(S, mapId, daytime)
  local project = S and S.project
  if not project or not mapId then return nil end
  local key = Preview.mapBgAssignKey(S, mapId, daytime)
  if key then
    local env, srcTod = parseEnvRef(key)
    if env then return Preview.envBgSet(S, env, srcTod) end
    local named = project.namedBgSets and project.namedBgSets[key]
    if type(named) == "table" and type(named[1]) == "table" then return named end
  end
  local rec = project.mapBgSets and project.mapBgSets[mapId]
  local set = rec and rec[daytime]
  if type(set) == "table" and type(set[1]) == "table" then return set end
  return nil
end

local function uniqueNamedId(project, want)
  project.namedBgSets = project.namedBgSets or {}
  if project.namedBgSets[want] == nil then return want end
  local n = 2
  while project.namedBgSets[want .. "_" .. n] ~= nil do
    n = n + 1
  end
  return want .. "_" .. n
end

function Preview.createMapBgPalette(S, mapDef)
  local mapId = mapDef and mapDef.id
  if not (S and S.project and type(mapId) == "string") then return nil end
  local daytime = Preview.gen2PreviewDaytime(S, mapDef)
  local set = cloneBgSet(select(1, Preview.gen2MapBgSet(S, mapDef, daytime)))
  if not set then
    set = cloneBgSet(select(1, Preview.gen2MapBgSet(S, mapDef, daytime, true)))
  end
  if not set then return nil end
  local id = uniqueNamedId(S.project, mapId .. "_" .. daytime)
  S.project.namedBgSets[id] = set
  Preview.setMapBgAssign(S, mapId, daytime, id)
  return id
end

function Preview.applyExistingBgPalette(S, mapDef, choiceId)
  local mapId = mapDef and mapDef.id
  if not (S and S.project and type(mapId) == "string") then return false end
  local daytime = Preview.gen2PreviewDaytime(S, mapDef)
  if not choiceId or choiceId == "default" then
    return Preview.setMapBgAssign(S, mapId, daytime, nil)
  end
  local copyMap, copyTod = tostring(choiceId):match("^copy:([^:]+):([A-Z]+)$")
  if copyMap then
    local src = Preview.mapBgOverride(S, copyMap, copyTod)
    src = cloneBgSet(src)
    if not src then return false end
    local id = uniqueNamedId(S.project, mapId .. "_" .. daytime)
    S.project.namedBgSets = S.project.namedBgSets or {}
    S.project.namedBgSets[id] = src
    return Preview.setMapBgAssign(S, mapId, daytime, id)
  end
  return Preview.setMapBgAssign(S, mapId, daytime, choiceId)
end

function Preview.gen2BgPaletteChoices(S, mapId)
  local ids, labels = {}, {}
  local pals = S and S.data and (S.data.palettes or S.data.gen2Palettes)
  pals = Preview.gen2EffectivePals(S, pals)
  local envs, seen = {}, {}
  if type(pals) == "table" and type(pals.environments) == "table" then
    for env in pairs(pals.environments) do
      if type(env) == "string" then
        envs[#envs + 1] = env
        seen[env] = true
      end
    end
  end
  for _, env in ipairs({
    "TOWN", "ROUTE", "INDOOR", "CAVE", "ENVIRONMENT_5", "GATE", "DUNGEON",
  }) do
    if not seen[env] then envs[#envs + 1] = env end
  end
  table.sort(envs)
  for _, env in ipairs(envs) do
    for _, tod in ipairs(Preview.GEN2_DAYTIMES) do
      local key = envRefKey(env, tod)
      ids[#ids + 1] = key
      labels[key] = env .. " · " .. tod
    end
  end
  local named = S and S.project and S.project.namedBgSets
  if type(named) == "table" then
    local nids = {}
    for id, set in pairs(named) do
      if type(id) == "string" and type(set) == "table" then
        nids[#nids + 1] = id
      end
    end
    table.sort(nids)
    for _, id in ipairs(nids) do
      ids[#ids + 1] = id
      labels[id] = id
    end
  end
  local assign = S and S.project and S.project.mapBgAssign
  local legacy = S and S.project and S.project.mapBgSets
  local extras = {}
  local function addCopy(mid, tod)
    if mid == mapId then return end
    local key = "copy:" .. mid .. ":" .. tod
    if extras[key] then return end
    extras[key] = true
    ids[#ids + 1] = key
    labels[key] = mid .. " · " .. tod
  end
  if type(assign) == "table" then
    for mid, rec in pairs(assign) do
      if type(rec) == "table" then
        for _, tod in ipairs(Preview.GEN2_DAYTIMES) do
          if rec[tod] then addCopy(mid, tod) end
        end
      end
    end
  end
  if type(legacy) == "table" then
    for mid, rec in pairs(legacy) do
      if type(rec) == "table" then
        for _, tod in ipairs(Preview.GEN2_DAYTIMES) do
          if type(rec[tod]) == "table" then addCopy(mid, tod) end
        end
      end
    end
  end
  return ids, labels
end

function Preview.ensureMapBgSet(S, mapDef)
  local mapId = mapDef and mapDef.id
  if not (S and S.project and type(mapId) == "string") then return nil end
  local daytime = Preview.gen2PreviewDaytime(S, mapDef)
  local key = Preview.mapBgAssignKey(S, mapId, daytime)
  if key and not parseEnvRef(key) then
    local named = S.project.namedBgSets and S.project.namedBgSets[key]
    if type(named) == "table" then return named, daytime end
  end
  local rec = S.project.mapBgSets and S.project.mapBgSets[mapId]
  if rec and type(rec[daytime]) == "table" and not key then
    return rec[daytime], daytime
  end
  local id = Preview.createMapBgPalette(S, mapDef)
  return id and S.project.namedBgSets[id] or nil, daytime
end

-- Edit one swatch. Env / default assignments fork a palette for this map first.
function Preview.setGen2MapSwatch(S, mapDef, groupIndex, colorIndex, rgb)
  if not (S and type(mapDef) == "table") then return false end
  groupIndex = tonumber(groupIndex) or 0
  colorIndex = tonumber(colorIndex) or 0
  if groupIndex < 1 or groupIndex > 8 or colorIndex < 1 or colorIndex > 4 then
    return false
  end
  rgb = {
    math.max(0, math.min(255, tonumber(rgb and rgb[1]) or 0)),
    math.max(0, math.min(255, tonumber(rgb and rgb[2]) or 0)),
    math.max(0, math.min(255, tonumber(rgb and rgb[3]) or 0)),
  }
  local set = Preview.ensureMapBgSet(S, mapDef)
  if not set then return false end
  set[groupIndex] = set[groupIndex] or cloneRgbRow(nil, 4)
  set[groupIndex][colorIndex] = rgb
  return true
end

-- baker.palettes copy so MapPreview.bake can see a per-map ToD override.
function Preview.palsForMapPreview(S, pals, mapDef)
  pals = Preview.gen2EffectivePals(S, pals) or pals
  if type(pals) ~= "table" or type(mapDef) ~= "table" then return pals end
  local daytime = Preview.gen2PreviewDaytime(S, mapDef)
  local over = Preview.mapBgOverride(S, mapDef.id, daytime)
  if not over then return pals end
  local bg = {}
  if type(pals.bg) == "table" then
    for i, row in ipairs(pals.bg) do bg[i] = row end
  end
  local indices = {}
  for i = 1, 8 do
    bg[#bg + 1] = cloneRgbRow(over[i], 4)
    indices[i] = #bg
  end
  local envName = mapDef.environment or "TOWN"
  local environments = {}
  if type(pals.environments) == "table" then
    for k, v in pairs(pals.environments) do environments[k] = v end
  end
  local row = {}
  local prev = pals.environments
    and (pals.environments[envName] or pals.environments.TOWN)
  if type(prev) == "table" then
    for k, v in pairs(prev) do row[k] = v end
  end
  row[daytime] = indices
  environments[envName] = row
  return {
    bg = bg,
    environments = environments,
    roofs = pals.roofs,
    roofSlot = pals.roofSlot,
    objects = pals.objects,
  }
end

-- Eight BG palettes for a Gold map at the preview daytime (roof folded in).
-- skipOverride: resolve the shared environment set (used when forking a map).
function Preview.gen2MapBgSet(S, mapDef, daytime, skipOverride)
  if type(mapDef) ~= "table" then
    local mapId = S and (S.builderMapId or S.mapId)
    if mapId then
      mapDef = S.project and S.project.maps and S.project.maps[mapId]
      if type(mapDef) ~= "table" then
        local okG, Generation = pcall(require, "Generation")
        if okG and Generation and Generation.dataMaps then
          mapDef = Generation.dataMaps(S)[mapId]
        end
      end
    end
  end
  if type(mapDef) ~= "table" then return nil, daytime end
  daytime = daytime or Preview.gen2PreviewDaytime(S, mapDef)
  if not skipOverride then
    local over = Preview.mapBgOverride(S, mapDef.id, daytime)
    if over then return over, daytime end
  end
  local data = S and S.data
  local pals = data and (data.palettes or data.gen2Palettes)
  pals = Preview.gen2EffectivePals(S, pals)
  if type(pals) ~= "table" then return nil, daytime end
  local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
  if not (okP and Palettes and Palettes.bgSet) then return nil, daytime end
  local set = Palettes.bgSet(pals, mapDef, daytime)
  if set and daytime == "DARK" and Palettes.withCaveFlicker then
    set = Palettes.withCaveFlicker(set, 1)
  end
  return set, daytime
end

local function isGen2Session(S)
  local ok, Generation = pcall(require, "Generation")
  if ok and Generation and Generation.isGen2 then
    return Generation.isGen2(S)
  end
  local okG, GameVersion = pcall(require, "src.core.GameVersion")
  return okG and GameVersion and GameVersion.generation
    and GameVersion.generation() == 2
end

-- Effective map palette name (map.palette or FieldDefaults cascade).
function Preview.mapPaletteName(S, map)
  if type(map) ~= "table" then
    return isGen2Session(S) and "PALETTE_AUTO" or "ROUTE"
  end
  if type(map.palette) == "string" and map.palette ~= "" then
    return map.palette
  end
  if isGen2Session(S) then return "PALETTE_AUTO" end
  local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  local pals = ok and FieldDefaults and FieldDefaults.FIELD and FieldDefaults.FIELD.palettes
  if not pals then return "ROUTE" end
  local mid = map.id
  if mid and pals.byMap and pals.byMap[mid] then return pals.byMap[mid] end
  local ts = map.tileset
  if ts and pals.byTileset and pals.byTileset[ts] then return pals.byTileset[ts] end
  if mid and type(pals.byPrefix) == "table" then
    for _, row in ipairs(pals.byPrefix) do
      if row.prefix and mid:sub(1, #row.prefix) == row.prefix then
        return row.palette or pals.default or "ROUTE"
      end
    end
  end
  return pals.default or "ROUTE"
end

-- Species battle palette name (authored → pack → MEWMON).
-- Gold stores GBC { normal, shiny } tables under palettes.pokemon[species];
-- those are not SGB named palettes, so fall through to MEWMON for swatches.
function Preview.monPaletteName(S, mon, speciesId)
  if mon and type(mon.palette) == "string" and mon.palette ~= "" then
    return mon.palette
  end
  local sid = speciesId or (mon and mon.id)
  local poke = S and S.data and S.data.palettes and S.data.palettes.pokemon
  if sid and poke and type(poke[sid]) == "string" and poke[sid] ~= "" then
    return poke[sid]
  end
  return "MEWMON"
end

-- Gold: white + 2 mid colors from palettes.pokemon[species].normal/shiny + black.
-- Project overrides merge over vanilla (partial shiny-only patches still work).
function Preview.gen2MonColors(S, speciesId, shiny)
  if type(speciesId) ~= "string" or speciesId == "" then return nil end
  local WHITE = { 255, 255, 255 }
  local BLACK = { 0, 0, 0 }
  local function entryFrom(bucket)
    return type(bucket) == "table" and bucket[speciesId] or nil
  end
  local function pairOf(entry, wantShiny)
    if type(entry) ~= "table" then return nil end
    local pair = (wantShiny and entry.shiny) or entry.normal
    if type(pair) == "table" and pair[1] and pair[2] then return pair end
    return nil
  end
  local data = S and S.data and (S.data.palettes or S.data.gen2Palettes)
  local vanilla = data and entryFrom(data.pokemon) or nil
  local proj = S and S.project and S.project.palettes
  local override = (type(proj) == "table") and entryFrom(proj.pokemon) or nil
  local pair = pairOf(override, shiny) or pairOf(vanilla, shiny)
  -- Shiny row missing → fall back to normal so preview never goes blank.
  if not pair and shiny then
    pair = pairOf(override, false) or pairOf(vanilla, false)
  end
  if not pair then return nil end
  local function rgb(c)
    if type(c) ~= "table" then return { 0, 0, 0 } end
    if c.r then return { c.r, c.g, c.b } end
    return { c[1] or 0, c[2] or 0, c[3] or 0 }
  end
  if pair[3] and pair[4] then
    return { rgb(pair[1]), rgb(pair[2]), rgb(pair[3]), rgb(pair[4]) }
  end
  return { WHITE, rgb(pair[1]), rgb(pair[2]), BLACK }
end

-- Vanilla Gold palettes.pokemon[species] row (nil when cache omitted palettes.lua).
function Preview.gen2MonPaletteEntry(S, speciesId)
  if type(speciesId) ~= "string" or speciesId == "" then return nil end
  local data = S and S.data and (S.data.palettes or S.data.gen2Palettes)
  local entry = data and data.pokemon and data.pokemon[speciesId]
  if type(entry) == "table" then return entry end
  local proj = S and S.project and S.project.palettes
  entry = proj and proj.pokemon and proj.pokemon[speciesId]
  return type(entry) == "table" and entry or nil
end

-- Trainer battle pic palette (MEWMON unless a named paletteSource matches).
function Preview.trainerPaletteName(S, tr)
  if tr and type(tr.paletteSource) == "string" and tr.paletteSource ~= "" then
    if Preview.paletteColors(S, tr.paletteSource) then
      return tr.paletteSource
    end
  end
  return "MEWMON"
end

-- Gold: white + 2 mid colors from palettes.trainers[class] + black.
-- Prefer project.palettes.trainers overrides when present.
function Preview.gen2TrainerColors(S, classId)
  if type(classId) ~= "string" or classId == "" then return nil end
  local WHITE = { 255, 255, 255 }
  local BLACK = { 0, 0, 0 }
  local pair = nil
  local proj = S and S.project and S.project.palettes
  if type(proj) == "table" and type(proj.trainers) == "table" then
    pair = proj.trainers[classId]
  end
  if not (pair and pair[1] and pair[2]) then
    local data = S and S.data and (S.data.palettes or S.data.gen2Palettes)
    pair = data and data.trainers and data.trainers[classId]
  end
  if not (pair and pair[1] and pair[2]) then return nil end
  local function rgb(c)
    if type(c) ~= "table" then return { 0, 0, 0 } end
    if c.r then return { c.r, c.g, c.b } end
    return { c[1] or 0, c[2] or 0, c[3] or 0 }
  end
  return { WHITE, rgb(pair[1]), rgb(pair[2]), BLACK }
end

-- Value for Preview.draw: Gen2 color row, else SGB palette name.
function Preview.trainerPalette(S, tr)
  if tr and tr.trueColor then return false end
  if isGen2Session(S) then
    if tr and type(tr.paletteSource) == "string" and tr.paletteSource ~= "" then
      if Preview.paletteColors(S, tr.paletteSource) then
        return tr.paletteSource
      end
    end
    local id = tr and (tr.id or tr.classId or tr.class)
    return Preview.gen2TrainerColors(S, id) or false
  end
  return Preview.trainerPaletteName(S, tr)
end

function Preview.drawSwatches(colors, x, y, w, h)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  w = w or (80 * s)
  h = h or (16 * s)
  colors = colors or {}
  local sw = w / 4
  for i = 1, 4 do
    local c = colors[i] or { 40, 40, 40 }
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", x + (i - 1) * sw, y, sw - 2 * s, h, 4 * s, 4 * s)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draw named-palette swatches (no-op if unknown). Returns height used.
function Preview.drawNamedSwatches(S, name, x, y, w, h)
  local colors = Preview.paletteColors(S, name)
  if not colors then return 0 end
  Preview.drawSwatches(colors, x, y, w, h)
  return h or 16
end

-- Live SGB shade-remap for grayscale draw calls (map canvas / block thumbs).
-- Callers skip this when the sheet is already RGB (TrueColor / Gold bake /
-- TileRenderer.gbcAtlas). Do not gate on PaletteFX.usesGbcPack(): that mode
-- only means "try GBC atlas"; if the atlas did not bake, maps stay 2bpp and
-- still need this shader.
function Preview.pushPaletteShader(S, nameOrColors)
  local colors = nameOrColors
  if type(nameOrColors) == "string" then
    colors = Preview.paletteColors(S, nameOrColors)
  end
  if type(colors) ~= "table" then return false end
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not (ok and PaletteFX and PaletteFX.shader and PaletteFX.sendColors) then
    return false
  end
  local sh = PaletteFX.shader()
  if not sh then return false end
  PaletteFX.sendColors(sh, colors)
  love.graphics.setShader(sh)
  return true
end

function Preview.popPaletteShader(pushed)
  if pushed then love.graphics.setShader() end
end

local function loadImageData(S, path)
  if not (love and love.image and love.image.newImageData) then return nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, id = pcall(Assets.imageData, path)
    if ok and id then return id end
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then return nil end
  if kind == "disk" then
    local f = io.open(resolved, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    if not bytes or #bytes == 0 then return nil end
    local name = resolved:match("[^/\\]+$") or "preview.png"
    local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
    if not (okFd and fd) then return nil end
    local okId, id = pcall(love.image.newImageData, fd)
    return okId and id or nil
  end
  local ok, id = pcall(love.image.newImageData, resolved)
  return ok and id or nil
end

local function flattenBgSet(bgSet)
  if not bgSet then return nil end
  local colors, seen = {}, {}
  for slot = 1, 8 do
    local pal = bgSet[slot]
    if pal then
      for i = 1, 4 do
        local c = pal[i]
        if c then
          local r = math.floor(c[1] or 0)
          local g = math.floor(c[2] or 0)
          local b = math.floor(c[3] or 0)
          local key = r * 65536 + g * 256 + b
          if not seen[key] then
            seen[key] = true
            colors[#colors + 1] = { r, g, b }
          end
        end
      end
    end
  end
  return #colors > 0 and colors or nil
end

local function snapImageDataToGbc(data, colors)
  if not (data and data.mapPixel and colors and #colors > 0) then return end
  data:mapPixel(function(_, _, r, g, b, a)
    if a <= 0 then return r, g, b, a end
    local r8 = math.floor(r * 255 + 0.5)
    local g8 = math.floor(g * 255 + 0.5)
    local b8 = math.floor(b * 255 + 0.5)
    local best, br, bg, bb
    for i = 1, #colors do
      local c = colors[i]
      local dr, dg, db = r8 - c[1], g8 - c[2], b8 - c[3]
      local d = dr * dr + dg * dg + db * db
      if d == 0 then return c[1] / 255, c[2] / 255, c[3] / 255, a end
      if not best or d < best then
        best, br, bg, bb = d, c[1], c[2], c[3]
      end
    end
    if not br then return r, g, b, a end
    return br / 255, bg / 255, bb / 255, a
  end)
end

-- TrueColor PNG restamped onto this map's current ToD palettes.
function Preview.gen2TrueColorImage(S, path, mapDef)
  if type(path) ~= "string" or path == "" or type(mapDef) ~= "table" then
    return nil
  end
  local daytime = Preview.gen2PreviewDaytime(S, mapDef) or "DAY"
  local key = "g2tc:" .. cacheKey(S, path) .. "|" .. daytime
    .. "|" .. tostring(mapDef.id or mapDef.environment or "")
  if cache[key] ~= nil then return cache[key] or nil end
  local src = loadImageData(S, path)
  if not (src and src.clone) then
    cache[key] = false
    return nil
  end
  local okClone, data = pcall(src.clone, src)
  if src.release then pcall(src.release, src) end
  if not (okClone and data) then
    cache[key] = false
    return nil
  end
  local pals = S and S.data and (S.data.palettes or S.data.gen2Palettes)
  local okP, Palettes = pcall(require, "src.world.gen2.Palettes")
  local okG, GbcPalette = pcall(require, "src.render.GbcPalette")
  local img
  if pals and okP and Palettes and Palettes.bgSet then
    local bakeMap = Preview.gen2BakeMap(mapDef, mapDef.tileset)
    snapImageDataToGbc(data, flattenBgSet(Palettes.bgSet(pals, bakeMap, "DAY")))
    local swap = Palettes.trueColorSwapTable
      and Palettes.trueColorSwapTable(pals, bakeMap, daytime)
    if swap and okG and GbcPalette and GbcPalette.recolorImage then
      img = GbcPalette.recolorImage(swap, data)
    end
    if not img then
      snapImageDataToGbc(data, flattenBgSet(Palettes.bgSet(pals, bakeMap, daytime)))
    end
  end
  if not img and love and love.graphics and love.graphics.newImage then
    local okImg, result = pcall(love.graphics.newImage, data)
    img = okImg and result or nil
  end
  if data.release then pcall(data.release, data) end
  if img and img.setFilter then img:setFilter("nearest", "nearest") end
  cache[key] = img or false
  return img
end

-- CPU shade-remap like BattleState.getImage (DMG r → palette color).
function Preview.imageWithPalette(S, path, colorsOrName)
  if type(path) ~= "string" or path == "" then return nil end
  local colors = colorsOrName
  local palName = nil
  if type(colorsOrName) == "string" then
    palName = colorsOrName
    colors = Preview.paletteColors(S, colorsOrName)
  end
  if type(colors) ~= "table" then return Preview.image(S, path) end
  local key = cacheKey(S, path) .. "#pal:" .. (palName or table.concat({
    colors[1][1], colors[1][2], colors[1][3],
    colors[2][1], colors[2][2], colors[2][3],
    colors[3][1], colors[3][2], colors[3][3],
    colors[4][1], colors[4][2], colors[4][3],
  }, ","))
  if cache[key] ~= nil then return cache[key] or nil end
  local data = loadImageData(S, path)
  if not data then
    cache[key] = Preview.image(S, path) or false
    return cache[key] or nil
  end
  local c = colors
  local okMap = pcall(function()
    data:mapPixel(function(_, _, r, g, b, a)
      if a == 0 then return r, g, b, a end
      local col = r > 0.83 and c[1] or r > 0.5 and c[2]
                  or r > 0.17 and c[3] or c[4]
      return (col[1] or 0) / 255, (col[2] or 0) / 255, (col[3] or 0) / 255, a
    end)
  end)
  if not okMap then
    cache[key] = Preview.image(S, path) or false
    return cache[key] or nil
  end
  local okImg, baked = pcall(love.graphics.newImage, data)
  cache[key] = (okImg and baked) or false
  return cache[key] or nil
end

-- Draw image fitted into maxW x maxH.  Optional paletteNameOrColors tints
-- DMG grayscale PNGs with an SGB 4-color palette.
-- Pass false/nil to skip remap (trueColor art).  Returns height consumed.
function Preview.draw(S, path, x, y, maxW, maxH, paletteNameOrColors)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  maxW = maxW or (96 * s)
  maxH = maxH or (96 * s)

  -- false = explicit trueColor opt-out (same as nil).
  if paletteNameOrColors == false then paletteNameOrColors = nil end

  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, maxW, maxH, 8 * s, 8 * s)

  -- Prefer live shader tint so TrueColor toggles update immediately on the
  -- same base image; fall back to a CPU bake when the shader is unavailable
  -- (headless / ADVANCED pack skips the shade remap).
  local img = Preview.image(S, path)
  local shaded = false
  if paletteNameOrColors then
    shaded = Preview.pushPaletteShader(S, paletteNameOrColors)
    if not shaded then
      img = Preview.imageWithPalette(S, path, paletteNameOrColors) or img
    end
  else
    -- Clear a leaked zone shader so raw trueColor pixels are not remapped.
    if love and love.graphics and love.graphics.setShader then
      love.graphics.setShader()
    end
  end

  if not img then
    love.graphics.setColor(1, 1, 1, 1)
    local msg = (path and path ~= "") and "no image" or "no path"
    if KitOk then
      Kit.text("micro", msg, x + 8 * s, y + maxH / 2 - 6 * s, PAL.faint)
    end
    Preview.popPaletteShader(shaded)
    return maxH
  end

  local iw, ih = img:getWidth(), img:getHeight()
  local scale = math.min(maxW / iw, maxH / ih)
  local dw, dh = iw * scale, ih * scale
  local dx = x + (maxW - dw) / 2
  local dy = y + (maxH - dh) / 2
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, dx, dy, 0, scale, scale)
  Preview.popPaletteShader(shaded)
  return maxH
end

Preview.drawWithPalette = Preview.draw

-- Trainer pic: prefer pic path, else basePic trainer's pic.
-- Gold: class pics live in gen2MenuGfx.battleHud.trainerPics[CLASS], not on
-- the trainers.lua record (schema gen2Fields has no `pic`).
function Preview.trainerPicPath(S, tr)
  if not tr then return nil end
  if type(tr.pic) == "string" and tr.pic ~= "" then return tr.pic end
  if isGen2Session(S) then
    local classId = tr.id or tr.classId or tr.class
    local gfx = S and S.data and (S.data.gen2MenuGfx or S.data.menu_gfx)
    local pics = gfx and gfx.battleHud and gfx.battleHud.trainerPics
    if type(classId) == "string" and type(pics) == "table"
        and type(pics[classId]) == "string" and pics[classId] ~= "" then
      return pics[classId]
    end
    -- Fallback when menu_gfx is missing: extractor writes this path.
    if type(classId) == "string" and classId ~= "" then
      local guess = "assets/generated/battle/trainers/"
        .. classId:lower() .. ".png"
      if Preview.resolve(S, guess) then return guess end
    end
    return nil
  end
  local baseId = tr.basePic
  if baseId and S.data and S.data.trainers and S.data.trainers[baseId] then
    return S.data.trainers[baseId].pic
  end
  if baseId and S.project and S.project.trainers and S.project.trainers[baseId] then
    return S.project.trainers[baseId].pic
  end
  return nil
end

function Preview.pokemonFront(S, mon)
  if not mon then return nil end
  return mon.spriteFront
end

local function spriteDef(S, spriteId)
  local sprites = S and S.data and S.data.sprites
  local def = sprites and sprites[spriteId]
  if def then return def end
  local proj = S and S.project and S.project.sprites
  return proj and proj[spriteId] or nil
end

local function spriteImage(S, spriteId, fallback)
  local def = spriteDef(S, spriteId)
  if def and def.image then return def.image end
  return fallback
end

local function spritePalette(S, spriteId)
  local def = spriteDef(S, spriteId)
  local src = def and def.paletteSource
  if type(src) == "string" and src ~= "" and Preview.paletteColors(S, src) then
    return src
  end
  return nil
end

-- Category stand-in sprite id for an item (nil when a custom icon is set).
-- Gen1 editor helper only — Gold uses pack pocket art (see drawItemIcon).
local function itemCategorySpriteId(item)
  if not item then return nil end
  local entry = item.icon
  if type(entry) == "string" and entry ~= "" then return nil end
  if type(entry) == "table" and type(entry.image) == "string" and entry.image ~= "" then
    return nil
  end
  local id = tostring(item.id or "")
  local isBall = item.ball or id:find("_BALL$") or id == "SAFARI_BALL"
  if isBall then return "SPRITE_POKE_BALL" end
  if item.machine or id:match("^TM_") or id:match("^HM_") then
    return "SPRITE_CLIPBOARD"
  end
  if id:find("FOSSIL") or id == "OLD_AMBER" then return "SPRITE_FOSSIL" end
  if id == "POKEDEX" or id == "TOWN_MAP" then return "SPRITE_POKEDEX" end
  if id:find("_STONE$") then return "SPRITE_FOSSIL" end
  if item.keyItem or item.tossable == false then return "SPRITE_POKEDEX" end
  return "SPRITE_POKE_BALL"
end

local function menuGfxPack(S)
  local mg = S and S.data and (S.data.gen2MenuGfx or S.data.menu_gfx)
  return mg and mg.pack or nil
end

-- Gold ItemAttributes pocket (editor stand-in when pocket is missing).
function Preview.itemPocket(item)
  if type(item) ~= "table" then return "ITEM" end
  if type(item.pocket) == "string" and item.pocket ~= "" then
    return item.pocket
  end
  local id = tostring(item.id or "")
  if item.ball or id:find("_BALL$") or id == "SAFARI_BALL" or id == "PARK_BALL" then
    return "BALL"
  end
  if item.machine or item.teaches
      or id:match("^TM%d") or id:match("^HM%d")
      or id:match("^TM_") or id:match("^HM_") then
    return "TM_HM"
  end
  if item.keyItem or item.canToss == false then return "KEY_ITEM" end
  return "ITEM"
end

local GEN2_POCKET_FALLBACK = {
  ITEM = { 72, 152, 88 },
  BALL = { 200, 72, 72 },
  KEY_ITEM = { 72, 112, 200 },
  TM_HM = { 184, 144, 56 },
}

-- Draw the PackGFX bag picture for this item's pocket (Gold has no per-item
-- bag icons — PackMenu is pocket chrome + text).
local function drawGen2ItemPocketIcon(S, item, x, y, maxW, maxH)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  maxW = maxW or (48 * s)
  maxH = maxH or (48 * s)
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, maxW, maxH, 6 * s, 6 * s)

  local pack = menuGfxPack(S)
  local pocket = Preview.itemPocket(item)
  local path = pack and pack.pack
  local first = pack and pack.pocketPicture and pack.pocketPicture[pocket]
  local img = path and Preview.image(S, path) or nil
  if img and type(first) == "number" then
    local wide = pack.packTilesWide or 5
    local high = pack.packTilesHigh or 3
    local sw, sh = wide * 8, high * 8
    local sx, sy = 0, math.floor(first / wide) * 8
    local scale = math.min(maxW / sw, maxH / sh)
    local dw, dh = sw * scale, sh * scale
    local dx = x + (maxW - dw) / 2
    local dy = y + (maxH - dh) / 2
    local colors = pack.palettes and pack.palettes[6]
    local quad
    local okQ, q = pcall(love.graphics.newQuad, sx, sy, sw, sh,
      img:getWidth(), img:getHeight())
    if okQ then quad = q end
    local function body()
      love.graphics.setColor(1, 1, 1, 1)
      if quad then
        love.graphics.draw(img, quad, dx, dy, 0, scale, scale)
      else
        love.graphics.draw(img, dx, dy, 0, scale, scale)
      end
    end
    local shaded = type(colors) == "table"
      and Preview.pushPaletteShader(S, colors)
    body()
    Preview.popPaletteShader(shaded)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- Cache without pack art: pocket-colored chip + label.
  local c = GEN2_POCKET_FALLBACK[pocket] or GEN2_POCKET_FALLBACK.ITEM
  love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1)
  local inset = 6 * s
  love.graphics.rectangle("fill", x + inset, y + inset,
    maxW - 2 * inset, maxH - 2 * inset, 4 * s, 4 * s)
  love.graphics.setColor(1, 1, 1, 1)
  local label = (pocket == "KEY_ITEM" and "KEY")
    or (pocket == "TM_HM" and "TM")
    or pocket
  local Kit2Ok, Kit2 = pcall(require, "Kit")
  if Kit2Ok and Kit2.text then
    Kit2.text("micro", label, x + 4 * s, y + maxH / 2 - 6 * s, PAL.text)
  end
end

-- Item icon path: Gen1 custom/stand-in; Gold pack sheet (pocket crop in draw).
function Preview.itemIconPath(S, item)
  if type(item) ~= "table" then return nil end
  if isGen2Session(S) then
    local pack = menuGfxPack(S)
    return pack and pack.pack or nil
  end
  local entry = item.icon
  if type(entry) == "string" and entry ~= "" then return entry end
  if type(entry) == "table" and type(entry.image) == "string" and entry.image ~= "" then
    return entry.image
  end
  local id = tostring(item.id or "")
  local icons = S and S.data and S.data.icons and S.data.icons.icons
  local sid = itemCategorySpriteId(item)
  if sid == "SPRITE_POKE_BALL" and icons and icons.BALL then return icons.BALL end
  if (id:find("FOSSIL") or id == "OLD_AMBER") and icons and icons.HELIX then
    return icons.HELIX
  end
  if id:find("_STONE$") and icons and icons.FAIRY then return icons.FAIRY end
  local fallbacks = {
    SPRITE_POKE_BALL = "assets/generated/sprites/poke_ball.png",
    SPRITE_CLIPBOARD = "assets/generated/sprites/clipboard.png",
    SPRITE_FOSSIL = "assets/generated/sprites/fossil.png",
    SPRITE_POKEDEX = "assets/generated/sprites/pokedex.png",
  }
  return spriteImage(S, sid, fallbacks[sid] or "assets/generated/sprites/poke_ball.png")
end

-- Item icon palette: Gen1 SGB name; Gold has no per-item palette (pack pals).
function Preview.itemPaletteName(S, item)
  if isGen2Session(S) then return nil end
  if item and type(item.palette) == "string" and item.palette ~= "" then
    return item.palette
  end
  local sid = itemCategorySpriteId(item)
  return (sid and spritePalette(S, sid)) or "MEWMON"
end

-- paletteName: nil = item default; false = no remap (trueColor); string = id.
function Preview.drawItemIcon(S, item, x, y, maxW, maxH, paletteName)
  if isGen2Session(S) then
    return drawGen2ItemPocketIcon(S, item, x, y, maxW, maxH)
  end
  local pal
  if paletteName == false then
    pal = false
  elseif paletteName ~= nil then
    pal = paletteName
  elseif item and item.trueColor then
    pal = false
  elseif type(item and item.icon) == "table" and item.icon.trueColor then
    pal = false
  else
    pal = Preview.itemPaletteName(S, item)
  end
  return Preview.draw(S, Preview.itemIconPath(S, item), x, y, maxW, maxH, pal)
end

-- Party-menu icon path + built-in class name (name => bake OBP0 like PartyMenu).
-- Gold: icons.species[SPECIES] = "ICON_*" and icons.icons[ICON_*].image.
function Preview.pokemonIcon(S, mon, speciesId)
  if not mon and not speciesId then return nil, nil end
  local icons = S and S.data and (S.data.gen2Icons or S.data.icons)
  if not icons then return nil, nil end
  local id = speciesId or (mon and (mon.id or mon.species))
  local vanilla = id and S.data.pokemon and S.data.pokemon[id]
  local def = mon or vanilla
  local entry = (mon and mon.icon)
    or (icons.species and id and icons.species[id])
    or (icons.bySpecies and id and icons.bySpecies[id])
    or (vanilla and vanilla.icon)
  local name, path
  if type(entry) == "string" then
    name = entry
    local sheet = icons.icons and icons.icons[entry]
    if type(sheet) == "table" then
      path = sheet.image
    elseif type(sheet) == "string" then
      path = sheet
    end
  elseif type(entry) == "table" then
    path = entry.image
  end
  local dex = (mon and mon.dex) or (vanilla and vanilla.dex) or (def and def.dex)
  if not path and dex and icons.byDex then
    name = icons.byDex[dex]
    local sheet = name and icons.icons and icons.icons[name]
    if type(sheet) == "table" then
      path = sheet.image
    elseif type(sheet) == "string" then
      path = sheet
    end
  end
  return path, name
end

local function loadObpIcon(S, path)
  if not (love and love.image and love.image.newImageData) then
    return Preview.image(S, path)
  end
  local data
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, id = pcall(Assets.imageData, path)
    if ok then data = id end
  end
  if not data then
    local resolved, kind = Preview.resolve(S, path)
    if not resolved then return nil end
    if kind == "disk" then
      -- Absolute host paths: decode via FileData (same size guard as sprites).
      local img = select(1, loadFromDisk(resolved))
      return img
    end
    local ok, id = pcall(love.image.newImageData, resolved)
    if ok then data = id end
  end
  if not data then return Preview.image(S, path) end
  local okMap = pcall(function()
    data:mapPixel(function(_, _, r, _, _, a)
      local v = 0
      if r > 0.5 then v = 1
      elseif r > 0.17 then v = 170 / 255
      end
      return v, v, v, a
    end)
  end)
  if not okMap then return Preview.image(S, path) end
  local okImg, baked = pcall(love.graphics.newImage, data)
  return okImg and baked or nil
end

-- True when species / custom icon table opts out of SGB remap.
function Preview.pokemonIconTrueColor(S, mon, speciesId)
  if mon and mon.trueColor then return true end
  local entry = mon and mon.icon
  if type(entry) ~= "table" then
    local id = speciesId or (mon and (mon.id or mon.species))
    local icons = S and S.data and (S.data.gen2Icons or S.data.icons)
    entry = (icons and icons.species and id and icons.species[id])
      or (icons and icons.bySpecies and id and icons.bySpecies[id])
  end
  return type(entry) == "table" and entry.trueColor and true or false
end

-- Draw party icon. Built-in class names get the OBP0 shade bake, then an
-- optional SGB palette tint (species palette). Custom PNG icons remap
-- directly through the palette when one is provided.
-- paletteName: nil = species default; false = no remap (trueColor); string = that id.
function Preview.drawPokemonIcon(S, mon, x, y, maxW, maxH, speciesId, paletteName)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  maxW = maxW or (24 * s)
  maxH = maxH or (24 * s)
  local path, name = Preview.pokemonIcon(S, mon, speciesId)
  local pal
  if paletteName == false then
    pal = nil
  elseif paletteName == nil then
    if Preview.pokemonIconTrueColor(S, mon, speciesId) then
      pal = nil
    else
      pal = Preview.monPaletteName(S, mon, speciesId)
    end
  else
    pal = paletteName
  end
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, maxW, maxH, 6 * s, 6 * s)
  if not path then
    love.graphics.setColor(1, 1, 1, 1)
    if KitOk then
      Kit.text("micro", "?", x + maxW / 2 - 4 * s, y + maxH / 2 - 6 * s, PAL.faint)
    end
    return maxH, nil
  end
  -- Custom PNG icons go through Preview.draw (shader / CPU palette).
  if not name then
    return Preview.draw(S, path, x, y, maxW, maxH, pal or false), name
  end
  -- Built-in class icons: OBP0 shade-bake, then optional live SGB tint.
  local key = (S and S.path or "") .. "|icon|" .. path .. "#obp"
  if cache[key] == nil then
    cache[key] = loadObpIcon(S, path) or false
  end
  local img = cache[key]
  if not img then
    return Preview.draw(S, path, x, y, maxW, maxH, pal or false), name
  end
  local iw, ih = img:getWidth(), img:getHeight()
  -- Built-in icons are often 16x32 two-frame strips; show frame 1 (top).
  local srcH = ih
  if ih >= iw * 2 then srcH = math.floor(ih / 2) end
  local scale = math.min(maxW / iw, maxH / srcH)
  local dw, dh = iw * scale, srcH * scale
  local dx = x + (maxW - dw) / 2
  local dy = y + (maxH - dh) / 2
  love.graphics.setColor(1, 1, 1, 1)
  local shaded = false
  if pal then
    shaded = Preview.pushPaletteShader(S, pal)
    if not shaded then
      -- ADVANCED / no shader: CPU-bake a paletted variant.
      local ckey = key .. "#pal:" .. tostring(pal)
      if cache[ckey] == nil then
        cache[ckey] = Preview.imageWithPalette(S, path, pal) or img or false
      end
      img = cache[ckey] or img
    end
  elseif love and love.graphics and love.graphics.setShader then
    love.graphics.setShader()
  end
  if srcH < ih then
    local qkey = key .. "|q"
    if cache[qkey] == nil then
      local ok, q = pcall(love.graphics.newQuad, 0, 0, iw, srcH, iw, ih)
      cache[qkey] = ok and q or false
    end
    if cache[qkey] then
      love.graphics.draw(img, cache[qkey], dx, dy, 0, scale, scale)
    else
      love.graphics.draw(img, dx, dy, 0, scale, scale)
    end
  else
    love.graphics.draw(img, dx, dy, 0, scale, scale)
  end
  Preview.popPaletteShader(shaded)
  return maxH, name
end

return Preview
