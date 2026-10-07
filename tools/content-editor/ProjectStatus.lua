-- Keep filesystem discovery out of the Project panel's per-frame hot path.
local M = {}
function M.get(S, DataSource, ModIO, order)
  local now = love.timer.getTime()
  local old = S._projectStatus
  if old and old.version == S.version and old.project == S.project
      and old.source == S.dataSource and old.dataPrefs == S.dataPrefs
      and now - old.at < 3 then return old end
  local prefs = DataSource.loadPrefs()
  local root = (S.dataPrefs and S.dataPrefs.recompRoot) or prefs.recompRoot
    or (DataSource.mountedRecompRoot and DataSource.mountedRecompRoot())
  if root == "" then root = nil end
  local status = {at=now, version=S.version, project=S.project,
    source=S.dataSource, dataPrefs=S.dataPrefs, prefs=prefs, root=root,
    mods=ModIO.listMods(), ready={}, imported={}}
  status.validRoot = root ~= nil and DataSource.isValidRecompRoot(root)
  for _, version in ipairs(order) do
    status.imported[version] = DataSource.hasImportedCacheMarker(version)
    status.ready[version] = status.imported[version]
      or DataSource.hasLocalCache(version)
      or (root and DataSource.recompHasVersion(root, version)) or false
  end
  S._projectStatus = status
  return status
end
return M
