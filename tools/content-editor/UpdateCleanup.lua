-- Remove only updater-owned scratch artifacts, never installation/user data.
local M = {}

function M.script(dir, windows, only)
  local function quote(s) return "'" .. s:gsub("'", windows and "''" or "'\\''") .. "'" end
  if windows then
    return "$ErrorActionPreference='Continue'\n$root=[IO.Path]::GetFullPath(" .. quote(dir) .. ")\n"
      .. "Get-ChildItem -LiteralPath $root -Force | Where-Object { "
      .. (only and "$_.Name -eq " .. quote(only) or
        "$_.Name -cmatch '^source-[0-9]+-[0-9]+$' -or $_.Name -cmatch '^(source|runtime)-[0-9a-fA-F]{40}\\.tar\\.gz$'")
      .. " } | ForEach-Object {\n"
      .. "  if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and [IO.Path]::GetDirectoryName($_.FullName) -eq $root) {\n"
      .. "    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue\n  }\n}\nexit 0\n"
  end
  return "#!/bin/sh\ncd " .. quote(dir) .. " || exit 0\n"
    .. "for item in " .. (only and quote(only) or "source-* runtime-*") .. "; do\n"
    .. "  [ -L \"$item\" ] && continue\n"
    .. (only and "" or "  printf '%s\\n' \"$item\" | LC_ALL=C grep -Eq '^(source-[0-9]+-[0-9]+|(source|runtime)-[0-9a-fA-F]{40}\\.tar\\.gz)$' || continue\n")
    .. "  rm -rf -- \"./$item\"\ndone\nexit 0\n"
end

return M
