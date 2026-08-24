-- UI tab: title/splash branding, boot screen ids, dialogue theme, fonts,
-- engine strings, town map, and badge icons.  Gen1 writes field.* via
-- project.title / intro / theme / townMap / boot; Gold (field gated) writes
-- data.title / gen2Intro / landmarks / gen2MenuGfx / gen2BootScreens.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local UiPreview = require("UiPreview")
local Generation = require("Generation")
local PAL = Theme.PAL

local Ui = {}

local MODES_GEN1 = {
  { id = "title", label = "Title",
    tip = "Logo, version ribbon, copyright, music, cycle species" },
  { id = "intro", label = "Intro",
    tip = "Studio splash, skip intro, Game Freak art paths" },
  { id = "boot", label = "Boot screens",
    tip = "splash / title / newGame screen registry ids" },
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
    tip = "GS cinema acts: water / grass / fire tile + sprite sheets" },
  { id = "boot", label = "Boot screens",
    tip = "Gen2CopyrightSplash → … → Gen2TitleState / Gen2OakSpeech ids" },
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

local function setKey(S, bucket, key, val, App)
  local b = ensureBucket(S, bucket)
  if val == nil or val == "" then
    b[key] = nil
  else
    b[key] = val
  end
  if App then App.markDirty() end
end

local function parseCsv(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    local t = part:match("^%s*(.-)%s*$")
    if t and t ~= "" then out[#out + 1] = t end
  end
  return out
end

local function joinCsv(list)
  if type(list) ~= "table" then return "" end
  local parts = {}
  for _, v in ipairs(list) do
    if type(v) == "string" and v ~= "" then parts[#parts + 1] = v end
  end
  return table.concat(parts, ", ")
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
    fieldId, path, onSet)
  Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
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
      { "image", "Logo" },
      { "screen", "Screen BG" },
      { "wordmark", "Wordmark" },
      { "suicune", "Suicune" },
      { "gem", "Gem" },
      { "copyright", "Copyright" },
      { "copyrightSplash", "© splash" },
    }
  else
    rows = {
      { "image", "Logo" },
      { "screen", "Screen BG" },
      { "clouds", "Clouds" },
      { "trail", "Trail" },
      { "hooh", "Ho-Oh" },
      { "copyright", "Copyright" },
      { "copyrightSplash", "© splash" },
    }
  end
  for _, row in ipairs(rows) do
    local key, label = row[1], row[2]
    local p = pathOf(select(1, eff(S, "title", key)))
    fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, label,
      "ui_title_" .. key, p, function(path)
        setKey(S, "title", key, path, App)
      end)
  end

  Kit.text("small", "Layout", viewX, fy + 6 * s, PAL.caption)
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
    local cur = select(1, eff(S, "title", row[1]))
    if type(cur) ~= "number" then cur = row[3] end
    local v = RegList.num(App, "ui_title_" .. row[1], viewX + labelW, fy, 80 * s, fh, cur)
    if v ~= cur then setKey(S, "title", row[1], v, App) end
    fy = fy + fh + 6 * s
  end

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
  do
    local cur = tostring(select(1, eff(S, "title", "music")) or "")
    local v = RegList.field(App, "ui_title_mus", viewX + labelW, fy, fieldW, fh,
      cur, "Music_TitleScreen")
    if v ~= cur then setKey(S, "title", "music", v ~= "" and v or nil, App) end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Cycle spp.", viewX, fy + 6 * s, PAL.caption)
  do
    local list = select(1, eff(S, "title", "cycleSpecies"))
    local cur = joinCsv(list)
    local v = RegList.field(App, "ui_title_cyc", viewX + labelW, fy, fieldW, fh,
      cur, "CHARIZARD, VENUSAUR")
    if v ~= cur then
      local parsed = parseCsv(v)
      setKey(S, "title", "cycleSpecies", #parsed > 0 and parsed or nil, App)
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Layout", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(select(1, eff(S, "title", "layout")) or "")
    local label = (cur ~= "" and cur) or "(default)"
    if Kit.button(viewX + labelW, fy, fieldW, fh,
        Kit.ellipsize("small", label, fieldW - 8 * s), { kind = "ghost" }) then
      local next = (cur == "") and "yellow_pikachu"
        or (cur == "yellow_pikachu") and "" or ""
      setKey(S, "title", "layout", next ~= "" and next or nil, App)
    end
  end
  fy = fy + fh + 8 * s

  local pika = pathOf(select(1, eff(S, "title", "pikachu")))
  local bubble = pathOf(select(1, eff(S, "title", "pikaBubble")))
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Pikachu",
    "ui_title_pika", pika, function(p) setKey(S, "title", "pikachu", p, App) end)
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Bubble",
    "ui_title_bub", bubble, function(p) setKey(S, "title", "pikaBubble", p, App) end)

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

  Kit.caption(viewX, fy, crystalUi(S) and "CRYSTAL INTRO" or "GS INTRO CINEMA")
  fy = fy + 22 * s
  Kit.text("micro", crystalUi(S)
      and "Unown / Suicune cinema (data.gen2Intro.acts)"
      or "Water → grass → fire acts (data.gen2Intro)",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  fy = UiPreview.draw(S, "intro", viewX, fy, viewW, s)

  for _, act in ipairs({ "water", "grass", "fire" }) do
    Kit.caption(viewX, fy, string.upper(act))
    fy = fy + 22 * s
    for _, key in ipairs({ "tiles", "sprites" }) do
      local p = pathOf(select(1, effNested(S, "intro", act, key)))
      fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s,
        act .. " " .. key, "ui_intro_" .. act .. "_" .. key, p, function(path)
          setNested(S, "intro", act, key, path, App)
        end)
    end
  end

  if next(S.project.intro) and Kit.button(viewX, fy, 120 * s, fh, "Clear all", {
      kind = "danger" }) then
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
  intro.studio = intro.studio or {}
  local fy, view, viewX, viewW = RegList.beginForm(S, x, y, w, h,
    "uiIntroScroll", "intro", 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - 12 * s

  Kit.caption(viewX, fy, "INTRO / SPLASH")
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
  do
    local skip = select(1, eff(S, "intro", "skip")) and true or false
    if Kit.chip(viewX + labelW, fy, 80 * s, fh, skip and "YES" or "NO",
        skip, PAL.yellow) then
      setKey(S, "intro", "skip", (not skip) and true or nil, App)
    end
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Music id", viewX, fy + 6 * s, PAL.caption)
  do
    local cur = tostring(select(1, eff(S, "intro", "music")) or "")
    local v = RegList.field(App, "ui_intro_mus", viewX + labelW, fy, fieldW, fh,
      cur, "optional")
    if v ~= cur then setKey(S, "intro", "music", v ~= "" and v or nil, App) end
  end
  fy = fy + fh + 8 * s

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

  FormPane.finish(S, "uiIntroScroll", contentTop, fy, view)
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
      if Kit.chip(chipX, fy, bw, fh, choice, on, PAL.green) then
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

    local bg = pathOf(tm.background or dataField(S, "townMap").background)
    fy = imageRow(S, App, viewX, fy, labelW, viewW - labelW - 12 * s, fh, s,
      "Background", "ui_tm_bg", bg, function(p)
        tm.background = p
        App.markDirty()
      end)
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
    "ui_bdg_sheet", badges, function(p) setSheet("badges", p) end)
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Leaders",
    "ui_bdg_leaders", leaders, function(p) setSheet("leaders", p) end)
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Card",
    "ui_bdg_card", card, function(p) setSheet("card", p) end)
  fy = imageRow(S, App, viewX, fy, labelW, fieldW, fh, s, "Status",
    "ui_bdg_status", status, function(p) setSheet("status", p) end)

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

  local icon = pathOf(badge.icon)
  local fieldW = viewW - labelW - 12 * s

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
  local modeY = RegList.modeChips(S, "uiMode", modes, x, y, s)
  local mode = S.uiMode or "title"
  local bh = h - (modeY - y)
  if mode == "title" then
    drawTitle(S, x, modeY, w, bh, App)
  elseif mode == "intro" then
    drawIntro(S, x, modeY, w, bh, App)
  elseif mode == "boot" then
    drawBoot(S, x, modeY, w, bh, App)
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
