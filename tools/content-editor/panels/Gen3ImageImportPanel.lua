-- GFX > Blocks > Import PNG: the screen for Gen3ImageImport.
--
-- Choose a PNG -- one picture, or a sprite sheet with the animation frames
-- side by side (the way the game keeps its own animated tiles) -- pick how
-- many blocks it covers and what sits behind it, check the preview, create.
local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local RegList = require("RegList")
local Blocks = require("Gen3Blocks")
local Import = require("Gen3ImageImport")

local M = {}

local BRIGHT = { { -0.2, "-20%" }, { -0.1, "-10%" }, { 0, "0" }, { 0.1, "+10%" }, { 0.2, "+20%" } }

local function stepper(x, y, s, label, value, lo, hi)
  Kit.text("small", label, x, y + 5 * s, PAL.text)
  local lw = 58 * s
  if Kit.chip(x + lw, y, 26 * s, 24 * s, "-", false, PAL.blue) and value > lo then value = value - 1 end
  Kit.text("button", tostring(value), x + lw + 34 * s, y + 3 * s, PAL.heading)
  if Kit.chip(x + lw + 56 * s, y, 26 * s, 24 * s, "+", false, PAL.blue) and value < hi then value = value + 1 end
  return value
end

-- Frames and plan follow the settings; rebuilt only when they change.
local function refresh(S, st, pair)
  if not st.picture then return end
  local fkey = st.across .. "x" .. st.down
  if st._framesKey ~= fkey then
    st._framesKey, st.frames, st.framesErr = fkey, Import.split(st.picture, st.across, st.down)
    st.frameW = math.floor(st.picture.w / st.across)
    st.frameH = math.floor(st.picture.h / st.down)
    st._planKey = nil
    if st.frames and not st.sizeChosen then st.blocksW, st.blocksH = Import.suggestSize(st.frames) end
  end
  if not st.frames then st.plan, st.planErr = nil, st.framesErr return end
  local bgKey = st.bg and (st.bg .. "|" .. Blocks.signature(Blocks.definition(S, pair, st.bg) or { slots = {} })) or "none"
  local key = table.concat({ fkey, st.blocksW, st.blocksH, bgKey, tostring(st.avoidBg),
    tostring(st.palette), st.bright, tostring(st.over) }, "|")
  if st._planKey == key then return end
  st._planKey = key
  st.plan, st.planErr = Import.plan(S, pair, { frames = st.frames, blocksW = st.blocksW,
    blocksH = st.blocksH, bg = st.bg, palette = st.palette, bright = st.bright,
    avoidBg = st.avoidBg, over = st.over })
  st.previews = nil
  if st.plan then st.blockCount, st.tileCount = Import.cost(st.plan) end
end

local function previews(S, st, pair)
  if st.previews then return st.previews end
  local pack = Blocks.pack(S, pair)
  local rgb = pack.rgb[st.plan.pal] or {}
  local out = {}
  for i, f in ipairs(st.plan.frames) do
    local data = love.image.newImageData(f.w, f.h)
    for p = 0, f.w * f.h - 1 do
      local v = f.idx[p + 1]
      if v ~= 0 then
        local c = rgb[v] or { 0, 0, 0 }
        data:setPixel(p % f.w, math.floor(p / f.w), c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    out[i] = img
  end
  st.previews = out
  return out
end

local function chooseFile(S, st)
  st.app.pickFile("Import picture or animation sheet", "PNG (*.png)|*.png", function(path)
    local bytes = require("ModIO").readText(path)
    local pic, err = Import.decode(bytes)
    if not pic then S.status = err return end
    st.picture, st.path = pic, path
    st.name = (tostring(path):match("([^/\\]+)$") or "image"):gsub("%.%w+$", "")
    st.across, st.down = Import.guessFrames(pic)
    st._framesKey, st.sizeChosen, st.result = nil, false, nil
    S.status = ("Loaded %s (%d x %d)"):format(st.name, pic.w, pic.h)
  end)
end

local function drawImported(S, App, st, pair, x, y, w, s, drawBlock, checker)
  -- Where to paint the last import.
  if st.result then
    local rec = st.result
    Kit.text("micro", ("PAINT %s ON THE MAP LIKE THIS  (first-frame blocks%s)"):format(rec.name:upper(),
      rec.frames > 1 and "; the rest are its animation" or ""), x, y, PAL.green)
    y = y + 16 * s
    local cell = 40 * s
    for r, row in ipairs(rec.grid or {}) do
      for c, mid in ipairs(row) do
        local cx, cy = x + (c - 1) * (cell + 3 * s), y + (r - 1) * (cell + 3 * s)
        checker(cx, cy, cell, cell, s)
        local def = Blocks.definition(S, pair, mid)
        if def then drawBlock(S, pair, mid, def, cx, cy, cell) end
        Kit.text("micro", tostring(mid), cx + 2 * s, cy + 1 * s, PAL.heading)
      end
    end
    y = y + #(rec.grid or {}) * (cell + 3 * s) + 16 * s
  end

  -- Earlier imports on this tileset.
  local list = Import.list(S.project, pair)
  if #list > 0 then
    Kit.text("micro", "IMPORTED HERE", x, y, PAL.caption)
    y = y + 16 * s
    for i, rec in ipairs(list) do
      Kit.text("small", ("%s  -  blocks %d-%d, %d x %d, %d frame%s"):format(rec.name, rec.base,
        rec.base + rec.count - 1, rec.w, rec.h, rec.frames, rec.frames == 1 and "" or "s"),
        x, y + 5 * s, PAL.text)
      if Kit.button(x + w - 200 * s, y, 96 * s, 24 * s, "Show", { kind = "ghost", font = "small",
          tooltip = "Show where to paint it" }) then
        st.result = rec
      end
      if Kit.button(x + w - 98 * s, y, 96 * s, 24 * s, "Remove", { kind = "danger", font = "small",
          tooltip = "Delete its blocks, tiles and animation" }) then
        if Import.remove(S, pair, i) then
          App.markDirty()
          S.status = ("Removed %s"):format(rec.name)
          if st.result == rec then st.result = nil end
        end
        break
      end
      y = y + 28 * s
    end
    y = y + 8 * s
  end

  return y
end

function M.draw(S, App, pair, x, y, w, drawBlock, checker)
  local s = Kit.scale
  local st = S.g3Import
  st.app = App
  st.across, st.down = st.across or 1, st.down or 1
  st.blocksW, st.blocksH = st.blocksW or 1, st.blocksH or 1

  Kit.text("button", "Import a picture", x, y, PAL.heading)
  y = y + 26 * s
  Kit.text("small", "A PNG: one picture, or animation frames side by side in one strip",
    x, y, PAL.muted)
  y = y + 18 * s
  Kit.text("small", "(the way the game keeps its own animated tiles). Colours are matched to one",
    x, y, PAL.muted)
  y = y + 18 * s
  Kit.text("small", "of this tileset's palettes; only your picture goes into the mod.",
    x, y, PAL.muted)
  y = y + 26 * s

  if Kit.button(x, y, 150 * s, 26 * s, st.picture and "Choose another..." or "Choose PNG...",
      { kind = st.picture and "ghost" or "good", font = "small" }) then
    chooseFile(S, st)
  end
  if st.picture then
    Kit.text("small", ("%s  -  %d x %d pixels"):format(st.name, st.picture.w, st.picture.h),
      x + 162 * s, y + 6 * s, PAL.detail)
  end
  y = y + 40 * s

  if not st.picture then return drawImported(S, App, st, pair, x, y, w, s, drawBlock, checker) + 12 * s end
  refresh(S, st, pair)

  -- Frames.
  Kit.text("micro", "FRAMES", x, y, PAL.caption)
  y = y + 16 * s
  local across = stepper(x, y, s, "Across", st.across, 1, 32)
  local down = stepper(x + 160 * s, y, s, "Down", st.down, 1, 16)
  if across ~= st.across or down ~= st.down then st.across, st.down = across, down end
  Kit.text("small", st.frames and ("%d frame%s of %d x %d"):format(#st.frames, #st.frames == 1 and "" or "s",
    st.frameW or 0, st.frameH or 0) or tostring(st.framesErr), x + 330 * s, y + 5 * s,
    st.frames and PAL.detail or PAL.red)
  y = y + 34 * s
  if not st.frames then return drawImported(S, App, st, pair, x, y, w, s, drawBlock, checker) end

  -- Size.
  Kit.text("micro", "SIZE IN BLOCKS (16 x 16 each)", x, y, PAL.caption)
  y = y + 16 * s
  local bw = stepper(x, y, s, "Wide", st.blocksW, 1, Import.MAX_BLOCKS)
  local bh = stepper(x + 160 * s, y, s, "High", st.blocksH, 1, Import.MAX_BLOCKS)
  if bw ~= st.blocksW or bh ~= st.blocksH then st.blocksW, st.blocksH, st.sizeChosen = bw, bh, true end
  if st.plan then
    Kit.text("small", st.plan.scale < 1 and ("Shrunk to %d%% to fit"):format(math.floor(st.plan.scale * 100 + 0.5))
      or "Fits at full size", x + 330 * s, y + 5 * s, PAL.detail)
  end
  y = y + 34 * s

  -- Background.
  Kit.text("micro", "BEHIND IT (shows through see-through pixels)", x, y, PAL.caption)
  y = y + 16 * s
  local thumb = 30 * s
  checker(x, y - 2 * s, thumb, thumb, s)
  if st.bg then
    local def = Blocks.definition(S, pair, st.bg)
    if def then drawBlock(S, pair, st.bg, def, x, y - 2 * s, thumb) end
  end
  Kit.text("small", st.bg and ("Block %d"):format(st.bg) or "Nothing", x + thumb + 8 * s, y + 5 * s, PAL.text)
  local bx = x + thumb + 90 * s
  if Kit.button(bx, y, 190 * s, 24 * s, ("Use selected block (%s)"):format(tostring(S.g3BlockId)),
      { kind = "ghost", font = "small", tooltip = "Click a block in the strip above first" }) then
    st.bg = S.g3BlockId
  end
  if Kit.button(bx + 196 * s, y, 80 * s, 24 * s, "Nothing", { kind = "ghost", font = "small" }) then
    st.bg = nil
  end
  y = y + 32 * s
  if st.bg then
    local v, changed = Kit.checkbox(x, y, 360 * s, 24 * s, st.avoidBg,
      "Keep the background's colours out of the picture")
    if changed then st.avoidBg = v end
    y = y + 30 * s
  end
  Kit.text("small", "Draw it", x, y + 5 * s, PAL.text)
  if Kit.chip(x + 70 * s, y, 150 * s, 24 * s, "Under the player", not st.over, PAL.blue) then st.over = false end
  if Kit.chip(x + 226 * s, y, 150 * s, 24 * s, "Over the player", st.over == true, PAL.blue) then st.over = true end
  y = y + 34 * s

  -- Palette.
  Kit.text("micro", "PALETTE", x, y, PAL.caption)
  y = y + 16 * s
  local scores = st.plan and st.plan.scores or {}
  if Kit.chip(x, y, 60 * s, 22 * s, "Auto", st.palette == "auto", PAL.blue, nil,
      "The palette that draws the picture best") then st.palette = "auto" end
  local chipW = 30 * s
  for p = 0, Blocks.PALETTES - 1 do
    local usable = scores[p] ~= nil
    local label = tostring(p) .. ((st.plan and st.plan.best == p) and "*" or "")
    if Kit.chip(x + 66 * s + p * (chipW + 3 * s), y, chipW, 22 * s, label, st.palette == p,
        PAL.blue, usable and nil or PAL.rowBg, usable and ("Palette %d  -  * = best match"):format(p)
          or "Too few colours for this picture") and usable then
      st.palette = p
    end
  end
  y = y + 28 * s
  if st.plan then
    local colours = Blocks.paletteColours(S, pair, st.plan.pal)
    local sw = 14 * s
    for i = 1, 15 do
      local c = colours[i] or { 0, 0, 0 }
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.rectangle("fill", x + (i - 1) * (sw + 2 * s), y, sw, sw)
    end
    love.graphics.setColor(1, 1, 1, 1)
    Kit.text("small", ("Palette %d%s"):format(st.plan.pal, st.palette == "auto" and " (auto)" or ""),
      x + 15 * (sw + 2 * s) + 8 * s, y, PAL.detail)
    y = y + sw + 12 * s
  end
  Kit.text("small", "Brightness", x, y + 5 * s, PAL.text)
  for i, b in ipairs(BRIGHT) do
    if Kit.chip(x + 90 * s + (i - 1) * 56 * s, y, 52 * s, 24 * s, b[2], st.bright == b[1], PAL.blue) then
      st.bright = b[1]
    end
  end
  y = y + 34 * s

  local many = st.frames and #st.frames > 1
  if many then
    Kit.text("small", "Frame time (ms)", x, y + 5 * s, PAL.text)
    local ms = RegList.num(App, "g3import_ms|" .. pair, x + 130 * s, y, 70 * s, 24 * s, st.duration)
    st.duration = math.max(16, math.min(5000, math.floor(tonumber(ms) or 120)))
    Kit.text("small", "per frame (the game's water: ~270)", x + 210 * s, y + 5 * s, PAL.faint)
    y = y + 34 * s
  end
  Kit.text("small", "Name", x, y + 5 * s, PAL.text)
  st.name = Kit.textfield("g3import_name|" .. pair, x + 130 * s, y, 200 * s, 24 * s, st.name or "", "name")
  Kit.text("small", "reusing a name replaces that import", x + 340 * s, y + 5 * s, PAL.faint)
  y = y + 38 * s

  -- Preview: the picture on its background, one block of background around it.
  if not st.plan then
    Kit.text("small", tostring(st.planErr), x, y, PAL.red)
    return drawImported(S, App, st, pair, x, y + 30 * s, w, s, drawBlock, checker)
  end
  Kit.text("micro", "PREVIEW", x, y, PAL.caption)
  y = y + 16 * s
  local images = previews(S, st, pair)
  local cols, rows = st.plan.w + 2, st.plan.h + 2
  local zoom = math.max(1, math.floor(math.min(4 * s, (w * 0.6) / (cols * 16))))
  local cell = 16 * zoom
  checker(x, y, cols * cell, rows * cell, s)
  if st.bg then
    local def = Blocks.definition(S, pair, st.bg)
    if def then
      for r = 0, rows - 1 do
        for c = 0, cols - 1 do drawBlock(S, pair, st.bg, def, x + c * cell, y + r * cell, cell) end
      end
    end
  end
  local frame = 1
  if #images > 1 then frame = math.floor((Kit.time or 0) * 1000 / st.duration) % #images + 1 end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(images[frame], x + cell, y + cell, 0, zoom, zoom)
  local info = ("%d block%s, %d new tile%s"):format(st.blockCount, st.blockCount == 1 and "" or "s",
    st.tileCount, st.tileCount == 1 and "" or "s")
  local ix = x + cols * cell + 20 * s
  Kit.text("small", info, ix, y, PAL.detail)
  if many then
    Kit.text("small", ("%d frames; animates on edited maps"):format(#images),
      ix, y + 20 * s, PAL.muted)
  end
  if st.bg then
    Kit.text("small", "Water behind it keeps moving in game", ix, y + 40 * s, PAL.muted)
  end
  if Kit.button(ix, y + 66 * s, 160 * s, 30 * s, "Create blocks", { kind = "good", font = "small" }) then
    local rec, err = Import.create(S, pair, st.plan, st.name ~= "" and st.name or "image", st.duration)
    if rec then
      App.markDirty()
      st.result = rec
      S.g3BlockId = rec.base
      S.status = ("Created %s: blocks %d-%d"):format(rec.name, rec.base, rec.base + rec.count - 1)
      st._planKey = nil
    else
      S.status = tostring(err)
    end
  end
  y = y + math.max(rows * cell, 100 * s) + 20 * s
  return drawImported(S, App, st, pair, x, y, w, s, drawBlock, checker)
end

return M
