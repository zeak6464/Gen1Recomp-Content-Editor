-- Inline autocomplete dropdown for Kit.textfield ID entry.
-- Panels call RegList.suggestField / Autocomplete.offer while a field is
-- focused; App draws the list and routes Up/Down/Enter/Tab.

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local Autocomplete = {}

local MAX_SHOW = 10

function Autocomplete.beginFrame(S)
  if not S then return end
  S._acOffer = nil
end

-- Ranked filter: prefix matches first, then substring. Case-insensitive.
function Autocomplete.filter(ids, query, maxShow)
  maxShow = maxShow or MAX_SHOW
  if type(ids) ~= "table" then return {} end
  local q = tostring(query or ""):upper()
  local prefix, mid = {}, {}
  if q == "" then
    for i = 1, math.min(#ids, maxShow) do
      prefix[i] = ids[i]
    end
    return prefix
  end
  for _, id in ipairs(ids) do
    local u = tostring(id):upper()
    if u:sub(1, #q) == q then
      prefix[#prefix + 1] = id
    elseif u:find(q, 1, true) then
      mid[#mid + 1] = id
    end
    if #prefix >= maxShow then break end
  end
  local out = prefix
  for i = 1, #mid do
    if #out >= maxShow then break end
    out[#out + 1] = mid[i]
  end
  return out
end

-- Register suggestions for the currently focused field (call each frame
-- from the field that owns Kit.focus).
-- opts: fieldId, x, y, w, query, ids (array) or getIds(), maxShow?
function Autocomplete.offer(S, opts)
  if not (S and opts and opts.fieldId) then return end
  if Kit.focus ~= opts.fieldId then return end
  local ids = opts.ids
  if type(opts.getIds) == "function" then
    ids = opts.getIds()
  end
  if type(ids) ~= "table" then ids = {} end
  local matches = Autocomplete.filter(ids, opts.query, opts.maxShow or MAX_SHOW)
  local prev = S._acOffer
  local idx = 1
  if prev and prev.fieldId == opts.fieldId and type(prev.index) == "number" then
    idx = Theme.clamp(prev.index, 1, math.max(1, #matches))
  end
  if #matches == 0 then idx = 1 end
  S._acOffer = {
    fieldId = opts.fieldId,
    x = opts.x, y = opts.y, w = opts.w,
    query = opts.query,
    matches = matches,
    index = idx,
  }
end

function Autocomplete.takePick(S, fieldId)
  local p = S and S._acPick
  if not p or p.fieldId ~= fieldId then return nil end
  S._acPick = nil
  return p.text
end

local function applyPick(S, text)
  local o = S and S._acOffer
  if not o then return end
  S._acPick = { fieldId = o.fieldId, text = text }
  S._acOffer = nil
  Kit.blur()
end

function Autocomplete.isOpen(S)
  local o = S and S._acOffer
  return o and o.matches and #o.matches > 0 and Kit.focus == o.fieldId
end

function Autocomplete.keypressed(S, key)
  if not Autocomplete.isOpen(S) then return false end
  local o = S._acOffer
  if key == "up" then
    o.index = (o.index > 1) and (o.index - 1) or #o.matches
    return true
  end
  if key == "down" then
    o.index = (o.index < #o.matches) and (o.index + 1) or 1
    return true
  end
  if key == "return" or key == "kpenter" or key == "tab" then
    local id = o.matches[o.index]
    if id then applyPick(S, id) end
    return true
  end
  if key == "escape" then
    S._acOffer = nil
    return true
  end
  return false
end

function Autocomplete.draw(S)
  if not Autocomplete.isOpen(S) then return end
  local o = S._acOffer
  local s = Kit.scale
  local rowH = 22 * s
  local pad = 6 * s
  local n = #o.matches
  local boxH = n * rowH + 4 * s
  local boxW = math.max(o.w or 120 * s, 160 * s)
  local x, y = o.x, o.y
  -- Keep on-screen if near bottom.
  local H = love.graphics.getHeight()
  if y + boxH > H - 8 * s then
    y = math.max(8 * s, (o.y - boxH - 28 * s))
  end

  Kit.blockClicks = false
  Theme.col(PAL.cardBody or PAL.bgBot, 0.97)
  love.graphics.rectangle("fill", x, y, boxW, boxH, 6 * s, 6 * s)
  Theme.stroke(x, y, boxW, boxH, 6 * s, PAL.cardBorder, 0.55, 1)
  Theme.col(PAL.blue, 0.08)
  love.graphics.rectangle("fill", x, y, boxW, boxH, 6 * s, 6 * s)

  for i, id in ipairs(o.matches) do
    local ry = y + 2 * s + (i - 1) * rowH
    local hot = Kit.hover(x, ry, boxW, rowH) or i == o.index
    if hot then
      Theme.col(PAL.blue, 0.22)
      love.graphics.rectangle("fill", x + 2 * s, ry, boxW - 4 * s, rowH, 4 * s, 4 * s)
      o.index = i
    end
    Kit.text("micro", Kit.ellipsize("micro", tostring(id), boxW - 2 * pad),
      x + pad, ry + (rowH - Kit.textHeight("micro")) / 2,
      hot and PAL.heading or PAL.muted)
    if Kit.press(x, ry, boxW, rowH) then
      applyPick(S, id)
      return
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- suggestion catalogs ------------------------------------------------

local function mergeKeys(...)
  local seen, ids = {}, {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if type(t) == "table" then
      for id in pairs(t) do
        if type(id) == "string" and id ~= "" and not seen[id] then
          seen[id] = true
          ids[#ids + 1] = id
        end
      end
    end
  end
  table.sort(ids)
  return ids
end

function Autocomplete.speciesIds(S)
  local ok, SpeciesPicker = pcall(require, "SpeciesPicker")
  if ok and SpeciesPicker and SpeciesPicker.allIds then
    return SpeciesPicker.allIds(S)
  end
  return mergeKeys(S.project and S.project.pokemon, S.data and S.data.pokemon)
end

function Autocomplete.itemIds(S)
  local ok, ItemPicker = pcall(require, "ItemPicker")
  if ok and ItemPicker and ItemPicker.allIds then
    return ItemPicker.allIds(S)
  end
  local State = require("State")
  local seen, ids = {}, {}
  local function consider(bag)
    if type(bag) ~= "table" then return end
    for id, rec in pairs(bag) do
      if not seen[id] and State.isItemRecord(id, rec) then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  consider(S.project and S.project.items)
  consider(S.data and S.data.items)
  table.sort(ids)
  return ids
end

function Autocomplete.moveIds(S)
  return mergeKeys(S.project and S.project.moves, S.data and S.data.moves)
end

function Autocomplete.mapIds(S)
  -- GAME PATCHES > Clean Project: the game's own maps are hidden, so map
  -- pickers (connections, warps, events) offer only the project's maps --
  -- otherwise an imported region shows every map twice (Route 128 and
  -- Hoenn Route 128) and picking the hidden one links to a map that isn't
  -- part of the mod.
  if S.project and type(S.project.gen3Clean) == "table" then
    return require("Generation").listedMapIds(S)
  end
  return mergeKeys(S.project and S.project.maps,
    require("Generation").dataMaps(S))
end

function Autocomplete.spriteIds(S)
  return mergeKeys(S.project and S.project.sprites, S.data and S.data.sprites)
end

function Autocomplete.trainerIds(S)
  -- Gold: data.trainers = { classes = { BEAUTY = … }, generation = 2 }.
  local data = S.data and S.data.trainers
  if type(data) == "table" and type(data.classes) == "table" then
    data = data.classes
  end
  return mergeKeys(S.project and S.project.trainers, data)
end

function Autocomplete.songIds(S)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local audio = S.data and S.data.audio
  if type(audio) == "table" then
    for id in pairs(audio.songs or audio) do add(id) end
  end
  local proj = S.project and S.project.audio
  if type(proj) == "table" then
    for id in pairs(proj.songs or proj) do add(id) end
  end
  table.sort(ids)
  return ids
end

function Autocomplete.flagIds(S)
  local ids, seen = {}, {}
  local function add(n)
    if type(n) == "string" and n ~= "" and not seen[n] then
      seen[n] = true
      ids[#ids + 1] = n
    end
  end
  local State = require("State")
  if State.rebuildEventFlags and S.project then
    pcall(State.rebuildEventFlags, S.project)
  end
  for n in pairs((S.project and S.project.eventFlags) or {}) do add(n) end
  if type(S.events) == "table" then
    for _, n in ipairs(S.events) do add(n) end
  end
  table.sort(ids)
  return ids
end

function Autocomplete.paletteIds(S)
  local ok, Preview = pcall(require, "Preview")
  if ok and Preview and Preview.paletteIds then
    return Preview.paletteIds(S)
  end
  return {}
end

function Autocomplete.textIds(S, mapId)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local function addBucket(bucket)
    if type(bucket) ~= "table" then return end
    for tid in pairs(bucket) do add(tid) end
  end
  local label = nil
  local map = (S.project and S.project.maps and S.project.maps[mapId])
    or require("Generation").dataMaps(S)[mapId]
  if map and type(map.label) == "string" then label = map.label end
  local ptrs = S.project and S.project.text_pointers
  if label and ptrs then addBucket(ptrs[label]) end
  local dataPtrs = S.data and S.data.text_pointers
  if label and dataPtrs then addBucket(dataPtrs[label]) end
  -- Also offer TEXT_* already used by this map's objects/signs.
  if map then
    for _, obj in ipairs(map.objects or {}) do add(obj.text) end
    for _, sign in ipairs(map.signs or {}) do add(sign.text) end
  end
  for id in pairs((S.project and S.project.text) or {}) do add(id) end
  table.sort(ids)
  return ids
end

return Autocomplete
