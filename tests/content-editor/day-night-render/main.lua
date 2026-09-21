-- Run from repository root with DAY_NIGHT_RUNTIME set to a FireRed runtime:
-- love/lovec.exe tests/content-editor/day-night-render
local root = love.filesystem.getWorkingDirectory():gsub("\\", "/")
local runtime = assert(os.getenv("DAY_NIGHT_RUNTIME"), "Set DAY_NIGHT_RUNTIME")
package.path = runtime:gsub("\\", "/") .. "/?.lua;" .. package.path
local function read(path)
  local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
function love.load()
  local ok, err = xpcall(function()
    local G = love.graphics
    local Runtime = require("src.mods.Runtime")
    local Hooks = require("src.mods.Hooks")
    local Sandbox = require("src.mods.Sandbox")
    local session = {map = "FR_TEST"}
    local game = {data = {maps = {FR_TEST = {mapType = 1}}}}
    local renderer = {
      worldCanvas = G.newCanvas(8, 8), uprightCanvas = G.newCanvas(8, 8),
      canvas = G.newCanvas(8, 8), uprightActive = true,
      endWorldPass = function(self) G.setCanvas(self.canvas) end,
    }
    local display = {present = function(g)
      G.setCanvas(renderer.worldCanvas); G.clear(0.5, 0.8, 0.6, 1)
      G.setCanvas(renderer.uprightCanvas); G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 0.5); G.rectangle("fill", 0, 0, 4, 4)
      G.setCanvas(renderer.worldCanvas)
      if not g.battle then renderer:endWorldPass() end
      G.setCanvas(renderer.canvas); G.clear(1, 1, 1, 1)
      G.setCanvas()
      return true
    end}
    package.loaded["src.core.game3.display"] = display
    package.loaded["src.render.Renderer"] = renderer
    package.loaded["src.core.game3.runtime"] = {getSession = function() return session end}
    local hour = 20
    local hooks
    local function install()
      hooks = Hooks.new()
      Runtime.install({}, hooks, {})
      local env = Sandbox.envFor({modId = "realtime_day_night", permissions = {engine_internals = true}})
      env.os.date = function(format) assert(format == "*t"); return {hour=hour,min=0,sec=0} end
      local entry = assert(Sandbox.compile(read(root .. "/mods/realtime_day_night/main.lua"), "@day-night", env))
      entry()({generation=3, hooks=hooks, exports={}, read=function(_, path)
        return read(root .. "/mods/realtime_day_night/" .. path)
      end})
    end
    install()
    local function pixel(canvas, x, y)
      local data = canvas:newImageData()
      local p = {data:getPixel(x or 1, y or 1)}; data:release(); return p
    end
    local function render(h, kind)
      hour, game.data.maps.FR_TEST.mapType = h, kind or 1
      assert(display.present(game))
      return pixel(renderer.worldCanvas)
    end
    local daylight = render(12)
    local dusk = render(20)
    assert(dusk[2] < daylight[2] - 0.2, "8 PM must visibly shade the world")
    local ui = pixel(renderer.canvas)
    assert(ui[1] == 1 and ui[2] == 1 and ui[3] == 1, "UI must stay unchanged")
    assert(pixel(renderer.uprightCanvas, 6, 6)[4] == 0, "Transparent pixels must stay transparent")
    assert(math.abs(pixel(renderer.uprightCanvas)[4] - 0.5) < 0.01)
    local night = render(0)
    assert(night[1] < dusk[1] and night[2] < dusk[2], "Night must deepen the tone")
    for _, kind in ipairs({4,5,7,8,9}) do
      local indoor = render(0, kind)
      for i=1,4 do assert(indoor[i] == daylight[i], "Indoor/cave map shaded") end
    end
    for _, kind in ipairs({1,2,3,6}) do assert(render(20,kind)[2] < daylight[2]) end
    game.battle = true
    assert(render(20)[2] == daylight[2], "Battle must not use world shading")
    game.battle = false
    assert(render(12)[2] == daylight[2], "Clock jump must update immediately")
    Runtime.reset()
    assert(render(20)[2] == daylight[2], "Disabled mod must leave world unchanged")
    install()
    assert(render(20)[2] == dusk[2], "Reload must not tint twice")
    local Time = assert(loadfile(root .. "/mods/realtime_day_night/time.lua"))()
    assert(Time.at({hour=20,min=0}).isNight and Time.at({hour=5,min=0}).isMorning)
    local before = Time.at({hour=23,min=59,sec=59}).tone
    local after = Time.at({hour=0,min=0,sec=0}).tone
    for i=1,4 do assert(math.abs(before[i]-after[i]) < 0.001) end
    G.setCanvas(renderer.worldCanvas)
    G.clear(0.5,0.8,0.6,1); G.setCanvas()
    print("PASS FireRed GPU: 20:00 dusk, midnight, clock jumps, indoor/cave exclusions, outdoor types, UI, alpha, disable/reload")
  end, debug.traceback)
  local result = ok and "PASS" or tostring(err)
  print(result)
  local f = assert(io.open(root .. "/dist/day-night-render-result.txt", "w")); f:write(result); f:close()
  love.event.quit(ok and 0 or 1)
end
