-- Project tab: create / open mod, overview, boot/constants, validate.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local ModIO = require("ModIO")
local DataSource = require("DataSource")
local Generation = require("Generation")
local PAL = Theme.PAL

local Project = {}

local FACINGS = { "up", "down", "left", "right" }

local function dataBoot(S)
  return (S.data and S.data.field and S.data.field.boot) or {}
end

local function dataConstants(S)
  return (S.data and S.data.constants) or {}
end

local function bootField(S, key)
  local b = S.project.boot
  if b and b[key] ~= nil then return b[key] end
  return dataBoot(S)[key]
end

local function lastHealField(S, key)
  local lh = S.project.boot and S.project.boot.lastHeal
  if lh and lh[key] ~= nil then return lh[key] end
  local dlh = dataBoot(S).lastHeal
  return dlh and dlh[key]
end

local function constField(S, key)
  local c = S.project.constants
  if c and c[key] ~= nil then return c[key] end
  return dataConstants(S)[key]
end

local function setBoot(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.boot[key] = val
  App.markDirty()
end

local function setLastHeal(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.boot.lastHeal = S.project.boot.lastHeal or {}
  S.project.boot.lastHeal[key] = val
  App.markDirty()
end

local function setConst(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.constants[key] = val
  App.markDirty()
end

local function parseCsvIds(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function joinCsvIds(t)
  if type(t) ~= "table" then return "" end
  return table.concat(t, ", ")
end

local function badgeRows(S)
  local c = S.project.constants
  if c and c.badges and #c.badges > 0 then return c.badges end
  local dc = dataConstants(S).badges
  if type(dc) == "table" and #dc > 0 then return dc end
  return {}
end

local function ensureBadges(S, App)
  State.ensureProjectFields(S.project)
  if not S.project.constants.badges or #S.project.constants.badges == 0 then
    local src = dataConstants(S).badges
    S.project.constants.badges = {}
    if type(src) == "table" then
      for i, row in ipairs(src) do
        S.project.constants.badges[i] = {
          id = row.id or "",
          name = row.name or "",
        }
      end
    end
    App.markDirty()
  end
  return S.project.constants.badges
end

-- Prefer MK* ERROR / FAIL lines; tips at the end used to hide the real errors.
local function lastValidateLines(text, n)
  if not text or text == "" then return {} end
  local all, errors, other = {}, {}, {}
  for line in tostring(text):gmatch("[^\r\n]+") do
    all[#all + 1] = line
    local u = line:upper()
    if u:find("ERROR", 1, true) or u:find("FAIL ", 1, true) then
      errors[#errors + 1] = line
    elseif not line:find("optional tip", 1, true) then
      other[#other + 1] = line
    end
  end
  local pick = (#errors > 0) and errors or other
  if #pick == 0 then pick = all end
  if #pick <= n then return pick end
  local out = {}
  for i = 1, n do out[i] = pick[i] end
  return out
end

function Project.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local pad = 16 * s
  FormPane.track(S, "projectPageScroll",
    S.project and S.project.id or "no-project")
  local row, pageView = FormPane.begin(
    S, "projectPageScroll", x, y, w, h)
  local pageTop = row
  w = pageView.contentW or w

  Kit.caption(x, row, "1  PROJECT")
  row = row + 28 * s
  Kit.text("micro", "Create a project or open an existing mod to edit and test.",
    x, row, PAL.muted)
  row = row + 22 * s

  local cardY = row
  local innerX = x + pad
  local innerW = w - 2 * pad
  local cy = cardY + pad

  local mods = ModIO.listMods()
  local btnH = 32 * s
  local chipH = 28 * s
  local chipGap = 8 * s

  local chipRows = 1
  local mx = 0
  for i, mid in ipairs(mods) do
    if i > 12 then break end
    local bw = Kit.textWidth("button", mid) + 24 * s
    if mx > 0 and mx + bw > innerW then
      chipRows = chipRows + 1
      mx = 0
    end
    mx = mx + bw + chipGap
  end
  if #mods == 0 then chipRows = 0 end

  local contentH = pad
    + 14 * s + 6 * s + btnH + 10 * s + 14 * s + 16 * s + 14 * s + 6 * s
  if chipRows > 0 then
    contentH = contentH + chipRows * chipH + (chipRows - 1) * chipGap
  else
    contentH = contentH + 14 * s
  end
  contentH = contentH + pad

  Kit.card(x, cardY, w, contentH, 14 * s)

  Kit.text("small", "New mod id", innerX, cy, PAL.caption)
  cy = cy + 20 * s

  local idW = math.min(280 * s, innerW - 150 * s)
  local idVal = Kit.textfield("new_mod_id", innerX, cy, idW, btnH,
    S.newModId or "my_content", "my_content")
  if idVal ~= S.newModId then S.newModId = idVal end

  if Kit.button(innerX + idW + 10 * s, cy, 140 * s, btnH, "Create",
      { kind = "primary" }) then
    App.createMod(S.newModId)
  end
  cy = cy + btnH + 10 * s

  Kit.text("micro", "Creates mods/<id>/ with manifest, editor_project.lua, main.lua",
    innerX, cy, PAL.muted)
  cy = cy + 14 * s + 16 * s

  Kit.text("small", "Existing mods/", innerX, cy, PAL.caption)
  cy = cy + 20 * s

  if #mods == 0 then
    Kit.text("micro", "(none yet)", innerX, cy, PAL.faint)
  else
    local cx = innerX
    local shown = 0
    for _, mid in ipairs(mods) do
      if shown >= 12 then break end
      local bw = Kit.textWidth("button", mid) + 24 * s
      if cx > innerX and cx + bw > x + w - pad then
        cx = innerX
        cy = cy + chipH + chipGap
      end
      if Kit.button(cx, cy, bw, chipH, mid, {
            kind = (S.project and S.project.id == mid) and "primary" or "ghost",
          }) then
        App.openMod(ModIO.modsRoot() .. package.config:sub(1, 1) .. mid)
      end
      cx = cx + bw + chipGap
      shown = shown + 1
    end
  end

  row = cardY + contentH + 20 * s

  Kit.caption(x, row, "2  TARGET GAME")
  row = row + 28 * s
  Kit.text("micro", "Controls the ROM data used by the editor and the game Playtest boots.",
    x, row, PAL.muted)
  row = row + 22 * s
  local gameCardY = row
  local gameCardH = 86 * s
  Kit.card(x, gameCardY, w, gameCardH, 14 * s)
  local gameX = x + pad
  local gameW = w - 2 * pad
  row = gameCardY + pad
  local GameVersion = require("src.core.GameVersion")
  local curVer = S.version or App.dataVersion or "red"
  local gen = (GameVersion.generation and GameVersion.generation(curVer)) or 1
  local order = GameVersion.ORDER or { "red", "blue", "yellow", "gold", "silver" }
  local chipCount = math.max(1, #order)
  local chipGap = 8 * s
  local chipW = math.floor((gameW - (chipCount - 1) * chipGap) / chipCount)
  local cachePrefs = S.dataPrefs or DataSource.loadPrefs()
  for i, vid in ipairs(order) do
    local info = GameVersion.info(vid) or {}
    local label = info.label or vid
    local bx = gameX + (i - 1) * (chipW + chipGap)
    local kind = (vid == curVer) and "primary" or "ghost"
    local hasCache = DataSource.hasImportedCache(vid)
      or DataSource.hasLocalCache(vid)
      or (cachePrefs.recompRoot and DataSource.recompHasVersion(cachePrefs.recompRoot, vid))
    local cacheNote = hasCache and "cache ready" or "no cache yet — Import ROM"
    if Kit.button(bx, row, chipW, btnH, label, {
        kind = kind,
        tooltip = (info.displayName or label)
          .. " — Gen " .. tostring(GameVersion.generation(vid) or 1)
          .. "\n" .. cacheNote,
      }) then
      if App.setGameVersion then App.setGameVersion(vid) end
      if S.project then
        S.project.game = vid
        App.markDirty()
      end
    end
  end
  row = row + btnH + 8 * s
  Kit.text("micro",
    string.format("Authoring for %s (Gen %d). Import mounts %scache.",
      (GameVersion.info(curVer) and GameVersion.info(curVer).displayName) or curVer,
      gen,
      (GameVersion.cachePrefix and GameVersion.cachePrefix(curVer)) or ""),
    gameX, row, PAL.muted)
  row = gameCardY + gameCardH + 16 * s

  Kit.caption(x, row, "3  GAME DATA")
  row = row + 28 * s
  Kit.text("micro",
    "Choose where editor previews and validation read game data. This does not change the Playtest runtime.",
    x, row, PAL.muted)
  row = row + 22 * s
  local dataCardY = row
  local dataCardH = 140 * s
  Kit.card(x, dataCardY, w, dataCardH, 14 * s)
  local dataX = x + pad
  local dataW = w - 2 * pad
  row = dataCardY + pad
  local src = S.dataSource or "fixtures"
  local persistedPrefs = DataSource.loadPrefs()
  local prefs = S.dataPrefs or persistedPrefs
  local mountedRoot = DataSource.mountedRecompRoot
    and DataSource.mountedRecompRoot() or nil
  local recompRoot = mountedRoot
    or (prefs and prefs.recompRoot)
    or (persistedPrefs and persistedPrefs.recompRoot)
  if recompRoot == "" then recompRoot = nil end
  local validRecompRoot = recompRoot ~= nil
    and DataSource.isValidRecompRoot(recompRoot)
  local usingRecomp = src == "recomp" and validRecompRoot
  local srcLine = DataSource.label(src)
  if recompRoot then
    local linkState = usingRecomp and "Linked" or "Remembered"
    srcLine = srcLine .. " — " .. linkState .. ": " .. tostring(recompRoot)
  end
  Kit.text("small", Kit.ellipsize("small", srcLine, dataW), dataX, row, PAL.text)
  row = row + 22 * s
  Kit.text("micro", "Imported ROM = complete data  •  Fixtures = samples  •  Link Recomp = optional reuse",
    dataX, row, PAL.muted)
  row = row + 24 * s
  local dsGap = 10 * s
  local dsW = math.min(150 * s, math.floor((dataW - 2 * dsGap) / 3))
  if Kit.button(dataX, row, dsW, btnH, "Link Recomp", {
      kind = "primary",
      tooltip = "Use data/generated (or red|blue|yellow|gold|silver/) from a Gen1Recomp install",
    }) then
    App.pickFolder("Choose Gen1Recomp folder", function(path)
      App.linkRecompFolder(path)
    end, recompRoot)
  end
  if Kit.button(dataX + dsW + dsGap, row, dsW, btnH, "Import ROM", {
      kind = "accent",
      tooltip = "Import US Red/Blue/Yellow (.gb, 1 MiB) or Gold/Silver (.gbc, 2 MiB)\n"
        .. "into the versioned save-directory cache",
    }) then
    App.pickFile("Choose Pokemon ROM",
      "Game Boy ROM (*.gb;*.gbc)|*.gb;*.gbc|All (*.*)|*.*",
      function(path) App.importRomFile(path) end)
  end
  if Kit.button(dataX + 2 * (dsW + dsGap), row, dsW, btnH, "Use fixtures", {
      kind = "ghost",
      tooltip = "ROM-free stub data for authoring without a cache",
    }) then
    App.useFixturesData()
  end
  row = row + btnH + 8 * s
  if Kit.button(dataX, row, dsW, btnH, "Clear cache", {
      kind = "danger",
      tooltip = "Delete save-directory ROM caches (red|blue|yellow|gold|silver/…)\n"
        .. "and flush editor image caches, then reload data.\n"
        .. "Does not delete a Linked Gen1Recomp folder.",
  }) then
    if App.clearCache then App.clearCache() end
  end
  local remembered = recompRoot ~= nil
  if Kit.button(dataX + dsW + dsGap, row, dsW, btnH, "Use last link", {
      kind = "accent",
      enabled = validRecompRoot and not usingRecomp,
      tooltip = remembered
        and (not validRecompRoot
          and ("Previously linked folder is no longer available:\n"
            .. tostring(recompRoot))
          or usingRecomp
            and ("Already using:\n" .. tostring(recompRoot))
            or ("Reconnect without browsing:\n" .. tostring(recompRoot)))
        or "No previously linked Gen1Recomp folder",
  }) then
    App.linkRecompFolder(recompRoot)
  end
  local importedReady = DataSource.hasImportedCache(curVer)
  if Kit.button(dataX + 2 * (dsW + dsGap), row, dsW, btnH,
      "Use imported ROM", {
        kind = "accent",
        enabled = importedReady and src ~= "imported",
        tooltip = importedReady
          and (src == "imported"
            and "Already using this version's imported ROM cache"
            or "Reuse this version's imported ROM cache without selecting the ROM again")
          or "No imported ROM cache exists for the selected game version",
      }) then
    App.useImportedData()
  end
  row = dataCardY + dataCardH + 18 * s

  local fh = 28 * s
  Kit.caption(x, row, "4  CHECK & RUN")
  row = row + 28 * s
  Kit.text("micro",
    "Validate finds content errors. Playtest saves and launches only this mod with the selected game.",
    x, row, PAL.muted)
  row = row + 22 * s

  if not S.project then
    Kit.emptyBox(x, row, w, 120 * s, "No mod open")
    FormPane.finish(S, "projectPageScroll", pageTop,
      row + 120 * s + pad, pageView)
    return
  end

  State.ensureProjectFields(S.project)
  local p = S.project
  local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
  end

  local overviewH = 164 * s
  Kit.card(x, row, w, overviewH, 14 * s)
  Kit.text("title", p.name or p.id, x + 20 * s, row + 16 * s, PAL.heading)
  Kit.text("small", string.format(
    "Pokemon %d    Items %d    Maps %d    Tilesets %d",
    count(p.pokemon), count(p.items), count(p.maps), count(p.tilesets)),
    x + 20 * s, row + 52 * s, PAL.text)
  Kit.text("micro",
    "Save writes editor_project.lua + main.lua (or editor_apply.lua if main.lua is hand-written).",
    x + 20 * s, row + 78 * s, PAL.muted)
  local actionGap = 10 * s
  local actionW = math.floor((w - 40 * s - actionGap) / 2)
  if Kit.button(x + 20 * s, row + 108 * s,
      actionW, 36 * s, "Validate mod", {
        kind = "primary",
        tooltip = "Check this mod against the selected game's current data",
      }) then
    if App.validateMod then App.validateMod()
    else S.status = "Implement App.validateMod() to run modkit validate from the editor" end
  end
  if Kit.button(x + 20 * s + actionW + actionGap, row + 108 * s,
      actionW, 36 * s, "Playtest mod", {
        kind = "accent",
        tooltip = "Save and launch the bundled runtime with only this mod enabled",
      }) then
    if App.playtestMod then App.playtestMod()
    else S.status = "Implement App.playtestMod() to launch a playtest build" end
  end

  row = row + overviewH + 16 * s
  Kit.caption(x, row, "VALIDATION RESULT")
  row = row + 24 * s
  if S.validateOutput and S.validateOutput ~= "" then
    local lines = lastValidateLines(S.validateOutput, 6)
    for _, line in ipairs(lines) do
      local col = line:upper():find("ERROR", 1, true) and PAL.red
        or line:upper():find("FAIL", 1, true) and PAL.yellow
        or PAL.muted
      Kit.text("micro", Kit.ellipsize("micro", line, w), x, row, col)
      row = row + 14 * s
    end
    row = row + 4 * s
  else
    Kit.text("micro", "Not run yet. Select Validate to check this mod against the active game data.",
      x, row, PAL.faint)
    row = row + 20 * s
  end

  -- The whole Project workflow scrolls as one page. Keep this settings card
  -- at its natural height instead of squeezing it into whatever viewport
  -- space remains, which previously hid validation and made the form
  -- impossible to reach on shorter windows.
  if S._projectAdvancedFor ~= p.id then
    S._projectAdvancedFor = p.id
    S.projectAdvancedOpen = false
  end
  Kit.caption(x, row, "ADVANCED MOD OVERRIDES")
  local advancedW = 144 * s
  if Kit.button(x + w - advancedW, row - 4 * s, advancedW, 28 * s,
      S.projectAdvancedOpen and "Hide settings" or "Show settings", {
        kind = S.projectAdvancedOpen and "accent" or "ghost",
        tooltip = "Show optional new-game, limits, trade/shop, and Fly overrides",
      }) then
    S.projectAdvancedOpen = not S.projectAdvancedOpen
  end
  row = row + 24 * s
  Kit.text("micro",
    "Optional new-game, rules, capacity, trade/shop, and Fly settings. Most mods do not need these.",
    x, row, PAL.muted)
  row = row + 24 * s
  if not S.projectAdvancedOpen then
    local closedH = 62 * s
    Kit.card(x, row, w, closedH, 14 * s)
    Kit.text("small", "ROM defaults remain active", x + pad, row + 12 * s, PAL.text)
    Kit.text("micro",
      "Open only when the mod intentionally changes how a new game starts or global limits.",
      x + pad, row + 36 * s, PAL.muted)
    row = row + closedH + pad
    FormPane.finish(S, "projectPageScroll", pageTop, row, pageView)
    return
  end
  local formY = row
  local lowerH = S._projectSettingsH or (520 * s)
  Kit.card(x, formY, w, lowerH, 14 * s)
  local scrollPad = 12 * s
  local viewX = x + scrollPad
  local viewY = formY + scrollPad
  local viewW = w - 2 * scrollPad
  local fy = viewY
  local labelW = 120 * s
  local secGap = 20 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.caption(viewX, fy, "NEW-GAME START")
  fy = fy + 24 * s
  Kit.text("micro",
    "Overrides the initial map, position, names, money, and healing return point for a new game.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s

  row("Start map", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "startMap") or "")
    local v = RegList.field(App, "pr_boot_map", fx, fy_, fw, fh_, cur, "REDS_HOUSE_2F")
    if v ~= cur then setBoot(S, "startMap", v, App) end
  end)

  row("Start X", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startX") or 0
    local v = RegList.num(App, "pr_boot_x", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startX", v, App) end
  end)

  row("Start Y", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startY") or 0
    local v = RegList.num(App, "pr_boot_y", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startY", v, App) end
  end)

  row("Facing", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "startFacing") or "down")
    if Kit.button(fx, fy_, fw, fh_, Kit.ellipsize("small", cur, fw - 8 * s),
        { kind = "ghost" }) then
      setBoot(S, "startFacing", RegList.cycle(FACINGS, cur), App)
    end
  end)

  row("Player", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "playerName") or "")
    local v = RegList.field(App, "pr_boot_pname", fx, fy_, fw, fh_, cur, "RED")
    if v ~= cur then setBoot(S, "playerName", v, App) end
  end)

  row("Rival", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "rivalName") or "")
    local v = RegList.field(App, "pr_boot_rname", fx, fy_, fw, fh_, cur, "BLUE")
    if v ~= cur then setBoot(S, "rivalName", v, App) end
  end)

  row("Starting money", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startMoney") or 0
    local v = RegList.num(App, "pr_boot_money", fx, fy_, 100 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startMoney", v, App) end
  end)

  row("Last heal map", function(fx, fy_, fw, fh_)
    local cur = tostring(lastHealField(S, "map") or "")
    local v = RegList.field(App, "pr_boot_lhm", fx, fy_, fw, fh_, cur, "REDS_HOUSE_2F")
    if v ~= cur then setLastHeal(S, "map", v, App) end
  end)

  row("Last heal X", function(fx, fy_, fw, fh_)
    local cur = lastHealField(S, "x") or 0
    local v = RegList.num(App, "pr_boot_lhx", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setLastHeal(S, "x", v, App) end
  end)

  row("Last heal Y", function(fx, fy_, fw, fh_)
    local cur = lastHealField(S, "y") or 0
    local v = RegList.num(App, "pr_boot_lhy", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setLastHeal(S, "y", v, App) end
  end)

  fy = fy + secGap
  Kit.caption(viewX, fy, "CONSTANTS")
  fy = fy + 24 * s
  Kit.text("micro",
    "Optional rules and capacity limits. Unchanged fields continue using the selected ROM's defaults.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s

  if Generation.isGen2(S) then
    row("Shiny rate", function(fx, fy_, fw, fh_)
      -- Denominator: 8192 = vanilla (~1/8192). Stored on project.shinyRate
      -- (not gen2Constants name lists) and emitted as data.shinyRate.
      local cur = tonumber(S.project.shinyRate) or 8192
      local v = RegList.num(App, "pr_shiny_rate", fx, fy_, 80 * s, fh_, cur)
      v = math.max(1, math.floor(v))
      if v ~= cur then
        State.ensureProjectFields(S.project)
        S.project.shinyRate = v
        App.markDirty()
      end
    end)
    Kit.text("micro",
      "1 / N chance a wild/gift mon rolls forced shiny DVs (vanilla 8192).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
  end

  row("Level cap", function(fx, fy_, fw, fh_)
    local cur = constField(S, "levelCap") or 100
    local v = RegList.num(App, "pr_const_lvl", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "levelCap", v, App) end
  end)

  row("Dex size", function(fx, fy_, fw, fh_)
    local cur = constField(S, "dexSize") or 151
    local v = RegList.num(App, "pr_const_dex", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "dexSize", v, App) end
  end)

  row("Dex digits", function(fx, fy_, fw, fh_)
    local cur = constField(S, "dexDigits") or 3
    local v = RegList.num(App, "pr_const_ddig", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "dexDigits", v, App) end
  end)

  row("Party max", function(fx, fy_, fw, fh_)
    local cur = constField(S, "partyMax") or 6
    local v = RegList.num(App, "pr_const_party", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "partyMax", v, App) end
  end)

  row("Bag size", function(fx, fy_, fw, fh_)
    local cur = constField(S, "bagSize") or 20
    local v = RegList.num(App, "pr_const_bag", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "bagSize", v, App) end
  end)

  row("Money cap", function(fx, fy_, fw, fh_)
    local cur = constField(S, "moneyCap") or 999999
    local v = RegList.num(App, "pr_const_money", fx, fy_, 100 * s, fh_, cur)
    if v ~= cur then setConst(S, "moneyCap", v, App) end
  end)

  row("Coin cap", function(fx, fy_, fw, fh_)
    local cur = constField(S, "coinCap") or 9999
    local v = RegList.num(App, "pr_const_coin", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "coinCap", v, App) end
  end)

  row("HM moves", function(fx, fy_, fw, fh_)
    local cur = joinCsvIds(constField(S, "hmMoves"))
    local v = RegList.field(App, "pr_const_hm", fx, fy_, fw, fh_, cur, "CUT, FLY, SURF")
    if v ~= cur then setConst(S, "hmMoves", parseCsvIds(v), App) end
  end)

  Kit.text("small", "Badges", viewX, fy + 6 * s, PAL.caption)
  fy = fy + 28 * s
  local badges = badgeRows(S)
  if #badges == 0 then
    Kit.text("micro", "(no badges — add one below)", viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end
  for i = 1, math.max(#badges, 0) do
    local badge = badges[i] or { id = "", name = "" }
    local idCur = tostring(badge.id or "")
    local nameCur = tostring(badge.name or "")
    Kit.text("micro", "#" .. i, viewX, fy + 8 * s, PAL.muted)
    local idV = RegList.field(App, "pr_bdg_id_" .. i, viewX + 28 * s, fy, 140 * s, fh,
      idCur, "BOULDERBADGE")
    local nameV = RegList.field(App, "pr_bdg_nm_" .. i, viewX + 176 * s, fy,
      viewW - 176 * s - 44 * s, fh, nameCur, "Boulder")
    if idV ~= idCur or nameV ~= nameCur then
      local rows = ensureBadges(S, App)
      rows[i] = rows[i] or {}
      rows[i].id = idV
      rows[i].name = nameV
    end
    if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X", { kind = "danger" }) then
      local rows = ensureBadges(S, App)
      table.remove(rows, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(viewX, fy, 100 * s, fh, "+ Badge", { kind = "good" }) then
    local rows = ensureBadges(S, App)
    rows[#rows + 1] = { id = "NEW_BADGE", name = "Badge" }
    App.markDirty()
  end
  fy = fy + fh + secGap

  Kit.caption(viewX, fy, "TRADES / SHOPS")
  fy = fy + 24 * s
  Kit.text("micro",
    "Open the dedicated editors for in-game trades and shop inventories.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s
  Kit.text("micro",
    "Use the TRADES and SHOPS tabs to edit in-game trades and mart stock.",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  if Kit.button(viewX, fy, 100 * s, fh, "Trades", { kind = "accent" }) then
    S.tab = "trades"
  end
  if Kit.button(viewX + 110 * s, fy, 100 * s, fh, "Shops", { kind = "accent" }) then
    S.tab = "shops"
  end
  fy = fy + fh + secGap

  -- Gen1 Town Map / Fly menu (field.flyOrder / field.flyWarps). Gold fly
  -- points live in FieldMoves.FLYPOINTS + gen2Landmarks.spawns instead (below).
  if not Generation.isGen2(S) then
    Kit.caption(viewX, fy, "FLY ORDER")
    fy = fy + 24 * s
    Kit.text("micro",
      "Controls the order and availability of destinations shown by the Fly menu.",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s
    Kit.text("micro",
      "field.flyOrder (Town Map / Fly menu) and landing spots in field.flyWarps.",
      viewX, fy, PAL.muted)
    fy = fy + 20 * s

    local function ensureFlyOrder()
      if type(S.project.flyOrder) == "table" then return S.project.flyOrder end
      local base = (S.data and S.data.field and S.data.field.flyOrder) or {}
      local copy = {}
      for i, mid in ipairs(base) do copy[i] = mid end
      S.project.flyOrder = copy
      if next(S.project.flyWarps or {}) == nil then
        local fw = (S.data and S.data.field and S.data.field.flyWarps) or {}
        S.project.flyWarps = {}
        for mid, spot in pairs(fw) do
          if type(spot) == "table" then
            S.project.flyWarps[mid] = { x = spot.x or 0, y = spot.y or 0 }
          end
        end
      end
      App.markDirty()
      return copy
    end

    if type(S.project.flyOrder) ~= "table" then
      if Kit.button(viewX, fy, 160 * s, fh, "Edit fly order…", { kind = "accent" }) then
        ensureFlyOrder()
      end
      fy = fy + fh + 8 * s
    else
      local order = S.project.flyOrder
      S.project.flyWarps = S.project.flyWarps or {}
      for i, mid in ipairs(order) do
        local midV = RegList.field(App, "pr_fly_" .. i, viewX, fy,
          160 * s, fh, tostring(mid or ""), "PALLET_TOWN"):upper():gsub("%s+", "_")
        if midV ~= mid then
          order[i] = midV
          if S.project.flyWarps[mid] and not S.project.flyWarps[midV] then
            S.project.flyWarps[midV] = S.project.flyWarps[mid]
            S.project.flyWarps[mid] = nil
          end
          App.markDirty()
          mid = midV
        end
        local spot = S.project.flyWarps[mid]
        if not spot then
          local base = S.data and S.data.field and S.data.field.flyWarps
            and S.data.field.flyWarps[mid]
          spot = { x = (base and base.x) or 0, y = (base and base.y) or 0 }
          S.project.flyWarps[mid] = spot
        end
        local xV = tonumber(RegList.num(App, "pr_flyx_" .. i,
          viewX + 170 * s, fy, 50 * s, fh, tonumber(spot.x) or 0)) or 0
        local yV = tonumber(RegList.num(App, "pr_flyy_" .. i,
          viewX + 228 * s, fy, 50 * s, fh, tonumber(spot.y) or 0)) or 0
        if xV ~= (spot.x or 0) or yV ~= (spot.y or 0) then
          spot.x, spot.y = xV, yV
          App.markDirty()
        end
        Kit.text("micro", "land x,y", viewX + 286 * s, fy + 8 * s, PAL.faint)
        if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
            { kind = "danger" }) then
          S.project.flyWarps[mid] = nil
          table.remove(order, i)
          App.markDirty()
          break
        end
        fy = fy + fh + 6 * s
      end
      if Kit.button(viewX, fy, 120 * s, fh, "+ Fly spot", { kind = "good" }) then
        order[#order + 1] = "NEW_TOWN"
        S.project.flyWarps["NEW_TOWN"] = { x = 0, y = 0 }
        App.markDirty()
      end
      fy = fy + fh + 8 * s
    end
  else
    -- Gold: fly points live in FieldMoves.FLYPOINTS (landmark/spawn/flag
    -- order) plus landing spots in gen2Landmarks.spawns; no field registry.
    Kit.caption(viewX, fy, "FLY POINTS")
    fy = fy + 24 * s
    Kit.text("micro",
      "Maps each Fly landmark to the spawn and landing position used on arrival.",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s
    Kit.text("micro",
      "FieldMoves.FLYPOINTS order (landmark/spawn/flag) and landing spots"
        .. " (map/x/y) from gen2Landmarks.spawns.",
      viewX, fy, PAL.muted)
    fy = fy + 20 * s

    local function ensureFlyPoints()
      if type(S.project.flyPoints) == "table" and #S.project.flyPoints > 0 then
        return S.project.flyPoints
      end
      local ok, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
      local base = (ok and FieldMoves and FieldMoves.FLYPOINTS) or {}
      local spawns = S.data and S.data.gen2Landmarks and S.data.gen2Landmarks.spawns
      local copy = {}
      for i, row in ipairs(base) do
        local spot = spawns and spawns[row.spawn]
        copy[i] = {
          landmark = row.landmark, spawn = row.spawn, flag = row.flag,
          map = spot and spot.map, x = spot and spot.x, y = spot and spot.y,
        }
      end
      S.project.flyPoints = copy
      App.markDirty()
      return copy
    end

    if type(S.project.flyPoints) ~= "table" or #S.project.flyPoints == 0 then
      if Kit.button(viewX, fy, 160 * s, fh, "Edit fly points…", { kind = "accent" }) then
        ensureFlyPoints()
      end
      fy = fy + fh + 8 * s
    else
      local rows = S.project.flyPoints
      for i, row in ipairs(rows) do
        local landmarkV = RegList.field(App, "pr_flylm_" .. i, viewX, fy,
          150 * s, fh, tostring(row.landmark or ""), "LANDMARK_...")
          :upper():gsub("%s+", "_")
        if landmarkV ~= row.landmark then row.landmark = landmarkV end
        local spawnV = RegList.field(App, "pr_flysp_" .. i, viewX + 158 * s, fy,
          130 * s, fh, tostring(row.spawn or ""), "SPAWN_...")
          :upper():gsub("%s+", "_")
        if spawnV ~= row.spawn then row.spawn = spawnV end
        local flagV = tonumber(RegList.num(App, "pr_flyfl_" .. i,
          viewX + 294 * s, fy, 44 * s, fh, tonumber(row.flag) or 0)) or 0
        if flagV ~= (row.flag or 0) then row.flag = flagV end
        local mapV = RegList.field(App, "pr_flymap_" .. i, viewX + 344 * s, fy,
          130 * s, fh, tostring(row.map or ""), "map")
          :upper():gsub("%s+", "_")
        if mapV ~= (row.map or "") then row.map = (mapV ~= "" and mapV) or nil end
        local xV = tonumber(RegList.num(App, "pr_flyx_" .. i,
          viewX + 480 * s, fy, 44 * s, fh, tonumber(row.x) or 0)) or 0
        local yV = tonumber(RegList.num(App, "pr_flyy_" .. i,
          viewX + 528 * s, fy, 44 * s, fh, tonumber(row.y) or 0)) or 0
        if xV ~= (row.x or 0) then row.x = xV end
        if yV ~= (row.y or 0) then row.y = yV end
        Kit.text("micro", "land map/x,y", viewX + 576 * s, fy + 8 * s, PAL.faint)
        if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
            { kind = "danger" }) then
          table.remove(rows, i)
          App.markDirty()
          break
        end
        fy = fy + fh + 6 * s
      end
      if Kit.button(viewX, fy, 120 * s, fh, "+ Fly point", { kind = "good" }) then
        rows[#rows + 1] = { landmark = "LANDMARK_NEW", spawn = "SPAWN_NEW", flag = 0 }
        App.markDirty()
      end
      fy = fy + fh + 8 * s
    end
  end

  lowerH = math.max(120 * s, fy - formY + scrollPad)
  S._projectSettingsH = lowerH
  row = formY + lowerH + pad
  FormPane.finish(S, "projectPageScroll", pageTop, row, pageView)
end

return Project
