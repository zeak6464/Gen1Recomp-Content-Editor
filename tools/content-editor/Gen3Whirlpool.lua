-- Whirlpools: blocks the player can only cross while surfing, with a party
-- Pokémon that knows WHIRLPOOL (like Waterfall in FireRed). Face one and
-- press A: without the move (or badge) the game says the currents are too
-- strong; with it, it asks, shows the Pokémon, and carries the player across
-- in the direction they face, landing on the first water past it.
--
-- Whirlpools are painted in the map editor: Collision tool, "Whirlpool"
-- (FireRed projects). A painted cell is blocked and gets behaviour M.BEHAVIOR
-- (Gen3Collision.painted.whirlpool) -- the editor's own value, FireRed has no
-- whirlpool behaviour -- and Gen3WhirlpoolRuntime adds the crossing. A block
-- given that behaviour works too on maps the editor hasn't touched.
--
-- Settings live in project.gen3Whirlpool:
--   { move = move id, flag = flag id or nil, ask = text, cant = text,
--     used = text ("{MON}" = the Pokémon's name) }
local M = {}

M.BEHAVIOR = 0x1F0
M.MOVE = 250 -- MOVE_WHIRLPOOL
M.FRAMES = 32 -- frames per step while crossing (the game's waterfall speed)

M.DEFAULTS = {
  move = M.MOVE,
  flag = nil,
  ask = "It's a vicious whirlpool!\nWould you like to use WHIRLPOOL?",
  cant = "The currents are too strong!\nA POKéMON may be able to cross it.",
  used = "{MON} used WHIRLPOOL!",
  sound = "SE_M_WHIRLPOOL", -- the game's own WHIRLPOOL sound; "" = silent
}

-- FireRed's badge flags (FLAG_BADGE01_GET ... FLAG_BADGE08_GET).
M.BADGES = {
  { label = "None" },
  { label = "Boulder", flag = 0x820 }, { label = "Cascade", flag = 0x821 },
  { label = "Thunder", flag = 0x822 }, { label = "Rainbow", flag = 0x823 },
  { label = "Soul", flag = 0x824 }, { label = "Marsh", flag = 0x825 },
  { label = "Volcano", flag = 0x826 }, { label = "Earth", flag = 0x827 },
}

--- The settings in effect (defaults filled in).
function M.settings(project)
  local own = (project or {}).gen3Whirlpool or {}
  local out = {}
  for k, v in pairs(M.DEFAULTS) do out[k] = v end
  for k, v in pairs(own) do out[k] = v end
  return out
end

--- Change one setting; back to default removes it.
function M.set(project, key, value)
  project.gen3Whirlpool = project.gen3Whirlpool or {}
  if value == M.DEFAULTS[key] then value = nil end
  if project.gen3Whirlpool[key] == value then return false end
  project.gen3Whirlpool[key] = value
  if not next(project.gen3Whirlpool) then project.gen3Whirlpool = nil end
  return true
end

--- Every whirlpool block, { [pair] = { [mid] = true } }, or nil when none.
function M.blocks(project)
  local out, any = {}, false
  for pair, rows in pairs((project or {}).gen3Blocks or {}) do
    for key, def in pairs(rows) do
      local mid = tonumber(key)
      if mid and type(def) == "table" and def.behavior == M.BEHAVIOR then
        out[pair] = out[pair] or {}
        out[pair][mid] = true
        any = true
      end
    end
  end
  return any and out or nil
end

--- Does any map built in the editor have cells painted Whirlpool?
function M.painted(project)
  for _, map in pairs((project or {}).gen3Layered or (project or {}).layeredMaps or {}) do
    for _, mode in pairs(type(map) == "table" and map.collision or {}) do
      if mode == "whirlpool" then return true end
    end
  end
  return false
end

--- What the game needs, or nil when the project has no whirlpools.
function M.compile(project)
  if not M.painted(project) and not M.blocks(project) then return nil end
  local s = M.settings(project)
  return {
    behavior = M.BEHAVIOR, move = math.floor(tonumber(s.move) or M.MOVE),
    flag = tonumber(s.flag), frames = M.FRAMES,
    ask = tostring(s.ask), cant = tostring(s.cant), used = tostring(s.used),
    sound = s.sound ~= "" and s.sound or nil,
  }
end

--- Make a block a whirlpool, or plain water again. A block from an imported
-- picture takes its whole import with it (every frame and corner).
-- Returns how many blocks changed.
function M.setWhirlpool(S, pair, mid, on)
  local Blocks = require("Gen3Blocks")
  local mids, back = { mid }, 0x15
  for _, rec in ipairs(((S.project.gen3Imports or {})[pair]) or {}) do
    if mid >= rec.base and mid < rec.base + rec.count then
      mids = {}
      for m = rec.base, rec.base + rec.count - 1 do mids[#mids + 1] = m end
      back = rec.behavior or back
      break
    end
  end
  local n = 0
  for _, m in ipairs(mids) do
    local def = Blocks.definition(S, pair, m)
    if def then
      local want = on and M.BEHAVIOR or (def.behavior == M.BEHAVIOR and back or def.behavior)
      if def.behavior ~= want then
        def.behavior = want
        if Blocks.store(S, pair, m, def) then n = n + 1 end
      end
    end
  end
  return n
end

function M.validate(project)
  local w = (project or {}).gen3Whirlpool
  if w == nil then return end
  assert(type(w) == "table", "Whirlpool settings must be a table")
  assert(w.move == nil or (type(w.move) == "number" and w.move >= 1 and w.move <= 1023), "Whirlpool: bad move")
  assert(w.flag == nil or (type(w.flag) == "number" and w.flag >= 0 and w.flag <= 0xFFFF), "Whirlpool: bad flag")
  for _, k in ipairs({ "ask", "cant", "used", "sound" }) do
    assert(w[k] == nil or type(w[k]) == "string", "Whirlpool: bad text " .. k)
  end
end

return M
