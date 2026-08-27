-- Project tab: create / open mod, target game, data source, validate.

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
  local gen = Generation.num(S)
  local rawOrder = GameVersion.ORDER or { "red", "blue", "yellow", "gold", "silver", "crystal" }
  local order = {}
  for _, vid in ipairs(rawOrder) do
    if (GameVersion.VERSIONS and GameVersion.VERSIONS[vid]) or vid == curVer then
      order[#order + 1] = vid
    end
  end
  if #order == 0 then order = { curVer } end
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
          .. " — Gen " .. tostring(Generation.num({ version = vid }))
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
  local dataCardH = 196 * s
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
      tooltip = "Use data/generated (or red|blue|yellow|gold|silver|crystal/) from a Gen1Recomp install",
    }) then
    App.pickFolder("Choose Gen1Recomp folder", function(path)
      App.linkRecompFolder(path)
    end, recompRoot)
  end
  if Kit.button(dataX + dsW + dsGap, row, dsW, btnH, "Import ROM", {
      kind = "accent",
      tooltip = "Import US Red/Blue/Yellow (.gb, 1 MiB) or Gold/Silver/Crystal (.gbc, 2 MiB)\n"
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
      tooltip = "Delete save-directory ROM caches (red|blue|yellow|gold|silver|crystal/…)\n"
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
  row = row + btnH + 8 * s
  local cacheFolder = DataSource.importedCacheFolder(curVer)
  if Kit.button(dataX, row, dsW, btnH, "Open cache", {
      kind = "ghost",
      tooltip = (cacheFolder and ("Open:\n" .. cacheFolder) or "Open the save-directory ROM cache")
        .. "\nImported data lives here (red|blue|yellow|gold|silver|crystal/)",
    }) then
    if App.openCacheFolder then App.openCacheFolder() end
  end
  row = dataCardY + dataCardH + 18 * s

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

  FormPane.finish(S, "projectPageScroll", pageTop, row, pageView)
end

return Project
