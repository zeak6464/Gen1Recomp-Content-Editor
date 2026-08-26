-- Index of map object/sign TEXT_* bindings and their talk scripts
-- (mod overrides, vanilla MapScripts rows, or plain dialog / engine fallbacks).
-- Gold: pins are object/bgEvent scriptKey → opcode lists in data.scripts.

local State = require("State")
local ModWriter = require("ModWriter")
local Generation = require("Generation")
local Gen2Talk = require("Gen2Talk")

local TalkIndex = {}

local scriptsOk = false
local scriptsTried = false

function TalkIndex.ensureScripts()
  if scriptsTried then return scriptsOk end
  scriptsTried = true
  local ok = pcall(require, "data.scripts.init")
  scriptsOk = ok
  return ok
end

local function mapRecord(S, mapId)
  if S.project and S.project.maps and S.project.maps[mapId] then
    return S.project.maps[mapId], true
  end
  local live = Generation.dataMaps(S)[mapId]
  if live then return live, false end
  return nil, false
end

local function pointerEntry(S, mapId, textId)
  if not textId then return nil end
  local label = State.mapLabel(S, mapId)
  local proj = S.project and S.project.text_pointers and S.project.text_pointers[label]
  if proj and proj[textId] then return proj[textId], true end
  local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
  return base and base[textId], false
end

local function resolveBody(S, strId)
  if not strId then return "" end
  if S.project and S.project.text and S.project.text[strId] ~= nil then
    return S.project.text[strId]
  end
  if S.data and S.data.text and S.data.text[strId] ~= nil then
    return S.data.text[strId]
  end
  return ""
end

local function findObject(S, mapId, textId)
  local map = mapRecord(S, mapId)
  if not map then return nil, nil end
  for i, obj in ipairs(map.objects or {}) do
    if obj.text == textId then return obj, i end
  end
  for i, sign in ipairs(map.signs or {}) do
    if sign.text == textId then return sign, i end
  end
  return nil, nil
end

local function talkRows(mapId, textId)
  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if not ok or not MapScripts then return nil end
  local rows = MapScripts.talkScript(mapId, textId)
  if rows == nil then rows = MapScripts.baseTalk(mapId, textId) end
  return rows
end

local function findByScriptKey(S, mapId, scriptKey)
  local map = mapRecord(S, mapId)
  if not map or not scriptKey then return nil, nil, nil end
  for i, obj in ipairs(map.objects or {}) do
    if obj.scriptKey == scriptKey then return obj, i, "object" end
  end
  for i, ev in ipairs(map.bgEvents or {}) do
    if ev.scriptKey == scriptKey then return ev, i, "bg" end
  end
  for i, ev in ipairs(map.coordEvents or {}) do
    if ev.scriptKey == scriptKey then return ev, i, "coord" end
  end
  return nil, nil, nil
end

local function gen2ScriptCommands(S, scriptKey)
  if not scriptKey or scriptKey == "" then return nil end
  local proj = S.project and S.project.scripts and S.project.scripts[scriptKey]
  if type(proj) == "table" then return proj end
  local data = S.data and S.data.scripts and S.data.scripts[scriptKey]
  if type(data) == "table" then return data end
  return nil
end

local function sourceBadgeGen2(S, mapId, scriptKey)
  if S.project and S.project.scripts
      and type(S.project.scripts[scriptKey]) == "table" then
    return "mod"
  end
  local obj = findByScriptKey(S, mapId, scriptKey)
  if obj then
    if obj.item then return "item" end
    if obj.trainerClass or obj.trainer or obj.trainerType then return "trainer" end
    if obj.pokemon or obj.species then return "pokemon" end
  end
  local cmds = gen2ScriptCommands(S, scriptKey)
  if type(cmds) == "table" and #cmds > 0 then return "script" end
  return "empty"
end

local function sourceBadge(S, mapId, textId)
  if Generation.isGen2(S) then
    return sourceBadgeGen2(S, mapId, textId)
  end
  local key = mapId .. "/" .. textId
  if S.project and S.project.talkScripts and S.project.talkScripts[key] then
    return "mod"
  end
  local rows = talkRows(mapId, textId)
  if type(rows) == "function" then return "lua" end
  if type(rows) == "table" and #rows > 0 then return "script" end
  local obj = findObject(S, mapId, textId)
  if obj then
    if obj.item then return "item" end
    if obj.trainerClass or obj.trainer then return "trainer" end
    if obj.pokemon or obj.species then return "pokemon" end
  end
  local ptr = pointerEntry(S, mapId, textId)
  if ptr then
    if ptr.mart then return "shop" end
    if ptr.nurse then return "nurse" end
    if ptr.pc then return "pc" end
    if ptr.cableClub then return "cable" end
    if ptr.asm then return "asm" end
    if ptr.text then
      local body = resolveBody(S, ptr.text)
      if type(body) == "string" and body ~= "" then return "text" end
    end
  end
  return "empty"
end

-- Virtual "maps" in Events → SCRIPTS so std / phone / leftover scripts
-- are editable without being attached to an NPC.
local CATALOG = {
  { id = "_STD", label = "Std scripts", pins = "STD SCRIPTS" },
  { id = "_PHONE", label = "Phone scripts", pins = "PHONE SCRIPTS" },
  { id = "_DECO", label = "Decor scripts", pins = "DECOR SCRIPTS" },
  { id = "_SPECIAL", label = "Special calls", pins = "SPECIAL CALLS" },
  { id = "_OTHER", label = "Other scripts", pins = "OTHER SCRIPTS" },
}

local SKIP_SCRIPT_META = {
  movements = true, generation = true, source = true, order = true,
  byId = true, labels = true,
}

function TalkIndex.isCatalogMap(id)
  if type(id) ~= "string" then return false end
  return id:sub(1, 1) == "_"
end

function TalkIndex.catalogLabel(id)
  for i = 1, #CATALOG do
    if CATALOG[i].id == id then return CATALOG[i].label end
  end
  return nil
end

function TalkIndex.catalogPinCaption(id)
  for i = 1, #CATALOG do
    if CATALOG[i].id == id then return CATALOG[i].pins end
  end
  return "OBJECT EVENTS"
end

local function isScriptBody(v)
  if type(v) ~= "table" then return false end
  local first = v[1]
  return type(first) == "table" and type(first.op) == "string"
end

local function scriptTable(S)
  return S.data and (S.data.scripts or S.data.gen2Scripts) or {}
end

local function stdTable(S)
  return S.data and (S.data.gen2StdScripts or S.data.std_scripts) or {}
end

local function eventTables(S)
  return S.data and (S.data.gen2EventTables or S.data.events) or {}
end

local function markUsed(used, key)
  if type(key) == "string" and key ~= "" then used[key] = true end
end

local function collectCatalog(S, mapId)
  local entries, seen = {}, {}
  local function add(scriptKey, kind, label, index)
    if type(scriptKey) ~= "string" or scriptKey == "" then return end
    local pinKey = tostring(kind) .. ":" .. tostring(index) .. ":" .. scriptKey
    if seen[pinKey] then return end
    seen[pinKey] = true
    local src = sourceBadgeGen2(S, mapId, scriptKey)
    entries[#entries + 1] = {
      key = mapId .. "/" .. scriptKey,
      mapId = mapId,
      textId = scriptKey,
      scriptKey = scriptKey,
      kind = kind,
      index = index,
      label = label or scriptKey,
      source = src,
      attached = src ~= "empty",
    }
  end

  if mapId == "_STD" then
    local std = stdTable(S)
    local order = std.order or {}
    local scripts = std.scripts or {}
    local listed = {}
    for i, name in ipairs(order) do
      local row = scripts[name]
      local key = row and row.key
      if type(key) == "string" then
        listed[name] = true
        add(key, "std", name, i)
      end
    end
    local extra = {}
    for name, row in pairs(scripts) do
      if type(name) == "string" and not listed[name]
          and type(row) == "table" and type(row.key) == "string" then
        extra[#extra + 1] = name
      end
    end
    table.sort(extra)
    for i, name in ipairs(extra) do
      add(scripts[name].key, "std", name, 1000 + i)
    end
  elseif mapId == "_PHONE" then
    local ev = eventTables(S)
    local phone = ev.phone or {}
    local ids = {}
    for k in pairs(phone) do ids[#ids + 1] = k end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(ids) do
      local row = phone[k]
      if type(row) == "table" then
        local name = row.contact or ("PHONE_" .. tostring(k))
        add(row.callee, "phone", name .. " callee", k)
        add(row.caller, "phone", name .. " caller", k)
      end
    end
    local named = ev.phoneScripts or {}
    local labels = {}
    for lab in pairs(named) do labels[#labels + 1] = lab end
    table.sort(labels)
    for _, lab in ipairs(labels) do
      local row = named[lab]
      add(row and row.script, "phone", lab, lab)
    end
  elseif mapId == "_DECO" then
    local deco = eventTables(S).decorations or {}
    local names = {}
    for k in pairs(deco) do
      if type(k) == "string" then names[#names + 1] = k end
    end
    table.sort(names)
    for i, name in ipairs(names) do
      local row = deco[name]
      if type(row) == "table" then
        add(row.script, "deco", name, i)
        for pi, poster in ipairs(row.posters or {}) do
          if type(poster) == "table" then
            add(poster.script, "deco", name .. " poster " .. pi, pi)
          end
        end
      end
    end
  elseif mapId == "_SPECIAL" then
    local calls = eventTables(S).specialCalls or {}
    for i, row in ipairs(calls) do
      if type(row) == "table" then
        add(row.script, "special", row.call or ("SPECIAL_" .. i), i)
      end
    end
  elseif mapId == "_OTHER" then
    local used = {}
    local maps = Generation.dataMaps(S)
    for _, def in pairs(maps) do
      if type(def) == "table" then
        for _, obj in ipairs(def.objects or {}) do
          markUsed(used, obj.scriptKey)
        end
        for _, ev in ipairs(def.bgEvents or {}) do
          markUsed(used, ev.scriptKey)
        end
        for _, ev in ipairs(def.coordEvents or {}) do
          markUsed(used, ev.scriptKey)
        end
        for _, sc in pairs(def.sceneScripts or {}) do
          if type(sc) == "table" then markUsed(used, sc.scriptKey) end
        end
        for _, cb in ipairs(def.callbacks or {}) do
          markUsed(used, cb.scriptKey)
        end
      end
    end
    local std = stdTable(S).scripts or {}
    for _, row in pairs(std) do
      if type(row) == "table" then markUsed(used, row.key) end
    end
    local ev = eventTables(S)
    for _, row in pairs(ev.phone or {}) do
      if type(row) == "table" then
        markUsed(used, row.callee)
        markUsed(used, row.caller)
      end
    end
    for _, row in pairs(ev.phoneScripts or {}) do
      if type(row) == "table" then markUsed(used, row.script) end
    end
    for _, row in ipairs(ev.specialCalls or {}) do
      if type(row) == "table" then markUsed(used, row.script) end
    end
    for _, row in pairs(ev.decorations or {}) do
      if type(row) == "table" then
        markUsed(used, row.script)
        for _, poster in ipairs(row.posters or {}) do
          if type(poster) == "table" then markUsed(used, poster.script) end
        end
      end
    end
    local keys, seenKeys = {}, {}
    local function consider(k, v)
      if type(k) == "string" and not SKIP_SCRIPT_META[k]
          and not used[k] and not seenKeys[k] and isScriptBody(v) then
        seenKeys[k] = true
        keys[#keys + 1] = k
      end
    end
    local scripts = scriptTable(S)
    for k, v in pairs(scripts) do consider(k, v) end
    if S.project and type(S.project.scripts) == "table" then
      for k, v in pairs(S.project.scripts) do consider(k, v) end
    end
    table.sort(keys)
    for i, k in ipairs(keys) do
      add(k, "other", k, i)
    end
  end

  table.sort(entries, function(a, b)
    if (a.label or "") ~= (b.label or "") then
      return tostring(a.label) < tostring(b.label)
    end
    return tostring(a.textId) < tostring(b.textId)
  end)
  return entries
end

local function collectGen2(S, mapId)
  if TalkIndex.isCatalogMap(mapId) then
    return collectCatalog(S, mapId)
  end
  local entries, seen = {}, {}
  -- Dedupe by kind+index+scriptKey so two objects never share one pin slot.
  local function add(scriptKey, kind, label, index)
    if not scriptKey or scriptKey == "" then return end
    local pinKey = string.format("%s:%s:%s", tostring(kind), tostring(index), scriptKey)
    if seen[pinKey] then return end
    seen[pinKey] = true
    local src = sourceBadgeGen2(S, mapId, scriptKey)
    entries[#entries + 1] = {
      key = mapId .. "/" .. scriptKey,
      mapId = mapId,
      textId = scriptKey,
      scriptKey = scriptKey,
      kind = kind,
      index = index,
      label = label or scriptKey,
      source = src,
      attached = src ~= "empty",
    }
  end
  local map = mapRecord(S, mapId)
  if map then
    for i, obj in ipairs(map.objects or {}) do
      if type(obj.scriptKey) == "string" and obj.scriptKey ~= "" then
        add(obj.scriptKey, "object",
          string.format("NPC #%d %s", obj.index or i, obj.sprite or ""), i)
      end
    end
    for i, ev in ipairs(map.bgEvents or {}) do
      if type(ev.scriptKey) == "string" and ev.scriptKey ~= "" then
        add(ev.scriptKey, "bg",
          string.format("BG #%d %s", i, ev.kind or "event"), i)
      end
    end
    for i, ev in ipairs(map.coordEvents or {}) do
      if type(ev.scriptKey) == "string" and ev.scriptKey ~= "" then
        add(ev.scriptKey, "coord",
          string.format("Coord #%d", i), i)
      end
    end
    local scenes = map.sceneScripts or map.scenes
    if type(scenes) == "table" then
      local ids = {}
      for k in pairs(scenes) do ids[#ids + 1] = k end
      table.sort(ids, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then return na < nb end
        return tostring(a) < tostring(b)
      end)
      for _, k in ipairs(ids) do
        local sc = scenes[k]
        local key = type(sc) == "table" and (sc.scriptKey or sc.script) or sc
        if type(key) == "string" then
          add(key, "scene", "Scene " .. tostring(k), k)
        end
      end
    end
    for i, cb in ipairs(map.callbacks or {}) do
      local key = cb.scriptKey or cb.script
      if type(key) == "string" then
        add(key, "callback",
          tostring(cb.callback or ("Callback #" .. i)), i)
      end
    end
  end
  -- Orphan mod talk scripts for this map (Events "+ Talk script" without attach).
  local prefix = "mod:" .. tostring(mapId) .. "_"
  if S.project and type(S.project.scripts) == "table" then
    local attached = {}
    for _, e in ipairs(entries) do
      if e.scriptKey then attached[e.scriptKey] = true end
    end
    local orphans = {}
    for sk in pairs(S.project.scripts) do
      if type(sk) == "string" and sk:sub(1, #prefix) == prefix
          and not attached[sk] then
        orphans[#orphans + 1] = sk
      end
    end
    table.sort(orphans)
    for _, sk in ipairs(orphans) do
      add(sk, "mod", "Talk " .. sk:gsub("^mod:", ""), nil)
    end
  end
  table.sort(entries, function(a, b)
    local rank = {
      object = 0, bg = 1, coord = 2, scene = 3, callback = 4, mod = 5,
    }
    local ao = rank[a.kind] or 6
    local bo = rank[b.kind] or 6
    if ao ~= bo then return ao < bo end
    if (a.index or 0) ~= (b.index or 0) then
      return (a.index or 0) < (b.index or 0)
    end
    return a.textId < b.textId
  end)
  return entries
end

-- Collect every talk-capable pin for a map: objects, signs, text_pointers,
-- vanilla talk keys, and mod talkScripts.  Gold: scriptKey pins only.
function TalkIndex.collect(S, mapId)
  if not mapId or mapId == "" then return {} end
  if Generation.isGen2(S) then return collectGen2(S, mapId) end
  local entries, seen = {}, {}

  local function add(textId, kind, label, index)
    if not textId or textId == "" then return end
    -- Objects/signs: unique per entity. Pointer/script/mod: unique per TEXT_*.
    local pinKey = (index ~= nil)
      and string.format("%s:%s:%s", tostring(kind), tostring(index), textId)
      or ("id:" .. textId)
    if seen[pinKey] then return end
    seen[pinKey] = true
    local src = sourceBadge(S, mapId, textId)
    entries[#entries + 1] = {
      key = mapId .. "/" .. textId,
      mapId = mapId,
      textId = textId,
      kind = kind,
      index = index,
      label = label or textId,
      source = src,
      attached = src ~= "empty",
    }
  end

  local map = mapRecord(S, mapId)
  if map then
    for i, obj in ipairs(map.objects or {}) do
      local tid = obj.text or ("TEXT_" .. mapId .. "_OBJ" .. i)
      add(tid, "object", string.format("NPC #%d %s", obj.index or i, obj.sprite or ""), i)
    end
    for i, sign in ipairs(map.signs or {}) do
      local tid = sign.text or ("TEXT_" .. mapId .. "_SIGN" .. i)
      add(tid, "sign", string.format("Sign #%d", i), i)
    end
  end

  local label = State.mapLabel(S, mapId)
  local function addPtrTable(ptrs)
    if not ptrs then return end
    local ids = {}
    for textId in pairs(ptrs) do ids[#ids + 1] = textId end
    table.sort(ids)
    for _, textId in ipairs(ids) do
      local entry = ptrs[textId]
      add(textId, "pointer", (entry and entry.label) or textId, nil)
    end
  end
  addPtrTable(S.data and S.data.text_pointers and S.data.text_pointers[label])
  addPtrTable(S.project and S.project.text_pointers and S.project.text_pointers[label])

  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if ok and MapScripts then
    local view = MapScripts.get(mapId)
    if view and view.talk then
      local ids = {}
      for textId in pairs(view.talk) do ids[#ids + 1] = textId end
      table.sort(ids)
      for _, textId in ipairs(ids) do
        add(textId, "script", textId, nil)
      end
    end
  end

  if S.project and S.project.talkScripts then
    local prefix = mapId .. "/"
    for key, script in pairs(S.project.talkScripts) do
      if key:sub(1, #prefix) == prefix then
        local tid = script.textId or key:sub(#prefix + 1)
        add(tid, "mod", tid, nil)
      end
    end
  end

  table.sort(entries, function(a, b)
    local ao = a.kind == "object" and 0 or a.kind == "sign" and 1 or 2
    local bo = b.kind == "object" and 0 or b.kind == "sign" and 1 or 2
    if ao ~= bo then return ao < bo end
    if (a.index or 0) ~= (b.index or 0) then
      return (a.index or 0) < (b.index or 0)
    end
    return a.textId < b.textId
  end)
  return entries
end

local function catalogHasPins(S, mapId)
  if mapId == "_STD" then
    local scripts = stdTable(S).scripts
    return type(scripts) == "table" and next(scripts) ~= nil
  elseif mapId == "_PHONE" then
    local ev = eventTables(S)
    return (type(ev.phone) == "table" and next(ev.phone) ~= nil)
      or (type(ev.phoneScripts) == "table" and next(ev.phoneScripts) ~= nil)
  elseif mapId == "_DECO" then
    local deco = eventTables(S).decorations
    return type(deco) == "table" and next(deco) ~= nil
  elseif mapId == "_SPECIAL" then
    local calls = eventTables(S).specialCalls
    return type(calls) == "table" and calls[1] ~= nil
  elseif mapId == "_OTHER" then
    local scripts = scriptTable(S)
    return type(scripts) == "table" and next(scripts) ~= nil
  end
  return false
end

function TalkIndex.allMapIds(S)
  local seen, ids = {}, {}
  local function add(id)
    if id and not seen[id] and not TalkIndex.isCatalogMap(id) then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.project then
    for id in pairs(S.project.maps or {}) do add(id) end
    for key in pairs(S.project.talkScripts or {}) do
      add(key:match("^([^/]+)/"))
    end
  end
  for _, id in ipairs(Generation.listedMapIds(S)) do add(id) end
  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if ok and MapScripts then
    -- Prefer maps that actually have objects or scripts; still include all
    -- data maps so empty indoor maps stay browsable.
  end
  table.sort(ids)
  if Generation.isGen2(S) then
    local head = {}
    for i = 1, #CATALOG do
      local cid = CATALOG[i].id
      if catalogHasPins(S, cid) then head[#head + 1] = cid end
    end
    for i = 1, #ids do head[#head + 1] = ids[i] end
    return head
  end
  return ids
end

local function summarizeGen2Op(cmd)
  if type(cmd) ~= "table" then return tostring(cmd) end
  local op = tostring(cmd.op or "?")
  local bits = { op }
  if cmd.text then bits[#bits + 1] = "text=" .. tostring(cmd.text) end
  if cmd.script then bits[#bits + 1] = "→" .. tostring(cmd.script) end
  if cmd.flag then bits[#bits + 1] = "flag=" .. tostring(cmd.flag) end
  if cmd.item then bits[#bits + 1] = "item=" .. tostring(cmd.item) end
  if cmd.special then bits[#bits + 1] = "special=" .. tostring(cmd.special) end
  return table.concat(bits, " ")
end

-- Build editor steps for a TEXT_* (does not write the project).
-- Gold: scriptSteps bag when owned; else opcode preview for scriptKey.
function TalkIndex.resolveSteps(S, mapId, textId)
  if Generation.isGen2(S) then
    local bag = Gen2Talk.getScriptSteps(S, textId)
    if bag and type(bag.steps) == "table" then
      return bag.steps, {
        owned = true,
        source = "mod",
        readOnly = false,
        gen2 = true,
        editable = true,
        scriptSteps = true,
      }
    end
    local cmds, ownedFlag = Gen2Talk.commands(S, textId)
    local owned = ownedFlag == true
      or (S.project and S.project.scripts
        and type(S.project.scripts[textId]) == "table")
    -- Owned without scriptSteps yet: decompile live for display, still readOnly
    -- until Override / ensureScriptSteps (keeps vanilla preview honest).
    local steps = Gen2Talk.cmdsToSteps(cmds)
    if #steps == 0 then
      steps[1] = {
        kind = "opcode",
        cmd = { op = "end" },
        op = "end",
      }
    end
    -- For read-only vanilla, show opcode notes like before when not decompiled
    -- into high-level kinds only — cmdsToSteps already yields mixed steps.
    local simple = Gen2Talk.isSimpleTalk(cmds)
    return steps, {
      owned = owned,
      source = owned and "mod" or "script",
      readOnly = not owned,
      gen2 = true,
      simpleTalk = simple,
      editable = owned,
      needsScriptSteps = owned and true or false,
    }
  end

  local key = mapId .. "/" .. textId
  local owned = S.project and S.project.talkScripts and S.project.talkScripts[key]
  if owned and type(owned.steps) == "table" then
    return owned.steps, { owned = true, source = "mod" }
  end

  local rows = talkRows(mapId, textId)
  if type(rows) == "function" then
    return {
      { kind = "raw", note = "Lua function handler (edit in Code / data/scripts)" },
    }, { owned = false, source = "lua", readOnly = true }
  end
  if type(rows) == "table" and #rows > 0 then
    return ModWriter.rowsToSteps(rows), {
      owned = false, source = "script", readOnly = true, rowCount = #rows,
    }
  end

  local obj = findObject(S, mapId, textId)
  if obj and obj.item then
    return {
      { kind = "raw", note = "Engine item-ball: " .. tostring(obj.item) },
    }, { owned = false, source = "item", readOnly = true }
  end
  if obj and (obj.trainerClass or obj.trainer) then
    return {
      {
        kind = "raw",
        note = "Engine trainer: " .. tostring(obj.trainerClass or obj.trainer)
          .. " party " .. tostring(obj.trainerParty or 1),
      },
    }, { owned = false, source = "trainer", readOnly = true }
  end
  if obj and (obj.pokemon or obj.species) then
    return {
      {
        kind = "raw",
        note = "Engine fixed wild: " .. tostring(obj.pokemon or obj.species)
          .. " Lv" .. tostring(obj.level or "?"),
      },
    }, { owned = false, source = "pokemon", readOnly = true }
  end

  local ptr = pointerEntry(S, mapId, textId)
  if ptr and ptr.asm then
    return {
      { kind = "raw", note = "ASM/engine text (ported script may live under data/scripts)" },
    }, { owned = false, source = "asm", readOnly = true }
  end
  if ptr and (ptr.mart or ptr.nurse or ptr.pc or ptr.cableClub) then
    local role = ptr.mart and "shop" or ptr.nurse and "nurse" or ptr.pc and "pc" or "cable"
    return {
      { kind = "raw", note = "Engine " .. role .. " interaction" },
    }, { owned = false, source = role, readOnly = true }
  end
  if ptr and ptr.text then
    local body = resolveBody(S, ptr.text)
    if type(body) == "string" and body ~= "" then
      return {
        { kind = "show_text", text = body },
      }, { owned = false, source = "text", readOnly = true }
    end
  end

  return {}, { owned = false, source = "empty", readOnly = true }
end

-- Display-only resolveSteps notes ("Engine item-ball: …") must not become
-- ScriptRunner rows. Build real editable steps for Clone / Save.
local function copyStep(step)
  local sc = {}
  for k, v in pairs(step) do sc[k] = v end
  return sc
end

local function stepsFromEngineObject(S, mapId, textId, src)
  local obj = findObject(S, mapId, textId)
  if not obj then return nil end
  if src == "item" and obj.item and obj.item ~= "0" and obj.item ~= 0 then
    local out = {
      { kind = "give_item", item = tostring(obj.item), count = 1 },
    }
    if type(obj.name) == "string" and obj.name ~= "" then
      out[#out + 1] = {
        kind = "raw",
        note = ("hide_object %s %s"):format(mapId, obj.name),
        row = { "hide_object", mapId, obj.name },
      }
    end
    return out
  end
  if src == "trainer" and (obj.trainerClass or obj.trainer) then
    return {
      {
        kind = "trainer_battle",
        trainer = tostring(obj.trainerClass or obj.trainer),
        party = tonumber(obj.trainerParty) or 1,
      },
    }
  end
  if src == "pokemon" and (obj.pokemon or obj.species) then
    return {
      {
        kind = "wild_battle",
        species = tostring(obj.pokemon or obj.species),
        level = tonumber(obj.level) or 5,
      },
    }
  end
  return nil
end

-- True for read-only placeholder notes that are not real engine verbs.
local function isPlaceholderRawNote(note)
  if type(note) ~= "string" then return false end
  return note:match("^Engine%s") ~= nil
    or note:match("^Lua%s") ~= nil
    or note:match("^ASM/") ~= nil
    or note:match("^ASM%s") ~= nil
end

-- Convert a single bad "Engine …" raw step into real steps (or nil).
local function expandPlaceholderRaw(S, mapId, textId, step)
  local note = step and step.note
  if type(note) ~= "string" then return nil end
  local item = note:match("^Engine item%-ball:%s*(%S+)")
  if item and item ~= "0" then
    return stepsFromEngineObject(S, mapId, textId, "item")
      or { { kind = "give_item", item = item, count = 1 } }
  end
  local trainer, party = note:match("^Engine trainer:%s*(%S+)%s+party%s+(%d+)")
  if trainer then
    return {
      {
        kind = "trainer_battle",
        trainer = trainer,
        party = tonumber(party) or 1,
      },
    }
  end
  local species, level = note:match("^Engine fixed wild:%s*(%S+)%s+Lv(%d+)")
  if species then
    return {
      {
        kind = "wild_battle",
        species = species,
        level = tonumber(level) or 5,
      },
    }
  end
  if isPlaceholderRawNote(note) then
    return { { kind = "show_text", text = "Hello!" } }
  end
  return nil
end

-- Repair owned talkScripts that still hold display-only Engine/Lua notes.
-- Returns true if steps were rewritten.
function TalkIndex.repairPlaceholderSteps(S, mapId, textId, script)
  if type(script) ~= "table" or type(script.steps) ~= "table" then
    return false
  end
  local changed = false
  local out = {}
  for _, step in ipairs(script.steps) do
    if (step.kind or "raw") == "raw" and isPlaceholderRawNote(step.note) then
      local repl = expandPlaceholderRaw(S, mapId, textId, step)
      if repl then
        for _, r in ipairs(repl) do out[#out + 1] = r end
        changed = true
      else
        out[#out + 1] = copyStep(step)
      end
    else
      out[#out + 1] = copyStep(step)
    end
  end
  if changed then script.steps = out end
  return changed
end

local function editableStepsForClone(S, mapId, textId, steps, meta)
  local src = meta and meta.source
  if src == "item" or src == "trainer" or src == "pokemon" then
    local built = stepsFromEngineObject(S, mapId, textId, src)
    if built then return built end
  end
  if src == "lua" or src == "asm" or src == "shop" or src == "nurse"
      or src == "pc" or src == "cable" then
    return { { kind = "show_text", text = "Hello!" } }
  end
  local copy = {}
  for _, step in ipairs(steps or {}) do
    if (step.kind or "raw") == "raw" and isPlaceholderRawNote(step.note) then
      local repl = expandPlaceholderRaw(S, mapId, textId, step)
      if repl then
        for _, r in ipairs(repl) do copy[#copy + 1] = r end
      end
    else
      copy[#copy + 1] = copyStep(step)
    end
  end
  if #copy == 0 then
    copy[1] = { kind = "show_text", text = "Hello!" }
  end
  return copy
end

-- Copy current resolved steps into project.talkScripts (mod override on Save).
-- Gold: clone opcodes + decompile into project.scriptSteps[scriptKey].
function TalkIndex.cloneToProject(S, mapId, textId)
  if Generation.isGen2(S) then
    Gen2Talk.cloneCommands(S, textId)
    local bag = Gen2Talk.ensureScriptSteps(S, textId, mapId)
    Gen2Talk.commitSteps(S, textId)
    return bag
  end
  State.ensureProjectFields(S.project)
  local key = mapId .. "/" .. textId
  if S.project.talkScripts[key] then
    TalkIndex.repairPlaceholderSteps(S, mapId, textId, S.project.talkScripts[key])
    return S.project.talkScripts[key]
  end
  local steps, meta = TalkIndex.resolveSteps(S, mapId, textId)
  local copy = editableStepsForClone(S, mapId, textId, steps, meta)
  local script = {
    mapId = mapId,
    textId = textId,
    steps = copy,
    _fromVanilla = meta and meta.source == "script" or nil,
  }
  S.project.talkScripts[key] = script
  return script
end

function TalkIndex.sourceLabel(src)
  local labels = {
    mod = "MOD",
    script = "SCRIPT",
    lua = "LUA",
    text = "TEXT",
    asm = "ASM",
    item = "ITEM",
    trainer = "TRAINER",
    pokemon = "MON",
    shop = "SHOP",
    nurse = "NURSE",
    pc = "PC",
    cable = "CABLE",
    std = "STD",
    phone = "PHONE",
    deco = "DECO",
    special = "CALL",
    scene = "SCENE",
    callback = "CB",
    other = "OTHER",
    empty = "-",
  }
  return labels[src] or tostring(src or "?")
end

-- Vanilla / composed map_scripts hooks for a map (onEnter, onStep, scripts…).
-- Used by Events > HOOKS so engine handlers are visible, not only mod drafts.
local _hookInfoCache = {}

function TalkIndex.mapHookInfo(mapId)
  if not mapId then return {} end
  local cached = _hookInfoCache[mapId]
  if cached then return cached end
  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if not ok or not MapScripts then
    _hookInfoCache[mapId] = { hooks = {}, scripts = {} }
    return _hookInfoCache[mapId]
  end
  local view = MapScripts.get(mapId)
  local info = { hooks = {}, scripts = {} }
  if type(view) == "table" then
    for _, name in ipairs({
      "onEnter", "onVictory", "onStep", "onBoulderMoved", "onInteract",
    }) do
      local h = view[name]
      if type(h) == "function" then
        info.hooks[name] = { form = "lua" }
      elseif type(h) == "table" and #h > 0 and type(h[1]) == "table" then
        info.hooks[name] = { form = "rows", rows = h }
      end
    end
    if type(view.scripts) == "table" then
      for name, rows in pairs(view.scripts) do
        if type(name) == "string" then
          if type(rows) == "function" then
            info.scripts[name] = { form = "lua" }
          elseif type(rows) == "table" and #rows > 0 then
            info.scripts[name] = { form = "rows", rows = rows }
          end
        end
      end
    end
  end
  _hookInfoCache[mapId] = info
  return info
end

function TalkIndex.mapHasHooks(mapId)
  local info = TalkIndex.mapHookInfo(mapId)
  if next(info.hooks or {}) then return true end
  if next(info.scripts or {}) then return true end
  return false
end

-- ------- Advanced: resolve chain + file hits (Events inspector)

local _scriptIndex = nil

local function walkLuaFiles(rel, out)
  if not (love and love.filesystem and love.filesystem.getDirectoryItems) then
    return
  end
  local ok, items = pcall(love.filesystem.getDirectoryItems, rel)
  if not ok or type(items) ~= "table" then return end
  for _, name in ipairs(items) do
    local path = (rel == "" or rel == ".") and name or (rel .. "/" .. name)
    local info = love.filesystem.getInfo(path)
    if info and info.type == "directory" then
      walkLuaFiles(path, out)
    elseif info and type(name) == "string" and name:sub(-4) == ".lua" then
      out[#out + 1] = path
    end
  end
end

local function readSourceFile(rel)
  if love and love.filesystem and love.filesystem.read then
    local ok, body = pcall(love.filesystem.read, rel)
    if ok and type(body) == "string" then return body end
  end
  local ModIO = require("ModIO")
  local root = ModIO.repoRoot()
  local sep = package.config:sub(1, 1)
  local full = root .. sep .. rel:gsub("/", sep)
  return ModIO.readText(full)
end

function TalkIndex.invalidateScriptIndex()
  _scriptIndex = nil
end

-- Index data/scripts (+ a few engine files) by TEXT_* and coarse path hints.
function TalkIndex.ensureScriptIndex()
  if _scriptIndex then return _scriptIndex end
  local byText, files = {}, {}
  walkLuaFiles("data/scripts", files)
  for _, path in ipairs({
    "src/world/OverworldController.lua",
    "src/script/Commands.lua",
    "src/script/MapScripts.lua",
  }) do
    if love and love.filesystem and love.filesystem.getInfo
        and love.filesystem.getInfo(path) then
      files[#files + 1] = path
    end
  end
  for _, path in ipairs(files) do
    local body = readSourceFile(path)
    if type(body) == "string" and #body > 0 and #body < 2.5e6 then
      local lineNo = 1
      for line in (body .. "\n"):gmatch("(.-)\n") do
        for tid in line:gmatch("TEXT_[A-Z0-9_]+") do
          local bucket = byText[tid]
          if not bucket then
            bucket = {}
            byText[tid] = bucket
          end
          local last = bucket[#bucket]
          if not (last and last.path == path and last.line == lineNo) then
            bucket[#bucket + 1] = { path = path, line = lineNo }
          end
        end
        lineNo = lineNo + 1
      end
    end
  end
  _scriptIndex = { byText = byText, files = files }
  return _scriptIndex
end

local function findLineWith(rel, query)
  if type(query) ~= "string" or query == "" then return 1 end
  local body = readSourceFile(rel)
  if type(body) ~= "string" then return 1 end
  local lineNo = 1
  for line in (body .. "\n"):gmatch("(.-)\n") do
    if line:find(query, 1, true) then return lineNo end
    lineNo = lineNo + 1
  end
  return 1
end

function TalkIndex.findScriptHits(mapId, textId)
  local idx = TalkIndex.ensureScriptIndex()
  local hits = {}
  local seen = {}
  local function add(path, line, why)
    local key = path .. "\0" .. tostring(line)
    if seen[key] then return end
    seen[key] = true
    hits[#hits + 1] = { path = path, line = line or 1, why = why }
  end
  if textId and idx.byText[textId] then
    for _, h in ipairs(idx.byText[textId]) do
      add(h.path, h.line, "TEXT_*")
    end
  end
  if mapId then
    local needle = mapId
    for _, path in ipairs(idx.files or {}) do
      if path:upper():find(needle, 1, true)
          or path:upper():find(needle:gsub("_", ""), 1, true) then
        add(path, findLineWith(path, needle), "map path")
      end
    end
  end
  table.sort(hits, function(a, b)
    local am = (mapId and a.path:upper():find(mapId, 1, true)) and 0 or 1
    local bm = (mapId and b.path:upper():find(mapId, 1, true)) and 0 or 1
    if am ~= bm then return am < bm end
    if a.why ~= b.why then return a.why == "TEXT_*" end
    return a.path < b.path
  end)
  return hits
end

local function previewSteps(steps, limit)
  limit = limit or 14
  local lines = {}
  for i, step in ipairs(steps or {}) do
    if i > limit then
      lines[#lines + 1] = "…"
      break
    end
    local kind = step.kind or "raw"
    local detail = step.note or step.text or step.item or step.flag
      or step.species or step.trainer or step.name or step.label or ""
    lines[#lines + 1] = string.format("%d. %s  %s", i, kind, tostring(detail))
  end
  if #lines == 0 then lines[1] = "(empty)" end
  return lines
end

local function previewRows(rows, limit)
  if type(rows) ~= "table" then return { tostring(rows) } end
  return previewSteps(ModWriter.rowsToSteps(rows), limit)
end

local function modIdFromSession(S)
  if S and S.path then
    return S.path:match("[/\\]([^/\\]+)$")
  end
  return nil
end

-- Resolve chain for Events → Advanced. layers[1] is what currently wins.
function TalkIndex.inspectTalk(S, mapId, textId)
  local key = mapId .. "/" .. textId
  local layers = {}
  local hits = TalkIndex.findScriptHits(mapId, textId)

  local owned = S.project and S.project.talkScripts and S.project.talkScripts[key]
  if owned and type(owned.steps) == "table" then
    local mid = modIdFromSession(S)
    layers[#layers + 1] = {
      id = "mod",
      title = "Mod override (talkScripts)",
      detail = "Wins at runtime · Save emits map_scripts talk",
      form = "steps",
      preview = previewSteps(owned.steps),
      open = mid and {
        kind = "mod", modId = mid, rel = "main.lua", query = textId,
      } or nil,
    }
  end

  TalkIndex.ensureScripts()
  local okMS, MapScripts = pcall(require, "src.script.MapScripts")
  local talk = okMS and MapScripts.talkScript(mapId, textId) or nil
  local baseTalk = okMS and MapScripts.baseTalk(mapId, textId) or nil
  local talkSrc = okMS and MapScripts.talkSource and MapScripts.talkSource(mapId, textId)

  if talk ~= nil then
    local openHit = hits[1]
    local open = openHit and {
      kind = "repo", rel = openHit.path, line = openHit.line, query = textId,
    } or nil
    if type(talk) == "function" then
      layers[#layers + 1] = {
        id = "lua",
        title = talkSrc and ("Lua talk [" .. tostring(talkSrc.modId) .. "]")
          or "Lua talk handler",
        detail = "Function body — not step rows",
        form = "lua",
        preview = {
          "Lua function (edit in source file)",
          openHit and ("→ " .. openHit.path .. ":" .. openHit.line) or "→ search data/scripts",
        },
        open = open,
      }
    elseif type(talk) == "table" then
      local title = talkSrc
        and ("map_scripts talk [" .. tostring(talkSrc.modId) .. "]")
        or "Vanilla map_scripts talk"
      layers[#layers + 1] = {
        id = talkSrc and "mod_script" or "script",
        title = title,
        detail = string.format("%d row(s)", #talk),
        form = "rows",
        preview = previewRows(talk),
        open = open,
      }
    end
  end

  if baseTalk ~= nil and baseTalk ~= talk then
    local openHit = hits[1]
    local open = openHit and {
      kind = "repo", rel = openHit.path, line = openHit.line, query = textId,
    } or nil
    if type(baseTalk) == "function" then
      layers[#layers + 1] = {
        id = "base_lua",
        title = "Engine base Lua talk",
        detail = "Under mod override",
        form = "lua",
        preview = { "Base Lua function behind mod/map_scripts" },
        open = open,
      }
    elseif type(baseTalk) == "table" then
      layers[#layers + 1] = {
        id = "base_script",
        title = "Engine base talk rows",
        detail = string.format("%d row(s) under override", #baseTalk),
        form = "rows",
        preview = previewRows(baseTalk),
        open = open,
      }
    end
  end

  local obj = findObject(S, mapId, textId)
  if obj and obj.item and obj.item ~= "0" and obj.item ~= 0 then
    layers[#layers + 1] = {
      id = "item",
      title = "Engine item-ball",
      detail = tostring(obj.item)
        .. (obj.name and (" · " .. tostring(obj.name)) or ""),
      form = "engine",
      preview = {
        "OverworldController item-ball branch",
        "(no talk script → give item + itemsTaken)",
      },
      open = {
        kind = "repo",
        rel = "src/world/OverworldController.lua",
        query = "item balls (object_event",
      },
    }
  end
  if obj and (obj.trainerClass or obj.trainer) then
    layers[#layers + 1] = {
      id = "trainer",
      title = "Engine trainer",
      detail = tostring(obj.trainerClass or obj.trainer)
        .. " party " .. tostring(obj.trainerParty or 1),
      form = "engine",
      preview = { "OverworldController trainer engage branch" },
      open = {
        kind = "repo",
        rel = "src/world/OverworldController.lua",
        query = "generic trainers (object_event",
      },
    }
  end
  if obj and (obj.pokemon or obj.species) then
    layers[#layers + 1] = {
      id = "pokemon",
      title = "Engine fixed wild",
      detail = tostring(obj.pokemon or obj.species)
        .. " Lv" .. tostring(obj.level or "?"),
      form = "engine",
      preview = { "OverworldController static wild branch" },
      open = {
        kind = "repo",
        rel = "src/world/OverworldController.lua",
        query = "static wild encounters",
      },
    }
  end

  local ptr = pointerEntry(S, mapId, textId)
  if ptr then
    if ptr.asm then
      layers[#layers + 1] = {
        id = "asm",
        title = "ASM / engine text pointer",
        detail = "May have a port under data/scripts",
        form = "engine",
        preview = { "text_pointers.asm entry", hits[1] and hits[1].path or "" },
        open = hits[1] and {
          kind = "repo", rel = hits[1].path, line = hits[1].line,
        } or nil,
      }
    elseif ptr.mart or ptr.nurse or ptr.pc or ptr.cableClub then
      local role = ptr.mart and "shop" or ptr.nurse and "nurse"
        or ptr.pc and "pc" or "cable"
      layers[#layers + 1] = {
        id = role,
        title = "Engine " .. role .. " interaction",
        detail = "Hard-coded UI path",
        form = "engine",
        preview = { "Not a talk-script row list" },
        open = {
          kind = "repo",
          rel = "src/world/OverworldController.lua",
          query = role == "shop" and "Poké Mart" or role,
        },
      }
    elseif ptr.text then
      layers[#layers + 1] = {
        id = "text",
        title = "Plain dialog text",
        detail = tostring(ptr.text),
        form = "text",
        preview = { resolveBody(S, ptr.text) },
        open = nil,
      }
    end
  end

  if #layers == 0 then
    layers[1] = {
      id = "empty",
      title = "No handler resolved",
      detail = "Empty / unknown",
      form = "empty",
      preview = { "No talk script, object branch, or text pointer" },
      open = hits[1] and {
        kind = "repo", rel = hits[1].path, line = hits[1].line,
      } or nil,
    }
  end

  return {
    mapId = mapId,
    textId = textId,
    key = key,
    layers = layers,
    hits = hits,
  }
end

return TalkIndex
