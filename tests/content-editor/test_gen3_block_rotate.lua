-- GFX > Blocks: turning a slot's tile and a whole block a quarter turn.
-- Against the game's own cache, no ROM, plain LuaJIT. From the repository root:
--   POKEPORT_RECOMP=<runtime checkout> POKEPORT_GEN3_CACHE=<folder holding
--   data/generated/gba, e.g. %APPDATA%/LOVE/pokemon-love2d/firered>
--   luajit tests/content-editor/test_gen3_block_rotate.lua
local RUNTIME = assert(os.getenv("POKEPORT_RECOMP"), "Set POKEPORT_RECOMP")
local CACHE = assert(os.getenv("POKEPORT_GEN3_CACHE"), "Set POKEPORT_GEN3_CACHE")
package.path = "tools/content-editor/?.lua;tools/save-editor/?.lua;" .. RUNTIME .. "/?.lua;"
  .. RUNTIME .. "/?/init.lua;" .. package.path

local Blocks = require("Gen3Blocks")
local TS = require("Gen3TileSource")

local function read(rel)
  local f = io.open(CACHE .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local shared = {}
local function fresh()
  return { project = {}, data = { _gen3Read = read, _g3Packs = shared } }
end
local PAIR = "pallet_outdoor"

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

-- What a slot shows: its tile through its flips, as 64 colour numbers.
local function shown(S, slot)
  local px = Blocks.tilePixels(S, PAIR, slot.tile)
  local out = {}
  for y = 0, 7 do for x = 0, 7 do
    out[y * 8 + x + 1] = px[(slot.vflip and 7 - y or y) * 8 + (slot.hflip and 7 - x or x) + 1]
  end end
  return out
end
-- A size x size picture a quarter turn clockwise: the left column becomes
-- the top row.
local function clockwise(px, size)
  local out = {}
  for y = 0, size - 1 do for x = 0, size - 1 do
    out[y * size + x + 1] = px[(size - 1 - x) * size + y + 1]
  end end
  return out
end
local function same(a, b, n)
  for i = 1, n do if (a[i] or 0) ~= (b[i] or 0) then return false, i end end
  return true
end
-- A game tile that looks different every way round.
local function lopsided(S)
  for _, t in ipairs(Blocks.gameTiles(S, PAIR)) do
    local a = t.px
    local b = clockwise(a, 8); local c = clockwise(b, 8); local d = clockwise(c, 8)
    if not same(a, b, 64) and not same(a, c, 64) and not same(a, d, 64) then return t end
  end
  error("no lopsided tile")
end

run("a quarter turn clockwise: the top-left pixel goes to the top-right", function()
  -- the pixel showing at the top-right (8) after one turn is the old top-left (1)
  assert(Blocks.turned(1, 8) == 1 and Blocks.turned(1, 1) == 57 and Blocks.turned(1, 64) == 8)
  assert(Blocks.turned(2, 1) == 64 and Blocks.turned(3, 1) == 8)
  for i = 1, 64 do
    assert(Blocks.turned(nil, i) == i and Blocks.turned(0, i) == i)
    assert(Blocks.turned(1, Blocks.turned(3, i)) == i and Blocks.turned(2, Blocks.turned(2, i)) == i)
  end
end)

run("the game's side turns the same way", function()
  local f = assert(io.open("tools/content-editor/Gen3BlocksRuntime.lua", "rb"))
  local src = f:read("*a"); f:close()
  local helpers = assert(src:match("(    local function turnedXY%(rot,x,y%).-)    local function tilesFor"),
    "rotation helpers not found in Gen3BlocksRuntime.lua")
  local turned, turnedXY = assert(loadstring(helpers .. "\nreturn turned,turnedXY"))()
  for rot = 0, 3 do
    for i = 1, 64 do
      assert(turned(rot ~= 0 and rot or nil, i) == Blocks.turned(rot, i), rot .. ":" .. i)
      local x, y = turnedXY(rot ~= 0 and rot or nil, (i - 1) % 8, math.floor((i - 1) / 8))
      assert(y * 8 + x + 1 == Blocks.turned(rot, i))
    end
  end
end)

run("a game tile turns as it shows, whatever the slot's flips, and no pixels are stored", function()
  for f = 0, 3 do
    local S = fresh()
    local t = lopsided(S)
    local slot = { tile = t.key, pal = t.pal, hflip = f % 2 == 1, vflip = f >= 2 }
    local before = shown(S, slot)
    local n = assert(Blocks.rotateTile(S, PAIR, slot))
    assert(slot.tile == n and Blocks.isCustom(n))
    assert(slot.hflip == (f % 2 == 1) and slot.vflip == (f >= 2), "flips kept")
    local ok, at = same(shown(S, slot), clockwise(before, 8), 64)
    assert(ok, "flips " .. f .. " pixel " .. tostring(at))
    local rec = Blocks.customTile(S.project, PAIR, n)
    assert(rec.base == t.key and rec.px == string.rep(".", 64), "names the game tile; nothing painted")
    assert(rec.rot == ((f == 1 or f == 2) and 3 or 1))
    Blocks.validate(S.project)
  end
end)

run("four turns come back to the game's own tile; a turned tile is reused, not made again", function()
  local S = fresh()
  local t = lopsided(S)
  local slot = { tile = t.key, pal = t.pal, hflip = false, vflip = false }
  local start = shown(S, slot)
  local n = assert(Blocks.rotateTile(S, PAIR, slot))
  local d = Blocks.definition(S, PAIR, 20); d.slots[1] = slot; Blocks.store(S, PAIR, 20, d)
  for turn = 2, 3 do
    assert(Blocks.rotateTile(S, PAIR, slot) == n, "your tile, used once: turned in place")
    assert(Blocks.customTile(S.project, PAIR, n).rot == turn)
    Blocks.store(S, PAIR, 20, d)
  end
  assert(Blocks.rotateTile(S, PAIR, slot) == t.key, "a full circle: the game tile again")
  Blocks.store(S, PAIR, 20, d)
  assert(same(shown(S, slot), start, 64))
  assert(#Blocks.customTiles(S.project, PAIR) == 0 and S.project.gen3Tiles == nil, "nothing left behind")
  -- the same game tile turned the same way in two slots is one tile
  n = assert(Blocks.rotateTile(S, PAIR, slot))
  Blocks.store(S, PAIR, 20, d)
  local other = { tile = t.key, pal = t.pal, hflip = false, vflip = false }
  assert(Blocks.rotateTile(S, PAIR, other) == n, "reused")
  d.slots[2] = other; Blocks.store(S, PAIR, 20, d)
  assert(#Blocks.customTiles(S.project, PAIR) == 1)
  -- used twice now: turning one slot on leaves the other as it is
  local keep = shown(S, other)
  local m = assert(Blocks.rotateTile(S, PAIR, slot))
  assert(m ~= n and same(shown(S, other), keep, 64))
  assert(Blocks.customTile(S.project, PAIR, n) ~= nil, "still used by the other slot")
end)

run("turning a block round and round does not use up tiles", function()
  local S = fresh()
  local mid, def
  for _, id in ipairs(Blocks.ids(S, PAIR)) do
    def = Blocks.definition(S, PAIR, id)
    if def.slots[1].tile and def.slots[2].tile then mid = id break end
  end
  local sig = Blocks.signature(def)
  local most = 0
  for _ = 1, 12 do
    assert(Blocks.rotateBlock(S, PAIR, def))
    Blocks.store(S, PAIR, mid, def)
    most = math.max(most, #Blocks.customTiles(S.project, PAIR))
  end
  assert(most <= 8, most .. " tiles for one block")
  assert(Blocks.signature(def) == sig, "three full circles: the block as it was")
  assert(S.project.gen3Tiles == nil and S.project.gen3Blocks == nil, "and nothing left in the project")
end)

run("a tile of yours used in two slots is copied before it turns", function()
  local S = fresh()
  local t = lopsided(S)
  local mine = assert(Blocks.newTile(S, PAIR, t.key))
  Blocks.setPixel(S, PAIR, mine, 1, (t.px[1] % 15) + 1)
  local a = Blocks.definition(S, PAIR, 20); a.slots[1].tile, a.slots[1].pal = mine, t.pal
  local b = Blocks.definition(S, PAIR, 21); b.slots[1].tile, b.slots[1].pal = mine, t.pal
  Blocks.store(S, PAIR, 20, a); Blocks.store(S, PAIR, 21, b)
  local keep = shown(S, b.slots[1])
  local n = assert(Blocks.rotateTile(S, PAIR, a.slots[1]))
  assert(n ~= mine, "copied")
  assert(same(shown(S, b.slots[1]), keep, 64), "the other slot is untouched")
end)

run("painted and merged pixels turn with the tile", function()
  local S = fresh()
  local tiles = Blocks.gameTiles(S, PAIR)
  local base, top
  for _, t in ipairs(tiles) do
    local n0 = 0
    for _, v in ipairs(t.px) do if v == 0 then n0 = n0 + 1 end end
    if not base and n0 == 0 then base = t end
    if base and not top and t.pal == base.pal and n0 > 8 and n0 < 56 then top = t end
  end
  assert(base and top, "no suitable tiles")
  local slot = { tile = base.key, pal = base.pal, hflip = true, vflip = false }
  local n = assert(Blocks.mergeTile(S, PAIR, slot, top.key, top.pal, false, false))
  Blocks.setPixel(S, PAIR, n, 10, (base.px[10] % 15) + 1)
  local d = Blocks.definition(S, PAIR, 20); d.slots[1] = slot; Blocks.store(S, PAIR, 20, d)
  local before = shown(S, slot)
  local rec = Blocks.customTile(S.project, PAIR, n)
  local mask, ones = rec.overMask, select(2, rec.overMask:gsub("1", ""))
  assert(Blocks.rotateTile(S, PAIR, slot) == n)
  assert(same(shown(S, slot), clockwise(before, 8), 64))
  rec = Blocks.customTile(S.project, PAIR, n)
  assert(rec.over == top.key and rec.overRot == 3 and rec.rot == 3, "H-flipped slot: three turns of the tile")
  assert(select(2, rec.overMask:gsub("1", "")) == ones and rec.overMask ~= mask)
  -- every merged pixel still shows the merged tile's pixel it came from
  for i = 1, 64 do
    if rec.overMask:sub(i, i) == "1" then
      local j = Blocks.turned(rec.overRot, i)
      local x, y = (j - 1) % 8, math.floor((j - 1) / 8)
      if rec.overH then x = 7 - x end
      if rec.overV then y = 7 - y end
      assert(Blocks.tilePixels(S, PAIR, n)[i] == top.px[y * 8 + x + 1], "merged pixel " .. i)
    end
  end
  Blocks.validate(S.project)
end)

run("a whole block turns: both layers, every corner", function()
  local S = fresh()
  local n = 0
  for _, mid in ipairs(Blocks.ids(S, PAIR)) do
    if n >= 40 then break end
    local def = Blocks.definition(S, PAIR, mid)
    local u, o = Blocks.composeBlock(S, PAIR, def)
    if u then
      local turnedSlots = assert(Blocks.rotateBlock(S, PAIR, def))
      Blocks.store(S, PAIR, mid, def)
      local ru, ro = Blocks.composeBlock(S, PAIR, Blocks.definition(S, PAIR, mid))
      local ok, at = same(ru, clockwise(u, 16), 256)
      assert(ok, "block " .. mid .. " bottom pixel " .. tostring(at))
      assert(same(ro, clockwise(o, 16), 256), "block " .. mid .. " top")
      assert(turnedSlots >= 0)
      n = n + 1
    end
  end
  assert(n == 40)
  Blocks.validate(S.project)
end)

run("a whole block flips left to right and top to bottom, with the game's own tiles", function()
  local S = fresh()
  local n = 0
  for _, mid in ipairs(Blocks.ids(S, PAIR)) do
    if n >= 40 then break end
    local def = Blocks.definition(S, PAIR, mid)
    local u, o = Blocks.composeBlock(S, PAIR, def)
    if u then
      for _, horizontal in ipairs({ true, false }) do
        local d = Blocks.definition(S, PAIR, mid)
        Blocks.flipBlock(d, horizontal)
        local fu, fo = Blocks.composeBlock(S, PAIR, d)
        for y = 0, 15 do for x = 0, 15 do
          local from = (horizontal and y or 15 - y) * 16 + (horizontal and 15 - x or x) + 1
          assert((fu[y * 16 + x + 1] or 0) == (u[from] or 0), "block " .. mid .. " bottom")
          assert((fo[y * 16 + x + 1] or 0) == (o[from] or 0), "block " .. mid .. " top")
        end end
        Blocks.flipBlock(d, horizontal)
        assert(Blocks.signature(d) == Blocks.signature(def), "twice is back to the start")
      end
      n = n + 1
    end
  end
  assert(n == 40 and S.project.gen3Tiles == nil, "no tile of yours is needed")
end)

run("a block that can't be turned (no room for tiles) is left as it was", function()
  local S = fresh()
  local def
  for _, mid in ipairs(Blocks.ids(S, PAIR)) do
    def = Blocks.definition(S, PAIR, mid)
    local kinds, seen = 0, {}
    for i = 1, 8 do
      local k = def.slots[i].tile
      if k and not seen[k] then seen[k] = true; kinds = kinds + 1 end
    end
    if kinds >= 3 then break end
  end
  local sig = Blocks.signature(def)
  local room = Blocks.MAX_CUSTOM
  Blocks.MAX_CUSTOM = 0 -- room for one tile only
  local ok, err = Blocks.rotateBlock(S, PAIR, def)
  Blocks.MAX_CUSTOM = room
  assert(ok == nil and type(err) == "string")
  assert(Blocks.signature(def) == sig and S.project.gen3Tiles == nil)
end)

run("the mod carries the turn as a number; the game draws what the editor draws", function()
  local S = fresh()
  local t = lopsided(S)
  local def = Blocks.definition(S, PAIR, 20)
  def.slots[1] = { tile = t.key, pal = t.pal, hflip = false, vflip = true }
  def.slots[2] = { tile = t.key, pal = t.pal, hflip = false, vflip = false }
  assert(Blocks.rotateBlock(S, PAIR, def))
  Blocks.store(S, PAIR, 20, def)
  local data, warnings = Blocks.compileRuntime(S)
  assert(#warnings == 0, warnings[1])
  local turnedTiles = 0
  for _, own in pairs(data.tiles) do
    assert(own.px == string.rep(".", 64), "no pixels in the mod")
    if own.rot then turnedTiles = turnedTiles + 1 end
  end
  assert(turnedTiles >= 2)
  -- exactly what Gen3BlocksRuntime does with a tile of yours
  local pack = TS.decodePair(read("data/generated/gba/native/" .. PAIR .. "/mids.idx"),
    read("data/generated/gba/native/" .. PAIR .. "/mids_over.idx"))
  local game = setmetatable({}, { __index = function(_, key)
    local own = data.tiles[key]
    if not own then return TS.tile(pack, key) end
    local base = own.base and TS.tile(pack, own.base)
    local px = {}
    for i = 1, 64 do
      local ch = own.px:sub(i, i)
      px[i] = ch == "." and base[Blocks.turned(own.rot, i)] or tonumber(ch, 16)
    end
    return px
  end })
  local rec = data.pairs[PAIR][20]
  local u, o = TS.compose(game, { slots = rec.slots, layerType = rec.layerType })
  local ru, ro = Blocks.composeBlock(S, PAIR, Blocks.definition(S, PAIR, 20))
  assert(u and same(u, ru, 256) and same(o, ro, 256))
end)

run("validate refuses a bad turn", function()
  local px = string.rep(".", 64)
  assert(pcall(Blocks.validate, { gen3Tiles = { p = { ["4096"] = { px = px, base = "20/u/0/2", rot = 3 } } } }))
  assert(not pcall(Blocks.validate, { gen3Tiles = { p = { ["4096"] = { px = px, base = "20/u/0/2", rot = 4 } } } }))
  assert(not pcall(Blocks.validate, { gen3Tiles = { p = { ["4096"] = { px = px, base = "20/u/0/2", rot = 0 } } } }))
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
