-- Battle Anims tab.
-- Gen1: moveAnims / subanims / tilesheets (seq rows).
-- Gold: script pool — moves/ids → pointer, scripts/objects/gfx tables.
-- Save: Gen1 register/patch per id; Gold battle_anims:patch(bucket, map).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local BattleAnimPreview = require("BattleAnimPreview")
local Generation = require("Generation")
local PAL = Theme.PAL

local BattleAnims = {}

local MODES_GEN1 = {
  { id = "moves", label = "Move anims",
    tip = "Per-move battle animation sequences (keyed by move id)" },
  { id = "subanims", label = "Subanims",
    tip = "Shared subanimation frame-block lists" },
  { id = "tilesheets", label = "Tilesheets",
    tip = "Battle animation tile atlases" },
}

local MODES_GEN2 = {
  { id = "moves", label = "Moves",
    tip = "Move id → script pointer (battle_anims.moves)" },
  { id = "scripts", label = "Scripts",
    tip = "Bytecode command rows keyed by ROM pointer" },
  { id = "ids", label = "Status ids",
    tip = "ANIM_* status/sendout scripts" },
  { id = "objects", label = "Objects",
    tip = "BATTLE_ANIM_OBJ_* spawn tables" },
  { id = "gfx", label = "Gfx",
    tip = "BATTLE_ANIM_GFX_* tile sheets" },
}

local SUBANIM_TYPES = {
  "NORMAL", "HFLIP", "HVFLIP", "COORDFLIP", "ENEMY", "REVERSE",
}

local SCRIPT_VERBS = {
  "wait", "ret", "sound", "obj", "call", "jump", "loop",
  "1gfx", "2gfx", "3gfx", "bgeffect", "bgp", "obp0", "obp1",
  "clearobjs", "cry", "setvar", "incvar", "incobj", "incbgeffect",
  "if_param_equal", "if_param_and", "if_var_equal",
  "battlergfx_1row", "battlergfx_2row", "beatup", "checkpokeball",
  "dropsub", "raisesub", "keepsprites", "minimizeopp", "transform",
  "resetobp0", "setobj", "jumpuntil",
}

local function deepClone(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do
    if type(val) == "function" then
      -- skip
    elseif type(val) == "table" then
      out[k] = deepClone(val)
    else
      out[k] = val
    end
  end
  return out
end

local function baRoot(S)
  return S.data and (S.data.gen2BattleAnims or S.data.battle_anims) or nil
end

local function projectBucket(S)
  State.ensureProjectFields(S.project)
  S.project.battle_anims = S.project.battle_anims or {}
  return S.project.battle_anims
end

local function parseRoute(id)
  local kind, index = tostring(id or ""):match("^(%a+):(%d+)$")
  if kind == "subanim" then return "subanims", tonumber(index) end
  if kind == "tilesheet" then return "tilesheets", tonumber(index) end
  return "moveAnims", id
end

-- ---- Gen2 nested project helpers ----

local function gen2Map(S, bucket)
  local proj = projectBucket(S)
  if type(proj[bucket]) ~= "table" then proj[bucket] = {} end
  return proj[bucket]
end

local function gen2ResolvePointer(S, moveOrAnimId)
  local root = baRoot(S)
  local proj = projectBucket(S)
  if proj.moves and proj.moves[moveOrAnimId] ~= nil then
    return proj.moves[moveOrAnimId], true
  end
  if proj.ids and proj.ids[moveOrAnimId] ~= nil then
    return proj.ids[moveOrAnimId], true
  end
  if root and root.moves and root.moves[moveOrAnimId] then
    return root.moves[moveOrAnimId], false
  end
  if root and root.ids and root.ids[moveOrAnimId] then
    return root.ids[moveOrAnimId], false
  end
  return nil, false
end

local function gen2ResolveScript(S, ptr)
  if not ptr or ptr == "" then return nil, false end
  local proj = projectBucket(S)
  if proj.scripts and proj.scripts[ptr] ~= nil then
    return proj.scripts[ptr], true
  end
  local root = baRoot(S)
  if root and root.scripts and root.scripts[ptr] then
    return root.scripts[ptr], false
  end
  return nil, false
end

local function gen2EnsureScript(S, ptr, App)
  local map = gen2Map(S, "scripts")
  if map[ptr] then return map[ptr] end
  local base = select(1, gen2ResolveScript(S, ptr))
  local copy = type(base) == "table" and deepClone(base) or { { "ret" } }
  map[ptr] = copy
  if App then App.markDirty() end
  return copy
end

local function gen2NewScriptPtr(S)
  local root = baRoot(S)
  local proj = projectBucket(S)
  local n = 1
  while true do
    local ptr = string.format("m%03x", n)
    local taken = (root and root.scripts and root.scripts[ptr])
      or (proj.scripts and proj.scripts[ptr])
    if not taken then return ptr end
    n = n + 1
    if n > 0xfff then return "mfff" end
  end
end

local function summarizeScript(rows)
  if type(rows) ~= "table" then return "empty" end
  local n = #rows
  local head = rows[1] and rows[1][1] or "?"
  return n .. " cmd · " .. tostring(head)
end

local function formatCmdRow(row)
  if type(row) ~= "table" then return tostring(row) end
  local parts = {}
  for i = 1, #row do parts[i] = tostring(row[i]) end
  return table.concat(parts, " | ")
end

local function parseCmdRow(str)
  local parts = {}
  for part in (tostring(str or "") .. "|"):gmatch("([^|]*)|") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      -- Decimal ints become numbers; hex pointers like 7c40 stay strings.
      if part:match("^%-?%d+$") then
        parts[#parts + 1] = tonumber(part)
      else
        parts[#parts + 1] = part
      end
    end
  end
  if #parts == 0 then return { "wait", 1 } end
  return parts
end

local function scriptUsers(S, ptr)
  local users = {}
  local function scan(tbl, prefix)
    for id, p in pairs(tbl or {}) do
      if p == ptr then users[#users + 1] = (prefix or "") .. id end
    end
  end
  local root = baRoot(S)
  local proj = projectBucket(S)
  scan(root and root.moves, "")
  scan(proj.moves, "")
  scan(root and root.ids, "")
  scan(proj.ids, "")
  table.sort(users)
  -- dedupe
  local out, seen = {}, {}
  for _, u in ipairs(users) do
    if not seen[u] then seen[u] = true; out[#out + 1] = u end
  end
  return out
end

-- ---- Gen1 resolve / lists (unchanged shape) ----

function BattleAnims.resolve(S, id)
  if not id then return nil, false end
  if Generation.isGen2(S) then
    -- Moves tab / picker: resolve move id → fake { script = ptr } for summarize.
    local ptr, owned = gen2ResolvePointer(S, id)
    if ptr then return { script = ptr }, owned end
    local rows, sOwned = gen2ResolveScript(S, id)
    if rows then return { rows = rows }, sOwned end
    return nil, false
  end
  local proj = S.project and S.project.battle_anims
  if proj and proj[id] ~= nil then return proj[id], true end
  local root = baRoot(S)
  if not root then return nil, false end
  local sub, key = parseRoute(id)
  local table_ = root[sub]
  if table_ and table_[key] ~= nil then return table_[key], false end
  return nil, false
end

function BattleAnims.moveAnimIds(S)
  if Generation.isGen2(S) then
    local seen, ids = {}, {}
    local function add(id)
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
    local proj = projectBucket(S)
    for id in pairs(proj.moves or {}) do add(id) end
    local root = baRoot(S)
    if root and root.moves then
      for id in pairs(root.moves) do add(id) end
    end
    table.sort(ids)
    return ids
  end
  local seen, ids = {}, {}
  local proj = S.project and S.project.battle_anims or {}
  for id in pairs(proj) do
    local sub = parseRoute(id)
    if sub == "moveAnims" then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local root = baRoot(S)
  if root and root.moveAnims then
    for id in pairs(root.moveAnims) do
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function listIdsGen1(S, mode)
  local proj = projectBucket(S)
  local root = baRoot(S)
  local seen, ids = {}, {}

  local function add(id)
    if not id or seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
  end

  if mode == "moves" then
    for id in pairs(proj) do
      if parseRoute(id) == "moveAnims" then add(id) end
    end
    if root and root.moveAnims then
      for id in pairs(root.moveAnims) do
        if type(id) == "string" then add(id) end
      end
    end
  elseif mode == "subanims" then
    for id in pairs(proj) do
      if parseRoute(id) == "subanims" then add(id) end
    end
    if root and root.subanims then
      for index in pairs(root.subanims) do
        add("subanim:" .. tostring(index))
      end
    end
  else -- tilesheets
    for id in pairs(proj) do
      if parseRoute(id) == "tilesheets" then add(id) end
    end
    if root and root.tilesheets then
      for index in pairs(root.tilesheets) do
        add("tilesheet:" .. tostring(index))
      end
    end
  end

  table.sort(ids, function(a, b)
    local _, ka = parseRoute(a)
    local _, kb = parseRoute(b)
    if type(ka) == "number" and type(kb) == "number" then return ka < kb end
    return tostring(a) < tostring(b)
  end)
  return ids
end

local function listIdsGen2(S, mode)
  local root = baRoot(S)
  local proj = projectBucket(S)
  local seen, ids = {}, {}
  local function add(id)
    if type(id) ~= "string" or seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
  end

  if mode == "moves" then
    for id in pairs(proj.moves or {}) do add(id) end
    if root and root.moves then
      for id in pairs(root.moves) do add(id) end
    end
  elseif mode == "scripts" then
    for id in pairs(proj.scripts or {}) do add(id) end
    if root and type(root.scriptOrder) == "table" then
      for _, id in ipairs(root.scriptOrder) do add(id) end
    elseif root and root.scripts then
      for id in pairs(root.scripts) do add(id) end
    end
  elseif mode == "ids" then
    for id in pairs(proj.ids or {}) do add(id) end
    if root and root.ids then
      for id in pairs(root.ids) do add(id) end
    end
  elseif mode == "objects" then
    for id in pairs(proj.objects or {}) do add(id) end
    if root and root.objects then
      for id in pairs(root.objects) do add(id) end
    end
  else -- gfx
    for id in pairs(proj.gfx or {}) do add(id) end
    if root and root.gfx then
      for id in pairs(root.gfx) do add(id) end
    end
  end
  table.sort(ids)
  return ids
end

local function summarizeGen1(id, rec)
  if type(rec) ~= "table" then return "empty" end
  local sub = parseRoute(id)
  if sub == "moveAnims" then
    local n = type(rec.seq) == "table" and #rec.seq or 0
    return n == 0 and "empty seq" or (n .. " row" .. (n == 1 and "" or "s"))
  end
  if sub == "subanims" then
    local n = type(rec.blocks) == "table" and #rec.blocks or 0
    return (rec.type or "?") .. " · " .. n .. " block" .. (n == 1 and "" or "s")
  end
  if sub == "tilesheets" then
    local path = tostring(rec.path or "")
    local short = path:match("([^/\\]+)$") or path
    return string.format("%dx%d · %s tiles · %s",
      tonumber(rec.width) or 0, tonumber(rec.height) or 0,
      tostring(rec.tiles or "?"), short ~= "" and short or "?")
  end
  return "?"
end

local function summarizeGen2(S, mode, id)
  local root = baRoot(S)
  local proj = projectBucket(S)
  if mode == "moves" or mode == "ids" then
    local ptr = (mode == "moves" and ((proj.moves and proj.moves[id])
        or (root and root.moves and root.moves[id])))
      or (mode == "ids" and ((proj.ids and proj.ids[id])
        or (root and root.ids and root.ids[id])))
    local rows = ptr and select(1, gen2ResolveScript(S, ptr))
    return tostring(ptr or "?") .. " · " .. summarizeScript(rows)
  end
  if mode == "scripts" then
    local rows = select(1, gen2ResolveScript(S, id))
    local users = scriptUsers(S, id)
    local u = #users > 0 and (" · " .. users[1] .. (#users > 1 and (" +" .. (#users - 1)) or "")) or ""
    return summarizeScript(rows) .. u
  end
  if mode == "objects" then
    local rec = (proj.objects and proj.objects[id])
      or (root and root.objects and root.objects[id])
    if type(rec) ~= "table" then return "empty" end
    return tostring(rec.gfx or "?") .. " · " .. tostring(rec.func or "?")
  end
  if mode == "gfx" then
    local rec = (proj.gfx and proj.gfx[id])
      or (root and root.gfx and root.gfx[id])
    if type(rec) ~= "table" then return "empty" end
    local path = tostring(rec.image or "")
    local short = path:match("([^/\\]+)$") or path
    return string.format("%s tiles · %s", tostring(rec.tiles or "?"), short)
  end
  return "?"
end

local function summarizeSeqRow(row, i)
  if type(row) ~= "table" then return tostring(i) .. ". ?" end
  if row.effect then
    local s = string.format("%d. effect %s", i, tostring(row.effect))
    if row.sound then s = s .. "  sfx=" .. tostring(row.sound) end
    return s
  end
  local s = string.format("%d. sub=%s tile=%s delay=%s",
    i, tostring(row.subanim), tostring(row.tileset), tostring(row.delay))
  if row.sound then s = s .. "  sfx=" .. tostring(row.sound) end
  return s
end

local function cloneIntoProject(S, id, App)
  local proj = projectBucket(S)
  if proj[id] then return proj[id] end
  local base = select(1, BattleAnims.resolve(S, id))
  local copy
  if type(base) == "table" then
    copy = deepClone(base)
  else
    local sub = parseRoute(id)
    if sub == "moveAnims" then
      copy = { seq = {} }
    elseif sub == "subanims" then
      copy = { type = "NORMAL", blocks = {} }
    else
      copy = { path = "", width = 128, height = 64, tiles = 1 }
    end
  end
  copy._isNew = base == nil
  if base ~= nil then copy._isNew = false end
  proj[id] = copy
  if App then App.markDirty() end
  return copy
end

-- Clone a source moveAnim onto targetMoveId (Gen1 seq / Gen2 script pointer).
function BattleAnims.cloneMoveAnim(S, targetMoveId, sourceMoveId, App)
  if not targetMoveId or not sourceMoveId then return nil end
  if Generation.isGen2(S) then
    local ptr = select(1, gen2ResolvePointer(S, sourceMoveId))
    if not ptr then return nil end
    local map = gen2Map(S, "moves")
    map[targetMoveId] = ptr
    if App then App.markDirty() end
    return { script = ptr }
  end
  local src = select(1, BattleAnims.resolve(S, sourceMoveId))
  if type(src) ~= "table" then return nil end
  local proj = projectBucket(S)
  local copy = deepClone(src)
  local root = baRoot(S)
  local hadVanilla = root and root.moveAnims and root.moveAnims[targetMoveId]
  copy._isNew = not hadVanilla
  proj[targetMoveId] = copy
  if App then App.markDirty() end
  return copy
end

-- ---- Clone-from picker (Moves tab + Anims tab) ----

function BattleAnims.isPickerOpen(S)
  return S and S.battleAnimPicker ~= nil
end

function BattleAnims.closePicker(S)
  if not S then return end
  S.battleAnimPicker = nil
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

function BattleAnims.openPicker(S, opts)
  opts = opts or {}
  S.battleAnimPicker = {
    query = "",
    offset = 0,
    opened = true,
    focus = opts.current,
    current = opts.current,
    title = opts.title or "CLONE BATTLE ANIM FROM",
    excludeId = opts.excludeId,
    onPick = opts.onPick,
  }
end

function BattleAnims.pickerKeypressed(S, key)
  if not BattleAnims.isPickerOpen(S) then return false end
  if key == "escape" then
    BattleAnims.closePicker(S)
    return true
  end
  return false
end

function BattleAnims.drawPicker(S, x, y, w, h)
  local p = S and S.battleAnimPicker
  if not p then return end
  local s = Kit.scale
  if p.opened then
    p.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 520 * s)
  local ph = math.min(h - 24 * s, 460 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    BattleAnims.closePicker(S)
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, p.title or "CLONE BATTLE ANIM FROM")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    BattleAnims.closePicker(S)
    return
  end
  cy = cy + 22 * s

  local qh = 28 * s
  local q = Kit.textfield("ba_pick_q", cx, cy, inner, qh, p.query or "",
    "search move anims...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local list = BattleAnims.moveAnimIds(S)
  if p.excludeId then
    local filtered = {}
    for _, id in ipairs(list) do
      if id ~= p.excludeId then filtered[#filtered + 1] = id end
    end
    list = filtered
  end
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      if id:lower():find(ql, 1, true) then filtered[#filtered + 1] = id end
    end
    list = filtered
  end

  local listY = cy + qh + 8 * s
  local btnH = 32 * s
  local listH = py + ph - pad - listY - btnH - 8 * s
  local rowH = 30 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(inner)
  p.offset = Kit.scroll(cx, listY, inner, listH, p.offset or 0, #list, perPage)

  local function accept(id)
    local cb = p.onPick
    BattleAnims.closePicker(S)
    if cb then cb(id) end
  end

  if #list == 0 then
    Kit.emptyBox(cx, listY, inner, listH, "No move anims match")
  else
    if not p.focus then p.focus = list[(p.offset or 0) + 1] or list[1] end
    local focusOk = false
    for _, id in ipairs(list) do
      if id == p.focus then focusOk = true; break end
    end
    if not focusOk then p.focus = list[(p.offset or 0) + 1] or list[1] end

    local ry = listY
    for i = (p.offset or 0) + 1, math.min(#list, (p.offset or 0) + perPage) do
      local id = list[i]
      local rec = select(1, BattleAnims.resolve(S, id))
      local on = p.focus == id
      if Kit.hover(cx, ry, innerW, rowH) then p.focus = id end
      if Kit.row(cx, ry, innerW, rowH, on, PAL.blue) then
        accept(id)
        return
      end
      Kit.text("mono", Kit.ellipsize("mono", id, math.max(8, innerW * 0.55)),
        cx + 8 * s, ry + 2 * s, PAL.text)
      local sum = Generation.isGen2(S)
        and summarizeGen2(S, "moves", id)
        or summarizeGen1(id, rec)
      Kit.text("micro", Kit.ellipsize("micro", sum, math.max(8, innerW - 16 * s)),
        cx + 8 * s, ry + 16 * s, PAL.faint)
      ry = ry + rowH + 3 * s
    end
  end
  p.offset = Kit.scrollbar(cx, listY, inner, listH, p.offset or 0, #list, perPage)

  local focusId = p.focus
  if focusId and Kit.button(cx, listY + listH + 4 * s, inner, btnH,
      "Clone " .. Kit.ellipsize("small", focusId, inner - 80 * s), {
        kind = "primary",
        tooltip = Generation.isGen2(S)
          and "Copy this move's script pointer onto the target"
          or "Copy this anim's sequence onto the target move id",
      }) then
    accept(focusId)
  end
end

-- ---- Gen1 forms ----

local function drawMoveAnimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local proj = projectBucket(S)
  local r = (owned and proj[id]) or rec or { seq = {} }
  local seq = type(r.seq) == "table" and r.seq or {}

  local function ensure()
    if owned then return proj[id] end
    local e = cloneIntoProject(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen1(id, r), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Clone from", function(fx, fy_, fw, fh_)
    if Kit.button(fx, fy_, math.min(160 * s, fw), fh_, "Choose…", {
        kind = "accent",
        tooltip = "Replace this anim with a copy of another move's seq",
      }) then
      BattleAnims.openPicker(S, {
        current = id,
        excludeId = id,
        title = "CLONE SEQUENCE FROM",
        onPick = function(srcId)
          local src = select(1, BattleAnims.resolve(S, srcId))
          if type(src) ~= "table" then return end
          local e = ensure()
          e.seq = deepClone(src.seq) or {}
          S.battleAnimRow = 1
          App.markDirty()
        end,
      })
    end
  end)

  Kit.text("small", "Sequence", viewX, fy + 4 * s, PAL.caption)
  fy = fy + 22 * s
  S.battleAnimRow = S.battleAnimRow or 1
  if S.battleAnimRow > #seq then S.battleAnimRow = math.max(1, #seq) end

  local rowH = 26 * s
  local listH = math.min(8, math.max(3, #seq)) * (rowH + 2 * s) + 4 * s
  Kit.card(viewX, fy, viewW, listH, 8 * s)
  local ry = fy + 4 * s
  local maxShow = math.floor((listH - 4 * s) / (rowH + 2 * s))
  local start = 1
  if #seq > maxShow then
    start = math.max(1, (S.battleAnimRow or 1) - maxShow + 1)
  end
  for i = start, math.min(#seq, start + maxShow - 1) do
    local on = S.battleAnimRow == i
    if Kit.row(viewX + 4 * s, ry, viewW - 8 * s, rowH, on, PAL.blue) then
      S.battleAnimRow = i
    end
    Kit.text("micro", Kit.ellipsize("micro", summarizeSeqRow(seq[i], i),
        viewW - 20 * s),
      viewX + 10 * s, ry + 6 * s, on and PAL.heading or PAL.text)
    ry = ry + rowH + 2 * s
  end
  fy = fy + listH + 8 * s

  local btnW = 72 * s
  if Kit.button(viewX, fy, btnW, fh, "+ Row", { kind = "good" }) then
    local e = ensure()
    e.seq = e.seq or {}
    e.seq[#e.seq + 1] = { subanim = 0, tileset = 0, delay = 1 }
    S.battleAnimRow = #e.seq
    App.markDirty()
  end
  if Kit.button(viewX + btnW + 6 * s, fy, btnW, fh, "+ SE", {
      kind = "ghost", tooltip = "Add special-effect row",
    }) then
    local e = ensure()
    e.seq = e.seq or {}
    e.seq[#e.seq + 1] = { effect = "SE_DELAY_ANIMATION_10" }
    S.battleAnimRow = #e.seq
    App.markDirty()
  end
  if #seq > 0 and Kit.button(viewX + 2 * (btnW + 6 * s), fy, btnW, fh, "Del", {
      kind = "danger",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    table.remove(e.seq, i)
    S.battleAnimRow = math.max(1, math.min(i, #e.seq))
    App.markDirty()
  end
  if #seq > 1 and Kit.button(viewX + 3 * (btnW + 6 * s), fy, btnW, fh, "Up", {
      kind = "ghost",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    if i > 1 then
      e.seq[i], e.seq[i - 1] = e.seq[i - 1], e.seq[i]
      S.battleAnimRow = i - 1
      App.markDirty()
    end
  end
  if #seq > 1 and Kit.button(viewX + 4 * (btnW + 6 * s), fy, btnW, fh, "Down", {
      kind = "ghost",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    if i < #e.seq then
      e.seq[i], e.seq[i + 1] = e.seq[i + 1], e.seq[i]
      S.battleAnimRow = i + 1
      App.markDirty()
    end
  end
  fy = fy + fh + 12 * s

  local idx = S.battleAnimRow or 1
  local cur = seq[idx]
  if cur then
    Kit.text("small", "Row " .. idx, viewX, fy + 4 * s, PAL.caption)
    fy = fy + 22 * s

    local isEffect = cur.effect ~= nil
    row("Kind", function(fx, fy_, fw, fh_)
      local label = isEffect and "effect" or "subanim"
      if Kit.button(fx, fy_, 120 * s, fh_, label, { kind = "ghost" }) then
        local e = ensure()
        local row_ = e.seq[idx]
        if not row_ then return end
        if row_.effect then
          e.seq[idx] = { subanim = 0, tileset = 0, delay = 1, sound = row_.sound }
        else
          e.seq[idx] = { effect = "SE_DELAY_ANIMATION_10", sound = row_.sound }
        end
        App.markDirty()
      end
    end)

    r = (owned and proj[id]) or r
    seq = type(r.seq) == "table" and r.seq or {}
    cur = seq[idx]
    if not cur then return fy, owned end
    isEffect = cur.effect ~= nil

    if isEffect then
      row("Effect", function(fx, fy_, fw, fh_)
        local v = RegList.field(App, "ba_eff", fx, fy_, fw, fh_,
          tostring(cur.effect or ""), "SE_...")
        if v ~= tostring(cur.effect or "") then
          ensure().seq[idx].effect = v
        end
      end)
    else
      row("Subanim", function(fx, fy_, fw, fh_)
        local v = RegList.num(App, "ba_sub", fx, fy_, 80 * s, fh_,
          tonumber(cur.subanim) or 0)
        if v ~= (tonumber(cur.subanim) or 0) then
          ensure().seq[idx].subanim = v
        end
      end)
      row("Tileset", function(fx, fy_, fw, fh_)
        local v = RegList.num(App, "ba_tile", fx, fy_, 80 * s, fh_,
          tonumber(cur.tileset) or 0)
        if v ~= (tonumber(cur.tileset) or 0) then
          ensure().seq[idx].tileset = v
        end
      end)
      row("Delay", function(fx, fy_, fw, fh_)
        local v = RegList.num(App, "ba_delay", fx, fy_, 80 * s, fh_,
          tonumber(cur.delay) or 1)
        if v < 1 then v = 1 end
        if v > 63 then v = 63 end
        if v ~= (tonumber(cur.delay) or 1) then
          ensure().seq[idx].delay = v
        end
      end)
    end
    row("Sound", function(fx, fy_, fw, fh_)
      local curS = tostring(cur.sound or "")
      local v = RegList.field(App, "ba_snd", fx, fy_, fw, fh_, curS, "MOVE_ID or empty")
      if v ~= curS then
        local e = ensure().seq[idx]
        if v == "" then e.sound = nil else e.sound = v end
      end
    end)
  else
    Kit.text("micro", "Empty sequence — add a row or clone from another move.",
      viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end

  fy = fy + 8 * s
  fy = BattleAnimPreview.draw(S, id, viewX, fy, viewW, s)

  return fy, owned
end

local function drawSubanimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  local proj = projectBucket(S)
  local r = (owned and proj[id]) or rec or { type = "NORMAL", blocks = {} }
  local s = Kit.scale

  local function ensure()
    if owned then return proj[id] end
    local e = cloneIntoProject(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen1(id, r), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Type", function(fx, fy_, fw, fh_)
    local cur = tostring(r.type or "NORMAL")
    if Kit.button(fx, fy_, math.min(160 * s, fw), fh_, cur, { kind = "ghost" }) then
      ensure().type = RegList.cycle(SUBANIM_TYPES, cur)
    end
  end)

  local blocks = type(r.blocks) == "table" and r.blocks or {}
  Kit.text("small", "Blocks (" .. #blocks .. ")", viewX, fy + 4 * s, PAL.caption)
  fy = fy + 22 * s
  for i = 1, math.min(#blocks, 12) do
    local b = blocks[i]
    local line = string.format("%d. block=%s coord=%s mode=%s",
      i, tostring(b.block), tostring(b.coord), tostring(b.mode))
    Kit.text("micro", Kit.ellipsize("micro", line, viewW), viewX, fy, PAL.muted)
    fy = fy + 16 * s
  end
  if #blocks > 12 then
    Kit.text("micro", ("… %d more"):format(#blocks - 12), viewX, fy, PAL.faint)
    fy = fy + 16 * s
  end
  if #blocks == 0 then
    Kit.text("micro", "No frame-block refs (read-only summary for now).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
  end

  return fy, owned
end

local function drawTilesheetForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  local proj = projectBucket(S)
  local r = (owned and proj[id]) or rec or {}
  local s = Kit.scale

  local function ensure()
    if owned then return proj[id] end
    local e = cloneIntoProject(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen1(id, r), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Path", function(fx, fy_, fw, fh_)
    local cur = tostring(r.path or "")
    local v = RegList.field(App, "ba_path", fx, fy_, fw, fh_, cur, "assets/...")
    if v ~= cur then ensure().path = v end
  end)
  row("Width", function(fx, fy_, fw, fh_)
    local cur = tonumber(r.width) or 0
    local v = RegList.num(App, "ba_w", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().width = v end
  end)
  row("Height", function(fx, fy_, fw, fh_)
    local cur = tonumber(r.height) or 0
    local v = RegList.num(App, "ba_h", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().height = v end
  end)
  row("Tiles", function(fx, fy_, fw, fh_)
    local cur = tonumber(r.tiles) or 0
    local v = RegList.num(App, "ba_tiles", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().tiles = v end
  end)

  if r.path and r.path ~= "" then
    fy = fy + Preview.draw(S, r.path, viewX, fy,
      math.min(viewW, 240 * s), math.min(160 * s, 120 * s)) + 8 * s
  end

  return fy, owned
end

-- ---- Gen2 forms ----

local function drawGen2MoveForm(S, App, id, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local root = baRoot(S)
  local moves = gen2Map(S, "moves")
  local owned = moves[id] ~= nil
  local ptr = moves[id] or (root and root.moves and root.moves[id]) or ""

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen2(S, "moves", id), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Script", function(fx, fy_, fw, fh_)
    local v = RegList.field(App, "ba2_ptr", fx, fy_, fw, fh_, tostring(ptr), "628a")
    v = v:lower():gsub("%s+", "")
    if v ~= tostring(ptr) and v:match("^[%w_]+$") then
      moves[id] = v
      owned = true
      App.markDirty()
      ptr = v
    end
  end)

  row("Clone from", function(fx, fy_, fw, fh_)
    if Kit.button(fx, fy_, math.min(140 * s, fw), fh_, "Choose…", {
        kind = "accent",
        tooltip = "Point this move at another move's script",
      }) then
      BattleAnims.openPicker(S, {
        current = id,
        excludeId = id,
        title = "CLONE SCRIPT POINTER FROM",
        onPick = function(srcId)
          local srcPtr = select(1, gen2ResolvePointer(S, srcId))
          if not srcPtr then return end
          moves[id] = srcPtr
          App.markDirty()
        end,
      })
    end
  end)

  row("Actions", function(fx, fy_, fw, fh_)
    local bw = 110 * s
    if Kit.button(fx, fy_, bw, fh_, "Edit script", {
        kind = "ghost",
        tooltip = "Open this pointer on the Scripts mode",
      }) and ptr ~= "" then
      S.battleAnimMode = "scripts"
      S.battleAnimScriptId = ptr
      S.battleAnimRow = 1
    end
    if Kit.button(fx + bw + 6 * s, fy_, bw + 20 * s, fh_, "Duplicate", {
        kind = "accent",
        tooltip = "Copy script rows to a new pointer and assign it here",
      }) and ptr ~= "" then
      local rows = select(1, gen2ResolveScript(S, ptr))
      local newPtr = gen2NewScriptPtr(S)
      gen2Map(S, "scripts")[newPtr] = deepClone(rows or { { "ret" } })
      moves[id] = newPtr
      S.battleAnimMode = "scripts"
      S.battleAnimScriptId = newPtr
      App.markDirty()
    end
  end)

  local rows = ptr ~= "" and select(1, gen2ResolveScript(S, ptr)) or nil
  if type(rows) == "table" then
    Kit.text("small", "Commands (" .. #rows .. ")", viewX, fy + 4 * s, PAL.caption)
    fy = fy + 20 * s
    for i = 1, math.min(#rows, 10) do
      Kit.text("micro", Kit.ellipsize("micro", i .. ". " .. formatCmdRow(rows[i]), viewW),
        viewX, fy, PAL.muted)
      fy = fy + 15 * s
    end
    if #rows > 10 then
      Kit.text("micro", ("… %d more"):format(#rows - 10), viewX, fy, PAL.faint)
      fy = fy + 16 * s
    end
  end

  fy = fy + 8 * s
  fy = BattleAnimPreview.draw(S, id, viewX, fy, viewW, s)

  return fy, owned
end

local function drawGen2ScriptForm(S, App, id, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local map = gen2Map(S, "scripts")
  local owned = map[id] ~= nil
  local rows = map[id] or select(1, gen2ResolveScript(S, id)) or {}
  if type(rows) ~= "table" then rows = {} end

  local function ensure()
    if owned then return map[id] end
    local e = gen2EnsureScript(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  local users = scriptUsers(S, id)
  Kit.text("micro", summarizeScript(rows)
      .. (#users > 0 and (" · used by " .. table.concat(users, ", ")) or ""),
    viewX, fy, PAL.muted)
  fy = fy + 18 * s

  S.battleAnimRow = S.battleAnimRow or 1
  if S.battleAnimRow > #rows then S.battleAnimRow = math.max(1, #rows) end

  local rowH = 26 * s
  local listH = math.min(10, math.max(3, #rows)) * (rowH + 2 * s) + 4 * s
  Kit.card(viewX, fy, viewW, listH, 8 * s)
  local ry = fy + 4 * s
  local maxShow = math.floor((listH - 4 * s) / (rowH + 2 * s))
  local start = 1
  if #rows > maxShow then
    start = math.max(1, (S.battleAnimRow or 1) - maxShow + 1)
  end
  for i = start, math.min(#rows, start + maxShow - 1) do
    local on = S.battleAnimRow == i
    if Kit.row(viewX + 4 * s, ry, viewW - 8 * s, rowH, on, PAL.blue) then
      S.battleAnimRow = i
    end
    Kit.text("micro", Kit.ellipsize("micro", i .. ". " .. formatCmdRow(rows[i]),
        viewW - 20 * s),
      viewX + 10 * s, ry + 6 * s, on and PAL.heading or PAL.text)
    ry = ry + rowH + 2 * s
  end
  fy = fy + listH + 8 * s

  local btnW = 72 * s
  if Kit.button(viewX, fy, btnW, fh, "+ Cmd", { kind = "good" }) then
    local e = ensure()
    e[#e + 1] = { "wait", 1 }
    S.battleAnimRow = #e
    App.markDirty()
  end
  if #rows > 0 and Kit.button(viewX + btnW + 6 * s, fy, btnW, fh, "Del", {
      kind = "danger",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    table.remove(e, i)
    S.battleAnimRow = math.max(1, math.min(i, #e))
    App.markDirty()
  end
  if #rows > 1 and Kit.button(viewX + 2 * (btnW + 6 * s), fy, btnW, fh, "Up", {
      kind = "ghost",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    if i > 1 then
      e[i], e[i - 1] = e[i - 1], e[i]
      S.battleAnimRow = i - 1
      App.markDirty()
    end
  end
  if #rows > 1 and Kit.button(viewX + 3 * (btnW + 6 * s), fy, btnW, fh, "Down", {
      kind = "ghost",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    if i < #e then
      e[i], e[i + 1] = e[i + 1], e[i]
      S.battleAnimRow = i + 1
      App.markDirty()
    end
  end
  fy = fy + fh + 12 * s

  local idx = S.battleAnimRow or 1
  local cur = (owned and map[id] or rows)[idx]
  if cur then
    Kit.text("small", "Command " .. idx, viewX, fy + 4 * s, PAL.caption)
    fy = fy + 22 * s
    row("Verb", function(fx, fy_, fw, fh_)
      local curV = tostring(cur[1] or "wait")
      if Kit.button(fx, fy_, math.min(160 * s, fw), fh_, curV, { kind = "accent" }) then
        local e = ensure()
        e[idx] = e[idx] or { "wait", 1 }
        e[idx][1] = RegList.cycle(SCRIPT_VERBS, curV)
        App.markDirty()
      end
    end)
    row("Line", function(fx, fy_, fw, fh_)
      local curLine = formatCmdRow(cur)
      local v = RegList.field(App, "ba2_cmd", fx, fy_, fw, fh_, curLine,
        "wait | 4")
      if v ~= curLine then
        ensure()[idx] = parseCmdRow(v)
      end
    end)
  else
    Kit.text("micro", "Empty script — add a command (usually ends with ret).",
      viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end

  fy = fy + 8 * s
  fy = BattleAnimPreview.draw(S, id, viewX, fy, viewW, s)

  return fy, owned
end

local function drawGen2IdForm(S, App, id, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local root = baRoot(S)
  local ids = gen2Map(S, "ids")
  local owned = ids[id] ~= nil
  local ptr = ids[id] or (root and root.ids and root.ids[id]) or ""

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen2(S, "ids", id), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Script", function(fx, fy_, fw, fh_)
    local v = RegList.field(App, "ba2_idptr", fx, fy_, fw, fh_, tostring(ptr), "54a3")
    v = v:lower():gsub("%s+", "")
    if v ~= tostring(ptr) and v:match("^[%w_]+$") then
      ids[id] = v
      owned = true
      App.markDirty()
      ptr = v
    end
  end)

  if Kit.button(viewX + labelW, fy, 120 * s, fh, "Edit script", { kind = "ghost" })
      and ptr ~= "" then
    S.battleAnimMode = "scripts"
    S.battleAnimScriptId = ptr
  end
  fy = fy + fh + 8 * s

  return fy, owned
end

local function drawGen2ObjectForm(S, App, id, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local root = baRoot(S)
  local map = gen2Map(S, "objects")
  local owned = map[id] ~= nil
  local rec = map[id] or (root and root.objects and root.objects[id]) or {}

  local function ensure()
    if owned then return map[id] end
    map[id] = deepClone(rec)
    owned = true
    if App then App.markDirty() end
    return map[id]
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen2(S, "objects", id), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  for _, key in ipairs({ "gfx", "palette", "frameset", "func" }) do
    row(key, function(fx, fy_, fw, fh_)
      local cur = tostring(rec[key] or "")
      local v = RegList.field(App, "ba2_obj_" .. key, fx, fy_, fw, fh_, cur, key)
      if v ~= cur then ensure()[key] = v end
    end)
    rec = map[id] or rec
  end
  row("fixY", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.fixY) or 0
    local v = RegList.num(App, "ba2_fixy", fx, fy_, 80 * s, fh_, cur)
    v = math.max(0, math.min(255, v))
    if v ~= cur then ensure().fixY = v end
  end)
  row("flags", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.flags) or 0
    local v = RegList.num(App, "ba2_flags", fx, fy_, 80 * s, fh_, cur)
    v = math.max(0, math.min(255, v))
    if v ~= cur then ensure().flags = v end
  end)

  return fy, owned
end

local function drawGen2GfxForm(S, App, id, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local root = baRoot(S)
  local map = gen2Map(S, "gfx")
  local owned = map[id] ~= nil
  local rec = map[id] or (root and root.gfx and root.gfx[id]) or {}

  local function ensure()
    if owned then return map[id] end
    map[id] = deepClone(rec)
    owned = true
    if App then App.markDirty() end
    return map[id]
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarizeGen2(S, "gfx", id), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Image", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.image or "")
    local browseW = 90 * s
    local pathW = math.max(60 * s, fw - browseW - 6 * s)
    Kit.text("micro", Kit.ellipsize("micro", cur ~= "" and cur or "(none)", pathW),
      fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + pathW + 6 * s, fy_, browseW, fh_, "Browse", {
        kind = "ghost",
      }) then
      App.pickFile("Battle anim GFX PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          if not picked or picked == "" then return end
          App.importToMod(picked, nil, function(rel)
            ensure().image = rel
            App.markDirty()
          end)
        end)
    end
  end)
  row("Path", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.image or "")
    local v = RegList.field(App, "ba2_gfx", fx, fy_, fw, fh_, cur, "assets/...")
    if v ~= cur then ensure().image = v end
  end)
  row("Tiles", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.tiles) or 1
    local v = RegList.num(App, "ba2_gtiles", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().tiles = math.max(1, v) end
  end)
  row("Wide", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.wide) or 1
    local v = RegList.num(App, "ba2_gwide", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().wide = math.max(1, v) end
  end)

  rec = map[id] or rec
  if rec.image and rec.image ~= "" then
    fy = fy + Preview.draw(S, rec.image, viewX, fy,
      math.min(viewW, 240 * s), math.min(160 * s, 120 * s)) + 8 * s
  end

  return fy, owned
end

local function isOwnedGen2(S, mode, id)
  local proj = projectBucket(S)
  local bucket = mode
  if mode == "moves" then bucket = "moves"
  elseif mode == "scripts" then bucket = "scripts"
  elseif mode == "ids" then bucket = "ids"
  elseif mode == "objects" then bucket = "objects"
  else bucket = "gfx" end
  return type(proj[bucket]) == "table" and proj[bucket][id] ~= nil
end

local function revertGen2(S, mode, id)
  local proj = projectBucket(S)
  local bucket = (mode == "gfx") and "gfx" or mode
  if type(proj[bucket]) == "table" then
    proj[bucket][id] = nil
  end
end

-- ---- Main draw ----

local function drawGen1(S, x, y, w, h, App)
  local s = Kit.scale
  local proj = projectBucket(S)

  local prevMode = S._battleAnimModeDrawn
  local modeY = RegList.modeChips(S, "battleAnimMode", MODES_GEN1, x, y, s)
  local mode = S.battleAnimMode or "moves"
  if prevMode and prevMode ~= mode then
    S.battleAnimListOffset = 0
    S.battleAnimRow = 1
  end
  S._battleAnimModeDrawn = mode
  local ids = listIdsGen1(S, mode)

  local selKey = (mode == "moves" and "battleAnimMoveId")
    or (mode == "subanims" and "battleAnimSubId")
    or "battleAnimSheetId"
  if mode == "moves" and S.battleAnimId and not S.battleAnimMoveId then
    S.battleAnimMoveId = S.battleAnimId
  end
  local title = (mode == "moves" and "MOVE ANIMS")
    or (mode == "subanims" and "SUBANIMS")
    or "TILESHEETS"

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w,
    h - (modeY - y), title, ids, {
      queryKey = "battleAnimQuery",
      offsetKey = "battleAnimListOffset",
      selKey = selKey,
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        local rec = select(1, BattleAnims.resolve(S, id))
        return tostring(summarizeGen1(id, rec)):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = mode == "moves" and "+ New move anim" or nil,
      onFooter = mode == "moves" and function()
        local nid = "NEW_MOVE_ANIM"
        local n = 1
        while proj[nid] or (baRoot(S) and baRoot(S).moveAnims
            and baRoot(S).moveAnims[nid]) do
          n = n + 1
          nid = "NEW_MOVE_ANIM_" .. n
        end
        proj[nid] = { seq = {}, _isNew = true }
        S.battleAnimMoveId = nid
        S.battleAnimId = nid
        S.battleAnimRow = 1
        App.markDirty()
      end or nil,
    })

  if not S[selKey] then S[selKey] = shown[1] end
  local id = S[selKey]
  if mode == "moves" then S.battleAnimId = id end
  local rec, owned = BattleAnims.resolve(S, id)
  if not id then
    Kit.emptyBox(formX, listY, formW, listH,
      "No battle anims loaded (Import ROM / Link Recomp)")
    return
  end

  Kit.caption(formX, y, (id or "?") .. (owned and "" or "  (vanilla)"))

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "battleAnimFormScroll", tostring(id) .. ":" .. mode,
    owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 100 * s
  local fh = 28 * s

  if mode == "moves" then
    fy, owned = drawMoveAnimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  elseif mode == "subanims" then
    fy, owned = drawSubanimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  else
    fy, owned = drawTilesheetForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  end

  if not owned then
    Kit.text("micro", "Edit clones into the mod (Save emits battle_anims patch).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      cloneIntoProject(S, id, App)
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "battleAnimFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
end

local function drawGen2(S, x, y, w, h, App)
  local s = Kit.scale
  local prevMode = S._battleAnimModeDrawn
  local modeY = RegList.modeChips(S, "battleAnimMode", MODES_GEN2, x, y, s)
  local mode = S.battleAnimMode or "moves"
  -- Drop Gen1-only modes if sticky from a prior Red session.
  if mode == "subanims" or mode == "tilesheets" then
    mode = "moves"
    S.battleAnimMode = mode
  end
  if prevMode and prevMode ~= mode then
    S.battleAnimListOffset = 0
    S.battleAnimRow = 1
  end
  S._battleAnimModeDrawn = mode

  local ids = listIdsGen2(S, mode)
  local selKey = (mode == "moves" and "battleAnimMoveId")
    or (mode == "scripts" and "battleAnimScriptId")
    or (mode == "ids" and "battleAnimStatusId")
    or (mode == "objects" and "battleAnimObjId")
    or "battleAnimGfxId"

  if mode == "moves" and S.battleAnimId and not S.battleAnimMoveId then
    S.battleAnimMoveId = S.battleAnimId
  end

  local title = (mode == "moves" and "MOVE → SCRIPT")
    or (mode == "scripts" and "SCRIPTS")
    or (mode == "ids" and "STATUS IDS")
    or (mode == "objects" and "OBJECTS")
    or "GFX"

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w,
    h - (modeY - y), title, ids, {
      queryKey = "battleAnimQuery",
      offsetKey = "battleAnimListOffset",
      selKey = selKey,
      accent = PAL.blue,
      isOwned = function(id) return isOwnedGen2(S, mode, id) end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        return tostring(summarizeGen2(S, mode, id)):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = (mode == "scripts" and "+ New script")
        or (mode == "moves" and "+ Map move")
        or nil,
      onFooter = (mode == "scripts" and function()
          local ptr = gen2NewScriptPtr(S)
          gen2Map(S, "scripts")[ptr] = { { "ret" } }
          S.battleAnimScriptId = ptr
          S.battleAnimRow = 1
          App.markDirty()
        end)
        or (mode == "moves" and function()
          local nid = "NEW_MOVE"
          local n = 1
          local root = baRoot(S)
          local moves = gen2Map(S, "moves")
          while moves[nid] or (root and root.moves and root.moves[nid]) do
            n = n + 1
            nid = "NEW_MOVE_" .. n
          end
          local ptr = gen2NewScriptPtr(S)
          gen2Map(S, "scripts")[ptr] = { { "ret" } }
          moves[nid] = ptr
          S.battleAnimMoveId = nid
          S.battleAnimId = nid
          App.markDirty()
        end)
        or nil,
    })

  if not S[selKey] then S[selKey] = shown[1] end
  local id = S[selKey]
  if mode == "moves" then S.battleAnimId = id end
  if not id then
    Kit.emptyBox(formX, listY, formW, listH,
      "No battle_anims (Import Gold/Silver ROM / Link Recomp)")
    return
  end

  local owned = isOwnedGen2(S, mode, id)
  Kit.caption(formX, y, (id or "?") .. (owned and "" or "  (vanilla)"))

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "battleAnimFormScroll", "g2:" .. tostring(id) .. ":" .. mode,
    owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 100 * s
  local fh = 28 * s

  if mode == "moves" then
    fy, owned = drawGen2MoveForm(S, App, id, viewX, viewW, fy, fh, labelW)
  elseif mode == "scripts" then
    fy, owned = drawGen2ScriptForm(S, App, id, viewX, viewW, fy, fh, labelW)
  elseif mode == "ids" then
    fy, owned = drawGen2IdForm(S, App, id, viewX, viewW, fy, fh, labelW)
  elseif mode == "objects" then
    fy, owned = drawGen2ObjectForm(S, App, id, viewX, viewW, fy, fh, labelW)
  else
    fy, owned = drawGen2GfxForm(S, App, id, viewX, viewW, fy, fh, labelW)
  end

  if not owned then
    Kit.text("micro",
      "First edit clones into the mod (Save = battle_anims:patch bucket).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
  end

  FormPane.finish(S, "battleAnimFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    revertGen2(S, mode, id)
    App.markDirty()
  end
end

function BattleAnims.draw(S, x, y, w, h, App)
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  if Generation.isGen2(S) then
    drawGen2(S, x, y, w, h, App)
  else
    drawGen1(S, x, y, w, h, App)
  end
end

return BattleAnims
