-- Shops tab: Gen1 text_pointers.mart inventories; Gold MART_* shelves + bargain.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local ItemPicker = require("ItemPicker")
local Generation = require("Generation")
local PAL = Theme.PAL

local Shops = {}

local DEFAULT_MART = {
  "POKE_BALL", "POTION", "ANTIDOTE", "PARLYZ_HEAL",
  "BURN_HEAL", "ICE_HEAL", "AWAKENING", "REPEL",
}

-- constants/mart_constants.asm order (lists[i] == MART_* index i-1).
local MART_ORDER = {
  "MART_CHERRYGROVE", "MART_CHERRYGROVE_DEX", "MART_VIOLET", "MART_AZALEA",
  "MART_CIANWOOD", "MART_GOLDENROD_2F_1", "MART_GOLDENROD_2F_2",
  "MART_GOLDENROD_3F", "MART_GOLDENROD_4F", "MART_GOLDENROD_5F_1",
  "MART_GOLDENROD_5F_2", "MART_GOLDENROD_5F_3", "MART_GOLDENROD_5F_4",
  "MART_OLIVINE", "MART_ECRUTEAK", "MART_MAHOGANY_1", "MART_MAHOGANY_2",
  "MART_BLACKTHORN", "MART_VIRIDIAN", "MART_PEWTER", "MART_CERULEAN",
  "MART_LAVENDER", "MART_VERMILION", "MART_CELADON_2F_1", "MART_CELADON_2F_2",
  "MART_CELADON_3F", "MART_CELADON_4F", "MART_CELADON_5F_1", "MART_CELADON_5F_2",
  "MART_FUCHSIA", "MART_SAFFRON", "MART_MT_MOON", "MART_INDIGO_PLATEAU",
  "MART_UNDERGROUND",
}

local function allItemIds(S)
  local seen, ids = {}, {}
  for id in pairs((S.project and S.project.items) or {}) do
    seen[id] = true
    ids[#ids + 1] = id
  end
  if S.data and S.data.items then
    for id in pairs(S.data.items) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function cloneEntry(src)
  local e = {}
  if not src then return e end
  for k, v in pairs(src) do
    if k == "mart" and type(v) == "table" then
      local m = {}
      for i, id in ipairs(v) do m[i] = id end
      e.mart = m
    else
      e[k] = v
    end
  end
  return e
end

local function cloneItemList(list)
  local m = {}
  if type(list) ~= "table" then return m end
  for i, id in ipairs(list) do m[i] = id end
  return m
end

local function cloneBargain(list)
  local m = {}
  if type(list) ~= "table" then return m end
  for i, row in ipairs(list) do
    if type(row) == "table" then
      m[i] = { item = row.item, price = tonumber(row.price) or 0 }
    end
  end
  return m
end

local function dataMarts(S)
  return (S.data and (S.data.marts or S.data.gen2Marts)) or {}
end

-- Count pokemart script refs per mart id (0-based).
local function martUsage(S)
  local usage = {}
  local scripts = S.data and S.data.scripts
  if type(scripts) ~= "table" then return usage end
  for _, cmds in pairs(scripts) do
    if type(cmds) == "table" then
      for _, cmd in ipairs(cmds) do
        if type(cmd) == "table" and cmd.op == "pokemart" then
          local martId = cmd.mart or cmd.martId
          local args = cmd.args
          if not martId and type(args) == "table" then
            martId = (args[2] or 0) + (args[3] or 0) * 0x100
          end
          if type(martId) == "number" then
            usage[martId] = (usage[martId] or 0) + 1
          end
        end
      end
    end
  end
  return usage
end

local function collectGen2Shops(S)
  local keys, byKey = {}, {}
  local marts = dataMarts(S)
  local lists = marts.lists or {}
  local proj = S.project and S.project.marts or {}
  local usage = martUsage(S)

  for i, name in ipairs(MART_ORDER) do
    local owned = type(proj[name]) == "table"
    local stock = owned and proj[name] or lists[i] or {}
    keys[#keys + 1] = name
    byKey[name] = {
      key = name,
      label = name,
      textId = name,
      martId = i - 1,
      mart = stock,
      owned = owned,
      kind = "list",
      uses = usage[i - 1] or 0,
    }
  end

  local bargainOwned = type(proj.BARGAIN) == "table"
  local bargain = bargainOwned and proj.BARGAIN or marts.bargain or {}
  keys[#keys + 1] = "BARGAIN"
  byKey.BARGAIN = {
    key = "BARGAIN",
    label = "BARGAIN",
    textId = "BARGAIN",
    martId = nil,
    mart = bargain,
    owned = bargainOwned,
    kind = "bargain",
    uses = 0,
  }

  return keys, byKey
end

-- Collect shops from project + vanilla text_pointers (entries with .mart).
local function collectGen1Shops(S)
  local byKey, keys = {}, {}
  local function consider(label, textId, entry, owned)
    if type(entry) ~= "table" or type(entry.mart) ~= "table" then return end
    local key = label .. "/" .. textId
    if byKey[key] and byKey[key].owned then return end
    if not byKey[key] then keys[#keys + 1] = key end
    byKey[key] = {
      key = key,
      label = label,
      textId = textId,
      mart = entry.mart,
      owned = owned and true or false,
      entry = entry,
      kind = "pointer",
    }
  end

  local dataPtrs = S.data and S.data.text_pointers or {}
  for label, bucket in pairs(dataPtrs) do
    if type(bucket) == "table" then
      for textId, entry in pairs(bucket) do
        if type(textId) == "string" then
          consider(label, textId, entry, false)
        end
      end
    end
  end

  local projPtrs = S.project and S.project.text_pointers or {}
  for label, bucket in pairs(projPtrs) do
    if type(bucket) == "table" then
      for textId, entry in pairs(bucket) do
        if type(textId) == "string" then
          consider(label, textId, entry, true)
        end
      end
    end
  end

  table.sort(keys)
  return keys, byKey
end

local function collectShops(S)
  if Generation.isGen2(S) then return collectGen2Shops(S) end
  return collectGen1Shops(S)
end

local function ensureGen1Shop(S, label, textId, App)
  State.ensureProjectFields(S.project)
  S.project.text_pointers[label] = S.project.text_pointers[label] or {}
  local bucket = S.project.text_pointers[label]
  if not bucket[textId] then
    local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
    bucket[textId] = cloneEntry(base and base[textId])
  end
  local e = bucket[textId]
  if type(e.mart) ~= "table" then
    e.mart = {}
    for i, id in ipairs(DEFAULT_MART) do e.mart[i] = id end
    e.nurse, e.pc, e.cableClub = nil, nil, nil
  end
  if App then App.markDirty() end
  return e
end

local function ensureGen2Shop(S, key, App)
  State.ensureProjectFields(S.project)
  S.project.marts = S.project.marts or {}
  if type(S.project.marts[key]) ~= "table" then
    local marts = dataMarts(S)
    if key == "BARGAIN" then
      S.project.marts[key] = cloneBargain(marts.bargain)
    else
      local idx = nil
      for i, name in ipairs(MART_ORDER) do
        if name == key then idx = i; break end
      end
      local src = idx and marts.lists and marts.lists[idx]
      S.project.marts[key] = cloneItemList(src)
      if #(S.project.marts[key]) == 0 then
        for i, id in ipairs(DEFAULT_MART) do
          S.project.marts[key][i] = id
        end
      end
    end
  end
  if App then App.markDirty() end
  return S.project.marts[key]
end

local function drawGen2Form(S, App, formX, listY, formW, listH, key, rec, items)
  local s = Kit.scale
  local fh = 28 * s
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "shopsFormScroll", key, rec.owned and 44 * s or 12 * s)
  local contentTop = fy

  local idLine = rec.key
  if rec.martId ~= nil then
    idLine = string.format("%s  ·  id %d", rec.key, rec.martId)
  end
  Kit.text("micro", idLine, viewX, fy, PAL.muted)
  fy = fy + 18 * s
  if rec.kind == "bargain" then
    Kit.text("micro",
      string.format("%d row(s)  |  Save: marts:override BARGAIN", #(rec.mart or {})),
      viewX, fy, PAL.detail)
  else
    Kit.text("micro",
      string.format("%d item(s)  |  %d script ref(s)  |  Save: marts:override",
        #(rec.mart or {}), rec.uses or 0),
      viewX, fy, PAL.detail)
  end
  fy = fy + 22 * s

  if not rec.owned then
    Kit.text("micro", "Edit clones this shelf into the mod.", viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensureGen2Shop(S, key, App)
    end
    fy = fy + fh + 12 * s
  end

  local mart = rec.mart or {}
  Kit.text("micro", rec.kind == "bargain" and "Bargain stock" or "Stock",
    viewX, fy, PAL.caption)
  fy = fy + 18 * s

  if rec.kind == "bargain" then
    for mi, row in ipairs(mart) do
      local slot = mi
      ItemPicker.field(S, {
        x = viewX, y = fy, w = viewW - 120 * s, h = fh,
        current = (row and row.item) or "NUGGET",
        title = "BARGAIN ITEM",
        onPick = function(id)
          local e = ensureGen2Shop(S, key, App)
          e[slot] = e[slot] or {}
          e[slot].item = id
          e[slot].price = tonumber(e[slot].price) or 0
          App.markDirty()
        end,
      })
      local price = tonumber(row and row.price) or 0
      local shown = RegList.field(App, "shop_bprice_" .. slot,
        viewX + viewW - 112 * s, fy, 68 * s, fh, tostring(price), "0")
      local n = tonumber(shown)
      if n and n ~= price then
        local e = ensureGen2Shop(S, key, App)
        e[slot] = e[slot] or {}
        e[slot].price = math.max(0, math.floor(n))
        App.markDirty()
      end
      if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
          { kind = "danger", font = "small" }) then
        local e = ensureGen2Shop(S, key, App)
        table.remove(e, slot)
        App.markDirty()
        break
      end
      fy = fy + fh + 6 * s
    end
    if Kit.button(viewX, fy, 140 * s, fh, "+ Add row", { kind = "good" }) then
      ensureGen2Shop(S, key, App)
      ItemPicker.open(S, {
        current = (#items > 0 and items[1]) or "NUGGET",
        title = "ADD BARGAIN ITEM",
        onPick = function(id)
          local e = ensureGen2Shop(S, key, App)
          e[#e + 1] = { item = id, price = 1000 }
          App.markDirty()
        end,
      })
    end
  else
    for mi, itemId in ipairs(mart) do
      local slot = mi
      ItemPicker.field(S, {
        x = viewX, y = fy, w = viewW - 44 * s, h = fh,
        current = itemId or "POKE_BALL",
        title = "SHOP STOCK",
        onPick = function(id)
          local e = ensureGen2Shop(S, key, App)
          e[slot] = id
          App.markDirty()
        end,
      })
      if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
          { kind = "danger", font = "small" }) then
        local e = ensureGen2Shop(S, key, App)
        table.remove(e, slot)
        App.markDirty()
        break
      end
      fy = fy + fh + 6 * s
    end
    if Kit.button(viewX, fy, 120 * s, fh, "+ Add item", { kind = "good" }) then
      ensureGen2Shop(S, key, App)
      ItemPicker.open(S, {
        current = (#items > 0 and items[1]) or "POKE_BALL",
        title = "ADD SHOP ITEM",
        onPick = function(id)
          local e = ensureGen2Shop(S, key, App)
          e[#e + 1] = id
          App.markDirty()
        end,
      })
    end
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "shopsFormScroll", contentTop, fy, view)

  if rec.owned and Kit.button(formX + 12 * s, listY + listH - 40 * s,
      140 * s, 32 * s, "Revert", {
        kind = "danger",
        tooltip = "Drop mod override (vanilla shelf again)",
      }) then
    if S.project.marts then S.project.marts[key] = nil end
    S.shopKey = nil
    App.markDirty()
  end
end

function Shops.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  if Generation.isGen2(S) then
    S.project.marts = S.project.marts or {}
  end

  local keys, byKey = collectShops(S)
  local items = allItemIds(S)
  local gen2 = Generation.isGen2(S)

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "SHOPS", keys, {
      queryKey = "shopsQuery",
      offsetKey = "shopsListOffset",
      selKey = "shopKey",
      accent = PAL.blue,
      isOwned = function(key)
        local rec = byKey[key]
        return rec and rec.owned
      end,
      searchPh = gen2 and "search MART_*..." or "search map / TEXT_*...",
      filter = function(key, q)
        local rec = byKey[key]
        local ql = q:lower()
        if key:lower():find(ql, 1, true) then return true end
        if rec and tostring(rec.textId):lower():find(ql, 1, true) then
          return true
        end
        if rec and type(rec.mart) == "table" then
          for _, id in ipairs(rec.mart) do
            local tip = type(id) == "table" and id.item or id
            if tostring(tip):lower():find(ql, 1, true) then return true end
          end
        end
        return false
      end,
      footerLabel = gen2 and nil or "+ New shop",
      onFooter = gen2 and nil or function()
        S.shopKey = "__new__"
      end,
    })

  if not S.shopKey and shown[1] then S.shopKey = shown[1] end
  local key = S.shopKey
  local fh = 28 * s

  if gen2 then
    if key == "__new__" then S.shopKey = shown[1]; key = S.shopKey end
    local rec = key and byKey[key]
    if not rec then
      Kit.emptyBox(formX, listY, formW, listH,
        #keys == 0
          and "No marts (Import Gold/Silver ROM / Link Recomp cache)"
          or "Select a mart")
      return
    end
    Kit.caption(formX, y, rec.textId .. (rec.owned and "" or "  (vanilla)"))
    drawGen2Form(S, App, formX, listY, formW, listH, key, rec, items)
    return
  end

  -- Create flow (Gen1)
  if key == "__new__" then
    Kit.caption(formX, y, "NEW SHOP")
    Kit.card(formX, listY, formW, listH, 12 * s)
    local viewX = formX + 12 * s
    local fy = listY + 16 * s
    local viewW = formW - 24 * s
    Kit.text("micro",
      "Map label is the text_pointers key (e.g. ViridianMart, PewterCity).",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s
    Kit.text("small", "Map label", viewX, fy + 6 * s, PAL.caption)
    S._shopNewLabel = RegList.field(App, "shop_new_lbl", viewX + 100 * s, fy,
      viewW - 100 * s, fh, S._shopNewLabel or "ViridianMart", "ViridianMart")
    fy = fy + fh + 8 * s
    Kit.text("small", "TEXT_*", viewX, fy + 6 * s, PAL.caption)
    S._shopNewText = RegList.field(App, "shop_new_tid", viewX + 100 * s, fy,
      viewW - 100 * s, fh,
      S._shopNewText or "TEXT_VIRIDIANMART_CLERK", "TEXT_*")
      :upper():gsub("%s+", "_")
    fy = fy + fh + 16 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Create", { kind = "good" }) then
      local label = tostring(S._shopNewLabel or ""):gsub("%s+", "")
      local textId = tostring(S._shopNewText or ""):upper():gsub("%s+", "_")
      if label ~= "" and textId ~= "" then
        ensureGen1Shop(S, label, textId, App)
        S.shopKey = label .. "/" .. textId
        S.status = "Shop " .. S.shopKey
      else
        S.status = "Need map label and TEXT_*"
      end
    end
    if Kit.button(viewX + 150 * s, fy, 100 * s, fh, "Cancel", { kind = "ghost" }) then
      S.shopKey = shown[1]
    end
    return
  end

  local rec = key and byKey[key]
  if not rec then
    Kit.emptyBox(formX, listY, formW, listH,
      #keys == 0
        and "No shops found (Link Recomp / Import ROM, or + New shop)"
        or "Select a shop")
    return
  end

  Kit.caption(formX, y,
    rec.textId .. (rec.owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "shopsFormScroll", key, rec.owned and 44 * s or 12 * s)
  local contentTop = fy

  Kit.text("micro", rec.label .. " / " .. rec.textId, viewX, fy, PAL.muted)
  fy = fy + 20 * s
  Kit.text("micro",
    string.format("%d item(s)  |  Save patches text_pointers", #(rec.mart or {})),
    viewX, fy, PAL.detail)
  fy = fy + 24 * s

  if not rec.owned then
    Kit.text("micro", "Edit clones this shop into the mod.", viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensureGen1Shop(S, rec.label, rec.textId, App)
      keys, byKey = collectShops(S)
      rec = byKey[key]
    end
    fy = fy + fh + 12 * s
  end

  local mart = rec.mart or {}
  Kit.text("micro", "Stock", viewX, fy, PAL.caption)
  fy = fy + 18 * s

  for mi, itemId in ipairs(mart) do
    local slot = mi
    local label = rec.label
    local textId = rec.textId
    ItemPicker.field(S, {
      x = viewX, y = fy, w = viewW - 44 * s, h = fh,
      current = itemId or "POKE_BALL",
      title = "SHOP STOCK",
      onPick = function(id)
        local e = ensureGen1Shop(S, label, textId, App)
        e.mart[slot] = id
        App.markDirty()
      end,
    })
    if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
        { kind = "danger", font = "small" }) then
      local e = ensureGen1Shop(S, label, textId, App)
      table.remove(e.mart, slot)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end

  if Kit.button(viewX, fy, 120 * s, fh, "+ Add item", { kind = "good" }) then
    local label = rec.label
    local textId = rec.textId
    ensureGen1Shop(S, label, textId, App)
    ItemPicker.open(S, {
      current = (#items > 0 and items[1]) or "POKE_BALL",
      title = "ADD SHOP ITEM",
      onPick = function(id)
        local e = ensureGen1Shop(S, label, textId, App)
        e.mart[#e.mart + 1] = id
        App.markDirty()
      end,
    })
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "shopsFormScroll", contentTop, fy, view)

  if rec.owned and Kit.button(formX + 12 * s, listY + listH - 40 * s,
      140 * s, 32 * s, "Clear shop", {
        kind = "danger",
        tooltip = "Remove mart from this TEXT_* (reverts role to talk)",
      }) then
    local e = ensureGen1Shop(S, rec.label, rec.textId, App)
    e.mart = nil
    local empty = true
    for k in pairs(e) do
      if k ~= "mart" then empty = false; break end
    end
    if empty then
      S.project.text_pointers[rec.label][rec.textId] = nil
      if not next(S.project.text_pointers[rec.label]) then
        S.project.text_pointers[rec.label] = nil
      end
    end
    S.shopKey = nil
    App.markDirty()
  end
end

return Shops
