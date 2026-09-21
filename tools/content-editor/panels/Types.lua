-- Types tab: browse/create types and edit matchup multipliers (x10).
-- Gold also edits foresightMatchups (the TypeMatchups block after $FE).

local Kit = require("Kit")
local Theme = require("Theme")
local Search = require("Search")
local TypeIds = require("TypeIds")
local State = require("State")
local FormPane = require("FormPane")
local RegList = require("RegList")
local Generation = require("Generation")
local PAL = Theme.PAL

local Types = {}

local MULTS = { 0, 5, 10, 20 }  -- immune / not very / neutral / super

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function numField(App, id, x, y, w, h, value)
  local v = field(App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

local function dataTypes(S)
  return S.data and S.data.type_chart and S.data.type_chart.types or nil
end

local function isVanillaType(S, id)
  if Generation.isGen2(S) or Generation.isGen3(S) then
    local types = dataTypes(S)
    return types and types[id] ~= nil
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.TYPES and TypeChart.TYPES[id] then
    return true
  end
  local types = dataTypes(S)
  return types and types[id] ~= nil
end

local function typeRecord(S, id)
  if S.project.types and S.project.types[id] then
    return S.project.types[id], true
  end
  -- Gold: prefer extracted type_chart.types (index + Gold categories).
  if Generation.isGen2(S) or Generation.isGen3(S) then
    local types = dataTypes(S)
    if types and types[id] then return types[id], false end
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.TYPES and TypeChart.TYPES[id] then
    return TypeChart.TYPES[id], false
  end
  local types = dataTypes(S)
  if types and types[id] then return types[id], false end
  return { name = id, category = "physical" }, false
end

local function ensureType(S, id, App)
  State.ensureProjectFields(S.project)
  if S.project.types[id] then return S.project.types[id] end
  local base = select(1, typeRecord(S, id))
  S.project.types[id] = {
    id = id,
    name = base.name or id,
    category = base.category or "special",
    index = base.index,
    _isNew = not isVanillaType(S, id),
  }
  App.markDirty()
  return S.project.types[id]
end

local function matchupKey(atk, def)
  return atk .. ">" .. def
end

local function getMultiplier(S, atk, def)
  local key = matchupKey(atk, def)
  if S.project.type_matchups and S.project.type_matchups[key] ~= nil then
    return S.project.type_matchups[key], true
  end
  if S.data and S.data.type_chart and S.data.type_chart.matchups then
    for _, row in ipairs(S.data.type_chart.matchups) do
      if row.attacker == atk and row.defender == def then
        return row.multiplier, false
      end
    end
  end
  return 10, false  -- default neutral
end

local function setMultiplier(S, atk, def, mult, App)
  State.ensureProjectFields(S.project)
  S.project.type_matchups = S.project.type_matchups or {}
  S.project.type_matchups[matchupKey(atk, def)] = mult
  App.markDirty()
end

local function getForesight(S, atk, def)
  local key = matchupKey(atk, def)
  if S.project.type_foresight and S.project.type_foresight[key] ~= nil then
    return S.project.type_foresight[key], true
  end
  local rows = S.data and S.data.type_chart and S.data.type_chart.foresightMatchups
  if type(rows) == "table" then
    for _, row in ipairs(rows) do
      if row.attacker == atk and row.defender == def then
        return row.multiplier, false
      end
    end
  end
  return nil, false
end

local function setForesight(S, atk, def, mult, App)
  State.ensureProjectFields(S.project)
  S.project.type_foresight = S.project.type_foresight or {}
  local key = matchupKey(atk, def)
  if mult == nil then
    S.project.type_foresight[key] = nil
  else
    S.project.type_foresight[key] = mult
  end
  App.markDirty()
end

local function foresightKeys(S)
  local seen, keys = {}, {}
  local function add(atk, def)
    local key = matchupKey(atk, def)
    if not seen[key] then
      seen[key] = true
      keys[#keys + 1] = key
    end
  end
  for key in pairs(S.project.type_foresight or {}) do
    local a, d = key:match("^([^>]+)>([^>]+)$")
    if a then add(a, d) end
  end
  local rows = S.data and S.data.type_chart and S.data.type_chart.foresightMatchups
  if type(rows) == "table" then
    for _, row in ipairs(rows) do
      if row.attacker and row.defender then
        add(row.attacker, row.defender)
      end
    end
  end
  table.sort(keys)
  return keys
end

function Types.draw(S, x, y, w, h, App)
  if Generation.isGen3(S) and S.project then require("Gen3Workbench").prepare(S) end
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  local gen2 = Generation.isGen2(S)

  local listW = math.min(200 * s, w * 0.24)
  Kit.caption(x, y, "TYPES")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qCh = Search.field(S, "typeQuery", x, qy, listW, qh, "search types...")
  if qCh then S.typeListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = TypeIds.list(S)
  if q ~= "" then ids = Search.filterIds(ids, q) end
  if not S.typeId then S.typeId = ids[1] end

  local rowH = 28 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 3 * s)))
  local scrollX, scrollY = x + 6 * s, listY + 8 * s
  local scrollW, scrollH = listW - 12 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.typeListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.typeListOffset or 0, #ids, perPage)
  local typeNav = RegList.bindNav(S, ids, {
    selKey = "typeId", offsetKey = "typeListOffset", perPage = perPage,
    onSelect = function() S.typeMatchOffset = 0 end,
  })
  local ry = scrollY
  for i = (S.typeListOffset or 0) + 1,
      math.min(#ids, (S.typeListOffset or 0) + perPage) do
    local id = ids[i]
    local owned = S.project.types[id] ~= nil
    if Kit.row(scrollX, ry, rowW, rowH, S.typeId == id, PAL.yellow) then
      typeNav.activate()
      S.typeId = id
      S.typeMatchOffset = 0
    end
    Kit.text("mono", Kit.ellipsize("mono", id, math.max(8, rowW - 12 * s)),
      x + 12 * s, ry + 6 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 3 * s
  end
  S.typeListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.typeListOffset or 0, #ids, perPage)

  if not Generation.isGen3(S) and Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New type",
      { kind = "good" }) then
    local nid = "NEW_TYPE"
    local n = 1
    local all = TypeIds.list(S)
    local used = {}
    for _, id in ipairs(all) do used[id] = true end
    while used[nid] do n = n + 1; nid = "NEW_TYPE_" .. n end
    S.project.types[nid] = {
      id = nid, name = nid, category = "special",
      index = gen2 and 28 or nil,
      _isNew = true,
    }
    S.typeId = nid
    App.markDirty()
  end

  local formX = x + listW + 12 * s
  local formW = w - listW - 12 * s
  local id = S.typeId
  if not id then
    Kit.emptyBox(formX, listY, formW, listH, "No types")
    return
  end
  local rec, owned = typeRecord(S, id)
  Kit.caption(formX, y, id .. (owned and "" or "  (vanilla)"))
  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = owned and 44 * s or 12 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "typeFormScroll", tostring(id))
  local fy, view = FormPane.begin(S, "typeFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local fh = 28 * s
  local labelW = 110 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 12 * s, fh)
    fy = fy + fh + 8 * s
  end

  row("ID", function(fx, fy_, fw, fh_)
    if Generation.isGen3(S) then Kit.caption(fx,fy_,id);return end
    local v = field(App, "ty_id", fx, fy_, fw, fh_, id, "TYPE_ID")
    if v ~= id and v:match("^[%w_]+$") and not (S.project.types and S.project.types[v]) then
      local taken = false
      for _, t in ipairs(TypeIds.list(S)) do if t == v then taken = true; break end end
      if not taken or owned then
        local r = ensureType(S, id, App)
        S.project.types[id] = nil
        r.id = v
        S.project.types[v] = r
        local function rewrite(bucket)
          local nm = {}
          for key, mult in pairs(bucket or {}) do
            local a, d = key:match("^([^>]+)>([^>]+)$")
            if a == id then a = v end
            if d == id then d = v end
            if a and d then nm[a .. ">" .. d] = mult end
          end
          return nm
        end
        S.project.type_matchups = rewrite(S.project.type_matchups)
        if gen2 then
          S.project.type_foresight = rewrite(S.project.type_foresight)
        end
        S.typeId = v
        id = v
        App.markDirty()
      end
    end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local cur = rec.name or id
    local v = field(App, "ty_name", fx, fy_, fw, fh_, cur, "NAME")
    if v ~= cur then
      rec = ensureType(S, id, App)
      rec.name = v
    end
  end)
  row("Category", function(fx, fy_, fw, fh_)
    local cur = rec.category or "special"
    if Kit.chip(fx, fy_, 120 * s, fh_, cur:upper(), true, PAL.blue) then
      rec = ensureType(S, id, App)
      rec.category = (cur == "physical") and "special" or "physical"
      App.markDirty()
    end
  end)
  if gen2 then
    row("Index", function(fx, fy_, fw, fh_)
      local cur = tonumber(rec.index)
      if cur == nil then cur = 0 end
      local v = numField(App, "ty_idx", fx, fy_, 80 * s, fh_, cur)
      v = math.max(0, math.min(255, v))
      if v ~= cur then
        rec = ensureType(S, id, App)
        rec.index = v
      end
    end)
  end

  Kit.text("micro",
    gen2
      and "x10 multipliers: 0 immune, 5 NVE, 10 neutral, 20 SE. Gold physical/special is by type index."
      or "Matchups use Gen1 x10 multipliers: 0 immune, 5 NVE, 10 neutral, 20 SE.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s
  Kit.caption(viewX, fy, "AS ATTACKER vs...")
  fy = fy + 22 * s

  local others = TypeIds.list(S)
  local mRowH = 26 * s
  for _, def in ipairs(others) do
    local mult, custom = getMultiplier(S, id, def)
    Kit.text("mono", def, viewX + 4 * s, fy + 5 * s, custom and PAL.text or PAL.muted)
    local bx = viewX + viewW - (#MULTS * 52 * s)
    for _, m in ipairs(MULTS) do
      local on = mult == m
      local label = (m == 0 and "0") or (m == 5 and "0.5") or (m == 10 and "1x") or "2x"
      if Kit.chip(bx, fy, 48 * s, mRowH, label, on, PAL.green) then
        setMultiplier(S, id, def, m, App)
      end
      bx = bx + 52 * s
    end
    fy = fy + mRowH + 3 * s
  end

  if gen2 then
    fy = fy + 10 * s
    Kit.caption(viewX, fy, "FORESIGHT MATCHUPS")
    fy = fy + 20 * s
    Kit.text("micro",
      "Rows after TypeMatchups $FE — immunities Foresight ignores (usually NORMAL/FIGHTING vs GHOST).",
      viewX, fy, PAL.muted)
    fy = fy + 20 * s

    local fKeys = foresightKeys(S)
    if #fKeys == 0 then
      Kit.text("micro", "No foresight rows yet.", viewX, fy, PAL.faint)
      fy = fy + 18 * s
    end
    for _, key in ipairs(fKeys) do
      local atk, def = key:match("^([^>]+)>([^>]+)$")
      local mult, custom = getForesight(S, atk, def)
      if mult == nil then mult = 0 end
      Kit.text("mono", Kit.ellipsize("mono", key, viewW - (#MULTS * 52 * s) - 60 * s),
        viewX + 4 * s, fy + 5 * s, custom and PAL.text or PAL.muted)
      local bx = viewX + viewW - (#MULTS * 52 * s) - 56 * s
      for _, m in ipairs(MULTS) do
        local on = mult == m
        local label = (m == 0 and "0") or (m == 5 and "0.5") or (m == 10 and "1x") or "2x"
        if Kit.chip(bx, fy, 48 * s, mRowH, label, on, PAL.yellow) then
          setForesight(S, atk, def, m, App)
        end
        bx = bx + 52 * s
      end
      if custom and Kit.button(bx, fy, 52 * s, mRowH, "×", {
          kind = "danger", tooltip = "Revert foresight row to vanilla / remove",
        }) then
        setForesight(S, atk, def, nil, App)
      end
      fy = fy + mRowH + 3 * s
    end

    if Kit.button(viewX, fy, 180 * s, fh, "+ Foresight row", {
        kind = "ghost",
        tooltip = "Add foresight matchup for selected type vs GHOST (or cycle)",
      }) then
      local def = "GHOST"
      local key = matchupKey(id, def)
      if S.project.type_foresight and S.project.type_foresight[key] ~= nil then
        -- already have this attacker; pick next defender type
        def = TypeIds.cycle(S, def) or "GHOST"
        key = matchupKey(id, def)
      end
      setForesight(S, id, def, 0, App)
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "typeFormScroll", contentTop, fy, view)

  if owned and Kit.button(formX + 12 * s, listY + listH - 36 * s, 120 * s, 28 * s,
      "Revert type", { kind = "danger" }) then
    S.project.types[id] = nil
    if rec._isNew then
      local function scrub(bucket)
        local nm = {}
        for key, mult in pairs(bucket or {}) do
          local a, d = key:match("^([^>]+)>([^>]+)$")
          if a ~= id and d ~= id then nm[key] = mult end
        end
        return nm
      end
      S.project.type_matchups = scrub(S.project.type_matchups)
      if gen2 then
        S.project.type_foresight = scrub(S.project.type_foresight)
      end
      S.typeId = TypeIds.list(S)[1]
    end
    App.markDirty()
  end
end

return Types
