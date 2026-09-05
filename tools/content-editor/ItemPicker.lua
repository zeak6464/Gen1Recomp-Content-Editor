-- Searchable item picker modal for Shops (and other item fields).

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local PAL = Theme.PAL

local ItemPicker = {}

function ItemPicker.isOpen(S)
  return S and S.itemPicker ~= nil
end

function ItemPicker.close(S)
  if not S then return end
  S.itemPicker = nil
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

function ItemPicker.allIds(S)
  local State = require("State")
  local seen, ids = {}, {}
  local deleted = (S.project and S.project.deleted and S.project.deleted.items) or {}
  for id, rec in pairs((S.project and S.project.items) or {}) do
    if not deleted[id] and State.isItemRecord(id, rec) then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.data and S.data.items then
    for id, rec in pairs(S.data.items) do
      if not seen[id] and not deleted[id] and State.isItemRecord(id, rec) then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function itemDef(S, id)
  if not id then return nil end
  return (S.project and S.project.items and S.project.items[id])
    or (S.data and S.data.items and S.data.items[id])
end

function ItemPicker.indexForId(S, id)
  if type(id) ~= "string" or id == "" then return nil end
  local rec = itemDef(S, id)
  if type(rec) == "table" and type(rec.index) == "number" then
    return rec.index
  end
  rec = itemDef(S, "ITEM_" .. id)
  if type(rec) == "table" and type(rec.index) == "number" then
    return rec.index
  end
  return nil
end

function ItemPicker.idForIndex(S, index)
  index = tonumber(index)
  if not index then return nil end
  local function scan(bucket)
    if type(bucket) ~= "table" then return nil end
    for sid, rec in pairs(bucket) do
      if type(rec) == "table" and rec.index == index then return sid end
    end
  end
  return scan(S and S.project and S.project.items)
    or scan(S and S.data and S.data.items)
end

-- opts: current, title, onPick(id)
function ItemPicker.open(S, opts)
  opts = opts or {}
  local cur = opts.current
  if cur == "" then cur = nil end
  S.itemPicker = {
    query = "",
    offset = 0,
    opened = true,
    focus = cur,
    current = cur,
    title = opts.title or "CHOOSE ITEM",
    allowClear = opts.allowClear and true or false,
    clearLabel = opts.clearLabel or "(none)",
    onPick = opts.onPick,
  }
end

function ItemPicker.keypressed(S, key)
  if not ItemPicker.isOpen(S) then return false end
  if key == "escape" then
    ItemPicker.close(S)
    return true
  end
  return false
end

local function pick(S, id)
  local p = S.itemPicker
  local cb = p and p.onPick
  ItemPicker.close(S)
  if cb then cb(id) end
end

-- Compact control: icon + button that opens the picker.
-- opts: x, y, w, h, current, title, onPick(id), tooltip
function ItemPicker.field(S, opts)
  opts = opts or {}
  local s = Kit.scale
  local x, y, w, h = opts.x, opts.y, opts.w, opts.h
  local cur = opts.current or ""
  local thumb = math.min(h, 28 * s)
  local def = itemDef(S, cur) or { id = cur }
  Preview.drawItemIcon(S, def, x, y + (h - thumb) / 2, thumb, thumb)
  local bx = x + thumb + 6 * s
  local bw = math.max(40 * s, w - thumb - 6 * s)
  local label = cur ~= "" and cur or (opts.emptyLabel or "(pick)")
  if Kit.button(bx, y, bw, h, Kit.ellipsize("small", label, bw - 8 * s), {
      kind = "accent",
      tooltip = opts.tooltip or "Pick an item",
    }) then
    ItemPicker.open(S, {
      current = cur ~= "" and cur or nil,
      title = opts.title or "CHOOSE ITEM",
      allowClear = opts.allowClear,
      clearLabel = opts.clearLabel or opts.emptyLabel,
      onPick = opts.onPick,
    })
  end
end

function ItemPicker.draw(S, x, y, w, h)
  local p = S and S.itemPicker
  if not p then return end
  local s = Kit.scale
  if p.opened then
    p.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 560 * s)
  local ph = math.min(h - 24 * s, 520 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    ItemPicker.close(S)
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, p.title or "CHOOSE ITEM")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    ItemPicker.close(S)
    return
  end
  cy = cy + 22 * s

  local listW = math.min(300 * s, inner * 0.58)
  local prevX = cx + listW + 12 * s
  local prevW = inner - listW - 12 * s

  local qh = 28 * s
  local q = Kit.textfield("item_pick_q", cx, cy, listW, qh, p.query or "",
    "search items...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local list = ItemPicker.allIds(S)
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      local def = itemDef(S, id)
      local name = def and tostring(def.name or ""):lower() or ""
      if id:lower():find(ql, 1, true) or name:find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    list = filtered
  end

  local listY = cy + qh + 8 * s
  local extra = p.allowClear and (32 * s) or 0
  local listH = py + ph - pad - listY - extra - 4 * s
  local rowH = 32 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(listW)
  p.offset = Kit.scroll(cx, listY, listW, listH, p.offset or 0, #list, perPage)

  if #list == 0 then
    Kit.emptyBox(cx, listY, listW, listH, "No items match")
  else
    local focusOk = false
    for _, id in ipairs(list) do
      if id == p.focus then focusOk = true; break end
    end
    if not focusOk then
      p.focus = list[(p.offset or 0) + 1] or list[1]
    end
    Kit.pushClip(cx, listY, innerW, listH)
    local ry = listY
    for i = (p.offset or 0) + 1, math.min(#list, (p.offset or 0) + perPage) do
      local id = list[i]
      local on = p.current == id
      local focused = p.focus == id
      if Kit.hover(cx, ry, innerW, rowH) then p.focus = id end
      if Kit.row(cx, ry, innerW, rowH, on or focused, PAL.blue) then
        pick(S, id)
        Kit.popClip()
        return
      end
      local def = itemDef(S, id) or { id = id }
      local thumb = 24 * s
      Preview.drawItemIcon(S, def, cx + 4 * s, ry + (rowH - thumb) / 2,
        thumb, thumb)
      local owned = S.project and S.project.items and S.project.items[id]
      Kit.text("mono",
        Kit.ellipsize("mono", id, math.max(8, innerW - 36 * s)),
        cx + 32 * s, ry + 8 * s,
        on and PAL.heading or (owned and PAL.text or PAL.muted))
      ry = ry + rowH + 3 * s
    end
    Kit.popClip()
  end
  p.offset = Kit.scrollbar(cx, listY, listW, listH, p.offset or 0, #list, perPage)

  local focusId = p.focus or p.current or list[1]
  Kit.text("micro", Kit.ellipsize("micro", tostring(focusId or ""), prevW),
    prevX, listY, PAL.caption)
  local def = itemDef(S, focusId) or (focusId and { id = focusId })
  local big = math.min(prevW, 72 * s)
  if def then
    Preview.drawItemIcon(S, def, prevX, listY + 22 * s, big, big)
  end
  if def and def.name then
    Kit.text("small", tostring(def.name), prevX, listY + 22 * s + big + 8 * s,
      PAL.text)
  end
  if p.allowClear then
    if Kit.button(cx, py + ph - pad - 28 * s, listW, 28 * s,
        p.clearLabel or "(none)", { kind = "ghost" }) then
      pick(S, nil)
      return
    end
  end
  if focusId and Kit.button(prevX, py + ph - pad - 32 * s, prevW, 28 * s,
      "Use", { kind = "good" }) then
    pick(S, focusId)
  end
end

return ItemPicker
