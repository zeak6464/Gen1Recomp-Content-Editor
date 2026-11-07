-- GFX > Day & night (Gen3DayNight): the clock hours, the morning and night
-- looks, a preview switch shared with the map editor and GFX > Blocks, and
-- the colours that stay lit at night.
local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local RegList = require("RegList")
local FormPane = require("FormPane")
local DN = require("Gen3DayNight")
local Core = DN.Core

local M = {}

local function swatch(x, y, size, r, g, b)
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x, y, size, size, 3 * Kit.scale, 3 * Kit.scale)
  Theme.stroke(x, y, size, size, 3 * Kit.scale, PAL.cardBorder, 0.4, 1)
  love.graphics.setColor(1, 1, 1, 1)
end

local function set(S, App, key, value)
  if DN.set(S.project, key, value) then App.markDirty() end
end

-- The preview time: Off / Morning / Day / Night, a 24-hour scrubber and Play
-- (a whole day in 36 seconds). Sets S.g3DayNightHour. Returns its height.
function M.timeBar(S, App, x, y, w)
  local s = Kit.scale
  local cfg = DN.settings(S.project)
  local hour = DN.previewHour(S)
  if S.g3DayNightPlay then
    local now = love.timer.getTime()
    hour = ((hour or cfg.morning) + (now - (S._g3DayNightLast or now)) * 24 / 36) % 24
    S._g3DayNightLast = now
    S.g3DayNightHour = hour
  end
  local bx = x
  if Kit.chip(bx, y, 64 * s, 24 * s, S.g3DayNightPlay and "Pause" or "Play", S.g3DayNightPlay == true, PAL.green, nil,
      "Run through a whole day in 36 seconds") then
    S.g3DayNightPlay = not S.g3DayNightPlay
    S._g3DayNightLast = love.timer.getTime()
    if S.g3DayNightPlay and not hour then S.g3DayNightHour = cfg.morning end
  end
  bx = bx + 68 * s
  for _, p in ipairs(DN.PREVIEWS) do
    local want = p.id and DN.hourFor(S, p.id) or nil
    local on = (p.id == nil and hour == nil) or (p.id ~= nil and hour ~= nil and select(4, Core.tintAt(cfg,
      math.floor(hour) % 24, math.floor((hour % 1) * 60))) == p.id)
    if Kit.chip(bx, y, 70 * s, 24 * s, p.label, on, PAL.blue) then
      S.g3DayNightHour, S.g3DayNightPlay = want, false
    end
    bx = bx + 74 * s
  end
  if hour then
    local _, _, _, period = Core.tintAt(cfg, math.floor(hour) % 24, math.floor((hour % 1) * 60))
    Kit.text("small", ("%02d:%02d  %s"):format(math.floor(hour) % 24, math.floor((hour % 1) * 60), period),
      bx + 6 * s, y + 5 * s, PAL.detail)
  else
    Kit.text("small", "as the game draws it", bx + 6 * s, y + 5 * s, PAL.faint)
  end
  -- The scrubber: 0-24 h, with the parts of the day shaded.
  local ty, th = y + 32 * s, 16 * s
  for h0 = 0, 23 do
    local r, g, b = Core.tintAt(cfg, h0, 30)
    love.graphics.setColor(0.35 * r + 0.1, 0.4 * g + 0.1, 0.55 * b + 0.1, 1)
    love.graphics.rectangle("fill", x + w * h0 / 24, ty, w / 24 + 1, th)
  end
  Theme.stroke(x, ty, w, th, 3 * s, PAL.cardBorder, 0.4, 1)
  for _, k in ipairs({ "morning", "day", "night" }) do
    local px = x + w * cfg[k] / 24
    Theme.col(PAL.heading, 0.8)
    love.graphics.line(px, ty - 2 * s, px, ty + th + 2 * s)
  end
  if hour then
    local px = x + w * hour / 24
    Theme.col(PAL.yellow, 1)
    love.graphics.rectangle("fill", px - 2 * s, ty - 3 * s, 4 * s, th + 6 * s)
  end
  love.graphics.setColor(1, 1, 1, 1)
  Kit.offerTooltip(x, ty, w, th, "Drag to preview any time of day")
  if Kit.hover(x, ty - 4 * s, w, th + 8 * s) and (Kit.mouseDown or Kit.mouseClicked) then
    local h = math.max(0, math.min(23.99, (Kit.mouseX - x) / w * 24))
    S.g3DayNightHour, S.g3DayNightPlay = math.floor(h * 4) / 4, false
  end
  return 32 * s + th + 4 * s
end

--- The map editor's time bar, bottom-left over the map. Collapsed it is one
-- chip; open it is the time bar plus a note when the map won't change in
-- game. Remembers its rectangle so clicks on it don't paint the map.
function M.mapTimeBar(S, App, x, y, w, h, mapId)
  local s = Kit.scale
  local open = S.g3DayNightBar == true
  local hour = DN.previewHour(S)
  local label = hour and ("Time %02d:%02d"):format(math.floor(hour) % 24, math.floor((hour % 1) * 60)) or "Time of day"
  if not open then
    local bw, bh = 110 * s, 26 * s
    local bx, by = x + 8 * s, y + h - bh - 8 * s
    S._g3DayNightBarRect = { bx, by, bw, bh }
    Theme.col(PAL.rowBg, 0.96)
    love.graphics.rectangle("fill", bx, by, bw, bh, 6 * s, 6 * s)
    love.graphics.setColor(1, 1, 1, 1)
    if Kit.chip(bx, by, bw, bh, label, hour ~= nil, PAL.blue, PAL.steel,
        "Preview this map at any time of day (GFX > Day & night)") then
      S.g3DayNightBar = true
    end
    return
  end
  local note
  if not DN.enabled(S.project) then
    note = "Day and night is off -- turn it on in GFX > Day & night."
  elseif DN.mapKind(S, mapId) == nil then
    note = "This map has no map type yet: in game it won't change until you set Town, City or Route."
  elseif not DN.isOutdoorMap(S, mapId) then
    note = "This map's type isn't outdoor, so it looks the same all day (as in game)."
  end
  local bw = math.min(w - 16 * s, 600 * s)
  local bh = (note and 96 or 76) * s
  local bx, by = x + 8 * s, y + h - bh - 8 * s
  S._g3DayNightBarRect = { bx, by, bw, bh }
  Theme.col(PAL.rowBg, 0.96)
  love.graphics.rectangle("fill", bx, by, bw, bh, 6 * s, 6 * s)
  Theme.stroke(bx, by, bw, bh, 6 * s, PAL.cardBorder, 0.5, 1)
  love.graphics.setColor(1, 1, 1, 1)
  M.timeBar(S, App, bx + 10 * s, by + 10 * s, bw - 20 * s - 34 * s)
  if Kit.button(bx + bw - 36 * s, by + 38 * s, 26 * s, 22 * s, "x", { kind = "ghost", font = "micro",
      tooltip = "Hide (the preview time stays)" }) then
    S.g3DayNightBar = false
  end
  if note then Kit.text("micro", Kit.ellipsize("micro", note, bw - 20 * s), bx + 10 * s, by + bh - 20 * s, PAL.yellow) end
end

-- Night look painter (GFX > Blocks, "Night look") ---------------------------

local PRESETS = {
  { "f8e080", "Warm window" }, { "f8c050", "Lamp" }, { "f8f8f8", "White" }, { "a0d8f8", "Cool light" },
}

-- The warm-light sample palette: oranges to yellows (columns, 15-60 degrees
-- of hue) from vivid to pale, then deeper, in colours the GBA can show.
local WARM = {}
do
  local rows = { { 1, 1 }, { 0.75, 1 }, { 0.5, 1 }, { 0.3, 1 }, { 0.15, 1 }, { 1, 0.85 }, { 0.8, 0.7 } }
  for _, row in ipairs(rows) do
    local line = {}
    for k = 0, 11 do
      local h, sat, val = (12 + k * 4.5) / 60, row[1], row[2] -- hue in sixths of the wheel
      local i = math.floor(h)
      local f = h - i
      local p, q, t = val * (1 - sat), val * (1 - sat * f), val * (1 - sat * (1 - f))
      local r, g, b
      if i == 0 then r, g, b = val, t, p else r, g, b = q, val, p end
      local function five(v) return math.floor(math.floor(v * 31 + 0.5) * 255 / 31 + 0.5) end
      line[#line + 1] = ("%02x%02x%02x"):format(five(r), five(g), five(b))
    end
    WARM[#WARM + 1] = line
  end
end

local function hexOf(c)
  return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

--- A block at night, 16 x 16 cells, with its selection: drag selects,
-- right-drag unselects; with S[sameKey] on, a click selects every pixel of
-- that day colour. Returns the grid's size.
local function pixelGrid(S, sel, day, night, tr, tg, tb, gx, gy, cell, sameKey)
  for i = 1, 256 do
    local px, py = gx + ((i - 1) % 16) * cell, gy + math.floor((i - 1) / 16) * cell
    local c = day[i]
    if night[i] then
      local r, g, b = Core.hex(night[i])
      love.graphics.setColor(r, g, b, 1)
    elseif c then
      local r, g, b = Core.grade(c[1] * 255, c[2] * 255, c[3] * 255, tr or 1, tg or 1, tb or 1)
      love.graphics.setColor(r / 255, g / 255, b / 255, 1)
    else
      Theme.col(PAL.rowBg, 1)
    end
    love.graphics.rectangle("fill", px, py, cell, cell)
    if sel.set[i] then
      Theme.col(PAL.yellow, 1)
      love.graphics.rectangle("line", px + 1, py + 1, cell - 2, cell - 2)
    end
  end
  Theme.col(PAL.cardBorder, 0.25)
  for k = 0, 16 do
    love.graphics.line(gx + k * cell, gy, gx + k * cell, gy + 16 * cell)
    love.graphics.line(gx, gy + k * cell, gx + 16 * cell, gy + k * cell)
  end
  love.graphics.setColor(1, 1, 1, 1)
  local right = love.mouse and love.mouse.isDown and love.mouse.isDown(2)
  if Kit.hover(gx, gy, cell * 16, cell * 16) then
    local cx, cy = math.floor((Kit.mouseX - gx) / cell), math.floor((Kit.mouseY - gy) / cell)
    if cx >= 0 and cx < 16 and cy >= 0 and cy < 16 then
      local i = cy * 16 + cx + 1
      Theme.col(PAL.heading, 1)
      love.graphics.rectangle("line", gx + cx * cell, gy + cy * cell, cell, cell)
      love.graphics.setColor(1, 1, 1, 1)
      if S[sameKey] and Kit.mouseClicked then
        local want = day[i] and hexOf(day[i])
        for k = 1, 256 do if day[k] and hexOf(day[k]) == want then sel.set[k] = true end end
        S[sameKey] = false
      elseif right then
        sel.set[i] = nil
      elseif Kit.mouseClicked or Kit.mouseDown then
        sel.set[i] = true
      end
    end
  end
  return cell * 16
end

--- The warm lights and a few others; a click makes it the night colour.
-- Returns the height used.
local function colourSwatches(S, bx, by, sw)
  local s = Kit.scale
  local colour = S.g3NightColour or PRESETS[1][1]
  for r, line in ipairs(WARM) do
    for k, hex in ipairs(line) do
      local px, py = bx + (k - 1) * (sw + 2 * s), by + (r - 1) * (sw + 2 * s)
      local cr, cg, cb = Core.hex(hex)
      love.graphics.setColor(cr, cg, cb, 1)
      love.graphics.rectangle("fill", px, py, sw, sw)
      if hex == colour then
        Theme.col(PAL.heading, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px - 1, py - 1, sw + 2, sw + 2)
        love.graphics.setLineWidth(1)
      end
      Kit.offerTooltip(px, py, sw, sw, hex)
      if Kit.press(px, py, sw, sw) then S.g3NightColour = hex end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local y = by + #WARM * (sw + 2 * s) + 2 * s
  for k, p in ipairs(PRESETS) do
    local pr, pg, pb = Core.hex(p[1])
    local px = bx + (k - 1) * (sw + 2 * s)
    swatch(px, y, sw, pr, pg, pb)
    Kit.offerTooltip(px, y, sw, sw, p[2] .. " (" .. p[1] .. ")")
    if Kit.press(px, y, sw, sw) then S.g3NightColour = p[1] end
  end
  return y + sw - by
end

--- "Remove all night looks", armed by the first click and done by a second
-- one within a few seconds.
local function removeAllButton(S, App, x, y, w, h)
  local now = love.timer and love.timer.getTime() or 0
  local armed = S._g3NightClearAll and now - S._g3NightClearAll < 4
  if Kit.button(x, y, w, h, armed and "Click again to remove all" or "Remove all night looks",
      { kind = armed and "danger" or "ghost", font = "micro",
        tooltip = "Every block darkens at night again (Undo / Ctrl+Z brings them back)" }) then
    if not armed then
      S._g3NightClearAll = now
    else
      S._g3NightClearAll = nil
      local n = DN.clearAllNightLooks(S.project)
      if n > 0 then
        App.markDirty()
        for _, item in ipairs((S.g3NightFound or {}).items or {}) do item.already = false; item.stale = true end
      end
      S.status = ("Night look removed from %d block%s"):format(n, n == 1 and "" or "s")
    end
  end
end

--- Select pixels of a block and give them their own night colour; every
-- other pixel just darkens with the night tint. Returns the next y.
function M.nightPainter(S, App, pair, mid, x, y, w)
  local s = Kit.scale
  local day = DN.dayPixels(S, pair, mid)
  if not day then
    Kit.text("small", "This block can't be drawn.", x, y, PAL.red)
    return y + 24 * s
  end
  local cfg = DN.settings(S.project)
  local tr, tg, tb = Core.hex(cfg.nightTint)
  local night = DN.nightPixels(S.project, pair, mid)
  local sel = S.g3NightSel
  if not sel or sel.pair ~= pair or sel.mid ~= mid then
    sel = { pair = pair, mid = mid, set = {} }
    S.g3NightSel = sel
  end
  local count, painted = 0, 0
  for _ in pairs(sel.set) do count = count + 1 end
  for _ in pairs(night) do painted = painted + 1 end

  Kit.text("micro", ("NIGHT LOOK  -  block %d"):format(mid), x, y, PAL.caption)
  y = y + 14 * s
  Kit.text("small", Kit.ellipsize("small",
    "Select pixels (drag; right-drag to unselect), then give them a night colour. Everything else darkens with the night tint.",
    w), x, y, PAL.muted)
  y = y + 22 * s

  -- The block at night, 16 x 16.
  local cell = 14 * s
  local gx, gy = x, y
  pixelGrid(S, sel, day, night, tr, tg, tb, gx, gy, cell, "g3NightSameColour")

  -- Tools, right of the grid.
  local bx, by = gx + 16 * cell + 16 * s, gy
  local bw = 150 * s
  if Kit.chip(bx, by, bw, 24 * s, "Select a colour", S.g3NightSameColour == true, PAL.yellow, nil,
      "Next click on the grid selects every pixel of that colour in this block") then
    S.g3NightSameColour = not S.g3NightSameColour
  end
  if Kit.button(bx + bw + 6 * s, by, 70 * s, 24 * s, "All", { kind = "ghost", font = "micro" }) then
    for k = 1, 256 do if day[k] then sel.set[k] = true end end
  end
  if Kit.button(bx + bw + 80 * s, by, 70 * s, 24 * s, "None", { kind = "ghost", font = "micro" }) then
    sel.set = {}
  end
  by = by + 32 * s
  Kit.text("small", ("%d selected  -  %d with a night colour"):format(count, painted), bx, by, PAL.detail)
  by = by + 24 * s

  Kit.text("micro", "NIGHT COLOUR", bx, by, PAL.caption)
  by = by + 14 * s
  local colour = S.g3NightColour or PRESETS[1][1]
  local typed = Kit.textfield("g3dn_nightColour", bx, by, 90 * s, 26 * s, colour, "rrggbb", "The colour selected pixels show at night")
  if typed ~= colour and Core.hex(typed) then S.g3NightColour = typed:lower():gsub("^#", ""); colour = S.g3NightColour end
  local r, g, b = Core.hex(colour)
  if r then swatch(bx + 96 * s, by + 3 * s, 20 * s, r, g, b) end
  by = by + 32 * s
  -- Warm lights to pick from.
  by = by + colourSwatches(S, bx, by, 20 * s) + 14 * s
  local selected = {}
  for k in pairs(sel.set) do selected[#selected + 1] = k end
  table.sort(selected)
  if Kit.button(bx, by, 150 * s, 26 * s, "Use this colour", { kind = "primary", font = "micro",
      tooltip = "Selected pixels show this colour at night" }) and #selected > 0 then
    if DN.setNightPixels(S.project, pair, mid, selected, colour) then
      App.markDirty()
      S.status = ("%d pixels of block %d are %s at night"):format(#selected, mid, colour)
    end
  end
  if Kit.button(bx + 156 * s, by, 150 * s, 26 * s, "Keep day colour", { kind = "ghost", font = "micro",
      tooltip = "Selected pixels keep their own day colour at night (lit, untinted)" }) and #selected > 0 then
    local any = false
    for _, k in ipairs(selected) do
      if day[k] then any = DN.setNightPixels(S.project, pair, mid, { k }, hexOf(day[k])) or any end
    end
    if any then App.markDirty(); S.status = ("%d pixels of block %d keep their day colour at night"):format(#selected, mid) end
  end
  by = by + 32 * s
  if Kit.button(bx, by, 150 * s, 26 * s, "Back to normal", { kind = "ghost", font = "micro",
      tooltip = "Selected pixels darken with the night tint again" }) and #selected > 0 then
    if DN.setNightPixels(S.project, pair, mid, selected, nil) then App.markDirty() end
  end
  if Kit.button(bx + 156 * s, by, 150 * s, 26 * s, "Pick from pixel", { kind = "ghost", font = "micro",
      tooltip = "Use the first selected pixel's night (or day) colour" }) and selected[1] then
    local k = selected[1]
    S.g3NightColour = night[k] or (day[k] and hexOf(day[k])) or colour
  end
  by = by + 32 * s
  -- A window the search missed: light the selected pixels like the example.
  local ex = S.g3NightExample
  if ex and not (ex.pair == pair and ex.mid == mid) then
    if Kit.button(bx, by, 306 * s, 26 * s, Kit.ellipsize("micro", ("Light like %s %d"):format(
        (ex.pair:gsub("^general__rom_", "general ")), ex.mid), 290 * s), { kind = "accent", font = "micro",
        tooltip = "Selected pixels take the example's night colours, darkest to brightest -- then this block is an example too" })
        and #selected > 0 then
      local n, err = DN.lightLikeExample(S, pair, mid, selected, ex.pair, ex.mid)
      if n then
        App.markDirty()
        S.status = ("%d pixels of block %d lit like %s %d -- search again with All lit blocks to find more like it"):format(
          n, mid, ex.pair, ex.mid)
      else
        S.status = tostring(err)
      end
    end
    by = by + 32 * s
  end
  if Kit.button(bx, by, 150 * s, 26 * s, "Remove night look", { kind = "danger", font = "micro",
      enabled = painted > 0, tooltip = "The whole block darkens at night again" }) then
    if DN.clearNightLook(S.project, pair, mid) then
      App.markDirty()
      sel.set = {}
      S.status = ("Block %d has no night look now"):format(mid)
    end
  end
  removeAllButton(S, App, bx + 156 * s, by, 150 * s, 26 * s)
  by = by + 32 * s
  by = by + 8 * s

  -- Day and night, side by side, 4x.
  local pv = 64 * s
  Kit.text("micro", "DAY", bx, by, PAL.caption)
  Kit.text("micro", "NIGHT", bx + pv + 16 * s, by, PAL.caption)
  by = by + 14 * s
  for i = 1, 256 do
    local c = day[i]
    local px, py = (i - 1) % 16 * pv / 16, math.floor((i - 1) / 16) * pv / 16
    if c then
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.rectangle("fill", bx + px, by + py, pv / 16 + 0.5, pv / 16 + 0.5)
      local nr, ng, nb
      if night[i] then nr, ng, nb = Core.hex(night[i])
      else
        nr, ng, nb = Core.grade(c[1] * 255, c[2] * 255, c[3] * 255, tr or 1, tg or 1, tb or 1)
        nr, ng, nb = nr / 255, ng / 255, nb / 255
      end
      love.graphics.setColor(nr, ng, nb, 1)
      love.graphics.rectangle("fill", bx + pv + 16 * s + px, by + py, pv / 16 + 0.5, pv / 16 + 0.5)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  local bottom = math.max(gy + 16 * cell, by + pv) + 16 * s
  return M.similar(S, App, pair, mid, x, bottom, w)
end

-- Finding blocks like this one ---------------------------------------------

--- What a found block looks like at night: its own night look once it has
-- one, else what the search would give it.
local lookOf = function(S, item)
  if item.already then return DN.nightPixels(S.project, item.pair, item.mid) end
  return item.pixels
end

local function thumbs(S, item, tr, tg, tb)
  local day = DN.dayPixels(S, item.pair, item.mid) or {}
  local look = lookOf(S, item)
  local d, n = love.image.newImageData(16, 16), love.image.newImageData(16, 16)
  for i = 1, 256 do
    local c = day[i]
    if c then
      local x, y = (i - 1) % 16, math.floor((i - 1) / 16)
      d:setPixel(x, y, c[1], c[2], c[3], 1)
      if look[i] then
        local r, g, b = Core.hex(look[i]); n:setPixel(x, y, r, g, b, 1)
      else
        local r, g, b = Core.grade(c[1] * 255, c[2] * 255, c[3] * 255, tr, tg, tb)
        n:setPixel(x, y, r / 255, g / 255, b / 255, 1)
      end
    end
  end
  local di, ni = love.graphics.newImage(d), love.graphics.newImage(n)
  di:setFilter("nearest", "nearest"); ni:setFilter("nearest", "nearest")
  return di, ni
end

--- Look for blocks like the examples -- this block (which = "this") or
-- every block with a night look ("all") -- in "tileset" or "outdoor"
-- tilesets, optionally with the looser match. Results go in S.g3NightFound.
function M.find(S, pair, mid, scope, which, loose)
  local list = scope == "tileset" and { pair } or DN.outdoorPairs(S)
  local examples
  if which == "all" then
    examples = DN.paintedBlocks(S.project)
  else
    examples = { { pair = pair, mid = mid } }
  end
  local items, err, nRules = DN.findSimilarTo(S, examples, list, loose and DN.LOOSE or nil)
  if not items then
    S.status = err
    return nil
  end
  if which ~= "all" then S.g3NightExample = { pair = pair, mid = mid } end
  local cfg = DN.settings(S.project)
  local tr, tg, tb = Core.hex(cfg.nightTint)
  for _, item in ipairs(items) do
    item.ticked = not item.already
    item.dayImage, item.nightImage = thumbs(S, item, tr or 1, tg or 1, tb or 1)
  end
  S.g3NightFound = { pair = pair, mid = mid, items = items, scope = scope }
  S.g3NightFix, S.g3NightFixSel = nil, nil
  S.status = ("%d similar blocks found in %d tileset%s (%d kind%s of window%s)"):format(#items, #list,
    #list == 1 and "" or "s", nRules or 1, (nRules or 1) == 1 and "" or "s", loose and ", looser match" or "")
  return S.g3NightFound
end

local function refreshThumbs(S, item)
  local tr, tg, tb = Core.hex(DN.settings(S.project).nightTint)
  item.dayImage, item.nightImage = thumbs(S, item, tr or 1, tg or 1, tb or 1)
  item.stale = nil
  local n = 0
  for _ in pairs(lookOf(S, item)) do n = n + 1 end
  item.count = n
end

--- Fix one found block where it is, before or after it's given its look:
-- right-click a card. Before, edits change what "Give" will write; after,
-- they go straight into the block. Returns the height used.
function M.fixFound(S, App, item, x, y, w)
  local s = Kit.scale
  local day = DN.dayPixels(S, item.pair, item.mid)
  if not day then return 0 end
  local tr, tg, tb = Core.hex(DN.settings(S.project).nightTint)
  local look = lookOf(S, item)
  local sel = S.g3NightFixSel
  if not sel or sel.item ~= item then
    sel = { item = item, set = {} }
    S.g3NightFixSel = sel
  end
  local selected = {}
  for k in pairs(sel.set) do selected[#selected + 1] = k end
  table.sort(selected)
  -- Write night colours (or nil: back to normal) to the block or the proposal.
  local function put(list, colour)
    local changed = false
    if item.already then
      changed = DN.setNightPixels(S.project, item.pair, item.mid, list, colour)
      if changed then App.markDirty() end
    else
      for _, i in ipairs(list) do
        if item.pixels[i] ~= colour then item.pixels[i] = colour; changed = true end
      end
      if changed then item.ticked = next(item.pixels) ~= nil end
    end
    if changed then refreshThumbs(S, item) end
    return changed
  end

  local cell = 12 * s
  local top = y
  local header = ("FIX  %s  block %d  -  %s"):format((item.pair:gsub("^general__rom_", "general ")), item.mid,
    item.already and "has its night look, edits save straight away" or "not given yet, edits change what it gets")
  Kit.text("micro", Kit.ellipsize("micro", header, w - 20 * s), x + 10 * s, y + 8 * s, PAL.caption)
  local gx, gy = x + 10 * s, y + 26 * s
  pixelGrid(S, sel, day, look, tr, tg, tb, gx, gy, cell, "g3NightFixSame")

  local bx, by = gx + 16 * cell + 14 * s, gy
  local bw, bh = 140 * s, 24 * s
  local half = (bw - 6 * s) / 2
  if Kit.chip(bx, by, bw, bh, "Select a colour", S.g3NightFixSame == true, PAL.yellow, nil,
      "Next click on the grid selects every pixel of that colour") then
    S.g3NightFixSame = not S.g3NightFixSame
  end
  if Kit.button(bx + bw + 6 * s, by, half, bh, "All", { kind = "ghost", font = "micro" }) then
    for k = 1, 256 do if day[k] then sel.set[k] = true end end
  end
  if Kit.button(bx + bw + 12 * s + half, by, half, bh, "None", { kind = "ghost", font = "micro" }) then
    sel.set = {}
  end
  by = by + 30 * s
  local colour = S.g3NightColour or PRESETS[1][1]
  if Kit.button(bx, by, bw, bh, "Use this colour", { kind = "primary", font = "micro",
      tooltip = "Selected pixels show the night colour (" .. colour .. ")" }) and #selected > 0 then
    put(selected, colour)
  end
  if Kit.button(bx + bw + 6 * s, by, bw, bh, "Back to normal", { kind = "ghost", font = "micro",
      tooltip = "Selected pixels darken with the night tint -- for pixels lit by mistake" }) and #selected > 0 then
    put(selected, nil)
  end
  by = by + 30 * s
  if Kit.button(bx, by, bw, bh, "Pick from pixel", { kind = "ghost", font = "micro",
      tooltip = "Use the first selected pixel's night (or day) colour" }) and selected[1] then
    local k = selected[1]
    S.g3NightColour = look[k] or (day[k] and hexOf(day[k])) or colour
  end
  local ex = S.g3NightExample
  if ex and not (ex.pair == item.pair and ex.mid == item.mid) then
    if Kit.button(bx + bw + 6 * s, by, bw, bh, ("Light like %d"):format(ex.mid), { kind = "accent", font = "micro",
        tooltip = ("Selected pixels take %s %d's night colours, darkest to brightest"):format(ex.pair, ex.mid) })
        and #selected > 0 then
      local out, n = DN.likeExample(S, item.pair, item.mid, selected, ex.pair, ex.mid)
      if out then
        local byColour = {}
        for i, c in pairs(out) do byColour[c] = byColour[c] or {}; table.insert(byColour[c], i) end
        for c, list in pairs(byColour) do put(list, c) end
      else
        S.status = tostring(n)
      end
    end
  end
  by = by + 30 * s
  if Kit.button(bx, by, bw, bh, "Remove night look", { kind = "danger", font = "micro",
      enabled = next(look) ~= nil, tooltip = "The whole block darkens at night again" }) then
    if item.already then
      if DN.clearNightLook(S.project, item.pair, item.mid) then App.markDirty() end
      item.already = false
    end
    item.pixels, item.ticked = {}, false
    sel.set = {}
    refreshThumbs(S, item)
    S.status = ("%s block %d has no night look"):format(item.pair, item.mid)
  end
  if not item.already then
    if Kit.button(bx + bw + 6 * s, by, bw, bh, "Give it this look", { kind = "accent", font = "micro",
        enabled = next(item.pixels) ~= nil, tooltip = "Write this block's night look now" }) then
      if DN.applySimilar(S.project, item) then App.markDirty() end
      item.already, item.ticked = true, false
      refreshThumbs(S, item)
    end
  end
  by = by + 30 * s
  if Kit.button(bx, by, bw, bh, "Open in block editor", { kind = "ghost", font = "micro",
      tooltip = "Show this block at the top of GFX > Blocks" }) then
    S.g3BlockPair, S.g3BlockId, S._g3BlockLastPair = item.pair, item.mid, item.pair
  end
  if Kit.button(bx + bw + 6 * s, by, bw, bh, "Done", { kind = "ghost", font = "micro" }) then
    S.g3NightFix, S.g3NightFixSel = nil, nil
  end
  by = by + 30 * s
  local r, g, b = Core.hex(colour)
  Kit.text("small", ("%d selected  -  night colour %s"):format(#selected, colour), bx, by + 4 * s, PAL.detail)
  if r then swatch(bx + 2 * bw - 14 * s, by, 20 * s, r, g, b) end
  by = by + 26 * s

  -- The colours, beside the tools when there's room, else under them.
  local sw = 14 * s
  local pw = 12 * (sw + 2 * s)
  local px, py = bx + 2 * bw + 20 * s, gy
  if px + pw > x + w - 10 * s then px, py = bx, by + 4 * s end
  local ph = colourSwatches(S, px, py, sw)
  local bottom = math.max(gy + 16 * cell, by, py + ph) + 10 * s
  Theme.stroke(x, top, w, bottom - top, 6 * s, PAL.yellow, 0.6, 1)
  return bottom - top
end

--- Find blocks with the same kind of window as the examples and give them
-- the same night look. Returns the next y.
function M.similar(S, App, pair, mid, x, y, w)
  local s = Kit.scale
  local found = S.g3NightFound
  local lit = DN.hasNightPixels(S.project, pair, mid)
  local nLit = #DN.paintedBlocks(S.project)
  Kit.text("micro", "FIND SIMILAR BLOCKS", x, y, PAL.caption)
  y = y + 14 * s
  Kit.text("small", Kit.ellipsize("small",
    "Finds blocks with the same kind of window (same colours inside the same frame colour) and gives them the example's night look.",
    w), x, y, PAL.muted)
  y = y + 22 * s
  local ex = S.g3NightExample
  if not lit and ex and not (ex.pair == pair and ex.mid == mid) then
    Kit.text("small", Kit.ellipsize("small", ("Missed by the search? Select this block's window pixels above, then Light like %s %d."):format(
      ex.pair, ex.mid), w), x, y, PAL.yellow)
    y = y + 22 * s
  end
  local which = S.g3NightWhich or "this"
  Kit.text("small", "Examples", x, y + 5 * s, PAL.text)
  if Kit.chip(x + 76 * s, y, 100 * s, 24 * s, "This block", which == "this", PAL.blue, nil,
      "Learn from the open block's night look") then S.g3NightWhich = "this"; which = "this" end
  if Kit.chip(x + 180 * s, y, 160 * s, 24 * s, ("All lit blocks (%d)"):format(nLit), which == "all", PAL.blue, nil,
      "Learn from every block with a night look -- each kind of window you lit, the search finds more of") then
    S.g3NightWhich = "all"; which = "all"
  end
  if Kit.chip(x + 346 * s, y, 120 * s, 24 * s, "Looser match", S.g3NightLoose == true, PAL.yellow, nil,
      "Frame on 40% of the patch's edge instead of 60%, and patches from 2 pixels -- finds more, check the results") then
    S.g3NightLoose = not S.g3NightLoose
  end
  y = y + 30 * s
  local scope = S.g3NightScope or "outdoor"
  Kit.text("small", "Where", x, y + 5 * s, PAL.text)
  if Kit.chip(x + 76 * s, y, 110 * s, 24 * s, "This tileset", scope == "tileset", PAL.blue) then S.g3NightScope = "tileset"; scope = "tileset" end
  if Kit.chip(x + 190 * s, y, 150 * s, 24 * s, "Outdoor tilesets", scope == "outdoor", PAL.blue, nil,
      "Every tileset an outdoor map (Town, City, Route) uses") then S.g3NightScope = "outdoor"; scope = "outdoor" end
  if Kit.button(x + 346 * s, y, 170 * s, 24 * s, "Find similar blocks", { kind = "accent", font = "micro" }) then
    found = M.find(S, pair, mid, scope, which, S.g3NightLoose == true)
  end
  y = y + 32 * s
  if not found then return y end
  if #found.items == 0 then
    Kit.text("small", "Nothing similar found.", x, y, PAL.faint)
    return y + 24 * s
  end
  local hide = S.g3NightHideLit ~= false
  local fixing = S.g3NightFix
  local shown, fixAt = {}, nil
  for _, item in ipairs(found.items) do
    if item.stale then refreshThumbs(S, item) end
    if not (hide and item.already) or item == fixing then
      shown[#shown + 1] = item
      if item == fixing then fixAt = #shown end
    end
  end
  if fixing and not fixAt then S.g3NightFix, fixing = nil, nil end
  Kit.text("small", ("%d found%s"):format(#found.items,
    hide and ("  -  %d already lit, hidden"):format(#found.items - #shown) or ""), x, y + 5 * s, PAL.detail)
  if Kit.chip(x + 260 * s, y, 150 * s, 24 * s, "Hide already lit", hide, PAL.blue, nil,
      "Hide blocks that already have a night look") then
    S.g3NightHideLit = not hide
  end
  y = y + 30 * s
  -- Cards: day | night, a tick box, tileset and block. The block being
  -- fixed opens under its row.
  local cw, chh = 150 * s, 62 * s
  local cols = math.max(1, math.floor((w + 6 * s) / (cw + 6 * s)))
  local fixRow = fixAt and math.floor((fixAt - 1) / cols)
  local fixH = 0
  if fixing then
    fixH = M.fixFound(S, App, fixing, x, y + (fixRow + 1) * (chh + 6 * s), w) + 6 * s
  end
  local ticked = 0
  local rightDown = love.mouse and love.mouse.isDown and love.mouse.isDown(2)
  for n, item in ipairs(shown) do
    local row = math.floor((n - 1) / cols)
    local cx = x + ((n - 1) % cols) * (cw + 6 * s)
    local cy = y + row * (chh + 6 * s) + ((fixRow and row > fixRow) and fixH or 0)
    Theme.col(item.ticked and PAL.blue or PAL.rowBg, item.ticked and 0.18 or 0.6)
    love.graphics.rectangle("fill", cx, cy, cw, chh, 5 * s, 5 * s)
    Theme.stroke(cx, cy, cw, chh, 5 * s, item == fixing and PAL.yellow or PAL.cardBorder, item == fixing and 1 or 0.35,
      item == fixing and 2 or 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(item.dayImage, cx + 6 * s, cy + 6 * s, 0, 32 * s / 16, 32 * s / 16)
    love.graphics.draw(item.nightImage, cx + 42 * s, cy + 6 * s, 0, 32 * s / 16, 32 * s / 16)
    Kit.text("micro", Kit.ellipsize("micro", (item.pair:gsub("^general__rom_", "general ")), cw - 84 * s), cx + 80 * s, cy + 6 * s, PAL.muted)
    Kit.text("small", ("block %d"):format(item.mid), cx + 80 * s, cy + 20 * s, PAL.text)
    Kit.text("micro", item.already and "has a night look" or ("%d px"):format(item.count), cx + 80 * s, cy + 38 * s,
      item.already and PAL.yellow or PAL.faint)
    Kit.text("micro", item.ticked and "[x]" or "[ ]", cx + 6 * s, cy + 44 * s, item.ticked and PAL.heading or PAL.faint)
    Kit.offerTooltip(cx, cy, cw, chh, "Click to tick or untick; right-click to fix it here")
    if rightDown and Kit.hover(cx, cy, cw, chh) and not S._g3NightRightDown then
      if item == fixing then S.g3NightFix = nil else S.g3NightFix = item end
    elseif Kit.press(cx, cy, cw, chh) then item.ticked = not item.ticked end
    if item.ticked then ticked = ticked + 1 end
  end
  S._g3NightRightDown = rightDown
  y = y + math.ceil(#shown / cols) * (chh + 6 * s) + fixH + 4 * s
  if Kit.button(x, y, 200 * s, 26 * s, ("Give %d block%s this look"):format(ticked, ticked == 1 and "" or "s"),
      { kind = "primary", font = "micro" }) and ticked > 0 then
    local n = 0
    for _, item in ipairs(found.items) do
      if item.ticked and DN.applySimilar(S.project, item) then n = n + 1; item.already = true; item.ticked = false end
    end
    if n > 0 then App.markDirty() end
    S.status = ("%d block%s now light up at night like block %d"):format(n, n == 1 and "" or "s", mid)
  end
  if Kit.button(x + 206 * s, y, 90 * s, 26 * s, "All", { kind = "ghost", font = "micro" }) then
    for _, item in ipairs(shown) do item.ticked = true end
  end
  if Kit.button(x + 300 * s, y, 90 * s, 26 * s, "None", { kind = "ghost", font = "micro" }) then
    for _, item in ipairs(found.items) do item.ticked = false end
  end
  if Kit.button(x + 394 * s, y, 90 * s, 26 * s, "Close", { kind = "ghost", font = "micro" }) then
    S.g3NightFound, S.g3NightFix, S.g3NightFixSel = nil, nil, nil
  end
  return y + 36 * s
end

--- Is the mouse over the map editor's time bar?
function M.mapBarHit(S)
  local r = S._g3DayNightBarRect
  return r ~= nil and Kit.hit(r[1], r[2], r[3], r[4])
end

function M.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local fy, view, vx, vw = RegList.beginForm(S, x, y, w, h, "g3DayNightScroll", "daynight", 12 * s)
  vw = vw - 10 * s
  local top = fy
  local cfg = DN.settings(S.project)

  Kit.caption(vx, fy, "DAY AND NIGHT")
  fy = fy + 22 * s
  Kit.text("small", Kit.ellipsize("small",
    "Outdoor maps follow the player's own clock. Buildings, caves and battles look the same all day.",
    vw), vx, fy, PAL.muted)
  fy = fy + 26 * s
  local on, changed = Kit.checkbox(vx, fy, math.min(vw, 360 * s), 30 * s, DN.enabled(S.project),
    "Use day and night in this mod")
  if changed then
    local before = #DN.paintedBlocks(S.project)
    local game = require("Generation").id(S)
    if DN.setEnabled(S.project, on, game == "firered" or game == "leafgreen") then
      App.markDirty()
      DN.syncCrystalPopulation(S) -- Encounter tables follow the clock (GAME PATCHES)
      local added = #DN.paintedBlocks(S.project) - before
      if added > 0 then S.status = ("Day and night on -- %d blocks start with the default night look"):format(added) end
    end
  end
  fy = fy + 40 * s

  -- Hours.
  Kit.text("micro", "PARTS OF THE DAY  (hour it starts, 0-23)", vx, fy, PAL.caption)
  fy = fy + 16 * s
  local col = math.max(120 * s, math.floor(vw / 4))
  local rows = { { "morning", "Morning" }, { "day", "Day" }, { "night", "Night" }, { "blend", "Fade (min)" } }
  for i, row in ipairs(rows) do
    local cx = vx + (i - 1) * col
    if cx + 110 * s > vx + vw then cx = vx; fy = fy + 58 * s end
    Kit.text("small", row[2], cx, fy, PAL.text)
    local v = RegList.num(App, "g3dn_" .. row[1], cx, fy + 18 * s, 70 * s, 26 * s, cfg[row[1]])
    if v ~= cfg[row[1]] then
      local max = row[1] == "blend" and 180 or 23
      set(S, App, row[1], math.max(0, math.min(max, math.floor(tonumber(v) or Core.DEFAULTS[row[1]]))))
    end
  end
  fy = fy + 52 * s
  local okHours = cfg.morning < cfg.day and cfg.day < cfg.night
  Kit.text("micro", okHours and "Defaults: morning 4, day 10, night 18. A new part fades in over the fade minutes."
    or "Morning, day and night must start in that order.", vx, fy, okHours and PAL.faint or PAL.red)
  fy = fy + 24 * s

  -- Looks.
  Kit.text("micro", "LOOKS  (every colour is multiplied by the tint; day is as the game draws it)", vx, fy, PAL.caption)
  fy = fy + 16 * s
  for i, row in ipairs({ { "morningTint", "Morning tint" }, { "nightTint", "Night tint" } }) do
    local cx = vx + (i - 1) * math.max(220 * s, math.floor(vw / 2))
    if cx + 200 * s > vx + vw then cx = vx; if i > 1 then fy = fy + 34 * s end end
    Kit.text("small", row[2], cx, fy + 6 * s, PAL.text)
    local value = Kit.textfield("g3dn_" .. row[1], cx + 96 * s, fy, 90 * s, 26 * s, cfg[row[1]], Core.DEFAULTS[row[1]],
      "rrggbb -- ffffff leaves colours as they are")
    if value ~= cfg[row[1]] and Core.hex(value) then set(S, App, row[1], value:lower():gsub("^#", "")) end
    local r, g, b = Core.hex(cfg[row[1]])
    if r then swatch(cx + 192 * s, fy + 3 * s, 20 * s, r, g, b) end
  end
  fy = fy + 36 * s
  if Kit.button(vx, fy, 150 * s, 24 * s, "Default settings", { kind = "ghost", font = "micro",
      tooltip = "Hours 4 / 10 / 18, 30-minute fade, the default tints" }) then
    local any = false
    for _, k in ipairs({ "morning", "day", "night", "blend", "morningTint", "nightTint" }) do
      any = DN.set(S.project, k, Core.DEFAULTS[k]) or any
    end
    if any then App.markDirty() end
  end
  fy = fy + 36 * s

  -- Preview and test hour.
  Kit.text("micro", "PREVIEW  (the same time shows in the map editor and GFX > Blocks)", vx, fy, PAL.caption)
  fy = fy + 16 * s
  fy = fy + M.timeBar(S, App, vx, fy, math.min(vw, 620 * s)) + 12 * s
  local t = os.date("*t")
  local _, _, _, period = Core.tintAt(cfg, t.hour, t.min)
  Kit.text("small", ("Your clock: %02d:%02d, %s"):format(t.hour, t.min, period), vx, fy, PAL.detail)
  fy = fy + 26 * s
  Kit.text("small", "Test hour", vx, fy + 6 * s, PAL.text)
  local testText = cfg.testHour and tostring(cfg.testHour) or ""
  local typed = Kit.textfield("g3dn_testHour", vx + 96 * s, fy, 60 * s, 26 * s, testText, "off",
    "Playtests use this hour instead of the clock. Empty = the real clock.")
  if typed ~= testText then
    local n = tonumber(typed)
    if typed == "" then set(S, App, "testHour", nil)
    elseif n and n >= 0 and n <= 23 then set(S, App, "testHour", math.floor(n)) end
  end
  Kit.text("micro", cfg.testHour and "The game is pinned to this hour -- clear it before you share the mod."
    or "Empty: the game uses the device's clock.", vx + 166 * s, fy + 8 * s, cfg.testHour and PAL.yellow or PAL.faint)
  fy = fy + 40 * s

  -- Wild encounters with lists of their own for a part of the day.
  -- one row per map and kind: "morning / day / night"
  local timed, seen = {}, {}
  for _, e in ipairs(DN.timeTables(S.project)) do
    local key = e.id .. "|" .. e.kind
    if not seen[key] then seen[key] = { id = e.id, kind = e.kind, periods = {} }; timed[#timed + 1] = seen[key] end
    table.insert(seen[key].periods, e.period)
  end
  Kit.text("micro", ("WILD ENCOUNTERS BY TIME OF DAY  (%d table%s)"):format(#timed, #timed == 1 and "" or "s"), vx, fy, PAL.caption)
  fy = fy + 16 * s
  Kit.text("small", Kit.ellipsize("small",
    "In Encounters, pick a map, then Morning, Day or Night: morning, day and night get lists of their own and the all-day list is off.",
    vw), vx, fy, PAL.muted)
  fy = fy + 24 * s
  if #timed == 0 then
    Kit.text("small", "None yet.", vx, fy, PAL.faint)
    fy = fy + 24 * s
  end
  local kindNames = { land = "Grass", water = "Surf", rocks = "Rock Smash", fishing = "Fishing" }
  for _, e in ipairs(timed) do
    Kit.text("small", Kit.ellipsize("small", ("%s  -  %s  -  %s"):format(
      require("Gen3Labels").map(e.id), kindNames[e.kind] or e.kind, table.concat(e.periods, " / ")), vw - 220 * s),
      vx, fy + 5 * s, PAL.text)
    if Kit.button(vx + vw - 210 * s, fy, 100 * s, 24 * s, "Open", { kind = "ghost", font = "micro",
        tooltip = "Show these lists in Encounters" }) then
      S.tab, S.g3EncounterSection, S.g3EncounterId = "encounters", "wild", e.id
      S.g3EncounterKind, S.g3EncounterTime = e.kind, e.periods[1]
    end
    if Kit.button(vx + vw - 100 * s, fy, 100 * s, 24 * s, "Remove", { kind = "ghost", font = "micro",
        tooltip = "Back to one all-day list for this map" }) then
      if DN.clearTimeLists(S.project, e.id, e.kind) then App.markDirty() end
    end
    fy = fy + 28 * s
  end
  fy = fy + 8 * s
  -- Night look: blocks with pixels of their own night colour.
  local painted = DN.paintedBlocks(S.project)
  Kit.text("micro", ("NIGHT LOOK  (%d blocks)"):format(#painted), vx, fy + 6 * s, PAL.caption)
  if #painted > 0 then removeAllButton(S, App, vx + vw - 210 * s, fy, 210 * s, 24 * s) end
  local missing = DN.missingDefaultLooks(S.project)
  if missing > 0 and Kit.button(vx + vw - 420 * s, fy, 204 * s, 24 * s, ("Add default night looks (%d)"):format(missing),
      { kind = "accent", font = "micro",
        tooltip = "Blocks with no night look get the default one; blocks you've drawn keep yours" }) then
    local n = DN.addDefaultLooks(S.project)
    if n > 0 then App.markDirty() end
    S.status = ("%d blocks got the default night look"):format(n)
  end
  fy = fy + 30 * s
  Kit.text("small", Kit.ellipsize("small",
    "In GFX > Blocks, open a block, turn on Night look, select pixels and give them a night colour (lit windows, lamps).",
    vw), vx, fy, PAL.muted)
  fy = fy + 24 * s
  if #painted == 0 then
    Kit.text("small", "None yet.", vx, fy, PAL.faint)
    fy = fy + 24 * s
  end
  for _, e in ipairs(painted) do
    local n = 0
    for _ in pairs(DN.nightPixels(S.project, e.pair, e.mid)) do n = n + 1 end
    Kit.text("small", Kit.ellipsize("small", ("%s  -  block %d  -  %d pixels with a night colour"):format(e.pair, e.mid, n),
      vw - 220 * s), vx, fy + 5 * s, PAL.text)
    if Kit.button(vx + vw - 210 * s, fy, 100 * s, 24 * s, "Open", { kind = "ghost", font = "micro",
        tooltip = "Show this block in GFX > Blocks" }) then
      S.g3GfxMode, S.g3BlockPair, S.g3BlockId, S.g3PickLights = "blocks", e.pair, e.mid, true
      S._g3BlockLastPair = e.pair
    end
    if Kit.button(vx + vw - 100 * s, fy, 100 * s, 24 * s, "Remove", { kind = "ghost", font = "micro",
        tooltip = "Remove this block's night look: the whole block darkens at night again" }) then
      if DN.clearNightLook(S.project, e.pair, e.mid) then App.markDirty() end
    end
    fy = fy + 28 * s
  end

  -- Lit colours (the earlier, whole-colour way): still honoured.
  local lit = DN.litList(S.project)
  if #lit > 0 then
    fy = fy + 8 * s
    Kit.text("micro", ("LIT COLOURS  (every pixel of the colour stays lit; %d of %d)"):format(#lit, Core.MAX_LIT), vx, fy, PAL.caption)
    fy = fy + 18 * s
    local tr, tg, tb = Core.hex(cfg.nightTint)
    for _, e in ipairs(lit) do
      local c = require("Gen3Blocks").paletteColours(S, e.pair, e.pal)[e.colour] or { 0, 0, 0 }
      swatch(vx, fy + 2 * s, 20 * s, c[1], c[2], c[3])
      local nr, ng, nb = Core.grade(c[1] * 255, c[2] * 255, c[3] * 255, tr or 1, tg or 1, tb or 1)
      swatch(vx + 24 * s, fy + 2 * s, 20 * s, nr / 255, ng / 255, nb / 255)
      Kit.text("small", Kit.ellipsize("small", ("%s  -  palette %d, colour %d  -  %d pixels in its game blocks"):format(
        e.pair, e.pal, e.colour, DN.colourUses(S, e.pair, e.pal, e.colour)), vw - 170 * s), vx + 54 * s, fy + 5 * s, PAL.text)
      if Kit.button(vx + vw - 100 * s, fy, 100 * s, 24 * s, "Not lit", { kind = "ghost", font = "micro",
          tooltip = "This colour darkens at night again" }) and DN.setLit(S.project, e.pair, e.pal, e.colour, false) then
        App.markDirty()
      end
      fy = fy + 28 * s
    end
  end
  fy = fy + 8 * s
  FormPane.finish(S, "g3DayNightScroll", top, fy, view)
end

return M
