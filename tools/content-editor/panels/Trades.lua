-- Trades tab: Gen1 field.trades; Gold NPC trades (events.lua / npc_trades).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local SpeciesPicker = require("SpeciesPicker")
local ItemPicker = require("ItemPicker")
local Generation = require("Generation")
local PAL = Theme.PAL

local Trades = {}

local DIALOG_SETS = {
  "TRADE_DIALOGSET_COLLECTOR",
  "TRADE_DIALOGSET_HAPPY",
  "TRADE_DIALOGSET_NEWBIE",
}

local GENDERS = {
  "TRADE_GENDER_EITHER",
  "TRADE_GENDER_MALE",
  "TRADE_GENDER_FEMALE",
}

local function cycle(list, cur)
  if type(list) ~= "table" or #list == 0 then return cur end
  for i, v in ipairs(list) do
    if v == cur then return list[(i % #list) + 1] end
  end
  return list[1]
end

local function speciesIndex(S, id)
  if not id or not S.data or not S.data.pokemon then return nil end
  local rec = S.data.pokemon[id]
  if type(rec) == "table" and type(rec.index) == "number" then
    return rec.index
  end
  return nil
end

local function baseTradesGen1(S)
  local t = S.data and S.data.field and S.data.field.trades
  return type(t) == "table" and t or {}
end

local function baseTradesGen2(S)
  local ev = S.data and (S.data.gen2EventTables or S.data.events)
  local t = ev and ev.trades
  return type(t) == "table" and t or {}
end

local function baseTrades(S)
  if Generation.isGen2(S) then return baseTradesGen2(S) end
  return baseTradesGen1(S)
end

local function cloneRowGen1(t)
  return {
    give = t.give,
    get = t.get,
    dialogset = t.dialogset or 1,
    nickname = t.nickname,
  }
end

local function cloneRowGen2(t, fallbackId)
  return {
    id = t.id ~= nil and t.id or fallbackId,
    dialog = t.dialog or DIALOG_SETS[1],
    give = t.give,
    get = t.get,
    giveIndex = t.giveIndex,
    getIndex = t.getIndex,
    nickname = t.nickname,
    dvs = type(t.dvs) == "table" and { t.dvs[1] or 0, t.dvs[2] or 0 } or { 0, 0 },
    item = t.item,
    otId = t.otId or 0,
    otName = t.otName or "",
    gender = t.gender or GENDERS[1],
  }
end

local function cloneBase(S)
  local copy = {}
  local gen2 = Generation.isGen2(S)
  for i, t in ipairs(baseTrades(S)) do
    if type(t) == "table" then
      copy[i] = gen2 and cloneRowGen2(t, i - 1) or cloneRowGen1(t)
    end
  end
  return copy
end

local function ensureTrades(S, App)
  State.ensureProjectFields(S.project)
  if type(S.project.trades) ~= "table" then
    S.project.trades = cloneBase(S)
    if App then App.markDirty() end
  end
  return S.project.trades
end

local function tradeList(S)
  if type(S.project.trades) == "table" then return S.project.trades, true end
  return baseTrades(S), false
end

local function summarize(t)
  if type(t) ~= "table" then return "?" end
  local give = t.give or "?"
  local get = t.get or "?"
  local nick = t.nickname and (" (" .. t.nickname .. ")") or ""
  return give .. " -> " .. get .. nick
end

local function dvNibbles(byte)
  byte = tonumber(byte) or 0
  return math.floor(byte / 16), byte % 16
end

function Trades.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local gen2 = Generation.isGen2(S)
  local trades, owned = tradeList(S)
  local ids = {}
  for i = 1, #trades do ids[i] = tostring(i) end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "IN-GAME TRADES", ids, {
      queryKey = "tradesQuery",
      offsetKey = "tradesListOffset",
      selKey = "tradeIndexStr",
      accent = PAL.green,
      isOwned = function() return owned end,
      searchPh = "search give/get...",
      filter = function(id, q)
        local t = trades[tonumber(id)]
        local ql = q:lower()
        return tostring(id):find(ql, 1, true)
          or summarize(t):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = "+ Trade",
      onFooter = function()
        local list = ensureTrades(S, App)
        if gen2 then
          list[#list + 1] = {
            id = #list,
            dialog = DIALOG_SETS[1],
            give = "ABRA", get = "MR_MIME",
            giveIndex = speciesIndex(S, "ABRA"),
            getIndex = speciesIndex(S, "MR_MIME"),
            nickname = "MIMEO",
            dvs = { 0x98, 0x88 },
            item = nil,
            otId = 0,
            otName = "NPC",
            gender = GENDERS[1],
          }
        else
          list[#list + 1] = {
            give = "ABRA", get = "MR_MIME", dialogset = 1, nickname = "MARCEL",
          }
        end
        S.tradeIndexStr = tostring(#list)
        App.markDirty()
      end,
    })

  if not S.tradeIndexStr and shown[1] then S.tradeIndexStr = shown[1] end
  local idx = tonumber(S.tradeIndexStr)
  if not idx or not trades[idx] then
    Kit.emptyBox(formX, listY, formW, listH,
      #trades == 0
        and (gen2
          and "No NPC trades (Import Gold/Silver ROM / Link Recomp cache)"
          or "No trades (Link Recomp / Import ROM for vanilla, or + Trade)")
        or "Select a trade")
    return
  end

  local t = trades[idx]
  local caption = gen2
    and string.format("#%d  id %s%s", idx, tostring(t.id ~= nil and t.id or (idx - 1)),
      owned and "" or "  (vanilla)")
    or string.format("#%d%s", idx, owned and "" or "  (vanilla)")
  Kit.caption(formX, y, caption)
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "tradesFormScroll", tostring(idx), owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s

  local function ensure()
    if owned then return S.project.trades[idx] end
    local list = ensureTrades(S, App)
    owned = true
    trades = list
    t = list[idx]
    return t
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro",
    gen2
      and "Gold: Save emits npc_trades:override (script `trade` id)."
      or "Events step \"In-game trade\" uses this 1-based index + a done flag.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s
  Kit.text("micro", summarize(t), viewX, fy, PAL.detail)
  fy = fy + 22 * s

  row("Wants (give)", function(fx, fy_, fw, fh_)
    SpeciesPicker.field(S, {
      x = fx, y = fy_, w = fw, h = fh_,
      current = t.give or "ABRA",
      title = "TRADE WANTS (GIVE)",
      onPick = function(id)
        local e = ensure()
        e.give = id
        if gen2 then e.giveIndex = speciesIndex(S, id) end
        App.markDirty()
      end,
    })
  end)

  row("Offers (get)", function(fx, fy_, fw, fh_)
    SpeciesPicker.field(S, {
      x = fx, y = fy_, w = fw, h = fh_,
      current = t.get or "MR_MIME",
      title = "TRADE OFFERS (GET)",
      onPick = function(id)
        local e = ensure()
        e.get = id
        if gen2 then e.getIndex = speciesIndex(S, id) end
        App.markDirty()
      end,
    })
  end)

  row("Nickname", function(fx, fy_, fw, fh_)
    local cur = tostring(t.nickname or "")
    local v = RegList.field(App, "trd_nick", fx, fy_, fw, fh_, cur,
      gen2 and "MUSCLE" or "MARCEL")
    if v ~= cur then ensure().nickname = v end
  end)

  if gen2 then
    row("Dialog set", function(fx, fy_, fw, fh_)
      local cur = t.dialog or DIALOG_SETS[1]
      if Kit.button(fx, fy_, fw, fh_, cur, { kind = "ghost" }) then
        ensure().dialog = cycle(DIALOG_SETS, cur)
        App.markDirty()
      end
    end)

    row("Gender req", function(fx, fy_, fw, fh_)
      local cur = t.gender or GENDERS[1]
      if Kit.button(fx, fy_, fw, fh_, cur, { kind = "ghost" }) then
        ensure().gender = cycle(GENDERS, cur)
        App.markDirty()
      end
    end)

    row("Held item", function(fx, fy_, fw, fh_)
      local cur = t.item
      ItemPicker.field(S, {
        x = fx, y = fy_, w = fw - 70 * s, h = fh_,
        current = cur or "GOLD_BERRY",
        title = "TRADE HELD ITEM",
        onPick = function(id)
          ensure().item = id
          App.markDirty()
        end,
      })
      if Kit.button(fx + fw - 64 * s, fy_, 60 * s, fh_, "None", {
          kind = "ghost", font = "small",
          tooltip = "Clear held item (NO_ITEM)",
        }) then
        ensure().item = nil
        App.markDirty()
      end
    end)

    row("OT name", function(fx, fy_, fw, fh_)
      local cur = tostring(t.otName or "")
      local v = RegList.field(App, "trd_otn", fx, fy_, fw, fh_, cur, "MIKE")
      if v ~= cur then ensure().otName = v end
    end)

    row("OT ID", function(fx, fy_, fw, fh_)
      local cur = tonumber(t.otId) or 0
      local v = RegList.num(App, "trd_otid", fx, fy_, 100 * s, fh_, cur)
      v = Theme.clamp(math.floor(v), 0, 65535)
      if v ~= cur then ensure().otId = v end
    end)

    row("DVs bytes", function(fx, fy_, fw, fh_)
      local dvs = type(t.dvs) == "table" and t.dvs or { 0, 0 }
      local b1 = tonumber(dvs[1]) or 0
      local b2 = tonumber(dvs[2]) or 0
      local v1 = RegList.num(App, "trd_dv1", fx, fy_, 56 * s, fh_, b1)
      local v2 = RegList.num(App, "trd_dv2", fx + 64 * s, fy_, 56 * s, fh_, b2)
      v1 = Theme.clamp(math.floor(v1), 0, 255)
      v2 = Theme.clamp(math.floor(v2), 0, 255)
      if v1 ~= b1 or v2 ~= b2 then
        ensure().dvs = { v1, v2 }
        App.markDirty()
      end
      local atk, def = dvNibbles(v1)
      local spd, spc = dvNibbles(v2)
      Kit.text("micro",
        string.format("ATK%d DEF%d SPD%d SPC%d", atk, def, spd, spc),
        fx + 132 * s, fy_ + 8 * s, PAL.faint)
    end)
  else
    row("Dialog set", function(fx, fy_, fw, fh_)
      local cur = tonumber(t.dialogset) or 1
      local v = RegList.num(App, "trd_ds", fx, fy_, 60 * s, fh_, cur)
      v = Theme.clamp(math.floor(v), 1, 3)
      if v ~= cur then ensure().dialogset = v end
      Kit.text("micro", "1-3 (WannaTrade text family)",
        fx + 70 * s, fy_ + 8 * s, PAL.faint)
    end)
  end

  if not owned then
    Kit.text("micro", "First edit clones the full trades table into the mod.",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensure()
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "tradesFormScroll", contentTop, fy, view)

  if owned then
    if Kit.button(formX + 12 * s, listY + listH - 40 * s, 100 * s, 32 * s,
        "Delete", { kind = "danger" }) then
      table.remove(S.project.trades, idx)
      if gen2 then
        for i, row in ipairs(S.project.trades) do
          if type(row) == "table" then row.id = i - 1 end
        end
      end
      S.tradeIndexStr = S.project.trades[idx] and tostring(idx)
        or (S.project.trades[idx - 1] and tostring(idx - 1)) or nil
      App.markDirty()
    end
    if Kit.button(formX + 120 * s, listY + listH - 40 * s, 120 * s, 32 * s,
        "Revert all", {
          kind = "ghost",
          tooltip = "Drop mod trades table (back to vanilla on next open)",
        }) then
      S.project.trades = nil
      S.tradeIndexStr = nil
      App.markDirty()
    end
  end
end

return Trades
