-- Disk IO for content-editor projects: scaffold, load, save under mods/.

local ModWriter = require("ModWriter")
local State = require("State")
local Json = require("src.link.Json")

local ModIO = {}

local MAP_BUILDER_TRANSFORM = "mapbuilder_transforms.lua"
local FILESYSTEM_PERMISSION = "filesystem"

local function join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. package.config:sub(1, 1) .. b
end

local MANIFEST_KEY_ORDER = {
  "id", "name", "version", "api", "entry", "profile", "game_version",
  "games", "gen2compat",
  "category", "priority", "permissions", "dependencies", "optional_dependencies",
  "conflicts", "incompatible", "experimental", "language", "affects_link",
  "description", "github", "options_schema", "assets_transforms",
}

local function trim(value)
  return value and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

-- Windowless Win32 directory enumeration. Repeated `io.popen("dir ...")`
-- flashes a cmd.exe window every time the editor refreshes its project list.
local function windowsNames(path, directories, pattern)
  if package.config:sub(1, 1) ~= "\\" then return nil end
  local ok, ffi = pcall(require, "ffi")
  if not ok then return nil end
  pcall(ffi.cdef, [[
    typedef unsigned long DWORD;
    typedef int BOOL;
    typedef void *HANDLE;
    typedef struct { DWORD low; DWORD high; } CE_FILETIME;
    typedef struct {
      DWORD attributes;
      CE_FILETIME creation, access, write;
      DWORD sizeHigh, sizeLow, reserved0, reserved1;
      char name[260]; char alternate[14];
    } CE_FIND_DATAA;
    HANDLE FindFirstFileA(const char *pattern, CE_FIND_DATAA *data);
    BOOL FindNextFileA(HANDLE handle, CE_FIND_DATAA *data);
    BOOL FindClose(HANDLE handle);
  ]])
  local kernel = ffi.load("kernel32")
  local data = ffi.new("CE_FIND_DATAA[1]")
  local query = path:gsub("/", "\\"):gsub("\\+$", "")
    .. "\\" .. (pattern or "*")
  local handle = kernel.FindFirstFileA(query, data)
  if handle == ffi.cast("HANDLE", -1) then return {} end
  local out = {}
  repeat
    local name = ffi.string(data[0].name)
    local isDirectory = bit.band(tonumber(data[0].attributes), 0x10) ~= 0
    if name ~= "." and name ~= ".." and isDirectory == directories then
      out[#out + 1] = name
    end
  until kernel.FindNextFileA(handle, data) == 0
  kernel.FindClose(handle)
  return out
end

local function commandOutput(command)
  local pipe = io.popen(command, "r")
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = trim(result)
  return result ~= "" and result or nil
end

local function shellQuote(s)
  return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function hasCommand(name)
  -- Run via env -i-less host PATH. AppImages often see a tool in PATH that
  -- cannot actually show a GUI from inside the sandbox.
  local path = commandOutput(
    "command -v " .. name .. " 2>/dev/null || which " .. name .. " 2>/dev/null")
  return path ~= nil, path
end

-- LÖVE AppImages set LD_LIBRARY_PATH to bundled libs; host zenity/kdialog
-- then crash or exit 1 with no window. Strip those vars for dialogs.
local function hostCmd(cmd)
  return "env -u LD_LIBRARY_PATH -u LD_PRELOAD " .. cmd
end

-- Run a dialog command; returns path, status ("ok"|"cancel"|"fail").
-- Zenity/kdialog use exit 1 for user cancel; other non-zero = failed to show.
local function runDialog(cmd)
  -- Capture stdout + exit code. Keep stderr quiet.
  local wrapped = string.format(
    "OUT=$(%s 2>/dev/null); EC=$?; printf '%%s\\n' \"$OUT\"; printf '__EC:%%s\\n' \"$EC\"",
    hostCmd(cmd))
  local pipe = io.popen(wrapped, "r")
  if not pipe then return nil, "fail" end
  local body = pipe:read("*a") or ""
  pipe:close()
  local ec = tonumber(body:match("__EC:(%d+)")) or -1
  local out = trim((body:gsub("\n?__EC:%d+%s*$", "")))
  if out ~= "" and ec == 0 then return out, "ok" end
  if out ~= "" then return out, "ok" end -- some tools omit exit 0
  if ec == 1 then return nil, "cancel" end
  return nil, "fail"
end

-- Convert Windows "Label|*.gb;*.gbc|All|*.*" filters to zenity/kdialog forms.
local function linuxFileFilters(filter)
  filter = filter or "All files (*.*)|*.*"
  local zenity, kdialog = {}, {}
  local parts = {}
  for part in (filter .. "|"):gmatch("([^|]*)|") do
    parts[#parts + 1] = part
  end
  for i = 1, #parts - 1, 2 do
    local label = parts[i]
    local pats = parts[i + 1] or "*.*"
    local globs = {}
    for g in pats:gmatch("[^;]+") do
      g = trim(g)
      if g ~= "" then globs[#globs + 1] = g end
    end
    if #globs > 0 then
      zenity[#zenity + 1] = string.format("--file-filter=%s",
        shellQuote(label .. " | " .. table.concat(globs, " ")))
      kdialog[#kdialog + 1] = table.concat(globs, " ") .. "|" .. label
    end
  end
  return zenity, kdialog
end

local function linuxPickFile(title, filter)
  title = title or "Choose a file"
  local zenFilters, kdFilters = linuxFileFilters(filter)
  local home = os.getenv("HOME") or "."
  local sawCancel = false

  if hasCommand("zenity") then
    local cmd = "zenity --file-selection --title=" .. shellQuote(title)
    for _, f in ipairs(zenFilters) do cmd = cmd .. " " .. f end
    local path, st = runDialog(cmd)
    if path then return path, "ok" end
    if st == "cancel" then sawCancel = true else
      -- failed to show — try another backend
    end
  end
  if hasCommand("kdialog") then
    local filt = kdFilters[1] or "*.*|All files"
    local path, st = runDialog(string.format(
      "kdialog --getopenfilename %s %s --title %s",
      shellQuote(home), shellQuote(filt), shellQuote(title)))
    if path then return path, "ok" end
    if st == "cancel" then sawCancel = true end
  end
  if hasCommand("yad") then
    local path, st = runDialog("yad --file --title=" .. shellQuote(title))
    if path then return path, "ok" end
    if st == "cancel" then sawCancel = true end
  end

  -- Preserve cancellation as a distinct result. The caller only falls back
  -- to manual path entry when no picker backend is available.
  if sawCancel then return nil, "cancel" end
  return nil, "unavailable"
end

local function linuxPickFolder(title, startPath)
  title = title or "Choose a folder"
  startPath = startPath or (os.getenv("HOME") or ".")
  local sawCancel = false

  if hasCommand("zenity") then
    local path, st = runDialog(string.format(
      "zenity --file-selection --directory --title=%s --filename=%s",
      shellQuote(title), shellQuote(startPath .. "/")))
    if path then return path, "ok" end
    if st == "cancel" then sawCancel = true end
  end
  if hasCommand("kdialog") then
    local path, st = runDialog(string.format(
      "kdialog --getexistingdirectory %s --title %s",
      shellQuote(startPath), shellQuote(title)))
    if path then return path, "ok" end
    if st == "cancel" then sawCancel = true end
  end
  if hasCommand("yad") then
    local path, st = runDialog(string.format(
      "yad --file --directory --title=%s --filename=%s",
      shellQuote(title), shellQuote(startPath .. "/")))
    if path then return path, "ok" end
    if st == "cancel" then sawCancel = true end
  end

  if sawCancel then return nil, "cancel" end
  return nil, "unavailable"
end

function ModIO.repoRoot()
  local configured = os.getenv("POKEPORT_CONTENT_ROOT")
  if configured and configured ~= "" then return configured end
  if love and love.filesystem and love.filesystem.getSource then
    return love.filesystem.getSource()
  end
  return "."
end

function ModIO.modsRoot()
  return join(ModIO.repoRoot(), "mods")
end

function ModIO.isValidId(id)
  return type(id) == "string" and id:match("^[%w%-_]+$") ~= nil
end

function ModIO.projectPath(modDir)
  return join(modDir, "editor_project.lua")
end

function ModIO.exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function ModIO.ensureDirectory(path)
  if type(path) ~= "string" or path == "" then return false, "no directory" end
  local sep = package.config:sub(1, 1)
  local command = sep == "\\"
    -- cmd.exe's bare mkdir exits 1 when the directory already exists.  Export
    -- All calls this once per source, so make the operation idempotent.
    and ('if not exist "' .. path .. '" mkdir "' .. path .. '"')
    or ('mkdir -p "' .. path .. '"')
  local ok = os.execute(command)
  return ok == true or ok == 0, ok
end

function ModIO.engineVersion()
  local ok, Version = pcall(require, "src.core.Version")
  if ok and Version and Version.engine then return Version.engine end
  return "0.0.0-dev"
end

function ModIO.create(id, name, version)
  if not ModIO.isValidId(id) then
    return nil, "bad id (use letters, numbers, _ or -)"
  end
  local dest = join(ModIO.modsRoot(), id)
  if ModIO.exists(join(dest, "manifest.json")) then
    return nil, dest .. " already exists"
  end
  local engine = ModIO.engineVersion()
  local major = tonumber(engine:match("^(%d+)")) or 0
  local nextMajor = major + 1
  local display = name or id:gsub("[_%-]", " "):gsub("(%a)([%w]*)", function(a, b)
    return a:upper() .. b:lower()
  end)

  local function mkdir(path)
    if love and love.filesystem and love.filesystem.createDirectory then
      -- love.filesystem is sandboxed; use os.execute for source-tree mods
    end
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
      os.execute('mkdir "' .. path .. '" 2>nul')
    else
      os.execute('mkdir -p "' .. path .. '"')
    end
  end

  mkdir(dest)
  mkdir(join(dest, "assets"))

  local Generation = require("Generation")
  local target = version and { version = version } or nil
  local games = Generation.manifestGames(target)
  local gamesLit = {}
  for i, g in ipairs(games) do
    gamesLit[i] = string.format("%q", g)
  end
  local gamesJson = "[" .. table.concat(gamesLit, ", ") .. "]"
  local gen2compat = (Generation.coversGen2(games) or Generation.isGen2(target))
    and "true" or "false"
  local manifest = string.format([[{
  "id": "%s",
  "name": "%s",
  "version": "0.1.0",
  "api": 2,
  "entry": "main.lua",
  "profile": "content",
  "game_version": ">=%s <%d.0.0",
  "games": %s,
  "gen2compat": %s,
  "category": "GAMEPLAY",
  "priority": 100,
  "dependencies": [],
  "optional_dependencies": [],
  "conflicts": [],
  "incompatible": [],
  "experimental": false,
  "description": "Authored with the Gen1Recomp content editor"
}
]], id, display, engine, nextMajor, gamesJson, gen2compat)

  local mf, err = io.open(join(dest, "manifest.json"), "wb")
  if not mf then return nil, err end
  mf:write(manifest)
  mf:close()

  local keep = io.open(join(dest, "assets", ".gitkeep"), "wb")
  if keep then keep:close() end

  local project = State.blankProject(id, display)
  if version then project.game = version end
  local ok, werr = ModIO.save(dest, project)
  if not ok then return nil, werr end
  return dest, project
end

local function mainLooksHandWritten(modDir)
  local mainPath = join(modDir, "main.lua")
  local f = io.open(mainPath, "rb")
  if not f then return false end
  local body = f:read("*a") or ""
  f:close()
  if body == "" then return false end
  -- Content-editor emits this banner; anything else is treated as authored Lua.
  if body:find("generated by tools/content%-editor", 1, false) then
    return false
  end
  return true
end

function ModIO.load(modDir)
  local path = ModIO.projectPath(modDir)
  if not ModIO.exists(path) then
    local id = modDir:match("[/\\]([^/\\]+)$") or "mod"
    local project = State.blankProject(id, id)
    if mainLooksHandWritten(modDir) then
      project._protectMain = true
      return project,
        "hand-written main.lua detected — Save writes editor_project.lua + editor_apply.lua and leaves main.lua alone"
    end
    return project, "no editor_project.lua; started empty project (Save regenerates main.lua)"
  end
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, project = pcall(chunk)
  if not ok then return nil, project end
  if type(project) ~= "table" then return nil, "editor_project.lua must return a table" end
  project = State.ensureProjectFields(project)
  -- Drop typing partials (H / HI / HIDE_…) left in older editor_project.lua files.
  State.rebuildEventFlags(project)
  return project
end

-- Which game this mod is authored against (red/blue/yellow/gold/silver/crystal).
-- Stored on editor_project.game; inferred from maps or a pinned manifest.games.
function ModIO.authoringGame(project, modDir)
  local GameVersion = require("src.core.GameVersion")
  local function valid(id)
    return type(id) == "string" and GameVersion.VERSIONS
      and GameVersion.VERSIONS[id] and id or nil
  end
  local stored = valid(project and project.game)
  if stored then return stored end

  local Generation = require("Generation")
  local function bagLooksGen2(bag)
    if type(bag) ~= "table" then return false end
    for id, def in pairs(bag) do
      if type(id) == "string" and id:sub(1, 8) == "TILESET_" then return true end
      if type(def) == "table" and Generation.mapLooksGen2(def) then return true end
    end
    return false
  end
  if project and (bagLooksGen2(project.maps)
      or bagLooksGen2(project.layeredMaps)
      or bagLooksGen2(project.tilesets)) then
    local current = valid(GameVersion.get and GameVersion.get())
    if current and Generation.num({ version = current }) == 2 then
      return current
    end
    return "gold"
  end

  if type(modDir) ~= "string" or modDir == "" then return nil end
  local body = ModIO.readText(join(modDir, "manifest.json"))
  if not body then return nil end
  local ok, mf = pcall(Json.decode, body)
  if not ok or type(mf) ~= "table" or type(mf.games) ~= "table" then return nil end
  local pinned = {}
  local onlyGen2 = true
  local any = false
  for _, token in ipairs(mf.games) do
    any = true
    local key = tostring(token or ""):lower()
    if valid(key) then pinned[#pinned + 1] = key end
    if not Generation.isExclusiveGen2Token(key) then
      onlyGen2 = false
    end
  end
  if #pinned == 1 then return pinned[1] end
  if any and onlyGen2 then return pinned[1] or "gold" end
  return nil
end

function ModIO.save(modDir, project, version)
  -- Persist trainer_headers seeded from map trainer objects / special battles.
  ModWriter.ensureTrainerHeaders(project)
  -- Drop flag-name typing partials before writing editor_project / main.lua.
  State.rebuildEventFlags(project)

  local keepMain = project._protectMain == true
    or mainLooksHandWritten(modDir)
  if keepMain then project._protectMain = true end

  local body = ModWriter.serializeProject(project)
  local path = ModIO.projectPath(modDir)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return false, err end
  local wok, werr = f:write(body)
  if not wok then f:close(); os.remove(tmp); return false, werr end
  f:close()
  os.remove(path)
  local ok, rerr = os.rename(tmp, path)
  if not ok then return false, tostring(rerr) end

  -- Generated runtime payload. Hand-written main.lua stays untouched; it should
  -- load editor_apply.lua so editor edits still reach playtest.
  -- Game AssetTransform writes save/mod-derived/<manifest.id>/.  project.id
  -- can differ (this folder is Nihon-Extension, project.id is my_content).
  local derivedModId = project and project.id
  do
    local folder = tostring(modDir or ""):match("[/\\]([^/\\]+)$")
    local mfBody = ModIO.readText(join(modDir, "manifest.json"))
    local decodedOk, mf = false, nil
    if mfBody then decodedOk, mf = pcall(Json.decode, mfBody) end
    if decodedOk and type(mf) == "table" and type(mf.id) == "string"
        and mf.id ~= "" then
      derivedModId = mf.id
    elseif folder and folder ~= "" then
      derivedModId = folder
    end
  end
  local generated = ModWriter.emitMain(project, ModIO._emitBaseData, derivedModId)
  if keepMain then
    local applyPath = join(modDir, "editor_apply.lua")
    local af, aerr = io.open(applyPath, "wb")
    if not af then return false, aerr end
    af:write(generated)
    af:close()
  else
    local mainPath = join(modDir, "main.lua")
    local mf, merr = io.open(mainPath, "wb")
    if not mf then return false, merr end
    mf:write(generated)
    mf:close()

    -- Ship Schemas.lua when maps use block ids above 255, or on Gen1 when
    -- trainer party DV/moves/statExp overrides exist.
    local schemasPath = join(modDir, "Schemas.lua")
    local Generation = require("Generation")
    local schemaBody = ModWriter.contentSchemasLua(project, Generation.isGen2(nil))
    if schemaBody then
      local okS, errS = ModIO.writeText(schemasPath, schemaBody)
      if not okS then return false, errS end
    elseif ModIO.exists(schemasPath) then
      os.remove(schemasPath)
    end
  end

  -- Keep the generated display name aligned with the project. Compatibility
  -- is user-authored manifest metadata: selecting a ROM for editing or
  -- playtesting must not narrow a cross-generation mod's declared support.
  local manifestPath = join(modDir, "manifest.json")
  if ModIO.exists(manifestPath) then
    local mh = io.open(manifestPath, "rb")
    if mh then
      local text = mh:read("*a")
      mh:close()
      local manifest, decodeErr = Json.decode(text)
      if not manifest then return false, decodeErr end
      if project.name then manifest.name = project.name end
      local mw, manifestErr = io.open(manifestPath, "wb")
      if not mw then return false, manifestErr end
      mw:write(ModIO.encodeManifest(manifest))
      mw:close()
    end
  end
  if keepMain then return true, "kept-main" end
  return true
end

-- Escape for PowerShell single-quoted strings.
local function psQuote(s)
  return tostring(s or ""):gsub("'", "''")
end

-- Write a temp .ps1 and run it (avoids -Command quoting breakage). Returns
-- stdout path or nil.
local function windowsRunPs1(body)
  local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
  local ps1 = tmp .. "\\pokeport_ce_picker_" .. tostring(os.time())
    .. tostring(math.random(1000, 9999)) .. ".ps1"
  local f = io.open(ps1, "wb")
  if not f then return nil end
  -- UTF-8 BOM so PowerShell parses Unicode paths/titles correctly
  f:write(string.char(0xEF, 0xBB, 0xBF))
  f:write(body)
  f:close()
  local out = commandOutput(string.format(
    'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%s"', ps1))
  pcall(os.remove, ps1)
  if out then
    out = out:gsub("\r", ""):gsub("\n$", "")
    out = trim(out)
  end
  return (out and out ~= "") and out or nil
end

-- TopMost owner form so the dialog is not buried under the LÖVE window.
local function windowsDialogPreamble()
  return table.concat({
    "Add-Type -AssemblyName System.Windows.Forms",
    "Add-Type -AssemblyName System.Drawing",
    "[System.Windows.Forms.Application]::EnableVisualStyles()",
    "[Console]::OutputEncoding = [Text.Encoding]::UTF8",
    "$owner = New-Object System.Windows.Forms.Form",
    "$owner.TopMost = $true",
    "$owner.ShowInTaskbar = $false",
    "$owner.FormBorderStyle = 'FixedToolWindow'",
    "$owner.StartPosition = 'Manual'",
    "$owner.Size = New-Object System.Drawing.Size(1,1)",
    "$owner.Location = New-Object System.Drawing.Point(-32000,-32000)",
    "$owner.Opacity = 0",
    "$owner.Show()",
    "$owner.Activate()",
  }, "\r\n")
end

local function windowsDialogEpilogue()
  return table.concat({
    "$owner.Close()",
    "$owner.Dispose()",
  }, "\r\n")
end

-- Returns path, status ("ok"|"cancel"|"unavailable").
-- Older callers that only use the first return still work.
function ModIO.chooseFolder(title, startPath)
  local platform = (love and love.system and love.system.getOS
                    and love.system.getOS()) or ""
  title = title or "Choose a folder"
  startPath = startPath or ModIO.repoRoot()
  if platform == "OS X" then
    local path = commandOutput(string.format(
      [[osascript -e 'POSIX path of (choose folder with prompt "%s" default location POSIX file "%s")' 2>/dev/null]],
      title:gsub('"', '\\"'), startPath:gsub('"', '\\"')))
    return path, path and "ok" or "cancel"
  elseif platform == "Windows" then
    local body = table.concat({
      windowsDialogPreamble(),
      "$d = New-Object System.Windows.Forms.FolderBrowserDialog",
      string.format("$d.Description = '%s'", psQuote(title)),
      string.format("$d.SelectedPath = '%s'", psQuote(startPath)),
      "$d.ShowNewFolderButton = $false",
      "if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {",
      "  [Console]::Write($d.SelectedPath)",
      "}",
      windowsDialogEpilogue(),
    }, "\r\n")
    local path = windowsRunPs1(body)
    return path, path and "ok" or "cancel"
  elseif platform == "Linux" then
    return linuxPickFolder(title, startPath)
  end
  return nil, "unavailable"
end

function ModIO.chooseModDir()
  return ModIO.chooseFolder("Choose a mod folder", ModIO.modsRoot())
end

function ModIO.chooseFile(title, filter)
  local platform = (love and love.system and love.system.getOS
                    and love.system.getOS()) or ""
  title = title or "Choose a file"
  filter = filter or "All files (*.*)|*.*"
  if platform == "OS X" then
    local path = commandOutput(string.format(
      [[osascript -e 'POSIX path of (choose file with prompt "%s")' 2>/dev/null]],
      title:gsub('"', '\\"')))
    return path, path and "ok" or "cancel"
  elseif platform == "Windows" then
    -- Mirror RomImporter: copy pick to an ASCII temp path when it's a ROM so
    -- console codepage cannot mangle non-ASCII folder names.
    local isRom = filter:lower():find("%.gb") ~= nil
    local bodyLines = {
      windowsDialogPreamble(),
      "$d = New-Object System.Windows.Forms.OpenFileDialog",
      string.format("$d.Title = '%s'", psQuote(title)),
      string.format("$d.Filter = '%s'", psQuote(filter)),
      "$d.Multiselect = $false",
      "$d.CheckFileExists = $true",
      "if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {",
    }
    if isRom then
      bodyLines[#bodyLines + 1] =
        "  $t = Join-Path $env:TEMP 'pokeport_ce_rom_pick.gb'"
      bodyLines[#bodyLines + 1] =
        "  Copy-Item -LiteralPath $d.FileName -Destination $t -Force"
      bodyLines[#bodyLines + 1] = "  [Console]::Write($t)"
    else
      bodyLines[#bodyLines + 1] = "  [Console]::Write($d.FileName)"
    end
    bodyLines[#bodyLines + 1] = "}"
    bodyLines[#bodyLines + 1] = windowsDialogEpilogue()
    local path = windowsRunPs1(table.concat(bodyLines, "\r\n"))
    return path, path and "ok" or "cancel"
  elseif platform == "Linux" then
    return linuxPickFile(title, filter)
  end
  return nil, "unavailable"
end

function ModIO.copyFile(src, dest)
  local inf = io.open(src, "rb")
  if not inf then return false, "cannot read " .. tostring(src) end
  local data = inf:read("*a")
  inf:close()
  local dir = dest:match("^(.*)[/\\][^/\\]+$")
  if dir then
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
      os.execute('mkdir "' .. dir .. '" 2>nul')
    else
      os.execute('mkdir -p "' .. dir .. '"')
    end
  end
  local out = io.open(dest, "wb")
  if not out then return false, "cannot write " .. tostring(dest) end
  out:write(data)
  out:close()
  return true
end

local function ensureArrayValue(values, wanted)
  values = type(values) == "table" and values or {}
  for _, value in ipairs(values) do
    if value == wanted then return values end
  end
  values[#values + 1] = wanted
  return values
end

-- Map Builder owns one transform recipe. Keep the manifest wiring and its
-- least-privilege capability declaration together as one idempotent update.
function ModIO.setMapBuilderTransform(modDir, relative)
  if type(modDir) ~= "string" then return false, "no mod directory" end
  local path = join(modDir, "manifest.json")
  local body, readErr = ModIO.readText(path)
  if not body then return false, readErr end
  local manifest, decodeErr = Json.decode(body)
  if not manifest then return false, decodeErr end

  local current = manifest.assets_transforms
  if relative and relative ~= MAP_BUILDER_TRANSFORM then
    return false, "unsupported Map Builder transform " .. tostring(relative)
  end
  if relative and current and current ~= MAP_BUILDER_TRANSFORM then
    return false, "Map Builder cannot replace the existing assets_transforms file "
      .. tostring(current)
  end
  if relative then
    manifest.assets_transforms = MAP_BUILDER_TRANSFORM
    -- The generated recipe writes its flattened atlases into the derived
    -- asset cache through ctx.writeImage.  Keep the capability declaration
    -- in sync automatically; otherwise a freshly-authored layered map saves
    -- successfully but is rejected as soon as Playtest loads the mod.
    manifest.permissions = ensureArrayValue(
      manifest.permissions, FILESYSTEM_PERMISSION)
  elseif current == MAP_BUILDER_TRANSFORM then
    manifest.assets_transforms = nil
  end
  return ModIO.writeText(path, ModIO.encodeManifest(manifest))
end

function ModIO.removeMapBuilderTransform(modDir)
  local ok, err = ModIO.setMapBuilderTransform(modDir, nil)
  if not ok then return false, err end
  local path = join(modDir, MAP_BUILDER_TRANSFORM)
  if ModIO.exists(path) then
    local removed, removeErr = os.remove(path)
    if not removed then return false, removeErr end
  end
  return true
end

function ModIO.listMods()
  local root = ModIO.modsRoot()
  local out = {}
  local sep = package.config:sub(1, 1)
  local names = windowsNames(root, true)
  if sep == "\\" then
    names = names or {}
  else
    names = {}
    local pipe = io.popen(string.format('ls -1 "%s" 2>/dev/null', root), "r")
    if not pipe then return out end
    for line in pipe:lines() do names[#names + 1] = line end
    pipe:close()
  end
  for _, line in ipairs(names) do
    line = trim(line)
    if line ~= "" and line ~= "examples" and ModIO.exists(join(join(root, line), "manifest.json")) then
      out[#out + 1] = line
    end
  end
  table.sort(out)
  return out
end

function ModIO.listSubdirs(root)
  local out = {}
  if type(root) ~= "string" or root == "" then return out end
  local sep = package.config:sub(1, 1)
  local names
  if sep == "\\" then
    names = windowsNames(root, true) or {}
  else
    names = {}
    local pipe = io.popen(string.format('ls -1 "%s" 2>/dev/null', root), "r")
    if pipe then
      for line in pipe:lines() do names[#names + 1] = line end
      pipe:close()
    end
  end
  for _, line in ipairs(names) do
    line = trim(line)
    if line ~= "" and line ~= "." and line ~= ".." then
      out[#out + 1] = line
    end
  end
  table.sort(out)
  return out
end

function ModIO.modDir(id)
  if not id or id == "" then return nil end
  return join(ModIO.modsRoot(), id)
end

function ModIO.readText(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local body = f:read("*a") or ""
  f:close()
  return body
end

function ModIO.writeText(path, body)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return false, err end
  local ok, werr = f:write(body or "")
  if not ok then f:close(); os.remove(tmp); return false, werr end
  f:close()
  os.remove(path)
  local renamed, rerr = os.rename(tmp, path)
  if not renamed then return false, tostring(rerr) end
  return true
end

local function encodeJsonValue(v, indent)
  local t = type(v)
  if v == nil then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' end
      if c == "\\" then return "\\\\" end
      if c == "\n" then return "\\n" end
      if c == "\r" then return "\\r" end
      if c == "\t" then return "\\t" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  if t ~= "table" then error("cannot encode " .. t) end
  local n = #v
  local isArray = n > 0 or next(v) == nil
  if isArray then
    if n == 0 then return "[]" end
    local parts = { "[" }
    for i = 1, n do
      parts[#parts + 1] = (i > 1 and ", " or "") .. encodeJsonValue(v[i], indent)
    end
    parts[#parts + 1] = "]"
    return table.concat(parts)
  end
  local keys, seen = {}, {}
  for _, key in ipairs(MANIFEST_KEY_ORDER) do
    if v[key] ~= nil then
      keys[#keys + 1] = key
      seen[key] = true
    end
  end
  local extras = {}
  for key in pairs(v) do
    if not seen[key] then extras[#extras + 1] = key end
  end
  table.sort(extras)
  for _, key in ipairs(extras) do keys[#keys + 1] = key end
  if #keys == 0 then return "{}" end
  local pad = indent .. "  "
  local parts = { "{\n" }
  for i, key in ipairs(keys) do
    parts[#parts + 1] = pad .. encodeJsonValue(key, pad) .. ": "
      .. encodeJsonValue(v[key], pad)
    parts[#parts + 1] = (i < #keys and ",\n" or "\n")
  end
  parts[#parts + 1] = indent .. "}"
  return table.concat(parts)
end

function ModIO.encodeManifest(data)
  return encodeJsonValue(data or {}, "") .. "\n"
end

function ModIO.setManifestTarget(modDir, version, name)
  local path = join(modDir, "manifest.json")
  local body, readErr = ModIO.readText(path)
  if not body then return false, readErr end
  local manifest, decodeErr = Json.decode(body)
  if not manifest then return false, decodeErr end
  if name then manifest.name = name end
  -- `version` selects the runtime used by Playtest. It does not describe the
  -- complete compatibility surface of the mod, so preserve games and
  -- gen2compat exactly as authored in the manifest.
  return ModIO.writeText(path, ModIO.encodeManifest(manifest))
end

function ModIO.readManifest(modId)
  local dir = ModIO.modDir(modId)
  if not dir then return nil, "no mod id" end
  local path = join(dir, "manifest.json")
  local body, err = ModIO.readText(path)
  if not body then return nil, err end
  local data, derr = Json.decode(body)
  if not data then return nil, derr end
  return data, path
end

function ModIO.writeManifest(modId, data)
  local dir = ModIO.modDir(modId)
  if not dir then return false, "no mod id" end
  local path = join(dir, "manifest.json")
  return ModIO.writeText(path, ModIO.encodeManifest(data))
end

-- Lua files under a mod (root + one subdirectory level).
function ModIO.listModLuaFiles(modId)
  local dir = ModIO.modDir(modId)
  local out, seen = {}, {}
  if not dir then return out end
  local sep = package.config:sub(1, 1)
  local function add(rel)
    rel = tostring(rel or ""):gsub("\\", "/")
    if rel ~= "" and rel:lower():match("%.lua$") and not seen[rel] then
      seen[rel] = true
      out[#out + 1] = rel
    end
  end
  local function listNames(cmd)
    local names = {}
    local pipe = io.popen(cmd, "r")
    if not pipe then return names end
    for line in pipe:lines() do
      line = trim(line)
      if line ~= "" and line ~= "." and line ~= ".." then
        names[#names + 1] = line
      end
    end
    pipe:close()
    return names
  end
  if sep == "\\" then
    for _, name in ipairs(windowsNames(dir, false, "*.lua") or {}) do
      add(name)
    end
    for _, sub in ipairs(windowsNames(dir, true) or {}) do
      for _, name in ipairs(windowsNames(join(dir, sub), false, "*.lua") or {}) do
        add(sub .. "/" .. name)
      end
    end
  else
    for _, path in ipairs(listNames(string.format('ls -1 "%s"/*.lua 2>/dev/null', dir))) do
      add(path:match("([^/]+%.lua)$") or path)
    end
    for _, subPath in ipairs(listNames(string.format('ls -1 -d "%s"/*/ 2>/dev/null', dir))) do
      local sub = trim(subPath):gsub("/$", ""):match("([^/]+)$")
      if sub then
        for _, path in ipairs(listNames(
            string.format('ls -1 "%s/%s"/*.lua 2>/dev/null', dir, sub))) do
          local base = path:match("([^/]+%.lua)$")
          if base then add(sub .. "/" .. base) end
        end
      end
    end
  end
  table.sort(out)
  return out
end

function ModIO.readModFile(modId, rel)
  local dir = ModIO.modDir(modId)
  if not dir or not rel or rel:find("%.%.") then return nil, "bad path" end
  rel = rel:gsub("/", package.config:sub(1, 1))
  return ModIO.readText(join(dir, rel))
end

function ModIO.writeModFile(modId, rel, body)
  local dir = ModIO.modDir(modId)
  if not dir or not rel or rel:find("%.%.") then return false, "bad path" end
  rel = rel:gsub("/", package.config:sub(1, 1))
  return ModIO.writeText(join(dir, rel), body)
end

return ModIO
