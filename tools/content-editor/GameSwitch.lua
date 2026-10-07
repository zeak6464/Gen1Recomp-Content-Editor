local M = {}
function M.start(version, DataSource)
  local prefs = DataSource.loadPrefs()
  local root = DataSource.cacheRootFor(prefs, version)
  local channel = love.thread.newChannel()
  local thread = love.thread.newThread("tools/content-editor/Gen3GameSwitchWorker.lua")
  thread:start(channel, {tables=require("Gen3").cacheTables,
    prefix=require("src.core.GameVersion").cachePrefix(version), root=root,
    packagePath=package.path, requirePath=love.filesystem.getRequirePath()})
  return {version=version, channel=channel, thread=thread}
end
function M.poll(job)
  job.prepared = job.prepared or {}
  local clock = love and love.timer and love.timer.getTime
  local start = clock and clock()
  while true do
    local message = job.channel:pop()
    if not message then break end
    if message.complete then return true, job.prepared end
    if message.error then return true, nil, message.error end
    job.progress = message.progress or job.progress
    if message.path then job.prepared[message.path] = {bytes=message.bytes, value=message.value} end
    -- Large table transfers also take time. Spread them across frames instead
    -- of copying the entire decoded cache in the completion frame.
    if clock and clock() - start >= .004 then return false end
  end
  local err = job.thread:getError()
  if err then return true, nil, err end
  return false
end
return M
