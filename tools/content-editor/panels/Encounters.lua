-- Encounters tab: wild tables (grass/water/fishing) + Special gifts/battles.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local FormPane = require("FormPane")
local RegList = require("RegList")
local SpeciesPicker = require("SpeciesPicker")
local EncounterEdit = require("EncounterEdit")
local Maps = require("Maps")
local Generation = require("Generation")
local PAL = Theme.PAL

local Encounters = {}

local DV_KEYS = { "attack", "defense", "speed", "special", "hp" }
local DV_LABELS = {
  attack = "Atk", defense = "Def", speed = "Spe", special = "Spc", hp = "HP",
}

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function deriveHpDv(dvs)
  if type(dvs) ~= "table" then return 0 end
  return (tonumber(dvs.attack) or 0) % 2 * 8
    + (tonumber(dvs.defense) or 0) % 2 * 4
    + (tonumber(dvs.speed) or 0) % 2 * 2
    + (tonumber(dvs.special) or 0) % 2
end

local function perfectDvs()
  return { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
end

local function isPerfect(dvs)
  if type(dvs) ~= "table" then return false end
  for _, k in ipairs({ "attack", "defense", "speed", "special" }) do
    if tonumber(dvs[k]) ~= 15 then return false end
  end
  return true
end

local function defaultSpecial(id)
  return {
    id = id,
    kind = "gift",
    mapId = "",
    species = "MAGIKARP",
    level = 100,
    moves = { "HYDRO_PUMP" },
    dvs = perfectDvs(),
    unique = true,
    flag = "GOT_" .. id,
    text = "Wow! A legendary MAGIKARP!",
    after = "I already gave you one.",
    won = "You're amazing!",
    bindTextId = "",
  }
end

local function drawWild(S, App, x, y, w, h)
  local s = Kit.scale
  local ids = Maps.allMapIds(S)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "MAPS", ids, {
      queryKey = "encountersMapQuery",
      offsetKey = "encountersMapOffset",
      selKey = "encountersMapId",
      accent = PAL.green,
      isOwned = function(id)
        return S.project.maps and S.project.maps[id] ~= nil
      end,
      filter = function(id, q)
        return id:lower():find(q:lower(), 1, true) ~= nil
      end,
      onSelect = function(id) S.mapId = id end,
    })

  if not S.encountersMapId then
    S.encountersMapId = S.mapId or shown[1]
  end
  local mapId = S.encountersMapId
  if not mapId then
    Kit.emptyBox(formX, listY, formW, listH, "No maps in data")
    return
  end

  local map = select(1, Maps.resolveMapDef(S, mapId))
  local function mutate()
    map = Maps.ensureOwned(S, mapId)
    return map
  end

  Kit.caption(formX, y, mapId or "?")
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "encountersWildScroll", tostring(mapId), 12 * s)
  local contentTop = fy
  local fh = 28 * s
  local listBottom = listY + listH - 16 * s

  if Kit.button(viewX, fy, 140 * s, 26 * s, "Open in Maps", { kind = "ghost" }) then
    S.tab = "maps"
    S.builderPane = "details"
    S.mapId = mapId
    S.mapSection = "encounters"
  end
  fy = fy + 32 * s

  fy = EncounterEdit.drawWild(S, map, mutate, App, viewX - 10 * s, fy,
    viewW + 10 * s, listBottom, fh, s) or fy

  FormPane.finish(S, "encountersWildScroll", contentTop, fy, view)
end

local function specialIds(S)
  return RegList.sortedKeys(S.project.specialEncounters)
end

local function renameSpecial(S, oldId, newId)
  newId = tostring(newId or ""):upper():gsub("%s+", "_"):gsub("%W+", "_")
  if newId == "" or newId == oldId then return oldId end
  local bucket = S.project.specialEncounters
  if bucket[newId] then return oldId end
  local rec = bucket[oldId]
  if not rec then return oldId end
  bucket[oldId] = nil
  rec.id = newId
  bucket[newId] = rec
  return newId
end

local function drawSpecial(S, App, x, y, w, h)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  local bucket = S.project.specialEncounters
  local ids = specialIds(S)

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "SPECIALS", ids, {
      queryKey = "encountersSpecQuery",
      offsetKey = "encountersSpecOffset",
      selKey = "specialEncounterId",
      accent = PAL.yellow,
      isOwned = function() return true end,
      footerLabel = "+ New",
      onFooter = function()
        local nid = "MAGIKARP_LEGEND"
        local n = 1
        while bucket[nid] do
          n = n + 1
          nid = "SPECIAL_" .. n
        end
        bucket[nid] = defaultSpecial(nid)
        S.specialEncounterId = nid
        App.markDirty()
      end,
    })

  if not S.specialEncounterId then S.specialEncounterId = shown[1] end
  local id = S.specialEncounterId
  if not id or not bucket[id] then
    Kit.emptyBox(formX, listY, formW, listH,
      "No specials yet — click + New for a custom gift/battle")
    return
  end

  local rec = bucket[id]
  Kit.caption(formX, y, id)
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "encountersSpecScroll", tostring(id), 44 * s)
  local contentTop = fy
  local fh = 28 * s
  local labelW = 110 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  row("Id", function(fx, fy_, fw, fh_)
    local v = field(App, "spec_id", fx, fy_, fw, fh_, id, "MAGIKARP_LEGEND")
      :upper():gsub("%s+", "_"):gsub("%W+", "_")
    if v ~= id and v ~= "" then
      local nid = renameSpecial(S, id, v)
      if nid ~= id then
        S.specialEncounterId = nid
        id = nid
        rec = bucket[id]
      end
    end
  end)

  row("Kind", function(fx, fy_, fw, fh_)
    local sx = fx
    for _, kind in ipairs({ "gift", "battle" }) do
      local on = (rec.kind or "gift") == kind
      local bw = Kit.textWidth("micro", kind:upper()) + 16 * s
      if Kit.chip(sx, fy_, bw, fh_, kind:upper(), on, PAL.green) then
        rec.kind = kind
        App.markDirty()
      end
      sx = sx + bw + 4 * s
    end
  end)

  row("Map", function(fx, fy_, fw, fh_)
    local v = field(App, "spec_map", fx, fy_, fw, fh_,
      rec.mapId or "", "PALLET_TOWN"):upper():gsub("%s+", "_")
    if v ~= (rec.mapId or "") then rec.mapId = v; App.markDirty() end
  end)

  row("Species", function(fx, fy_, fw, fh_)
    SpeciesPicker.field(S, {
      x = fx, y = fy_, w = fw, h = fh_,
      current = rec.species or "MAGIKARP",
      title = "SPECIAL ENCOUNTER SPECIES",
      onPick = function(id)
        rec.species = id
        App.markDirty()
      end,
    })
  end)

  row("Level", function(fx, fy_, fw, fh_)
    local v = tonumber(field(App, "spec_lv", fx, fy_, 70 * s, fh_,
      tostring(rec.level or 1), "1")) or 1
    v = math.max(1, math.min(100, v))
    if v ~= (rec.level or 1) then rec.level = v; App.markDirty() end
  end)

  Kit.text("micro", "Moves (up to 4)", viewX, fy, PAL.caption)
  fy = fy + 14 * s
  local moves = rec.moves or {}
  local moveW = math.max(70 * s, math.floor((viewW - 8 * s) / 4))
  local typed = {}
  for slot = 1, 4 do
    local cur = tostring(moves[slot] or "")
    local v = field(App, "spec_mv_" .. slot,
      viewX + (slot - 1) * (moveW + 4 * s), fy, moveW, fh,
      cur, "MOVE"):upper():gsub("%s+", "_")
    if v == "MOVE" then v = "" end
    typed[slot] = v
  end
  do
    local newMoves = {}
    for slot = 1, 4 do
      if typed[slot] ~= "" then newMoves[#newMoves + 1] = typed[slot] end
    end
    local same = #newMoves == #(moves or {})
    if same then
      for i = 1, #newMoves do
        if newMoves[i] ~= moves[i] then same = false; break end
      end
    end
    if not same then rec.moves = newMoves; App.markDirty() end
  end
  fy = fy + fh + 10 * s

  local dvs = rec.dvs or {}
  local perfect = isPerfect(dvs)
  Kit.text("micro", "DVs 0-15", viewX, fy, PAL.caption)
  local chipW = Kit.textWidth("micro", "Perfect") + 16 * s
  if Kit.chip(viewX + viewW - chipW, fy - 2 * s, chipW, 22 * s,
      "Perfect", perfect, PAL.yellow) then
    if perfect then
      rec.dvs = nil
    else
      rec.dvs = perfectDvs()
    end
    App.markDirty()
    dvs = rec.dvs or {}
    perfect = isPerfect(dvs)
  end
  fy = fy + 16 * s
  local numW = 42 * s
  local dvCell = numW + 26 * s
  local newDvs = {}
  for di, key in ipairs(DV_KEYS) do
    local lx = viewX + (di - 1) * dvCell
    Kit.text("micro", DV_LABELS[key], lx, fy, PAL.faint)
    local cur = dvs[key]
    if cur == nil and key == "hp" then cur = deriveHpDv(dvs) end
    local raw = field(App, "spec_dv_" .. key, lx, fy + 12 * s, numW, fh - 4 * s,
      cur ~= nil and tostring(cur) or "", "-")
    if raw ~= "" and raw ~= "-" then
      newDvs[key] = Theme.clamp(tonumber(raw) or 0, 0, 15)
    end
  end
  if next(newDvs) then
    if newDvs.hp == nil then newDvs.hp = deriveHpDv(newDvs) end
    local changed = false
    for _, k in ipairs(DV_KEYS) do
      if tonumber(newDvs[k] or -1) ~= tonumber(dvs[k] or -1) then
        changed = true; break
      end
    end
    if changed then rec.dvs = newDvs; App.markDirty() end
  end
  fy = fy + 12 * s + fh + 10 * s

  row("Unique", function(fx, fy_, fw, fh_)
    local cur = rec.unique ~= false
    if Kit.chip(fx, fy_, 80 * s, fh_, cur and "YES" or "NO", cur, PAL.yellow) then
      rec.unique = not cur
      App.markDirty()
    end
  end)

  row("Flag", function(fx, fy_, fw, fh_)
    local v = field(App, "spec_flag", fx, fy_, fw, fh_,
      rec.flag or "", "GOT_MAGIKARP"):upper():gsub("%s+", "_")
    if v ~= (rec.flag or "") then rec.flag = v; App.markDirty() end
  end)
  do
    local preview = State.modFlag(S.project,
      (rec.flag and rec.flag ~= "") and rec.flag or "GOT_SPEC")
    Kit.text("micro", preview, viewX + labelW, fy - 4 * s, PAL.faint)
    fy = fy + 12 * s
  end

  local kind = rec.kind or "gift"
  if kind == "gift" then
    row("Intro", function(fx, fy_, fw, fh_)
      local v = field(App, "spec_text", fx, fy_, fw, fh_, rec.text or "", "Here!")
      if v ~= (rec.text or "") then rec.text = v; App.markDirty() end
    end)
    row("After", function(fx, fy_, fw, fh_)
      local v = field(App, "spec_after", fx, fy_, fw, fh_,
        rec.after or "", "Already gave one.")
      if v ~= (rec.after or "") then rec.after = v; App.markDirty() end
    end)
  else
    row("Before", function(fx, fy_, fw, fh_)
      local v = field(App, "spec_text", fx, fy_, fw, fh_,
        rec.text or "", "Let's fight!")
      if v ~= (rec.text or "") then rec.text = v; App.markDirty() end
    end)
    row("Won", function(fx, fy_, fw, fh_)
      local v = field(App, "spec_won", fx, fy_, fw, fh_,
        rec.won or "", "I lost...")
      if v ~= (rec.won or "") then rec.won = v; App.markDirty() end
    end)
    row("After", function(fx, fy_, fw, fh_)
      local v = field(App, "spec_after", fx, fy_, fw, fh_,
        rec.after or "", "You're strong.")
      if v ~= (rec.after or "") then rec.after = v; App.markDirty() end
    end)
  end

  local gen2 = Generation.isGen2(S)
  row(gen2 and "Bind (scriptKey)" or "Bind text", function(fx, fy_, fw, fh_)
    local v = field(App, "spec_bind", fx, fy_, fw, fh_,
      rec.bindTextId or "", gen2 and "mod:SPECIAL_..." or "TEXT_..."):upper():gsub("%s+", "_")
    if v ~= (rec.bindTextId or "") then rec.bindTextId = v; App.markDirty() end
  end)
  Kit.text("micro",
    gen2
      and "Gold scriptKey (project.scripts) — point a map object's"
        .. " scriptKey here, or leave blank for mod:SPECIAL_<id>."
      or "Optional TEXT_* on the map — Save wires a oneshot talk script.",
    viewX, fy, PAL.faint)
  fy = fy + 20 * s

  Kit.text("micro",
    kind == "gift"
      and (gen2
        and "Save emits a givepoke script; DVs/moves add"
          .. " commands:register(mod:give_special) via a modcommand step."
        or "Save emits commands:register(mod:give_special) + SPECIALS table.")
      or ("Save emits trainers:register(OPP_SPEC_" .. id
        .. ") + trainer_headers when Bind text matches a map object."),
    viewX, fy, PAL.muted)
  fy = fy + 24 * s

  FormPane.finish(S, "encountersSpecScroll", contentTop, fy, view)
  if Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Delete", { kind = "danger" }) then
    bucket[id] = nil
    S.specialEncounterId = next(bucket)
    App.markDirty()
  end
end

function Encounters.draw(S, x, y, w, h, App)
  if Generation.isGen3(S) and S.project then return require("Gen3EncounterForms").draw(S,x,y,w,h,App) end
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local modeY = RegList.modeChips(S, "encountersMode", {
    { id = "wild", label = "Wild", tip = "Grass / water / fishing tables" },
    { id = "special", label = "Special", tip = "Custom gift or battle with DVs & moves" },
  }, x, y, s)

  local bodyY = modeY + 4 * s
  local bodyH = h - (bodyY - y)
  if S.encountersMode == "special" then
    drawSpecial(S, App, x, bodyY, w, bodyH)
  else
    drawWild(S, App, x, bodyY, w, bodyH)
  end
end

return Encounters
