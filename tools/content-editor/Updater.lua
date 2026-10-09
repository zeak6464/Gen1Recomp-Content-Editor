-- Automatically follow Content Editor main source commits. Stage in the save
-- folder, then replace only application-owned paths after the editor closes.
-- Git checkouts fast-forward safely; user mods, caches, saves and settings are preserved.

local M = {}
local Source = require("SourceUpdate")
local q

M.REPO = "zeak6464/Gen1Recomp-Content-Editor"
M.VERSION_FILE = "content-editor-version.txt"
M.COMMIT_FILE = "content-editor-commit.txt"
M.CHECK_INTERVAL = 15 * 60
M.ASSETS = {
  Windows = "gen1recomp-content-editor-win64.zip",
  Linux = "gen1recomp-content-editor-linux64.tar.gz",
  ["OS X"] = "gen1recomp-content-editor-macos-universal.tar.gz",
}
M.LAUNCHERS = { Windows = "ContentEditor.bat", Linux = "ContentEditor.sh", ["OS X"] = "ContentEditor.command" }

function M.apiUrl()
  local o = os.getenv("POKEPORT_UPDATE_API")
  if o and o ~= "" then return o end
  return "https://api.github.com/repos/" .. M.REPO .. "/commits/main"
end

function M.releasesPage()
  return "https://github.com/" .. M.REPO .. "/tree/main"
end

function M.parseCommit(text)
  local data, err = M.decodeJson(text or "")
  if type(data) ~= "table" then return nil, "couldn't read GitHub commit: " .. tostring(err) end
  if not Source.validSha(data.sha) then return nil, tostring(data.message or "invalid source commit") end
  local sha = data.sha:lower()
  return { tag = sha, name = "Source " .. sha:sub(1, 12),
    page = "https://github.com/" .. M.REPO .. "/commit/" .. sha,
    notes = M.cleanNotes(type(data.commit) == "table" and data.commit.message or ""),
    url = "https://api.github.com/repos/" .. M.REPO .. "/tarball/" .. sha,
    asset = "source-" .. sha .. ".tar.gz" }
end

-- A small JSON reader (the release API's answer) ------------------------------

function M.decodeJson(text)
  local pos = 1
  local function ws() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = text:sub(i, i)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local e = text:sub(i + 1, i + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if e == "u" then
          local code = tonumber(text:sub(i + 2, i + 5), 16) or 63
          i = i + 6
          if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == "\\u" then
            local low = tonumber(text:sub(i + 2, i + 5), 16) or 0xDC00
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            i = i + 6
          end
          if code < 0x80 then out[#out + 1] = string.char(code)
          elseif code < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
          elseif code < 0x10000 then
            out[#out + 1] = string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
          else
            out[#out + 1] = string.char(0xF0 + math.floor(code / 262144), 0x80 + math.floor(code / 4096) % 64,
              0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
          end
        else
          out[#out + 1] = map[e] or e
          i = i + 2
        end
      else
        local j = text:find('["\\]', i)
        if not j then error("unterminated string") end
        out[#out + 1] = text:sub(i, j - 1)
        i = j
      end
    end
  end
  function value()
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1; ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws()
        if text:sub(pos, pos) ~= '"' then error("expected a key at " .. pos) end
        local k = str(); ws()
        if text:sub(pos, pos) ~= ":" then error("expected : at " .. pos) end
        pos = pos + 1
        obj[k] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then error("expected , or } at " .. (pos - 1)) end
      end
    elseif c == "[" then
      local arr = {}
      pos = pos + 1; ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then error("expected , or ] at " .. (pos - 1)) end
      end
    elseif c == '"' then return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then error("unexpected character at " .. pos) end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local ok, result = pcall(value)
  if not ok then return nil, result end
  return result
end

-- Versions ---------------------------------------------------------------------

--- "content-editor-v0.1.104" -> { 0, 1, 104 }, or nil.
function M.parseVersion(tag)
  local v = tostring(tag or ""):match("v?(%d[%d%.]*)%s*$")
  if not v then return nil end
  local nums = {}
  for n in v:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
  return #nums > 0 and nums or nil
end

--- Is release tag `a` newer than `b`? (b nil = unknown: yes.)
function M.newer(a, b)
  local va, vb = M.parseVersion(a), M.parseVersion(b)
  if not va then return false end
  if not vb then return true end
  for i = 1, math.max(#va, #vb) do
    local x, y = va[i] or 0, vb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

--- "content-editor-v0.1.104" -> "v0.1.104".
function M.short(tag)
  if Source.validSha(tag) then return tag:sub(1, 12) end
  return tag and (tostring(tag):match("(v[%d%.]+)%s*$") or tostring(tag)) or "unknown"
end

--- The release API's answer -> { tag, name, notes, url, size, page }, or nil and why.
function M.parseRelease(text, platform)
  local data, err = M.decodeJson(text or "")
  if type(data) ~= "table" then return nil, "couldn't read the release list (" .. tostring(err) .. ")" end
  if data.message and not data.tag_name then return nil, "GitHub says: " .. tostring(data.message) end
  if not data.tag_name then return nil, "no release found" end
  local want = M.ASSETS[platform or "Windows"]
  local asset
  for _, a in ipairs(data.assets or {}) do
    if a.name == want then asset = a end
  end
  return {
    tag = data.tag_name, name = data.name or data.tag_name, page = data.html_url or M.releasesPage(),
    notes = M.cleanNotes(data.body), url = asset and asset.browser_download_url, size = asset and asset.size,
    asset = want,
  }
end

--- Release notes as a few plain lines (GitHub's generated notes are markdown).
function M.cleanNotes(body)
  local lines = {}
  for line in tostring(body or ""):gsub("\r", ""):gmatch("[^\n]+") do
    line = line:gsub("%*%*", ""):gsub("^#+%s*", ""):gsub("^[%*%-]%s+", "- ")
      :gsub(" by @[%w%-_]+ in https?://%S+", ""):gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
    if line:match("%S") and not line:match("^Full Changelog") and line ~= "What's Changed" then
      lines[#lines + 1] = line
    end
  end
  return lines
end

-- Where things are -------------------------------------------------------------

local function sep() return package.config:sub(1, 1) end
local function join(a, b) return (a:gsub("[/\\]+$", "")) .. sep() .. b end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end
M.exists = exists

local function readText(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function writeText(path, text)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(text); f:close()
  return true
end

local function fileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end"); f:close()
  return n
end

function M.platform()
  return love and love.system and love.system.getOS and love.system.getOS() or (sep() == "\\" and "Windows" or "Linux")
end

--- The editor's own folder (where ContentEditor.bat and main.lua are).
function M.root()
  local configured = os.getenv("POKEPORT_CONTENT_ROOT")
  if configured and configured ~= "" then return configured end
  return love and love.filesystem and love.filesystem.getSource() or "."
end

--- A source checkout (git) -- updated by fast-forward, never portable copying.
function M.isCheckout(root)
  root = root or M.root()
  return exists(join(join(root, ".git"), "HEAD")) or exists(join(root, ".git"))
end

function M.currentVersion(root)
  root = root or M.root()
  if M.isCheckout(root) then
    if M.checkoutVersionRoot ~= root then
      local pipe = io.popen("git -C " .. q(root) .. " rev-parse HEAD 2>" .. (M.platform() == "Windows" and "nul" or "/dev/null"))
      local sha = pipe and pipe:read("*l")
      if pipe then pipe:close() end
      M.checkoutVersion = Source.validSha(sha) and sha:lower() or nil
      M.checkoutVersionRoot = root
    end
    return M.checkoutVersion
  end
  local commit = readText(join(root or M.root(), M.COMMIT_FILE))
  commit = commit and commit:match("%S+")
  if Source.validSha(commit) then return commit:lower() end
  local text = readText(join(root or M.root(), M.VERSION_FILE))
  local tag = text and text:match("%S+")
  return tag
end

--- The working folder, in the editor's save folder.
function M.workDir()
  local o = os.getenv("POKEPORT_UPDATE_DIR")
  if o and o ~= "" then return o end
  love.filesystem.createDirectory("update")
  return join(love.filesystem.getSaveDirectory(), "update")
end

--- A line in update/restart.log (what the Restart button did), for when
-- something doesn't go as expected.
function M.log(line)
  local ok, dir = pcall(M.workDir)
  if not ok then return end
  local f = io.open(join(dir, "restart.log"), "ab")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. tostring(line) .. "\n"); f:close() end
end

--- The release an update just installed (once, the first time the editor
-- opens after it), or nil.
function M.justInstalled()
  local ok, dir = pcall(M.workDir)
  if not ok then return nil end
  local path = join(dir, "installed.txt")
  local text = readText(path)
  if not text then return nil end
  os.remove(path)
  return text:match("%S+")
end

-- Running tools in the background ------------------------------------------------

local ffiC
local function ffi()
  if ffiC ~= nil then return ffiC end
  local ok, lib = pcall(require, "ffi")
  if not ok then ffiC = false return false end
  if M.platform() == "Windows" then
    pcall(lib.cdef, [[
      typedef struct { unsigned long cb; char *lpReserved; char *lpDesktop; char *lpTitle;
        unsigned long dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        unsigned short wShowWindow, cbReserved2; unsigned char *lpReserved2; void *hStdInput, *hStdOutput, *hStdError;
      } UPD_STARTUPINFOA;
      typedef struct { void *hProcess; void *hThread; unsigned long dwProcessId, dwThreadId; } UPD_PROCESS_INFORMATION;
      int CreateProcessA(const char *, char *, void *, void *, int, unsigned long, void *, const char *,
        UPD_STARTUPINFOA *, UPD_PROCESS_INFORMATION *);
      int CloseHandle(void *);
      unsigned long GetCurrentProcessId(void);
    ]])
  else
    pcall(lib.cdef, "int getpid(void);")
  end
  ffiC = lib
  return lib
end

function M.pid()
  local lib = ffi()
  if not lib then return 0 end
  local ok, pid
  if M.platform() == "Windows" then ok, pid = pcall(function() return lib.C.GetCurrentProcessId() end)
  else ok, pid = pcall(function() return lib.C.getpid() end) end
  return ok and tonumber(pid) or 0
end

--- Run a script without waiting and without a window. Windows: a .bat
-- (hidden, or `visible` in its own console); elsewhere a sh script.
function M.launch(script, visible)
  if M.platform() == "Windows" then
    local lib = ffi()
    local cmd = ('cmd.exe /d /c ""%s""'):format(script)
    if lib then
      local buf = lib.new("char[?]", #cmd + 1, cmd)
      local si = lib.new("UPD_STARTUPINFOA"); si.cb = lib.sizeof(si)
      local pi = lib.new("UPD_PROCESS_INFORMATION")
      -- CREATE_NO_WINDOW | DETACHED... (hidden) or CREATE_NEW_CONSOLE (visible)
      local flags = visible and 0x00000010 or 0x08000000
      local ok, made = pcall(function() return lib.C.CreateProcessA(nil, buf, nil, nil, 0, flags, nil, nil, si, pi) end)
      if ok and made ~= 0 then
        lib.C.CloseHandle(pi.hThread); lib.C.CloseHandle(pi.hProcess)
        return true
      end
    end
    return os.execute(('start "%s" /min cmd /d /c ""%s""'):format("Content Editor update", script)) ~= nil
  end
  return os.execute(("sh '%s' >/dev/null 2>&1 &"):format(script)) ~= nil
end

q = function(path) -- quoted for the script (Windows paths get backslashes)
  if M.platform() == "Windows" then
    if not path:match("^%a+://") then path = path:gsub("/", "\\") end
    return '"' .. path .. '"'
  end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

--- A background job: `lines` (script body) run, then `done` holds its exit code.
local function job(name, lines)
  local dir = M.workDir()
  local done = join(dir, name .. ".done")
  os.remove(done)
  local win = M.platform() == "Windows"
  local script = join(dir, name .. (win and ".bat" or ".sh"))
  local body
  if win then
    body = "@echo off\r\ncd /d " .. q(dir) .. "\r\ncall :main\r\n> " .. q(done) .. " echo %errorlevel%\r\nexit /b\r\n:main\r\n"
      .. table.concat(lines, "\r\n") .. "\r\nexit /b %errorlevel%\r\n"
  else
    body = "#!/bin/sh\ncd " .. q(dir) .. "\n( " .. table.concat(lines, "\n") .. "\n)\necho $? > " .. q(done) .. "\n"
  end
  if not writeText(script, body) then return nil, "couldn't write " .. script end
  if not M.launch(script) then return nil, "couldn't start " .. script end
  return { done = done, started = os.time() }
end

--- nil while running; then true / false (and the exit code).
local function finished(j)
  local code = j and readText(j.done)
  if not code then return nil end
  code = tonumber(code:match("%-?%d+")) or 1
  return code == 0, code
end

local function fetchLines(url, out, api)
  local accept = api and "-H \"Accept: application/vnd.github+json\" " or ""
  local timeout = api and "45" or "600"
  if M.platform() == "Windows" then
    local o = q(out):sub(2, -2)
    return {
      "where curl.exe >nul 2>nul",
      "if %errorlevel%==0 (",
      "  curl.exe -fsSL --max-time " .. timeout .. " --connect-timeout 15 " .. accept .. "-o " .. q(out) .. " " .. q(url),
      ") else (",
      "  powershell -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -TimeoutSec " .. timeout .. " -UseBasicParsing -Uri '"
        .. url:gsub("'", "''") .. "' -OutFile '" .. o:gsub("'", "''") .. "'\"",
      ")",
    }
  end
  return {
    "if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time " .. timeout .. " --connect-timeout 15 " .. accept:gsub('"', "'") .. "-o "
      .. q(out) .. " " .. q(url) .. "; else wget -q -T " .. timeout .. " -t 1 -O " .. q(out) .. " " .. q(url) .. "; fi",
  }
end

local function cleanupCommand(dir, only)
  local win = M.platform() == "Windows"
  local script = join(dir, (only and "cleanup-installed" or "cleanup") .. (win and ".ps1" or ".sh"))
  if not writeText(script, require("UpdateCleanup").script(dir, win, only)) then return nil end
  return (win and "powershell -NoProfile -ExecutionPolicy Bypass -File " or "sh ") .. q(script)
end

-- The steps --------------------------------------------------------------------
-- M.state: { step = "idle" | "checking" | "ready" | "latest" | "downloading" |
--   "unpacking" | "staged" | "error", release =, error =, auto = }

M.state = { step = "idle" }

--- Automatic updates (check at start and every 15 minutes, download, install
-- on close). Off with Settings > Updates or POKEPORT_NO_UPDATE_CHECK=1; the
-- Updates button can still check and install by hand.
function M.autoEnabled()
  if os.getenv("POKEPORT_NO_UPDATE_CHECK") == "1" then return false end
  local ok, on = pcall(function() return require("EditorSettings").get("autoUpdate") end)
  return not ok or on ~= false
end

function M.check(auto)
  if M.state.step == "checking" or M.state.step == "downloading" or M.state.step == "unpacking"
      or M.state.step == "staged" or M.state.step == "installing" then return end
  M.nextCheck = os.time() + M.CHECK_INTERVAL
  M.checkoutVersionRoot = nil
  local okDir, dir = pcall(M.workDir)
  if not okDir then M.state = { step = "error", error = "no update folder: " .. tostring(dir), auto = auto } return end
  local out = join(dir, "latest.json")
  os.remove(out)
  local lines = fetchLines(M.apiUrl(), out, true)
  local cleanup = cleanupCommand(dir)
  if cleanup then table.insert(lines, 1, cleanup) end
  local j, err = job("check", lines)
  if not j then M.state = { step = "error", error = err, auto = auto } return end
  M.state = { step = "checking", job = j, file = out, auto = auto }
end

function M.download()
  local rel = M.state.release
  if M.state.step ~= "ready" or not rel or not rel.url then return end
  local dir = M.workDir()
  if M.isCheckout() then
    local win = M.platform() == "Windows"
    local script = join(dir, win and "prepare-checkout.ps1" or "prepare-checkout.sh")
    local log = join(dir, "checkout.log")
    local body = require("GitUpdate").script(M.root(), rel.tag, win)
    if not writeText(script, body) then M.state.step, M.state.error = "error", "couldn't prepare Git update" return end
    local command = (win and "powershell -NoProfile -ExecutionPolicy Bypass -File " or "sh ") .. q(script)
    local j, err = job("checkout", { command .. " > " .. q(log) .. " 2>&1" })
    if not j then M.state.step, M.state.error = "error", err return end
    M.state.step, M.state.job, M.state.checkout, M.state.log = "downloading", j, true, log
    return
  end
  local pkg = join(dir, rel.asset)
  M.downloadNumber = (M.downloadNumber or 0) + 1
  local staged = join(dir, "source-" .. os.time() .. "-" .. M.downloadNumber)
  os.remove(pkg)
  local lines = fetchLines(rel.url, pkg)
  if M.platform() == "Windows" then
    lines[#lines + 1] = "if not %errorlevel%==0 exit /b %errorlevel%"
    lines[#lines + 1] = "mkdir " .. q(staged)
    -- GNU tar (e.g. Git Bash's) reads "C:\..." as a remote host; use Windows' bsdtar.
    lines[#lines + 1] = 'set "TAR=%SystemRoot%\\System32\\tar.exe"'
    lines[#lines + 1] = 'if not exist "%TAR%" set "TAR=tar"'
    lines[#lines + 1] = '"%TAR%" -xzf ' .. q(pkg) .. " -C " .. q(staged) .. " --strip-components=1"
  else
    lines[#lines + 1] = "[ -s " .. q(pkg) .. " ] || exit 1"
    lines[#lines + 1] = "mkdir -p " .. q(staged) .. " || exit 1"
    lines[#lines + 1] = "tar -xzf " .. q(pkg) .. " -C " .. q(staged) .. " --strip-components=1"
  end
  local j, err = job("download", lines)
  if not j then M.state.step, M.state.error = "error", err return end
  M.state.step, M.state.job, M.state.pkg, M.state.staged = "downloading", j, pkg, staged
end

--- The unpacked editor folder inside `staged` (the pack has one top folder).
function M.findPackage(staged)
  if exists(join(staged, "main.lua")) then return staged end
  local win = M.platform() == "Windows"
  local list = win and io.popen('dir /b /ad "' .. staged .. '" 2>nul') or io.popen("ls -1 '" .. staged .. "' 2>/dev/null")
  local found
  if list then
    for name in list:lines() do
      local p = join(staged, name)
      if not found and exists(join(p, "main.lua")) then found = p end
    end
    list:close()
  end
  return found
end

--- Call every frame: moves the steps along.
function M.poll()
  local st = M.state
  if M.autoEnabled() and M.nextCheck and os.time() >= M.nextCheck and
      (st.step == "latest" or st.step == "error" or st.step == "ready" or st.step == "blocked") then
    M.check(true)
    return
  end
  if st.step == "checking" then
    local ok = finished(st.job)
    if ok == nil then
      if os.time() - st.job.started > 60 then M.state = { step = "error", error = "the check timed out", auto = st.auto } end
      return
    end
    if not ok then M.state = { step = "error", error = "couldn't reach GitHub (offline?)", auto = st.auto } return end
    local rel, err = M.parseCommit(readText(st.file))
    if not rel then M.state = { step = "error", error = err, auto = st.auto } return end
    local current = M.currentVersion()
    local newer = rel.tag ~= current
    M.state = { step = newer and "ready" or "latest", release = rel, current = current, auto = st.auto, checked = os.time() }
    -- With automatic updates off, a check only reports; Download update fetches it.
    if newer and M.autoEnabled() then M.download() end
  elseif st.step == "downloading" then
    local ok = finished(st.job)
    if st.checkout then
      if ok == nil then return end
      if not ok then
        st.step, st.error = "blocked", "Git could not safely fast-forward this checkout. Local changes and mods were kept. Details: " .. st.log
        return
      end
      st.step = "staged"
      return
    end
    st.got = fileSize(st.pkg)
    if ok == nil then return end
    if not ok then st.step, st.error = "error", "the download failed" return end
    local pin = M.decodeJson(readText(join(st.staged, ".github/runtime-upstream.json")) or "")
    if type(pin) ~= "table" or pin.repository ~= "bryanthaboi/gen1recomp" or not Source.validSha(pin.integratedCommit) then
      st.step, st.error = "error", "source has no valid pinned runtime" return
    end
    local runtimeArchive = join(M.workDir(), "runtime-" .. pin.integratedCommit .. ".tar.gz")
    local packageDir = join(st.staged, "package")
    local win = M.platform() == "Windows"
    local script = join(st.staged, win and "stage.ps1" or "stage.sh")
    if not writeText(script, Source.stageScript(st.staged, packageDir, runtimeArchive, win)) then
      st.step, st.error = "error", "couldn't write source staging script" return
    end
    local lines = fetchLines("https://api.github.com/repos/" .. pin.repository .. "/tarball/" .. pin.integratedCommit, runtimeArchive)
    lines[#lines + 1] = win and "if not %errorlevel%==0 exit /b %errorlevel%" or "[ -s " .. q(runtimeArchive) .. " ] || exit 1"
    lines[#lines + 1] = (win and "powershell -NoProfile -ExecutionPolicy Bypass -File " or "sh ") .. q(script)
    local j, err = job("stage", lines)
    if not j then st.step, st.error = "error", err return end
    st.step, st.job, st.package, st.runtimeArchive = "unpacking", j, packageDir, runtimeArchive
  elseif st.step == "unpacking" then
    local ok = finished(st.job)
    if ok == nil then return end
    if not ok or not exists(join(st.package, "runtime/gen1recomp.love")) then
      st.step, st.error = "error", "source staging failed (tar and, on Linux/macOS, zip are required)" return
    end
    os.remove(st.pkg)
    os.remove(st.runtimeArchive)
    st.step = "staged"
  end
end

--- Write the helper that swaps the files in once the editor has closed,
-- start it, and return true (the editor should quit straight after).
function M.install(relaunch)
  local st = M.state
  if st.step ~= "staged" or (not st.package and not st.checkout) then return nil, "nothing downloaded" end
  local root = M.root()
  if M.isCheckout(root) and not st.checkout then return nil, "this editor is a git checkout" end
  local pid = M.pid()
  if pid <= 0 then return nil, "couldn't identify the editor process" end
  if not Source.validSha(st.release.tag) then return nil, "invalid source commit" end
  if not st.checkout and not writeText(join(st.package, M.COMMIT_FILE), st.release.tag .. "\n") then
    return nil, "couldn't record source commit"
  end
  local win = M.platform() == "Windows"
  local script = join(st.staged or M.workDir(), win and "install.ps1" or "install.sh")
  local launcher = M.LAUNCHERS[M.platform()] or "ContentEditor.sh"
  local restart = relaunch ~= false and os.getenv("POKEPORT_UPDATE_NO_RELAUNCH") ~= "1"
  local body
  if st.checkout then
    body = require("GitUpdate").script(root, st.release.tag, win, pid, restart and launcher or nil)
  else
    body = Source.installScript(root, st.package, pid, win, launcher, restart)
  end
  if not writeText(script, body) then return nil, "couldn't write the helper" end
  local command = (win and "powershell -NoProfile -ExecutionPolicy Bypass -File " or "sh ") .. q(script)
  local lines = {
    command .. " > " .. q(join(M.workDir(), "install.log")) .. " 2>&1",
    win and "if not %errorlevel%==0 exit /b %errorlevel%" or "[ $? -eq 0 ] || exit 1",
    "echo " .. st.release.tag .. " > " .. q(join(M.workDir(), "installed.txt")),
  }
  if st.staged then
    local name = st.staged:match("([^/\\]+)$")
    if name and name:match("^source-%d+-%d+$") then
      local cleanup = cleanupCommand(M.workDir(), name)
      if cleanup then lines[#lines + 1] = cleanup end
    end
  end
  local j, err = job("install", lines)
  if not j then return nil, err end
  st.step = "installing"
  return true
end

return M
