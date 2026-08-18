-- Searchable species picker modal for Trades / Encounters / Trainers / Maps.

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local PAL = Theme.PAL

local SpeciesPicker = {}

function SpeciesPicker.isOpen(S)
  return S and S.speciesPicker ~= nil
end

function SpeciesPicker.close(S)
  if not S then return end
  S.speciesPicker = nil
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

function SpeciesPicker.allIds(S)
  local seen, ids = {}, {}
  local deleted = (S.project and S.project.deleted and S.project.deleted.pokemon) or {}
  for id in pairs((S.project and S.project.pokemon) or {}) do
    if not deleted[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.data and S.data.pokemon then
    for id in pairs(S.data.pokemon) do
      if not seen[id] and not deleted[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function speciesDef(S, id)
  if not id then return nil end
  return (S.project and S.project.pokemon and S.project.pokemon[id])
    or (S.data and S.data.pokemon and S.data.pokemon[id])
end

-- opts: current, title, onPick(id)
function SpeciesPicker.open(S, opts)
  opts = opts or {}
  local cur = opts.current
  if cur == "" then cur = nil end
  S.speciesPicker = {
    query = "",
    offset = 0,
    opened = true,
    focus = cur,
    current = cur,
    title = opts.title or "CHOOSE SPECIES",
    onPick = opts.onPick,
  }
end

function SpeciesPicker.keypressed(S, key)
  if not SpeciesPicker.isOpen(S) then return false end
  if key == "escape" then
    SpeciesPicker.close(S)
    return true
  end
  return false
end

local function pick(S, id)
  local p = S.speciesPicker
  local cb = p and p.onPick
  SpeciesPicker.close(S)
  if cb and id then cb(id) end
end

-- Compact control: sprite + button that opens the picker.
-- opts: x, y, w, h, current, title, onPick(id), tooltip
function SpeciesPicker.field(S, opts)
  opts = opts or {}
  local s = Kit.scale
  local x, y, w, h = opts.x, opts.y, opts.w, opts.h
  local cur = opts.current or ""
  local thumb = math.min(h, 28 * s)
  local def = speciesDef(S, cur)
  if def and def.spriteFront then
    local pal = Preview.monPaletteName(S, def, cur)
    if def.trueColor then pal = false end
    Preview.draw(S, def.spriteFront, x, y + (h - thumb) / 2, thumb, thumb, pal)
  end
  local bx = x + thumb + 6 * s
  local bw = math.max(40 * s, w - thumb - 6 * s)
  local label = opts.label
    or ((cur ~= "" and cur ~= 0) and tostring(cur))
    or (opts.emptyLabel or "(pick)")
  if Kit.button(bx, y, bw, h, Kit.ellipsize("small", label, bw - 8 * s), {
      kind = "accent",
      tooltip = opts.tooltip or "Pick a species",
    }) then
    SpeciesPicker.open(S, {
      current = cur ~= "" and cur or nil,
      title = opts.title or "CHOOSE SPECIES",
      onPick = opts.onPick,
    })
  end
end

function SpeciesPicker.draw(S, x, y, w, h)
  local p = S and S.speciesPicker
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
    SpeciesPicker.close(S)
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, p.title or "CHOOSE SPECIES")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    SpeciesPicker.close(S)
    return
  end
  cy = cy + 22 * s

  local listW = math.min(280 * s, inner * 0.55)
  local prevX = cx + listW + 12 * s
  local prevW = inner - listW - 12 * s

  local qh = 28 * s
  local q = Kit.textfield("sp_pick_q", cx, cy, listW, qh, p.query or "",
    "search species...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local list = SpeciesPicker.allIds(S)
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      local def = speciesDef(S, id)
      local name = def and tostring(def.name or ""):lower() or ""
      if id:lower():find(ql, 1, true) or name:find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    list = filtered
  end

  local listY = cy + qh + 8 * s
  local listH = py + ph - pad - listY - 4 * s
  local rowH = 32 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(listW)
  p.offset = Kit.scroll(cx, listY, listW, listH, p.offset or 0, #list, perPage)

  if #list == 0 then
    Kit.emptyBox(cx, listY, listW, listH, "No species match")
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
      if Kit.row(cx, ry, innerW, rowH, on or focused, PAL.green) then
        pick(S, id)
        Kit.popClip()
        return
      end
      local def = speciesDef(S, id)
      local thumb = 24 * s
      if def and def.spriteFront then
        local pal = Preview.monPaletteName(S, def, id)
        if def.trueColor then pal = false end
        Preview.draw(S, def.spriteFront, cx + 4 * s, ry + (rowH - thumb) / 2,
          thumb, thumb, pal)
      end
      local owned = S.project and S.project.pokemon and S.project.pokemon[id]
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
  local def = speciesDef(S, focusId)
  local big = math.min(prevW, 120 * s)
  if def and def.spriteFront then
    local pal = Preview.monPaletteName(S, def, focusId)
    if def.trueColor then pal = false end
    Preview.draw(S, def.spriteFront, prevX, listY + 22 * s, big, big, pal)
  end
  if def and def.name then
    Kit.text("small", tostring(def.name), prevX, listY + 22 * s + big + 8 * s,
      PAL.text)
  end
  if focusId and Kit.button(prevX, py + ph - pad - 32 * s, prevW, 28 * s,
      "Use", { kind = "good" }) then
    pick(S, focusId)
  end
end

return SpeciesPicker
