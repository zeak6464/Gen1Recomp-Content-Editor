-- GFX > Blocks > Import image: turn a PNG (one picture, or a sprite sheet of
-- animation frames) into Gen 3 blocks.
--
-- The picture is cut into 16x16 blocks of 2x2 tiles. Its colours are matched
-- to one of the tileset's own palettes (palettes can't be edited yet), each
-- 8x8 piece becomes one of your tiles, and every frame becomes its own set of
-- blocks. With more than one frame, each block position gets a tile animation
-- (the same kind the map editor's Animate drawer makes) that steps through
-- the frames, so painting the first frame's blocks on a map is enough.
--
-- An optional background block goes in the bottom layer, so see-through
-- pixels show it -- including its water, sand or flower animation in game.
-- Nothing from the game is copied into the project: the background is stored
-- as a reference to the game's own block, the picture as your tiles.
--
-- Everything but the PNG decoding is plain Lua, so the tests run it under
-- LuaJIT.
local Blocks = require("Gen3Blocks")
local TS = require("Gen3TileSource")

local M = {}

M.MAX_BLOCKS = 6 -- widest / tallest picture, in blocks

-- Pictures ------------------------------------------------------------------
-- A picture is { w, h, px } with px a flat array of r, g, b, a (0-255).

--- Decode PNG (or any image LOVE reads) bytes into a picture.
function M.decode(bytes)
  if type(bytes) ~= "string" or #bytes == 0 then return nil, "The file is empty" end
  local ok, data = pcall(function()
    return love.image.newImageData(love.filesystem.newFileData(bytes, "import.png"))
  end)
  if not ok or not data then return nil, "Not a picture this editor can read -- use a PNG" end
  local w, h = data:getWidth(), data:getHeight()
  local px, n = {}, 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      px[n + 1] = math.floor(r * 255 + 0.5)
      px[n + 2] = math.floor(g * 255 + 0.5)
      px[n + 3] = math.floor(b * 255 + 0.5)
      px[n + 4] = math.floor(a * 255 + 0.5)
      n = n + 4
    end
  end
  return { w = w, h = h, px = px }
end

local function blank(w, h)
  local px = {}
  for i = 1, w * h * 4 do px[i] = 0 end
  return { w = w, h = h, px = px }
end

--- Guess the frame layout of a sprite sheet: square frames in one row
-- (the usual strip), else one frame.
function M.guessFrames(pic)
  if pic.h > 0 and pic.w > pic.h and pic.w % pic.h == 0 then return pic.w / pic.h, 1 end
  if pic.w > 0 and pic.h > pic.w and pic.h % pic.w == 0 then return 1, pic.h / pic.w end
  return 1, 1
end

--- Cut a sheet into across x down frames, left to right, top to bottom.
function M.split(pic, across, down)
  across, down = math.max(1, across or 1), math.max(1, down or 1)
  local fw, fh = math.floor(pic.w / across), math.floor(pic.h / down)
  if fw < 1 or fh < 1 then return nil, "The picture is too small for that many frames" end
  local frames = {}
  for r = 0, down - 1 do
    for c = 0, across - 1 do
      local f = blank(fw, fh)
      for y = 0, fh - 1 do
        for x = 0, fw - 1 do
          local si = ((r * fh + y) * pic.w + c * fw + x) * 4
          local di = (y * fw + x) * 4
          for k = 1, 4 do f.px[di + k] = pic.px[si + k] end
        end
      end
      -- a completely empty cell at the end of a sheet is not a frame
      local any = false
      for i = 4, #f.px, 4 do if f.px[i] >= 128 then any = true break end end
      if any then frames[#frames + 1] = f end
    end
  end
  if #frames == 0 then return nil, "The picture has no visible pixels" end
  return frames
end

--- The box around every visible pixel of every frame (frames share it, so
-- the animation doesn't jump about). Returns x, y, w, h.
function M.bounds(frames)
  local x0, y0, x1, y1 = math.huge, math.huge, -1, -1
  for _, f in ipairs(frames) do
    for y = 0, f.h - 1 do
      for x = 0, f.w - 1 do
        if f.px[(y * f.w + x) * 4 + 4] >= 128 then
          if x < x0 then x0 = x end
          if y < y0 then y0 = y end
          if x > x1 then x1 = x end
          if y > y1 then y1 = y end
        end
      end
    end
  end
  if x1 < 0 then return 0, 0, 0, 0 end
  return x0, y0, x1 - x0 + 1, y1 - y0 + 1
end

--- Suggested size in blocks for these frames.
function M.suggestSize(frames)
  local _, _, w, h = M.bounds(frames)
  return math.max(1, math.min(M.MAX_BLOCKS, math.ceil(w / 16))),
    math.max(1, math.min(M.MAX_BLOCKS, math.ceil(h / 16)))
end

--- Fit frames into bw x bh blocks: centred, shrunk (never enlarged) when
-- they don't fit. Shrinking averages the covered pixels, weighted by alpha.
-- Returns new frames of bw*16 x bh*16 and the scale used.
function M.fit(frames, bw, bh)
  local bx, by, cw, ch = M.bounds(frames)
  local tw, th = bw * 16, bh * 16
  local scale = math.min(1, tw / math.max(1, cw), th / math.max(1, ch))
  local ow, oh = math.max(1, math.floor(cw * scale + 0.5)), math.max(1, math.floor(ch * scale + 0.5))
  ow, oh = math.min(ow, tw), math.min(oh, th)
  local ox, oy = math.floor((tw - ow) / 2), math.floor((th - oh) / 2)
  local sx, sy = cw / ow, ch / oh
  local out = {}
  for i, f in ipairs(frames) do
    local g = blank(tw, th)
    for y = 0, oh - 1 do
      for x = 0, ow - 1 do
        local r, gg, b, a, wsum = 0, 0, 0, 0, 0
        local fy0, fy1 = y * sy, (y + 1) * sy
        local fx0, fx1 = x * sx, (x + 1) * sx
        for yy = math.floor(fy0), math.ceil(fy1) - 1 do
          local wy = math.min(yy + 1, fy1) - math.max(yy, fy0)
          if wy > 0 then
            for xx = math.floor(fx0), math.ceil(fx1) - 1 do
              local wx = math.min(xx + 1, fx1) - math.max(xx, fx0)
              if wx > 0 then
                local si = ((by + yy) * f.w + bx + xx) * 4
                local ww = wx * wy
                local al = (f.px[si + 4] or 0) / 255
                r = r + (f.px[si + 1] or 0) * ww * al
                gg = gg + (f.px[si + 2] or 0) * ww * al
                b = b + (f.px[si + 3] or 0) * ww * al
                a = a + ww * al
                wsum = wsum + ww
              end
            end
          end
        end
        local di = ((oy + y) * tw + ox + x) * 4
        if a > 0 then
          g.px[di + 1], g.px[di + 2], g.px[di + 3] = r / a, gg / a, b / a
        end
        g.px[di + 4] = wsum > 0 and 255 * a / wsum or 0
      end
    end
    out[i] = g
  end
  return out, scale
end

-- Colours --------------------------------------------------------------------

local function dist2(r, g, b, c)
  local dr, dg, db = r - c[1], g - c[2], b - c[3]
  -- weighted towards green, as the eye is
  return 2 * dr * dr + 4 * dg * dg + 3 * db * db
end

--- The colours of a block's under-the-player picture, as {r,g,b} list.
function M.blockColours(S, pair, mid)
  if not mid then return {} end
  local def = Blocks.definition(S, pair, mid)
  local pack = Blocks.pack(S, pair)
  if not def or not pack then return {} end
  local under = Blocks.composeBlock(S, pair, def)
  local seen, out = {}, {}
  for i = 1, 256 do
    local v = under and under[i] or 0
    if v ~= 0 and not seen[v] then
      seen[v] = true
      local c = (pack.rgb[math.floor(v / 16)] or {})[v % 16]
      if c then out[#out + 1] = c end
    end
  end
  return out
end

--- Colour numbers (1-15) of a palette the picture may use: not see-through
-- magenta, no duplicates and, with `avoid`, nothing that looks like the
-- background's own colours (so the picture doesn't melt into it).
function M.usable(rgb, avoid)
  local out, seen = {}, {}
  for c = 1, 15 do
    local col = rgb[c]
    if col then
      local key = col[1] .. "," .. col[2] .. "," .. col[3]
      local magenta = col[1] >= 248 and col[2] <= 8 and col[3] >= 248
      local near = false
      for _, a in ipairs(avoid or {}) do
        if dist2(col[1], col[2], col[3], a) < 9 * 144 then near = true break end
      end
      if not magenta and not near and not seen[key] then
        seen[key] = true
        out[#out + 1] = c
      end
    end
  end
  return out
end

local function histogram(frames, bright)
  local hist, list = {}, {}
  for _, f in ipairs(frames) do
    for i = 1, #f.px, 4 do
      if f.px[i + 3] >= 128 then
        local r, g, b = f.px[i], f.px[i + 1], f.px[i + 2]
        if bright ~= 0 then
          local k = 1 + bright
          r = math.max(0, math.min(255, r * k + bright * 80))
          g = math.max(0, math.min(255, g * k + bright * 80))
          b = math.max(0, math.min(255, b * k + bright * 80))
        end
        local key = math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b)
        local e = hist[key]
        if not e then e = { r, g, b, 0 }; hist[key] = e; list[#list + 1] = e end
        e[4] = e[4] + 1
      end
    end
  end
  return list, hist
end

local function nearest(r, g, b, rgb, allowed)
  local best, bestD = allowed[1], math.huge
  for _, c in ipairs(allowed) do
    local d = dist2(r, g, b, rgb[c])
    if d < bestD then best, bestD = c, d end
  end
  return best, bestD
end

--- How well each palette (0-12) can draw the frames: { [pal] = average
-- error } (lower is better; nil when the palette has too few colours), and
-- the best palette.
function M.rankPalettes(rgbAll, frames, avoid, bright)
  local list = histogram(frames, bright or 0)
  local scores, best, bestScore = {}, nil, math.huge
  for p = 0, Blocks.PALETTES - 1 do
    local rgb = rgbAll[p]
    local allowed = rgb and M.usable(rgb, avoid) or {}
    if #allowed >= 2 then
      local total, count = 0, 0
      for _, e in ipairs(list) do
        local _, d = nearest(e[1], e[2], e[3], rgb, allowed)
        total, count = total + math.sqrt(d) * e[4], count + e[4]
      end
      scores[p] = count > 0 and total / count or 0
      if scores[p] < bestScore then best, bestScore = p, scores[p] end
    end
  end
  return scores, best
end

--- Frames as colour numbers (0 = see-through) in one palette.
function M.quantize(frames, rgb, allowed, bright)
  local out = {}
  for i, f in ipairs(frames) do
    local idx = {}
    for p = 0, f.w * f.h - 1 do
      local j = p * 4
      if f.px[j + 4] >= 128 then
        local r, g, b = f.px[j + 1], f.px[j + 2], f.px[j + 3]
        if (bright or 0) ~= 0 then
          local k = 1 + bright
          r = math.max(0, math.min(255, r * k + bright * 80))
          g = math.max(0, math.min(255, g * k + bright * 80))
          b = math.max(0, math.min(255, b * k + bright * 80))
        end
        idx[p + 1] = nearest(r, g, b, rgb, allowed)
      else
        idx[p + 1] = 0
      end
    end
    out[i] = { w = f.w, h = f.h, idx = idx }
  end
  return out
end

-- Plan and create ------------------------------------------------------------

--- Work out an import without touching the project.
-- opts = { frames = pictures, blocksW, blocksH, bg = block id or nil,
--          palette = 0-12 or "auto", bright = -0.3..0.3, avoidBg = bool,
--          over = bool (draw over the player) }
-- Returns plan = { frames (colour numbers), pal, scores, scale, w, h, bg, ...}
function M.plan(S, pair, opts)
  local pack, err = Blocks.pack(S, pair)
  if not pack then return nil, err end
  local frames = opts.frames
  if not frames or #frames == 0 then return nil, "Choose a PNG first" end
  local bw = math.max(1, math.min(M.MAX_BLOCKS, opts.blocksW or 1))
  local bh = math.max(1, math.min(M.MAX_BLOCKS, opts.blocksH or 1))
  local fitted, scale = M.fit(frames, bw, bh)
  local avoid = (opts.avoidBg ~= false) and M.blockColours(S, pair, opts.bg) or {}
  local bright = opts.bright or 0
  local scores, best = M.rankPalettes(pack.rgb, fitted, avoid, bright)
  local pal = type(opts.palette) == "number" and opts.palette or best
  if pal == nil or not scores[pal] then
    return nil, "That palette has too few colours for this picture -- pick another"
  end
  local allowed = M.usable(pack.rgb[pal], avoid)
  return {
    pair = pair, w = bw, h = bh, bg = opts.bg, over = opts.over == true,
    pal = pal, best = best, scores = scores, scale = scale, bright = bright,
    frames = M.quantize(fitted, pack.rgb[pal], allowed, bright),
  }
end

-- The bottom layer that shows the background block: its own pictures, by
-- reference, in the palettes its bottom layer uses (unflipped, so the game's
-- tile animation carries over).
local function backgroundSlots(S, pair, bg)
  local empty = function() return { tile = false, pal = 0, hflip = false, vflip = false } end
  local slots = { empty(), empty(), empty(), empty() }
  if not bg then return slots, 0 end
  local def, edited = Blocks.definition(S, pair, bg)
  if not def then return slots, 0 end
  local pack = Blocks.pack(S, pair)
  for q = 1, 4 do
    local s = def.slots[q]
    if edited or not (pack and pack.index[bg]) then
      slots[q] = { tile = s.tile, pal = s.pal, hflip = s.hflip, vflip = s.vflip }
    elseif s.tile then
      slots[q] = { tile = TS.key(bg, "u", q - 1, s.pal), pal = s.pal, hflip = false, vflip = false }
    end
  end
  return slots, def.behavior or 0
end

local HEX = "0123456789abcdef"

-- One 8x8 piece of a frame as tile pixels ("0"-"f"), or nil when it's empty.
local function piece(frame, px, py)
  local chars, any = {}, false
  for y = 0, 7 do
    for x = 0, 7 do
      local v = frame.idx[(py + y) * frame.w + px + x + 1] or 0
      if v ~= 0 then any = true end
      chars[#chars + 1] = HEX:sub(v + 1, v + 1)
    end
  end
  return any and table.concat(chars) or nil
end

--- How many blocks and new tiles a plan needs.
function M.cost(plan)
  local seen, tiles = {}, 0
  for _, f in ipairs(plan.frames) do
    for py = 0, f.h - 8, 8 do
      for px = 0, f.w - 8, 8 do
        local t = piece(f, px, py)
        if t and not seen[t] then seen[t] = true; tiles = tiles + 1 end
      end
    end
  end
  return plan.w * plan.h * #plan.frames, tiles
end

local function imports(project, pair, create)
  if create then
    project.gen3Imports = project.gen3Imports or {}
    project.gen3Imports[pair] = project.gen3Imports[pair] or {}
  end
  return project.gen3Imports and project.gen3Imports[pair]
end

--- The imports made on a tileset: { {name, base, count, w, h, frames}, ... }.
function M.list(project, pair)
  return imports(project, pair) or {}
end

--- Remove an import: its blocks, its tiles and its animations.
function M.remove(S, pair, index)
  local list = imports(S.project, pair)
  local rec = list and list[index]
  if not rec then return false end
  local rows = S.project.gen3Blocks and S.project.gen3Blocks[pair]
  for mid = rec.base, rec.base + rec.count - 1 do
    local def = rows and rows[tostring(mid)]
    if def then
      for _, slot in ipairs(def.slots or {}) do
        if Blocks.isCustom(slot.tile) then Blocks.deleteTile(S, pair, slot.tile) end
      end
      Blocks.revert(S, pair, mid)
    end
    local anims = S.project.runtimeTileAnims and S.project.runtimeTileAnims[pair]
    if anims then anims[mid] = nil end
  end
  table.remove(list, index)
  if #list == 0 then S.project.gen3Imports[pair] = nil end
  if S.project.gen3Imports and not next(S.project.gen3Imports) then S.project.gen3Imports = nil end
  return true
end

-- First run of `count` block ids from 640 that neither the game nor the
-- project uses.
local function freeRun(S, pair, count, prefer)
  local pack = Blocks.pack(S, pair)
  local rows = Blocks.own(S.project, pair) or {}
  local function free(base)
    if base < Blocks.PRIMARY or base + count - 1 > Blocks.MAX_MID then return false end
    for mid = base, base + count - 1 do
      if pack.index[mid] or rows[tostring(mid)] ~= nil then return false end
    end
    return true
  end
  if prefer and free(prefer) then return prefer end
  for base = Blocks.PRIMARY, Blocks.MAX_MID - count + 1 do
    if free(base) then return base end
  end
  return nil
end

--- Write a plan into the project. An earlier import with the same name is
-- replaced, keeping its block numbers when the size matches, so maps already
-- painted with it pick up the new picture.
-- Returns record { name, base, count, w, h, frames, grid } or nil, message.
function M.create(S, pair, plan, name, duration)
  name = tostring(name or "image")
  local count, tileCount = M.cost(plan)
  local prefer
  for i, rec in ipairs(M.list(S.project, pair)) do
    if rec.name == name then
      prefer = rec.count == count and rec.base or nil
      M.remove(S, pair, i)
      break
    end
  end
  local freeTiles = Blocks.MAX_CUSTOM + 1 - #Blocks.customTiles(S.project, pair)
  if tileCount > freeTiles then
    return nil, ("This needs %d new tiles but the tileset only has room for %d more"):format(tileCount, freeTiles)
  end
  local base = freeRun(S, pair, count, prefer)
  if not base then
    return nil, ("No room for %d more blocks in this tileset (ids stop at %d)"):format(count, Blocks.MAX_MID)
  end
  local bottom, behavior = backgroundSlots(S, pair, plan.bg)
  local layerType
  if plan.bg then layerType = plan.over and "normal" or "covered" else layerType = "normal" end
  local imageOnTop = plan.bg ~= nil or plan.over
  local made = {}
  local function tileFor(px)
    if not px then return false end
    if made[px] then return made[px] end
    local n = assert(Blocks.newTile(S, pair, nil))
    Blocks.customTile(S.project, pair, n).px = px
    made[px] = n
    return n
  end
  local F = #plan.frames
  local grid = {}
  for p = 0, plan.w * plan.h - 1 do
    local bx, by = p % plan.w, math.floor(p / plan.w)
    grid[by + 1] = grid[by + 1] or {}
    grid[by + 1][bx + 1] = base + p * F
    for k = 1, F do
      local slots = {}
      for q = 1, 4 do
        local s = bottom[q]
        slots[q] = { tile = s.tile, pal = s.pal, hflip = s.hflip, vflip = s.vflip }
        slots[q + 4] = { tile = false, pal = 0, hflip = false, vflip = false }
      end
      for q = 0, 3 do
        local px = piece(plan.frames[k], bx * 16 + (q % 2) * 8, by * 16 + math.floor(q / 2) * 8)
        local slot = { tile = tileFor(px), pal = plan.pal, hflip = false, vflip = false }
        if imageOnTop then slots[q + 5] = slot else slots[q + 1] = slot end
      end
      Blocks.store(S, pair, base + p * F + k - 1,
        { slots = slots, layerType = layerType, behavior = behavior, new = true })
    end
    if F > 1 then
      S.project.runtimeTileAnims = S.project.runtimeTileAnims or {}
      S.project.runtimeTileAnims[pair] = S.project.runtimeTileAnims[pair] or {}
      local frames = {}
      for k = 1, F do
        frames[k] = { tile = base + p * F + k - 1, duration = math.max(16, math.floor(duration or 120)) }
      end
      S.project.runtimeTileAnims[pair][base + p * F] = frames
    end
  end
  local rec = { name = name, base = base, count = count, w = plan.w, h = plan.h, frames = F, grid = grid }
  local list = imports(S.project, pair, true)
  list[#list + 1] = rec
  return rec
end

return M
