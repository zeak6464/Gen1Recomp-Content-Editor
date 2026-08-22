-- RPG Maker-style command list for talk-script steps.
-- Mutates the existing scriptSteps / talkScripts bags; two call sites.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Generation = require("Generation")
local ModWriter = require("ModWriter")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local EventScriptEditor = {}

local FORMAT = "gen1recomp-event-script"

local CATEGORIES = {
  { id = "message", label = "Message",
    kinds = { "show_text", "ask", "show_image" } },
  { id = "party", label = "Party",
    kinds = {
      "give_item", "take_item", "check_item_skip", "check_item_missing",
      "give_pokemon", "give_starter", "oneshot_gift", "oneshot_pokemon",
      "heal_party", "give_money", "trade",
    } },
  { id = "flow", label = "Flow",
    kinds = {
      "label", "jump", "jump_if_yes", "jump_if_no", "jump_script", "opcode",
      "set_flag", "clear_flag", "check_flag_skip", "check_flag_missing",
      "set_field", "raw",
    } },
  { id = "map", label = "Map",
    kinds = { "face_player", "warp" } },
  { id = "battle", label = "Battle",
    kinds = { "wild_battle", "trainer_battle", "oneshot_trainer" } },
}

local function eventsApi()
  return require("Events")
end

local function uiFor(S, listKey)
  S._ese = S._ese or {}
  local ui = S._ese[listKey]
  if not ui then
    ui = { sel = 1, edit = false, picker = false, editKind = false,
      category = "message" }
    S._ese[listKey] = ui
  end
  return ui
end

local function kindRec(Events, kind)
  for _, rec in ipairs(Events.stepKinds()) do
    if rec.id == kind then return rec end
  end
  return nil
end

function EventScriptEditor.defaultStep(S, kind)
  local gen2 = Generation.isGen2(S)
  local mapHint = S.eventMapId or S.mapId or "PALLET_TOWN"
  local key = S.eventScriptKey or ""
  local tid = key:match("/(.+)$")
  if kind == "show_text" then
    if gen2 then
      return {
        kind = "show_text",
        text = (tid and (tid .. "_TEXT")) or "mod:TEXT",
        facePlayer = true,
        jumptext = true,
      }
    end
    return { kind = "show_text", text = tid or "Hello!" }
  elseif kind == "ask" then
    return { kind = "ask", text = tid or "OK?", skipOnNo = true }
  elseif kind == "show_image" then
    return { kind = "show_image", path = "assets/pic.png", text = "" }
  elseif kind == "give_item" then
    return { kind = "give_item", item = "POTION", count = 1 }
  elseif kind == "take_item" then
    return { kind = "take_item", item = "POTION", count = 1 }
  elseif kind == "check_item_skip" then
    return { kind = "check_item_skip", item = "POTION" }
  elseif kind == "check_item_missing" then
    return { kind = "check_item_missing", item = "POTION" }
  elseif kind == "give_pokemon" then
    return { kind = "give_pokemon", species = "EEVEE", level = 25 }
  elseif kind == "give_starter" then
    return {
      kind = "give_starter",
      species = gen2 and "CYNDAQUIL" or "BULBASAUR",
      level = 5,
      choseFlag = "EVENT_CHOSE_BULBASAUR", rivalStarter = 1,
    }
  elseif kind == "oneshot_gift" then
    return {
      kind = "oneshot_gift", text = "Here, take this!",
      after = "I already gave you one.", item = "POTION", flag = "DONE",
    }
  elseif kind == "oneshot_pokemon" then
    return {
      kind = "oneshot_pokemon", text = "Here! Take this POKeMON!",
      after = "I already gave you one.", species = "EEVEE", level = 25,
      flag = "GOT_MON",
    }
  elseif kind == "heal_party" then
    return { kind = "heal_party" }
  elseif kind == "give_money" then
    return { kind = "give_money", amount = 500 }
  elseif kind == "trade" then
    return { kind = "trade", index = 1, flag = "TRADED" }
  elseif kind == "label" then
    return { kind = "label", name = "label" }
  elseif kind == "jump" then
    return { kind = "jump", name = "end" }
  elseif kind == "jump_if_yes" then
    return { kind = "jump_if_yes", name = "yes" }
  elseif kind == "jump_if_no" then
    return { kind = "jump_if_no", name = "no" }
  elseif kind == "jump_script" then
    return { kind = "jump_script", script = "", when = "true", op = "iftrue" }
  elseif kind == "opcode" then
    return { kind = "opcode", cmd = { op = "end" }, op = "end" }
  elseif kind == "set_flag" then
    if gen2 then return { kind = "set_flag", flag = "0", event = 0 } end
    return { kind = "set_flag", flag = "DONE" }
  elseif kind == "clear_flag" then
    if gen2 then return { kind = "clear_flag", flag = "0", event = 0 } end
    return { kind = "clear_flag", flag = "DONE" }
  elseif kind == "check_flag_skip" then
    if gen2 then
      return { kind = "check_flag_skip", flag = "0", event = 0, script = "" }
    end
    return { kind = "check_flag_skip", flag = "DONE" }
  elseif kind == "check_flag_missing" then
    if gen2 then
      return { kind = "check_flag_missing", flag = "0", event = 0, script = "" }
    end
    return { kind = "check_flag_missing", flag = "DONE" }
  elseif kind == "set_field" then
    return { kind = "set_field", field = "mod:value", value = "", valueType = "str" }
  elseif kind == "raw" then
    return {
      kind = "raw",
      note = "check_flag EVENT_FLAG",
      row = { "check_flag", "EVENT_FLAG" },
    }
  elseif kind == "face_player" then
    return { kind = "face_player" }
  elseif kind == "warp" then
    return { kind = "warp", map = mapHint, x = 5, y = 6, facing = "down" }
  elseif kind == "wild_battle" then
    return { kind = "wild_battle", species = "PIDGEY", level = 5, reload = true }
  elseif kind == "trainer_battle" then
    if gen2 then
      return { kind = "trainer_battle", class = 1, member = 1, party = 1 }
    end
    return {
      kind = "trainer_battle",
      trainer = S.trainerId or "OPP_YOUNGSTER", party = 1,
    }
  elseif kind == "oneshot_trainer" then
    return {
      kind = "oneshot_trainer",
      text = "Let's fight!", won = "I lost...", after = "You're strong.",
      trainer = S.trainerId or "OPP_YOUNGSTER", party = 1,
      flag = "BEAT_TRAINER",
    }
  end
  return { kind = kind or "show_text" }
end

function EventScriptEditor.stepLine(S, step, maxW)
  local Events = eventsApi()
  local kind = (step and step.kind) or "show_text"
  local label = Events.stepLabel(kind, step)
  local detail = Events.stepPreview(S, step, math.max(40, (maxW or 400) - 80))
  if detail and detail ~= "" then
    return "@> " .. label .. ": " .. detail
  end
  return "@> " .. label
end

local function allowedKinds(S, Events)
  local out = {}
  for _, rec in ipairs(Events.stepKinds()) do
    if Events.stepKindAllowed(S, rec) then out[#out + 1] = rec end
  end
  return out
end

local function kindsInCategory(S, Events, cat)
  local allowed = {}
  for _, id in ipairs(cat.kinds) do
    local rec = kindRec(Events, id)
    if rec and Events.stepKindAllowed(S, rec) then
      allowed[#allowed + 1] = rec
    end
  end
  return allowed
end

local function clampSel(ui, steps)
  local n = #(steps or {})
  if n == 0 then
    ui.sel = 0
    ui.edit = false
    return
  end
  if not ui.sel or ui.sel < 1 then ui.sel = 1 end
  if ui.sel > n then ui.sel = n end
end

local function swapSteps(steps, i, j)
  if type(steps) ~= "table" then return false end
  if i < 1 or j < 1 or i > #steps or j > #steps or i == j then return false end
  steps[i], steps[j] = steps[j], steps[i]
  return true
end

local function isTextKey(value)
  if type(value) ~= "string" or value == "" then return false end
  if value:find("[%s\\]") then return false end
  return value:match("^TEXT_") or value:match("^_[%w_]+")
    or value:match("_TEXT$") or value:match("^mod:")
end

local function collectText(S, steps)
  local bag = {}
  local function take(key)
    if not isTextKey(key) then return end
    local body
    if S.project and S.project.text and S.project.text[key] ~= nil then
      body = tostring(S.project.text[key])
    elseif S.data and S.data.text and S.data.text[key] ~= nil then
      body = tostring(S.data.text[key])
    end
    if body then bag[key] = body end
  end
  for _, step in ipairs(steps or {}) do
    take(step.text)
    take(step.after)
    take(step.won)
  end
  return bag
end

local function mergeText(S, text)
  if type(text) ~= "table" then return 0 end
  State.ensureProjectFields(S.project)
  S.project.text = S.project.text or {}
  local n = 0
  for k, v in pairs(text) do
    if type(k) == "string" and type(v) == "string" then
      S.project.text[k] = v
      if S.data and S.data.text then S.data.text[k] = v end
      n = n + 1
    end
  end
  return n
end

local function safeScriptId(scriptId)
  local id = tostring(scriptId or "script"):gsub("[^%w_%-]", "_")
  if id == "" then id = "script" end
  return id
end

local function mkdir(path)
  local sep = package.config:sub(1, 1)
  if sep == "\\" then
    os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. package.config:sub(1, 1) .. b
end

function EventScriptEditor.exportFile(S, App, scriptId, steps)
  if not (S and S.path) then return false, "no open mod" end
  local Events = eventsApi()
  local dir = join(S.path, "scripts")
  mkdir(dir)
  local rel = "scripts/" .. safeScriptId(scriptId) .. ".lua"
  local path = join(S.path, rel:gsub("/", package.config:sub(1, 1)))
  local payload = {
    format = FORMAT,
    version = 1,
    scriptKey = scriptId,
    steps = Events.cloneSteps(steps),
    text = collectText(S, steps),
  }
  local body = "-- Event script exported by the Gen1Recomp content editor.\n"
    .. "return " .. ModWriter.encodeLua(payload) .. "\n"
  local ok, err = require("ModIO").writeText(path, body)
  if not ok then return false, tostring(err or "write failed") end
  return true, path
end

function EventScriptEditor.importFile(S, App, steps, onDone)
  if not App or not App.pickFile then return false, "no file picker" end
  App.pickFile("Event script", "Lua (*.lua)|*.lua|All (*.*)|*.*",
    function(picked)
      if not picked or picked == "" then return end
      local f, oerr = io.open(picked, "rb")
      if not f then
        S.status = "Import failed: " .. tostring(oerr)
        return
      end
      local src = f:read("*a") or ""
      f:close()
      local loader = loadstring or load
      local chunk, lerr = loader(src, picked)
      if not chunk then
        S.status = "Import failed: " .. tostring(lerr)
        return
      end
      local ok, data = pcall(chunk)
      if not ok or type(data) ~= "table" then
        S.status = "Import failed: file did not return a table"
        return
      end
      if data.format ~= FORMAT then
        S.status = "Import failed: not a " .. FORMAT .. " file"
        return
      end
      if type(data.steps) ~= "table" then
        S.status = "Import failed: missing steps"
        return
      end
      local Events = eventsApi()
      Events.replaceSteps(steps, data.steps)
      local nText = mergeText(S, data.text)
      if onDone then onDone() end
      if App.markDirty then App.markDirty() end
      S.status = string.format("Imported %d steps%s",
        #steps, nText > 0 and (" · " .. nText .. " text keys") or "")
    end)
  return true
end

local function mark(S, App, onChange)
  if App and App.markDirty then App.markDirty() end
  if onChange then onChange() end
end

local function drawPicker(S, App, ui, Events, x, y, w, h, steps, onChange)
  local s = Kit.scale
  Theme.col(PAL.rowBg, 0.92)
  love.graphics.rectangle("fill", x, y, w, h, 8 * s, 8 * s)
  Kit.text("micro", "INSERT COMMAND", x + 8 * s, y + 6 * s, PAL.caption)
  local cy = y + 24 * s
  local cx = x + 8 * s
  for _, cat in ipairs(CATEGORIES) do
    if #kindsInCategory(S, Events, cat) > 0 then
      local bw = Kit.textWidth("micro", cat.label) + 16 * s
      if Kit.chip(cx, cy, bw, 22 * s, cat.label,
          ui.category == cat.id, PAL.yellow, PAL.steel) then
        ui.category = cat.id
      end
      cx = cx + bw + 4 * s
    end
  end
  local cat
  for _, c in ipairs(CATEGORIES) do
    if c.id == ui.category then cat = c; break end
  end
  cat = cat or CATEGORIES[1]
  local kinds = kindsInCategory(S, Events, cat)
  local kx, ky = x + 8 * s, cy + 28 * s
  for _, rec in ipairs(kinds) do
    local bw = Kit.textWidth("micro", rec.label) + 14 * s
    if kx + bw > x + w - 8 * s and kx > x + 8 * s then
      kx = x + 8 * s
      ky = ky + 24 * s
    end
    if ky + 22 * s > y + h - 6 * s then break end
    if Kit.chip(kx, ky, bw, 22 * s, rec.label, false, PAL.blue, PAL.steel) then
      local step = EventScriptEditor.defaultStep(S, rec.id)
      local at = math.max(0, ui.sel or 0)
      table.insert(steps, at + 1, step)
      ui.sel = at + 1
      ui.edit = true
      ui.picker = false
      ui.editKind = false
      mark(S, App, onChange)
    end
    kx = kx + bw + 4 * s
  end
  if Kit.button(x + w - 70 * s, y + 4 * s, 62 * s, 20 * s, "Close", {
      kind = "ghost", font = "small",
    }) then
    ui.picker = false
  end
end

local function drawFooter(S, App, ui, x, y, w, h, steps, readOnly, scriptId, onChange)
  local s = Kit.scale
  local bh = 24 * s
  local gap = 4 * s
  local bx, by = x, y
  local maxX = x + w
  local function slot(label, kind, tip, enabled)
    local bw = Kit.textWidth("small", label) + 14 * s
    if bx + bw > maxX and bx > x then
      bx = x
      by = by + bh + gap
    end
    local hit = false
    if Kit.button(bx, by, bw, bh, label, {
        kind = kind or "ghost", font = "small", tooltip = tip,
        enabled = enabled ~= false,
      }) then
      hit = true
    end
    bx = bx + bw + gap
    return hit
  end

  if not readOnly and slot("Insert", "good", "Add a command from the picker") then
    ui.picker = true
    ui.edit = false
    ui.editKind = false
  end
  if not readOnly and slot("Edit", "accent", "Edit the selected command",
      ui.sel and ui.sel > 0) then
    ui.edit = true
    ui.picker = false
    ui.editKind = false
  end
  if not readOnly and slot("Delete", "danger", "Remove the selected command",
      ui.sel and ui.sel > 0) then
    table.remove(steps, ui.sel)
    clampSel(ui, steps)
    ui.edit = false
    mark(S, App, onChange)
  end
  if not readOnly and slot("^", "ghost", "Move up",
      ui.sel and ui.sel > 1) then
    if swapSteps(steps, ui.sel, ui.sel - 1) then
      ui.sel = ui.sel - 1
      mark(S, App, onChange)
    end
  end
  if not readOnly and slot("v", "ghost", "Move down",
      ui.sel and ui.sel < #steps) then
    if swapSteps(steps, ui.sel, ui.sel + 1) then
      ui.sel = ui.sel + 1
      mark(S, App, onChange)
    end
  end
  if slot("Copy", "ghost", "Copy these steps") then
    local Events = eventsApi()
    S.eventClip = {
      type = Generation.isGen2(S) and "gen2Steps" or "talkSteps",
      key = S.eventScriptKey,
      scriptKey = scriptId,
      steps = Events.cloneSteps(steps),
    }
    S.status = string.format("Copied %d steps", #steps)
  end
  if not readOnly and slot("Paste", "good", "Replace steps with clipboard",
      S.eventClip and type(S.eventClip.steps) == "table") then
    local Events = eventsApi()
    Events.replaceSteps(steps, S.eventClip.steps)
    clampSel(ui, steps)
    mark(S, App, onChange)
    S.status = string.format("Pasted %d steps", #steps)
  end
  if not readOnly and slot("Import", "ghost", "Load steps from a .lua file") then
    EventScriptEditor.importFile(S, App, steps, onChange)
  end
  if slot("Export", "ghost", "Write scripts/<id>.lua under this mod") then
    local ok, msg = EventScriptEditor.exportFile(S, App, scriptId, steps)
    if ok then
      S.status = "Exported " .. tostring(msg)
    else
      S.status = "Export failed: " .. tostring(msg)
    end
  end
  return by + bh - y
end

-- opts: x, y, w, h, steps, scriptId, listKey, readOnly, onChange
function EventScriptEditor.draw(S, App, opts)
  opts = opts or {}
  local Events = eventsApi()
  Events.bindSession(S)
  local s = Kit.scale
  local x, y, w, h = opts.x, opts.y, opts.w, opts.h
  local steps = opts.steps
  if type(steps) ~= "table" then
    Kit.emptyBox(x, y, w, h, "No script steps")
    return
  end
  local readOnly = opts.readOnly == true
  local listKey = opts.listKey or ("ese:" .. tostring(opts.scriptId or ""))
  local ui = uiFor(S, listKey)
  clampSel(ui, steps)

  local footerH = 56 * s
  local pad = 4 * s
  local listY = y
  local listH = math.max(40 * s, h - footerH - pad)
  local editH = 0
  if ui.edit and not readOnly and ui.sel and steps[ui.sel] then
    editH = math.min(160 * s, math.floor(listH * 0.55))
    listH = listH - editH - 4 * s
  end

  Theme.col(PAL.rowBg, 0.35)
  love.graphics.rectangle("fill", x, listY, w, listH, 6 * s, 6 * s)

  if ui.picker == true and not readOnly then
    drawPicker(S, App, ui, Events, x, listY, w, listH, steps, opts.onChange)
  else
    local rowH = 22 * s
    FormPane.track(S, "eseScroll", listKey)
    local fy, view = FormPane.begin(S, "eseScroll", x + 2 * s, listY + 4 * s,
      w - 4 * s, listH - 8 * s)
    local contentTop = fy
    local innerW = view.contentW or (w - 8 * s)
    if #steps == 0 then
      Kit.text("micro", "No commands — Insert to add one.",
        x + 10 * s, fy + 4 * s, PAL.muted)
      fy = fy + rowH
    end
    for i, step in ipairs(steps) do
      local selected = ui.sel == i
      if Kit.row(x + 6 * s, fy, innerW - 8 * s, rowH, selected, PAL.yellow) then
        if selected and not readOnly then
          ui.edit = not ui.edit
          ui.picker = false
          ui.editKind = false
        else
          ui.sel = i
          if not readOnly then ui.edit = false end
        end
      end
      local line = string.format("%d %s", i,
        EventScriptEditor.stepLine(S, step, innerW - 24 * s))
      Kit.text("micro", Kit.ellipsize("micro", line, innerW - 16 * s),
        x + 10 * s, fy + 4 * s, selected and PAL.heading or PAL.text)
      fy = fy + rowH
    end
    FormPane.finish(S, "eseScroll", contentTop, fy, view)
  end

  if editH > 0 then
    local ex, ey, ew, eh = x, listY + listH + 4 * s, w, editH
    Theme.col(PAL.rowBg, 0.5)
    love.graphics.rectangle("fill", ex, ey, ew, eh, 6 * s, 6 * s)
    local step = steps[ui.sel]
    local kind = step.kind or "show_text"
    local kindW = 168 * s
    if Kit.button(ex + 6 * s, ey + 6 * s, kindW, 24 * s,
        Kit.ellipsize("small", Events.stepLabel(kind, step), kindW - 10 * s), {
          kind = "accent", font = "small",
          tooltip = "Change command type",
        }) then
      ui.editKind = not ui.editKind
    end
    Kit.text("micro", "Command " .. tostring(ui.sel),
      ex + kindW + 14 * s, ey + 10 * s, PAL.faint)
    if ui.editKind then
      local kinds = allowedKinds(S, Events)
      local kx, ky = ex + 6 * s, ey + 34 * s
      for _, rec in ipairs(kinds) do
        local bw = Kit.textWidth("micro", rec.label) + 12 * s
        if kx + bw > ex + ew - 6 * s then
          kx = ex + 6 * s
          ky = ky + 22 * s
        end
        if ky + 20 * s > ey + eh then break end
        if Kit.chip(kx, ky, bw, 20 * s, rec.label,
            rec.id == kind, PAL.blue, PAL.steel) then
          local fresh = EventScriptEditor.defaultStep(S, rec.id)
          for k in pairs(step) do step[k] = nil end
          for k, v in pairs(fresh) do step[k] = v end
          ui.editKind = false
          mark(S, App, opts.onChange)
        end
        kx = kx + bw + 4 * s
      end
    else
      Events.drawStepFields(S, App, step, ui.sel, kind,
        ex + 6 * s, ey + 36 * s, ew - 12 * s, 26 * s, s)
    end
  end

  drawFooter(S, App, ui, x, y + h - footerH, w, footerH,
    steps, readOnly, opts.scriptId, opts.onChange)
end

return EventScriptEditor
