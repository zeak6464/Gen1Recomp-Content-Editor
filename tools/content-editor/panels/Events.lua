-- Events tab: talk-script step builder, Oak starter remap, save-flag tester.
-- Gen1 SCRIPTS: TEXT_* + MapScripts. Gold: edit talk scripts (Says / face) + PHONE.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local SaveIO = require("SaveIO")
local Search = require("Search")
local FormPane = require("FormPane")
local TalkIndex = require("TalkIndex")
local Gen2Talk = require("Gen2Talk")
local ModWriter = require("ModWriter")
local RegList = require("RegList")
local SpeciesPicker = require("SpeciesPicker")
local ItemPicker = require("ItemPicker")
local Autocomplete = require("Autocomplete")
local ChoicePicker = require("ChoicePicker")
local Code = require("Code")
local ModIO = require("ModIO")
local Generation = require("Generation")
local EventScriptEditor = require("EventScriptEditor")
local OpcodeHelp = require("OpcodeHelp")
local PAL = Theme.PAL

local Events = {}
local acS -- session for RegList.suggestField (set in Events.draw)

-- gen1Only / gen2Only gate cycleKind + shortcuts. Omit both = all gens.
local STEP_KINDS = {
  { id = "show_text", label = "Show text" },
  { id = "show_image", label = "Show image", gen1Only = true },
  { id = "ask", label = "Ask yes/no" },
  { id = "label", label = "Label", gen1Only = true },
  { id = "jump", label = "Jump to label", gen1Only = true },
  { id = "jump_if_yes", label = "Jump if yes", gen1Only = true },
  { id = "jump_if_no", label = "Jump if no", gen1Only = true },
  { id = "jump_script", label = "Go to script", gen2Only = true },
  { id = "opcode", label = "Other command", gen2Only = true },
  { id = "face_player", label = "Face player" },
  { id = "give_item", label = "Give item" },
  { id = "take_item", label = "Take item" },
  { id = "check_item_skip", label = "Skip if has item", gen1Only = true },
  { id = "check_item_missing", label = "Skip if no item", gen1Only = true },
  { id = "give_pokemon", label = "Give pokemon" },
  { id = "give_starter", label = "Give starter" },
  { id = "oneshot_gift", label = "One-shot item" },
  { id = "oneshot_pokemon", label = "One-shot pokemon", gen1Only = true },
  { id = "set_flag", label = "Set flag" },
  { id = "clear_flag", label = "Clear flag" },
  { id = "check_flag_skip", label = "Skip if flag set" },
  { id = "check_flag_missing", label = "Skip if flag clear" },
  { id = "heal_party", label = "Heal party" },
  { id = "give_money", label = "Give money", gen1Only = true },
  { id = "warp", label = "Warp" },
  { id = "wild_battle", label = "Wild battle" },
  { id = "trainer_battle", label = "Trainer battle" },
  { id = "oneshot_trainer", label = "One-shot trainer", gen1Only = true },
  { id = "set_field", label = "Set save field", gen1Only = true },
  { id = "trade", label = "In-game trade", gen1Only = true },
  { id = "raw", label = "Engine cmd", gen1Only = true },
}

local function stepKindAllowed(S, kindRec)
  if not kindRec then return false end
  local gen2 = Generation.isGen2(S)
  if gen2 and kindRec.gen1Only then return false end
  if not gen2 and kindRec.gen2Only then return false end
  return true
end

local OAK_BALLS = {
  { from = "CHARMANDER", label = "Left ball (Charmander)" },
  { from = "SQUIRTLE", label = "Middle ball (Squirtle)" },
  { from = "BULBASAUR", label = "Right ball (Bulbasaur)" },
}

-- Yellow Oak's Lab: one Pikachu gift (no three-ball choice). Rival's Eevee
-- ball is a separate script, not a starter pick.
local YELLOW_STARTER = {
  { from = "PIKACHU", label = "Oak's gift (Pikachu)" },
}

-- Elm's Lab left→right (Cyndaquil / Totodile / Chikorita), matching Oak's
-- fire / water / grass ball order.
local ELM_BALLS = {
  { from = "CYNDAQUIL", label = "Left ball (Cyndaquil)" },
  { from = "TOTODILE", label = "Middle ball (Totodile)" },
  { from = "CHIKORITA", label = "Right ball (Chikorita)" },
}

-- Footer quick-add buttons (kind = Kit button style).
-- Order matters: most-used first so a tight footer still shows Warp / flags.
local function shortcutDefs(S)
  local mapHint = S.eventMapId or S.mapId or "PALLET_TOWN"
  local gen2 = Generation.isGen2(S)
  local list = {
    { label = "+ Text", kind = "good",
      tip = "Show a dialog box. Edit the words after you add it.",
      make = function()
        local key = S.eventScriptKey or ""
        local tid = key:match("/(.+)$")
        if gen2 then
          return {
            kind = "show_text",
            text = (tid and (tid .. "_TEXT")) or "mod:TEXT",
            facePlayer = true,
            jumptext = true,
          }
        end
        return { kind = "show_text", text = tid or "..." }
      end },
    { label = "+ Warp", kind = "good",
      tip = "Move the player to another map. Set the map name and X/Y after adding.",
      make = function()
        return {
          kind = "warp", map = mapHint, x = 5, y = 6, facing = "down",
        }
      end },
    { label = "+ Set flag", kind = "accent",
      tip = "Mark a story flag as done (so this event can refuse to repeat).",
      make = function()
        if gen2 then return { kind = "set_flag", flag = "0", event = 0 } end
        return { kind = "set_flag", flag = "DONE" }
      end },
    { label = "+ If flag", kind = "ghost",
      tip = "Skip the rest of these steps if a flag is already set.",
      make = function()
        if gen2 then
          return {
            kind = "check_flag_skip", flag = "0", event = 0, script = "",
          }
        end
        return { kind = "check_flag_skip", flag = "DONE" }
      end },
    { label = "+ If no flag", kind = "ghost", gen1Only = true,
      tip = "Skip the rest of these steps if a flag is still clear.",
      make = function()
        return { kind = "check_flag_missing", flag = "DONE" }
      end },
    { label = "+ Face", kind = "ghost",
      tip = "Turn this NPC to face the player before talking.",
      make = function() return { kind = "face_player" } end },
    { label = "+ Ask", kind = "accent",
      tip = "Yes / No question. By default the rest is skipped on No.",
      make = function()
        local key = S.eventScriptKey or ""
        local tid = key:match("/(.+)$")
        return { kind = "ask", text = tid or "OK?", skipOnNo = true }
      end },
    { label = "+ Item", kind = "accent",
      tip = "Put an item in the bag (Potion ×1 by default).",
      make = function()
        return { kind = "give_item", item = "POTION", count = 1 }
      end },
    { label = "1-shot item", kind = "ghost",
      tip = "Give an item once, then a different line if they talk again.",
      make = function()
        return {
          kind = "oneshot_gift", text = "Here, take this!",
          after = "I already gave you one.", item = "POTION", flag = "DONE",
        }
      end },
    { label = "+ Heal", kind = "ghost",
      tip = "Fully heal the party (Poké Center style).",
      make = function() return { kind = "heal_party" } end },
    { label = "+ Command", kind = "ghost", gen1Only = true,
      tip = "A raw game command (check_flag, hide_object, play_sound…). Edit the row after adding.",
      make = function()
        return {
          kind = "raw",
          note = "check_flag EVENT_FLAG",
          row = { "check_flag", "EVENT_FLAG" },
        }
      end },
    { label = "+ Opcode", kind = "ghost", gen2Only = true,
      tip = "A Gold/Crystal command by opcode name. Starts as 'end'; pick the real one after.",
      make = function()
        return { kind = "opcode", cmd = { op = "end" }, op = "end" }
      end },
    { label = "+ Go to", kind = "ghost", gen2Only = true,
      tip = "Jump into another script (always, or only on Yes / No).",
      make = function()
        return {
          kind = "jump_script", script = "", when = "true", op = "iftrue",
        }
      end },
    { label = "+ Pokemon", kind = "accent",
      tip = "Give a Pokémon and ask for a nickname.",
      make = function()
        return { kind = "give_pokemon", species = "EEVEE", level = 25 }
      end },
    { label = "+ Wild", kind = "accent",
      tip = "Start a wild battle (species and level are editable).",
      make = function()
        return { kind = "wild_battle", species = "PIDGEY", level = 5, reload = true }
      end },
    { label = "+ Trainer", kind = "accent",
      tip = "Start a trainer battle. Does not mark them beaten by itself.",
      make = function()
        if gen2 then
          return { kind = "trainer_battle", class = 1, member = 1, party = 1 }
        end
        return {
          kind = "trainer_battle",
          trainer = S.trainerId or "OPP_YOUNGSTER", party = 1,
        }
      end },
    { label = "1-shot fight", kind = "accent", gen1Only = true,
      tip = "A trainer who fights once: intro text, battle, then a beaten line.",
      make = function()
        return {
          kind = "oneshot_trainer",
          text = "Let's fight!", won = "I lost...", after = "You're strong.",
          trainer = S.trainerId or "OPP_YOUNGSTER", party = 1,
          flag = "BEAT_TRAINER",
        }
      end },
    { label = "1-shot mon", kind = "ghost", gen1Only = true,
      tip = "Give a Pokémon once, then a different line if they talk again.",
      make = function()
        return {
          kind = "oneshot_pokemon", text = "Here! Take this POKeMON!",
          after = "I already gave you one.", species = "EEVEE", level = 25,
          flag = "GOT_MON",
        }
      end },
    { label = "+ Starter", kind = "accent",
      tip = Generation.id(S) == "yellow"
        and "Give Oak's Pikachu (EVENT_GOT_STARTER + EVENT_CHOSE_PIKACHU)."
        or "Give a lab starter and set EVENT_GOT_STARTER plus the chose-flag.",
      make = function()
        local yellow = Generation.id(S) == "yellow"
        return {
          kind = "give_starter",
          species = gen2 and "CYNDAQUIL" or (yellow and "PIKACHU" or "BULBASAUR"),
          level = 5,
          choseFlag = yellow and "EVENT_CHOSE_PIKACHU" or "EVENT_CHOSE_BULBASAUR",
          rivalStarter = 1,
        }
      end },
    { label = "+ Take item", kind = "ghost",
      tip = "Remove an item from the bag.",
      make = function()
        return { kind = "take_item", item = "POTION", count = 1 }
      end },
    { label = "+ Check item", kind = "ghost", gen1Only = true,
      tip = "Skip the rest if the player does not have this item.",
      make = function()
        return { kind = "check_item_missing", item = "POTION" }
      end },
    { label = "+ Clear flag", kind = "ghost",
      tip = "Clear a story flag (the opposite of Set flag).",
      make = function()
        if gen2 then return { kind = "clear_flag", flag = "0", event = 0 } end
        return { kind = "clear_flag", flag = "DONE" }
      end },
    { label = "+ Label", kind = "ghost", gen1Only = true,
      tip = "A named marker that Jump steps can go to.",
      make = function() return { kind = "label", name = "label" } end },
    { label = "+ Jump", kind = "ghost", gen1Only = true,
      tip = "Jump to a label (skip the steps in between).",
      make = function() return { kind = "jump", name = "end" } end },
    { label = "+ Money", kind = "ghost", gen1Only = true,
      tip = "Give the player money (¥500 by default).",
      make = function() return { kind = "give_money", amount = 500 } end },
    { label = "+ Image", kind = "accent", gen1Only = true,
      tip = "Show a framed picture (PNG). Browse to pick the file.",
      make = function()
        return { kind = "show_image", path = "assets/pic.png", text = "" }
      end },
    { label = "+ Trade", kind = "accent", gen1Only = true,
      tip = "An in-game trade. Set the trade slot and a done-flag so it happens once.",
      make = function()
        return { kind = "trade", index = 1, flag = "TRADED" }
      end },
  }
  local out = {}
  for _, sc in ipairs(list) do
    if not (gen2 and sc.gen1Only) and not ((not gen2) and sc.gen2Only) then
      out[#out + 1] = sc
    end
  end
  return out
end

-- How tall a wrapped shortcut strip needs to be (never clip buttons).
local function shortcutStripHeight(shortcuts, formW, s, extraFirstRowW)
  local bh, gap = 26 * s, 4 * s
  local maxX = formW - 12 * s
  local bx = 12 * s + (tonumber(extraFirstRowW) or 0)
  local rows = 1
  for _, sc in ipairs(shortcuts or {}) do
    local bw = Kit.textWidth("small", sc.label) + 16 * s
    if bx + bw > maxX then
      bx = 12 * s
      rows = rows + 1
    end
    bx = bx + bw + gap
  end
  return rows * (bh + gap) + 10 * s
end

-- Draw shortcut / recipe chips; sc.apply() or sc.make() → onAdd(step).
-- opts.firstRowSkip: leave room on row 1 for Copy/Paste drawn by the caller.
local function drawShortcutStrip(shortcuts, x, y, w, h, s, onAdd, opts)
  opts = opts or {}
  local bh, gap = 26 * s, 4 * s
  local firstSkip = tonumber(opts.firstRowSkip) or 0
  local bx, by = x + firstSkip, y
  local maxX = x + w
  local maxY = y + h
  Kit.pushClip(x - 4 * s, y - 2 * s, w + 8 * s, h + 4 * s)
  for _, sc in ipairs(shortcuts or {}) do
    local bw = Kit.textWidth("small", sc.label) + 16 * s
    if bx + bw > maxX then
      bx = x
      by = by + bh + gap
    end
    if by + bh > maxY then break end
    if Kit.button(bx, by, bw, bh, sc.label,
        { kind = sc.kind or "ghost", font = "small", tooltip = sc.tip }) then
      if sc.apply then
        sc.apply()
      elseif sc.make and onAdd then
        onAdd(sc.make())
      end
    end
    bx = bx + bw + gap
  end
  Kit.popClip()
end

local function stepLabel(kind, step)
  if kind == "opcode" then
    local cmd = type(step) == "table" and (step.cmd or step) or nil
    local op = cmd and (cmd.op or step.op)
    return OpcodeHelp.label(op)
  end
  for _, k in ipairs(STEP_KINDS) do
    if k.id == kind then return k.label end
  end
  return kind or "?"
end

local function cycleKind(S, kind)
  local allowed = {}
  for _, k in ipairs(STEP_KINDS) do
    if stepKindAllowed(S, k) then allowed[#allowed + 1] = k end
  end
  if #allowed == 0 then return kind end
  local idx = 1
  for i, k in ipairs(allowed) do
    if k.id == kind then idx = i; break end
  end
  return allowed[(idx % #allowed) + 1].id
end

local function parseKey(key)
  if not key then return nil, nil end
  return key:match("^([^/]+)/(.+)$")
end

-- Create an empty mod script (only for "+ Empty script").
local function ensureEmptyScript(S, key)
  State.ensureProjectFields(S.project)
  local mapId, textId = parseKey(key)
  if not mapId then return nil end
  local script = S.project.talkScripts[key]
  if not script then
    -- Default show_text to this pin's TEXT_* so Dialog bodies connect.
    script = {
      mapId = mapId,
      textId = textId,
      steps = { { kind = "show_text", text = textId or "Hello!" } },
    }
    S.project.talkScripts[key] = script
  end
  return script
end

-- Gold: clone map into project so we can attach a new scriptKey to an NPC.
local function ensureMapOwnedForTalk(S, mapId)
  if not mapId then return nil end
  State.ensureProjectFields(S.project)
  if S.project.maps[mapId] then return S.project.maps[mapId] end
  local base = S.data and S.data.maps and S.data.maps[mapId]
  if type(base) ~= "table" then return nil end
  local copy = {}
  for k, v in pairs(base) do copy[k] = v end
  copy.objects = {}
  for i, o in ipairs(base.objects or {}) do
    local oc = {}
    for k, v in pairs(o) do oc[k] = v end
    copy.objects[i] = oc
  end
  copy.bgEvents = {}
  for i, e in ipairs(base.bgEvents or {}) do
    local ec = {}
    for k, v in pairs(e) do ec[k] = v end
    copy.bgEvents[i] = ec
  end
  S.project.maps[mapId] = copy
  if S.data and S.data.maps then S.data.maps[mapId] = copy end
  return copy
end

local function tryAttachScriptKey(S, mapId, scriptKey)
  local map = ensureMapOwnedForTalk(S, mapId)
  if not map then return false end
  for _, obj in ipairs(map.objects or {}) do
    if type(obj.scriptKey) ~= "string" or obj.scriptKey == "" then
      obj.scriptKey = scriptKey
      return true, "object"
    end
  end
  for _, ev in ipairs(map.bgEvents or {}) do
    if type(ev.scriptKey) ~= "string" or ev.scriptKey == "" then
      ev.scriptKey = scriptKey
      return true, "bg"
    end
  end
  return false
end

local function openDialogForScript(S, mapId, scriptKey)
  S.tab = "dialog"
  S.dialogMapId = mapId
  S.dialogScriptKey = scriptKey
  local tid = Gen2Talk.textKeyForScript(S, scriptKey)
  if tid then S.dialogTextId = tid end
end

local function sourceColor(src)
  if src == "mod" then return PAL.green end
  if src == "script" or src == "lua" then return PAL.yellow end
  if src == "std" or src == "phone" or src == "deco" or src == "special" then
    return PAL.yellow
  end
  if src == "text" then return PAL.blue end
  if src == "item" or src == "trainer" or src == "pokemon" then return PAL.blue end
  return PAL.faint
end

-- Optional 9th arg `suggest`: id list or function() -> list for autocomplete.
local function field(App, id, x, y, w, h, value, ph, suggest)
  if acS and suggest then
    return RegList.suggestField(App, acS, id, x, y, w, h, value, ph, suggest)
  end
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

-- Fit an id into a row: ellipsize by font metrics, then hard-cut if still wide.
-- Collapse script newlines so LOVE never paints a second line under the bar.
local function fitIn(fontName, text, maxW)
  text = tostring(text or "")
    :gsub("\r\n", "\n"):gsub("[\n\r\f\v]", " / "):gsub(" +/ +", " / ")
  if maxW <= 0 then return "" end
  local shown = Kit.ellipsize(fontName, text, maxW)
  if Kit.textWidth(fontName, shown) > maxW + 0.5 then
    local unit = math.max(1, Kit.textWidth(fontName, "W"))
    local n = math.max(0, math.floor(maxW / unit) - 3)
    shown = (n > 0 and text:sub(1, n) or "") .. "..."
  end
  return shown
end

-- Gold SCRIPTS form: Says + face-player for simple talk; override for vanilla.
local function drawGen2ScriptForm(S, App, formX, listY, formW, listH, mapId, scriptKey)
  local s = Kit.scale
  local pad = 12 * s
  local cmds, ownedFlag = Gen2Talk.commands(S, scriptKey)
  local owned = ownedFlag == true
    or (S.project.scripts and type(S.project.scripts[scriptKey]) == "table")
  local simple = Gen2Talk.isSimpleTalk(cmds)
  -- Room for Override / templates / Dialog — not just a single button row.
  local footerH = owned and 72 * s or 40 * s
  local viewX = formX + pad
  local viewY = listY + pad + 36 * s
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH - 36 * s)

  Kit.text("micro", fitIn("micro", mapId .. "/" .. scriptKey, formW - 24 * s),
    formX + 12 * s, listY + 10 * s, PAL.faint)
  Kit.text("micro",
    owned
      and (simple
        and "Edit talk here — Save writes Gold scripts"
        or "Mod script (advanced ops) — edit text bodies below")
      or "Vanilla — Override in mod to edit talk",
    formX + 12 * s, listY + 22 * s, owned and PAL.green or PAL.yellow)

  FormPane.track(S, "eventFormScroll",
    S.eventScriptKey .. (owned and (simple and ":g2s" or ":g2a") or ":g2v"))
  local fy, view = FormPane.begin(S, "eventFormScroll", viewX, viewY, viewW, viewH)
  local contentTop = fy
  local fh = 28 * s
  local innerW = view.contentW or view.w

  if not owned then
    Kit.text("small", "Opcode preview (read-only)", viewX, fy, PAL.caption)
    fy = fy + 20 * s
    if type(cmds) == "table" and #cmds > 0 then
      for _, cmd in ipairs(cmds) do
        local note = tostring(cmd.op or "?")
        if cmd.text then note = note .. "  text=" .. tostring(cmd.text) end
        if cmd.script then note = note .. "  →" .. tostring(cmd.script) end
        Kit.text("micro", fitIn("micro", note, innerW), viewX, fy + 6 * s, PAL.muted)
        fy = fy + fh
      end
    else
      Kit.text("micro", "No script commands", viewX, fy, PAL.muted)
      fy = fy + fh
    end
  elseif simple then
    local face = Gen2Talk.facesPlayer(cmds)
    Kit.text("small", "Face player", viewX, fy + 6 * s, PAL.caption)
    if Kit.chip(viewX + 100 * s, fy, 80 * s, fh, face and "YES" or "NO",
        face, PAL.yellow) then
      Gen2Talk.setFacePlayer(S, scriptKey, not face)
      App.markDirty()
      S.status = "Face player " .. (not face and "on" or "off")
    end
    fy = fy + fh + 10 * s

    local textKey = Gen2Talk.textKeyForScript(S, scriptKey)
    if not textKey then
      _, textKey = Gen2Talk.ensureSimpleTalk(S, scriptKey, face)
      App.markDirty()
    end
    Kit.text("small", "Says", viewX, fy, PAL.caption)
    fy = fy + 16 * s
    local body = Gen2Talk.getSays(S, textKey)
    local display = body:gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\v", "\\v")
    local edited = field(App, "ev_g2_says", viewX, fy, innerW, 36 * s,
      display, "(what they say)")
    if edited then
      local decoded = edited:gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\\v")
      if decoded ~= body then
        Gen2Talk.setSays(S, textKey, decoded)
        App.markDirty()
      end
    end
    fy = fy + 44 * s
    Kit.text("micro",
      "Use \\n new line, \\f page break, \\v A-wait, {PLAYER} for name",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    Kit.text("micro", "text key: " .. tostring(textKey), viewX, fy, PAL.muted)
    fy = fy + 22 * s
  else
    Kit.text("small", "Advanced script", viewX, fy, PAL.caption)
    fy = fy + 18 * s
    Kit.text("micro",
      "Multi-op script — edit text bodies; opcode list is preview-only for now",
      viewX, fy, PAL.faint)
    fy = fy + 20 * s
    if type(cmds) == "table" then
      for _, cmd in ipairs(cmds) do
        local note = tostring(cmd.op or "?")
        if cmd.text then note = note .. "  text=" .. tostring(cmd.text) end
        Kit.text("micro", fitIn("micro", note, innerW), viewX, fy + 4 * s, PAL.muted)
        fy = fy + 22 * s
      end
    end
    fy = fy + 8 * s
    local keys = Gen2Talk.collectTextKeys(S, scriptKey)
    for ti, tid in ipairs(keys) do
      Kit.text("small", "Text " .. ti .. " · " .. tid, viewX, fy, PAL.caption)
      fy = fy + 16 * s
      local body = Gen2Talk.getSays(S, tid)
      local display = body:gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\\v", "\\v")
      local edited = field(App, "ev_g2_t" .. ti, viewX, fy, innerW, 32 * s,
        display, "...")
      if edited then
        local decoded = edited:gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\\v")
        if decoded ~= body then
          Gen2Talk.setSays(S, tid, decoded)
          App.markDirty()
        end
      end
      fy = fy + 40 * s
    end
    if #keys == 0 then
      Kit.text("micro", "No text keys in this script", viewX, fy, PAL.muted)
      fy = fy + fh
    end
  end

  FormPane.finish(S, "eventFormScroll", contentTop, fy, view)

  local by = listY + listH - footerH + 6 * s
  local bx = formX + 12 * s
  local bh = 28 * s
  if not owned then
    if Kit.button(bx, by, 180 * s, bh, "Override in mod",
        { kind = "good", font = "small",
          tooltip = "Clone opcodes into mod and open the step builder" }) then
      TalkIndex.cloneToProject(S, mapId, scriptKey)
      App.markDirty()
      S.status = "Overrode " .. scriptKey .. " — edit steps like Red"
    end
    bx = bx + 188 * s
  else
    if Kit.button(bx, by, 120 * s, bh, "Open steps", {
        kind = "good", font = "small",
        tooltip = "Decompile into the step builder",
      }) then
      Gen2Talk.ensureScriptSteps(S, scriptKey, mapId)
      Gen2Talk.commitSteps(S, scriptKey)
      App.markDirty()
      S.status = "Step builder ready for " .. scriptKey
    end
    bx = bx + 128 * s
  end
  if Kit.button(bx, by, 140 * s, bh, "Open in Dialog",
      { kind = "accent", font = "small" }) then
    openDialogForScript(S, mapId, scriptKey)
  end
end

-- Resolve TEXT_* / _FooText to a string-table id for project.text lookup.
local function resolveStringIdForText(S, value, mapId)
  if type(value) ~= "string" or value == "" then return nil end
  if value:find("[%s\\]") then return nil end
  if S.project and S.project.text and S.project.text[value] ~= nil then
    return value
  end
  if S.data and S.data.text and S.data.text[value] ~= nil then
    return value
  end
  if value:match("^TEXT_") then
    local mid = mapId or S.eventMapId or S.dialogMapId
    if mid then
      local label = State.mapLabel(S, mid)
      local function from(ptrs)
        local e = ptrs and label and ptrs[label] and ptrs[label][value]
        if type(e) == "table" and type(e.text) == "string" then return e.text end
      end
      return from(S.project and S.project.text_pointers)
        or from(S.data and S.data.text_pointers)
        or ("_" .. value:gsub("^TEXT_", ""))
    end
  end
  if value:match("^_[%w_]+") then return value end
  return nil
end

local function resolveTextBody(S, strId)
  if not strId then return "" end
  return Gen2Talk.getSays(S, strId)
end

local function encodeTextBody(body)
  return tostring(body or ""):gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\v", "\\v")
end

local function decodeTextBody(display)
  return tostring(display or "")
    :gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\\v"):gsub("\\/", "/")
end

-- Gold bank:addr keys (55:4e7c). Keep TEXT_* / mod:… visible.
local function looksLikeAddr(s)
  return type(s) == "string" and s:match("^%x+:%x+$") ~= nil
end

local WHEN_LABEL = {
  ["true"] = "If yes",
  ["false"] = "If no",
  always = "Always",
}

local function firstScriptLine(S, scriptKey)
  local bag = Gen2Talk.getScriptSteps(S, scriptKey)
  local mapId = (bag and bag.mapId)
    or S.eventMapId
    or select(1, parseKey(S.eventScriptKey))
  if bag and type(bag.steps) == "table" then
    for _, step in ipairs(bag.steps) do
      if type(step) == "table"
          and (step.kind == "show_text" or step.kind == "ask") then
        local strId = resolveStringIdForText(S, step.text, mapId)
        local body = strId and resolveTextBody(S, strId) or tostring(step.text or "")
        body = body:gsub("[\r\n\f\v]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if body ~= "" and body ~= "..." then
          return body
        end
      end
    end
  end
  local tid = Gen2Talk.textKeyForScript(S, scriptKey)
  if tid then
    local body = resolveTextBody(S, tid)
    body = body:gsub("[\r\n\f\v]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if body ~= "" and body ~= "..." then
      return body
    end
  end
  return nil
end

local function scriptDisplayName(S, scriptKey)
  if type(scriptKey) ~= "string" or scriptKey == "" then
    return "Pick a person or sign"
  end
  local mapId = S.eventMapId or select(1, parseKey(S.eventScriptKey))
  if mapId then
    for _, e in ipairs(TalkIndex.collect(S, mapId) or {}) do
      if e.scriptKey == scriptKey or e.textId == scriptKey then
        return e.label
      end
    end
  end
  if scriptKey:match("^mod:") then
    return scriptKey:gsub("^mod:", ""):gsub("_", " ")
  end
  local line = firstScriptLine(S, scriptKey)
  if line then return line end
  if looksLikeAddr(scriptKey) then
    return "Other lines"
  end
  return scriptKey
end

local function addJumpTargetsFrom(add, src)
  if type(src) ~= "table" then return end
  for _, item in ipairs(src) do
    if type(item) == "table" then
      if type(item.script) == "string" and item.script ~= "" then
        add(item.script)
      end
      if type(item.cmd) == "table" and type(item.cmd.script) == "string"
          and item.cmd.script ~= "" then
        add(item.cmd.script)
      end
    end
  end
end

local function collectScriptChoices(S, extraKey)
  local mapId = S.eventMapId or select(1, parseKey(S.eventScriptKey))
  local ids, labels, seen = {}, {}, {}
  local function add(id, label)
    if type(id) ~= "string" or id == "" or seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
    labels[id] = label or scriptDisplayName(S, id)
  end
  local curKey = select(2, parseKey(S.eventScriptKey))
  if mapId then
    for _, e in ipairs(TalkIndex.collect(S, mapId) or {}) do
      local id = e.scriptKey or e.textId
      local label = e.label
      if id == curKey and label then
        label = label .. " (this one)"
      end
      add(id, label)
    end
  end
  if curKey then
    add(curKey, scriptDisplayName(S, curKey) .. " (this one)")
  end
  local bag = curKey and Gen2Talk.getScriptSteps(S, curKey)
  if bag then addJumpTargetsFrom(add, bag.steps) end
  addJumpTargetsFrom(add, curKey and Gen2Talk.commands(S, curKey))
  if extraKey then add(extraKey) end
  return ids, labels
end

-- Edit show_text / ask: TEXT_* / _FooText edit project.text; literals decode \n.
local function drawDialogTextFields(S, App, step, i, fx, fw, fh, s, row)
  local y = row()
  local value = step.text or ""
  local mapId = S.eventMapId or select(1, parseKey(S.eventScriptKey))
  local strId = resolveStringIdForText(S, value, mapId)
  if strId then
    local body = resolveTextBody(S, strId)
    local display = encodeTextBody(body)
    local edited = field(App, "ev_tbody_" .. i, fx, y, fw, fh, display,
      "dialog text (\\n = line, \\f = page)")
    if edited ~= display then
      State.ensureProjectFields(S.project)
      S.project.text[strId] = decodeTextBody(edited)
      if value:match("^TEXT_") and mapId then
        local label = State.mapLabel(S, mapId)
        if label then
          S.project.text_pointers[label] = S.project.text_pointers[label] or {}
          local ptr = S.project.text_pointers[label][value]
          if type(ptr) ~= "table" then
            S.project.text_pointers[label][value] = { text = strId }
          elseif not ptr.text then
            ptr.text = strId
          end
        end
      end
    end
    -- Gold bank:addr text ids are engine plumbing; the body above is the edit.
    if not looksLikeAddr(value) then
      local yKey = row()
      Kit.text("micro", "key", fx, yKey + 8 * s, PAL.faint)
      step.text = field(App, "ev_t_" .. i, fx + 34 * s, yKey, fw - 34 * s, fh,
        value, "TEXT_* or _FooText")
    end
  else
    local display = encodeTextBody(value)
    local edited = field(App, "ev_t_" .. i, fx, y, fw, fh, display,
      "literal (\\n = line, \\f = page)")
    if edited ~= display then
      step.text = decodeTextBody(edited)
    end
  end
end

local function previewDialogText(S, value, maxW)
  local mapId = S.eventMapId or select(1, parseKey(S.eventScriptKey))
  local strId = resolveStringIdForText(S, value, mapId)
  if strId then
    local body = resolveTextBody(S, strId)
    if body ~= "" then
      return fitIn("micro", body, maxW)
    end
  end
  return fitIn("micro", value or "", maxW)
end

local function stepPreview(S, step, maxW)
  if type(step) ~= "table" then return "" end
  local kind = step.kind or "show_text"
  maxW = maxW or 240
  if kind == "raw" then
    return fitIn("micro", step.note or "", maxW)
  elseif kind == "show_image" then
    local line = tostring(step.path or step.image or "")
    if step.text and step.text ~= "" then
      line = line .. "  ·  " .. tostring(step.text)
    end
    return fitIn("micro", line, maxW)
  elseif kind == "show_text" or kind == "ask" then
    local body = previewDialogText(S, step.text, maxW)
    if body:sub(1, 1) ~= '"' and body ~= "" then
      return '"' .. body .. '"'
    end
    return body
  elseif kind == "label" or kind == "jump" or kind == "jump_if_yes"
      or kind == "jump_if_no" then
    return fitIn("micro", step.name or step.label or "", maxW)
  elseif kind == "jump_script" then
    local when = WHEN_LABEL[step.when or "true"] or tostring(step.when or "")
    local dest = scriptDisplayName(S, step.script)
    return fitIn("micro", when .. " → " .. dest, maxW)
  elseif kind == "opcode" then
    local cmd = type(step.cmd) == "table" and step.cmd or step
    local shown = OpcodeHelp.preview(cmd)
    if type(cmd.script) == "string" and cmd.script ~= "" then
      local name = scriptDisplayName(S, cmd.script)
      if shown == cmd.script or shown == "" then
        shown = name
      else
        shown = shown:gsub(cmd.script, name, 1)
      end
    end
    return fitIn("micro", shown, maxW)
  elseif kind == "set_flag" or kind == "clear_flag"
      or kind == "check_flag_skip" or kind == "check_flag_missing" then
    return tostring(step.flag or step.event or "")
  elseif kind == "give_item" or kind == "take_item"
      or kind == "check_item_skip" or kind == "check_item_missing" then
    return tostring(step.item or "") .. " x" .. tostring(step.count or 1)
  elseif kind == "oneshot_gift" then
    return tostring(step.item or "") .. " x" .. tostring(step.count or 1)
  elseif kind == "give_pokemon" or kind == "give_starter"
      or kind == "oneshot_pokemon" or kind == "wild_battle" then
    return tostring(step.species or "") .. " Lv" .. tostring(step.level or 5)
  elseif kind == "give_money" then
    return tostring(step.amount or 0)
  elseif kind == "warp" then
    return fitIn("micro", string.format("%s (%s,%s)",
      tostring(step.map or ""), tostring(step.x or 0), tostring(step.y or 0)),
      maxW)
  elseif kind == "trainer_battle" or kind == "oneshot_trainer" then
    if step.class then
      return "class " .. tostring(step.class) .. " / " .. tostring(step.member or 1)
    end
    return tostring(step.trainer or "") .. " #" .. tostring(step.party or 1)
  elseif kind == "set_field" then
    return fitIn("micro",
      tostring(step.field or "") .. " = " .. tostring(step.value or ""), maxW)
  elseif kind == "trade" then
    return "#" .. tostring(step.index or 1)
  end
  return ""
end

local function drawStepFields(S, App, step, i, kind, fx, fy, fw, fh, s)
  local used = 0
  local function row()
    used = used + 1
    return fy + (used - 1) * (fh + 4 * s)
  end

  if kind == "show_text" or kind == "ask" then
    drawDialogTextFields(S, App, step, i, fx, fw, fh, s, row)
    if kind == "show_text" and Generation.isGen2(S) then
      local y2 = row()
      local face = step.facePlayer ~= false
      if Kit.chip(fx, y2, 100 * s, fh, face and "Face YES" or "Face NO",
          face, PAL.yellow) then
        step.facePlayer = not face
        step.jumptext = true
        App.markDirty()
      end
      local jt = step.jumptext == true
      if Kit.chip(fx + 110 * s, y2, 120 * s, fh,
          jt and "jumptext" or "writetext", jt, PAL.blue) then
        step.jumptext = not jt
        App.markDirty()
      end
    end
    if kind == "ask" then
      local y2 = row()
      local on = step.skipOnNo ~= false
      if Kit.chip(fx, y2, 160 * s, fh, on and "Skip on NO" or "Keep on NO",
          on, PAL.yellow) then
        -- Do not use `on and false or true` — Lua treats false as failure
        -- and the expression always collapses to true.
        step.skipOnNo = not on
        App.markDirty()
      end
    end
  elseif kind == "opcode" then
    local cmd = type(step.cmd) == "table" and step.cmd or {}
    step.cmd = cmd
    local op = tostring(cmd.op or step.op or "end")
    cmd.op = op
    step.op = op
    local y = row()
    ChoicePicker.field(S, {
      x = fx, y = y, w = fw, h = fh,
      current = op,
      ids = OpcodeHelp.ops(),
      labels = OpcodeHelp.labels(),
      title = "COMMAND",
      tooltip = "What this command does",
      onPick = function(id)
        step.cmd = { op = id or "end" }
        step.op = step.cmd.op
        App.markDirty()
      end,
    })
    local fields = OpcodeHelp.fields(op, cmd)
    for fi, spec in ipairs(fields) do
      local fy = row()
      local cap = spec.caption or spec.key
      local capW = math.min(110 * s, fw * 0.38)
      Kit.text("micro", cap, fx, fy + 8 * s, PAL.faint)
      if spec.kind == "script" then
        local ids, labels = collectScriptChoices(S, cmd.script)
        ChoicePicker.field(S, {
          x = fx + capW, y = fy, w = fw - capW, h = fh,
          current = type(cmd.script) == "string" and cmd.script or "",
          ids = ids,
          labels = labels,
          emptyLabel = "Pick a talk",
          title = "WHICH TALK",
          tooltip = "Which lines to run",
          onPick = function(id)
            cmd.script = type(id) == "string" and id or nil
            App.markDirty()
          end,
        })
      elseif spec.kind == "pokemon" or spec.key == "species" then
        local raw = cmd[spec.key]
        local shown = raw
        if type(raw) == "number" then
          shown = SpeciesPicker.idForIndex(S, raw) or tostring(raw)
        end
        SpeciesPicker.field(S, {
          x = fx + capW, y = fy, w = fw - capW, h = fh,
          current = type(shown) == "string" and shown or "",
          emptyLabel = (spec.ph and spec.ph ~= "" and spec.ph) or "(pokemon)",
          title = "POKEMON",
          tooltip = "Pick a species from the list",
          onPick = function(pickId)
            if Generation.isGen2(S) then
              cmd[spec.key] = SpeciesPicker.indexForId(S, pickId) or pickId
            else
              cmd[spec.key] = pickId
            end
            App.markDirty()
          end,
        })
      elseif spec.kind == "item" or spec.key == "item" then
        local raw = cmd[spec.key]
        local shown = raw
        if type(raw) == "number" then
          shown = ItemPicker.idForIndex(S, raw) or tostring(raw)
        end
        ItemPicker.field(S, {
          x = fx + capW, y = fy, w = fw - capW, h = fh,
          current = type(shown) == "string" and shown or "",
          emptyLabel = (spec.ph and spec.ph ~= "" and spec.ph) or "(item)",
          title = "ITEM",
          tooltip = "Pick an item. Gold scripts need the item's index, not the name.",
          onPick = function(pickId)
            if Generation.isGen2(S) then
              cmd[spec.key] = ItemPicker.indexForId(S, pickId) or pickId
            else
              cmd[spec.key] = pickId
            end
            App.markDirty()
          end,
        })
      elseif spec.kind == "song" or spec.key == "music" then
        ChoicePicker.songField(S, {
          x = fx + capW, y = fy, w = fw - capW, h = fh,
          current = type(cmd[spec.key]) == "string" and cmd[spec.key] or "",
          emptyLabel = (spec.ph and spec.ph ~= "" and spec.ph) or "(music)",
          allowClear = true,
          onPick = function(pickId)
            cmd[spec.key] = (type(pickId) == "string" and pickId ~= "") and pickId or nil
            App.markDirty()
          end,
        })
      else
        local raw = field(App, "ev_opc_" .. spec.key .. "_" .. i .. "_" .. fi,
          fx + capW, fy, fw - capW, fh,
          cmd[spec.key] ~= nil and tostring(cmd[spec.key]) or "",
          spec.ph or spec.key)
        if spec.numeric then
          local n = tonumber(raw)
          cmd[spec.key] = n or (raw ~= "" and raw or nil)
        elseif raw ~= "" then
          cmd[spec.key] = raw
        else
          cmd[spec.key] = nil
        end
      end
    end
    local hint = OpcodeHelp.hint(op)
    if hint then
      local hy = row()
      Kit.text("micro", hint, fx, hy + 6 * s, PAL.muted)
    end
  elseif kind == "jump_script" then
    local y = row()
    local ids, labels = collectScriptChoices(S, step.script)
    local when = step.when or "true"
    local whenW = 90 * s
    ChoicePicker.field(S, {
      x = fx, y = y, w = fw - whenW - 8 * s, h = fh,
      current = step.script or "",
      ids = ids,
      labels = labels,
      emptyLabel = "Pick a person or sign",
      title = "GO TO",
      tooltip = "Who to talk to next",
      onPick = function(id)
        step.script = type(id) == "string" and id or ""
        App.markDirty()
      end,
    })
    local whenLabel = WHEN_LABEL[when] or when
    if Kit.chip(fx + fw - whenW, y, whenW, fh, whenLabel, true, PAL.yellow) then
      step.when = (when == "true" and "false")
        or (when == "false" and "always")
        or "true"
      step.op = step.when == "false" and "iffalse"
        or step.when == "always" and "sjump"
        or "iftrue"
      App.markDirty()
    end
  elseif kind == "show_image" then
    local y = row()
    local browseW = 90 * s
    local pathW = math.max(80 * s, fw - browseW - 6 * s)
    step.path = field(App, "ev_img_" .. i, fx, y, pathW, fh,
      step.path or step.image or "", "assets/pic.png")
    if Kit.button(fx + pathW + 6 * s, y, browseW, fh, "Browse",
        { kind = "ghost", font = "small",
          tooltip = "Import a PNG into the mod and use it here" }) then
      App.pickFile("Image PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          if not picked or picked == "" then return end
          App.importToMod(picked, nil, function(rel)
            step.path = rel
            App.markDirty()
            S.status = "Image set to " .. tostring(rel)
          end)
        end)
    end
    local y2 = row()
    step.text = field(App, "ev_imgt_" .. i, fx, y2, fw, fh,
      step.text or "", "optional caption after close")
  elseif kind == "set_flag" or kind == "clear_flag"
      or kind == "check_flag_skip" or kind == "check_flag_missing" then
    local y = row()
    if Generation.isGen2(S) then
      local ev = tonumber(step.event) or tonumber(step.flag) or 0
      ev = tonumber(field(App, "ev_f_" .. i, fx, y, 80 * s, fh,
        tostring(ev), "0")) or 0
      step.event = ev
      step.flag = tostring(ev)
      Kit.text("micro", "event #", fx + 90 * s, y + 8 * s, PAL.faint)
      if kind == "check_flag_skip" or kind == "check_flag_missing" then
        local y2 = row()
        step.script = field(App, "ev_fs_" .. i, fx, y2, fw, fh,
          step.script or "", "target script")
      end
    else
      step.flag = field(App, "ev_f_" .. i, fx, y, 160 * s, fh,
        step.flag or "STARTED", "short name or EVENT_*",
        function() return Autocomplete.flagIds(S) end)
      -- Do not write eventFlags here: each keystroke would tombstone partials
      -- (M, MA, MAP…). Save / flag tester rebuild from finished step.flag.
      local full = State.modFlag(S.project, step.flag)
      Kit.text("micro", "→ " .. full, fx + 170 * s, y + 8 * s, PAL.faint)
    end
  elseif kind == "give_item" or kind == "take_item"
      or kind == "check_item_skip" or kind == "check_item_missing" then
    local y = row()
    local shown = step.item or "POTION"
    if type(shown) == "number" then
      shown = ItemPicker.idForIndex(S, shown) or tostring(shown)
    end
    ItemPicker.field(S, {
      x = fx, y = y, w = 140 * s, h = fh,
      current = tostring(shown),
      title = "ITEM",
      tooltip = "Pick an item from the list",
      onPick = function(id)
        step.item = id or "POTION"
        App.markDirty()
      end,
    })
    if kind == "give_item" or kind == "take_item" then
      step.count = tonumber(field(App, "ev_c_" .. i, fx + 150 * s, y, 50 * s, fh,
        tostring(step.count or 1), "1")) or 1
    end
  elseif kind == "give_pokemon" or kind == "give_starter"
      or kind == "oneshot_pokemon" or kind == "wild_battle" then
    local y = row()
    local defSp = kind == "wild_battle" and "PIDGEY"
      or (kind == "give_starter"
        and (Generation.isGen2(S) and "CYNDAQUIL"
          or (Generation.id(S) == "yellow" and "PIKACHU" or "BULBASAUR"))
        or "PIKACHU")
    SpeciesPicker.field(S, {
      x = fx, y = y, w = 140 * s, h = fh,
      current = step.species or defSp,
      title = kind == "give_starter" and "STARTER SPECIES"
        or "SPECIES",
      onPick = function(id)
        step.species = id
        App.markDirty()
      end,
    })
    step.level = tonumber(field(App, "ev_lv_" .. i, fx + 150 * s, y, 50 * s, fh,
      tostring(step.level or 5), "5")) or 5
    if kind == "wild_battle" and Generation.isGen2(S) then
      local y2 = row()
      local shiny = step.forceShiny and true or false
      if Kit.chip(fx, y2, 120 * s, fh, shiny and "Force shiny" or "Normal DVs",
          shiny, PAL.yellow) then
        step.forceShiny = (not shiny) or nil
        App.markDirty()
      end
    elseif kind ~= "wild_battle" then
      local y2 = row()
      local nick = step.skipNickname and true or false
      if Kit.chip(fx, y2, 140 * s, fh, nick and "No nickname" or "Ask nickname",
          nick, PAL.blue) then
        step.skipNickname = (not nick) or nil
        App.markDirty()
      end
    end
    if kind == "give_starter" then
      local y3 = row()
      step.choseFlag = field(App, "ev_cf_" .. i, fx, y3, 160 * s, fh,
        step.choseFlag or (Generation.id(S) == "yellow"
          and "EVENT_CHOSE_PIKACHU" or "EVENT_CHOSE_BULBASAUR"), "EVENT_CHOSE_*",
        function() return Autocomplete.flagIds(S) end)
      step.rivalStarter = tonumber(field(App, "ev_rs_" .. i,
        fx + 170 * s, y3, 40 * s, fh,
        tostring(step.rivalStarter or 1), "1")) or 1
      Kit.text("micro", "rival 1-3", fx + 220 * s, y3 + 8 * s, PAL.faint)
    end
    if kind == "oneshot_pokemon" then
      local y3 = row()
      step.text = field(App, "ev_ot_" .. i, fx, y3, fw, fh,
        step.text or "Here! Take this POKeMON!", "intro")
      local y4 = row()
      step.after = field(App, "ev_oa_" .. i, fx, y4, fw - 140 * s, fh,
        step.after or "I already gave you one.", "after")
      step.flag = field(App, "ev_of_" .. i, fx + fw - 130 * s, y4, 120 * s, fh,
        step.flag or "GOT_MON", "GOT_MON",
        function() return Autocomplete.flagIds(S) end)
    end
  elseif kind == "oneshot_gift" then
    local y = row()
    step.text = field(App, "ev_gt_" .. i, fx, y, fw, fh,
      step.text or "Here, take this!", "intro")
    local y2 = row()
    do
      local shown = step.item or "POTION"
      if type(shown) == "number" then
        shown = ItemPicker.idForIndex(S, shown) or tostring(shown)
      end
      ItemPicker.field(S, {
        x = fx, y = y2, w = 120 * s, h = fh,
        current = tostring(shown),
        title = "ITEM",
        onPick = function(id)
          step.item = id or "POTION"
          App.markDirty()
        end,
      })
    end
    step.count = tonumber(field(App, "ev_gc_" .. i, fx + 130 * s, y2, 40 * s, fh,
      tostring(step.count or 1), "1")) or 1
    step.flag = field(App, "ev_gf_" .. i, fx + 180 * s, y2, 100 * s, fh,
      step.flag or "DONE", "DONE",
      function() return Autocomplete.flagIds(S) end)
    local y3 = row()
    step.after = field(App, "ev_ga_" .. i, fx, y3, fw, fh,
      step.after or "I already gave you one.", "after text")
  elseif kind == "give_money" then
    local y = row()
    step.amount = tonumber(field(App, "ev_m_" .. i, fx, y, 100 * s, fh,
      tostring(step.amount or 500), "500")) or 500
  elseif kind == "warp" then
    local y = row()
    step.map = field(App, "ev_wm_" .. i, fx, y, 140 * s, fh,
      step.map or "PALLET_TOWN", "MAP",
      function() return Autocomplete.mapIds(S) end):upper():gsub("%s+", "_")
    step.x = tonumber(field(App, "ev_wx_" .. i, fx + 150 * s, y, 40 * s, fh,
      tostring(step.x or 0), "0")) or 0
    step.y = tonumber(field(App, "ev_wy_" .. i, fx + 200 * s, y, 40 * s, fh,
      tostring(step.y or 0), "0")) or 0
    step.facing = field(App, "ev_wf_" .. i, fx + 250 * s, y, 70 * s, fh,
      step.facing or "down", "down")
  elseif kind == "trainer_battle" or kind == "oneshot_trainer" then
    local y = row()
    if Generation.isGen2(S) and kind == "trainer_battle" then
      step.class = tonumber(field(App, "ev_tr_" .. i, fx, y, 70 * s, fh,
        tostring(step.class or 1), "1")) or 1
      step.member = tonumber(field(App, "ev_tp_" .. i, fx + 80 * s, y, 50 * s, fh,
        tostring(step.member or step.party or 1), "1")) or 1
      step.party = step.member
      Kit.text("micro", "class / member", fx + 140 * s, y + 8 * s, PAL.faint)
    else
      step.trainer = field(App, "ev_tr_" .. i, fx, y, 160 * s, fh,
        step.trainer or "OPP_BUG_CATCHER", "OPP_*",
        function() return Autocomplete.trainerIds(S) end):upper():gsub("%s+", "_")
      step.party = tonumber(field(App, "ev_tp_" .. i, fx + 170 * s, y, 40 * s, fh,
        tostring(step.party or 1), "1")) or 1
    end
    if kind == "oneshot_trainer" then
      local y2 = row()
      step.text = field(App, "ev_tb_" .. i, fx, y2, fw, fh,
        step.text or "Let's fight!", "before battle")
      local y3 = row()
      step.won = field(App, "ev_tw_" .. i, fx, y3, fw - 140 * s, fh,
        step.won or "I lost...", "on win")
      step.flag = field(App, "ev_tf_" .. i, fx + fw - 130 * s, y3, 120 * s, fh,
        step.flag or "BEAT_TRAINER", "BEAT_*",
        function() return Autocomplete.flagIds(S) end)
      local y4 = row()
      step.after = field(App, "ev_ta_" .. i, fx, y4, fw, fh,
        step.after or "You're strong.", "after defeated")
    end
  elseif kind == "set_field" then
    local y = row()
    step.field = field(App, "ev_sf_" .. i, fx, y, 140 * s, fh,
      step.field or "mod:value", "mod:key or rivalStarter")
    step.value = field(App, "ev_sv_" .. i, fx + 150 * s, y, 100 * s, fh,
      tostring(step.value or ""), "value")
    if Kit.button(fx + 260 * s, y, 70 * s, fh,
        step.valueType or "str", { kind = "ghost" }) then
      local order = { "str", "number", "bool" }
      local idx = 1
      for oi, o in ipairs(order) do
        if o == (step.valueType or "str") then idx = oi; break end
      end
      step.valueType = order[(idx % #order) + 1]
      App.markDirty()
    end
  elseif kind == "trade" then
    local y = row()
    step.index = tonumber(field(App, "ev_trd_" .. i, fx, y, 50 * s, fh,
      tostring(step.index or 1), "1")) or 1
    Kit.text("micro", "trade #", fx + 56 * s, y + 8 * s, PAL.faint)
    step.flag = field(App, "ev_trdf_" .. i, fx + 110 * s, y, 140 * s, fh,
      step.flag or "TRADED", "TRADED",
      function() return Autocomplete.flagIds(S) end)
    local full = State.modFlag(S.project, step.flag)
    Kit.text("micro", full, fx + 260 * s, y + 8 * s, PAL.faint)
  elseif kind == "raw" then
    local y = row()
    if not step.note or step.note == "" then
      if type(step.row) == "table" then
        step.note = ModWriter.formatEngineLine(step.row)
      else
        step.note = "check_flag EVENT_FLAG"
      end
    end
    local prev = step.note
    step.note = field(App, "ev_raw_" .. i, fx, y, fw, fh,
      step.note, "verb arg1 arg2 …")
    if step.note ~= prev then
      step.row = ModWriter.parseEngineLine(step.note)
    end
    -- Mirror Set/Clear flag: short flag names in Engine cmd get MOD_<mod>_…
    local parsed = ModWriter.parseEngineLine(step.note)
    local verb = parsed and parsed[1]
    if (verb == "set_flag" or verb == "clear_flag" or verb == "check_flag")
        and type(parsed[2]) == "string" then
      local full = State.modFlag(S.project, parsed[2])
      if full ~= parsed[2] then
        local y2 = row()
        Kit.text("micro", "→ emits " .. verb .. " " .. full,
          fx, y2 + 8 * s, PAL.faint)
      end
    end
  elseif kind == "label" then
    local y = row()
    step.name = field(App, "ev_lbl_" .. i, fx, y, fw, fh,
      step.name or step.label or "", "label_name")
  elseif kind == "jump" or kind == "jump_if_yes" or kind == "jump_if_no" then
    local y = row()
    step.name = field(App, "ev_jmp_" .. i, fx, y, fw, fh,
      step.name or step.label or "", "target_label")
  elseif kind == "face_player" or kind == "heal_party" then
    Kit.text("micro", "(no params)", fx, row() + 8 * s, PAL.faint)
  end

  return used
end

local function swapSteps(steps, i, j)
  if type(steps) ~= "table" then return false end
  if i < 1 or j < 1 or i > #steps or j > #steps or i == j then return false end
  steps[i], steps[j] = steps[j], steps[i]
  return true
end

local function moveStep(steps, from, to)
  if type(steps) ~= "table" then return false end
  if from < 1 or from > #steps or to < 1 or to > #steps or from == to then
    return false
  end
  local item = table.remove(steps, from)
  table.insert(steps, to, item)
  return true
end

local function beginStepListReorder(S, listKey)
  if S._stepDrag and S._stepDrag.listKey ~= listKey and not Kit.mouseDown then
    S._stepDrag = nil
  end
  S._stepRowBounds = {}
  -- Block field clicks for the rest of this frame while a drag is active.
  if S._stepDrag and S._stepDrag.listKey == listKey and Kit.mouseDown then
    Kit.blockClicks = true
  end
end

local function finishStepListReorder(S, steps, listKey, App)
  local drag = S._stepDrag
  if not drag or drag.listKey ~= listKey then return end
  if Kit.mouseDown then
    Kit.blockClicks = true
    local my = Kit.mouseY
    local bounds = S._stepRowBounds or {}
    local over = drag.from
    if #bounds > 0 then
      if my < bounds[1].y then
        over = bounds[1].i
      elseif my >= bounds[#bounds].y + bounds[#bounds].h then
        over = bounds[#bounds].i
      else
        for _, r in ipairs(bounds) do
          if my >= r.y and my < r.y + r.h then
            over = r.i
            break
          end
        end
      end
    end
    drag.over = over
  else
    if drag.over and drag.from and drag.over ~= drag.from then
      if moveStep(steps, drag.from, drag.over) then
        App.markDirty()
      end
    end
    S._stepDrag = nil
  end
end

-- Editable step row: [≡] [Kind] fields… [↑] [↓] [X]
-- Returns the next fy after this block.
local function drawEditableStep(S, App, steps, i, listKey, viewX, fy, innerW, kindW, fh, s)
  local step = steps[i]
  if not step then return fy end
  local kind = step.kind or "show_text"
  local handleW = 26 * s
  local btnW = 26 * s
  local gap = 2 * s
  local rightChrome = btnW * 3 + gap * 2
  local leftChrome = handleW + 4 * s
  local kindX = viewX + leftChrome
  local fieldX = kindX + kindW + 8 * s
  local fieldW = math.max(40 * s,
    innerW - leftChrome - kindW - 8 * s - rightChrome - 4 * s)
  local xBtn = viewX + innerW - btnW
  local downBtn = xBtn - btnW - gap
  local upBtn = downBtn - btnW - gap

  local drag = S._stepDrag
  local isFrom = drag and drag.listKey == listKey and drag.from == i
  local isOver = drag and drag.listKey == listKey and drag.over == i
    and drag.from ~= i

  -- Start drag from the handle only (click frame).
  if not drag and Kit.mouseClicked and not Kit.blockClicks
      and Kit.hit(viewX, fy, handleW, fh) then
    S._stepDrag = { listKey = listKey, from = i, over = i }
    drag = S._stepDrag
    isFrom = true
  end

  if Kit.button(viewX, fy, handleW, fh, "=", {
      kind = isFrom and "accent" or "ghost", font = "small",
      tooltip = "Drag to reorder",
    }) then
    -- Visual only; drag starts via mouseClicked on the handle hit rect.
  end

  if Kit.button(kindX, fy, kindW, fh, stepLabel(kind, step),
      { kind = "accent", font = "small",
        tooltip = kind == "raw"
          and "Engine cmd — edit the line, or click to change step type"
          or "Click to change step type" }) then
    local nextKind = cycleKind(S, kind)
    step.kind = nextKind
    if nextKind == "raw" and (not step.note or step.note == "") then
      step.note = "check_flag EVENT_FLAG"
      step.row = { "check_flag", "EVENT_FLAG" }
    elseif nextKind == "opcode" and type(step.cmd) ~= "table" then
      step.cmd = { op = "end" }
      step.op = "end"
    elseif nextKind == "jump_script" and not step.script then
      step.script = ""
      step.when = "true"
      step.op = "iftrue"
    end
    App.markDirty()
  end

  local rowsN = drawStepFields(S, App, step, i, step.kind or kind,
    fieldX, fy, fieldW, fh, s)
  local blockH = math.max(1, rowsN) * (fh + 4 * s)
  local rowH = blockH + 8 * s

  S._stepRowBounds[#S._stepRowBounds + 1] = { i = i, y = fy, h = rowH }

  if isFrom or isOver then
    Theme.col(PAL.blue, isOver and 0.35 or 0.18)
    love.graphics.rectangle("line", viewX, fy, innerW, blockH, 4 * s, 4 * s)
  end

  if i > 1 and Kit.button(upBtn, fy, btnW, fh, "^", {
      kind = "ghost", font = "small", tooltip = "Move step up",
    }) then
    if swapSteps(steps, i, i - 1) then
      S._stepDrag = nil
      App.markDirty()
    end
  end
  if i < #steps and Kit.button(downBtn, fy, btnW, fh, "v", {
      kind = "ghost", font = "small", tooltip = "Move step down",
    }) then
    if swapSteps(steps, i, i + 1) then
      S._stepDrag = nil
      App.markDirty()
    end
  end
  if Kit.button(xBtn, fy, btnW, fh, "X", {
      kind = "danger", font = "small",
    }) then
    table.remove(steps, i)
    S._stepDrag = nil
    App.markDirty()
  end

  return fy + rowH
end

local function revealPath(path)
  if type(path) ~= "string" or path == "" then return false end
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  if osName == "Windows" then
    local win = path:gsub("/", "\\")
    os.execute('explorer /select,"' .. win:gsub('"', "") .. '"')
    return true
  end
  if osName == "OS X" then
    os.execute('open -R "' .. path:gsub('"', "") .. '"')
    return true
  end
  if osName == "Linux" then
    local dir = path:match("^(.*)[/\\]") or path
    os.execute('xdg-open "' .. dir:gsub('"', "") .. '"')
    return true
  end
  return false
end

local function fullRepoPath(rel)
  local sep = package.config:sub(1, 1)
  local root = ModIO.repoRoot()
  rel = tostring(rel or ""):gsub("\\", "/")
  if root:sub(-1) == "/" or root:sub(-1) == "\\" then
    return root .. rel:gsub("/", sep)
  end
  return root .. sep .. rel:gsub("/", sep)
end

-- Events → Advanced: resolve chain + open source for the selected TEXT_*.
local function drawAdvancedTalk(S, App, x, y, w, h, mapId, textId)
  local s = Kit.scale
  local inspect = TalkIndex.inspectTalk(S, mapId, textId)
  local layers = inspect.layers or {}
  local sel = S.eventAdvLayer or 1
  if sel < 1 then sel = 1 end
  if sel > #layers then sel = #layers end
  S.eventAdvLayer = sel

  Theme.col(PAL.rowBg, 0.55)
  love.graphics.rectangle("fill", x, y, w, h, 8 * s, 8 * s)
  Kit.text("micro", "ADVANCED — resolve chain / source",
    x + 8 * s, y + 4 * s, PAL.caption)

  local listY = y + 18 * s
  local listH = math.max(28 * s, math.floor(h * 0.38))
  local rowH = 20 * s
  local per = math.max(1, math.floor(listH / rowH))
  S.eventAdvOffset = Kit.scroll(x + 4 * s, listY, w - 8 * s, listH,
    S.eventAdvOffset or 0, #layers, per)
  for i = 1, per do
    local li = (S.eventAdvOffset or 0) + i
    local layer = layers[li]
    if not layer then break end
    local ry = listY + (i - 1) * rowH
    local on = li == sel
    if Kit.press(x + 6 * s, ry, w - 12 * s, rowH) then
      S.eventAdvLayer = li
      sel = li
    end
    if on then
      Theme.col(PAL.yellow, 0.14)
      love.graphics.rectangle("fill", x + 6 * s, ry, w - 12 * s, rowH)
    end
    local mark = (li == 1) and "▶ " or "  "
    Kit.text("micro",
      fitIn("micro", mark .. layer.title
        .. (layer.detail and (" — " .. layer.detail) or ""), w - 20 * s),
      x + 10 * s, ry + 3 * s, on and PAL.heading or PAL.muted)
  end

  local layer = layers[sel] or layers[1]
  local prevY = listY + listH + 4 * s
  local btnH = 24 * s
  local btnY = y + h - btnH - 6 * s
  local prevH = math.max(24 * s, btnY - prevY - 4 * s)
  Kit.pushClip(x + 8 * s, prevY, w - 16 * s, prevH)
  local py = prevY
  for _, line in ipairs((layer and layer.preview) or { "(no preview)" }) do
    Kit.text("micro", fitIn("micro", tostring(line), w - 24 * s),
      x + 10 * s, py, PAL.text)
    py = py + 14 * s
    if py > prevY + prevH then break end
  end
  Kit.popClip()

  local bx = x + 8 * s
  if layer and layer.open
      and Kit.button(bx, btnY, 110 * s, btnH, "Open source", {
        kind = "accent", font = "small",
        tooltip = "Open in Code tab (engine files are read-only)",
      }) then
    if Code.openTarget(S, layer.open) then
      S.status = "Opened source for " .. tostring(layer.title)
    end
  end
  bx = bx + 116 * s
  if layer and layer.open and layer.open.kind == "repo"
      and Kit.button(bx, btnY, 90 * s, btnH, "Copy path", {
        kind = "ghost", font = "small",
      }) then
    local full = fullRepoPath(layer.open.rel)
    if love and love.system and love.system.setClipboardText then
      love.system.setClipboardText(full)
    end
    S.status = "Copied " .. full
  end
  bx = bx + 96 * s
  if layer and layer.open and layer.open.kind == "repo"
      and Kit.button(bx, btnY, 80 * s, btnH, "Reveal", {
        kind = "ghost", font = "small",
      }) then
    local full = fullRepoPath(layer.open.rel)
    if revealPath(full) then
      S.status = "Revealed " .. tostring(layer.open.rel)
    else
      S.status = full
    end
  end
  bx = bx + 86 * s
  local hits = inspect.hits or {}
  if #hits > 1 and Kit.button(bx, btnY, 100 * s, btnH,
      string.format("+%d hits", #hits - 1), {
        kind = "ghost", font = "small",
        tooltip = "Open next script file hit for this TEXT_*/map",
      }) then
    S.eventAdvHit = ((S.eventAdvHit or 1) % #hits) + 1
    local hit = hits[S.eventAdvHit]
    Code.openTarget(S, {
      kind = "repo", rel = hit.path, line = hit.line, query = textId,
    })
  end
end

local function drawScripts(S, x, y, w, h, App)
  local s = Kit.scale
  TalkIndex.ensureScripts()
  State.ensureProjectFields(S.project)

  local mapColW = math.min(160 * s, w * 0.18)
  local listW = math.min(260 * s, w * 0.32)
  local qh = 28 * s
  local qy = y + 22 * s
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y)

  -- Map picker (same idea as Dialog): every object on the map is listed.
  Kit.caption(x, y, "MAP")
  local mapQ, mapQCh = Search.field(S, "eventMapQuery", x, qy, mapColW, qh, "maps...")
  if mapQCh then S.eventMapOffset = 0 end
  Kit.card(x, listY, mapColW, listH, 12 * s)
  local maps = Search.filterIds(TalkIndex.allMapIds(S), mapQ)
  if not S.eventMapId then
    S.eventMapId = S.dialogMapId or S.mapId or maps[1]
  end
  local mapRowH = 26 * s
  local perMap = math.max(1, math.floor((listH - 16 * s) / (mapRowH + 2 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = mapColW - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.eventMapOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.eventMapOffset or 0, #maps, perMap)
  local mapNav = RegList.bindNav(S, maps, {
    selKey = "eventMapId", offsetKey = "eventMapOffset", perPage = perMap,
    onSelect = function()
      S.eventScriptKey = nil
      S.eventScriptOffset = 0
    end,
  })
  local ry = listY + 8 * s
  for i = (S.eventMapOffset or 0) + 1,
      math.min(#maps, (S.eventMapOffset or 0) + perMap) do
    local id = maps[i]
    if Kit.row(mapScrollX, ry, mapRowW, mapRowH, S.eventMapId == id, PAL.blue) then
      mapNav.activate()
      S.eventMapId = id
      S.eventScriptKey = nil
      S.eventScriptOffset = 0
    end
    Kit.pushClip(mapScrollX, ry, mapRowW, mapRowH)
    Kit.text("micro", fitIn("micro",
        TalkIndex.catalogLabel(id) or id, math.max(8, mapRowW - 12 * s)),
      mapScrollX + 6 * s, ry + 6 * s, PAL.text)
    Kit.popClip()
    ry = ry + mapRowH + 2 * s
  end
  S.eventMapOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.eventMapOffset or 0, #maps, perMap)

  -- Object / TEXT_* events for the map (or a script catalog on Gold).
  local pinX = x + mapColW + 10 * s
  Kit.caption(pinX, y, TalkIndex.catalogPinCaption(S.eventMapId))
  local q, qChanged = Search.field(S, "eventScriptQuery", pinX, qy, listW, qh,
    "search events...")
  if qChanged then S.eventScriptOffset = 0 end
  Kit.card(pinX, listY, listW, listH, 12 * s)

  local entries = TalkIndex.collect(S, S.eventMapId)
  entries = Search.filterItems(entries, q, function(e)
    return table.concat({
      e.textId or "", e.label or "", e.source or "", e.key or "",
    }, " ")
  end)

  local rowH = 34 * s
  local footerBtns = 70 * s
  local perPage = math.max(1, math.floor((listH - footerBtns - 16 * s) / (rowH + 3 * s)))
  local pinScrollX = pinX + 6 * s
  local pinScrollW = listW - 12 * s
  local pinScrollH = listH - footerBtns - 16 * s
  local pinRowW = Kit.scrollInnerWidth(pinScrollW)
  S.eventScriptOffset = Kit.scroll(pinScrollX, listY + 8 * s, pinScrollW,
    pinScrollH, S.eventScriptOffset or 0, #entries, perPage)
  local entryKeys = {}
  for i, e in ipairs(entries) do entryKeys[i] = e.key end
  local eventNav = RegList.bindNav(S, entryKeys, {
    selKey = "eventScriptKey", offsetKey = "eventScriptOffset", perPage = perPage,
  })
  ry = listY + 8 * s
  for i = (S.eventScriptOffset or 0) + 1,
      math.min(#entries, (S.eventScriptOffset or 0) + perPage) do
    local e = entries[i]
    if Kit.row(pinScrollX, ry, pinRowW, rowH, S.eventScriptKey == e.key, PAL.yellow) then
      eventNav.activate()
      S.eventScriptKey = e.key
      S.eventAdvLayer = 1
      S.eventAdvOffset = 0
      S.eventAdvHit = 1
      -- Selection only — do not invent a Hello! stub.
    end
    local badge = TalkIndex.sourceLabel(e.source)
    local badgeW = Kit.textWidth("micro", badge) + 10 * s
    Kit.pushClip(pinScrollX, ry, pinRowW, rowH)
    local primary = Generation.isGen2(S)
      and (e.label or e.textId) or e.textId
    local secondary = Generation.isGen2(S)
      and (e.textId or "") or (e.label or "")
    Kit.text("micro",
      fitIn("micro", primary, math.max(8, pinRowW - badgeW - 16 * s)),
      pinScrollX + 6 * s, ry + 4 * s, PAL.text)
    Kit.text("micro", fitIn("micro", secondary, math.max(8, pinRowW - 12 * s)),
      pinScrollX + 6 * s, ry + 18 * s, PAL.faint)
    Kit.text("micro", badge, pinScrollX + pinRowW - badgeW, ry + 4 * s,
      sourceColor(e.source))
    Kit.popClip()
    ry = ry + rowH + 3 * s
  end
  S.eventScriptOffset = Kit.scrollbar(pinScrollX, listY + 8 * s, pinScrollW,
    pinScrollH, S.eventScriptOffset or 0, #entries, perPage)

  local gen2 = Generation.isGen2(S)
  local catalog = TalkIndex.isCatalogMap(S.eventMapId)
  if not catalog and Kit.button(pinX + 8 * s, listY + listH - 70 * s, listW - 16 * s, 28 * s,
      "From Dialog selection", { kind = "accent" }) then
    if S.dialogMapId and (S.dialogScriptKey or S.dialogTextId) then
      S.eventMapId = S.dialogMapId
      local pin = S.dialogScriptKey or S.dialogTextId
      S.eventScriptKey = S.dialogMapId .. "/" .. pin
    else
      S.status = "Pick a map NPC/sign on the Dialog tab first"
    end
  end
  if not catalog and not gen2 and Kit.button(pinX + 8 * s, listY + listH - 36 * s, listW - 16 * s, 28 * s,
      "+ Empty script", { kind = "good" }) then
    local mapId = S.eventMapId or S.mapId or S.dialogMapId or "NEW_MAP"
    State.ensureProjectFields(S.project)
    local n = 1
    local textId, key
    repeat
      textId = "TEXT_" .. mapId .. "_NPC" .. n
      key = mapId .. "/" .. textId
      n = n + 1
    until not (S.project.talkScripts and S.project.talkScripts[key])
    ensureEmptyScript(S, key)
    S.eventMapId = mapId
    S.eventScriptKey = key
    App.markDirty()
    S.status = "New empty script " .. textId
      .. " — edit steps here; Dialog edits the TEXT_* body"
  elseif not catalog and gen2 and Kit.button(pinX + 8 * s, listY + listH - 36 * s, listW - 16 * s, 28 * s,
      "+ Talk script", { kind = "good",
        tooltip = "Create a face-player talk script for this map" }) then
    local mapId = S.eventMapId or S.mapId or S.dialogMapId or "NEW_MAP"
    local sk, tid = Gen2Talk.allocTalk(S, mapId, "OBJ",
      #(entries) + 1, true)
    Gen2Talk.ensureScriptSteps(S, sk, mapId)
    Gen2Talk.commitSteps(S, sk)
    local attached, where = tryAttachScriptKey(S, mapId, sk)
    S.eventMapId = mapId
    S.eventScriptKey = mapId .. "/" .. sk
    S.dialogMapId = mapId
    S.dialogTextId = tid
    S.dialogScriptKey = sk
    App.markDirty()
    if attached then
      S.status = "Talk script on " .. where .. " — edit steps on the right"
    else
      S.status = "Talk script created — attach scriptKey on Maps, or edit steps here"
    end
  end

  local formX = pinX + listW + 12 * s
  local formW = w - (formX - x)
  Kit.caption(formX, y, gen2 and "TALK" or "STEPS")
  local advOn = S.eventAdvanced == true
  if not gen2 and Kit.chip(formX + formW - 100 * s, y, 100 * s, 22 * s, "ADVANCED",
      advOn, PAL.yellow, nil,
      "Resolve chain, injections, open mod/vanilla source") then
    S.eventAdvanced = not advOn
    advOn = S.eventAdvanced
    S.eventAdvLayer = 1
    S.eventAdvOffset = 0
    S.eventAdvHit = 1
  end
  if gen2 then advOn = false end
  Kit.card(formX, listY, formW, listH, 12 * s)

  if not S.eventScriptKey then
    Kit.emptyBox(formX + 8 * s, listY + 8 * s, formW - 16 * s, listH - 16 * s,
      gen2
        and (TalkIndex.isCatalogMap(S.eventMapId)
          and "Select a script — Override in mod to edit steps"
          or "Select a pin or + Talk script — Override opens the step builder")
        or "Select a map object — badges: SCRIPT (vanilla), TEXT, ITEM, MOD…")
    return
  end

  local mapId, textId = parseKey(S.eventScriptKey)
  if not mapId then
    Kit.emptyBox(formX + 8 * s, listY + 8 * s, formW - 16 * s, listH - 16 * s,
      "Invalid event key")
    return
  end

  -- Gold: step builder when scriptSteps exist (or owned scripts auto-decompile).
  -- Vanilla pins without override keep the opcode preview form.
  if gen2 then
    local bag = Gen2Talk.getScriptSteps(S, textId)
    if not bag and S.project.scripts and type(S.project.scripts[textId]) == "table" then
      bag = Gen2Talk.ensureScriptSteps(S, textId, mapId)
    end
    if not bag then
      drawGen2ScriptForm(S, App, formX, listY, formW, listH, mapId, textId)
      return
    end
  end

  local owned = gen2
    and Gen2Talk.getScriptSteps(S, textId)
    or S.project.talkScripts[S.eventScriptKey]
  if owned and not gen2
      and TalkIndex.repairPlaceholderSteps(S, mapId, textId, owned) then
    App.markDirty()
    S.status = "Fixed invalid Engine placeholder steps for "
      .. tostring(S.eventScriptKey)
  end
  local steps, meta = TalkIndex.resolveSteps(S, mapId, textId)
  if gen2 and owned and type(owned.steps) == "table" then
    steps = owned.steps
    meta = { owned = true, source = "mod", readOnly = false, gen2 = true }
  end
  local readOnly = not owned
  local footerH = readOnly and 40 * s or 0
  local advH = advOn and math.min(210 * s, math.floor(listH * 0.42)) or 0
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad + 36 * s
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s,
    listH - pad - footerH - 36 * s - advH - (advOn and 6 * s or 0))

  Kit.text("micro", fitIn("micro", S.eventScriptKey, formW - (readOnly and 24 or 200) * s),
    formX + 12 * s, listY + 10 * s, PAL.faint)
  local src = (meta and meta.source) or (owned and "mod") or "?"
  Kit.text("micro",
    readOnly
      and (gen2
        and ("Vanilla (" .. TalkIndex.sourceLabel(src)
          .. ") — Override in mod to edit steps")
        or ("Vanilla / engine (" .. TalkIndex.sourceLabel(src)
          .. ") — Clone to mod to edit steps; Dialog edits TEXT_* body"))
      or (gen2
        and "Mod script — edit steps (Save → Gold opcodes); Dialog edits text"
        or "Mod override — edit steps here; Dialog edits the TEXT_* body"),
    formX + 12 * s, listY + 22 * s, readOnly and PAL.yellow or PAL.green)

  local listKey = "script:" .. tostring(S.eventScriptKey or "")
  EventScriptEditor.draw(S, App, {
    x = viewX, y = viewY, w = viewW, h = viewH,
    steps = steps,
    scriptId = textId,
    listKey = listKey,
    readOnly = readOnly,
    onChange = function()
      if gen2 then Gen2Talk.commitSteps(S, textId) end
    end,
  })

  if advOn and advH > 0 then
    drawAdvancedTalk(S, App, viewX, viewY + viewH + 4 * s, viewW, advH,
      mapId, textId)
  end

  if readOnly then
    local by = listY + listH - 34 * s
    local cloneLabel = gen2 and "Override in mod" or "Clone to mod"
    if Kit.button(formX + 12 * s, by, 180 * s, 28 * s, cloneLabel,
        { kind = "good", font = "small",
          tooltip = gen2
            and "Clone opcodes into mod and open the step builder"
            or "Copy into mod to edit steps here; Dialog still edits TEXT_* body" }) then
      TalkIndex.cloneToProject(S, mapId, textId)
      App.markDirty()
      S.status = (gen2 and "Overrode " or "Cloned ") .. S.eventScriptKey
        .. (gen2 and " — edit steps here" or " — edit steps here; Dialog edits the TEXT_* body")
    end
    if Kit.button(formX + 200 * s, by, 70 * s, 28 * s, "Dialog", {
        kind = "accent", font = "small",
        tooltip = "Open this line on the Dialog tab",
      }) then
      if gen2 then
        openDialogForScript(S, mapId, textId)
      else
        S.tab = "dialog"
        S.dialogMapId = mapId
        S.dialogTextId = textId
      end
    end
    return
  end

  local script = owned
  if gen2 then
    local sx = formX + formW - 90 * s
    local sy = listY + 8 * s
    if Kit.chip(sx, sy, 80 * s, 20 * s, "Simplify", false, PAL.yellow, PAL.steel,
        "Replace with a single jumptextfaceplayer (destructive)") then
      local n = script.steps and #script.steps or 0
      if n > 1 and not S._confirmSimplify then
        S._confirmSimplify = textId
        S.status = "Click Simplify again to wipe " .. n .. " steps → Face talk"
      else
        S._confirmSimplify = nil
        Gen2Talk.ensureSimpleTalk(S, textId, true)
        Gen2Talk.refreshStepsFromCmds(S, textId)
        App.markDirty()
        S.status = "Simplified to Face talk"
      end
    elseif S._confirmSimplify and S._confirmSimplify ~= textId then
      S._confirmSimplify = nil
    end
    if Kit.button(formX + formW - 180 * s, listY + 8 * s, 82 * s, 20 * s, "Dialog", {
        kind = "ghost", font = "small",
        tooltip = "Open this script's text on the Dialog tab",
      }) then
      openDialogForScript(S, mapId, textId)
    end
    Gen2Talk.commitSteps(S, textId)
  else
    if Kit.button(formX + formW - 90 * s, listY + 8 * s, 80 * s, 20 * s, "Dialog", {
        kind = "ghost", font = "small",
        tooltip = "Edit the TEXT_* body on the Dialog tab",
      }) then
      S.tab = "dialog"
      S.dialogMapId = mapId
      S.dialogTextId = textId
    end
  end
end

local function drawStarters(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  local gen2 = Generation.isGen2(S)
  local yellow = Generation.id(S) == "yellow"
  local balls = gen2 and ELM_BALLS or (yellow and YELLOW_STARTER or OAK_BALLS)
  Kit.caption(x, y,
    gen2 and "ELM LAB STARTERS"
      or (yellow and "OAK'S PIKACHU" or "OAK LAB STARTERS"))
  local listY = y + 28 * s
  Kit.text("micro",
    gen2
      and "Remap the three Elm's Lab balls. Save emits pokemon.before_give on ELMS_LAB."
      or (yellow
        and "Yellow has no three-ball choice. Oak gives one Pikachu. Save remaps that gift."
        or "Remap the three Oak's Lab balls. Save emits pokemon.before_give (like example_mew_starter)."),
    x, listY, PAL.muted)
  listY = listY + 22 * s

  Kit.card(x, listY, w, h - (listY - y), 12 * s)
  local fy = listY + 16 * s
  local fh = 30 * s
  local remap = S.project.starterRemap

  for _, ball in ipairs(balls) do
    local cur = remap[ball.from]
    local sp = (type(cur) == "table" and cur.species)
      or (type(cur) == "string" and cur)
      or ball.from
    local lv = (type(cur) == "table" and tonumber(cur.level)) or 5

    Kit.text("small", ball.label, x + 20 * s, fy + 6 * s, PAL.caption)
    fy = fy + 22 * s
    Kit.text("micro", "becomes", x + 20 * s, fy + 8 * s, PAL.faint)
    SpeciesPicker.field(S, {
      x = x + 90 * s, y = fy, w = 160 * s, h = fh,
      current = sp,
      title = "STARTER · " .. ball.label,
      onPick = function(id)
        remap[ball.from] = { species = id, level = lv }
        App.markDirty()
      end,
    })
    local nlv = tonumber(field(App, "st_lv_" .. ball.from, x + 260 * s, fy, 50 * s, fh,
      tostring(lv), "5")) or 5
    if nlv ~= lv then
      remap[ball.from] = { species = sp, level = nlv }
      App.markDirty()
    end
    if Kit.button(x + 330 * s, fy, 70 * s, fh, "Reset", { kind = "ghost" }) then
      remap[ball.from] = nil
      App.markDirty()
    end
    fy = fy + fh + 16 * s
  end

  Kit.text("micro",
    gen2
      and "Pic/cry/text still show the vanilla ball species; the gift species/level change on receive."
      or (yellow
        and "Rival's Eevee ball is not remapped here. Extra Kanto gifts (Melanie, Damian, Jenny) are NPC scripts."
        or "Custom gifts on any NPC: Events > Scripts > + Pokemon / Give starter / One-shot pokemon."),
    x + 20 * s, fy, PAL.faint)
end

local function scrapeFlags(S)
  State.rebuildEventFlags(S.project)
  local names = {}
  local seen = {}
  local function add(n)
    if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  for n in pairs(S.project.eventFlags or {}) do add(n) end
  if S.events then
    for _, n in ipairs(S.events) do add(n) end
  end
  table.sort(names)
  return names
end

local function drawSaveFlags(S, x, y, w, h, App)
  local s = Kit.scale
  Kit.caption(x, y, "TEST SAVE FLAGS")
  local listY = y + 28 * s
  Kit.text("micro",
    "Toggles flags on a real save for playtesting. This does not author content.",
    x, listY, PAL.muted)
  listY = listY + 22 * s

  if Kit.button(x, listY, 140 * s, 30 * s, "Open save...", { kind = "accent" }) then
    local path = SaveIO.choosePath and SaveIO.choosePath()
    if path then
      local save, err = SaveIO.load(path)
      if save then
        S.testSave = save
        S.testSavePath = path
        S.status = "Loaded test save " .. path
      else
        S.status = "Save load failed: " .. tostring(err)
      end
    end
  end
  if Kit.button(x + 150 * s, listY, 100 * s, 30 * s, "Save",
      { kind = "primary", enabled = S.testSave ~= nil }) then
    if S.testSave and S.testSavePath then
      local ok, err = SaveIO.save(S.testSavePath, S.testSave)
      S.status = ok and ("Wrote " .. S.testSavePath) or tostring(err)
    end
  end
  Kit.text("micro", S.testSavePath or "(no save open)",
    x + 270 * s, listY + 8 * s, PAL.faint)
  listY = listY + 44 * s

  local filter = Search.field(S, "flagFilter", x, listY, 220 * s, 28 * s, "search flags...")
  listY = listY + 36 * s

  if not S.testSave then
    Kit.emptyBox(x, listY, w, h - (listY - y), "Open a save.lua to toggle flags")
    return
  end
  S.testSave.flags = S.testSave.flags or {}

  local flags = Search.filterIds(scrapeFlags(S), filter)
  local colW = (w - 12 * s) / 2
  local ry = listY
  local rowH = 28 * s
  local col = 0
  for _, name in ipairs(flags) do
    local cx = x + col * (colW + 12 * s)
    local on = S.testSave.flags[name] == true
    if Kit.chip(cx, ry, colW, rowH, name, on, PAL.green) then
      if on then
        S.testSave.flags[name] = nil
      else
        S.testSave.flags[name] = true
      end
      S.status = (on and "Cleared " or "Set ") .. name
    end
    col = col + 1
    if col > 1 then
      col = 0
      ry = ry + rowH + 6 * s
    end
    if ry > y + h - rowH then break end
  end
end

local HOOK_KINDS = {
  { id = "onEnter", label = "On enter",
    tip = "When the player walks into this map.",
    lines = {
      "When the player walks into this map.",
      "* = the game already has a script here.",
      "Add steps below; they still run.",
    } },
  { id = "onVictory", label = "After battle",
    tip = "After a trainer battle on this map ends.",
    lines = {
      "After a trainer battle on this map ends.",
      "Gym doors, rival scenes, 'you beat me'.",
    } },
  { id = "onStep", label = "Step on tile",
    tip = "When the player steps on a tile. Set X and Y on the right.",
    lines = {
      "When the player steps on one tile (set X/Y).",
      "Ladders, warps, and floor triggers.",
    } },
  { id = "script", label = "Named scripts",
    tip = "Scripts this map can call by name (not enter / battle / step).",
    lines = {
      "Scripts this map can call by name.",
      "Not enter, battle, or step. Pick a name first.",
    } },
}

local function ensureMapHooks(S, mapId)
  S.project.mapHooks = S.project.mapHooks or {}
  S.project.mapHooks[mapId] = S.project.mapHooks[mapId] or {}
  return S.project.mapHooks[mapId]
end

-- create=false: browse without inventing empty mod bags.
local function resolveHookSteps(hooks, kind, cellIdx, scriptName, create)
  if kind == "onEnter" then
    if not hooks.onEnter then
      if not create then return nil end
      hooks.onEnter = { steps = {} }
    end
    hooks.onEnter.steps = hooks.onEnter.steps or {}
    return hooks.onEnter.steps
  elseif kind == "onVictory" then
    if not hooks.onVictory then
      if not create then return nil end
      hooks.onVictory = { steps = {} }
    end
    hooks.onVictory.steps = hooks.onVictory.steps or {}
    return hooks.onVictory.steps
  elseif kind == "onStep" then
    if not hooks.onStepCells then
      if not create then return nil end
      hooks.onStepCells = { { x = 0, y = 0, steps = {} } }
    end
    cellIdx = tonumber(cellIdx) or 1
    if cellIdx < 1 then cellIdx = 1 end
    if not hooks.onStepCells[cellIdx] then
      if not create then return nil end
      hooks.onStepCells[cellIdx] = { x = 0, y = 0, steps = {} }
    end
    local cell = hooks.onStepCells[cellIdx]
    cell.steps = cell.steps or {}
    return cell.steps, cell
  elseif kind == "script" then
    hooks.scripts = hooks.scripts or {}
    scriptName = scriptName or "script"
    if not hooks.scripts[scriptName] then
      if not create then return nil end
      hooks.scripts[scriptName] = { steps = {} }
    end
    hooks.scripts[scriptName].steps = hooks.scripts[scriptName].steps or {}
    return hooks.scripts[scriptName].steps
  end
  return nil
end

local function vanillaHookLabel(info, kind)
  if kind == "script" then
    local n = 0
    for _ in pairs(info.scripts or {}) do n = n + 1 end
    if n > 0 then return string.format(" (%d)", n) end
    return ""
  end
  local h = info.hooks and info.hooks[kind]
  if not h then return "" end
  return " *"
end

local function mapHasModHooks(S, mapId)
  local hooks = S.project and S.project.mapHooks and S.project.mapHooks[mapId]
  if type(hooks) ~= "table" then return false end
  if hooks.onEnter or hooks.onVictory then return true end
  if type(hooks.onStepCells) == "table" and #hooks.onStepCells > 0 then return true end
  if type(hooks.scripts) == "table" and next(hooks.scripts) then return true end
  return false
end

-- Deep-clone tables for the Events clipboard (warp map names, nested rows, …).
local function cloneValue(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do
    out[k] = cloneValue(val)
  end
  return out
end

local function cloneSteps(steps)
  local out = {}
  for i, step in ipairs(steps or {}) do
    out[i] = cloneValue(step)
  end
  return out
end

local function replaceSteps(dest, src)
  if type(dest) ~= "table" then return end
  for i = #dest, 1, -1 do dest[i] = nil end
  for i, step in ipairs(src or {}) do
    dest[i] = cloneValue(step)
  end
end

-- Copy the current hook cell / step bag / talk script into S.eventClip.
local function copyCurrentEvent(S)
  if not S or not S.project then return false, "no project" end
  State.ensureProjectFields(S.project)
  local mode = S.eventsMode or "scripts"
  if mode == "hooks" then
    local mapId = S.eventMapId
    if not mapId then return false, "select a map" end
    local hooks = S.project.mapHooks and S.project.mapHooks[mapId]
    local kind = S.eventHookKind or "onEnter"
    if kind == "onStep" then
      local cells = hooks and hooks.onStepCells
      local idx = math.max(1, tonumber(S.eventHookCellIdx) or 1)
      local cell = cells and cells[idx]
      if not cell then return false, "no onStep cell to copy — add one first" end
      S.eventClip = {
        type = "hookCell",
        kind = "onStep",
        x = tonumber(cell.x) or 0,
        y = tonumber(cell.y) or 0,
        steps = cloneSteps(cell.steps),
        fromMap = mapId,
      }
      return true, string.format(
        "Copied onStep (%d,%d) · %d steps — switch map, Ctrl+V to paste",
        S.eventClip.x, S.eventClip.y, #S.eventClip.steps)
    end
    local bag = resolveHookSteps(hooks or {}, kind, S.eventHookCellIdx,
      S.eventHookScriptName, false)
    if not bag then
      return false, "nothing to copy — add mod steps first"
    end
    S.eventClip = {
      type = "hookSteps",
      kind = kind,
      scriptName = S.eventHookScriptName,
      steps = cloneSteps(bag),
      fromMap = mapId,
    }
    return true, string.format(
      "Copied %s · %d steps — Ctrl+V to paste on another map",
      kind, #S.eventClip.steps)
  end
  if mode == "scripts" then
    local key = S.eventScriptKey
    if not key then return false, "select a script" end
    local mapId, textId = parseKey(key)
    local gen2 = Generation.isGen2(S)
    local owned = gen2
      and Gen2Talk.getScriptSteps(S, textId)
      or (S.project.talkScripts and S.project.talkScripts[key])
    local steps
    if owned and type(owned.steps) == "table" then
      steps = owned.steps
    elseif mapId then
      steps = select(1, TalkIndex.resolveSteps(S, mapId, textId))
    end
    if type(steps) ~= "table" then return false, "nothing to copy" end
    S.eventClip = {
      type = gen2 and "gen2Steps" or "talkSteps",
      key = key,
      scriptKey = textId,
      steps = cloneSteps(steps),
    }
    return true, string.format(
      "Copied %d steps — Ctrl+V pastes into the selected script", #S.eventClip.steps)
  end
  return false, "copy not available in this mode"
end

-- Paste S.eventClip: onStep+cell → new cell; otherwise replace current steps.
local function pasteEventClip(S, App)
  if not S or not S.project then return false, "no project" end
  local clip = S.eventClip
  if not clip or type(clip.steps) ~= "table" then
    return false, "clipboard empty — Copy an event first (Ctrl+C)"
  end
  State.ensureProjectFields(S.project)
  local mode = S.eventsMode or "scripts"
  if mode == "hooks" then
    local mapId = S.eventMapId
    if not mapId then return false, "select a map" end
    local hooks = ensureMapHooks(S, mapId)
    local kind = S.eventHookKind or "onEnter"
    if kind == "onStep" and clip.type == "hookCell" then
      hooks.onStepCells = hooks.onStepCells or {}
      hooks.onStepCells[#hooks.onStepCells + 1] = {
        x = tonumber(clip.x) or 0,
        y = tonumber(clip.y) or 0,
        steps = cloneSteps(clip.steps),
      }
      S.eventHookCellIdx = #hooks.onStepCells
      if App and App.markDirty then App.markDirty() end
      return true, string.format(
        "Pasted onStep (%d,%d) → %s  (%d steps)",
        clip.x or 0, clip.y or 0, mapId, #clip.steps)
    end
    local steps = resolveHookSteps(hooks, kind, S.eventHookCellIdx,
      S.eventHookScriptName, true)
    replaceSteps(steps, clip.steps)
    if App and App.markDirty then App.markDirty() end
    return true, string.format(
      "Pasted %d steps into %s / %s", #clip.steps, mapId, kind)
  end
  if mode == "scripts" then
    local key = S.eventScriptKey
    if not key then return false, "select a script" end
    local mapId, textId = parseKey(key)
    if not mapId then return false, "invalid script key" end
    if Generation.isGen2(S) then
      local bag = Gen2Talk.ensureScriptSteps(S, textId, mapId)
      if not bag then return false, "could not own script" end
      bag.steps = Gen2Talk.copySteps(clip.steps)
      Gen2Talk.commitSteps(S, textId)
      if App and App.markDirty then App.markDirty() end
      return true, string.format("Pasted %d steps into %s", #bag.steps, textId)
    end
    local owned = S.project.talkScripts[key]
    if not owned then
      TalkIndex.cloneToProject(S, mapId, textId)
      owned = S.project.talkScripts[key]
    end
    if not owned then return false, "could not own script" end
    owned.steps = cloneSteps(clip.steps)
    if App and App.markDirty then App.markDirty() end
    return true, string.format("Pasted %d steps into %s", #owned.steps, key)
  end
  return false, "paste not available in this mode"
end

-- Drop the current mod hook bag (onEnter / onVictory / one onStep cell / named script).
local function clearModHook(S, mapId, kind, cellIdx, scriptName)
  local bag = S.project.mapHooks and S.project.mapHooks[mapId]
  if type(bag) ~= "table" then return false end
  if kind == "onEnter" then
    bag.onEnter = nil
  elseif kind == "onVictory" then
    bag.onVictory = nil
  elseif kind == "onStep" then
    if type(bag.onStepCells) == "table" then
      local idx = tonumber(cellIdx) or 1
      table.remove(bag.onStepCells, idx)
      if #bag.onStepCells == 0 then bag.onStepCells = nil end
    end
  elseif kind == "script" then
    if type(bag.scripts) == "table" and scriptName then
      bag.scripts[scriptName] = nil
      if not next(bag.scripts) then bag.scripts = nil end
    end
  else
    return false
  end
  if not bag.onEnter and not bag.onVictory
      and not bag.onStepCells and not bag.scripts then
    S.project.mapHooks[mapId] = nil
  end
  return true
end

local function drawHooks(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  TalkIndex.ensureScripts()

  local mapColW = math.min(160 * s, w * 0.18)
  local listW = math.min(220 * s, w * 0.28)
  local qh = 28 * s
  local qy = y + 22 * s
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y)

  Kit.caption(x, y, "MAP")
  Kit.offerTooltip(x, y, mapColW, 20 * s,
    "Pick a map. * = the game already scripts it. + = you added steps.")
  local mapQ, mapQCh = Search.field(S, "hookMapQuery", x, qy, mapColW, qh, "maps...")
  if mapQCh then S.hookMapOffset = 0 end
  Kit.card(x, listY, mapColW, listH, 12 * s)
  local maps = Search.filterIds(TalkIndex.allMapIds(S), mapQ)
  if not S.eventMapId then
    S.eventMapId = S.dialogMapId or S.mapId or maps[1]
  end
  local mapRowH = 26 * s
  local perMap = math.max(1, math.floor((listH - 16 * s) / (mapRowH + 2 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = mapColW - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.hookMapOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.hookMapOffset or 0, #maps, perMap)
  local ry = listY + 8 * s
  for i = (S.hookMapOffset or 0) + 1,
      math.min(#maps, (S.hookMapOffset or 0) + perMap) do
    local id = maps[i]
    if Kit.row(mapScrollX, ry, mapRowW, mapRowH, S.eventMapId == id, PAL.blue) then
      S.eventMapId = id
      S.hookFormScroll = nil
    end
    local hasV = TalkIndex.mapHasHooks(id)
    local hasM = mapHasModHooks(S, id)
    local mark = (hasM and " +" or "") .. (hasV and " *" or "")
    Kit.pushClip(mapScrollX, ry, mapRowW, mapRowH)
    Kit.text("micro",
      fitIn("micro", id .. mark, math.max(8, mapRowW - 12 * s)),
      mapScrollX + 6 * s, ry + 6 * s,
      hasM and PAL.green or (hasV and PAL.yellow or PAL.text))
    Kit.popClip()
    Kit.offerTooltip(mapScrollX, ry, mapRowW, mapRowH,
      hasM and "You added steps on this map."
        or (hasV and "The game already has a script on this map."
          or "Nothing extra on this map yet."))
    ry = ry + mapRowH + 2 * s
  end
  S.hookMapOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.hookMapOffset or 0, #maps, perMap)

  local pinX = x + mapColW + 10 * s
  Kit.caption(pinX, y, "WHEN")
  Kit.offerTooltip(pinX, y, listW, 20 * s,
    "When this runs. Hover each choice for a short explanation.")
  Kit.card(pinX, listY, listW, listH, 12 * s)
  S.eventHookKind = S.eventHookKind or "onEnter"
  local vanillaInfo = TalkIndex.mapHookInfo(S.eventMapId)
  ry = listY + 10 * s
  local selectedHk
  for _, hk in ipairs(HOOK_KINDS) do
    local on = S.eventHookKind == hk.id
    if on then selectedHk = hk end
    local label = hk.label .. vanillaHookLabel(vanillaInfo, hk.id)
    if Kit.chip(pinX + 10 * s, ry, listW - 20 * s, 28 * s, label, on, PAL.yellow,
        nil, hk.tip) then
      S.eventHookKind = hk.id
    end
    ry = ry + 34 * s
  end
  local tipW = listW - 20 * s
  local helpH = math.max(8, listY + listH - (ry + 8 * s))
  Kit.pushClip(pinX + 10 * s, ry + 4 * s, tipW, helpH)
  local hy = ry + 8 * s
  for _, line in ipairs((selectedHk and selectedHk.lines) or {}) do
    Kit.text("micro", line, pinX + 10 * s, hy, PAL.faint)
    hy = hy + 14 * s
  end
  Kit.popClip()

  local formX = pinX + listW + 12 * s
  local formW = w - (formX - x)
  Kit.caption(formX, y, "STEPS")
  Kit.offerTooltip(formX, y, 80 * s, 20 * s,
    "What to do at that time. Buttons at the bottom add a step.")
  Kit.card(formX, listY, formW, listH, 12 * s)

  local mapId = S.eventMapId
  if not mapId then
    Kit.emptyBox(formX + 8 * s, listY + 8 * s, formW - 16 * s, listH - 16 * s,
      "Select a map")
    return
  end

  local hooks = ensureMapHooks(S, mapId)
  local kind = S.eventHookKind or "onEnter"
  local pad = 12 * s
  local metaH = 40 * s
  if kind == "onStep" or kind == "script" then metaH = 70 * s end
  -- Recipes + step shortcuts; sized so Warp / Ladder are never clipped.
  local stepShortcuts = shortcutDefs(S)
  -- +1 row for Ladder / Warp step / Flag gate recipes ahead of step chips.
  local footerH = math.max(140 * s,
    shortcutStripHeight(stepShortcuts, formW, s, 0) + 40 * s)
  local viewX = formX + pad
  local viewY = listY + pad + metaH
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH - metaH)

  Kit.text("micro",
    Kit.ellipsize("micro",
      mapId .. " · " .. ((selectedHk and selectedHk.label) or kind),
      formW - 140 * s),
    formX + 12 * s, listY + 10 * s, PAL.faint)

  -- Named scripts: pick from vanilla list + mod drafts.
  if kind == "script" then
    local names, seen = {}, {}
    for name in pairs(vanillaInfo.scripts or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    for name in pairs(hooks.scripts or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    table.sort(names)
    if not S.eventHookScriptName or S.eventHookScriptName == "" then
      S.eventHookScriptName = names[1] or "script"
    end
    local nx = formX + 12 * s
    for _, name in ipairs(names) do
      local on = S.eventHookScriptName == name
      local lab = name
      if vanillaInfo.scripts and vanillaInfo.scripts[name] then
        lab = lab .. " *"
      end
      local bw = Kit.textWidth("micro", lab) + 14 * s
      if Kit.chip(nx, listY + 28 * s, bw, 24 * s, lab, on, PAL.blue) then
        S.eventHookScriptName = name
      end
      nx = nx + bw + 4 * s
    end
    local name = field(App, "hk_sn", formX + 12 * s, listY + 54 * s,
      160 * s, 24 * s, S.eventHookScriptName or "script", "script_name")
    name = tostring(name or "script"):gsub("%s+", "_")
    if name ~= S.eventHookScriptName then
      if hooks.scripts and hooks.scripts[S.eventHookScriptName]
          and not hooks.scripts[name] then
        hooks.scripts[name] = hooks.scripts[S.eventHookScriptName]
        hooks.scripts[S.eventHookScriptName] = nil
      end
      S.eventHookScriptName = name
      App.markDirty()
    end
    metaH = 86 * s
    viewY = listY + pad + metaH
    viewH = math.max(40 * s, listH - pad - footerH - metaH)
  elseif kind == "onStep" then
    local cells = hooks.onStepCells
    local nCells = (type(cells) == "table" and #cells) or 0
    if nCells > 0 then
      S.eventHookCellIdx = math.max(1, math.min(
        S.eventHookCellIdx or 1, nCells))
      local idx = S.eventHookCellIdx
      local cell = cells[idx]
      Kit.text("micro", "Mod cell #" .. idx, formX + 12 * s, listY + 28 * s, PAL.caption)
      cell.x = tonumber(field(App, "hk_cx", formX + 90 * s, listY + 24 * s,
        50 * s, 26 * s, tostring(cell.x or 0), "0")) or 0
      cell.y = tonumber(field(App, "hk_cy", formX + 150 * s, listY + 24 * s,
        50 * s, 26 * s, tostring(cell.y or 0), "0")) or 0
      if Kit.button(formX + 210 * s, listY + 24 * s, 60 * s, 26 * s, "Prev",
          { kind = "ghost", font = "small" }) and idx > 1 then
        S.eventHookCellIdx = idx - 1
      end
      if Kit.button(formX + 276 * s, listY + 24 * s, 60 * s, 26 * s, "Next",
          { kind = "ghost", font = "small" }) and idx < nCells then
        S.eventHookCellIdx = idx + 1
      end
      if Kit.button(formX + 342 * s, listY + 24 * s, 70 * s, 26 * s, "+ Cell",
          { kind = "good", font = "small" }) then
        cells[#cells + 1] = { x = 0, y = 0, steps = {} }
        S.eventHookCellIdx = #cells
        App.markDirty()
      end
      if Kit.button(formX + 418 * s, listY + 24 * s, 80 * s, 26 * s, "Del cell",
          { kind = "danger", font = "small",
            tooltip = "Remove this mod onStep cell" }) then
        clearModHook(S, mapId, "onStep", idx, nil)
        if hooks.onStepCells and #hooks.onStepCells > 0 then
          S.eventHookCellIdx = math.min(idx, #hooks.onStepCells)
        else
          S.eventHookCellIdx = 1
        end
        App.markDirty()
      end
    else
      Kit.text("micro", "No mod cells yet — + Cell or Paste a copied onStep",
        formX + 12 * s, listY + 30 * s, PAL.muted)
      if Kit.button(formX + 280 * s, listY + 24 * s, 70 * s, 26 * s, "+ Cell",
          { kind = "good", font = "small" }) then
        hooks.onStepCells = { { x = 0, y = 0, steps = {} } }
        S.eventHookCellIdx = 1
        App.markDirty()
      end
    end
  end

  local steps = resolveHookSteps(hooks, kind, S.eventHookCellIdx,
    S.eventHookScriptName, false)
  local editing = type(steps) == "table"

  -- Copy / Paste / Clear along the STEPS header (Ctrl+C/V also work).
  do
    local hx = formX + formW - 12 * s
    if Kit.button(hx - 52 * s, listY + 6 * s, 52 * s, 26 * s, "Paste", {
        kind = "good", font = "small",
        tooltip = "Paste clipboard (Ctrl+V). onStep cell → new cell on this map",
      }) then
      local ok, msg = pasteEventClip(S, App)
      S.status = msg or (ok and "Pasted" or "Paste failed")
      hooks = ensureMapHooks(S, mapId)
      steps = resolveHookSteps(hooks, kind, S.eventHookCellIdx,
        S.eventHookScriptName, false)
      editing = type(steps) == "table"
    end
    if Kit.button(hx - 108 * s, listY + 6 * s, 52 * s, 26 * s, "Copy", {
        kind = "ghost", font = "small",
        tooltip = "Copy this event / onStep cell (Ctrl+C), including warp map names",
      }) then
      local ok, msg = copyCurrentEvent(S)
      S.status = msg or (ok and "Copied" or "Copy failed")
    end
    if editing and kind ~= "onStep" and Kit.button(
        hx - 216 * s, listY + 6 * s, 100 * s, 26 * s,
        "Clear mod", {
          kind = "danger", font = "small",
          tooltip = "Remove this mod's hook steps (engine hook stays)",
        }) then
      clearModHook(S, mapId, kind, S.eventHookCellIdx, S.eventHookScriptName)
      App.markDirty()
      steps = nil
      editing = false
    end
  end

  local function ensureSteps()
    if editing then return steps end
    steps = resolveHookSteps(hooks, kind, S.eventHookCellIdx,
      S.eventHookScriptName, true)
    editing = true
    return steps
  end

  local function addStep(step)
    local bag = ensureSteps()
    bag[#bag + 1] = step
    App.markDirty()
  end

  local track = mapId .. "/" .. kind .. "/"
    .. tostring(S.eventHookCellIdx or 0) .. "/"
    .. tostring(S.eventHookScriptName or "")
    .. (editing and ":m" or ":v")
  FormPane.track(S, "hookFormScroll", track)
  local fy, view = FormPane.begin(S, "hookFormScroll", viewX, viewY, viewW, viewH)
  local contentTop = fy
  local fh = 28 * s
  local kindW = 150 * s
  local innerW = view.contentW or view.w

  -- Show engine hook summary when this kind exists in data/scripts.
  local vHook = (kind ~= "script") and vanillaInfo.hooks and vanillaInfo.hooks[kind]
  local vScript = (kind == "script") and vanillaInfo.scripts
    and vanillaInfo.scripts[S.eventHookScriptName or ""]
  if vHook or vScript then
    local form = (vHook and vHook.form) or (vScript and vScript.form)
    Kit.text("micro", "ENGINE", viewX, fy + 6 * s, PAL.yellow)
    if form == "lua" then
      Kit.text("micro",
        "The game already runs a script here (not editable here).",
        viewX + 60 * s, fy + 2 * s, PAL.muted)
      Kit.text("micro",
        "Add your own steps below — they still run.",
        viewX + 60 * s, fy + 16 * s, PAL.muted)
      fy = fy + fh + 8 * s
    elseif form == "rows" then
      local rows = (vHook and vHook.rows) or (vScript and vScript.rows) or {}
      Kit.text("micro",
        string.format("%d game command(s) — read-only", #rows),
        viewX + 60 * s, fy + 6 * s, PAL.muted)
      fy = fy + fh + 4 * s
      local show = ModWriter.rowsToSteps(rows)
      for _, step in ipairs(show) do
        local sk = step.kind or "raw"
        Kit.text("micro", stepLabel(sk, step), viewX, fy + 6 * s, PAL.caption)
        local detail = step.note or step.text or step.flag or step.name or ""
        Kit.text("micro",
          fitIn("micro", tostring(detail), innerW - kindW - 8 * s),
          viewX + kindW + 8 * s, fy + 6 * s, PAL.faint)
        fy = fy + fh + 4 * s
        if fy > viewY + viewH + 200 * s then break end
      end
    end
    fy = fy + 8 * s
  end

  if not editing or #(steps or {}) == 0 then
    if not vHook and not vScript then
      Kit.text("small", "Nothing runs here yet. Use a button below to add a step.",
        viewX, fy, PAL.muted)
      fy = fy + 24 * s
    else
      Kit.text("small", "Your extra steps (run in addition to the game script):",
        viewX, fy, PAL.muted)
      fy = fy + 24 * s
    end
    if Kit.button(viewX, fy, 110 * s, fh, "+ Text", {
        kind = "good", font = "small",
        tooltip = "Show a dialog box. Edit the words after you add it.",
      }) then
      addStep({ kind = "show_text", text = "..." })
    end
    if Kit.button(viewX + 118 * s, fy, 110 * s, fh, "+ Command", {
        kind = "accent", font = "small",
        tooltip = "A raw game command (check_flag, hide_object, play_sound…). Edit the row after adding.",
      }) then
      addStep({
        kind = "raw",
        note = "check_flag EVENT_FLAG",
        row = { "check_flag", "EVENT_FLAG" },
      })
    end
    if Kit.button(viewX + 236 * s, fy, 110 * s, fh, "+ Set flag", {
        kind = "ghost", font = "small",
        tooltip = "Mark a story flag as done so this event can refuse to repeat.",
      }) then
      addStep({ kind = "set_flag", flag = "DONE" })
    end
    if kind == "onStep" and Kit.button(viewX + 354 * s, fy, 100 * s, fh, "+ Cell", {
        kind = "ghost", font = "small",
        tooltip = "Add another tile (X/Y) that runs steps when stepped on.",
      }) then
      ensureSteps()
      hooks.onStepCells = hooks.onStepCells or {}
      if #hooks.onStepCells == 0 then
        -- ensureSteps already created cell 1
      else
        hooks.onStepCells[#hooks.onStepCells + 1] = { x = 0, y = 0, steps = {} }
        S.eventHookCellIdx = #hooks.onStepCells
      end
      App.markDirty()
    end
    fy = fy + fh + 12 * s
  end

  if editing then
    local listKey = "hook:" .. tostring(mapId) .. "/" .. tostring(kind)
      .. "/" .. tostring(S.eventHookCellIdx or 0) .. "/"
      .. tostring(S.eventHookScriptName or "")
    beginStepListReorder(S, listKey)
    for i = 1, #steps do
      fy = drawEditableStep(S, App, steps, i, listKey,
        viewX, fy, innerW, kindW, fh, s)
    end
    finishStepListReorder(S, steps, listKey, App)
  end
  FormPane.finish(S, "hookFormScroll", contentTop, fy, view)

  local destMap = mapId
  local recipes = {
    { label = "+ Ladder", kind = "good",
      tip = "New tile trigger: stepping here warps (stairs / ladder). Set cell X/Y and the destination.",
      apply = function()
        S.eventHookKind = "onStep"
        hooks.onStepCells = hooks.onStepCells or {}
        hooks.onStepCells[#hooks.onStepCells + 1] = {
          x = 0, y = 0,
          steps = {
            {
              kind = "warp", map = destMap, x = 5, y = 6, facing = "down",
            },
          },
        }
        S.eventHookCellIdx = #hooks.onStepCells
        App.markDirty()
        S.status = "Ladder cell added — set cell x/y and warp destination map"
      end },
    { label = "+ Warp step", kind = "accent",
      tip = "Add a warp to the current list (not a new tile). Set map / X / Y after.",
      apply = function()
        addStep({
          kind = "warp", map = destMap, x = 5, y = 6, facing = "down",
        })
        S.status = "Warp step added — edit map / x / y"
      end },
    { label = "+ Flag gate", kind = "ghost",
      tip = "Run once: skip if the flag is already set, then set that flag.",
      apply = function()
        addStep({ kind = "check_flag_skip", flag = "DONE" })
        addStep({ kind = "set_flag", flag = "DONE" })
        S.status = "Flag gate added — rename DONE to your event flag"
      end },
  }
  local allShortcuts = {}
  for _, sc in ipairs(recipes) do allShortcuts[#allShortcuts + 1] = sc end
  for _, sc in ipairs(stepShortcuts) do allShortcuts[#allShortcuts + 1] = sc end

  local by = listY + listH - footerH + 6 * s
  Kit.text("micro", "Add a step  ·  hover a button for what it does",
    formX + 12 * s, by - 14 * s, PAL.caption)
  drawShortcutStrip(allShortcuts, formX + 12 * s, by, formW - 24 * s,
    footerH - 10 * s, s, function(step) addStep(step) end)
end

-- ---- Gold Pokegear phone contacts ----

local function phoneContactOrder(S)
  local c = S.data and (S.data.gen2Constants or S.data.constants)
  return (c and c.phoneContactOrder) or {}
end

local function phoneResolved(S, id)
  local order = phoneContactOrder(S)
  local index
  for i, name in ipairs(order) do
    if name == id then index = i - 1; break end
  end
  if index == nil then return nil, nil, false end
  local owned = S.project.phoneContacts and S.project.phoneContacts[id]
  if owned then return owned, index, true end
  local copy = { index = index }
  local ok, Phone = pcall(require, "src.core.gen2.Phone")
  local lit = ok and Phone and Phone.CONTACTS and Phone.CONTACTS[index]
  if type(lit) == "table" then
    for k, v in pairs(lit) do copy[k] = v end
  elseif lit == false then
    return nil, index, false
  end
  local ev = S.data and (S.data.gen2EventTables or S.data.events)
  local row = ev and ev.phone and ev.phone[index]
  if type(row) == "table" then
    copy.map = row.map
    copy.calleeTime = row.calleeTime
    copy.callerTime = row.callerTime
    copy.calleeKey = row.callee
    copy.callerKey = row.caller
    if row.number and row.number ~= 0 then copy.number = row.number end
  end
  copy.index = index
  return copy, index, false
end

local function drawPhone(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  S.project.phoneContacts = S.project.phoneContacts or {}
  Kit.caption(x, y, "PHONE CONTACTS")
  Kit.text("micro", "Pokegear book — Save emits phone_contacts:patch",
    x + 160 * s, y + 4 * s, PAL.faint)

  local order = phoneContactOrder(S)
  local ids = {}
  for _, id in ipairs(order) do
    if id ~= "PHONE_UNUSED" and id ~= "PHONE_00" then
      ids[#ids + 1] = id
    end
  end
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y + 22 * s, w, h - 22 * s,
    "CONTACTS", ids, {
      queryKey = "eventPhoneQuery",
      offsetKey = "eventPhoneOffset",
      selKey = "eventPhoneId",
      accent = PAL.blue,
      isOwned = function(id)
        return S.project.phoneContacts[id] ~= nil
      end,
    })
  if not S.eventPhoneId then S.eventPhoneId = shown[1] end
  local id = S.eventPhoneId
  local rec, index, owned = phoneResolved(S, id)
  if not id or not rec then
    Kit.emptyBox(formX, listY, formW, listH,
      "No phone contacts (import Gold/Silver ROM cache)")
    return
  end

  local function ensure()
    if owned then return S.project.phoneContacts[id] end
    local copy = {}
    for k, v in pairs(rec) do copy[k] = v end
    copy.index = index
    copy._isNew = false
    S.project.phoneContacts[id] = copy
    owned = true
    App.markDirty()
    return copy
  end

  Kit.caption(formX, listY - 28 * s,
    id .. "  #" .. tostring(index) .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "eventPhoneScroll", "phone|" .. id, owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  row("Map", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.map or "")
    local v = RegList.field(App, "ph_map", fx, fy_, fw, fh_, cur, "ROUTE_30")
    if v ~= cur then
      local e = ensure()
      e.map = (v ~= "" and v) or nil
    end
  end)
  row("Number", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.number) or 0
    local v = RegList.num(App, "ph_num", fx, fy_, 80 * s, fh_, cur)
    v = math.max(0, math.min(255, math.floor(v)))
    if v ~= cur then ensure().number = v end
  end)
  row("Callee time", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.calleeTime) or 0
    local v = RegList.num(App, "ph_ct", fx, fy_, 80 * s, fh_, cur)
    v = math.max(0, math.min(7, math.floor(v)))
    if v ~= cur then ensure().calleeTime = v end
    Kit.text("micro", "bitmask MORN|DAY|NITE (0=never)",
      fx + 90 * s, fy_ + 8 * s, PAL.faint)
  end)
  row("Caller time", function(fx, fy_, fw, fh_)
    local cur = tonumber(rec.callerTime) or 0
    local v = RegList.num(App, "ph_cr", fx, fy_, 80 * s, fh_, cur)
    v = math.max(0, math.min(7, math.floor(v)))
    if v ~= cur then ensure().callerTime = v end
  end)
  row("Class", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.class or "")
    local v = RegList.field(App, "ph_cls", fx, fy_, fw, fh_, cur, "YOUNGSTER")
    if v ~= cur then
      local e = ensure()
      e.class = (v ~= "" and v) or nil
    end
  end)
  row("Member", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.member or "")
    local v = RegList.field(App, "ph_mem", fx, fy_, fw, fh_, cur, "JOEY1")
    if v ~= cur then
      local e = ensure()
      e.member = (v ~= "" and v) or nil
    end
  end)
  row("Callee", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.callee or rec.calleeKey or "")
    Kit.text("micro", Kit.ellipsize("micro", cur, fw), fx, fy_ + 8 * s, PAL.muted)
  end)
  row("Caller", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.caller or rec.callerKey or "")
    Kit.text("micro", Kit.ellipsize("micro", cur, fw), fx, fy_ + 8 * s, PAL.muted)
  end)

  if not owned then
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensure()
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "eventPhoneScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    S.project.phoneContacts[id] = nil
    App.markDirty()
  end
end

function Events.keypressed(S, key, App)
  if not S or Kit.focus then return false end
  local mode = S.eventsMode or "scripts"
  if mode ~= "hooks" and mode ~= "scripts" then return false end
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  if not ctrl then return false end
  if key == "c" then
    local ok, msg = copyCurrentEvent(S)
    S.status = msg or (ok and "Copied" or "Copy failed")
    return true
  end
  if key == "v" then
    local ok, msg = pasteEventClip(S, App)
    S.status = msg or (ok and "Pasted" or "Paste failed")
    return true
  end
  return false
end

function Events.bindSession(S)
  acS = S
end

function Events.stepLabel(kind, step)
  return stepLabel(kind, step)
end

function Events.stepKinds()
  return STEP_KINDS
end

function Events.stepKindAllowed(S, rec)
  return stepKindAllowed(S, rec)
end

function Events.drawStepFields(S, App, step, i, kind, fx, fy, fw, fh, s)
  return drawStepFields(S, App, step, i, kind, fx, fy, fw, fh, s)
end

function Events.stepPreview(S, step, maxW)
  return stepPreview(S, step, maxW)
end

function Events.cloneSteps(steps)
  return cloneSteps(steps)
end

function Events.replaceSteps(dest, src)
  return replaceSteps(dest, src)
end

function Events.parseKey(key)
  return parseKey(key)
end

-- Own a talk script bag (Gold scriptSteps / Gen1 talkScripts) for editing.
function Events.ownTalkScript(S, mapId, scriptId)
  if not (S and S.project and scriptId and scriptId ~= "") then return nil end
  State.ensureProjectFields(S.project)
  if Generation.isGen2(S) then
    local bag = Gen2Talk.getScriptSteps(S, scriptId)
    if bag then return bag.steps end
    bag = Gen2Talk.ensureScriptSteps(S, scriptId, mapId)
    if bag then Gen2Talk.commitSteps(S, scriptId) end
    return bag and bag.steps or nil
  end
  local key = mapId .. "/" .. scriptId
  local script = S.project.talkScripts[key]
  if not script then
    TalkIndex.cloneToProject(S, mapId, scriptId)
    script = S.project.talkScripts[key]
  end
  if not script then
    script = {
      mapId = mapId,
      textId = scriptId,
      steps = { { kind = "show_text", text = scriptId or "Hello!" } },
    }
    S.project.talkScripts[key] = script
  end
  return script.steps
end

function Events.draw(S, x, y, w, h, App)
  acS = S
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  local gen2 = Generation.isGen2(S)

  local mode = S.eventsMode or "scripts"
  if Kit.chip(x, y, 90 * s, 26 * s, "SCRIPTS", mode == "scripts", PAL.yellow,
      nil, "Talk scripts: what an NPC says when you talk to them.") then
    S.eventsMode = "scripts"; mode = "scripts"
  end
  local chipX = x + 96 * s
  if Kit.chip(chipX, y, 90 * s, 26 * s, "HOOKS", mode == "hooks", PAL.yellow,
      nil, "When the player enters a map, wins a battle, or steps on a tile.") then
    S.eventsMode = "hooks"; mode = "hooks"
  end
  chipX = chipX + 96 * s
  if Kit.chip(chipX, y, 100 * s, 26 * s, "STARTERS",
      mode == "starters", PAL.green, nil,
      Generation.id(S) == "yellow"
        and "Oak's Pikachu gift (Yellow has no three-ball choice)."
        or (gen2
          and "Elm's Lab Cyndaquil / Totodile / Chikorita."
          or "Oak's Lab Charmander / Squirtle / Bulbasaur.")) then
    S.eventsMode = "starters"; mode = "starters"
  end
  chipX = chipX + 106 * s
  if gen2 then
    if Kit.chip(chipX, y, 90 * s, 26 * s, "PHONE", mode == "phone", PAL.green) then
      S.eventsMode = "phone"; mode = "phone"
    end
    chipX = chipX + 96 * s
  end
  if Kit.chip(chipX, y, 120 * s, 26 * s, "SAVE FLAGS",
      mode == "saveflags", PAL.blue) then
    S.eventsMode = "saveflags"; mode = "saveflags"
  end

  local bodyY = y + 36 * s
  local bodyH = h - 36 * s
  if mode == "saveflags" then
    drawSaveFlags(S, x, bodyY, w, bodyH, App)
  elseif mode == "phone" and gen2 then
    drawPhone(S, x, bodyY, w, bodyH, App)
  elseif mode == "starters" then
    drawStarters(S, x, bodyY, w, bodyH, App)
  elseif mode == "hooks" then
    drawHooks(S, x, bodyY, w, bodyH, App)
  else
    drawScripts(S, x, bodyY, w, bodyH, App)
  end
end

return Events
