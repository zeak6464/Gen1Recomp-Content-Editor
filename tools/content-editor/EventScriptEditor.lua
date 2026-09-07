-- RPG Maker-style command list for talk-script steps.
-- Mutates the existing scriptSteps / talkScripts bags; two call sites.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Generation = require("Generation")
local ModWriter = require("ModWriter")
local FormPane = require("FormPane")
local OpcodeHelp = require("OpcodeHelp")
local Autocomplete = require("Autocomplete")
local PAL = Theme.PAL

local CMD_ID = "ese_cmd"

local PRESET_FILL = {
  show_text = { "text" },
  ask = { "text" },
  show_image = { "path", "text" },
  give_item = { "item", "count" },
  take_item = { "item", "count" },
  check_item_skip = { "item" },
  check_item_missing = { "item" },
  give_pokemon = { "species", "level" },
  give_starter = { "species", "level" },
  oneshot_gift = { "item", "flag" },
  oneshot_pokemon = { "species", "level" },
  give_money = { "amount" },
  trade = { "index" },
  label = { "name" },
  jump = { "name" },
  jump_if_yes = { "name" },
  jump_if_no = { "name" },
  jump_script = { "script" },
  set_flag = { "flag" },
  clear_flag = { "flag" },
  check_flag_skip = { "flag" },
  check_flag_missing = { "flag" },
  set_field = { "field", "value" },
  warp = { "map", "x", "y" },
  wild_battle = { "species", "level" },
  trainer_battle = { "trainer", "party" },
  oneshot_trainer = { "trainer" },
}

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
    ui = { sel = 1, editKind = false, category = "message", cmd = "" }
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
  local yellow = Generation.id(S) == "yellow"
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
      species = gen2 and "CYNDAQUIL" or (yellow and "PIKACHU" or "BULBASAUR"),
      level = 5,
      choseFlag = yellow and "EVENT_CHOSE_PIKACHU" or "EVENT_CHOSE_BULBASAUR", rivalStarter = 1,
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

local function tokenize(text)
  local out = {}
  local i = 1
  local s = tostring(text or "")
  while i <= #s do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == '"' then
      local j = s:find('"', i + 1)
      out[#out + 1] = s:sub(i + 1, (j or (#s + 1)) - 1)
      i = (j or #s) + 1
    else
      local tok = s:match("^%S+", i)
      out[#out + 1] = tok
      i = i + #tok
    end
  end
  return out
end

local function firstToken(text)
  return tostring(text or ""):match("^%s*(%S+)")
end

local function replaceFirstToken(text, picked)
  local rest = tostring(text or ""):match("^%s*%S+%s+(.*)$")
  if rest and rest ~= "" then return picked .. " " .. rest end
  return picked .. " "
end

local function matchKind(S, Events, name)
  if type(name) ~= "string" or name == "" then return nil end
  local key = name:lower():gsub("[%s%-]+", "_"):gsub("^%++_", "")
  if Events then
    for _, rec in ipairs(allowedKinds(S, Events)) do
      if rec.id == name or rec.id:lower() == key then return rec.id end
      local lab = tostring(rec.label or ""):lower():gsub("[%s%-]+", "_")
      if lab == key then return rec.id end
    end
  else
    for _, cat in ipairs(CATEGORIES) do
      for _, id in ipairs(cat.kinds) do
        if id:lower() == key then return id end
      end
    end
    if PRESET_FILL[key] then return key end
  end
  return nil
end

local function fillPreset(step, tokens)
  local keys = PRESET_FILL[step.kind]
  if not keys then return step end
  for i, key in ipairs(keys) do
    local raw = tokens[i + 1]
    if raw ~= nil and raw ~= "" then
      local n = tonumber(raw)
      if type(step[key]) == "number" or key == "count" or key == "level"
          or key == "amount" or key == "index" or key == "party"
          or key == "x" or key == "y" then
        step[key] = n or raw
      else
        step[key] = raw
      end
    end
  end
  return step
end

function EventScriptEditor.parseCommand(S, text)
  local line = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if line == "" then return nil, "empty" end
  local tokens = tokenize(line)
  local okEv, Events = pcall(eventsApi)
  if not okEv then Events = nil end
  local op = OpcodeHelp.parseLine(line)
  if op then
    return { kind = "opcode", cmd = op, op = op.op }
  end
  local kind = matchKind(S, Events, tokens[1])
  if kind == "opcode" then
    local rest = line:match("^%S+%s+(.*)$")
    if rest and rest ~= "" then
      local cmd = OpcodeHelp.parseLine(rest)
      if cmd then return { kind = "opcode", cmd = cmd, op = cmd.op } end
    end
    return EventScriptEditor.defaultStep(S, "opcode")
  end
  if kind then
    return fillPreset(EventScriptEditor.defaultStep(S, kind), tokens)
  end
  if not Generation.isGen2(S) then
    return { kind = "raw", note = line, row = tokens }
  end
  local cmd = { op = tokens[1] }
  for i = 2, #tokens do
    cmd["arg" .. (i - 1)] = tokens[i]
  end
  return { kind = "opcode", cmd = cmd, op = tokens[1] }
end

local function insertStep(S, App, ui, steps, step, onChange)
  if type(step) ~= "table" then return end
  local at = math.max(0, ui.sel or 0)
  table.insert(steps, at + 1, step)
  ui.sel = at + 1
  ui.editKind = false
  mark(S, App, onChange)
end

local function submitCommand(S, App, ui, steps, onChange)
  local step, err = EventScriptEditor.parseCommand(S, ui.cmd)
  if not step then
    if err ~= "empty" then
      S.status = "Could not parse command"
    end
    return false
  end
  insertStep(S, App, ui, steps, step, onChange)
  ui.cmd = ""
  Kit.focus = CMD_ID
  S.status = "Inserted " .. tostring(step.kind or step.op or "command")
  return true
end

function EventScriptEditor.keypressed(S, key)
  if not S or Kit.focus ~= CMD_ID then return false end
  if key == "return" or key == "kpenter" then
    S._eseSubmit = true
    return true
  end
  return false
end

local function commandIds(S, Events)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) ~= "string" or id == "" or seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
  end
  if Generation.isGen2(S) then
    for _, op in ipairs(OpcodeHelp.ops()) do add(op) end
  end
  for _, rec in ipairs(allowedKinds(S, Events)) do add(rec.id) end
  return ids
end

local function drawCommandLine(S, App, ui, Events, x, y, w, h, steps, onChange)
  local s = Kit.scale
  Kit.text("micro", "TYPE A COMMAND", x, y, PAL.caption)
  local fy = y + 14 * s
  local addW = 56 * s
  local picked = Autocomplete.takePick(S, CMD_ID)
  if picked then
    ui.cmd = replaceFirstToken(ui.cmd, picked)
    Kit.focus = CMD_ID
  end
  if S._eseSubmit then
    S._eseSubmit = nil
    submitCommand(S, App, ui, steps, onChange)
  end
  local v = Kit.textfield(CMD_ID, x, fy, w - addW - 6 * s, h,
    ui.cmd or "", "appear 3   applymovement 2 jump_bush",
    "Type an opcode or preset and press Enter")
  ui.cmd = v
  local first = firstToken(v)
  local exact = first and (OpcodeHelp.resolve(first) or matchKind(S, Events, first))
  local rest = first and v:match("^%s*%S+(.*)$")
  if Kit.focus == CMD_ID and not (exact and rest and rest:match("^%s")) then
    Autocomplete.offer(S, {
      fieldId = CMD_ID,
      x = x,
      y = fy + h + 2 * s,
      w = w - addW - 6 * s,
      query = first or v,
      ids = commandIds(S, Events),
    })
  end
  if Kit.button(x + w - addW, fy, addW, h, "Add", {
      kind = "good", font = "small",
      tooltip = "Insert this line after the selected step",
    }) then
    submitCommand(S, App, ui, steps, onChange)
  end
  return fy + h
end

local function drawPresetStrip(S, App, ui, Events, x, y, w, steps, onChange)
  local s = Kit.scale
  Kit.text("micro", "OR CLICK A PRESET", x, y, PAL.caption)
  local cy = y + 14 * s
  local cx = x
  local fh = 20 * s
  for _, cat in ipairs(CATEGORIES) do
    if #kindsInCategory(S, Events, cat) > 0 then
      local bw = Kit.textWidth("micro", cat.label) + 14 * s
      if cx + bw > x + w and cx > x then
        cx = x
        cy = cy + fh + 3 * s
      end
      if Kit.chip(cx, cy, bw, fh, cat.label,
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
  cx, cy = x, cy + fh + 6 * s
  for _, rec in ipairs(kinds) do
    local bw = Kit.textWidth("micro", rec.label) + 12 * s
    if cx + bw > x + w and cx > x then
      cx = x
      cy = cy + fh + 3 * s
    end
    if Kit.chip(cx, cy, bw, fh, rec.label, false, PAL.blue, PAL.steel,
        "Insert " .. rec.label) then
      insertStep(S, App, ui, steps, EventScriptEditor.defaultStep(S, rec.id),
        onChange)
    end
    cx = cx + bw + 4 * s
  end
  return cy + fh
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

  if not readOnly and slot("Insert", "good", "Focus the command line") then
    Kit.focus = CMD_ID
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
  local gap = 8 * s
  local bodyH = math.max(40 * s, h - footerH - 4 * s)
  local listW = math.max(140 * s, math.floor(w * 0.42))
  local editX = x + listW + gap
  local editW = math.max(120 * s, w - listW - gap)

  Theme.col(PAL.rowBg, 0.35)
  love.graphics.rectangle("fill", x, y, listW, bodyH, 6 * s, 6 * s)

  local rowH = 20 * s
  local listInnerX, listInnerY = x + 4 * s, y + 4 * s
  local listInnerW, listInnerH = listW - 8 * s, bodyH - 8 * s
  local per = math.max(1, math.floor(listInnerH / rowH))
  local innerW = Kit.scrollInnerWidth(listInnerW)
  local scrollId = "eseList:" .. listKey
  ui.offset = Kit.scroll(listInnerX, listInnerY, listInnerW, listInnerH,
    ui.offset or 0, math.max(#steps, 1), per, 1, scrollId)
  Kit.pushClip(listInnerX, listInnerY, innerW, listInnerH)
  if #steps == 0 then
    Kit.text("micro", "No commands yet — type one on the right.",
      listInnerX + 6 * s, listInnerY + 6 * s, PAL.muted)
  end
  for i = 1, per do
    local li = (ui.offset or 0) + i
    local step = steps[li]
    if not step then break end
    local ry = listInnerY + (i - 1) * rowH
    local selected = ui.sel == li
    if Kit.row(listInnerX + 2 * s, ry, innerW - 4 * s, rowH - 1, selected,
        PAL.yellow) then
      ui.sel = li
      ui.editKind = false
    end
    local line = string.format("%d %s", li,
      EventScriptEditor.stepLine(S, step, innerW - 20 * s))
    Kit.text("micro", Kit.ellipsize("micro", line, innerW - 10 * s),
      listInnerX + 6 * s, ry + 3 * s, selected and PAL.heading or PAL.text)
  end
  Kit.popClip()
  ui.offset = Kit.scrollbar(listInnerX, listInnerY, listInnerW, listInnerH,
    ui.offset or 0, math.max(#steps, 1), per, scrollId)

  Theme.col(PAL.rowBg, 0.28)
  love.graphics.rectangle("fill", editX, y, editW, bodyH, 6 * s, 6 * s)
  local ex, ey, ew = editX + 8 * s, y + 6 * s, editW - 16 * s
  if not readOnly then
    ey = drawCommandLine(S, App, ui, Events, ex, ey, ew, 26 * s,
      steps, opts.onChange) + 8 * s
  end

  FormPane.track(S, "eseEdit", listKey)
  local fy, view = FormPane.begin(S, "eseEdit", ex, ey, ew,
    math.max(40 * s, y + bodyH - ey - 4 * s))
  local contentTop = fy
  local fw = view.contentW or ew
  local step = steps[ui.sel]
  if step then
    local kind = step.kind or "show_text"
    local kindW = math.min(168 * s, fw * 0.55)
    if not readOnly and Kit.button(ex, fy, kindW, 24 * s,
        Kit.ellipsize("small", Events.stepLabel(kind, step), kindW - 10 * s), {
          kind = "accent", font = "small",
          tooltip = "Change command type",
        }) then
      ui.editKind = not ui.editKind
    elseif readOnly then
      Kit.text("small", Events.stepLabel(kind, step), ex, fy + 4 * s, PAL.heading)
    end
    Kit.text("micro", "Command " .. tostring(ui.sel),
      ex + kindW + 10 * s, fy + 6 * s, PAL.faint)
    fy = fy + 28 * s
    if ui.editKind and not readOnly then
      local kx = ex
      for _, rec in ipairs(allowedKinds(S, Events)) do
        local bw = Kit.textWidth("micro", rec.label) + 12 * s
        if kx + bw > ex + fw and kx > ex then
          kx = ex
          fy = fy + 22 * s
        end
        if Kit.chip(kx, fy, bw, 20 * s, rec.label,
            rec.id == kind, PAL.blue, PAL.steel) then
          local fresh = EventScriptEditor.defaultStep(S, rec.id)
          for k in pairs(step) do step[k] = nil end
          for k, v in pairs(fresh) do step[k] = v end
          ui.editKind = false
          mark(S, App, opts.onChange)
        end
        kx = kx + bw + 4 * s
      end
      fy = fy + 26 * s
    elseif not readOnly then
      local used = Events.drawStepFields(S, App, step, ui.sel, kind,
        ex, fy, fw, 26 * s, s)
      fy = fy + math.max(1, tonumber(used) or 1) * 30 * s + 8 * s
    end
  else
    Kit.text("micro", readOnly and "No command selected"
      or "Type a command above, or click a preset.",
      ex, fy, PAL.muted)
    fy = fy + 22 * s
  end
  if not readOnly then
    fy = drawPresetStrip(S, App, ui, Events, ex, fy, fw, steps, opts.onChange)
      + 8 * s
  end
  FormPane.finish(S, "eseEdit", contentTop, fy, view)

  drawFooter(S, App, ui, x, y + h - footerH, w, footerH,
    steps, readOnly, opts.scriptId, opts.onChange)
end

return EventScriptEditor
