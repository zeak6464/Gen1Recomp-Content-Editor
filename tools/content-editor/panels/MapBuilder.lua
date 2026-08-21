-- Native 16x16 layered map authoring panel.

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local LayeredMap = require("LayeredMap")
local TilesetExport = require("TilesetExport")
local Generation = require("Generation")
local FormPane = require("FormPane")

local MapBuilder = {}
local PAL = Theme.PAL
local CELL = LayeredMap.CELL_SIZE

local TOOLS = {
  { id = "pencil", label = "Pencil", tip = "Paint the selected 16x16 tile" },
  { id = "eraser", label = "Eraser", tip = "Erase cells; drag for a range" },
  { id = "fill", label = "Fill", tip = "Flood-fill matching cells" },
  { id = "rectangle", label = "Rectangle", tip = "Drag a filled rectangle" },
  { id = "picker", label = "Picker", tip = "Pick a source tile from the map" },
  { id = "select", label = "Select", tip = "Drag ranges; Shift adds another" },
  { id = "collision", label = "Collision", tip = "Paint cell passage" },
  { id = "warp", label = "Warp", tip = "Place directed, two-way, or custom-return warps" },
  { id = "pan", label = "Pan", tip = "Drag the map without painting" },
}

local EVENT_TOOLS = {
  { id = "object", mapTool = "object", label = "Event",
    tip = "Place an NPC or scripted object on a 16x16 cell" },
  { id = "sign", mapTool = "sign", label = "Sign",
    tip = "Place a sign/background event on a 16x16 cell" },
  { id = "trainer", mapTool = "trainer", label = "Trainer",
    tip = "Place a trainer event" },
  { id = "wild", mapTool = "wild", label = "Wild",
    tip = "Place a fixed wild encounter" },
  { id = "event_select", mapTool = "select", label = "Select",
    tip = "Select the nearest object, sign, or transfer" },
}

local EVENT_TOOL_BY_ID = {}
for _, tool in ipairs(EVENT_TOOLS) do EVENT_TOOL_BY_ID[tool.id] = tool end

local function stencilFitScale(source, iw, ih)
  if iw < 1 or ih < 1 then return 1 end
  local mapW = (source.cellWidth or 1) * CELL
  local mapH = (source.cellHeight or 1) * CELL
  return math.min(mapW / iw, mapH / ih)
end

local function stencilScaleValue(source, iw, ih)
  local scale = tonumber(source.stencilScale)
  if scale and scale > 0 then return scale end
  return stencilFitScale(source, iw, ih)
end

local function drawMapStencil(S, source)
  if not source or source.stencilVisible == false then return end
  local path = source.stencilImage
  if type(path) ~= "string" or path == "" then return end
  local image = Preview.image(S, path)
  if not image then return end
  local iw, ih = image:getDimensions()
  if iw < 1 or ih < 1 then return end
  local scale = stencilScaleValue(source, iw, ih)
  if love.graphics.setShader then love.graphics.setShader() end
  love.graphics.setColor(1, 1, 1, math.max(0, math.min(1,
    tonumber(source.stencilOpacity) or 0.45)))
  love.graphics.draw(image,
    tonumber(source.stencilX) or 0, tonumber(source.stencilY) or 0,
    0, scale, scale)
  love.graphics.setColor(1, 1, 1, 1)
end

local BASIC_TERRAIN_TOOLS = { pencil = true, eraser = true, fill = true, pan = true }
local BASIC_EVENT_TOOLS = { object = true, sign = true, event_select = true }

-- Shared panel helpers

local function clamp(value, low, high)
  value = tonumber(value) or low
  return math.max(low, math.min(high, value))
end

local function importStencil(S, source, App)
  if not (S.project and S.path and source and App and App.pickFile) then return end
  App.pickFile("Map stencil PNG", "PNG (*.png)|*.png|All files (*.*)|*.*",
    function(picked)
      local stem = tostring(source.id or "map"):lower() .. "_stencil.png"
      local base = App.assetBaseName(picked, stem)
      if not base:lower():match("%.png$") then base = base .. ".png" end
      local rel = "assets/mapbuilder/stencils/" .. base
      App.importToMod(picked, rel, function(imported)
        source.stencilImage = imported
        if source.stencilOpacity == nil then source.stencilOpacity = 0.45 end
        source.stencilVisible = true
        source.stencilX, source.stencilY = 0, 0
        App.markDirty()
        local image = Preview.image(S, imported)
        if image then
          local iw, ih = image:getDimensions()
          source.stencilScale = stencilFitScale(source, iw, ih)
          S.status = "Stencil over the map — Scale it, or Fit to the map"
        else
          local err = Preview.lastError and Preview.lastError() or "unknown error"
          S.status = "Stencil copied but did not load: " .. tostring(err)
        end
      end)
    end)
end

local function applyImagePathAsMap(S, source, App, path, iw, ih)
  App.beginEditBatch()
  local tileSource, widthOrErr, height = LayeredMap.applyPngAsMap(
    S, source.id or S.builderMapId, path, iw, ih)
  if not tileSource then
    App.endEditBatch()
    S.status = "Could not use PNG as map: " .. tostring(widthOrErr)
    return
  end
  source.stencilVisible = false
  S.builderSourceId = tileSource.id
  S.builderTile = 0
  S.builderLayer = 1
  S.builderSelections = {}
  S._builderDoFit = true
  App.markDirty()
  App.endEditBatch()
  S.status = string.format(
    "Map is the PNG — %dx%d cells. Paint collision as needed.",
    widthOrErr, height)
end

local function usePngAsMap(S, source, App)
  if not (S.project and source and App) then return end
  local path = source.stencilImage
  if type(path) == "string" and path ~= "" then
    local image = Preview.image(S, path)
    if not image then
      S.status = "PNG could not be loaded"
      return
    end
    local iw, ih = image:getDimensions()
    applyImagePathAsMap(S, source, App, path, iw, ih)
    return
  end
  if not (S.path and App.pickFile) then return end
  App.pickFile("Map PNG", "PNG (*.png)|*.png|All files (*.*)|*.*",
    function(picked)
      local stem = App.assetBaseName(picked, "map.png")
      if not stem:lower():match("%.png$") then stem = stem .. ".png" end
      local rel = "assets/mapbuilder/sources/" .. stem
      App.importToMod(picked, rel, function(imported)
        if Preview.invalidatePath then Preview.invalidatePath(imported) end
        local image = Preview.image(S, imported)
        if not image then
          S.status = "Imported PNG could not be decoded"
          return
        end
        local iw, ih = image:getDimensions()
        applyImagePathAsMap(S, source, App, imported, iw, ih)
      end)
    end)
end

local function sortedKeys(bucket)
  local out = {}
  for key in pairs(bucket or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function field(App, id, x, y, w, h, value, placeholder)
  local result = Kit.textfield(id, x, y, w, h, value, placeholder)
  if result ~= tostring(value or "") then App.markDirty() end
  return result
end

local function mapSource(S)
  local source = S.project and S.project.layeredMaps
    and S.project.layeredMaps[S.builderMapId]
  if source then LayeredMap.internSourceCells(source) end
  return source
end

local function drawSourceTile(S, source, tile, x, y, size, alpha)
  return LayeredMap.drawSourceTile(S, source, tile, x, y, size, alpha)
end

local function refEqual(left, right)
  if left == right then return true end
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  return left.source == right.source and left.tile == right.tile
end

local function activeLayer(S, source)
  S.builderLayer = clamp(S.builderLayer or 1, 1, math.max(1, #source.layers))
  return source.layers[S.builderLayer], S.builderLayer
end

local function brushRef(S)
  if not S.builderSourceId then return nil end
  return { source = S.builderSourceId, tile = S.builderTile or 0 }
end

local function stampCells(S)
  local stamp = S.builderStamp
  if type(stamp) == "table" and type(stamp.cells) == "table" and stamp.cells[1] then
    return stamp.cells, stamp.source or S.builderSourceId
  end
  if not S.builderSourceId then return nil end
  return { { dx = 0, dy = 0, tile = S.builderTile or 0 } }, S.builderSourceId
end

local function setStamp(S, sourceId, cells)
  S.builderSourceId = sourceId
  S.builderStamp = { source = sourceId, cells = cells }
  S.builderTile = cells[1] and cells[1].tile or 0
  S.builderTool = "pencil"
end

local function clearStamp(S)
  S.builderStamp = nil
end

local function sheetAssemblyCells(descriptor, tile0, tile1)
  local cols = math.max(1, descriptor.columns or 1)
  local count = math.max(0, descriptor.count or 0)
  local function xy(tile)
    tile = clamp(tile, 0, math.max(0, count - 1))
    return tile % cols, math.floor(tile / cols)
  end
  local x0, y0 = xy(tile0)
  local x1, y1 = xy(tile1)
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  local cells = {}
  for y = y0, y1 do
    for x = x0, x1 do
      local tile = y * cols + x
      if tile < count then
        cells[#cells + 1] = { dx = x - x0, dy = y - y0, tile = tile }
      end
    end
  end
  return cells
end

local function runtimeAssemblyCells(block0, block1, columns, blockCount)
  columns = math.max(1, columns)
  blockCount = math.max(0, blockCount or 0)
  local function xy(block)
    block = clamp(block, 0, math.max(0, blockCount - 1))
    return block % columns, math.floor(block / columns)
  end
  local x0, y0 = xy(block0)
  local x1, y1 = xy(block1)
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  local cells = {}
  for gy = y0, y1 do
    for gx = x0, x1 do
      local blockId = gy * columns + gx
      if blockId < blockCount then
        local ox, oy = (gx - x0) * 2, (gy - y0) * 2
        for dy = 0, 1 do
          for dx = 0, 1 do
            cells[#cells + 1] = {
              dx = ox + dx, dy = oy + dy,
              tile = blockId * 4 + dy * 2 + dx,
            }
          end
        end
      end
    end
  end
  return cells
end

-- Editing primitives

local function paintCell(S, source, x, y, App, erase, deferDirty, single)
  local layer, layerIndex = activeLayer(S, source)
  if not layer then return false end
  if erase or single or not S.builderStamp then
    local before = LayeredMap.getCell(source, layerIndex, x, y)
    local after = erase and nil or brushRef(S)
    if refEqual(before, after) then return false end
    LayeredMap.setCell(source, layerIndex, x, y, after)
    if not deferDirty then App.markDirty() end
    return true
  end
  local cells, srcId = stampCells(S)
  if not (cells and srcId) then return false end
  local changed = false
  for i = 1, #cells do
    local cell = cells[i]
    local px, py = x + cell.dx, y + cell.dy
    if px >= 0 and py >= 0
        and px < source.cellWidth and py < source.cellHeight then
      local after = { source = srcId, tile = cell.tile }
      local before = LayeredMap.getCell(source, layerIndex, px, py)
      if not refEqual(before, after) then
        LayeredMap.setCell(source, layerIndex, px, py, after)
        changed = true
      end
    end
  end
  if changed and not deferDirty then App.markDirty() end
  return changed
end

local function paintCollisionCell(S, source, x, y)
  local index = y * source.cellWidth + x + 1
  local mode = S.builderCollision or "solid"
  if source.collision[index] == mode then return false end
  LayeredMap.setCollision(source, x, y, mode)
  return true
end

-- Visit every grid cell crossed by a quick mouse movement. Without this,
-- a fast drag only paints the cells sampled on rendered frames and leaves gaps.
local function visitCellLine(x0, y0, x1, y1, visit)
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local stepX = x0 < x1 and 1 or -1
  local stepY = y0 < y1 and 1 or -1
  local errorValue = dx - dy

  while true do
    visit(x0, y0)
    if x0 == x1 and y0 == y1 then break end
    local twiceError = 2 * errorValue
    if twiceError > -dy then
      errorValue = errorValue - dy
      x0 = x0 + stepX
    end
    if twiceError < dx then
      errorValue = errorValue + dx
      y0 = y0 + stepY
    end
  end
end

local function floodFill(S, source, x, y, App)
  local layer, layerIndex = activeLayer(S, source)
  if not layer then return end
  local replacement = brushRef(S)
  if not replacement then return end
  local target = LayeredMap.getCell(source, layerIndex, x, y)
  if refEqual(target, replacement) then return end
  local queue, cursor = { { x, y } }, 1
  local seen = {}
  local changed = false
  while cursor <= #queue do
    local point = queue[cursor]
    cursor = cursor + 1
    local px, py = point[1], point[2]
    local key = py * source.cellWidth + px + 1
    if not seen[key] and px >= 0 and py >= 0
        and px < source.cellWidth and py < source.cellHeight then
      seen[key] = true
      if refEqual(LayeredMap.getCell(source, layerIndex, px, py), target) then
        LayeredMap.setCell(source, layerIndex, px, py, replacement)
        changed = true
        queue[#queue + 1] = { px - 1, py }
        queue[#queue + 1] = { px + 1, py }
        queue[#queue + 1] = { px, py - 1 }
        queue[#queue + 1] = { px, py + 1 }
      end
    end
  end
  if changed then App.markDirty() end
end

local function normalizedRect(rect)
  if not rect then return nil end
  return math.min(rect.x0, rect.x1), math.min(rect.y0, rect.y1),
    math.max(rect.x0, rect.x1), math.max(rect.y0, rect.y1)
end

local function applyRectangle(S, source, rect, App, erase)
  local x0, y0, x1, y1 = normalizedRect(rect)
  if not x0 then return end
  local changed = false
  for y = y0, y1 do
    for x = x0, x1 do
      changed = paintCell(S, source, x, y, App, erase, false, true) or changed
    end
  end
  return changed
end

local function clearSelections(S, source, App, withinBatch)
  if not S.builderSelections or #S.builderSelections == 0 then return false end
  if not withinBatch then App.beginEditBatch() end
  local changed = false
  for _, rect in ipairs(S.builderSelections) do
    local x0, y0, x1, y1 = normalizedRect(rect)
    for y = y0, y1 do
      for x = x0, x1 do
        local index = y * source.cellWidth + x + 1
        for layerIndex, layer in ipairs(source.layers or {}) do
          if layer.cells[index] ~= nil then
            LayeredMap.setCell(source, layerIndex, x, y, nil)
            changed = true
          end
        end
        if source.collision[index] ~= "solid" then
          LayeredMap.setCollision(source, x, y, "solid")
          changed = true
        end
      end
    end
  end
  if changed then App.markDirty() end
  if not withinBatch then App.endEditBatch() end
  if changed then
    S.status = string.format("Cleared %d selected range(s)", #S.builderSelections)
  end
  return changed
end

local function selectionBounds(S)
  local minX, minY, maxX, maxY
  for _, rect in ipairs(S.builderSelections or {}) do
    local x0, y0, x1, y1 = normalizedRect(rect)
    minX, minY = math.min(minX or x0, x0), math.min(minY or y0, y0)
    maxX, maxY = math.max(maxX or x1, x1), math.max(maxY or y1, y1)
  end
  return minX, minY, maxX, maxY
end

local function copySelection(S, source)
  local x0, y0, x1, y1 = selectionBounds(S)
  if not x0 then return false end
  local clip = { width = x1 - x0 + 1, height = y1 - y0 + 1,
    layers = {}, collision = {} }
  for layerIndex = 1, #source.layers do clip.layers[layerIndex] = {} end
  for y = y0, y1 do
    for x = x0, x1 do
      local ci = (y - y0) * clip.width + (x - x0) + 1
      for layerIndex = 1, #source.layers do
        local ref = LayeredMap.getCell(source, layerIndex, x, y)
        if ref then
          clip.layers[layerIndex][ci] = { source = ref.source, tile = ref.tile }
        end
      end
      clip.collision[ci] = source.collision[y * source.cellWidth + x + 1]
    end
  end
  S.builderClip = clip
  S.status = string.format("Copied %dx%d cells across all layers",
    clip.width, clip.height)
  return true
end

local function pasteSelection(S, source, App, destX, destY, withinBatch)
  local clip = S.builderClip
  if not clip then S.status = "Copy a selection first"; return false end
  if not withinBatch then App.beginEditBatch() end
  local changed = false
  for y = 0, clip.height - 1 do
    for x = 0, clip.width - 1 do
      local px, py = destX + x, destY + y
      if px >= 0 and py >= 0 and px < source.cellWidth and py < source.cellHeight then
        local ci = y * clip.width + x + 1
        for layerIndex = 1, math.min(#source.layers, #(clip.layers or {})) do
          local ref = clip.layers[layerIndex][ci]
          local nextRef = ref and { source = ref.source, tile = ref.tile } or nil
          if not refEqual(LayeredMap.getCell(source, layerIndex, px, py), nextRef) then
            LayeredMap.setCell(source, layerIndex, px, py, nextRef)
            changed = true
          end
        end
        local collision = clip.collision and clip.collision[ci] or "solid"
        local destIndex = py * source.cellWidth + px + 1
        if source.collision[destIndex] ~= collision then
          LayeredMap.setCollision(source, px, py, collision)
          changed = true
        end
      end
    end
  end
  if changed then App.markDirty() end
  if not withinBatch then App.endEditBatch() end
  S.builderSelections = { { x0 = destX, y0 = destY,
    x1 = destX + clip.width - 1, y1 = destY + clip.height - 1 } }
  S.status = changed and "Pasted cells" or "Paste made no changes"
  return changed
end

local function nudgeSelection(S, source, dx, dy, App)
  local x0, y0, x1, y1 = selectionBounds(S)
  if not x0 then S.status = "Select a range first"; return end
  if x0 + dx < 0 or y0 + dy < 0
      or x1 + dx >= source.cellWidth or y1 + dy >= source.cellHeight then
    S.status = "Cannot nudge selection outside the map"
    return
  end
  if not copySelection(S, source) then return end
  App.beginEditBatch()
  clearSelections(S, source, App, true)
  pasteSelection(S, source, App, x0 + dx, y0 + dy, true)
  App.endEditBatch()
end

local function sourceAtCell(S, source, x, y)
  for index = #source.layers, 1, -1 do
    local layer = source.layers[index]
    if layer.visible ~= false then
      local ref = LayeredMap.getCell(source, index, x, y)
      if ref then return ref, index end
    end
  end
  return nil
end

-- Warp placement workflow

-- Placement is a short state machine: source, destination, and optionally a
-- custom return point. Changing the selected map between clicks is expected.
local function ensureLayeredDestination(S, App)
  if mapSource(S) then return true end
  local source, err = LayeredMap.convertMap(S, S.builderMapId)
  if not source then
    S.status = "Convert failed: " .. tostring(err)
    return false
  end
  S.builderLayer = 1
  App.markDirty()
  S.status = "Converted " .. S.builderMapId .. " to editable layers"
  return true
end

local function completeWarp(S, App, point)
  local draft = S.builderWarpDraft
  local mode = S.builderWarpMode or "two_way"
  if not draft then
    S.builderWarpDraft = { phase = "destination", from = point, mode = mode }
    S.status = "Source placed — select a destination map and click its arrival cell"
    return
  end
  if draft.phase == "destination" then
    if mode == "custom_return" then
      draft.destination = point
      draft.phase = "return"
      S.status = "Arrival placed — select any map and click the return destination"
      return
    end
    local ok, err = LayeredMap.createWarpLink(
      S.project, mode, draft.from, point)
    if ok then
      S.builderWarpDraft = nil
      App.markDirty()
      S.status = mode == "two_way" and "Created two-way warp"
        or "Created one-way warp"
    else
      S.status = "Warp failed: " .. tostring(err)
    end
    return
  end
  local ok, err = LayeredMap.createWarpLink(
    S.project, "custom_return", draft.from, draft.destination, point)
  if ok then
    S.builderWarpDraft = nil
    App.markDirty()
    S.status = "Created warp with a custom return destination"
  else
    S.status = "Warp failed: " .. tostring(err)
  end
end

-- Canvas rendering and input

local function drawChecker(x, y, size)
  local half = size / 2
  love.graphics.setColor(0.16, 0.18, 0.22, 1)
  love.graphics.rectangle("fill", x, y, size, size)
  love.graphics.setColor(0.2, 0.22, 0.27, 1)
  love.graphics.rectangle("fill", x, y, half, half)
  love.graphics.rectangle("fill", x + half, y + half, half, half)
end

local function drawSelections(S, source)
  for _, rect in ipairs(S.builderSelections or {}) do
    local x0, y0, x1, y1 = normalizedRect(rect)
    love.graphics.setColor(0.25, 0.65, 1, 0.18)
    love.graphics.rectangle("fill", x0 * CELL, y0 * CELL,
      (x1 - x0 + 1) * CELL, (y1 - y0 + 1) * CELL)
    love.graphics.setColor(0.35, 0.75, 1, 0.95)
    love.graphics.rectangle("line", x0 * CELL + 0.5, y0 * CELL + 0.5,
      (x1 - x0 + 1) * CELL - 1, (y1 - y0 + 1) * CELL - 1)
  end
  if S.builderRangeDraft then
    local x0, y0, x1, y1 = normalizedRect(S.builderRangeDraft)
    love.graphics.setColor(1, 0.75, 0.25, 0.22)
    love.graphics.rectangle("fill", x0 * CELL, y0 * CELL,
      (x1 - x0 + 1) * CELL, (y1 - y0 + 1) * CELL)
  end
end

local function drawGhostPen(S, cx, cy)
  local tool = S.builderTool or "pencil"
  if tool ~= "pencil" then return end
  local cells, srcId = stampCells(S)
  if not (cells and srcId) then return end
  local desc = LayeredMap.sourceDescriptor(S, srcId)
  if not desc then return end
  local w, h = 1, 1
  for i = 1, #cells do
    w = math.max(w, cells[i].dx + 1)
    h = math.max(h, cells[i].dy + 1)
    drawSourceTile(S, desc, cells[i].tile,
      (cx + cells[i].dx) * CELL, (cy + cells[i].dy) * CELL, CELL, 0.45)
  end
  love.graphics.setColor(0.35, 0.85, 1, 0.55)
  love.graphics.rectangle("line", cx * CELL + 0.5, cy * CELL + 0.5,
    w * CELL - 1, h * CELL - 1)
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawWarpNodes(S, source)
  for _, node in ipairs(LayeredMap.nodesForMap(S.project, S.builderMapId)) do
    local cx, cy = node.x * CELL + CELL / 2, node.y * CELL + CELL / 2
    local selected = S.builderWarpNodeId == node.id
    love.graphics.setColor(node.active and 1 or 0.25,
      node.active and 0.38 or 0.7, node.active and 0.18 or 1, 0.82)
    love.graphics.circle("fill", cx, cy, selected and 6 or 5)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("line", cx, cy, selected and 7 or 6)
  end
end

local function neighborsEnabled(S)
  return S.mapShowNeighbors == true
end

local function neighborExtents(S, source)
  local x0, y0 = 0, 0
  local x1 = source.cellWidth * CELL
  local y1 = source.cellHeight * CELL
  if not neighborsEnabled(S) then return x0, y0, x1, y1 end
  local mapRec = S.project and S.project.maps and S.project.maps[source.id]
  local Maps = require("Maps")
  if not (mapRec and Maps.directNeighbors) then return x0, y0, x1, y1 end
  for _, nb in ipairs(Maps.directNeighbors(S, mapRec)) do
    local nw = math.max(1, tonumber(nb.def.width) or 1) * 32
    local nh = math.max(1, tonumber(nb.def.height) or 1) * 32
    if nb.ox < x0 then x0 = nb.ox end
    if nb.oy < y0 then y0 = nb.oy end
    if nb.ox + nw > x1 then x1 = nb.ox + nw end
    if nb.oy + nh > y1 then y1 = nb.oy + nh end
  end
  return x0, y0, x1, y1
end

local function fitCanvas(S, source, viewW, viewH)
  local mapW = math.max(1, source.cellWidth * CELL)
  local mapH = math.max(1, source.cellHeight * CELL)
  local zoom = math.min(viewW / mapW, viewH / mapH)
  zoom = clamp(zoom, 0.25, 6)
  S.builderZoom = zoom
  S.builderCamX = (mapW - viewW / zoom) / 2
  S.builderCamY = (mapH - viewH / zoom) / 2
  S._builderCamMapId = source.id
end

local function clampBuilderCam(S, source, viewW, viewH, zoom)
  local x0, y0, x1, y1 = neighborExtents(S, source)
  local pad = CELL * 2
  x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad, y1 + pad
  local worldW, worldH = viewW / zoom, viewH / zoom
  local minX, maxX, minY, maxY
  local bw, bh = x1 - x0, y1 - y0
  if bw <= worldW then
    minX = x0 + (bw - worldW) / 2
    maxX = minX
  else
    minX, maxX = x0, x1 - worldW
  end
  if bh <= worldH then
    minY = y0 + (bh - worldH) / 2
    maxY = minY
  else
    minY, maxY = y0, y1 - worldH
  end
  local x = tonumber(S.builderCamX) or 0
  local y = tonumber(S.builderCamY) or 0
  if x < minX then x = minX elseif x > maxX then x = maxX end
  if y < minY then y = minY elseif y > maxY then y = maxY end
  S.builderCamX, S.builderCamY = x, y
end

local function drawConnectedNeighbors(S, source, camX, camY, viewW, viewH)
  if not neighborsEnabled(S) then return end
  local mapRec = S.project and S.project.maps and S.project.maps[source.id]
  local Maps = require("Maps")
  if not (mapRec and Maps.directNeighbors) then return end
  for _, nb in ipairs(Maps.directNeighbors(S, mapRec)) do
    local nw = math.max(1, tonumber(nb.def.width) or 1) * 32
    local nh = math.max(1, tonumber(nb.def.height) or 1) * 32
    if not (nb.ox + nw < camX or nb.oy + nh < camY
        or nb.ox > camX + viewW or nb.oy > camY + viewH) then
      local localCamX, localCamY = camX - nb.ox, camY - nb.oy
      love.graphics.push()
      love.graphics.translate(nb.ox, nb.oy)
      -- Undo the renderer's camera translate so tiles stay in local space,
      -- while still passing the visible rect for cell culling.
      love.graphics.push()
      love.graphics.translate(localCamX, localCamY)
      love.graphics.setColor(1, 1, 1, 0.82)
      local layered = S.project.layeredMaps and S.project.layeredMaps[nb.id]
      if layered and LayeredMap.previewRenderer then
        local okR, renderer = pcall(LayeredMap.previewRenderer, S, layered, nb.id)
        if okR and renderer then
          renderer:draw(localCamX, localCamY, viewW, viewH)
        end
      else
        local ok, loaded = Maps.loadEditorMap(S, nb.id)
        if ok and loaded and loaded.renderer then
          local draw = loaded.renderer.drawMapOnly or loaded.renderer.draw
          if draw then
            draw(loaded.renderer, localCamX, localCamY, viewW, viewH)
          end
        end
      end
      love.graphics.pop()
      love.graphics.setColor(0.27, 0.59, 1, 0.7)
      love.graphics.rectangle("line", 0.5, 0.5, nw - 1, nh - 1)
      love.graphics.pop()
    end
  end
end

local function drawCanvas(S, source, x, y, w, h, App)
  local pad = 8 * Kit.scale
  local vx, vy = x + pad, y + pad
  local vw, vh = math.max(1, w - pad * 2), math.max(1, h - pad * 2)
  if S._builderDoFit or S.builderZoom == nil then
    S._builderDoFit = nil
    fitCanvas(S, source, vw, vh)
  end
  local zoom = clamp(S.builderZoom or 1, 0.25, 8)
  S.builderZoom = zoom
  if S._builderCamMapId ~= source.id then
    S._builderCamMapId = source.id
    S.builderCamX = (source.cellWidth * CELL - vw / zoom) / 2
    S.builderCamY = (source.cellHeight * CELL - vh / zoom) / 2
  end
  clampBuilderCam(S, source, vw, vh, zoom)

  love.graphics.setScissor(math.floor(vx), math.floor(vy),
    math.ceil(vw), math.ceil(vh))
  love.graphics.push()
  love.graphics.translate(vx, vy)
  love.graphics.scale(zoom, zoom)
  love.graphics.translate(-(S.builderCamX or 0), -(S.builderCamY or 0))

  local camX, camY = S.builderCamX or 0, S.builderCamY or 0
  local viewW, viewH = vw / zoom, vh / zoom
  local viewX0 = math.floor(camX / CELL) - 1
  local viewY0 = math.floor(camY / CELL) - 1
  local viewX1 = math.floor((camX + viewW) / CELL) + 1
  local viewY1 = math.floor((camY + viewH) / CELL) + 1
  local x0 = math.max(0, viewX0)
  local y0 = math.max(0, viewY0)
  local x1 = math.min(source.cellWidth - 1, viewX1)
  local y1 = math.min(source.cellHeight - 1, viewY1)
  love.graphics.setColor(0.16, 0.18, 0.22, 1)
  love.graphics.rectangle("fill", viewX0 * CELL, viewY0 * CELL,
    math.max(0, viewX1 - viewX0 + 1) * CELL,
    math.max(0, viewY1 - viewY0 + 1) * CELL)

  -- One 32x32 block of Gold border around this map — not the whole camera.
  local BORDER = 2
  local mapRec = S.project.maps and S.project.maps[source.id]
  local borderBlock = mapRec and (mapRec.borderBlock or 0) or 0
  local borderTs = source.baseTileset or (mapRec and mapRec.tileset)
  local borderDesc = borderTs
    and LayeredMap.sourceDescriptor(S, LayeredMap.runtimeSourceId(borderTs))
  if borderDesc then
    local bx0 = math.max(viewX0, -BORDER)
    local by0 = math.max(viewY0, -BORDER)
    local bx1 = math.min(viewX1, source.cellWidth - 1 + BORDER)
    local by1 = math.min(viewY1, source.cellHeight - 1 + BORDER)
    for cy = by0, by1 do
      for cx = bx0, bx1 do
        if cx < 0 or cy < 0
            or cx >= source.cellWidth or cy >= source.cellHeight then
          local tile = borderBlock * 4 + (cy % 2) * 2 + (cx % 2)
          local desc = borderDesc
          if mapRec and mapRec._borderExplicit
              and type(mapRec._borderTile) == "number" then
            tile = mapRec._borderTile
            if mapRec._borderSource then
              desc = LayeredMap.sourceDescriptor(S, mapRec._borderSource) or desc
            end
          end
          drawSourceTile(S, desc, tile, cx * CELL, cy * CELL, CELL, 1)
        end
      end
    end
  end

  drawConnectedNeighbors(S, source, camX, camY, viewW, viewH)

  for cy = y0, y1 do
    for cx = x0, x1 do
      local dx, dy = cx * CELL, cy * CELL
      for _, layer in ipairs(source.layers or {}) do
        if layer.visible ~= false then
          local ref = layer.cells[cy * source.cellWidth + cx + 1]
          if ref then
            local tileSource = LayeredMap.sourceDescriptor(S, ref.source)
            drawSourceTile(S, tileSource, ref.tile, dx, dy, CELL,
              clamp(layer.opacity or 1, 0, 1))
          end
        end
      end
      if (S.builderTool or "pencil") == "collision" or S.mapShowCollision then
        local mode = source.collision[cy * source.cellWidth + cx + 1] or "solid"
        local colors = {
          solid = { 1, 0.2, 0.2 }, walk = { 0.2, 1, 0.4 },
          grass = { 1, 0.2, 0.9 }, water = { 0.15, 0.55, 1 },
          shore = { 0.95, 0.75, 0.25 },
        }
        local color = colors[mode] or colors.solid
        love.graphics.setColor(color[1], color[2], color[3], 0.28)
        love.graphics.rectangle("fill", dx, dy, CELL, CELL)
      end
    end
  end
  drawMapStencil(S, source)
  if S.mapShowGrid ~= false then
    love.graphics.setColor(1, 1, 1, 0.18)
    local mapW, mapH = source.cellWidth * CELL, source.cellHeight * CELL
    for gx = x0, x1 + 1 do
      local px = gx * CELL
      love.graphics.line(px, y0 * CELL, px, math.min(mapH, (y1 + 1) * CELL))
    end
    for gy = y0, y1 + 1 do
      local py = gy * CELL
      love.graphics.line(x0 * CELL, py, math.min(mapW, (x1 + 1) * CELL), py)
    end
  end
  local mapPx = source.cellWidth * CELL
  local mapPy = source.cellHeight * CELL
  love.graphics.setColor(0.12, 0.12, 0.14, 0.9)
  love.graphics.rectangle("line", -1, -1, mapPx + 2, mapPy + 2)
  love.graphics.setColor(0.35, 0.95, 0.5, 1)
  love.graphics.rectangle("line", 0, 0, mapPx, mapPy)
  drawSelections(S, source)
  drawWarpNodes(S, source)
  if S.mapWorkspace then
    local Maps = require("Maps")
    Maps.drawEventOverlays(S)
  end
  do
    local hoverCx = math.floor(((Kit.mouseX - vx) / zoom + (S.builderCamX or 0)) / CELL)
    local hoverCy = math.floor(((Kit.mouseY - vy) / zoom + (S.builderCamY or 0)) / CELL)
    if Kit.hit(vx, vy, vw, vh)
        and hoverCx >= 0 and hoverCy >= 0
        and hoverCx < source.cellWidth and hoverCy < source.cellHeight then
      drawGhostPen(S, hoverCx, hoverCy)
    end
  end
  love.graphics.pop()
  love.graphics.setScissor()

  local over = Kit.hit(vx, vy, vw, vh)
  S._builderViewHit = over
  local function mouseCell()
    local worldX = (Kit.mouseX - vx) / zoom + (S.builderCamX or 0)
    local worldY = (Kit.mouseY - vy) / zoom + (S.builderCamY or 0)
    return math.floor(worldX / CELL), math.floor(worldY / CELL)
  end
  local cx, cy = mouseCell()
  local inMap = cx >= 0 and cy >= 0
    and cx < source.cellWidth and cy < source.cellHeight
  if over and inMap then
    S.builderHoverX, S.builderHoverY = cx, cy
    S._mapHoverCx, S._mapHoverCy = cx, cy
  elseif not over then
    S._mapHoverCx, S._mapHoverCy = nil, nil
  end

  local middle = love.mouse and love.mouse.isDown and love.mouse.isDown(3)
  local rmb = love.mouse and love.mouse.isDown and love.mouse.isDown(2)
  local space = love.keyboard and love.keyboard.isDown
    and (love.keyboard.isDown("space") or love.keyboard.isDown("lalt"))
  local ctrl = love.keyboard and love.keyboard.isDown
    and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
      or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui"))
  local tool = S.builderTool or "pencil"
  local eventTool = EVENT_TOOL_BY_ID[tool]
  local panning = tool == "pan" or middle or space
  local stencilReady = type(source.stencilImage) == "string"
    and source.stencilImage ~= ""
    and source.stencilVisible ~= false
  local movingStencil = stencilReady and not panning
    and (S.builderStencilMove or ctrl)
  local stencilDrag = S._builderDrag and S._builderDrag.stencil
  local stencilHandled = false
  if not Kit.blockClicks and (over or stencilDrag)
      and (stencilDrag or (Kit.mouseDown and movingStencil)) then
    if Kit.mouseDown then
      if not stencilDrag then
        App.beginEditBatch()
        S._builderDrag = {
          stencil = true, mx = Kit.mouseX, my = Kit.mouseY,
          x = tonumber(source.stencilX) or 0,
          y = tonumber(source.stencilY) or 0,
        }
      else
        source.stencilX = S._builderDrag.x
          + (Kit.mouseX - S._builderDrag.mx) / zoom
        source.stencilY = S._builderDrag.y
          + (Kit.mouseY - S._builderDrag.my) / zoom
      end
    elseif stencilDrag then
      App.markDirty()
      App.endEditBatch()
      S._builderDrag = nil
    end
    stencilHandled = true
  end
  if over and inMap and rmb and not S._builderRmbWasDown
      and not Kit.blockClicks and not space then
    local ref, layerIndex = sourceAtCell(S, source, cx, cy)
    if ref then
      S.builderSourceId, S.builderTile = ref.source, ref.tile
      S.builderLayer = layerIndex
      clearStamp(S)
      if tool == "picker" then S.builderTool = "pencil" end
      if LayeredMap.isRuntimeSource(ref.source) then
        S.mapPaletteTileset = LayeredMap.runtimeTilesetId(ref.source)
      end
      S.status = string.format("Copied 16x16 tile %s", tostring(ref.tile))
    end
  end
  S._builderRmbWasDown = rmb and true or false
  local eventHandled = false
  if stencilHandled then
    -- Stencil drag owns this pointer gesture.
  elseif eventTool and not Kit.blockClicks then
    local Maps = require("Maps")
    local drag = S._builderEvent
    if over and inMap and Kit.mouseClicked and not drag then
      local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
      local kind, index = Maps.pickEventAt(S, cx, cy)
      App.beginEditBatch()
      if kind and not shift then
        Maps.selectEvent(S, kind, index)
        S._builderEvent = { move = true, kind = kind, index = index,
          lastX = cx, lastY = cy }
        S.status = string.format("Selected %s #%d - drag to move", kind, index)
      else
        S._builderEvent = { click = true, x = cx, y = cy,
          mx = Kit.mouseX, my = Kit.mouseY,
          camX = S.builderCamX or 0, camY = S.builderCamY or 0,
          moved = false }
      end
      drag = S._builderEvent
      eventHandled = true
    elseif Kit.mouseDown and drag then
      if drag.move and inMap and (cx ~= drag.lastX or cy ~= drag.lastY) then
        drag.lastX, drag.lastY = cx, cy
        Maps.moveEvent(S, drag.kind, drag.index, cx, cy, App)
      elseif drag.click then
        local dx, dy = Kit.mouseX - drag.mx, Kit.mouseY - drag.my
        if math.abs(dx) > 3 or math.abs(dy) > 3 then
          drag.moved = true
          S.builderCamX = drag.camX - dx / zoom
          S.builderCamY = drag.camY - dy / zoom
        end
      end
      eventHandled = true
    elseif drag and not Kit.mouseDown then
      if drag.click and not drag.moved and eventTool.mapTool ~= "select" then
        Maps.applyEventAtCell(S, eventTool.mapTool, drag.x, drag.y, App)
      elseif drag.click and not drag.moved then
        Maps.applyEventAtCell(S, "select", drag.x, drag.y, App)
      end
      App.endEditBatch()
      S._builderEvent = nil
      eventHandled = true
    end
  elseif S._builderEvent then
    App.endEditBatch()
    S._builderEvent = nil
  end
  if stencilHandled then
    -- Stencil drag owns this pointer gesture.
  elseif eventHandled then
    -- Event interaction owns this pointer gesture.
  elseif over and inMap and Kit.mouseClicked and not Kit.blockClicks
      and (tool == "fill" or tool == "picker" or tool == "warp") then
    if tool == "fill" then
      App.beginEditBatch()
      floodFill(S, source, cx, cy, App)
      App.endEditBatch()
    elseif tool == "picker" then
      local ref, layerIndex = sourceAtCell(S, source, cx, cy)
      if ref then
        S.builderSourceId, S.builderTile = ref.source, ref.tile
        S.builderLayer = layerIndex
        clearStamp(S)
        S.builderTool = "pencil"
        S.status = "Picked tile — Pencil armed"
      end
    else
      completeWarp(S, App, { map = S.builderMapId, x = cx, y = cy })
    end
  elseif Kit.mouseDown and not Kit.blockClicks and not S._assemblyDrag
      and (over or S._builderDrag) then
    if panning then
      if not S._builderDrag or not S._builderDrag.pan then
        S._builderDrag = {
          pan = true, mx = Kit.mouseX, my = Kit.mouseY,
          camX = S.builderCamX or 0, camY = S.builderCamY or 0,
        }
      else
        S.builderCamX = S._builderDrag.camX
          - (Kit.mouseX - S._builderDrag.mx) / zoom
        S.builderCamY = S._builderDrag.camY
          - (Kit.mouseY - S._builderDrag.my) / zoom
      end
    elseif inMap and (tool == "rectangle" or tool == "select" or tool == "eraser") then
      if not S._builderDrag then
        S._builderDrag = { range = true, x0 = cx, y0 = cy, tool = tool }
      end
      S.builderRangeDraft = {
        x0 = S._builderDrag.x0, y0 = S._builderDrag.y0, x1 = cx, y1 = cy,
      }
    elseif inMap and (tool == "pencil" or tool == "collision") then
      local stroke = S._builderStroke
      if not stroke or stroke.tool ~= tool then
        if stroke then App.endEditBatch() end
        App.beginEditBatch()
        stroke = { tool = tool, x = cx, y = cy }
        S._builderStroke = stroke
      end

      local changed = false
      visitCellLine(stroke.x, stroke.y, cx, cy, function(px, py)
        if px >= 0 and py >= 0
            and px < source.cellWidth and py < source.cellHeight then
          if tool == "pencil" then
            changed = paintCell(S, source, px, py, App, false, true) or changed
          else
            changed = paintCollisionCell(S, source, px, py) or changed
          end
        end
      end)
      stroke.x, stroke.y = cx, cy
      if changed then App.markDirty() end
    end
  elseif S._builderDrag then
    if S._builderDrag.range and S.builderRangeDraft then
      local rect = S.builderRangeDraft
      if S._builderDrag.tool == "select" then
        local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
        if not shift then S.builderSelections = {} end
        S.builderSelections = S.builderSelections or {}
        S.builderSelections[#S.builderSelections + 1] = rect
      elseif S._builderDrag.tool == "eraser" then
        App.beginEditBatch()
        applyRectangle(S, source, rect, App, true)
        App.endEditBatch()
      else
        App.beginEditBatch()
        applyRectangle(S, source, rect, App, false)
        App.endEditBatch()
      end
    end
    S._builderDrag = nil
    S.builderRangeDraft = nil
  end

  if not Kit.mouseDown and S._builderStroke then
    App.endEditBatch()
    S._builderStroke = nil
  end

  love.graphics.setColor(1, 1, 1, 1)
  local coord = inMap and string.format("cell %d, %d", cx, cy) or ""
  Kit.text("micro", coord, vx + 6 * Kit.scale, vy + vh - 18 * Kit.scale, PAL.heading)
end

local function filteredMapIds(S)
  local query = tostring(S.builderMapQuery or ""):upper()
  local ids = {}
  for _, id in ipairs(LayeredMap.allMapIds(S)) do
    if query == "" or id:upper():find(query, 1, true) then
      ids[#ids + 1] = id
    else
      local map = S.project.maps and S.project.maps[id]
      local label = map and map.label
      if type(label) == "string" and label:upper():find(query, 1, true) then
        ids[#ids + 1] = id
      end
    end
  end
  return ids
end

-- Map and tileset browsers

local function newMapTilesets(S)
  local ids = sortedKeys(Generation.dataTilesets(S))
  if #ids == 0 then
    ids[1] = Generation.isGen2(S) and "TILESET_JOHTO" or "OVERWORLD"
  end
  return ids
end

local function beginNewMap(S)
  local ids = newMapTilesets(S)
  local selected = ids[1]
  for _, id in ipairs(ids) do
    if id == "OVERWORLD" or id == "TILESET_JOHTO" then selected = id; break end
  end
  S.builderNewMap = {
    id = "NEW_MAP", width = "20", height = "18", tileset = selected,
  }
  Kit.blur()
end

local function drawNewMapForm(S, x, y, w, App)
  local draft = S.builderNewMap
  if not draft then return end
  Kit.text("micro", "Map ID", x, y + 5 * Kit.scale, PAL.caption)
  draft.id = Kit.textfield("builder_new_map_id", x + 52 * Kit.scale, y,
    w - 52 * Kit.scale, 24 * Kit.scale, draft.id, "MY_NEW_MAP")
  y = y + 30 * Kit.scale
  Kit.text("micro", "Size", x, y + 5 * Kit.scale, PAL.caption)
  draft.width = Kit.textfield("builder_new_map_w", x + 52 * Kit.scale, y,
    64 * Kit.scale, 24 * Kit.scale, draft.width, "20")
  Kit.text("micro", "x", x + 121 * Kit.scale, y + 5 * Kit.scale, PAL.muted)
  draft.height = Kit.textfield("builder_new_map_h", x + 134 * Kit.scale, y,
    64 * Kit.scale, 24 * Kit.scale, draft.height, "18")
  Kit.text("micro", "cells", x + 203 * Kit.scale, y + 5 * Kit.scale, PAL.muted)
  y = y + 30 * Kit.scale

  local tilesets = newMapTilesets(S)
  local selectedIndex = 1
  for index, id in ipairs(tilesets) do
    if id == draft.tileset then selectedIndex = index; break end
  end
  if Kit.stepper(x, y, 24 * Kit.scale, 24 * Kit.scale, "<") then
    selectedIndex = ((selectedIndex - 2) % #tilesets) + 1
    draft.tileset = tilesets[selectedIndex]
  end
  Kit.textCenter("micro", Kit.ellipsize("micro", draft.tileset, w - 56 * Kit.scale),
    x + 28 * Kit.scale, y + 5 * Kit.scale, w - 56 * Kit.scale, PAL.heading)
  if Kit.stepper(x + w - 24 * Kit.scale, y, 24 * Kit.scale, 24 * Kit.scale, ">") then
    selectedIndex = (selectedIndex % #tilesets) + 1
    draft.tileset = tilesets[selectedIndex]
  end
  y = y + 31 * Kit.scale

  local width, height = tonumber(draft.width), tonumber(draft.height)
  local validSize = width and height and width >= 2 and height >= 2
    and width % 2 == 0 and height % 2 == 0
  local half = (w - 4 * Kit.scale) / 2
  if Kit.button(x, y, half, 25 * Kit.scale, "Create", {
      kind = "good", enabled = validSize,
      tooltip = "Map dimensions must be even 16x16-cell values",
    }) then
    local source = LayeredMap.createMap(
      S, draft.id, width, height, draft.tileset)
    S.builderNewMap = nil
    S.builderMapId = source.id
    S.builderLayer = 1
    S.builderSourceId = LayeredMap.runtimeSourceId(source.baseTileset)
    S.builderSelections = {}
    S._builderDoFit = true
    App.markDirty()
    S.status = "Created custom map " .. source.id
  end
  if Kit.button(x + half + 4 * Kit.scale, y, half, 25 * Kit.scale,
      "Cancel", { kind = "ghost" }) then
    S.builderNewMap = nil
    Kit.blur()
  end
end

local function drawMapList(S, x, y, w, h, App)
  Kit.card(x, y, w, h, 10 * Kit.scale)
  Kit.text("caption", "MAPS", x + 10 * Kit.scale, y + 8 * Kit.scale, PAL.heading)
  S.builderMapQuery = Kit.textfield("builder_map_search",
    x + 10 * Kit.scale, y + 28 * Kit.scale, w - 20 * Kit.scale,
    26 * Kit.scale, S.builderMapQuery or "", "Filter map IDs")
  local ids = filteredMapIds(S)
  if not S.builderMapId then
    S.builderMapId = sortedKeys(S.project.layeredMaps)[1] or ids[1]
  end
  local rowH = 25 * Kit.scale
  local listY = y + 60 * Kit.scale
  local footerH = (S.mapWorkspace and 34
    or (S.builderNewMap and 154 or 66)) * Kit.scale
  local listH = math.max(rowH, h - (listY - y) - footerH)
  local perPage = math.max(1, math.floor(listH / rowH))
  local offset = clamp(S.builderMapOffset or 0, 0, math.max(0, #ids - perPage))
  local innerW = w - 28 * Kit.scale
  local scrollId = "builderMapOffset"
  offset = Kit.scroll(x + 8 * Kit.scale, listY, w - 16 * Kit.scale, listH,
    offset, #ids, perPage, 3, scrollId)
  Kit.pushClip(x + 8 * Kit.scale, listY, innerW, listH)
  for row = 1, perPage do
    local id = ids[offset + row]
    if not id then break end
    local ry = listY + (row - 1) * rowH
    local layered = S.project.layeredMaps[id] ~= nil
    if Kit.row(x + 8 * Kit.scale, ry, innerW, rowH - 2 * Kit.scale,
        id == S.builderMapId, PAL.blue, 5 * Kit.scale) then
      S.builderMapId = id
      S.mapId = id
      if not layered then S.builderPane = "details" end
      S.builderLayer = 1
      S.builderSelections = {}
      local src = S.project.layeredMaps[id]
      if src and src.baseTileset then
        S.builderSourceId = LayeredMap.runtimeSourceId(src.baseTileset)
        S.builderTile, S.builderTileOffset = 0, 0
      end
      if S.builderWarpDraft and not S.project.layeredMaps[id] then
        if S.mapWorkspace then
          S.builderWarpDraft = nil
          S.status = "Transfer cancelled; click Edit Map before changing this map"
        else
          ensureLayeredDestination(S, App)
        end
      end
    end
    Kit.text("micro", Kit.ellipsize("micro", id, innerW - 42 * Kit.scale),
      x + 14 * Kit.scale, ry + 6 * Kit.scale,
      layered and PAL.heading or PAL.muted)
    if layered then
      Kit.textRight("micro", "EDIT", x + innerW, ry + 6 * Kit.scale, PAL.green)
    end
  end
  Kit.popClip()
  S.builderMapOffset = Kit.scrollbar(x + w - 18 * Kit.scale, listY,
    10 * Kit.scale, listH, offset, #ids, perPage, scrollId)

  local fy = y + h - footerH + 6 * Kit.scale
  if not S.mapWorkspace and S.builderNewMap then
    drawNewMapForm(S, x + 8 * Kit.scale, fy, w - 16 * Kit.scale, App)
    return
  end
  local half = (w - 24 * Kit.scale) / 2
  if not S.mapWorkspace and Kit.button(x + 8 * Kit.scale, fy, half, 26 * Kit.scale, "+ New", {
      kind = "good", tooltip = "Create a blank layered custom map",
    }) then
    beginNewMap(S)
  end
  if not S.mapWorkspace then
    local canConvert = S.builderMapId and not mapSource(S)
    if Kit.button(x + 12 * Kit.scale + half, fy, half, 26 * Kit.scale,
        "Convert", { kind = "accent", enabled = canConvert,
          tooltip = "Preserve this map and open it as editable 16x16 layers" }) then
      ensureLayeredDestination(S, App)
    end
  end
  local selected = S.builderMapId or "none"
  Kit.text("micro", Kit.ellipsize("micro", selected, w - 16 * Kit.scale),
    x + 8 * Kit.scale, fy + (S.mapWorkspace and 8 or 34) * Kit.scale, PAL.faint)
end

local function importTileset(S, App)
  if not (S.project and S.path) then return end
  App.pickFile("Import 16x16 tileset PNG",
    "PNG (*.png)|*.png|All files (*.*)|*.*", function(picked)
      local base = App.assetBaseName(picked, "tiles.png")
      if not base:lower():match("%.png$") then base = base .. ".png" end
      local rel = "assets/mapbuilder/sources/" .. base
      App.importToMod(picked, rel, function(imported)
        Preview.invalidatePath(imported)
        local image = Preview.image(S, imported)
        if not image then
          S.status = "Imported PNG could not be decoded"
          return
        end
        local width, height = image:getDimensions()
        local stem = base:gsub("%.[Pp][Nn][Gg]$", "")
        local source, err = LayeredMap.addTileSource(
          S.project, stem, imported, width, height)
        if not source then
          S.status = "Tileset import failed: " .. tostring(err)
          return
        end
        S.builderSourceId = source.id
        S.builderTile = 0
        App.markDirty()
        S.status = string.format("Imported %s — %d tiles", source.id, source.count)
      end)
    end)
end

local function replaceTileSource(S, App, source)
  if not (source and not source.runtimeTileset) then
    S.status = "Select a custom PNG source to replace"
    return
  end
  App.pickFile("Replace 16x16 tileset PNG",
    "PNG (*.png)|*.png|All files (*.*)|*.*", function(picked)
      local base = App.assetBaseName(picked, "tiles.png")
      if not base:lower():match("%.png$") then base = base .. ".png" end
      local rel = "assets/mapbuilder/sources/" .. base
      App.importToMod(picked, rel, function(imported)
        local image = Preview.image(S, imported)
        if not image then S.status = "Replacement PNG could not be decoded"; return end
        local width, height = image:getDimensions()
        if width < 16 or height < 16 or width % 16 ~= 0 or height % 16 ~= 0 then
          S.status = "Replacement dimensions must be multiples of 16 pixels"
          return
        end
        source.image = imported
        source.columns = width / 16
        source.count = (width / 16) * (height / 16)
        for tile in pairs(source.animations or {}) do
          if tile >= source.count then source.animations[tile] = nil end
        end
        S.builderTile = clamp(S.builderTile or 0, 0, source.count - 1)
        App.markDirty()
        S.status = "Replaced source " .. tostring(source.id)
      end)
    end)
end

local function exportSourcesToMod(S, sources)
  local result = TilesetExport.exportSources(S, sources)
  if result.ok then
    S.status = string.format("Exported %d tileset PNG%s to %s", result.count,
      result.count == 1 and "" or "s", result.folder)
  else
    S.status = string.format("Exported %d; %d failed (%s)", result.count,
      #result.failures, table.concat(result.failures, "; "))
  end
  return result.ok, result.count, result.failures
end

function MapBuilder.exportAllTilesets(S, mapId)
  local ids = LayeredMap.sourceIds(S, mapId or S.builderMapId)
  local sources = {}
  for _, id in ipairs(ids) do
    local item = LayeredMap.sourceDescriptor(S, id)
    if item then sources[#sources + 1] = item end
  end
  return exportSourcesToMod(S, sources)
end

local function drawTilePalette(S, source, x, y, w, h, App)
  Kit.card(x, y, w, h, 10 * Kit.scale)
  Kit.text("caption", "TILESETS", x + 10 * Kit.scale, y + 8 * Kit.scale, PAL.heading)
  if Kit.button(x + w - 90 * Kit.scale, y + 5 * Kit.scale,
      80 * Kit.scale, 24 * Kit.scale, "Import PNG", {
        kind = "good", tooltip = "Add a custom PNG arranged as 16x16 tiles",
      }) then importTileset(S, App) end

  local ids = source and LayeredMap.sourceIds(S, source.id) or sortedKeys(
    S.project.mapTileSources)
  local preferred = source and source.baseTileset
    and LayeredMap.runtimeSourceId(source.baseTileset)
  if not S.builderSourceId or not LayeredMap.sourceDescriptor(S, S.builderSourceId) then
    S.builderSourceId = (preferred and LayeredMap.sourceDescriptor(S, preferred)
      and preferred) or ids[1]
  end
  local sy = y + 34 * Kit.scale
  local sourceIndex = 1
  for index, id in ipairs(ids) do
    if id == S.builderSourceId then sourceIndex = index; break end
  end
  if Kit.stepper(x + 8 * Kit.scale, sy, 26 * Kit.scale, 24 * Kit.scale, "<",
      { tooltip = "Previous tileset source" }) and #ids > 0 then
    sourceIndex = ((sourceIndex - 2) % #ids) + 1
    S.builderSourceId, S.builderTile, S.builderTileOffset = ids[sourceIndex], 0, 0
    clearStamp(S)
  end
  local sourceLabel = LayeredMap.sourceDescriptor(S, S.builderSourceId)
  sourceLabel = sourceLabel and (sourceLabel.name or sourceLabel.id) or "No source"
  Kit.textCenter("micro", Kit.ellipsize("micro", sourceLabel, w - 84 * Kit.scale),
    x + 38 * Kit.scale, sy + 5 * Kit.scale, w - 76 * Kit.scale, PAL.heading)
  if Kit.stepper(x + w - 34 * Kit.scale, sy, 26 * Kit.scale, 24 * Kit.scale, ">",
      { tooltip = "Next tileset source" }) and #ids > 0 then
    sourceIndex = (sourceIndex % #ids) + 1
    S.builderSourceId, S.builderTile, S.builderTileOffset = ids[sourceIndex], 0, 0
    clearStamp(S)
  end

  Kit.text("micro", string.format("source %d / %d", sourceIndex, #ids),
    x + 10 * Kit.scale, sy + 25 * Kit.scale, PAL.faint)

  local descriptor = LayeredMap.sourceDescriptor(S, S.builderSourceId)
  S.builderPalette = S.builderPalette or "tiles"
  local palY = sy + 42 * Kit.scale
  local chipW = (w - 20 * Kit.scale) / 2
  if Kit.chip(x + 8 * Kit.scale, palY, chipW - 2 * Kit.scale, 22 * Kit.scale, "Tiles",
      S.builderPalette == "tiles", PAL.blue, PAL.steel,
      "Pick a single 16x16 tile") then
    S.builderPalette = "tiles"
  end
  if Kit.chip(x + 10 * Kit.scale + chipW, palY, chipW - 2 * Kit.scale, 22 * Kit.scale,
      "Assembly", S.builderPalette == "assembly", PAL.blue, PAL.steel,
      "Stamp a house or decoration from its upper-left tile") then
    S.builderPalette = "assembly"
  end

  local gridY = palY + 26 * Kit.scale
  local footerH = (S.builderSourceOptions and 118 or 34) * Kit.scale
  local gridH = math.max(20 * Kit.scale,
    h - (gridY - y) - footerH - 8 * Kit.scale)
  if not descriptor then
    Kit.emptyBox(x + 8 * Kit.scale, gridY, w - 16 * Kit.scale, gridH,
      "Import a 16x16 PNG tileset")
    return
  end

  local assembly = S.builderPalette == "assembly"
  local runtime = descriptor.runtimeTileset and true or false
  local tileSize = (assembly and runtime) and 40 * Kit.scale or 34 * Kit.scale
  local columns = math.max(1, math.floor((w - 28 * Kit.scale) / tileSize))
  if assembly and not runtime then
    columns = math.max(1, descriptor.columns or 1)
    tileSize = math.max(12 * Kit.scale,
      math.floor((w - 28 * Kit.scale) / columns))
  end
  local rows = math.max(1, math.floor(gridH / tileSize))
  local perPage = columns * rows
  local blockCount = runtime and #(descriptor.tileset and descriptor.tileset.blocks or {}) or 0
  local count = assembly and runtime and blockCount or (descriptor.count or 0)
  local scrollKey = assembly and "builderAssemblyOffset" or "builderTileOffset"
  local offset = clamp(S[scrollKey] or 0, 0, math.max(0, count - perPage))
  offset = Kit.scroll(x + 8 * Kit.scale, gridY, w - 16 * Kit.scale, gridH,
    offset, count, perPage, columns, scrollKey)
  offset = math.floor(offset / columns) * columns

  local function stampHasTile(tile)
    local cells = S.builderStamp and S.builderStamp.cells
    if not cells then return (S.builderTile or 0) == tile end
    for i = 1, #cells do
      if cells[i].tile == tile then return true end
    end
    return false
  end
  local function stampHasBlock(blockId)
    local cells = S.builderStamp and S.builderStamp.cells
    if not cells then return math.floor((S.builderTile or 0) / 4) == blockId end
    for i = 1, #cells do
      if math.floor(cells[i].tile / 4) == blockId then return true end
    end
    return false
  end

  local drag = S._assemblyDrag
  if assembly and Kit.mouseDown and not Kit.blockClicks
      and Kit.hit(x + 8 * Kit.scale, gridY, w - 28 * Kit.scale, gridH) then
    local col = math.floor((Kit.mouseX - (x + 8 * Kit.scale)) / tileSize)
    local row = math.floor((Kit.mouseY - gridY) / tileSize)
    if col >= 0 and row >= 0 and col < columns then
      local index = offset + row * columns + col
      if index >= 0 and index < count then
        if not drag or drag.source ~= S.builderSourceId then
          drag = { source = S.builderSourceId, runtime = runtime,
            columns = columns, first = index }
          S._assemblyDrag = drag
        end
        drag.last = index
        if runtime then
          setStamp(S, S.builderSourceId,
            runtimeAssemblyCells(drag.first, drag.last, columns, blockCount))
        else
          setStamp(S, S.builderSourceId,
            sheetAssemblyCells(descriptor, drag.first, drag.last))
        end
      end
    end
  elseif drag and not Kit.mouseDown then
    S._assemblyDrag = nil
  end

  Kit.pushClip(x + 8 * Kit.scale, gridY, w - 28 * Kit.scale, gridH)
  for slot = 0, perPage - 1 do
    local index = offset + slot
    if index >= count then break end
    local col, row = slot % columns, math.floor(slot / columns)
    local tx, ty = x + 8 * Kit.scale + col * tileSize, gridY + row * tileSize
    local selected
    if assembly and runtime then
      selected = stampHasBlock(index)
    else
      selected = stampHasTile(index)
    end
    if selected then
      love.graphics.setColor(0.2, 0.65, 1, 0.35)
      love.graphics.rectangle("fill", tx, ty, tileSize - 2, tileSize - 2, 4, 4)
    end
    local inner = tileSize - 6 * Kit.scale
    drawChecker(tx + 3 * Kit.scale, ty + 3 * Kit.scale, inner)
    if assembly and runtime then
      local half = inner / 2
      for dy = 0, 1 do
        for dx = 0, 1 do
          drawSourceTile(S, descriptor, index * 4 + dy * 2 + dx,
            tx + 3 * Kit.scale + dx * half,
            ty + 3 * Kit.scale + dy * half, half, 1)
        end
      end
    else
      drawSourceTile(S, descriptor, index,
        tx + 3 * Kit.scale, ty + 3 * Kit.scale, inner, 1)
      if descriptor.animations and descriptor.animations[index] then
        love.graphics.setColor(PAL.green)
        love.graphics.circle("fill", tx + tileSize - 8 * Kit.scale,
          ty + 7 * Kit.scale, 5 * Kit.scale)
        Kit.textCenter("micro", "A", tx + tileSize - 13 * Kit.scale,
          ty + 1 * Kit.scale, 10 * Kit.scale, PAL.greenInk)
      end
    end
    if not assembly and Kit.press(tx, ty, tileSize - 2, tileSize - 2) then
      S.builderTile = index
      clearStamp(S)
    end
  end
  Kit.popClip()
  S[scrollKey] = Kit.scrollbar(x + w - 18 * Kit.scale, gridY,
    10 * Kit.scale, gridH, offset, count, perPage, scrollKey)

  local fy = y + h - footerH + 4 * Kit.scale
  local bw = (w - 20 * Kit.scale) / 2
  local custom = descriptor and not descriptor.runtimeTileset
  if assembly and custom then
    if Kit.button(x + 8 * Kit.scale, fy, bw, 24 * Kit.scale,
        "Full image", { kind = "accent",
          tooltip = "Stamp this whole PNG from its upper-left tile" }) then
      local last = math.max(0, (descriptor.count or 1) - 1)
      setStamp(S, S.builderSourceId, sheetAssemblyCells(descriptor, 0, last))
      S.status = "Assembly: full image"
    end
  elseif Kit.button(x + 8 * Kit.scale, fy, bw, 24 * Kit.scale,
      custom and "Animate selected" or "Edit game tileset", { kind = "accent",
        tooltip = custom
          and "Create or edit an animation for the selected tile"
          or "Open this game tileset in the graphics editor" }) then
    if custom then
      S.builderPane = "tileset"
    elseif descriptor and descriptor.runtimeTileset then
      S.tab = "gfx"
      S.gfxMode = "tilesets"
      S.tilesetEditId = descriptor.runtimeTileset
      S.gfxTilesetPane = "flags"
    end
  end
  if Kit.button(x + 12 * Kit.scale + bw, fy, bw, 24 * Kit.scale,
      S.builderSourceOptions and "Hide options" or "More options", {
        kind = "ghost", tooltip = "Show import, replace, and export tools" }) then
    S.builderSourceOptions = not S.builderSourceOptions
  end
  if S.builderSourceOptions then
    fy = fy + 28 * Kit.scale
    if Kit.button(x + 8 * Kit.scale, fy, bw, 24 * Kit.scale,
        custom and "Replace image" or "Import tile image", { kind = "good",
          tooltip = custom and "Replace this source without changing painted cells"
            or "Add your own 16x16 tile image" }) then
      if custom then replaceTileSource(S, App, descriptor)
      else importTileset(S, App) end
    end
    if Kit.button(x + 12 * Kit.scale + bw, fy, bw, 24 * Kit.scale,
        "Import TMX", { kind = "accent",
          tooltip = "Import engine TMX, or convert Pokemonium TMX to blocks" }) then
      App.pickFile("Tiled TMX",
        "Tiled map (*.tmx)|*.tmx|All (*.*)|*.*", function(path)
          local Maps = require("Maps")
          Maps.importTmx(S, path, App)
        end)
    end
    fy = fy + 28 * Kit.scale
    if Kit.button(x + 8 * Kit.scale, fy, bw, 24 * Kit.scale,
        "Export TMX", { kind = "good",
          tooltip = "Export this map as a Tiled .tmx (32x32 blocks)" }) then
      local Maps = require("Maps")
      Maps.exportTmx(S, App)
    end
    fy = fy + 28 * Kit.scale
    if Kit.button(x + 8 * Kit.scale, fy, bw, 24 * Kit.scale,
        "Export selected", { kind = "ghost", enabled = descriptor ~= nil,
          tooltip = "Export this source to the mod's workspace folder" }) then
      exportSourcesToMod(S, { descriptor })
    end
    if Kit.button(x + 12 * Kit.scale + bw, fy, bw, 24 * Kit.scale,
        "Export all", { kind = "ghost", enabled = #ids > 0,
          tooltip = "Export every source to the mod's workspace folder" }) then
      MapBuilder.exportAllTilesets(S, source.id)
    end
  end
end

-- Toolbars and property panes

local function drawToolbar(S, source, x, y, w, App)
  local s = Kit.scale
  local stackedHeader = w < 460 * s
  local tx, toolY = x, y + (stackedHeader and 64 or 32) * s
  local workspace = S.mapWorkspace
  if workspace then
    S.mapEditMode = S.mapEditMode or "map"
    Kit.text("micro", "EDIT", x, y + 7 * s, PAL.caption)
    local modeX = x + 34 * s
    if Kit.chip(modeX, y, 82 * s, 26 * s, "Paint map",
        S.mapEditMode == "map", PAL.green, PAL.steel) then
      S.mapEditMode = "map"
      if EVENT_TOOL_BY_ID[S.builderTool] then S.builderTool = "pencil" end
    end
    if Kit.chip(modeX + 85 * s, y, 86 * s, 26 * s, "Add events",
        S.mapEditMode == "events", PAL.yellow, PAL.steel) then
      S.mapEditMode = "events"
      if not EVENT_TOOL_BY_ID[S.builderTool] then S.builderTool = "object" end
    end
  end
  local viewY = stackedHeader and y + 32 * s or y
  local zx = stackedHeader and x or x + w - 276 * s
  if Kit.chip(zx, viewY, 88 * s, 26 * s, "Neighbors",
      neighborsEnabled(S), PAL.blue, PAL.steel,
      "Show directly connected maps around this one") then
    S.mapShowNeighbors = not neighborsEnabled(S)
  end
  if not stackedHeader and zx > x + 220 * s then
    if Kit.chip(zx - 128 * s, y, 52 * s, 26 * s, "Grid",
        S.mapShowGrid ~= false, PAL.steel) then
      S.mapShowGrid = S.mapShowGrid == false and true or false
    end
    if Kit.chip(zx - 72 * s, y, 68 * s, 26 * s, "Passage",
        S.mapShowCollision == true, PAL.red, PAL.steel,
        "Show collision without changing tools") then
      S.mapShowCollision = not S.mapShowCollision
    end
  end
  local zc = zx + 92 * s
  if Kit.stepper(zc, viewY, 26 * s, 26 * s, "-") then
    S.builderZoom = clamp((S.builderZoom or 1) - 0.25, 0.25, 8)
  end
  Kit.textCenter("mono", string.format("%.2fx", S.builderZoom or 1),
    zc + 28 * s, viewY + 6 * s, 52 * s, PAL.muted)
  if Kit.stepper(zc + 82 * s, viewY, 26 * s, 26 * s, "+") then
    S.builderZoom = clamp((S.builderZoom or 1) + 0.25, 0.25, 8)
  end
  if Kit.button(zc + 112 * s, viewY, 68 * s, 26 * s,
      "Fit", { kind = "ghost",
        tooltip = "Fit this map in the canvas" }) then
    S._builderDoFit = true
  end

  local allTools = workspace and S.mapEditMode == "events" and EVENT_TOOLS or TOOLS
  local basicTools = workspace and S.mapEditMode == "events"
    and BASIC_EVENT_TOOLS or BASIC_TERRAIN_TOOLS
  local visibleTools = {}
  for _, tool in ipairs(allTools) do
    if S.builderAdvancedTools or basicTools[tool.id]
        or S.builderTool == tool.id then
      visibleTools[#visibleTools + 1] = tool
    end
  end
  Kit.text("micro", "ACTION", x, toolY + 7 * s, PAL.caption)
  tx = x + 50 * s
  for _, tool in ipairs(visibleTools) do
    local bw = math.max(48 * s, Kit.textWidth("micro", tool.label) + 14 * s)
    if tx + bw > x + w and tx > x + 50 * s then
      toolY = toolY + 29 * s
      tx = x + 50 * s
    end
    if Kit.chip(tx, toolY, bw, 26 * s, tool.label,
        (S.builderTool or "pencil") == tool.id, PAL.blue, PAL.steel, tool.tip) then
      S.builderTool = tool.id
      S.builderRangeDraft = nil
      if tool.id ~= "warp" then S.builderWarpDraft = nil end
      if tool.mapTool == "warp" then S.builderPane = "warps" end
      if tool.mapTool == "sign" then S.mapSection = "signs"
      elseif tool.mapTool then S.mapSection = "objects" end
      if tool.mapTool and tool.mapTool ~= "warp" then
        S.builderPane = "details"
      end
    end
    tx = tx + bw + 3 * s
  end
  local moreLabel = S.builderAdvancedTools and "Fewer tools" or "More tools"
  local moreW = Kit.textWidth("micro", moreLabel) + 18 * s
  if tx + moreW > x + w and tx > x + 50 * s then
    toolY = toolY + 29 * s
    tx = x + 50 * s
  end
  if Kit.chip(tx, toolY, moreW, 26 * s, moreLabel,
      S.builderAdvancedTools == true, PAL.yellow, PAL.steel,
      "Show selection, collision, warp, trainer, and other advanced tools") then
    S.builderAdvancedTools = not S.builderAdvancedTools
  end

  local barY = toolY + 31 * s
  local barBottom = barY + 24 * s
  if EVENT_TOOL_BY_ID[S.builderTool] then
    if Kit.button(x, barY, 62 * s, 24 * s, "Dialog",
        { kind = "ghost", tooltip = "Open dialog for this map or selected event" }) then
      local Dialog = require("Dialog")
      Dialog.openMap(S, S.mapId)
    end
    Kit.text("micro", Kit.ellipsize("micro",
      "Click a cell to place; drag an existing marker to move it", w - 76 * s),
      x + 70 * s, barY + 5 * s, PAL.muted)
    local bx = x
    if S.builderTool == "trainer" then
      local fieldY = barY + 29 * s
      Kit.text("micro", "Class", bx, fieldY + 5 * s, PAL.caption)
      S.trainerId = Kit.textfield("builder_trainer_class", bx + 42 * s, fieldY,
        132 * s, 24 * s, S.trainerId or "OPP_YOUNGSTER",
        "Trainer class"):upper():gsub("%s+", "_")
      Kit.text("micro", "Party", bx + 184 * s, fieldY + 5 * s, PAL.caption)
      local party = Kit.textfield("builder_trainer_party", bx + 224 * s,
        fieldY, 48 * s, 24 * s,
        tostring(S.placeTrainerParty or 1), "1")
      S.placeTrainerParty = math.max(1, math.floor(tonumber(party) or 1))
      barBottom = fieldY + 24 * s
    elseif S.builderTool == "wild" then
      local fieldY = barY + 29 * s
      Kit.text("micro", "Species", bx, fieldY + 5 * s, PAL.caption)
      S.placeWildSpecies = Kit.textfield("builder_wild_species", bx + 52 * s, fieldY,
        132 * s, 24 * s, S.placeWildSpecies or "ARTICUNO",
        "Species"):upper():gsub("%s+", "_")
      Kit.text("micro", "Level", bx + 194 * s, fieldY + 5 * s, PAL.caption)
      local level = Kit.textfield("builder_wild_level", bx + 236 * s,
        fieldY, 48 * s, 24 * s,
        tostring(S.placeWildLevel or 50), "50")
      S.placeWildLevel = math.max(1, math.min(100,
        math.floor(tonumber(level) or 50)))
      barBottom = fieldY + 24 * s
    end
  elseif (S.builderTool or "pencil") == "collision" then
    Kit.text("micro", "PASSAGE", x, barY + 5 * s, PAL.caption)
    local bx, modeY = x + 56 * s, barY
    for _, mode in ipairs(LayeredMap.COLLISION_MODES) do
      local bw = Kit.textWidth("micro", mode) + 16 * s
      if bx + bw > x + w and bx > x + 56 * s then
        modeY, bx = modeY + 27 * s, x + 56 * s
        barBottom = modeY + 24 * s
      end
      if Kit.chip(bx, modeY, bw, 24 * s, mode,
          (S.builderCollision or "solid") == mode, PAL.green, PAL.steel) then
        S.builderCollision = mode
      end
      bx = bx + bw + 3 * s
    end
  elseif (S.builderTool or "pencil") == "select" then
    local count = #(S.builderSelections or {})
    Kit.text("micro", string.format("%d selected range(s)", count),
      x, barY + 5 * Kit.scale, PAL.muted)
    local actionX, actionY = x, barY + 27 * s
    local function slot(width)
      if actionX + width > x + w and actionX > x then
        actionX, actionY = x, actionY + 27 * s
      end
      local sx, sy = actionX, actionY
      actionX = actionX + width + 4 * s
      barBottom = math.max(barBottom, actionY + 24 * s)
      return sx, sy
    end
    local bx, by = slot(34 * s)
    if Kit.button(bx, by, 34 * s, 24 * s,
        "All", { kind = "accent" }) then
      S.builderSelections = { { x0 = 0, y0 = 0,
        x1 = source.cellWidth - 1, y1 = source.cellHeight - 1 } }
    end
    bx, by = slot(48 * s)
    if Kit.button(bx, by, 48 * s, 24 * s,
        "Copy", { kind = "accent", enabled = count > 0 }) then
      copySelection(S, source)
    end
    bx, by = slot(50 * s)
    if Kit.button(bx, by, 50 * s, 24 * s,
        "Paste", { kind = "good", enabled = S.builderClip ~= nil }) then
      local x0, y0 = selectionBounds(S)
      pasteSelection(S, source, App,
        x0 or S.builderHoverX or 0, y0 or S.builderHoverY or 0)
    end
    for _, move in ipairs({ { "<", -1, 0 }, { ">", 1, 0 },
        { "^", 0, -1 }, { "v", 0, 1 } }) do
      bx, by = slot(24 * s)
      if Kit.button(bx, by, 24 * s, 24 * s, move[1],
          { kind = "ghost", enabled = count > 0,
            tooltip = "Nudge selected cells" }) then
        nudgeSelection(S, source, move[2], move[3], App)
      end
    end
    bx, by = slot(78 * s)
    if Kit.button(bx, by, 78 * s, 24 * s,
        "Clear tiles", { kind = "danger", enabled = count > 0,
          tooltip = "Erase the active layer inside every selected range" }) then
      clearSelections(S, source, App)
    end
    bx, by = slot(68 * s)
    if Kit.button(bx, by, 68 * s, 24 * s,
        "Deselect", { kind = "ghost", enabled = count > 0 }) then
      S.builderSelections = {}
    end
  elseif (S.builderTool or "pencil") == "warp" then
    local draft = S.builderWarpDraft
    local instruction = not draft and "Click the source cell"
      or draft.phase == "destination" and "Select a map, then click the arrival cell"
      or "Select a map, then click the return destination"
    Kit.text("micro", instruction, x, barY + 5 * Kit.scale, PAL.yellow)
    if draft and Kit.button(x + 330 * Kit.scale, barY,
        70 * Kit.scale, 24 * Kit.scale, "Cancel", { kind = "ghost" }) then
      S.builderWarpDraft = nil
      S.status = "Warp placement cancelled"
    end
  else
    local layer = activeLayer(S, source)
    local label = layer and layer.name or "No layer"
    Kit.text("micro", "Active layer: " .. label,
      x, barY + 5 * Kit.scale, PAL.muted)
  end
  return barBottom + 5 * s
end

local function drawStencilSection(S, source, x, y, w, App)
  Kit.text("micro", "STENCIL", x, y, PAL.caption)
  if type(source.stencilImage) == "string" and source.stencilImage ~= "" then
    if Kit.chip(x + w - 84 * Kit.scale, y - 3 * Kit.scale,
        40 * Kit.scale, 20 * Kit.scale, "Move",
        S.builderStencilMove == true, PAL.blue, PAL.steel,
        "Drag the stencil on the canvas. Ctrl-drag also works.") then
      S.builderStencilMove = not S.builderStencilMove
      S.status = S.builderStencilMove
        and "Drag on the canvas to move the stencil"
        or "Pencil paints tiles again"
    end
    if Kit.chip(x + w - 40 * Kit.scale, y - 3 * Kit.scale,
        40 * Kit.scale, 20 * Kit.scale, "Eye",
        source.stencilVisible ~= false, PAL.green, PAL.steel,
        "Show or hide the stencil") then
      source.stencilVisible = source.stencilVisible == false
      App.markDirty()
    end
  else
    Kit.textRight("micro", "Editor only", x + w, y, PAL.muted)
  end
  y = y + 16 * Kit.scale
  local half = (w - 4 * Kit.scale) / 2
  if Kit.button(x, y, half, 25 * Kit.scale, "Use PNG", {
      kind = "accent",
      tooltip = "Trace a screenshot over the tiles. Scale it to match." }) then
    importStencil(S, source, App)
  end
  if Kit.button(x + half + 4 * Kit.scale, y, half, 25 * Kit.scale, "Clear", {
      kind = "ghost",
      enabled = type(source.stencilImage) == "string" and source.stencilImage ~= "",
      tooltip = "Remove the stencil image" }) then
    source.stencilImage = nil
    App.markDirty()
  end
  y = y + 30 * Kit.scale
  if Kit.button(x, y, w, 25 * Kit.scale, "Use as map", {
      kind = "good",
      tooltip = "Resize this map to the PNG and paint Ground as 16x16 tiles" }) then
    usePngAsMap(S, source, App)
  end
  y = y + 30 * Kit.scale
  local stencilName = source.stencilImage
  if type(stencilName) == "string" and stencilName ~= "" then
    stencilName = stencilName:match("[^/\\]+$") or stencilName
    Kit.text("micro", Kit.ellipsize("micro", stencilName, w), x, y, PAL.faint)
    y = y + 16 * Kit.scale
    Kit.text("micro", "Opacity", x, y + 5 * Kit.scale, PAL.caption)
    if Kit.stepper(x + 70 * Kit.scale, y, 26 * Kit.scale, 24 * Kit.scale, "-") then
      source.stencilOpacity = clamp((source.stencilOpacity or 0.45) - 0.1, 0, 1)
      App.markDirty()
    end
    Kit.text("mono", string.format("%.0f%%",
        (source.stencilOpacity or 0.45) * 100),
      x + 102 * Kit.scale, y + 5 * Kit.scale, PAL.heading)
    if Kit.stepper(x + 154 * Kit.scale, y, 26 * Kit.scale, 24 * Kit.scale, "+") then
      source.stencilOpacity = clamp((source.stencilOpacity or 0.45) + 0.1, 0, 1)
      App.markDirty()
    end
    y = y + 32 * Kit.scale
    local stencilImage = Preview.image(S, source.stencilImage)
    local iw, ih = 1, 1
    if stencilImage then iw, ih = stencilImage:getDimensions() end
    local scale = stencilScaleValue(source, iw, ih)
    Kit.text("micro", "Scale", x, y + 5 * Kit.scale, PAL.caption)
    if Kit.stepper(x + 70 * Kit.scale, y, 26 * Kit.scale, 24 * Kit.scale, "-") then
      source.stencilScale = clamp(scale * 0.9, 0.05, 8)
      App.markDirty()
    end
    Kit.text("mono", string.format("%.0f%%", scale * 100),
      x + 102 * Kit.scale, y + 5 * Kit.scale, PAL.heading)
    if Kit.stepper(x + 154 * Kit.scale, y, 26 * Kit.scale, 24 * Kit.scale, "+") then
      source.stencilScale = clamp(scale * 1.1, 0.05, 8)
      App.markDirty()
    end
    if Kit.chip(x + w - 40 * Kit.scale, y + 2 * Kit.scale,
        40 * Kit.scale, 20 * Kit.scale, "Fit",
        false, PAL.green, PAL.steel,
        "Fit the stencil inside the map") then
      source.stencilScale = stencilFitScale(source, iw, ih)
      source.stencilX, source.stencilY = 0, 0
      App.markDirty()
    end
    y = y + 32 * Kit.scale
  else
    Kit.text("micro", "Optional trace image over the tiles", x, y, PAL.muted)
    y = y + 18 * Kit.scale
  end
  return y + 10 * Kit.scale
end

local function drawLayersPane(S, source, x, y, w, h, App)
  FormPane.track(S, "builderLayersScroll", source.id)
  local contentY, view = FormPane.begin(S, "builderLayersScroll", x, y, w, h)
  w = view.contentW
  local by = drawStencilSection(S, source, x, contentY, w, App)
  local rowH = 28 * Kit.scale
  for index, layer in ipairs(source.layers) do
    local ry = by + (index - 1) * rowH
    if Kit.row(x, ry, w, rowH - 2 * Kit.scale,
        S.builderLayer == index, PAL.blue, 5 * Kit.scale) then
      S.builderLayer = index
    end
    Kit.text("micro", Kit.ellipsize("micro", layer.name, w - 88 * Kit.scale),
      x + 7 * Kit.scale, ry + 7 * Kit.scale,
      layer.visible == false and PAL.faint or PAL.heading)
    if Kit.chip(x + w - 80 * Kit.scale, ry + 2 * Kit.scale,
        34 * Kit.scale, 22 * Kit.scale, "Eye", layer.visible ~= false,
        PAL.green, PAL.steel) then
      layer.visible = layer.visible == false and true or false
      App.markDirty()
    end
    if Kit.chip(x + w - 42 * Kit.scale, ry + 2 * Kit.scale,
        40 * Kit.scale, 22 * Kit.scale, "Out", layer.export ~= false,
        PAL.blue, PAL.steel, "Included in the saved game map by default") then
      layer.export = layer.export == false and true or false
      App.markDirty()
    end
  end
  by = by + math.max(1, #source.layers) * rowH + 5 * Kit.scale
  local bw = (w - 4 * Kit.scale) / 2
  if Kit.button(x, by, bw, 25 * Kit.scale, "Add layer", { kind = "good" }) then
    local _, index = LayeredMap.addLayer(source, "Decoration")
    S.builderLayer = index
    App.markDirty()
  end
  if Kit.button(x + bw + 4 * Kit.scale, by, bw, 25 * Kit.scale, "Delete layer",
      { kind = "danger", enabled = (S.builderLayer or 1) > 1,
        tooltip = "Remove the selected layer" }) then
    local ok, err = LayeredMap.removeLayer(source, S.builderLayer or 1)
    if ok then
      S.builderLayer = clamp((S.builderLayer or 1) - 1, 1, #source.layers)
      App.markDirty()
    else S.status = err end
  end
  by = by + 30 * Kit.scale
  if Kit.button(x, by, bw, 25 * Kit.scale, "Move layer up",
      { kind = "accent", tooltip = "Draw this layer above the next layer" }) then
    S.builderLayer = LayeredMap.moveLayer(source, S.builderLayer or 1, 1)
    App.markDirty()
  end
  if Kit.button(x + bw + 4 * Kit.scale, by, bw, 25 * Kit.scale, "Move layer down",
      { kind = "accent", tooltip = "Draw this layer below the previous layer" }) then
    S.builderLayer = LayeredMap.moveLayer(source, S.builderLayer or 1, -1)
    App.markDirty()
  end
  local layer = activeLayer(S, source)
  if layer then
    by = by + 34 * Kit.scale
    Kit.text("micro", "Name", x, by + 5 * Kit.scale, PAL.caption)
    local name = field(App, "builder_layer_name", x + 54 * Kit.scale, by,
      w - 54 * Kit.scale, 24 * Kit.scale, layer.name or layer.id, "Layer name")
    if name ~= (layer.name or layer.id) then layer.name = name end
    by = by + 32 * Kit.scale
    Kit.text("micro", "Opacity", x, by + 5 * Kit.scale, PAL.caption)
    if Kit.stepper(x + 70 * Kit.scale, by, 26 * Kit.scale, 24 * Kit.scale, "-") then
      layer.opacity = clamp((layer.opacity or 1) - 0.1, 0, 1)
      App.markDirty()
    end
    Kit.text("mono", string.format("%.0f%%", (layer.opacity or 1) * 100),
      x + 102 * Kit.scale, by + 5 * Kit.scale, PAL.heading)
    if Kit.stepper(x + 154 * Kit.scale, by, 26 * Kit.scale, 24 * Kit.scale, "+") then
      layer.opacity = clamp((layer.opacity or 1) + 0.1, 0, 1)
      App.markDirty()
    end
    by = by + 32 * Kit.scale
  end
  FormPane.finish(S, "builderLayersScroll", contentY, by, view)
end

local function drawTilesetPane(S, x, y, w, h, App)
  local source = LayeredMap.sourceDescriptor(S, S.builderSourceId)
  if not source then
    Kit.emptyBox(x, y, w, math.min(h, 100 * Kit.scale), "Import a tileset PNG")
    return
  end
  Kit.text("small", "Tile animation", x, y, PAL.heading)
  Kit.textRight("micro", source.name or source.id, x + w, y + 2 * Kit.scale,
    PAL.muted)
  y = y + 24 * Kit.scale
  if source.runtimeTileset then
    Kit.text("micro", "Animations require an imported PNG source.", x, y, PAL.muted)
    Kit.text("micro", "Use + New PNG below the tile palette, then select a tile.",
      x, y + 17 * Kit.scale, PAL.caption)
    return
  end
  Kit.text("micro", "Color mode", x, y + 5 * Kit.scale, PAL.caption)
  local cx = x + 82 * Kit.scale
  for _, option in ipairs({
    { id = "palette", label = "Palette" },
    { id = "true_color", label = "True color" },
  }) do
    local bw = Kit.textWidth("micro", option.label) + 16 * Kit.scale
    if Kit.chip(cx, y, bw, 24 * Kit.scale, option.label,
        (source.colorMode or "true_color") == option.id,
        PAL.blue, PAL.steel) then
      source.colorMode = option.id
      App.markDirty()
    end
    cx = cx + bw + 4 * Kit.scale
  end
  y = y + 38 * Kit.scale
  local tile = S.builderTile or 0
  local frames = source.animations and source.animations[tile]
  local count = frames and #frames or 1
  local duration = frames and frames[1] and frames[1].duration or 200
  local function copyFrames(value)
    local copy = {}
    for index, frame in ipairs(value or {}) do
      copy[index] = { tile = frame.tile, duration = frame.duration }
    end
    return copy
  end
  local available = math.max(1, (source.count or 1) - tile)
  Kit.text("micro", "1. Selected tile: " .. tostring(tile), x, y, PAL.caption)
  Kit.textRight("micro", string.format("%d consecutive tile%s available",
    available, available == 1 and "" or "s"), x + w, y, PAL.faint)
  y = y + 18 * Kit.scale
  local ax = x
  for _, frameCount in ipairs({ 1, 2, 3, 4, 6, 8 }) do
    local possible = frameCount <= available
    local label = frameCount == 1 and "Static" or tostring(frameCount)
    local bw = frameCount == 1 and 58 * Kit.scale or 32 * Kit.scale
    if Kit.chip(ax, y, bw, 24 * Kit.scale, label, count == frameCount,
        possible and PAL.green or PAL.steel, PAL.steel,
        possible and "Use this many consecutive tiles as animation frames"
          or "Not enough tiles remain after the selected tile") and possible then
      local ok, err = LayeredMap.setSourceAnimation(
        source, tile, frameCount, duration)
      if ok then
        App.markDirty()
        S.status = frameCount == 1
          and string.format("Tile %d is now static", tile)
          or string.format("Created %d-frame animation on tile %d", frameCount, tile)
      else
        S.status = err
      end
    end
    ax = ax + bw + 3 * Kit.scale
  end
  y = y + 34 * Kit.scale
  if frames then
    Kit.text("micro", "2. Edit frames", x, y, PAL.caption)
    y = y + 18 * Kit.scale
    local function saveFrames(nextFrames, message)
      local ok, err = LayeredMap.setAnimationFrames(source, tile, nextFrames)
      if ok then
        App.markDirty()
        S.status = message
      else
        S.status = err
      end
    end
    for index, frame in ipairs(frames) do
      local rowY = y + (index - 1) * 29 * Kit.scale
      Kit.text("micro", tostring(index), x, rowY + 5 * Kit.scale, PAL.faint)
      Kit.text("micro", "Tile", x + 18 * Kit.scale, rowY + 5 * Kit.scale,
        PAL.caption)
      local fieldKey = tostring(source.id) .. "_" .. tostring(tile)
        .. "_" .. tostring(index)
      local tileId = "builder_anim_tile_" .. fieldKey
      local tileValue = field(App, tileId, x + 46 * Kit.scale, rowY,
        44 * Kit.scale, 24 * Kit.scale, tostring(frame.tile), "0")
      Kit.text("micro", "ms", x + 96 * Kit.scale, rowY + 5 * Kit.scale,
        PAL.caption)
      local timeId = "builder_anim_ms_" .. fieldKey
      local timeValue = field(App, timeId, x + 114 * Kit.scale, rowY,
        48 * Kit.scale, 24 * Kit.scale, tostring(frame.duration), "200")
      if Kit.focus ~= tileId and Kit.focus ~= timeId then
        local nextTile = clamp(math.floor(tonumber(tileValue) or frame.tile),
          0, math.max(0, (source.count or 1) - 1))
        local nextDuration = math.max(16,
          math.floor(tonumber(timeValue) or frame.duration))
        if nextTile ~= frame.tile or nextDuration ~= frame.duration then
          local nextFrames = copyFrames(frames)
          nextFrames[index].tile = nextTile
          nextFrames[index].duration = nextDuration
          saveFrames(nextFrames, string.format("Updated animation frame %d", index))
          frames = source.animations and source.animations[tile] or frames
        end
      end
      local bx = x + w - 94 * Kit.scale
      if Kit.stepper(bx, rowY, 22 * Kit.scale, 24 * Kit.scale, "^")
          and index > 1 then
        local nextFrames = copyFrames(frames)
        nextFrames[index - 1], nextFrames[index] = nextFrames[index], nextFrames[index - 1]
        saveFrames(nextFrames, "Moved animation frame up")
        break
      end
      if Kit.stepper(bx + 24 * Kit.scale, rowY, 22 * Kit.scale, 24 * Kit.scale, "v")
          and index < #frames then
        local nextFrames = copyFrames(frames)
        nextFrames[index + 1], nextFrames[index] = nextFrames[index], nextFrames[index + 1]
        saveFrames(nextFrames, "Moved animation frame down")
        break
      end
      if Kit.button(bx + 50 * Kit.scale, rowY, 44 * Kit.scale, 24 * Kit.scale,
          "Delete", { kind = "danger", enabled = #frames > 2 }) then
        local nextFrames = copyFrames(frames)
        table.remove(nextFrames, index)
        saveFrames(nextFrames, "Deleted animation frame")
        break
      end
    end
    y = y + #frames * 29 * Kit.scale + 4 * Kit.scale
    if Kit.button(x, y, 92 * Kit.scale, 24 * Kit.scale, "+ Add frame", {
        kind = "good", enabled = #frames < 16,
        tooltip = "Append a frame; its tile and duration can be edited above" }) then
      local nextFrames = copyFrames(frames)
      local last = nextFrames[#nextFrames]
      nextFrames[#nextFrames + 1] = {
        tile = math.min((source.count or 1) - 1, (last.tile or tile) + 1),
        duration = last.duration or 200,
      }
      saveFrames(nextFrames, "Added animation frame")
    end
    Kit.text("micro", "Each frame can use any tile and timing (minimum 16 ms).",
      x, y + 31 * Kit.scale, PAL.muted)
  else
    Kit.text("micro", "Choose 2 or more frames to create the animation.",
      x, y, PAL.muted)
  end
end

local function nodeTargetText(project, node)
  local target = node.targetNode and project.mapWarpNodes[node.targetNode]
  if target then
    return string.format("%s (%d,%d)", target.map, target.x, target.y)
  end
  if node.targetMap and node.targetIndex then
    return string.format("%s warp %d", node.targetMap, node.targetIndex)
  end
  return "arrival only"
end

local function drawWarpsPane(S, source, x, y, w, h, App)
  local bottom = y + h
  Kit.text("micro", "New warp", x, y, PAL.caption)
  y = y + 18 * Kit.scale
  local wx = x
  for _, mode in ipairs({
    { id = "two_way", label = "Two-way" },
    { id = "one_way", label = "One-way" },
    { id = "custom_return", label = "Custom return" },
  }) do
    local bw = Kit.textWidth("micro", mode.label) + 16 * Kit.scale
    if Kit.chip(wx, y, bw, 24 * Kit.scale, mode.label,
        (S.builderWarpMode or "two_way") == mode.id, PAL.blue, PAL.steel) then
      S.builderWarpMode = mode.id
      S.builderWarpDraft = nil
      S.builderTool = "warp"
    end
    wx = wx + bw + 3 * Kit.scale
  end
  y = y + 34 * Kit.scale
  local nodes = LayeredMap.nodesForMap(S.project, S.builderMapId)
  Kit.text("micro", string.format("Endpoints on this map (%d)", #nodes), x, y, PAL.caption)
  y = y + 18 * Kit.scale
  local rowH = 30 * Kit.scale
  local listH = math.max(rowH, bottom - y - 38 * Kit.scale)
  local perPage = math.max(1, math.floor(listH / rowH))
  local offset = clamp(S.builderWarpOffset or 0, 0,
    math.max(0, #nodes - perPage))
  local scrollId = "builderWarpOffset"
  offset = Kit.scroll(x, y, w, listH, offset, #nodes, perPage, 2, scrollId)
  local rowW = w - (#nodes > perPage and 14 * Kit.scale or 0)
  Kit.pushClip(x, y, w, listH)
  for row = 1, perPage do
    local index = offset + row
    local node = nodes[index]
    if not node then break end
    local label = string.format("%s (%d,%d) -> %s",
      node.active and "Warp" or "Arrival", node.x, node.y,
      nodeTargetText(S.project, node))
    local ry = y + (row - 1) * rowH
    if Kit.row(x, ry, rowW, 27 * Kit.scale,
        S.builderWarpNodeId == node.id, PAL.blue, 5 * Kit.scale) then
      S.builderWarpNodeId = node.id
    end
    Kit.text("micro", Kit.ellipsize("micro", label, rowW - 12 * Kit.scale),
      x + 6 * Kit.scale, ry + 7 * Kit.scale,
      node.active and PAL.heading or PAL.muted)
  end
  Kit.popClip()
  if #nodes > perPage then
    S.builderWarpOffset = Kit.scrollbar(x + w - 11 * Kit.scale, y,
      10 * Kit.scale, listH, offset, #nodes, perPage, scrollId)
  else
    S.builderWarpOffset = 0
  end
  y = y + listH
  local selected = S.builderWarpNodeId
    and S.project.mapWarpNodes[S.builderWarpNodeId]
  if Kit.button(x, y + 4 * Kit.scale, w, 26 * Kit.scale,
      "Delete selected endpoint", { kind = "danger", enabled = selected ~= nil,
        tooltip = "Targets pointing here become inactive arrival records" }) then
    LayeredMap.removeWarpNode(S.project, selected.id)
    S.builderWarpNodeId = nil
    App.markDirty()
    S.status = "Deleted warp endpoint"
  end
end

local PANE_INFO = {
  details = { label = "Map setup", help = "Name, size, encounters, and map behavior" },
  layers = { label = "Layers", help = "Choose what you paint on and arrange draw order" },
  tileset = { label = "Tile animation", help = "Advanced: animate individual source tiles" },
  warps = { label = "Doors & exits", help = "Connect this map to another location" },
}

local function drawPaneNavigation(S, x, y, w)
  local s = Kit.scale
  local tabs = { "details", "layers", "tileset", "warps" }
  local bw = (w - 4 * s) / 2
  for index, id in ipairs(tabs) do
    local col, row = (index - 1) % 2, math.floor((index - 1) / 2)
    local tx, ty = x + col * (bw + 4 * s), y + row * 30 * s
    local info = PANE_INFO[id]
    if Kit.chip(tx, ty, bw, 27 * s, info.label,
        S.builderPane == id, PAL.blue, PAL.steel, info.help) then
      S.builderPane = id
      if id == "warps" then S.builderTool = "warp" end
    end
  end
  local info = PANE_INFO[S.builderPane] or PANE_INFO.layers
  Kit.text("micro", Kit.ellipsize("micro", info.help, w),
    x, y + 63 * s, PAL.muted)
  return y + 82 * s
end

local function drawProperties(S, source, x, y, w, h, App)
  if S.builderPane == "details" then
    Kit.card(x, y, w, h, 10 * Kit.scale)
    local s = Kit.scale
    local contentY = drawPaneNavigation(S, x + 10 * s, y + 8 * s, w - 20 * s)
    local Maps = require("Maps")
    Maps.drawDetails(S, x, contentY, w, h - (contentY - y), App)
    return
  end
  Kit.card(x, y, w, h, 10 * Kit.scale)
  local px, py = x + 10 * Kit.scale, y + 9 * Kit.scale
  local innerW = w - 20 * Kit.scale
  S.builderPane = S.builderPane or "layers"
  py = drawPaneNavigation(S, px, py, innerW)
  if S.builderPane == "layers" then
    Kit.text("micro", "MAP SIZE", px, py, PAL.caption)
    Kit.textRight("micro", string.format("Current: %d x %d cells",
      source.cellWidth, source.cellHeight), px + innerW, py, PAL.muted)
    py = py + 18 * Kit.scale
    local draft = S._builderSizeDraft
    if not draft or draft.map ~= source.id then
      draft = { map = source.id, w = tostring(source.cellWidth),
        h = tostring(source.cellHeight) }
      S._builderSizeDraft = draft
    end
    local function stepSize(key, delta)
      local value = math.floor(tonumber(draft[key]) or source[
        key == "w" and "cellWidth" or "cellHeight"])
      draft[key] = tostring(math.max(2, value + delta))
    end
    Kit.text("micro", "Width", px, py + 5 * Kit.scale, PAL.heading)
    if Kit.stepper(px + 48 * Kit.scale, py, 24 * Kit.scale, 25 * Kit.scale, "-") then
      stepSize("w", -2)
    end
    draft.w = Kit.textfield("builder_map_w", px + 76 * Kit.scale, py,
      72 * Kit.scale, 25 * Kit.scale, draft.w, "20")
    if Kit.stepper(px + 152 * Kit.scale, py, 24 * Kit.scale, 25 * Kit.scale, "+") then
      stepSize("w", 2)
    end
    py = py + 31 * Kit.scale
    Kit.text("micro", "Height", px, py + 5 * Kit.scale, PAL.heading)
    if Kit.stepper(px + 48 * Kit.scale, py, 24 * Kit.scale, 25 * Kit.scale, "-") then
      stepSize("h", -2)
    end
    draft.h = Kit.textfield("builder_map_h", px + 76 * Kit.scale, py,
      72 * Kit.scale, 25 * Kit.scale, draft.h, "18")
    if Kit.stepper(px + 152 * Kit.scale, py, 24 * Kit.scale, 25 * Kit.scale, "+") then
      stepSize("h", 2)
    end

    local newWidth, newHeight = tonumber(draft.w), tonumber(draft.h)
    local whole = newWidth and newHeight
      and newWidth == math.floor(newWidth) and newHeight == math.floor(newHeight)
    local valid = whole and newWidth >= 2 and newHeight >= 2
      and newWidth % 2 == 0 and newHeight % 2 == 0
    local changed = valid and (newWidth ~= source.cellWidth
      or newHeight ~= source.cellHeight)
    local shrinking = valid and (newWidth < source.cellWidth
      or newHeight < source.cellHeight)
    local cropped = 0
    if shrinking then
      for _, node in pairs(S.project.mapWarpNodes or {}) do
        if node.map == source.id and (node.x >= newWidth or node.y >= newHeight) then
          cropped = cropped + 1
        end
      end
      local map = S.project.maps and S.project.maps[source.id]
      local function countCropped(list)
        for _, event in ipairs(list or {}) do
          if event.x >= newWidth or event.y >= newHeight then cropped = cropped + 1 end
        end
      end
      if map then
        countCropped(map.objects)
        countCropped(map.warps)
        countCropped(map.signs)
        countCropped(map.bgEvents)
      end
    end
    py = py + 33 * Kit.scale
    if not valid then
      Kit.text("micro", "Use whole, even values of at least 2 cells.",
        px, py, PAL.red)
    elseif shrinking then
      local warning = cropped > 0
        and string.format("Shrinking crops right/bottom and removes %d event(s).", cropped)
        or "Shrinking crops terrain from the right and bottom."
      Kit.text("micro", Kit.ellipsize("micro", warning, innerW),
        px, py, PAL.yellow)
    else
      Kit.text("micro", "New space is added on the right and bottom.",
        px, py, PAL.muted)
    end
    py = py + 20 * Kit.scale
    local half = (innerW - 4 * Kit.scale) / 2
    if Kit.button(px, py, half, 26 * Kit.scale, "Reset", {
        kind = "ghost", enabled = changed or not valid }) then
      draft.w, draft.h = tostring(source.cellWidth), tostring(source.cellHeight)
      Kit.blur()
    end
    if Kit.button(px + half + 4 * Kit.scale, py, half, 26 * Kit.scale,
        shrinking and "Resize & Crop" or "Apply Resize", {
          kind = shrinking and "danger" or "good", enabled = changed,
          tooltip = "Resize from the top-left corner" }) then
      App.beginEditBatch()
      local ok, result = LayeredMap.resizeMap(
        S.project, source.id, newWidth, newHeight)
      if ok then
        S.builderSelections = {}
        App.markDirty()
        App.endEditBatch()
        draft.w, draft.h = tostring(source.cellWidth), tostring(source.cellHeight)
        S.status = result > 0
          and string.format("Resized map; removed %d out-of-bounds event(s)", result)
          or string.format("Resized map to %d x %d cells", newWidth, newHeight)
      else
        App.endEditBatch()
        S.status = "Resize rejected: " .. tostring(result)
      end
      Kit.blur()
    end
    py = py + 36 * Kit.scale
  end
  local remaining = y + h - py - 8 * Kit.scale
  if S.builderPane == "tileset" then
    drawTilesetPane(S, px, py, innerW, remaining, App)
  elseif S.builderPane == "warps" then
    drawWarpsPane(S, source, px, py, innerW, remaining, App)
  else
    drawLayersPane(S, source, px, py, innerW, remaining, App)
  end
end

-- Public panel API

function MapBuilder.keypressed(S, key, App)
  if not S or not S.project then return false end
  if key == "escape" and S.builderNewMap then
    S.builderNewMap = nil
    Kit.blur()
    S.status = "New map cancelled"
    return true
  end
  local source = mapSource(S)
  if not source then return false end
  if Kit.focus then return false end
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  if ctrl and (key == "c" or key == "v") then
    if S.mapEditMode == "events" then
      local Maps = require("Maps")
      local ok, msg
      if key == "c" then
        ok, msg = Maps.copySelectedEvent(S)
      else
        ok, msg = Maps.pasteEvent(S, App)
      end
      S.status = msg or (ok and (key == "c" and "Copied event" or "Pasted event")
        or "Event copy/paste failed")
    elseif key == "c" then
      copySelection(S, source)
    else
      local x0, y0 = selectionBounds(S)
      pasteSelection(S, source, App,
        x0 or S.builderHoverX or 0, y0 or S.builderHoverY or 0)
    end
    return true
  end
  if key == "delete" or key == "backspace" then
    if S.mapEditMode == "events" and Kit.focus == nil then
      return require("Maps").deleteSelectedEvent(S, App)
    elseif #(S.builderSelections or {}) > 0 and Kit.focus == nil then
      clearSelections(S, source, App)
      return true
    end
  elseif key == "escape" and S.builderWarpDraft then
    S.builderWarpDraft = nil
    S.status = "Warp placement cancelled"
    return true
  end
  return false
end

function MapBuilder.update(S, dt)
  if not (S and S._builderViewHit and not Kit.focus and love.keyboard) then return end
  local dx, dy = 0, 0
  if love.keyboard.isDown("a") then dx = dx - 1 end
  if love.keyboard.isDown("d") then dx = dx + 1 end
  if love.keyboard.isDown("w") then dy = dy - 1 end
  if love.keyboard.isDown("s") then dy = dy + 1 end
  if dx ~= 0 or dy ~= 0 then
    local step = 360 * (tonumber(dt) or 0) / math.max(0.25, S.builderZoom or 1)
    S.builderCamX = (S.builderCamX or 0) + dx * step
    S.builderCamY = (S.builderCamY or 0) + dy * step
  end
end

function MapBuilder.wheelmoved(S, dy, dx)
  if not (S and S._builderViewHit) then return false end
  dy, dx = tonumber(dy) or 0, tonumber(dx) or 0
  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  if dx ~= 0 or shift or ctrl then
    local amount = dx ~= 0 and -dx or -dy
    if shift then
      S.builderCamY = (S.builderCamY or 0) + amount * 48
    else
      S.builderCamX = (S.builderCamX or 0) + amount * 48
    end
  elseif dy ~= 0 then
    S.builderZoom = clamp((S.builderZoom or 1) + (dy > 0 and 0.25 or -0.25),
      0.25, 8)
  end
  return dy ~= 0 or dx ~= 0
end

function MapBuilder.draw(S, x, y, w, h, App)
  if not (S and S.project) then
    Kit.emptyBox(x, y, w, h, "Open or create a mod first")
    return
  end
  LayeredMap.ensureProject(S.project)
  S.builderTool = S.builderTool or "pencil"
  S.builderTile = S.builderTile or 0
  S.builderCollision = S.builderCollision or "solid"
  S.builderWarpMode = S.builderWarpMode or "two_way"

  local s = Kit.scale
  local leftW = math.min(270 * s, math.max(220 * s, w * 0.22))
  local rightW = math.min(330 * s, math.max(270 * s, w * 0.25))
  local gap = 9 * s
  local centerX = x + leftW + gap
  local centerW = math.max(220 * s, w - leftW - rightW - gap * 2)
  local rightX = centerX + centerW + gap

  local mapListMin = S.builderNewMap and 244 * s or 210 * s
  local mapListH = math.min(290 * s, math.max(mapListMin, h * 0.43))
  drawMapList(S, x, y, leftW, mapListH, App)
  local source = mapSource(S)
  if source then
    drawTilePalette(S, source, x, y + mapListH + gap,
      leftW, h - mapListH - gap, App)
  elseif S.mapPreviewOnly then
    Kit.card(x, y + mapListH + gap, leftW, h - mapListH - gap, 10 * s)
    Kit.emptyBox(x + 10 * s, y + mapListH + gap + 10 * s,
      leftW - 20 * s, h - mapListH - gap - 20 * s,
      "Click Edit Map to unlock tiles and tools")
  else
    local Maps = require("Maps")
    Maps.drawClassicTileset(S, x, y + mapListH + gap,
      leftW, h - mapListH - gap, App)
  end

  if S.mapViewMode == "world" then
    S._builderViewHit = false
    local Maps = require("Maps")
    Maps.drawWorld(S, App, centerX, y, centerW + gap + rightW, h)
    return
  end

  if not source then
    if S.mapPreviewOnly then
      local Maps = require("Maps")
      Maps.drawPreview(S, centerX, y, centerW + gap + rightW, h, App)
    else
      Kit.card(centerX, y, centerW, h, 10 * s)
      local Maps = require("Maps")
      Maps.drawClassicTerrain(S, centerX, y, centerW, h, App)
      Maps.drawDetails(S, rightX, y, rightW, h, App)
    end
    return
  end

  local canvasY = drawToolbar(S, source, centerX, y, centerW, App)
  Kit.card(centerX, canvasY, centerW, y + h - canvasY, 10 * s)
  drawCanvas(S, source, centerX, canvasY, centerW, y + h - canvasY, App)
  drawProperties(S, source, rightX, y, rightW, h, App)
end

return MapBuilder
