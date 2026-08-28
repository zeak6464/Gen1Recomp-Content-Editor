-- Export / import Tiled TMX for content-editor maps.
-- Native export/import uses the TMX tileset PNG as that map's own tileset.
-- Pokemonium / foreign TMX is converted into engine blocks + a new tileset.

local ModIO = require("ModIO")
local Generation = require("Generation")
local Preview = require("Preview")

local TmxIO = {}

local SEP = package.config:sub(1, 1)
local function join(...)
  local parts = { ... }
  for i = 1, #parts do
    parts[i] = tostring(parts[i] or ""):gsub("[/\\]+$", "")
  end
  return table.concat(parts, SEP)
end

local function xml(s)
  s = tostring(s or "")
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function resolveMap(S, mapId)
  if not mapId then return nil end
  return (S.project and S.project.maps and S.project.maps[mapId])
    or Generation.dataMaps(S)[mapId]
end

local function resolveTileset(S, tilesetId)
  if not tilesetId then return nil end
  return (S.project and S.project.tilesets and S.project.tilesets[tilesetId])
    or Generation.dataTilesets(S)[tilesetId]
end

local function dirname(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or "."
end

local function basename(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function resolvePath(base, rel)
  rel = tostring(rel or ""):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
  if rel == "" then return base end
  if rel:match("^[A-Za-z]:/") or rel:sub(1, 1) == "/" then
    return rel:gsub("/", SEP)
  end
  return join(base, (rel:gsub("/", SEP)))
end

local function safeTilesetId(name, fallback)
  local id = tostring(name or ""):upper():gsub("[^A-Z0-9_]", "_")
  id = id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if id == "" then id = fallback or "TMX_TILES" end
  if id:match("^%d") then id = "TS_" .. id end
  return id
end

local function ownTilesetId(S, mapId, tmName)
  if type(tmName) == "string" and tmName ~= ""
      and not Generation.dataTilesets(S)[tmName]
      and not (S.project.tilesets and S.project.tilesets[tmName]
        and S.project.tilesets[tmName]._layeredGenerated) then
    return safeTilesetId(tmName, mapId .. "_TILES")
  end
  return safeTilesetId(mapId .. "_TILES", "TMX_TILES")
end

local function layeredSource(S, mapId)
  return S.project and S.project.layeredMaps and S.project.layeredMaps[mapId]
end

local function cellsFromLayered(source)
  local w = source.cellWidth or 0
  local h = source.cellHeight or 0
  if w < 1 or h < 1 then return nil end
  local layer = source.layers and source.layers[1]
  local cells = layer and layer.cells
  if type(cells) ~= "table" then return nil end
  local out = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local ref = cells[y * w + x + 1]
      out[#out + 1] = ref and tonumber(ref.tile) or 0
    end
  end
  return out, w, h
end

-- Layered cell refs store runtime tiles as block*4+quadrant. Those GIDs
-- belong to source.baseTileset, not the compiled *_LAYERED atlas.
local function layeredRuntimeTileset(source)
  if not source then return nil end
  local LayeredMap = require("LayeredMap")
  local layer = source.layers and source.layers[1]
  local cells = layer and layer.cells
  if type(cells) ~= "table" then return source.baseTileset end
  local tilesetId
  for _, ref in pairs(cells) do
    if type(ref) == "table" and ref.source then
      if not LayeredMap.isRuntimeSource(ref.source) then return nil end
      tilesetId = tilesetId or LayeredMap.runtimeTilesetId(ref.source)
    end
  end
  return tilesetId or source.baseTileset
end

local function mapPayload(S, mapId)
  local map = resolveMap(S, mapId)
  if not map then return nil, "unknown map" end
  local source = layeredSource(S, mapId)
  local runtimeTileset = layeredRuntimeTileset(source)
  if runtimeTileset then
    local cells, width, height = cellsFromLayered(source)
    if cells then
      return {
        id = map.id or mapId,
        map = map,
        blocks = cells,
        width = width,
        height = height,
        tileset = runtimeTileset,
        tileSize = 16,
        source = source,
      }
    end
  end
  if type(map.blocks) ~= "table" or type(map.width) ~= "number"
      or type(map.height) ~= "number" then
    return nil, "map has no block grid"
  end
  return {
    id = map.id or mapId,
    map = map,
    blocks = map.blocks,
    width = map.width,
    height = map.height,
    tileset = map.tileset,
    tileSize = 32,
    source = source,
  }
end

local function imageDataFromBytes(bytes, name)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  if not (love and love.image and love.image.newImageData) then return nil end
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, name or "tiles.png")
  if not (okFd and fd) then return nil end
  local ok, data = pcall(love.image.newImageData, fd)
  return ok and data or nil
end

local function loadImageData(S, path)
  if type(path) ~= "string" or path == "" then return nil end
  if love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(path) then
    local data = imageDataFromBytes(love.filesystem.read(path),
      path:match("[^/\\]+$"))
    if data then return data end
  end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, data = pcall(Assets.imageData, path)
    if ok and data then return data end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local data = imageDataFromBytes(CacheFs.readActive(path),
      path:match("[^/\\]+$"))
    if data then return data end
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved or not (love and love.image and love.image.newImageData) then
    return nil
  end
  if kind == "disk" then
    return imageDataFromBytes(ModIO.readText(resolved), "tiles.png")
  end
  local ok, data = pcall(love.image.newImageData, resolved)
  return ok and data or nil
end

local function writePng(imageData, path)
  if not (imageData and imageData.encode) then return false, "no encode" end
  local ok, fileData = pcall(imageData.encode, imageData, "png")
  if not (ok and fileData) then return false, fileData end
  local bytes = fileData.getString and fileData:getString() or tostring(fileData)
  return ModIO.writeText(path, bytes)
end

local function paletteForTile(S, map, tileset, tileId)
  if Generation.isGen2(S) then
    local bakeMap = Preview.gen2BakeMap(map, tileset and tileset.id)
    local bgSet = select(1, Preview.gen2MapBgSet(S, bakeMap))
    if not bgSet then return nil end
    local pals = tileset and tileset.tilePalettes
    if not pals then
      local vanilla = Generation.dataTilesets(S)[tileset and tileset.id]
      pals = vanilla and vanilla.tilePalettes
    end
    local slot = (pals and pals[(tileId or 0) + 1]) or 1
    return bgSet[slot]
  end
  return Preview.paletteColors(S, Preview.mapPaletteName(S, map))
end

local function applyShade(r, g, b, a, colors)
  if not colors or a <= 0 then return r, g, b, a end
  local shade = math.floor((1 - r) * 3 + 0.5)
  if shade < 0 then shade = 0 elseif shade > 3 then shade = 3 end
  local c = colors[shade + 1]
  if not c then return r, g, b, a end
  return (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, a
end

local function blit8(atlas, sheet, dx, dy, sx, sy, colors)
  local sw, sh = sheet:getWidth(), sheet:getHeight()
  if sx < 0 or sy < 0 or sx + 8 > sw or sy + 8 > sh then return end
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = sheet:getPixel(sx + x, sy + y)
      r, g, b, a = applyShade(r, g, b, a, colors)
      atlas:setPixel(dx + x, dy + y, r, g, b, a)
    end
  end
end

local function blitBlock(atlas, sheet, tileset, block, ax, ay, palFn)
  if type(block) ~= "table" then return end
  local perRow = tileset.tilesPerRow or 16
  for i = 0, 15 do
    local tid = block[i + 1] or 0
    local sx = (tid % perRow) * 8
    local sy = math.floor(tid / perRow) * 8
    blit8(atlas, sheet, ax + (i % 4) * 8, ay + math.floor(i / 4) * 8, sx, sy,
      palFn and palFn(tid))
  end
end

local function blitCell(atlas, sheet, tileset, cellTile, ax, ay, palFn)
  local blockId = math.floor((cellTile or 0) / 4)
  local quadrant = (cellTile or 0) % 4
  local block = tileset.blocks and tileset.blocks[blockId + 1]
  if type(block) ~= "table" then return end
  local qx, qy = quadrant % 2, math.floor(quadrant / 2)
  local perRow = tileset.tilesPerRow or 16
  for microY = 0, 1 do
    for microX = 0, 1 do
      local tid = block[(qy * 2 + microY) * 4 + qx * 2 + microX + 1] or 0
      blit8(atlas, sheet, ax + microX * 8, ay + microY * 8,
        (tid % perRow) * 8, math.floor(tid / perRow) * 8,
        palFn and palFn(tid))
    end
  end
end

local function buildBlockAtlas(S, map, tileset)
  local sheet = loadImageData(S, tileset and tileset.image)
  local blocks = tileset and tileset.blocks
  if not (sheet and type(blocks) == "table" and #blocks > 0) then
    return nil
  end
  local n = #blocks
  local cols = 16
  local rows = math.max(1, math.ceil(n / cols))
  local atlas = love.image.newImageData(cols * 32, rows * 32)
  local function palFn(tid) return paletteForTile(S, map, tileset, tid) end
  for bi = 0, n - 1 do
    blitBlock(atlas, sheet, tileset, blocks[bi + 1],
      (bi % cols) * 32, math.floor(bi / cols) * 32, palFn)
  end
  return atlas, n, cols, cols * 32, rows * 32
end

-- One Tiled tile = one editor 16x16 cell (block*4+quadrant), matching Map Builder.
local function buildCellAtlas(S, map, tileset)
  local sheet = loadImageData(S, tileset and tileset.image)
  local blocks = tileset and tileset.blocks
  if not (sheet and type(blocks) == "table" and #blocks > 0) then
    return nil
  end
  local n = #blocks * 4
  local cols = 16
  local rows = math.max(1, math.ceil(n / cols))
  local atlas = love.image.newImageData(cols * 16, rows * 16)
  local function palFn(tid) return paletteForTile(S, map, tileset, tid) end
  for tile = 0, n - 1 do
    blitCell(atlas, sheet, tileset, tile,
      (tile % cols) * 16, math.floor(tile / cols) * 16, palFn)
  end
  return atlas, n, cols, cols * 16, rows * 16
end

local function csvBlocks(blocks, width, height)
  local lines = {}
  for y = 0, height - 1 do
    local row = {}
    for x = 0, width - 1 do
      local bid = tonumber(blocks[y * width + x + 1]) or 0
      row[#row + 1] = tostring(bid + 1)
    end
    local line = table.concat(row, ",")
    if y < height - 1 then line = line .. "," end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

local function objectXml(kind, obj, id)
  local cx = tonumber(obj.x) or 0
  local cy = tonumber(obj.y) or 0
  local props = {}
  local function prop(name, value, typ)
    if value == nil or value == "" then return end
    if typ then
      props[#props + 1] = string.format(
        '   <property name="%s" type="%s" value="%s"/>',
        xml(name), typ, xml(value))
    else
      props[#props + 1] = string.format(
        '   <property name="%s" value="%s"/>', xml(name), xml(value))
    end
  end
  if kind == "warp" then
    prop("destMap", obj.destMap or obj.map)
    prop("destWarp", obj.destWarp or obj.dest or 0, "int")
    prop("destGroup", obj.destGroup, "int")
    prop("destMapNum", obj.destMapNum, "int")
  elseif kind == "sign" then
    prop("text", obj.text or obj.script or "")
  else
    prop("sprite", obj.sprite)
    prop("movement", tonumber(obj.movement) or obj.movement)
    prop("range", obj.range, "int")
    prop("text", obj.text)
    prop("facing", obj.facing or obj.range)
    prop("name", obj.name)
    prop("index", obj.index, "int")
    prop("type", obj.type, "int")
    prop("scriptKey", obj.scriptKey)
    if type(obj.hours) == "table" then
      prop("hours", tostring(obj.hours[1] or -1) .. "," .. tostring(obj.hours[2] or -1))
    end
    if type(obj.radius) == "table" then
      prop("radiusX", obj.radius.x, "int")
      prop("radiusY", obj.radius.y, "int")
    end
  end
  return string.format(
    '  <object id="%d" name="%s" type="%s" x="%d" y="%d" width="16" height="16">\n'
      .. "   <properties>\n%s\n   </properties>\n  </object>",
    id, xml(kind), xml(kind), cx * 16, cy * 16, table.concat(props, "\n"))
end

function TmxIO.defaultFolder(S)
  if not (S and S.path) then return nil end
  return join(S.path, "exports", "tmx")
end

function TmxIO.exportMap(S, mapId, folder)
  folder = folder or TmxIO.defaultFolder(S)
  if not folder then return false, "no mod open" end
  local payload, err = mapPayload(S, mapId)
  if not payload then return false, err end
  local made, makeErr = ModIO.ensureDirectory(folder)
  if not made then return false, makeErr end

  local tileset = resolveTileset(S, payload.tileset) or {}
  tileset.id = tileset.id or payload.tileset
  local tsName = payload.tileset or "TILESET"
  local tileSize = payload.tileSize or 32
  local pngName = tsName:lower():gsub("[^a-z0-9_-]", "_")
    .. (tileSize == 16 and "_cells.png" or "_blocks.png")
  local atlas, tilecount, columns, imgW, imgH
  if tileSize == 16 then
    atlas, tilecount, columns, imgW, imgH = buildCellAtlas(S, payload.map, tileset)
  else
    atlas, tilecount, columns, imgW, imgH = buildBlockAtlas(S, payload.map, tileset)
  end
  if not atlas then
    return false, "could not build tileset PNG for " .. tostring(tsName)
      .. " (missing " .. tostring(tileset.image or "tileset image") .. ")"
  end
  local okPng, pngErr = writePng(atlas, join(folder, pngName))
  if not okPng then return false, pngErr end

  local map = payload.map
  local objects, nextId = {}, 1
  local function addGroup(name, list, kind)
    if type(list) ~= "table" or #list == 0 then return end
    local body = {}
    for _, obj in ipairs(list) do
      body[#body + 1] = objectXml(kind, obj, nextId)
      nextId = nextId + 1
    end
    objects[#objects + 1] = string.format(
      ' <objectgroup id="%d" name="%s">\n%s\n </objectgroup>',
      #objects + 2, name, table.concat(body, "\n"))
  end
  addGroup("warps", map.warps, "warp")
  addGroup("signs", map.signs or map.bgEvents, "sign")
  addGroup("objects", map.objects, "object")

  local props = {
    string.format('  <property name="editor" value="gen1recomp"/>'),
    string.format('  <property name="mapId" value="%s"/>', xml(payload.id)),
    string.format('  <property name="tileset" value="%s"/>', xml(tsName)),
    string.format('  <property name="tileSize" type="int" value="%d"/>', tileSize),
  }
  if type(map.palette) == "string" and map.palette ~= "" then
    props[#props + 1] = string.format(
      '  <property name="palette" value="%s"/>', xml(map.palette))
  end
  if type(map.environment) == "string" and map.environment ~= "" then
    props[#props + 1] = string.format(
      '  <property name="environment" value="%s"/>', xml(map.environment))
  end
  if map.generation or Generation.isGen2(S) then
    props[#props + 1] = string.format(
      '  <property name="generation" type="int" value="%s"/>',
      tostring(map.generation or 2))
  end

  local tmx = {
    '<?xml version="1.0" encoding="UTF-8"?>',
    string.format(
      '<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" '
        .. 'renderorder="right-down" width="%d" height="%d" tilewidth="%d" '
        .. 'tileheight="%d" infinite="0" nextlayerid="%d" nextobjectid="%d">',
      payload.width, payload.height, tileSize, tileSize, #objects + 2, nextId),
    " <properties>",
    table.concat(props, "\n"),
    " </properties>",
    string.format(
      ' <tileset firstgid="1" name="%s" tilewidth="%d" tileheight="%d" '
        .. 'tilecount="%d" columns="%d">',
      xml(tsName), tileSize, tileSize, tilecount, columns),
    string.format(
      '  <image source="%s" width="%d" height="%d"/>',
      xml(pngName), imgW, imgH),
    " </tileset>",
    string.format(
      ' <layer id="1" name="blocks" width="%d" height="%d">',
      payload.width, payload.height),
    '  <data encoding="csv">',
    csvBlocks(payload.blocks, payload.width, payload.height),
    "  </data>",
    " </layer>",
  }
  for _, group in ipairs(objects) do
    tmx[#tmx + 1] = group
  end
  tmx[#tmx + 1] = "</map>"

  local dest = join(folder, payload.id .. ".tmx")
  local ok, writeErr = ModIO.writeText(dest, table.concat(tmx, "\n") .. "\n")
  if not ok then return false, writeErr end
  return true, dest
end

local function attr(tag, name)
  local pat = name .. '%s*=%s*"([^"]*)"'
  return tag:match(pat)
end

local function parseCsv(text, width, height)
  local vals = {}
  for num in tostring(text or ""):gmatch("%d+") do
    vals[#vals + 1] = tonumber(num) or 0
  end
  local need = width * height
  while #vals < need do vals[#vals + 1] = 0 end
  return vals
end

local function parseObjects(xmlText, kind)
  local out = {}
  for obj in xmlText:gmatch("<object%s.-</object>") do
    local otype = attr(obj, "type") or attr(obj, "class") or ""
    local name = attr(obj, "name") or ""
    local hit = kind == "warp" and (otype:find("warp") or name:find("warp"))
      or kind == "sign" and (otype:find("sign") or name:find("sign"))
      or kind == "object" and (otype:find("object") or otype:find("npc")
        or name ~= "")
    if kind == "object" and (otype:find("warp") or otype:find("sign")) then
      hit = false
    end
    if hit then
      local x = tonumber(attr(obj, "x")) or 0
      local y = tonumber(attr(obj, "y")) or 0
      local rec = {
        x = math.floor(x / 16),
        y = math.floor(y / 16),
      }
      for pname, pval in obj:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
        if pname == "destMap" or pname == "map" then rec.destMap = pval
        elseif pname == "destWarp" or pname == "dest" then
          rec.destWarp = tonumber(pval) or 0
        elseif pname == "destGroup" then rec.destGroup = tonumber(pval)
        elseif pname == "destMapNum" then rec.destMapNum = tonumber(pval)
        elseif pname == "text" then rec.text = pval
        elseif pname == "sprite" then rec.sprite = pval
        elseif pname == "movement" then rec.movement = tonumber(pval) or pval
        elseif pname == "range" then rec.range = tonumber(pval) or 0
        elseif pname == "facing" then rec.facing = pval
        elseif pname == "name" then rec.name = pval
        elseif pname == "index" then rec.index = tonumber(pval)
        elseif pname == "type" then rec.type = tonumber(pval)
        elseif pname == "scriptKey" then rec.scriptKey = pval
        elseif pname == "hours" then
          local a, b = pval:match("([^,]+),([^,]+)")
          rec.hours = { tonumber(a) or -1, tonumber(b) or -1 }
        elseif pname == "radiusX" then
          rec.radius = rec.radius or {}
          rec.radius.x = tonumber(pval) or 0
        elseif pname == "radiusY" then
          rec.radius = rec.radius or {}
          rec.radius.y = tonumber(pval) or 0
        end
      end
      out[#out + 1] = rec
    end
  end
  return out
end

function TmxIO.parse(path)
  local body, err = ModIO.readText(path)
  if not body then return nil, err end
  local mapTag = body:match("<map%s.->")
  if not mapTag then return nil, "not a TMX map" end
  local width = tonumber(attr(mapTag, "width"))
  local height = tonumber(attr(mapTag, "height"))
  local tilewidth = tonumber(attr(mapTag, "tilewidth")) or 32
  local tileheight = tonumber(attr(mapTag, "tileheight")) or 32
  if not (width and height) then return nil, "TMX missing width/height" end

  local props = {}
  for name, value in body:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
    props[name] = value
  end

  local firstgid = tonumber(body:match('firstgid="(%d+)"')) or 1
  local tilesetName = body:match('<tileset[^>]-name="([^"]+)"')
  local imgSrc = body:match('<image%s[^>]*source="([^"]+)"')
  local imagePath = imgSrc and resolvePath(dirname(path), imgSrc) or nil
  local data = body:match('<layer[^>]-name="blocks".-<data[^>]*>(.-)</data>')
    or body:match("<data%s+encoding=\"csv\"[^>]*>(.-)</data>")
    or body:match("<data[^>]*>(.-)</data>")
  if not data then return nil, "TMX has no tile layer" end
  local gids = parseCsv(data, width, height)
  local blocks = {}
  for i = 1, width * height do
    local gid = tonumber(gids[i]) or 0
    if gid >= 0x20000000 then gid = gid % 0x20000000 end
    if gid == 0 then
      blocks[i] = 0
    else
      blocks[i] = math.max(0, gid - firstgid)
    end
  end
  return {
    width = width,
    height = height,
    tilewidth = tilewidth,
    tileheight = tileheight,
    props = props,
    tileset = tilesetName,
    imagePath = imagePath,
    blocks = blocks,
    warps = parseObjects(body, "warp"),
    signs = parseObjects(body, "sign"),
    objects = parseObjects(body, "object"),
    ours = props.editor == "gen1recomp",
  }
end

local function ensureLayered(S, mapId, map, width, height, tilesetId)
  local LayeredMap = require("LayeredMap")
  LayeredMap.ensureProject(S.project)
  if layeredSource(S, mapId) then return layeredSource(S, mapId) end
  if tilesetId and resolveTileset(S, tilesetId) then
    pcall(LayeredMap.convertMap, S, mapId)
    if layeredSource(S, mapId) then return layeredSource(S, mapId) end
  end
  local cw = width + (width % 2)
  local ch = height + (height % 2)
  local source = {
    id = mapId,
    cellWidth = cw,
    cellHeight = ch,
    baseTileset = tilesetId,
    layers = {
      {
        id = "ground", name = "Ground", visible = true, export = true,
        opacity = 1, cells = {},
      },
    },
    collision = {},
  }
  S.project.layeredMaps[mapId] = source
  map._layeredSource = mapId
  map.width = math.max(1, math.floor(cw / 2))
  map.height = math.max(1, math.floor(ch / 2))
  return source
end

local function loadDiskPng(path)
  local bytes = ModIO.readText(path)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  return imageDataFromBytes(bytes, basename(path))
end

local function copyPngToMod(S, absPath, destRel)
  local dest = join(S.path, (destRel:gsub("/", SEP)))
  local ok, err = ModIO.copyFile(absPath, dest)
  if not ok then return nil, err end
  return destRel
end

local function registerBlockTileset(S, id, rel, img, tilecount, columns)
  columns = columns or math.max(1, math.floor(img:getWidth() / 32))
  local sheetCols = math.max(1, math.floor(img:getWidth() / 8))
  local n = tilecount or (math.floor(img:getWidth() / 32)
    * math.floor(img:getHeight() / 32))
  local blocks, walkable = {}, {}
  for bi = 0, n - 1 do
    local bx = (bi % columns) * 4
    local by = math.floor(bi / columns) * 4
    local block = {}
    for row = 0, 3 do
      for col = 0, 3 do
        local tid = (by + row) * sheetCols + (bx + col)
        block[row * 4 + col + 1] = tid
        walkable[tid] = true
      end
    end
    blocks[#blocks + 1] = block
  end
  local walkList = {}
  for tid in pairs(walkable) do walkList[#walkList + 1] = tid end
  table.sort(walkList)
  local rec = {
    id = id,
    image = rel,
    tilesPerRow = sheetCols,
    imageWidth = img:getWidth(),
    imageHeight = img:getHeight(),
    blocks = blocks,
    walkable = walkList,
    waterTiles = {},
    warpTiles = {},
    doorTiles = {},
    counterTiles = {},
    animation = "TILEANIM_NONE",
    trueColor = true,
    _isNew = true,
  }
  S.project.tilesets = S.project.tilesets or {}
  S.project.tilesets[id] = rec
  if S.data and S.data.tilesets then S.data.tilesets[id] = rec end
  if S.data and S.data.gen2Tilesets and S.data.gen2Tilesets ~= S.data.tilesets then
    S.data.gen2Tilesets[id] = rec
  end
  return rec
end

local function applyLayeredCells(S, mapId, map, cellTiles, width, height,
    paintSource, tilesetId)
  local LayeredMap = require("LayeredMap")
  local source = ensureLayered(S, mapId, map, width, height, tilesetId)
  if not source then return end
  paintSource = paintSource or LayeredMap.runtimeSourceId(tilesetId)
  if LayeredMap.isRuntimeSource(paintSource) then
    source.baseTileset = tilesetId
  end
  if tilesetId then map.tileset = tilesetId end
  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local tile = cellTiles[index] or 0
      cells[index] = {
        source = paintSource,
        tile = tile,
      }
      collision[index] = source.collision and source.collision[index] or "walk"
    end
  end
  if source.layers and source.layers[1] then
    source.layers[1].cells = cells
  end
  source.collision = collision
  source.cellWidth, source.cellHeight = width, height
  map.width = math.max(1, math.floor(width / 2))
  map.height = math.max(1, math.floor(height / 2))
  local blocks = {}
  for by = 0, map.height - 1 do
    for bx = 0, map.width - 1 do
      local tile = cellTiles[(by * 2) * width + (bx * 2) + 1] or 0
      blocks[#blocks + 1] = math.floor(tile / 4)
    end
  end
  map.blocks = blocks
end

local function applyLayeredBlocks(S, mapId, map, tilesetId)
  local LayeredMap = require("LayeredMap")
  local width, height = map.width * 2, map.height * 2
  local source = ensureLayered(S, mapId, map, width, height, tilesetId)
  if not source then return end
  tilesetId = tilesetId or map.tileset or source.baseTileset
  source.baseTileset = tilesetId
  map.tileset = tilesetId
  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local block = map.blocks[math.floor(y / 2) * map.width + math.floor(x / 2) + 1] or 0
      cells[index] = {
        source = LayeredMap.runtimeSourceId(tilesetId),
        tile = block * 4 + (y % 2) * 2 + (x % 2),
      }
      collision[index] = source.collision and source.collision[index] or "walk"
    end
  end
  if source.layers and source.layers[1] then
    source.layers[1].cells = cells
  end
  source.collision = collision
  source.cellWidth, source.cellHeight = width, height
end

function TmxIO.canImportNative(parsed)
  return parsed and parsed.ours == true
end

function TmxIO.importFile(S, path, App)
  if not (S and S.project) then return false, "no project" end
  local Convert = require("TmxPokemonium")
  local files = Convert.collectTmx(path)
  if #files == 0 then return false, "no .tmx files" end
  if #files > 1 or not tostring(path):lower():match("%.tmx$") then
    return Convert.importPath(S, path, App)
  end
  local body, readErr = ModIO.readText(files[1])
  if not body then return false, readErr end
  local ours = body:find('name="editor"%s+value="gen1recomp"')
    or body:find('value="gen1recomp"%s+name="editor"')
  if not ours then
    return Convert.importPath(S, files[1], App)
  end
  path = files[1]
  local parsed, err = TmxIO.parse(path)
  if not parsed then return false, err end

  local mapId = parsed.props.mapId
  if type(mapId) ~= "string" or mapId == "" then
    mapId = (path:match("([^/\\]+)%.[Tt][Mm][Xx]$") or "IMPORTED_MAP")
      :gsub("[^%w_]", "_"):upper()
  end
  local existing = resolveMap(S, mapId)
  local map
  if existing then
    map = existing
    if S.project.maps[mapId] ~= map then
      local copy = {}
      for k, v in pairs(existing) do copy[k] = v end
      S.project.maps[mapId] = copy
      map = copy
    end
  else
    map = {
      id = mapId,
      tileset = parsed.tileset or (Generation.isGen2(S) and "TILESET_JOHTO" or "OVERWORLD"),
      _isNew = true,
    }
    S.project.maps[mapId] = map
  end
  map.id = mapId
  local LayeredMap = require("LayeredMap")
  local fallbackTs = Generation.isGen2(S) and "TILESET_JOHTO" or "OVERWORLD"
  local paintSource, tilesetId
  local isCells = parsed.tilewidth == 16 or tonumber(parsed.props.tileSize) == 16
  if parsed.imagePath then
    local img = loadDiskPng(parsed.imagePath)
    if img then
      local tsId = ownTilesetId(S, mapId, parsed.tileset)
      if isCells then
        local pngName = basename(parsed.imagePath)
        if not tostring(pngName):lower():match("%.png$") then
          pngName = tsId:lower() .. "_cells.png"
        end
        local rel = "assets/mapbuilder/sources/" .. pngName
        ModIO.ensureDirectory(join(S.path, "assets", "mapbuilder", "sources"))
        local copied = copyPngToMod(S, parsed.imagePath, rel)
        if copied then
          pcall(function() Preview.invalidatePath(copied) end)
          local src, srcErr = LayeredMap.installTileSource(
            S.project, tsId, copied, img:getWidth(), img:getHeight())
          if src then
            src.colorMode = "true_color"
            paintSource = src.id
            tilesetId = map.tileset
            if not tilesetId or Generation.dataTilesets(S)[tilesetId]
                or (S.project.tilesets and S.project.tilesets[tilesetId]
                  and S.project.tilesets[tilesetId]._layeredGenerated) then
              tilesetId = fallbackTs
            end
          else
            return false, srcErr or "could not install TMX tileset PNG"
          end
        end
      else
        local rel = "assets/tilesets/" .. tsId:lower() .. ".png"
        ModIO.ensureDirectory(join(S.path, "assets", "tilesets"))
        local copied = copyPngToMod(S, parsed.imagePath, rel)
        if copied then
          pcall(function() Preview.invalidatePath(copied) end)
          local cols = math.max(1, math.floor(img:getWidth() / 32))
          registerBlockTileset(S, tsId, copied, img, nil, cols)
          tilesetId = tsId
        end
      end
    end
  end
  if not tilesetId then
    tilesetId = parsed.tileset
    if type(tilesetId) ~= "string" or tilesetId == ""
        or not resolveTileset(S, tilesetId) then
      tilesetId = map.tileset or fallbackTs
    end
  end
  map.tileset = tilesetId
  if isCells then
    applyLayeredCells(S, mapId, map, parsed.blocks, parsed.width, parsed.height,
      paintSource or LayeredMap.runtimeSourceId(tilesetId), tilesetId)
  else
    map.width = parsed.width
    map.height = parsed.height
    map.blocks = parsed.blocks
    applyLayeredBlocks(S, mapId, map, tilesetId)
  end
  S.builderSourceId = paintSource or LayeredMap.runtimeSourceId(tilesetId)
  S.builderLayer = 1
  S.tilesetEditId = tilesetId
  S.mapPaletteTileset = tilesetId
  if parsed.props.palette then map.palette = parsed.props.palette end
  if parsed.props.environment then map.environment = parsed.props.environment end
  if parsed.warps and #parsed.warps > 0 then
    map.warps = parsed.warps
    require("LayeredMap").syncMapWarps(S, map)
  end
  if parsed.signs and #parsed.signs > 0 then map.signs = parsed.signs end
  if parsed.objects and #parsed.objects > 0 then map.objects = parsed.objects end
  if S.data and S.data.maps then S.data.maps[mapId] = map end
  S.mapId = mapId
  S.builderMapId = mapId
  S._mapCenteredFor = nil
  if App and App.markDirty then App.markDirty() end
  pcall(function() require("LayeredMap").compileProject(S) end)
  pcall(function() require("src.world.MapLoader").invalidate(mapId) end)
  pcall(function()
    local Maps = require("Maps")
    if Maps.invalidateGoldPreview then Maps.invalidateGoldPreview(S, mapId) end
  end)
  return true, mapId
end

return TmxIO
