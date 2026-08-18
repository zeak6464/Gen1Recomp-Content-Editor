-- Convert Pokemonium / generic Tiled TMX into engine block maps + a tileset.
-- Each unique 32x32 composite becomes one block of 16 8x8 tiles.

local ModIO = require("ModIO")
local Generation = require("Generation")
local State = require("State")

local TmxPokemonium = {}

local SEP = package.config:sub(1, 1)
local FLIP_UNIT = 0x20000000

local function join(...)
  local parts = { ... }
  for i = 1, #parts do
    parts[i] = tostring(parts[i] or ""):gsub("[/\\]+$", "")
  end
  return table.concat(parts, SEP)
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
  local combined = (tostring(base or ".") .. "/" .. rel):gsub("\\", "/")
  local prefix = combined:match("^([A-Za-z]:)") or ""
  local rest = combined:sub(#prefix + 1)
  local parts = {}
  for part in rest:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local out = prefix
  if prefix ~= "" then
    out = prefix .. SEP .. table.concat(parts, SEP)
  elseif combined:sub(1, 1) == "/" then
    out = SEP .. table.concat(parts, SEP)
  else
    out = table.concat(parts, SEP)
  end
  return out
end

local function unescapeXml(s)
  s = tostring(s or "")
  s = s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">")
  return (s:gsub("&amp;", "&"))
end

local function attr(tag, name)
  local v = tag and tag:match(name .. '%s*=%s*"([^"]*)"')
  if not v then
    v = tag and tag:match(name .. "%s*=%s*'([^']*)'")
  end
  return v and unescapeXml(v) or v
end

local function safeId(name, fallback)
  local id = tostring(name or ""):upper():gsub("[^A-Z0-9_]", "_")
  id = id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if id == "" then id = fallback or "PM_TILES" end
  if id:match("^%d") then id = "TS_" .. id end
  return id
end

local function safeFile(name)
  local s = tostring(name or ""):gsub("[^A-Za-z0-9._-]+", "_")
    :gsub("^[._]+", ""):gsub("[._]+$", "")
  return s ~= "" and s or "tiles"
end

local function layerKey(name)
  return tostring(name or ""):lower():gsub("%s+", "")
end

local function mapIdFromPath(path)
  local base = basename(path):gsub("%.[Tt][Mm][Xx]$", "")
  local x, y = base:match("^(-?%d+)%.(%-?%d+)$")
  if x then
    return ("PM_" .. x .. "_" .. y):gsub("%-", "M")
  end
  return "PM_" .. base:gsub("[^%w_]", "_"):upper()
end

local function worldCoords(path)
  local base = basename(path):gsub("%.[Tt][Mm][Xx]$", "")
  local x, y = base:match("^(-?%d+)%.(%-?%d+)$")
  if x then return tonumber(x), tonumber(y) end
end

local function loadMapNames(mapsDir)
  local names = {}
  local candidates = {
    join(mapsDir, "..", "language", "english", "_MAPNAMES.txt"),
    join(mapsDir, "..", "res", "language", "english", "_MAPNAMES.txt"),
    join(mapsDir, "..", "..", "language", "english", "_MAPNAMES.txt"),
    join(mapsDir, "language", "english", "_MAPNAMES.txt"),
  }
  local body
  for i = 1, #candidates do
    body = ModIO.readText(candidates[i])
    if body then break end
  end
  if not body then return names end
  for line in body:gmatch("[^\r\n]+") do
    if line ~= "" and line:sub(1, 1) ~= "*" then
      local x, y, rest = line:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(.-)%s*$")
      if x and rest ~= "" then
        names[tonumber(x) .. "," .. tonumber(y)] = rest
      end
    end
  end
  return names
end

function TmxPokemonium.collectTmx(path)
  if type(path) ~= "string" or path == "" then return {} end
  if path:lower():match("%.tmx$") then return { path } end
  local files = {}
  local cmd
  if SEP == "\\" then
    cmd = 'dir /b /a-d "' .. path .. '\\*.tmx" 2>nul'
  else
    cmd = 'ls -1 "' .. path .. '"/*.tmx 2>/dev/null'
  end
  local pipe = io.popen(cmd, "r")
  if pipe then
    for line in pipe:lines() do
      line = tostring(line or ""):gsub("%s+$", "")
      if line ~= "" then
        if line:find("[/\\]") then
          files[#files + 1] = line
        else
          files[#files + 1] = join(path, line)
        end
      end
    end
    pipe:close()
  end
  table.sort(files)
  return files
end

local function decodeGid(gid)
  gid = tonumber(gid) or 0
  if gid < 0 then gid = 0 end
  local flags = math.floor(gid / FLIP_UNIT)
  local raw = gid % FLIP_UNIT
  return raw,
    math.floor(flags / 4) % 2 == 1,
    math.floor(flags / 2) % 2 == 1,
    flags % 2 == 1
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

local function decodeBase64(text)
  text = tostring(text or ""):gsub("%s+", "")
  if text == "" then return "" end
  if love and love.data and love.data.decode then
    local ok, raw = pcall(love.data.decode, "string", "base64", text)
    if ok and type(raw) == "string" then return raw end
  end
  return ""
end

local function decompress(raw, compression, expectLen)
  if not compression or compression == "" then return raw end
  if not (love and love.data and love.data.decompress) then return raw end
  local order = { compression }
  if compression == "gzip" then
    order[2], order[3] = "zlib", "deflate"
  elseif compression == "zlib" then
    order[2], order[3] = "gzip", "deflate"
  end
  local fallback
  for i = 1, #order do
    local ok, out = pcall(love.data.decompress, "string", order[i], raw)
    if ok and type(out) == "string" and #out > 0 then
      if expectLen and #out == expectLen then return out end
      if not fallback then
        fallback = out
      elseif expectLen then
        if math.abs(#out - expectLen) < math.abs(#fallback - expectLen) then
          fallback = out
        end
      elseif #out > #fallback then
        fallback = out
      end
    end
  end
  return fallback or raw
end

local function unpackU32(raw, width, height)
  local vals = {}
  for i = 1, #raw, 4 do
    local b1, b2, b3, b4 = raw:byte(i, i + 3)
    if not b4 then break end
    vals[#vals + 1] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  end
  local need = width * height
  while #vals < need do vals[#vals + 1] = 0 end
  return vals
end

local function decodeLayer(dataOpen, text, width, height)
  local encoding = (attr(dataOpen, "encoding") or "csv"):lower()
  local compression = (attr(dataOpen, "compression") or ""):lower()
  if encoding == "csv" and compression == "" then
    return parseCsv(text, width, height)
  end
  if encoding == "base64" then
    local raw = decompress(decodeBase64(text), compression, width * height * 4)
    return unpackU32(raw, width, height)
  end
  return parseCsv(text, width, height)
end

local function loadImage(path)
  local bytes = ModIO.readText(path)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  if not (love and love.image and love.image.newImageData) then return nil end
  local name = basename(path)
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
  if not (okFd and fd) then return nil end
  local ok, data = pcall(love.image.newImageData, fd)
  return ok and data or nil
end

local function applyColorKey(img, hex)
  hex = tostring(hex or ""):gsub("^#", "")
  if #hex ~= 6 or not img then return img end
  local kr = tonumber(hex:sub(1, 2), 16)
  local kg = tonumber(hex:sub(3, 4), 16)
  local kb = tonumber(hex:sub(5, 6), 16)
  if not (kr and kg and kb) then return img end
  local w, h = img:getWidth(), img:getHeight()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b = img:getPixel(x, y)
      if math.floor(r * 255 + 0.5) == kr
          and math.floor(g * 255 + 0.5) == kg
          and math.floor(b * 255 + 0.5) == kb then
        img:setPixel(x, y, r, g, b, 0)
      end
    end
  end
  return img
end

local function cloneMapped(src, dw, dh, mapX, mapY)
  local dst = love.image.newImageData(dw, dh)
  local w, h = src:getWidth(), src:getHeight()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      dst:setPixel(mapX(x, y), mapY(x, y), src:getPixel(x, y))
    end
  end
  return dst
end

local function applyFlips(src, flipH, flipV, flipD)
  if not (flipH or flipV or flipD) then return src end
  local img = src
  if flipD then
    local w, h = img:getWidth(), img:getHeight()
    img = cloneMapped(img, h, w,
      function(x, y) return y end,
      function(x, y) return x end)
  end
  if flipH then
    local w = img:getWidth()
    img = cloneMapped(img, w, img:getHeight(),
      function(x) return w - 1 - x end,
      function(_, y) return y end)
  end
  if flipV then
    local h = img:getHeight()
    img = cloneMapped(img, img:getWidth(), h,
      function(x) return x end,
      function(_, y) return h - 1 - y end)
  end
  return img
end

local function resizeNearest(src, dw, dh)
  local sw, sh = src:getWidth(), src:getHeight()
  if sw == dw and sh == dh then return src end
  local dst = love.image.newImageData(dw, dh)
  for y = 0, dh - 1 do
    local sy = math.floor(y * sh / dh)
    for x = 0, dw - 1 do
      dst:setPixel(x, y, src:getPixel(math.floor(x * sw / dw), sy))
    end
  end
  return dst
end

local function pasteHard(dst, src, dx, dy)
  local sw, sh = src:getWidth(), src:getHeight()
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local r, g, b, a = src:getPixel(x, y)
      if a > 0 then
        dst:setPixel(dx + x, dy + y, r, g, b, a)
      end
    end
  end
end

local function crop(src, sx, sy, w, h)
  local dst = love.image.newImageData(w, h)
  dst:paste(src, 0, 0, sx, sy, w, h)
  return dst
end

local function parseTileImages(inner, baseDir)
  local images = {}
  if not inner then return images end
  local pos = 1
  while true do
    local start = inner:find("<tile[%s>]", pos)
    if not start then break end
    local gt = inner:find(">", start)
    if not gt then break end
    local id = tonumber(attr(inner:sub(start, gt), "id"))
    local close = inner:find("</tile>", gt)
    local chunk = close and inner:sub(start, close + 6) or inner:sub(start, gt)
    local imgStart = chunk:find("<image[%s>]")
    local imgGt = imgStart and chunk:find(">", imgStart)
    if id and imgStart and imgGt then
      local src = attr(chunk:sub(imgStart, imgGt), "source")
      if src and src ~= "" then
        images[id] = resolvePath(baseDir, src)
      end
    end
    pos = (close or gt) + 1
  end
  return images
end

local function tilesetFromXml(openTag, inner, baseDir, firstgid, nameHint, defaultTile)
  local name = attr(openTag, "name") or nameHint or "tiles"
  local tilewidth = tonumber(attr(openTag, "tilewidth")) or defaultTile or 32
  local tileheight = tonumber(attr(openTag, "tileheight")) or defaultTile or 32
  local columns = tonumber(attr(openTag, "columns")) or 0
  local tilecount = tonumber(attr(openTag, "tilecount")) or 0
  local spacing = tonumber(attr(openTag, "spacing")) or 0
  local margin = tonumber(attr(openTag, "margin")) or 0
  inner = inner or ""
  local tileStart = inner:find("<tile[%s>]")
  local imgStart = inner:find("<image[%s>]")
  local imgTag
  if imgStart and (not tileStart or imgStart < tileStart) then
    local imgGt = inner:find(">", imgStart)
    imgTag = imgGt and inner:sub(imgStart, imgGt) or nil
  end
  local imagePath = imgTag and resolvePath(baseDir, attr(imgTag, "source") or "") or nil
  local tileImages = parseTileImages(inner, baseDir)
  if not imagePath and not next(tileImages) then
    return nil, "tileset " .. name .. " has no image"
  end
  return {
    firstgid = firstgid,
    name = name,
    tilewidth = tilewidth,
    tileheight = tileheight,
    columns = columns,
    tilecount = tilecount,
    spacing = spacing,
    margin = margin,
    imagePath = imagePath,
    tileImages = next(tileImages) and tileImages or nil,
    trans = imgTag and attr(imgTag, "trans") or nil,
    imageWidth = imgTag and tonumber(attr(imgTag, "width")) or 0,
    imageHeight = imgTag and tonumber(attr(imgTag, "height")) or 0,
  }
end

local function loadTsx(path, firstgid, defaultTile)
  local body = ModIO.readText(path)
  if not body then return nil, "missing tsx " .. path end
  local start = body:find("<tileset[%s>]")
  local gt = start and body:find(">", start)
  if not (start and gt) then return nil, "invalid tsx " .. path end
  local open = body:sub(start, gt)
  local close = body:find("</tileset>", gt)
  local inner = close and body:sub(gt + 1, close - 1) or ""
  local name = attr(open, "name") or basename(path):gsub("%.[Tt][Ss][Xx]$", "")
  return tilesetFromXml(open, inner, dirname(path), firstgid, name, defaultTile)
end

local function parseTilesets(body, tmxDir, report, defaultTile)
  local tilesets = {}
  local pos = 1
  while true do
    local start = body:find("<tileset%s", pos)
    if not start then break end
    local gt = body:find(">", start)
    if not gt then break end
    local open = body:sub(start, gt)
    local firstgid = tonumber(attr(open, "firstgid")) or 1
    local source = attr(open, "source")
    if source then
      local tsxPath = resolvePath(tmxDir, source)
      local ts, err = loadTsx(tsxPath, firstgid, defaultTile)
      if ts then
        ts.tsxPath = tsxPath
        tilesets[#tilesets + 1] = ts
      else
        report[#report + 1] = err or ("bad tileset " .. source)
      end
      pos = gt + 1
    else
      local close = body:find("</tileset>", gt)
      local inner = close and body:sub(gt + 1, close - 1) or ""
      local ts, err = tilesetFromXml(open, inner, tmxDir, firstgid, nil, defaultTile)
      if ts then
        tilesets[#tilesets + 1] = ts
      else
        report[#report + 1] = err or "bad embedded tileset"
      end
      pos = (close or gt) + 1
    end
  end
  table.sort(tilesets, function(a, b) return a.firstgid > b.firstgid end)
  return tilesets
end

local function parseLayers(body, width, height)
  local layers = {}
  local pos = 1
  while true do
    local start = body:find("<layer%s", pos)
    if not start then break end
    local close = body:find("</layer>", start)
    if not close then break end
    local chunk = body:sub(start, close + 7)
    local layerGt = chunk:find(">")
    local open = layerGt and chunk:sub(1, layerGt) or ""
    local lw = tonumber(attr(open, "width")) or width
    local lh = tonumber(attr(open, "height")) or height
    local dataStart = chunk:find("<data[%s>]")
    local dataGt = dataStart and chunk:find(">", dataStart)
    local dataClose = chunk:find("</data>")
    local dataOpen = (dataStart and dataGt) and chunk:sub(dataStart, dataGt) or "<data>"
    local text = (dataGt and dataClose and dataClose > dataGt)
      and chunk:sub(dataGt + 1, dataClose - 1) or ""
    layers[#layers + 1] = {
      name = attr(open, "name") or "",
      width = lw,
      height = lh,
      gids = decodeLayer(dataOpen, text, lw, lh),
    }
    pos = close + 1
  end
  return layers
end

-- Pokemonium WalkBehind/Water layers are often 256x256; the map is the
-- top-left window of that grid (layer stride is layer.width, not map width).
local function sampleGid(layer, tx, ty, mapW, mapH)
  if not layer then return 0 end
  local lw = layer.width or mapW
  local lh = layer.height or mapH
  local lx, ly = tx, ty
  if lx < 0 or ly < 0 or lx >= lw or ly >= lh then return 0 end
  return (layer.gids and layer.gids[ly * lw + lx + 1]) or 0
end

local function parseMapProperties(body)
  local props = {}
  local mapEnd = body:find("<tileset") or body:find("<layer") or #body
  local chunk = body:sub(1, mapEnd)
  for name, val in chunk:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
    props[unescapeXml(name)] = unescapeXml(val)
  end
  for name, val in chunk:gmatch('<property%s+name="([^"]+)"[^>]*>([^<]*)</property>') do
    if props[name] == nil then
      props[unescapeXml(name)] = unescapeXml(val)
    end
  end
  return props
end

local function objectRecord(obj)
  local rec = {
    name = attr(obj, "name") or "",
    type = attr(obj, "type") or attr(obj, "class") or "",
    x = tonumber(attr(obj, "x")) or 0,
    y = tonumber(attr(obj, "y")) or 0,
    properties = {},
  }
  for pname, pval in obj:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
    rec.properties[pname] = pval
  end
  return rec
end

local function parseObjects(body)
  local out = {}
  for obj in body:gmatch("<object%s.-</object>") do
    out[#out + 1] = objectRecord(obj)
  end
  for obj in body:gmatch("<object%s.-/>") do
    out[#out + 1] = objectRecord(obj)
  end
  return out
end

local function gidToLocal(gid, tilesets)
  local raw = gid % FLIP_UNIT
  if raw == 0 then return nil end
  for i = 1, #tilesets do
    local ts = tilesets[i]
    if ts.firstgid <= raw then
      return ts, raw - ts.firstgid
    end
  end
  return nil
end

local function ensureTilesetImage(ts, report, conv)
  if ts.image then return ts.image end
  conv = conv or {}
  conv.imageCache = conv.imageCache or {}
  local cached = ts.imagePath and conv.imageCache[ts.imagePath]
  if cached then
    ts.image = cached
    ts.imageWidth = cached:getWidth()
    ts.imageHeight = cached:getHeight()
    local derived = (ts.tilewidth > 0)
      and math.max(1, math.floor(cached:getWidth() / ts.tilewidth)) or 1
    if ts.columns <= 1 and derived > 1 then ts.columns = derived
    elseif ts.columns <= 0 then ts.columns = derived end
    return cached
  end
  local img = loadImage(ts.imagePath)
  if not img then
    if ts.imagePath then
      report[#report + 1] = "missing tileset image: " .. tostring(ts.imagePath)
    end
    return nil
  end
  if ts.trans then applyColorKey(img, ts.trans) end
  local derived = (ts.tilewidth > 0)
    and math.max(1, math.floor(img:getWidth() / ts.tilewidth)) or 1
  if ts.columns <= 1 and derived > 1 then
    ts.columns = derived
  elseif ts.columns <= 0 then
    ts.columns = derived
  end
  ts.image = img
  ts.imageWidth = img:getWidth()
  ts.imageHeight = img:getHeight()
  if ts.imagePath then conv.imageCache[ts.imagePath] = img end
  return img
end

local function extractTile(ts, localId, report, conv)
  conv = conv or {}
  conv.tileCache = conv.tileCache or {}
  local cacheKey = tostring(ts.imagePath or ts.name) .. ":" .. tostring(localId)
  local cached = conv.tileCache[cacheKey]
  if cached then return cached end
  if ts.tileImages and ts.tileImages[localId] then
    local path = ts.tileImages[localId]
    conv.imageCache = conv.imageCache or {}
    local img = conv.imageCache[path] or loadImage(path)
    if img then
      conv.imageCache[path] = img
      conv.tileCache[cacheKey] = img
      return img
    end
    report[#report + 1] = "missing tile image: " .. tostring(path)
  end
  local img = ensureTilesetImage(ts, report, conv)
  if not img then return nil end
  local cols = math.max(1, ts.columns)
  local tw, th = ts.tilewidth, ts.tileheight
  local spacing = ts.spacing or 0
  local margin = ts.margin or 0
  local sx = margin + (localId % cols) * (tw + spacing)
  local sy = margin + math.floor(localId / cols) * (th + spacing)
  if sx < 0 or sy < 0 or sx + tw > img:getWidth() or sy + th > img:getHeight() then
    report[#report + 1] = string.format(
      "tile %s#%d out of range", ts.name, localId)
    return nil
  end
  local tile = crop(img, sx, sy, tw, th)
  conv.tileCache[cacheKey] = tile
  return tile
end

local function renderGid(rawGid, tilesets, report, conv, destSize)
  destSize = destSize or 32
  local raw, flipH, flipV, flipD = decodeGid(rawGid)
  if raw == 0 then return nil end
  local ts, localId = gidToLocal(rawGid, tilesets)
  if not ts then return nil end
  local tile = extractTile(ts, localId, report, conv)
  if not tile then return nil end
  tile = applyFlips(tile, flipH, flipV, flipD)
  if tile:getWidth() ~= destSize or tile:getHeight() ~= destSize then
    tile = resizeNearest(tile, destSize, destSize)
  end
  return tile, ts
end

local function compositeStack(stack, tilesets, report, conv, destSize)
  destSize = destSize or 32
  local canvas
  for i = 1, #stack do
    local tile, ts = renderGid(stack[i], tilesets, report, conv, destSize)
    if tile then
      if ts then report._used = report._used or {} ; report._used[ts.name] = true end
      if not canvas then
        canvas = love.image.newImageData(destSize, destSize)
      end
      pasteHard(canvas, tile, 0, 0)
    end
  end
  return canvas
end

-- GIDs are per-file; key by tileset + local id + flip so maps can share blocks.
local function stackKey(stack, tilesets)
  local parts = {}
  for i = 1, #stack do
    local gid = stack[i] or 0
    local raw = gid % FLIP_UNIT
    if raw == 0 then
      parts[i] = "0"
    else
      local ts, localId = gidToLocal(gid, tilesets)
      parts[i] = table.concat({
        ts and (ts.imagePath or ts.name) or "?",
        tostring(localId or 0),
        tostring(gid - raw),
      }, ":")
    end
  end
  return table.concat(parts, "|")
end

local function writePng(imageData, path)
  if not (imageData and imageData.encode) then return false, "no encode" end
  local ok, fileData = pcall(imageData.encode, imageData, "png")
  if not (ok and fileData) then return false, fileData end
  local bytes = fileData.getString and fileData:getString() or tostring(fileData)
  return ModIO.writeText(path, bytes)
end

local function uniqueTilesetId(S, wanted)
  local id = safeId(wanted, "PM_TILES")
  local n = 2
  while (S.project.tilesets and S.project.tilesets[id])
      or Generation.dataTilesets(S)[id] do
    id = safeId(wanted, "PM_TILES") .. "_" .. n
    n = n + 1
  end
  return id
end

local function copySourceTilesets(S, tilesets, report)
  local destDir = join(S.path, "assets", "tilesets", "source")
  ModIO.ensureDirectory(destDir)
  local copied, seen = {}, {}
  for i = 1, #tilesets do
    local ts = tilesets[i]
    local key = ts.imagePath
    if key and not seen[key] then
      seen[key] = true
      local imgName = safeFile(basename(ts.imagePath))
      local destImg = join(destDir, imgName)
      if ModIO.copyFile(ts.imagePath, destImg) then
        copied[#copied + 1] = {
          name = ts.name,
          image = "assets/tilesets/source/" .. imgName,
        }
        report[#report + 1] = "copied source tileset " .. ts.name
      end
    end
  end
  return copied
end

local function convertOne(path, conv, report)
  local body, err = ModIO.readText(path)
  if not body then return nil, err end
  local mapStart = body:find("<map[%s>]")
  local mapGt = mapStart and body:find(">", mapStart)
  local mapTag = (mapStart and mapGt) and body:sub(mapStart, mapGt) or nil
  if not mapTag then return nil, "not a TMX map" end
  local width = tonumber(attr(mapTag, "width"))
  local height = tonumber(attr(mapTag, "height"))
  local tilewidth = tonumber(attr(mapTag, "tilewidth")) or 32
  local tileheight = tonumber(attr(mapTag, "tileheight")) or 32
  if not (width and height) then return nil, "TMX missing width/height" end
  local pack = (tilewidth <= 16 and tileheight <= 16) and 2 or 1
  local destSize = math.floor(32 / pack)
  if pack == 2 then
    report[#report + 1] = string.format(
      "%s: %dx%d tiles at %dx%d (2x2 tiles = one engine block)",
      basename(path), width, height, tilewidth, tileheight)
  elseif tilewidth ~= 32 or tileheight ~= 32 then
    report[#report + 1] = string.format(
      "%s: tile size %dx%d (scaled to 32x32 blocks)",
      basename(path), tilewidth, tileheight)
  end

  local tilesets = parseTilesets(body, dirname(path), report, tilewidth)
  if #tilesets == 0 then return nil, "TMX has no tilesets" end
  for i = 1, #tilesets do conv.allTilesets[#conv.allTilesets + 1] = tilesets[i] end
  local mapProps = parseMapProperties(body)
  local xOff = tonumber(mapProps.xOffsetModifier) or 0
  local yOff = tonumber(mapProps.yOffsetModifier) or 0
  local layers = parseLayers(body, width, height)
  if #layers == 0 then return nil, "TMX has no tile layers" end

  -- Draw every tile layer in file order (Walkable, Water, Collisions,
  -- WalkBehind). Pokemonium's client does the same; Collisions often holds
  -- house walls and tree trunks. Passage still uses map-sized collision only.
  local ground, collisions, waterLayers = {}, {}, {}
  for i = 1, #layers do
    local key = layerKey(layers[i].name)
    ground[#ground + 1] = layers[i]
    if key == "collisions" or key == "collision" then
      collisions[#collisions + 1] = layers[i]
    elseif key == "water" then
      waterLayers[#waterLayers + 1] = layers[i]
    end
  end
  if #ground == 0 then ground[1] = layers[1] end
  local sizedColl = {}
  for i = 1, #collisions do
    local lw = collisions[i].width or width
    local lh = collisions[i].height or height
    if lw <= width and lh <= height then
      sizedColl[#sizedColl + 1] = collisions[i]
    end
  end
  if #sizedColl > 0 then collisions = sizedColl end

  local blockW = math.ceil(width / pack)
  local blockH = math.ceil(height / pack)
  conv.cellTiles = conv.cellTiles or {}
  conv.cellKeyToId = conv.cellKeyToId or {}
  local cellIds, cellCollision, cellFilled = {}, {}, {}
  if pack == 2 then
    for ty = 0, height - 1 do
      for tx = 0, width - 1 do
        local i = ty * width + tx + 1
        local stack, any = {}, false
        for li = 1, #ground do
          local gid = sampleGid(ground[li], tx, ty, width, height)
          stack[li] = gid
          if gid % FLIP_UNIT ~= 0 then any = true end
        end
        local key = stackKey(stack, tilesets)
        local cid = conv.cellKeyToId[key]
        if cid == nil then
          local tile = any and compositeStack(stack, tilesets, report, conv, destSize)
          conv.cellTiles[#conv.cellTiles + 1] = tile
            or love.image.newImageData(destSize, destSize)
          cid = #conv.cellTiles - 1
          conv.cellKeyToId[key] = cid
        end
        cellIds[i] = cid
        cellFilled[i] = any
        local mode = "walk"
        for li = 1, #collisions do
          if sampleGid(collisions[li], tx, ty, width, height) % FLIP_UNIT ~= 0 then
            mode = "solid"
            break
          end
        end
        if mode ~= "solid" then
          for li = 1, #waterLayers do
            if sampleGid(waterLayers[li], tx, ty, width, height) % FLIP_UNIT ~= 0 then
              mode = "water"
              break
            end
          end
        end
        cellCollision[i] = mode
      end
    end
  end

  local blocks = {}
  for by = 0, blockH - 1 do
    for bx = 0, blockW - 1 do
      local parts = {}
      local any = false
      for qy = 0, pack - 1 do
        for qx = 0, pack - 1 do
          local tx, ty = bx * pack + qx, by * pack + qy
          local stack = {}
          if tx < width and ty < height then
            local cell = ty * width + tx + 1
            if pack == 2 then
              parts[#parts + 1] = tostring(cellIds[cell] or 0)
              if cellFilled[cell] then any = true end
            else
              for li = 1, #ground do
                local gid = sampleGid(ground[li], tx, ty, width, height)
                stack[li] = gid
                if gid % FLIP_UNIT ~= 0 then any = true end
              end
              parts[#parts + 1] = stackKey(stack, tilesets)
            end
          else
            parts[#parts + 1] = pack == 2 and "0" or stackKey({}, tilesets)
          end
        end
      end
      local bi = by * blockW + bx + 1
      if not any then
        blocks[bi] = 0
      else
        local key = table.concat(parts, "/")
        local bid = conv.keyToBlock[key]
        if bid == nil then
          local composed = love.image.newImageData(32, 32)
          local painted = false
          for qy = 0, pack - 1 do
            for qx = 0, pack - 1 do
              local tx, ty = bx * pack + qx, by * pack + qy
              local tile
              if tx < width and ty < height then
                local cell = ty * width + tx + 1
                if pack == 2 then
                  tile = conv.cellTiles[(cellIds[cell] or 0) + 1]
                else
                  local stack = {}
                  for li = 1, #ground do
                    stack[li] = sampleGid(ground[li], tx, ty, width, height)
                  end
                  tile = compositeStack(stack, tilesets, report, conv, destSize)
                end
              end
              if tile then
                if tile:getWidth() ~= destSize or tile:getHeight() ~= destSize then
                  tile = resizeNearest(tile, destSize, destSize)
                end
                pasteHard(composed, tile, qx * destSize, qy * destSize)
                painted = true
              end
            end
          end
          bid = painted and conv.appendBlock(composed) or 0
          conv.keyToBlock[key] = bid
        end
        blocks[bi] = bid
      end
    end
  end

  for ty = 0, height - 1 do
    for tx = 0, width - 1 do
      local i = ty * width + tx + 1
      local bx, by = math.floor(tx / pack), math.floor(ty / pack)
      local qx, qy = tx % pack, ty % pack
      local row = conv.blockTiles[(blocks[by * blockW + bx + 1] or 0) + 1]
      if row then
        local blocked = false
        for li = 1, #collisions do
          if sampleGid(collisions[li], tx, ty, width, height) % FLIP_UNIT ~= 0 then
            blocked = true
            break
          end
        end
        if blocked then
          if pack == 1 then
            conv.walkableSet[row[13] or 0] = nil
          else
            local ox, oy = qx * 2, qy * 2
            conv.walkableSet[row[oy * 4 + ox + 1]] = nil
            conv.walkableSet[row[oy * 4 + ox + 2]] = nil
            conv.walkableSet[row[(oy + 1) * 4 + ox + 1]] = nil
            conv.walkableSet[row[(oy + 1) * 4 + ox + 2]] = nil
          end
        end
        local wet = false
        for li = 1, #waterLayers do
          if sampleGid(waterLayers[li], tx, ty, width, height) % FLIP_UNIT ~= 0 then
            wet = true
            break
          end
        end
        if wet then
          if pack == 1 then
            for t = 1, 16 do conv.waterSet[row[t]] = true end
          else
            local ox, oy = qx * 2, qy * 2
            conv.waterSet[row[oy * 4 + ox + 1]] = true
            conv.waterSet[row[oy * 4 + ox + 2]] = true
            conv.waterSet[row[(oy + 1) * 4 + ox + 1]] = true
            conv.waterSet[row[(oy + 1) * 4 + ox + 2]] = true
          end
        end
      end
    end
  end

  local warps, objects, signs = {}, {}, {}
  local parsedObjs = parseObjects(body)
  for i = 1, #parsedObjs do
    local obj = parsedObjs[i]
    local cx = math.floor(obj.x / tilewidth)
    local cy = math.floor(obj.y / tileheight)
    if pack == 1 then
      cx, cy = cx * 2, cy * 2
    end
    local props = obj.properties
    local otype = (obj.type or ""):lower()
    local name = (obj.name or ""):lower()
    if otype:find("warp", 1, true) or name:find("warp", 1, true)
        or props.destMap or props.map then
      warps[#warps + 1] = {
        x = cx, y = cy,
        destMap = tostring(props.destMap or props.map or "PALLET_TOWN"),
        destWarp = tonumber(props.destWarp or props.warp) or 0,
      }
    elseif otype:find("sign", 1, true) or name:find("sign", 1, true) then
      signs[#signs + 1] = {
        x = cx, y = cy,
        text = props.text or obj.name or "SIGN",
      }
    elseif otype:find("npc", 1, true) or otype:find("object", 1, true)
        or obj.name ~= "" then
      objects[#objects + 1] = {
        index = #objects + 1,
        x = cx, y = cy,
        sprite = props.sprite or "SPRITE_RED",
        movement = props.movement or "STAY",
        range = tonumber(props.range) or 0,
        text = props.text or obj.name or "TEXT",
      }
    end
  end

  local wx, wy = worldCoords(path)
  return {
    id = mapIdFromPath(path),
    width = blockW,
    height = blockH,
    blocks = blocks,
    warps = warps,
    objects = objects,
    signs = signs,
    wx = wx,
    wy = wy,
    xOff = xOff,
    yOff = yOff,
    -- Pokemonium modifiers are 32px per TMX tile. Engine offset is blocks
    -- (32px = 2 cells). 16px tiles pack 2x2, so divide by 64; 32px tiles by 32.
    alignDiv = pack == 2 and 64 or 32,
    cellIds = pack == 2 and cellIds or nil,
    cellWidth = pack == 2 and width or nil,
    cellHeight = pack == 2 and height or nil,
    cellCollision = pack == 2 and cellCollision or nil,
    props = mapProps,
  }
end

function TmxPokemonium.importPath(S, path, App)
  if not (S and S.project and S.path) then return false, "no project" end
  if not (love and love.image and love.image.newImageData) then
    return false, "python"
  end
  local files = TmxPokemonium.collectTmx(path)
  if #files == 0 then return false, "no .tmx files" end
  local mapsDir = path:lower():match("%.tmx$") and dirname(path) or path
  local mapNames = loadMapNames(mapsDir)

  State.ensureProjectFields(S.project)
  local report = {
    string.format("converting %d Pokemonium TMX → engine blocks", #files),
  }
  if next(mapNames) then
    report[#report + 1] = "loaded map names from _MAPNAMES.txt"
  end
  local emptyBlock = {}
  for i = 1, 16 do emptyBlock[i] = 0 end
  local conv = {
    sheetTiles = { love.image.newImageData(8, 8) },
    blockTiles = { emptyBlock },
    walkableSet = {},
    waterSet = {},
    keyToBlock = {},
    imageCache = {},
    tileCache = {},
    allTilesets = {},
  }
  function conv.appendBlock(tile)
    local base = #conv.sheetTiles
    local ids = {}
    for row = 0, 3 do
      for col = 0, 3 do
        local tid = base + row * 4 + col
        conv.sheetTiles[tid + 1] = crop(tile, col * 8, row * 8, 8, 8)
        ids[row * 4 + col + 1] = tid
        conv.walkableSet[tid] = true
      end
    end
    conv.blockTiles[#conv.blockTiles + 1] = ids
    return #conv.blockTiles - 1
  end

  local converted = {}
  for i = 1, #files do
    local m, err = convertOne(files[i], conv, report)
    if m then
      converted[#converted + 1] = m
    else
      report[#report + 1] = "FAIL " .. basename(files[i]) .. ": " .. tostring(err)
    end
    if i == 1 or i % 50 == 0 or i == #files then
      local line = string.format("[pokemonium] map %d/%d %s", i, #files, basename(files[i]))
      print(line)
      local lf = io.open((os.getenv("TEMP") or ".") .. "\\pokemonium_pack.log", "a")
      if lf then lf:write(line .. "\n"); lf:close() end
      collectgarbage("collect")
    end
  end
  if #converted == 0 then
    return false, report[#report] or "no maps converted"
  end

  local tilesetId
  local firstExisting = S.project.maps[converted[1].id]
  local existingTs = firstExisting and firstExisting.tileset
    and S.project.tilesets[firstExisting.tileset]
  if existingTs and existingTs._isNew and not existingTs._layeredGenerated then
    tilesetId = firstExisting.tileset
  elseif #conv.allTilesets == 1 then
    tilesetId = uniqueTilesetId(S, conv.allTilesets[1].name)
  else
    tilesetId = uniqueTilesetId(S, "PM_TILES")
  end

  local nTiles = #conv.sheetTiles
  local cols = 16
  local rows = math.max(1, math.ceil(nTiles / cols))
  local atlas = love.image.newImageData(cols * 8, rows * 8)
  for i = 1, nTiles do
    local tile = conv.sheetTiles[i]
    if tile then
      atlas:paste(tile, ((i - 1) % cols) * 8, math.floor((i - 1) / cols) * 8, 0, 0, 8, 8)
    end
  end
  local rel = "assets/tilesets/" .. tilesetId:lower() .. ".png"
  ModIO.ensureDirectory(join(S.path, "assets", "tilesets"))
  local okPng, pngErr = writePng(atlas, join(S.path, (rel:gsub("/", SEP))))
  if not okPng then return false, pngErr end

  local walkable, waterTiles = {}, {}
  for id in pairs(conv.walkableSet) do walkable[#walkable + 1] = id end
  for id in pairs(conv.waterSet) do waterTiles[#waterTiles + 1] = id end
  table.sort(walkable)
  table.sort(waterTiles)
  local tsRec = {
    id = tilesetId,
    image = rel,
    tilesPerRow = 16,
    imageWidth = atlas:getWidth(),
    imageHeight = atlas:getHeight(),
    animation = "TILEANIM_NONE",
    doorTiles = {},
    warpTiles = {},
    counterTiles = {},
    blocks = conv.blockTiles,
    walkable = walkable,
    waterTiles = waterTiles,
    trueColor = true,
    _isNew = true,
  }
  S.project.tilesets[tilesetId] = tsRec
  if S.data and S.data.tilesets then S.data.tilesets[tilesetId] = tsRec end
  copySourceTilesets(S, conv.allTilesets, report)

  local LayeredMap = require("LayeredMap")
  local cellSourceId
  if conv.cellTiles and #conv.cellTiles > 0 then
    local nCells = #conv.cellTiles
    local cellCols = math.max(1, math.ceil(math.sqrt(nCells)))
    local cellRows = math.max(1, math.ceil(nCells / cellCols))
    local cellAtlas = love.image.newImageData(cellCols * 16, cellRows * 16)
    for i = 1, nCells do
      local tile = conv.cellTiles[i]
      if tile then
        if tile:getWidth() ~= 16 or tile:getHeight() ~= 16 then
          tile = resizeNearest(tile, 16, 16)
        end
        cellAtlas:paste(tile, ((i - 1) % cellCols) * 16,
          math.floor((i - 1) / cellCols) * 16, 0, 0, 16, 16)
      end
    end
    local cellRel = "assets/mapbuilder/sources/" .. tilesetId:lower() .. "_cells.png"
    ModIO.ensureDirectory(join(S.path, "assets", "mapbuilder", "sources"))
    if writePng(cellAtlas, join(S.path, (cellRel:gsub("/", SEP)))) then
      local src = LayeredMap.installTileSource(
        S.project, tilesetId .. "_CELLS", cellRel,
        cellAtlas:getWidth(), cellAtlas:getHeight())
      if src then
        cellSourceId = src.id
        pcall(function() require("Preview").invalidatePath(cellRel) end)
      end
    end
    if cellAtlas.release then pcall(cellAtlas.release, cellAtlas) end
  end

  local byWorld = {}
  for i = 1, #converted do
    local m = converted[i]
    if m.wx then byWorld[m.wx .. "," .. m.wy] = m end
  end

  local gen2 = Generation.isGen2(S)
  local firstId
  for i = 1, #converted do
    local rec = converted[i]
    local existing = S.project.maps[rec.id]
    local index
    if existing and existing.index then
      index = existing.index
    else
      index = S.project.nextMapIndex or 1000
      S.project.nextMapIndex = index + 1
    end
    local connections = {}
    if rec.wx then
      local dirs = {
        { 0, -1, "north" }, { 0, 1, "south" },
        { -1, 0, "west" }, { 1, 0, "east" },
      }
      local div = rec.alignDiv or 64
      for d = 1, 4 do
        local neighbor = byWorld[(rec.wx + dirs[d][1]) .. "," .. (rec.wy + dirs[d][2])]
        if neighbor then
          local dir = dirs[d][3]
          local px
          if dir == "north" or dir == "south" then
            px = (neighbor.xOff or 0) - (rec.xOff or 0)
          else
            px = (neighbor.yOff or 0) - (rec.yOff or 0)
          end
          connections[dir] = {
            mapId = neighbor.id, map = neighbor.id, offset = px / div,
          }
        end
      end
    end
    local map = existing or {}
    map.id = rec.id
    local placeName = rec.wx and mapNames[rec.wx .. "," .. rec.wy]
    map.label = placeName or map.label or rec.id
    map.index = index
    map.tileset = tilesetId
    map.width = rec.width
    map.height = rec.height
    map.blocks = rec.blocks
    map.borderBlock = map.borderBlock or 0
    map.warps = rec.warps
    map.objects = rec.objects
    map.signs = rec.signs
    map.connections = connections
    map._isNew = true
    if gen2 then
      map.environment = map.environment or "TOWN"
      map.bgEvents = map.bgEvents or {}
    else
      map.environment = map.environment or "outside"
    end
    if map.outdoor == nil then
      map.outdoor = gen2 or map.environment == "outside"
    end
    map.trueColor = true
    map._pmProps = rec.props
    map._pmWx, map._pmWy = rec.wx, rec.wy
    S.project.maps[rec.id] = map
    if S.data and S.data.maps then S.data.maps[rec.id] = map end
    if S.project.layeredMaps then S.project.layeredMaps[rec.id] = nil end
    if rec.cellIds and cellSourceId then
      local cw = rec.cellWidth + (rec.cellWidth % 2)
      local ch = rec.cellHeight + (rec.cellHeight % 2)
      local intern = {}
      local cells, collision = {}, {}
      for y = 0, ch - 1 do
        for x = 0, cw - 1 do
          local index = y * cw + x + 1
          local srcIndex = (y < rec.cellHeight and x < rec.cellWidth)
            and (y * rec.cellWidth + x + 1) or nil
          local tile = srcIndex and (rec.cellIds[srcIndex] or 0) or 0
          local ref = intern[tile]
          if not ref then
            ref = { source = cellSourceId, tile = tile }
            intern[tile] = ref
          end
          cells[index] = ref
          collision[index] = (srcIndex and rec.cellCollision and rec.cellCollision[srcIndex])
            or "solid"
        end
      end
      S.project.layeredMaps = S.project.layeredMaps or {}
      S.project.layeredMaps[rec.id] = {
        id = rec.id,
        cellWidth = cw,
        cellHeight = ch,
        baseTileset = tilesetId,
        layers = {{
          id = "ground", name = "Ground", visible = true, export = true,
          opacity = 1, cells = cells,
        }},
        collision = collision,
      }
      map._layeredSource = rec.id
      map.width, map.height = cw / 2, ch / 2
    else
      pcall(function() LayeredMap.convertMap(S, rec.id) end)
    end
    pcall(function() require("src.world.MapLoader").invalidate(rec.id) end)
    report[#report + 1] = string.format(
      "%s: %dx%d blocks, %d warps, %d objects",
      rec.id, rec.width, rec.height, #rec.warps, #rec.objects)
    firstId = firstId or rec.id
  end

  if report._used then
    local used = {}
    for name in pairs(report._used) do used[#used + 1] = name end
    table.sort(used)
    report._used = nil
    report[#report + 1] = "used tileset(s): " .. table.concat(used, ", ")
  end
  report[#report + 1] = string.format(
    "tileset %s: %d unique blocks, %d 8x8 tiles",
    tilesetId, #conv.blockTiles - 1, nTiles)
  if nTiles > 256 then
    report[#report + 1] = "WARNING: " .. nTiles .. " 8x8 tiles (engine limit 256)"
  end
  if #conv.blockTiles > 256 then
    report[#report + 1] = "WARNING: " .. #conv.blockTiles .. " blocks (engine limit 256)"
  end

  S.mapId = firstId
  S.builderMapId = firstId
  S.builderSourceId = cellSourceId or LayeredMap.runtimeSourceId(tilesetId)
  S.tilesetEditId = tilesetId
  S.mapPaletteTileset = tilesetId
  S._mapPaletteFor = firstId
  S._mapCenteredFor = nil
  S._builderFitFor = nil
  S._mapNeedsRebuild = firstId
  S.importReport = table.concat(report, "\n")
  pcall(function() require("Preview").invalidatePath(rel) end)
  if App and App.markDirty then App.markDirty() end
  local function dropImage(img)
    if img and img.release then pcall(img.release, img) end
  end
  if conv.cellTiles then
    for i = 1, #conv.cellTiles do dropImage(conv.cellTiles[i]) end
  end
  if conv.sheetTiles then
    for i = 1, #conv.sheetTiles do dropImage(conv.sheetTiles[i]) end
  end
  if conv.tileCache then
    for _, img in pairs(conv.tileCache) do dropImage(img) end
  end
  if conv.imageCache then
    for _, img in pairs(conv.imageCache) do dropImage(img) end
  end
  conv.cellTiles, conv.sheetTiles, conv.imageCache, conv.tileCache = nil, nil, nil, nil
  pcall(function() require("LayeredMap").compileProject(S) end)
  pcall(function() require("src.world.MapLoader").invalidate(firstId) end)
  pcall(function()
    local Maps = require("Maps")
    if Maps.invalidateGoldPreview then Maps.invalidateGoldPreview(S, firstId) end
  end)
  pcall(function() require("History").clear(S) end)
  collectgarbage("collect")
  local summary = #converted == 1
    and (firstId .. " (converted to engine blocks)")
    or string.format("%d maps + tileset %s", #converted, tilesetId)
  return true, summary
end

function TmxPokemonium.importFile(S, path, App)
  return TmxPokemonium.importPath(S, path, App)
end

return TmxPokemonium
