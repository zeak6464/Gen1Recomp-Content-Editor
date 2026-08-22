-- Searchable id list for types / growth / icons / egg groups.

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local ChoicePicker = {}

function ChoicePicker.isOpen(S)
  return S and S.choicePicker ~= nil
end

function ChoicePicker.close(S)
  if not S then return end
  S.choicePicker = nil
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

function ChoicePicker.open(S, opts)
  opts = opts or {}
  local cur = opts.current
  if cur == "" then cur = nil end
  S.choicePicker = {
    query = "",
    offset = 0,
    opened = true,
    focus = cur,
    current = cur,
    ids = opts.ids or {},
    labels = opts.labels or {},
    title = opts.title or "CHOOSE",
    allowClear = opts.allowClear and true or false,
    clearLabel = opts.clearLabel or "(none)",
    onPick = opts.onPick,
  }
end

function ChoicePicker.keypressed(S, key)
  if not ChoicePicker.isOpen(S) then return false end
  if key == "escape" then
    ChoicePicker.close(S)
    return true
  end
  return false
end

local function pick(S, id)
  local p = S.choicePicker
  local cb = p and p.onPick
  ChoicePicker.close(S)
  if cb then cb(id) end
end

function ChoicePicker.field(S, opts)
  opts = opts or {}
  local s = Kit.scale
  local x, y, w, h = opts.x, opts.y, opts.w, opts.h
  local cur = opts.current or ""
  local shown = (opts.labels and opts.labels[cur]) or cur
  local label = shown ~= "" and shown or (opts.emptyLabel or "(pick)")
  if Kit.button(x, y, w, h, Kit.ellipsize("small", label, w - 10 * s), {
      kind = opts.kind or "accent",
      tooltip = opts.tooltip or "Pick from list",
    }) then
    ChoicePicker.open(S, {
      current = cur ~= "" and cur or nil,
      ids = opts.ids,
      labels = opts.labels,
      title = opts.title or "CHOOSE",
      allowClear = opts.allowClear,
      clearLabel = opts.clearLabel or opts.emptyLabel,
      onPick = opts.onPick,
    })
  end
end

function ChoicePicker.draw(S, x, y, w, h)
  local p = S and S.choicePicker
  if not p then return end
  local s = Kit.scale
  if p.opened then
    p.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 420 * s)
  local ph = math.min(h - 24 * s, 480 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    ChoicePicker.close(S)
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, p.title or "CHOOSE")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    ChoicePicker.close(S)
    return
  end
  cy = cy + 22 * s

  local qh = 28 * s
  local q = Kit.textfield("choice_pick_q", cx, cy, inner, qh, p.query or "",
    "search...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local labels = p.labels or {}
  local list = {}
  for _, id in ipairs(p.ids or {}) do
    if type(id) == "string" and id ~= "" then list[#list + 1] = id end
  end
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      local shown = tostring(labels[id] or id)
      if id:lower():find(ql, 1, true) or shown:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    list = filtered
  end

  local listY = cy + qh + 8 * s
  local extra = p.allowClear and (32 * s) or 0
  local listH = py + ph - pad - listY - extra - 4 * s
  local rowH = 28 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(inner)
  p.offset = Kit.scroll(cx, listY, inner, listH, p.offset or 0, #list, perPage)

  if #list == 0 then
    Kit.emptyBox(cx, listY, inner, listH, "No matches")
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
      local shown = labels[id] or id
      Kit.text("small", Kit.ellipsize("small", shown, math.max(8, innerW - 12 * s)),
        cx + 8 * s, ry + 6 * s, on and PAL.heading or PAL.text)
      ry = ry + rowH + 3 * s
    end
    Kit.popClip()
  end
  p.offset = Kit.scrollbar(cx, listY, inner, listH, p.offset or 0, #list, perPage)

  if p.allowClear then
    if Kit.button(cx, py + ph - pad - 28 * s, inner, 28 * s,
        p.clearLabel or "(none)", { kind = "ghost" }) then
      pick(S, nil)
    end
  end
end

return ChoicePicker
