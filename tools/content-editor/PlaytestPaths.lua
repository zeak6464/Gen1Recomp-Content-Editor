local PlaytestPaths = {}

local function separator()
  return package.config:sub(1, 1)
end

function PlaytestPaths.linkedRuntime(envRoot, selectedRoot, savedRoot, mountedRoot, isLaunchable)
  -- A mounted ROM cache supplies editor data, but cannot launch the game.
  for _, root in ipairs({envRoot or "", selectedRoot or "", savedRoot or "", mountedRoot or ""}) do
    if root ~= "" and isLaunchable(root) then
      return (root:gsub("[/\\]+$", ""))
    end
  end
end

function PlaytestPaths.absoluteFromRoot(path, root)
  path = tostring(path or "")
  local windowsAbsolute = path:match("^%a:[/\\]") ~= nil
    or path:match("^[/\\][/\\]") ~= nil
  local unixAbsolute = path:sub(1, 1) == "/"
  if windowsAbsolute or unixAbsolute then return path end
  return root .. separator() .. path
end

function PlaytestPaths.same(a, b)
  local sep = separator()
  local function normalize(path)
    path = tostring(path or ""):gsub("[/\\]+", sep):gsub("[/\\]+$", "")
    if sep == "\\" then path = path:lower() end
    return path
  end
  return normalize(a) == normalize(b)
end

function PlaytestPaths.pinnedRuntime(root, isValidRoot, isFile)
  local candidate = tostring(root or "") .. separator()
    .. "runtime" .. separator() .. "gen1recomp"
  if type(isValidRoot) == "function" and isValidRoot(candidate) then
    return candidate
  end
  local archive = candidate .. ".love"
  if type(isFile) == "function" and isFile(archive) then return archive end
  local fused = tostring(root or "") .. separator() .. "love"
    .. separator() .. "gen1recomp.exe"
  if type(isFile) == "function" and isFile(fused) then return fused end
  return nil
end

function PlaytestPaths.windowsLaunch(loveExe, runtimeSource, workDir, version)
  local source = runtimeSource
  if version == nil then
    version, workDir, source = workDir, runtimeSource, runtimeSource
  end
  -- Non-empty title: cmd /c start "" eats the empty quotes, then the next
  -- quoted string (often love.exe) is treated as the window title and the
  -- process exits immediately — playtest looks like it opens and closes.
  -- /D keeps cwd on the game folder. start otherwise resets cwd to love.exe.
  return string.format('start "Gen1RecompPlaytest" /D "%s" "%s" "%s" --game=%s',
    workDir, loveExe, source, version)
end

-- Write a .bat so os.execute does not nest cmd /c start quoting.
function PlaytestPaths.windowsDetach(startCmd)
  local tmp = os.getenv("TEMP") or os.getenv("TMP")
  if not tmp or tmp == "" or type(startCmd) ~= "string" then return startCmd end
  local bat = tmp .. "\\pokeport_playtest.bat"
  local f = io.open(bat, "wb")
  if not f then return startCmd end
  f:write("@echo off\r\n")
  f:write(startCmd)
  f:write("\r\n")
  f:close()
  return '"' .. bat .. '"'
end

return PlaytestPaths
