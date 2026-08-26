-- Undo/redo for content-editor project mutations.
--
-- Panels mutate during love.draw (immediate-mode UI) and then call
-- App.markDirty().  We keep a baseline snapshot of the project from the end
-- of the previous frame; the first dirty mark in a frame pushes that baseline
-- onto the undo stack.  Rapid edits (typing) coalesce within COALESCE_SEC so
-- one undo step reverts a burst of keystrokes.
--
-- Restore also prunes live S.data aliases created for brand-new assets and
-- deletes mod asset files that the restored project no longer references, so
-- create → undo does not leave ghost ids / orphan PNGs.

local History = {}

local MAX_STACK = 8
local COALESCE_SEC = 0.55

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, val in pairs(v) do
    out[deepCopy(k, seen)] = deepCopy(val, seen)
  end
  return out
end

local function ensureProject(project)
  local ok, State = pcall(require, "State")
  if ok and State.ensureProjectFields then
    return State.ensureProjectFields(deepCopy(project))
  end
  return deepCopy(project)
end

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

-- Mod-relative asset path worth tracking (skip ROM-cache generated sheets).
local function isModAssetPath(path)
  if type(path) ~= "string" or path == "" then return false end
  path = path:gsub("\\", "/")
  if path:sub(1, #"assets/generated/") == "assets/generated/" then
    return false
  end
  return path:sub(1, #"assets/") == "assets/"
    or path:sub(1, #"tilesets/") == "tilesets/"
end

local function collectAssetPaths(node, into, seen)
  if type(node) ~= "table" then
    if isModAssetPath(node) then into[node:gsub("\\", "/")] = true end
    return
  end
  seen = seen or {}
  if seen[node] then return end
  seen[node] = true
  for _, v in pairs(node) do
    collectAssetPaths(v, into, seen)
  end
end

local function absModPath(S, rel)
  if not (S and S.path and rel) then return nil end
  local sep = package.config:sub(1, 1)
  return S.path .. sep .. tostring(rel):gsub("/", sep)
end

-- Drop brand-new live aliases that the restored project no longer owns.
-- Vanilla ids without a backup stay (they were never project-owned).
local function pruneLiveBucket(live, projectBucket, backup)
  if type(live) ~= "table" then return end
  projectBucket = projectBucket or {}
  backup = backup or {}
  local drop = {}
  for id, rec in pairs(live) do
    if not projectBucket[id] then
      if backup[id] then
        live[id] = backup[id]
      elseif type(rec) == "table" and rec._isNew then
        drop[#drop + 1] = id
      end
    end
  end
  for _, id in ipairs(drop) do
    live[id] = nil
  end
end

-- Map/terrain paint mutates project.maps / project.tilesets and aliases them
-- into S.data.*. Restoring only S.project would leave the live tables on
-- screen. Re-bind from the project (or pre-edit vanilla backups) after restore.
local function syncLiveMaps(S)
  if not (S and S.data and S.data.maps) then return end
  local projectMaps = (S.project and S.project.maps) or {}
  local backup = S._vanillaMapBackup or {}
  for id, def in pairs(projectMaps) do
    S.data.maps[id] = def
  end
  for id, vanilla in pairs(backup) do
    if not projectMaps[id] then
      S.data.maps[id] = vanilla
    end
  end
  pruneLiveBucket(S.data.maps, projectMaps, backup)
end

local function syncLiveTilesets(S)
  if not (S and S.data and S.data.tilesets) then return end
  local projectTs = (S.project and S.project.tilesets) or {}
  local backup = S._vanillaTilesetBackup or {}
  for id, ts in pairs(projectTs) do
    S.data.tilesets[id] = ts
  end
  for id, vanilla in pairs(backup) do
    if not projectTs[id] then
      S.data.tilesets[id] = vanilla
    end
  end
  pruneLiveBucket(S.data.tilesets, projectTs, backup)
  -- Drop editor path wrappers so the next draw rebuilds from restored images.
  S._liveTilesets = nil
end

local function syncLiveLedges(S)
  if not (S and S.data and S.data.field) then return end
  local base = S._vanillaLedgesBackup
  if not base then return end
  local out = {}
  for _, row in ipairs(base) do out[#out + 1] = row end
  for _, row in ipairs((S.project and S.project.ledges) or {}) do
    out[#out + 1] = row
  end
  S.data.field.ledges = out
end

local function removeOrphanAssetFiles(S, beforeProject, afterProject)
  if not (S and S.path) then return end
  local before, after = {}, {}
  collectAssetPaths(beforeProject, before)
  collectAssetPaths(afterProject, after)
  local Preview = nil
  pcall(function() Preview = require("Preview") end)
  local ModIO = nil
  pcall(function() ModIO = require("ModIO") end)
  for rel in pairs(before) do
    if not after[rel] then
      local abs = absModPath(S, rel)
      if abs and ModIO and ModIO.exists and ModIO.exists(abs) then
        pcall(os.remove, abs)
        if Preview and Preview.invalidatePath then
          pcall(Preview.invalidatePath, rel)
        end
      end
    end
  end
end

local function clearStaleSelections(S)
  if not S then return end
  local function has(bucket, id)
    if not id then return true end
    if S.project and S.project[bucket] and S.project[bucket][id] then return true end
    if S.data and S.data[bucket] and S.data[bucket][id] then return true end
    return false
  end
  if not has("sprites", S.spriteEditId) then S.spriteEditId = nil end
  if not has("tilesets", S.tilesetEditId) then S.tilesetEditId = nil end
  if not has("pokemon", S.pokemonEditId) then S.pokemonEditId = nil end
  if not has("items", S.itemEditId) then S.itemEditId = nil end
  if not has("trainers", S.trainerEditId) then S.trainerEditId = nil end
  if not has("moves", S.moveEditId) then S.moveEditId = nil end
  if not has("maps", S.mapId) then
    S.mapId = nil
    S._mapCenteredFor = nil
  end
  if S.mapPlaceSprite and not has("sprites", S.mapPlaceSprite) then
    S.mapPlaceSprite = nil
  end
  if S.paintTileset and not has("tilesets", S.paintTileset) then
    S.paintTileset = nil
  end
end

local function invalidateCaches(S)
  local okSU, SpriteUtil = pcall(require, "SpriteUtil")
  if okSU and SpriteUtil.invalidateIdCache then
    SpriteUtil.invalidateIdCache(S)
  end
  local okMaps, Maps = pcall(require, "Maps")
  if okMaps and Maps and Maps.invalidateCaches then
    Maps.invalidateCaches(S)
  end
  local okPrev, Preview = pcall(require, "Preview")
  if okPrev and Preview and Preview.invalidate then
    pcall(Preview.invalidate)
  end
end

local function restore(S, snapshot)
  local before = S.project
  S.project = ensureProject(snapshot)
  S._histBaseline = deepCopy(S.project)
  S._histDirtyFrame = false
  S._histLastPush = nil
  S.dirty = true
  S.uiPreviewTick = (S.uiPreviewTick or 0) + 1
  -- Keep map/world camera + zoom; only rebuild tiles for the restored data.
  S._mapNeedsRebuild = S.mapId
  syncLiveMaps(S)
  syncLiveTilesets(S)
  syncLiveLedges(S)
  removeOrphanAssetFiles(S, before, S.project)
  clearStaleSelections(S)
  invalidateCaches(S)
  local ok, MapLoader = pcall(require, "src.world.MapLoader")
  if ok and MapLoader and MapLoader.invalidateAll then
    MapLoader.invalidateAll()
  end
end

function History.clear(S)
  if not S then return end
  S.undoStack = {}
  S.redoStack = {}
  S._histBaseline = S.project and deepCopy(S.project) or nil
  S._histBatch = nil
  S._histDirtyFrame = false
  S._histLastPush = nil
  S._histLastTab = nil
  S._vanillaLedgesBackup = nil
end

function History.beginFrame(S)
  if not S then return end
  S._histDirtyFrame = false
  if S.project and not S._histBaseline then
    S._histBaseline = deepCopy(S.project)
  end
end

function History.noteDirty(S)
  if not (S and S.project) then return end
  -- A batch keeps one snapshot for the whole gesture. This avoids copying a
  -- large layered map on every frame while the mouse is held down.
  if S._histBatch then
    S._histBatch.dirty = true
    return
  end
  if S._histDirtyFrame then return end
  S._histDirtyFrame = true

  local t = now()
  local coalesce = S._histLastPush
    and (t - S._histLastPush) < COALESCE_SEC
    and S._histLastTab == S.tab
    and #(S.undoStack or {}) > 0

  if coalesce then
    S._histLastPush = t
    return
  end

  S.undoStack = S.undoStack or {}
  -- Always copy: the baseline table is replaced later, but nested aliases
  -- must not be shared with the live project after the push.
  S.undoStack[#S.undoStack + 1] = deepCopy(S._histBaseline or S.project)
  while #S.undoStack > MAX_STACK do
    table.remove(S.undoStack, 1)
  end
  S.redoStack = {}
  S._histLastPush = t
  S._histLastTab = S.tab
end

function History.endFrame(S)
  if not (S and S.project) then return end
  if S._histBatch then return end
  if S._histDirtyFrame or not S._histBaseline then
    S._histBaseline = deepCopy(S.project)
  end
end

function History.beginBatch(S)
  if not (S and S.project) or S._histBatch then return false end
  S._histBatch = {
    baseline = deepCopy(S._histBaseline or S.project),
    dirty = false,
  }
  return true
end

function History.endBatch(S)
  if not S then return false end
  local batch = S._histBatch
  S._histBatch = nil
  if not (batch and batch.dirty and S.project) then return false end

  S.undoStack = S.undoStack or {}
  S.undoStack[#S.undoStack + 1] = batch.baseline
  while #S.undoStack > MAX_STACK do
    table.remove(S.undoStack, 1)
  end
  S.redoStack = {}
  S._histLastPush = now()
  S._histLastTab = S.tab
  S._histBaseline = deepCopy(S.project)
  S._histDirtyFrame = false
  return true
end

-- Replace the baseline after an internal, non-user edit.
function History.resetBaseline(S)
  if not (S and S.project) then return false end
  S._histBaseline = deepCopy(S.project)
  S._histDirtyFrame = false
  S._histBatch = nil
  S._histLastPush = nil
  return true
end

function History.canUndo(S)
  return S and S.undoStack and #S.undoStack > 0
end

function History.canRedo(S)
  return S and S.redoStack and #S.redoStack > 0
end

function History.undo(S)
  History.endBatch(S)
  if not History.canUndo(S) then return false end
  S.redoStack = S.redoStack or {}
  S.redoStack[#S.redoStack + 1] = deepCopy(S.project)
  local prev = table.remove(S.undoStack)
  restore(S, prev)
  return true
end

function History.redo(S)
  History.endBatch(S)
  if not History.canRedo(S) then return false end
  S.undoStack = S.undoStack or {}
  S.undoStack[#S.undoStack + 1] = deepCopy(S.project)
  local nxt = table.remove(S.redoStack)
  restore(S, nxt)
  return true
end

-- Public: prune live new aliases after Revert (same rules as undo restore).
function History.pruneLiveAfterProjectChange(S)
  if not S then return end
  syncLiveMaps(S)
  syncLiveTilesets(S)
  clearStaleSelections(S)
  invalidateCaches(S)
end

return History
