-- GFX > Blocks data layer against the game's own cache. No ROM. Plain LuaJIT,
-- no LOVE. Run from the repository root:
--   POKEPORT_RECOMP=<runtime checkout> POKEPORT_GEN3_CACHE=<folder holding
--   data/generated/gba, e.g. %APPDATA%/LOVE/pokemon-love2d/firered>
--   luajit tests/content-editor/test_gen3_blocks.lua
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
local shared = {} -- tileset packs are built once per session, as in the editor
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
local function same(a, b)
  for i = 1, 256 do if (a[i] or 0) ~= (b[i] or 0) then return false end end
  return true
end
local function cached(pack, mid)
  local n, u, o = pack.index[mid], {}, {}
  for i = 1, 256 do u[i] = pack.under[(n - 1) * 256 + i]; o[i] = pack.over[(n - 1) * 256 + i] or 0 end
  return u, o
end

run("every saved block, described in tiles, draws back exactly", function()
  local S, n = fresh(), 0
  for _, pair in ipairs({ "pallet_outdoor", "viridian_outdoor", "player_house", "network",
      "general__rom_082d4af4", "building__rom_082d4bcc" }) do
    local pack = assert(Blocks.pack(S, pair))
    for _, mid in ipairs(pack.mids) do
      local u, o = Blocks.composeBlock(S, pair, Blocks.gameDefinition(S, pair, mid))
      local cu, co = cached(pack, mid)
      assert(same(u, cu) and same(o, co), pair .. " block " .. mid)
      n = n + 1
    end
  end
  print("      " .. n .. " blocks")
end)

run("covered blocks split back into two layers", function()
  local S, found = fresh(), false
  local pack = Blocks.pack(S, "player_house")
  for _, mid in ipairs(pack.mids) do
    local d = Blocks.gameDefinition(S, "player_house", mid)
    if d.layerType == "covered" and d.slots[5].tile then found = true; break end
  end
  assert(found, "no covered two-palette block found")
end)

run("every game block round-trips through the editor unchanged", function()
  local S = fresh()
  for _, mid in ipairs(Blocks.ids(S, PAIR)) do
    local def, edited = Blocks.definition(S, PAIR, mid)
    assert(def and not edited, "block " .. mid)
    assert(Blocks.store(S, PAIR, mid, def) == false, "storing the game's own block is a no-op")
  end
  assert(S.project.gen3Blocks == nil)
end)

run("an edit is stored, shows as edited, and reverts", function()
  local S = fresh()
  local def = Blocks.definition(S, PAIR, 20)
  def.slots[1].hflip = not def.slots[1].hflip
  assert(Blocks.store(S, PAIR, 20, def))
  local now, edited, isNew = Blocks.definition(S, PAIR, 20)
  assert(edited and not isNew and now.slots[1].hflip == def.slots[1].hflip)
  assert(Blocks.revert(S, PAIR, 20))
  assert(S.project.gen3Blocks == nil)
end)

run("editing a block back to the game's version drops it", function()
  local S = fresh()
  local game = Blocks.definition(S, PAIR, 20)
  local d = Blocks.normalize(game); d.slots[1].pal = (d.slots[1].pal + 1) % 13
  assert(Blocks.store(S, PAIR, 20, d))
  assert(Blocks.store(S, PAIR, 20, game))
  assert(S.project.gen3Blocks == nil)
end)

run("new blocks take free ids from 640 and are listed", function()
  local S = fresh()
  local pack = Blocks.pack(S, PAIR)
  local a = assert(Blocks.newBlock(S, PAIR))
  local b = assert(Blocks.newBlock(S, PAIR))
  assert(a >= 640 and not pack.index[a] and b > a and not pack.index[b])
  local ids = Blocks.ids(S, PAIR)
  assert(ids[#ids] == b)
  assert(Blocks.revert(S, PAIR, a))
end)

run("the tile sheet has each tile once, with the palette it was found in", function()
  local S = fresh()
  local tiles = Blocks.gameTiles(S, PAIR)
  assert(#tiles > 100, #tiles .. " tiles")
  local seen = {}
  for _, t in ipairs(tiles) do
    local key = table.concat(t.px, ",")
    assert(not seen[key], "duplicate tile " .. t.key); seen[key] = true
    assert(TS.parseKey(t.key) and t.pal >= 0 and t.pal < 16)
  end
end)

run("normalize clamps junk; tiles from the old ROM-based format are kept and flagged", function()
  local d = Blocks.normalize({ slots = { { tile = 0, pal = -3, hflip = "yes" }, { tile = 245 },
    { tile = 9000 }, { tile = "not a key" } }, layerType = "sideways", behavior = 9999 })
  assert(d.slots[1].tile == false and d.slots[1].pal == 0 and d.slots[1].hflip == false)
  assert(d.slots[2].tile == 245 and d.slots[3].tile == Blocks.CUSTOM + Blocks.MAX_CUSTOM)
  assert(d.slots[4].tile == false and d.layerType == "normal" and d.behavior == 511)
  local S = fresh()
  local mid = Blocks.newBlock(S, PAIR, { slots = { { tile = 245 } } })
  assert(#Blocks.problems(S, PAIR, mid) == 1, "old tile numbers can't be drawn without the ROM")
end)

run("a block saved by the ROM-based version with your own tiles still works", function()
  -- The shape of the first real block made with the earlier build.
  local S = fresh()
  S.project.gen3Tiles = { harbor = { ["4096"] = { px = string.rep("7", 64) },
    ["4097"] = { px = string.rep("5", 64) } } }
  S.project.gen3Blocks = { harbor = { ["719"] = { new = true, behavior = 0, layerType = "normal",
    slots = { { tile = 4096, pal = 4 }, { tile = 4097, pal = 4 }, { tile = 4096, pal = 4 },
      { tile = 4097, pal = 4 }, { tile = 0, pal = 0 }, { tile = 0, pal = 0 }, { tile = 0, pal = 0 }, { tile = 0, pal = 0 } } } } }
  assert(#Blocks.problems(S, "harbor", 719) == 0)
  local u = Blocks.composeBlock(S, "harbor", Blocks.definition(S, "harbor", 719))
  assert(u[1] == 4 * 16 + 7 and u[9] == 4 * 16 + 5)
  Blocks.validate(S.project)
end)

run("a copy of a game tile stores no pixels until painted, then only those", function()
  local S = fresh()
  local base = Blocks.gameTiles(S, PAIR)[10].key
  local n = assert(Blocks.newTile(S, PAIR, base))
  local t = Blocks.customTile(S.project, PAIR, n)
  assert(t.px == string.rep(".", 64) and t.base == base)
  local orig = Blocks.tilePixels(S, PAIR, base)
  assert(Blocks.setPixel(S, PAIR, n, 10, (orig[10] + 1) % 16))
  assert(Blocks.paintedCount(S.project, PAIR, n) == 1)
  assert(Blocks.setPixel(S, PAIR, n, 10, orig[10]))
  assert(t.px == string.rep(".", 64))
  Blocks.validate(S.project)
end)

run("a block using unpainted copies looks exactly like the original", function()
  local S = fresh()
  local def = Blocks.definition(S, PAIR, 20)
  local ru, ro = Blocks.composeBlock(S, PAIR, def)
  for i = 1, 8 do
    if def.slots[i].tile then def.slots[i].tile = assert(Blocks.newTile(S, PAIR, def.slots[i].tile)) end
  end
  local u, o = Blocks.composeBlock(S, PAIR, def)
  assert(same(u, ru) and same(o, ro))
end)

run("tiles drawn from scratch need nothing; deleting one flags its blocks", function()
  local S = fresh()
  local n = assert(Blocks.newTile(S, PAIR, nil))
  for i = 1, 64 do Blocks.setPixel(S, PAIR, n, i, i % 16) end
  local mid = assert(Blocks.newBlock(S, PAIR, { slots = { { tile = n, pal = 3 } } }))
  assert(#Blocks.problems(S, PAIR, mid) == 0)
  assert(Blocks.deleteTile(S, PAIR, n))
  assert(#Blocks.problems(S, PAIR, mid) == 1)
end)

-- The in-game side: exactly what Gen3BlocksRuntime does with the saved data.
local function inGame(data, pair)
  local pack = TS.decodePair(read("data/generated/gba/native/" .. pair .. "/mids.idx"),
    read("data/generated/gba/native/" .. pair .. "/mids_over.idx"))
  return setmetatable({}, { __index = function(_, key)
    local own = data.tiles[key]
    if not own then return TS.tile(pack, key) end
    local base = own.base and TS.tile(pack, own.base)
    local px = {}
    for i = 1, 64 do
      local ch = own.px:sub(i, i)
      px[i] = ch == "." and base[i] or tonumber(ch, 16)
    end
    return px
  end })
end

run("saved blocks rebuild in game exactly as the editor draws them", function()
  local S = fresh()
  local tiles = Blocks.gameTiles(S, PAIR)
  local mine = assert(Blocks.newTile(S, PAIR, tiles[5].key))
  for i = 1, 8 do Blocks.setPixel(S, PAIR, mine, i * 8, 9) end
  local mids = {}
  for _, layer in ipairs({ "normal", "covered", "split" }) do
    local def = { layerType = layer, behavior = 2, slots = {} }
    for i = 1, 8 do
      def.slots[i] = { tile = (i == 3) and mine or tiles[(i * 7) % #tiles + 1].key,
        pal = (i * 3) % 13, hflip = i % 2 == 0, vflip = i % 3 == 0 }
    end
    mids[#mids + 1] = assert(Blocks.newBlock(S, PAIR, def))
  end
  local edit = Blocks.definition(S, PAIR, 20); edit.slots[2].vflip = not edit.slots[2].vflip
  Blocks.store(S, PAIR, 20, edit); mids[#mids + 1] = 20
  local b1 = Blocks.definition(S, PAIR, 1); b1.behavior = 0x13; Blocks.store(S, PAIR, 1, b1)
  local data, warnings = Blocks.compileRuntime(S)
  assert(#warnings == 0, warnings[1])
  assert(data.pairs[PAIR][1].slots == nil and data.pairs[PAIR][1].behavior == 0x13)
  local game = inGame(data, PAIR)
  for _, mid in ipairs(mids) do
    local rec = data.pairs[PAIR][mid]
    local u, o = TS.compose(game, { slots = rec.slots, layerType = rec.layerType })
    local ru, ro = Blocks.composeBlock(S, PAIR, Blocks.definition(S, PAIR, mid))
    assert(u and same(u, ru) and same(o, ro), "block " .. mid)
  end
end)

run("what a mod carries is numbers and short names, plus your painted pixels", function()
  local S = fresh()
  local mine = Blocks.newTile(S, PAIR, nil)
  for i = 1, 64 do Blocks.setPixel(S, PAIR, mine, i, 5) end
  local d = Blocks.definition(S, PAIR, 20); d.slots[1].tile = mine; Blocks.store(S, PAIR, 20, d)
  local data = Blocks.compileRuntime(S)
  local function walk(v)
    if type(v) == "table" then for k, x in pairs(v) do walk(k); walk(x) end
    elseif type(v) == "string" then assert(#v <= 64, "string of " .. #v .. " bytes")
    else assert(type(v) == "number" or type(v) == "boolean") end
  end
  walk(data)
end)

run("validate refuses malformed blocks and tiles", function()
  assert(not pcall(Blocks.validate, { gen3Blocks = { p = { ["2000"] = Blocks.normalize({}) } } }))
  assert(not pcall(Blocks.validate, { gen3Blocks = { p = { ["5"] = { slots = {} } } } }))
  local bad = Blocks.normalize({}); bad.layerType = "sideways"
  assert(not pcall(Blocks.validate, { gen3Blocks = { p = { ["5"] = bad } } }))
  assert(not pcall(Blocks.validate, { gen3Tiles = { p = { ["4096"] = { px = "zz" } } } }))
  assert(pcall(Blocks.validate, { gen3Tiles = { p = { ["4096"] = { px = string.rep("a", 64), base = "20/u/0/2" } } } }))
end)

run("merge: a tile drawn over a slot's tile, in the same slot", function()
  local S = fresh()
  local tiles = Blocks.gameTiles(S, PAIR)
  -- a base tile, and a top tile with some see-through pixels, same palette
  local base, top
  for _, t in ipairs(tiles) do
    local n0 = 0
    for _, v in ipairs(t.px) do if v == 0 then n0 = n0 + 1 end end
    if not base and n0 == 0 then base = t end
    if base and not top and t.pal == base.pal and n0 > 8 and n0 < 56 then top = t end
  end
  assert(base and top, "no suitable tiles")
  local d = Blocks.definition(S, PAIR, 20)
  local slot = d.slots[1]
  slot.tile, slot.pal, slot.hflip, slot.vflip = base.key, base.pal, true, false
  local n, approx = assert(Blocks.mergeTile(S, PAIR, slot, top.key, top.pal, false, false))
  assert(approx == 0 and slot.tile == n and Blocks.customTile(S.project, PAIR, n).base == base.key)
  Blocks.store(S, PAIR, 20, d)
  -- What shows in the slot (with its H-flip) is the top tile over the base.
  local px = Blocks.tilePixels(S, PAIR, n)
  for y = 0, 7 do for x = 0, 7 do
    local shown = px[y * 8 + (7 - x) + 1]
    local want = top.px[y * 8 + x + 1] ~= 0 and top.px[y * 8 + x + 1] or base.px[y * 8 + (7 - x) + 1]
    assert(shown == want, ("pixel %d,%d"):format(x, y))
  end end
  -- Only the merged pixels are stored.
  local painted = Blocks.paintedCount(S.project, PAIR, n)
  local nonzero = 0
  for _, v in ipairs(top.px) do if v ~= 0 then nonzero = nonzero + 1 end end
  assert(painted <= nonzero, "stored more than the merged pixels")
  -- Merging again paints the same tile of yours (used only here).
  assert(Blocks.mergeTile(S, PAIR, slot, top.key, top.pal, true, true) == n)
  -- A tile of yours used twice is copied, not changed under the other slot.
  local d2 = Blocks.definition(S, PAIR, 21); d2.slots[2].tile, d2.slots[2].pal = n, slot.pal
  Blocks.store(S, PAIR, 21, d2); Blocks.store(S, PAIR, 20, d)
  local copy = assert(Blocks.mergeTile(S, PAIR, d2.slots[2], top.key, top.pal))
  assert(copy ~= n, "shared tile was changed in place")
end)

run("merge: colours from another palette move to the nearest in the slot's", function()
  local S = fresh()
  local pack = Blocks.pack(S, PAIR)
  local other
  for _, t in ipairs(Blocks.gameTiles(S, PAIR)) do if t.pal ~= 2 then other = t break end end
  local slot = { tile = false, pal = 2, hflip = false, vflip = false }
  local n = assert(Blocks.mergeTile(S, PAIR, slot, other.key, other.pal))
  local px = Blocks.tilePixels(S, PAIR, n)
  for i = 1, 64 do
    local v = other.px[i]
    if v ~= 0 then
      local src, got = pack.rgb[other.pal][v], pack.rgb[2][px[i]]
      local dGot = (src[1]-got[1])^2 + (src[2]-got[2])^2 + (src[3]-got[3])^2
      for k = 1, 15 do
        local c = pack.rgb[2][k]
        assert(dGot <= (src[1]-c[1])^2 + (src[2]-c[2])^2 + (src[3]-c[3])^2, "not the nearest colour")
      end
    end
  end
end)

run("merge keeps colours: other layer, or a palette with both tiles' colours", function()
  local S = fresh()
  local pack = Blocks.pack(S, PAIR)
  local tiles = Blocks.gameTiles(S, PAIR)
  -- Free corner on the other layer: layered, own palette, under the player.
  local d = Blocks.definition(S, PAIR, 21)
  for i = 5, 8 do d.slots[i] = { tile = false, pal = 0, hflip = false, vflip = false } end
  d.slots[1] = { tile = tiles[1].key, pal = tiles[1].pal, hflip = false, vflip = false }
  local other
  for _, t in ipairs(tiles) do if t.pal ~= tiles[1].pal then other = t break end end
  local n, how = Blocks.merge(S, PAIR, d, 1, other.key, other.pal)
  assert(how == "layer" and d.slots[5].tile == other.key and d.slots[5].pal == other.pal
    and d.layerType == "covered", "not layered: " .. tostring(how))
  -- Other layer taken: exact whenever it isn't "nearest".
  local exact, palette, moved = 0, 0, 0
  for i = 1, #tiles, 7 do
    for j = 2, #tiles, 11 do
      local a, b = tiles[i], tiles[j]
      if a.pal ~= b.pal then
        local def = Blocks.definition(S, PAIR, 21)
        def.layerType = "normal"
        def.slots[1] = { tile = a.key, pal = a.pal, hflip = false, vflip = false }
        def.slots[5] = { tile = tiles[3].key, pal = tiles[3].pal, hflip = false, vflip = false }
        local got, kind = Blocks.merge(S, PAIR, def, 1, b.key, b.pal)
        assert(got, kind)
        if kind ~= "nearest" then
          exact = exact + 1
          if kind == "palette" or kind == "added" then palette = palette + 1; Blocks.store(S, PAIR, 21, def) end
          if def.slots[1].pal ~= a.pal then
            -- Moved palette: the base's pixels stay the base's (so they keep
            -- animating in game), recoloured rather than repainted.
            moved = moved + 1
            local t = Blocks.customTile(S.project, PAIR, got)
            for k = 1, 64 do
              if b.px[k] == 0 and a.px[k] ~= 0 then assert(t.px:sub(k, k) == ".", "base pixel repainted") end
            end
          end
          local px = Blocks.tilePixels(S, PAIR, got)
          for k = 1, 64 do
            local want = b.px[k] ~= 0 and pack.rgb[b.pal][b.px[k]] or (a.px[k] ~= 0 and pack.rgb[a.pal][a.px[k]])
            if want then
              local c = pack.rgb[def.slots[1].pal][px[k]]
              assert(c[1] == want[1] and c[2] == want[2] and c[3] == want[3], "colour changed in " .. kind)
            end
          end
        end
      end
      if palette > 0 and exact > 3 then break end
    end
    if palette > 0 and exact > 3 then break end
  end
  assert(palette > 0, "never kept colours through another palette or added colours")
  -- Added colours reach the game as 15-bit BGR.
  local data = Blocks.compileRuntime(S)
  local added = S.project.gen3Palettes and S.project.gen3Palettes[PAIR]
  assert(added and data.palettes and data.palettes[PAIR], "added colours not compiled")
  for pk, cols in pairs(added) do
    if pk ~= "rev" then
      for ck, hex in pairs(cols) do
        local v = data.palettes[PAIR][tonumber(pk)][tonumber(ck)]
        local r, g, b = v % 32, math.floor(v / 32) % 32, math.floor(v / 1024) % 32
        local c = pack.rgb[tonumber(pk)][tonumber(ck)]
        assert(r * 8 + math.floor(r / 4) == c[1] and g * 8 + math.floor(g / 4) == c[2] and b * 8 + math.floor(b / 4) == c[3],
          "colour changed on the way to the game")
      end
    end
  end
  assert(pcall(Blocks.validate, S.project))
end)

run("merge remembers where merged game pixels came from; hand painting forgets", function()
  local S = fresh()
  local tiles = Blocks.gameTiles(S, PAIR)
  local a, b = tiles[1], nil
  for _, t in ipairs(tiles) do if t.pal == a.pal and t.key ~= a.key then b = t break end end
  local d = Blocks.definition(S, PAIR, 21)
  for i = 5, 8 do d.slots[i] = { tile = tiles[3].key, pal = tiles[3].pal, hflip = false, vflip = false } end
  d.layerType = "normal"
  d.slots[1] = { tile = a.key, pal = a.pal, hflip = true, vflip = false }
  local n = assert(Blocks.merge(S, PAIR, d, 1, b.key, b.pal, false, true))
  local t = Blocks.customTile(S.project, PAIR, n)
  assert(t.over == b.key and t.overH == true and t.overV == true, "source not remembered")
  -- every remembered pixel really is that tile's pixel, flipped
  local px = Blocks.tilePixels(S, PAIR, n)
  for i = 1, 64 do
    if t.overMask:sub(i, i) == "1" then
      local x, y = (i - 1) % 8, math.floor((i - 1) / 8)
      assert(px[i] == b.px[(7 - y) * 8 + (7 - x) + 1], "mask/flip mismatch at " .. i)
    end
  end
  Blocks.store(S, PAIR, 21, d)
  local data = Blocks.compileRuntime(S)
  local rt = data.tiles["y:" .. PAIR .. ":" .. n]
  assert(rt and rt.over == b.key and rt.overMask == t.overMask, "not compiled")
  local first = t.overMask:find("1", 1, true)
  Blocks.setPixel(S, PAIR, n, first, (px[first] % 15) + 1)
  assert(t.overMask:sub(first, first) == "0" or not t.over, "hand-painted pixel still animates")
  assert(pcall(Blocks.validate, S.project))
end)

run("layers: swap round-trips; merging top into bottom keeps the look", function()
  local S = fresh()
  local pack = Blocks.pack(S, PAIR)
  local function rgbOf(u, o)
    local out = {}
    for i = 1, 256 do
      local v = (o and o[i] ~= 0) and o[i] or u[i]
      local c = v ~= 0 and pack.rgb[math.floor(v / 16)][v % 16]
      out[i] = c and (c[1] .. "," .. c[2] .. "," .. c[3]) or "-"
    end
    return out
  end
  local tried, exact = 0, 0
  for _, mid in ipairs(pack.mids) do
    local d = Blocks.definition(S, PAIR, mid)
    local tops = 0
    for i = 5, 8 do if d.slots[i].tile then tops = tops + 1 end end
    local bottoms = 0
    for i = 1, 4 do if d.slots[i].tile then bottoms = bottoms + 1 end end
    if tops > 0 and bottoms == 4 and d.layerType == "normal" and tried < 25 then
      tried = tried + 1
      -- swap twice = unchanged
      local sw = Blocks.normalize(d)
      Blocks.swapLayers(Blocks.swapLayers(sw))
      assert(Blocks.signature(sw) == Blocks.signature(d), "swap twice changed block " .. mid)
      local before = rgbOf(Blocks.composeBlock(S, PAIR, d))
      local n, approx = assert(Blocks.flattenLayers(S, PAIR, d))
      assert(n == tops, "merged " .. n .. " of " .. tops)
      for i = 5, 8 do assert(not d.slots[i].tile, "top layer not emptied") end
      if approx == 0 then
        exact = exact + 1
        local u = Blocks.composeBlock(S, PAIR, d)
        local after = rgbOf(u)
        for i = 1, 256 do assert(after[i] == before[i], ("block %d pixel %d changed"):format(mid, i)) end
      end
      S.project = {}
    end
  end
  assert(tried > 0 and exact > 0, ("tried %d, exact %d"):format(tried, exact))
  print(("      %d blocks flattened, %d with every colour exact"):format(tried, exact))
end)

-- Import PNG ------------------------------------------------------------------
local Import = require("Gen3ImageImport")
-- A sheet of `n` frames of 24 x 24: a moving bright square on nothing.
local function sheet(n)
  local w, h, px = 24 * n, 24, {}
  for i = 1, w * h * 4 do px[i] = 0 end
  for f = 0, n - 1 do
    for y = 4, 19 do for x = 4 + f, 19 do
      local i = (y * w + f * 24 + x) * 4
      px[i + 1], px[i + 2], px[i + 3], px[i + 4] = 200, 230, 255, 255
    end end
  end
  return { w = w, h = h, px = px }
end

run("import: a sheet splits into frames, fits and becomes animated blocks", function()
  local S = fresh()
  local pic = sheet(3)
  local across, down = Import.guessFrames(pic)
  assert(across == 3 and down == 1, "strip not recognised")
  local frames = assert(Import.split(pic, across, down))
  assert(#frames == 3)
  local bw, bh = Import.suggestSize(frames)
  assert(bw == 1 and bh == 1, "16px content should suggest 1 x 1")
  local plan = assert(Import.plan(S, "general__rom_082d4af4",
    { frames = frames, blocksW = 1, blocksH = 1, bg = 299, palette = "auto" }))
  assert(plan.scale == 1, "16 x 16 content fits a block as it is")
  local rec = assert(Import.create(S, "general__rom_082d4af4", plan, "square", 100))
  assert(rec.count == 3 and rec.grid[1][1] == rec.base)
  local anim = S.project.runtimeTileAnims["general__rom_082d4af4"][rec.base]
  assert(#anim == 3 and anim[2].tile == rec.base + 1 and anim[1].duration == 100)
  for mid = rec.base, rec.base + 2 do
    assert(#Blocks.problems(S, "general__rom_082d4af4", mid) == 0, "block " .. mid)
    local d = Blocks.definition(S, "general__rom_082d4af4", mid)
    assert(d.layerType == "covered" and d.slots[1].tile == "299/u/0/" .. d.slots[1].pal,
      "background not the game's own block")
  end
  -- Same name: replaced in place. Remove: gone, tiles too.
  local again = assert(Import.create(S, "general__rom_082d4af4", plan, "square", 100))
  assert(again.base == rec.base and #Import.list(S.project, "general__rom_082d4af4") == 1)
  assert(Import.remove(S, "general__rom_082d4af4", 1))
  assert(not Blocks.own(S.project, "general__rom_082d4af4") and not S.project.gen3Tiles
    and not next(S.project.runtimeTileAnims["general__rom_082d4af4"]), "left something behind")
end)

run("import: background colours are kept out of the picture", function()
  local S = fresh()
  local frames = assert(Import.split(sheet(1), 1, 1))
  local plan = assert(Import.plan(S, "general__rom_082d4af4",
    { frames = frames, blocksW = 1, blocksH = 1, bg = 299, palette = 4, avoidBg = true }))
  local pack = Blocks.pack(S, "general__rom_082d4af4")
  local sea = {}
  for _, c in ipairs(Import.blockColours(S, "general__rom_082d4af4", 299)) do sea[c[1] .. "," .. c[2] .. "," .. c[3]] = true end
  for _, v in ipairs(plan.frames[1].idx) do
    if v ~= 0 then
      local c = pack.rgb[4][v]
      assert(not sea[c[1] .. "," .. c[2] .. "," .. c[3]], "picture uses a sea colour")
    end
  end
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
