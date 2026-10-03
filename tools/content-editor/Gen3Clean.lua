-- GAME PATCHES > Clean Project (FireRed / LeafGreen / Emerald): start a mod from
-- scratch. Apply wipes the open project -- every edit made so far -- and
-- leaves one blank starter map to begin on:
--   * a new game starts on that map (PLAYER > start map, via the workbench
--     boot settings) with no story flags or variables set;
--   * the intro only asks boy or girl and the player's name (no professor,
--     no rival) -- Gen3CleanIntro; the title screen and menu are unchanged;
--   * FireRed's own maps and scripts are hidden in the editor and can't be
--     reached in game. A FireRed map can be brought in as a template (MAPS >
--     Import template map): its layout under a new name, never its events or
--     story.
-- Pokemon, moves, items, types, tilesets, graphics and trainers stay.
local M = {}

M.STARTER = { id = "FR_STARTER_MAP", width = 20, height = 18, pair = "pallet_outdoor", tile = 1 }
-- Emerald: a field of grass on Petalburg's tileset; the intro is Birch's
-- scene cut the same way (Gen3CleanIntro.configureBirch), with no truck.
M.STARTER_EMERALD = { id = "EM_STARTER_MAP", width = 20, height = 18, pair = "general__petalburg", tile = 1 }
local function emerald(project) return (project.game or project.version) == "emerald" end

function M.enabled(project)
  return type(project) == "table" and type(project.gen3Clean) == "table"
end

--- Wipe S.project and set up the clean start. Returns the starter map id.
-- The caller saves and reopens the mod (GamePatches does).
function M.apply(S)
  local State = require("State")
  local old = assert(S.project, "no project")
  local fresh = State.ensureProjectFields(State.blankProject(old.id, old.name))
  fresh.game = old.game
  fresh.gen3Workspace = true
  -- Emerald: GAME PATCHES > FireRed Maps stays as it was (its tilesets and
  -- template maps), without the imported region.
  if emerald(old) and old.gen3FrLink == true then fresh.gen3FrLink = true end
  -- FireRed / LeafGreen: GAME PATCHES > Emerald Maps the same way.
  if not emerald(old) and old.gen3EmLink == true then fresh.gen3EmLink = true end
  S.project = fresh
  pcall(function() require("Generation").restoreUnownedLiveMaps(S) end)
  if S.data then S.data._g3Packs = {}; S.data._editorMaps, S.data._editorTilesets = nil, nil end
  pcall(function() require("Gen3Workspace").prepare(S) end)
  local L = require("LayeredMap")
  L.ensureProject(fresh)
  local c = emerald(fresh) and M.STARTER_EMERALD or M.STARTER
  local source, map = L.createMap(S, c.id, c.width, c.height, c.pair)
  assert(source, "could not create the starter map: " .. tostring(map))
  for _, layer in ipairs(source.layers) do
    for i, cell in pairs(layer.cells) do layer.cells[i] = { source = cell.source, tile = c.tile } end
  end
  map.label = "STARTER_MAP"
  local x, y = math.floor(source.cellWidth / 2), math.floor(source.cellHeight / 2)
  fresh.gen3Clean = { version = 1, applied = os.date and os.date("%Y-%m-%d") or nil }
  fresh.gen3Workbench = true
  fresh.boot = { startMap = source.id, startX = x, startY = y, startFacing = "down",
    lastHeal = { map = source.id, x = x, y = y } }
  S.mapId, S.builderMapId, S.dialogMapId = source.id, source.id, source.id
  return source.id
end

--- The game's own maps, for Import template map: { ids }, { [id] = label }.
function M.templateMaps(S)
  local ids, labels = {}, {}
  local Labels = require("Gen3Labels")
  local prefix = "^" .. require("Generation").gen3MapPrefix(S)
  for id in pairs(((S.data or {})._editorMaps) or ((S.data or {}).maps) or {}) do
    -- the game's own maps only: not the project's (made, resized or
    -- brought in by Import region)
    local own = ((S.project or {}).maps or {})[id] or ((S.project or {}).gen3MapLayouts or {})[id]
      or (((S.project or {}).gen3 or {}).maps or {})[id]
    if type(id) == "string" and id:match(prefix) and not own then
      ids[#ids + 1] = id
      labels[id] = Labels.map(id) .. "  (" .. id .. ")"
    end
  end
  table.sort(ids, function(a, b) return Labels.natural(labels[a], labels[b]) end)
  -- Emerald with GAME PATCHES > FireRed Maps on: FireRed's maps too.
  do
    local frIds, frLabels = require("Gen3Link").templateMaps(S.project)
    for _, id in ipairs(frIds) do ids[#ids + 1] = id; labels[id] = frLabels[id] end
  end
  return ids, labels
end

--- Bring a game map in as a template (in Emerald also a FireRed one,
-- "frlg:FR_…", Gen3FrLink): its layout, collision, heights and border under a
-- new name, with no events, scripts, warps or connections.
-- Returns the new map id, or nil and why.
function M.importTemplate(S, baseId)
  local W = require("Gen3Workspace")
  local L = require("LayeredMap")
  local copy = require("src.mods.Merge").deepCopy
  local FrLink = require("Gen3Link")
  local fireRed = FrLink.isMap(baseId)
  local base, err
  if fireRed then base, err = FrLink.templateSource(S, baseId) else base, err = W.source(S, baseId) end
  if not base then return nil, err end
  local wanted = (fireRed and FrLink.templateName(baseId)
    or baseId:gsub("^" .. require("Generation").gen3MapPrefix(S), "")) .. "_TEMPLATE"
  local source, map = L.createMap(S, wanted, base.cellWidth, base.cellHeight, base.baseTileset)
  if not source then return nil, map end
  local id = source.id
  local fresh = copy(base)
  fresh.id = id
  S.project.layeredMaps[id] = fresh
  map.width, map.height = fresh.cellWidth / 2, fresh.cellHeight / 2
  map.tileset = fresh.baseTileset
  map._gen3Border = copy(fresh.gen3Border)
  map.label = id
  map.warps, map.objects, map.signs, map.connections = {}, {}, {}, {}
  local props = require("Gen3MapProperties")
  local kind
  if fireRed then kind = (FrLink.header(baseId) or {}).mapType
  else kind = props.resolve(S, { id = baseId }).mapType end
  if kind then props.apply(map, kind) end
  return id
end

--- The game side: no story flags or variables on a new game, and the short
-- intro. (The start map comes from the workbench boot settings.)
function M.emit(project, encode, out)
  if not M.enabled(project) then return end
  local intro = assert(love.filesystem.read("tools/content-editor/Gen3CleanIntro.lua"), "Gen3CleanIntro.lua missing")
  out[#out + 1] = "  local cleanIntro=(function()\n" .. intro .. "\n  end)()"
  out[#out + 1] = [=[
  do
    local Runtime=require("src.mods.Runtime")
    -- a new game starts with no story: no flags, no variables
    mod.hooks:wrap("save.new_game",function(proceed,session)
      session=proceed(session)
      if type(session)=="table" then session.flags={};session.vars={} end
      return session
    end)
    -- the intro: boy or girl, and a name
    local okS,Scene=pcall(require,]=] .. (emerald(project) and '"src.ui.game3.rse.birch_speech"' or '"src.ui.game3.new_game_scene"') .. [=[)
    if okS and type(Scene)=="table" and Scene.new then
      if not Scene._editorCleanIntroBridge then
        Scene._editorCleanIntroBridge=true
        local base=Scene.new
        Scene.new=function(...) return Runtime.call("editor.gen3.clean.intro",base,...) end
      end
      mod.hooks:wrap("editor.gen3.clean.intro",function(proceed,...)
        return cleanIntro.]=] .. (emerald(project) and "configureBirch" or "configure") .. [=[(proceed(...))
      end)
    end
  end
]=]
end

return M
