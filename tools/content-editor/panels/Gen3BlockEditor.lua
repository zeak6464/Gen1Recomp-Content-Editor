-- GFX > Blocks: the Gen 3 block (metatile) editor.
--
-- Works the way the Gen 1/2 block editor does -- pick a block from the strip,
-- click one of its cells, then click a tile in the sheet -- with the parts a
-- FireRed block adds: two layers of 2x2 tiles (eight slots), a palette and
-- flips on every slot, a layer type and a behaviour.
--
-- No ROM is involved. Tiles come from the block pictures the game already
-- saved when FireRed was imported -- the same data the maps are drawn from --
-- and the project only stores which tile, palette and flip goes where, plus
-- pixels the modder paints (Gen3Blocks, Gen3TileSource).

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local RegList = require("RegList")
local FormPane = require("FormPane")
local Blocks = require("Gen3Blocks")

local M = {}

local LAYER_LABEL = { normal = "Normal", covered = "Covered", split = "Split" }
local LAYER_HELP = {
  normal = "Top layer draws over the player (roofs, tree tops)",
  covered = "Both layers draw under the player",
  split = "Top layer draws over the player",
}
local CORNER = { "top-left", "top-right", "bottom-left", "bottom-right" }

-- Transparent areas get a faint checkerboard, as in any image editor.
local function checker(x, y, w, h, s)
  Theme.col(PAL.rowBg, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  local step = math.max(3, math.floor(4 * s))
  Theme.col(PAL.cardBorder, 0.12)
  for cy = 0, math.ceil(h / step) - 1 do
    for cx = 0, math.ceil(w / step) - 1 do
      if (cx + cy) % 2 == 0 then
        love.graphics.rectangle("fill", x + cx * step, y + cy * step,
          math.min(step, w - cx * step), math.min(step, h - cy * step))
      end
    end
  end
end

-- One slot's tile, with its palette and flips, filling a size x size square.
local function drawSlotTile(S, pair, slot, x, y, size)
  local img = slot.tile and Blocks.tileImage(S, pair, slot.tile, slot.pal)
  if not img then return false end
  local sc = size / 8
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x + (slot.hflip and size or 0), y + (slot.vflip and size or 0), 0,
    slot.hflip and -sc or sc, slot.vflip and -sc or sc)
  return true
end

local function drawBlock(S, pair, mid, def, x, y, size)
  local under, over = Blocks.blockImages(S, pair, mid, def)
  if not under then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(under, x, y, 0, size / 16, size / 16)
  love.graphics.draw(over, x, y, 0, size / 16, size / 16)
end

local function save(S, App, pair, mid, def, message)
  if Blocks.store(S, pair, mid, def) then
    App.markDirty()
    if message then S.status = message end
  end
end

-- Block strip --------------------------------------------------------------

local function drawStrip(S, App, pair, ids, x, y, w)
  local s = Kit.scale
  local thumb, gap = 36 * s, 4 * s
  local perRow = math.max(1, math.floor((w + gap) / (thumb + gap)))
  local totalRows = math.max(1, math.ceil(#ids / perRow))
  local rowsShown = math.min(4, totalRows)
  local maxStart = math.max(0, totalRows - rowsShown)

  -- Buttons along the top.
  local btnH = 24 * s
  if Kit.button(x, y, 104 * s, btnH, "+ New block", { kind = "good", font = "small",
      tooltip = "Add a blank block after this tileset's own blocks" }) then
    local mid, err = Blocks.newBlock(S, pair)
    if mid then
      App.markDirty()
      S.g3BlockId, S.g3BlockSlot = mid, 1
      S.g3BlockStripRow = 1e9 -- new blocks sit at the end; clamped below
      S.status = ("Added block %d"):format(mid)
    else
      S.status = tostring(err)
    end
  end
  if Kit.button(x + 110 * s, y, 96 * s, btnH, "Duplicate", { kind = "ghost", font = "small",
      tooltip = "Copy this block into a new one" }) then
    local def = Blocks.definition(S, pair, S.g3BlockId)
    local mid, err = Blocks.newBlock(S, pair, def)
    if mid then
      App.markDirty()
      S.g3BlockId, S.g3BlockSlot = mid, nil
      S.g3BlockStripRow = 1e9
      S.status = ("Copied into block %d"):format(mid)
    else
      S.status = tostring(err)
    end
  end

  -- Jump to a block id.
  local gx = x + 214 * s
  Kit.text("micro", "GO TO", gx, y + 7 * s, PAL.caption)
  local typed = Kit.textfield("g3blk_goto|" .. pair, gx + 40 * s, y, 70 * s, btnH,
    S.g3BlockGoto or "", "id")
  if typed ~= (S.g3BlockGoto or "") then
    S.g3BlockGoto = typed
    local want = tonumber(typed)
    for i, mid in ipairs(ids) do
      if mid == want then
        S.g3BlockId, S.g3BlockSlot = mid, nil
        S.g3BlockStripRow = math.min(maxStart, math.floor((i - 1) / perRow))
        break
      end
    end
  end

  local startRow = math.max(0, math.min(maxStart, tonumber(S.g3BlockStripRow) or 0))
  if Kit.chip(x + w - 70 * s, y, 32 * s, btnH, "^", false, PAL.blue, nil, "Scroll up")
      and startRow > 0 then
    startRow = startRow - 1
  end
  if Kit.chip(x + w - 34 * s, y, 32 * s, btnH, "v", false, PAL.blue, nil, "Scroll down")
      and startRow < maxStart then
    startRow = startRow + 1
  end
  y = y + btnH + 8 * s

  local stripH = rowsShown * (thumb + gap)
  -- Where the strip is, so M.draw can hand it the wheel next frame before the
  -- form's own scrolling takes it.
  S._g3BlockStripRect = { x = x, y = y, w = w, h = stripH, maxStart = maxStart }
  S.g3BlockStripRow = startRow

  local rows = Blocks.own(S.project, pair) or {}
  Kit.pushClip(x, y, w, stripH)
  local first = startRow * perRow + 1
  local last = math.min(#ids, (startRow + rowsShown) * perRow)
  for i = first, last do
    local mid = ids[i]
    local k = i - first
    local bx = x + (k % perRow) * (thumb + gap)
    local by = y + math.floor(k / perRow) * (thumb + gap)
    Theme.col(PAL.rowBg, 1)
    love.graphics.rectangle("fill", bx, by, thumb, thumb, 3 * s, 3 * s)
    local def = Blocks.definition(S, pair, mid)
    if def then drawBlock(S, pair, mid, def, bx + 2 * s, by + 2 * s, thumb - 4 * s) end
    local mine = rows[tostring(mid)]
    if mine then
      -- green dot: a block this project added; accent dot: an edited ROM block;
      -- red dot: uses a tile the game can't draw
      local bad = def and #(Blocks.problems(S, pair, mid, def) or {}) > 0
      Theme.col(bad and PAL.red or (mine.new and PAL.green or PAL.blue), 1)
      love.graphics.circle("fill", bx + thumb - 5 * s, by + 5 * s, 3.5 * s)
    end
    if mid == S.g3BlockId then
      Theme.col(PAL.blue, 1)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", bx, by, thumb, thumb, 3 * s, 3 * s)
      love.graphics.setLineWidth(1)
    end
    Kit.offerTooltip(bx, by, thumb, thumb, ("Block %d"):format(mid))
    if Kit.press(bx, by, thumb, thumb) then
      S.g3BlockId, S.g3BlockSlot = mid, nil
    end
  end
  Kit.popClip()
  love.graphics.setColor(1, 1, 1, 1)
  y = y + stripH + 2 * s
  Kit.text("micro", ("rows %d-%d of %d  -  scroll with the mouse wheel"):format(
    startRow + 1, startRow + rowsShown, totalRows), x, y, PAL.faint)
  return y + 16 * s
end

-- The block itself ---------------------------------------------------------

local function drawSlotGrid(S, pair, def, firstSlot, x, y, cell, label, bad)
  local s = Kit.scale
  Kit.text("micro", label, x, y, PAL.caption)
  y = y + 14 * s
  for q = 1, 4 do
    local slotIndex = firstSlot + q - 1
    local slot = def.slots[slotIndex]
    local cx = x + ((q - 1) % 2) * (cell + 3 * s)
    local cy = y + math.floor((q - 1) / 2) * (cell + 3 * s)
    checker(cx, cy, cell, cell, s)
    drawSlotTile(S, pair, slot, cx, cy, cell)
    local selected = S.g3BlockSlot == slotIndex
    if bad and bad[slotIndex] and not selected then
      Theme.col(PAL.red, 1)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", cx, cy, cell, cell)
      love.graphics.setLineWidth(1)
    elseif selected then
      Theme.col(PAL.yellow, 1)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", cx, cy, cell, cell)
      love.graphics.setLineWidth(1)
    else
      Theme.col(PAL.cardBorder, 0.45)
      love.graphics.rectangle("line", cx, cy, cell, cell)
    end
    local tag = Blocks.tileLabel(S, pair, slot.tile) .. (slot.hflip and " H" or "") .. (slot.vflip and " V" or "")
    Kit.text("micro", tag, cx + 2 * s, cy + 1 * s, PAL.heading)
    Kit.offerTooltip(cx, cy, cell, cell,
      ("Slot %d: tile %s, palette %d"):format(slotIndex, Blocks.tileLabel(S, pair, slot.tile), slot.pal)
      .. ((bad and bad[slotIndex]) and " -- the game can't draw this tile" or ""))
    if Kit.press(cx, cy, cell, cell) then
      if selected then S.g3BlockSlot = nil else S.g3BlockSlot = slotIndex end
    end
  end
  return y + 2 * (cell + 3 * s)
end

local function drawBlockEditor(S, App, pair, mid, x, y, w)
  local s = Kit.scale
  local def, edited, isNew = Blocks.definition(S, pair, mid)
  if not def then
    Kit.text("small", "This block could not be read.", x, y, PAL.red)
    return y + 24 * s
  end

  -- Title row
  local state = isNew and "new block" or (edited and "edited" or "as in the game")
  local tw = Kit.text("button", ("Block %d"):format(mid), x, y, PAL.heading)
  Kit.text("small", state, x + tw + 10 * s, y + 3 * s,
    isNew and PAL.green or (edited and PAL.blue or PAL.muted))
  if isNew then
    if Kit.button(x + w - 130 * s, y - 2 * s, 130 * s, 24 * s, "Delete block",
        { kind = "danger", font = "small" }) and Blocks.revert(S, pair, mid) then
      App.markDirty()
      S.status = ("Deleted block %d"):format(mid)
      S.g3BlockId, S.g3BlockSlot = nil, nil
      return y + 30 * s
    end
  elseif edited then
    if Kit.button(x + w - 130 * s, y - 2 * s, 130 * s, 24 * s, "Revert",
        { kind = "ghost", font = "small" }) and Blocks.revert(S, pair, mid) then
      App.markDirty()
      S.status = ("Block %d reverted"):format(mid)
    end
  end
  y = y + 30 * s

  -- Tiles the game can't rebuild: say so, and which slots.
  local problems = Blocks.problems(S, pair, mid, def) or {}
  local bad = {}
  for _, i in ipairs(problems) do bad[i] = true end
  if #problems > 0 then
    Kit.text("small", ("Slot%s %s use%s a tile the game can't draw -- in game this block %s until %s changed.")
      :format(#problems > 1 and "s" or "", table.concat(problems, ", "), #problems > 1 and "" or "s",
        isNew and "won't appear" or "stays as it was", #problems > 1 and "they're" or "it's"),
      x, y - 6 * s, PAL.red)
    y = y + 18 * s
  end

  -- Two slot grids, then the composed block and a 3x3 tiling of it.
  local cell = 44 * s
  local gridW = 2 * cell + 3 * s
  local gy = y
  drawSlotGrid(S, pair, def, 1, x, gy, cell, "BOTTOM LAYER", bad)
  drawSlotGrid(S, pair, def, 5, x + gridW + 24 * s, gy, cell, "TOP LAYER", bad)
  local px = x + 2 * (gridW + 24 * s)
  Kit.text("micro", "PREVIEW", px, gy, PAL.caption)
  local pv = 2 * cell + 3 * s
  checker(px, gy + 14 * s, pv, pv, s)
  drawBlock(S, pair, mid, def, px, gy + 14 * s, pv)
  local tx = px + pv + 24 * s
  local rowBottom = gy + 14 * s + pv
  if tx + pv <= x + w then
    Kit.text("micro", "TILED", tx, gy, PAL.caption)
    local t = pv / 3
    for r = 0, 2 do
      for c = 0, 2 do drawBlock(S, pair, mid, def, tx + c * t, gy + 14 * s + r * t, t) end
    end
  end
  -- Painting: the selected slot's tile, when it's one of yours.
  local sel = S.g3BlockSlot and def.slots[S.g3BlockSlot]
  if sel and Blocks.isCustom(sel.tile) then
    local ex = tx + pv + 32 * s
    if ex + 300 * s > x + w then ex = x; rowBottom = rowBottom + 12 * s; gy = rowBottom; rowBottom = nil end
    local bottom = M.drawPixelEditor(S, App, pair, sel, ex, gy, x + w - ex)
    rowBottom = rowBottom and math.max(rowBottom, bottom) or bottom
  end
  y = rowBottom + 12 * s

  -- The selected slot.
  local si = S.g3BlockSlot
  if si and def.slots[si] then
    local slot = def.slots[si]
    Kit.text("micro", ("SLOT %d  -  %s layer, %s"):format(si,
      si <= 4 and "bottom" or "top", CORNER[(si - 1) % 4 + 1]), x, y, PAL.yellow)
    y = y + 16 * s
    Kit.text("small", "Tile " .. Blocks.tileLabel(S, pair, slot.tile), x, y + 5 * s, PAL.text)
    local hflip, hChanged = Kit.checkbox(x + 80 * s, y, 110 * s, 26 * s, slot.hflip, "H-flip")
    local vflip, vChanged = Kit.checkbox(x + 196 * s, y, 110 * s, 26 * s, slot.vflip, "V-flip")
    if hChanged or vChanged then
      slot.hflip, slot.vflip = hflip, vflip
      save(S, App, pair, mid, def)
    end
    if Kit.button(x + 314 * s, y + 1 * s, 96 * s, 24 * s, "Clear slot",
        { kind = "ghost", font = "small", tooltip = "Empty the slot" }) then
      def.slots[si] = { tile = false, pal = 0, hflip = false, vflip = false }
      save(S, App, pair, mid, def)
    end
    if not Blocks.isCustom(slot.tile) and Kit.button(x + 416 * s, y + 1 * s, 130 * s, 24 * s,
        slot.tile and "Paint on a copy" or "Paint a new tile", { kind = "accent", font = "small",
          tooltip = "Make this tile one of yours and edit its pixels" }) then
      if slot.tile and not Blocks.tileAvailable(S, pair, slot.tile) then
        S.status = "This tile can't be copied -- pick one from the sheet first"
      else
        local n, err = Blocks.newTile(S, pair, slot.tile or nil)
        if n then
          slot.tile = n
          save(S, App, pair, mid, def)
          App.markDirty()
          S.status = ("Copied tile to your tile %s -- paint on it on the right"):format(Blocks.tileLabel(S, pair, n))
        else
          S.status = tostring(err)
        end
      end
    end
    y = y + 34 * s
  else
    Kit.text("small", "Click a slot above, then a tile in the sheet below.", x, y, PAL.muted)
    y = y + 24 * s
  end

  -- Palette: the selected slot's, or just the sheet's when no slot is picked.
  local current = (si and def.slots[si]) and def.slots[si].pal or (tonumber(S.g3BlockPal) or 0)
  Kit.text("micro", "PALETTE  (0-6 primary, 7-12 this tileset)", x, y, PAL.caption)
  y = y + 14 * s
  local chipW = 30 * s
  for p = 0, Blocks.PALETTES - 1 do
    if Kit.chip(x + p * (chipW + 3 * s), y, chipW, 22 * s, tostring(p), p == current,
        PAL.blue, nil, "Palette " .. p) then
      S.g3BlockPal = p
      if si and def.slots[si] then
        def.slots[si].pal = p
        save(S, App, pair, mid, def)
      end
      current = p
    end
  end
  y = y + 26 * s
  local colours = Blocks.paletteColours(S, pair, current)
  local sw = 14 * s
  for i = 0, 15 do
    local sx = x + i * (sw + 2 * s)
    if i == 0 then
      checker(sx, y, sw, sw, s)
    else
      local c = colours[i] or { 0, 0, 0 }
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.rectangle("fill", sx, y, sw, sw)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  y = y + sw + 14 * s

  -- Block-wide settings.
  Kit.text("micro", "LAYER TYPE", x, y, PAL.caption)
  y = y + 14 * s
  for i, id in ipairs(Blocks.LAYERS) do
    if Kit.chip(x + (i - 1) * 90 * s, y, 86 * s, 22 * s, LAYER_LABEL[id],
        def.layerType == id, PAL.blue) and def.layerType ~= id then
      def.layerType = id
      save(S, App, pair, mid, def)
    end
  end
  Kit.text("small", LAYER_HELP[def.layerType] or "", x + 280 * s, y + 3 * s, PAL.muted)
  y = y + 30 * s

  Kit.text("micro", "BEHAVIOUR", x, y, PAL.caption)
  y = y + 14 * s
  local value = RegList.num(App, ("g3blk_beh|%s|%d"):format(pair, mid),
    x, y, 80 * s, 26 * s, def.behavior)
  if value ~= def.behavior then
    def.behavior = math.max(0, math.min(511, math.floor(tonumber(value) or 0)))
    save(S, App, pair, mid, def)
  end
  local okNames, Names = pcall(require, "Gen3MetatileBehaviors")
  local label = okNames and Names.label(def.behavior, mid) or ("Behaviour " .. def.behavior)
  Kit.text("small", label, x + 90 * s, y + 5 * s, PAL.detail)
  return y + 40 * s
end

-- Pixel editor -------------------------------------------------------------

-- Paints the selected slot's tile when it is one of yours. Left button
-- paints (click or drag), right button picks a colour; the Pick chip does the
-- same for one click. Colours are the slot's palette; 0 is see-through.
function M.drawPixelEditor(S, App, pair, slot, x, y, w)
  local s = Kit.scale
  local tile = slot.tile
  local t = Blocks.customTile(S.project, pair, tile)
  if not t then
    Kit.text("small", "This tile was deleted.", x, y + 14 * s, PAL.red)
    return y + 40 * s
  end
  local painted = Blocks.paintedCount(S.project, pair, tile)
  Kit.text("micro", ("YOUR TILE %s  -  %s"):format(Blocks.tileLabel(S, pair, tile),
    t.base and ("painted over game tile %s (%d px yours)"):format(Blocks.tileLabel(S, pair, t.base), painted)
      or "drawn from scratch"), x, y, PAL.caption)
  y = y + 14 * s

  local px = Blocks.tilePixels(S, pair, tile) or {}
  local colours = Blocks.paletteColours(S, pair, slot.pal)
  local cell = 20 * s
  local gx, gy = x, y
  checker(gx, gy, cell * 8, cell * 8, s)
  for i = 1, 64 do
    local c = px[i] or 0
    if c ~= 0 then
      local rgb = colours[c] or { 0, 0, 0 }
      love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
      love.graphics.rectangle("fill", gx + ((i - 1) % 8) * cell, gy + math.floor((i - 1) / 8) * cell,
        cell, cell)
    end
  end
  Theme.col(PAL.cardBorder, 0.35)
  for k = 0, 8 do
    love.graphics.line(gx + k * cell, gy, gx + k * cell, gy + 8 * cell)
    love.graphics.line(gx, gy + k * cell, gx + 8 * cell, gy + k * cell)
  end

  -- Brush colour and tool.
  local brush = math.max(0, math.min(15, tonumber(S.g3PaintColour) or 1))
  local picking = S.g3PaintPick == true
  local right = love.mouse and love.mouse.isDown and love.mouse.isDown(2)
  if Kit.hover(gx, gy, cell * 8, cell * 8) then
    local cx = math.floor((Kit.mouseX - gx) / cell)
    local cy = math.floor((Kit.mouseY - gy) / cell)
    local i = cy * 8 + cx + 1
    if cx >= 0 and cx < 8 and cy >= 0 and cy < 8 then
      Theme.col(PAL.yellow, 1)
      love.graphics.rectangle("line", gx + cx * cell, gy + cy * cell, cell, cell)
      if right or (picking and Kit.mouseClicked) then
        S.g3PaintColour, S.g3PaintPick = px[i] or 0, false
      elseif Kit.mouseClicked or Kit.mouseDown then
        if not S._g3PaintBatch then
          App.beginEditBatch()
          S._g3PaintBatch = true
        end
        if Blocks.setPixel(S, pair, tile, i, brush) then App.markDirty() end
      end
    end
  end
  if S._g3PaintBatch and not Kit.mouseDown and not Kit.mouseClicked then
    App.endEditBatch()
    S._g3PaintBatch = nil
  end

  -- Palette swatches, two columns of eight, beside the grid.
  local sx = gx + cell * 8 + 12 * s
  local sw = 18 * s
  for c = 0, 15 do
    local bx = sx + math.floor(c / 8) * (sw + 4 * s)
    local by = gy + (c % 8) * (sw + 2 * s)
    if c == 0 then
      checker(bx, by, sw, sw, s)
    else
      local rgb = colours[c] or { 0, 0, 0 }
      love.graphics.setColor(rgb[1], rgb[2], rgb[3], 1)
      love.graphics.rectangle("fill", bx, by, sw, sw)
    end
    if c == brush then
      Theme.col(PAL.yellow, 1)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", bx - 1, by - 1, sw + 2, sw + 2)
      love.graphics.setLineWidth(1)
    end
    Kit.offerTooltip(bx, by, sw, sw, c == 0 and "Colour 0: see-through" or ("Colour %d"):format(c))
    if Kit.press(bx, by, sw, sw) then S.g3PaintColour = c end
  end

  -- Tools.
  local bx = sx + 2 * (sw + 4 * s) + 8 * s
  local by = gy
  if Kit.chip(bx, by, 84 * s, 22 * s, "Pick", picking, PAL.yellow, nil,
      "Next click on the grid picks its colour (or hold the right button)") then
    S.g3PaintPick = not picking
  end
  by = by + 28 * s
  if Kit.button(bx, by, 84 * s, 22 * s, t.base and "Reset" or "Clear", { kind = "ghost", font = "micro",
      tooltip = t.base and "Undo all painting on this tile" or "Make it blank again" })
      and Blocks.resetTile(S, pair, tile) then
    App.markDirty()
  end
  by = by + 28 * s
  if Kit.button(bx, by, 84 * s, 22 * s, "Delete tile", { kind = "danger", font = "micro",
      tooltip = "Remove this tile; blocks using it will be flagged" })
      and Blocks.deleteTile(S, pair, tile) then
    App.markDirty()
    S.status = ("Deleted your tile %s"):format(Blocks.tileLabel(S, pair, tile))
  end
  love.graphics.setColor(1, 1, 1, 1)
  return gy + cell * 8
end

-- Tile sheet ---------------------------------------------------------------

-- `which` = "game" (tiles found in this tileset's saved blocks, each shown
-- in its own colours) or "custom" (your tiles, in palette `pal`).
local function drawSheetPart(S, App, pair, mid, which, pal, x, y, w, cols, cell)
  local s = Kit.scale
  local img, list = Blocks.tileSheet(S, pair, pal, which, cols)
  local count = #list
  if not img or count == 0 then return y end
  local rows = math.ceil(count / cols)
  checker(x, y, cols * cell, rows * cell, s)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y, 0, cell / 8, cell / 8)

  local def = Blocks.definition(S, pair, mid)
  local si = S.g3BlockSlot
  local slot = def and si and def.slots[si]
  local game = which == "game" and Blocks.gameTiles(S, pair) or nil

  -- Mark the tile the selected slot currently uses.
  if slot and slot.tile then
    for index, tile in ipairs(list) do
      if tile == slot.tile then
        local i = index - 1
        Theme.col(PAL.yellow, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x + (i % cols) * cell, y + math.floor(i / cols) * cell, cell, cell)
        love.graphics.setLineWidth(1)
      end
    end
  end

  -- Hover + click, hit-tested per tile.
  local mx, my = Kit.mouseX or -1, Kit.mouseY or -1
  if Kit.hover(x, y, cols * cell, rows * cell) then
    local c, r = math.floor((mx - x) / cell), math.floor((my - y) / cell)
    local index = r * cols + c
    if c >= 0 and c < cols and index >= 0 and index < count then
      local tx, ty = x + c * cell, y + r * cell
      local tile = list[index + 1]
      local ok = Blocks.tileAvailable(S, pair, tile)
      Theme.col(ok and PAL.heading or PAL.red, 0.9)
      love.graphics.rectangle("line", tx, ty, cell, cell)
      Kit.offerTooltip(tx, ty, cell, cell, ("Tile %s"):format(Blocks.tileLabel(S, pair, tile))
        .. (ok and "" or " -- its base tile is missing"))
      if slot and Kit.press(tx, ty, cell, cell) then
        -- Game tiles come in the palette they were found in; yours in the
        -- palette you're viewing them in. Palette chips recolour afterwards.
        slot.tile, slot.pal = tile, game and game[index + 1].pal or pal
        save(S, App, pair, mid, def)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return y + rows * cell
end

local function drawSheet(S, App, pair, mid, x, y, w)
  local s = Kit.scale
  if mid == nil then return y end
  local def = Blocks.definition(S, pair, mid)
  local si = S.g3BlockSlot
  local pal = (def and si and def.slots[si]) and def.slots[si].pal or (tonumber(S.g3BlockPal) or 0)
  local cols = (w >= 32 * 16 * s) and 32 or 16
  local cell = math.max(12 * s, math.min(28 * s, math.floor(w / cols)))
  Kit.text("micro", ("TILES IN THIS TILESET'S BLOCKS  (%d)"):format(#Blocks.gameTiles(S, pair)),
    x, y, PAL.caption)
  Kit.text("small", si and ("Click a tile to put it in slot %d"):format(si)
    or "Select a slot above to place tiles", x + 260 * s, y - 2 * s, si and PAL.yellow or PAL.muted)
  y = y + 18 * s
  y = drawSheetPart(S, App, pair, mid, "game", pal, x, y, w, cols, cell)
  y = y + 14 * s

  -- Your own tiles.
  local mine = Blocks.customTiles(S.project, pair)
  Kit.text("micro", ("YOUR TILES  (%d)  -  palette %d"):format(#mine, pal), x, y + 6 * s, PAL.caption)
  if Kit.button(x + 190 * s, y, 130 * s, 24 * s, "+ New blank tile", { kind = "good", font = "small",
      tooltip = "Draw a tile from scratch" }) then
    local n, err = Blocks.newTile(S, pair, nil)
    if n then
      App.markDirty()
      if si and def and def.slots[si] then
        def.slots[si].tile, def.slots[si].pal = n, pal
        save(S, App, pair, mid, def)
      end
      S.status = ("Added your tile %s"):format(Blocks.tileLabel(S, pair, n))
    else
      S.status = tostring(err)
    end
  end
  Kit.text("micro", "Only the pixels you paint are saved; the rest come from the player's game.",
    x + 330 * s, y + 6 * s, PAL.faint)
  y = y + 32 * s
  if #mine > 0 then
    y = drawSheetPart(S, App, pair, mid, "custom", pal, x, y, w, cols, cell)
  end
  return y + 12 * s
end

-- Panel --------------------------------------------------------------------

function M.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local ids, usedBy = Blocks.pairs(S)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "TILESETS", ids, {
      queryKey = "g3BlockQuery", offsetKey = "g3BlockListOffset", selKey = "g3BlockPair",
      accent = PAL.blue,
      isOwned = function(id) return Blocks.hasEdits(S.project, id) end,
    })
  if not S.g3BlockPair then S.g3BlockPair = shown[1] end
  local pair = S.g3BlockPair
  if not pair then
    Kit.emptyBox(formX, listY, formW, listH, "No tilesets found -- open a FireRed project first")
    return
  end
  local blockIds, idsErr = Blocks.ids(S, pair)
  if not blockIds or #blockIds == 0 then
    Kit.emptyBox(formX, listY, formW, listH, tostring(idsErr))
    return
  end
  if S._g3BlockLastPair ~= pair then
    S._g3BlockLastPair = pair
    S.g3BlockId, S.g3BlockSlot, S.g3BlockStripRow = blockIds[1], nil, 0
    S.g3BlockGoto = nil
  end
  local known = false
  for _, mid in ipairs(blockIds) do if mid == S.g3BlockId then known = true break end end
  if not known then S.g3BlockId, S.g3BlockSlot = blockIds[1], nil end

  Kit.caption(formX, y, "BLOCK EDITOR  -  " .. pair)
  -- The wheel over the block strip scrolls the strip, not the form. The form
  -- takes the wheel inside beginForm, so claim it first.
  local r = S._g3BlockStripRect
  if r and (Kit.wheelY or 0) ~= 0 and Kit.hover(r.x, r.y, r.w, r.h) then
    local row = tonumber(S.g3BlockStripRow) or 0
    S.g3BlockStripRow = math.max(0, math.min(r.maxStart, row - Kit.wheelY))
    Kit.wheelY = 0
  end
  local fy, view, vx, vw = RegList.beginForm(S, formX, listY, formW, listH,
    "g3BlockFormScroll", "blk|" .. pair, 12 * s)
  vw = vw - 10 * s -- keep clear of the scrollbar
  local top = fy

  -- Header: what uses this tileset, and what has changed.
  local maps = usedBy[pair] or {}
  local names = {}
  for i = 1, math.min(4, #maps) do names[i] = tostring(maps[i]):gsub("^FR_", "") end
  local used = #maps == 0 and "Not used by any map"
    or ("Used by " .. table.concat(names, ", ") .. (#maps > 4 and (" +" .. (#maps - 4) .. " more") or ""))
  Kit.text("small", used, vx, fy, PAL.detail)
  local edited, added = 0, 0
  for _, def in pairs(Blocks.own(S.project, pair) or {}) do
    if def.new then added = added + 1 else edited = edited + 1 end
  end
  Kit.textRight("small", ("%d blocks  -  %d edited  -  %d new"):format(#blockIds, edited, added),
    vx + vw, fy, PAL.muted)
  fy = fy + 20 * s
  Kit.text("micro", "Saved as recipes (tile, palette, flip) -- no game graphics go into your mod.",
    vx, fy, PAL.faint)
  fy = fy + 18 * s

  fy = drawStrip(S, App, pair, blockIds, vx, fy, vw)
  fy = fy + 6 * s
  fy = drawBlockEditor(S, App, pair, S.g3BlockId, vx, fy, vw)
  fy = drawSheet(S, App, pair, S.g3BlockId, vx, fy, vw)
  FormPane.finish(S, "g3BlockFormScroll", top, fy, view)
end

return M
