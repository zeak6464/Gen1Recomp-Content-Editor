-- Code tab: browse mods/ Lua files; line editor with multi-line paste + undo.

local Kit = require("Kit")
local Theme = require("Theme")
local ModIO = require("ModIO")
local RegList = require("RegList")
local PAL = Theme.PAL

local Code = {}

local function splitLines(body)
  body = tostring(body or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  if body == "" then
    lines[1] = ""
    return lines
  end
  local start = 1
  while true do
    local i = body:find("\n", start, true)
    if not i then
      lines[#lines + 1] = body:sub(start)
      break
    end
    lines[#lines + 1] = body:sub(start, i - 1)
    start = i + 1
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

local function joinLines(lines)
  return table.concat(lines or { "" }, "\n")
end

local function pushCodeUndo(S)
  S._codeUndo = S._codeUndo or {}
  S._codeUndo[#S._codeUndo + 1] = {
    lines = splitLines(joinLines(S.codeLines)),
    line = S.codeLine or 1,
    file = S.codeFile,
    mod = S.browseModId,
  }
  while #S._codeUndo > 40 do table.remove(S._codeUndo, 1) end
  S._codeRedo = {}
end

local function ensureBrowseMod(S)
  local mods = ModIO.listMods()
  if not S.browseModId or S.browseModId == "" then
    if S.path then
      S.browseModId = S.path:match("[/\\]([^/\\]+)$")
    end
    if not S.browseModId and mods[1] then S.browseModId = mods[1] end
  end
  return mods
end

local function loadFile(S, modId, rel)
  local body, err = ModIO.readModFile(modId, rel)
  if body == nil then
    S.codeLines = { "" }
    S.codeLoadError = tostring(err)
    S.codeDirty = false
    S.codeLine = 1
    S._codeUndo, S._codeRedo = {}, {}
    return
  end
  S.codeLines = splitLines(body)
  S.codeLoadError = nil
  S.codeDirty = false
  S.codeLine = math.min(S.codeLine or 1, #S.codeLines)
  S.codeScroll = 0
  S._codeFollowLine = nil
  S._codeUndo, S._codeRedo = {}, {}
end

local function ensureFile(S)
  if not S.browseModId then return end
  local files = ModIO.listModLuaFiles(S.browseModId)
  S._codeFiles = files
  if not S.codeFile or S.codeFile == "" then
    for _, f in ipairs(files) do
      if f == "main.lua" then S.codeFile = f; break end
    end
    S.codeFile = S.codeFile or files[1]
  end
  local key = tostring(S.browseModId) .. "\0" .. tostring(S.codeFile or "")
  if S._codeFor ~= key and S.codeFile then
    if S.codeDirty and S._codeFor then
      return files
    end
    loadFile(S, S.browseModId, S.codeFile)
    S._codeFor = key
  end
  return files
end

local function markCodeDirty(S)
  S.codeDirty = true
  S._quitArmed = nil
end

local function saveFile(S)
  if not (S.browseModId and S.codeFile and S.codeLines) then
    S.status = "No file selected"
    return
  end
  local body = joinLines(S.codeLines)
  local ok, err = ModIO.writeModFile(S.browseModId, S.codeFile, body)
  if not ok then
    S.status = "Write failed: " .. tostring(err)
    return
  end
  S.codeDirty = false
  S.status = "Wrote mods/" .. S.browseModId .. "/" .. S.codeFile
  if S.codeFile == "main.lua" and S.project and not S.project._protectMain then
    local openId = S.path and S.path:match("[/\\]([^/\\]+)$")
    if openId == S.browseModId then
      S.status = S.status .. " — content Save will regenerate main.lua"
    end
  end
end

local function joinPath(root, rel)
  local sep = package.config:sub(1, 1)
  rel = tostring(rel or ""):gsub("\\", "/")
  if root:sub(-1) == "/" or root:sub(-1) == "\\" then
    return root .. rel:gsub("/", sep)
  end
  return root .. sep .. rel:gsub("/", sep)
end

function Code.engineRoots(S)
  local roots = {}
  local function add(r)
    if type(r) ~= "string" or r == "" then return end
    for i = 1, #roots do
      if roots[i] == r then return end
    end
    roots[#roots + 1] = r
  end
  if S and S.dataPrefs then add(S.dataPrefs.recompRoot) end
  local ok, DS = pcall(require, "DataSource")
  if ok and DS and DS.mountedRecompRoot then add(DS.mountedRecompRoot()) end
  add(joinPath(ModIO.repoRoot(), "runtime/gen1recomp"))
  add(ModIO.repoRoot())
  return roots
end

function Code.engineFilePath(S, rel)
  rel = tostring(rel or ""):gsub("\\", "/"):gsub("^/+", "")
  if rel == "" or rel:find("%.%.") then return nil end
  for _, root in ipairs(Code.engineRoots(S)) do
    local full = joinPath(root, rel)
    local f = io.open(full, "rb")
    if f then f:close(); return full end
  end
  return nil
end

local function jumpToQuery(S, query, line)
  if type(line) == "number" and line >= 1 then
    S.codeLine = math.min(line, #(S.codeLines or {}))
    return
  end
  if type(query) ~= "string" or query == "" then
    S.codeLine = 1
    return
  end
  for i, text in ipairs(S.codeLines or {}) do
    if tostring(text):find(query, 1, true) then
      S.codeLine = i
      return
    end
  end
  S.codeLine = 1
end

-- Open a mod Lua file on the Code tab (Events → Advanced).
function Code.openModFile(S, modId, rel, opts)
  opts = opts or {}
  if S.codeDirty and S.codeSourceKind ~= "repo" then
    S.status = "Unsaved Code edits — Write or Reload before opening"
    return false
  end
  if not modId or not rel then return false end
  S.codeSourceKind = "mod"
  S.codeReadOnly = false
  S.codeRepoRel = nil
  S.codeRepoFull = nil
  S.browseModId = modId
  S.codeFile = rel
  S._codeFor = nil
  S._codeFiles = nil
  loadFile(S, modId, rel)
  S._codeFor = tostring(modId) .. "\0" .. tostring(rel)
  jumpToQuery(S, opts.query, opts.line)
  S.codeScroll = math.max(0, (S.codeLine or 1) - 1)
  S._codeFollowLine = S.codeLine
  S.tab = "code"
  S.status = "Opened mods/" .. modId .. "/" .. rel
  return true
end

-- Open a repo-relative engine/vanilla file read-only on the Code tab.
function Code.openRepoFile(S, rel, opts)
  opts = opts or {}
  if S.codeDirty and S.codeSourceKind ~= "repo" then
    S.status = "Unsaved Code edits — Write or Reload before opening"
    return false
  end
  rel = tostring(rel or ""):gsub("\\", "/"):gsub("^/+", "")
  if rel == "" or rel:find("%.%.") then return false end
  local full = Code.engineFilePath(S, rel)
  local body, err
  if full then
    body, err = ModIO.readText(full)
  end
  if body == nil and love and love.filesystem and love.filesystem.read then
    local ok, data = pcall(love.filesystem.read, rel)
    if ok and type(data) == "string" then body, err = data, nil end
  end
  if body == nil then
    S.status = "Open failed: " .. tostring(err or rel)
    return false
  end
  S.codeSourceKind = "repo"
  S.codeReadOnly = true
  S.codeRepoRel = rel
  S.codeRepoFull = full
  S.codeLines = splitLines(body)
  S.codeLoadError = nil
  S.codeDirty = false
  S._codeUndo, S._codeRedo = {}, {}
  jumpToQuery(S, opts.query, opts.line)
  S.codeScroll = math.max(0, (S.codeLine or 1) - 1)
  S._codeFollowLine = S.codeLine
  S.tab = "code"
  S.status = "Opened " .. rel .. " (read-only)"
  return true
end

function Code.openTarget(S, target)
  if type(target) ~= "table" then return false end
  if target.kind == "mod" then
    return Code.openModFile(S, target.modId, target.rel, target)
  end
  if target.kind == "repo" then
    return Code.openRepoFile(S, target.rel, target)
  end
  return false
end

function Code.undo(S)
  if not (S._codeUndo and #S._codeUndo > 0) then return false end
  S._codeRedo = S._codeRedo or {}
  S._codeRedo[#S._codeRedo + 1] = {
    lines = splitLines(joinLines(S.codeLines)),
    line = S.codeLine or 1,
  }
  local snap = table.remove(S._codeUndo)
  S.codeLines = snap.lines
  S.codeLine = snap.line or 1
  markCodeDirty(S)
  return true
end

function Code.redo(S)
  if not (S._codeRedo and #S._codeRedo > 0) then return false end
  S._codeUndo = S._codeUndo or {}
  S._codeUndo[#S._codeUndo + 1] = {
    lines = splitLines(joinLines(S.codeLines)),
    line = S.codeLine or 1,
  }
  local snap = table.remove(S._codeRedo)
  S.codeLines = snap.lines
  S.codeLine = snap.line or 1
  markCodeDirty(S)
  return true
end

function Code.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local mods = ensureBrowseMod(S)
  local repoMode = S.codeSourceKind == "repo"
  local files = {}
  if repoMode then
    if S.browseModId then files = ModIO.listModLuaFiles(S.browseModId) or {} end
    S._codeFiles = files
  else
    files = ensureFile(S) or {}
  end

  local col1 = math.min(180 * s, w * 0.22)
  local col2 = math.min(200 * s, w * 0.24)
  local gap = 10 * s
  local mainX = x + col1 + gap + col2 + gap
  local mainW = w - (col1 + gap + col2 + gap)

  Kit.caption(x, y, "MODS/")
  local listY = y + 22 * s
  local listH = h - 22 * s
  Kit.card(x, listY, col1, listH, 12 * s)
  local rowH = 28 * s
  local perMod = math.max(1, math.floor((listH - 16 * s) / rowH))
  local modX, modY = x + 4 * s, listY + 8 * s
  local modW, modH = col1 - 8 * s, listH - 16 * s
  local modInner = Kit.scrollInnerWidth(modW)
  S.codeModOffset = Kit.scroll(modX, modY, modW, modH,
    S.codeModOffset or 0, #mods, perMod, 1, "codeMods")
  local codeDirty = S.codeDirty
  local modGuard = codeDirty and S.browseModId or nil
  local modNav = RegList.bindNav(S, mods, {
    selKey = "browseModId", offsetKey = "codeModOffset", perPage = perMod,
    onSelect = function(id)
      if modGuard and id ~= modGuard then
        S.browseModId = modGuard
        S.status = "Unsaved file — Write or Reload before switching"
        return
      end
      S.codeFile = nil
      S._codeFor = nil
      S._codeFiles = nil
    end,
  })
  Kit.pushClip(modX, modY, modInner, modH)
  for i = 1, perMod do
    local mid = mods[(S.codeModOffset or 0) + i]
    if not mid then break end
    local ry = listY + 8 * s + (i - 1) * rowH
    local on = S.browseModId == mid
    if Kit.row(x + 6 * s, ry, modInner - 4 * s, rowH - 4 * s, on, PAL.blue) then
      modNav.activate()
      if S.codeDirty and not repoMode then
        S.status = "Unsaved file — Write or Reload before switching"
      else
        S.codeSourceKind = "mod"
        S.codeReadOnly = false
        S.codeRepoRel = nil
        S.browseModId = mid
        S.codeFile = nil
        S._codeFor = nil
        S._codeFiles = nil
      end
    end
    Kit.text("small", Kit.ellipsize("small", mid, modInner - 16 * s),
      x + 12 * s, ry + 5 * s, on and PAL.heading or PAL.text)
  end
  Kit.popClip()
  S.codeModOffset = Kit.scrollbar(modX, modY, modW, modH,
    S.codeModOffset or 0, #mods, perMod, "codeMods")

  local fileX = x + col1 + gap
  Kit.caption(fileX, y, "LUA FILES")
  Kit.card(fileX, listY, col2, listH, 12 * s)
  local perFile = math.max(1, math.floor((listH - 50 * s) / rowH))
  local fileListX, fileListY = fileX + 4 * s, listY + 8 * s
  local fileListW, fileListH = col2 - 8 * s, listH - 50 * s
  local fileInner = Kit.scrollInnerWidth(fileListW)
  S.codeFileOffset = Kit.scroll(fileListX, fileListY, fileListW, fileListH,
    S.codeFileOffset or 0, #files, perFile, 1, "codeFiles")
  local fileGuard = codeDirty and S.codeFile or nil
  local fileNav = RegList.bindNav(S, files, {
    selKey = "codeFile", offsetKey = "codeFileOffset", perPage = perFile,
    onSelect = function(rel)
      if fileGuard and rel ~= fileGuard then
        S.codeFile = fileGuard
        S.status = "Unsaved file — Write or Reload before switching"
        return
      end
      S._codeFor = nil
    end,
  })
  Kit.pushClip(fileListX, fileListY, fileInner, fileListH)
  for i = 1, perFile do
    local rel = files[(S.codeFileOffset or 0) + i]
    if not rel then break end
    local ry = listY + 8 * s + (i - 1) * rowH
    local on = S.codeFile == rel
    if Kit.row(fileX + 6 * s, ry, fileInner - 4 * s, rowH - 4 * s, on, PAL.green) then
      fileNav.activate()
      if S.codeDirty and not repoMode and S.codeFile ~= rel then
        S.status = "Unsaved file — Write or Reload before switching"
      else
        S.codeSourceKind = "mod"
        S.codeReadOnly = false
        S.codeRepoRel = nil
        S.codeFile = rel
        S._codeFor = nil
      end
    end
    Kit.text("small", Kit.ellipsize("small", rel, fileInner - 16 * s),
      fileX + 12 * s, ry + 5 * s, on and PAL.heading or PAL.text)
  end
  Kit.popClip()
  S.codeFileOffset = Kit.scrollbar(fileListX, fileListY, fileListW, fileListH,
    S.codeFileOffset or 0, #files, perFile, "codeFiles")
  local newY = listY + listH - 38 * s
  if Kit.button(fileX + 8 * s, newY, col2 - 16 * s, 28 * s, "+ New .lua",
      { kind = "ghost" }) then
    if S.codeDirty then
      S.status = "Write or Reload before creating a file"
    else
      S.codeNewName = S.codeNewName or "script.lua"
      S._codeCreating = true
    end
  end

  if not repoMode and not S.browseModId then
    Kit.emptyBox(mainX, listY, mainW, listH, "Select a mod under mods/")
    return
  end
  if not repoMode and (not S.codeFile or not S.codeLines) then
    Kit.emptyBox(mainX, listY, mainW, listH, "Select or create a .lua file")
    if S._codeCreating then
      local name = Kit.textfield("code_new", mainX + 12 * s, listY + 40 * s,
        mainW - 140 * s, 30 * s, S.codeNewName or "script.lua", "name.lua")
      S.codeNewName = name
      if Kit.button(mainX + mainW - 120 * s, listY + 40 * s, 100 * s, 30 * s,
          "Create", { kind = "primary" }) then
        local rel = name:gsub("^/+", ""):gsub("\\", "/")
        if not rel:lower():match("%.lua$") then rel = rel .. ".lua" end
        if rel:find("%.%.") or rel:find("^/") then
          S.status = "Bad file name"
        else
          local ok, err = ModIO.writeModFile(S.browseModId, rel,
            "-- " .. rel .. "\nreturn function(mod)\nend\n")
          if ok then
            S.codeFile = rel
            S._codeFor = nil
            S._codeCreating = false
            S.status = "Created " .. rel
          else
            S.status = "Create failed: " .. tostring(err)
          end
        end
      end
    end
    return
  end
  if repoMode and not S.codeLines then
    Kit.emptyBox(mainX, listY, mainW, listH, "No engine file loaded")
    return
  end

  local title
  if repoMode then
    title = "ENGINE  " .. tostring(S.codeRepoRel or "?")
  else
    title = (S.codeDirty and "* " or "")
      .. S.browseModId .. "/" .. S.codeFile
  end
  Kit.caption(mainX, y, Kit.ellipsize("caption", title, mainW))

  local barY = listY
  local btnH = 28 * s
  local bw = 78 * s
  local readOnly = S.codeReadOnly or repoMode
  if readOnly then
    Kit.text("micro", "Read-only engine/vanilla source",
      mainX, barY + 6 * s, PAL.yellow)
  elseif Kit.button(mainX, barY, bw, btnH, "Write", { kind = "primary" }) then
    saveFile(S)
  end
  if not readOnly
      and Kit.button(mainX + bw + 6 * s, barY, bw, btnH, "Reload",
        { kind = "ghost" }) then
    loadFile(S, S.browseModId, S.codeFile)
    S._codeFor = tostring(S.browseModId) .. "\0" .. tostring(S.codeFile)
    S.status = "Reloaded " .. S.codeFile
  end
  if repoMode and Kit.button(mainX + 200 * s, barY, 100 * s, btnH, "Copy path",
      { kind = "ghost" }) then
    local full = S.codeRepoFull
      or Code.engineFilePath(S, S.codeRepoRel or "")
      or joinPath(ModIO.repoRoot(), S.codeRepoRel or "")
    if love and love.system and love.system.setClipboardText then
      love.system.setClipboardText(full)
    end
    S.status = "Copied " .. full
  end
  if not readOnly
      and Kit.button(mainX + 2 * (bw + 6 * s), barY, 70 * s, btnH, "+ Line",
        { kind = "accent" }) then
    pushCodeUndo(S)
    local i = S.codeLine or 1
    table.insert(S.codeLines, i + 1, "")
    S.codeLine = i + 1
    markCodeDirty(S)
  end
  if not readOnly
      and Kit.button(mainX + 2 * (bw + 6 * s) + 76 * s, barY, 70 * s, btnH,
        "Del line", { kind = "danger" }) then
    pushCodeUndo(S)
    local i = S.codeLine or 1
    if #S.codeLines > 1 then
      table.remove(S.codeLines, i)
      S.codeLine = math.min(i, #S.codeLines)
      markCodeDirty(S)
    else
      S.codeLines[1] = ""
      markCodeDirty(S)
    end
  end

  if S.codeLoadError then
    Kit.text("micro", "Load error: " .. S.codeLoadError,
      mainX, barY + btnH + 4 * s, PAL.red)
  end

  local editY = barY + btnH + 18 * s
  local editH = 30 * s
  Kit.text("micro", "Line " .. tostring(S.codeLine or 1)
      .. (readOnly and "  (read-only preview)"
        or "  (paste multi-line OK · Ctrl+Z undoes code edits)"),
    mainX, editY - 14 * s, PAL.caption)
  local lineIdx = S.codeLine or 1
  local cur = S.codeLines[lineIdx] or ""
  if readOnly then
    Kit.text("mono", Kit.ellipsize("mono", cur, mainW),
      mainX, editY + 6 * s, PAL.muted)
  else
    local edited = Kit.textfield("code_line", mainX, editY, mainW, editH, cur, "")
    if edited ~= cur then
      pushCodeUndo(S)
      if edited:find("\n", 1, true) or edited:find("\r", 1, true) then
        local parts = splitLines(edited)
        S.codeLines[lineIdx] = parts[1] or ""
        for i = 2, #parts do
          table.insert(S.codeLines, lineIdx + i - 1, parts[i])
        end
        S.codeLine = lineIdx + #parts - 1
      else
        S.codeLines[lineIdx] = edited
      end
      markCodeDirty(S)
    end
  end

  local viewY = editY + editH + 10 * s
  local viewH = listY + listH - viewY
  Kit.card(mainX, viewY, mainW, viewH, 12 * s)

  local lines = S.codeLines
  local lineH = 18 * s
  local viewX, viewInnerY = mainX + 4 * s, viewY + 8 * s
  local viewInnerW, viewInnerH = mainW - 8 * s, viewH - 16 * s
  local perPage = math.max(1, math.floor(viewInnerH / lineH))
  local innerW = Kit.scrollInnerWidth(viewInnerW)
  S.codeScroll = Kit.scroll(viewX, viewInnerY, viewInnerW, viewInnerH,
    S.codeScroll or 0, #lines, perPage, 3, "codeView")
  if S._codeFollowLine ~= lineIdx then
    S._codeFollowLine = lineIdx
    if lineIdx - 1 < (S.codeScroll or 0) then
      S.codeScroll = math.max(0, lineIdx - 1)
    elseif lineIdx > (S.codeScroll or 0) + perPage then
      S.codeScroll = math.max(0, lineIdx - perPage)
    end
  end

  local gutter = 44 * s
  Kit.pushClip(viewX, viewInnerY, innerW, viewInnerH)
  for i = 1, perPage do
    local li = (S.codeScroll or 0) + i
    local text = lines[li]
    if text == nil then break end
    local ry = viewY + 8 * s + (i - 1) * lineH
    local on = li == lineIdx
    if Kit.press(mainX + 6 * s, ry, innerW - 4 * s, lineH) then
      S.codeLine = li
      if not readOnly then Kit.focus = "code_line" end
    end
    if on then
      Theme.col(PAL.blue, 0.18)
      love.graphics.rectangle("fill", mainX + 6 * s, ry, innerW - 4 * s, lineH)
    end
    Kit.text("mono", string.format("%4d", li),
      mainX + 10 * s, ry + 1 * s, PAL.faint)
    Kit.text("mono", Kit.ellipsize("mono", text, innerW - gutter - 16 * s),
      mainX + gutter, ry + 1 * s, on and PAL.heading or PAL.text)
  end
  Kit.popClip()
  S.codeScroll = Kit.scrollbar(viewX, viewInnerY, viewInnerW, viewInnerH,
    S.codeScroll or 0, #lines, perPage, "codeView")

  Kit.text("micro",
    readOnly
      and (#lines .. " lines — engine/vanilla preview (Events → Advanced)")
      or (#lines .. " lines — click a line to edit, Write saves under mods/"),
    mainX, listY + listH + 2 * s, PAL.faint)
end

function Code.keypressed(S, key)
  if not S.codeLines then return false end
  if Kit.focus == "code_line" then
    if key == "up" then
      S.codeLine = math.max(1, (S.codeLine or 1) - 1)
      return true
    elseif key == "down" then
      S.codeLine = math.min(#S.codeLines, (S.codeLine or 1) + 1)
      return true
    end
  end
  return false
end

return Code
