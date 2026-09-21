-- generated editor entry wrapper: original mod stays intact
return function(mod)
  local function run(path)
    local body = assert(mod:read(path))
    local entry = assert(loadstring(body, '@' .. mod.path .. '/' .. path))()
    if type(entry) == 'function' then entry(mod) end
  end
  run("main.lua")
  run("editor_apply.lua")
end
