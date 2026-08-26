-- RULES tab: data registries from the wiki that had no GUI yet.
-- Function APIs (hooks, events, commands, screens) stay on the CODE tab.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Generation = require("Generation")
local PAL = Theme.PAL

local Rules = {}

local ALL_MODES = {
  { id = "statuses", label = "STATUSES",
    tip = "Status labels, catch/wobble bonuses, stat cuts (R29)" },
  { id = "rulesets", label = "RULESETS", gen1 = true,
    tip = "Battle quirk toggles (R38). Gold has no ruleset dispatch." },
  { id = "transitions", label = "FADES", gen1 = true,
    tip = "Warp / battle wipe frames and flash (R42). Gold uses cart wipes." },
  { id = "scales", label = "SCALES",
    tip = "Per-image battle sprite scale (R36)" },
  { id = "apricorns", label = "APRICORNS", gen2 = true,
    tip = "Kurt apricorn → ball rows" },
  { id = "radio", label = "RADIO", gen2 = true,
    tip = "Pokegear / wall-radio stations" },
  { id = "lua", label = "LUA",
    tip = "Wiki recipes that are functions — author them on CODE" },
}

local RULESET_FLAGS = {
  { key = "oneIn256Miss", label = "1/256 miss" },
  { key = "critUsesBaseSpeed", label = "Crit base SPD" },
  { key = "critIgnoresStages", label = "Crit ignore stages" },
  { key = "focusEnergyBug", label = "Focus Energy bug" },
  { key = "enemyUnlimitedPP", label = "Enemy free PP" },
  { key = "hyperBeamSkipRechargeOnKO", label = "Hyper Beam KO skip" },
  { key = "residualAfterMove", label = "Residual after move" },
}

local LUA_RECIPES = {
  { id = "R16", api = "growth_rates:register", note = "expForLevel(level) function" },
  { id = "R17", api = "evolution_methods:register", note = "check / describe functions" },
  { id = "R19", api = "trainers:patch(brain)", note = "custom AI chooser function" },
  { id = "R20", api = "mod.commands:register", note = "script command handler" },
  { id = "R21", api = "tokens:register", note = "text token expander" },
  { id = "R23", api = "mod.world:spawnNpc", note = "runtime NPC spawn" },
  { id = "R27", api = "events:on", note = "battle / world event listener" },
  { id = "R28", api = "hooks:wrap", note = "wrap battle.damage and other hooks" },
  { id = "R31", api = "hooks:wrap(ui.start_menu.items)", note = "Start-menu entries" },
  { id = "R32", api = "screens:register", note = "custom screen { new = fn }" },
  { id = "R33", api = "mod.save:get/set", note = "persist mod state" },
  { id = "R34", api = "mod.options:define", note = "mod options row" },
  { id = "R35", api = "mod.exports / mod.find", note = "inter-mod API" },
  { id = "R37", api = "hooks:wrap(intro.oak_speech.build)", note = "reshape Oak speech" },
  { id = "R39", api = "battle.overlay", note = "shiny / HUD overlay draw" },
  { id = "R40", api = "hooks:wrap(movement.speed)", note = "running shoes" },
  { id = "R41", api = "world.tod + map.palette", note = "day / night palettes" },
  { id = "R44", api = "hooks:wrap(music.volume)", note = "distance / indoor volume" },
  { id = "R45", api = "hooks:wrap(ui.list_menu)", note = "bag wrap / hold-scroll" },
  { id = "R46", api = "hooks:wrap(ui.naming.grid)", note = "naming-screen digits" },
  { id = "R47", api = "hooks:wrap(zoom.range)", note = "survey zoom range" },
  { id = "R48", api = "hooks:wrap(render.letterbox)", note = "SGB border" },
  { id = "R49", api = "hooks:wrap(pokemon.sprite)", note = "pick sprites at draw time" },
  { id = "R52", api = "mod.world:availableFieldActions", note = "one-button field actions" },
  { id = "R53", api = "battle.caught_marker_visible", note = "Gen2 battle QoL toggles" },
  { id = "R54", api = "mod.steps", note = "real-world step events" },
}

local RADIO_FALLBACK = {
  OAKS_POKEMON_TALK = { channel = 1, name = "OAK's POKéMON Talk" },
  POKEDEX_SHOW = { channel = 2, name = "POKéDEX Show" },
  POKEMON_MUSIC = { channel = 3, name = "POKéMON Music" },
  LUCKY_CHANNEL = { channel = 4, name = "Lucky Channel" },
  UNOWN_RADIO = { channel = 5, name = "Unown Radio" },
  PLACES_AND_PEOPLE = { channel = 6, name = "Places & People" },
  LETS_ALL_SING = { channel = 7, name = "Let's All Sing" },
  ROCKET_RADIO = { channel = 8, name = "Rocket Radio" },
}

local function modesFor(S)
  local gen2 = Generation.isGen2(S)
  local out = {}
  for _, m in ipairs(ALL_MODES) do
    if m.gen1 and gen2 then
      -- skip
    elseif m.gen2 and not gen2 then
      -- skip
    else
      out[#out + 1] = m
    end
  end
  return out
end

local function cloneData(rec, extra)
  local copy = {}
  if type(rec) == "table" then
    for k, v in pairs(rec) do
      if type(k) == "string" and k:sub(1, 1) ~= "_" and type(v) ~= "function" then
        if type(v) == "table" then
          copy[k] = cloneData(v)
        else
          copy[k] = v
        end
      end
    end
  end
  if extra then
    for k, v in pairs(extra) do copy[k] = v end
  end
  return copy
end

local function allocId(proj, data, prefix)
  local nid = prefix
  local n = 1
  while proj[nid] or (data and data[nid]) do
    n = n + 1
    nid = prefix .. "_" .. n
  end
  return nid
end

local function statusData(S)
  if Generation.isGen2(S) then
    local t = S.data and (S.data.gen2Statuses or S.data.statuses)
    if type(t) == "table" and next(t) then return t end
    local ok, Battle = pcall(require, "src.battle.gen2.Battle")
    if ok and Battle and type(Battle.STATUSES) == "table" then
      return Battle.STATUSES
    end
    return {}
  end
  local t = S.data and S.data.statuses
  if type(t) == "table" and next(t) then return t end
  local ok, Status = pcall(require, "src.battle.Status")
  if ok and Status and type(Status.RECORDS) == "table" then
    return Status.RECORDS
  end
  return {}
end

local function rulesetData(S)
  local t = S.data and S.data.rulesets
  if type(t) == "table" and next(t) then return t end
  local out = {}
  local ok1, a = pcall(require, "src.battle.rulesets.gen1_faithful")
  if ok1 and type(a) == "table" and a.name then out[a.name] = a end
  local ok2, b = pcall(require, "src.battle.rulesets.modern_clean")
  if ok2 and type(b) == "table" and b.name then out[b.name] = b end
  return out
end

local function transitionData(S)
  local t = S.data and S.data.transitions
  if type(t) == "table" and next(t) then return t end
  local out = {}
  local okB, BT = pcall(require, "src.render.BattleTransition")
  if okB and BT and type(BT.STYLES) == "table" then
    for id, rec in pairs(BT.STYLES) do out[id] = rec end
  end
  local okT, Tr = pcall(require, "src.render.Transition")
  if okT and Tr and type(Tr.STYLES) == "table" then
    for id, rec in pairs(Tr.STYLES) do out[id] = rec end
  end
  return out
end

local function scaleData(S)
  return (S.data and S.data.battle_sprite_scales) or {}
end

local function apricornData(S)
  local t = S.data and (S.data.gen2Apricorns or S.data.apricorns)
  if type(t) == "table" and next(t) then return t end
  local ok, Apr = pcall(require, "src.core.gen2.Apricorns")
  if ok and Apr and type(Apr.BALLS) == "table" then
    local out = {}
    for i, row in ipairs(Apr.BALLS) do
      if type(row) == "table" and type(row.apricorn) == "string" then
        out[row.apricorn] = {
          apricorn = row.apricorn,
          ball = row.ball,
          event = row.event,
          index = i,
        }
      end
    end
    return out
  end
  return {}
end

local function radioData(S)
  local t = S.data and (S.data.gen2RadioChannels or S.data.radio_channels)
  if type(t) == "table" and next(t) then return t end
  return RADIO_FALLBACK
end

local SPECS = {
  statuses = {
    projectKey = "statuses",
    caption = "STATUSES",
    newId = "MOD_STATUS",
    data = statusData,
    newRec = function()
      return {
        label = "NEW", hudLabel = "NEW",
        catchBonus = 0, shakeBonus = 0,
        cureOnSwitch = false,
        _isNew = true,
      }
    end,
    summarize = function(rec)
      if type(rec) ~= "table" then return "" end
      local bits = { rec.label or rec.id or "?" }
      if rec.catchBonus then bits[#bits + 1] = "catch=" .. tostring(rec.catchBonus) end
      if rec.statPenalty and rec.statPenalty.stat then
        bits[#bits + 1] = rec.statPenalty.stat .. "/ " .. tostring(rec.statPenalty.div or 1)
      end
      return table.concat(bits, "  ·  ")
    end,
  },
  rulesets = {
    projectKey = "rulesets",
    caption = "RULESETS",
    newId = "custom_rules",
    data = rulesetData,
    newRec = function()
      return { name = "custom", _isNew = true }
    end,
    summarize = function(rec)
      if type(rec) ~= "table" then return "" end
      return rec.name or "?"
    end,
  },
  transitions = {
    projectKey = "transitions",
    caption = "FADES",
    newId = "custom_fade",
    data = transitionData,
    newRec = function()
      return { frames = 30, flash = false, _isNew = true }
    end,
    summarize = function(rec)
      if type(rec) ~= "table" then return "" end
      local bits = { tostring(rec.frames or "?") .. "f" }
      if rec.flash then bits[#bits + 1] = "flash" end
      if rec.sound and rec.sound ~= "" then bits[#bits + 1] = rec.sound end
      return table.concat(bits, "  ·  ")
    end,
  },
  scales = {
    projectKey = "battle_sprite_scales",
    caption = "SPRITE SCALES",
    newId = "custom_scale",
    data = scaleData,
    newRec = function()
      return { path = "", scale = 1, _isNew = true }
    end,
    summarize = function(rec)
      if type(rec) ~= "table" then return "" end
      return string.format("%s  ×%s", rec.path or "?", tostring(rec.scale or 1))
    end,
  },
  apricorns = {
    projectKey = "apricorns",
    caption = "APRICORNS",
    newId = "MOD_APRICORN",
    data = apricornData,
    newRec = function()
      return { apricorn = "MOD_APRICORN", ball = "POKE_BALL", event = 0, index = 8, _isNew = true }
    end,
    summarize = function(rec)
      if type(rec) ~= "table" then return "" end
      return string.format("%s → %s", rec.apricorn or "?", rec.ball or "?")
    end,
  },
  radio = {
    projectKey = "radio_channels",
    caption = "RADIO",
    newId = "MOD_RADIO",
    data = radioData,
    newRec = function()
      return { channel = 9, name = "NEW STATION", _isNew = true }
    end,
    summarize = function(rec)
      if type(rec) ~= "table" then return "" end
      return string.format("ch %s  %s", tostring(rec.channel or "?"), rec.name or "")
    end,
  },
}

local function projectBag(S, spec)
  State.ensureProjectFields(S.project)
  return S.project[spec.projectKey]
end

local function resolve(S, spec, id)
  local proj = projectBag(S, spec)
  if proj[id] ~= nil then return proj[id], true end
  local data = spec.data(S)
  if data[id] ~= nil then return data[id], false end
  return nil, false
end

local function drawLua(S, x, y, w, h)
  local s = Kit.scale
  Kit.caption(x, y, "LUA APIS  (CODE TAB)")
  local fy, view = FormPane.begin(S, "rulesLuaScroll", x, y + 22 * s, w, h - 22 * s)
  local top = fy
  Kit.text("micro",
    "These wiki recipes are Lua functions. Author them as files on the CODE tab. Data registries are the other RULES modes plus Pokémon, Items, Maps, UI, Audio, Events.",
    x, fy, PAL.muted)
  fy = fy + 36 * s
  local rowH = 36 * s
  for _, row in ipairs(LUA_RECIPES) do
    Kit.card(x, fy, w, rowH, 8 * s)
    Kit.text("small", row.id .. "  " .. row.api, x + 10 * s, fy + 4 * s, PAL.text)
    Kit.text("micro", row.note, x + 10 * s, fy + 20 * s, PAL.faint)
    fy = fy + rowH + 6 * s
  end
  FormPane.finish(S, "rulesLuaScroll", top, fy, view)
end

local function drawStatuses(S, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  local gen2 = Generation.isGen2(S)
  local r = type(rec) == "table" and rec or {}
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end
  row("Label", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().label) or r.label or "")
    local v = RegList.field(App, "ru_st_lab", fx, fy_, fw, fh_, cur, "PSN")
    if v ~= cur then ensure().label = v end
  end)
  row("HUD label", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().hudLabel) or r.hudLabel or "")
    local v = RegList.field(App, "ru_st_hud", fx, fy_, fw, fh_, cur, "PSN")
    if v ~= cur then ensure().hudLabel = v ~= "" and v or nil end
  end)
  row("Catch bonus", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().catchBonus) or r.catchBonus or 0
    local v = RegList.num(App, "ru_st_catch", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().catchBonus = v end
  end)
  row("Shake bonus", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().shakeBonus) or r.shakeBonus or 0
    local v = RegList.num(App, "ru_st_shake", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().shakeBonus = v end
  end)
  row("Cure on switch", function(fx, fy_, fw, fh_)
    local cur = not not ((owned and ensure().cureOnSwitch) or r.cureOnSwitch)
    if Kit.chip(fx, fy_, 80 * s, fh_, cur and "YES" or "NO", cur, PAL.yellow) then
      ensure().cureOnSwitch = not cur
    end
  end)
  row("Move priority", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().beforeMovePriority) or r.beforeMovePriority or 0
    local v = RegList.num(App, "ru_st_pri", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().beforeMovePriority = v end
  end)
  local pen = (owned and ensure().statPenalty) or r.statPenalty or {}
  row("Stat penalty", function(fx, fy_, fw, fh_)
    local stat = tostring(pen.stat or "")
    local v = RegList.field(App, "ru_st_pstat", fx, fy_, math.max(80 * s, fw - 90 * s),
      fh_, stat, "attack")
    if v ~= stat then
      local e = ensure()
      e.statPenalty = e.statPenalty or {}
      e.statPenalty.stat = v ~= "" and v or nil
      if not e.statPenalty.stat then e.statPenalty = nil end
    end
    local div = tonumber(pen.div) or 1
    local dv = RegList.num(App, "ru_st_pdiv", fx + fw - 80 * s, fy_, 80 * s, fh_, div)
    if dv ~= div then
      local e = ensure()
      if type(e.statPenalty) ~= "table" or not e.statPenalty.stat then
        e.statPenalty = { stat = "attack", div = dv }
      else
        e.statPenalty.div = dv
      end
    end
  end)
  if gen2 then
    row("Heal class", function(fx, fy_, fw, fh_)
      local cur = tostring((owned and ensure().healClass) or r.healClass or "")
      local v = RegList.field(App, "ru_st_heal", fx, fy_, fw, fh_, cur, "psn")
      if v ~= cur then ensure().healClass = v ~= "" and v or nil end
    end)
    row("Inflict text", function(fx, fy_, fw, fh_)
      local cur = tostring((owned and ensure().inflictText) or r.inflictText or "")
      local v = RegList.field(App, "ru_st_inf", fx, fy_, fw, fh_, cur, " was poisoned!")
      if v ~= cur then ensure().inflictText = v ~= "" and v or nil end
    end)
  end
  Kit.text("micro",
    "canInflict / onInflict / beforeMove / residual are functions — author those on CODE.",
    viewX, fy, PAL.faint)
  fy = fy + 28 * s
  return fy
end

local function drawRulesets(_, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  local r = type(rec) == "table" and rec or {}
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end
  row("Name", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().name) or r.name or "")
    local v = RegList.field(App, "ru_rs_name", fx, fy_, fw, fh_, cur, "custom")
    if v ~= cur then ensure().name = v end
  end)
  row("Crit rate", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().critRate) or r.critRate
    local shown = cur == nil and "" or tostring(cur)
    local v = RegList.field(App, "ru_rs_crit", fx, fy_, 80 * s, fh_, shown, "0")
    if v ~= shown then
      local n = tonumber(v)
      ensure().critRate = n
    end
  end)
  row("Rand min", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().randMin) or r.randMin or 217
    local v = RegList.num(App, "ru_rs_rmin", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().randMin = v end
  end)
  row("Rand max", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().randMax) or r.randMax or 255
    local v = RegList.num(App, "ru_rs_rmax", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().randMax = v end
  end)
  for _, flag in ipairs(RULESET_FLAGS) do
    row(flag.label, function(fx, fy_, fw, fh_)
      local cur = not not ((owned and ensure()[flag.key]) or r[flag.key])
      if Kit.chip(fx, fy_, 80 * s, fh_, cur and "YES" or "NO", cur, PAL.yellow) then
        ensure()[flag.key] = not cur
      end
    end)
  end
  return fy
end

local function drawTransitions(_, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  local r = type(rec) == "table" and rec or {}
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end
  row("Frames", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().frames) or r.frames or 30
    local v = math.max(1, RegList.num(App, "ru_tr_fr", fx, fy_, 80 * s, fh_, cur))
    if v ~= cur then ensure().frames = v end
  end)
  row("Frames in", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().framesIn) or r.framesIn
    local shown = cur == nil and "" or tostring(cur)
    local v = RegList.field(App, "ru_tr_fin", fx, fy_, 80 * s, fh_, shown, "0")
    if v ~= shown then ensure().framesIn = tonumber(v) end
  end)
  row("Sound", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().sound) or r.sound or "")
    local v = RegList.field(App, "ru_tr_snd", fx, fy_, fw, fh_, cur, "SFX_...")
    if v ~= cur then ensure().sound = v ~= "" and v or nil end
  end)
  row("Flash", function(fx, fy_, fw, fh_)
    local cur = not not ((owned and ensure().flash) or r.flash)
    if Kit.chip(fx, fy_, 80 * s, fh_, cur and "YES" or "NO", cur, PAL.yellow) then
      ensure().flash = not cur
    end
  end)
  Kit.text("micro", "Custom wipe draw() is a function — author that on CODE.",
    viewX, fy, PAL.faint)
  fy = fy + 28 * s
  return fy
end

local function drawScales(_, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  local r = type(rec) == "table" and rec or {}
  Kit.text("small", "Path", viewX, fy + 6 * s, PAL.caption)
  local fx = viewX + labelW
  local fieldW = viewW - labelW - 8 * s
  local cur = tostring((owned and ensure().path) or r.path or "")
  local v = RegList.field(App, "ru_sc_path", fx, fy, math.max(40 * s, fieldW - 100 * s),
    fh, cur, "assets/...")
  if v ~= cur then ensure().path = v end
  if Kit.button(fx + fieldW - 96 * s, fy, 96 * s, fh, "Browse", {
      kind = "ghost", tooltip = "Import PNG into mod",
    }) then
    App.pickFile("Battle pic PNG", "PNG (*.png)|*.png|All|*.*", function(picked)
      App.importToMod(picked, nil, function(rel)
        ensure().path = rel
        local Preview = require("Preview")
        if Preview.invalidate then Preview.invalidate() end
      end)
    end)
  end
  fy = fy + fh + 8 * s
  Kit.text("small", "Scale", viewX, fy + 6 * s, PAL.caption)
  local sc = (owned and ensure().scale) or r.scale or 1
  local nv = RegList.num(App, "ru_sc_sc", fx, fy, 80 * s, fh, sc)
  if nv ~= sc then
    if nv < 0.25 then nv = 0.25 end
    if nv > 4 then nv = 4 end
    ensure().scale = nv
  end
  fy = fy + fh + 8 * s
  Kit.text("micro",
    "1 = native pixels. Image-level scale beats species battleScaleFront/Back. Range 0.25–4.",
    viewX, fy, PAL.faint)
  fy = fy + 28 * s
  return fy
end

local function drawApricorns(S, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  local r = type(rec) == "table" and rec or {}
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end
  row("Apricorn", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().apricorn) or r.apricorn or "")
    local v = RegList.suggestField(App, S, "ru_ap_apr", fx, fy_, fw, fh_, cur,
      "RED_APRICORN", function() return require("Autocomplete").itemIds(S) end)
    if v ~= cur then ensure().apricorn = v end
  end)
  row("Ball", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().ball) or r.ball or "")
    local v = RegList.suggestField(App, S, "ru_ap_ball", fx, fy_, fw, fh_, cur,
      "LEVEL_BALL", function() return require("Autocomplete").itemIds(S) end)
    if v ~= cur then ensure().ball = v end
  end)
  row("Event", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().event) or r.event or 0
    local v = RegList.num(App, "ru_ap_ev", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().event = v end
  end)
  row("Index", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().index) or r.index or 1
    local v = math.max(1, RegList.num(App, "ru_ap_ix", fx, fy_, 80 * s, fh_, cur))
    if v ~= cur then ensure().index = v end
  end)
  return fy
end

local function drawRadio(_, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  local r = type(rec) == "table" and rec or {}
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end
  row("Channel", function(fx, fy_, fw, fh_)
    local cur = (owned and ensure().channel) or r.channel or 1
    local v = RegList.num(App, "ru_rd_ch", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().channel = v end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local cur = tostring((owned and ensure().name) or r.name or "")
    local v = RegList.field(App, "ru_rd_nm", fx, fy_, fw, fh_, cur, "STATION")
    if v ~= cur then ensure().name = v ~= "" and v or nil end
  end)
  Kit.text("micro", "Channel 0 is region/time-of-day, not a station. Do not claim it.",
    viewX, fy, PAL.faint)
  fy = fy + 28 * s
  return fy
end

local FORM_DRAW = {
  statuses = drawStatuses,
  rulesets = drawRulesets,
  transitions = drawTransitions,
  scales = drawScales,
  apricorns = drawApricorns,
  radio = drawRadio,
}

function Rules.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  local modes = modesFor(S)
  local valid = false
  for _, m in ipairs(modes) do
    if m.id == S.rulesMode then valid = true; break end
  end
  if not valid then S.rulesMode = modes[1] and modes[1].id end
  local modeY = RegList.modeChips(S, "rulesMode", modes, x, y, s)
  local mode = S.rulesMode or "statuses"
  if mode == "lua" then
    drawLua(S, x, modeY, w, h - (modeY - y))
    return
  end
  local spec = SPECS[mode]
  if not spec then return end
  local proj = projectBag(S, spec)
  local data = spec.data(S)
  local ids = RegList.mergeIds(proj, data)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w,
    h - (modeY - y), spec.caption, ids, {
      queryKey = "rulesQuery",
      offsetKey = "rulesListOffset",
      selKey = "rulesId_" .. mode,
      accent = PAL.yellow,
      isOwned = function(id) return proj[id] ~= nil end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        local rec = select(1, resolve(S, spec, id))
        return tostring(spec.summarize(rec)):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = "+ New",
      onFooter = function()
        local nid = allocId(proj, data, spec.newId)
        local rec = spec.newRec()
        if mode == "apricorns" then rec.apricorn = nid end
        proj[nid] = rec
        S["rulesId_" .. mode] = nid
        App.markDirty()
      end,
    })

  local selKey = "rulesId_" .. mode
  if not S[selKey] then S[selKey] = shown[1] end
  local id = S[selKey]
  local rec, owned = resolve(S, spec, id)
  if not id then
    Kit.emptyBox(formX, listY, formW, listH, "No records")
    return
  end

  Kit.caption(formX, modeY, (id or "?") .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "rulesFormScroll", mode .. ":" .. tostring(id), owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 130 * s
  local fh = 28 * s

  local function ensure()
    if owned then return proj[id] end
    proj[id] = cloneData(rec, { _isNew = false })
    owned = true
    App.markDirty()
    return proj[id]
  end

  Kit.text("micro", spec.summarize(rec), viewX, fy, PAL.muted)
  fy = fy + 20 * s

  local drawer = FORM_DRAW[mode]
  if drawer then
    fy = drawer(S, App, rec, owned, ensure, fy, viewX, viewW, fh, s, labelW)
  end

  if not owned then
    Kit.text("micro", "Edit clones into the mod (Save emits a patch).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensure()
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "rulesFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
end

return Rules
