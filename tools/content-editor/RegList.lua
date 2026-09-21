-- Shared id-list + form chrome for content-editor registry panels.
-- Also owns Up/Down list navigation with hold-to-repeat (bindNav).

local Kit = require("Kit")
local Theme = require("Theme")
local Search = require("Search")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local RegList = {}

local HOLD_DELAY = 0.32
local HOLD_RATE = 0.055

function RegList.cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

function RegList.field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

-- Text field with inline autocomplete dropdown (see Autocomplete.lua).
-- idsOrFn: string array, or function() -> array of suggestion ids.
function RegList.suggestField(App, S, id, x, y, w, h, value, ph, idsOrFn)
  local Autocomplete = require("Autocomplete")
  local picked = Autocomplete.takePick(S, id)
  if picked ~= nil then
    value = picked
    App.markDirty()
  end
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  local ids = idsOrFn
  if type(idsOrFn) == "function" then
    ids = idsOrFn()
  end
  Autocomplete.offer(S, {
    fieldId = id,
    x = x,
    y = y + h + 2 * (Kit.scale or 1),
    w = w,
    query = v,
    ids = ids,
  })
  return v
end

function RegList.num(App, id, x, y, w, h, value)
  local v = RegList.field(App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

function RegList.sortedKeys(t)
  local ids = {}
  for id in pairs(t or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function RegList.mergeIds(projectTbl, dataTbl)
  local seen, ids = {}, {}
  for id in pairs(projectTbl or {}) do
    seen[id] = true; ids[#ids + 1] = id
  end
  for id in pairs(dataTbl or {}) do
    if not seen[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

-- Call once per frame before the active panel draws lists.
function RegList.clearNav(S)
  if not S then return end
  S._regNavSlots = {}
end

local function resolveActive(S)
  local slots = S._regNavSlots or {}
  if #slots == 0 then
    S._regNav = nil
    return
  end
  local ai = tonumber(S._regNavActive) or 1
  if ai < 1 or ai > #slots then ai = 1 end
  S._regNavActive = ai
  S._regNav = slots[ai]
end

-- Register a scrollable selection list for arrow-key nav.
-- Returns nav with :activate() — call on row click for multi-list panels.
-- opts: selKey, offsetKey, perPage, onSelect(id)
function RegList.bindNav(S, ids, opts)
  opts = opts or {}
  if not S or type(ids) ~= "table" then
    return { activate = function() end }
  end
  S._regNavSlots = S._regNavSlots or {}
  local index = #S._regNavSlots + 1
  local nav = {
    ids = ids,
    selKey = opts.selKey or "regId",
    offsetKey = opts.offsetKey or "regListOffset",
    perPage = math.max(1, opts.perPage or 10),
    onSelect = opts.onSelect,
    index = index,
  }
  function nav.activate()
    S._regNavActive = index
    S._regNav = nav
  end
  S._regNavSlots[index] = nav
  resolveActive(S)
  return nav
end

-- Draw left list. opts: queryKey, offsetKey, selKey, accent, rowH, filter(id)->bool
-- onSelect(id), footerLabel, onFooter()
-- Returns formX, formW, listY, listH, ids
function RegList.drawList(S, App, x, y, w, h, title, ids, opts)
  opts = opts or {}
  local s = Kit.scale
  local listW = opts.listW or math.min(220 * s, w * 0.28)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s
  Kit.caption(x, y, title)
  local qh = 28 * s
  local qy = y + 22 * s
  local qKey = opts.queryKey or "regQuery"
  local q, qChanged = Search.field(S, qKey, x, qy, listW, qh, opts.searchPh or "search...")
  local offKey = opts.offsetKey or "regListOffset"
  if qChanged then S[offKey] = 0 end
  if q ~= "" and opts.filter then
    local filtered = {}
    for _, id in ipairs(ids) do
      if opts.filter(id, q) then filtered[#filtered + 1] = id end
    end
    ids = filtered
  elseif q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
        local label=opts.label and opts.label(id) or id
        if (id.." "..label):lower():find(ql, 1, true) then filtered[#filtered + 1] = id end
    end
    ids = filtered
  end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)
  local rowH = opts.rowH or 30 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 4 * s)))
  local scrollX = x + 8 * s
  local scrollW = listW - 16 * s
  local scrollH = listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S[offKey] = Kit.scroll(scrollX, listY + 8 * s, scrollW, scrollH,
    S[offKey] or 0, #ids, perPage, nil, offKey)
  local selKey = opts.selKey or "regId"
  local accent = opts.accent or PAL.blue
  local nav = RegList.bindNav(S, ids, {
    selKey = selKey,
    offsetKey = offKey,
    perPage = perPage,
    onSelect = opts.onSelect,
  })
  local ry = listY + 8 * s
  for i = (S[offKey] or 0) + 1, math.min(#ids, (S[offKey] or 0) + perPage) do
    local id = ids[i]
    local owned = opts.isOwned and opts.isOwned(id)
    if Kit.row(scrollX, ry, rowW, rowH, S[selKey] == id, accent) then
      nav.activate()
      S[selKey] = id
      if opts.onSelect then opts.onSelect(id) end
    end
    Kit.text("mono", Kit.ellipsize("mono", opts.label and opts.label(id) or id, math.max(8, rowW - 16 * s)),
      x + 16 * s, ry + (rowH - Kit.textHeight("mono")) / 2,
      owned and PAL.text or PAL.muted)
    ry = ry + rowH + 4 * s
  end
  S[offKey] = Kit.scrollbar(scrollX, listY + 8 * s, scrollW, scrollH,
    S[offKey] or 0, #ids, perPage, offKey)
  if opts.footerLabel and Kit.button(x, y + h - 36 * s, listW, 32 * s,
      opts.footerLabel, { kind = "good" }) then
    if opts.onFooter then opts.onFooter() end
  end
  return formX, formW, listY, listH, ids
end

-- Move selection by `step` rows. Returns true when handled.
function RegList.step(S, step)
  if not S or not step or step == 0 then return false end
  resolveActive(S)
  local nav = S._regNav
  if not nav or type(nav.ids) ~= "table" or #nav.ids == 0 then
    return false
  end
  local ids = nav.ids
  local selKey = nav.selKey
  local cur = S[selKey]
  local idx = 1
  for i, id in ipairs(ids) do
    if id == cur then idx = i; break end
  end
  local nextIdx = Theme.clamp(idx + step, 1, #ids)
  if nextIdx == idx and ids[idx] == cur then return true end
  S[selKey] = ids[nextIdx]
  local offKey = nav.offsetKey
  local perPage = math.max(1, nav.perPage or 1)
  local offset = S[offKey] or 0
  if nextIdx - 1 < offset then
    offset = nextIdx - 1
  elseif nextIdx > offset + perPage then
    offset = nextIdx - perPage
  end
  S[offKey] = Theme.clamp(offset, 0, math.max(0, #ids - perPage))
  if nav.onSelect then nav.onSelect(ids[nextIdx]) end
  return true
end

local function heldStep(S)
  if not (love and love.keyboard and love.keyboard.isDown) then return 0 end
  local nav = S._regNav
  local page = math.max(1, (nav and nav.perPage) or 1)
  if love.keyboard.isDown("up") then return -1 end
  if love.keyboard.isDown("down") then return 1 end
  if love.keyboard.isDown("pageup") then return -page end
  if love.keyboard.isDown("pagedown") then return page end
  return 0
end

local function switchSlot(S, delta)
  local slots = S._regNavSlots or {}
  if #slots < 2 then return false end
  local ai = (tonumber(S._regNavActive) or 1) + delta
  if ai < 1 then ai = #slots
  elseif ai > #slots then ai = 1 end
  S._regNavActive = ai
  resolveActive(S)
  S._regNavHold = nil
  return true
end

-- Up/Down/Page navigate the active list; Left/Right switch list columns.
-- No-op while a textfield has focus or a scrollbar is arrow-scrolling.
function RegList.keypressed(S, key)
  if not S or Kit.focus then return false end
  if Kit.scrollNavActive and Kit.scrollNavActive() then return false end
  resolveActive(S)
  if key == "left" then return switchSlot(S, -1) end
  if key == "right" then return switchSlot(S, 1) end
  local step = 0
  local nav = S._regNav
  local page = math.max(1, (nav and nav.perPage) or 1)
  if key == "up" then step = -1
  elseif key == "down" then step = 1
  elseif key == "pageup" then step = -page
  elseif key == "pagedown" then step = page
  else return false end
  if not RegList.step(S, step) then return false end
  S._regNavHold = { dir = step, t = 0, delay = true }
  return true
end

-- Keep stepping while arrow / page keys are held.
function RegList.update(S, dt)
  if not S then return end
  if Kit.focus or Kit.blockClicks then
    S._regNavHold = nil
    return
  end
  -- Don't fight the focused scrollbar's arrow-key hold-repeat.
  if Kit.scrollNavActive and Kit.scrollNavActive() then
    S._regNavHold = nil
    return
  end
  resolveActive(S)
  local dir = heldStep(S)
  if dir == 0 then
    S._regNavHold = nil
    return
  end
  local hold = S._regNavHold
  if not hold or hold.dir ~= dir then
    RegList.step(S, dir)
    S._regNavHold = { dir = dir, t = 0, delay = true }
    return
  end
  hold.t = (hold.t or 0) + (tonumber(dt) or 0)
  local need = hold.delay and HOLD_DELAY or HOLD_RATE
  while hold.t >= need do
    hold.t = hold.t - need
    hold.delay = false
    need = HOLD_RATE
    if not RegList.step(S, dir) then break end
  end
end

function RegList.beginForm(S, formX, listY, formW, listH, scrollKey, identity, footerH)
  local s = Kit.scale
  footerH = footerH or 12 * s
  local pad = 12 * s
  Kit.card(formX, listY, formW, listH, 12 * s)
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, scrollKey, identity)
  local fy, view = FormPane.begin(S, scrollKey, viewX, viewY, viewW, viewH)
  return fy, view, viewX, view.contentW or viewW
end

function RegList.modeChips(S, key, modes, x, y, s)
  local sx = x
  S[key] = S[key] or modes[1].id
  for _, m in ipairs(modes) do
    local on = S[key] == m.id
    local bw = Kit.textWidth("micro", m.label) + 18 * s
    if Kit.chip(sx, y, bw, 26 * s, m.label, on, PAL.green, nil, m.tip) then
      S[key] = m.id
    end
    sx = sx + bw + 4 * s
  end
  return y + 32 * s
end

return RegList
