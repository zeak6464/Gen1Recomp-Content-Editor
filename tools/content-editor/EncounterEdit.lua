-- Shared wild-encounter editors (grass/water/fishing) for Maps + Encounters tabs.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local SpeciesPicker = require("SpeciesPicker")
local Generation = require("Generation")
local PAL = Theme.PAL

local EncounterEdit = {}

EncounterEdit.KINDS = {
  { id = "grass", label = "GRASS" },
  { id = "water", label = "WATER" },
  { id = "super", label = "SUPER" },
  { id = "old", label = "OLD" },
  { id = "good", label = "GOOD" },
}

EncounterEdit.KINDS_GEN2 = {
  { id = "grass", label = "GRASS" },
  { id = "water", label = "WATER" },
  { id = "fish", label = "FISH" },
  { id = "tree", label = "TREE" },
}

local TOD = { "MORN", "DAY", "NITE" }

local function copySlot(slot)
  if type(slot) ~= "table" then return { level = 5, species = "PIDGEY" } end
  local out = { level = slot.level, species = slot.species }
  if type(slot.chance) == "number" then out.chance = slot.chance end
  if type(slot.form) == "string" and slot.form ~= "" then out.form = slot.form end
  if type(slot.timeGroup) == "number" then out.timeGroup = slot.timeGroup end
  if type(slot.day) == "table" then out.day = copySlot(slot.day) end
  if type(slot.nite) == "table" then out.nite = copySlot(slot.nite) end
  return out
end

function EncounterEdit.cloneSlots(slots)
  local out = {}
  for i, slot in ipairs(slots or {}) do
    out[i] = copySlot(slot)
  end
  return out
end

local function cloneTodSlots(slots)
  if type(slots) ~= "table" then return { MORN = {}, DAY = {}, NITE = {} } end
  if slots.MORN or slots.DAY or slots.NITE then
    local out = {}
    for _, tod in ipairs(TOD) do
      out[tod] = EncounterEdit.cloneSlots(slots[tod])
    end
    return out
  end
  -- Flat Gen1-style list → copy into all ToD buckets.
  local flat = EncounterEdit.cloneSlots(slots)
  return { MORN = flat, DAY = EncounterEdit.cloneSlots(flat),
    NITE = EncounterEdit.cloneSlots(flat) }
end

function EncounterEdit.cloneEncounters(enc)
  if type(enc) ~= "table" then return nil end
  local out = {}
  for _, kind in ipairs({ "grass", "water" }) do
    local band = enc[kind]
    if type(band) == "table" then
      if band.rates or (band.slots and band.slots.MORN) then
        out[kind] = {
          map = band.map,
          rates = band.rates and {
            MORN = band.rates.MORN, DAY = band.rates.DAY, NITE = band.rates.NITE,
          } or nil,
          rate = band.rate,
          slots = cloneTodSlots(band.slots),
        }
        if kind == "water" then
          out[kind].slots = EncounterEdit.cloneSlots(
            type(band.slots) == "table" and not band.slots.MORN and band.slots
              or (band.slots and band.slots.DAY) or band.slots)
          out[kind].rates = nil
        end
      else
        out[kind] = {
          rate = band.rate or 0,
          slots = EncounterEdit.cloneSlots(band.slots),
        }
      end
    end
  end
  return out
end

function EncounterEdit.resolveEncounters(S, mapId, mapDef)
  if mapDef and mapDef.encounters then return mapDef.encounters, true end
  if Generation.isGen2(S) then
    local root = S.data and (S.data.gen2Encounters or S.data.encounters)
    if type(root) == "table" and (root.grass or root.water) then
      return {
        grass = root.grass and root.grass[mapId],
        water = root.water and root.water[mapId],
      }, false
    end
    return nil, false
  end
  if S.data and S.data.encounters and S.data.encounters[mapId] then
    return S.data.encounters[mapId], false
  end
  return nil, false
end

function EncounterEdit.resolveSuperRod(S, mapId, mapDef)
  if mapDef and mapDef.superRod then return mapDef.superRod, true end
  if S.data and S.data.field and S.data.field.superRod
      and S.data.field.superRod[mapId] then
    return S.data.field.superRod[mapId], false
  end
  return nil, false
end

local function defaultFishing(S)
  local FieldDefaults = require("src.world.FieldDefaults")
  return FieldDefaults.field(S.data, "fishing") or {}
end

function EncounterEdit.resolveOldRod(S)
  State.ensureProjectFields(S.project)
  if S.project.fishing and S.project.fishing.OLD_ROD then
    return S.project.fishing.OLD_ROD, true
  end
  return defaultFishing(S).OLD_ROD, false
end

function EncounterEdit.resolveGoodRod(S)
  State.ensureProjectFields(S.project)
  if S.project.fishing and S.project.fishing.GOOD_ROD then
    return S.project.fishing.GOOD_ROD, true
  end
  return defaultFishing(S).GOOD_ROD, false
end

local function ensureEncounterBand(map, kind)
  map.encounters = map.encounters or {}
  if not map.encounters[kind] then
    map.encounters[kind] = { rate = 0, slots = {} }
  end
  map.encounters[kind].slots = map.encounters[kind].slots or {}
  return map.encounters[kind]
end

local function seedGen2Band(S, map, mapId, kind)
  if map.encounters and type(map.encounters[kind]) == "table" then
    return map.encounters[kind]
  end
  -- Prefer the global Gold grass/water tables even if map.encounters is an
  -- empty owned stub (resolveEncounters would otherwise short-circuit).
  local root = S and S.data and (S.data.gen2Encounters or S.data.encounters)
  local band = type(root) == "table" and root[kind] and root[kind][mapId]
  if type(band) == "table" then
    local cloned = EncounterEdit.cloneEncounters({ [kind] = band })
    return cloned and cloned[kind]
  end
  return nil
end

local function ensureGen2Grass(map, mapId, S)
  map.encounters = map.encounters or {}
  local g = map.encounters.grass
  if type(g) ~= "table" or not g.rates then
    g = seedGen2Band(S, map, mapId, "grass")
    if type(g) ~= "table" or not g.rates then
      g = {
        map = mapId,
        rates = { MORN = 25, DAY = 25, NITE = 25 },
        slots = {
          MORN = { { level = 3, species = "PIDGEY" } },
          DAY = { { level = 3, species = "PIDGEY" } },
          NITE = { { level = 3, species = "HOOTHOOT" } },
        },
      }
    end
    map.encounters.grass = g
  end
  g.slots = cloneTodSlots(g.slots)
  g.rates = g.rates or { MORN = 25, DAY = 25, NITE = 25 }
  return g
end

local function ensureGen2Water(map, mapId, S)
  map.encounters = map.encounters or {}
  local w = map.encounters.water
  local needs = type(w) ~= "table" or type(w.slots) ~= "table"
    or (type(w.slots) == "table" and w.slots.MORN ~= nil)
  if needs then
    w = seedGen2Band(S, map, mapId, "water")
    local flatOk = type(w) == "table" and type(w.slots) == "table"
      and w.slots.MORN == nil
    if not flatOk then
      w = {
        map = mapId,
        rate = 5,
        slots = { { level = 5, species = "TENTACOOL" } },
      }
    end
    map.encounters.water = w
  end
  w.slots = w.slots or {}
  return w
end

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function readForm(App, id, x, y, w, h, current)
  local v = field(App, id, x, y, w, h, current or "", "FORM")
  v = v:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]", "")
  if v == "" or v == "FORM" then return nil end
  return v
end

local function drawSlotRows(S, App, px, py, propW, listBottom, fh, s,
    kindKey, slots, onChange, onDelete, maxSlots)
  Kit.text("micro", "Slots (level, species, form)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  for si = 1, #(slots or {}) do
    if py + fh > listBottom - 36 * s then break end
    local slot = slots[si]
    local lx = px + 10 * s
    local lvl = tonumber(field(App, "enc_lv_" .. kindKey .. si, lx, py, 40 * s, fh,
      tostring(slot.level or 1), "1")) or 1
    local formW = 56 * s
    local spW = math.max(70 * s, propW - (lx - px) - 48 * s - formW - 42 * s - 12 * s)
    local sp = slot.species or "PIDGEY"
    SpeciesPicker.field(S, {
      x = lx + 48 * s, y = py, w = spW, h = fh,
      current = sp,
      title = "ENCOUNTER SPECIES",
      onPick = function(id)
        onChange(si, {
          level = math.max(1, slot.level or 1), species = id, form = slot.form,
        })
      end,
    })
    local formVal = readForm(App, "enc_fm_" .. kindKey .. si,
      lx + 48 * s + spW + 4 * s, py, formW, fh, slot.form)
    if lvl ~= (slot.level or 1) or formVal ~= (slot.form or nil) then
      onChange(si, { level = math.max(1, lvl), species = sp, form = formVal })
    end
    if Kit.button(px + propW - 42 * s, py, 28 * s, fh, "X", { kind = "danger" }) then
      onDelete(si)
      break
    end
    py = py + math.max(fh, 26 * s) + 4 * s
  end
  if #(slots or {}) < (maxSlots or 10) and py + 30 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Slot", { kind = "accent" }) then
      onChange(#(slots or {}) + 1, { level = 5, species = "MAGIKARP" }, true)
    end
    py = py + 32 * s
  end
  return py
end

-- Gold `species = 0` is TimeFishGroups: the level byte is the group index,
-- and day vs nite pick the real mon. pret/pokegold data/wild/fish.asm.
local GOLD_TIME_FISH = {
  [0] = { day = "CORSOLA", dayLevel = 20, nite = "STARYU", niteLevel = 20 },
  [1] = { day = "CORSOLA", dayLevel = 40, nite = "STARYU", niteLevel = 40 },
  [2] = { day = "SHELLDER", dayLevel = 20, nite = "SHELLDER", niteLevel = 20 },
  [3] = { day = "SHELLDER", dayLevel = 40, nite = "SHELLDER", niteLevel = 40 },
  [4] = { day = "GOLDEEN", dayLevel = 20, nite = "GOLDEEN", niteLevel = 20 },
  [5] = { day = "GOLDEEN", dayLevel = 40, nite = "GOLDEEN", niteLevel = 40 },
  [6] = { day = "POLIWAG", dayLevel = 20, nite = "POLIWAG", niteLevel = 20 },
  [7] = { day = "POLIWAG", dayLevel = 40, nite = "POLIWAG", niteLevel = 40 },
  [8] = { day = "DRATINI", dayLevel = 20, nite = "DRATINI", niteLevel = 20 },
  [9] = { day = "DRATINI", dayLevel = 40, nite = "DRATINI", niteLevel = 40 },
  [10] = { day = "QWILFISH", dayLevel = 20, nite = "QWILFISH", niteLevel = 20 },
  [11] = { day = "QWILFISH", dayLevel = 40, nite = "QWILFISH", niteLevel = 40 },
  [12] = { day = "REMORAID", dayLevel = 20, nite = "REMORAID", niteLevel = 20 },
  [13] = { day = "REMORAID", dayLevel = 40, nite = "REMORAID", niteLevel = 40 },
  [14] = { day = "GYARADOS", dayLevel = 20, nite = "GYARADOS", niteLevel = 20 },
  [15] = { day = "GYARADOS", dayLevel = 40, nite = "GYARADOS", niteLevel = 40 },
  [16] = { day = "DRATINI", dayLevel = 10, nite = "DRATINI", niteLevel = 10 },
  [17] = { day = "DRATINI", dayLevel = 10, nite = "DRATINI", niteLevel = 10 },
  [18] = { day = "HORSEA", dayLevel = 20, nite = "HORSEA", niteLevel = 20 },
  [19] = { day = "HORSEA", dayLevel = 40, nite = "HORSEA", niteLevel = 40 },
  [20] = { day = "TENTACOOL", dayLevel = 20, nite = "TENTACOOL", niteLevel = 20 },
  [21] = { day = "TENTACOOL", dayLevel = 40, nite = "TENTACOOL", niteLevel = 40 },
}

local function isTimeFishSlot(slot)
  local sp = slot and slot.species
  return sp == 0 or sp == "0"
end

local function timeFishGroup(S, index)
  index = tonumber(index) or 0
  local root = S and S.data and (S.data.gen2Encounters or S.data.encounters)
  local groups = root and (root.timeFishGroups or root.fishTimeGroups)
  if type(groups) == "table" then
    local row = groups[index]
    if type(row) ~= "table" then row = groups[index + 1] end
    if type(row) == "table" then
      return {
        day = row.day or row.daySpecies or row.species or row[1],
        dayLevel = row.dayLevel or row.level or row[2],
        nite = row.nite or row.niteSpecies or row[3] or row.day or row[1],
        niteLevel = row.niteLevel or row[4] or row.dayLevel or row[2],
      }
    end
  end
  return GOLD_TIME_FISH[index]
end

-- Fishing / headbutt-tree slots carry a chance (0-255) alongside level+species.
local function drawChanceSlotRows(S, App, px, py, propW, listBottom, fh, s,
    kindKey, slots, onChange, onDelete, maxSlots)
  Kit.text("micro", "Slots (chance, level, species, form)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  for si = 1, #(slots or {}) do
    if py + fh > listBottom - 36 * s then break end
    local slot = slots[si]
    local lx = px + 10 * s
    local timeSlot = isTimeFishSlot(slot)
    local tg = timeSlot and timeFishGroup(S, slot.level)
    local shownLevel = (tg and (tg.dayLevel or tg.niteLevel)) or (slot.level or 1)
    local shownSpecies = slot.species or "MAGIKARP"
    local shownLabel = nil
    if tg then
      shownSpecies = tg.day or shownSpecies
      if tg.nite and tg.nite ~= tg.day then
        shownLabel = tostring(tg.day) .. "/" .. tostring(tg.nite)
      else
        shownLabel = tostring(tg.day or "TIME")
      end
    elseif timeSlot then
      shownSpecies = nil
      shownLabel = "TIME " .. tostring(slot.level or 0)
    end
    local chance = tonumber(field(App, "enc_ch_" .. kindKey .. si, lx, py, 44 * s, fh,
      tostring(slot.chance or 0), "0")) or 0
    local lvl = tonumber(field(App, "enc_cl_" .. kindKey .. si, lx + 48 * s, py, 40 * s, fh,
      tostring(shownLevel), "1")) or 1
    local formW = 56 * s
    local spW = math.max(64 * s, propW - (lx - px) - 96 * s - formW - 42 * s - 12 * s)
    SpeciesPicker.field(S, {
      x = lx + 92 * s, y = py, w = spW, h = fh,
      current = shownSpecies,
      label = shownLabel,
      title = "ENCOUNTER SPECIES",
      tooltip = tg and "Gold time-of-day fish (day / nite). Pick a species to make it a fixed slot."
        or nil,
      onPick = function(id)
        onChange(si, {
          chance = math.max(0, math.min(255, slot.chance or 0)),
          level = math.max(1, shownLevel or 1), species = id, form = slot.form,
        })
      end,
    })
    local formVal = readForm(App, "enc_cfm_" .. kindKey .. si,
      lx + 92 * s + spW + 4 * s, py, formW, fh, slot.form)
    if chance ~= (slot.chance or 0) or lvl ~= shownLevel
        or formVal ~= (slot.form or nil) then
      if timeSlot and lvl == shownLevel then
        onChange(si, {
          chance = math.max(0, math.min(255, chance)),
          level = slot.level, species = 0, form = formVal,
        })
      else
        onChange(si, {
          chance = math.max(0, math.min(255, chance)),
          level = math.max(1, lvl),
          species = (tg and tg.day) or slot.species or "MAGIKARP",
          form = formVal,
        })
      end
    end
    if Kit.button(px + propW - 42 * s, py, 28 * s, fh, "X", { kind = "danger" }) then
      onDelete(si)
      break
    end
    py = py + math.max(fh, 26 * s) + 4 * s
  end
  if #(slots or {}) < (maxSlots or 10) and py + 30 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Slot", { kind = "accent" }) then
      onChange(#(slots or {}) + 1, { chance = 0, level = 5, species = "MAGIKARP" }, true)
    end
    py = py + 32 * s
  end
  return py
end

local FISH_RODS = { "old", "good", "super" }

-- Clone project.fishGroups[group] from data.gen2Encounters/encounters on
-- first edit so authored slots start from the vanilla table.
local function ensureFishGroup(S, group)
  S.project.fishGroups = S.project.fishGroups or {}
  if S.project.fishGroups[group] then return S.project.fishGroups[group] end
  local root = S.data and (S.data.gen2Encounters or S.data.encounters)
  local base = type(root) == "table" and root.fishGroups and root.fishGroups[group]
  local cloned = { old = {}, good = {}, super = {} }
  if type(base) == "table" then
    for _, rod in ipairs(FISH_RODS) do
      local rows = base[rod]
      if type(rows) == "table" then
        for i, row in ipairs(rows) do
          cloned[rod][i] = copySlot(row)
        end
      end
    end
  end
  S.project.fishGroups[group] = cloned
  return cloned
end

-- Clone project.treeSets[setId] from data.gen2Encounters/encounters on
-- first edit (shared by headbutt trees and Rock Smash rocks).
local function ensureTreeSet(S, setId)
  S.project.treeSets = S.project.treeSets or {}
  if S.project.treeSets[setId] then return S.project.treeSets[setId] end
  local root = S.data and (S.data.gen2Encounters or S.data.encounters)
  local base = type(root) == "table" and root.treeSets and root.treeSets[setId]
  local cloned = { common = {}, rare = {} }
  if type(base) == "table" then
    for _, listName in ipairs({ "common", "rare" }) do
      local rows = base[listName]
      if type(rows) == "table" then
        for i, row in ipairs(rows) do
          cloned[listName][i] = copySlot(row)
        end
      end
    end
  end
  S.project.treeSets[setId] = cloned
  return cloned
end

local function collectTreeSetIds(S, root)
  local seen, ids = {}, {}
  if type(root) == "table" and type(root.treeSets) == "table" then
    for id in pairs(root.treeSets) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  for id in pairs(S.project.treeSets or {}) do
    if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

-- Advance to the next known set id; starts at the first id when cur is
-- unset or unrecognized (e.g. "(none)").
local function cycleSetId(list, cur)
  if not list or #list == 0 then return cur end
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  local n = idx + 1
  if n > #list then n = 1 end
  return list[n]
end

local function isKindKnown(list, id)
  for _, k in ipairs(list) do
    if k.id == id then return true end
  end
  return false
end

local function drawGen2Wild(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  local mapId = map.id or S.mapId
  local enc = EncounterEdit.resolveEncounters(S, mapId, map)
  S.mapEncKind = isKindKnown(EncounterEdit.KINDS_GEN2, S.mapEncKind)
    and S.mapEncKind or "grass"
  S.mapEncTod = S.mapEncTod or "DAY"
  local sx, sy = px + 10 * s, py
  for _, kind in ipairs(EncounterEdit.KINDS_GEN2) do
    local on = S.mapEncKind == kind.id
    local bw = Kit.textWidth("micro", kind.label) + 14 * s
    if Kit.chip(sx, sy, bw, fh, kind.label, on, PAL.green) then
      S.mapEncKind = kind.id
    end
    sx = sx + bw + 4 * s
  end
  py = sy + fh + 8 * s

  local kind = S.mapEncKind
  if kind == "grass" then
    local band = enc and enc.grass
    if not band then
      Kit.text("micro", "No grass encounters (ToD) on this map.",
        px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add grass",
          { kind = "good" }) then
        map = mutate()
        ensureGen2Grass(map, mapId, S)
        App.markDirty()
      end
      return py + 36 * s
    end
    Kit.text("micro", "Rates MORN / DAY / NITE", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local rates = band.rates or {}
    local rx = px + 10 * s
    for _, tod in ipairs(TOD) do
      local cur = rates[tod] or 0
      local v = tonumber(field(App, "enc_g2r_" .. tod, rx, py, 50 * s, fh,
        tostring(cur), "0")) or 0
      if v ~= cur then
        map = mutate()
        local g = ensureGen2Grass(map, mapId, S)
        g.rates = g.rates or {}
        g.rates[tod] = math.max(0, math.min(255, v))
      end
      Kit.text("micro", tod, rx, py + fh + 2 * s, PAL.faint)
      rx = rx + 58 * s
    end
    py = py + fh + 18 * s
    sx = px + 10 * s
    for _, tod in ipairs(TOD) do
      local on = S.mapEncTod == tod
      local bw = Kit.textWidth("micro", tod) + 14 * s
      if Kit.chip(sx, py, bw, fh, tod, on, PAL.blue) then
        S.mapEncTod = tod
      end
      sx = sx + bw + 4 * s
    end
    py = py + fh + 8 * s
    local tod = S.mapEncTod
    local slots = (band.slots and band.slots[tod]) or {}
    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s,
      "g2g_" .. tod, slots,
      function(si, slot, isAdd)
        map = mutate()
        local g = ensureGen2Grass(map, mapId, S)
        g.slots[tod] = g.slots[tod] or {}
        if isAdd then g.slots[tod][#g.slots[tod] + 1] = slot
        else g.slots[tod][si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        local g = ensureGen2Grass(map, mapId, S)
        table.remove(g.slots[tod], si)
        App.markDirty()
      end, 7)
    if py + 36 * s <= listBottom then
      if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear grass",
          { kind = "ghost" }) then
        map = mutate()
        if map.encounters then map.encounters.grass = nil end
        App.markDirty()
      end
      py = py + 36 * s
    end
    return py
  end

  if kind == "fish" then
    local group = map.fishGroup
    Kit.text("micro", "Map fish group: " .. tostring(group or "FISHGROUP_NONE")
      .. " (edit on the Group / Map header row above)", px + 10 * s, py, PAL.muted)
    py = py + 20 * s
    if not group or group == "" or group == "FISHGROUP_NONE" then
      Kit.text("micro", "No fish group set on this map.", px + 10 * s, py, PAL.faint)
      return py + 20 * s
    end
    S.mapEncRod = (S.mapEncRod == "old" or S.mapEncRod == "good" or S.mapEncRod == "super")
      and S.mapEncRod or "old"
    sx = px + 10 * s
    for _, rod in ipairs(FISH_RODS) do
      local on = S.mapEncRod == rod
      local label = rod:upper()
      local bw = Kit.textWidth("micro", label) + 14 * s
      if Kit.chip(sx, py, bw, fh, label, on, PAL.blue) then
        S.mapEncRod = rod
      end
      sx = sx + bw + 4 * s
    end
    py = py + fh + 8 * s
    local fg = ensureFishGroup(S, group)
    local rod = S.mapEncRod
    return drawChanceSlotRows(S, App, px, py, propW, listBottom, fh, s,
      "fish_" .. group .. "_" .. rod, fg[rod],
      function(si, slot, isAdd)
        fg[rod] = fg[rod] or {}
        if isAdd then fg[rod][#fg[rod] + 1] = slot else fg[rod][si] = slot end
        App.markDirty()
      end,
      function(si)
        table.remove(fg[rod], si)
        App.markDirty()
      end, 10)
  end

  if kind == "tree" then
    S.project.trees = S.project.trees or {}
    S.project.rocks = S.project.rocks or {}
    local root = S.data and (S.data.gen2Encounters or S.data.encounters)
    local setIds = collectTreeSetIds(S, root)

    Kit.text("micro", "Tree set (headbutt)", px + 10 * s, py, PAL.caption)
    py = py + 16 * s
    local curTree = S.project.trees[mapId]
      or (type(root) == "table" and root.trees and root.trees[mapId])
    if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s,
        Kit.ellipsize("small", tostring(curTree or "(none)"), propW - 30 * s),
        { kind = "ghost", tooltip = "Cycle headbutt tree set for this map" }) then
      S.project.trees[mapId] = cycleSetId(setIds, curTree)
      App.markDirty()
    end
    py = py + 32 * s

    Kit.text("micro", "Rock set (Rock Smash, optional)", px + 10 * s, py, PAL.caption)
    py = py + 16 * s
    local curRock = S.project.rocks[mapId]
      or (type(root) == "table" and root.rocks and root.rocks[mapId])
    if Kit.button(px + 10 * s, py, propW - 92 * s, 28 * s,
        Kit.ellipsize("small", tostring(curRock or "(none)"), propW - 102 * s),
        { kind = "ghost", tooltip = "Cycle Rock Smash set for this map" }) then
      S.project.rocks[mapId] = cycleSetId(setIds, curRock)
      App.markDirty()
    end
    if S.project.rocks[mapId] and Kit.button(px + propW - 78 * s, py, 68 * s, 28 * s,
        "Clear", { kind = "danger" }) then
      S.project.rocks[mapId] = nil
      App.markDirty()
    end
    py = py + 32 * s

    local setId = S.project.trees[mapId]
      or (type(root) == "table" and root.trees and root.trees[mapId])
    if not setId then
      Kit.text("micro", "No tree set on this map.", px + 10 * s, py, PAL.faint)
      return py + 20 * s
    end
    local ts = ensureTreeSet(S, setId)
    S.mapEncTreeList = (S.mapEncTreeList == "common" or S.mapEncTreeList == "rare")
      and S.mapEncTreeList or "common"
    sx = px + 10 * s
    for _, listName in ipairs({ "common", "rare" }) do
      local on = S.mapEncTreeList == listName
      local label = listName:upper()
      local bw = Kit.textWidth("micro", label) + 14 * s
      if Kit.chip(sx, py, bw, fh, label, on, PAL.blue) then
        S.mapEncTreeList = listName
      end
      sx = sx + bw + 4 * s
    end
    py = py + fh + 8 * s
    local listName = S.mapEncTreeList
    return drawChanceSlotRows(S, App, px, py, propW, listBottom, fh, s,
      "tree_" .. setId .. "_" .. listName, ts[listName],
      function(si, slot, isAdd)
        ts[listName] = ts[listName] or {}
        if isAdd then ts[listName][#ts[listName] + 1] = slot else ts[listName][si] = slot end
        App.markDirty()
      end,
      function(si)
        table.remove(ts[listName], si)
        App.markDirty()
      end, 10)
  end

  -- water
  local band = enc and enc.water
  if not band then
    Kit.text("micro", "No water encounters on this map.",
      px + 10 * s, py, PAL.faint)
    py = py + 18 * s
    if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add water",
        { kind = "good" }) then
      map = mutate()
      ensureGen2Water(map, mapId, S)
      App.markDirty()
    end
    return py + 36 * s
  end
  Kit.text("micro", "Rate (0-255)", px + 10 * s, py, PAL.caption)
  py = py + 14 * s
  local rate = tonumber(field(App, "enc_g2w_rate", px + 10 * s, py, 70 * s, fh,
    tostring(band.rate or 0), "0")) or 0
  if rate ~= (band.rate or 0) then
    map = mutate()
    ensureGen2Water(map, mapId, S).rate = math.max(0, math.min(255, rate))
  end
  py = py + fh + 8 * s
  py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "g2w", band.slots,
    function(si, slot, isAdd)
      map = mutate()
      local w = ensureGen2Water(map, mapId, S)
      if isAdd then w.slots[#w.slots + 1] = slot else w.slots[si] = slot end
      App.markDirty()
    end,
    function(si)
      map = mutate()
      table.remove(ensureGen2Water(map, mapId, S).slots, si)
      App.markDirty()
    end, 3)
  if py + 36 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear water",
        { kind = "ghost" }) then
      map = mutate()
      if map.encounters then map.encounters.water = nil end
      App.markDirty()
    end
    py = py + 36 * s
  end
  return py
end

-- Draw wild encounter editor for a map. mutate() must return an owned map def.
function EncounterEdit.drawWild(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  if not map then
    Kit.text("micro", "Select a map.", px + 10 * s, py, PAL.faint)
    return py + 20 * s
  end
  State.ensureProjectFields(S.project)
  if Generation.isGen2(S) then
    return drawGen2Wild(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  end
  local mapId = map.id or S.mapId
  local enc = EncounterEdit.resolveEncounters(S, mapId, map)
  local superSlots = EncounterEdit.resolveSuperRod(S, mapId, map)

  S.mapEncKind = S.mapEncKind or "grass"
  local sx, sy = px + 10 * s, py
  for _, kind in ipairs(EncounterEdit.KINDS) do
    local on = S.mapEncKind == kind.id
    local bw = Kit.textWidth("micro", kind.label) + 14 * s
    if sx + bw > px + propW - 10 * s then
      sx = px + 10 * s
      sy = sy + fh + 4 * s
    end
    if Kit.chip(sx, sy, bw, fh, kind.label, on, PAL.green) then
      S.mapEncKind = kind.id
    end
    sx = sx + bw + 4 * s
  end
  py = sy + fh + 10 * s

  local kind = S.mapEncKind

  if kind == "grass" or kind == "water" then
    local band = enc and enc[kind]
    if not band then
      Kit.text("micro", "No " .. kind .. " encounters on this map.",
        px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add " .. kind,
          { kind = "good" }) then
        map = mutate()
        local b = ensureEncounterBand(map, kind)
        b.rate = kind == "grass" and 25 or 5
        b.slots = {
          { level = kind == "grass" and 3 or 5,
            species = kind == "grass" and "PIDGEY" or "TENTACOOL" },
        }
        App.markDirty()
      end
      return py + 36 * s
    end

    Kit.text("micro", "Rate (0-255)", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local rate = tonumber(field(App, "enc_rate_" .. kind, px + 10 * s, py, 70 * s, fh,
      tostring(band.rate or 0), "0")) or 0
    if rate ~= (band.rate or 0) then
      map = mutate()
      ensureEncounterBand(map, kind).rate = math.max(0, math.min(255, rate))
    end
    py = py + fh + 8 * s

    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, kind, band.slots,
      function(si, slot, isAdd)
        map = mutate()
        local b = ensureEncounterBand(map, kind)
        if isAdd then b.slots[#b.slots + 1] = slot
        else b.slots[si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        table.remove(ensureEncounterBand(map, kind).slots, si)
        App.markDirty()
      end, 10)

    if py + 36 * s <= listBottom then
      if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear " .. kind,
          { kind = "ghost" }) then
        map = mutate()
        if map.encounters then map.encounters[kind] = nil end
        App.markDirty()
      end
      py = py + 36 * s
    end
    return py

  elseif kind == "super" then
    Kit.text("micro", "Super Rod group for this map (field.superRod).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    if not superSlots then
      Kit.text("micro", "No Super Rod table here.", px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add Super Rod",
          { kind = "good" }) then
        map = mutate()
        map.superRod = { { level = 15, species = "POLIWAG" } }
        App.markDirty()
      end
      return py + 36 * s
    end
    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "super", superSlots,
      function(si, slot, isAdd)
        map = mutate()
        map.superRod = map.superRod or EncounterEdit.cloneSlots(superSlots)
        if isAdd then map.superRod[#map.superRod + 1] = slot
        else map.superRod[si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        map.superRod = map.superRod or EncounterEdit.cloneSlots(superSlots)
        table.remove(map.superRod, si)
        App.markDirty()
      end, 10)
    if py + 36 * s <= listBottom then
      if Kit.button(px + 10 * s, py, 110 * s, 28 * s, "Clear Super",
          { kind = "ghost" }) then
        map = mutate()
        map.superRod = {}
        App.markDirty()
      end
      py = py + 36 * s
    end
    return py

  elseif kind == "old" then
    Kit.text("micro", "Old Rod (global -- always hooks this mon).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    local def = select(1, EncounterEdit.resolveOldRod(S))
      or { always = { species = "MAGIKARP", level = 5 } }
    local always = def.always or { species = "MAGIKARP", level = 5 }
    Kit.text("micro", "Level", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local lvl = tonumber(field(App, "enc_old_lv", px + 10 * s, py, 50 * s, fh,
      tostring(always.level or 5), "5")) or 5
    local sp = always.species or "MAGIKARP"
    local formW = 56 * s
    SpeciesPicker.field(S, {
      x = px + 70 * s, y = py, w = math.max(80 * s, propW - 90 * s - formW), h = fh,
      current = sp,
      title = "OLD ROD SPECIES",
      onPick = function(id)
        S.project.fishing.OLD_ROD = {
          always = {
            level = math.max(1, always.level or 5), species = id, form = always.form,
          },
        }
        App.markDirty()
      end,
    })
    local formVal = readForm(App, "enc_old_fm",
      px + propW - formW - 8 * s, py, formW, fh, always.form)
    if lvl ~= (always.level or 5) or formVal ~= (always.form or nil) then
      S.project.fishing.OLD_ROD = {
        always = { level = math.max(1, lvl), species = sp, form = formVal },
      }
      App.markDirty()
    end
    py = py + fh + 10 * s
    if S.project.fishing.OLD_ROD
        and Kit.button(px + 10 * s, py, 120 * s, 28 * s, "Revert Old",
          { kind = "danger" }) then
      S.project.fishing.OLD_ROD = nil
      App.markDirty()
    end
    return py + 36 * s
  end

  -- good
  Kit.text("micro", "Good Rod (global pool -- ~1/3 bite).",
    px + 10 * s, py, PAL.muted)
  py = py + 18 * s
  local def = select(1, EncounterEdit.resolveGoodRod(S)) or {
    pool = {
      { species = "GOLDEEN", level = 10 },
      { species = "POLIWAG", level = 10 },
    },
  }
  local pool = def.pool or {}
  py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "good", pool,
    function(si, slot, isAdd)
      local cur = EncounterEdit.resolveGoodRod(S)
      local base = (cur and cur.pool)
        and EncounterEdit.cloneSlots(cur.pool)
        or EncounterEdit.cloneSlots(pool)
      if isAdd then base[#base + 1] = slot else base[si] = slot end
      S.project.fishing.GOOD_ROD = { pool = base }
      App.markDirty()
    end,
    function(si)
      local cur = EncounterEdit.resolveGoodRod(S)
      local base = (cur and cur.pool)
        and EncounterEdit.cloneSlots(cur.pool)
        or EncounterEdit.cloneSlots(pool)
      table.remove(base, si)
      S.project.fishing.GOOD_ROD = { pool = base }
      App.markDirty()
    end, 8)
  if S.project.fishing.GOOD_ROD and py + 36 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 120 * s, 28 * s, "Revert Good",
        { kind = "danger" }) then
      S.project.fishing.GOOD_ROD = nil
      App.markDirty()
    end
    py = py + 36 * s
  end
  return py
end

return EncounterEdit
