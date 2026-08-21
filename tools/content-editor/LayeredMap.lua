-- Native layered map source and compiler.
--
-- The editor works in 16x16 walk cells. Saving folds the exported layers into
-- the runtime's 32x32 block format. Maps painted from one game tileset keep
-- that tileset (and its ledge collision). Mixed or custom graphics still bake
-- one generated tileset per map. The source stays in editor_project.lua.

local ModIO = require("ModIO")
local Preview = require("Preview")

local LayeredMap = {}

LayeredMap.CELL_SIZE = 16
LayeredMap.COLOR_MODES = { "palette", "true_color" }
LayeredMap.COLLISION_MODES = {
  "solid", "walk", "grass", "water", "shore",
}

local RUNTIME_PREFIX = "@runtime:"

-- Project model and identifiers

local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[deepCopy(key, seen)] = deepCopy(child, seen)
  end
  return out
end

local function sortedKeys(bucket)
  local out = {}
  for key in pairs(bucket or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function listSet(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[value] = true end
  return out
end

local function clamp(value, low, high)
  value = tonumber(value) or low
  return math.max(low, math.min(high, value))
end

local function cleanId(value, fallback)
  local id = tostring(value or ""):upper():gsub("[^A-Z0-9_]", "_")
  id = id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if id == "" then id = fallback or "MAP" end
  if id:match("^%d") then id = "MAP_" .. id end
  return id
end

local function ensureProject(project)
  project.layeredMaps = project.layeredMaps or {}
  project.mapTileSources = project.mapTileSources or {}
  project.mapWarpNodes = project.mapWarpNodes or {}
  project.maps = project.maps or {}
  project.tilesets = project.tilesets or {}
  project.nextMapIndex = project.nextMapIndex or 1000
  project.nextWarpNode = project.nextWarpNode or 1
  return project
end

function LayeredMap.ensureProject(project)
  return ensureProject(project)
end

function LayeredMap.runtimeSourceId(tilesetId)
  return RUNTIME_PREFIX .. tostring(tilesetId or "OVERWORLD")
end

function LayeredMap.isRuntimeSource(sourceId)
  return type(sourceId) == "string"
    and sourceId:sub(1, #RUNTIME_PREFIX) == RUNTIME_PREFIX
end

function LayeredMap.runtimeTilesetId(sourceId)
  if not LayeredMap.isRuntimeSource(sourceId) then return nil end
  return sourceId:sub(#RUNTIME_PREFIX + 1)
end

local function resolveMap(S, mapId)
  local Generation = require("Generation")
  return (S.project and S.project.maps and S.project.maps[mapId])
    or Generation.dataMaps(S)[mapId]
end

local function resolveTileset(S, tilesetId)
  local Generation = require("Generation")
  return (S.project and S.project.tilesets and S.project.tilesets[tilesetId])
    or Generation.dataTilesets(S)[tilesetId]
end

function LayeredMap.allMapIds(S)
  local seen, ids = {}, {}
  local function add(bucket)
    for id in pairs(bucket or {}) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  add(S.project and S.project.layeredMaps)
  add(S.project and S.project.maps)
  add(require("Generation").dataMaps(S))
  table.sort(ids)
  return ids
end

local function uniqueMapId(S, wanted)
  local base = cleanId(wanted, "NEW_MAP")
  local id, suffix = base, 1
  while resolveMap(S, id) or (S.project.layeredMaps and S.project.layeredMaps[id]) do
    suffix = suffix + 1
    id = base .. "_" .. suffix
  end
  return id
end

local function uniqueSourceId(project, wanted)
  local base = cleanId(wanted, "CUSTOM_TILES")
  local id, suffix = base, 1
  while project.mapTileSources[id] do
    suffix = suffix + 1
    id = base .. "_" .. suffix
  end
  return id
end

local function defaultEnvironment(tilesetId)
  if tilesetId == "CAVERN" then return "cave" end
  if tilesetId == "OVERWORLD" or tilesetId == "PLATEAU" then
    return "outside"
  end
  return "inside"
end

local function cellIndex(mapSource, x, y)
  return y * mapSource.cellWidth + x + 1
end

-- Same (source, tile) shares one table. A 700x550 map is 385k cells; without
-- this the editor holds hundreds of thousands of duplicate {source,tile} tables.
local cellRefPool = {}

local function internCellRef(ref)
  if type(ref) ~= "table" then return nil end
  local source = ref.source
  local tile = math.max(0, math.floor(tonumber(ref.tile) or 0))
  local key = tostring(source or "") .. "\0" .. tostring(tile)
  local pooled = cellRefPool[key]
  if pooled then return pooled end
  pooled = { source = source, tile = tile }
  cellRefPool[key] = pooled
  return pooled
end

local internedSources = setmetatable({}, { __mode = "k" })

function LayeredMap.internSourceCells(source)
  if not source or internedSources[source] then return source end
  for _, layer in ipairs(source.layers or {}) do
    local cells = layer.cells
    if cells then
      for index, cell in pairs(cells) do
        cells[index] = internCellRef(cell)
      end
    end
  end
  internedSources[source] = true
  return source
end

local function defaultRuntimeRef(tilesetId, x, y, block)
  local quadrant = (y % 2) * 2 + (x % 2)
  return internCellRef({
    source = LayeredMap.runtimeSourceId(tilesetId),
    tile = (block or 0) * 4 + quadrant,
  })
end

-- Map creation and conversion

function LayeredMap.createMap(S, wantedId, cellWidth, cellHeight, tilesetId)
  local project = ensureProject(assert(S.project, "no project"))
  local id = uniqueMapId(S, wantedId)
  local width = math.max(2, math.floor(tonumber(cellWidth) or 20))
  local height = math.max(2, math.floor(tonumber(cellHeight) or 18))
  if width % 2 ~= 0 then width = width + 1 end
  if height % 2 ~= 0 then height = height + 1 end
  tilesetId = tilesetId or "OVERWORLD"

  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      cells[index] = defaultRuntimeRef(tilesetId, x, y, 0)
      collision[index] = "walk"
    end
  end

  local source = {
    id = id,
    cellWidth = width,
    cellHeight = height,
    baseTileset = tilesetId,
    layers = {
      {
        id = "ground", name = "Ground", visible = true, export = true,
        opacity = 1, cells = cells,
      },
    },
    collision = collision,
  }
  project.layeredMaps[id] = source

  local environment = defaultEnvironment(tilesetId)
  local blockWidth, blockHeight = width / 2, height / 2
  local blocks = {}
  for i = 1, blockWidth * blockHeight do blocks[i] = 0 end
  project.maps[id] = {
    id = id,
    label = id,
    index = project.nextMapIndex,
    tileset = tilesetId,
    environment = environment,
    outdoor = environment == "outside",
    width = blockWidth,
    height = blockHeight,
    blocks = blocks,
    borderBlock = 0,
    warps = {}, objects = {}, signs = {}, connections = {},
    _isNew = true,
    _layeredSource = id,
  }
  project.nextMapIndex = project.nextMapIndex + 1
  return source, project.maps[id]
end

local function ownedMap(S, mapId)
  local project = ensureProject(assert(S.project, "no project"))
  if project.maps[mapId] then return project.maps[mapId] end
  local base = require("Generation").dataMaps(S)[mapId]
  if not base then return nil end
  local copy = deepCopy(base)
  copy.id = mapId
  copy._isNew = false
  project.maps[mapId] = copy
  return copy
end

local function collisionMode(tileset, tile, map, x, y)
  if tileset and type(tileset.collision) == "table" and map and map.blocks then
    local blockX, blockY = math.floor(x / 2), math.floor(y / 2)
    local blockId = map.blocks[blockY * map.width + blockX + 1] or 0
    local quad = tileset.collision[blockId + 1]
    if type(quad) == "table" then
      local coll = quad[(y % 2) * 2 + (x % 2) + 1]
      local okP, Permissions = pcall(require, "src.world.gen2.Permissions")
      if okP and Permissions then
        if Permissions.isGrass and Permissions.isGrass(coll) then return "grass" end
        if Permissions.isWater and Permissions.isWater(coll) then return "water" end
        if Permissions.isWalkable and Permissions.isWalkable(coll) then
          return "walk"
        end
        return "solid"
      end
    end
  end
  if not tileset or tile == nil then return "solid" end
  if tileset.grassTile == tile then return "grass" end
  if listSet(tileset.waterTiles)[tile] then return "water" end
  if listSet(tileset.shoreTiles)[tile] then return "shore" end
  if listSet(tileset.walkable)[tile] then return "walk" end
  return "solid"
end

local function rawCellTile(map, tileset, x, y)
  local blockX, blockY = math.floor(x / 2), math.floor(y / 2)
  local blockId = map.blocks[blockY * map.width + blockX + 1] or 0
  local block = tileset and tileset.blocks and tileset.blocks[blockId + 1]
  if not block then return nil, blockId end
  local tileX = (x % 2) * 2
  local tileY = (y % 2) * 2 + 1
  return block[tileY * 4 + tileX + 1], blockId
end

local function nodeAt(project, mapId, x, y)
  for _, node in pairs(project.mapWarpNodes or {}) do
    if node.map == mapId and node.x == x and node.y == y then return node end
  end
  return nil
end

local function newNode(project, mapId, x, y)
  local id
  repeat
    id = "WARP_" .. tostring(project.nextWarpNode)
    project.nextWarpNode = project.nextWarpNode + 1
  until project.mapWarpNodes[id] == nil
  local node = {
    id = id, map = mapId, x = x, y = y,
    active = false, order = project.nextWarpNode - 1,
  }
  project.mapWarpNodes[id] = node
  return node
end

function LayeredMap.nodeAt(project, mapId, x, y)
  ensureProject(project)
  return nodeAt(project, mapId, x, y)
end

function LayeredMap.ensureWarpNode(project, mapId, x, y)
  ensureProject(project)
  return nodeAt(project, mapId, x, y) or newNode(project, mapId, x, y)
end

local function importMapWarps(S, map)
  local project = ensureProject(S.project)
  for index, warp in ipairs(map.warps or {}) do
    -- Existing editor nodes are the source of truth. Re-applying compiled
    -- map.warps would resurrect deleted endpoints on Save.
    local node = nodeAt(project, map.id, warp.x, warp.y)
    if not node then
      node = newNode(project, map.id, warp.x, warp.y)
      node.active = true
      node.originalIndex = index
      node.targetMap = warp.destMap
      node.targetIndex = warp.destWarp
      node.destGroup = warp.destGroup
      node.destMapNum = warp.destMapNum
      if warp.destMap and not project.layeredMaps[warp.destMap] then
        node.targetNode = nil
      end
    elseif not node.originalIndex then
      node.originalIndex = index
    end
  end

  -- Reconnect only when the destination is also a layered map.
  for _, node in pairs(project.mapWarpNodes) do
    if node.targetNode == nil and node.targetMap and node.targetIndex
        and project.layeredMaps[node.targetMap] then
      for _, candidate in pairs(project.mapWarpNodes) do
        if candidate.map == node.targetMap
            and candidate.originalIndex == node.targetIndex then
          node.targetNode = candidate.id
          break
        end
      end
    end
  end
end

function LayeredMap.syncMapWarps(S, map)
  if not (S and S.project and map) then return end
  importMapWarps(S, map)
end

function LayeredMap.convertMap(S, mapId)
  local project = ensureProject(assert(S.project, "no project"))
  if project.layeredMaps[mapId] then return project.layeredMaps[mapId] end
  local map = ownedMap(S, mapId)
  if not map then return nil, "unknown map " .. tostring(mapId) end
  local tileset = resolveTileset(S, map.tileset)
  if not (tileset and type(tileset.blocks) == "table") then
    return nil, "map tileset is unavailable: " .. tostring(map.tileset)
  end

  local width, height = map.width * 2, map.height * 2
  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local tile, block = rawCellTile(map, tileset, x, y)
      cells[index] = defaultRuntimeRef(map.tileset, x, y, block)
      collision[index] = collisionMode(tileset, tile, map, x, y)
    end
  end
  local source = {
    id = mapId,
    cellWidth = width,
    cellHeight = height,
    baseTileset = map.tileset,
    layers = {
      {
        id = "ground", name = "Ground", visible = true, export = true,
        opacity = 1, cells = cells,
      },
    },
    collision = collision,
  }
  project.layeredMaps[mapId] = source
  map._layeredSource = mapId
  importMapWarps(S, map)
  return source
end

-- Point an editable map at a different runtime tileset. Cells that used the
-- previous @runtime: source follow the new one; custom PNG cells stay put.
function LayeredMap.assignTileset(S, mapId, tilesetId)
  if not (S and S.project and mapId and tilesetId) then return false end
  local source = ensureProject(S.project).layeredMaps[mapId]
  if not source then return false end
  local oldId = source.baseTileset
  source.baseTileset = tilesetId
  local oldSrc = oldId and LayeredMap.runtimeSourceId(oldId)
  local newSrc = LayeredMap.runtimeSourceId(tilesetId)
  for _, layer in ipairs(source.layers or {}) do
    for index, cell in pairs(layer.cells or {}) do
      if type(cell) == "table" then
        if cell.source == oldSrc
            or (not oldSrc and LayeredMap.isRuntimeSource(cell.source)) then
          layer.cells[index] = internCellRef({ source = newSrc, tile = cell.tile })
        end
      end
    end
  end
  return true
end

-- Editable map operations

function LayeredMap.resize(source, newWidth, newHeight)
  if type(source) ~= "table" then return false, "no layered map" end
  local width = math.max(2, math.floor(tonumber(newWidth) or source.cellWidth))
  local height = math.max(2, math.floor(tonumber(newHeight) or source.cellHeight))
  if width % 2 ~= 0 or height % 2 ~= 0 then
    return false, "map size must use even 16x16-cell dimensions"
  end
  if width == source.cellWidth and height == source.cellHeight then return true end
  local oldWidth, oldHeight = source.cellWidth, source.cellHeight
  for layerIndex, layer in ipairs(source.layers or {}) do
    local cells = {}
    for y = 0, height - 1 do
      for x = 0, width - 1 do
        if x < oldWidth and y < oldHeight then
          cells[y * width + x + 1] = layer.cells[y * oldWidth + x + 1]
        elseif layerIndex == 1 then
          cells[y * width + x + 1] =
            defaultRuntimeRef(source.baseTileset, x, y, 0)
        end
      end
    end
    layer.cells = cells
  end
  local collision = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      collision[y * width + x + 1] =
        (x < oldWidth and y < oldHeight)
          and source.collision[y * oldWidth + x + 1] or "solid"
    end
  end
  source.collision = collision
  source.cellWidth, source.cellHeight = width, height
  return true
end

function LayeredMap.resizeMap(project, mapId, newWidth, newHeight)
  ensureProject(project)
  local source = project.layeredMaps[mapId]
  local ok, err = LayeredMap.resize(source, newWidth, newHeight)
  if not ok then return false, err end
  local removed = 0
  local drop = {}
  for id, node in pairs(project.mapWarpNodes) do
    if node.map == mapId
        and (node.x >= source.cellWidth or node.y >= source.cellHeight) then
      drop[#drop + 1] = id
    end
  end
  for _, id in ipairs(drop) do
    LayeredMap.removeWarpNode(project, id)
    removed = removed + 1
  end
  local map = project.maps[mapId]
  if map then
    map.width, map.height = source.cellWidth / 2, source.cellHeight / 2
    local function trimEvents(list)
      for index = #(list or {}), 1, -1 do
        local event = list[index]
        if event.x >= source.cellWidth or event.y >= source.cellHeight then
          table.remove(list, index)
          removed = removed + 1
        end
      end
    end
    trimEvents(map.objects)
    trimEvents(map.warps)
    trimEvents(map.signs)
    trimEvents(map.bgEvents)
  end
  return true, removed
end

function LayeredMap.addLayer(source, name)
  local base = cleanId(name, "LAYER"):lower()
  local id, suffix = base, 1
  local used = {}
  for _, layer in ipairs(source.layers or {}) do used[layer.id] = true end
  while used[id] do
    suffix = suffix + 1
    id = base .. "_" .. suffix
  end
  local layer = {
    id = id,
    name = tostring(name or "Layer " .. (#source.layers + 1)),
    visible = true,
    export = true,
    opacity = 1,
    cells = {},
  }
  source.layers[#source.layers + 1] = layer
  return layer, #source.layers
end

function LayeredMap.removeLayer(source, index)
  if index == 1 then return false, "Ground cannot be removed" end
  if not source.layers[index] then return false, "unknown layer" end
  table.remove(source.layers, index)
  return true
end

function LayeredMap.moveLayer(source, index, direction)
  local target = index + direction
  if index < 1 or target < 1 or target > #source.layers then return index end
  source.layers[index], source.layers[target] =
    source.layers[target], source.layers[index]
  return target
end

function LayeredMap.setCell(source, layerIndex, x, y, ref)
  if x < 0 or y < 0 or x >= source.cellWidth or y >= source.cellHeight then
    return false
  end
  local layer = source.layers[layerIndex]
  if not layer then return false end
  layer.cells[cellIndex(source, x, y)] = internCellRef(ref)
  return true
end

function LayeredMap.getCell(source, layerIndex, x, y)
  local layer = source.layers[layerIndex]
  if not layer then return nil end
  return layer.cells[cellIndex(source, x, y)]
end

function LayeredMap.setCollision(source, x, y, mode)
  if x < 0 or y < 0 or x >= source.cellWidth or y >= source.cellHeight then
    return false
  end
  local valid = false
  for _, value in ipairs(LayeredMap.COLLISION_MODES) do
    if value == mode then valid = true; break end
  end
  if not valid then return false end
  source.collision[cellIndex(source, x, y)] = mode
  return true
end

-- Tileset sources and animation

function LayeredMap.addTileSource(project, wantedId, image, width, height)
  ensureProject(project)
  width, height = tonumber(width), tonumber(height)
  if not width or not height or width < 16 or height < 16
      or width % 16 ~= 0 or height % 16 ~= 0 then
    return nil, "tileset PNG dimensions must be multiples of 16 pixels"
  end
  local id = uniqueSourceId(project, wantedId)
  local source = {
    id = id,
    name = id,
    image = image,
    tileWidth = 16,
    tileHeight = 16,
    columns = width / 16,
    count = (width / 16) * (height / 16),
    colorMode = "true_color",
    animations = {},
  }
  project.mapTileSources[id] = source
  return source
end

-- Reuse a stable id so re-importing a TMX replaces the same source.
function LayeredMap.installTileSource(project, wantedId, image, width, height)
  ensureProject(project)
  width, height = tonumber(width), tonumber(height)
  if not width or not height or width < 16 or height < 16
      or width % 16 ~= 0 or height % 16 ~= 0 then
    return nil, "tileset PNG dimensions must be multiples of 16 pixels"
  end
  local id = cleanId(wantedId, "CUSTOM_TILES")
  local source = project.mapTileSources[id] or {
    id = id, name = id, animations = {},
  }
  source.image = image
  source.tileWidth = 16
  source.tileHeight = 16
  source.columns = width / 16
  source.count = (width / 16) * (height / 16)
  source.colorMode = "true_color"
  project.mapTileSources[id] = source
  return source
end

-- Turn a PNG into this map: one 16x16 cell per image tile, even cell size.
function LayeredMap.applyPngAsMap(S, mapId, imagePath, pixelWidth, pixelHeight)
  local project = ensureProject(assert(S and S.project, "no project"))
  local source = project.layeredMaps and project.layeredMaps[mapId]
  if not source then return nil, "no layered map" end
  pixelWidth = tonumber(pixelWidth) or 0
  pixelHeight = tonumber(pixelHeight) or 0
  local cols = math.floor(pixelWidth / 16)
  local rows = math.floor(pixelHeight / 16)
  if cols < 1 or rows < 1 then
    return nil, "PNG must be at least 16x16 pixels"
  end
  local cellWidth = cols + (cols % 2)
  local cellHeight = rows + (rows % 2)
  local stem = tostring(imagePath or mapId):match("([^/\\]+)%.[Pp][Nn][Gg]$")
    or tostring(mapId) .. "_png"
  local tileSource, err = LayeredMap.installTileSource(
    project, stem, imagePath, cols * 16, rows * 16)
  if not tileSource then return nil, err end
  local ok, resizeErr = LayeredMap.resizeMap(project, mapId, cellWidth, cellHeight)
  if not ok then return nil, resizeErr end
  local ground = source.layers and source.layers[1]
  if not ground then return nil, "map has no Ground layer" end
  local cells, collision = {}, {}
  for y = 0, cellHeight - 1 do
    for x = 0, cellWidth - 1 do
      local index = y * cellWidth + x + 1
      local sx = math.min(x, cols - 1)
      local sy = math.min(y, rows - 1)
      cells[index] = internCellRef({
        source = tileSource.id,
        tile = sy * cols + sx,
      })
      collision[index] = "walk"
    end
  end
  ground.cells = cells
  source.collision = collision
  for layerIndex = 2, #(source.layers or {}) do
    source.layers[layerIndex].cells = {}
  end
  return tileSource, cellWidth, cellHeight
end

function LayeredMap.sourceDescriptor(S, sourceId)
  if LayeredMap.isRuntimeSource(sourceId) then
    local tilesetId = LayeredMap.runtimeTilesetId(sourceId)
    local tileset = resolveTileset(S, tilesetId)
    if not tileset then return nil end
    return {
      id = sourceId,
      name = tilesetId .. " (game blocks)",
      image = tileset.image,
      colorMode = tileset.trueColor and "true_color" or "palette",
      runtimeTileset = tilesetId,
      tileset = tileset,
      columns = 8,
      count = #(tileset.blocks or {}) * 4,
    }
  end
  return S.project and S.project.mapTileSources
    and S.project.mapTileSources[sourceId]
end

function LayeredMap.sourceIds(S, mapId)
  local ids, seen = {}, {}
  local function add(id)
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local mapSource = S.project and S.project.layeredMaps
    and S.project.layeredMaps[mapId]
  if mapSource and mapSource.layers then
    for _, layer in ipairs(mapSource.layers) do
      for _, ref in pairs(layer.cells or {}) do
        if type(ref) == "table" then add(ref.source) end
      end
    end
  end
  if mapSource and mapSource.baseTileset then
    add(LayeredMap.runtimeSourceId(mapSource.baseTileset))
  end

  -- A layered map may paint from any loaded game tileset. Keep the base
  -- source first, then expose the complete runtime registry alphabetically.
  local runtimeIds, runtimeSeen = {}, {}
  for _, bucket in ipairs({ S.project and S.project.tilesets,
      require("Generation").dataTilesets(S) }) do
    for tilesetId in pairs(bucket or {}) do
      if not runtimeSeen[tilesetId] then
        runtimeSeen[tilesetId] = true
        runtimeIds[#runtimeIds + 1] = tilesetId
      end
    end
  end
  table.sort(runtimeIds)
  for _, tilesetId in ipairs(runtimeIds) do
    add(LayeredMap.runtimeSourceId(tilesetId))
  end

  for _, id in ipairs(sortedKeys(S.project and S.project.mapTileSources)) do
    add(id)
  end
  return ids
end

function LayeredMap.setAnimationFrames(source, tile, frames)
  if not source or source.runtimeTileset then
    return false, "import a PNG to define a custom animation"
  end
  tile = math.floor(tonumber(tile) or 0)
  if tile < 0 or tile >= (source.count or 0) then
    return false, "animation tile is outside the source"
  end
  source.animations = source.animations or {}
  local normalized = {}
  for _, frame in ipairs(frames or {}) do
    local frameTile = math.floor(tonumber(frame.tile) or -1)
    if frameTile < 0 or frameTile >= (source.count or 0) then
      return false, "frame tile is outside the source"
    end
    normalized[#normalized + 1] = {
      tile = frameTile,
      duration = math.max(16, math.floor(tonumber(frame.duration) or 200)),
    }
  end
  source.animations[tile] = #normalized > 1 and normalized or nil
  return true
end

function LayeredMap.setSourceAnimation(source, tile, frameCount, duration)
  if not source or source.runtimeTileset then
    return false, "import a PNG to define a custom animation"
  end
  tile = math.floor(tonumber(tile) or 0)
  if tile < 0 or tile >= (source.count or 0) then
    return false, "animation tile is outside the source"
  end
  frameCount = math.floor(tonumber(frameCount) or 1)
  if frameCount <= 1 then
    return LayeredMap.setAnimationFrames(source, tile, {})
  end
  frameCount = math.min(frameCount, (source.count or 1) - tile)
  local frames = {}
  for offset = 0, frameCount - 1 do
    frames[#frames + 1] = { tile = tile + offset, duration = duration }
  end
  return LayeredMap.setAnimationFrames(source, tile, frames)
end

local function validPoint(point)
  return type(point) == "table" and type(point.map) == "string"
    and type(point.x) == "number" and type(point.y) == "number"
end

-- Warp endpoints are stored as a graph with stable ids. Runtime warp indexes
-- are assigned only during compilation, so inserting or deleting another
-- endpoint does not silently change a link in the editor project.
function LayeredMap.createWarpLink(project, mode, from, destination, returnPoint)
  ensureProject(project)
  if not validPoint(from) or not validPoint(destination) then
    return false, "source and destination cells are required"
  end
  if mode == "custom_return" and not validPoint(returnPoint) then
    return false, "custom return cell is required"
  end
  local first = LayeredMap.ensureWarpNode(project, from.map, from.x, from.y)
  local second = LayeredMap.ensureWarpNode(
    project, destination.map, destination.x, destination.y)
  first.active = true
  first.targetNode = second.id
  first.targetMap, first.targetIndex = nil, nil

  if mode == "two_way" then
    second.active = true
    second.targetNode = first.id
    second.targetMap, second.targetIndex = nil, nil
  elseif mode == "custom_return" then
    local third = LayeredMap.ensureWarpNode(
      project, returnPoint.map, returnPoint.x, returnPoint.y)
    second.active = true
    second.targetNode = third.id
    second.targetMap, second.targetIndex = nil, nil
    if third.targetNode == nil then third.active = false end
  else
    -- The destination record supplies arrival coordinates but does not fire.
    second.active = false
    second.targetNode = nil
    second.targetMap, second.targetIndex = nil, nil
  end
  return true, first.id, second.id
end

local function stripMapWarpsAt(project, mapId, x, y)
  local map = project.maps and project.maps[mapId]
  if not (map and map.warps) then return end
  for index = #map.warps, 1, -1 do
    local warp = map.warps[index]
    if warp and warp.x == x and warp.y == y then
      table.remove(map.warps, index)
    end
  end
end

function LayeredMap.removeWarpNode(project, nodeId)
  ensureProject(project)
  local gone = project.mapWarpNodes[nodeId]
  if not gone then return false end
  stripMapWarpsAt(project, gone.map, gone.x, gone.y)
  project.mapWarpNodes[nodeId] = nil
  for _, node in pairs(project.mapWarpNodes) do
    if node.targetNode == nodeId then
      node.targetNode = nil
      node.active = false
    end
  end
  return true
end

function LayeredMap.removeWarpAt(project, mapId, x, y)
  ensureProject(project)
  local node = nodeAt(project, mapId, x, y)
  if node then return LayeredMap.removeWarpNode(project, node.id) end
  stripMapWarpsAt(project, mapId, x, y)
  return true
end

function LayeredMap.adoptWarpRecord(project, mapId, warp)
  if not (project and mapId and type(warp) == "table") then return nil end
  ensureProject(project)
  if not project.layeredMaps[mapId] then return nil end
  local node = nodeAt(project, mapId, warp.x, warp.y)
    or newNode(project, mapId, warp.x, warp.y)
  node.active = true
  if not node.targetNode then
    node.targetMap = warp.destMap
    node.targetIndex = warp.destWarp
    node.destGroup = warp.destGroup
    node.destMapNum = warp.destMapNum
  end
  return node
end

function LayeredMap.moveWarpAt(project, mapId, oldX, oldY, newX, newY)
  ensureProject(project)
  local node = nodeAt(project, mapId, oldX, oldY)
  if not node then return false end
  node.x, node.y = newX, newY
  return true
end

function LayeredMap.nodesForMap(project, mapId)
  ensureProject(project)
  local nodes = {}
  for _, node in pairs(project.mapWarpNodes) do
    if node.map == mapId then nodes[#nodes + 1] = node end
  end
  table.sort(nodes, function(left, right)
    local lo = left.order or 0
    local ro = right.order or 0
    if lo == ro then return left.id < right.id end
    return lo < ro
  end)
  return nodes
end

function LayeredMap.renameMap(project, oldId, newId)
  ensureProject(project)
  local namespace = cleanId(project.id, "MOD")
  local oldTilesetId = namespace .. "_" .. cleanId(oldId, "MAP") .. "_LAYERED"
  local oldTileset = project.tilesets[oldTilesetId]
  if oldTileset and oldTileset._layeredGenerated then
    project.tilesets[oldTilesetId] = nil
  end
  if project.layeredMaps[oldId] then
    local source = project.layeredMaps[oldId]
    project.layeredMaps[oldId] = nil
    source.id = newId
    project.layeredMaps[newId] = source
  end
  for _, node in pairs(project.mapWarpNodes) do
    if node.map == oldId then node.map = newId end
    if node.targetMap == oldId then node.targetMap = newId end
  end
end

function LayeredMap.removeMap(project, mapId)
  ensureProject(project)
  local namespace = cleanId(project.id, "MOD")
  local tilesetId = namespace .. "_" .. cleanId(mapId, "MAP") .. "_LAYERED"
  local tileset = project.tilesets[tilesetId]
  if tileset and tileset._layeredGenerated then project.tilesets[tilesetId] = nil end
  project.layeredMaps[mapId] = nil
  local drop = {}
  for id, node in pairs(project.mapWarpNodes) do
    if node.map == mapId then drop[#drop + 1] = id end
  end
  for _, id in ipairs(drop) do LayeredMap.removeWarpNode(project, id) end
end

-- Runtime compiler

-- Source sampling -----------------------------------------------------------

local function readImageData(S, path)
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then error("image is unavailable: " .. tostring(path), 0) end
  if kind == "love" then
    local ok, image = pcall(love.image.newImageData, resolved)
    if ok and image then return image end
    error("could not decode " .. tostring(path) .. ": " .. tostring(image), 0)
  end
  local file = io.open(resolved, "rb")
  if not file then error("could not read " .. tostring(resolved), 0) end
  local bytes = file:read("*a")
  file:close()
  local name = resolved:match("[^/\\]+$") or "tiles.png"
  local okFile, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not okFile or not fileData then
    error("could not prepare " .. tostring(path), 0)
  end
  local ok, image = pcall(love.image.newImageData, fileData)
  if ok and image then return image end
  error("could not decode " .. tostring(path) .. ": " .. tostring(image), 0)
end

local function imageFor(context, source)
  local key = source.id or source.image
  if context.images[key] then return context.images[key] end
  local image = readImageData(context.S, source.image)
  context.images[key] = image
  return image
end

local function runtimeMicroTile(tileset, cellTile, micro)
  local blockId = math.floor(cellTile / 4)
  local quadrant = cellTile % 4
  local block = tileset.blocks and tileset.blocks[blockId + 1]
  if not block then return nil end
  local qx, qy = quadrant % 2, math.floor(quadrant / 2)
  local mx, my = micro % 2, math.floor(micro / 2)
  return block[(qy * 2 + my) * 4 + qx * 2 + mx + 1]
end

-- Gold: 4 GBC shades for one 8x8 in a runtime tileset, using the map's BG set.
local function gbcMicroPalette(S, map, source, cellTile, micro)
  if not (source and source.runtimeTileset) then return nil end
  if source.colorMode == "true_color" then return nil end
  local Generation = require("Generation")
  if not Generation.isGen2(S) then return nil end
  local bakeMap = Preview.gen2BakeMap(map, source.runtimeTileset)
  local bgSet = select(1, Preview.gen2MapBgSet(S, bakeMap))
  if not bgSet then return nil end
  local microTile = runtimeMicroTile(source.tileset, cellTile, micro)
  if microTile == nil then return nil end
  local pals = source.tileset and source.tileset.tilePalettes
  if not pals then
    local vanilla = Generation.dataTilesets(S)[source.runtimeTileset]
    pals = vanilla and vanilla.tilePalettes
  end
  local slot = (pals and pals[microTile + 1]) or 1
  return bgSet[slot]
end

local function animationFor(source, tile)
  if source.runtimeTileset then return nil end
  return source.animations and source.animations[tile]
end

local function paletteSample(r, g, b, a, colors)
  if not colors or a <= 0 then return r, g, b, a end
  local light = (r + g + b) / 3
  local color = light > 0.83 and colors[1]
    or light > 0.5 and colors[2]
    or light > 0.17 and colors[3] or colors[4]
  if not color then return r, g, b, a end
  return color[1] / 255, color[2] / 255, color[3] / 255, a
end

local function sourcePixel(context, source, tile, micro, x, y, paletteColors)
  local image = imageFor(context, source)
  local sx, sy
  if source.runtimeTileset then
    local microTile = runtimeMicroTile(source.tileset, tile, micro)
    if microTile == nil then return 0, 0, 0, 0 end
    local columns = source.tileset.tilesPerRow
      or math.max(1, math.floor(image:getWidth() / 8))
    sx = (microTile % columns) * 8 + x
    sy = math.floor(microTile / columns) * 8 + y
  else
    local columns = source.columns or math.max(1, math.floor(image:getWidth() / 16))
    sx = (tile % columns) * 16 + (micro % 2) * 8 + x
    sy = math.floor(tile / columns) * 16 + math.floor(micro / 2) * 8 + y
  end
  if sx < 0 or sy < 0 or sx >= image:getWidth() or sy >= image:getHeight() then
    return 0, 0, 0, 0
  end
  local r, g, b, a = image:getPixel(sx, sy)
  if paletteColors and source.colorMode ~= "true_color" then
    return paletteSample(r, g, b, a, paletteColors)
  end
  return r, g, b, a
end

local function colorByte(value)
  return math.floor(clamp(value, 0, 1) * 255 + 0.5)
end

-- Custom art can ship with the mod, but the transform sandbox deliberately
-- cannot read arbitrary mod files. Embed only the used 8x8 samples in the
-- generated recipe; base-game samples stay as coordinates into the player's
-- own imported cache.
local function embeddedMicro(context, source, tile, micro)
  context.microIds = context.microIds or {}
  local lookup = tostring(source.id or source.image) .. ":"
    .. tostring(tile) .. ":" .. tostring(micro)
  local cached = context.microIds[lookup]
  if cached then return cached end
  local pack = context._packBytes
  if not pack then
    pack = {}
    context._packBytes = pack
  end
  local n = 0
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = sourcePixel(context, source, tile, micro, x, y, nil)
      pack[n + 1] = colorByte(r)
      pack[n + 2] = colorByte(g)
      pack[n + 3] = colorByte(b)
      pack[n + 4] = colorByte(a)
      n = n + 4
    end
  end
  local raw = string.char(unpack(pack, 1, n))
  local id = context.pixelIds[raw]
  if not id then
    id = "P" .. tostring(#context.pixels + 1)
    context.pixelIds[raw] = id
    context.pixels[#context.pixels + 1] = { id = id, bytes = raw }
  end
  context.microIds[lookup] = id
  return id
end

local function transformSpec(context, refs, micro, animatedIndex, frameTile,
    paletteColors)
  local layers = {}
  for index, ref in ipairs(refs) do
    local tile = index == animatedIndex and frameTile or ref.tile
    local layer = { opacity = ref.opacity }
    local source = ref.source
    local generatedPrefix = "assets/generated/"
    if source.runtimeTileset
        and type(source.image) == "string"
        and source.image:sub(1, #generatedPrefix) == generatedPrefix then
      local microTile = runtimeMicroTile(source.tileset, tile, micro)
      local relative = source.image:sub(#generatedPrefix + 1)
      layer.base = relative
      layer.tile = microTile or 0
      layer.columns = source.tileset.tilesPerRow or 16
      context.bases[relative] = true
    else
      layer.pixels = embeddedMicro(context, source, tile, micro)
    end
    local pal = paletteColors
    if not pal then
      pal = gbcMicroPalette(context.S, context.map, source, tile, micro)
    end
    if pal and source.colorMode ~= "true_color" then
      layer.palette = pal
    end
    -- Upper layers keep PNG color 0 transparent so grass shows through
    -- building/sign tiles. Only the bottom layer fills GBC holes.
    if index > 1 then layer.overlay = true end
    layers[#layers + 1] = layer
  end
  return layers
end

local function transformSpecKey(spec)
  local parts = {}
  for _, layer in ipairs(spec or {}) do
    parts[#parts + 1] = table.concat({
      layer.base or "", layer.pixels or "", tostring(layer.tile or ""),
      tostring(layer.columns or ""), tostring(layer.opacity or 1),
      layer.overlay and "ov" or "",
    }, ":")
    if layer.palette then
      for _, color in ipairs(layer.palette) do
        parts[#parts + 1] = table.concat(color, ",")
      end
    end
  end
  return table.concat(parts, "|")
end

local function addTransformOutput(context, relative, width, height, placements)
  context.outputs[relative] = {
    path = relative, width = width, height = height, placements = placements,
  }
end

local function sampleTransformLayer(layer, baseImages, pixelsById, x, y)
  local r, g, b, a = 0, 0, 0, 0
  if layer.base then
    local image = baseImages[layer.base]
    if not image then return 0, 0, 0, 0 end
    local columns = layer.columns or 16
    local sx = (layer.tile % columns) * 8 + x
    local sy = math.floor(layer.tile / columns) * 8 + y
    if sx < 0 or sy < 0 or sx >= image:getWidth() or sy >= image:getHeight() then
      return 0, 0, 0, 0
    end
    r, g, b, a = image:getPixel(sx, sy)
  else
    local raw = pixelsById[layer.pixels]
    if type(raw) ~= "string" then return 0, 0, 0, 0 end
    local offset = (y * 8 + x) * 4 + 1
    local rb, gb, bb, ab = string.byte(raw, offset, offset + 3)
    if not rb then return 0, 0, 0, 0 end
    r, g, b, a = rb / 255, gb / 255, bb / 255, (ab or 0) / 255
  end
  -- GBC sheets store color 0 as transparent in the PNG. The editor shader
  -- still paints that as palette[1]. Skipping it here punches holes in the
  -- trueColor atlas, and Gold's world canvas is white behind them.
  -- Overlay layers (buildings on grass) must keep that transparency;
  -- filling it with palette[1] paints white boxes on Yellow/Gen1 maps.
  if layer.palette then
    if a <= 0 then
      if not layer.base or layer.overlay then
        return 0, 0, 0, a * (layer.opacity or 1)
      end
      a = 1
      r, g, b = 1, 1, 1
    end
    local light = (r + g + b) / 3
    local color = light > 0.83 and layer.palette[1]
      or light > 0.5 and layer.palette[2]
      or light > 0.17 and layer.palette[3] or layer.palette[4]
    if color then
      r, g, b = color[1] / 255, color[2] / 255, color[3] / 255
    end
  end
  return r, g, b, a * (layer.opacity or 1)
end

-- Write compiled mapbuilder atlases into the editor save directory so
-- MapLoader / TileRenderer can preview them before the game transform runs.
local function writeEditorDerivedImages(context)
  if not (love and love.image and love.image.newImageData
      and love.filesystem and love.filesystem.createDirectory) then
    return
  end
  local project = context.project
  if not project then return end
  local pixelsById = {}
  for _, entry in ipairs(context.pixels or {}) do
    if entry.id and entry.bytes then pixelsById[entry.id] = entry.bytes end
  end
  local baseImages = {}
  for relative in pairs(context.bases or {}) do
    local ok, image = pcall(readImageData, context.S,
      "assets/generated/" .. relative)
    if ok and image then baseImages[relative] = image end
  end
  for _, output in pairs(context.outputs or {}) do
    local image = love.image.newImageData(output.width, output.height)
    for _, placement in ipairs(output.placements or {}) do
      for y = 0, 7 do
        for x = 0, 7 do
          local outR, outG, outB, outA = 0, 0, 0, 0
          local premulR, premulG, premulB = 0, 0, 0
          for _, layer in ipairs(placement.layers or {}) do
            local r, g, b, a = sampleTransformLayer(
              layer, baseImages, pixelsById, x, y)
            premulR = r * a + premulR * (1 - a)
            premulG = g * a + premulG * (1 - a)
            premulB = b * a + premulB * (1 - a)
            outA = a + outA * (1 - a)
          end
          if outA > 0 then
            outR, outG, outB = premulR / outA, premulG / outA, premulB / outA
          end
          image:setPixel(placement.x + x, placement.y + y,
            outR, outG, outB, outA)
        end
      end
    end
    local dest = "save/mod-derived/" .. tostring(project.id) .. "/" .. output.path
    local dir = dest:match("^(.*)/[^/]+$")
    if dir then love.filesystem.createDirectory(dir) end
    pcall(function() image:encode("png", dest) end)
    if image.release then pcall(image.release, image) end
  end
  for _, image in pairs(baseImages) do
    if image and image.release then pcall(image.release, image) end
  end
end

local function cellRefs(context, mapSource, index)
  local refs = {}
  for _, layer in ipairs(mapSource.layers or {}) do
    if layer.export ~= false then
      local ref = layer.cells and layer.cells[index]
      if ref then
        local source = LayeredMap.sourceDescriptor(context.S, ref.source)
        if not source then
          error("unknown map tileset source " .. tostring(ref.source), 0)
        end
        refs[#refs + 1] = {
          source = source,
          tile = math.max(0, math.floor(tonumber(ref.tile) or 0)),
          opacity = clamp(layer.opacity or 1, 0, 1),
        }
      end
    end
  end
  return refs
end

local function frameInfo(refs)
  local animatedIndex, frames
  for index, ref in ipairs(refs) do
    local candidate = animationFor(ref.source, ref.tile)
    if candidate and #candidate > 1 then
      if frames then
        return nil, nil, "a cell cannot stack more than one animated tile"
      end
      animatedIndex, frames = index, candidate
    end
  end
  return animatedIndex, frames
end

local function timing(frames)
  local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
  end
  local ticks, divisor = {}, nil
  for index, frame in ipairs(frames) do
    local count = math.max(1,
      math.floor((tonumber(frame.duration) or 200) * 60 / 1000 + 0.5))
    ticks[index] = count
    divisor = divisor and gcd(divisor, count) or count
  end
  local sequence = {}
  for index, count in ipairs(ticks) do
    for _ = 1, count / divisor do sequence[#sequence + 1] = index end
  end
  return divisor or 1, sequence
end

local function safeFilename(value)
  local name = tostring(value or "map"):lower():gsub("[^a-z0-9_-]", "_")
  return name ~= "" and name or "map"
end

local function derivedAssetPath(project, relative)
  return "save/mod-derived/" .. tostring(project.id) .. "/" .. relative
end

local function generatedTilesetId(project, mapId)
  return cleanId(project.id, "MOD") .. "_" .. cleanId(mapId, "MAP")
    .. "_LAYERED"
end

local function paletteNameForMap(S, map, mapSource)
  -- Compiling replaces the authored/base tileset id with a generated id. Gen1
  -- palette defaults are keyed by the original tileset id, so resolve through
  -- baseTileset when the map does not carry an explicit palette of its own.
  if type(map.palette) == "string" and map.palette ~= "" then
    return map.palette
  end
  if mapSource and mapSource.baseTileset then
    local lookup = setmetatable({ tileset = mapSource.baseTileset },
      { __index = map })
    return Preview.mapPaletteName(S, lookup)
  end
  return Preview.mapPaletteName(S, map)
end

local function paletteForMap(S, map, mapSource)
  local name = paletteNameForMap(S, map, mapSource)
  return Preview.paletteColors(S, name), name
end

local function usesTrueColor(context, mapSource)
  for index = 1, mapSource.cellWidth * mapSource.cellHeight do
    for _, ref in ipairs(cellRefs(context, mapSource, index)) do
      if ref.source.colorMode == "true_color" then return true end
    end
  end
  return false
end

-- Assign final one-based runtime indexes after the complete endpoint graph is
-- known. Arrival-only nodes are retained because active warps may target them.
local function warpPlan(project)
  local groups, indexByNode, activeCells = {}, {}, {}
  for mapId in pairs(project.layeredMaps or {}) do
    groups[mapId] = LayeredMap.nodesForMap(project, mapId)
    activeCells[mapId] = {}
  end
  for mapId, nodes in pairs(groups) do
    for index, node in ipairs(nodes) do
      indexByNode[node.id] = index
      if node.active then
        activeCells[mapId][node.y * project.layeredMaps[mapId].cellWidth
          + node.x + 1] = true
      end
    end
  end
  local records = {}
  for mapId, nodes in pairs(groups) do
    records[mapId] = {}
    for index, node in ipairs(nodes) do
      local target = node.targetNode and project.mapWarpNodes[node.targetNode]
      local destMap, destWarp
      if node.targetMap and node.targetMap ~= mapId then
        destMap = node.targetMap
        destWarp = node.targetIndex
      elseif target then
        destMap = target.map
        destWarp = indexByNode[target.id] or target.originalIndex
      else
        destMap = node.targetMap
        destWarp = node.targetIndex
      end
      if not destMap or not destWarp then
        destMap, destWarp = mapId, index
      end
      records[mapId][index] = {
        x = node.x, y = node.y,
        destMap = destMap, destWarp = destWarp,
        destGroup = node.destGroup,
        destMapNum = node.destMapNum,
      }
    end
  end
  return records, activeCells
end

-- Transform recipe generation ----------------------------------------------

local function luaString(value)
  local out = { '"' }
  value = tostring(value or "")
  for index = 1, #value do
    local byteValue = value:byte(index)
    if byteValue >= 32 and byteValue <= 126
        and byteValue ~= 34 and byteValue ~= 92 then
      out[#out + 1] = string.char(byteValue)
    else
      out[#out + 1] = string.format("\\%03d", byteValue)
    end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

local function luaLiteral(value)
  local kind = type(value)
  if kind == "nil" then return "nil" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return luaString(value) end
  if kind ~= "table" then return "nil" end

  local length = #value
  local sequence = true
  local count = 0
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key > length
        or key % 1 ~= 0 then sequence = false end
  end
  local parts = {}
  if sequence and count == length then
    for index = 1, length do parts[#parts + 1] = luaLiteral(value[index]) end
  else
    for _, key in ipairs(sortedKeys(value)) do
      parts[#parts + 1] = "[" .. luaString(key) .. "]=" .. luaLiteral(value[key])
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function emitTransform(context)
  local bases = sortedKeys(context.bases)
  local pixels = {}
  for _, entry in ipairs(context.pixels) do pixels[entry.id] = entry.bytes end
  local outputs = {}
  for _, path in ipairs(sortedKeys(context.outputs)) do
    outputs[#outputs + 1] = context.outputs[path]
  end

  local lines = {
    "-- Generated by Map Builder. Saving the project rewrites this file.",
    "-- Base-game pixels are sampled from the player's imported cache; only",
    "-- custom source pixels used by the composed maps are stored here.",
    "local BASES = " .. luaLiteral(bases),
    "local PIXELS = " .. luaLiteral(pixels),
    "local OUTPUTS = " .. luaLiteral(outputs),
    "",
    "local function sample(layer, baseImages, x, y)",
    "  local r, g, b, a",
    "  if layer.base then",
    "    local image = baseImages[layer.base]",
    "    local sx = (layer.tile % layer.columns) * 8 + x",
    "    local sy = math.floor(layer.tile / layer.columns) * 8 + y",
    "    r, g, b, a = image:getPixel(sx, sy)",
    "  else",
    "    local raw = PIXELS[layer.pixels]",
    "    local offset = (y * 8 + x) * 4 + 1",
    "    local rb, gb, bb, ab = string.byte(raw, offset, offset + 3)",
    "    r, g, b, a = rb / 255, gb / 255, bb / 255, ab / 255",
    "  end",
    "  if layer.palette then",
    "    if a <= 0 then",
    "      if not layer.base or layer.overlay then",
    "        return 0, 0, 0, a * (layer.opacity or 1)",
    "      end",
    "      a = 1",
    "      r, g, b = 1, 1, 1",
    "    end",
    "    local light = (r + g + b) / 3",
    "    local color = light > 0.83 and layer.palette[1]",
    "      or light > 0.5 and layer.palette[2]",
    "      or light > 0.17 and layer.palette[3] or layer.palette[4]",
    "    r, g, b = color[1] / 255, color[2] / 255, color[3] / 255",
    "  end",
    "  return r, g, b, a * (layer.opacity or 1)",
    "end",
    "",
    "return function(ctx)",
    "  local baseImages = {}",
    "  for _, relative in ipairs(BASES) do",
    "    if not ctx.exists(relative) then return end",
    "    baseImages[relative] = ctx.readImage(relative)",
    "  end",
    "  for _, output in ipairs(OUTPUTS) do",
    "    local image = ctx.blank(output.width, output.height)",
    "    for _, placement in ipairs(output.placements) do",
    "      for y = 0, 7 do",
    "        for x = 0, 7 do",
    "          local outR, outG, outB, outA = 0, 0, 0, 0",
    "          local premulR, premulG, premulB = 0, 0, 0",
    "          for _, layer in ipairs(placement.layers) do",
    "            local r, g, b, a = sample(layer, baseImages, x, y)",
    "            premulR = r * a + premulR * (1 - a)",
    "            premulG = g * a + premulG * (1 - a)",
    "            premulB = b * a + premulB * (1 - a)",
    "            outA = a + outA * (1 - a)",
    "          end",
    "          if outA > 0 then",
    "            outR, outG, outB = premulR / outA, premulG / outA, premulB / outA",
    "          end",
    "          image:setPixel(placement.x + x, placement.y + y,",
    "            outR, outG, outB, outA)",
    "        end",
    "      end",
    "    end",
    "    ctx.writeImage(image, output.path)",
    "  end",
    "end",
    "",
  }
  local sep = package.config:sub(1, 1)
  local path = context.S.path .. sep .. "mapbuilder_transforms.lua"
  local ok, err = ModIO.writeText(path, table.concat(lines, "\n"))
  if not ok then return false, err end
  return ModIO.setMapBuilderTransform(context.S.path, "mapbuilder_transforms.lua")
end

-- Map assembly --------------------------------------------------------------

local function exportedCellsAt(mapSource, index)
  local refs = {}
  for _, layer in ipairs(mapSource.layers or {}) do
    if layer.export ~= false then
      local cell = layer.cells and layer.cells[index]
      if type(cell) == "table" and cell.source then
        refs[#refs + 1] = cell
      end
    end
  end
  return refs
end

-- If every 32x32 is one game-tileset metatile, keep that tileset. Mixed 16x16
-- cells in a 2x2 (or a custom PNG) return nil so Save bakes an atlas that
-- matches the editor instead of flattening the map.
local function runtimeBlockGrid(mapSource)
  local width, height = mapSource.cellWidth, mapSource.cellHeight
  local tilesetId, blocks = nil, {}
  for blockY = 0, height / 2 - 1 do
    for blockX = 0, width / 2 - 1 do
      local blockId = nil
      for cellY = 0, 1 do
        for cellX = 0, 1 do
          local index = (blockY * 2 + cellY) * width + blockX * 2 + cellX + 1
          local refs = exportedCellsAt(mapSource, index)
          local ref = refs[#refs]
          if ref then
            local ts = LayeredMap.runtimeTilesetId(ref.source)
            if not ts then return nil end
            if tilesetId and tilesetId ~= ts then return nil end
            tilesetId = ts
            local b = math.floor((tonumber(ref.tile) or 0) / 4)
            if blockId ~= nil and blockId ~= b then return nil end
            blockId = b
          end
        end
      end
      blocks[#blocks + 1] = blockId or 0
    end
  end
  return tilesetId or mapSource.baseTileset, blocks
end

local function dropGeneratedTileset(S, project, mapId)
  local genId = generatedTilesetId(project, mapId)
  local ts = project.tilesets[genId]
  if ts and ts._layeredGenerated then project.tilesets[genId] = nil end
  local function dropLive(bag)
    local live = bag and bag[genId]
    if live and live._layeredGenerated then bag[genId] = nil end
  end
  if S and S.data then
    dropLive(S.data.tilesets)
    dropLive(S.data.gen2Tilesets)
  end
  return genId
end

local function applyCompiledWarps(map, warpRecords)
  map.warps = type(warpRecords) == "table" and warpRecords or {}
end

local function compilePassthrough(context, mapId, mapSource, warpRecords,
    tilesetId, mapBlocks)
  local project, S, map = context.project, context.S, context.project.maps[mapId]
  dropGeneratedTileset(S, project, mapId)
  map.tileset = tilesetId
  map.width = mapSource.cellWidth / 2
  map.height = mapSource.cellHeight / 2
  map.blocks = mapBlocks
  if map.borderBlock == nil then
    map.borderBlock = 0
  end
  map.trueColor = nil
  map._layeredSource = mapId
  applyCompiledWarps(map, warpRecords)
  return map
end

-- Each 16x16 editor cell becomes four 8x8 graphics tiles. Groups of four
-- editor cells are then deduplicated into the runtime's 32x32 map blocks.
local function compileMap(context, mapId, mapSource, warpRecords, activeWarpCells)
  local project, S = context.project, context.S
  local map = project.maps[mapId]
  if not map then error("layered map has no map record: " .. mapId, 0) end
  local width, height = mapSource.cellWidth, mapSource.cellHeight
  if width < 2 or height < 2 or width % 2 ~= 0 or height % 2 ~= 0 then
    error(mapId .. ": map dimensions must be even 16x16-cell values", 0)
  end

  for _, node in ipairs(LayeredMap.nodesForMap(project, mapId)) do
    if node.x < 0 or node.y < 0 or node.x >= width or node.y >= height then
      error(("%s: warp %s is outside the resized map"):format(mapId, node.id), 0)
    end
  end

  local inferredTileset, passthroughBlocks = runtimeBlockGrid(mapSource)
  local genId = generatedTilesetId(project, mapId)
  local assigned = mapSource.baseTileset or map.tileset
  if assigned == genId then assigned = nil end
  if inferredTileset and passthroughBlocks then
    local keepTileset = assigned or inferredTileset
    if keepTileset and keepTileset ~= genId then
      return compilePassthrough(context, mapId, mapSource, warpRecords,
        keepTileset, passthroughBlocks)
    end
  end

  local tilesetId = generatedTilesetId(project, mapId)
  local previousTileset = project.tilesets[tilesetId]
  context.map = map
  -- GFX/Tilesets is allowed to force a generated atlas to TrueColor. Preserve
  -- that authored override across recompiles instead of replacing it with the
  -- color modes inferred from the painted sources.
  -- Gold layered maps bake GBC shades into the atlas so playtest matches the
  -- editor (the game will not remap a generated unique-tile sheet correctly).
  local gen2 = require("Generation").isGen2(S)
  local trueColor = usesTrueColor(context, mapSource)
    or (previousTileset and previousTileset.trueColor) or gen2 or false
  local paletteColors, paletteName = paletteForMap(S, map, mapSource)
  -- Mixed atlases are emitted as true color, so palette-mode layers must be
  -- baked. Fully palette-mode atlases keep grayscale pixels for runtime remap.
  -- Gen2 uses per-8x8 GBC palettes in transformSpec instead of one SGB set.
  if gen2 or not trueColor then paletteColors = nil end
  local tiles, tileIds = {}, {}
  local cells = {}
  local animatedTiles = {}
  local walkable, water, shore, warp = {}, {}, {}, {}
  local grassTile

  local function addTile(spec, class, animationImages, frames)
    local animKey = ""
    if frames then
      local parts = {}
      for _, frame in ipairs(frames) do
        parts[#parts + 1] = tostring(frame.tile) .. ":" .. tostring(frame.duration)
      end
      animKey = "|anim=" .. table.concat(parts, ",")
    end
    local key = transformSpecKey(spec)
      .. "|class=" .. tostring(class or "") .. animKey
    local id = tileIds[key]
    if id ~= nil then return id end
    id = #tiles
    -- Unique 8x8 count can exceed the Gen I 256-tile sheet; bake true-color
    -- so large maps are not rejected.
    if id >= 256 then trueColor = true end
    tileIds[key] = id
    tiles[#tiles + 1] = { layers = spec, class = class }
    local baseClass = class and class:gsub("%+warp$", "") or nil
    if baseClass == "walk" then walkable[id] = true
    elseif baseClass == "grass" then
      walkable[id] = true
      -- The original format has one grass collision tile. Additional grass
      -- graphics remain walkable; the first one carries encounter behavior.
      grassTile = grassTile or id
    elseif baseClass == "water" then water[id] = true
    elseif baseClass == "shore" then shore[id] = true end
    if class and class:find("+warp", 1, true) then warp[id] = true end
    if animationImages and frames then
      local period, sequence = timing(frames)
      animatedTiles[#animatedTiles + 1] = {
        tile = id, kind = "frames", period = period,
        images = animationImages, sequence = sequence,
      }
    end
    return id
  end

  local cellGraphicCache = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local refs = cellRefs(context, mapSource, index)
      local animatedIndex, frames, frameErr = frameInfo(refs)
      if frameErr then
        error(("%s (%d,%d): %s"):format(mapId, x, y, frameErr), 0)
      end
      local class = mapSource.collision[index] or "solid"
      if activeWarpCells and activeWarpCells[index] then
        class = class .. "+warp"
      end
      local cacheKey
      if frames then
        cacheKey = nil
      else
        local parts = { class }
        for ri = 1, #refs do
          local r = refs[ri]
          parts[#parts + 1] = tostring(r.source.id or r.source.image)
          parts[#parts + 1] = tostring(r.tile)
          parts[#parts + 1] = tostring(r.opacity)
        end
        cacheKey = table.concat(parts, "\0")
      end
      local cached = cacheKey and cellGraphicCache[cacheKey]
      if cached then
        cells[index] = cached
      else
        local microIds = {}
        for micro = 0, 3 do
          local firstFrame = frames and frames[1].tile or nil
          local spec = transformSpec(
            context, refs, micro, animatedIndex, firstFrame, paletteColors)
          local tileClass = micro == 2 and class or nil
          local animationImages
          if frames then
            animationImages = {}
            for frameIndex, frame in ipairs(frames) do
              local frameSpec = transformSpec(context, refs, micro,
                animatedIndex, frame.tile, paletteColors)
              local rel = ("mapbuilder/%s/animations/%s_%d_%d_%d.png")
                :format(safeFilename(project.id), safeFilename(mapId),
                  index, micro, frameIndex)
              addTransformOutput(context, rel, 8, 8, {
                { x = 0, y = 0, layers = frameSpec },
              })
              animationImages[#animationImages + 1] = derivedAssetPath(project, rel)
            end
          end
          microIds[micro + 1] = addTile(spec, tileClass, animationImages, frames)
        end
        if cacheKey then cellGraphicCache[cacheKey] = microIds end
        cells[index] = microIds
      end
    end
  end

  if #tiles == 0 then
    addTile({}, "solid")
  end
  -- Gold's void is tileset block 0 when map.borderBlock is 0. Pack that
  -- 32x32 before the atlas is written, using the same wall the editor
  -- previews (base-tileset metatile, or an explicit 16x16), not sixteen
  -- copies of whatever 8x8 happened to be packed first.
  local borderGraphic = nil
  do
    local srcId = (map._borderExplicit and map._borderSource)
      or LayeredMap.runtimeSourceId(mapSource.baseTileset)
    local source = srcId and LayeredMap.sourceDescriptor(S, srcId)
    if source then
      local metatile = map.borderBlock or 0
      local graphic = {}
      for q = 0, 3 do
        local cellTile = metatile * 4 + q
        if map._borderExplicit and type(map._borderTile) == "number" then
          cellTile = map._borderTile
        end
        local refs = { { source = source, tile = cellTile, opacity = 1 } }
        local cellY, cellX = math.floor(q / 2), q % 2
        for micro = 0, 3 do
          local spec = transformSpec(
            context, refs, micro, nil, nil, paletteColors)
          local microY, microX = math.floor(micro / 2), micro % 2
          graphic[(cellY * 2 + microY) * 4 + cellX * 2 + microX + 1]
            = addTile(spec, "solid")
        end
      end
      borderGraphic = graphic
    end
  end
  local atlasWidth = 128
  local atlasHeight = math.max(8, math.ceil(#tiles / 16) * 8)
  local atlasPlacements = {}
  for id, entry in ipairs(tiles) do
    local tileId = id - 1
    atlasPlacements[#atlasPlacements + 1] = {
      x = (tileId % 16) * 8,
      y = math.floor(tileId / 16) * 8,
      layers = entry.layers,
    }
  end
  local atlasTransformRel = "mapbuilder/" .. safeFilename(project.id) .. "/"
    .. safeFilename(mapId) .. "_tiles.png"
  addTransformOutput(context, atlasTransformRel,
    atlasWidth, atlasHeight, atlasPlacements)
  local atlasRel = derivedAssetPath(project, atlasTransformRel)

  local blocks, blockIds, collisionQuads = {}, {}, {}
  -- Gold treats block id 0 as "use the map border" (Map:cellCollision /
  -- LoadMetatiles). The 16 8x8s here are that border graphic.
  blocks[1] = borderGraphic
    or { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  collisionQuads[1] = { 0xff, 0xff, 0xff, 0xff }
  local COLL = {
    solid = 0x07, walk = 0x00, grass = 0x18, water = 0x21, shore = 0x23,
  }
  -- Gold only takes a warp if the cell's COLL_* is a warp kind (door, carpet,
  -- stairs). Gen 1 uses warpTiles on the 8x8 sheet; that list is not enough.
  local COLL_DOOR = 0x71
  local function addBlock(block, quad)
    local key = table.concat(block, ",") .. ":" .. table.concat(quad, ",")
    local id = blockIds[key]
    if id ~= nil then return id end
    id = #blocks
    if id >= 256 then trueColor = true end
    blockIds[key] = id
    blocks[#blocks + 1] = block
    collisionQuads[#collisionQuads + 1] = quad
    return id
  end
  local mapBlocks = {}
  for blockY = 0, height / 2 - 1 do
    for blockX = 0, width / 2 - 1 do
      local block, quad = {}, {}
      for cellY = 0, 1 do
        for cellX = 0, 1 do
          local index = (blockY * 2 + cellY) * width
            + blockX * 2 + cellX + 1
          local microIds = cells[index]
          local mode = (mapSource.collision and mapSource.collision[index])
            or "solid"
          local collByte = COLL[mode] or 0x07
          if activeWarpCells and activeWarpCells[index] then
            collByte = COLL_DOOR
          end
          quad[cellY * 2 + cellX + 1] = collByte
          for microY = 0, 1 do
            for microX = 0, 1 do
              block[(cellY * 2 + microY) * 4
                + cellX * 2 + microX + 1] = microIds[microY * 2 + microX + 1]
            end
          end
        end
      end
      mapBlocks[#mapBlocks + 1] = addBlock(block, quad)
    end
  end

  local function values(set)
    local out = {}
    for value in pairs(set) do out[#out + 1] = value end
    table.sort(out)
    return out
  end

  local tileset = {
    id = tilesetId,
    image = atlasRel,
    imageWidth = atlasWidth,
    imageHeight = atlasHeight,
    tilesPerRow = 16,
    blocks = blocks,
    walkable = values(walkable),
    waterTiles = values(water),
    shoreTiles = values(shore),
    doorTiles = {},
    warpTiles = values(warp),
    counterTiles = {},
    animation = "TILEANIM_NONE",
    trueColor = trueColor and true or nil,
    animatedTiles = #animatedTiles > 0 and animatedTiles or nil,
    collision = (trueColor or require("Generation").isGen2(context.S))
      and collisionQuads or nil,
    _isNew = true,
    _layeredGenerated = true,
  }
  project.tilesets[tilesetId] = tileset

  map.tileset = tilesetId
  -- Preserve the Gen1 palette association that would otherwise be lost when
  -- map.tileset changes from (for example) CAVERN to MOD_MAP_LAYERED.
  if not trueColor and (type(map.palette) ~= "string" or map.palette == "") then
    -- Only stamp an explicit value when changing the tileset actually changes
    -- resolution (notably CAVERN/CEMETERY). Interiors whose vanilla behavior
    -- inherits the last outdoor palette must remain unset.
    local generatedDefault = Preview.mapPaletteName(S, map)
    if paletteName ~= generatedDefault then map.palette = paletteName end
  end
  map.width, map.height = width / 2, height / 2
  map.blocks = mapBlocks
  -- Layered block 0 is the void graphic; Gold reads that when borderBlock is 0.
  map.borderBlock = 0
  -- Bedroom MAPCALLBACK_TILES paints the feathery bed / town-map poster with
  -- vanilla TILESET_PLAYERS_ROOM block ids (0x1b, 0x1f). Those ids do not
  -- exist on a generated atlas, so Gold leaves those 32x32s as the canvas
  -- clear colour (white holes). The painted blocks are the map now.
  if type(map.callbacks) == "table" then
    local kept = {}
    for i = 1, #map.callbacks do
      local cb = map.callbacks[i]
      if not (type(cb) == "table" and cb.callback == "MAPCALLBACK_TILES") then
        kept[#kept + 1] = cb
      end
    end
    map.callbacks = kept
  end
  applyCompiledWarps(map, warpRecords)
  -- Carry this on both records.  The tileset flag is the canonical link, but
  -- editor/world previews can temporarily retain an older tileset object
  -- while a generated map is being rebuilt.  The map-level override makes
  -- the color contract immediate and is also what TileRenderer checks first.
  map.trueColor = trueColor and true or nil
  map._layeredSource = mapId
  return map, tileset
end

-- Compiler entry point ------------------------------------------------------

local function tilesetResolves(S, tilesetId)
  return type(tilesetId) == "string" and tilesetId ~= ""
    and resolveTileset(S, tilesetId) ~= nil
end

local function generatedTilesetName(tilesetId)
  return type(tilesetId) == "string"
    and tilesetId:find("_LAYERED", 1, true) ~= nil
end

-- ROM map / tileset when live Data still holds another mod's generated atlas.
local function vanillaMapFor(S, mapId)
  local bak = S and S._vanillaMapBackup and S._vanillaMapBackup[mapId]
  if type(bak) == "table" and tilesetResolves(S, bak.tileset) then
    return bak
  end
  return nil
end

local function vanillaTilesetForMap(S, mapId, map)
  local vanilla = vanillaMapFor(S, mapId)
  if vanilla then return vanilla.tileset, vanilla end
  local index = map and tonumber(map.tilesetId)
  if index ~= nil then
    if type(S._vanillaTilesetIds) == "table" then
      for id in pairs(S._vanillaTilesetIds) do
        local rec = resolveTileset(S, id)
        if rec and rec.index == index then return id, nil end
      end
    end
    local constants = S.data and (S.data.gen2Constants or S.data.constants)
    local order = constants and constants.tilesetOrder
    if type(order) == "table" then
      local id = order[index + 1] or order[index]
      if tilesetResolves(S, id) then return id, nil end
    end
  end
  return nil, nil
end

-- Every owned map must point at a tileset this mod can emit. Leftover
-- TEST_MAP_*_LAYERED ids from another project fail validation otherwise.
function LayeredMap.ensureMissingMapTilesets(S, project)
  project = ensureProject(project or (S and S.project))
  for mapId, source in pairs(project.layeredMaps) do
    if not project.maps[mapId] then
      if not ownedMap(S, mapId) then
        return false, "layered map has no map record: " .. tostring(mapId)
      end
    end
    if type(source) == "table" and source.baseTileset
        and not tilesetResolves(S, source.baseTileset) then
      local tid = vanillaTilesetForMap(S, mapId, project.maps[mapId])
      if tid then LayeredMap.assignTileset(S, mapId, tid) end
    end
  end
  for _, mapId in ipairs(sortedKeys(project.maps)) do
    local map = project.maps[mapId]
    if type(map) == "table" and not tilesetResolves(S, map.tileset) then
      local missing = map.tileset
      if not project.layeredMaps[mapId] then
        local tid, vanilla = vanillaTilesetForMap(S, mapId, map)
        if not tid then
          return false, mapId .. ": unresolved tileset "
            .. tostring(missing)
        end
        if generatedTilesetName(missing) and vanilla
            and type(vanilla.blocks) == "table" then
          map.blocks = deepCopy(vanilla.blocks)
          if vanilla.width then map.width = vanilla.width end
          if vanilla.height then map.height = vanilla.height end
        end
        map.tileset = tid
        local source, err = LayeredMap.convertMap(S, mapId)
        if not source then
          return false, err or (mapId .. ": could not generate tileset")
        end
      end
    end
  end
  return true
end

function LayeredMap.compileProject(S)
  if not (S and S.project and S.path) then return false, "no open mod" end
  local project = ensureProject(S.project)
  local okTilesets, tilesetErr = LayeredMap.ensureMissingMapTilesets(S, project)
  if not okTilesets then return false, tilesetErr end
  if not next(project.layeredMaps) then
    if project.layeredTransform then
      local removed, removeErr = ModIO.removeMapBuilderTransform(S.path)
      if not removed then return false, removeErr end
      project.layeredTransform = nil
      if S.manifestDraft and S.browseModId == project.id then
        S.manifestDraft.assets_transforms = nil
      end
    end
    return true, "no layered maps"
  end
  if not (love and love.image and love.image.newImageData) then
    return false, "layered maps require LÖVE image support"
  end

  local context = {
    S = S,
    project = project,
    images = {},
    bases = {},
    pixelIds = {},
    pixels = {},
    outputs = {},
  }
  for id, map in pairs(project.maps or {}) do
    if type(map) == "table" and not project.layeredMaps[id] then
      importMapWarps(S, map)
    end
  end
  local records, activeCells = warpPlan(project)
  local compiled = 0
  for _, mapId in ipairs(sortedKeys(project.layeredMaps)) do
    LayeredMap.internSourceCells(project.layeredMaps[mapId])
    local ok, err = pcall(compileMap, context, mapId,
      project.layeredMaps[mapId], records[mapId], activeCells[mapId])
    if not ok then return false, err end
    compiled = compiled + 1
    if S.data then
      S.data.maps = S.data.maps or {}
      S.data.tilesets = S.data.tilesets or {}
      S.data.maps[mapId] = project.maps[mapId]
      local tilesetId = project.maps[mapId].tileset
      if project.tilesets[tilesetId] then
        S.data.tilesets[tilesetId] = project.tilesets[tilesetId]
      end
      if S.data.gen2Maps and S.data.gen2Maps ~= S.data.maps then
        S.data.gen2Maps[mapId] = project.maps[mapId]
      end
      if S.data.gen2Tilesets and S.data.gen2Tilesets ~= S.data.tilesets
          and project.tilesets[tilesetId] then
        S.data.gen2Tilesets[tilesetId] = project.tilesets[tilesetId]
      end
    end
  end
  if next(context.outputs) then
    local transformed, transformErr = emitTransform(context)
    if not transformed then return false, transformErr end
    project.layeredTransform = "mapbuilder_transforms.lua"
    if S.manifestDraft and S.browseModId == project.id then
      S.manifestDraft.assets_transforms = project.layeredTransform
    end
    writeEditorDerivedImages(context)
  elseif project.layeredTransform then
    local removed, removeErr = ModIO.removeMapBuilderTransform(S.path)
    if not removed then return false, removeErr end
    project.layeredTransform = nil
    if S.manifestDraft and S.browseModId == project.id then
      S.manifestDraft.assets_transforms = nil
    end
  end
  if context.images then
    for _, img in pairs(context.images) do
      if img and img.release then pcall(img.release, img) end
    end
  end
  context.pixels, context.pixelIds, context.images, context.bases,
    context.outputs, context.microIds, context._packBytes = nil, nil, nil, nil, nil, nil, nil
  pcall(function() require("src.world.MapLoader").invalidateAll() end)
  pcall(function() require("src.render.TileRenderer").invalidate() end)
  pcall(function()
    local Maps = require("Maps")
    if Maps.invalidateGoldPreview then Maps.invalidateGoldPreview(S) end
  end)
  Preview.invalidate()
  collectgarbage("collect")
  return true, string.format("compiled %d layered map(s)", compiled)
end

-- Rebuild missing save/mod-derived atlases so MapLoader can preview a map
-- that was compiled on a previous save (the game transform has not run).
function LayeredMap.ensureEditorAtlas(S, mapId)
  if not (S and S.project and S.path and mapId) then return end
  if not (love and love.filesystem and love.filesystem.getInfo) then return end
  local map = S.project.maps and S.project.maps[mapId]
  local ts = map and S.project.tilesets and S.project.tilesets[map.tileset]
  if not (ts and ts._layeredGenerated and type(ts.image) == "string") then
    return
  end
  local image = ts.image
  if love.filesystem.getInfo(image) then return end
  if image:sub(1, 11) == "mapbuilder/" then
    local derived = "save/mod-derived/" .. tostring(S.project.id) .. "/" .. image
    if love.filesystem.getInfo(derived) then
      ts.image = derived
      return
    end
  end
  if S._editorAtlasBaking then return end
  S._editorAtlasBake = S._editorAtlasBake or {}
  if S._editorAtlasBake[image] then return end
  S._editorAtlasBake[image] = true
  S._editorAtlasBaking = true
  pcall(LayeredMap.compileProject, S)
  S._editorAtlasBaking = nil
end

LayeredMap.deepCopy = deepCopy
LayeredMap.cleanId = cleanId

function LayeredMap.usesCellPreview(source)
  local layer = source and source.layers and source.layers[1]
  return type(layer) == "table" and type(layer.cells) == "table"
end

-- Shared 16x16 cell draw (Map Builder, World View, map preview). Runtime
-- tilesets expand each cell from its 32x32 metatile and apply Gold GBC
-- palettes the same way the paint canvas does.
local previewQuads = setmetatable({}, { __mode = "k" })

local function tileQuad(image, x, y, w, h)
  local bucket = previewQuads[image]
  if not bucket then
    bucket = {}
    previewQuads[image] = bucket
  end
  local key = table.concat({ x, y, w, h }, ":")
  if not bucket[key] then
    local iw, ih = image:getDimensions()
    bucket[key] = love.graphics.newQuad(x, y, w, h, iw, ih)
  end
  return bucket[key]
end

local function animationTile(source, tile)
  local frames = source and source.animations and source.animations[tile]
  if not frames or #frames < 2 then return tile end
  local total = 0
  for _, frame in ipairs(frames) do
    total = total + math.max(16, tonumber(frame.duration) or 200)
  end
  local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local cursor = (now * 1000) % total
  for _, frame in ipairs(frames) do
    cursor = cursor - math.max(16, tonumber(frame.duration) or 200)
    if cursor < 0 then return frame.tile end
  end
  return frames[#frames].tile
end

function LayeredMap.drawSourceTile(S, source, tile, x, y, size, alpha, mapId)
  if not source or not source.image then return false end
  local image = Preview.image(S, source.image)
  if not image then return false end
  tile = animationTile(source, math.max(0, math.floor(tonumber(tile) or 0)))
  local shaded = false
  local gbc, bgSet, tilePals
  if source.colorMode ~= "true_color" and source.runtimeTileset then
    local Generation = require("Generation")
    if Generation.isGen2(S) then
      mapId = mapId or S.builderMapId or S.mapId
      local map = (S.project and S.project.maps and S.project.maps[mapId])
        or Generation.dataMaps(S)[mapId]
      if type(map) == "table" then
        bgSet = select(1, Preview.gen2MapBgSet(S, map))
      end
    end
    if bgSet then
      local okG, GbcPalette = pcall(require, "src.render.GbcPalette")
      if okG and GbcPalette and GbcPalette.with then
        gbc = GbcPalette
        tilePals = source.tileset and source.tileset.tilePalettes
        if not tilePals then
          local vanilla = require("Generation").dataTilesets(S)[source.runtimeTileset]
          tilePals = vanilla and vanilla.tilePalettes
        end
      end
    end
  end
  if source.colorMode ~= "true_color" and not gbc then
    mapId = mapId or S.builderMapId or S.mapId
    local map = S.project and S.project.maps and S.project.maps[mapId]
      or require("Generation").dataMaps(S)[mapId]
    shaded = Preview.pushPaletteShader(S, Preview.mapPaletteName(S, map))
  end
  love.graphics.setColor(1, 1, 1, alpha or 1)
  if source.runtimeTileset then
    local blockId = math.floor(tile / 4)
    local quadrant = tile % 4
    local block = source.tileset.blocks and source.tileset.blocks[blockId + 1]
    if not block then
      Preview.popPaletteShader(shaded)
      love.graphics.setColor(1, 1, 1, 1)
      return false
    end
    local qx, qy = quadrant % 2, math.floor(quadrant / 2)
    local scale = size / 16
    local perRow = source.tileset.tilesPerRow
      or math.max(1, math.floor(image:getWidth() / 8))
    for microY = 0, 1 do
      for microX = 0, 1 do
        local tileId = block[(qy * 2 + microY) * 4 + qx * 2 + microX + 1]
        if tileId then
          local sx = (tileId % perRow) * 8
          local sy = math.floor(tileId / perRow) * 8
          local dx = x + microX * 8 * scale
          local dy = y + microY * 8 * scale
          if gbc then
            local slot = (tilePals and tilePals[tileId + 1]) or 1
            gbc.with(bgSet[slot], function()
              love.graphics.draw(image, tileQuad(image, sx, sy, 8, 8),
                dx, dy, 0, scale, scale)
            end)
          else
            love.graphics.draw(image, tileQuad(image, sx, sy, 8, 8),
              dx, dy, 0, scale, scale)
          end
        end
      end
    end
  else
    local columns = source.columns or math.max(1, math.floor(image:getWidth() / 16))
    local sx = (tile % columns) * 16
    local sy = math.floor(tile / columns) * 16
    local scale = size / 16
    love.graphics.draw(image, tileQuad(image, sx, sy, 16, 16),
      x, y, 0, scale, scale)
  end
  Preview.popPaletteShader(shaded)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- World View / engine preview: same 16x16 cells as Map Builder, including
-- Gold runtime tilesets. MapPreview.bake uses compiled 32x32 blocks and a
-- different palette path, so World View used to disagree with the canvas.
function LayeredMap.previewRenderer(S, source, mapId)
  if not source then return nil end
  LayeredMap.internSourceCells(source)
  local CELL = LayeredMap.CELL_SIZE
  mapId = mapId or source.id
  local function draw(_, camX, camY, vw, vh)
    camX, camY = camX or 0, camY or 0
    vw = vw or source.cellWidth * CELL
    vh = vh or source.cellHeight * CELL
    local x0 = math.max(0, math.floor(camX / CELL) - 1)
    local y0 = math.max(0, math.floor(camY / CELL) - 1)
    local x1 = math.min(source.cellWidth - 1,
      math.floor((camX + vw) / CELL) + 1)
    local y1 = math.min(source.cellHeight - 1,
      math.floor((camY + vh) / CELL) + 1)
    love.graphics.push()
    love.graphics.translate(-math.floor(camX), -math.floor(camY))
    for cy = y0, y1 do
      for cx = x0, x1 do
        for _, layer in ipairs(source.layers or {}) do
          if layer.visible ~= false then
            local ref = layer.cells[cy * source.cellWidth + cx + 1]
            if ref then
              local desc = LayeredMap.sourceDescriptor(S, ref.source)
              if desc then
                LayeredMap.drawSourceTile(S, desc, ref.tile,
                  cx * CELL, cy * CELL, CELL, layer.opacity or 1, mapId)
              end
            end
          end
        end
      end
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
  end
  return { draw = draw, drawMapOnly = draw, cellPreview = true }
end

return LayeredMap
