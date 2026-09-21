-- Dialog tab: browse every TEXT_* / string for a map (vanilla + project),
-- edit bodies, emit text:override + text_pointers:patch on Save.
-- Gold: pins come from object/bgEvent scriptKey → writetext keys (bank:addr).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local RegList = require("RegList")
local UiPreview = require("UiPreview")
local Generation = require("Generation")
local PAL = Theme.PAL

local Dialog = {}

-- Gen2 script ops that carry a text pointer (data/generated/text.lua key).
local GEN2_TEXT_OPS = {
  writetext = true,
  jumptext = true,
  jumptextfaceplayer = true,
  farwritetext = true,
}

local function scriptCommands(S, scriptKey)
  if not scriptKey or scriptKey == "" then return nil end
  local proj = S.project and S.project.scripts and S.project.scripts[scriptKey]
  if type(proj) == "table" then return proj end
  local data = S.data and S.data.scripts and S.data.scripts[scriptKey]
  if type(data) == "table" then return data end
  return nil
end

-- Collect text keys reachable from a script (follow if*/sjump/scall lightly).
local function collectGen2TextKeys(S, scriptKey, out, seen, depth)
  out = out or {}
  seen = seen or {}
  depth = depth or 0
  if not scriptKey or scriptKey == "" or seen[scriptKey] or depth > 5 then
    return out
  end
  seen[scriptKey] = true
  local cmds = scriptCommands(S, scriptKey)
  if type(cmds) ~= "table" then return out end
  for _, cmd in ipairs(cmds) do
    if type(cmd) == "table" then
      local tid = cmd.text
      if type(tid) == "string" and tid ~= "" and GEN2_TEXT_OPS[cmd.op] then
        out[#out + 1] = tid
      end
      if type(cmd.script) == "string" then
        collectGen2TextKeys(S, cmd.script, out, seen, depth + 1)
      end
    end
  end
  return out
end

-- Truncate on UTF-8 codepoint boundaries (byte sub() splits POKeMON / etc).
local function utf8Prefix(s, maxBytes)
  s = tostring(s or "")
  if #s <= maxBytes then return s end
  local i, n = 1, #s
  local last = 1
  while i <= n and i <= maxBytes do
    last = i
    local b = s:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4
    elseif b >= 0xE0 then len = 3
    elseif b >= 0xC0 then len = 2
    end
    if i + len - 1 > n then len = 1 end
    if i + len - 1 > maxBytes then break end
    i = i + len
    last = i
  end
  return s:sub(1, last - 1)
end

local function allMapIds(S)
  local seen, ids = {}, {}
  if S.project then
    for id in pairs(S.project.maps or {}) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  for id in pairs(require("Generation").dataMaps(S)) do
    if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
  end
  table.sort(ids)
  if Generation.isGen3(S) then table.insert(ids,1,"ALL DIALOG") end
  return ids
end

local function mapRecord(S, mapId)
  if S.project and S.project.maps and S.project.maps[mapId] then
    return S.project.maps[mapId], true
  end
  local live = require("Generation").dataMaps(S)[mapId]
  if live then return live, false end
  return nil, false
end

local function pointerTable(S, label)
  local proj = S.project and S.project.text_pointers and S.project.text_pointers[label]
  local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
  return proj, base
end

-- Resolve pin id → string id. Gen1: TEXT_* via text_pointers. Gold: id IS the key.
local function resolveStringId(S, mapId, textId)
  if not textId then return nil end
  if Generation.isGen2(S) or Generation.isGen3(S) then
    return textId, State.mapLabel(S, mapId), false
  end
  local label = State.mapLabel(S, mapId)
  local proj, base = pointerTable(S, label)
  if proj and proj[textId] and proj[textId].text then
    return proj[textId].text, label, true
  end
  if base and base[textId] and base[textId].text then
    return base[textId].text, label, false
  end
  -- invented binding for brand-new pins
  local invented = "_" .. textId:gsub("^TEXT_", "")
  return invented, label, false
end

local function resolveBody(S, strId)
  if Generation.isGen3(S) then
    local edited=S.project.text[strId]
    return require("Gen3Dialog").display(edited or S.data.text[strId]),edited~=nil
  end
  if not strId then return "" end
  if S.project.text and S.project.text[strId] ~= nil then
    return S.project.text[strId], true
  end
  if S.data and S.data.text and S.data.text[strId] ~= nil then
    return S.data.text[strId], false
  end
  return "", false
end

local function collectPins(S, mapId)
  if Generation.isGen3(S) then return require("Gen3Dialog").pins(S,mapId) end
  local map = mapRecord(S, mapId)
  local pins, seen = {}, {}
  -- Dedupe by kind+index+textId so two NPCs never collapse into one pin.
  local function add(kind, index, textId, label, x, y, scriptKey)
    if not textId or textId == "" then return end
    local pinKey = string.format("%s:%s:%s", tostring(kind), tostring(index), textId)
    if seen[pinKey] then return end
    seen[pinKey] = true
    local strId = select(1, resolveStringId(S, mapId, textId))
    local body = select(1, resolveBody(S, strId))
    if type(body) ~= "string" then body = "" end
    local preview = body:gsub("\n", " "):gsub("\f", " / "):gsub("\v", " ")
    if #preview > 40 then preview = utf8Prefix(preview, 38) .. "..." end
    pins[#pins + 1] = {
      kind = kind, index = index, textId = textId,
      label = label, x = x, y = y,
      strId = strId, preview = preview,
      scriptKey = scriptKey,
      pinKey = pinKey,
    }
  end

  if Generation.isGen2(S) then
    if map then
      for i, obj in ipairs(map.objects or {}) do
        local sk = obj.scriptKey
        local keys = collectGen2TextKeys(S, sk)
        local baseLabel = string.format("NPC #%d %s", obj.index or i, obj.sprite or "")
        if #keys == 0 then
          -- Still list the NPC so multi-event maps aren't "missing" dialog.
          if type(sk) == "string" and sk ~= "" then
            add("object", i, sk, baseLabel .. " (no text)", obj.x, obj.y, sk)
          end
        else
          for ti, tid in ipairs(keys) do
            local label = (#keys > 1)
              and string.format("%s · text %d", baseLabel, ti)
              or baseLabel
            add("object", i, tid, label, obj.x, obj.y, sk)
          end
        end
      end
      for i, ev in ipairs(map.bgEvents or {}) do
        local sk = ev.scriptKey
        local keys = collectGen2TextKeys(S, sk)
        local baseLabel = string.format("BG (%d,%d)", ev.x or 0, ev.y or 0)
        if #keys == 0 then
          if type(sk) == "string" and sk ~= "" then
            add("bg", i, sk, baseLabel .. " (no text)", ev.x, ev.y, sk)
          end
        else
          for ti, tid in ipairs(keys) do
            local label = (#keys > 1)
              and string.format("%s · text %d", baseLabel, ti)
              or baseLabel
            add("bg", i, tid, label, ev.x, ev.y, sk)
          end
        end
      end
    end
    return pins
  end

  if map then
    for i, obj in ipairs(map.objects or {}) do
      add("object", i,
        obj.text or ("TEXT_" .. mapId .. "_OBJ" .. i),
        string.format("NPC #%d %s", obj.index or i, obj.sprite or ""),
        obj.x, obj.y)
    end
    for i, sign in ipairs(map.signs or {}) do
      add("sign", i,
        sign.text or ("TEXT_" .. mapId .. "_SIGN" .. i),
        string.format("Sign #%d", i),
        sign.x, sign.y)
    end
  end

  -- every TEXT_* registered for this map label (trainers, scripts, unused, ...)
  local label = State.mapLabel(S, mapId)
  local proj, base = pointerTable(S, label)
  local function addPtrTable(ptrs)
    if not ptrs then return end
    local ids = {}
    for textId in pairs(ptrs) do ids[#ids + 1] = textId end
    table.sort(ids)
    for _, textId in ipairs(ids) do
      local entry = ptrs[textId]
      local hint = (entry and entry.label) or textId
      add("pointer", nil, textId, hint, nil, nil)
    end
  end
  addPtrTable(base)
  addPtrTable(proj)

  return pins
end

local function ensureOwnedMap(S, mapId)
  local map, owned = mapRecord(S, mapId)
  if not map or owned then return map end
  local copy = {}
  for k, v in pairs(map) do copy[k] = v end
  copy.objects = {}
  for i, o in ipairs(map.objects or {}) do
    local oc = {}
    for k, v in pairs(o) do oc[k] = v end
    copy.objects[i] = oc
  end
  copy.signs = {}
  for i, s in ipairs(map.signs or {}) do
    local sc = {}
    for k, v in pairs(s) do sc[k] = v end
    copy.signs[i] = sc
  end
  if type(map.bgEvents) == "table" then
    copy.bgEvents = {}
    for i, e in ipairs(map.bgEvents) do
      local ec = {}
      for k, v in pairs(e) do ec[k] = v end
      copy.bgEvents[i] = ec
    end
  end
  copy._isNew = false
  S.project.maps[mapId] = copy
  return copy
end

-- Bind project pointer + text on first real edit (not on mere selection).
local function ensureEditable(S, mapId, textId, App)
  State.ensureProjectFields(S.project)
  local strId, label = resolveStringId(S, mapId, textId)
  if Generation.isGen3(S) then return strId end
  if Generation.isGen2(S) then
    -- Gold: text ids are bank:addr keys; Save emits text:override only.
    if strId and S.project.text[strId] == nil then
      local body = select(1, resolveBody(S, strId))
      S.project.text[strId] = body
    end
    App.markDirty()
    return strId
  end
  S.project.text_pointers[label] = S.project.text_pointers[label] or {}
  if not S.project.text_pointers[label][textId] then
    local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
    local src = base and base[textId]
    local copy = {
      text = (src and src.text) or strId,
      label = src and src.label or nil,
      asm = src and src.asm or nil,
      nurse = src and src.nurse or nil,
      pc = src and src.pc or nil,
      cableClub = src and src.cableClub or nil,
    }
    if src and type(src.mart) == "table" then
      copy.mart = {}
      for i, id in ipairs(src.mart) do copy.mart[i] = id end
    end
    S.project.text_pointers[label][textId] = copy
  end
  if S.project.text[strId] == nil then
    local body = select(1, resolveBody(S, strId))
    S.project.text[strId] = body
  end
  local map = ensureOwnedMap(S, mapId)
  if map then
    for _, pin in ipairs(collectPins(S, mapId)) do
      if pin.textId == textId then
        if pin.kind == "object" and map.objects[pin.index] then
          map.objects[pin.index].text = textId
        elseif pin.kind == "sign" and map.signs[pin.index] then
          map.signs[pin.index].text = textId
        end
      end
    end
  end
  App.markDirty()
  return strId
end

function Dialog.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  if Generation.isGen3(S) then require("Gen3ContentAdapter").prepare(S) end

  local col1 = math.min(200 * s, w * 0.22)
  local col2 = math.min(260 * s, w * 0.30)
  local col3 = w - col1 - col2 - 24 * s

  -- maps
  Kit.caption(x, y, "MAP")
  local qh = 28 * s
  local qy = y + 22 * s
  local mapQ, mapQCh = Search.field(S, "dialogMapQuery", x, qy, col1, qh, "search maps...")
  if mapQCh then S.dialogMapOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = math.max(40 * s, h - (listY - y))
  Kit.card(x, listY, col1, listH, 12 * s)
  local maps = Search.filterIds(allMapIds(S), Generation.isGen3(S) and mapQ:gsub(" ","_") or mapQ)
  if not S.dialogMapId then S.dialogMapId = S.mapId or maps[1] end
  local rowH = 26 * s
  local perMap = math.max(1, math.floor((listH - 16 * s) / (rowH + 2 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = col1 - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.dialogMapOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.dialogMapOffset or 0, #maps, perMap)
  local mapNav = RegList.bindNav(S, maps, {
    selKey = "dialogMapId", offsetKey = "dialogMapOffset", perPage = perMap,
    onSelect = function()
      S.dialogTextId = nil
      S.dialogPinOffset = 0
    end,
  })
  local ry = listY + 8 * s
  for i = (S.dialogMapOffset or 0) + 1,
      math.min(#maps, (S.dialogMapOffset or 0) + perMap) do
    local id = maps[i]
    if Kit.row(mapScrollX, ry, mapRowW, rowH, S.dialogMapId == id, PAL.blue) then
      mapNav.activate()
      S.dialogMapId = id
      S.dialogTextId = nil
      S.dialogPinOffset = 0
    end
    local textMax = math.max(8, mapRowW - 12 * s)
    Kit.pushClip(mapScrollX, ry, mapRowW, rowH)
    Kit.text("micro", Kit.ellipsize("micro", Generation.isGen3(S) and require("Gen3Names").map(id) or id, textMax),
      mapScrollX + 6 * s, ry + 6 * s, PAL.text)
    Kit.popClip()
    ry = ry + rowH + 2 * s
  end
  S.dialogMapOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.dialogMapOffset or 0, #maps, perMap)

  -- pins / all TEXT_* (Gen1) or script writetext keys (Gold)
  local px = x + col1 + 12 * s
  Kit.caption(px, y, "DIALOG")
  local pinQ, pinQCh = Search.field(S, "dialogPinQuery", px, qy, col2, qh, "search dialog...")
  if pinQCh then S.dialogPinOffset = 0 end
  Kit.card(px, listY, col2, listH, 12 * s)
  local pins = Search.filterItems(collectPins(S, S.dialogMapId), pinQ, function(p)
    return table.concat({
      p.textId or "", p.label or "", p.preview or "", p.strId or "",
      p.scriptKey or "",
    }, " ")
  end)
  local pinRowH = 34 * s
  local perPin = math.max(1, math.floor((listH - 16 * s) / (pinRowH + 4 * s)))
  local pinScrollX = px + 6 * s
  local pinScrollW = col2 - 12 * s
  local pinRowW = Kit.scrollInnerWidth(pinScrollW)
  S.dialogPinOffset = Kit.scroll(pinScrollX, listY + 8 * s, pinScrollW,
    mapScrollH, S.dialogPinOffset or 0, #pins, perPin)
  local pinIds = {}
  for i, pin in ipairs(pins) do pinIds[i] = pin.textId end
  local pinNav = RegList.bindNav(S, pinIds, {
    selKey = "dialogTextId", offsetKey = "dialogPinOffset", perPage = perPin,
  })
  ry = listY + 8 * s
  for i = (S.dialogPinOffset or 0) + 1,
      math.min(#pins, (S.dialogPinOffset or 0) + perPin) do
    local pin = pins[i]
    local on = S.dialogTextId == pin.textId
    if Kit.row(pinScrollX, ry, pinRowW, pinRowH, on, PAL.green) then
      pinNav.activate()
      S.dialogTextId = pin.textId
      S.dialogScriptKey = pin.scriptKey
      -- selection only -- do not clone / invent Hello!
    end
    local tw = pinRowW - 12 * s
    Kit.text("micro", Kit.ellipsize("micro", tostring(pin.label or ""), tw),
      px + 12 * s, ry + 2 * s, PAL.text)
    local sub = pin.preview ~= "" and pin.preview or pin.textId
    Kit.text("micro", Kit.ellipsize("micro", tostring(sub or ""), tw),
      px + 12 * s, ry + 16 * s, PAL.faint)
    ry = ry + pinRowH + 4 * s
  end
  S.dialogPinOffset = Kit.scrollbar(pinScrollX, listY + 8 * s, pinScrollW,
    mapScrollH, S.dialogPinOffset or 0, #pins, perPin)
  if #pins == 0 then
    Kit.text("micro", "No dialog on this map",
      px + 12 * s, listY + 16 * s, PAL.muted)
  end

  -- editor
  local ex = px + col2 + 12 * s
  Kit.caption(ex, y, "TEXT")
  Kit.card(ex, listY, col3, listH, 12 * s)
  if not S.dialogTextId then
    Kit.emptyBox(ex + 8 * s, listY + 8 * s, col3 - 16 * s, listH - 16 * s,
      "Select a dialog entry")
    return
  end

  local strId, label = resolveStringId(S, S.dialogMapId, S.dialogTextId)
  local body, ownedText = resolveBody(S, strId)
  if type(body) ~= "string" then body = "" end
  local selPin = nil
  for _, p in ipairs(pins) do
    if p.textId == S.dialogTextId then selPin = p; break end
  end
  Kit.text("small", Kit.ellipsize("small", Generation.isGen3(S) and (selPin and selPin.label or require("Gen3Names").dialog(strId,body)) or tostring(S.dialogTextId or ""), col3-24*s), ex + 12 * s, listY + 12 * s, PAL.caption)
  if Generation.isGen3(S) then
    Kit.text("micro", require("Gen3Names").map(S.dialogMapId)..(ownedText and " | Edited" or " | Original").." | ID: "..tostring(strId), ex+12*s,listY+32*s,PAL.faint)
  elseif Generation.isGen2(S) then
    Kit.text("micro", string.format("%s%s%s",
        ownedText and "mod override" or "vanilla",
        selPin and selPin.scriptKey and ("  |  script " .. selPin.scriptKey) or "",
        selPin and selPin.label and ("  |  " .. selPin.label) or ""),
      ex + 12 * s, listY + 32 * s, PAL.faint)
  else
    Kit.text("micro", string.format("%s  |  %s%s",
        tostring(strId), tostring(label), ownedText and "" or "  (vanilla)"),
      ex + 12 * s, listY + 32 * s, PAL.faint)
  end

  Kit.text("micro",
    Generation.isGen2(S)
      and "Use \\n for new line, \\f for page break, \\v for A-wait, {PLAYER} for name"
      or "Use \\n for new line, \\f for page break, {PLAYER} for name",
    ex + 12 * s, listY + 52 * s, PAL.muted)
  local display = body:gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\v", "\\v")
  local fieldW = math.max(40 * s, col3 - 24 * s)
  local edited = Kit.textfield("dlg_body", ex + 12 * s, listY + 72 * s,
    fieldW, 36 * s, display, "(empty)")
  if edited then
    local decoded = edited:gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\v")
    if decoded ~= body then
      strId = ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
      S.project.text[strId] = Generation.isGen3(S) and require("Gen3Dialog").encode(decoded,S.project.text[strId] or S.data.text[strId]) or decoded
      App.markDirty()
      body = decoded
      ownedText = true
    end
  end

  -- Gen1 text-box preview (Font border + two lines + ▼)
  local previewY = listY + 120 * s
  local previewKey = tostring(S.dialogMapId or "") .. "/"
    .. tostring(S.dialogTextId or "") .. "\0" .. body
  if S._dialogPreviewKey ~= previewKey then
    S._dialogPreviewKey = previewKey
    S.dialogPreviewPage = 1
    S.dialogPreviewLine = 1
  end
  Kit.text("micro", "PREVIEW:", ex + 12 * s, previewY, PAL.caption)
  local boxY = previewY + 16 * s
  local frameH, pinfo = UiPreview.drawTextBoxPreview(S, body, ex + 12 * s, boxY, fieldW, {
    page = S.dialogPreviewPage or 1,
    lineStart = S.dialogPreviewLine or 1,
  })
  if pinfo then
    S.dialogPreviewPage = pinfo.page
    S.dialogPreviewLine = pinfo.lineStart
  end
  local navY = boxY + (frameH or 48 * s) + 6 * s
  local navH = 0
  if pinfo and (pinfo.pageCount > 1 or pinfo.canPrev or pinfo.canNext) then
    navH = 26 * s
    local chipW = 36 * s
    if Kit.chip(ex + 12 * s, navY, chipW, navH - 2 * s, "<",
        pinfo.canPrev, PAL.blue, nil, "Previous page / line") and pinfo.canPrev then
      local np, nl = UiPreview.stepTextBoxPreview(S, body,
        S.dialogPreviewPage, S.dialogPreviewLine, -1)
      S.dialogPreviewPage, S.dialogPreviewLine = np, nl
    end
    if Kit.chip(ex + 12 * s + chipW + 4 * s, navY, chipW, navH - 2 * s, ">",
        pinfo.canNext, PAL.blue, nil, "Next page / line") and pinfo.canNext then
      local np, nl = UiPreview.stepTextBoxPreview(S, body,
        S.dialogPreviewPage, S.dialogPreviewLine, 1)
      S.dialogPreviewPage, S.dialogPreviewLine = np, nl
    end
    Kit.text("micro",
      string.format("page %d/%d", pinfo.page, pinfo.pageCount),
      ex + 12 * s + chipW * 2 + 16 * s, navY + 6 * s, PAL.muted)
  end

  local by = navY + navH + 8 * s
  if Kit.button(ex + 12 * s, by, 160 * s, 30 * s, "Insert {PLAYER}",
      { kind = "accent" }) then
    strId = ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
    if Generation.isGen3(S) then
      S.project.text[strId]=require("Gen3Dialog").encode(body.."{PLAYER}",S.project.text[strId] or S.data.text[strId])
    else S.project.text[strId] = (S.project.text[strId] or body or "") .. "{PLAYER}" end
    App.markDirty()
  end
  if Kit.button(ex + 184 * s, by, 140 * s, 30 * s, "Open in Events",
      { kind = "ghost" }) then
    -- Browse only — do not invent a Hello! stub that would override vanilla.
    S.tab = "events"
    S.eventsMode = "scripts"
    S.eventMapId = S.dialogMapId
    if Generation.isGen3(S) then
      S.g3EventMode="scripts"
      S.gen3Id=selPin and selPin.scriptKey
    elseif Generation.isGen2(S) then
      local sk = (selPin and selPin.scriptKey) or S.dialogScriptKey
      S.dialogScriptKey = sk
      S.eventScriptKey = (S.dialogMapId or "") .. "/"
        .. (sk or S.dialogTextId or "")
    else
      S.eventScriptKey = (S.dialogMapId or "") .. "/" .. (S.dialogTextId or "")
    end
  end
  if ownedText and Kit.button(ex + 12 * s, by + 38 * s, 120 * s, 28 * s, "Revert",
      { kind = "danger" }) then
    if strId then S.project.text[strId] = nil end
    if not Generation.isGen2(S) and not Generation.isGen3(S) then
      local lbl = State.mapLabel(S, S.dialogMapId)
      if S.project.text_pointers[lbl] then
        S.project.text_pointers[lbl][S.dialogTextId] = nil
        if not next(S.project.text_pointers[lbl]) then
          S.project.text_pointers[lbl] = nil
        end
      end
    end
    App.markDirty()
  end

  -- Mart / shop stock on this TEXT_* (Gen1 only; Gold marts are script-driven).
  local ptrEntry = nil
  if not Generation.isGen2(S) and not Generation.isGen3(S) then
    local lbl = State.mapLabel(S, S.dialogMapId)
    local proj = S.project.text_pointers and S.project.text_pointers[lbl]
    if proj and proj[S.dialogTextId] then
      ptrEntry = proj[S.dialogTextId]
    else
      local base = S.data and S.data.text_pointers and S.data.text_pointers[lbl]
      ptrEntry = base and base[S.dialogTextId]
    end
  end
  local martY = by + 72 * s
  local isShop = ptrEntry and type(ptrEntry.mart) == "table"
  if Generation.isGen3(S) then
    Kit.text("micro","Native text controls are preserved as {CONTROL:number}.",ex+12*s,martY,PAL.faint)
  elseif Generation.isGen2(S) then
    Kit.text("micro",
      "Gold: text:override for this key. Shop stock → SHOPS tab (MART_*).",
      ex + 12 * s, martY, PAL.faint)
  elseif isShop then
    Kit.text("micro", string.format("Shop stock (%d)", #ptrEntry.mart),
      ex + 12 * s, martY, PAL.caption)
    martY = martY + 16 * s
    local items = {}
    local seen = {}
    local function consider(id, rec)
      if seen[id] or not State.isItemRecord(id, rec) then return end
      seen[id] = true
      items[#items + 1] = id
    end
    for id, rec in pairs(S.project.items or {}) do
      consider(id, rec)
    end
    if S.data and S.data.items then
      for id, rec in pairs(S.data.items) do
        consider(id, rec)
      end
    end
    table.sort(items)
    local function cycleItem(cur)
      if #items == 0 then return cur or "POKE_BALL" end
      for i, id in ipairs(items) do
        if id == cur then return items[(i % #items) + 1] end
      end
      return items[1]
    end
    local rowH = 26 * s
    local maxRows = math.max(1, math.floor(
      (listY + listH - 36 * s - martY) / (rowH + 4 * s)) - 1)
    for mi = 1, math.min(#ptrEntry.mart, maxRows) do
      local itemId = ptrEntry.mart[mi]
      if Kit.button(ex + 12 * s, martY, fieldW - 44 * s, rowH, itemId or "?",
          { kind = "accent", font = "small" }) then
        ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
        local lbl = State.mapLabel(S, S.dialogMapId)
        local e = S.project.text_pointers[lbl][S.dialogTextId]
        e.mart = e.mart or {}
        e.mart[mi] = cycleItem(itemId)
        App.markDirty()
      end
      if Kit.button(ex + fieldW - 24 * s, martY, 28 * s, rowH, "X",
          { kind = "danger", font = "small" }) then
        ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
        local lbl = State.mapLabel(S, S.dialogMapId)
        local e = S.project.text_pointers[lbl][S.dialogTextId]
        if e.mart then table.remove(e.mart, mi) end
        App.markDirty()
      end
      martY = martY + rowH + 4 * s
    end
    if Kit.button(ex + 12 * s, martY, 120 * s, 26 * s, "+ Add item",
        { kind = "good", font = "small" }) then
      ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
      local lbl = State.mapLabel(S, S.dialogMapId)
      local e = S.project.text_pointers[lbl][S.dialogTextId]
      e.mart = e.mart or {}
      e.mart[#e.mart + 1] = (#items > 0 and items[1]) or "POKE_BALL"
      App.markDirty()
    end
    if Kit.button(ex + 140 * s, martY, 130 * s, 26 * s, "Clear shop",
        { kind = "ghost", font = "small" }) then
      ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
      local lbl = State.mapLabel(S, S.dialogMapId)
      local e = S.project.text_pointers[lbl][S.dialogTextId]
      e.mart = nil
      App.markDirty()
    end
  elseif Kit.button(ex + 12 * s, martY, 160 * s, 28 * s, "Mark as Shop",
      { kind = "accent", font = "small",
        tooltip = "Attach a mart inventory to this TEXT_* (Poké Mart clerk)" }) then
    ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
    local lbl = State.mapLabel(S, S.dialogMapId)
    local e = S.project.text_pointers[lbl][S.dialogTextId]
    e.mart = {}
    e.nurse, e.pc, e.cableClub = nil, nil, nil
    App.markDirty()
  end

  Kit.text("micro",
    "Shows vanilla dialog. First edit clones into the mod (Save = text:override).",
    ex + 12 * s, listY + listH - 28 * s, PAL.faint)
end

-- Maps → Dialog: first writetext key for a Gen2 scriptKey (or nil).
function Dialog.firstTextForScript(S, scriptKey)
  if not Generation.isGen2(S) and not Generation.isGen3(S) then return nil end
  local keys = collectGen2TextKeys(S, scriptKey)
  return keys[1]
end

function Dialog.openMap(S, mapId, textId)
  S.tab = "dialog"
  S.dialogMapId = mapId
  if textId then
    S.dialogTextId = textId
    S.dialogPinOffset = 0
  end
end

return Dialog
