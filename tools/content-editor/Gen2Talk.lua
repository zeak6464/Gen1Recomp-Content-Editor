-- Shared Gold talk helpers: allocate mod scripts, resolve Says text keys,
-- normalize jumptext / jumptextfaceplayer stubs for Maps + Events.

local State = require("State")

local Gen2Talk = {}

-- constants/battle_constants.asm — Lake of Rage Red Gyarados arm.
local VAR_BATTLETYPE = 3
local BATTLETYPE_FORCESHINY = 7

local SIMPLE_OPS = {
  jumptext = true,
  jumptextfaceplayer = true,
}

local function isForceShinyLoadvar(cmd)
  if type(cmd) ~= "table" or cmd.op ~= "loadvar" then return false end
  local var = tonumber(cmd.var) or tonumber(cmd.args and cmd.args[1])
  local val = tonumber(cmd.value) or tonumber(cmd.args and cmd.args[2])
  return var == VAR_BATTLETYPE and val == BATTLETYPE_FORCESHINY
end

function Gen2Talk.commands(S, scriptKey)
  if type(scriptKey) ~= "string" or scriptKey == "" then return nil end
  local proj = S.project and S.project.scripts and S.project.scripts[scriptKey]
  if type(proj) == "table" then return proj, true end
  local data = S.data and S.data.scripts and S.data.scripts[scriptKey]
  if type(data) == "table" then return data, false end
  return nil, false
end

function Gen2Talk.mirrorLive(S, scriptKey, cmds)
  if not S or not scriptKey then return end
  if S.data then
    S.data.scripts = S.data.scripts or {}
    S.data.scripts[scriptKey] = cmds
  end
end

-- Allocate a unique mod talk script + text body.
-- Returns scriptKey, textKey.
function Gen2Talk.allocTalk(S, mapId, kind, index, facePlayer)
  State.ensureProjectFields(S.project)
  S.project.scripts = S.project.scripts or {}
  S.project.text = S.project.text or {}
  mapId = mapId or "MAP"
  kind = kind or "OBJ"
  local n = tonumber(index) or 1
  local function keys(i)
    local scriptKey = string.format("mod:%s_%s_%d", mapId, kind, i)
    return scriptKey, scriptKey .. "_TEXT"
  end
  local scriptKey, textKey = keys(n)
  while S.project.scripts[scriptKey]
      or (S.data and S.data.scripts and S.data.scripts[scriptKey]) do
    n = n + 1
    scriptKey, textKey = keys(n)
  end
  local op = facePlayer and "jumptextfaceplayer" or "jumptext"
  local cmds = { { op = op, text = textKey } }
  S.project.scripts[scriptKey] = cmds
  if S.project.text[textKey] == nil then
    S.project.text[textKey] = "..."
  end
  Gen2Talk.mirrorLive(S, scriptKey, cmds)
  return scriptKey, textKey
end

function Gen2Talk.textKeyForScript(S, scriptKey)
  if type(scriptKey) ~= "string" or scriptKey == "" then return nil end
  local ok, Dialog = pcall(require, "Dialog")
  if ok and Dialog and Dialog.firstTextForScript then
    local tid = Dialog.firstTextForScript(S, scriptKey)
    if tid then return tid end
  end
  local cmds = Gen2Talk.commands(S, scriptKey)
  if type(cmds) == "table" then
    for _, cmd in ipairs(cmds) do
      if type(cmd) == "table" and type(cmd.text) == "string" and cmd.text ~= ""
          and SIMPLE_OPS[cmd.op] then
        return cmd.text
      end
    end
    for _, cmd in ipairs(cmds) do
      if type(cmd) == "table" and type(cmd.text) == "string" and cmd.text ~= "" then
        return cmd.text
      end
    end
  end
  return nil
end

-- True when cmds is empty, or a single jumptext / jumptextfaceplayer.
function Gen2Talk.isSimpleTalk(cmds)
  if type(cmds) ~= "table" then return false end
  if #cmds == 0 then return true end
  if #cmds ~= 1 then return false end
  local cmd = cmds[1]
  return type(cmd) == "table" and SIMPLE_OPS[cmd.op] == true
end

function Gen2Talk.facesPlayer(cmds)
  if type(cmds) ~= "table" or type(cmds[1]) ~= "table" then return true end
  return cmds[1].op == "jumptextfaceplayer"
end

-- Ensure project owns a simple talk script at scriptKey.
-- Preserves existing text key when possible.
function Gen2Talk.ensureSimpleTalk(S, scriptKey, facePlayer)
  if type(scriptKey) ~= "string" or scriptKey == "" then return nil, nil end
  State.ensureProjectFields(S.project)
  S.project.scripts = S.project.scripts or {}
  S.project.text = S.project.text or {}
  local cmds = S.project.scripts[scriptKey]
  local textKey = Gen2Talk.textKeyForScript(S, scriptKey)
  if not textKey then
    textKey = scriptKey .. "_TEXT"
  end
  if type(cmds) ~= "table" or not Gen2Talk.isSimpleTalk(cmds) or #cmds == 0 then
    local src = cmds
    if type(src) ~= "table" then
      src = S.data and S.data.scripts and S.data.scripts[scriptKey]
    end
    if type(src) == "table" then
      for _, cmd in ipairs(src) do
        if type(cmd) == "table" and type(cmd.text) == "string" and cmd.text ~= "" then
          textKey = cmd.text
          break
        end
      end
    end
  elseif type(cmds[1]) == "table" and type(cmds[1].text) == "string" then
    textKey = cmds[1].text
  end
  local op = facePlayer and "jumptextfaceplayer" or "jumptext"
  if facePlayer == nil then
    op = (type(cmds) == "table" and cmds[1] and cmds[1].op == "jumptext")
      and "jumptext" or "jumptextfaceplayer"
  end
  cmds = { { op = op, text = textKey } }
  S.project.scripts[scriptKey] = cmds
  if S.project.text[textKey] == nil then
    local body = S.data and S.data.text and S.data.text[textKey]
    S.project.text[textKey] = (type(body) == "string" and body) or "..."
  end
  Gen2Talk.mirrorLive(S, scriptKey, cmds)
  -- Keep step bags aligned when templates collapse a multi-op script.
  if S.project.scriptSteps and S.project.scriptSteps[scriptKey] then
    Gen2Talk.refreshStepsFromCmds(S, scriptKey)
  end
  return scriptKey, textKey
end

function Gen2Talk.setFacePlayer(S, scriptKey, face)
  local cmds = S.project and S.project.scripts and S.project.scripts[scriptKey]
  if type(cmds) ~= "table" or not Gen2Talk.isSimpleTalk(cmds) or #cmds == 0 then
    return Gen2Talk.ensureSimpleTalk(S, scriptKey, face and true or false)
  end
  local textKey = cmds[1].text or (scriptKey .. "_TEXT")
  cmds[1] = {
    op = face and "jumptextfaceplayer" or "jumptext",
    text = textKey,
  }
  Gen2Talk.mirrorLive(S, scriptKey, cmds)
  return scriptKey, textKey
end

function Gen2Talk.getSays(S, textKey)
  if type(textKey) ~= "string" or textKey == "" then return "" end
  local vanilla = S.data and S.data.text and S.data.text[textKey]
  local vanillaStr = type(vanilla) == "string" and vanilla or nil
  local bucket = S.project and S.project.text
  local proj = bucket and bucket[textKey]
  -- commitSteps used to stamp "..." over every Gold key; that hid ROM text.
  if type(proj) == "string" then
    if proj == "..." and vanillaStr and vanillaStr ~= "" and vanillaStr ~= "..." then
      bucket[textKey] = nil
      return vanillaStr
    end
    return proj
  end
  if vanillaStr then return vanillaStr end
  return ""
end

function Gen2Talk.setSays(S, textKey, body)
  if type(textKey) ~= "string" or textKey == "" then return end
  State.ensureProjectFields(S.project)
  S.project.text = S.project.text or {}
  S.project.text[textKey] = tostring(body or "")
  if S.data then
    S.data.text = S.data.text or {}
    S.data.text[textKey] = S.project.text[textKey]
  end
end

-- Deep-copy vanilla cmds into project.scripts[scriptKey].
function Gen2Talk.cloneCommands(S, scriptKey)
  if type(scriptKey) ~= "string" or scriptKey == "" then return nil end
  State.ensureProjectFields(S.project)
  S.project.scripts = S.project.scripts or {}
  if type(S.project.scripts[scriptKey]) == "table" then
    return S.project.scripts[scriptKey]
  end
  local src = S.data and S.data.scripts and S.data.scripts[scriptKey]
  local copy = {}
  if type(src) == "table" then
    for i, cmd in ipairs(src) do
      if type(cmd) == "table" then
        local row = {}
        for k, v in pairs(cmd) do row[k] = v end
        copy[i] = row
      else
        copy[i] = cmd
      end
    end
  end
  if #copy == 0 then
    local textKey = scriptKey .. "_TEXT"
    copy[1] = { op = "jumptextfaceplayer", text = textKey }
    S.project.text = S.project.text or {}
    if S.project.text[textKey] == nil then
      S.project.text[textKey] = "..."
    end
  end
  S.project.scripts[scriptKey] = copy
  Gen2Talk.mirrorLive(S, scriptKey, copy)
  return copy
end

-- Collect text keys from a command list (for advanced script body editing).
function Gen2Talk.collectTextKeys(S, scriptKey)
  local keys, seen = {}, {}
  local cmds = Gen2Talk.commands(S, scriptKey)
  if type(cmds) ~= "table" then return keys end
  for _, cmd in ipairs(cmds) do
    if type(cmd) == "table" and type(cmd.text) == "string" and cmd.text ~= ""
        and not seen[cmd.text] then
      seen[cmd.text] = true
      keys[#keys + 1] = cmd.text
    end
  end
  return keys
end

local function copyCmd(cmd)
  if type(cmd) ~= "table" then return cmd end
  local row = {}
  for k, v in pairs(cmd) do row[k] = v end
  return row
end

local function copySteps(steps)
  local out = {}
  for i, step in ipairs(steps or {}) do
    if type(step) == "table" then
      local s = {}
      for k, v in pairs(step) do
        if k == "cmd" and type(v) == "table" then
          s.cmd = copyCmd(v)
        else
          s[k] = v
        end
      end
      out[i] = s
    else
      out[i] = step
    end
  end
  return out
end

local function opcodeStep(cmd)
  return { kind = "opcode", cmd = copyCmd(cmd), op = cmd and cmd.op }
end

-- Decompile Gold opcode rows into editor steps. Unknown ops → opaque opcode.
function Gen2Talk.cmdsToSteps(cmds)
  local steps = {}
  if type(cmds) ~= "table" then return steps end
  local i = 1
  local n = #cmds
  while i <= n do
    local cmd = cmds[i]
    if type(cmd) ~= "table" or not cmd.op then
      i = i + 1
    elseif SIMPLE_OPS[cmd.op] then
      steps[#steps + 1] = {
        kind = "show_text",
        text = cmd.text or "",
        facePlayer = cmd.op == "jumptextfaceplayer",
        jumptext = true,
      }
      i = i + 1
    elseif cmd.op == "faceplayer" then
      steps[#steps + 1] = { kind = "face_player" }
      i = i + 1
    elseif cmd.op == "writetext" then
      local text = cmd.text or ""
      local j = i + 1
      if j <= n and type(cmds[j]) == "table" and cmds[j].op == "waitbutton" then
        j = j + 1
      end
      steps[#steps + 1] = { kind = "show_text", text = text, facePlayer = false }
      i = j
    elseif cmd.op == "yesorno" then
      steps[#steps + 1] = { kind = "ask", text = "", skipOnNo = true }
      i = i + 1
    elseif cmd.op == "setevent" then
      steps[#steps + 1] = {
        kind = "set_flag",
        flag = tostring(cmd.event or cmd.flag or 0),
        event = tonumber(cmd.event) or tonumber(cmd.flag),
      }
      i = i + 1
    elseif cmd.op == "clearevent" then
      steps[#steps + 1] = {
        kind = "clear_flag",
        flag = tostring(cmd.event or cmd.flag or 0),
        event = tonumber(cmd.event) or tonumber(cmd.flag),
      }
      i = i + 1
    elseif cmd.op == "giveitem" then
      steps[#steps + 1] = {
        kind = "give_item",
        item = cmd.item or "POTION",
        count = tonumber(cmd.quantity) or tonumber(cmd.count) or 1,
      }
      i = i + 1
    elseif cmd.op == "takeitem" then
      steps[#steps + 1] = {
        kind = "take_item",
        item = cmd.item or "POTION",
        count = tonumber(cmd.quantity) or tonumber(cmd.count) or 1,
      }
      i = i + 1
    elseif cmd.op == "givepoke" then
      steps[#steps + 1] = {
        kind = "give_pokemon",
        species = cmd.species,
        level = tonumber(cmd.level) or 5,
        item = cmd.item,
      }
      i = i + 1
    elseif cmd.op == "warp" or cmd.op == "warpfacing" then
      steps[#steps + 1] = {
        kind = "warp",
        map = cmd.map or cmd.destMap,
        x = tonumber(cmd.x) or 0,
        y = tonumber(cmd.y) or 0,
        facing = cmd.facing,
        warpOp = cmd.op,
      }
      i = i + 1
    elseif cmd.op == "loadwildmon" then
      local level = tonumber(cmd.level) or 5
      local species = cmd.species
      local j = i + 1
      local reload = false
      local forceShiny = false
      -- Fold a preceding `loadvar VAR_BATTLETYPE, FORCESHINY` into this step.
      if #steps > 0 then
        local prev = steps[#steps]
        if prev.kind == "opcode"
            and isForceShinyLoadvar(prev.cmd or prev) then
          table.remove(steps)
          forceShiny = true
        end
      end
      while j <= n and type(cmds[j]) == "table" do
        local ncmd = cmds[j]
        if ncmd.op == "startbattle" then
          j = j + 1
          if j <= n and type(cmds[j]) == "table"
              and cmds[j].op == "reloadmapafterbattle" then
            reload = true
            j = j + 1
          end
          break
        elseif ncmd.op == "loadvar" then
          if isForceShinyLoadvar(ncmd) then forceShiny = true end
          j = j + 1
        else
          break
        end
      end
      if j > i + 1 then
        steps[#steps + 1] = {
          kind = "wild_battle",
          species = species,
          level = level,
          reload = reload,
          forceShiny = forceShiny or nil,
        }
        i = j
      else
        steps[#steps + 1] = opcodeStep(cmd)
        i = i + 1
      end
    elseif cmd.op == "loadtrainer" then
      local class = tonumber(cmd.class)
      local member = tonumber(cmd.member) or 1
      local j = i + 1
      local reload = false
      if j <= n and type(cmds[j]) == "table" and cmds[j].op == "startbattle" then
        j = j + 1
        if j <= n and type(cmds[j]) == "table"
            and cmds[j].op == "reloadmapafterbattle" then
          reload = true
          j = j + 1
        end
        steps[#steps + 1] = {
          kind = "trainer_battle",
          class = class,
          member = member,
          party = member,
          reload = reload,
        }
        i = j
      else
        steps[#steps + 1] = opcodeStep(cmd)
        i = i + 1
      end
    elseif (cmd.op == "iftrue" or cmd.op == "iffalse" or cmd.op == "sjump"
        or cmd.op == "jump") and type(cmd.script) == "string" then
      steps[#steps + 1] = {
        kind = "jump_script",
        script = cmd.script,
        when = (cmd.op == "iffalse" and "false")
          or (cmd.op == "iftrue" and "true")
          or "always",
        op = cmd.op,
      }
      i = i + 1
    else
      steps[#steps + 1] = opcodeStep(cmd)
      i = i + 1
    end
  end
  return steps
end

-- Compile editor steps back to Gold opcode rows.
function Gen2Talk.stepsToCmds(S, scriptKey, steps)
  local cmds = {}
  if type(steps) ~= "table" then return cmds end
  local function ensureText(key, fallback)
    if type(key) ~= "string" or key == "" then
      key = (scriptKey or "mod:SCRIPT") .. "_TEXT"
    end
    if S and S.project then
      State.ensureProjectFields(S.project)
      S.project.text = S.project.text or {}
      local vanilla = S.data and S.data.text and S.data.text[key]
      local cur = S.project.text[key]
      if cur == "..." and type(vanilla) == "string"
          and vanilla ~= "" and vanilla ~= "..." then
        S.project.text[key] = nil
        cur = nil
      end
      if cur == nil and (type(vanilla) ~= "string" or vanilla == "") then
        S.project.text[key] = fallback or "..."
      end
    end
    return key
  end

  for _, step in ipairs(steps) do
    if type(step) ~= "table" then
      -- skip
    elseif step.kind == "opcode" and type(step.cmd) == "table" then
      cmds[#cmds + 1] = copyCmd(step.cmd)
    elseif step.kind == "show_text" then
      local text = ensureText(step.text, "...")
      if step.jumptext then
        local op = step.facePlayer == false and "jumptext" or "jumptextfaceplayer"
        cmds[#cmds + 1] = { op = op, text = text }
      else
        cmds[#cmds + 1] = { op = "writetext", text = text }
        cmds[#cmds + 1] = { op = "waitbutton" }
      end
    elseif step.kind == "face_player" then
      cmds[#cmds + 1] = { op = "faceplayer" }
    elseif step.kind == "ask" then
      if step.text and step.text ~= "" then
        local text = ensureText(step.text, "OK?")
        cmds[#cmds + 1] = { op = "writetext", text = text }
        cmds[#cmds + 1] = { op = "waitbutton" }
      end
      cmds[#cmds + 1] = { op = "yesorno" }
    elseif step.kind == "set_flag" then
      local ev = tonumber(step.event) or tonumber(step.flag) or 0
      cmds[#cmds + 1] = { op = "setevent", event = ev }
    elseif step.kind == "clear_flag" then
      local ev = tonumber(step.event) or tonumber(step.flag) or 0
      cmds[#cmds + 1] = { op = "clearevent", event = ev }
    elseif step.kind == "check_flag_skip" then
      local ev = tonumber(step.event) or tonumber(step.flag) or 0
      cmds[#cmds + 1] = { op = "checkevent", event = ev }
      if step.script then
        cmds[#cmds + 1] = { op = "iftrue", script = step.script }
      end
    elseif step.kind == "check_flag_missing" then
      local ev = tonumber(step.event) or tonumber(step.flag) or 0
      cmds[#cmds + 1] = { op = "checkevent", event = ev }
      if step.script then
        cmds[#cmds + 1] = { op = "iffalse", script = step.script }
      end
    elseif step.kind == "give_item" then
      cmds[#cmds + 1] = {
        op = "giveitem",
        item = step.item or "POTION",
        quantity = tonumber(step.count) or 1,
      }
    elseif step.kind == "take_item" then
      cmds[#cmds + 1] = {
        op = "takeitem",
        item = step.item or "POTION",
        quantity = tonumber(step.count) or 1,
      }
    elseif step.kind == "give_pokemon" or step.kind == "give_starter" then
      cmds[#cmds + 1] = {
        op = "givepoke",
        species = step.species or 1,
        level = tonumber(step.level) or 5,
        item = tonumber(step.item) or 0,
        trainer = 0,
      }
    elseif step.kind == "warp" then
      local op = step.warpOp or "warp"
      cmds[#cmds + 1] = {
        op = op,
        map = step.map,
        destMap = step.map,
        x = tonumber(step.x) or 0,
        y = tonumber(step.y) or 0,
        facing = step.facing,
      }
    elseif step.kind == "wild_battle" then
      if step.forceShiny then
        cmds[#cmds + 1] = {
          op = "loadvar",
          var = VAR_BATTLETYPE,
          args = { VAR_BATTLETYPE, BATTLETYPE_FORCESHINY },
        }
      end
      cmds[#cmds + 1] = {
        op = "loadwildmon",
        species = step.species or 1,
        level = tonumber(step.level) or 5,
      }
      cmds[#cmds + 1] = { op = "startbattle" }
      if step.reload ~= false then
        cmds[#cmds + 1] = { op = "reloadmapafterbattle" }
      end
    elseif step.kind == "trainer_battle" then
      cmds[#cmds + 1] = {
        op = "loadtrainer",
        class = tonumber(step.class) or 1,
        member = tonumber(step.member) or tonumber(step.party) or 1,
      }
      cmds[#cmds + 1] = { op = "startbattle" }
      if step.reload then
        cmds[#cmds + 1] = { op = "reloadmapafterbattle" }
      end
    elseif step.kind == "jump_script" then
      local when = step.when or "always"
      local op = step.op
        or (when == "false" and "iffalse")
        or (when == "true" and "iftrue")
        or "sjump"
      cmds[#cmds + 1] = { op = op, script = step.script or "" }
    elseif step.kind == "heal_party" then
      -- SpecialHealParty is special id 0 in many dumps; keep opaque-friendly.
      cmds[#cmds + 1] = { op = "special", id = 0 }
    elseif step.kind == "oneshot_gift" then
      local textKey = ensureText(step.textKey or (scriptKey .. "_TEXT"),
        step.text or "...")
      local afterKey = ensureText(step.afterKey or (scriptKey .. "_AFTER_TEXT"),
        step.after or "I already gave you one.")
      local alreadyKey = scriptKey .. "_Already"
      local ev = tonumber(step.event) or tonumber(step.flag) or 0
      if S and S.project then
        S.project.scripts = S.project.scripts or {}
        local already = {
          { op = "writetext", text = afterKey },
          { op = "waitbutton" },
          { op = "closetext" },
          { op = "end" },
        }
        S.project.scripts[alreadyKey] = already
        Gen2Talk.mirrorLive(S, alreadyKey, already)
      end
      cmds[#cmds + 1] = { op = "faceplayer" }
      cmds[#cmds + 1] = { op = "opentext" }
      cmds[#cmds + 1] = { op = "checkevent", event = ev }
      cmds[#cmds + 1] = { op = "iftrue", script = alreadyKey }
      cmds[#cmds + 1] = { op = "writetext", text = textKey }
      cmds[#cmds + 1] = { op = "waitbutton" }
      cmds[#cmds + 1] = {
        op = "giveitem",
        item = step.item or "POTION",
        quantity = tonumber(step.count) or 1,
      }
      cmds[#cmds + 1] = { op = "setevent", event = ev }
      cmds[#cmds + 1] = { op = "closetext" }
      cmds[#cmds + 1] = { op = "end" }
    else
      -- Unsupported high-level kind: skip rather than invent broken ops.
    end
  end
  return cmds
end

function Gen2Talk.getScriptSteps(S, scriptKey)
  if not (S and S.project and type(scriptKey) == "string") then return nil end
  State.ensureProjectFields(S.project)
  local bag = S.project.scriptSteps[scriptKey]
  if type(bag) == "table" and type(bag.steps) == "table" then return bag end
  return nil
end

-- Own cmds (if needed), decompile into scriptSteps, return the bag.
function Gen2Talk.ensureScriptSteps(S, scriptKey, mapId)
  if type(scriptKey) ~= "string" or scriptKey == "" then return nil end
  State.ensureProjectFields(S.project)
  S.project.scriptSteps = S.project.scriptSteps or {}
  local bag = S.project.scriptSteps[scriptKey]
  if type(bag) == "table" and type(bag.steps) == "table" then
    if mapId and not bag.mapId then bag.mapId = mapId end
    return bag
  end
  local cmds = Gen2Talk.cloneCommands(S, scriptKey)
  local steps = Gen2Talk.cmdsToSteps(cmds)
  if #steps == 0 then
    steps[1] = {
      kind = "show_text",
      text = scriptKey .. "_TEXT",
      facePlayer = true,
      jumptext = true,
    }
  end
  bag = {
    mapId = mapId,
    scriptKey = scriptKey,
    steps = steps,
  }
  S.project.scriptSteps[scriptKey] = bag
  return bag
end

-- Recompile scriptSteps → project.scripts and mirror live data.
function Gen2Talk.commitSteps(S, scriptKey)
  if not (S and S.project and type(scriptKey) == "string") then return nil end
  local bag = Gen2Talk.getScriptSteps(S, scriptKey)
  if not bag then return nil end
  local cmds = Gen2Talk.stepsToCmds(S, scriptKey, bag.steps)
  State.ensureProjectFields(S.project)
  S.project.scripts[scriptKey] = cmds
  Gen2Talk.mirrorLive(S, scriptKey, cmds)
  return cmds
end

-- After surgical opcode edits (Maps loadtrainer / loadwildmon), refresh steps.
function Gen2Talk.refreshStepsFromCmds(S, scriptKey)
  if not (S and S.project and type(scriptKey) == "string") then return nil end
  State.ensureProjectFields(S.project)
  local cmds = S.project.scripts and S.project.scripts[scriptKey]
  if type(cmds) ~= "table" then
    cmds = Gen2Talk.commands(S, scriptKey)
  end
  if type(cmds) ~= "table" then return nil end
  local bag = S.project.scriptSteps[scriptKey]
  local mapId = bag and bag.mapId
  S.project.scriptSteps[scriptKey] = {
    mapId = mapId,
    scriptKey = scriptKey,
    steps = Gen2Talk.cmdsToSteps(cmds),
  }
  return S.project.scriptSteps[scriptKey]
end

-- Recompile every scriptSteps bag into project.scripts (Save path).
function Gen2Talk.commitAllSteps(S)
  if not (S and S.project) then return 0 end
  State.ensureProjectFields(S.project)
  local n = 0
  for scriptKey, bag in pairs(S.project.scriptSteps or {}) do
    if type(scriptKey) == "string" and type(bag) == "table"
        and type(bag.steps) == "table" then
      Gen2Talk.commitSteps(S, scriptKey)
      n = n + 1
    end
  end
  return n
end

function Gen2Talk.copySteps(steps)
  return copySteps(steps)
end

return Gen2Talk
