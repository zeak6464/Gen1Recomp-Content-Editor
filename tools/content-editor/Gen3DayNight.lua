-- Day and night for FireRed projects: a Crystal-style clock (the device's
-- own time and weekday), morning / day / night looks on outdoor maps, and
-- colours that stay lit at night (windows, lamps, signs).
--
-- Settings live in project.gen3DayNight:
--   { enabled = true, morning = hour, day = hour, night = hour, blend = minutes,
--     morningTint = "rrggbb", nightTint = "rrggbb", testHour = hour or nil,
--     lit = { [pair] = { ["<palette>/<colour>"] = true } },
--     paint = { [pair] = { ["<block>"] = { px = 256 chars, cols = { "rrggbb", ... } } } },
--     encounters = { [table id] = { [period] = { [kind] = { rate =, slots = } } } } }
-- `paint` is the night look drawn pixel by pixel: in `px`, "." keeps the
-- pixel (it just darkens with the night tint) and "1"-"9", "a"-"z" pick a
-- colour from `cols` that the pixel shows at night instead, untinted.
-- `encounters` are wild tables by part of the day (Crystal's morning / day /
-- night grass): a kind (land, water, rocks, fishing) given lists of its own
-- gets one for each part and its all-day list is off; kinds without keep
-- their all-day list.
-- Only what differs from Gen3DayNightCore.DEFAULTS is stored. The rules
-- themselves are in Gen3DayNightCore; the game side is Gen3DayNightRuntime.
local Core = require("Gen3DayNightCore")

local M = {}

M.Core = Core
M.PREVIEWS = { { id = nil, label = "Off" }, { id = "morning", label = "Morning" }, { id = "day", label = "Day" }, { id = "night", label = "Night" } }

local function own(project)
  project.gen3DayNight = project.gen3DayNight or {}
  return project.gen3DayNight
end

-- Encounter tables' mark on one of Crystal's FireRed tables:
-- { id = the table id the Encounters list shows (ROUTE_1 for FR_ROUTE_1),
--   cleared = true once you've put it back on its all-day list }, or nil.
local function crystalMark(project, targetId)
  return ((((project or {}).gen3DayNight or {}).crystalFilled) or {})[targetId]
end

local function tidy(project)
  local d = project.gen3DayNight
  if d and d.lit then
    for pair, set in pairs(d.lit) do if not next(set) then d.lit[pair] = nil end end
    if not next(d.lit) then d.lit = nil end
  end
  if d and d.paint then
    for pair, set in pairs(d.paint) do if not next(set) then d.paint[pair] = nil end end
    if not next(d.paint) then d.paint = nil end
  end
  if d and d.allDay then
    for id, kinds in pairs(d.allDay) do if not next(kinds) then d.allDay[id] = nil end end
    if not next(d.allDay) then d.allDay = nil end
  end
  if d and d.crystalFilled and not next(d.crystalFilled) then d.crystalFilled = nil end
  if d and d.encounters then
    for id, periods in pairs(d.encounters) do
      for period, kinds in pairs(periods) do if not next(kinds) then periods[period] = nil end end
      if not next(periods) then d.encounters[id] = nil end
    end
    if not next(d.encounters) then d.encounters = nil end
  end
  if d and not next(d) then project.gen3DayNight = nil end
end

function M.enabled(project)
  return ((project or {}).gen3DayNight or {}).enabled == true
end

--- Turn day and night on or off. Turning it on in a project with no night
-- looks yet starts from the default ones (Gen3DayNightDefaults).
-- `kanto` = false (Emerald): the defaults and Crystal's lists are FireRed's,
-- so Encounter tables stay off and no default looks are added.
function M.setEnabled(project, on, kanto)
  kanto = kanto ~= false
  if M.enabled(project) == (on == true) then return false end
  own(project).enabled = on == true or nil
  if on then project.gen3DayNight.encountersOff = (not kanto) or nil end -- Encounter tables come on with the clock
  if on and kanto and not (project.gen3DayNight.paint and next(project.gen3DayNight.paint)) then
    M.addDefaultLooks(project)
  end
  tidy(project)
  return true
end

--- The default night looks: { [pair] = { ["<block>"] = { px =, cols = } } }.
function M.defaultLooks()
  local ok, looks = pcall(require, "Gen3DayNightDefaults")
  return ok and type(looks) == "table" and looks or {}
end

--- Give every block in the defaults that has no night look its default one;
-- blocks with a look of their own keep it. Returns how many were added.
function M.addDefaultLooks(project)
  local n = 0
  for pair, set in pairs(M.defaultLooks()) do
    for mid, rec in pairs(set) do
      if not M.hasNightPixels(project, pair, mid) then
        local d = own(project)
        d.paint = d.paint or {}
        d.paint[pair] = d.paint[pair] or {}
        local cols = {}
        for i, c in ipairs(rec.cols) do cols[i] = c end
        d.paint[pair][tostring(mid)] = { px = rec.px, cols = cols }
        n = n + 1
      end
    end
  end
  if n > 0 then M.paintRevision = (M.paintRevision or 0) + 1 end
  tidy(project)
  return n
end

--- How many default night looks the project doesn't have.
function M.missingDefaultLooks(project)
  local n = 0
  for pair, set in pairs(M.defaultLooks()) do
    for mid in pairs(set) do if not M.hasNightPixels(project, pair, mid) then n = n + 1 end end
  end
  return n
end

--- The settings in effect (defaults filled in).
function M.settings(project)
  local out = {}
  for k, v in pairs(Core.DEFAULTS) do out[k] = v end
  for k, v in pairs((project or {}).gen3DayNight or {}) do
    if k ~= "lit" and k ~= "enabled" and k ~= "paint" and k ~= "encounters" and k ~= "crystal"
        and k ~= "encountersOff" and k ~= "allDay" and k ~= "crystalFilled" then out[k] = v end
  end
  return out
end

--- Change one setting; back to its default removes it.
function M.set(project, key, value)
  if value == Core.DEFAULTS[key] then value = nil end
  local d = own(project)
  if d[key] == value then tidy(project) return false end
  d[key] = value
  tidy(project)
  return true
end

-- Lit colours ---------------------------------------------------------------

local function litKey(pal, colour) return ("%d/%d"):format(pal, colour) end

function M.isLit(project, pair, pal, colour)
  local set = ((((project or {}).gen3DayNight or {}).lit or {})[pair])
  return set ~= nil and set[litKey(pal, colour)] == true
end

--- Turn "stays lit at night" on or off for one palette colour of a tileset.
function M.setLit(project, pair, pal, colour, on)
  if colour == 0 or M.isLit(project, pair, pal, colour) == (on == true) then return false end
  local d = own(project)
  d.lit = d.lit or {}
  d.lit[pair] = d.lit[pair] or {}
  d.lit[pair][litKey(pal, colour)] = on == true or nil
  tidy(project)
  return true
end

--- Every lit colour: { {pair=, pal=, colour=}, ... }, sorted.
function M.litList(project)
  local out = {}
  for pair, set in pairs((((project or {}).gen3DayNight or {}).lit) or {}) do
    for key in pairs(set) do
      local pal, colour = key:match("^(%d+)/(%d+)$")
      if pal then out[#out + 1] = { pair = pair, pal = tonumber(pal), colour = tonumber(colour) } end
    end
  end
  table.sort(out, function(a, b)
    if a.pair ~= b.pair then return a.pair < b.pair end
    if a.pal ~= b.pal then return a.pal < b.pal end
    return a.colour < b.colour
  end)
  return out
end

--- How many pixels of the tileset's saved blocks use a palette colour (a
-- lit colour that is also used elsewhere lights that up too).
function M.colourUses(S, pair, pal, colour)
  local pack = require("Gen3Blocks").pack(S, pair)
  if not pack then return 0 end
  local want, n = pal * 16 + colour, 0
  for _, pixels in ipairs({ pack.under or {}, pack.over or {} }) do
    for i = 1, #pixels do if pixels[i] == want then n = n + 1 end end
  end
  return n
end

-- Night paint: pixels with their own night colour ---------------------------------

local DIGITS = "123456789abcdefghijklmnopqrstuvwxyz"
M.MAX_NIGHT_COLOURS = #DIGITS

--- A block's night colours: { [pixel 1-256] = "rrggbb" }.
function M.nightPixels(project, pair, mid)
  local rec = ((((project or {}).gen3DayNight or {}).paint or {})[pair] or {})[tostring(mid)]
  local out = {}
  if not rec then return out end
  for i = 1, 256 do
    local k = DIGITS:find(rec.px:sub(i, i), 1, true)
    if k and rec.cols[k] then out[i] = rec.cols[k] end
  end
  return out
end

function M.hasNightPixels(project, pair, mid)
  return ((((project or {}).gen3DayNight or {}).paint or {})[pair] or {})[tostring(mid)] ~= nil
end

--- Give pixels (a list of 1-256) a night colour ("rrggbb"), or nil to put
-- them back to normal. Returns true when something changed.
function M.setNightPixels(project, pair, mid, pixels, colour)
  if colour ~= nil then
    colour = tostring(colour):lower():gsub("^#", "")
    if not Core.hex(colour) then return false end
  end
  local cur = M.nightPixels(project, pair, mid)
  local changed = false
  for _, i in ipairs(pixels) do
    if i >= 1 and i <= 256 and cur[i] ~= colour then cur[i] = colour; changed = true end
  end
  if not changed then return false end
  local cols, index, px = {}, {}, {}
  for i = 1, 256 do
    local c = cur[i]
    if c and not index[c] then
      if #cols >= #DIGITS then return false end
      cols[#cols + 1] = c; index[c] = #cols
    end
    px[i] = c and DIGITS:sub(index[c], index[c]) or "."
  end
  M.paintRevision = (M.paintRevision or 0) + 1
  local d = own(project)
  d.paint = d.paint or {}
  d.paint[pair] = d.paint[pair] or {}
  d.paint[pair][tostring(mid)] = #cols > 0 and { px = table.concat(px), cols = cols } or nil
  tidy(project)
  return true
end

--- A block was turned a quarter turn clockwise (GFX > Blocks > Rotate
-- block): its night colours turn with it. Returns true when it had any.
function M.rotateNightPixels(project, pair, mid)
  local rec = ((((project or {}).gen3DayNight or {}).paint or {})[pair] or {})[tostring(mid)]
  if not rec or type(rec.px) ~= "string" or #rec.px ~= 256 then return false end
  local out = {}
  for y = 0, 15 do
    for x = 0, 15 do
      local i = (15 - x) * 16 + y + 1
      out[y * 16 + x + 1] = rec.px:sub(i, i)
    end
  end
  rec.px = table.concat(out)
  M.paintRevision = (M.paintRevision or 0) + 1
  return true
end

--- A block was flipped (GFX > Blocks > H-flip block / V-flip block): its
-- night colours flip with it. Returns true when it had any.
function M.flipNightPixels(project, pair, mid, horizontal)
  local rec = ((((project or {}).gen3DayNight or {}).paint or {})[pair] or {})[tostring(mid)]
  if not rec or type(rec.px) ~= "string" or #rec.px ~= 256 then return false end
  local out = {}
  for y = 0, 15 do
    for x = 0, 15 do
      local i = (horizontal and y or 15 - y) * 16 + (horizontal and 15 - x or x) + 1
      out[y * 16 + x + 1] = rec.px:sub(i, i)
    end
  end
  rec.px = table.concat(out)
  M.paintRevision = (M.paintRevision or 0) + 1
  return true
end

--- Every painted block: { {pair=, mid=}, ... }.
function M.paintedBlocks(project)
  local out = {}
  for pair, set in pairs((((project or {}).gen3DayNight or {}).paint) or {}) do
    for mid in pairs(set) do out[#out + 1] = { pair = pair, mid = tonumber(mid) } end
  end
  table.sort(out, function(a, b) if a.pair ~= b.pair then return a.pair < b.pair end return a.mid < b.mid end)
  return out
end

--- A block's finished day picture: { [1-256] = {r, g, b} (0-1) or false }.
function M.dayPixels(S, pair, mid)
  local Blocks = require("Gen3Blocks")
  local def = Blocks.definition(S, pair, mid)
  local pack = Blocks.pack(S, pair)
  if not def or not pack then return nil end
  local u, o = Blocks.composeBlock(S, pair, def)
  if not u then return nil end
  local out = {}
  for i = 1, 256 do
    local v = (o and o[i] and o[i] % 16 ~= 0) and o[i] or u[i]
    local c = v and v % 16 ~= 0 and pack.rgb[math.floor(v / 16)] and pack.rgb[math.floor(v / 16)][v % 16]
    if not c and v and u[i] then
      -- colour 0 of the bottom layer shows the palette's backdrop
      c = pack.rgb[math.floor(u[i] / 16)] and pack.rgb[math.floor(u[i] / 16)][u[i] % 16]
    end
    out[i] = c and { c[1] / 255, c[2] / 255, c[3] / 255 } or false
  end
  return out
end

local overlays = {}
--- A 16x16 image of a block's night pixels (transparent elsewhere), or nil.
function M.nightOverlay(S, pair, mid)
  local rec = ((((S.project or {}).gen3DayNight or {}).paint or {})[pair] or {})[tostring(mid)]
  if not rec then return nil end
  local key = pair .. "|" .. mid .. "|" .. rec.px .. table.concat(rec.cols, ",")
  local hit = overlays[pair .. "|" .. mid]
  if hit and hit.key == key then return hit.image end
  local data = love.image.newImageData(16, 16)
  for i, c in pairs(M.nightPixels(S.project, pair, mid)) do
    local r, g, b = Core.hex(c)
    data:setPixel((i - 1) % 16, math.floor((i - 1) / 16), r, g, b, 1)
  end
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  overlays[pair .. "|" .. mid] = { key = key, image = image }
  return image
end

-- Finding similar blocks -------------------------------------------------------
--
-- A block with a night look teaches the rule: each day colour it changed
-- turns into its night colour, and the colours right next to those pixels
-- (a window's frame) mark where the rule applies. In another block, a patch
-- of those day colours is lit when at least 60% of what borders it (inside
-- the block) is frame -- windows yes, blue roofs and water no.

local function hexOf(c)
  return c and ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
    math.floor(c[3] * 255 + 0.5)) or nil
end

--- What a reference block's night look does: { map = {day -> night}, frame = {colour = true} }.
function M.learn(S, pair, mid)
  local day = M.dayPixels(S, pair, mid)
  local night = M.nightPixels(S.project, pair, mid)
  if not day or not next(night) then return nil end
  local votes, frame = {}, {}
  for i, n in pairs(night) do
    local d = hexOf(day[i])
    if d then
      votes[d] = votes[d] or {}
      votes[d][n] = (votes[d][n] or 0) + 1
    end
  end
  local map = {}
  for d, v in pairs(votes) do
    local best, most = nil, -1
    for n, count in pairs(v) do if count > most then best, most = n, count end end
    map[d] = best
  end
  for i in pairs(night) do
    local x, y = (i - 1) % 16, math.floor((i - 1) / 16)
    for _, dd in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + dd[1], y + dd[2]
      if nx >= 0 and nx < 16 and ny >= 0 and ny < 16 then
        local k = ny * 16 + nx + 1
        local h = hexOf(day[k])
        if h and not night[k] and not map[h] then frame[h] = true end
      end
    end
  end
  if not next(frame) then return nil end
  return { map = map, frame = frame }
end

M.FRAME_SHARE = 0.6
M.MIN_PATCH = 4 -- pixels; smaller specks are left alone

--- The pixels of a block the rule lights: { [pixel] = "rrggbb" }, and how many.
function M.matchBlock(S, rule, pair, mid, opts)
  opts = opts or {}
  local share, minPatch = opts.share or M.FRAME_SHARE, opts.minPatch or M.MIN_PATCH
  local day = M.dayPixels(S, pair, mid)
  if not day then return {}, 0 end
  local hex = {}
  for i = 1, 256 do hex[i] = hexOf(day[i]) end
  local out, total, seen = {}, 0, {}
  for i = 1, 256 do
    if not seen[i] and rule.map[hex[i] or ""] then
      local comp, stack, fr, other = {}, { i }, 0, 0
      seen[i] = true
      while #stack > 0 do
        local k = table.remove(stack)
        comp[#comp + 1] = k
        local x, y = (k - 1) % 16, math.floor((k - 1) / 16)
        for _, dd in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + dd[1], y + dd[2]
          if nx >= 0 and nx < 16 and ny >= 0 and ny < 16 then
            local n = ny * 16 + nx + 1
            local h = hex[n] or ""
            if rule.map[h] then
              if not seen[n] then seen[n] = true; stack[#stack + 1] = n end
            elseif rule.frame[h] then fr = fr + 1
            else other = other + 1 end
          end
        end
      end
      if #comp >= minPatch and fr > 0 and fr / (fr + other) >= share then
        for _, k in ipairs(comp) do out[k] = rule.map[hex[k]] end
        total = total + #comp
      end
    end
  end
  return out, total
end

--- Tilesets that outdoor maps use (where night shows).
function M.outdoorPairs(S)
  local ids, usedBy = require("Gen3Blocks").pairs(S)
  local out = {}
  for _, pair in ipairs(ids or {}) do
    for _, mapId in ipairs(usedBy[pair] or {}) do
      if M.isOutdoorMap(S, mapId) or M.mapKind(S, mapId) == nil and (S.project.maps or {})[mapId] then
        out[#out + 1] = pair
        break
      end
    end
  end
  table.sort(out)
  return out
end

M.LOOSE = { share = 0.4, minPatch = 2 } -- "Looser match"

--- Every distinct rule taught by the given examples ({pair=, mid=} each).
function M.rules(S, examples)
  local out, seen = {}, {}
  for _, e in ipairs(examples) do
    local rule = M.learn(S, e.pair, e.mid)
    if rule then
      local keys = {}
      for d, n in pairs(rule.map) do keys[#keys + 1] = d .. ">" .. n end
      for f in pairs(rule.frame) do keys[#keys + 1] = "|" .. f end
      table.sort(keys)
      local key = table.concat(keys, ",")
      if not seen[key] then seen[key] = true; out[#out + 1] = rule end
    end
  end
  return out
end

--- Blocks like the examples, in `pairList`:
-- { {pair=, mid=, pixels=, count=, already=}, ... }. `examples` is a list of
-- {pair=, mid=} (blocks with a night look); `opts` = { share=, minPatch= }.
function M.findSimilarTo(S, examples, pairList, opts)
  local rules = M.rules(S, examples)
  if #rules == 0 then return nil, "Give a block a night look first -- it's the example." end
  local skip = {}
  for _, e in ipairs(examples) do skip[e.pair .. "|" .. e.mid] = true end
  local Blocks = require("Gen3Blocks")
  local out = {}
  for _, pair in ipairs(pairList) do
    for _, mid in ipairs(Blocks.ids(S, pair) or {}) do
      if not skip[pair .. "|" .. mid] then
        local pixels, count = {}, 0
        for _, rule in ipairs(rules) do
          local px = M.matchBlock(S, rule, pair, mid, opts)
          for k, c in pairs(px) do if not pixels[k] then pixels[k] = c; count = count + 1 end end
        end
        if count > 0 then
          out[#out + 1] = { pair = pair, mid = mid, pixels = pixels, count = count,
            already = M.hasNightPixels(S.project, pair, mid) }
        end
      end
    end
  end
  return out, nil, #rules
end

--- Blocks like one reference block (see M.findSimilarTo).
function M.findSimilar(S, refPair, refMid, pairList, opts)
  if not M.learn(S, refPair, refMid) then return nil, "Give this block a night look first -- it's the example." end
  return M.findSimilarTo(S, { { pair = refPair, mid = refMid } }, pairList, opts)
end

local function luminance(hex)
  local r, g, b = Core.hex(hex)
  return 0.299 * r + 0.587 * g + 0.114 * b
end

--- Light pixels of a block the search missed, the way an example is lit:
-- the chosen pixels' day colours, darkest to brightest, take the example's
-- night colours in the same order (so a window with other blues still gets
-- the example's gradient). likeExample only works it out: { [pixel] =
-- "rrggbb" } and how many; lightLikeExample writes it into the block.
-- Both return nil and why when they can't.
function M.likeExample(S, pair, mid, pixels, exPair, exMid)
  local rule = M.learn(S, exPair, exMid)
  if not rule then return nil, "The example has no night look" end
  local day = M.dayPixels(S, pair, mid)
  if not day or #pixels == 0 then return nil, "Select the pixels to light first" end
  local mine, seen = {}, {}
  for _, i in ipairs(pixels) do
    local h = hexOf(day[i])
    if h and not seen[h] then seen[h] = true; mine[#mine + 1] = h end
  end
  local theirs = {}
  for d in pairs(rule.map) do theirs[#theirs + 1] = d end
  table.sort(mine, function(a, b) return luminance(a) < luminance(b) end)
  table.sort(theirs, function(a, b) return luminance(a) < luminance(b) end)
  local to = {}
  for k, h in ipairs(mine) do
    local t = #mine == 1 and math.ceil(#theirs / 2) or 1 + math.floor((k - 1) * (#theirs - 1) / (#mine - 1) + 0.5)
    to[h] = rule.map[theirs[t]]
  end
  local out, n = {}, 0
  for _, i in ipairs(pixels) do
    local c = to[hexOf(day[i]) or ""]
    if c then out[i] = c; n = n + 1 end
  end
  return out, n
end

function M.lightLikeExample(S, pair, mid, pixels, exPair, exMid)
  local out, n = M.likeExample(S, pair, mid, pixels, exPair, exMid)
  if not out then return nil, n end
  local byColour = {}
  for i, c in pairs(out) do byColour[c] = byColour[c] or {}; table.insert(byColour[c], i) end
  for c, list in pairs(byColour) do M.setNightPixels(S.project, pair, mid, list, c) end
  return n
end

--- Take a block's night look away: the whole block darkens at night again.
function M.clearNightLook(project, pair, mid)
  if not M.hasNightPixels(project, pair, mid) then return false end
  local d = own(project)
  d.paint[pair][tostring(mid)] = nil
  M.paintRevision = (M.paintRevision or 0) + 1
  tidy(project)
  return true
end

--- Take every night look away. Returns how many blocks had one.
function M.clearAllNightLooks(project)
  local n = #M.paintedBlocks(project)
  if n == 0 then return 0 end
  own(project).paint = nil
  M.paintRevision = (M.paintRevision or 0) + 1
  tidy(project)
  return n
end

--- Give a found block its night pixels. Returns true when something changed.
function M.applySimilar(project, item)
  local byColour = {}
  for i, c in pairs(item.pixels) do
    byColour[c] = byColour[c] or {}
    byColour[c][#byColour[c] + 1] = i
  end
  local changed = false
  for c, list in pairs(byColour) do
    changed = M.setNightPixels(project, item.pair, item.mid, list, c) or changed
  end
  return changed
end

--- Map editor: draw the night pixels of the visible cells (call after the
-- tiles, with the preview shader off).
function M.drawMapNight(S, source, x0, y0, x1, y1, cell)
  if not M.previewIsNight(S) or not ((S.project.gen3DayNight or {}).paint) then return end
  love.graphics.setColor(1, 1, 1, 1)
  for cy = y0, y1 do
    for cx = x0, x1 do
      for _, layer in ipairs(source.layers or {}) do
        local ref = layer.visible ~= false and layer.cells[cy * source.cellWidth + cx + 1]
        local pair = ref and type(ref.source) == "string" and ref.source:match("^@runtime:(.+)$")
        local image = pair and M.nightOverlay(S, pair, ref.tile)
        if image then love.graphics.draw(image, cx * cell, cy * cell, 0, cell / 16, cell / 16) end
      end
    end
  end
end

--- A map's cells whose block has a night look: { {x, y, pair, block}, ... },
-- remembered until the night look or the map changes.
local paintedCellCache = {}
function M.paintedCells(S, mapId)
  local p = S.project or {}
  local source = (p.gen3Layered or {})[mapId] or (p.layeredMaps or {})[mapId]
  local key = tostring(M.paintRevision or 0) .. "|" .. tostring(source) .. "|" .. tostring(S.data)
  local hit = paintedCellCache[mapId]
  if hit and hit.key == key then return hit.cells end
  local cells = { width = 0 }
  if (p.gen3DayNight or {}).paint then
    if source then
      local w = source.cellWidth or 0
      cells.width = w
      for _, layer in ipairs(source.layers or {}) do
        if layer.visible ~= false then
          for i, ref in pairs(layer.cells or {}) do
            local pair = type(ref.source) == "string" and ref.source:match("^@runtime:(.+)$")
            if pair and M.hasNightPixels(p, pair, ref.tile) then
              cells[#cells + 1] = { (i - 1) % w, math.floor((i - 1) / w), pair, ref.tile }
            end
          end
        end
      end
    else
      local ok, layout = pcall(require("Gen3Map").layout, S.data, mapId, p)
      if ok and layout and layout.pair and layout.cellAt then
        cells.width = layout.width or 0
        for y = 0, (layout.height or 0) - 1 do
          for x = 0, (layout.width or 0) - 1 do
            local c = layout:cellAt(x, y)
            if c and M.hasNightPixels(p, layout.pair, c.mid) then cells[#cells + 1] = { x, y, layout.pair, c.mid } end
          end
        end
      end
    end
  end
  paintedCellCache[mapId] = { key = key, cells = cells }
  return cells
end

--- World view: draw a map's night pixels into its box (x, y, w wide), when
-- the preview time is night.
function M.drawWorldNight(S, mapId, x, y, w)
  if not M.previewIsNight(S) then return end
  local cells = M.paintedCells(S, mapId)
  if #cells == 0 or cells.width < 1 then return end
  local cs = w / cells.width
  love.graphics.setColor(1, 1, 1, 1)
  for _, c in ipairs(cells) do
    local image = M.nightOverlay(S, c[3], c[4])
    if image then love.graphics.draw(image, x + c[1] * cs, y + c[2] * cs, 0, cs / 16, cs / 16) end
  end
end

--- Is the preview time in the night part (when night pixels show)?
function M.previewIsNight(S)
  local h = M.previewHour(S)
  if not h then return false end
  local _, _, _, period = Core.tintAt(M.settings(S.project), math.floor(h) % 24, math.floor((h % 1) * 60))
  return period == "night"
end

-- Wild encounters by time of day ------------------------------------------------

M.ENCOUNTER_KINDS = { land = true, water = true, rocks = true, fishing = true }

local function copyArea(area)
  if type(area) ~= "table" then return nil end
  local out = { rate = tonumber(area.rate) or 0, slots = {} }
  for i, slot in ipairs(area.slots or area.mons or {}) do
    out.slots[i] = { species = slot.species or slot[1], minLevel = tonumber(slot.minLevel or slot[2]) or 1,
      maxLevel = tonumber(slot.maxLevel or slot.minLevel or slot[2]) or 1 }
  end
  return out
end
M.copyArea = copyArea

--- An encounter table's own list for one part of the day, or nil (the
-- table's usual list is used then).
function M.timeArea(project, id, period, kind)
  local t = ((((project or {}).gen3DayNight or {}).encounters or {})[id] or {})[period]
  return t and t[kind] or nil
end

--- Give a table its own list for a part of the day (a copy of `area`), or
-- nil to go back to the usual list. Returns true when something changed.
function M.setTimeArea(project, id, period, kind, area)
  if not M.ENCOUNTER_KINDS[kind] or not (period == "morning" or period == "day" or period == "night") then return false end
  if area == nil and M.timeArea(project, id, period, kind) == nil then return false end
  local d = own(project)
  d.encounters = d.encounters or {}
  d.encounters[id] = d.encounters[id] or {}
  d.encounters[id][period] = d.encounters[id][period] or {}
  d.encounters[id][period][kind] = copyArea(area)
  tidy(project)
  return true
end

--- Does this table's kind have lists of its own for the parts of the day?
-- Then its all-day list is off (while day and night is on).
function M.hasTimeLists(project, id, kind)
  for _, period in ipairs(Core.PERIODS) do
    if M.timeArea(project, id, period, kind) then return true end
  end
  return false
end

--- Give morning, day and night each their own list (copies of `area`, the
-- all-day list), keeping any they already have. The all-day list is off
-- from then on. Returns how many were added.
function M.startTimeLists(project, id, kind, area)
  local n = 0
  for _, period in ipairs(Core.PERIODS) do
    if not M.timeArea(project, id, period, kind) and M.setTimeArea(project, id, period, kind, area) then n = n + 1 end
  end
  return n
end

--- Back to one all-day list: drop the morning, day and night lists.
function M.clearTimeLists(project, id, kind)
  local changed = false
  for _, period in ipairs(Core.PERIODS) do
    changed = M.setTimeArea(project, id, period, kind, nil) or changed
  end
  -- a table Encounter tables filled in, now back on its all-day list: it
  -- isn't filled in again while Encounter tables stays on
  if changed and kind == "land" then
    for _, mark in pairs(((project.gen3DayNight or {}).crystalFilled) or {}) do
      if mark.id == id then mark.cleared = true end
    end
  end
  return changed
end

--- Tables with lists of their own for some part of the day, sorted:
-- { {id=, period=, kind=}, ... }.
function M.timeTables(project)
  local out = {}
  for id, periods in pairs((((project or {}).gen3DayNight or {}).encounters) or {}) do
    for period, kinds in pairs(periods) do
      for kind in pairs(kinds) do out[#out + 1] = { id = id, period = period, kind = kind } end
    end
  end
  local order = { morning = 1, day = 2, night = 3 }
  table.sort(out, function(a, b)
    if a.id ~= b.id then return a.id < b.id end
    if a.period ~= b.period then return order[a.period] < order[b.period] end
    return a.kind < b.kind
  end)
  return out
end

--- For the game: { [id] = { [period] = { [kind] = { rate, slots } } } }.
function M.compileEncounters(project)
  local out = {}
  for _, e in ipairs(M.timeTables(project)) do
    out[e.id] = out[e.id] or {}
    out[e.id][e.period] = out[e.id][e.period] or {}
    out[e.id][e.period][e.kind] = copyArea(M.timeArea(project, e.id, e.period, e.kind))
  end
  return out
end

-- Pokemon Crystal's encounters (GAME PATCHES > Encounter tables) -----------------

--- Crystal's seven grass slots (30, 30, 20, 10, 5, 4, 1 %) spread over
-- FireRed's twelve (20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 %) with the
-- same chances: FireRed slot i shows Crystal slot CRYSTAL_SLOTS[i].
M.CRYSTAL_SLOTS = { 1, 2, 1, 2, 3, 3, 4, 4, 5, 6, 5, 7 }

--- Encounter tables (GAME PATCHES > Real time clock): a setting of the
-- clock, so off while the clock is off, and turning the clock on turns
-- them on too (M.setEnabled). While on, FireRed's own tables get Pokemon
-- Crystal's morning / day / night lists as their own (M.populateCrystal);
-- off, those come back out (M.unpopulateCrystal) and every table uses its
-- all-day list. Lists you made yourself are kept either way.
function M.encountersEnabled(project)
  return M.enabled(project) and project.gen3DayNight.encountersOff ~= true
end

function M.setEncounters(project, on)
  if on and not M.enabled(project) then return false end -- the clock comes first
  if M.encountersEnabled(project) == (on == true) then return false end
  local d = own(project)
  d.encountersOff = (not on) or nil
  d.crystal = nil -- an earlier switch, folded into this one
  tidy(project)
  return true
end

--- A table that keeps its all-day list at every time, whatever the time
-- lists (yours or Crystal's) say.
function M.isAllDay(project, id, kind)
  local t = ((((project or {}).gen3DayNight or {}).allDay) or {})[id]
  return t ~= nil and t[kind] == true
end

function M.setAllDay(project, id, kind, on)
  if M.isAllDay(project, id, kind) == (on == true) then return false end
  local d = own(project)
  d.allDay = d.allDay or {}
  d.allDay[id] = d.allDay[id] or {}
  d.allDay[id][kind] = on == true or nil
  tidy(project)
  return true
end

--- Tables kept on their all-day list: { {id=, kind=}, ... }, sorted.
function M.allDayList(project)
  local out = {}
  for id, kinds in pairs((((project or {}).gen3DayNight or {}).allDay) or {}) do
    for kind in pairs(kinds) do out[#out + 1] = { id = id, kind = kind } end
  end
  table.sort(out, function(a, b) return a.id == b.id and a.kind < b.kind or a.id < b.id end)
  return out
end

-- kept for older callers
M.crystalEnabled = M.encountersEnabled
M.setCrystal = M.setEncounters

--- A FireRed land list from Crystal's seven { level, species } slots.
function M.crystalArea(slots, rate)
  local area = { rate = rate, slots = {} }
  for i, k in ipairs(M.CRYSTAL_SLOTS) do
    local c = slots[k]
    area.slots[i] = { species = c[2], minLevel = c[1], maxLevel = c[1] }
  end
  return area
end

--- Where Crystal's lists go: FireRed's own tables, { {crystal=, id=}, ... },
-- sorted. Maps added in a mod are never touched.
function M.crystalTargets(project)
  local C = require("Gen3CrystalEncounters")
  local out = {}
  for name, ids in pairs(C.kanto) do
    for _, id in ipairs(ids) do out[#out + 1] = { crystal = name, id = id } end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

--- For the game: { [table id] = { [period] = { land = { slots } } } }. The
-- tables keep their own encounter rate.
function M.compileCrystal(project)
  local C = require("Gen3CrystalEncounters")
  local out = {}
  for _, e in ipairs(M.crystalTargets(project)) do
    local m = C.maps[e.crystal]
    -- only tables the editor hasn't filled in yet (older projects); filled
    -- ones have them as their own lists, cleared ones use the all-day list
    if crystalMark(project, e.id) == nil then
      out[e.id] = {}
      for _, period in ipairs(Core.PERIODS) do
        out[e.id][period] = { land = M.crystalArea(m[period], nil) }
      end
    end
  end
  return out
end

--- Crystal's lists for an encounter table the editor shows (matched by map
-- group and number, like the game does), or nil: name, { [period] = area }.
function M.crystalFor(S, id)
  local C = require("Gen3CrystalEncounters")
  local catalog = (S.data or {}).encounters or {}
  local rec = catalog[id] or ((S.project or {}).encounters or {})[id]
  for _, e in ipairs(M.crystalTargets(S.project)) do
    local other = catalog[e.id]
    if e.id == id or (rec and other and rec.mapGroup ~= nil and other.mapGroup == rec.mapGroup
        and other.mapNum == rec.mapNum) then
      local m = C.maps[e.crystal]
      local lists = {}
      for i, period in ipairs(Core.PERIODS) do
        local base = rec and (rec.land or rec.grass)
        lists[period] = M.crystalArea(m[period], (base and base.rate) or 21)
      end
      return e.crystal, lists
    end
  end
end

--- Is this table filled in with Crystal's lists by Encounter tables (and
-- not put back on its all-day list since)?
function M.isCrystalFilled(project, id)
  for _, mark in pairs((((project or {}).gen3DayNight or {}).crystalFilled) or {}) do
    if mark.id == id and not mark.cleared then return true end
  end
  return false
end

--- The id the Encounters list shows for one of Crystal's FireRed tables.
function M.shownTableId(S, targetId)
  local labels = require("Gen3Labels")
  local ok, name = pcall(labels.map, targetId)
  local shown = ok and labels.preferredEncounterIds((S.project or {}).encounters, (S.data or {}).encounters)[name]
  return shown or targetId
end

--- Give Crystal's morning / day / night lists to FireRed's own tables that
-- don't have lists of their own yet -- as that table's own lists, the same
-- as if you'd made them yourself; no separate step to make them "yours".
-- They go on the id the Encounters list shows. Needs S (each table's rate
-- comes from the game's data). Returns how many tables were filled in.
function M.populateCrystal(S)
  local n = 0
  for _, e in ipairs(M.crystalTargets(S.project)) do
    if crystalMark(S.project, e.id) == nil then
      local id = M.shownTableId(S, e.id)
      if not M.hasTimeLists(S.project, id, "land") then
        local _, lists = M.crystalFor(S, id)
        if lists then
          for _, period in ipairs(Core.PERIODS) do M.setTimeArea(S.project, id, period, "land", lists[period]) end
          local d = own(S.project)
          d.crystalFilled = d.crystalFilled or {}
          d.crystalFilled[e.id] = { id = id }
          n = n + 1
        end
      end
    end
  end
  tidy(S.project)
  return n
end

local function sameArea(a, b)
  if not a or not b or #a.slots ~= #b.slots then return false end
  for i, x in ipairs(a.slots) do
    local y = b.slots[i]
    if x.species ~= y.species or x.minLevel ~= y.minLevel or x.maxLevel ~= y.maxLevel then return false end
  end
  return true
end

--- Take Crystal's lists back out of the tables M.populateCrystal filled in,
-- where they're still Crystal's. A filled-in table you've since edited is
-- yours from then on and stays. Needs S. Returns how many were cleared.
function M.unpopulateCrystal(S)
  local project = S.project
  local d = project.gen3DayNight
  if not (d and d.crystalFilled) then return 0 end
  local n = 0
  local marks = d.crystalFilled
  d.crystalFilled = nil
  for _, mark in pairs(marks) do
    if not mark.cleared then
      local _, lists = M.crystalFor(S, mark.id)
      local untouched = lists ~= nil
      for _, period in ipairs(Core.PERIODS) do
        if untouched and not sameArea(M.timeArea(project, mark.id, period, "land"), lists[period]) then untouched = false end
      end
      if untouched and M.clearTimeLists(project, mark.id, "land") then n = n + 1 end
    end
  end
  tidy(project)
  return n
end

--- Keep the stored tables matching the Encounter tables switch: Crystal's
-- lists filled in while it's on, taken back out while it's off. Safe to
-- call often -- does nothing once it's already in sync. Returns true when
-- it changed something (worth a save).
function M.syncCrystalPopulation(S)
  if not S or not S.project then return false end
  if M.encountersEnabled(S.project) then return M.populateCrystal(S) > 0 end
  local had = ((S.project.gen3DayNight or {}).crystalFilled) ~= nil
  M.unpopulateCrystal(S)
  return had
end

-- In the game ------------------------------------------------------------------

--- What the game needs, or nil when day and night is off.
function M.compile(project)
  if not M.enabled(project) then return nil end
  local s = M.settings(project)
  local lit = {}
  for _, e in ipairs(M.litList(project)) do lit[#lit + 1] = { e.pair, e.pal, e.colour } end
  return {
    morning = tonumber(s.morning), day = tonumber(s.day), night = tonumber(s.night),
    blend = tonumber(s.blend), morningTint = tostring(s.morningTint), nightTint = tostring(s.nightTint),
    testHour = tonumber(s.testHour), lit = lit, paint = M.compilePaint(project),
    encounters = M.encountersEnabled(project) and M.compileEncounters(project) or {},
    crystal = M.encountersEnabled(project) and M.compileCrystal(project) or nil,
    allDay = M.encountersEnabled(project) and (((project.gen3DayNight or {}).allDay)) or nil,
  }
end

--- Night paint for the game: { {pair, block, px, cols}, ... }.
function M.compilePaint(project)
  local out = {}
  for _, e in ipairs(M.paintedBlocks(project)) do
    local rec = project.gen3DayNight.paint[e.pair][tostring(e.mid)]
    out[#out + 1] = { e.pair, e.mid, rec.px, rec.cols }
  end
  return out
end

function M.validate(project)
  local d = (project or {}).gen3DayNight
  if d == nil then return end
  assert(type(d) == "table", "Day and night settings must be a table")
  for _, k in ipairs({ "morning", "day", "night" }) do
    assert(d[k] == nil or (type(d[k]) == "number" and d[k] >= 0 and d[k] <= 23), "Day and night: bad hour " .. k)
  end
  local s = M.settings(project)
  assert(s.morning < s.day and s.day < s.night, "Day and night: morning, day and night must start in that order")
  assert(d.blend == nil or (type(d.blend) == "number" and d.blend >= 0 and d.blend <= 180), "Day and night: bad blend")
  assert(d.testHour == nil or (type(d.testHour) == "number" and d.testHour >= 0 and d.testHour <= 23),
    "Day and night: bad test hour")
  for _, k in ipairs({ "morningTint", "nightTint" }) do
    assert(d[k] == nil or Core.hex(d[k]), "Day and night: bad colour " .. k)
  end
  assert(#M.litList(project) <= Core.MAX_LIT, ("Day and night: at most %d lit colours"):format(Core.MAX_LIT))
  for pair, set in pairs(d.paint or {}) do
    for mid, rec in pairs(set) do
      assert(tonumber(mid) and type(rec) == "table" and type(rec.px) == "string" and #rec.px == 256
        and not rec.px:find("[^%.1-9a-z]") and type(rec.cols) == "table",
        ("Day and night: bad night paint on %s block %s"):format(pair, tostring(mid)))
      for _, c in ipairs(rec.cols) do assert(Core.hex(c), "Day and night: bad night colour " .. tostring(c)) end
    end
  end
  for id, periods in pairs(d.encounters or {}) do
    for period, kinds in pairs(periods) do
      assert(period == "morning" or period == "day" or period == "night",
        ("Day and night: %s has encounters for an unknown time %s"):format(tostring(id), tostring(period)))
      for kind, area in pairs(kinds) do
        assert(M.ENCOUNTER_KINDS[kind] and type(area) == "table" and type(area.slots) == "table",
          ("Day and night: bad %s %s encounters on %s"):format(period, tostring(kind), tostring(id)))
        for i, slot in ipairs(area.slots) do
          assert(type(slot) == "table" and slot.species ~= nil and tonumber(slot.minLevel) and tonumber(slot.maxLevel),
            ("Day and night: bad slot %d in %s %s encounters on %s"):format(i, period, kind, tostring(id)))
        end
      end
    end
  end
end

-- Editor previews --------------------------------------------------------------

local shader, shaderFailed

--- The editor's preview time: S.g3DayNightHour (0-24, fractions are
-- minutes), or nil for "as the game draws it". The GFX tab, the map editor's
-- time bar and GFX > Blocks all share it.
function M.previewHour(S) return S and tonumber(S.g3DayNightHour) end

--- A typical hour for each part of the day (after its fade).
function M.hourFor(S, period)
  local s = M.settings(S.project)
  if period == "morning" then return math.min(s.day - 0.5, s.morning + 2) end
  if period == "night" then return (s.night + 4) % 24 end
  if period == "day" then return math.min(s.night - 0.5, s.day + 3) end
  return nil
end

--- The tint the editor previews, or nil when colours stay as they are.
function M.previewTint(S)
  local h = M.previewHour(S)
  if not h then return nil end
  local r, g, b = Core.tintAt(M.settings(S.project), math.floor(h) % 24, math.floor((h % 1) * 60))
  if r > 0.999 and g > 0.999 and b > 0.999 then return nil end
  return r, g, b
end

--- Draw what follows as it looks at the previewed time (lit colours stay).
-- Returns true when a preview is on; call M.endPreview afterwards.
function M.beginPreview(S)
  local r, g, b = M.previewTint(S)
  if not r or shaderFailed then return false end
  if not shader then
    local ok, sh = pcall(love.graphics.newShader, Core.SHADER)
    if not ok then shaderFailed = true return false end
    shader = sh
  end
  local lit = {}
  for _, e in ipairs(M.litList(S.project)) do
    local c = require("Gen3Blocks").paletteColours(S, e.pair, e.pal)[e.colour]
    if c and #lit < Core.MAX_LIT then
      lit[#lit + 1] = { math.floor(c[1] * 31 + 0.5), math.floor(c[2] * 31 + 0.5), math.floor(c[3] * 31 + 0.5) }
    end
  end
  shader:send("tint", { r, g, b })
  shader:send("litCount", #lit)
  if #lit > 0 then shader:send("lit", (table.unpack or unpack)(lit)) end
  love.graphics.setShader(shader)
  return true
end

--- The map editor's preview: outdoor map types, as in the game -- and maps
-- with no type yet (so the preview works while the type is still unset).
function M.beginMapPreview(S, mapId)
  if not M.previewHour(S) then return false end
  local kind = M.mapKind(S, mapId)
  if kind ~= nil and not Core.OUTDOOR[kind] then return false end
  return M.beginPreview(S)
end

--- A map's type (1 Town ... 8 Indoor), or nil when none is set.
function M.mapKind(S, mapId)
  local p = S.project or {}
  local rec = (p.maps or {})[mapId] or ((p.gen3 or {}).maps or {})[mapId]
  local kind = rec and tonumber(rec.mapType)
  if kind == nil then
    local ok, Props = pcall(require, "Gen3MapProperties")
    if ok and Props.resolve then
      local okR, r = pcall(Props.resolve, S, setmetatable({ id = mapId }, { __index = rec or {} }))
      kind = okR and r and tonumber(r.mapType) or nil
    end
  end
  if kind == nil then
    local native = ((S.data or {}).maps or {})[mapId]
    kind = native and tonumber(native.mapType)
  end
  return kind
end

--- Does a map change with the time in game? Its map type (Town, City, Route,
-- Ocean route) decides.
function M.isOutdoorMap(S, mapId)
  local kind = M.mapKind(S, mapId)
  return kind ~= nil and Core.OUTDOOR[kind] == true
end

function M.endPreview()
  love.graphics.setShader()
end

return M
