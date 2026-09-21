-- Run from the repository root using tools/tooling/luajit/luajit.exe.
local hook, color, rectangle, pushes, pops, forwarded
local clock = { hour = 0, min = 0, sec = 0 }
local stamp = 0
local env = setmetatable({
  os = {
    time = function() return stamp end,
    date = function(format) assert(format == "*t"); return clock end,
  },
  love = { graphics = {
    push = function(mode) assert(mode == "all"); pushes = pushes + 1 end,
    pop = function() pops = pops + 1 end,
    origin = function() end, setShader = function() end,
    setScissor = function() end, setBlendMode = function() end,
    setColor = function(...) color = {...} end,
    rectangle = function(...) rectangle = {...} end,
  } },
}, { __index = _G })
local entry = assert(loadfile("mods/realtime_day_night/main.lua"))
setfenv(entry, env)
entry()({ hooks = { wrap = function(_, name, callback)
  assert(name == "render.hud"); hook = callback
end } })
local viewport = { gameX = 20, gameY = 30, gameWidth = 640, gameHeight = 576 }
local game = {}
local function render(hour, minute, second)
  clock = {hour = hour, min = minute or 0, sec = second or 0}
  stamp = stamp + 1
  color, rectangle, pushes, pops, forwarded = nil, nil, 0, 0, 0
  local result = hook(function(g, vp)
    assert(g == game and vp == viewport)
    forwarded = forwarded + 1
    return "chained"
  end, game, viewport)
  assert(result == "chained" and forwarded == 1)
  assert(pushes == pops)
  if rectangle then
    assert(rectangle[2] == 20 and rectangle[3] == 30)
    assert(rectangle[4] == 640 and rectangle[5] == 576)
  end
  return color
end
local midnight = render(0)
assert(midnight[3] > midnight[1] and midnight[4] == 0.36)
assert(render(12) == nil, "Daylight should have no overlay")
local dusk = render(18)
assert(dusk[1] > dusk[3] and dusk[4] == 0.20)
local beforeMidnight = render(23, 59, 59)
for i = 1, 4 do assert(math.abs(beforeMidnight[i] - midnight[i]) < 0.00001) end
-- Jumping the device clock backwards must immediately re-evaluate the tone.
assert(render(12) == nil)
assert(render(2)[4] == 0.36)
local previous
for minute = 0, 1439 do
  local current = render(math.floor(minute / 60), minute % 60)
  local opacity = current and current[4] or 0
  assert(opacity >= 0 and opacity <= 0.36)
  if previous then assert(math.abs(opacity - previous) < 0.01) end
  previous = opacity
end
print("PASS: local clock, day/night colors, full-day continuity, midnight, clock jumps, viewport, hook chaining, graphics state")

-- Optional integration: exercise the actual FireRed Game3 HUD entry point.
-- Pass the FireRed runtime root as the first argument.
if arg and arg[1] then
  local runtimeRoot = arg[1]:gsub("\\", "/"):gsub("/+$", "")
  local hudCalls = 0
  local gameEnv = setmetatable({
    love = env.love,
    require = function(name)
      if name == "src.mods.Runtime" then
        return {
          wantsHook = function(name) return name == "render.hud" end,
          call = function(name, next, game, vp)
            assert(name == "render.hud")
            hudCalls = hudCalls + 1
            return hook(next, game, vp)
          end,
        }
      elseif name == "src.core.game3.display" then
        return { W = 240, H = 160, fit = function()
          return 3, 40, 60, nil, nil, 2
        end }
      end
      return {}
    end,
  }, { __index = _G })
  local chunk = assert(loadfile(runtimeRoot .. "/src/core/Game3.lua"))
  setfenv(chunk, gameEnv)
  local Game3 = chunk()
  clock, stamp = {hour = 23, min = 0, sec = 0}, stamp + 1
  rectangle, pushes, pops = nil, 0, 0
  Game3._drawHud({}, 800, 440)
  assert(hudCalls == 1 and rectangle, "FireRed must draw the night tone")
  assert(rectangle[2] == 40 and rectangle[3] == 60)
  assert(rectangle[4] == 720 and rectangle[5] == 320)
  assert(pushes == pops)
  print("PASS: actual FireRed Game3 HUD hook, GBA dimensions, nonuniform scale, graphics state")
end
