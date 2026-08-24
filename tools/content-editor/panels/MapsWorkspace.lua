-- Maps workspace.

local Kit = require("Kit")
local Theme = require("Theme")
local MapBuilder = require("MapBuilder")
local Maps = require("Maps")
local LayeredMap = require("LayeredMap")
local Generation = require("Generation")

local MapsWorkspace = {}
local PAL = Theme.PAL

local function sortedTilesets(S)
  local seen, ids = {}, {}
  for _, bucket in ipairs({ S.project and S.project.tilesets,
      Generation.dataTilesets(S) }) do
    for id in pairs(bucket or {}) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  if #ids == 0 then
    ids[1] = Generation.isGen2(S) and "TILESET_JOHTO" or "OVERWORLD"
  end
  return ids
end

local function beginNewMap(S)
  local ids = sortedTilesets(S)
  local chosen = ids[1]
  for _, id in ipairs(ids) do
    if id == "OVERWORLD" or id == "TILESET_JOHTO" then chosen = id; break end
  end
  S.mapNewDraft = {
    id = "MY_FIRST_MAP", width = "20", height = "18",
    tileset = chosen,
  }
  Kit.blur()
end

local function beginEditingMap(S, App, mapId)
  if not (S.project and mapId) then return false end
  local source, err = LayeredMap.convertMap(S, mapId)
  if not source then
    S.status = "Could not edit " .. tostring(mapId) .. ": " .. tostring(err)
    return false
  end
  S.mapId, S.builderMapId = source.id, source.id
  S.builderLayer = 1
  S.builderSourceId = LayeredMap.runtimeSourceId(source.baseTileset)
  S.builderSelections = {}
  S.builderPane = "layers"
  S.mapEditMode = "map"
  App.markDirty()
  S.status = "Editable copy created for " .. source.id
  return true
end

local function drawNewMapForm(S, x, y, w, App)
  local d, s = S.mapNewDraft, Kit.scale
  Kit.card(x, y, w, 146 * s, 10 * s)
  local px, py = x + 14 * s, y + 10 * s
  Kit.text("caption", "CREATE A NEW MAP", px, py, PAL.heading)
  Kit.text("micro", "Start with a preset. You can resize and change tiles later.",
    px + 142 * s, py + 2 * s, PAL.muted)
  py = py + 25 * s
  Kit.text("micro", "Map name", px, py + 5 * s, PAL.caption)
  Kit.offerTooltip(px, py, 68 * s, 26 * s,
    "Internal map id: letters, numbers, and underscores")
  d.id = Kit.textfield("maps_new_id", px + 68 * s, py, 190 * s, 26 * s,
    d.id, "MY_FIRST_MAP",
    "Internal map id: letters, numbers, and underscores")
  Kit.text("micro", "Letters, numbers, and underscores", px + 266 * s,
    py + 6 * s, PAL.muted)
  py = py + 32 * s
  Kit.text("micro", "Map size", px, py + 5 * s, PAL.caption)
  local presets = {
    { label = "Small room", w = 12, h = 10 },
    { label = "Town", w = 20, h = 18 },
    { label = "Large area", w = 32, h = 24 },
  }
  local bx = px + 68 * s
  for _, preset in ipairs(presets) do
    local active = tonumber(d.width) == preset.w and tonumber(d.height) == preset.h
    if Kit.chip(bx, py, 82 * s, 26 * s, preset.label, active,
        PAL.green, PAL.steel, string.format("%d x %d walkable cells", preset.w, preset.h)) then
      d.width, d.height = tostring(preset.w), tostring(preset.h)
    end
    bx = bx + 86 * s
  end
  Kit.text("micro", "Custom", bx + 2 * s, py + 5 * s, PAL.caption)
  d.width = Kit.textfield("maps_new_w", bx + 50 * s, py, 56 * s, 26 * s,
    d.width, "20", "Width in 16x16 cells. Must be even")
  Kit.text("micro", "x", bx + 110 * s, py + 6 * s, PAL.muted)
  d.height = Kit.textfield("maps_new_h", bx + 122 * s, py, 56 * s, 26 * s,
    d.height, "18", "Height in 16x16 cells. Must be even")
  py = py + 32 * s
  local ids, selected = sortedTilesets(S), 1
  for i, id in ipairs(ids) do if id == d.tileset then selected = i; break end end
  Kit.text("micro", "Visual style", px, py + 5 * s, PAL.caption)
  Kit.offerTooltip(px, py, 68 * s, 26 * s,
    "Starting tileset. You can change this later")
  if Kit.stepper(px + 68 * s, py, 26 * s, 26 * s, "<",
      { tooltip = "Previous tileset style" }) then
    selected = ((selected - 2) % #ids) + 1; d.tileset = ids[selected]
  end
  Kit.textCenter("micro", Kit.ellipsize("micro", d.tileset, 180 * s),
    px + 98 * s, py + 6 * s, 180 * s, PAL.heading)
  if Kit.stepper(px + 282 * s, py, 26 * s, 26 * s, ">",
      { tooltip = "Next tileset style" }) then
    selected = (selected % #ids) + 1; d.tileset = ids[selected]
  end
  local width, height = tonumber(d.width), tonumber(d.height)
  local valid = width and height and width >= 2 and height >= 2
    and width % 2 == 0 and height % 2 == 0
  if not valid then
    Kit.text("micro", "Size must use even numbers, 2 or larger.",
      px + 320 * s, py + 6 * s, PAL.red)
  end
  if Kit.button(x + w - 220 * s, py, 112 * s, 26 * s, "Create map", {
      kind = "good", enabled = valid,
      tooltip = "Dimensions must be even 16x16-cell values" }) then
    local created, err = LayeredMap.createMap(
      S, d.id, width, height, d.tileset)
    if created then
      S.mapId, S.builderMapId = created.id, created.id
      S.builderLayer = 1
      S.builderSourceId = LayeredMap.runtimeSourceId(created.baseTileset)
      S.builderSelections = {}
      S._builderDoFit = true
      App.markDirty()
    end
    if created then
      S.mapNewDraft = nil
      S.builderPane = "layers"
      S.status = "Created layered map " .. created.id
      Kit.blur()
    else
      S.status = "Create map failed: " .. tostring(err)
    end
  end
  if Kit.button(x + w - 100 * s, py, 86 * s, 26 * s, "Cancel",
      { kind = "ghost", tooltip = "Close without creating a map" }) then S.mapNewDraft = nil; Kit.blur() end
end

function MapsWorkspace.draw(S, x, y, w, h, App)
  S.mapWorkspace = true
  if S.mapSection == "warps" then
    S.mapSection = "basics"
    S.builderPane = "warps"
    S.builderTool = "warp"
  end
  S.builderPane = S.builderPane or "layers"
  local s = Kit.scale
  local moreH = S.mapMoreActions and 36 * s or 0
  local barH = 76 * s + moreH
  local selected = S.mapId or S.builderMapId
  local isLayered = selected and S.project and S.project.layeredMaps
    and S.project.layeredMaps[selected] ~= nil

  Kit.card(x, y, w, barH, 10 * s)
  Kit.text("caption", "MAP BUILDER", x + 12 * s, y + 10 * s, PAL.heading)
  local steps = {
    { label = "1  Choose a map", done = selected ~= nil },
    { label = "2  Make it editable", done = isLayered },
    { label = "3  Paint or add events", done = isLayered },
    { label = "4  Save your mod", done = isLayered and not S.dirty },
  }
  local stepX = x + 118 * s
  for _, step in ipairs(steps) do
    local sw = Kit.textWidth("micro", step.label) + 18 * s
    Kit.chip(stepX, y + 6 * s, sw, 25 * s, step.label, step.done,
      PAL.green, PAL.steel, step.label)
    stepX = stepX + sw + 5 * s
  end
  local actionY = y + 40 * s
  local world = S.mapViewMode == "world"
  local worldLabel = world and "Back to Editor" or "World View"
  if Kit.button(x + 12 * s, actionY, 110 * s, 28 * s,
      worldLabel, { kind = world and "accent" or "ghost",
        enabled = selected ~= nil,
        tooltip = world
          and "Return to the map editor"
          or "Zoomed overview of this map and its neighbors. The editor already draws connected routes around the map." }) then
    S.mapViewMode = world and "editor" or "world"
    if S.mapViewMode == "world" then
      S._worldFitKey = nil
    else
      S._worldViewHit = false
    end
  end
  if Kit.button(x + 128 * s, actionY, 132 * s, 28 * s,
      isLayered and "Ready to edit" or "Edit this map", {
        kind = isLayered and "ghost" or "accent",
        enabled = selected ~= nil and not isLayered,
        tooltip = isLayered
          and "This map already has an editable project copy"
          or "Create an editable copy; viewing and World View never change maps",
      }) then
    isLayered = beginEditingMap(S, App, selected) or isLayered
  end
  if Kit.button(x + 266 * s, actionY, 126 * s, 28 * s,
      "Create new map", { kind = "good", enabled = S.project ~= nil,
        tooltip = "Start a new map with beginner-friendly defaults" }) then
    if S.mapNewDraft then S.mapNewDraft = nil else beginNewMap(S) end
  end
  if Kit.button(x + 398 * s, actionY, 104 * s, 28 * s,
      S.mapMoreActions and "Less actions" or "More actions", {
        kind = "ghost", tooltip = "Show or hide advanced map actions" }) then
    S.mapMoreActions = not S.mapMoreActions
  end
  local actionRight = x + w - 12 * s
  if Kit.button(actionRight - 104 * s, actionY, 104 * s, 28 * s,
      S.dirty and "Save changes" or "Saved", {
        kind = S.dirty and "primary" or "ghost",
        enabled = S.dirty == true,
        tooltip = "Save this mod and all map changes" }) then
    App.save()
  end
  if S.mapMoreActions and Kit.button(x + 12 * s, y + 76 * s, 112 * s, 26 * s,
      "Clear Events", { kind = "ghost", enabled = isLayered,
        tooltip = "Remove objects, signs, transfers, and layered warp endpoints" }) then
    Maps.clearEvents(S, App)
  end
  local owned = selected and S.project and S.project.maps
    and S.project.maps[selected] ~= nil
  local rec = owned and S.project.maps[selected]
  local canReset = owned and rec and rec._isNew ~= true
    and (not S._vanillaMapIds or S._vanillaMapIds[selected] == true)
  if S.mapMoreActions and Kit.button(x + 130 * s, y + 76 * s, 118 * s, 26 * s,
      "Reset original", { kind = "ghost", enabled = canReset,
        tooltip = "Restore this game map's blocks, tileset, and events from the ROM" }) then
    Maps.resetToOriginal(S, App)
  end
  if S.mapMoreActions and Kit.button(x + 254 * s, y + 76 * s, 104 * s, 26 * s,
      "Delete map", { kind = "danger", enabled = owned,
        tooltip = "Delete this project-owned map (vanilla maps revert to source)" }) then
    Maps.deleteMap(S, App)
  end
  if S.mapMoreActions and Kit.button(x + 364 * s, y + 76 * s, 96 * s, 26 * s,
      "Export TMX", { kind = "good", enabled = selected ~= nil,
        tooltip = "Write this map as a Tiled .tmx (one tile = one block)" }) then
    Maps.exportTmx(S, App)
  end
  if S.mapMoreActions and Kit.button(x + 466 * s, y + 76 * s, 96 * s, 26 * s,
      "Import TMX", { kind = "accent", enabled = S.project ~= nil,
        tooltip = "Import engine TMX, or convert Pokemonium TMX to blocks" }) then
    App.pickFile("Tiled TMX", "Tiled map (*.tmx)|*.tmx|All (*.*)|*.*",
      function(path)
        Maps.importTmx(S, path, App)
      end)
  end
  if S.mapMoreActions and Kit.button(x + 568 * s, y + 76 * s, 118 * s, 26 * s,
      "TMX folder", { kind = "accent", enabled = S.project ~= nil,
        tooltip = "Convert a Pokemonium maps folder to engine blocks" }) then
    local picked = require("ModIO").chooseFolder("Pokemonium / Tiled maps folder", S.path)
    if picked then Maps.importTmx(S, picked, App) end
  end

  local formH = S.mapNewDraft and 154 * s or 0
  if S.mapNewDraft then drawNewMapForm(S, x, y + barH + 6 * s, w, App) end
  local bodyY = y + barH + 8 * s + formH
  local bodyH = h - barH - 8 * s - formH
  if selected then
    S.mapId = selected
    S.builderMapId = selected
  end
  S.mapPreviewOnly = not isLayered
  MapBuilder.draw(S, x, bodyY, w, bodyH, App)
  S.mapPreviewOnly = nil
end

function MapsWorkspace.keypressed(S, key, App)
  if key == "escape" and S.mapNewDraft then
    S.mapNewDraft = nil
    Kit.blur()
    S.status = "New map cancelled"
    return true
  end
  local id = S.mapId or S.builderMapId
  local layered = id and S.project and S.project.layeredMaps
    and S.project.layeredMaps[id]
  if layered then
    return MapBuilder.keypressed and MapBuilder.keypressed(S, key, App)
  end
  -- Preview mode is deliberately navigation-only. Classic editor shortcuts can
  -- call ensureOwned and silently copy a vanilla map into the project.
  return false
end

function MapsWorkspace.update(S, dt)
  if Maps.update then Maps.update(S, dt) end
  if MapBuilder.update then MapBuilder.update(S, dt) end
end

function MapsWorkspace.wheelmoved(S, dy, dx)
  if MapBuilder.wheelmoved and MapBuilder.wheelmoved(S, dy, dx) then return true end
  return Maps.wheelmoved and Maps.wheelmoved(S, dy, dx) or false
end

return MapsWorkspace
