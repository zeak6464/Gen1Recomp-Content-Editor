-- UI tab "Menus" mode: replace in-game chrome sheets the engine already
-- loads (battle HUD, pack, dex, naming, emotes, slots, diploma, …).
-- Does not reimplement screen flow. Player backs stay on Player; trainer
-- class pics on Trainers; trainer-card sheets on Badges.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local UiPreview = require("UiPreview")
local Generation = require("Generation")
local PAL = Theme.PAL

local UiMenus = {}

local SKIP = {
  trainerPics = true, trainerCard = true,
  playerBack = true, playerBackFemale = true, dudeBack = true,
  palettes = true, palettesFemale = true, paletteZones = true, palMap = true,
  palette = true, cursorPalette = true, questionMarkPalette = true,
  orangePalette = true,
  pocketName = true, pocketOrder = true, pocketPicture = true,
  cards = true, maps = true, page1 = true, footprintOrder = true,
  order = true, badgeOam = true, generation = true, source = true,
  bubbles = true, symbols = true,
}

local NAMING_KEYS = { "border", "cursor", "middleLine", "underLine" }

-- Field keys that already have their own UI-tab modes (or are gameplay).
local SKIP_FIELD_EXTRA = {
  title = true, intro = true, oakSpeech = true, credits = true, theme = true,
  townMap = true, boot = true, playerPics = true, playerSprites = true,
  ledges = true, hiddenItems = true, badgeGates = true, flyOrder = true,
  flyWarps = true, seafoam = true, cardKeyDoors = true, bikeRiding = true,
  presetNames = true, pcItemCap = true, surfPikachu = true,
  surfingPikachu = true,
}

local GEN2_NESTS = {
  { id = "naming", label = "Naming" },
  { id = "battleHud", label = "Battle HUD", nest = "battleHud" },
  { id = "pack", label = "Pack", nest = "pack" },
  { id = "pokedex", label = "Pokédex", nest = "pokedex" },
  { id = "pokegear", label = "Pokégear", nest = "pokegear" },
  { id = "billsPc", label = "PC", nest = "billsPc" },
  { id = "stats", label = "Stats", nest = "stats" },
  { id = "emotes", label = "Emotes", nest = "emotes" },
  { id = "healMachine", label = "Heal machine", nest = "healMachine" },
  { id = "eggHatch", label = "Egg hatch", nest = "eggHatch" },
  { id = "unownPuzzle", label = "Unown puzzle", nest = "unownPuzzle" },
  { id = "slots", label = "Slots", nest = "slots" },
  { id = "cardFlip", label = "Card flip", nest = "cardFlip" },
  { id = "diploma", label = "Diploma", diploma = true },
}

local GEN1_NESTS = {
  { id = "battleHud", label = "Battle HUD", nest = "battleHud" },
  { id = "overworldFx", label = "Overworld FX", nest = "overworldFx" },
  { id = "emotionBubbles", label = "Emotes", nest = "emotionBubbles" },
  { id = "slotSymbols", label = "Slots", nest = "slotSymbols" },
  { id = "tradeArt", label = "Trade art", nest = "tradeArt" },
}

local function isAsset(s)
  if type(s) ~= "string" or s == "" then return false end
  local lower = s:lower()
  return lower:sub(-4) == ".png"
    or lower:sub(-8) == ".tilemap"
    or s:sub(1, 7) == "assets/"
    or s:sub(1, 5) == "mods/"
end

local function pathOf(v)
  if type(v) == "table" then return tostring(v.path or v.sheet or v.image or "") end
  if type(v) == "string" then return v end
  return ""
end

local function niceLabel(key)
  local s = tostring(key)
  s = s:gsub("(%l)(%u)", "%1 %2")
  s = s:gsub("_", " ")
  return (s:sub(1, 1):upper() .. s:sub(2)):gsub("^Hp ", "HP ")
end

local function appendKey(keys, k)
  local out = {}
  for i = 1, #keys do out[i] = keys[i] end
  out[#out + 1] = k
  return out
end

local function isNumberList(t)
  local n = 0
  for k, v in pairs(t) do
    if type(k) ~= "number" or type(v) ~= "number" then return false end
    n = n + 1
  end
  return n > 0
end

local function collectImages(tbl, pathKeys, out)
  if type(tbl) ~= "table" then return end
  local names = {}
  for k in pairs(tbl) do names[#names + 1] = k end
  table.sort(names, function(a, b)
    local na, nb = type(a) == "number", type(b) == "number"
    if na and nb then return a < b end
    if na then return true end
    if nb then return false end
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(names) do
    if not SKIP[k] then
      local v = tbl[k]
      local nextKeys = appendKey(pathKeys, k)
      if isAsset(v) then
        local label = niceLabel(k)
        if (k == "path" or k == "sheet" or k == "image") and pathKeys[1] then
          label = niceLabel(pathKeys[#pathKeys])
        end
        out[#out + 1] = { keys = nextKeys, label = label }
      elseif type(v) == "table" then
        if isNumberList(v) then
          -- tilemap / raw bytes
        else
          collectImages(v, nextKeys, out)
        end
      end
    end
  end
end

local function menuGfx(S)
  return S.data and (S.data.gen2MenuGfx or S.data.menu_gfx) or {}
end

local function diplomaData(S)
  return S.data and (S.data.gen2Diploma or S.data.diploma) or {}
end

local function fieldData(S)
  return (S.data and S.data.field) or {}
end

local function walkKeys(t, keys)
  local cur = t
  for _, key in ipairs(keys) do
    if type(cur) ~= "table" then return nil end
    cur = cur[key]
  end
  return cur
end

local function hasImages(v)
  if isAsset(v) then return true end
  if type(v) ~= "table" then return false end
  local acc = {}
  collectImages(v, {}, acc)
  return acc[1] ~= nil
end

local function groupsFor(S)
  local groups = {}
  if Generation.isGen2(S) then
    local gfx = menuGfx(S)
    local used = { trainerCard = true, generation = true, source = true }
    for _, spec in ipairs(GEN2_NESTS) do
      if spec.diploma then
        local d = diplomaData(S)
        if type(d) == "table" and type(d.image) == "string" then
          groups[#groups + 1] = spec
        end
      elseif spec.id == "naming" then
        local any = false
        for _, k in ipairs(NAMING_KEYS) do
          used[k] = true
          if gfx[k] ~= nil then any = true end
        end
        if any then groups[#groups + 1] = spec end
      elseif spec.nest then
        used[spec.nest] = true
        if type(gfx[spec.nest]) == "table" then
          groups[#groups + 1] = spec
        end
      end
    end
    local extra = {}
    for k, v in pairs(gfx) do
      if not used[k] and not SKIP[k] and hasImages(v) then
        extra[#extra + 1] = k
      end
    end
    table.sort(extra)
    for _, k in ipairs(extra) do
      groups[#groups + 1] = { id = k, label = niceLabel(k), nest = k }
    end
    return groups
  end
  local field = fieldData(S)
  local used = {}
  for _, spec in ipairs(GEN1_NESTS) do
    used[spec.nest] = true
    if type(field[spec.nest]) == "table" then
      groups[#groups + 1] = spec
    end
  end
  local extra = {}
  for k, v in pairs(field) do
    if not used[k] and not SKIP[k] and not SKIP_FIELD_EXTRA[k]
        and type(k) == "string" and k:sub(1, 1) ~= "_" and hasImages(v) then
      extra[#extra + 1] = k
    end
  end
  table.sort(extra)
  for _, k in ipairs(extra) do
    groups[#groups + 1] = { id = k, label = niceLabel(k), nest = k }
  end
  return groups
end

local function groupSource(S, spec)
  if spec.diploma then return diplomaData(S) end
  if Generation.isGen2(S) then
    local gfx = menuGfx(S)
    if spec.id == "naming" then
      local t = {}
      for _, k in ipairs(NAMING_KEYS) do t[k] = gfx[k] end
      return t
    end
    if spec.nest then return gfx[spec.nest] or {} end
    return gfx
  end
  if spec.nest then return fieldData(S)[spec.nest] or {} end
  return {}
end

local function projectBucket(S, spec)
  State.ensureProjectFields(S.project)
  if spec.diploma then
    S.project.diploma = S.project.diploma or {}
    return S.project.diploma
  end
  S.project.menuGfx = S.project.menuGfx or {}
  return S.project.menuGfx
end

local function projectBranch(S, spec)
  local root = projectBucket(S, spec)
  if spec.diploma then return root end
  if spec.id == "naming" then return root end
  if spec.nest then
    return type(root[spec.nest]) == "table" and root[spec.nest] or nil
  end
  return root
end

local function groupOwned(S, spec)
  local branch = projectBranch(S, spec)
  if type(branch) ~= "table" then return false end
  if spec.id == "naming" then
    for _, k in ipairs(NAMING_KEYS) do
      if branch[k] ~= nil then return true end
    end
    return false
  end
  return next(branch) ~= nil
end

local function fieldsFor(S, spec)
  local acc = {}
  collectImages(groupSource(S, spec), {}, acc)
  return acc
end

local function effPath(S, spec, keys)
  local proj = projectBucket(S, spec)
  local fromP
  if spec.diploma then
    fromP = walkKeys(proj, keys)
  elseif spec.nest then
    fromP = walkKeys(proj[spec.nest], keys)
  else
    fromP = walkKeys(proj, keys)
  end
  if fromP ~= nil then return pathOf(fromP), true end
  return pathOf(walkKeys(groupSource(S, spec), keys)), false
end

local function setPath(S, spec, keys, val, App)
  local root = projectBucket(S, spec)
  local cur = root
  if spec.nest then
    if type(cur[spec.nest]) ~= "table" then cur[spec.nest] = {} end
    cur = cur[spec.nest]
  end
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(cur[key]) ~= "table" then cur[key] = {} end
    cur = cur[key]
  end
  local last = keys[#keys]
  if val == nil or val == "" then
    cur[last] = nil
  else
    cur[last] = val
  end
  if App then App.markDirty() end
  pcall(Preview.invalidate)
end

local function clearGroup(S, spec, App)
  local root = projectBucket(S, spec)
  if spec.diploma then
    S.project.diploma = {}
  elseif spec.id == "naming" then
    for _, k in ipairs(NAMING_KEYS) do root[k] = nil end
  elseif spec.nest then
    root[spec.nest] = nil
  end
  if App then App.markDirty() end
  pcall(Preview.invalidate)
end

local function browseImage(App, label, onRel)
  App.pickFile(label, "PNG (*.png)|*.png|All|*.*", function(picked)
    App.importToMod(picked, nil, function(rel)
      onRel(rel)
      Preview.invalidate()
    end)
  end)
end

local function drawThumb(S, path, x, y, maxW, maxH)
  local image = Preview.image(S, path)
  Kit.card(x, y, maxW, maxH, 8 * Kit.scale)
  if not image then
    Kit.text("micro", "(no preview)", x + 8, y + 8, PAL.faint)
    return maxH
  end
  local ok, iw, ih = pcall(function()
    return image:getWidth(), image:getHeight()
  end)
  if not ok or type(iw) ~= "number" or type(ih) ~= "number" or iw < 1 or ih < 1 then
    return maxH
  end
  local pad = 6 * Kit.scale
  local sc = math.min((maxW - pad * 2) / iw, (maxH - pad * 2) / ih, 4)
  local dw, dh = iw * sc, ih * sc
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, x + (maxW - dw) / 2, y + (maxH - dh) / 2, 0, sc, sc)
  love.graphics.setColor(1, 1, 1, 1)
  return maxH
end

function UiMenus.draw(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  S.project.menuGfx = S.project.menuGfx or {}
  S.project.diploma = S.project.diploma or {}

  local groups = groupsFor(S)
  local ids = {}
  for i, g in ipairs(groups) do ids[i] = g.id end
  if #ids == 0 then ids = { "(none)" } end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "MENUS", ids, {
      queryKey = "uiMenuQuery", offsetKey = "uiMenuOffset", selKey = "uiMenuId",
      accent = PAL.yellow,
      isOwned = function(id)
        for _, g in ipairs(groups) do
          if g.id == id then return groupOwned(S, g) end
        end
        return false
      end,
    })

  if not S.uiMenuId then S.uiMenuId = shown[1] end
  local spec
  for _, g in ipairs(groups) do
    if g.id == S.uiMenuId then spec = g; break end
  end
  if not spec and shown[1] and shown[1] ~= "(none)" then
    S.uiMenuId = shown[1]
    for _, g in ipairs(groups) do
      if g.id == S.uiMenuId then spec = g; break end
    end
  end
  if not spec then
    Kit.text("micro", Generation.isGen2(S)
        and "No menu chrome in this cache (import Gold/Crystal first)"
        or "No UI chrome tables on field (battle HUD / FX / emotes / slots)",
      formX + 12 * s, listY + 12 * s, PAL.faint)
    return
  end

  local fields = fieldsFor(S, spec)
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "uiMenuScroll", tostring(spec.id), 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, spec.label:upper())
  fy = fy + 22 * s
  Kit.text("micro", Generation.isGen2(S)
      and (spec.diploma
        and "Sheet → data.gen2Diploma (Save merges on mods.loaded)"
        or "Sheets → data.gen2MenuGfx (Save merges on mods.loaded)")
      or "Sheets → field." .. tostring(spec.nest or spec.id) .. " (Save patches field)",
    viewX, fy, PAL.muted)
  fy = fy + 18 * s
  fy = UiPreview.draw(S, "menus", viewX, fy, viewW, s)

  if #fields == 0 then
    Kit.text("micro", "No replaceable image paths in this group",
      viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end

  for _, field in ipairs(fields) do
    local cur, owned = effPath(S, spec, field.keys)
    local fieldId = "ui_menu_" .. spec.id
    for _, k in ipairs(field.keys) do
      fieldId = fieldId .. "_" .. tostring(k)
    end
    Kit.text("small", field.label, viewX, fy + 6 * s, PAL.caption)
    if owned then
      Kit.text("micro", "override", viewX, fy + 16 * s, PAL.yellow)
    end
    local fx = viewX + labelW
    local v = RegList.field(App, fieldId, fx, fy,
      math.max(40 * s, fieldW - 100 * s), fh, cur, "assets/...")
    if v ~= cur then setPath(S, spec, field.keys, v ~= "" and v or nil, App) end
    if Kit.button(fx + fieldW - 96 * s, fy, 96 * s, fh, "Browse", {
        kind = "ghost", tooltip = "Import PNG into mod",
      }) then
      browseImage(App, field.label .. " PNG", function(rel)
        setPath(S, spec, field.keys, rel, App)
      end)
    end
    fy = fy + fh + 6 * s
    local thumbH = 64 * s
    fy = fy + drawThumb(S, v ~= "" and v or cur, viewX, fy, viewW, thumbH) + 10 * s
  end

  if groupOwned(S, spec) and Kit.button(viewX, fy, 120 * s, fh, "Clear", {
      kind = "danger" }) then
    clearGroup(S, spec, App)
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiMenuScroll", contentTop, fy, view)
end

return UiMenus
