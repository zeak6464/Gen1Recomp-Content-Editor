-- Save-editor preview: a generated Gen 3 mod replays its game.ready handlers
-- when the loader reports mods.loaded for a save editor (Data has game3Maps),
-- and does nothing extra in the game. Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_gen3_editor_ready.lua
local f = assert(io.open("tools/content-editor/Gen3.lua")):read("*a")
local src = assert(f:match("Gen3%.READY_REPLAY=%[%[(.-)%]%]\n"))
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

-- the loader's own per-mod events table, with its listener bus
local function loader()
  local bus = {}
  local mod = { events = { on = function(_, name, cb, prio)
    bus[name] = bus[name] or {}; table.insert(bus[name], { cb = cb, prio = prio or 0 })
    table.sort(bus[name], function(a, b) return a.prio > b.prio end)
  end } }
  local function emit(name, payload) for _, e in ipairs(bus[name] or {}) do e.cb(payload) end end
  return mod, emit
end
local function install(mod) assert(loadstring("return function(mod)\n" .. src .. "\nend"))()(mod) end

run("editor: game.ready handlers run once on mods.loaded, in priority order", function()
  local mod, emit = loader(); install(mod)
  local seen = {}
  mod.events:on("game.ready", function(ctx) seen[#seen + 1] = "low"; assert(ctx.game.data.maps) end, -5)
  mod.events:on("game.ready", function() seen[#seen + 1] = "a" end)
  mod.events:on("game.ready", function() error("boom") end)
  mod.events:on("game.ready", function() seen[#seen + 1] = "b" end)
  mod.events:on("map.entered", function() seen[#seen + 1] = "never" end)
  emit("mods.loaded", { data = { game3Maps = {}, maps = {} } })
  assert(table.concat(seen, ",") == "a,b,low", table.concat(seen, ","))
end)

run("game: mods.loaded without game3Maps replays nothing", function()
  local mod, emit = loader(); install(mod)
  local n = 0
  mod.events:on("game.ready", function() n = n + 1 end)
  emit("mods.loaded", { data = { maps = {} } })
  assert(n == 0)
  emit("game.ready", { game = {} })
  assert(n == 1)
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
