-- UI tab: title/splash branding, boot screen ids, in-game menu chrome,
-- dialogue theme, fonts, engine strings, town map, and badge icons.
-- Gen1 writes field.* via project.title / intro / theme / townMap / boot /
-- menuGfx; Gold (field gated) writes data.title / gen2Intro / landmarks /
-- gen2MenuGfx / gen2BootScreens / gen2Diploma.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local UiPreview = require("UiPreview")
local UiMenus = require("UiMenus")
local Generation = require("Generation")
local ChoicePicker = require("ChoicePicker")
local SpeciesPicker = require("SpeciesPicker")
local ColorWheel = require("ColorWheel")
local PAL = Theme.PAL

local Ui = {}

local MODES_GEN1 = {
  { id = "title", label = "Title",
    tip = "Logo, version ribbon, copyright, music, cycle species" },
  { id = "intro", label = "Intro",
    tip = "Studio splash, skip intro, Game Freak / fight / Yellow cinema art" },
  { id = "oak", label = "Oak",
    tip = "New-game Oak speech: pics, music, demo species, lines" },
  { id = "credits", label = "Credits",
    tip = "End-roll screens, silhouette mons, THE END art" },
  { id = "minigames", label = "Minigames",
    tip = "Slot machine and Yellow Surfing Pikachu (Pikachu's Beach)" },
  { id = "boot", label = "Boot screens",
    tip = "splash / title / newGame screen registry ids" },
  { id = "menus", label = "Menus",
    tip = "Battle HUD, overworld FX, emotes, slot machine art" },
  { id = "theme", label = "Theme",
    tip = "Cursor glyphs and textBox / choiceBox geometry" },
  { id = "fonts", label = "Fonts",
    tip = "Font page sheets (image, base, glyphsPerRow)" },
  { id = "strings", label = "Strings",
    tip = "Engine Strings() source → override catalog" },
  { id = "townmap", label = "Town map",
    tip = "Town map grid size, locations, background" },
  { id = "badges", label = "Badges",
    tip = "Badge ids with optional icon paths" },
}

local MODES_GEN2 = {
  { id = "title", label = "Title",
    tip = "Gold/Crystal title art: screen, mascot, copyright" },
  { id = "intro", label = "Intro",
    tip = "Gold/Silver water-grass-fire cinema, or Crystal Unown/Suicune sheets" },
  { id = "oak", label = "Oak",
    tip = "New-game Oak speech: pics, music, Marill/Wooper, lines" },
  { id = "credits", label = "Credits",
    tip = "Staff roll names, THE END / banner sheets" },
  { id = "minigames", label = "Minigames",
    tip = "Slots, card flip, Unown puzzle: text, art, music, live preview" },
  { id = "boot", label = "Boot screens",
    tip = "Gen2CopyrightSplash → … → Gen2TitleState / Gen2OakSpeech ids" },
  { id = "menus", label = "Menus",
    tip = "Battle HUD, pack, Pokédex, naming, emotes, slots, diploma…" },
  { id = "fonts", label = "Fonts",
    tip = "Font page sheets (image, base, glyphsPerRow)" },
  { id = "strings", label = "Strings",
    tip = "Engine Strings() source → override catalog" },
  { id = "townmap", label = "Town map",
    tip = "Pokegear landmarks (name, x, y, index)" },
  { id = "badges", label = "Badges",
    tip = "Trainer card badge / leader sheet paths" },
}

local BOOT_SCREEN_DEFAULTS = {
  splash = "IntroMovie", title = "TitleState", newGame = "OakSpeech",
}

local BOOT_SCREEN_DEFAULTS_GEN2 = {
  splash = "Gen2CopyrightSplash", title = "Gen2TitleState",
  newGame = "Gen2OakSpeech",
}

local BOOT_SCREEN_CHOICES = {
  "IntroMovie", "YellowIntro", "TitleState", "OakSpeech",
}

local BOOT_SCREEN_CHOICES_GEN2 = {
  "Gen2CopyrightSplash", "Gen2GameFreakPresents", "Gen2CrystalSplash",
  "Gen2GoldSilverIntro", "Gen2CrystalIntro",
  "Gen2TitleState", "Gen2OakSpeech", "Gen2MainMenu",
}

local COMMON_STRINGS = {
  "NEW GAME", "OPTION", "CONTINUE", "YES", "NO",
  "But, it failed!", "Got away safely!",
  "Enemy %s\nfainted!", "Wild %s\nappeared!",
  "Go! %s!", "%s\nused %s!",
  "POKéDEX", "POKéMON", "ITEM", "SAVE", "EXIT",
  "PLAYER", "RIVAL", "MONEY",
}

-- ---- helpers ----

local function pathOf(v)
  if type(v) == "table" then return tostring(v.path or "") end
  if type(v) == "string" then return v end
  return ""
end

local function landmarkTable(S)
  local L = S.data and (S.data.gen2Landmarks or S.data.landmarks)
  if type(L) ~= "table" then return {} end
  if type(L.landmarks) == "table" then return L.landmarks end
  return L
end

local function dataField(S, key)
  if Generation.isGen2(S) then
    if key == "title" then
      return (S.data and (S.data.title or S.data.gen2Title)) or {}
    elseif key == "intro" then
      return (S.data and (S.data.gen2Intro or S.data.intro)) or {}
    elseif key == "oakSpeech" then
      return (S.data and (S.data.oakSpeech or S.data.gen2OakSpeech)) or {}
    elseif key == "credits" then
      return (S.data and (S.data.gen2Credits or S.data.credits)) or {}
    elseif key == "townMap" then
      return { locations = landmarkTable(S) }
    elseif key == "boot" then
      local boot = S.data and S.data.gen2BootScreens
      return { screens = (type(boot) == "table" and boot) or BOOT_SCREEN_DEFAULTS_GEN2 }
    elseif key == "theme" then
      return {}
    end
  end
  return (S.data and S.data.field and S.data.field[key]) or {}
end

local function ensureBucket(S, key)
  State.ensureProjectFields(S.project)
  S.project[key] = S.project[key] or {}
  return S.project[key]
end

-- Effective value: project override else data bucket[key].
local function eff(S, bucket, key)
  local p = S.project and S.project[bucket]
  if p ~= nil and p[key] ~= nil then return p[key], true end
  local d = dataField(S, bucket)
  return d[key], false
end

local function effNested(S, bucket, nest, key)
  local p = S.project and S.project[bucket] and S.project[bucket][nest]
  if type(p) == "table" and p[key] ~= nil then return p[key], true end
  local d = dataField(S, bucket)[nest]
  if type(d) == "table" then return d[key], false end
  return nil, false
end

local function setNested(S, bucket, nest, key, val, App)
  local b = ensureBucket(S, bucket)
  b[nest] = b[nest] or {}
  if val == nil or val == "" then
    b[nest][key] = nil
    if not next(b[nest]) then b[nest] = nil end
  else
    b[nest][key] = val
  end
  if App then App.markDirty() end
end

local function walkKeys(t, keys)
  local cur = t
  for _, key in ipairs(keys) do
    if type(cur) ~= "table" then return nil end
    cur = cur[key]
  end
  return cur
end

local function effDeep(S, bucket, keys)
  local fromP = walkKeys(S.project and S.project[bucket], keys)
  if fromP ~= nil then return fromP, true end
  return walkKeys(dataField(S, bucket), keys), false
end

local function setDeep(S, bucket, keys, val, App)
  if type(keys) ~= "table" or #keys == 0 then return end
  local cur = ensureBucket(S, bucket)
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
end

local function setDeepMany(S, bucket, keyLists, val, App)
  for _, keys in ipairs(keyLists) do
    setDeep(S, bucket, keys, val, nil)
  end
  if App then App.markDirty() end
end

local function setKey(S, bucket, key, val, App)
  local b = ensureBucket(S, bucket)
  if val == nil or val == "" then
    b[key] = nil
  else
    b[key] = val
  end
  if App then App.markDirty() end
end

local function speciesFrontPath(S, id)
  if type(id) ~= "string" or id == "" then return nil end
  local rec = (S.project and S.project.pokemon and S.project.pokemon[id])
    or (S.data and S.data.pokemon and S.data.pokemon[id])
  if type(rec) == "table" then
    local p = pathOf(rec.spriteFront)
    if p ~= "" then return p end
  end
  local ok, Sprites = pcall(require, "src.pokemon.Sprites")
  if ok and Sprites and Sprites.path and S.data then
    local path
    ok, path = pcall(Sprites.path, S.data, id, "front", { kind = "oak" })
    if ok then
      local p = pathOf(path)
      if p ~= "" then return p end
    end
  end
  return "assets/generated/battle/front/" .. string.lower(id) .. ".png"
end

local function drawMusicPicker(S, App, x, y, w, h, bucket, key, emptyLabel)
  local cur = tostring(select(1, eff(S, bucket, key)) or "")
  ChoicePicker.songField(S, {
    x = x, y = y, w = w, h = h,
    current = cur,
    emptyLabel = emptyLabel or "(music)",
    allowClear = true,
    onPick = function(id)
      setKey(S, bucket, key,
        (type(id) == "string" and id ~= "") and id or nil, App)
    end,
  })
end

local function drawCycleSpecies(S, App, viewX, fy, labelW, fieldW, fh, s, list)
  Kit.text("small", "Cycle spp.", viewX, fy + 6 * s, PAL.caption)
  if Kit.button(viewX + labelW, fy, fieldW, fh, "Add species", {
      kind = "accent", tooltip = "Pick a Pokémon for the title cycle",
    }) then
    SpeciesPicker.open(S, {
      title = "TITLE CYCLE SPECIES",
      onPick = function(id)
        if type(id) ~= "string" or id == "" then return end
        local next = {}
        if type(list) == "table" then
          for _, sp in ipairs(list) do next[#next + 1] = sp end
        end
        for _, sp in ipairs(next) do
          if sp == id then return end
        end
        next[#next + 1] = id
        setKey(S, "title", "cycleSpecies", next, App)
      end,
    })
  end
  fy = fy + fh + 6 * s
  if type(list) ~= "table" or #list == 0 then
    return fy + 2 * s
  end
  local cx, rowY = viewX + labelW, fy
  local chipW = math.min(120 * s, fieldW)
  for i, sp in ipairs(list) do
    if cx + chipW > viewX + labelW + fieldW + 1 and cx > viewX + labelW then
      rowY = rowY + fh + 4 * s
      cx = viewX + labelW
    end
    local shown = Kit.ellipsize("small", tostring(sp), chipW - 16 * s)
    if Kit.chip(cx, rowY, chipW, fh, shown, true, PAL.green, PAL.steel,
        "Remove " .. tostring(sp)) then
      local next = {}
      for j, other in ipairs(list) do
        if j ~= i then next[#next + 1] = other end
      end
      setKey(S, "title", "cycleSpecies", #next > 0 and next or nil, App)
    end
    cx = cx + chipW + 6 * s
  end
  return rowY + fh + 8 * s
end

local function browseImage(App, label, onRel)
  App.pickFile(label, "PNG (*.png)|*.png|All|*.*", function(picked)
    App.importToMod(picked, nil, function(rel)
      onRel(rel)
      Preview.invalidate()
    end)
  end)
end

local function imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, label,
    fieldId, path, onSet, tip)
  Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
  Kit.offerTooltip(viewX, fy, labelW, fh,
    tip or ("Import a PNG for " .. label))
  local fx = viewX + labelW
  local cur = path or ""
  local v = RegList.field(App, fieldId, fx, fy, math.max(40 * s, fieldW - 100 * s),
    fh, cur, "assets/...")
  if v ~= cur then onSet(v ~= "" and v or nil) end
  if Kit.button(fx + fieldW - 96 * s, fy, 96 * s, fh, "Browse", {
      kind = "ghost", tooltip = "Import PNG into mod",
    }) then
    browseImage(App, label .. " PNG", function(rel) onSet(rel) end)
  end
  return fy + fh + 8 * s
end

local function crystalUi(S)
  if Generation.isCrystal(S) then return true end
  local title = dataField(S, "title")
  return type(title) == "table" and title.layout == "crystal_title"
end

local function yellowUi(S)
  return Generation.id(S) == "yellow"
end

local drawNamedPals

local CRYSTAL_INTRO_SHEETS = {
  { label = "Unowns tiles", tip = "Unown letter cinema BG tiles",
    keys = {
      { "acts", "unownA", "tiles" },
      { "acts", "unownHI", "tiles" },
      { "acts", "unowns", "tiles" },
    } },
  { label = "Pulse sprites", tip = "Unown pulse OBJ sheet",
    keys = {
      { "acts", "unownA", "sprites" },
      { "acts", "unownHI", "sprites" },
      { "acts", "unowns", "sprites" },
    } },
  { label = "Background", tip = "Forest / grass BG tiles",
    keys = { { "acts", "background", "tiles" } } },
  { label = "Suicune run", tip = "Running Suicune OBJ sheet",
    keys = { { "acts", "background", "sprites" } } },
  { label = "Pichu/Wooper", tip = "Pichu and Wooper VRAM-bank-1 sheet",
    keys = { { "acts", "background", "sprites1" } } },
  { label = "Jump tiles", tip = "Suicune jump BG tiles",
    keys = { { "acts", "suicuneJump", "tiles" } } },
  { label = "Unown back", tip = "Unown-from-behind OBJ sheet",
    keys = {
      { "acts", "suicuneJump", "sprites" },
      { "acts", "suicuneBack", "sprites" },
    } },
  { label = "Close tiles", tip = "Close-up Suicune BG tiles",
    keys = { { "acts", "suicuneClose", "tiles" } } },
  { label = "Back tiles", tip = "Suicune from behind + Unown ring",
    keys = { { "acts", "suicuneBack", "tiles" } } },
  { label = "Crystal Unowns", tip = "CRYSTAL Unown word tiles",
    keys = { { "acts", "crystalUnowns", "tiles" } } },
  { label = "Grass frames", tip = "Rustling grass animation strip",
    keys = { { "grassFrames" } } },
}

local YELLOW_INTRO_SHEETS = {
  { key = "atlas1", label = "Atlas 1",
    fallback = "assets/generated/intro/yellow_intro_1.png",
    tip = "Yellow cinema BG atlas (16x8 tiles)" },
  { key = "atlas2", label = "Atlas 2",
    fallback = "assets/generated/intro/yellow_intro_2.png",
    tip = "Yellow cinema OBJ atlas (16x16 tiles)" },
  { key = "clouds", label = "Clouds",
    fallback = "assets/generated/intro/clouds.png",
    tip = "Cloud frames used in the fly scene" },
}

local GS_SPLASH_SHEETS = {
  { key = "presents", label = "Presents",
    fallback = "assets/generated/splash/presents.png",
    tip = "GAME FREAK letter strip (oakSpeech.splash.presents)" },
  { key = "logo", label = "GF logo",
    fallback = "assets/generated/splash/logo.png",
    tip = "GAME FREAK cube logo" },
  { key = "star", label = "Star",
    fallback = "assets/generated/splash/star.png",
    tip = "Spiraling star on the Game Freak splash" },
  { key = "sparkle", label = "Sparkle",
    fallback = "assets/generated/splash/sparkle.png",
    tip = "Sparkle frames after the star lands" },
}

local function drawTitleGen2(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "title")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiTitleScroll", "title-g2", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, crystalUi(S) and "CRYSTAL TITLE" or "GOLD TITLE")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "title", viewX, fy, viewW, s)

  local rows
  if crystalUi(S) then
    rows = {
      { "image", "Logo",
        "Optional extra logo overlay. Crystal already draws the logo on Screen BG" },
      { "screen", "Screen BG",
        "Full Crystal title art, including the wordmark" },
      { "wordmark", "Wordmark",
        "CRYSTAL VERSION overlay. Leave empty if Screen BG already has it" },
      { "suicune", "Suicune",
        "Animated Suicune frames on the Crystal title" },
      { "gem", "Gem",
        "Crystal gem that sits above the screen" },
      { "copyright", "Copyright",
        "Copyright line on the title screen" },
      { "copyrightSplash", "© splash",
        "Copyright on the Game Freak splash" },
    }
  else
    rows = {
      { "image", "Logo", "Gold title logo overlay" },
      { "screen", "Screen BG", "Title background behind Ho-Oh and clouds" },
      { "clouds", "Clouds", "Scrolling cloud layer on the Gold title" },
      { "trail", "Trail", "Ho-Oh trail / sparkle overlay" },
      { "hooh", "Ho-Oh", "Ho-Oh sprite on the Gold title" },
      { "copyright", "Copyright", "Copyright line on the title screen" },
      { "copyrightSplash", "© splash", "Copyright on the Game Freak splash" },
    }
  end
  for _, row in ipairs(rows) do
    local key, label, tip = row[1], row[2], row[3]
    local p = pathOf(select(1, eff(S, "title", key)))
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, label,
      "ui_title_" .. key, p, function(path)
        setKey(S, "title", key, path, App)
      end, tip)
  end

  Kit.text("small", "Layout", viewX, fy + 6 * s, PAL.caption)
  Kit.offerTooltip(viewX, fy, labelW, fh,
    crystalUi(S)
      and "crystal_title uses Screen BG as the full Crystal title"
      or "gold_title is Ho-Oh / clouds; crystal_title uses Screen BG as the full title")
  do
    local placeholder = crystalUi(S) and "crystal_title" or "gold_title"
    local cur = tostring(select(1, eff(S, "title", "layout")) or placeholder)
    local v = RegList.field(App, "ui_title_layout", viewX + labelW, fy, fieldW, fh,
      cur, placeholder)
    if v ~= cur then setKey(S, "title", "layout", v ~= "" and v or nil, App) end
  end
  fy = fy + fh + 8 * s

  local layoutRows
  if crystalUi(S) then
    layoutRows = {
      { "suicuneX", "Suicune X", 48 },
      { "suicuneY", "Suicune Y", 96 },
      { "gemX", "Gem X", 56 },
      { "gemY", "Gem Y", 6 },
    }
  else
    layoutRows = {
      { "hoohX", "Ho-Oh X", 48 },
      { "hoohY", "Ho-Oh Y", 56 },
      { "cloudY", "Cloud Y", 88 },
    }
  end
  for _, row in ipairs(layoutRows) do
    Kit.text("small", row[2], viewX, fy + 6 * s, PAL.caption)
    Kit.offerTooltip(viewX, fy, labelW, fh,
      "Pixel offset for " .. row[2] .. " on the title screen")
    local cur = select(1, eff(S, "title", row[1]))
    if type(cur) ~= "number" then cur = row[3] end
    local v = RegList.num(App, "ui_title_" .. row[1], viewX + labelW, fy, 80 * s, fh, cur)
    if v ~= cur then setKey(S, "title", row[1], v, App) end
    fy = fy + fh + 6 * s
  end

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  drawMusicPicker(S, App, viewX + labelW, fy, fieldW, fh,
    "title", "music", "Music_TitleScreen")
  fy = fy + fh + 8 * s

  if next(S.project.title) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger", tooltip = "Remove project.title overrides",
    }) then
    S.project.title = {}
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiTitleScroll", contentTop, fy, view)
end

local function drawTitle(S, x, y, w, h, App)
  if Generation.isGen2(S) then
    return drawTitleGen2(S, x, y, w, h, App)
  end
  local s = Kit.scale
  ensureBucket(S, "title")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiTitleScroll", "title", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, "TITLE SCREEN")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "title", viewX, fy, viewW, s)

  local logo = pathOf(select(1, eff(S, "title", "logo")))
  local version = pathOf(select(1, eff(S, "title", "versionRibbon"))
    or select(1, eff(S, "title", "version")))
  fieldW = viewW - labelW - 12 * s

  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Logo",
    "ui_title_logo", logo, function(p) setKey(S, "title", "logo", p, App) end)

  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Version",
    "ui_title_ver", version, function(p)
      setKey(S, "title", "versionRibbon", p, App)
      setKey(S, "title", "version", p, App)
    end)

  Kit.text("small", "Copyright", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(select(1, eff(S, "title", "copyrightText")) or "")
    local v = RegList.field(App, "ui_title_copy", viewX + labelW, fy, fieldW, fh,
      cur, "©1995 …")
    if v ~= cur then setKey(S, "title", "copyrightText", v ~= "" and v or nil, App) end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  drawMusicPicker(S, App, viewX + labelW, fy, fieldW, fh,
    "title", "music", "Music_TitleScreen")
  fy = fy + fh + 8 * s

  fy = drawCycleSpecies(S, App, viewX, fy, labelW, fieldW, fh, s,
    select(1, eff(S, "title", "cycleSpecies")))

  Kit.text("small", "Layout", viewX, fy + 6 * s, PAL.caption)
  Kit.offerTooltip(viewX, fy, labelW, fh,
    "Yellow can use the Pikachu title layout")
  do
    local cur = tostring(select(1, eff(S, "title", "layout")) or "")
    local label = (cur ~= "" and cur) or "(default)"
    if Kit.button(viewX + labelW, fy, fieldW, fh,
        Kit.ellipsize("small", label, fieldW - 8 * s), {
          kind = "ghost",
          tooltip = "Cycle title layout (default / yellow Pikachu)",
        }) then
      local next = (cur == "") and "yellow_pikachu"
        or (cur == "yellow_pikachu") and "" or ""
      setKey(S, "title", "layout", next ~= "" and next or nil, App)
    end
  end
  fy = fy + fh + 8 * s

  local pika = pathOf(select(1, eff(S, "title", "pikachu")))
  local bubble = pathOf(select(1, eff(S, "title", "pikaBubble")))
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Pikachu",
    "ui_title_pika", pika, function(p) setKey(S, "title", "pikachu", p, App) end,
    "Yellow title Pikachu sprite")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Bubble",
    "ui_title_bub", bubble, function(p) setKey(S, "title", "pikaBubble", p, App) end,
    "Pikachu speech bubble on the Yellow title")

  local yellowTitle = yellowUi(S)
    or tostring(select(1, eff(S, "title", "layout")) or "") == "yellow_pikachu"
  local titlePals
  if yellowTitle then
    titlePals = {
      { id = "LOGO2", label = "Logo (LOGO2)" },
      { id = "MEWMON", label = "Pikachu / copyright (MEWMON)" },
    }
  else
    titlePals = {
      { id = "LOGO2", label = "Logo (LOGO2)" },
      { id = "LOGO1", label = "Version ribbon (LOGO1)" },
      { id = "MEWMON", label = "Mon / player (MEWMON)" },
    }
  end
  fy = drawNamedPals(S, App, viewX, fy, viewW, s, titlePals)

  if next(S.project.title) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger", tooltip = "Remove project.title overrides",
    }) then
    S.project.title = {}
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiTitleScroll", contentTop, fy, view)
end

-- ---- Intro ----

local function drawIntroGen2(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "intro")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiIntroScroll", "intro-g2", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s
  local crystal = crystalUi(S)

  Kit.caption(viewX, fy, crystal and "CRYSTAL INTRO" or "GOLD/SILVER INTRO")
  fy = fy + 22 * s
  Kit.text("micro", crystal
      and "Unown / Suicune cinema sheets (data.gen2Intro.acts)"
      or "Water → grass → fire acts (data.gen2Intro)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  fy = UiPreview.draw(S, "intro", viewX, fy, viewW, s)

  if crystal then
    for i, row in ipairs(CRYSTAL_INTRO_SHEETS) do
      local p = pathOf(select(1, effDeep(S, "intro", row.keys[1])))
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, row.label,
        "ui_intro_cryl_" .. i, p, function(path)
          setDeepMany(S, "intro", row.keys, path, App)
        end, row.tip)
    end
  else
    for _, act in ipairs({ "water", "grass", "fire" }) do
      Kit.caption(viewX, fy, string.upper(act))
      fy = fy + 22 * s
      for _, key in ipairs({ "tiles", "sprites" }) do
        local p = pathOf(select(1, effNested(S, "intro", act, key)))
        fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s,
          act .. " " .. key, "ui_intro_" .. act .. "_" .. key, p, function(path)
            setNested(S, "intro", act, key, path, App)
          end, "Tile or sprite sheet for the " .. act .. " intro act")
      end
    end
    Kit.caption(viewX, fy, "GAME FREAK SPLASH")
    fy = fy + 22 * s
    Kit.text("micro", "Boot splash sheets (oakSpeech.splash)",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    for _, row in ipairs(GS_SPLASH_SHEETS) do
      local p = pathOf(select(1, effNested(S, "oakSpeech", "splash", row.key)))
      if p == "" then p = row.fallback end
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, row.label,
        "ui_intro_spl_" .. row.key, p, function(path)
          setNested(S, "oakSpeech", "splash", row.key, path, App)
        end, row.tip)
    end
  end

  if next(S.project.intro) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger", tooltip = "Remove project.intro overrides" }) then
    S.project.intro = {}
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiIntroScroll", contentTop, fy, view)
end

local function drawIntro(S, x, y, w, h, App)
  if Generation.isGen2(S) then
    return drawIntroGen2(S, x, y, w, h, App)
  end
  local s = Kit.scale
  local intro = ensureBucket(S, "intro")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiIntroScroll", "intro", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s
  local yellow = yellowUi(S)

  Kit.caption(viewX, fy, yellow and "YELLOW INTRO" or "INTRO / SPLASH")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "intro", viewX, fy, viewW, s)

  local studioLogo = pathOf((intro.studio and intro.studio.logo)
    or (dataField(S, "intro").studio and dataField(S, "intro").studio.logo))
  fieldW = viewW - labelW - 12 * s

  Kit.text("small", "Studio logo", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = studioLogo
    local fx = viewX + labelW
    local v = RegList.field(App, "ui_intro_logo", fx, fy,
      math.max(40 * s, fieldW - 100 * s), fh, cur, "assets/...")
    if v ~= cur then
      intro.studio = intro.studio or {}
      intro.studio.logo = (v ~= "" and v) or nil
      App.markDirty()
    end
    if Kit.button(fx + fieldW - 96 * s, fy, 96 * s, fh, "Browse", {
        kind = "ghost" }) then
      browseImage(App, "Studio logo", function(rel)
        intro.studio = intro.studio or {}
        intro.studio.logo = rel
        App.markDirty()
      end)
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Credit", viewX, fy + 6 * s, PAL.caption)
  do
    local dStudio = dataField(S, "intro").studio or {}
    local cur = tostring((intro.studio and intro.studio.credit)
      or dStudio.credit or "")
    local v = RegList.field(App, "ui_intro_cred", viewX + labelW, fy, fieldW, fh,
      cur, "presents")
    if v ~= cur then
      intro.studio = intro.studio or {}
      intro.studio.credit = (v ~= "" and v) or nil
      App.markDirty()
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Skip intro", viewX, fy + 6 * s, PAL.caption)
  Kit.offerTooltip(viewX, fy, labelW, fh,
    "When YES, the game skips the intro cinema and goes to the title")
  do
    local skip = select(1, eff(S, "intro", "skip")) and true or false
    if Kit.chip(viewX + labelW, fy, 80 * s, fh, skip and "YES" or "NO",
        skip, PAL.yellow, PAL.steel,
        skip and "Skip the intro cinema and go to the title"
          or "Play the intro cinema before the title") then
      setKey(S, "intro", "skip", (not skip) and true or nil, App)
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  drawMusicPicker(S, App, viewX + labelW, fy, fieldW, fh,
    "intro", "music", "(none)")
  fy = fy + fh + 8 * s

  Kit.caption(viewX, fy, "GAME FREAK SPLASH")
  fy = fy + 22 * s
  local splashKeys = {
    { "gamefreakLogo", "GF logo" },
    { "gamefreakText", "GF text" },
    { "bigStar", "Big star" },
    { "fallingStar", "Fall star" },
    { "fallingStarBlink", "Star blink" },
  }
  for _, row in ipairs(splashKeys) do
    local key, label = row[1], row[2]
    local p = pathOf(select(1, eff(S, "intro", key)))
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, label,
      "ui_intro_" .. key, p, function(path)
        setKey(S, "intro", key, path, App)
      end)
  end

  if yellow then
    Kit.caption(viewX, fy, "YELLOW CINEMA")
    fy = fy + 22 * s
    Kit.text("micro", "Pikachu attract movie atlases (YellowIntro)",
      viewX, fy, PAL.muted)
    fy = fy + 20 * s
    for _, row in ipairs(YELLOW_INTRO_SHEETS) do
      local p = pathOf(select(1, effNested(S, "intro", "yellowIntro", row.key)))
      if p == "" then p = row.fallback end
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, row.label,
        "ui_intro_yel_" .. row.key, p, function(path)
          setNested(S, "intro", "yellowIntro", row.key, path, App)
        end, row.tip)
    end
  else
    Kit.caption(viewX, fy, "GENGAR / NIDORINO")
    fy = fy + 22 * s
    Kit.text("micro", "Attract-fight poses after the Game Freak splash",
      viewX, fy, PAL.muted)
    fy = fy + 20 * s
    local fightRows = {
      { "gengar", "frame1", "Gengar 1" },
      { "gengar", "frame2", "Gengar 2" },
      { "gengar", "frame3", "Gengar 3" },
      { "nidorino", "frame1", "Nidorino 1" },
      { "nidorino", "frame2", "Nidorino 2" },
      { "nidorino", "frame3", "Nidorino 3" },
    }
    for _, row in ipairs(fightRows) do
      local nest, key, label = row[1], row[2], row[3]
      local p = pathOf(select(1, effNested(S, "intro", nest, key)))
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, label,
        "ui_intro_" .. nest .. "_" .. key, p, function(path)
          setNested(S, "intro", nest, key, path, App)
        end, "Pose frame for the Red/Blue intro fight")
    end
  end

  local introPals
  if yellow then
    introPals = {
      { id = "GAMEFREAK", label = "Studio splash (GAMEFREAK)" },
      { id = "REDMON", label = "Star (REDMON)" },
      { id = "VIRIDIAN", label = "Star (VIRIDIAN)" },
      { id = "BLUEMON", label = "Star (BLUEMON)" },
      { id = "MEWMON", label = "Cinema (MEWMON)" },
      { id = "PIKACHUS_BEACH", label = "Beach scenes" },
    }
  else
    introPals = {
      { id = "GAMEFREAK", label = "Studio splash (GAMEFREAK)" },
      { id = "REDMON", label = "Star (REDMON)" },
      { id = "VIRIDIAN", label = "Star (VIRIDIAN)" },
      { id = "BLUEMON", label = "Star (BLUEMON)" },
      { id = "PURPLEMON", label = "Fight (PURPLEMON)" },
      { id = "BLACK", label = "Letterbox (BLACK)" },
    }
  end
  fy = drawNamedPals(S, App, viewX, fy, viewW, s, introPals)

  if next(S.project.intro) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger", tooltip = "Remove project.intro overrides" }) then
    S.project.intro = {}
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiIntroScroll", contentTop, fy, view)
end

-- ---- Oak / Credits ----

local OAK_LINES_GEN1 = {
  { key = "_OakSpeechText1", label = "Welcome" },
  { key = "_OakSpeechText2A", label = "This world" },
  { key = "_OakSpeechText2B", label = "Pets / fights" },
  { key = "_IntroducePlayerText", label = "Your name?" },
  { key = "_YourNameIsText", label = "Confirm name" },
  { key = "_IntroduceRivalText", label = "Rival intro" },
  { key = "_HisNameIsText", label = "Confirm rival" },
  { key = "_OakSpeechText3", label = "Legend" },
}

local OAK_LINES_GEN2 = {
  { key = "_OakText1", label = "Welcome" },
  { key = "_OakText2", label = "This world" },
  { key = "_OakText4", label = "Live together" },
  { key = "_OakText5", label = "Mysteries" },
  { key = "_OakText6", label = "Your name?" },
  { key = "_OakText7", label = "Ready / legend" },
}

local function encodeBody(s)
  return tostring(s or ""):gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\v", "\\v")
end

local function decodeBody(s)
  return tostring(s or ""):gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\v")
end

local function joinLines(v)
  if type(v) == "table" then return table.concat(v, "\n") end
  return tostring(v or "")
end

local function splitLines(s)
  local rows = {}
  for line in (tostring(s or "") .. "\n"):gmatch("(.-)\n") do
    rows[#rows + 1] = line
  end
  if #rows > 0 and rows[#rows] == "" then rows[#rows] = nil end
  return rows
end

local function oakLineText(S, key)
  local p = S.project and S.project.oakSpeech
  if type(p) == "table" and type(p.text) == "table" and type(p.text[key]) == "string" then
    return p.text[key], true
  end
  if S.project and S.project.text and type(S.project.text[key]) == "string" then
    return S.project.text[key], true
  end
  local d = dataField(S, "oakSpeech")
  if type(d.text) == "table" and type(d.text[key]) == "string" then
    return d.text[key], false
  end
  if S.data and S.data.text and type(S.data.text[key]) == "string" then
    return S.data.text[key], false
  end
  return "", false
end

local function setOakLine(S, key, body, App)
  local b = ensureBucket(S, "oakSpeech")
  b.text = b.text or {}
  b.text[key] = body
  if not Generation.isGen2(S) then
    S.project.text = S.project.text or {}
    S.project.text[key] = body
    if S.data then
      S.data.text = S.data.text or {}
      S.data.text[key] = body
    end
  end
  if App then App.markDirty() end
end

local function drawEncodedRow(S, App, viewX, fy, viewW, fh, fieldId, label, body, onSet)
  Kit.text("small", label, viewX, fy, PAL.caption)
  fy = fy + 18 * Kit.scale
  local cur = encodeBody(body)
  local v = RegList.field(App, fieldId, viewX, fy, viewW, fh, cur, "\\n \\f \\v")
  if v ~= cur then onSet(decodeBody(v)) end
  return fy + fh + 8 * Kit.scale
end

local function drawOak(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "oakSpeech")
  local gen2 = Generation.isGen2(S)
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiOakScroll", gen2 and "oak-g2" or "oak", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, gen2 and "OAK SPEECH (GOLD/CRYSTAL)" or "OAK SPEECH")
  fy = fy + 22 * s
  Kit.text("micro", gen2
      and "New-game Oak intro (data/generated/oak_speech.lua)"
      or "New-game Oak intro (field.oakSpeech + text keys)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  fy = UiPreview.draw(S, "oak", viewX, fy, viewW, s)

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  drawMusicPicker(S, App, viewX + labelW, fy, fieldW, fh,
    "oakSpeech", "music", gen2 and "Music_Route30" or "Music_Routes2")
  fy = fy + fh + 8 * s

  Kit.text("small", "Demo species", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(select(1, eff(S, "oakSpeech", "demoSpecies")) or "")
    SpeciesPicker.field(S, {
      x = viewX + labelW, y = fy, w = fieldW, h = fh,
      current = cur,
      emptyLabel = gen2 and "MARILL" or "NIDORINO",
      title = "DEMO SPECIES",
      tooltip = "Pokémon Oak shows off in the speech",
      onPick = function(id)
        local sid = (type(id) == "string" and id ~= "") and id or nil
        local b = ensureBucket(S, "oakSpeech")
        b.demoSpecies = sid
        local picKey = gen2 and "marillPic" or "demoPic"
        if sid then
          b[picKey] = speciesFrontPath(S, sid)
        else
          b[picKey] = nil
        end
        if App then App.markDirty() end
      end,
    })
  end
  fy = fy + fh + 8 * s

  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Oak pic",
    "ui_oak_pic", pathOf(select(1, eff(S, "oakSpeech", "oakPic"))),
    function(p) setKey(S, "oakSpeech", "oakPic", p, App) end,
    "Professor Oak front pic")
  if not gen2 then
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Rival pic",
      "ui_oak_rival", pathOf(select(1, eff(S, "oakSpeech", "rivalPic"))),
      function(p) setKey(S, "oakSpeech", "rivalPic", p, App) end,
      "Rival front pic")
  end
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Player pic",
    "ui_oak_player", pathOf(select(1, eff(S, "oakSpeech", "playerPic"))),
    function(p) setKey(S, "oakSpeech", "playerPic", p, App) end,
    "Player intro pic")
  if gen2 then
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Player ♀",
      "ui_oak_player_f", pathOf(select(1, eff(S, "oakSpeech", "playerPicFemale"))),
      function(p) setKey(S, "oakSpeech", "playerPicFemale", p, App) end,
      "Kris / female intro pic")
  end
  do
    local picKey = gen2 and "marillPic" or "demoPic"
    local owned = S.project and S.project.oakSpeech
    local demoPicPath = pathOf(owned and owned[picKey])
    if demoPicPath == "" then
      local sid = tostring(select(1, eff(S, "oakSpeech", "demoSpecies")) or "")
      if sid ~= "" then demoPicPath = speciesFrontPath(S, sid) or "" end
    end
    if demoPicPath == "" then
      demoPicPath = pathOf(select(1, eff(S, "oakSpeech", picKey)))
    end
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Demo pic",
      gen2 and "ui_oak_marill" or "ui_oak_demo_pic", demoPicPath,
      function(p) setKey(S, "oakSpeech", picKey, p, App) end,
      gen2 and "Show-off mon pic (Marill / Wooper)"
        or "Show-off mon pic (Nidorino)")
  end
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Shrink 1",
    "ui_oak_sh1", pathOf(select(1, eff(S, "oakSpeech", "shrink1"))),
    function(p) setKey(S, "oakSpeech", "shrink1", p, App) end,
    "Player shrink frame 1")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Shrink 2",
    "ui_oak_sh2", pathOf(select(1, eff(S, "oakSpeech", "shrink2"))),
    function(p) setKey(S, "oakSpeech", "shrink2", p, App) end,
    "Player shrink frame 2")

  Kit.caption(viewX, fy, "LINES")
  fy = fy + 22 * s
  Kit.text("micro", "Use \\n new line, \\f page, \\v A-wait, {PLAYER} / {RIVAL}",
    viewX, fy, PAL.muted)
  fy = fy + 18 * s
  local rows = gen2 and OAK_LINES_GEN2 or OAK_LINES_GEN1
  for _, row in ipairs(rows) do
    local body = select(1, oakLineText(S, row.key))
    fy = drawEncodedRow(S, App, viewX, fy, viewW, fh,
      "ui_oak_t_" .. row.key, row.label, body, function(v)
        setOakLine(S, row.key, v, App)
      end)
  end

  if next(S.project.oakSpeech) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger", tooltip = "Remove project.oakSpeech overrides" }) then
    S.project.oakSpeech = {}
    App.markDirty()
  end
  fy = fy + fh + 8 * s
  FormPane.finish(S, "uiOakScroll", contentTop, fy, view)
end

local function gen2CreditCatalog()
  if UiPreview.gen2CreditCatalog then
    return UiPreview.gen2CreditCatalog()
  end
  return nil, nil
end

local function gen2CreditString(S, id)
  local p = S.project and S.project.credits and S.project.credits.strings
  if type(p) == "table" and p[id] ~= nil then return joinLines(p[id]), true end
  local C, vanilla = gen2CreditCatalog()
  if C and C.ID and C.ID[id] ~= nil then
    local idx = C.ID[id]
    local src = vanilla and vanilla[idx]
    if src == nil then src = C.STRINGS and C.STRINGS[idx] end
    return joinLines(src), false
  end
  return "", false
end

local function gen2PageLineText(S, line)
  local body = select(1, gen2CreditString(S, line.id))
  if line.table then
    local rows = splitLines(body)
    return tostring(rows[line.row] or "")
  end
  return body
end

local function setGen2PageLine(S, line, newText, App)
  local b = ensureBucket(S, "credits")
  b.strings = b.strings or {}
  if line.table then
    local body = select(1, gen2CreditString(S, line.id))
    local rows = splitLines(body)
    rows[line.row] = newText
    b.strings[line.id] = rows
  elseif newText == "" then
    b.strings[line.id] = nil
  else
    b.strings[line.id] = newText
  end
  if type(b.strings) == "table" and not next(b.strings) then b.strings = nil end
  if App then App.markDirty() end
end

local function cloneCreditScreens(src)
  local copy = {}
  for i, sc in ipairs(src or {}) do
    local lines = {}
    for j, ln in ipairs(sc.lines or {}) do
      lines[j] = { text = ln.text, column = ln.column }
    end
    copy[i] = {
      fade = sc.fade and true or nil,
      mon = sc.mon,
      copyright = sc.copyright and true or nil,
      lines = lines,
    }
  end
  return copy
end

local function creditScreens(S)
  local p = S.project and S.project.credits
  if type(p) == "table" and type(p.screens) == "table" then
    return p.screens, true
  end
  return dataField(S, "credits").screens or {}, false
end

local function ownCreditScreens(S, App)
  local b = ensureBucket(S, "credits")
  if type(b.screens) ~= "table" then
    b.screens = cloneCreditScreens(dataField(S, "credits").screens)
    if App then App.markDirty() end
  end
  return b.screens
end

local function drawCreditsGen2(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "credits")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiCredScroll", "credits-g2", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, "GOLD/CRYSTAL CREDITS")
  fy = fy + 22 * s
  Kit.text("micro", "Staff-roll text, music, and banner sheets (data.gen2Credits)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  fy = UiPreview.draw(S, "credits", viewX, fy, viewW, s)

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  drawMusicPicker(S, App, viewX + labelW, fy, fieldW, fh,
    "credits", "music", "Music_Credits")
  fy = fy + fh + 8 * s

  Kit.caption(viewX, fy, "STAFF ROLL")
  fy = fy + 22 * s
  do
    local pages = (UiPreview.gen2CreditPages and UiPreview.gen2CreditPages()) or {}
    if #pages == 0 then
      Kit.text("micro", "Could not read the credits script.", viewX, fy, PAL.muted)
      fy = fy + 18 * s
    else
      S.uiCreditIndex = math.max(1, math.min(S.uiCreditIndex or 1, #pages))
      Kit.text("micro", "Each card is one screen of the roll. Leading spaces center a name.",
        viewX, fy, PAL.muted)
      fy = fy + 18 * s
      Kit.caption(viewX, fy, string.format("CARD %d / %d", S.uiCreditIndex, #pages))
      fy = fy + 22 * s
      if Kit.chip(viewX, fy, 50 * s, fh, "<", false, PAL.steel, PAL.steel, "Previous credits card")
          and S.uiCreditIndex > 1 then
        S.uiCreditIndex = S.uiCreditIndex - 1
      end
      if Kit.chip(viewX + 56 * s, fy, 50 * s, fh, ">", false, PAL.steel, PAL.steel, "Next credits card")
          and S.uiCreditIndex < #pages then
        S.uiCreditIndex = S.uiCreditIndex + 1
      end
      fy = fy + fh + 10 * s
      local page = pages[S.uiCreditIndex]
      for i, line in ipairs(page.lines or {}) do
        local label = tostring(line.id or ""):gsub("_", " ")
        if line.table then
          label = label .. " " .. tostring(line.row)
        end
        Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
        local cur = gen2PageLineText(S, line)
        local v = RegList.field(App, "ui_cred_p" .. S.uiCreditIndex .. "_" .. i,
          viewX + labelW, fy, fieldW, fh, cur, "line")
        if v ~= cur then setGen2PageLine(S, line, v, App) end
        fy = fy + fh + 6 * s
      end
    end
  end

  Kit.caption(viewX, fy, "BANNER ART")
  fy = fy + 22 * s
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Border",
    "ui_cred_border", pathOf(select(1, eff(S, "credits", "border"))),
    function(p) setKey(S, "credits", "border", p, App) end,
    "Credits border strip")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "THE END",
    "ui_cred_end", pathOf(select(1, eff(S, "credits", "theEnd"))),
    function(p) setKey(S, "credits", "theEnd", p, App) end,
    "THE END graphic")

  local scenes = dataField(S, "credits").scenes
  local projScenes = S.project.credits.scenes
  if type(scenes) == "table" then
    for i, sc in ipairs(scenes) do
      local p = ""
      if type(projScenes) == "table" and type(projScenes[i]) == "table" then
        p = pathOf(projScenes[i].image)
      end
      if p == "" then p = pathOf(sc.image) end
      local label = tostring((sc.species or ("Scene " .. i)))
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, label,
        "ui_cred_sc_" .. i, p, function(path)
          local b = ensureBucket(S, "credits")
          b.scenes = b.scenes or {}
          b.scenes[i] = b.scenes[i] or {}
          b.scenes[i].image = path
          App.markDirty()
        end, "Credits banner for " .. label)
    end
  end

  if next(S.project.credits) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger" }) then
    S.project.credits = {}
    App.markDirty()
  end
  fy = fy + fh + 8 * s
  FormPane.finish(S, "uiCredScroll", contentTop, fy, view)
end

local function drawCreditsGen1(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "credits")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiCredScroll", "credits", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s
  local screens, owned = creditScreens(S)
  if type(screens) ~= "table" then screens = {} end
  S.uiCreditIndex = math.max(1, math.min(S.uiCreditIndex or 1, math.max(1, #screens)))

  Kit.caption(viewX, fy, "CREDITS ROLL")
  fy = fy + 22 * s
  Kit.text("micro", "Hall of Fame screens (field.credits)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  fy = UiPreview.draw(S, "credits", viewX, fy, viewW, s)

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  drawMusicPicker(S, App, viewX + labelW, fy, fieldW, fh,
    "credits", "music", "Music_Credits")
  fy = fy + fh + 8 * s

  local theEnd = dataField(S, "credits").theEnd
  local endPath = pathOf(select(1, effNested(S, "credits", "theEnd", "path")))
  if endPath == "" then endPath = pathOf(theEnd) end
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "THE END",
    "ui_cred_end", endPath, function(p)
      setNested(S, "credits", "theEnd", "path", p, App)
    end, "THE END letter sheet")

  Kit.caption(viewX, fy, string.format("SCREEN %d / %d", S.uiCreditIndex, math.max(1, #screens)))
  fy = fy + 22 * s
  if Kit.chip(viewX, fy, 50 * s, fh, "<", false, PAL.steel, PAL.steel, "Previous screen")
      and S.uiCreditIndex > 1 then
    S.uiCreditIndex = S.uiCreditIndex - 1
  end
  if Kit.chip(viewX + 56 * s, fy, 50 * s, fh, ">", false, PAL.steel, PAL.steel, "Next screen")
      and S.uiCreditIndex < #screens then
    S.uiCreditIndex = S.uiCreditIndex + 1
  end
  if Kit.button(viewX + 116 * s, fy, 70 * s, fh, "+ Screen", { kind = "good" }) then
    screens = ownCreditScreens(S, App)
    screens[#screens + 1] = { fade = true, lines = { { text = "STAFF", column = 6 } } }
    S.uiCreditIndex = #screens
  end
  if #screens > 0 and Kit.button(viewX + 192 * s, fy, 80 * s, fh, "Remove", {
      kind = "danger" }) then
    screens = ownCreditScreens(S, App)
    table.remove(screens, S.uiCreditIndex)
    S.uiCreditIndex = math.max(1, math.min(S.uiCreditIndex, math.max(1, #screens)))
  end
  fy = fy + fh + 10 * s

  local sc = screens[S.uiCreditIndex]
  if sc then
    local function touch()
      screens = ownCreditScreens(S, App)
      sc = screens[S.uiCreditIndex]
      return sc
    end
    Kit.text("small", "Fade in", viewX, fy + 6 * s, PAL.caption)
    if Kit.chip(viewX + labelW, fy, 80 * s, fh, sc.fade and "YES" or "NO",
        sc.fade and true or false, PAL.yellow, PAL.steel) then
      sc = touch()
      if sc then sc.fade = not sc.fade; App.markDirty() end
    end
    fy = fy + fh + 8 * s
    Kit.text("small", "Copyright", viewX, fy + 6 * s, PAL.caption)
    if Kit.chip(viewX + labelW, fy, 80 * s, fh, sc.copyright and "YES" or "NO",
        sc.copyright and true or false, PAL.yellow, PAL.steel) then
      sc = touch()
      if sc then sc.copyright = not sc.copyright or nil; App.markDirty() end
    end
    fy = fy + fh + 8 * s
    Kit.text("small", "Mon", viewX, fy + 6 * s, PAL.caption)
    SpeciesPicker.field(S, {
      x = viewX + labelW, y = fy, w = fieldW, h = fh,
      current = tostring(sc.mon or ""),
      emptyLabel = "(none)",
      title = "CREDITS MON",
      tooltip = "Silhouette species on this credits screen",
      onPick = function(id)
        sc = touch()
        if sc then
          sc.mon = (type(id) == "string" and id ~= "") and id or nil
          App.markDirty()
        end
      end,
    })
    fy = fy + fh + 8 * s
    Kit.caption(viewX, fy, "LINES")
    fy = fy + 20 * s
    local lines = sc.lines or {}
    for i = 1, 4 do
      local ln = lines[i] or { text = "", column = 4 }
      Kit.text("micro", "col", viewX, fy + 8 * s, PAL.muted)
      local col = tonumber(RegList.field(App, "ui_cred_c" .. i, viewX + 28 * s, fy,
        40 * s, fh, tostring(ln.column or 4), "4")) or 4
      local txt = RegList.field(App, "ui_cred_l" .. i, viewX + 76 * s, fy,
        viewW - 76 * s, fh, tostring(ln.text or ""), "STAFF")
      if col ~= (ln.column or 4) or txt ~= tostring(ln.text or "") then
        sc = touch()
        if sc then
          sc.lines = sc.lines or {}
          local nextLines = {}
          for j = 1, 4 do
            local src = sc.lines[j] or (j == i and { text = "", column = 4 }) or nil
            if j == i then
              if txt ~= "" then nextLines[#nextLines + 1] = { text = txt, column = col } end
            elseif type(src) == "table" and src.text and src.text ~= "" then
              nextLines[#nextLines + 1] = src
            end
          end
          sc.lines = nextLines
          App.markDirty()
        end
      end
      fy = fy + fh + 6 * s
    end
  end

  if next(S.project.credits) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger" }) then
    S.project.credits = {}
    S.uiCreditIndex = 1
    App.markDirty()
  end
  fy = fy + fh + 8 * s
  FormPane.finish(S, "uiCredScroll", contentTop, fy, view)
end

local function drawCredits(S, x, y, w, h, App)
  if Generation.isGen2(S) then
    return drawCreditsGen2(S, x, y, w, h, App)
  end
  return drawCreditsGen1(S, x, y, w, h, App)
end

-- ---- Boot screens ----

local function bootDefaults(S)
  return Generation.isGen2(S) and BOOT_SCREEN_DEFAULTS_GEN2 or BOOT_SCREEN_DEFAULTS
end

local function bootChoices(S)
  return Generation.isGen2(S) and BOOT_SCREEN_CHOICES_GEN2 or BOOT_SCREEN_CHOICES
end

local function screenField(S, key)
  local defaults = bootDefaults(S)
  local boot = S.project and S.project.boot
  if boot and type(boot.screens) == "table" and boot.screens[key] then
    return boot.screens[key], true
  end
  local d = dataField(S, "boot")
  if type(d.screens) == "table" and d.screens[key] then
    return d.screens[key], false
  end
  return defaults[key], false
end

local function setScreen(S, key, val, App)
  local defaults = bootDefaults(S)
  State.ensureProjectFields(S.project)
  S.project.boot = S.project.boot or {}
  S.project.boot.screens = S.project.boot.screens or {}
  if val == nil or val == "" or val == defaults[key] then
    S.project.boot.screens[key] = nil
    if not next(S.project.boot.screens) then S.project.boot.screens = nil end
  else
    S.project.boot.screens[key] = val
  end
  App.markDirty()
end

local function drawBoot(S, x, y, w, h, App)
  local s = Kit.scale
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiBootScroll", "boot", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local gen2 = Generation.isGen2(S)

  Kit.caption(viewX, fy, Generation.isCrystal(S) and "CRYSTAL BOOT SCREENS"
    or (gen2 and "GOLD BOOT SCREENS" or "BOOT SCREENS"))
  fy = fy + 22 * s
  fy = UiPreview.draw(S, "boot", viewX, fy, viewW, s)
  Kit.text("micro", gen2
      and "data.gen2BootScreens: splash / title / newGame (movie & gamefreak stay vanilla unless set in Code)"
      or "Registry ids for splash → title → new game (Code tab for custom factories)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s

  local slots = {
    { id = "splash", label = "Splash" },
    { id = "title", label = "Title" },
    { id = "newGame", label = "New game" },
  }
  local choices = bootChoices(S)
  for _, slot in ipairs(slots) do
    local cur, owned = screenField(S, slot.id)
    cur = tostring(cur or "")
    Kit.text("small", slot.label, viewX, fy + 6 * s, PAL.caption)
    local fx = viewX + labelW
    local chipX = fx
    for _, choice in ipairs(choices) do
      local on = cur == choice
      local bw = Kit.textWidth("micro", choice) + 14 * s
      if Kit.chip(chipX, fy, bw, fh, choice, on, PAL.green, PAL.steel,
          "Use " .. choice .. " for the " .. slot.label .. " boot screen") then
        setScreen(S, slot.id, choice, App)
        cur = choice
      end
      chipX = chipX + bw + 4 * s
    end
    fy = fy + fh + 6 * s
    local v = RegList.field(App, "ui_boot_" .. slot.id, fx, fy, viewW - labelW, fh,
      cur, slot.id)
    if v ~= cur then setScreen(S, slot.id, v, App) end
    if owned then
      Kit.text("micro", "override", fx + viewW - labelW - 70 * s, fy + 8 * s, PAL.yellow)
    end
    fy = fy + fh + 12 * s
  end

  FormPane.finish(S, "uiBootScroll", contentTop, fy, view)
end

-- ---- Theme ----

local THEME_DEFAULTS = {
  cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE,
  textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 },
  choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 },
}

local function themeNum(S, key, fallback)
  local v = select(1, eff(S, "theme", key))
  if type(v) == "number" then return v end
  return fallback
end

local function themeBox(S, boxKey)
  local p = S.project and S.project.theme and S.project.theme[boxKey]
  local d = dataField(S, "theme")[boxKey]
  local base = THEME_DEFAULTS[boxKey] or {}
  local out = {}
  for k, def in pairs(base) do
    if type(p) == "table" and p[k] ~= nil then
      out[k] = p[k]
    elseif type(d) == "table" and d[k] ~= nil then
      out[k] = d[k]
    else
      out[k] = def
    end
  end
  return out
end

local function setThemeBox(S, boxKey, field, val, App)
  local theme = ensureBucket(S, "theme")
  theme[boxKey] = theme[boxKey] or {}
  theme[boxKey][field] = val
  App.markDirty()
end

local function drawTheme(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "theme")
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiThemeScroll", "theme", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s

  Kit.caption(viewX, fy, "DIALOGUE THEME")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "theme", viewX, fy, viewW, s)

  local tb = themeBox(S, "textBox")
  local cb = themeBox(S, "choiceBox")

  for _, row in ipairs({
    { "cursor", "Cursor", THEME_DEFAULTS.cursor },
    { "cursorHollow", "Hollow", THEME_DEFAULTS.cursorHollow },
    { "moreArrow", "More ▾", THEME_DEFAULTS.moreArrow },
  }) do
    Kit.text("small", row[2], viewX, fy + 6 * s, PAL.caption)
    local cur = themeNum(S, row[1], row[3])
    local v = RegList.num(App, "ui_th_" .. row[1], viewX + labelW, fy, 80 * s, fh, cur)
    if v ~= cur then setKey(S, "theme", row[1], v, App) end
    Kit.text("micro", string.format("0x%02X", v % 256),
      viewX + labelW + 90 * s, fy + 8 * s, PAL.muted)
    fy = fy + fh + 8 * s
  end

  Kit.caption(viewX, fy, "TEXT BOX")
  fy = fy + 22 * s
  for _, f in ipairs({ "tx", "ty", "tw", "th", "maxCols" }) do
    Kit.text("small", f, viewX, fy + 6 * s, PAL.caption)
    local cur = tb[f] or 0
    local v = RegList.num(App, "ui_tb_" .. f, viewX + labelW, fy, 80 * s, fh, cur)
    if v ~= cur then setThemeBox(S, "textBox", f, v, App) end
    fy = fy + fh + 6 * s
  end

  Kit.caption(viewX, fy, "CHOICE BOX")
  fy = fy + 22 * s
  for _, f in ipairs({ "tx", "ty", "tw", "th" }) do
    Kit.text("small", f, viewX, fy + 6 * s, PAL.caption)
    local cur = cb[f] or 0
    local v = RegList.num(App, "ui_cb_" .. f, viewX + labelW, fy, 80 * s, fh, cur)
    if v ~= cur then setThemeBox(S, "choiceBox", f, v, App) end
    fy = fy + fh + 6 * s
  end

  FormPane.finish(S, "uiThemeScroll", contentTop, fy, view)
end

-- ---- Fonts ----

local function fontData(S)
  return (S.data and S.data.font and S.data.font.pages) or {}
end

local function resolveFont(S, id)
  if S.project and S.project.font and S.project.font[id] then
    return S.project.font[id], true
  end
  return fontData(S)[id], false
end

local function ensureFont(S, id, App)
  local proj = ensureBucket(S, "font")
  if proj[id] then return proj[id] end
  local src = fontData(S)[id]
  local copy = {}
  if type(src) == "table" then
    for k, v in pairs(src) do
      if type(v) ~= "function" then copy[k] = v end
    end
    copy._isNew = false
  else
    copy = { image = "assets/font/" .. id .. ".png", base = 0,
             glyphsPerRow = 16, _isNew = true }
  end
  proj[id] = copy
  if App then App.markDirty() end
  return copy
end

local function drawFonts(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "font")
  local proj = S.project.font
  local data = fontData(S)
  local ids = RegList.mergeIds(proj, data)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "FONT PAGES", ids, {
      queryKey = "uiFontQuery", offsetKey = "uiFontOffset", selKey = "uiFontId",
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
    })
  if not S.uiFontId then S.uiFontId = shown[1] end
  local id = S.uiFontId
  if not id then
    Kit.text("micro", "(no font pages in data)", formX + 12 * s, listY + 12 * s, PAL.faint)
    return
  end
  local rec, owned = resolveFont(S, id)
  rec = rec or {}

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "uiFontScroll", tostring(id), owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s

  Kit.caption(viewX, fy, id .. (owned and "" or "  (vanilla)"))
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "fonts", viewX, fy, viewW, s)
  local fieldW = viewW - labelW - 12 * s

  local function ensure()
    return ensureFont(S, id, App)
  end

  Kit.text("small", "Image", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(rec.image or "")
    local fx = viewX + labelW
    local v = RegList.field(App, "ui_font_img", fx, fy,
      math.max(40 * s, fieldW - 100 * s), fh, cur, "assets/...")
    if v ~= cur then ensure().image = v; App.markDirty() end
    if Kit.button(fx + fieldW - 96 * s, fy, 96 * s, fh, "Browse", {
        kind = "ghost" }) then
      browseImage(App, "Font sheet", function(rel)
        ensure().image = rel
        App.markDirty()
      end)
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Base", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = rec.base or 0
    local v = RegList.num(App, "ui_font_base", viewX + labelW, fy, 80 * s, fh, cur)
    if v ~= cur then ensure().base = v end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Glyphs/row", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = rec.glyphsPerRow or 16
    local v = RegList.num(App, "ui_font_gpr", viewX + labelW, fy, 80 * s, fh, cur)
    v = math.max(1, v)
    if v ~= cur then ensure().glyphsPerRow = v end
  end
  fy = fy + fh + 8 * s

  if owned and Kit.button(viewX, fy, 120 * s, fh, "Revert", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiFontScroll", contentTop, fy, view)
end

-- ---- Strings ----

local function stringIds(S)
  local seen, ids = {}, {}
  local function add(k)
    if type(k) == "string" and k ~= "" and not seen[k] then
      seen[k] = true
      ids[#ids + 1] = k
    end
  end
  for _, k in ipairs(COMMON_STRINGS) do add(k) end
  if S.data and type(S.data.strings) == "table" then
    for k in pairs(S.data.strings) do add(k) end
  end
  if S.project and type(S.project.strings) == "table" then
    for k in pairs(S.project.strings) do add(k) end
  end
  table.sort(ids)
  return ids
end

local function drawStrings(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "strings")
  local proj = S.project.strings
  local ids = stringIds(S)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "STRINGS", ids, {
      queryKey = "uiStrQuery", offsetKey = "uiStrOffset", selKey = "uiStrId",
      accent = PAL.blue,
      isOwned = function(id)
        return type(proj[id]) == "string" and proj[id] ~= ""
      end,
    })
  if not S.uiStrId then S.uiStrId = shown[1] end
  local id = S.uiStrId
  if not id then return end

  local dataVal = S.data and S.data.strings and S.data.strings[id]
  local cur = proj[id]
  if type(cur) ~= "string" then cur = (type(dataVal) == "string" and dataVal) or "" end
  local owned = type(proj[id]) == "string"

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "uiStrScroll", tostring(id), owned and 44 * s or 12 * s)
  local contentTop = fy
  local fh = 28 * s

  Kit.caption(viewX, fy, "SOURCE → OVERRIDE")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "strings", viewX, fy, viewW, s)
  Kit.text("micro", "Source key", viewX, fy, PAL.caption)
  fy = fy + 16 * s
  Kit.text("small", Kit.ellipsize("small", id, viewW), viewX, fy, PAL.muted)
  fy = fy + 22 * s

  Kit.text("micro", "Override text", viewX, fy, PAL.caption)
  fy = fy + 16 * s
  local v = RegList.field(App, "ui_str_body", viewX, fy, viewW, fh, cur, id)
  if v ~= cur then
    if v == "" then
      proj[id] = nil
    else
      proj[id] = v
    end
    App.markDirty()
  end
  fy = fy + fh + 10 * s

  Kit.text("micro", "Add custom source key:", viewX, fy, PAL.caption)
  fy = fy + 18 * s
  local newKey = RegList.field(App, "ui_str_new", viewX, fy, viewW - 100 * s, fh,
    S.uiStrNewKey or "", "New source…")
  if newKey ~= (S.uiStrNewKey or "") then S.uiStrNewKey = newKey end
  if Kit.button(viewX + viewW - 92 * s, fy, 92 * s, fh, "Add", { kind = "good" }) then
    local k = tostring(S.uiStrNewKey or ""):match("^%s*(.-)%s*$")
    if k and k ~= "" then
      proj[k] = proj[k] or k
      S.uiStrId = k
      S.uiStrNewKey = ""
      App.markDirty()
    end
  end
  fy = fy + fh + 8 * s

  if owned and Kit.button(viewX, fy, 120 * s, fh, "Clear", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiStrScroll", contentTop, fy, view)
end

-- ---- Town map ----

local function townLocIds(S)
  local seen, ids = {}, {}
  local function addFrom(locs)
    if type(locs) ~= "table" then return end
    for k in pairs(locs) do
      if type(k) == "string" and not seen[k] then
        seen[k] = true
        ids[#ids + 1] = k
      end
    end
  end
  addFrom(S.project and S.project.townMap and S.project.townMap.locations)
  addFrom(dataField(S, "townMap").locations)
  table.sort(ids)
  return ids
end

local function locRec(S, id)
  local p = S.project and S.project.townMap and S.project.townMap.locations
  if p and p[id] then return p[id], true end
  local d = dataField(S, "townMap").locations
  if d and d[id] then return d[id], false end
  return { x = 0, y = 0, name = id }, false
end

local function ensureLoc(S, id, App)
  local tm = ensureBucket(S, "townMap")
  tm.locations = tm.locations or {}
  if not tm.locations[id] then
    local src = select(1, locRec(S, id))
    tm.locations[id] = {
      x = (src and src.x) or 0,
      y = (src and src.y) or 0,
      name = (src and src.name) or id,
      index = src and src.index,
      id = (src and src.id) or id,
    }
    if App then App.markDirty() end
  end
  return tm.locations[id]
end

local function drawTownMap(S, x, y, w, h, App)
  local s = Kit.scale
  local tm = ensureBucket(S, "townMap")
  local gen2 = Generation.isGen2(S)
  local ids = townLocIds(S)
  if #ids == 0 then ids = { gen2 and "LANDMARK_NEW_BARK_TOWN" or "PALLET_TOWN" } end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    gen2 and "LANDMARKS" or "LOCATIONS", ids, {
      queryKey = "uiTmQuery", offsetKey = "uiTmOffset", selKey = "uiTmLoc",
      accent = PAL.green,
      isOwned = function(id)
        return tm.locations and tm.locations[id] ~= nil
      end,
      listW = math.min(180 * s, w * 0.28),
    })

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "uiTmScroll", "townmap|" .. tostring(S.uiTmLoc), 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s

  Kit.caption(viewX, fy, gen2 and "POKEGEAR LANDMARKS" or "TOWN MAP")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "townmap", viewX, fy, viewW, s)

  if not gen2 then
    Kit.text("small", "Grid px", viewX, fy + 6 * s, PAL.caption)
    do
      local d = dataField(S, "townMap")
      local cur = tm.gridPixelSize or d.gridPixelSize or 8
      local v = RegList.num(App, "ui_tm_grid", viewX + labelW, fy, 80 * s, fh, cur)
      if v ~= cur then tm.gridPixelSize = v; App.markDirty() end
    end
    fy = fy + fh + 8 * s

    local dBg = dataField(S, "townMap")
    local function bgPath(key, fallback)
      local bg = tm.background
      if type(bg) ~= "table" then bg = dBg.background end
      local p = ""
      if type(bg) == "table" then p = pathOf(bg[key]) end
      if p == "" then p = fallback end
      return p
    end
    local function setBg(key, p)
      if type(tm.background) ~= "table" then tm.background = {} end
      if p == nil or p == "" then
        tm.background[key] = nil
      else
        local rec = tm.background[key]
        if type(rec) == "table" then
          rec.path = p
        else
          tm.background[key] = { path = p }
        end
      end
      App.markDirty()
      pcall(function() require("UiPreview").rebuild(S) end)
    end
    fy = imageRow(S, App, viewX, fy, labelW, viewW - labelW - 12 * s, fh, s,
      "Tiles", "ui_tm_tiles",
      bgPath("tiles", "assets/generated/townmap/tiles.png"),
      function(p) setBg("tiles", p) end, "Town map 8x8 tile sheet")
    fy = imageRow(S, App, viewX, fy, labelW, viewW - labelW - 12 * s, fh, s,
      "Cursor", "ui_tm_cursor",
      bgPath("cursor", "assets/generated/townmap/cursor.png"),
      function(p) setBg("cursor", p) end, "Blinking town-map cursor")
  else
    Kit.text("micro", "Edits emit mod.content.landmarks:patch · coords are screen px",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    Kit.text("small", "Region", viewX, fy + 6 * s, PAL.caption)
    do
      local cur = S.uiTmRegion or "auto"
      local opts = { "auto", "johto", "kanto" }
      if Kit.button(viewX + labelW, fy, 120 * s, fh,
          Kit.ellipsize("small", cur:upper(), 110 * s), {
            kind = "ghost",
            tooltip = "Pokegear map tilemap (auto follows landmark index)",
          }) then
        local i = 1
        for n, o in ipairs(opts) do if o == cur then i = n; break end end
        S.uiTmRegion = opts[(i % #opts) + 1]
        if S.uiTmRegion == "auto" then S.uiTmRegion = nil end
        pcall(function() require("UiPreview").rebuild(S) end)
      end
    end
    fy = fy + fh + 8 * s
  end

  if not S.uiTmLoc then S.uiTmLoc = shown[1] end
  local id = S.uiTmLoc
  if id then
    Kit.caption(viewX, fy, (gen2 and "LANDMARK  " or "LOCATION  ") .. id)
    fy = fy + 22 * s
    local rec = locRec(S, id)
    Kit.text("small", "Name", viewX, fy + 6 * s, PAL.caption)
    do
      local cur = tostring(rec.name or "")
      local v = RegList.field(App, "ui_tm_name", viewX + labelW, fy,
        viewW - labelW, fh, cur, id)
      if v ~= cur then ensureLoc(S, id, App).name = v end
    end
    fy = fy + fh + 6 * s
    Kit.text("small", "X", viewX, fy + 6 * s, PAL.caption)
    do
      local cur = rec.x or 0
      local v = RegList.num(App, "ui_tm_x", viewX + labelW, fy, 80 * s, fh, cur)
      if v ~= cur then
        ensureLoc(S, id, App).x = v
        pcall(function() require("UiPreview").rebuild(S) end)
      end
    end
    fy = fy + fh + 6 * s
    Kit.text("small", "Y", viewX, fy + 6 * s, PAL.caption)
    do
      local cur = rec.y or 0
      local v = RegList.num(App, "ui_tm_y", viewX + labelW, fy, 80 * s, fh, cur)
      if v ~= cur then
        ensureLoc(S, id, App).y = v
        pcall(function() require("UiPreview").rebuild(S) end)
      end
    end
    fy = fy + fh + 6 * s
    if gen2 then
      Kit.text("small", "Index", viewX, fy + 6 * s, PAL.caption)
      do
        local cur = tonumber(rec.index) or 0
        local v = RegList.num(App, "ui_tm_idx", viewX + labelW, fy, 80 * s, fh, cur)
        Kit.text("micro", "≥46 = Kanto map", viewX + labelW + 90 * s, fy + 8 * s, PAL.faint)
        if v ~= cur then
          ensureLoc(S, id, App).index = v
          pcall(function() require("UiPreview").rebuild(S) end)
        end
      end
      fy = fy + fh + 8 * s
    else
      fy = fy + 2 * s
    end

    if tm.locations and tm.locations[id]
        and Kit.button(viewX, fy, 120 * s, fh, "Revert loc", { kind = "danger" }) then
      tm.locations[id] = nil
      App.markDirty()
    end
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", gen2 and "Add landmark id:" or "Add location id:", viewX, fy, PAL.caption)
  fy = fy + 16 * s
  local newId = RegList.field(App, "ui_tm_new", viewX, fy, viewW - 100 * s, fh,
    S.uiTmNewId or "", gen2 and "LANDMARK_…" or "MAP_ID")
  if newId ~= (S.uiTmNewId or "") then S.uiTmNewId = newId end
  if Kit.button(viewX + viewW - 92 * s, fy, 92 * s, fh, "Add", { kind = "good" }) then
    local k = tostring(S.uiTmNewId or ""):match("^%s*(.-)%s*$")
    if k and k ~= "" then
      local row = ensureLoc(S, k, App)
      if gen2 and (row.index == nil) then
        local maxIdx = 0
        for _, e in pairs(dataField(S, "townMap").locations or {}) do
          if type(e) == "table" and tonumber(e.index) then
            maxIdx = math.max(maxIdx, tonumber(e.index))
          end
        end
        for _, e in pairs(tm.locations or {}) do
          if type(e) == "table" and tonumber(e.index) then
            maxIdx = math.max(maxIdx, tonumber(e.index))
          end
        end
        row.index = maxIdx + 1
      end
      S.uiTmLoc = k
      S.uiTmNewId = ""
      pcall(function() require("UiPreview").rebuild(S) end)
    end
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiTmScroll", contentTop, fy, view)
end

-- ---- Badges ----

local function dataBadges(S)
  local c = S.data and S.data.constants
  return (c and c.badges) or {}
end

local function ensureBadges(S, App)
  State.ensureProjectFields(S.project)
  S.project.constants = S.project.constants or {}
  if not S.project.constants.badges or #S.project.constants.badges == 0 then
    local src = dataBadges(S)
    S.project.constants.badges = {}
    for i, row in ipairs(src) do
      S.project.constants.badges[i] = {
        id = row.id or "",
        name = row.name or "",
        icon = row.icon,
      }
    end
    if App then App.markDirty() end
  end
  return S.project.constants.badges
end

local function badgeRows(S)
  local c = S.project and S.project.constants
  if c and c.badges and #c.badges > 0 then return c.badges end
  return dataBadges(S)
end

local JOHTO_BADGE_NAMES = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING",
}
local KANTO_BADGE_NAMES = {
  "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH",
}

local function trainerCardGfx(S)
  local gfx = S.data and (S.data.gen2MenuGfx or S.data.menu_gfx)
  return (gfx and gfx.trainerCard) or {}
end

local function drawBadgesGen2(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  S.project.trainerCard = S.project.trainerCard or {}
  local proj = S.project.trainerCard
  local base = trainerCardGfx(S)

  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiBdgScroll", "badges-g2", 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, "TRAINER CARD BADGES")
  fy = fy + 22 * s
  Kit.text("micro", "Sheets → gen2MenuGfx.trainerCard (Save merges on mods.loaded)",
    viewX, fy, PAL.muted)
  fy = fy + 18 * s
  fy = UiPreview.draw(S, "badges", viewX, fy, viewW, s)

  local function setSheet(key, p)
    proj[key] = p
    App.markDirty()
    pcall(function() require("UiPreview").rebuild(S) end)
  end

  local badges = pathOf(proj.badges or base.badges)
  local leaders = pathOf(proj.leaders or base.leaders)
  local card = pathOf(proj.card or base.card)
  local status = pathOf(proj.status or base.status)
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Badges",
    "ui_bdg_sheet", badges, function(p) setSheet("badges", p) end,
    "Trainer card badge icon sheet")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Leaders",
    "ui_bdg_leaders", leaders, function(p) setSheet("leaders", p) end,
    "Gym leader mugshot sheet")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Card",
    "ui_bdg_card", card, function(p) setSheet("card", p) end,
    "Trainer card background")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Status",
    "ui_bdg_status", status, function(p) setSheet("status", p) end,
    "Status screen background")

  Kit.caption(viewX, fy, "JOHTO")
  fy = fy + 20 * s
  Kit.text("micro", table.concat(JOHTO_BADGE_NAMES, " · "), viewX, fy, PAL.muted)
  fy = fy + 18 * s
  Kit.caption(viewX, fy, "KANTO")
  fy = fy + 20 * s
  Kit.text("micro", table.concat(KANTO_BADGE_NAMES, " · "), viewX, fy, PAL.muted)
  fy = fy + 22 * s

  if next(proj) and Kit.button(viewX, fy, 120 * s, fh, "Clear", { kind = "danger" }) then
    S.project.trainerCard = {}
    App.markDirty()
    pcall(function() require("UiPreview").rebuild(S) end)
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiBdgScroll", contentTop, fy, view)
end

local function drawBadges(S, x, y, w, h, App)
  if Generation.isGen2(S) then
    return drawBadgesGen2(S, x, y, w, h, App)
  end
  local s = Kit.scale
  local badges = badgeRows(S)
  local ids = {}
  for i, b in ipairs(badges) do
    ids[i] = tostring(b.id or ("badge_" .. i))
  end
  if #ids == 0 then ids = { "(none)" } end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "BADGES", ids, {
      queryKey = "uiBdgQuery", offsetKey = "uiBdgOffset", selKey = "uiBdgId",
      accent = PAL.yellow,
      isOwned = function(id)
        local rows = S.project and S.project.constants and S.project.constants.badges
        if not rows then return false end
        for _, b in ipairs(rows) do
          if tostring(b.id) == id and b.icon then return true end
        end
        return rows ~= nil
      end,
    })

  if not S.uiBdgId then S.uiBdgId = shown[1] end
  local sel = S.uiBdgId
  local idx = 1
  for i, b in ipairs(badges) do
    if tostring(b.id or ("badge_" .. i)) == sel then idx = i; break end
  end
  local badge = badges[idx] or { id = "", name = "" }

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "uiBdgScroll", tostring(sel), 44 * s)
  local contentTop = fy
  local labelW = 90 * s
  local fh = 28 * s

  Kit.caption(viewX, fy, "BADGE ICON")
  fy = fy + 24 * s
  fy = UiPreview.draw(S, "badges", viewX, fy, viewW, s)

  local fieldW = viewW - labelW - 12 * s
  State.ensureProjectFields(S.project)
  S.project.trainerCard = S.project.trainerCard or {}
  local tc = S.project.trainerCard
  local function setCard(key, p)
    tc[key] = p
    App.markDirty()
    pcall(function() require("UiPreview").rebuild(S) end)
  end
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet",
    "ui_bdg_sheet", pathOf(tc.badges) ~= "" and pathOf(tc.badges)
      or "assets/generated/trainer_card/badges.png",
    function(p) setCard("badges", p) end,
    "Stacked gym-leader face + badge pairs")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Numbers",
    "ui_bdg_nums", pathOf(tc.numbers) ~= "" and pathOf(tc.numbers)
      or "assets/generated/trainer_card/badge_numbers.png",
    function(p) setCard("numbers", p) end,
    "1–8 badge number tiles")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Frame",
    "ui_bdg_frame", pathOf(tc.frame) ~= "" and pathOf(tc.frame)
      or "assets/generated/trainer_card/trainer_info.png",
    function(p) setCard("frame", p) end,
    "Trainer-card window frame tiles")
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Circle",
    "ui_bdg_circle", pathOf(tc.circle) ~= "" and pathOf(tc.circle)
      or "assets/generated/trainer_card/circle_tile.png",
    function(p) setCard("circle", p) end,
    "BADGES banner circle tile")

  local icon = pathOf(badge.icon)

  Kit.text("small", "Id", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(badge.id or "")
    local v = RegList.field(App, "ui_bdg_id", viewX + labelW, fy, fieldW, fh,
      cur, "BOULDERBADGE")
    if v ~= cur then
      local rows = ensureBadges(S, App)
      rows[idx] = rows[idx] or {}
      rows[idx].id = v
      S.uiBdgId = v
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Name", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(badge.name or "")
    local v = RegList.field(App, "ui_bdg_nm", viewX + labelW, fy, fieldW, fh,
      cur, "Boulder")
    if v ~= cur then
      local rows = ensureBadges(S, App)
      rows[idx] = rows[idx] or {}
      rows[idx].name = v
    end
  end
  fy = fy + fh + 8 * s

  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Icon",
    "ui_bdg_icon", icon, function(p)
      local rows = ensureBadges(S, App)
      rows[idx] = rows[idx] or {}
      rows[idx].icon = p
      App.markDirty()
    end)

  if Kit.button(viewX, fy, 100 * s, fh, "+ Badge", { kind = "good" }) then
    local rows = ensureBadges(S, App)
    rows[#rows + 1] = { id = "NEW_BADGE", name = "Badge" }
    S.uiBdgId = "NEW_BADGE"
    App.markDirty()
  end
  if #badges > 0 and Kit.button(viewX + 110 * s, fy, 100 * s, fh, "Remove", {
      kind = "danger" }) then
    local rows = ensureBadges(S, App)
    table.remove(rows, idx)
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "uiBdgScroll", contentTop, fy, view)
end

-- ---- minigames ----

local MINIGAMES_GEN2 = {
  { id = "slots", label = "Slots" },
  { id = "cardflip", label = "Card flip" },
  { id = "unown", label = "Unown puzzle" },
}

local MINIGAMES_GEN1 = {
  { id = "slots", label = "Slots" },
  { id = "surf", label = "Surf Pikachu" },
}

local SLOT_TEXT_ROWS = {
  { key = "betHowMany", label = "Bet how many" },
  { key = "start", label = "Start" },
  { key = "notEnough", label = "Not enough" },
  { key = "ranOut", label = "Ran out" },
  { key = "playAgain", label = "Play again" },
  { key = "darn", label = "Darn" },
}

local CARD_TEXT_ROWS = {
  { key = "playWithThree", label = "Play with 3" },
  { key = "notEnough", label = "Not enough" },
  { key = "chooseACard", label = "Choose a card" },
  { key = "placeYourBet", label = "Place your bet" },
  { key = "playAgain", label = "Play again" },
  { key = "shuffled", label = "Shuffled" },
  { key = "yeah", label = "Yeah" },
  { key = "darn", label = "Darn" },
}

local SURF_TEXT_ROWS = {
  { key = "beach", label = "Beach title" },
  { key = "hiScore", label = "Hi-Score line" },
  { key = "pressStart", label = "Press start" },
  { key = "hpLeft", label = "HP Left" },
  { key = "radness", label = "Radness" },
  { key = "total", label = "Total" },
  { key = "pts", label = "Pts" },
  { key = "hiScoreRecord", label = "Hi-Score!!" },
}

local SURF_ART_ROWS = {
  { key = "bg", label = "Waves",
    fallback = "assets/generated/minigame/surf_1a.png",
    tip = "Water / beach / score tiles (surf_1a)" },
  { key = "sprites", label = "Sprites",
    fallback = "assets/generated/minigame/surf_1b.png",
    tip = "Pikachu poses, clouds, HUD digits (surf_1b)" },
  { key = "intro", label = "Intro",
    fallback = "assets/generated/minigame/surf_1c.png",
    tip = "Logo, poses, and Use Control Pad to Surf (surf_1c)" },
  { key = "titleBg", label = "Title BG",
    fallback = "assets/generated/minigame/title_bg.png",
    tip = "Pikachu's Beach title composite" },
}

local UNOWN_PUZZLES = { "Kabuto", "Omanyte", "Aerodactyl", "Ho-Oh" }

local MINIGAME_PALS = {
  slots = {
    { id = "SLOTS1", label = "Reels / text (SLOTS1)" },
    { id = "SLOTS2", label = "Top chrome (SLOTS2)" },
    { id = "SLOTS3", label = "Mid band (SLOTS3)" },
    { id = "SLOTS4", label = "Inner band (SLOTS4)" },
  },
  surf = {
    { id = "PIKACHUS_BEACH", label = "Beach / ride" },
    { id = "PIKACHUS_BEACH_TITLE", label = "Title logo" },
  },
}

local UNOWN_PAL_FALLBACK = {
  palette = {
    { 255, 255, 255 }, { 197, 165, 90 }, { 148, 107, 90 }, { 0, 0, 0 },
  },
  cursorPalette = {
    { 255, 0, 0 }, { 197, 165, 90 }, { 148, 107, 90 }, { 255, 0, 0 },
  },
}

local function parseRgb(s, fallback)
  local r, g, b = tostring(s or ""):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if r then return { tonumber(r), tonumber(g), tonumber(b) } end
  return fallback or { 0, 0, 0 }
end

local function fmtRgb(c)
  if type(c) ~= "table" then return "0,0,0" end
  if c.r then return string.format("%d,%d,%d", c.r, c.g, c.b) end
  return string.format("%d,%d,%d", c[1] or 0, c[2] or 0, c[3] or 0)
end

local function clampRgb(rgb)
  return {
    math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
    math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
    math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
  }
end

local function drawColorSlots(S, App, viewX, fy, viewW, s, colors, fieldPrefix, onSlot)
  local fh = 28 * s
  for i = 1, 4 do
    local c = colors[i] or { 40, 40, 40 }
    Kit.text("small", "C" .. i, viewX, fy + 6 * s, PAL.caption)
    local sw = 28 * s
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
      (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("line", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
    love.graphics.setColor(1, 1, 1, 1)
    if Kit.press(viewX + 36 * s, fy + 2 * s, sw, 24 * s) then
      local slot = i
      ColorWheel.open(S, {
        title = "C" .. slot,
        color = c,
        onChange = function(rgb) onSlot(slot, clampRgb(rgb)) end,
        onApply = function(rgb) onSlot(slot, clampRgb(rgb)) end,
      })
    end
    local v = RegList.field(App, fieldPrefix .. i, viewX + 36 * s + sw + 8 * s, fy,
      viewW - 36 * s - sw - 8 * s, fh, fmtRgb(c), "r,g,b")
    local parsed = parseRgb(v, c)
    if fmtRgb(parsed) ~= fmtRgb(c) then
      onSlot(i, clampRgb(parsed))
    end
    fy = fy + fh + 6 * s
  end
  return fy
end

drawNamedPals = function(S, App, viewX, fy, viewW, s, rows)
  Kit.caption(viewX, fy, "PALETTES")
  fy = fy + 22 * s
  Kit.text("micro", "SGB palettes this screen colorizes with. Same names as GFX → Palettes.",
    viewX, fy, PAL.muted)
  fy = fy + 18 * s
  for _, row in ipairs(rows) do
    Kit.text("small", row.label, viewX, fy, PAL.caption)
    fy = fy + 18 * s
    local palId = row.id
    local colors = Preview.paletteColors(S, palId) or {
      { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
    }
    fy = drawColorSlots(S, App, viewX, fy, viewW, s, colors,
      "ui_mg_pal_" .. palId .. "_",
      function(slot, rgb)
        local rec = Preview.ensureProjectPalette(S, palId)
        if not rec then return end
        rec.colors = rec.colors or {}
        rec.colors[slot] = rgb
        Preview.invalidate()
        if App and App.markDirty then App.markDirty() end
      end)
  end
  return fy
end

local function menuGfxSrc(S, nest)
  if Generation.isGen2(S) then
    local gfx = S.data and (S.data.gen2MenuGfx or S.data.menu_gfx)
    return type(gfx) == "table" and gfx[nest] or nil
  end
  return S.data and S.data.field and S.data.field[nest]
end

local function menuGfxPath(S, nest, key)
  local p = S.project and S.project.menuGfx and S.project.menuGfx[nest]
  if type(p) == "table" and p[key] ~= nil then return pathOf(p[key]), true end
  local d = menuGfxSrc(S, nest)
  if type(d) == "table" then return pathOf(d[key]), false end
  return "", false
end

local function setMenuGfxPath(S, nest, key, val, App)
  setNested(S, "menuGfx", nest, key, val, App)
end

local function unownPicPath(S, index)
  local p = S.project and S.project.menuGfx and S.project.menuGfx.unownPuzzle
  if type(p) == "table" and type(p.pictures) == "table" and p.pictures[index] ~= nil then
    return pathOf(p.pictures[index]), true
  end
  local d = menuGfxSrc(S, "unownPuzzle")
  if type(d) == "table" and type(d.pictures) == "table" then
    return pathOf(d.pictures[index]), false
  end
  return "", false
end

local function setMinigameText(S, game, key, body, App)
  local b = ensureBucket(S, "minigames")
  b[game] = b[game] or {}
  b[game].texts = b[game].texts or {}
  if body == nil or body == "" then
    b[game].texts[key] = nil
    if not next(b[game].texts) then b[game].texts = nil end
    if not next(b[game]) then b[game] = nil end
  else
    b[game].texts[key] = body
  end
  if App then App.markDirty() end
end

local function drawMinigameMusic(S, App, x, y, w, h, game, emptyLabel)
  local p = S.project and S.project.minigames and S.project.minigames[game]
  local cur = tostring(p and p.music or "")
  ChoicePicker.songField(S, {
    x = x, y = y, w = w, h = h,
    current = cur,
    emptyLabel = emptyLabel or "Music_GameCorner",
    allowClear = true,
    onPick = function(id)
      setNested(S, "minigames", game, "music",
        (type(id) == "string" and id ~= "") and id or nil, App)
    end,
  })
end

local function drawMinigames(S, x, y, w, h, App)
  local s = Kit.scale
  ensureBucket(S, "minigames")
  ensureBucket(S, "menuGfx")
  local gen2 = Generation.isGen2(S)
  local games = gen2 and MINIGAMES_GEN2 or MINIGAMES_GEN1
  if not S.uiMinigame then S.uiMinigame = "slots" end
  local valid = false
  for i = 1, #games do
    if games[i].id == S.uiMinigame then valid = true; break end
  end
  if not valid then S.uiMinigame = "slots" end

  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiMiniScroll", gen2 and "mini-g2" or "mini-g1", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, gen2 and "MINIGAMES (GOLD/CRYSTAL)" or "MINIGAMES")
  fy = fy + 22 * s
  Kit.text("micro", gen2
      and "Game Corner slots / card flip, and Ruins of Alph Unown puzzle"
      or "Game Corner slots, and Yellow Surfing Pikachu (Pikachu's Beach)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s

  local cx = viewX
  for _, game in ipairs(games) do
    local on = S.uiMinigame == game.id
    local cw = 110 * s
    if Kit.chip(cx, fy, cw, fh, game.label, on, PAL.green, PAL.steel,
        "Preview " .. game.label) then
      S.uiMinigame = game.id
    end
    cx = cx + cw + 8 * s
  end
  fy = fy + fh + 10 * s

  fy = UiPreview.draw(S, "minigames", viewX, fy, viewW, s)

  local kind = S.uiMinigame or "slots"

  if gen2 and kind ~= "unown" then
    Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
    drawMinigameMusic(S, App, viewX + labelW, fy, fieldW, fh, kind,
      "Music_GameCorner")
    fy = fy + fh + 8 * s
  end

  if gen2 and kind == "slots" then
    Kit.caption(viewX, fy, "PROMPTS")
    fy = fy + 22 * s
    Kit.text("micro", "One line per row. Blank restores the vanilla line.",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    for _, row in ipairs(SLOT_TEXT_ROWS) do
      local body = select(1, UiPreview.minigameText(S, "slots", row.key))
      Kit.text("small", row.label, viewX, fy, PAL.caption)
      fy = fy + 18 * s
      local v = RegList.field(App, "ui_mg_s_" .. row.key, viewX, fy, viewW, fh,
        body, "line")
      if v ~= body then setMinigameText(S, "slots", row.key, v, App) end
      fy = fy + fh + 6 * s
    end
    Kit.caption(viewX, fy, "ART")
    fy = fy + 22 * s
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet 1",
      "ui_mg_slots_1", select(1, menuGfxPath(S, "slots", "sheet1")),
      function(p) setMenuGfxPath(S, "slots", "sheet1", p, App) end,
      "Machine / Vileplume tiles")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet 2",
      "ui_mg_slots_2", select(1, menuGfxPath(S, "slots", "sheet2")),
      function(p) setMenuGfxPath(S, "slots", "sheet2", p, App) end,
      "Reel symbols")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet 3",
      "ui_mg_slots_3", select(1, menuGfxPath(S, "slots", "sheet3")),
      function(p) setMenuGfxPath(S, "slots", "sheet3", p, App) end,
      "Golem / Chansey actors")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Actors",
      "ui_mg_slots_act", select(1, menuGfxPath(S, "slots", "actors")),
      function(p) setMenuGfxPath(S, "slots", "actors", p, App) end,
      "Optional actors sheet (overrides sheet 3 for Golem/Chansey)")
  elseif gen2 and kind == "cardflip" then
    Kit.caption(viewX, fy, "PROMPTS")
    fy = fy + 22 * s
    Kit.text("micro", "One line per row. Blank restores the vanilla line.",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    for _, row in ipairs(CARD_TEXT_ROWS) do
      local body = select(1, UiPreview.minigameText(S, "cardflip", row.key))
      Kit.text("small", row.label, viewX, fy, PAL.caption)
      fy = fy + 18 * s
      local v = RegList.field(App, "ui_mg_c_" .. row.key, viewX, fy, viewW, fh,
        body, "line")
      if v ~= body then setMinigameText(S, "cardflip", row.key, v, App) end
      fy = fy + fh + 6 * s
    end
    Kit.caption(viewX, fy, "ART")
    fy = fy + 22 * s
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet 1",
      "ui_mg_cf_1", select(1, menuGfxPath(S, "cardFlip", "sheet1")),
      function(p) setMenuGfxPath(S, "cardFlip", "sheet1", p, App) end,
      "Board tiles")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet 2",
      "ui_mg_cf_2", select(1, menuGfxPath(S, "cardFlip", "sheet2")),
      function(p) setMenuGfxPath(S, "cardFlip", "sheet2", p, App) end,
      "Card faces")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Sheet 3",
      "ui_mg_cf_3", select(1, menuGfxPath(S, "cardFlip", "sheet3")),
      function(p) setMenuGfxPath(S, "cardFlip", "sheet3", p, App) end,
      "Cursor corners")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "On",
      "ui_mg_cf_on", select(1, menuGfxPath(S, "cardFlip", "on")),
      function(p) setMenuGfxPath(S, "cardFlip", "on", p, App) end,
      "Played-hand light on")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Off",
      "ui_mg_cf_off", select(1, menuGfxPath(S, "cardFlip", "off")),
      function(p) setMenuGfxPath(S, "cardFlip", "off", p, App) end,
      "Played-hand light off")
  elseif gen2 and kind == "unown" then
    Kit.caption(viewX, fy, "PUZZLE")
    fy = fy + 22 * s
    S.uiUnownPuzzle = math.max(0, math.min(3, tonumber(S.uiUnownPuzzle) or 0))
    local ux = viewX
    for i, name in ipairs(UNOWN_PUZZLES) do
      local idx = i - 1
      local on = S.uiUnownPuzzle == idx
      local cw = 118 * s
      if ux + cw > viewX + viewW + 1 and ux > viewX then
        fy = fy + fh + 6 * s
        ux = viewX
      end
      if Kit.chip(ux, fy, cw, fh, name, on, PAL.green, PAL.steel,
          "Preview the " .. name .. " puzzle") then
        S.uiUnownPuzzle = idx
      end
      ux = ux + cw + 8 * s
    end
    fy = fy + fh + 10 * s
    Kit.caption(viewX, fy, "ART")
    fy = fy + 22 * s
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Chrome",
      "ui_mg_un_chrome", select(1, menuGfxPath(S, "unownPuzzle", "chrome")),
      function(p) setMenuGfxPath(S, "unownPuzzle", "chrome", p, App) end,
      "Start/Cancel box and caption tiles")
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Cursor",
      "ui_mg_un_cursor", select(1, menuGfxPath(S, "unownPuzzle", "cursor")),
      function(p) setMenuGfxPath(S, "unownPuzzle", "cursor", p, App) end,
      "Piece cursor bracket")
    for i, name in ipairs(UNOWN_PUZZLES) do
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, name,
        "ui_mg_un_pic" .. i, select(1, unownPicPath(S, i)),
        function(p)
          setDeep(S, "menuGfx", { "unownPuzzle", "pictures", i }, p, App)
        end,
        name .. " puzzle picture")
    end
    Kit.caption(viewX, fy, "PALETTES")
    fy = fy + 22 * s
    Kit.text("micro", "Board (white / tan / brown / black) and red cursor bracket.",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    local function unownPal(key)
      local p = S.project and S.project.menuGfx and S.project.menuGfx.unownPuzzle
      if type(p) == "table" and type(p[key]) == "table" and p[key][1] then
        return p[key]
      end
      local d = menuGfxSrc(S, "unownPuzzle")
      if type(d) == "table" and type(d[key]) == "table" then return d[key] end
      return UNOWN_PAL_FALLBACK[key]
    end
    local function setUnownPal(key, slot, rgb)
      local cur = unownPal(key)
      local copy = {}
      for i = 1, 4 do
        local c = cur[i] or { 0, 0, 0 }
        copy[i] = { c[1] or 0, c[2] or 0, c[3] or 0 }
      end
      copy[slot] = rgb
      setDeep(S, "menuGfx", { "unownPuzzle", key }, copy, App)
      Preview.invalidate()
    end
    Kit.text("small", "Board", viewX, fy, PAL.caption)
    fy = fy + 18 * s
    fy = drawColorSlots(S, App, viewX, fy, viewW, s, unownPal("palette"),
      "ui_mg_un_pal_", function(slot, rgb) setUnownPal("palette", slot, rgb) end)
    Kit.text("small", "Cursor", viewX, fy, PAL.caption)
    fy = fy + 18 * s
    fy = drawColorSlots(S, App, viewX, fy, viewW, s, unownPal("cursorPalette"),
      "ui_mg_un_cpal_", function(slot, rgb)
        setUnownPal("cursorPalette", slot, rgb)
      end)
  elseif kind == "surf" then
    Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
    drawMinigameMusic(S, App, viewX + labelW, fy, fieldW, fh, "surf",
      "Music_SurfingPikachu")
    fy = fy + fh + 8 * s

    Kit.caption(viewX, fy, "SCREEN")
    fy = fy + 22 * s
    S.uiSurfScreen = S.uiSurfScreen or "title"
    local screens = {
      { id = "title", label = "Title" },
      { id = "ride", label = "Ride" },
      { id = "results", label = "Results" },
    }
    local sx = viewX
    for _, row in ipairs(screens) do
      local on = S.uiSurfScreen == row.id
      if Kit.chip(sx, fy, 90 * s, fh, row.label, on, PAL.green, PAL.steel,
          "Preview the " .. row.label:lower() .. " screen") then
        S.uiSurfScreen = row.id
      end
      sx = sx + 98 * s
    end
    fy = fy + fh + 10 * s

    Kit.caption(viewX, fy, "TEXT")
    fy = fy + 22 * s
    Kit.text("micro", "Title and results lines. Hi-Score line may use %4d for the number.",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    for _, row in ipairs(SURF_TEXT_ROWS) do
      local body = select(1, UiPreview.minigameText(S, "surf", row.key))
      Kit.text("small", row.label, viewX, fy, PAL.caption)
      fy = fy + 18 * s
      local v = RegList.field(App, "ui_mg_surf_" .. row.key, viewX, fy, viewW, fh,
        body, "line")
      if v ~= body then setMinigameText(S, "surf", row.key, v, App) end
      fy = fy + fh + 6 * s
    end

    Kit.caption(viewX, fy, "ART")
    fy = fy + 22 * s
    Kit.text("micro", "Logo and Use Control Pad to Surf live on the intro sheet.",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    for _, row in ipairs(SURF_ART_ROWS) do
      local cur = select(1, menuGfxPath(S, "surfPikachu", row.key))
      if cur == "" then cur = row.fallback end
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, row.label,
        "ui_mg_surf_" .. row.key, cur,
        function(p) setMenuGfxPath(S, "surfPikachu", row.key, p, App) end,
        row.tip)
    end
    fy = drawNamedPals(S, App, viewX, fy, viewW, s, MINIGAME_PALS.surf)
  else
    Kit.caption(viewX, fy, "ART")
    fy = fy + 22 * s
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Symbols",
      "ui_mg_g1_sym", select(1, menuGfxPath(S, "slotSymbols", "sheet")),
      function(p) setMenuGfxPath(S, "slotSymbols", "sheet", p, App) end,
      "Reel symbol strip")
    do
      local p = S.project and S.project.menuGfx and S.project.menuGfx.slotSymbols
      local owned = ""
      if type(p) == "table" and type(p.tilemap) == "table" then
        owned = pathOf(p.tilemap.sheet)
      end
      local cur = owned
      if cur == "" then
        local d = menuGfxSrc(S, "slotSymbols")
        if type(d) == "table" and type(d.tilemap) == "table" then
          cur = pathOf(d.tilemap.sheet)
        end
      end
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Frame",
        "ui_mg_g1_tm", cur,
        function(path)
          setDeep(S, "menuGfx", { "slotSymbols", "tilemap", "sheet" }, path, App)
        end,
        "Machine frame tilemap sheet")
    end
    fy = drawNamedPals(S, App, viewX, fy, viewW, s, MINIGAME_PALS.slots)
  end

  local ownedMini = S.project.minigames and S.project.minigames[kind]
  if type(ownedMini) == "table" and next(ownedMini)
      and Kit.button(viewX, fy, 140 * s, fh, "Clear texts", {
        kind = "danger", tooltip = "Remove prompt / music overrides for this game",
      }) then
    S.project.minigames[kind] = nil
    App.markDirty()
  end
  fy = fy + fh + 8 * s
  FormPane.finish(S, "uiMiniScroll", contentTop, fy, view)
end

-- ---- shell ----

function Ui.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local modes = Generation.isGen2(S) and MODES_GEN2 or MODES_GEN1
  if S.uiMode == "theme" and Generation.isGen2(S) then
    S.uiMode = "title"
  end
  if S.uiMode == "elm" then
    S.uiMode = "oak"
  end
  local modeY = RegList.modeChips(S, "uiMode", modes, x, y, s)
  local mode = S.uiMode or "title"
  local bh = h - (modeY - y)
  if mode == "title" then
    drawTitle(S, x, modeY, w, bh, App)
  elseif mode == "intro" then
    drawIntro(S, x, modeY, w, bh, App)
  elseif mode == "oak" then
    drawOak(S, x, modeY, w, bh, App)
  elseif mode == "credits" then
    drawCredits(S, x, modeY, w, bh, App)
  elseif mode == "minigames" then
    drawMinigames(S, x, modeY, w, bh, App)
  elseif mode == "boot" then
    drawBoot(S, x, modeY, w, bh, App)
  elseif mode == "menus" then
    UiMenus.draw(S, x, modeY, w, bh, App)
  elseif mode == "theme" then
    drawTheme(S, x, modeY, w, bh, App)
  elseif mode == "fonts" then
    drawFonts(S, x, modeY, w, bh, App)
  elseif mode == "strings" then
    drawStrings(S, x, modeY, w, bh, App)
  elseif mode == "townmap" then
    drawTownMap(S, x, modeY, w, bh, App)
  else
    drawBadges(S, x, modeY, w, bh, App)
  end
end

return Ui
