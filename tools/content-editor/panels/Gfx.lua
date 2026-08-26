-- GFX tab: palettes, overworld sprites, tilesets.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local ColorWheel = require("ColorWheel")
local PalettePicker = require("PalettePicker")
local ChoicePicker = require("ChoicePicker")
local ModIO = require("ModIO")
local SpriteUtil = require("SpriteUtil")
local SpriteAnimPreview = require("SpriteAnimPreview")
local MapLoader = require("src.world.MapLoader")
local Generation = require("Generation")
local PAL = Theme.PAL

local Gfx = {}

local MODES = {
  { id = "palettes", label = "Palettes", tip = "SGB/GBC color palettes (4 colors)" },
  { id = "sprites", label = "Sprites", tip = "Overworld sprite sheets" },
  { id = "tilesets", label = "Tilesets",
    tip = "Tileset editor: import PNG, paint flags, compose 4×4 blocks" },
}

local TILE_PX = 8  -- Gen1 tileset sheet cells are 8x8
local FLAG_MODES = {
  { id = "walk", label = "Walk", tip = "Passage O — passable (in walkable list)" },
  { id = "solid", label = "Solid", tip = "Passage X — blocked (not walkable)" },
  { id = "water", label = "Water", tip = "Surfable water tile" },
  { id = "grass", label = "Grass", tip = "Tall grass / bush (wild encounters)" },
  { id = "shore", label = "Shore", tip = "Shore / beach (surf edge)" },
  { id = "door", label = "Door", tip = "Door tile (doorTiles)" },
  { id = "warp", label = "Warp", tip = "Warp / carpet tile (warpTiles)" },
  { id = "counter", label = "Counter", tip = "Shop counter tile (counterTiles)" },
}

-- Gen2: paint COLL_* bytes onto each metatile's 2×2 collision quad.
local COLL_MODES = {
  { id = "walk", label = "Land", tip = "COLL land (0x00)", value = 0x00 },
  { id = "solid", label = "Wall", tip = "COLL wall (0xff)", value = 0xff },
  { id = "grass", label = "Grass", tip = "COLL_TALL_GRASS (0x18)", value = 0x18 },
  { id = "water", label = "Water", tip = "COLL_WATER (0x29)", value = 0x29 },
  { id = "door", label = "Door", tip = "COLL_DOOR (0x71)", value = 0x71 },
  { id = "warp", label = "Warp", tip = "COLL_WARP_PANEL (0x7c)", value = 0x7c },
}
local TILE_ANIMS = {
  "TILEANIM_NONE",
  "TILEANIM_WATER",
  "TILEANIM_WATER_FLOWER",
}

local function parseRgb(s, fallback)
  local r, g, b = tostring(s or ""):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if r then return { tonumber(r), tonumber(g), tonumber(b) } end
  return fallback or { 0, 0, 0 }
end

local function fmtRgb(c)
  if type(c) ~= "table" then return "0,0,0" end
  if c.r then return string.format("%d,%d,%d", c.r, c.g, c.b) end
  return string.format("%d,%d,%d", c[1] or 0, c[2] or 0, c[3] or 0)
end

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

local function drawPalettePreview(colors, x, y, w, h, s)
  colors = colors or {}
  local sw = w / 4
  for i = 1, 4 do
    local c = colors[i] or { 40, 40, 40 }
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", x + (i - 1) * sw, y, sw - 2 * s, h, 4 * s, 4 * s)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function csvNums(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    local n = tonumber(part:match("%d+"))
    if n then out[#out + 1] = n end
  end
  return out
end

local function joinNums(t)
  if type(t) ~= "table" then return "" end
  return table.concat(t, ",")
end

local function listIndex(list, n)
  for i, v in ipairs(list or {}) do
    if v == n then return i end
  end
  return nil
end

local function listSet(list, n, on)
  local i = listIndex(list, n)
  if on and not i then
    list[#list + 1] = n
    table.sort(list)
  elseif not on and i then
    table.remove(list, i)
  end
end

local function cloneNumList(v)
  local a = {}
  for i = 1, #(v or {}) do a[i] = v[i] end
  return a
end

local function syncTilesetLive(S, id, ts)
  if S.data then
    S.data.tilesets = S.data.tilesets or {}
    S.data.tilesets[id] = ts
    if S.data.gen2Tilesets and S.data.gen2Tilesets ~= S.data.tilesets then
      S.data.gen2Tilesets[id] = ts
    end
  end
  MapLoader.invalidateAll()
end

local function tilesetTileCount(rec, img)
  local tpr = rec.tilesPerRow or 16
  if img then
    local cols = math.max(1, math.floor(img:getWidth() / TILE_PX))
    local rows = math.max(1, math.floor(img:getHeight() / TILE_PX))
    return cols * rows, cols
  end
  local maxId = 0
  for _, block in ipairs(rec.blocks or {}) do
    for _, t in ipairs(block) do
      if type(t) == "number" and t > maxId then maxId = t end
    end
  end
  return maxId + 1, tpr
end

local function rebuildBlocksFromSheet(rec, img)
  if not (rec and img) then return end
  local tw = math.max(1, math.floor(img:getWidth() / TILE_PX))
  local th = math.max(1, math.floor(img:getHeight() / TILE_PX))
  local tileCount = tw * th
  local nBlocks = math.max(1, math.floor(tileCount / 16))
  local blocks = {}
  for b = 0, nBlocks - 1 do
    local row = {}
    for i = 0, 15 do row[i + 1] = b * 16 + i end
    blocks[b + 1] = row
  end
  rec.blocks = blocks
  rec.tilesPerRow = tw
  rec.imageWidth = img:getWidth()
  rec.imageHeight = img:getHeight()
end

-- Draw one 4×4 metatile from the tileset sheet into a square cell.
local function drawMetatileThumb(img, block, tilesPerRow, x, y, size)
  if not (img and type(block) == "table" and love.graphics.newQuad) then return false end
  local per = tilesPerRow or 16
  local tileDraw = size / 4
  local iw, ih = img:getDimensions()
  love.graphics.setColor(1, 1, 1, 1)
  for r = 0, 3 do
    for c = 0, 3 do
      local tid = block[r * 4 + c + 1] or 0
      if type(tid) == "number" then
        local q = love.graphics.newQuad(
          (tid % per) * TILE_PX, math.floor(tid / per) * TILE_PX,
          TILE_PX, TILE_PX, iw, ih)
        love.graphics.draw(img, q, x + c * tileDraw, y + r * tileDraw,
          0, tileDraw / TILE_PX, tileDraw / TILE_PX)
      end
    end
  end
  return true
end

-- Gen2: paint COLL_* on metatile collision quads (4 bytes per block).
-- Metatile graphics are drawn under a translucent COLL color overlay.
local function drawCollisionPainter(S, App, rec, ensureFn, id, x, y, w, s)
  Kit.text("micro", "COLLISION QUADS (per metatile — COLL_* bytes)", x, y, PAL.caption)
  y = y + 14 * s
  S.gfxCollMode = S.gfxCollMode or "walk"
  local mx = x
  local paintVal = 0x00
  for _, mode in ipairs(COLL_MODES) do
    local on = S.gfxCollMode == mode.id
    if on then paintVal = mode.value end
    local bw = Kit.textWidth("micro", mode.label) + 14 * s
    if mx + bw > x + w then
      mx = x
      y = y + 26 * s
    end
    if Kit.chip(mx, y, bw, 22 * s, mode.label, on, PAL.green, nil, mode.tip) then
      S.gfxCollMode = mode.id
      paintVal = mode.value
    end
    mx = mx + bw + 3 * s
  end
  y = y + 28 * s
  Kit.text("micro",
    "Click a metatile to set all 4 COLL bytes. Green=land  Red=wall  Magenta=grass  Blue=water  Yellow=door  Orange=warp",
    x, y, PAL.faint)
  y = y + 14 * s
  local coll = rec.collision or {}
  local blocks = rec.blocks or {}
  local n = math.max(#coll, #blocks, 1)
  local cols = math.max(1, math.floor(w / (36 * s)))
  local cell = math.floor(w / cols)
  local img = Preview.image(S, rec.image)
  local per = rec.tilesPerRow or 16
  local inner = cell - 2
  for bi = 0, n - 1 do
    local col = bi % cols
    local row = math.floor(bi / cols)
    local tx = x + col * cell
    local ty = y + row * cell
    Theme.col(PAL.rowBg, 1)
    love.graphics.rectangle("fill", tx + 1, ty + 1, inner, inner)
    drawMetatileThumb(img, blocks[bi + 1], per, tx + 1, ty + 1, inner)
    local quad = coll[bi + 1] or { 0xff, 0xff, 0xff, 0xff }
    local sample = quad[1] or 0xff
    if sample == 0x18 then
      love.graphics.setColor(0.95, 0.2, 0.85, 0.45)
    elseif sample == 0x21 or sample == 0x29 then
      love.graphics.setColor(0.15, 0.45, 1, 0.4)
    elseif sample == 0x71 then
      love.graphics.setColor(0.95, 0.85, 0.15, 0.45)
    elseif sample == 0x7c then
      love.graphics.setColor(1, 0.55, 0.1, 0.45)
    elseif sample == 0x00 then
      love.graphics.setColor(0.2, 0.9, 0.4, 0.35)
    else
      love.graphics.setColor(1, 0.2, 0.25, 0.35)
    end
    love.graphics.rectangle("fill", tx + 1, ty + 1, inner, inner)
    Kit.text("micro", tostring(bi), tx + 2, ty + 2, PAL.heading)
    if Kit.press(tx, ty, cell, cell) then
      local e = ensureFn()
      e.collision = e.collision or {}
      for i = #e.collision + 1, bi + 1 do
        e.collision[i] = { 0xff, 0xff, 0xff, 0xff }
      end
      for _, mode in ipairs(COLL_MODES) do
        if mode.id == (S.gfxCollMode or "walk") then paintVal = mode.value end
      end
      e.collision[bi + 1] = { paintVal, paintVal, paintVal, paintVal }
      syncTilesetLive(S, id, e)
      App.markDirty()
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local rows = math.ceil(n / cols)
  return y + rows * cell + 8 * s
end

-- Clickable 8x8 sheet: paint walk / solid / water / grass / shore / door / warp / counter.
-- Returns the Y after the painter (for FormPane content height).
-- opts.onTileClick(tid) — optional override (block editor pick); skips flag paint.
local function drawTileFlagPainter(S, App, rec, ensureFn, id, x, y, w, s, palName, opts)
  opts = opts or {}
  if Generation.isGen2(S) and not opts.pickOnly then
    return drawCollisionPainter(S, App, rec, ensureFn, id, x, y, w, s)
  end
  Kit.text("micro",
    opts.title or "TILE FLAGS (sheet — map Passage paint is on Maps)",
    x, y, PAL.caption)
  y = y + 14 * s
  if not opts.pickOnly then
    S.gfxTileFlagMode = S.gfxTileFlagMode or "walk"
    local mx = x
    for _, mode in ipairs(FLAG_MODES) do
      local on = S.gfxTileFlagMode == mode.id
      local bw = Kit.textWidth("micro", mode.label) + 14 * s
      if mx + bw > x + w then
        mx = x
        y = y + 26 * s
      end
      if Kit.chip(mx, y, bw, 22 * s, mode.label, on, PAL.green, nil, mode.tip) then
        S.gfxTileFlagMode = mode.id
      end
      mx = mx + bw + 3 * s
    end
    y = y + 28 * s
    Kit.text("micro",
      "green=walk  red=solid  blue=water  cyan=shore  magenta=grass  yellow=door  orange=warp  purple=counter",
      x, y, PAL.faint)
    y = y + 14 * s
  end

  local img = Preview.image(S, rec.image)
  local count, cols = tilesetTileCount(rec, img)
  cols = cols or (rec.tilesPerRow or 16)
  local cell = math.max(12 * s, math.min(20 * s, math.floor((w - 4 * s) / cols)))
  local rows = math.max(1, math.ceil(count / cols))
  local gridW = cols * cell
  local gridH = rows * cell
  local walk = {}
  for _, t in ipairs(rec.walkable or {}) do walk[t] = true end
  local water = {}
  for _, t in ipairs(rec.waterTiles or {}) do water[t] = true end
  local shore = {}
  for _, t in ipairs(rec.shoreTiles or {}) do shore[t] = true end
  local door = {}
  for _, t in ipairs(rec.doorTiles or {}) do door[t] = true end
  local warp = {}
  for _, t in ipairs(rec.warpTiles or {}) do warp[t] = true end
  local counter = {}
  for _, t in ipairs(rec.counterTiles or {}) do counter[t] = true end
  local grass = rec.grassTile

  Kit.pushClip(x, y, w, gridH)
  Theme.col(PAL.bgBot, 1)
  love.graphics.rectangle("fill", x, y, gridW, gridH)

  local shaded = (not rec.trueColor) and Preview.pushPaletteShader(S, palName)
  if img and love.graphics.draw then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, cell / TILE_PX, cell / TILE_PX)
  end
  if shaded then Preview.popPaletteShader(shaded) end

  for tid = 0, count - 1 do
    local col = tid % cols
    local row = math.floor(tid / cols)
    local tx = x + col * cell
    local ty = y + row * cell

    if not opts.pickOnly then
      if water[tid] then
        love.graphics.setColor(0.15, 0.45, 1, 0.4)
        love.graphics.rectangle("fill", tx, ty, cell, cell)
      end
      if shore[tid] then
        love.graphics.setColor(0.2, 0.85, 0.9, 0.35)
        love.graphics.rectangle("fill", tx, ty, cell, cell)
      end
      if walk[tid] then
        love.graphics.setColor(0.2, 0.9, 0.4, 0.28)
        love.graphics.rectangle("fill", tx, ty, cell, cell)
      else
        love.graphics.setColor(1, 0.2, 0.25, 0.32)
        love.graphics.rectangle("fill", tx, ty, cell, cell)
      end
      if grass ~= nil and grass == tid then
        love.graphics.setColor(0.95, 0.2, 0.85, 0.45)
        love.graphics.rectangle("fill", tx, ty, cell, cell)
        love.graphics.setColor(1, 0.35, 0.95, 1)
        love.graphics.rectangle("line", tx + 1, ty + 1, cell - 2, cell - 2)
      end
      if door[tid] then
        love.graphics.setColor(0.95, 0.85, 0.15, 0.45)
        love.graphics.rectangle("line", tx + 1, ty + 1, cell - 2, cell - 2)
      end
      if warp[tid] then
        love.graphics.setColor(1, 0.55, 0.1, 0.5)
        love.graphics.rectangle("line", tx + 2, ty + 2, cell - 4, cell - 4)
      end
      if counter[tid] then
        love.graphics.setColor(0.7, 0.3, 0.95, 0.45)
        love.graphics.rectangle("fill", tx, ty + cell * 0.65, cell, cell * 0.35)
      end
    end

    if Kit.press(tx, ty, cell, cell) then
      if opts.onTileClick then
        opts.onTileClick(tid)
      else
        local e = ensureFn()
        e.walkable = e.walkable or {}
        e.waterTiles = e.waterTiles or {}
        e.shoreTiles = e.shoreTiles or {}
        e.doorTiles = e.doorTiles or {}
        e.warpTiles = e.warpTiles or {}
        e.counterTiles = e.counterTiles or {}
        local mode = S.gfxTileFlagMode or "walk"
        if mode == "walk" then
          listSet(e.walkable, tid, true)
        elseif mode == "solid" then
          listSet(e.walkable, tid, false)
        elseif mode == "water" then
          listSet(e.waterTiles, tid, listIndex(e.waterTiles, tid) == nil)
        elseif mode == "shore" then
          listSet(e.shoreTiles, tid, listIndex(e.shoreTiles, tid) == nil)
        elseif mode == "grass" then
          e.grassTile = (e.grassTile == tid) and nil or tid
        elseif mode == "door" then
          listSet(e.doorTiles, tid, listIndex(e.doorTiles, tid) == nil)
        elseif mode == "warp" then
          listSet(e.warpTiles, tid, listIndex(e.warpTiles, tid) == nil)
        elseif mode == "counter" then
          listSet(e.counterTiles, tid, listIndex(e.counterTiles, tid) == nil)
        end
        syncTilesetLive(S, id, e)
        App.markDirty()
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  Kit.popClip()

  return y + gridH + 8 * s
end

-- Visual Gen1 block composer: pick a block, edit its 4×4 tile ids from the sheet.
local function drawBlockEditor(S, App, rec, ensureFn, id, x, y, w, s, palName)
  Kit.text("micro", "BLOCKS (each map cell = one 4×4 block of 8×8 tiles)", x, y, PAL.caption)
  y = y + 14 * s

  local ePeek = rec
  local blocks = ePeek.blocks or {}
  local nBlocks = #blocks
  S.gfxBlockEditId = math.max(0, math.min(math.max(0, nBlocks - 1),
    tonumber(S.gfxBlockEditId) or 0))

  local btnH = 24 * s
  if Kit.button(x, y, 88 * s, btnH, "+ Block", {
      kind = "good", font = "small",
      tooltip = "Append a new 4×4 block (all tile 0)",
    }) then
    local e = ensureFn()
    e.blocks = e.blocks or {}
    local row = {}
    for i = 1, 16 do row[i] = 0 end
    e.blocks[#e.blocks + 1] = row
    S.gfxBlockEditId = #e.blocks - 1
    syncTilesetLive(S, id, e)
    App.markDirty()
  end
  if Kit.button(x + 94 * s, y, 88 * s, btnH, "- Last", {
      kind = "danger", font = "small",
      tooltip = "Remove the last block",
    }) and nBlocks > 1 then
    local e = ensureFn()
    table.remove(e.blocks, #e.blocks)
    S.gfxBlockEditId = math.min(S.gfxBlockEditId or 0, #e.blocks - 1)
    syncTilesetLive(S, id, e)
    App.markDirty()
  end
  if Kit.button(x + 188 * s, y, 120 * s, btnH, "Rebuild sheet", {
      kind = "ghost", font = "small",
      tooltip = "Rebuild sequential blocks from PNG size (16 tiles each)",
    }) then
    local e = ensureFn()
    local img = Preview.image(S, e.image)
    if img then
      rebuildBlocksFromSheet(e, img)
      S.gfxBlockEditId = 0
      syncTilesetLive(S, id, e)
      App.markDirty()
      S.status = "Rebuilt " .. #e.blocks .. " blocks from sheet"
    else
      S.status = "No tileset image — Browse a PNG first"
    end
  end
  y = y + btnH + 8 * s

  local live = (S.project.tilesets and S.project.tilesets[id]) or rec
  blocks = live.blocks or {}
  nBlocks = #blocks
  if nBlocks == 0 then
    Kit.text("micro", "No blocks yet — Rebuild sheet or + Block", x, y, PAL.muted)
    return y + 20 * s
  end

  local thumb = 36 * s
  local gap = 4 * s
  local perRow = math.max(1, math.floor((w + gap) / (thumb + gap)))
  local img = Preview.image(S, live.image)
  local bid = math.max(0, math.min(nBlocks - 1, tonumber(S.gfxBlockEditId) or 0))
  S.gfxBlockEditId = bid
  local maxRows = 3
  local startRow = tonumber(S.gfxBlockStripRow) or 0
  local totalRows = math.max(1, math.ceil(nBlocks / perRow))
  if startRow > totalRows - 1 then startRow = math.max(0, totalRows - 1) end
  S.gfxBlockStripRow = startRow
  if Kit.chip(x + w - 70 * s, y - btnH - 8 * s, 32 * s, btnH, "^",
      false, PAL.blue, nil, "Scroll blocks up") and startRow > 0 then
    S.gfxBlockStripRow = startRow - 1
    startRow = S.gfxBlockStripRow
  end
  if Kit.chip(x + w - 34 * s, y - btnH - 8 * s, 32 * s, btnH, "v",
      false, PAL.blue, nil, "Scroll blocks down") and startRow < totalRows - maxRows then
    S.gfxBlockStripRow = startRow + 1
    startRow = S.gfxBlockStripRow
  end

  local rowsShown = math.min(maxRows, totalRows - startRow)
  local stripH = rowsShown * (thumb + gap)
  Kit.pushClip(x, y, w, stripH)
  for i = 0, nBlocks - 1 do
    local col = i % perRow
    local row = math.floor(i / perRow)
    if row < startRow or row >= startRow + rowsShown then
      -- skip
    else
      local bx = x + col * (thumb + gap)
      local by = y + (row - startRow) * (thumb + gap)
      local block = blocks[i + 1]
      Theme.col(PAL.rowBg, 1)
      love.graphics.rectangle("fill", bx, by, thumb, thumb, 3 * s, 3 * s)
      if type(block) == "table" and img then
        local tileDraw = thumb / 4
        local per = live.tilesPerRow or 16
        local iw, ih = img:getDimensions()
        local shaded = (not live.trueColor) and Preview.pushPaletteShader(S, palName)
        love.graphics.setColor(1, 1, 1, 1)
        for r = 0, 3 do
          for c = 0, 3 do
            local tid = block[r * 4 + c + 1] or 0
            if type(tid) == "number" and love.graphics.newQuad then
              local q = love.graphics.newQuad(
                (tid % per) * TILE_PX, math.floor(tid / per) * TILE_PX,
                TILE_PX, TILE_PX, iw, ih)
              love.graphics.draw(img, q, bx + c * tileDraw, by + r * tileDraw,
                0, tileDraw / TILE_PX, tileDraw / TILE_PX)
            end
          end
        end
        if shaded then Preview.popPaletteShader(shaded) end
      end
      if i == bid then
        love.graphics.setColor(0.3, 0.75, 1, 1)
        love.graphics.rectangle("line", bx, by, thumb, thumb, 3 * s, 3 * s)
      end
      if Kit.press(bx, by, thumb, thumb) then
        S.gfxBlockEditId = i
        S.gfxBlockCell = nil
      end
    end
  end
  Kit.popClip()
  love.graphics.setColor(1, 1, 1, 1)
  y = y + stripH + 6 * s

  Kit.text("micro",
    string.format("Block %d / %d — click a cell, then a sheet tile",
      bid, math.max(0, nBlocks - 1)),
    x, y, PAL.caption)
  y = y + 14 * s

  local block = blocks[bid + 1]
  if type(block) ~= "table" then
    return y + 8 * s
  end
  local cell = math.min(40 * s, math.floor((w - 8 * s) / 4))
  for r = 0, 3 do
    for c = 0, 3 do
      local ci = r * 4 + c + 1
      local cx = x + c * (cell + 2 * s)
      local cy = y + r * (cell + 2 * s)
      local tid = block[ci] or 0
      if img then
        local per = live.tilesPerRow or 16
        local iw, ih = img:getDimensions()
        local shaded = (not live.trueColor) and Preview.pushPaletteShader(S, palName)
        love.graphics.setColor(1, 1, 1, 1)
        if type(tid) == "number" and love.graphics.newQuad then
          local q = love.graphics.newQuad(
            (tid % per) * TILE_PX, math.floor(tid / per) * TILE_PX,
            TILE_PX, TILE_PX, iw, ih)
          love.graphics.draw(img, q, cx, cy, 0, cell / TILE_PX, cell / TILE_PX)
        end
        if shaded then Preview.popPaletteShader(shaded) end
      else
        Theme.col(PAL.rowBg, 1)
        love.graphics.rectangle("fill", cx, cy, cell, cell)
      end
      local selected = S.gfxBlockCell == ci
      love.graphics.setColor(selected and 0.3 or 1, selected and 0.85 or 1,
        selected and 1 or 1, selected and 1 or 0.35)
      love.graphics.rectangle("line", cx, cy, cell, cell)
      Kit.text("micro", tostring(tid), cx + 2 * s, cy + 2 * s, PAL.heading)
      if Kit.press(cx, cy, cell, cell) then
        S.gfxBlockCell = ci
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  y = y + 4 * (cell + 2 * s) + 8 * s

  if S.gfxBlockCell then
    Kit.text("micro", "Pick a tile from the sheet below for cell "
      .. tostring(S.gfxBlockCell), x, y, PAL.yellow)
    y = y + 14 * s
    y = drawTileFlagPainter(S, App, live, ensureFn, id, x, y, w, s, palName, {
      pickOnly = true,
      title = "SHEET (click to set selected block cell)",
      onTileClick = function(tid)
        local e = ensureFn()
        e.blocks = e.blocks or {}
        local b = e.blocks[(S.gfxBlockEditId or 0) + 1]
        if type(b) ~= "table" then return end
        b[S.gfxBlockCell] = tid
        syncTilesetLive(S, id, e)
        App.markDirty()
      end,
    })
  end
  return y
end

-- ---- Gold palette contexts (GBC tables, not flat SGB names) ----

local GEN2_PAL_CONTEXTS = {
  { id = "pokemon", label = "Pokemon", tip = "Species normal + shiny (4 GBC colors)" },
  { id = "trainers", label = "Trainers", tip = "Trainer class pics (2 colors)" },
  { id = "objects", label = "OW OBJ", tip = "Overworld OBJ rows per time of day" },
  { id = "bg", label = "BG", tip = "BG palette rows (4 colors)" },
  { id = "roofs", label = "Roofs", tip = "Town roof pairs" },
  { id = "hpBar", label = "HP bar", tip = "HP bar colours" },
  { id = "battleObjects", label = "Battle OBJ", tip = "Battle object palettes" },
  { id = "expBar", label = "EXP", tip = "EXP bar colours" },
}

local function cloneColorRow(row, n)
  n = n or (type(row) == "table" and #row) or 2
  local out = {}
  for i = 1, n do
    local c = (type(row) == "table" and row[i]) or { 0, 0, 0 }
    if c.r then out[i] = { c.r, c.g, c.b }
    else out[i] = { c[1] or 0, c[2] or 0, c[3] or 0 } end
  end
  return out
end

local function cloneMonRow(row)
  if type(row) == "table" and row[3] and row[4] then
    return cloneColorRow(row, 4)
  end
  local mid = cloneColorRow(row, 2)
  return { { 255, 255, 255 }, mid[1], mid[2], { 0, 0, 0 } }
end

local function gen2PalRoot(S)
  return (S.data and (S.data.palettes or S.data.gen2Palettes)) or {}
end

local function gen2EntryIds(S, ctx)
  local root = gen2PalRoot(S)
  local base = root[ctx]
  local proj = S.project and S.project.palettes and S.project.palettes[ctx]
  local ids, seen = {}, {}
  local function add(id)
    local key = tostring(id)
    if key ~= "" and not seen[key] then
      seen[key] = true
      ids[#ids + 1] = key
    end
  end
  if ctx == "expBar" then
    add("expBar")
    return ids
  end
  if ctx == "bg" and type(base) == "table" then
    for i = 1, #base do add(tostring(i)) end
  elseif ctx == "roofs" and type(base) == "table" then
    for k in pairs(base) do add(tostring(k)) end
  elseif type(base) == "table" then
    for k, v in pairs(base) do
      -- Skip meta / non-row keys (source, generation, …).
      if (type(k) == "string" or type(k) == "number") and type(v) == "table" then
        if ctx ~= "pokemon" or (v.normal or v.shiny) then
          add(k)
        end
      end
    end
  end
  if type(proj) == "table" then
    for k, v in pairs(proj) do
      if (type(k) == "string" or type(k) == "number")
          and (type(v) == "table" or ctx == "expBar") then
        if ctx ~= "pokemon" or type(v) ~= "table" or v.normal or v.shiny then
          add(k)
        end
      end
    end
  end
  table.sort(ids, function(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na < nb end
    return a < b
  end)
  return ids
end

local function gen2ResolveEntry(S, ctx, id)
  local projBucket = S.project and S.project.palettes and S.project.palettes[ctx]
  if ctx == "expBar" then
    if projBucket ~= nil and type(projBucket) == "table" and projBucket[1] then
      return projBucket, true
    end
    return gen2PalRoot(S).expBar, false
  end
  if ctx == "bg" then
    local idx = tonumber(id) or 1
    if type(projBucket) == "table" and projBucket[idx] ~= nil then
      return projBucket[idx], true
    end
    local base = gen2PalRoot(S).bg
    return type(base) == "table" and base[idx] or nil, false
  end
  local key = id
  local num = tonumber(id)
  if ctx == "roofs" and num then key = num end
  if type(projBucket) == "table" and projBucket[key] ~= nil then
    return projBucket[key], true
  end
  if type(projBucket) == "table" and num and projBucket[tostring(num)] ~= nil then
    return projBucket[tostring(num)], true
  end
  local base = gen2PalRoot(S)[ctx]
  local rec
  if type(base) == "table" then
    rec = base[key]
    if rec == nil and num then rec = base[num] or base[tostring(num)] end
  end
  return rec, false
end

local function drawColorSlots(S, App, colors, count, viewX, fy, viewW, s, title, onSet)
  count = count or #colors
  for i = 1, count do
    Kit.text("small", "C" .. i, viewX, fy + 6 * s, PAL.caption)
    local sw = 28 * s
    local c = colors[i] or { 40, 40, 40 }
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
      (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("line", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
    love.graphics.setColor(1, 1, 1, 1)
    if Kit.press(viewX + 36 * s, fy + 2 * s, sw, 24 * s) then
      local slot = i
      ColorWheel.open(S, {
        title = (title or "C") .. slot,
        color = c,
        onChange = function(rgb)
          onSet(slot, {
            math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
            math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
            math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
          })
        end,
        onApply = function(rgb)
          onSet(slot, {
            math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
            math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
            math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
          })
        end,
      })
    end
    local v = RegList.field(App, "g2pal_" .. tostring(title) .. "_" .. i,
      viewX + 36 * s + sw + 8 * s, fy,
      viewW - 36 * s - sw - 8 * s, 28 * s, fmtRgb(colors[i]), "r,g,b")
    local parsed = parseRgb(v, colors[i])
    if fmtRgb(parsed) ~= fmtRgb(colors[i]) then
      onSet(i, parsed)
    end
    fy = fy + 36 * s
  end
  return fy
end

local function drawGen2Palettes(S, x, y, w, h, App, modeY)
  local s = Kit.scale
  S.project.palettes = S.project.palettes or {}
  local ctx = S.gfxPalContext or "pokemon"
  local chipX = x
  for _, c in ipairs(GEN2_PAL_CONTEXTS) do
    local bw = Kit.textWidth("micro", c.label) + 14 * s
    if Kit.chip(chipX, modeY, bw, 22 * s, c.label, ctx == c.id, PAL.yellow,
        nil, c.tip) then
      S.gfxPalContext = c.id
      ctx = c.id
      S.paletteId = nil
    end
    chipX = chipX + bw + 4 * s
  end
  modeY = modeY + 28 * s

  -- expBar/bg are single fixed entries (no per-ID creation makes sense there).
  local canCreate = ctx ~= "expBar" and ctx ~= "bg"

  local ids = gen2EntryIds(S, ctx)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w,
    h - (modeY - y),
    "PALETTES · " .. ctx:upper(), ids, {
      queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "paletteId",
      accent = PAL.yellow,
      isOwned = function(id)
        local _, owned = gen2ResolveEntry(S, ctx, id)
        return owned
      end,
      footerLabel = canCreate and "+ New Palette" or nil,
      onFooter = canCreate and function()
        S.paletteId = "__new__"
      end or nil,
    })

  if not S.paletteId then S.paletteId = shown[1] end
  local id = S.paletteId
  local fh = 28 * s

  -- Create flow: type an ID, defaults get filled in per-context on Create.
  if id == "__new__" then
    Kit.caption(formX, modeY, "NEW " .. ctx:upper() .. " PALETTE")
    Kit.card(formX, listY, formW, listH, 12 * s)
    local viewX = formX + 12 * s
    local fy = listY + 16 * s
    local viewW = formW - 24 * s
    Kit.text("micro",
      "Must match an ID used elsewhere (e.g. a species, trainer class, roof set).",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s
    Kit.text("small", "ID", viewX, fy + 6 * s, PAL.caption)
    S.gfxNewPalId = RegList.field(App, "g2pal_newid", viewX + 60 * s, fy,
      viewW - 60 * s, fh, S.gfxNewPalId or "", "NEW_PALETTE")
    fy = fy + fh + 16 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Create", { kind = "good" }) then
      local nid = tostring(S.gfxNewPalId or "")
        :gsub("^%s+", ""):gsub("%s+$", ""):upper()
      if nid == "" then
        S.status = "Type an ID first"
      else
        S.project.palettes[ctx] = S.project.palettes[ctx] or {}
        local bucket = S.project.palettes[ctx]
        local key = (ctx == "roofs" and tonumber(nid)) or nid

        if bucket[key] ~= nil then
          S.status = tostring(key) .. " already has a " .. ctx .. " palette"
        else
          if ctx == "pokemon" then
            bucket[key] = {
              normal = {
                { 255, 255, 255 }, { 200, 200, 200 }, { 80, 80, 80 }, { 0, 0, 0 },
              },
              shiny  = {
                { 255, 255, 255 }, { 216, 184, 200 }, { 96, 64, 88 }, { 0, 0, 0 },
              },
            }
          elseif ctx == "roofs" then
            bucket[key] = {
              mornDay = { { 248, 80, 80 }, { 120, 16, 16 } },
              nite    = { { 80, 40, 120 }, { 24, 8, 48 } },
            }
          elseif ctx == "objects" then
            local rows = {}
            for i = 1, 8 do
              rows[i] = { { 248, 248, 248 }, { 168, 168, 168 },
                          { 88, 88, 88 }, { 16, 16, 16 } }
            end
            bucket[key] = rows
          elseif ctx == "battleObjects" then
            bucket[key] = { { 248, 248, 248 }, { 168, 168, 168 },
                            { 88, 88, 88 }, { 16, 16, 16 } }
          else
            -- trainers / hpBar: plain 2-colour row
            bucket[key] = { { 248, 248, 248 }, { 16, 16, 16 } }
          end
          S.paletteId = tostring(key)
          S.gfxNewPalId = ""
          App.markDirty()
          S.status = "Added " .. ctx .. " palette: " .. tostring(key)
        end
      end
    end
    if Kit.button(viewX + 150 * s, fy, 100 * s, fh, "Cancel", { kind = "ghost" }) then
      S.paletteId = shown[1]
    end
    return
  end

  local rec, owned = gen2ResolveEntry(S, ctx, id)
  if not id or not rec then
    Kit.emptyBox(formX, listY, formW, listH,
      "No Gold palette data (import ROM cache)")
    return
  end
  Kit.caption(formX, modeY, tostring(id) .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "gfxFormScroll", "g2pal|" .. ctx .. "|" .. tostring(id),
    owned and 44 * s or 12 * s)
  local contentTop = fy

  local function ensureBucket()
    S.project.palettes[ctx] = S.project.palettes[ctx] or {}
    return S.project.palettes[ctx]
  end

  local function ensure()
    if owned then
      if ctx == "expBar" then return S.project.palettes.expBar end
      if ctx == "bg" then
        -- project.palettes.bg is the full row list; id is 1-based index
        local list = S.project.palettes.bg
        local idx = tonumber(id) or 1
        return list and list[idx]
      end
      local bucket = ensureBucket()
      local key = (ctx == "roofs" and tonumber(id)) or id
      return bucket[key] or bucket[id]
    end
    if ctx == "expBar" then
      S.project.palettes.expBar = cloneColorRow(rec, 2)
      owned = true
      App.markDirty()
      return S.project.palettes.expBar
    end
    if ctx == "bg" then
      -- lists must patch as a full array; clone every vanilla row once
      local base = gen2PalRoot(S).bg or {}
      local list = {}
      for i, row in ipairs(base) do list[i] = cloneColorRow(row, 4) end
      local idx = tonumber(id) or 1
      if not list[idx] then list[idx] = cloneColorRow(rec, 4) end
      S.project.palettes.bg = list
      owned = true
      App.markDirty()
      return list[idx]
    end
    local bucket = ensureBucket()
    local key = id
    local num = tonumber(id)
    if ctx == "roofs" and num then key = num end
    if ctx == "pokemon" then
      bucket[key] = {
        normal = cloneMonRow(rec.normal),
        shiny = cloneMonRow(rec.shiny),
      }
    elseif ctx == "roofs" then
      bucket[key] = {
        mornDay = cloneColorRow(rec.mornDay, 2),
        nite = cloneColorRow(rec.nite, 2),
      }
    elseif ctx == "objects" then
      local rows = {}
      for i, row in ipairs(rec) do rows[i] = cloneColorRow(row, 4) end
      bucket[key] = rows
    else
      -- trainers / hpBar / battleObjects: colour row
      local n = (type(rec) == "table" and #rec) or 2
      if n < 2 then n = 2 end
      bucket[key] = cloneColorRow(rec, n)
    end
    owned = true
    App.markDirty()
    return bucket[key]
  end

  if ctx == "pokemon" then
    Kit.text("micro", "normal / shiny — 4 GBC shades (white + mids + black)",
      viewX, fy, PAL.faint)
    fy = fy + 16 * s
    local normal = cloneMonRow((owned and rec.normal) or rec.normal)
    local shiny = cloneMonRow((owned and rec.shiny) or rec.shiny)
    drawPalettePreview(normal, viewX, fy, viewW / 2 - 4 * s, 28 * s, s)
    drawPalettePreview(shiny, viewX + viewW / 2, fy, viewW / 2 - 4 * s, 28 * s, s)
    fy = fy + 36 * s
    Kit.text("small", "Normal", viewX, fy, PAL.caption)
    fy = fy + 16 * s
    fy = drawColorSlots(S, App, normal, 4, viewX, fy, viewW, s, "n", function(slot, rgb)
      local e = ensure()
      e.normal = e.normal or normal
      e.normal[slot] = rgb
      normal[slot] = rgb
      Preview.invalidate()
      App.markDirty()
    end)
    Kit.text("small", "Shiny", viewX, fy, PAL.caption)
    fy = fy + 16 * s
    fy = drawColorSlots(S, App, shiny, 4, viewX, fy, viewW, s, "s", function(slot, rgb)
      local e = ensure()
      e.shiny = e.shiny or shiny
      e.shiny[slot] = rgb
      shiny[slot] = rgb
      Preview.invalidate()
      App.markDirty()
    end)
  elseif ctx == "roofs" then
    local morn = cloneColorRow(rec.mornDay, 2)
    local nite = cloneColorRow(rec.nite, 2)
    Kit.text("small", "Morn/Day", viewX, fy, PAL.caption)
    fy = fy + 16 * s
    fy = drawColorSlots(S, App, morn, 2, viewX, fy, viewW, s, "rm", function(slot, rgb)
      local e = ensure()
      e.mornDay = e.mornDay or morn
      e.mornDay[slot] = rgb
      App.markDirty()
    end)
    Kit.text("small", "Nite", viewX, fy, PAL.caption)
    fy = fy + 16 * s
    fy = drawColorSlots(S, App, nite, 2, viewX, fy, viewW, s, "rn", function(slot, rgb)
      local e = ensure()
      e.nite = e.nite or nite
      e.nite[slot] = rgb
      App.markDirty()
    end)
  elseif ctx == "objects" then
    Kit.text("micro", "8 OBJ rows (PAL_OW_RED … ROCK) · 4 colours each",
      viewX, fy, PAL.faint)
    fy = fy + 16 * s
    local names = SpriteUtil.OW_PALETTES
    for si = 1, 8 do
      local row = cloneColorRow(rec[si], 4)
      Kit.text("micro", names[si] or ("slot " .. si), viewX, fy, PAL.caption)
      fy = fy + 14 * s
      drawPalettePreview(row, viewX, fy, viewW, 22 * s, s)
      fy = fy + 26 * s
      fy = drawColorSlots(S, App, row, 4, viewX, fy, viewW, s, "o" .. si,
        function(slot, rgb)
          local e = ensure()
          e[si] = e[si] or row
          e[si][slot] = rgb
          row[slot] = rgb
          Preview.invalidate()
          App.markDirty()
        end)
    end
  else
    local n = (ctx == "bg" or ctx == "battleObjects") and 4 or 2
    if type(rec) == "table" and #rec > n then n = #rec end
    local colors = cloneColorRow(rec, n)
    drawPalettePreview(colors, viewX, fy, viewW, 36 * s, s)
    fy = fy + 44 * s
    fy = drawColorSlots(S, App, colors, n, viewX, fy, viewW, s, "r", function(slot, rgb)
      local e = ensure()
      if ctx == "expBar" then
        e[slot] = rgb
      else
        e[slot] = rgb
      end
      colors[slot] = rgb
      Preview.invalidate()
      App.markDirty()
    end)
  end

  FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    if ctx == "expBar" or ctx == "bg" then
      S.project.palettes[ctx] = nil
    else
      local bucket = S.project.palettes[ctx]
      if type(bucket) == "table" then
        local key = (ctx == "roofs" and tonumber(id)) or id
        bucket[key] = nil
        bucket[id] = nil
      end
    end
    App.markDirty()
  end
end

function Gfx.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  S.project.palettes = S.project.palettes or {}
  S.project.sprites = S.project.sprites or {}
  S.project.tilesets = S.project.tilesets or {}

  local modeY = RegList.modeChips(S, "gfxMode", MODES, x, y, s)
  local mode = S.gfxMode or "palettes"
  local gen2 = Generation.isGen2(S)

  if mode == "palettes" then
    if gen2 then
      drawGen2Palettes(S, x, y, w, h, App, modeY)
      return
    end
    local proj = S.project.palettes
    local data = (S.data and S.data.palettes and S.data.palettes.palettes) or {}
    local gbcOn = Preview.useGbcPalettes(S)
    if Kit.chip(x, modeY, 120 * s, 22 * s, gbcOn and "GBC ON" or "GBC OFF",
        gbcOn, PAL.yellow, nil,
        gbcOn and "List/resolve GBC pack palettes"
          or "ROM/cache SGB palettes only") then
      Preview.setUseGbcPalettes(S, not gbcOn)
      S.status = (not gbcOn)
        and "GBC palettes ON — pokered-gbc pack colors"
        or "GBC palettes OFF — ROM/cache SGB colors"
    end
    modeY = modeY + 28 * s
    local ids = Preview.paletteIds(S)
    local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
      "PALETTES", ids, {
        queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "paletteId",
        accent = PAL.yellow,
        isOwned = function(id) return proj[id] ~= nil end,
        footerLabel = "+ New palette",
        onFooter = function()
          local nid = "MOD_PAL"
          local n = 1
          local known = {}
          for _, pid in ipairs(Preview.paletteIds(S)) do known[pid] = true end
          while proj[nid] or data[nid] or known[nid] do
            n = n + 1; nid = "MOD_PAL_" .. n
          end
          proj[nid] = {
            colors = {
              { 248, 248, 248 }, { 168, 168, 168 },
              { 88, 88, 88 }, { 16, 16, 16 },
            },
            _isNew = true,
          }
          S.paletteId = nid
          App.markDirty()
        end,
      })
    if not S.paletteId then S.paletteId = shown[1] end
    local id = S.paletteId
    local owned = id and proj[id] ~= nil
    local rec = owned and proj[id] or data[id]
    if not rec and id then
      -- GBC/Yellow pack-only entry: synthesize a read-only view until edited.
      local cols = Preview.paletteColors(S, id)
      if cols then rec = { colors = cols } end
    end
    if not id or not rec then
      Kit.emptyBox(formX, listY, formW, listH, "No palettes")
      return
    end
    Kit.caption(formX, modeY, id .. (owned and "" or "  (vanilla)"))
    local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
      "gfxFormScroll", "pal|" .. id, owned and 44 * s or 12 * s)
    local contentTop = fy
    local colors = normalizeColors(rec) or {
      { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
    }
    drawPalettePreview(colors, viewX, fy, viewW, 36 * s, s)
    fy = fy + 44 * s
    local function ensure()
      if owned then return proj[id] end
      proj[id] = { colors = colors, _isNew = false }
      owned = true
      App.markDirty()
      return proj[id]
    end
    for i = 1, 4 do
      Kit.text("small", "C" .. i, viewX, fy + 6 * s, PAL.caption)
      local sw = 28 * s
      local c = colors[i] or { 40, 40, 40 }
      love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
        (c[3] or 0) / 255, 1)
      love.graphics.rectangle("fill", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
      love.graphics.setColor(1, 1, 1, 0.35)
      love.graphics.rectangle("line", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
      love.graphics.setColor(1, 1, 1, 1)
      if Kit.press(viewX + 36 * s, fy + 2 * s, sw, 24 * s) then
        local slot = i
        ColorWheel.open(S, {
          title = "C" .. slot .. " · " .. tostring(id),
          color = c,
          onChange = function(rgb)
            local e = ensure()
            e.colors = e.colors or colors
            e.colors[slot] = {
              math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
            }
            colors[slot] = e.colors[slot]
            Preview.invalidate()
          end,
          onApply = function(rgb)
            local e = ensure()
            e.colors = e.colors or colors
            e.colors[slot] = {
              math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
            }
            colors[slot] = e.colors[slot]
            Preview.invalidate()
          end,
        })
      end
      local v = RegList.field(App, "pal_c_" .. i, viewX + 36 * s + sw + 8 * s, fy,
        viewW - 36 * s - sw - 8 * s, 28 * s, fmtRgb(colors[i]), "r,g,b")
      local parsed = parseRgb(v, colors[i])
      if fmtRgb(parsed) ~= fmtRgb(colors[i]) then
        local e = ensure()
        e.colors = e.colors or colors
        e.colors[i] = parsed
        colors[i] = parsed
        Preview.invalidate()
      end
      fy = fy + 36 * s
    end
    FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
    if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
        "Revert", { kind = "danger" }) then
      proj[id] = nil; App.markDirty()
    end
    return
  end

  if mode == "sprites" then
    local proj = S.project.sprites
    local data = (S.data and S.data.sprites) or {}
    local ids = RegList.mergeIds(proj, data)
    local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
      "SPRITES", ids, {
        queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "spriteEditId",
        accent = PAL.green,
        isOwned = function(id) return proj[id] ~= nil end,
        footerLabel = "+ New sprite",
        onFooter = function()
          local nid = SpriteUtil.createNew(S)
          if nid then
            S.spriteEditId = nid
            App.markDirty()
          end
        end,
      })
    if not S.spriteEditId then S.spriteEditId = shown[1] end
    local id = S.spriteEditId
    local owned = id and proj[id] ~= nil
    local rec = owned and proj[id] or data[id]
    if not id or not rec then
      Kit.emptyBox(formX, listY, formW, listH, "No sprites")
      return
    end
    local function ensure()
      if owned then return proj[id] end
      local copy = {}
      for k, v in pairs(rec) do copy[k] = v end
      copy._isNew = false
      proj[id] = copy
      owned = true
      App.markDirty()
      return copy
    end
    Kit.caption(formX, modeY, id .. (owned and "" or "  (vanilla)"))
    local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
      "gfxFormScroll", "spr|" .. id, owned and 44 * s or 12 * s)
    local contentTop = fy
    local prev = 64 * s
    -- Overworld sprites: Gen1 SGB paletteSource; Gold PAL_OW_* / paletteId.
    local sprPal = nil
    local sprPalColors = nil
    if not rec.trueColor then
      if gen2 then
        sprPalColors = Preview.gen2ObjectPalette(S, rec.palette or rec.paletteId)
        sprPal = sprPalColors
      else
        local src = rec.paletteSource
        if type(src) == "string" and src ~= "" and Preview.paletteColors(S, src) then
          sprPal = src
        else
          sprPal = "MEWMON"
        end
      end
    end
    SpriteAnimPreview.drawStand(S, rec, viewX + viewW - prev, fy, prev)
    if sprPalColors then
      Preview.drawSwatches(sprPalColors,
        viewX + viewW - prev, fy + prev + 4 * s, prev, 12 * s)
    elseif type(sprPal) == "string" then
      Preview.drawNamedSwatches(S, sprPal,
        viewX + viewW - prev, fy + prev + 4 * s, prev, 12 * s)
    end
    local labelW = 110 * s
    local fh = 28 * s
    local fieldW = viewW - labelW - prev - 12 * s
    local function row(label, body)
      Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
      body(viewX + labelW, fy, fieldW, fh)
      fy = fy + fh + 8 * s
    end
    row("Image", function(fx, fy_, fw, fh_)
      Kit.text("micro", Kit.ellipsize("micro", tostring(rec.image or ""), fw - 100 * s),
        fx, fy_ + 8 * s, PAL.muted)
      if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
          kind = "ghost", tooltip = "Import overworld sprite PNG",
        }) then
        local sid = id
        App.pickFile("Sprite PNG", "PNG (*.png)|*.png|All|*.*",
          function(picked)
            State.ensureProjectFields(S.project)
            local e = S.project.sprites[sid]
            if not e then
              e = {}
              for k, v in pairs(rec) do e[k] = v end
              e._isNew = false
              S.project.sprites[sid] = e
            end
            App.importToMod(picked, nil, function(rel)
              e.image = rel
              -- Full-color PNG imports usually need TrueColor.
              e.trueColor = true
              Preview.invalidate()
              App.markDirty()
            end)
          end)
      end
    end)
    row("Frames", function(fx, fy_, fw, fh_)
      local cur = rec.frames or 1
      local v = RegList.num(App, "spr_fr", fx, fy_, 60 * s, fh_, cur)
      v = math.max(1, math.min(16, v))
      if v ~= cur then ensure().frames = v end
    end)
    row("Walker", function(fx, fy_, fw, fh_)
      local on = rec.walker and true or false
      if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.green) then
        ensure().walker = not on
        App.markDirty()
      end
    end)
    row("TrueColor", function(fx, fy_, fw, fh_)
      local on = rec.trueColor and true or false
      if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow,
          nil, "YES = raw PNG colors (skip palette remap)") then
        local e = ensure()
        e.trueColor = not on
        if not e.trueColor then e.trueColor = nil end
        Preview.invalidate()
        App.markDirty()
      end
      Kit.text("micro", on and "raw PNG" or (gen2 and "OBJ remap" or "SGB remap"),
        fx + 90 * s, fy_ + 8 * s, PAL.faint)
    end)
    if gen2 then
      row("Palette", function(fx, fy_, fw, fh_)
        if rec.trueColor then
          Kit.text("small", "(ignored — TrueColor)", fx, fy_ + 6 * s, PAL.faint)
          return
        end
        local cur = rec.palette or "PAL_OW_RED"
        ChoicePicker.field(S, {
          x = fx, y = fy_, w = math.min(fw, 160 * s), h = fh_,
          current = cur,
          ids = SpriteUtil.OW_PALETTES,
          emptyLabel = "PAL_OW_RED",
          title = "OW PALETTE",
          tooltip = "Pick PAL_OW_*",
          onPick = function(id)
            if type(id) ~= "string" or id == "" then return end
            local e = ensure()
            e.palette = id
            local idx
            for i, name in ipairs(SpriteUtil.OW_PALETTES) do
              if name == id then idx = i - 1; break end
            end
            if idx then e.paletteId = idx end
            Preview.invalidate()
            App.markDirty()
          end,
        })
        if sprPalColors then
          Preview.drawSwatches(sprPalColors, fx + fw - 80 * s,
            fy_ + (fh_ - 14 * s) / 2, 80 * s, 14 * s)
        end
      end)
      row("Palette id", function(fx, fy_, fw, fh_)
        local cur = tonumber(rec.paletteId) or 0
        local v = RegList.num(App, "spr_pid", fx, fy_, 60 * s, fh_, cur)
        v = math.max(0, math.min(7, math.floor(v)))
        if v ~= cur then
          local e = ensure()
          e.paletteId = v
          e.palette = SpriteUtil.OW_PALETTES[v + 1] or e.palette
          Preview.invalidate()
          App.markDirty()
        end
      end)
      row("Sprite type", function(fx, fy_, fw, fh_)
        local cur = rec.spriteType or "WALKING_SPRITE"
        ChoicePicker.field(S, {
          x = fx, y = fy_, w = math.min(fw, 180 * s), h = fh_,
          current = cur,
          ids = SpriteUtil.SPRITE_TYPES,
          emptyLabel = "WALKING_SPRITE",
          title = "SPRITE TYPE",
          tooltip = "Walk / stand / still / Pokémon sheet",
          onPick = function(id)
            if type(id) ~= "string" or id == "" then return end
            ensure().spriteType = id
            App.markDirty()
          end,
        })
      end)
    else
      row("Palette src", function(fx, fy_, fw, fh_)
        if rec.trueColor then
          Kit.text("small", "(ignored — TrueColor)", fx, fy_ + 6 * s, PAL.faint)
          return
        end
        PalettePicker.row(S, {
          x = fx, y = fy_, w = fw, h = fh_,
          current = rec.paletteSource or "",
          effective = type(sprPal) == "string" and sprPal or nil,
          emptyLabel = "(MEWMON)",
          clearLabel = "(MEWMON default)",
          allowClear = true,
          title = "SPRITE PALETTE",
          tooltip = "SGB palette for this overworld sheet",
          onPick = function(id)
            local e = ensure()
            e.paletteSource = id
            Preview.invalidate()
            App.markDirty()
          end,
          owner = {
            kind = "sprite",
            entityId = id,
            entityLabel = id,
            assign = function(palId)
              local e = ensure()
              e.paletteSource = palId
              Preview.invalidate()
              App.markDirty()
            end,
          },
        })
      end)
    end
    fy = fy + 4 * s
    fy = SpriteAnimPreview.draw(S, rec, viewX, fy, viewW, {
      prefix = "gfxSpriteAnim", s = s, title = "Sprite animation",
    })
    fy = fy + 8 * s
    fy = SpriteAnimPreview.drawStrip(S, rec, viewX, fy, 40 * s, s)
    FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
    if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
        "Revert", { kind = "danger" }) then
      proj[id] = nil
      SpriteUtil.invalidateIdCache(S)
      if S.spriteEditId == id then S.spriteEditId = nil end
      App.markDirty()
    end
    return
  end

  -- tilesets (full editor: image, flags, blocks)
  local proj = S.project.tilesets
  -- Gold keeps records on gen2Tilesets; overlay so the list is not empty.
  local data = Generation.dataTilesets(S)
  local ids = {}
  do
    local merged = RegList.mergeIds(proj, data)
    for _, tid in ipairs(merged) do
      local rec = proj[tid] or data[tid]
      -- Gold ships anim frame sheets beside TILESET_* records; skip junk keys.
      if type(rec) == "table" and (rec.blocks or rec.collision or rec.image) then
        ids[#ids + 1] = tid
      end
    end
  end

  local function blankCollision(n)
    local c = {}
    for i = 1, n do c[i] = { 0xff, 0xff, 0xff, 0xff } end
    return c
  end

  local function createBlankTileset()
    local nid = gen2 and "TILESET_MOD" or "MOD_TILES"
    local n = 1
    while proj[nid] or data[nid] do
      n = n + 1
      nid = (gen2 and "TILESET_MOD_" or "MOD_TILES_") .. n
    end
    local blockCount = gen2 and 128 or 16
    local blocks = {}
    for i = 1, blockCount do
      local row = {}
      for j = 1, 16 do row[j] = 0 end
      blocks[i] = row
    end
    local e
    if gen2 then
      e = {
        id = nid,
        image = "assets/tilesets/" .. nid:lower() .. ".png",
        tilesPerRow = 16, blocks = blocks,
        collision = blankCollision(blockCount),
        generation = 2, _isNew = true,
      }
    else
      e = {
        id = nid,
        image = "assets/tilesets/" .. nid:lower() .. ".png",
        tilesPerRow = 16, blocks = blocks, walkable = { 1 },
        waterTiles = {}, shoreTiles = {},
        doorTiles = {}, warpTiles = {}, counterTiles = {},
        animation = "TILEANIM_NONE", _isNew = true,
      }
    end
    proj[nid] = e
    syncTilesetLive(S, nid, e)
    S.tilesetEditId = nid
    S.gfxTilesetPane = "flags"
    App.markDirty()
    S.status = "Created " .. nid .. " — Browse a PNG, then paint flags / blocks"
  end

  local function createTilesetFromPng()
    App.pickFile("Tileset PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
      function(picked)
        State.ensureProjectFields(S.project)
        local base = App.assetBaseName(picked, "tiles.png")
        if not base:lower():match("%.png$") then base = base .. ".png" end
        local stem = base:gsub("%.[Pp][Nn][Gg]$", ""):gsub("[^%w_]", "_"):upper()
        if stem == "" then stem = gen2 and "TILESET_MOD" or "MOD_TILES" end
        if gen2 and not stem:match("^TILESET_") then stem = "TILESET_" .. stem end
        local nid, n = stem, 1
        while proj[nid] or data[nid] do
          n = n + 1
          nid = stem .. "_" .. n
        end
        App.importToMod(picked, "assets/tilesets/" .. base, function(rel)
          local e
          if gen2 then
            e = {
              id = nid, image = rel, tilesPerRow = 16, blocks = {},
              collision = {}, generation = 2, _isNew = true,
            }
          else
            e = {
              id = nid, image = rel, tilesPerRow = 16, blocks = {},
              walkable = { 1 }, waterTiles = {}, shoreTiles = {},
              doorTiles = {}, warpTiles = {}, counterTiles = {},
              animation = "TILEANIM_NONE", _isNew = true,
            }
          end
          local img = Preview.image(S, rel)
          if img then rebuildBlocksFromSheet(e, img) end
          if gen2 then
            local nBlocks = math.max(128, #(e.blocks or {}))
            e.collision = blankCollision(nBlocks)
          end
          proj[nid] = e
          syncTilesetLive(S, nid, e)
          S.tilesetEditId = nid
          S.gfxTilesetPane = "flags"
          App.markDirty()
          S.status = "Imported tileset " .. nid
        end)
      end)
  end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
    "TILESETS", ids, {
      queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "tilesetEditId",
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
      footerLabel = "+ New blank",
      onFooter = createBlankTileset,
    })
  -- Second create action above the list footer area (form column).
  if Kit.button(formX + formW - 132 * s, modeY, 128 * s, 26 * s, "New from PNG", {
      kind = "accent", font = "small",
      tooltip = "Import a PNG into assets/tilesets/ and build blocks",
    }) then
    createTilesetFromPng()
  end
  if not S.tilesetEditId then S.tilesetEditId = shown[1] end
  local id = S.tilesetEditId
  local owned = id and proj[id] ~= nil
  local rec = owned and proj[id] or data[id]
  if not id or not rec then
    Kit.emptyBox(formX, listY, formW, listH, "No tilesets — New blank or New from PNG")
    return
  end
  local function ensure()
    if owned then return proj[id] end
    local copy = {}
    for k, v in pairs(rec) do
      if k == "walkable" or k == "doorTiles" or k == "warpTiles"
          or k == "counterTiles" or k == "waterTiles" or k == "shoreTiles"
          or k == "tilePalettes" then
        copy[k] = cloneNumList(v)
      elseif k == "collision" and type(v) == "table" then
        -- Gold COLL_* quads: deep-copy so GFX paint does not mutate vanilla.
        local c = {}
        for i, quad in ipairs(v) do
          if type(quad) == "table" then
            c[i] = { quad[1], quad[2], quad[3], quad[4] }
          else
            c[i] = quad
          end
        end
        copy.collision = c
      elseif k == "blocks" and type(v) == "table" then
        local b = {}
        for i, row in ipairs(v) do
          local r = {}
          for j = 1, #row do r[j] = row[j] end
          b[i] = r
        end
        copy.blocks = b
      else
        copy[k] = v
      end
    end
    copy.waterTiles = copy.waterTiles or {}
    copy.shoreTiles = copy.shoreTiles or {}
    copy.doorTiles = copy.doorTiles or {}
    copy.warpTiles = copy.warpTiles or {}
    copy.counterTiles = copy.counterTiles or {}
    copy._isNew = false
    proj[id] = copy
    owned = true
    syncTilesetLive(S, id, copy)
    App.markDirty()
    return copy
  end

  local function editList(key, value)
    local e = ensure()
    e[key] = value
    syncTilesetLive(S, id, e)
  end
  Kit.caption(formX, modeY, "TILESET EDITOR · " .. id)
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "gfxFormScroll", "ts|" .. id, owned and 44 * s or 12 * s)
  local contentTop = fy
  local ownershipLabel, ownershipHelp, ownershipColor
  if not owned then
    ownershipLabel = "RUNTIME REFERENCE"
    ownershipHelp = "Read-only data from the selected ROM · editing creates a custom replacement"
    ownershipColor = PAL.blue
  elseif rec._isNew then
    ownershipLabel = "CUSTOM TILESET"
    ownershipHelp = "Mod-owned tileset · image and metadata are saved with this project"
    ownershipColor = PAL.green
  else
    ownershipLabel = "CUSTOM REPLACEMENT"
    ownershipHelp = "Mod-owned override of runtime tileset " .. id
    ownershipColor = PAL.yellow
  end
  Kit.text("small", ownershipLabel, viewX, fy, ownershipColor)
  Kit.text("micro", Kit.ellipsize("micro", ownershipHelp, viewW),
    viewX, fy + 18 * s, PAL.muted)
  fy = fy + 40 * s
  local prev = 72 * s
  local tsPals = (not gen2) and Preview.paletteIds(S) or {}
  if not gen2 then
    if not S.gfxTilesetPalPreview or not Preview.paletteColors(S, S.gfxTilesetPalPreview) then
      S.gfxTilesetPalPreview = (#tsPals > 0 and tsPals[1]) or "ROUTE"
    end
  end
  local tsPal = (not gen2) and S.gfxTilesetPalPreview or nil
  Preview.draw(S, rec.image, viewX + viewW - prev, fy, prev, prev,
    (not rec.trueColor) and tsPal or nil)
  if not gen2 and not rec.trueColor and tsPal then
    Preview.drawNamedSwatches(S, tsPal,
      viewX + viewW - prev, fy + prev + 4 * s, prev, 12 * s)
  end
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - prev - 12 * s
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  -- Flags vs Blocks pane switch
  S.gfxTilesetPane = S.gfxTilesetPane or "flags"
  do
    local pane = S.gfxTilesetPane
    if Kit.chip(viewX, fy, 70 * s, 22 * s, "Flags", pane == "flags", PAL.green,
        nil, gen2 and "Paint COLL_* quads on metatiles"
          or "Paint walk/solid/water/door/warp/counter on the sheet") then
      S.gfxTilesetPane = "flags"
    end
    if Kit.chip(viewX + 76 * s, fy, 70 * s, 22 * s, "Blocks", pane == "blocks", PAL.blue,
        nil, "Compose 4×4 blocks from sheet tiles") then
      S.gfxTilesetPane = "blocks"
    end
    Kit.text("micro", string.format("%d blocks", #(rec.blocks or {})),
      viewX + 156 * s, fy + 4 * s, PAL.faint)
    fy = fy + 28 * s
  end

  if not gen2 and not rec.trueColor then
    row("Preview pal", function(fx, fy_, fw, fh_)
      if Kit.button(fx, fy_, math.min(fw, 160 * s), fh_,
          Kit.ellipsize("small", tsPal, math.min(fw, 160 * s) - 8 * s),
          { kind = "ghost", tooltip = "Cycle SGB palette used for this PNG preview" })
          and #tsPals > 0 then
        local idx = 1
        for i, pid in ipairs(tsPals) do
          if pid == tsPal then idx = i; break end
        end
        S.gfxTilesetPalPreview = tsPals[(idx % #tsPals) + 1]
      end
      Preview.drawNamedSwatches(S, S.gfxTilesetPalPreview,
        fx + fw - 80 * s, fy_ + (fh_ - 14 * s) / 2, 80 * s, 14 * s)
    end)
  end
  if not gen2 and Preview.useGbcPalettes(S) and Preview.hasTilesetGbcGroups(S, id) then
    local names = Preview.GBC_GROUP_NAMES
    local groups = Preview.tilesetGbcGroups(S, id)
    local ownedGbc = Preview.tilesetGbcGroupsOwned(S, id)
    Kit.text("micro", "GBC BG groups"
        .. (ownedGbc and " (mod)" or " (vanilla)"),
      viewX, fy, PAL.caption)
    fy = fy + 14 * s
    local sw = 20 * s
    local gap = 3 * s
    for gi = 1, 8 do
      local label = names[gi] or ("G" .. (gi - 1))
      Kit.text("micro", label, viewX, fy + 4 * s, PAL.muted)
      local g = groups and groups[gi]
      local bx = viewX + 48 * s
      for ci = 1, 4 do
        local c = (g and g[ci]) or { 40, 40, 40 }
        local sx = bx + (ci - 1) * (sw + gap)
        love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
          (c[3] or 0) / 255, 1)
        love.graphics.rectangle("fill", sx, fy, sw, 18 * s, 3 * s, 3 * s)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.rectangle("line", sx, fy, sw, 18 * s, 3 * s, 3 * s)
        love.graphics.setColor(1, 1, 1, 1)
        if Kit.press(sx, fy, sw, 18 * s) then
          local groupI, colorI, tid = gi, ci, id
          ColorWheel.open(S, {
            title = label .. " C" .. colorI .. " · " .. tostring(tid),
            color = c,
            onChange = function(rgb)
              Preview.ensureTilesetGbcGroups(S, tid)
              local ow = S.project.gbcWorld.groupColors[tid]
              if ow and ow[groupI] then
                ow[groupI][colorI] = {
                  math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
                }
              end
              App.markDirty()
            end,
            onApply = function(rgb)
              Preview.setTilesetGbcGroupColor(S, tid, groupI, colorI, rgb)
              App.markDirty()
              S.status = "GBC " .. label .. " C" .. colorI .. " updated"
            end,
          })
        end
      end
      fy = fy + 22 * s
    end
    if ownedGbc then
      if Kit.button(viewX, fy, 100 * s, fh, "Revert GBC", {
          kind = "danger",
          tooltip = "Clear mod overrides for this tileset's 8 BG groups",
        }) then
        Preview.clearTilesetGbcGroups(S, id)
        App.markDirty()
      end
      fy = fy + fh + 8 * s
    else
      fy = fy + 6 * s
    end
  end
  row("Image", function(fx, fy_, fw, fh_)
    Kit.text("micro", Kit.ellipsize("micro", tostring(rec.image or ""), fw - 100 * s),
      fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 128 * s, fy_, 128 * s, fh_,
        owned and "Replace PNG" or "Replace in mod", {
        kind = owned and "ghost" or "accent",
        tooltip = owned
          and "Replace this mod-owned PNG in assets/tilesets/"
          or "Create a custom replacement and copy its PNG into this mod",
      }) then
      local tid = id
      App.pickFile("Tileset PNG", "PNG (*.png)|*.png|All|*.*",
        function(picked)
          State.ensureProjectFields(S.project)
          local e = S.project.tilesets[tid]
          if not e then e = ensure() end
          local base = App.assetBaseName(picked, "tiles.png")
          if not base:lower():match("%.png$") then base = base .. ".png" end
          App.importToMod(picked, "assets/tilesets/" .. base, function(rel)
            e.image = rel
            local img = Preview.image(S, rel)
            if img then
              e.imageWidth = img:getWidth()
              e.imageHeight = img:getHeight()
              if not e.blocks or #e.blocks == 0 then
                rebuildBlocksFromSheet(e, img)
              end
            end
            syncTilesetLive(S, tid, e)
          end)
        end)
    end
  end)
  if gen2 then
    row("Anim", function(fx, fy_, fw, fh_)
      local anim = rec.anim
      local label = "(none)"
      if type(anim) == "table" then
        label = string.format("program (%d keys)",
          (function()
            local n = 0
            for _ in pairs(anim) do n = n + 1 end
            return n
          end)())
      end
      Kit.text("micro", label, fx, fy_ + 8 * s, PAL.muted)
    end)
  else
    row("Animation", function(fx, fy_, fw, fh_)
      local cur = tostring(rec.animation or "TILEANIM_NONE")
      local mx = fx
      for _, anim in ipairs(TILE_ANIMS) do
        local label = anim:gsub("^TILEANIM_", "")
        local bw = Kit.textWidth("micro", label) + 12 * s
        if Kit.chip(mx, fy_ + 2 * s, bw, fh_ - 4 * s, label, cur == anim, PAL.blue) then
          local e = ensure()
          e.animation = anim
          syncTilesetLive(S, id, e)
          App.markDirty()
        end
        mx = mx + bw + 3 * s
      end
    end)
  end
  row("TrueColor", function(fx, fy_, fw, fh_)
    local on = rec.trueColor and true or false
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      local e = ensure()
      e.trueColor = not on
      if not e.trueColor then e.trueColor = nil end
      syncTilesetLive(S, id, e)
      App.markDirty()
    end
  end)

  rec = owned and proj[id] or rec
  if S.gfxTilesetPane == "blocks" then
    fy = drawBlockEditor(S, App, rec, ensure, id, viewX, fy, viewW, s, tsPal)
  else
    if Generation.isGen2(S) then
      Kit.text("micro",
        "Gold uses COLL_* quads (paint below). Gen1 walkable/door CSV lists are unused.",
        viewX, fy, PAL.faint)
      fy = fy + 18 * s
    else
    -- Compact CSV lists (advanced) above the painter
    row("Walkable", function(fx, fy_, fw, fh_)
      local cur = joinNums(rec.walkable)
      local v = RegList.field(App, "ts_walk", fx, fy_, fw, fh_, cur, "1,16,19")
      if v ~= cur then editList("walkable", csvNums(v)) end
    end)
    row("Grass tile", function(fx, fy_, fw, fh_)
      local cur = rec.grassTile ~= nil and tostring(rec.grassTile) or ""
      local v = RegList.field(App, "ts_grass", fx, fy_, fw, fh_, cur, "82")
      if v ~= cur then
        local e = ensure()
        e.grassTile = tonumber(v)
        syncTilesetLive(S, id, e)
      end
    end)
    row("Water / Shore", function(fx, fy_, fw, fh_)
      local half = math.floor((fw - 6 * s) / 2)
      local curW = joinNums(rec.waterTiles)
      local vW = RegList.field(App, "ts_water", fx, fy_, half, fh_, curW, "20")
      if vW ~= curW then editList("waterTiles", csvNums(vW)) end
      local curS = joinNums(rec.shoreTiles)
      local vS = RegList.field(App, "ts_shore", fx + half + 6 * s, fy_, half, fh_, curS, "50")
      if vS ~= curS then editList("shoreTiles", csvNums(vS)) end
    end)
    row("Door / Warp", function(fx, fy_, fw, fh_)
      local half = math.floor((fw - 6 * s) / 2)
      local curD = joinNums(rec.doorTiles)
      local vD = RegList.field(App, "ts_door", fx, fy_, half, fh_, curD, "27")
      if vD ~= curD then editList("doorTiles", csvNums(vD)) end
      local curW = joinNums(rec.warpTiles)
      local vW = RegList.field(App, "ts_warp", fx + half + 6 * s, fy_, half, fh_, curW, "19")
      if vW ~= curW then editList("warpTiles", csvNums(vW)) end
    end)
    row("Counter", function(fx, fy_, fw, fh_)
      local cur = joinNums(rec.counterTiles)
      local v = RegList.field(App, "ts_ctr", fx, fy_, fw, fh_, cur, "18")
      if v ~= cur then editList("counterTiles", csvNums(v)) end
    end)
    end
    rec = owned and proj[id] or rec
    fy = drawTileFlagPainter(S, App, rec, ensure, id, viewX, fy, viewW, s, tsPal)
  end
  FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 152 * s, 32 * s,
      rec._isNew and "Delete custom" or "Remove replacement", { kind = "danger" }) then
    local dropped = proj[id]
    proj[id] = nil
    if S.data and S.data.tilesets and S.data.tilesets[id] == dropped then
      local bak = S._vanillaTilesetBackup and S._vanillaTilesetBackup[id]
      S.data.tilesets[id] = bak
    elseif S.data and S.data.tilesets and type(S.data.tilesets[id]) == "table"
        and S.data.tilesets[id]._isNew then
      S.data.tilesets[id] = nil
    end
    if S.tilesetEditId == id then S.tilesetEditId = nil end
    MapLoader.invalidateAll()
    App.markDirty()
  end
end

return Gfx
