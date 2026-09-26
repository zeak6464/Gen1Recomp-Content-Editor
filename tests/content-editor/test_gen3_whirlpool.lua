-- Whirlpools (Gen3Whirlpool + Gen3WhirlpoolRuntime) against the real engine
-- field, player and collision code on a synthetic sea. Plain LuaJIT, no LOVE.
-- Run from the repository root:
--   POKEPORT_RECOMP=<runtime checkout> luajit tests/content-editor/test_gen3_whirlpool.lua
local RUNTIME = assert(os.getenv("POKEPORT_RECOMP"), "Set POKEPORT_RECOMP")
package.path = "tools/content-editor/?.lua;tools/save-editor/?.lua;" .. RUNTIME .. "/?.lua;"
  .. RUNTIME .. "/?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = {
  plain = function(k) return k end, box = function(k) return k end,
  ascii = function(k) return k end, has = function() return true end,
  key = function(n) return n end, at = function(n) return n end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

-- Sound: record what plays; each sound "plays" for 40 frames.
package.loaded["src.core.game3.m4a_mix"] = { SAMPLE_RATE = 44100 }
local played, playing = {}, {}
package.loaded["src.core.game3.audio"] = setmetatable({
  playSe = function(id) played[#played + 1] = id; playing[id] = 40; return true end,
  isSePlaying = function(id) return (playing[id] or 0) > 0 end,
}, { __index = function() return function() end end })
local function soundTick() for k, v in pairs(playing) do playing[k] = v - 1 end end

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

-- UI stubs: record what is shown and answer yes/no.
local shown, answer = {}, true
package.loaded["src.ui.game3.message"] = {
  show = function(text, cb) shown[#shown + 1] = text; if type(cb) == "function" then cb() end end,
  close = function() end, isOpen = function() return false end,
}
package.loaded["src.ui.game3.choice"] = { yesNo = function(cb) cb(answer) end }
package.loaded["src.core.game3.field_move_show_mon"] = { start = function(_, _, cb) cb() end }
package.loaded["src.core.game3.pokemon"] = setmetatable({
  displayMonName = function(mon) return mon.nickname end,
}, { __index = function() return function() end end })
local hooks = {}
package.loaded["src.mods.Runtime"] = {
  wants = function() return false end, emit = function() end,
  call = function(name, proceed, ...)
    if hooks[name] then return hooks[name](proceed, ...) end
    return proceed(...)
  end,
}

local W = require("Gen3Whirlpool")
local Emit = require("Gen3WhirlpoolRuntime")
local encode = require("ModWriter").encodeLua
local Collision = require("src.core.game3.collision")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")

-- A 9 x 3 sea; whirlpool blocks 700-703 as a 2 x 2 at x 3-4, y 0-1.
local PAIR, MW, MH = "whirl_test", 9, 3
local WATER, LAND = 1, 2
local WHIRL = { [700] = true, [701] = true, [702] = true, [703] = true }
Interaction.behaviors[PAIR] = { [WATER] = 0x15, [LAND] = 0x00,
  [700] = W.BEHAVIOR, [701] = W.BEHAVIOR, [702] = W.BEHAVIOR, [703] = W.BEHAVIOR }
local mids = {}
local function reset(landAtEnd)
  for y = 0, MH - 1 do
    for x = 0, MW - 1 do
      local m = WATER
      if x >= 3 and x <= 4 and y <= 1 then m = 700 + (x - 3) + (y * 2) end
      if landAtEnd and x == 5 then m = LAND end
      mids[y * MW + x + 1] = m
    end
  end
  Collision._mapDef = { pair = PAIR, midLayout = { width = MW, height = MH,
    midAt = function(_, x, y) return mids[y * MW + x + 1] or LAND end,
    elevAt = function() return 0 end } }
  Collision._mapId = "WHIRL_TEST"
  Collision._widthCells, Collision._heightCells = MW, MH
  Collision._grid = {}
  -- Like the game: a whirlpool cell is not water (behaviour 0x1F0).
  for i, m in ipairs(mids) do Collision._grid[i] = (m == LAND or WHIRL[m]) and 0xFF or 0x29 end
end

-- Load the emitted runtime the way a mod would, with a stand-in `mod`.
local function install(project)
  local data = assert(W.compile(project), "nothing compiled")
  local src = "return function(mod)\n" .. Emit(data, encode) .. "\nend"
  local chunk = assert(loadstring(src))()
  local ready
  local mod = {
    events = { on = function(_, name, fn) if name == "game.ready" then ready = fn end end },
    hooks = { wrap = function(_, name, fn) hooks[name] = fn end },
  }
  chunk(mod)
  ready({ game = {} })
end

local project = { gen3Blocks = { [PAIR] = {
  ["700"] = { behavior = W.BEHAVIOR }, ["701"] = { behavior = W.BEHAVIOR },
  ["702"] = { behavior = W.BEHAVIOR }, ["703"] = { behavior = W.BEHAVIOR },
  ["704"] = { behavior = 0x15 } } } }

run("compile lists only whirlpool blocks, with the defaults", function()
  local d = W.compile(project)
  assert(d.behavior == W.BEHAVIOR)
  assert(d.move == 250 and d.flag == nil and d.used:find("{MON}", 1, true))
  assert(W.compile({ gen3Blocks = { p = { ["5"] = { behavior = 0x15 } } } }) == nil)
end)

reset(false)
install(project)
local gyarados = { nickname = "GYARADOS", moves = { 57, 250 } }
local function surfAt(x, y, facing)
  Field.running, Field.locked = true, false
  Player.reset(x, y, facing)
  Player.surfing = true
  shown = {}
end
local function stubSpace()
  package.loaded["src.core.game3.scripting.space"] = { active = true, startScript = function() return false end,
    store = { flags = {} }, vm = { isRunning = function() return false end } }
end
stubSpace()
local function drive(limit)
  local frames = 0
  for _ = 1, limit or 900 do
    Field.updateWaterfall(nil)
    Player.tick(nil)
    soundTick()
    assert(Player.surfing, ("stopped surfing at %d,%d"):format(Player.cellX, Player.cellY))
    frames = frames + 1
    if not Field.locked and not Player.moving then break end
  end
  return frames
end

run("nobody surfs into a whirlpool", function()
  surfAt(2, 0, "right")
  assert(Collision.canEnter(nil, 3, 0, { surfing = true }) == false, "whirlpool enterable")
  assert(Collision.canEnter(nil, 1, 0, { surfing = true }) ~= false, "plain water blocked")
end)

run("without a Pokemon that knows WHIRLPOOL: the currents are too strong", function()
  Field._session = { party = { { nickname = "PIDGEY", moves = { 33 } } }, flags = {} }
  surfAt(2, 0, "right")
  assert(Field.interact(nil) == true, "not handled")
  assert(#shown == 1 and shown[1] == W.DEFAULTS.cant, "wrong text: " .. tostring(shown[1]))
  assert(Player.cellX == 2 and not Field.locked)
end)

run("with WHIRLPOOL: asks, names the Pokemon, carries the player across", function()
  Field._session = { party = { gyarados }, flags = {} }
  surfAt(2, 1, "right")
  assert(Field.interact(nil) == true)
  assert(shown[1] == W.DEFAULTS.ask and shown[2] == "GYARADOS used WHIRLPOOL!", "texts: " .. table.concat(shown, " | "))
  assert(Field.locked == true, "not locked while crossing")
  local frames = drive()
  assert(Player.cellX == 5 and Player.cellY == 1, ("landed at %d,%d"):format(Player.cellX, Player.cellY))
  assert(Player.surfing and not Field.locked, "not surfing / still locked")
  assert(frames >= 3 * 32, "too fast: " .. frames .. " frames")
end)

run("the sound plays once and the crossing ends as it does", function()
  Field._session = { party = { gyarados }, flags = {} }
  local Audio = package.loaded["src.core.game3.audio"]
  -- The game keeps each baked sound's samples: say WHIRLPOOL lasts 2.4 s.
  local rate = require("src.core.game3.m4a_mix").SAMPLE_RATE
  Audio._seRaw = { [require("src.core.game3.se_ids").SE_M_WHIRLPOOL] = { frames = math.floor(rate * 2.4), loop = false } }
  played, playing = {}, {}
  surfAt(2, 1, "right"); Field.interact(nil)
  local frames = drive()
  assert(#played == 1 and played[1] == "SE_M_WHIRLPOOL", "played " .. #played .. " times")
  assert(Player.cellX == 5, "didn't cross")
  -- 2.4 s = 144 frames over 3 steps (two whirlpool cells and out)
  assert(math.abs(frames - 144) <= 6, "crossing took " .. frames .. " frames, sound 144")
  -- Without a baked length it falls back to the waterfall's pace.
  Audio._seRaw = nil
  surfAt(2, 1, "right"); Field.interact(nil)
  frames = drive()
  assert(math.abs(frames - 96) <= 6, "fallback took " .. frames .. " frames")
end)

run("works in every direction the player faces", function()
  Field._session = { party = { gyarados }, flags = {} }
  surfAt(5, 0, "left"); Field.interact(nil); drive()
  assert(Player.cellX == 2 and Player.cellY == 0, ("left: %d,%d"):format(Player.cellX, Player.cellY))
  surfAt(3, 2, "up")
  -- up from y 2 would cross y 1..0 and leave the map: the far side must exist
  Field.interact(nil)
  assert(shown[1] == W.DEFAULTS.cant and Player.cellY == 2, "crossed off the map")
end)

run("answering no leaves the player where they are", function()
  Field._session = { party = { gyarados }, flags = {} }
  answer = false
  surfAt(2, 0, "right"); Field.interact(nil); drive(100)
  answer = true
  assert(Player.cellX == 2 and not Field.locked)
end)

run("a badge requirement, and a blocked far side, stop the crossing", function()
  project.gen3Whirlpool = { flag = 0x827 }
  hooks = {}
  for _, key in ipairs({ "editor.gen3.whirlpool.enter", "editor.gen3.whirlpool.interact", "editor.gen3.whirlpool.tick" }) do
    Collision[key], Field[key] = nil, nil
  end
  install(project)
  Field._session = { party = { gyarados }, flags = {} }
  surfAt(2, 0, "right"); Field.interact(nil)
  assert(shown[1] == W.DEFAULTS.cant and Player.cellX == 2, "crossed without the badge")
  package.loaded["src.core.game3.scripting.space"].store.flags[0x827] = true
  require("src.core.game3.scripting.flags").setFlag(package.loaded["src.core.game3.scripting.space"].store, nil, 0x827, true)
  surfAt(2, 0, "right"); Field.interact(nil); drive()
  assert(Player.cellX == 5, "badge set but no crossing")
  reset(true)
  surfAt(2, 0, "right"); Field.interact(nil)
  assert(shown[1] == W.DEFAULTS.cant and Player.cellX == 2, "crossed onto land")
  reset(false)
  project.gen3Whirlpool = nil
end)

run("painted Whirlpool collision: compiled, and crossed with no whirlpool block", function()
  hooks = {}
  for _, key in ipairs({ "editor.gen3.whirlpool.enter", "editor.gen3.whirlpool.water",
      "editor.gen3.whirlpool.interact", "editor.gen3.whirlpool.tick" }) do
    Collision[key], Field[key] = nil, nil
  end
  -- A map built in the editor: plain water tiles, four cells painted
  -- Whirlpool. The layered runtime gives those cells the painted collision's
  -- behaviour (Gen3Collision.painted.whirlpool).
  local C = require("Gen3Collision")
  assert(C.painted.whirlpool and C.painted.whirlpool[2] == W.BEHAVIOR, "no Whirlpool collision mode")
  local collision = {}
  for i = 1, MW * MH do collision[i] = "water" end
  for _, i in ipairs({ 4, 5, 13, 14 }) do collision[i] = "whirlpool" end
  local painted = { gen3Layered = { WHIRL_TEST = { cellWidth = MW, cellHeight = MH, collision = collision } } }
  assert(W.compile({ gen3Layered = { M = { collision = { "water" } } } }) == nil, "compiled without whirlpools")
  -- the compiled atlas: whirlpool cells are slot 9, whose behaviour is painted
  Interaction.behaviors[PAIR][9] = C.painted.whirlpool[2]
  for i = 1, #mids do mids[i] = collision[i] == "whirlpool" and 9 or WATER end
  install(painted)
  Field._session = { party = { gyarados }, flags = {} }
  surfAt(2, 1, "right")
  assert(Collision.canEnter(nil, 4, 1, { surfing = true }) == false, "painted whirlpool enterable")
  Field.interact(nil); drive()
  assert(Player.cellX == 5, "painted crossing failed at " .. Player.cellX)
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
