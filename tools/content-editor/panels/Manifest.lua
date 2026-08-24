-- Manifest tab: browse mods/ and edit manifest.json fields.

local Kit = require("Kit")
local Theme = require("Theme")
local ModIO = require("ModIO")
local FormPane = require("FormPane")
local RegList = require("RegList")
local ManifestSchema = require("src.mods.Manifest")
local PAL = Theme.PAL

local Manifest = {}

local PROFILES = { "content", "overhaul", "total_conversion" }
local CATEGORIES = {
  "GAMEPLAY", "QUEST", "COSMETIC", "AUDIO", "UI", "FIX", "OTHER",
}
local PERMISSIONS = { "engine_internals", "filesystem", "network" }

local function cycle(list, cur)
  local idx = 1
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

local function csv(list)
  if type(list) ~= "table" then return "" end
  return table.concat(list, ", ")
end

local function splitCsv(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part and part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function defaultDraft(id)
  local engine = ModIO.engineVersion()
  local major = tonumber(engine:match("^(%d+)")) or 0
  local Generation = require("Generation")
  local games = Generation.manifestGames(nil)
  return {
    id = id or "mod",
    name = id or "mod",
    version = "0.1.0",
    api = 2,
    entry = "main.lua",
    profile = "content",
    game_version = string.format(">=%s <%d.0.0", engine, major + 1),
    games = games,
    gen2compat = Generation.coversGen2(games) or Generation.isGen2(nil) or false,
    category = "GAMEPLAY",
    priority = 100,
    permissions = {},
    dependencies = {},
    optional_dependencies = {},
    conflicts = {},
    incompatible = {},
    experimental = false,
    language = false,
    description = "",
    github = "",
  }
end

local function loadDraft(S, modId)
  local data, err = ModIO.readManifest(modId)
  if not data then
    S.manifestDraft = defaultDraft(modId)
    S.manifestLoadError = tostring(err)
    S.manifestDirty = false
    return
  end
  local Generation = require("Generation")
  local d = defaultDraft(modId)
  for k, v in pairs(data) do d[k] = v end
  d.permissions = type(d.permissions) == "table" and d.permissions or {}
  d.dependencies = type(d.dependencies) == "table" and d.dependencies or {}
  d.optional_dependencies = type(d.optional_dependencies) == "table"
    and d.optional_dependencies or {}
  d.conflicts = type(d.conflicts) == "table" and d.conflicts or {}
  d.incompatible = type(d.incompatible) == "table" and d.incompatible or {}
  d.experimental = d.experimental == true
  d.language = d.language == true
  d.github = d.github or ""
  d.description = d.description or ""
  -- New-mod defaults are `games: ["all"]` + gen2compat. An existing file that
  -- omitted both is Gen 1 only in the loader. Do not keep those defaults, or
  -- the Manifest tab shows YES while Gold skips with "not marked gen2compat".
  if type(data.games) == "table" then
    d.games = data.games
  else
    d.games = {}
  end
  d.gen2compat = data.gen2compat == true or Generation.coversGen2(d.games)
  S.manifestDraft = d
  S.manifestLoadError = nil
  S.manifestDirty = false
  S.manifestValidateMsg = nil
end

local function ensureBrowseMod(S)
  local mods = ModIO.listMods()
  if not S.browseModId or S.browseModId == "" then
    if S.path then
      S.browseModId = S.path:match("[/\\]([^/\\]+)$")
    end
    if not S.browseModId and mods[1] then S.browseModId = mods[1] end
  end
  if S.browseModId and S._manifestFor ~= S.browseModId then
    loadDraft(S, S.browseModId)
    S._manifestFor = S.browseModId
    S.manifestScroll = 0
  end
  return mods
end

local function markManifestDirty(S)
  S.manifestDirty = true
  S._quitArmed = nil
  S.manifestValidateMsg = nil
end

local function field(S, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then markManifestDirty(S) end
  return v
end

function Manifest.save(S, App)
  local d = S.manifestDraft
  if not (d and S.browseModId) then
    S.status = "No mod selected"
    return false
  end
  local payload = {
    id = tostring(d.id or S.browseModId),
    name = tostring(d.name or ""),
    version = tostring(d.version or ""),
    api = tonumber(d.api) or 2,
    entry = tostring(d.entry or "main.lua"),
    profile = tostring(d.profile or "content"),
    game_version = tostring(d.game_version or ""),
    games = type(d.games) == "table" and d.games or {},
    gen2compat = d.gen2compat == true,
    category = tostring(d.category or "OTHER"),
    priority = tonumber(d.priority) or 0,
    permissions = d.permissions or {},
    dependencies = d.dependencies or {},
    optional_dependencies = d.optional_dependencies or {},
    conflicts = d.conflicts or {},
    incompatible = d.incompatible or {},
    experimental = d.experimental == true,
    description = tostring(d.description or ""),
  }
  if d.language == true then payload.language = true end
  if type(d.affects_link) == "boolean" then payload.affects_link = d.affects_link end
  if d.github and d.github ~= "" then payload.github = d.github end
  if d.options_schema and d.options_schema ~= "" then
    payload.options_schema = d.options_schema
  end
  if d.assets_transforms and d.assets_transforms ~= "" then
    payload.assets_transforms = d.assets_transforms
  end

  local ok, err = pcall(ManifestSchema.validate, payload)
  if not ok then
    S.manifestValidateMsg = tostring(err)
    S.status = "Manifest invalid: " .. tostring(err)
    return false
  end

  local wok, werr = ModIO.writeManifest(S.browseModId, payload)
  if not wok then
    S.status = "Write failed: " .. tostring(werr)
    return false
  end
  S.manifestDirty = false
  S.manifestValidateMsg = "OK"
  S.status = "Wrote mods/" .. S.browseModId .. "/manifest.json"
  -- keep open content-editor project name in sync when editing that mod
  if S.project and S.path then
    local openId = S.path:match("[/\\]([^/\\]+)$")
    if openId == S.browseModId and S.project.name ~= payload.name then
      S.project.name = payload.name
      if App and App.markDirty then App.markDirty() end
    end
  end
  return true
end

function Manifest.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local mods = ensureBrowseMod(S)
  local listW = math.min(220 * s, w * 0.28)
  local gap = 12 * s
  local mainX = x + listW + gap
  local mainW = w - listW - gap

  Kit.caption(x, y, "MODS/")
  local listY = y + 22 * s
  local listH = h - 22 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local rowH = 30 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / rowH))
  local scrollX, scrollY = x + 4 * s, listY + 8 * s
  local scrollW, scrollH = listW - 8 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.manifestListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.manifestListOffset or 0, #mods, perPage)
  local dirtyGuard = (S.manifestDirty and S._manifestFor) or nil
  local manNav = RegList.bindNav(S, mods, {
    selKey = "browseModId", offsetKey = "manifestListOffset", perPage = perPage,
    onSelect = function(id)
      if dirtyGuard and id ~= dirtyGuard then
        S.browseModId = dirtyGuard
        S.status = "Unsaved manifest — Write or Reload before switching"
        return
      end
      S._manifestFor = nil
    end,
  })
  for i = 1, perPage do
    local idx = (S.manifestListOffset or 0) + i
    local mid = mods[idx]
    if not mid then break end
    local ry = scrollY + (i - 1) * rowH
    local on = S.browseModId == mid
    if Kit.row(x + 6 * s, ry, rowW - 2 * s, rowH - 4 * s, on, PAL.blue) then
      manNav.activate()
      if dirtyGuard and mid ~= dirtyGuard then
        S.status = "Unsaved manifest — Write or Reload before switching"
      else
        S.browseModId = mid
        S._manifestFor = nil
      end
    end
    Kit.text("small", Kit.ellipsize("small", mid, math.max(8, rowW - 20 * s)),
      x + 14 * s, ry + 6 * s, on and PAL.heading or PAL.text)
  end
  S.manifestListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.manifestListOffset or 0, #mods, perPage)

  if not S.browseModId or not S.manifestDraft then
    Kit.emptyBox(mainX, listY, mainW, listH, "Select a mod under mods/")
    return
  end

  local d = S.manifestDraft
  local title = (S.manifestDirty and "* " or "") .. S.browseModId .. " / manifest.json"
  Kit.caption(mainX, y, Kit.ellipsize("caption", title, mainW))

  local barY = listY
  local btnH = 30 * s
  local bw = 88 * s
  if Kit.button(mainX, barY, bw, btnH, "Write", { kind = "primary" }) then
    Manifest.save(S, App)
  end
  if Kit.button(mainX + bw + 8 * s, barY, bw, btnH, "Reload", { kind = "ghost" }) then
    loadDraft(S, S.browseModId)
    S._manifestFor = S.browseModId
    S.status = "Reloaded manifest"
  end
  if Kit.button(mainX + 2 * (bw + 8 * s), barY, 110 * s, btnH,
      "Open mod", { kind = "accent" }) then
    local want = ModIO.modDir(S.browseModId)
    local openId = S.path and S.path:match("[/\\]([^/\\]+)$")
    if want and openId ~= S.browseModId then
      App.openMod(want)
    else
      S.status = "Already open as content project"
    end
  end

  local formY = barY + btnH + 10 * s
  local formH = listY + listH - formY
  Kit.card(mainX, formY, mainW, formH, 12 * s)

  FormPane.track(S, "manifestScroll", S.browseModId)
  local py, view = FormPane.begin(S, "manifestScroll",
    mainX + 10 * s, formY + 10 * s, mainW - 20 * s, formH - 20 * s)
  local px = mainX + 10 * s
  local propW = view.contentW or (mainW - 20 * s)
  local fh = 28 * s
  local labelW = 120 * s

  local function row(label, body)
    Kit.text("micro", label, px, py + 6 * s, PAL.caption)
    body(px + labelW, py, propW - labelW, fh)
    py = py + fh + 8 * s
  end

  if S.manifestLoadError then
    Kit.text("micro", "Load note: " .. S.manifestLoadError, px, py, PAL.yellow)
    py = py + 18 * s
  end
  if S.manifestValidateMsg and S.manifestValidateMsg ~= "OK" then
    Kit.text("micro", Kit.ellipsize("micro", S.manifestValidateMsg, propW),
      px, py, PAL.red)
    py = py + 18 * s
  elseif S.manifestValidateMsg == "OK" then
    Kit.text("micro", "Validated OK", px, py, PAL.green)
    py = py + 18 * s
  end

  row("id", function(fx, fy, fw, fh_)
    d.id = field(S, "mf_id", fx, fy, fw, fh_, d.id, "mod_id")
  end)
  row("name", function(fx, fy, fw, fh_)
    d.name = field(S, "mf_name", fx, fy, fw, fh_, d.name, "Display name")
  end)
  row("version", function(fx, fy, fw, fh_)
    d.version = field(S, "mf_ver", fx, fy, fw, fh_, d.version, "1.0.0")
  end)
  row("api", function(fx, fy, fw, fh_)
    local v = field(S, "mf_api", fx, fy, 70 * s, fh_, tostring(d.api or 2), "2")
    d.api = tonumber(v) or d.api
  end)
  row("entry", function(fx, fy, fw, fh_)
    d.entry = field(S, "mf_entry", fx, fy, fw, fh_, d.entry, "main.lua")
  end)
  row("profile", function(fx, fy, fw, fh_)
    if Kit.button(fx, fy, fw, fh_, tostring(d.profile or "content"), { kind = "ghost" }) then
      d.profile = cycle(PROFILES, d.profile or "content")
      markManifestDirty(S)
    end
  end)
  row("category", function(fx, fy, fw, fh_)
    if Kit.button(fx, fy, fw, fh_, tostring(d.category or "OTHER"), { kind = "ghost" }) then
      d.category = cycle(CATEGORIES, d.category or "OTHER")
      markManifestDirty(S)
    end
  end)
  row("priority", function(fx, fy, fw, fh_)
    local v = field(S, "mf_pri", fx, fy, 80 * s, fh_, tostring(d.priority or 100), "100")
    d.priority = tonumber(v) or d.priority
  end)
  row("game_version", function(fx, fy, fw, fh_)
    d.game_version = field(S, "mf_gv", fx, fy, fw, fh_, d.game_version, ">=0.0.0-dev <1.0.0")
  end)
  row("games", function(fx, fy, fw, fh_)
    local cur = csv(d.games)
    local v = field(S, "mf_games", fx, fy, fw, fh_, cur, "all")
    if v ~= cur then
      local Generation = require("Generation")
      d.games = splitCsv(v)
      d.gen2compat = Generation.coversGen2(d.games)
      markManifestDirty(S)
    end
  end)
  row("gen2compat", function(fx, fy, fw, fh_)
    local on = d.gen2compat == true
    if Kit.chip(fx, fy, 80 * s, fh_, on and "YES" or "NO", on, PAL.green) then
      local Generation = require("Generation")
      d.gen2compat = not on
      d.games = type(d.games) == "table" and d.games or {}
      local hasGen2 = Generation.coversGen2(d.games)
      if d.gen2compat and not hasGen2 then
        if #d.games == 0 then
          d.games = { "all" }
        else
          d.games[#d.games + 1] = "gen2"
        end
      elseif not d.gen2compat and hasGen2 then
        local nextGames = {}
        for _, g in ipairs(d.games) do
          if not Generation.isExclusiveGen2Token(g)
              and tostring(g):lower() ~= "all" then
            nextGames[#nextGames + 1] = g
          end
        end
        if #nextGames == 0 then nextGames = { "gen1" } end
        d.games = nextGames
      end
      markManifestDirty(S)
    end
  end)
  row("github", function(fx, fy, fw, fh_)
    d.github = field(S, "mf_gh", fx, fy, fw, fh_, d.github or "", "owner/repo")
  end)
  row("description", function(fx, fy, fw, fh_)
    d.description = field(S, "mf_desc", fx, fy, fw, fh_, d.description or "", "Short summary")
  end)

  Kit.text("micro", "permissions", px, py + 6 * s, PAL.caption)
  py = py + 20 * s
  local chipX = px
  for _, perm in ipairs(PERMISSIONS) do
    local on = false
    for _, p in ipairs(d.permissions or {}) do if p == perm then on = true; break end end
    local cw = Kit.textWidth("micro", perm) + 18 * s
    if chipX + cw > px + propW then
      chipX = px
      py = py + 30 * s
    end
    if Kit.chip(chipX, py, cw, 26 * s, perm, on, PAL.yellow) then
      local nextPerms = {}
      if on then
        for _, p in ipairs(d.permissions or {}) do
          if p ~= perm then nextPerms[#nextPerms + 1] = p end
        end
      else
        for _, p in ipairs(d.permissions or {}) do nextPerms[#nextPerms + 1] = p end
        nextPerms[#nextPerms + 1] = perm
      end
      d.permissions = nextPerms
      markManifestDirty(S)
    end
    chipX = chipX + cw + 6 * s
  end
  py = py + 34 * s

  local function flagRow(label, key)
    Kit.text("micro", label, px, py + 6 * s, PAL.caption)
    local on = d[key] == true
    if Kit.chip(px + labelW, py, 70 * s, fh, on and "YES" or "NO", on, PAL.green) then
      d[key] = not on
      markManifestDirty(S)
    end
    py = py + fh + 8 * s
  end
  flagRow("experimental", "experimental")
  flagRow("language", "language")

  row("dependencies", function(fx, fy, fw, fh_)
    local v = field(S, "mf_deps", fx, fy, fw, fh_, csv(d.dependencies), "mod_a, mod_b@^1")
    d.dependencies = splitCsv(v)
  end)
  row("optional_deps", function(fx, fy, fw, fh_)
    local v = field(S, "mf_odeps", fx, fy, fw, fh_, csv(d.optional_dependencies), "")
    d.optional_dependencies = splitCsv(v)
  end)
  row("conflicts", function(fx, fy, fw, fh_)
    local v = field(S, "mf_conf", fx, fy, fw, fh_, csv(d.conflicts), "")
    d.conflicts = splitCsv(v)
  end)
  row("incompatible", function(fx, fy, fw, fh_)
    local v = field(S, "mf_inc", fx, fy, fw, fh_, csv(d.incompatible), "")
    d.incompatible = splitCsv(v)
  end)

  Kit.text("micro",
    "Write validates against the engine manifest schema, then saves mods/<id>/manifest.json.",
    px, py, PAL.faint)
  py = py + 20 * s

  FormPane.finish(S, "manifestScroll", view.y, py, view)
end

return Manifest
