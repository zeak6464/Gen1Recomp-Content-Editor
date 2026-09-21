-- Mount the pinned Gen1Recomp directory into the editor's PhysFS root.
-- love.filesystem.mount cannot mount an arbitrary source-relative directory
-- on desktop, so use the same native PHYSFS_mount entry point as Gen1Recomp's
-- cache layer. This bootstrap deliberately has no runtime-module dependency.

local RuntimeMount = {}

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function join(a, b)
  local sep = package.config:sub(1, 1)
  a = tostring(a or ""):gsub("[/\\]+$", "")
  b = tostring(b or ""):gsub("^[/\\]+", "")
  return a .. sep .. b
end

local function looksLikeRecomp(path)
  if type(path) ~= "string" or path == "" then return false end
  return fileExists(join(path, "src/core/GameVersion.lua"))
    or fileExists(join(path, "src\\core\\GameVersion.lua"))
end

local function unescapeJson(s)
  return (tostring(s or ""):gsub("\\u(%x%x%x%x)", function(h)
    return string.char(tonumber(h, 16) % 256)
  end):gsub("\\/", "/"):gsub("\\\\", "\\"):gsub('\\"', '"'))
end

local function linkedRecompPath()
  local env = os.getenv("POKEPORT_RECOMP")
  if looksLikeRecomp(env) then return env end
  local save = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory()
  local prefs = save and join(save, "content_editor_data.json")
  local body = prefs and fileExists(prefs) and (function()
    local f = io.open(prefs, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
  end)()
  local raw = body and body:match('"recompRoot"%s*:%s*"([^"]*)"')
  local path = raw and unescapeJson(raw)
  if looksLikeRecomp(path) then return path end
  return nil
end

local function loveDllCandidates()
  local paths = {}
  local exe = love.filesystem.getExecutablePath and love.filesystem.getExecutablePath()
  if type(exe) == "string" and exe ~= "" then
    local dir = exe:match("^(.*)[/\\][^/\\]+$")
    if dir then
      paths[#paths + 1] = join(dir, "love.dll")
      paths[#paths + 1] = join(dir, "love")
    end
  end
  paths[#paths + 1] = "love"
  return paths
end

-- Every PHYSFS_mount we can reach. Windows often has the symbol on love.dll
-- (next to love.exe) rather than ffi.C; keep trying after a failed call.
local function physfsMountFns()
  local fns = {}
  if love.filesystem.mountFullPath then
    fns[#fns + 1] = function(path)
      local ok, result = pcall(love.filesystem.mountFullPath, path, "", true)
      return ok and result
    end
  end
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi then return fns end
  pcall(ffi.cdef,
    "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  local libraries = { function() return ffi.C end }
  for _, dll in ipairs(loveDllCandidates()) do
    local name = dll
    libraries[#libraries + 1] = function() return ffi.load(name) end
  end
  local seen = {}
  for _, getLibrary in ipairs(libraries) do
    local loaded, library = pcall(getLibrary)
    if loaded and library then
      local found, fn = pcall(function() return library.PHYSFS_mount end)
      if found and fn and not seen[tostring(fn)] then
        seen[tostring(fn)] = true
        fns[#fns + 1] = function(path)
          -- Append: editor-owned tools at the package root must win collisions
          -- such as tools/save-editor/Kit.lua.
          local called, result = pcall(fn, path, "", 1)
          return called and result ~= 0
        end
      end
    end
  end
  return fns
end

local function runtimeComplete(fs)
  return fs.getInfo("src/core/GameVersion.lua", "file")
    and fs.getInfo("src/mods/Loader.lua", "file")
end

local function addRequirePath(root)
  local prefix = tostring(root or ""):gsub("\\", "/"):gsub("/+$", "")
  if prefix == "" then return end
  local extra = prefix .. "/?.lua;" .. prefix .. "/?/init.lua;"
  package.path = extra .. package.path
end

local function requirePathComplete(root)
  return looksLikeRecomp(root)
end

local function jsonEscape(s)
  return tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function saveLinkedRoot(path)
  if type(path) ~= "string" or path == "" then return end
  path = path:gsub("[/\\]+$", "")
  local encoded = jsonEscape(path)
  local existing = love.filesystem.read and love.filesystem.read("content_editor_data.json")
  local body
  if type(existing) == "string" and existing:find("{", 1, true) then
    if existing:find('"recompRoot"', 1, true) then
      body = existing:gsub('"recompRoot"%s*:%s*"[^"]*"',
        '"recompRoot":"' .. encoded .. '"', 1)
    else
      body = existing:gsub("{", '{"recompRoot":"' .. encoded .. '",', 1)
    end
  else
    body = '{"mode":"auto","recompRoot":"' .. encoded
      .. '","useGbcPalettes":true,"lastVersion":"red"}'
  end
  pcall(love.filesystem.write, "content_editor_data.json", body)
end

local function commandOutput(command)
  local pipe = io.popen(command, "r")
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = result and result:gsub("^%s+", ""):gsub("%s+$", "") or ""
  return result ~= "" and result or nil
end

-- First-run prompt so a new user can point at their own Gen1Recomp checkout.
local function chooseRecompFolder()
  local platform = (love and love.system and love.system.getOS
    and love.system.getOS()) or ""
  local title = "Choose your Gen1Recomp folder"
  if platform == "OS X" then
    local home = os.getenv("HOME") or "/"
    local path = commandOutput(string.format(
      [[osascript -e 'POSIX path of (choose folder with prompt "%s" default location POSIX file "%s")' 2>/dev/null]],
      title:gsub('"', '\\"'), home:gsub('"', '\\"')))
    if path then path = path:gsub("/+$", "") end
    return looksLikeRecomp(path) and path or nil
  elseif platform == "Windows" then
    local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
    local ps1 = tmp .. "\\pokeport_ce_recomp_" .. tostring(os.time()) .. ".ps1"
    local f = io.open(ps1, "wb")
    if not f then return nil end
    f:write(string.char(0xEF, 0xBB, 0xBF))
    f:write(table.concat({
      "Add-Type -AssemblyName System.Windows.Forms",
      "Add-Type -AssemblyName System.Drawing",
      "$owner = New-Object System.Windows.Forms.Form",
      "$owner.TopMost = $true",
      "$owner.ShowInTaskbar = $false",
      "$owner.FormBorderStyle = 'FixedToolWindow'",
      "$owner.StartPosition = 'Manual'",
      "$owner.Size = New-Object System.Drawing.Size(1,1)",
      "$owner.Location = New-Object System.Drawing.Point(-32000,-32000)",
      "$owner.Opacity = 0",
      "$owner.Show(); $owner.Activate()",
      "$d = New-Object System.Windows.Forms.FolderBrowserDialog",
      "$d.Description = '" .. title:gsub("'", "''") .. "'",
      "$d.ShowNewFolderButton = $false",
      "if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {",
      "  [Console]::Write($d.SelectedPath)",
      "}",
      "$owner.Close(); $owner.Dispose()",
    }, "\r\n"))
    f:close()
    local path = commandOutput(string.format(
      'powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%s"', ps1))
    pcall(os.remove, ps1)
    if path then path = path:gsub("\r", ""):gsub("[/\\]+$", "") end
    return looksLikeRecomp(path) and path or nil
  elseif platform == "Linux" then
    local home = os.getenv("HOME") or "."
    local path = commandOutput(string.format(
      "zenity --file-selection --directory --title=%s --filename=%s 2>/dev/null",
      "'" .. title:gsub("'", "'\\''") .. "'",
      "'" .. (home .. "/"):gsub("'", "'\\''") .. "'"))
    if not path then
      path = commandOutput(string.format(
        "kdialog --getexistingdirectory %s --title %s 2>/dev/null",
        "'" .. home:gsub("'", "'\\''") .. "'",
        "'" .. title:gsub("'", "'\\''") .. "'"))
    end
    if path then path = path:gsub("/+$", "") end
    return looksLikeRecomp(path) and path or nil
  end
  return nil
end

local function tryMount(fs, candidates, fns)
  for i = 1, #candidates do
    for j = 1, #fns do
      pcall(fns[j], candidates[i])
      if runtimeComplete(fs) then return true end
    end
  end
  if runtimeComplete(fs) then return true end
  for i = 1, #candidates do
    if requirePathComplete(candidates[i]) then
      addRequirePath(candidates[i])
      return true
    end
  end
  return false
end

-- Recent runtimes no longer expose CacheFs.mountExternal. Keep data linking
-- independent of that private helper, using the same desktop mount boundary.
function RuntimeMount.mountData(path)
  for _,mount in ipairs(physfsMountFns()) do if mount(path) then return true end end
  return false
end

function RuntimeMount.unmountData(path)
  if love.filesystem.unmountFullPath then return love.filesystem.unmountFullPath(path) end
  local ok,ffi=pcall(require,"ffi")
  if not ok then return false end
  pcall(ffi.cdef,"int PHYSFS_unmount(const char *oldDir);")
  for _,name in ipairs(loveDllCandidates()) do
    local loaded,lib=pcall(ffi.load,name)
    if loaded then
      local called,result=pcall(function() return lib.PHYSFS_unmount(path) end)
      if called and result~=0 then return true end
    end
  end
  return false
end

function RuntimeMount.mount()
  local fs = assert(love and love.filesystem, "LÖVE filesystem unavailable")
  if runtimeComplete(fs) then return true end

  local separator = package.config:sub(1, 1)
  local source = assert(fs.getSource(), "LÖVE source directory unavailable")
  local root = source:gsub("[/\\]+$", "")
  local archive = root .. separator .. "runtime" .. separator .. "gen1recomp.love"
  local fused = root .. separator .. "love" .. separator .. "gen1recomp.exe"
  local directory = root .. separator .. "runtime" .. separator .. "gen1recomp"
  local candidates = {}
  local function add(path)
    if type(path) ~= "string" or path == "" then return end
    for i = 1, #candidates do
      if candidates[i] == path then return end
    end
    candidates[#candidates + 1] = path
  end
  add(linkedRecompPath())
  if fileExists(archive) then add(archive) end
  if fileExists(fused) then add(fused) end
  if looksLikeRecomp(directory) then add(directory) end
  add(linkedRecompPath())
  local content = os.getenv("POKEPORT_CONTENT_ROOT")
  if content and content ~= "" then
    add(join(content, "runtime" .. separator .. "gen1recomp"))
    add(join(content, ".content-editor-runtime" .. separator
      .. "runtime" .. separator .. "gen1recomp"))
  end
  local parent = root:match("^(.*)[/\\][^/\\]+$")
  if parent then
    add(join(parent, "gen1recomp"))
    add(join(parent, "Gen1Recomp"))
  end

  local fns = physfsMountFns()
  if tryMount(fs, candidates, fns) then return true end

  local picked = chooseRecompFolder()
  if picked then
    saveLinkedRoot(picked)
    add(picked)
    if tryMount(fs, { picked }, fns) then return true end
  end
  return false
end

return RuntimeMount
