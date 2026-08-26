-- Pokemon tab: full species editing (stats, learnset, evolutions, tmhm, dex).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local ModIO = require("ModIO")
local Search = require("Search")
local TypeIds = require("TypeIds")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local PaletteEdit = require("PaletteEdit")
local ItemPicker = require("ItemPicker")
local ChoicePicker = require("ChoicePicker")
local SpeciesPicker = require("SpeciesPicker")
local ColorWheel = require("ColorWheel")
local FormPane = require("FormPane")
local RegList = require("RegList")
local Autocomplete = require("Autocomplete")
local Generation = require("Generation")
local EvoBreedTrees = require("EvoBreedTrees")
local PAL = Theme.PAL

local Pokemon = {}

local GROWTH = { "MEDIUM_FAST", "MEDIUM_SLOW", "FAST", "SLOW" }
local GROWTH_GEN2 = {
  "GROWTH_MEDIUM_FAST", "GROWTH_MEDIUM_SLOW", "GROWTH_FAST", "GROWTH_SLOW",
  "GROWTH_SLIGHTLY_FAST", "GROWTH_SLIGHTLY_SLOW",
}
local GROWTH_IDS = {
  GROWTH_MEDIUM_FAST = 0, GROWTH_SLIGHTLY_FAST = 1, GROWTH_SLIGHTLY_SLOW = 2,
  GROWTH_MEDIUM_SLOW = 3, GROWTH_FAST = 4, GROWTH_SLOW = 5,
}
local EVO_METHODS = { "LEVEL", "ITEM", "TRADE" }
local EVO_METHODS_GEN2 = {
  "EVOLVE_LEVEL", "EVOLVE_ITEM", "EVOLVE_TRADE", "EVOLVE_HAPPINESS", "EVOLVE_STAT",
}
local EVO_TIME = { "ANYTIME", "MORNDAY", "NITE" }
local EVO_COMPARISON = { "ATK_LT_DEF", "ATK_GT_DEF", "ATK_EQ_DEF" }
local EGG_GROUPS = {
  "EGG_MONSTER", "EGG_WATER_1", "EGG_BUG", "EGG_FLYING", "EGG_GROUND",
  "EGG_FAIRY", "EGG_PLANT", "EGG_HUMANSHAPE", "EGG_WATER_3", "EGG_MINERAL",
  "EGG_INDETERMINATE", "EGG_WATER_2", "EGG_DITTO", "EGG_DRAGON", "EGG_NONE",
}
local ICON_NAMES = {
  "", "MON", "BALL", "HELIX", "FAIRY", "BIRD", "WATER",
  "BUG", "GRASS", "SNAKE", "QUADRUPED", "PIKACHU",
}
local ICON_NAMES_GEN2 = {
  "", "ICON_MONSTER", "ICON_BALL", "ICON_BIRD", "ICON_BUG", "ICON_FISH",
  "ICON_FOX", "ICON_PIKACHU", "ICON_ODDISH", "ICON_HUMANSHAPE", "ICON_EQUINE",
  "ICON_SERPENT", "ICON_UNOWN", "ICON_EGG",
}
local SECTIONS = {
  { id = "basics", label = "Basics" },
  { id = "learnset", label = "Learnset" },
  { id = "evolutions", label = "Evos" },
  { id = "trees", label = "Trees" },
  { id = "tmhm", label = "TM/HM" },
  { id = "dex", label = "Dex" },
}

local function iconNameOf(mon)
  local entry = mon and mon.icon
  if type(entry) == "string" then return entry end
  return ""
end

local function growthList(S)
  return Generation.isGen2(S) and GROWTH_GEN2 or GROWTH
end

local function iconList(S)
  if not Generation.isGen2(S) then return ICON_NAMES end
  local icons = S.data and (S.data.gen2Icons or S.data.icons)
  if type(icons) == "table" and type(icons.icons) == "table" then
    local names = { "" }
    for id in pairs(icons.icons) do names[#names + 1] = id end
    table.sort(names, function(a, b)
      if a == "" then return true end
      if b == "" then return false end
      return a < b
    end)
    return names
  end
  return ICON_NAMES_GEN2
end

local function normalizeGrowth(rate)
  if type(rate) ~= "string" or rate == "" then return "GROWTH_MEDIUM_FAST" end
  if rate:sub(1, 7) == "GROWTH_" then return rate end
  local map = {
    MEDIUM_FAST = "GROWTH_MEDIUM_FAST", MEDIUM_SLOW = "GROWTH_MEDIUM_SLOW",
    FAST = "GROWTH_FAST", SLOW = "GROWTH_SLOW",
    SLIGHTLY_FAST = "GROWTH_SLIGHTLY_FAST", SLIGHTLY_SLOW = "GROWTH_SLIGHTLY_SLOW",
  }
  return map[rate] or ("GROWTH_" .. rate)
end

local function normalizeEvoMethod(method)
  if type(method) ~= "string" or method == "" then return "EVOLVE_LEVEL" end
  if method:sub(1, 7) == "EVOLVE_" then return method end
  local map = {
    LEVEL = "EVOLVE_LEVEL", ITEM = "EVOLVE_ITEM", TRADE = "EVOLVE_TRADE",
    HAPPINESS = "EVOLVE_HAPPINESS", HAPPINESS_DAY = "EVOLVE_HAPPINESS",
    HAPPINESS_NITE = "EVOLVE_HAPPINESS", STAT = "EVOLVE_STAT",
  }
  return map[method] or method
end

local function copyStringList(v)
  local a = {}
  for i = 1, #(v or {}) do a[i] = v[i] end
  return a
end

-- Gold wild held items: rare = [1], common = [2]; common-only is sparse {[2]=…}.
local function copyItemsList(v)
  if type(v) ~= "table" then return {} end
  local a = {}
  if type(v[1]) == "string" and v[1] ~= "" then a[1] = v[1] end
  if type(v[2]) == "string" and v[2] ~= "" then a[2] = v[2] end
  return a
end

local function setWildItem(mon, slot, id)
  local items = copyItemsList(mon.items)
  if type(id) == "string" and id ~= "" and id ~= "NO_ITEM" then
    items[slot] = id
  else
    items[slot] = nil
  end
  if items[1] == nil and items[2] == nil then
    mon.items = {}
  else
    mon.items = items
  end
end

local function allSpeciesIds(S)
  local seen, ids = {}, {}
  local deleted = (S.project and S.project.deleted and S.project.deleted.pokemon) or {}
  for id, rec in pairs((S.project and S.project.pokemon) or {}) do
    if not deleted[id] and State.isPokemonRecord(id, rec) then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.data and S.data.pokemon then
    for id, rec in pairs(S.data.pokemon) do
      if not seen[id] and not deleted[id] and State.isPokemonRecord(id, rec) then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local WHITE = { 255, 255, 255 }
local BLACK = { 0, 0, 0 }

local function rgbOf(c, fallback)
  fallback = fallback or { 128, 128, 128 }
  if type(c) ~= "table" then return { fallback[1], fallback[2], fallback[3] } end
  if c.r then return { c.r, c.g, c.b } end
  return { c[1] or fallback[1], c[2] or fallback[2], c[3] or fallback[3] }
end

-- Gold battle pics are 4 GBC shades. Vanilla extract stores the two middle
-- colors only; expand those to white + mids + black so all four are editable.
local function cloneRgbRow(row)
  local src = type(row) == "table" and row or {}
  if src[3] and src[4] then
    return { rgbOf(src[1], WHITE), rgbOf(src[2]), rgbOf(src[3]), rgbOf(src[4], BLACK) }
  end
  return { rgbOf(WHITE, WHITE), rgbOf(src[1]), rgbOf(src[2]), rgbOf(BLACK, BLACK) }
end

-- Clone vanilla palettes.pokemon[species] into the mod for editing.
local function ensureGen2MonPalette(S, speciesId, App)
  if not speciesId or speciesId == "" then return nil end
  State.ensureProjectFields(S.project)
  S.project.palettes = S.project.palettes or {}
  S.project.palettes.pokemon = S.project.palettes.pokemon or {}
  local owned = S.project.palettes.pokemon[speciesId]
  if type(owned) == "table" and owned.normal and owned.shiny then
    owned.normal = cloneRgbRow(owned.normal)
    owned.shiny = cloneRgbRow(owned.shiny)
    return owned
  end
  local base = Preview.gen2MonPaletteEntry(S, speciesId)
  local copy = {
    normal = cloneRgbRow(base and base.normal),
    shiny = cloneRgbRow(base and base.shiny),
  }
  -- Keep a partial project override's colors when only one form was patched.
  if type(owned) == "table" then
    if owned.normal then copy.normal = cloneRgbRow(owned.normal) end
    if owned.shiny then copy.shiny = cloneRgbRow(owned.shiny) end
  end
  S.project.palettes.pokemon[speciesId] = copy
  if App and App.markDirty then App.markDirty() end
  return copy
end

local function cloneAnim(src)
  if type(src) ~= "table" then return nil end
  local a = {}
  for k, v in pairs(src) do a[k] = v end
  return a
end

local function deepCloneMon(def)
  local copy = {}
  for k, v in pairs(def) do
    if k == "items" then
      copy[k] = copyItemsList(v)
    elseif k == "types" or k == "level1Moves" or k == "tmhm"
        or k == "eggGroups" or k == "eggMoves"
        or k == "tmhmRaw" then
      copy[k] = copyStringList(v)
    elseif k == "baseStats" and type(v) == "table" then
      local s = {}
      for sk, sv in pairs(v) do s[sk] = sv end
      copy.baseStats = s
    elseif (k == "learnset" or k == "levelMoves") and type(v) == "table" then
      local a = {}
      for i, row in ipairs(v) do
        if type(row) == "table" then
          local r = {}
          for rk, rv in pairs(row) do r[rk] = rv end
          a[i] = r
        else
          a[i] = row
        end
      end
      copy[k] = a
    elseif k == "evolutions" and type(v) == "table" then
      local a = {}
      for i, row in ipairs(v) do
        if type(row) == "table" then
          local r = {}
          for rk, rv in pairs(row) do r[rk] = rv end
          a[i] = r
        else
          a[i] = row
        end
      end
      copy.evolutions = a
    elseif k == "anim" and type(v) == "table" then
      copy.anim = cloneAnim(v)
    elseif (k == "dexEntry" or k == "letters" or k == "forms") and type(v) == "table" then
      local d = {}
      for dk, dv in pairs(v) do
        if type(dv) == "table" then
          local sub = {}
          for sk, sv in pairs(dv) do
            if sk == "anim" and type(sv) == "table" then
              sub.anim = cloneAnim(sv)
            else
              sub[sk] = sv
            end
          end
          d[dk] = sub
        else
          d[dk] = dv
        end
      end
      copy[k] = d
    elseif k == "icon" and type(v) == "table" then
      local ic = {}
      for ik, iv in pairs(v) do ic[ik] = iv end
      copy.icon = ic
    else
      copy[k] = v
    end
  end
  copy._isNew = false
  return copy
end

local function resolveMon(S, id)
  if not id then return nil, false end
  if S.project.pokemon[id] then return S.project.pokemon[id], true end
  if S.data and S.data.pokemon and S.data.pokemon[id] then
    return S.data.pokemon[id], false
  end
  return nil, false
end

local function ensureOwned(S, id)
  local def, owned = resolveMon(S, id)
  if not def then return nil end
  if owned then return def end
  local copy = deepCloneMon(def)
  S.project.pokemon[id] = copy
  return copy
end

local function considerDex(bucket, maxDex)
  for _, rec in pairs(bucket or {}) do
    local n = type(rec) == "table" and tonumber(rec.dex)
    if n and n > maxDex then maxDex = n end
  end
  return maxDex
end

-- Gold's species `index` is the ROM byte (Celebi is 251; 253 is EGG). Extra
-- species omit that field and take the next national dex number from 252 up.
local function nextOverflowDex(S)
  local maxDex = 251
  maxDex = considerDex(S.data and S.data.pokemon, maxDex)
  maxDex = considerDex(S.project and S.project.pokemon, maxDex)
  maxDex = considerDex(S.project and S.project.pokedex, maxDex)
  local entries = S.data and S.data.gen2Pokedex and S.data.gen2Pokedex.entries
  maxDex = considerDex(entries, maxDex)
  return maxDex + 1
end

local function defaultMon(id, S)
  if Generation.isGen2(S) then
    local dex = nextOverflowDex(S)
    return {
      id = id,
      name = id,
      dex = dex,
      types = { "NORMAL" },
      baseStats = {
        hp = 50, attack = 50, defense = 50, speed = 50,
        specialAttack = 50, specialDefense = 50,
      },
      catchRate = 190,
      baseExp = 64,
      growthRate = "GROWTH_MEDIUM_FAST",
      growthRateId = 0,
      levelMoves = { { level = 1, move = "TACKLE" } },
      evolutions = {},
      tmhm = {},
      eggGroups = { "EGG_GROUND", "EGG_GROUND" },
      eggMoves = {},
      eggSteps = 20,
      genderRatio = 31,
      items = {},
      spriteFront = "",
      spriteBack = "",
      picSize = 5,
      _isNew = true,
    }
  end
  return {
    id = id,
    name = id,
    dex = 1,
    types = { "NORMAL" },
    baseStats = { hp = 50, attack = 50, defense = 50, speed = 50, special = 50 },
    catchRate = 190,
    baseExp = 64,
    growthRate = "MEDIUM_FAST",
    level1Moves = { "TACKLE" },
    learnset = {},
    evolutions = {},
    tmhm = {},
    spriteFront = "",
    spriteBack = "",
    frontSize = 5,
    dexEntry = { kind = "???", heightFt = 1, heightIn = 0, weight = 10, text = "" },
    _isNew = true,
  }
end

-- Optional 9th arg `suggest`: id list or function() -> list for autocomplete.
local function field(S, App, id, x, y, w, h, value, ph, suggest)
  if suggest then
    return RegList.suggestField(App, S, id, x, y, w, h, value, ph, suggest)
  end
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function numField(S, App, id, x, y, w, h, value)
  local v = field(S, App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

local function parseMoveList(str)
  local moves = {}
  for part in (str .. ","):gmatch("([^,]*),") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then moves[#moves + 1] = part:upper():gsub("%s+", "_") end
  end
  return moves
end

-- Prefer authored path; fall back to vanilla when project omitted ROM-cache sprites.
local function monSpritePath(S, mon, field)
  local p = mon and mon[field]
  if type(p) == "string" and p ~= "" then return p end
  local id = (mon and mon.id) or S.pokemonId
  local vanilla = id and S.data and S.data.pokemon and S.data.pokemon[id]
  local vp = vanilla and vanilla[field]
  if type(vp) == "string" and vp ~= "" then return vp end
  return nil
end

local UNOWN_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function isUnownLetterId(id)
  return type(id) == "string" and #id == 1 and UNOWN_LETTERS:find(id, 1, true)
end

local function normalizeFormId(s)
  if type(s) ~= "string" then return nil end
  s = s:upper():gsub("%s+", "_"):gsub("[^A-Z0-9_]", "")
  if s == "" then return nil end
  return s
end

-- Unown keeps `letters` (engine UnownPicPointers). Everyone else uses `forms`.
local function formBucketKey(mon, formId)
  if not mon then return "forms" end
  if mon.id == "UNOWN" then return "letters" end
  if formId and type(mon.letters) == "table" and type(mon.letters[formId]) == "table" then
    return "letters"
  end
  return "forms"
end

local function formRecord(mon, formId)
  if not formId or type(mon) ~= "table" then return nil end
  for _, key in ipairs({ "letters", "forms" }) do
    local bucket = mon[key]
    if type(bucket) == "table" then
      local rec = bucket[formId]
      if type(rec) == "table" then return rec end
    end
  end
  return nil
end

local function formIdList(mon)
  local ids, seen = {}, {}
  if mon and mon.id == "UNOWN" then
    for i = 1, 26 do
      local L = UNOWN_LETTERS:sub(i, i)
      ids[#ids + 1] = L
      seen[L] = true
    end
  end
  local extra = {}
  for _, key in ipairs({ "letters", "forms" }) do
    local bucket = mon and mon[key]
    if type(bucket) == "table" then
      for k in pairs(bucket) do
        if type(k) == "string" and k ~= "" and not seen[k] then
          extra[#extra + 1] = k
          seen[k] = true
        end
      end
    end
  end
  table.sort(extra)
  for _, k in ipairs(extra) do ids[#ids + 1] = k end
  return ids
end

local function selectedFormId(S, mon)
  local ids = formIdList(mon)
  local cur = normalizeFormId(S.pokemonFormId or S.pokemonUnownLetter)
  if mon and mon.id == "UNOWN" then
    if not cur then return "A" end
    for _, id in ipairs(ids) do
      if id == cur then return id end
    end
    return "A"
  end
  if not cur then return nil end
  for _, id in ipairs(ids) do
    if id == cur then return id end
  end
  return nil
end

local function isLockedForm(mon, formId)
  return mon and mon.id == "UNOWN" and isUnownLetterId(formId)
end

local function vanillaMon(S, mon)
  local id = (mon and mon.id) or S.pokemonId
  return id and S.data and S.data.pokemon and S.data.pokemon[id] or nil
end

local function formSpritePath(S, mon, field, formId)
  local rec = formRecord(mon, formId)
  if rec and type(rec[field]) == "string" and rec[field] ~= "" then
    return rec[field]
  end
  rec = formRecord(vanillaMon(S, mon), formId)
  if rec and type(rec[field]) == "string" and rec[field] ~= "" then
    return rec[field]
  end
  return monSpritePath(S, mon, field)
end

local function formAnim(S, mon, formId)
  local rec = formRecord(mon, formId)
  if rec and type(rec.anim) == "table" and rec.anim.sheet then return rec.anim end
  rec = formRecord(vanillaMon(S, mon), formId)
  if rec and type(rec.anim) == "table" and rec.anim.sheet then return rec.anim end
  if type(mon.anim) == "table" and mon.anim.sheet then return mon.anim end
  local vanilla = vanillaMon(S, mon)
  if type(vanilla) == "table" and type(vanilla.anim) == "table" and vanilla.anim.sheet then
    return vanilla.anim
  end
  return nil
end

local function assignFormSprite(mon, formId, key, rel)
  if formId then
    local bucket = formBucketKey(mon, formId)
    mon[bucket] = mon[bucket] or {}
    mon[bucket][formId] = mon[bucket][formId] or {}
    mon[bucket][formId][key] = rel
    if mon.id == "UNOWN" and formId == "A" then mon[key] = rel end
  else
    mon[key] = rel
  end
end

local function assignFormAnimSheet(mon, formId, rel)
  if formId then
    local bucket = formBucketKey(mon, formId)
    mon[bucket] = mon[bucket] or {}
    local rec = mon[bucket][formId] or {}
    mon[bucket][formId] = rec
    rec.anim = cloneAnim(rec.anim) or cloneAnim(mon.anim)
      or { tiles = mon.picSize or 5, count = 1 }
    rec.anim.sheet = rel
    if mon.id == "UNOWN" and formId == "A" then
      mon.anim = cloneAnim(mon.anim) or rec.anim
      mon.anim.sheet = rel
    end
  else
    mon.anim = cloneAnim(mon.anim) or { tiles = mon.picSize or 5, count = 1 }
    mon.anim.sheet = rel
  end
end

local function drawAnimPreview(S, anim, x, y, box, pal)
  local path = anim and anim.sheet
  if type(path) ~= "string" or path == "" then return false end
  local img = Preview.image(S, path)
  if not img then return false end
  local s = Kit.scale
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, box, box, 8 * s, 8 * s)
  local tiles = tonumber(anim.tiles) or 5
  local size = math.max(8, tiles * 8)
  local count = math.max(1, tonumber(anim.count) or 1)
  local ok, iw, ih = pcall(function() return img:getDimensions() end)
  if not (ok and iw and ih and ih >= size) then return false end
  local t = 0
  if love.timer and love.timer.getTime then t = love.timer.getTime() end
  local frame = math.floor(t * 8) % count
  if (frame + 1) * size > ih then frame = 0 end
  local quad = love.graphics.newQuad(0, frame * size, math.min(size, iw), size, iw, ih)
  local scale = math.min(box / size, box / size)
  local dw, dh = size * scale, size * scale
  local shaded = false
  if pal then shaded = Preview.pushPaletteShader(S, pal) end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, x + (box - dw) / 2, y + (box - dh) / 2, 0, scale, scale)
  Preview.popPaletteShader(shaded)
  return true
end

local function drawBasics(S, mon, mutate, App, formX, fy, formW, labelW, fh, s)
  local prevSize = 96 * s
  local iconSize = 40 * s
  local gap = 10 * s
  local previewBottom = fy + prevSize + 30 * s
  local iconX = formX + formW - prevSize * 2 - gap - iconSize - gap
  local gen2 = Generation.isGen2(S)
  local sid = S.pokemonId or mon.id
  local palName = Preview.monPaletteName(S, mon, sid)
  local shinyPrev = gen2 and S.pokemonShinyPreview and true or false
  -- false = skip SGB remap. Gold uses GBC species palettes (normal/shiny).
  local drawPal = false
  local iconPal = false
  local gen2Colors = nil
  if gen2 then
    gen2Colors = Preview.gen2MonColors(S, sid, shinyPrev)
    drawPal = gen2Colors or false
    iconPal = gen2Colors or false
  else
    drawPal = palName
    if mon.trueColor then drawPal = false end
    iconPal = palName
    if Preview.pokemonIconTrueColor(S, mon, sid) then iconPal = false end
  end
  local function openMonPal()
    if gen2 or mon.trueColor then return end
    local eid = sid
    PalettePicker.open(S, {
      current = mon.palette,
      allowClear = true,
      clearLabel = "(pack default / MEWMON)",
      title = "POKEMON SPRITE / ICON PALETTE",
      onPick = function(id)
        mon = mutate()
        mon.palette = id
        Preview.invalidate()
        App.markDirty()
      end,
      owner = {
        kind = "pokemon",
        entityId = eid,
        entityLabel = mon.name or eid,
        assign = function(id)
          mon = mutate()
          mon.palette = id
          Preview.invalidate()
          App.markDirty()
        end,
      },
    })
  end
  Preview.drawPokemonIcon(S, mon, iconX, fy, iconSize, iconSize, sid, iconPal)
  if not gen2 and Kit.press(iconX, fy, iconSize, iconSize) then openMonPal() end
  local frontX = formX + formW - prevSize * 2 - gap
  local formId = selectedFormId(S, mon)
  local anim = formAnim(S, mon, formId)
  local playAnim = anim and (S.pokemonAnimPreview ~= false)
  local frontPath = formSpritePath(S, mon, "spriteFront", formId)
  local backPath = formSpritePath(S, mon, "spriteBack", formId)
  if not (playAnim and drawAnimPreview(S, anim, frontX, fy, prevSize, drawPal)) then
    Preview.draw(S, frontPath, frontX, fy, prevSize, prevSize, drawPal)
  end
  Preview.draw(S, backPath, formX + formW - prevSize, fy, prevSize, prevSize,
    drawPal)
  if not gen2 and Kit.press(frontX, fy, prevSize * 2 + gap, prevSize) then
    openMonPal()
  end
  if gen2 then
    local chipY = fy + prevSize + 2 * s
    local nw = Kit.textWidth("micro", "Normal") + 12 * s
    local sw = Kit.textWidth("micro", "Shiny") + 12 * s
    local cx = frontX
    if Kit.chip(cx, chipY, nw, 16 * s, "Normal", not shinyPrev, PAL.blue) then
      S.pokemonShinyPreview = false
    end
    cx = cx + nw + 4 * s
    if Kit.chip(cx, chipY, sw, 16 * s, "Shiny", shinyPrev, PAL.yellow) then
      S.pokemonShinyPreview = true
    end
    cx = cx + sw + 4 * s
    if anim then
      local aw = Kit.textWidth("micro", "Anim") + 12 * s
      if Kit.chip(cx, chipY, aw, 16 * s, "Anim", playAnim, PAL.green, PAL.steel,
          "Crystal battle front animation") then
        S.pokemonAnimPreview = not playAnim
      end
      cx = cx + aw + 4 * s
    end
    if Kit.button(cx, chipY, 70 * s, 16 * s, "GFX", {
        kind = "ghost", font = "micro",
        tooltip = "Edit normal/shiny colors on GFX → Palettes → Pokemon",
      }) then
      S.tab = "gfx"
      S.gfxMode = "palettes"
      S.gfxPalContext = "pokemon"
      S.paletteId = sid
    end
    if gen2Colors then
      Preview.drawSwatches(gen2Colors, frontX, chipY + 18 * s,
        prevSize * 2 + gap, 10 * s)
    else
      Kit.text("micro", "missing palettes.lua (re-import Gold/Silver ROM)",
        frontX, chipY + 18 * s, PAL.danger or PAL.yellow)
    end
    previewBottom = fy + prevSize + 48 * s
  elseif mon.trueColor then
    Kit.text("micro", "true color", frontX, fy + prevSize + 2 * s, PAL.yellow)
  else
    Preview.drawNamedSwatches(S, palName, frontX, fy + prevSize + 2 * s,
      prevSize * 2 + gap, 10 * s)
    if Kit.press(frontX, fy + prevSize + 2 * s, prevSize * 2 + gap, 12 * s) then
      openMonPal()
    end
  end
  Kit.text("micro", "icon", iconX + 4 * s, fy + iconSize + 2 * s, PAL.faint)
  Kit.text("micro", playAnim and "front (anim)" or "front", frontX + 4 * s,
    fy + prevSize + (gen2 and 34 * s or 14 * s), PAL.faint)
  Kit.text("micro", "back", formX + formW - prevSize + 4 * s,
    fy + prevSize + (gen2 and 34 * s or 14 * s), PAL.faint)

  local fieldW = formW - labelW - prevSize * 2 - gap - iconSize - gap - 24 * s
  if fieldW < 160 * s then fieldW = formW - labelW - 20 * s end
  local function row(label, body)
    Kit.text("small", label, formX, fy + 6 * s, PAL.caption)
    body(formX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  row("ID", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_id", fx, fy_, fw, fh_, mon.id, "SPECIES_ID")
    if v ~= mon.id and v:match("^[%w_]+$")
       and not S.project.pokemon[v]
       and not (S.data.pokemon and S.data.pokemon[v]) then
      mon = mutate()
      local old = mon.id
      S.project.pokemon[old] = nil
      mon.id = v
      S.project.pokemon[v] = mon
      S.pokemonId = v
      if S.project.pokedex and S.project.pokedex[old] then
        S.project.pokedex[v] = S.project.pokedex[old]
        S.project.pokedex[old] = nil
        S.project.pokedex[v].id = v
      end
      App.markDirty()
    end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_name", fx, fy_, fw, fh_, mon.name, "NAME")
    if v ~= (mon.name or "") then mon = mutate(); mon.name = v end
  end)
  row("Dex #", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_dex", fx, fy_, 80 * s, fh_, mon.dex)
    if v ~= mon.dex then mon = mutate(); mon.dex = v end
    if Generation.isGen2(S) then
      Kit.offerTooltip(fx, fy_, 80 * s, fh_,
        "National dex number. Extra species start at 252")
    end
  end)
  row("Index", function(fx, fy_, fw, fh_)
    if Generation.isGen2(S) then
      local cur = mon.index
      local shown = (type(cur) == "number" and cur >= 0 and cur <= 255)
        and tostring(cur) or ""
      Kit.offerTooltip(formX, fy, labelW + fw, fh,
        "ROM species byte (0–255). Leave empty for extra species past Celebi")
      local v = field(S, App, "pk_idx", fx, fy_, 80 * s, fh_, shown, "overflow")
      if v == "" then
        if cur ~= nil then mon = mutate(); mon.index = nil end
      else
        local n = tonumber(v)
        if n and n >= 0 and n <= 255 then
          if n ~= cur then mon = mutate(); mon.index = n end
        elseif Kit.focus ~= "pk_idx" then
          if cur ~= nil then mon = mutate(); mon.index = nil end
          S.status = "Gold species index is a ROM byte (0–255). Extra species omit it."
        end
      end
      Kit.text("micro", shown == "" and "dex overflow — no ROM byte"
        or "ROM byte; 253 is EGG",
        fx + 90 * s, fy_ + 8 * s, PAL.faint)
    else
      local cur = mon.index or 0
      local v = numField(S, App, "pk_idx", fx, fy_, 80 * s, fh_, cur)
      if v ~= cur then mon = mutate(); mon.index = v end
    end
  end)

  Kit.text("small", "Types", formX, fy + 6 * s, PAL.caption)
  do
    local tx = formX + labelW
    mon.types = mon.types or { "NORMAL" }
    local typeIds = TypeIds.list(S)
    local half = math.floor((fieldW - 8 * s) / 2)
    for i = 1, 2 do
      local cur = mon.types[i] or (i == 1 and "NORMAL" or "")
      local slot = i
      ChoicePicker.field(S, {
        x = tx, y = fy, w = half, h = fh,
        current = cur,
        ids = typeIds,
        emptyLabel = slot == 1 and "NORMAL" or "(none)",
        allowClear = slot == 2,
        clearLabel = "(none)",
        title = slot == 1 and "TYPE 1" or "TYPE 2",
        tooltip = "Pick a type from the list",
        onPick = function(id)
          mon = mutate()
          mon.types = mon.types or { "NORMAL" }
          if slot == 1 then
            mon.types[1] = (type(id) == "string" and id ~= "" and id) or "NORMAL"
          else
            mon.types[2] = (type(id) == "string" and id ~= "") and id or nil
          end
          App.markDirty()
        end,
      })
      tx = tx + half + 8 * s
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Stats", formX, fy + 6 * s, PAL.caption)
  mon.baseStats = mon.baseStats or {}
  local sx = formX + labelW
  local statKeys = Generation.isGen2(S)
    and { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }
    or { "hp", "attack", "defense", "speed", "special" }
  local sw = Generation.isGen2(S) and (58 * s) or (70 * s)
  for _, key in ipairs(statKeys) do
    local lab = key == "specialAttack" and "SPA"
      or key == "specialDefense" and "SPD"
      or key == "special" and "SPC"
      or key:sub(1, 3):upper()
    Kit.text("micro", lab, sx, fy - 2 * s, PAL.faint)
    local cur = mon.baseStats[key]
    if cur == nil and key == "specialAttack" then
      cur = mon.baseStats.special or 50
    elseif cur == nil and key == "specialDefense" then
      cur = mon.baseStats.special or 50
    end
    cur = cur or 50
    local v = numField(S, App, "pk_st_" .. key, sx, fy + 12 * s, sw, fh, cur)
    if v ~= cur then
      mon = mutate()
      mon.baseStats = mon.baseStats or {}
      mon.baseStats[key] = math.max(1, math.min(255, v))
      if Generation.isGen2(S) then mon.baseStats.special = nil end
    end
    sx = sx + sw + 6 * s
  end
  fy = fy + fh + 28 * s

  row("Catch", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_catch", fx, fy_, 80 * s, fh_, mon.catchRate)
    if v ~= mon.catchRate then mon = mutate(); mon.catchRate = v end
  end)
  row("Base Exp", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_exp", fx, fy_, 80 * s, fh_, mon.baseExp)
    if v ~= mon.baseExp then mon = mutate(); mon.baseExp = v end
  end)
  row("Growth", function(fx, fy_, fw, fh_)
    local rates = growthList(S)
    local cur = mon.growthRate or rates[1]
    if Generation.isGen2(S) then cur = normalizeGrowth(cur) end
    ChoicePicker.field(S, {
      x = fx, y = fy_, w = fw, h = fh_,
      current = cur,
      ids = rates,
      title = "GROWTH RATE",
      tooltip = "Pick a growth rate from the list",
      onPick = function(id)
        if type(id) ~= "string" or id == "" then return end
        mon = mutate()
        mon.growthRate = id
        if Generation.isGen2(S) then
          mon.growthRateId = GROWTH_IDS[mon.growthRate]
        end
        App.markDirty()
      end,
    })
  end)
  row(Generation.isGen2(S) and "Pic size" or "Front size", function(fx, fy_, fw, fh_)
    local cur = Generation.isGen2(S)
      and (mon.picSize or mon.frontSize or 5)
      or (mon.frontSize or 5)
    local v = numField(S, App, "pk_fs", fx, fy_, 60 * s, fh_, cur)
    v = math.max(1, math.min(7, v))
    if v ~= cur then
      mon = mutate()
      if Generation.isGen2(S) then
        mon.picSize = v
        mon.frontSize = nil
      else
        mon.frontSize = v
      end
    end
  end)
  row("Scale front", function(fx, fy_, fw, fh_)
    local cur = mon.battleScaleFront
    local shown = (cur ~= nil) and tostring(cur) or ""
    local v = field(S, App, "pk_scf", fx, fy_, 80 * s, fh_, shown, "1.0")
    if v ~= shown then
      mon = mutate()
      if v == "" then mon.battleScaleFront = nil
      else
        local n = tonumber(v)
        if n then mon.battleScaleFront = math.max(0.25, math.min(4, n)) end
      end
    end
  end)
  row("Scale back", function(fx, fy_, fw, fh_)
    local cur = mon.battleScaleBack
    local shown = (cur ~= nil) and tostring(cur) or ""
    local v = field(S, App, "pk_scb", fx, fy_, 80 * s, fh_, shown, "2.0")
    if v ~= shown then
      mon = mutate()
      if v == "" then mon.battleScaleBack = nil
      else
        local n = tonumber(v)
        if n then mon.battleScaleBack = math.max(0.25, math.min(4, n)) end
      end
    end
  end)
  if not gen2 then
    row("TrueColor", function(fx, fy_, fw, fh_)
      local on = mon.trueColor and true or false
      if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
        mon = mutate()
        mon.trueColor = not on
        if not mon.trueColor then mon.trueColor = nil end
        Preview.invalidate()
        App.markDirty()
      end
    end)
    row("L1 moves", function(fx, fy_, fw, fh_)
      local joined = table.concat(mon.level1Moves or {}, ",")
      local v = field(S, App, "pk_l1", fx, fy_, fw, fh_, joined, "TACKLE,GROWL")
      if v ~= joined then mon = mutate(); mon.level1Moves = parseMoveList(v) end
    end)
  else
    row("Gender %", function(fx, fy_, fw, fh_)
      -- genderRatio byte: 0 = always male, 254 = always female, 255 = genderless,
      -- 31 ~= 12.5% female (starter default).
      local cur = mon.genderRatio
      if cur == nil then cur = 31 end
      local v = numField(S, App, "pk_gender", fx, fy_, 80 * s, fh_, cur)
      v = math.max(0, math.min(255, v))
      if v ~= cur then mon = mutate(); mon.genderRatio = v end
    end)
    row("Egg steps", function(fx, fy_, fw, fh_)
      local cur = mon.eggSteps or 20
      local v = numField(S, App, "pk_eggs", fx, fy_, 80 * s, fh_, cur)
      if v ~= cur then mon = mutate(); mon.eggSteps = v end
    end)
    row("Egg groups", function(fx, fy_, fw, fh_)
      mon.eggGroups = mon.eggGroups or { "EGG_GROUND", "EGG_GROUND" }
      local g1 = mon.eggGroups[1] or "EGG_GROUND"
      local g2 = mon.eggGroups[2] or g1
      local half = math.floor((fw - 8 * s) / 2)
      ChoicePicker.field(S, {
        x = fx, y = fy_, w = half, h = fh_,
        current = g1, ids = EGG_GROUPS, title = "EGG GROUP 1",
        tooltip = "Pick an egg group from the list",
        onPick = function(id)
          if type(id) ~= "string" or id == "" then return end
          mon = mutate()
          mon.eggGroups = mon.eggGroups or {}
          mon.eggGroups[1] = id
          App.markDirty()
        end,
      })
      ChoicePicker.field(S, {
        x = fx + half + 8 * s, y = fy_, w = half, h = fh_,
        current = g2, ids = EGG_GROUPS, title = "EGG GROUP 2",
        tooltip = "Pick an egg group from the list",
        onPick = function(id)
          if type(id) ~= "string" or id == "" then return end
          mon = mutate()
          mon.eggGroups = mon.eggGroups or {}
          mon.eggGroups[2] = id
          App.markDirty()
        end,
      })
    end)
    row("Egg moves", function(fx, fy_, fw, fh_)
      local joined = table.concat(mon.eggMoves or {}, ",")
      local v = field(S, App, "pk_eggm", fx, fy_, fw, fh_, joined, "CHARM,FLAIL")
      if v ~= joined then mon = mutate(); mon.eggMoves = parseMoveList(v) end
    end)
    -- BaseData Item1 / Item2: rare then common (25% / 8% wild rolls in-cart).
    row("Rare item", function(fx, fy_, fw, fh_)
      local cur = (mon.items and mon.items[1]) or nil
      ItemPicker.field(S, {
        x = fx, y = fy_, w = fw - 70 * s, h = fh_,
        current = cur or "",
        emptyLabel = "(none)",
        title = "WILD RARE HELD ITEM (Item1)",
        tooltip = "Rare wild held item — BaseData Item1",
        onPick = function(id)
          mon = mutate()
          setWildItem(mon, 1, id)
          App.markDirty()
        end,
      })
      if Kit.button(fx + fw - 64 * s, fy_, 60 * s, fh_, "None", {
          kind = "ghost", font = "small",
          tooltip = "Clear rare slot (NO_ITEM)",
        }) then
        mon = mutate()
        setWildItem(mon, 1, nil)
        App.markDirty()
      end
    end)
    row("Common item", function(fx, fy_, fw, fh_)
      local cur = (mon.items and mon.items[2]) or nil
      ItemPicker.field(S, {
        x = fx, y = fy_, w = fw - 70 * s, h = fh_,
        current = cur or "",
        emptyLabel = "(none)",
        title = "WILD COMMON HELD ITEM (Item2)",
        tooltip = "Common wild held item — BaseData Item2",
        onPick = function(id)
          mon = mutate()
          setWildItem(mon, 2, id)
          App.markDirty()
        end,
      })
      if Kit.button(fx + fw - 64 * s, fy_, 60 * s, fh_, "None", {
          kind = "ghost", font = "small",
          tooltip = "Clear common slot (NO_ITEM)",
        }) then
        mon = mutate()
        setWildItem(mon, 2, nil)
        App.markDirty()
      end
    end)
    Kit.text("micro",
      "Wild held items for battle (rare 25% / common 8%). Trainer party items: Trainers tab.",
      formX, fy, PAL.faint)
    fy = fy + 16 * s
  end
  row("Cry", function(fx, fy_, fw, fh_)
    -- Prefer a custom file under audio.cries[species]; else mon.cry alias.
    local sid = S.pokemonId or mon.id
    local projCry = S.project and S.project.audio and S.project.audio.cries
      and S.project.audio.cries[sid]
    local filePath = (type(projCry) == "table" and type(projCry.file) == "string"
      and projCry.file) or ""
    local cur = mon.cry or ""
    local label = (filePath ~= "" and filePath)
      or (cur ~= "" and ("alias " .. cur))
      or "(species / pick)"
    local browseW = 90 * s
    local aliasW = 70 * s
    local gap = 4 * s
    local pathW = math.max(60 * s, fw - browseW - aliasW - gap * 2)
    Kit.text("micro", Kit.ellipsize("micro", label, pathW - 4 * s),
      fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + pathW + gap, fy_, aliasW, fh_, "Alias", {
        kind = "ghost", font = "small",
        tooltip = "Pick a species whose cry to reuse",
      }) then
      SpeciesPicker.open(S, {
        current = cur ~= "" and cur or sid,
        title = "CRY ALIAS",
        onPick = function(id)
          if type(id) ~= "string" or id == "" then return end
          mon = mutate()
          mon.cry = id
          if S.project.audio and S.project.audio.cries then
            S.project.audio.cries[sid] = nil
          end
          App.markDirty()
        end,
      })
    end
    if Kit.button(fx + pathW + gap + aliasW + gap, fy_, browseW, fh_, "Browse", {
        kind = "ghost", font = "small",
        tooltip = "Import a .wav / .ogg / .mp3 from your PC as this species' cry",
      }) then
      mon = mutate()
      local id = sid
      App.pickFile("Cry audio", "Audio|*.ogg;*.wav;*.mp3|All|*.*",
        function(picked)
          if not picked or picked == "" then return end
          local m = S.project.pokemon[id]
          if not m then return end
          S.project.audio = S.project.audio or {}
          S.project.audio.cries = S.project.audio.cries or {}
          App.importToMod(picked, nil, function(rel)
            local hadVanilla = S.data and S.data.audio and S.data.audio.cries
              and S.data.audio.cries[id] ~= nil
            S.project.audio.cries[id] = {
              file = rel,
              _isNew = not hadVanilla,
            }
            -- Species-keyed file is enough for Sound.playCry; clear alias.
            m.cry = nil
            App.markDirty()
            S.status = "Cry -> " .. tostring(rel)
          end)
        end)
    end
  end)
  if gen2 then
    -- Gold: palettes.pokemon[species] = { normal = {c1,c2}, shiny = {c1,c2} }
    local eid = S.pokemonId or mon.id
    local function livePalEntry()
      local proj = S.project.palettes and S.project.palettes.pokemon
        and S.project.palettes.pokemon[eid]
      if type(proj) == "table" then return proj end
      return Preview.gen2MonPaletteEntry(S, eid)
    end
    local entry = livePalEntry()
    Kit.text("micro",
      "GBC battle colors (4 shades). Click a swatch to edit.",
      formX, fy, PAL.faint)
    fy = fy + 16 * s
    if not entry then
      Kit.text("micro",
        "No palettes.pokemon row — Import / Link a Gold/Silver ROM cache with palettes.lua",
        formX, fy, PAL.danger or PAL.yellow)
      fy = fy + 18 * s
    else
      local function drawSlots(label, which)
        Kit.text("small", label, formX, fy + 6 * s, PAL.caption)
        local live = livePalEntry() or entry
        local pair = (which == "shiny") and (live.shiny or live.normal)
          or (live.normal or live.shiny)
        pair = cloneRgbRow(pair)
        local x0 = formX + labelW
        local sw = math.min(36 * s, math.floor((fieldW - 24 * s) / 4))
        for i = 1, 4 do
          local c = pair[i]
          love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
            (c[3] or 0) / 255, 1)
          love.graphics.rectangle("fill", x0, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
          love.graphics.setColor(1, 1, 1, 0.35)
          love.graphics.rectangle("line", x0, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
          love.graphics.setColor(1, 1, 1, 1)
          if Kit.press(x0, fy + 2 * s, sw, 24 * s) then
            local slot = i
            ColorWheel.open(S, {
              title = label .. " C" .. slot,
              color = c,
              onChange = function(rgb)
                local e = ensureGen2MonPalette(S, eid, App)
                e[which] = e[which] or cloneRgbRow(pair)
                e[which][slot] = {
                  math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
                }
                Preview.invalidate()
                App.markDirty()
              end,
              onApply = function(rgb)
                local e = ensureGen2MonPalette(S, eid, App)
                e[which] = e[which] or cloneRgbRow(pair)
                e[which][slot] = {
                  math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
                }
                Preview.invalidate()
                App.markDirty()
              end,
            })
          end
          x0 = x0 + sw + 8 * s
        end
        fy = fy + fh + 8 * s
      end
      drawSlots("Normal", "normal")
      drawSlots("Shiny", "shiny")
      if S.project.palettes and S.project.palettes.pokemon
          and S.project.palettes.pokemon[eid] then
        if Kit.button(formX + labelW, fy, 120 * s, fh, "Revert colors", {
            kind = "ghost", font = "small",
            tooltip = "Drop mod palette override for this species",
          }) then
          S.project.palettes.pokemon[eid] = nil
          Preview.invalidate()
          App.markDirty()
        end
        fy = fy + fh + 8 * s
      end
    end
  elseif mon.trueColor then
    row("Palette", function(fx, fy_, fw, fh_)
      Kit.text("small", "(ignored — TrueColor)", fx, fy_ + 6 * s, PAL.faint)
    end)
  else
    row("Palette", function(fx, fy_, fw, fh_)
      local eid = S.pokemonId or mon.id
      PalettePicker.row(S, {
        x = fx, y = fy_, w = fw, h = fh_,
        current = mon.palette or "",
        effective = Preview.monPaletteName(S, mon, eid),
        emptyLabel = "(pack default)",
        clearLabel = "(pack default / MEWMON)",
        allowClear = true,
        title = "POKEMON SPRITE / ICON PALETTE",
        tooltip = "SGB palette for battle sprites and icon preview",
        onPick = function(id)
          mon = mutate()
          mon.palette = id
          Preview.invalidate()
          App.markDirty()
        end,
        owner = {
          kind = "pokemon",
          entityId = eid,
          entityLabel = mon.name or eid,
          assign = function(id)
            mon = mutate()
            mon.palette = id
            Preview.invalidate()
            App.markDirty()
          end,
        },
      })
    end)
    do
      local entityId = S.pokemonId or mon.id
      fy = PaletteEdit.drawColorRows(S, {
        kind = "pokemon",
        entityId = entityId,
        entityLabel = mon.name or entityId,
        paletteId = Preview.monPaletteName(S, mon, entityId),
        assign = function(id)
          mon = mutate()
          mon.palette = id
          Preview.invalidate()
          App.markDirty()
        end,
        App = App,
        x = formX, y = fy, labelW = labelW, fieldW = fieldW, fh = fh,
        fieldPrefix = "pk_pal_c",
      })
    end
  end
  row("Icon", function(fx, fy_, fw, fh_)
    local _, resolvedName = Preview.pokemonIcon(S, mon, S.pokemonId)
    local cur = iconNameOf(mon)
    if cur == "" and Generation.isGen2(S) then
      local icons = S.data and (S.data.gen2Icons or S.data.icons)
      local sid = S.pokemonId or mon.id
      if icons and icons.species and icons.species[sid] then
        cur = icons.species[sid]
      end
    end
    local label
    if type(mon.icon) == "table" and mon.icon.image then
      label = "custom"
    elseif cur ~= "" then
      label = cur
    else
      label = (resolvedName and (resolvedName .. " (dex)") or "(default)")
    end
    local names = iconList(S)
    ChoicePicker.field(S, {
      x = fx, y = fy_, w = math.max(80 * s, fw - 100 * s), h = fh_,
      current = (type(mon.icon) == "table" and mon.icon.image) and "" or cur,
      ids = names,
      emptyLabel = label,
      allowClear = true,
      clearLabel = "(default)",
      title = "PARTY ICON",
      kind = "ghost",
      tooltip = "Pick a party icon from the list",
      onPick = function(id)
        mon = mutate()
        if type(id) ~= "string" or id == "" then
          mon.icon = nil
        else
          mon.icon = id
        end
        Preview.invalidate()
        App.markDirty()
      end,
    })
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "PNG", {
        kind = "ghost", tooltip = "Import a custom party icon PNG",
      }) then
      mon = mutate()
      local id = mon.id
      App.pickFile("Party icon PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local m = S.project.pokemon[id]
          if not m then return end
          App.importToMod(picked, nil, function(rel)
            m.icon = { image = rel, frames = 2 }
          end)
        end)
    end
  end)
  do
    -- Custom PNG icons can opt out of SGB remap independently of battle TrueColor.
    -- Gold skips SGB remap for icons, so this toggle is Gen1-only.
    local customIcon = (not gen2)
      and type(mon.icon) == "table" and type(mon.icon.image) == "string"
    if customIcon then
      row("Icon TrueColor", function(fx, fy_, fw, fh_)
        local on = mon.icon.trueColor and true or false
        if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
          mon = mutate()
          if type(mon.icon) ~= "table" then
            mon.icon = { image = "", frames = 2 }
          end
          mon.icon.trueColor = not on
          if not mon.icon.trueColor then mon.icon.trueColor = nil end
          Preview.invalidate()
          App.markDirty()
        end
      end)
    end
  end
  do
    local ids = formIdList(mon)
    Kit.text("small", "Forms", formX, fy + 6 * s, PAL.caption)
    local fx = formX + labelW
    local x = fx
    local rowH = 22 * s
    local placed = false
    local function placeChip(label, selected, color, onClick)
      placed = true
      local cw = math.max(22 * s, Kit.textWidth("micro", label) + 12 * s)
      if x + cw > fx + fieldW then
        x = fx
        fy = fy + rowH
      end
      if Kit.chip(x, fy, cw, 20 * s, label, selected, color) then
        onClick()
      end
      x = x + cw + 3 * s
    end
    if mon.id ~= "UNOWN" and #ids > 0 then
      placeChip("Base", formId == nil, PAL.blue, function()
        S.pokemonFormId = nil
        S.pokemonUnownLetter = nil
      end)
    end
    for _, id in ipairs(ids) do
      placeChip(id, formId == id, PAL.green, function()
        S.pokemonFormId = id
        S.pokemonUnownLetter = id
      end)
    end
    if placed then
      fy = fy + rowH + 4 * s
    else
      fy = fy + 4 * s
    end
    local typed = Kit.textfield("pk_form_new", fx, fy,
      fieldW, fh, S.pokemonNewFormId or "", "ALOLAN")
    S.pokemonNewFormId = typed
    fy = fy + fh + 4 * s
    local addId = normalizeFormId(typed)
    if Kit.button(fx, fy, 64 * s, fh, "Add", {
        kind = "good",
        tooltip = "Add a named form with its own front / back / anim",
      }) then
      if addId then
        local exists = false
        for _, id in ipairs(ids) do
          if id == addId then exists = true; break end
        end
        if not exists then
          mon = mutate()
          local bucket = formBucketKey(mon, addId)
          mon[bucket] = mon[bucket] or {}
          mon[bucket][addId] = mon[bucket][addId] or {}
          App.markDirty()
        end
        S.pokemonFormId = addId
        S.pokemonUnownLetter = addId
        S.pokemonNewFormId = ""
      end
    end
    if formId and not isLockedForm(mon, formId) then
      if Kit.button(fx + 70 * s, fy, 64 * s, fh, "Del", {
          kind = "danger",
          tooltip = "Remove this form (Unown A-Z stay)",
        }) then
        mon = mutate()
        for _, key in ipairs({ "letters", "forms" }) do
          if type(mon[key]) == "table" then
            mon[key][formId] = nil
            if next(mon[key]) == nil then mon[key] = nil end
          end
        end
        S.pokemonFormId = (mon.id == "UNOWN") and "A" or nil
        S.pokemonUnownLetter = S.pokemonFormId
        App.markDirty()
      end
    end
    fy = fy + fh + 8 * s
  end
  local frontLabel = formId and ("Front " .. formId) or "Front PNG"
  row(frontLabel, function(fx, fy_, fw, fh_)
    local owned = formId and formRecord(mon, formId)
    local path = owned and owned.spriteFront or (not formId and mon.spriteFront) or ""
    if path == "" then
      local vp = formSpritePath(S, mon, "spriteFront", formId)
      path = vp and ("(vanilla) " .. vp) or ""
    end
    Kit.text("micro", path ~= "" and path or "(none)", fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 90 * s, fy_, 90 * s, fh_, "Browse", {
        kind = "ghost",
        tooltip = "Copies your file into assets/ with the same name",
      }) then
      mon = mutate()
      local id = mon.id
      local L = formId
      App.pickFile("Front sprite PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local m = S.project.pokemon[id]
          if not m then return end
          App.importToMod(picked, nil, function(rel)
            assignFormSprite(m, L, "spriteFront", rel)
          end)
        end)
    end
  end)
  local backLabel = formId and ("Back " .. formId) or "Back PNG"
  row(backLabel, function(fx, fy_, fw, fh_)
    local owned = formId and formRecord(mon, formId)
    local path = owned and owned.spriteBack or (not formId and mon.spriteBack) or ""
    if path == "" then
      local vp = formSpritePath(S, mon, "spriteBack", formId)
      path = vp and ("(vanilla) " .. vp) or ""
    end
    Kit.text("micro", path ~= "" and path or "(none)", fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 90 * s, fy_, 90 * s, fh_, "Browse", {
        kind = "ghost",
        tooltip = "Copies your file into assets/ with the same name",
      }) then
      mon = mutate()
      local id = mon.id
      local L = formId
      App.pickFile("Back sprite PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local m = S.project.pokemon[id]
          if not m then return end
          App.importToMod(picked, nil, function(rel)
            assignFormSprite(m, L, "spriteBack", rel)
          end)
        end)
    end
  end)
  if anim or Generation.isCrystal(S) then
    local animLabel = formId and ("Anim " .. formId) or "Anim sheet"
    row(animLabel, function(fx, fy_, fw, fh_)
      local rec = formId and formRecord(mon, formId)
      local sheet = rec and rec.anim and rec.anim.sheet
        or (not formId and mon.anim and mon.anim.sheet) or ""
      if sheet == "" then
        local va = formAnim(S, mon, formId)
        sheet = va and va.sheet and ("(vanilla) " .. va.sheet) or ""
      end
      Kit.text("micro", sheet ~= "" and sheet or "(none)", fx, fy_ + 8 * s, PAL.muted)
      if Kit.button(fx + fw - 90 * s, fy_, 90 * s, fh_, "Browse", {
          kind = "ghost",
          tooltip = "Crystal battle anim: one column of full front pics",
        }) then
        mon = mutate()
        local id = mon.id
        local L = formId
        App.pickFile("Anim sheet PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
          function(picked)
            local m = S.project.pokemon[id]
            if not m then return end
            App.importToMod(picked, nil, function(rel)
              assignFormAnimSheet(m, L, rel)
            end)
          end)
      end
    end)
  end
  return math.max(fy, previewBottom), mon
end

local function drawLearnset(S, mon, mutate, App, formX, fy, formW, fh, s)
  local gen2 = Generation.isGen2(S)
  local key = gen2 and "levelMoves" or "learnset"
  Kit.text("micro",
    gen2 and "Level-up moves (levelMoves). Add rows below."
      or "Level-up moves (level, move id). Add rows below.",
    formX, fy, PAL.muted)
  fy = fy + 20 * s
  if gen2 and not mon.levelMoves and mon.learnset then
    mon.levelMoves = mon.learnset
  end
  mon[key] = mon[key] or {}
  for i, row in ipairs(mon[key]) do
    local lvl = row.level or 1
    local mv = row.move or "TACKLE"
    local vLvl = numField(S, App, "pk_ls_l_" .. i, formX, fy, 60 * s, fh, lvl)
    local vMv = field(S, App, "pk_ls_m_" .. i, formX + 70 * s, fy,
      formW - 160 * s, fh, mv, "MOVE",
      function() return Autocomplete.moveIds(S) end)
    vMv = vMv:upper():gsub("%s+", "_")
    if vLvl ~= lvl or vMv ~= mv then
      mon = mutate()
      mon[key][i] = { level = math.max(1, math.min(100, vLvl)), move = vMv }
    end
    if Kit.button(formX + formW - 70 * s, fy, 60 * s, fh, "Del",
        { kind = "danger" }) then
      mon = mutate()
      table.remove(mon[key], i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(formX, fy, 140 * s, fh, "+ Learn row", { kind = "good" }) then
    mon = mutate()
    mon[key] = mon[key] or {}
    mon[key][#mon[key] + 1] = { level = 10, move = "TACKLE" }
    App.markDirty()
  end
  return fy + fh + 8 * s, mon
end

local function applyEvoMethod(evo, method, gen2)
  evo.method = method
  if not gen2 then return end
  if method == "EVOLVE_HAPPINESS" then
    evo.time = evo.time or "ANYTIME"
    evo.level, evo.item, evo.comparison = nil, nil, nil
  elseif method == "EVOLVE_STAT" then
    evo.comparison = evo.comparison or "ATK_LT_DEF"
    evo.level = evo.level or 20
    evo.time, evo.item = nil, nil
  elseif method == "EVOLVE_ITEM" then
    evo.item = evo.item or "MOON_STONE"
    evo.level, evo.time, evo.comparison = nil, nil, nil
  elseif method == "EVOLVE_TRADE" then
    evo.level, evo.time, evo.comparison = nil, nil, nil
  else
    evo.level = evo.level or 16
    evo.item, evo.time, evo.comparison = nil, nil, nil
  end
end

local function drawEvolutions(S, mon, mutate, App, formX, fy, formW, fh, s)
  local gen2 = Generation.isGen2(S)
  local methods = gen2 and EVO_METHODS_GEN2 or EVO_METHODS
  local intoKey = gen2 and "into" or "species"
  Kit.text("micro",
    gen2
      and "Pick method, species, and item / time / stat from the lists."
      or "Pick method, species, and item from the lists. Level evolutions still use a number.",
    formX, fy, PAL.muted)
  fy = fy + 20 * s
  mon.evolutions = mon.evolutions or {}
  for i, evo in ipairs(mon.evolutions) do
    local method = evo.method or (gen2 and "EVOLVE_LEVEL" or "LEVEL")
    if gen2 then method = normalizeEvoMethod(method) end
    local methodW = gen2 and 150 * s or 100 * s
    local row = i
    ChoicePicker.field(S, {
      x = formX, y = fy, w = methodW, h = fh,
      current = method,
      ids = methods,
      title = "EVOLUTION METHOD",
      tooltip = "Pick how this species evolves",
      onPick = function(id)
        if type(id) ~= "string" or id == "" then return end
        mon = mutate()
        applyEvoMethod(mon.evolutions[row], id, gen2)
        App.markDirty()
      end,
    })
    local curInto = evo[intoKey] or evo.into or evo.species or ""
    SpeciesPicker.field(S, {
      x = formX + methodW + 10 * s, y = fy, w = 130 * s, h = fh,
      current = curInto,
      emptyLabel = "SPECIES",
      title = "EVOLVES INTO",
      tooltip = "Species this evolution becomes",
      onPick = function(id)
        mon = mutate()
        mon.evolutions[row][intoKey] = id
        if gen2 then mon.evolutions[row].species = nil
        else mon.evolutions[row].into = nil end
        App.markDirty()
      end,
    })
    local paramX = formX + methodW + 150 * s
    local paramW = math.max(80 * s, formW - (paramX - formX) - 78 * s)
    if method == "LEVEL" or method == "EVOLVE_LEVEL"
        or method == "STAT" or method == "EVOLVE_STAT" then
      local lvl = numField(S, App, "pk_ev_lv_" .. i, paramX, fy,
        60 * s, fh, evo.level or 16)
      if lvl ~= (evo.level or 16) then
        mon = mutate(); mon.evolutions[i].level = lvl
      end
      if gen2 and method == "EVOLVE_STAT" then
        ChoicePicker.field(S, {
          x = paramX + 70 * s, y = fy, w = math.max(80 * s, paramW - 70 * s), h = fh,
          current = evo.comparison or "ATK_LT_DEF",
          ids = EVO_COMPARISON,
          title = "STAT COMPARISON",
          tooltip = "Attack vs Defense check at this level",
          kind = "ghost",
          onPick = function(id)
            if type(id) ~= "string" or id == "" then return end
            mon = mutate()
            mon.evolutions[row].comparison = id
            App.markDirty()
          end,
        })
      end
    elseif method == "ITEM" or method == "EVOLVE_ITEM" then
      ItemPicker.field(S, {
        x = paramX, y = fy, w = paramW, h = fh,
        current = evo.item or "",
        emptyLabel = "ITEM",
        title = "EVOLUTION ITEM",
        tooltip = "Stone or item that triggers this evolution",
        onPick = function(id)
          if type(id) ~= "string" or id == "" then return end
          mon = mutate()
          mon.evolutions[row].item = id
          App.markDirty()
        end,
      })
    elseif gen2 and method == "EVOLVE_HAPPINESS" then
      ChoicePicker.field(S, {
        x = paramX, y = fy, w = math.min(paramW, 130 * s), h = fh,
        current = evo.time or "ANYTIME",
        ids = EVO_TIME,
        title = "TIME OF DAY",
        tooltip = "When happiness evolution can happen",
        kind = "ghost",
        onPick = function(id)
          if type(id) ~= "string" or id == "" then return end
          mon = mutate()
          mon.evolutions[row].time = id
          App.markDirty()
        end,
      })
    end
    if Kit.button(formX + formW - 70 * s, fy, 60 * s, fh, "Del", {
        kind = "danger" }) then
      mon = mutate()
      table.remove(mon.evolutions, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(formX, fy, 140 * s, fh, "+ Evolution", { kind = "good" }) then
    mon = mutate()
    mon.evolutions = mon.evolutions or {}
    local row = gen2
      and { method = "EVOLVE_LEVEL", level = 16, into = "BAYLEEF" }
      or { method = "LEVEL", level = 16, species = "ABRA" }
    mon.evolutions[#mon.evolutions + 1] = row
    App.markDirty()
  end
  return fy + fh + 8 * s, mon
end

local function tmhmSlotLabel(S, index)
  index = tonumber(index) or 0
  if index < 1 then return "TM/HM" end
  if index <= 50 then return string.format("TM%02d", index) end
  local hm = index - 50
  if Generation.isGen2(S) then
    if hm <= 7 then return string.format("HM%02d", hm) end
    return string.format("TUTOR%d", hm - 7)
  end
  return string.format("HM%02d", hm)
end

-- Move id -> "TM29" / "HM05" from the ROM TMHMMoves table and item records.
local function tmhmCatalog(S)
  local byMove, ids = {}, {}
  local function add(move, label)
    if type(move) ~= "string" or move == "" then return end
    if not byMove[move] then
      ids[#ids + 1] = move
    end
    byMove[move] = byMove[move] or label or "TM/HM"
  end
  local list = S.data and S.data.pokemon and S.data.pokemon.tmhmMoves
  if type(list) == "table" then
    for i, move in ipairs(list) do
      if type(move) == "string" then add(move, tmhmSlotLabel(S, i)) end
    end
  end
  local function consider(items)
    if type(items) ~= "table" then return end
    for id, rec in pairs(items) do
      if type(rec) == "table" then
        local move = rec.teaches
        if not move and type(rec.machine) == "table" then
          move = rec.machine.move
        end
        local label = rec.tmLabel
        if not label and type(rec.machine) == "table" then
          label = string.format("%s%02d",
            rec.machine.kind or "TM", rec.machine.number or 0)
        end
        if not label then
          local sid = tostring(id)
          if sid:sub(1, 3) == "HM_" or sid:sub(1, 3) == "TM_" then
            label = sid:gsub("_", " ")
          end
        end
        add(move, label)
      end
    end
  end
  consider(S.data and S.data.items)
  consider(S.project and S.project.items)
  table.sort(ids)
  return byMove, ids
end

local function drawTmhm(S, mon, mutate, App, formX, fy, formW, fh, s)
  Kit.text("micro", "TM/HM compatibility. Add a machine move the same way as Learnset.",
    formX, fy, PAL.muted)
  fy = fy + 20 * s
  local labels, suggest = tmhmCatalog(S)
  if not suggest or #suggest == 0 then
    suggest = Autocomplete.moveIds(S)
  end
  mon.tmhm = mon.tmhm or {}
  for i, mv in ipairs(mon.tmhm) do
    mv = tostring(mv or "")
    local tag = labels[mv] or "TM/HM"
    Kit.text("micro", tag, formX, fy + 8 * s, PAL.caption)
    local vMv = field(S, App, "pk_tm_" .. i, formX + 70 * s, fy,
      formW - 160 * s, fh, mv, "MOVE",
      function() return suggest end)
    vMv = vMv:upper():gsub("%s+", "_")
    if vMv ~= mv then
      mon = mutate()
      mon.tmhm[i] = vMv
    end
    if Kit.button(formX + formW - 70 * s, fy, 60 * s, fh, "Del",
        { kind = "danger" }) then
      mon = mutate()
      table.remove(mon.tmhm, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(formX, fy, 140 * s, fh, "+ TM/HM", { kind = "good" }) then
    mon = mutate()
    mon.tmhm = mon.tmhm or {}
    local have = {}
    for _, id in ipairs(mon.tmhm) do have[id] = true end
    local add = "FLASH"
    for _, id in ipairs(suggest or {}) do
      if not have[id] then add = id; break end
    end
    mon.tmhm[#mon.tmhm + 1] = add
    App.markDirty()
  end
  fy = fy + fh + 8 * s
  Kit.text("micro", string.format("%d TM/HM moves", #(mon.tmhm or {})),
    formX, fy, PAL.faint)
  return fy + 24 * s, mon
end

local function dexDataEntry(S, id)
  local dex = S.data and (S.data.gen2Pokedex or S.data.pokedex)
  local entries = dex and dex.entries
  return (entries and entries[id]) or {}
end

local function ensureDexOwned(S, id, App)
  State.ensureProjectFields(S.project)
  S.project.pokedex = S.project.pokedex or {}
  if not S.project.pokedex[id] then
    local src = dexDataEntry(S, id)
    local copy = {}
    for k, v in pairs(src) do copy[k] = v end
    copy.id = copy.id or id
    S.project.pokedex[id] = copy
    if App then App.markDirty() end
  end
  return S.project.pokedex[id]
end

local function drawDex(S, mon, mutate, App, formX, fy, formW, labelW, fh, s)
  local fieldW = formW - labelW - 20 * s
  local function row(label, body)
    Kit.text("small", label, formX, fy + 6 * s, PAL.caption)
    body(formX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  if Generation.isGen2(S) then
    Kit.text("micro", "Gold dex lives in gen2Pokedex.entries (not on the species record).",
      formX, fy, PAL.muted)
    fy = fy + 20 * s
    local id = mon.id
    local owned = S.project.pokedex and S.project.pokedex[id] ~= nil
    local de = owned and S.project.pokedex[id] or dexDataEntry(S, id)
    local function mutateDex()
      return ensureDexOwned(S, id, App)
    end
    row("Dex #", function(fx, fy_, fw, fh_)
      local cur = de.dex or 0
      local v = numField(S, App, "pk_ddex", fx, fy_, 80 * s, fh_, cur)
      if v ~= cur then de = mutateDex(); de.dex = v end
      Kit.text("micro", "National order (used by NEW/OLD/A-Z list + printed #). Extra species start at 252.",
        fx + 90 * s, fy_ + 8 * s, PAL.faint)
    end)
    row("Kind", function(fx, fy_, fw, fh_)
      local v = field(S, App, "pk_dk", fx, fy_, fw, fh_, de.kind or "", "LEAF")
      if v ~= (de.kind or "") then de = mutateDex(); de.kind = v end
    end)
    row("Height", function(fx, fy_, fw, fh_)
      local cur = de.height or 0
      local v = numField(S, App, "pk_dht", fx, fy_, 80 * s, fh_, cur)
      if v ~= cur then de = mutateDex(); de.height = v end
      Kit.text("micro", "packed ft/in int", fx + 90 * s, fy_ + 8 * s, PAL.faint)
    end)
    row("Weight", function(fx, fy_, fw, fh_)
      local cur = de.weight or 0
      local v = numField(S, App, "pk_dw", fx, fy_, 80 * s, fh_, cur)
      if v ~= cur then de = mutateDex(); de.weight = v end
    end)
    row("Text", function(fx, fy_, fw, fh_)
      local cur = tostring(de.text or "")
      local shown = cur:gsub("\n", "\\n"):gsub("<NEXT>", "\\n")
      local v = field(S, App, "pk_dbody", fx, fy_, fw, fh_, shown, "Dex text…")
      local decoded = v:gsub("\\n", "<NEXT>")
      if decoded ~= cur then de = mutateDex(); de.text = decoded end
    end)
    row("Text 2", function(fx, fy_, fw, fh_)
      local cur = tostring(de.text2 or "")
      local shown = cur:gsub("\n", "\\n"):gsub("<NEXT>", "\\n")
      local v = field(S, App, "pk_dbody2", fx, fy_, fw, fh_, shown, "Dex text 2…")
      local decoded = v:gsub("\\n", "<NEXT>")
      if decoded ~= cur then de = mutateDex(); de.text2 = decoded end
    end)
    if owned and Kit.button(formX, fy, 120 * s, fh, "Revert dex", { kind = "danger" }) then
      S.project.pokedex[id] = nil
      App.markDirty()
    end
    fy = fy + fh + 8 * s
    return fy, mon
  end

  mon.dexEntry = mon.dexEntry or {}
  local de = mon.dexEntry
  row("Kind", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_dk", fx, fy_, fw, fh_, de.kind or "", "MOUSE")
    if v ~= (de.kind or "") then mon = mutate(); mon.dexEntry.kind = v end
  end)
  row("Height ft/in", function(fx, fy_, fw, fh_)
    local ft = numField(S, App, "pk_dft", fx, fy_, 50 * s, fh_, de.heightFt or 0)
    local inch = numField(S, App, "pk_din", fx + 60 * s, fy_, 50 * s, fh_,
      de.heightIn or 0)
    if ft ~= (de.heightFt or 0) or inch ~= (de.heightIn or 0) then
      mon = mutate()
      mon.dexEntry.heightFt = ft
      mon.dexEntry.heightIn = math.max(0, math.min(11, inch))
    end
  end)
  row("Weight", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_dw", fx, fy_, 80 * s, fh_, de.weight or 0)
    if v ~= (de.weight or 0) then mon = mutate(); mon.dexEntry.weight = v end
  end)
  row("Text id", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_dt", fx, fy_, fw, fh_, de.text or "", "_FooDexEntry")
    if v ~= (de.text or "") then
      mon = mutate()
      mon.dexEntry.text = v
    end
  end)
  row("Dex body", function(fx, fy_, fw, fh_)
    local tid = de.text
    local body = ""
    if tid and S.project.text and S.project.text[tid] then
      body = S.project.text[tid]
    elseif tid and S.data and S.data.text then
      body = S.data.text[tid] or ""
    end
    local shown = body:gsub("\n", "\\n"):gsub("\f", "\\f")
    local v = field(S, App, "pk_dbody", fx, fy_, fw, fh_, shown, "Dex text…")
    local decoded = v:gsub("\\n", "\n"):gsub("\\f", "\f")
    if tid and tid ~= "" and decoded ~= body then
      mon = mutate()
      if not mon.dexEntry.text or mon.dexEntry.text == "" then
        mon.dexEntry.text = "_" .. mon.id:sub(1, 1)
          .. mon.id:sub(2):lower():gsub("_(%w)", function(c) return c:upper() end)
          .. "DexEntry"
      end
      S.project.text[mon.dexEntry.text] = decoded
      App.markDirty()
    end
  end)
  return fy, mon
end

function Pokemon.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end

  local listW = math.min(220 * s, w * 0.28)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s

  Kit.caption(x, y, "SPECIES")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "pokemonQuery", x, qy, listW, qh, "search species...")
  if qChanged then S.pokemonListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allSpeciesIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local mon = S.project.pokemon[id]
        or (S.data.pokemon and S.data.pokemon[id])
      local name = mon and tostring(mon.name or "") or ""
      if id:lower():find(ql, 1, true) or name:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local rowH = 30 * s
  local thumb = 24 * s
  local listInnerX, listInnerY = x + 8 * s, listY + 8 * s
  local listInnerW, listInnerH = listW - 16 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(listInnerW)
  local perPage = math.max(1, math.floor(listInnerH / (rowH + 4 * s)))
  S.pokemonListOffset = Kit.scroll(listInnerX, listInnerY, listInnerW, listInnerH,
    S.pokemonListOffset or 0, #ids, perPage)
  local pokeNav = RegList.bindNav(S, ids, {
    selKey = "pokemonId", offsetKey = "pokemonListOffset", perPage = perPage,
  })
  Kit.pushClip(listInnerX, listInnerY, rowW, listInnerH)
  local ry = listInnerY
  for i = (S.pokemonListOffset or 0) + 1,
      math.min(#ids, (S.pokemonListOffset or 0) + perPage) do
    local id = ids[i]
    local rowMon = S.project.pokemon[id]
      or (S.data.pokemon and S.data.pokemon[id])
    local owned = S.project.pokemon[id] ~= nil
    if Kit.row(listInnerX, ry, rowW, rowH, S.pokemonId == id, PAL.green) then
      pokeNav.activate()
      S.pokemonId = id
    end
    Preview.drawPokemonIcon(S, rowMon, listInnerX + 4 * s,
      ry + (rowH - thumb) / 2, thumb, thumb, id)
    local textX = listInnerX + 8 * s + thumb
    Kit.text("mono", Kit.ellipsize("mono", id, rowW - (textX - listInnerX) - 4 * s),
      textX, ry + 7 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 4 * s
  end
  Kit.popClip()
  Kit.scrollbar(listInnerX, listInnerY, listInnerW, listInnerH,
    S.pokemonListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New species", {
      kind = "good",
      tooltip = Generation.isGen2(S)
        and "Adds a species past #251 with no ROM index byte (dex overflow)"
        or "Register a new species in this mod",
    }) then
    local nid = "NEW_MON"
    local n = 1
    while S.project.pokemon[nid] or (S.data.pokemon and S.data.pokemon[nid]) do
      n = n + 1
      nid = "NEW_MON_" .. n
    end
    local rec = defaultMon(nid, S)
    S.project.pokemon[nid] = rec
    if Generation.isGen2(S) then
      S.project.pokedex = S.project.pokedex or {}
      S.project.pokedex[nid] = {
        id = nid,
        dex = rec.dex,
        kind = "???",
        height = 0,
        weight = 10,
        text = "",
      }
    end
    S.pokemonId = nid
    App.markDirty()
  end

  local mon, owned = resolveMon(S, S.pokemonId)
  if not mon then
    local first = ids[1]
    S.pokemonId = first
    mon, owned = resolveMon(S, first)
  end
  if not mon then
    Kit.emptyBox(formX, listY, formW, listH, "No species in data — import a ROM cache")
    return
  end

  local function mutate()
    mon = ensureOwned(S, S.pokemonId)
    owned = true
    return mon
  end

  Kit.caption(formX, y, "EDIT  " .. (mon.id or "?") .. (owned and "" or "  (vanilla)"))
  local secY = y + 22 * s
  local sx = formX
  S.pokemonSection = S.pokemonSection or "basics"
  for _, sec in ipairs(SECTIONS) do
    local on = S.pokemonSection == sec.id
    local bw = Kit.textWidth("micro", sec.label) + 18 * s
    if Kit.chip(sx, secY, bw, 26 * s, sec.label, on, PAL.green) then
      S.pokemonSection = sec.id
    end
    sx = sx + bw + 4 * s
  end

  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = 44 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "pokemonFormScroll",
    tostring(S.pokemonId) .. "|" .. tostring(S.pokemonSection))
  local fy, view = FormPane.begin(S, "pokemonFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local labelW = 110 * s
  local fh = 30 * s

  if S.pokemonSection == "basics" then
    fy, mon = drawBasics(S, mon, mutate, App, viewX, fy, viewW, labelW, fh, s)
  elseif S.pokemonSection == "learnset" then
    fy, mon = drawLearnset(S, mon, mutate, App, viewX, fy, viewW, fh, s)
  elseif S.pokemonSection == "evolutions" then
    fy, mon = drawEvolutions(S, mon, mutate, App, viewX, fy, viewW, fh, s)
  elseif S.pokemonSection == "trees" then
    fy = EvoBreedTrees.draw(S, S.pokemonId, viewX, fy, viewW)
  elseif S.pokemonSection == "tmhm" then
    fy, mon = drawTmhm(S, mon, mutate, App, viewX, fy, viewW, fh, s)
  elseif S.pokemonSection == "dex" then
    fy, mon = drawDex(S, mon, mutate, App, viewX, fy, viewW, labelW, fh, s)
  end
  FormPane.finish(S, "pokemonFormScroll", contentTop, fy, view)

  local btnY = listY + listH - 40 * s
  local bx = formX + 12 * s
  if owned then
    if Kit.button(bx, btnY, 120 * s, 32 * s, "Revert", { kind = "ghost" }) then
      S.project.pokemon[mon.id] = nil
      S.pokemonId = mon.id
      App.markDirty()
    end
    bx = bx + 128 * s
  end
  if Kit.button(bx, btnY, 120 * s, 32 * s,
      "Delete", { kind = "danger",
        tooltip = "Remove from this mod (Save emits content:remove)" }) then
    State.markDeleted(S.project, "pokemon", mon.id, mon,
      S.data and S.data.pokemon)
    if S.project.pokedex then S.project.pokedex[mon.id] = nil end
    local ids = allSpeciesIds(S)
    S.pokemonId = ids[1]
    App.markDirty()
  end
end

return Pokemon
