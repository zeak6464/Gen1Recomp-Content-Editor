-- Gen 3 blocks (FireRed metatiles) for the content editor. No ROM needed.
--
-- A block is 2x2 tiles in two layers: eight slots, each holding a tile, a
-- palette and two flips, plus a layer type and a behaviour.
--
-- Everything here comes from the game data the editor already has loaded --
-- the same cache the maps are drawn from. Tiles are cut out of the tileset's
-- saved block pictures (Gen3TileSource), and every saved block is described
-- in terms of those tiles, drawing back exactly as the game does. The project
-- stores only DEFINITIONS -- which tile (by where it sits in the cache), which
-- palette, which flip -- plus pixels the modder paints. No game graphics ever
-- go into a mod (CONTRIBUTING-mods.md, "Legal posture": mods distribute
-- recipes, not extracted content), and a player needs nothing beyond the
-- import they already did to start the game.
--
--   project.gen3Blocks[pair][tostring(mid)] = {
--     slots = { {tile=<key>|<your tile>|false, pal=0..15, hflip, vflip} x 8 },
--               -- 1-4 bottom layer, 5-8 top layer, reading order
--               -- <key> "20/u/2/3" = a tile from the cache (Gen3TileSource)
--               -- <your tile> = 4096.. (below); false = empty
--     layerType = "normal" | "covered" | "split",
--     behavior = 0..511,
--     new = true,   -- only on blocks the game doesn't have
--   }
--
--   project.gen3Tiles[pair][tostring(n)] = {       -- your own tiles
--     base = <key> | nil,  -- a game tile to paint over, or nil for scratch
--     px = "....3a..",     -- 64 characters, reading order: "." = keep the
--                          -- base tile's pixel, "0"-"f" = a painted colour
--   }
--
-- A game block edited back to exactly what the game has is dropped rather
-- than stored, so the project only ever carries real changes.

local TS = require("Gen3TileSource")

local M = {}

M.PRIMARY = 640        -- first secondary block id
M.MAX_MID = 1023       -- block ids are 10 bits
M.PALETTES = 13        -- FRLG map palettes: 0-6 primary, 7-12 secondary
M.CUSTOM = 4096        -- first "your tile" number
M.MAX_CUSTOM = 1023    -- how many of your own tiles a tileset can hold
M.LAYERS = { "normal", "covered", "split" }

local LAYER_OK = { normal = true, covered = true, split = true }
local NATIVE = "data/generated/gba/native/"
local HEX = "0123456789abcdef"

-- The game's cache ----------------------------------------------------------

local function read(S, path)
  local data = S.data or {}
  if type(data._gen3Read) ~= "function" then return nil end
  local ok, bytes = pcall(data._gen3Read, path)
  return ok and bytes or nil
end

local function behaviourTable(S)
  local data = S.data or {}
  if data._g3Behaviors == nil then
    local src = read(S, "data/generated/gba/objects/pack.lua")
    local chunk = src and load(src, "=objects", "t", {})
    local ok, pack = pcall(chunk or function() end)
    data._g3Behaviors = ok and type(pack) == "table" and pack.behaviors or false
  end
  return data._g3Behaviors or {}
end

--- One tileset's cached block pictures, palettes, behaviours and tiles.
-- Returns pack or nil, message.
function M.pack(S, pair)
  local data = S.data or {}
  data._g3Packs = data._g3Packs or {}
  local hit = data._g3Packs[pair]
  if hit ~= nil then return hit or nil, "No saved blocks for " .. tostring(pair) end
  local pack = TS.decodePair(read(S, NATIVE .. pair .. "/mids.idx"),
    read(S, NATIVE .. pair .. "/mids_over.idx"))
  if pack then
    local NativePack = require("src.import.gba.native_pack")
    local bgr = NativePack.decodePalettes(read(S, NATIVE .. pair .. "/palettes.bin"))
    pack.rgb = NativePack.palsToRgb8(bgr or {})
    pack.behaviors = behaviourTable(S)[pair] or {}
    pack.sheet = TS.harvest(pack)
  end
  data._g3Packs[pair] = pack or false
  if not pack then
    return nil, "The game data has no saved blocks for " .. tostring(pair)
      .. " -- load FireRed on the Project tab"
  end
  return pack
end

-- Tileset pairs --------------------------------------------------------------

--- Every tileset pair a map uses, and which maps use it (ROM maps and maps
-- built in the editor).
function M.pairs(S)
  local usedBy, seen = {}, {}
  local function add(pair, mapId)
    if type(pair) ~= "string" or pair == "" then return end
    usedBy[pair] = usedBy[pair] or {}
    local key = pair .. "\0" .. tostring(mapId)
    if mapId and not seen[key] then
      seen[key] = true
      usedBy[pair][#usedBy[pair] + 1] = mapId
    end
  end
  local layouts = (((S.data or {}).gen3Native or {}).layouts) or {}
  for mapId, info in pairs(layouts) do add(type(info) == "table" and info.pair, mapId) end
  for mapId, src in pairs(((S.project or {}).layeredMaps) or {}) do
    add(type(src) == "table" and src.baseTileset, mapId)
  end
  for pair in pairs(((S.project or {}).gen3Blocks) or {}) do add(pair, nil) end
  local ids = {}
  for pair, maps in pairs(usedBy) do
    table.sort(maps)
    ids[#ids + 1] = pair
  end
  -- Named tilesets first, then the ones known only by address.
  table.sort(ids, function(a, b)
    local ra, rb = a:find("__rom_", 1, true) ~= nil, b:find("__rom_", 1, true) ~= nil
    if ra ~= rb then return rb end
    return a < b
  end)
  return ids, usedBy
end

-- Definitions ----------------------------------------------------------------

local function int(v, lo, hi, default)
  v = tonumber(v)
  if not v or v ~= v then return default end
  v = math.floor(v)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.isCustom(tile) return type(tile) == "number" and tile >= M.CUSTOM end

local function cleanTile(tile)
  if tile == false or tile == nil then return false end
  if type(tile) == "string" then return TS.parseKey(tile) and tile or false end
  tile = tonumber(tile)
  if not tile then return false end
  if tile >= M.CUSTOM then return int(tile, M.CUSTOM, M.CUSTOM + M.MAX_CUSTOM, M.CUSTOM) end
  -- Projects saved by the first, ROM-based version numbered game tiles 0-1023.
  -- Tile 0 is the empty tile; other numbers can't be placed without the ROM
  -- and are kept so `problems` can point at them.
  if tile <= 0 then return false end
  return int(tile, 1, 1023, 1)
end

--- A clean copy of a definition: exactly 8 slots, in-range numbers.
function M.normalize(def)
  def = type(def) == "table" and def or {}
  local out = { slots = {}, layerType = LAYER_OK[def.layerType] and def.layerType or "normal",
    behavior = int(def.behavior, 0, 511, 0) }
  for i = 1, 8 do
    local s = type(def.slots) == "table" and def.slots[i] or nil
    s = type(s) == "table" and s or {}
    out.slots[i] = { tile = cleanTile(s.tile), pal = int(s.pal, 0, 15, 0),
      hflip = s.hflip == true, vflip = s.vflip == true }
  end
  if def.new then out.new = true end
  return out
end

--- One string per distinct look + meaning, for comparing and caching.
function M.signature(def)
  local parts = {}
  for i = 1, 8 do
    local s = def.slots[i]
    parts[i] = (s.tile and tostring(s.tile) or "-") .. "." .. s.pal
      .. (s.hflip and "h" or "") .. (s.vflip and "v" or "")
  end
  return table.concat(parts, ",") .. "|" .. def.layerType .. "|" .. def.behavior
end

local function own(project, pair, create)
  if not project then return nil end
  if create then
    project.gen3Blocks = project.gen3Blocks or {}
    project.gen3Blocks[pair] = project.gen3Blocks[pair] or {}
  end
  return project.gen3Blocks and project.gen3Blocks[pair]
end
M.own = own

function M.hasEdits(project, pair)
  local rows = own(project, pair)
  return rows ~= nil and next(rows) ~= nil
end

--- The block as the game has it (from its saved picture), or nil for an id
-- the game has no picture for.
function M.gameDefinition(S, pair, mid)
  if type(mid) ~= "number" then return nil end
  local pack = M.pack(S, pair)
  local def = pack and pack.sheet.defs[mid]
  if not def then return nil end
  local out = M.normalize(def)
  out.behavior = int(pack.behaviors[mid], 0, 511, 0)
  return out
end
M.romDefinition = M.gameDefinition

--- The block in effect: the project's edit if there is one, else the game's.
-- Returns def, edited, isNew.
function M.definition(S, pair, mid)
  if type(mid) ~= "number" then return nil, false, false end
  local rows = own(S.project, pair)
  local mine = rows and rows[tostring(mid)]
  if mine then return M.normalize(mine), true, mine.new == true end
  return M.gameDefinition(S, pair, mid), false, false
end

--- Save a block. Returns true when the project changed.
function M.store(S, pair, mid, def)
  def = M.normalize(def)
  local key = tostring(mid)
  local game = M.gameDefinition(S, pair, mid)
  local rows = own(S.project, pair, true)
  local before = rows[key] and M.signature(M.normalize(rows[key])) or nil
  if game then
    def.new = nil
    if M.signature(game) == M.signature(def) then
      rows[key] = nil
      if not next(rows) then S.project.gen3Blocks[pair] = nil end
      if not next(S.project.gen3Blocks) then S.project.gen3Blocks = nil end
      return before ~= nil
    end
  else
    def.new = true
  end
  if before == M.signature(def) then return false end
  rows[key] = def
  return true
end

--- Drop an edit to a game block, or delete a block the project added.
function M.revert(S, pair, mid)
  local rows = own(S.project, pair)
  if not rows or rows[tostring(mid)] == nil then return false end
  rows[tostring(mid)] = nil
  if not next(rows) then S.project.gen3Blocks[pair] = nil end
  if not next(S.project.gen3Blocks) then S.project.gen3Blocks = nil end
  return true
end

--- Every block id to show for a pair: the game's, then the project's new ones.
function M.ids(S, pair)
  local pack, err = M.pack(S, pair)
  if not pack then return nil, err end
  local out = {}
  for i, mid in ipairs(pack.mids) do out[i] = mid end
  local added = {}
  for key, def in pairs(own(S.project, pair) or {}) do
    local mid = tonumber(key)
    if mid and type(def) == "table" and def.new and not pack.index[mid] then
      added[#added + 1] = mid
    end
  end
  table.sort(added)
  for _, mid in ipairs(added) do out[#out + 1] = mid end
  return out
end

--- Add a block (blank, or a copy of `def`) with the first free id from 640.
-- Returns its id.
function M.newBlock(S, pair, def)
  local pack, err = M.pack(S, pair)
  if not pack then return nil, err end
  local rows = own(S.project, pair) or {}
  for mid = M.PRIMARY, M.MAX_MID do
    if rows[tostring(mid)] == nil and not pack.index[mid] then
      M.store(S, pair, mid, def or {})
      return mid
    end
  end
  return nil, "This tileset has no free block ids left (ids stop at 1023)"
end

--- For export: refuse anything malformed before it reaches a mod.
function M.validate(project)
  local function tileOk(t)
    return t == false or (type(t) == "string" and TS.parseKey(t) ~= nil)
      or (type(t) == "number" and t % 1 == 0 and ((t >= 1 and t <= 1023)
        or (t >= M.CUSTOM and t <= M.CUSTOM + M.MAX_CUSTOM)))
  end
  for pair, rows in pairs((project or {}).gen3Blocks or {}) do
    assert(type(pair) == "string" and pair ~= "", "Invalid tileset pair")
    assert(type(rows) == "table", "Invalid block table for " .. pair)
    for key, def in pairs(rows) do
      local mid = tonumber(key)
      assert(mid and mid % 1 == 0 and mid >= 0 and mid <= M.MAX_MID,
        "Invalid block id " .. tostring(key) .. " in " .. pair)
      assert(type(def) == "table" and type(def.slots) == "table" and #def.slots == 8,
        "Block " .. key .. " in " .. pair .. " needs 8 slots")
      for i, s in ipairs(def.slots) do
        assert(tileOk(s.tile) or s.tile == 0, ("Block %s slot %d: bad tile"):format(key, i))
        assert(type(s.pal) == "number" and s.pal % 1 == 0 and s.pal >= 0 and s.pal <= 15,
          ("Block %s slot %d: bad palette"):format(key, i))
      end
      assert(LAYER_OK[def.layerType], "Block " .. key .. ": bad layer type")
      assert(type(def.behavior) == "number" and def.behavior >= 0 and def.behavior <= 511,
        "Block " .. key .. ": bad behaviour")
    end
  end
  for pair, rows in pairs((project or {}).gen3Tiles or {}) do
    assert(type(pair) == "string" and pair ~= "" and type(rows) == "table", "Invalid tile table")
    for key, t in pairs(rows) do
      local n = tonumber(key)
      assert(n and n % 1 == 0 and n >= M.CUSTOM and n <= M.CUSTOM + M.MAX_CUSTOM,
        "Invalid tile number " .. tostring(key) .. " in " .. pair)
      assert(type(t) == "table" and type(t.px) == "string" and #t.px == 64
        and not t.px:find("[^%.0-9a-f]"), "Tile " .. key .. " in " .. pair .. ": bad pixels")
      assert(t.base == nil or (type(t.base) == "string" and TS.parseKey(t.base))
        or (type(t.base) == "number" and t.base % 1 == 0 and t.base >= 0 and t.base <= 1023),
        "Tile " .. key .. ": bad base tile")
    end
  end
end

-- Tiles ------------------------------------------------------------------------

local function ownTiles(project, pair, create)
  if not project then return nil end
  if create then
    project.gen3Tiles = project.gen3Tiles or {}
    project.gen3Tiles[pair] = project.gen3Tiles[pair] or {}
  end
  return project.gen3Tiles and project.gen3Tiles[pair]
end

function M.customTile(project, pair, tile)
  local rows = ownTiles(project, pair)
  return rows and rows[tostring(tile)]
end

--- Your tiles for a pair, in number order.
function M.customTiles(project, pair)
  local out = {}
  for key in pairs(ownTiles(project, pair) or {}) do
    local n = tonumber(key)
    if n then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

--- The game tiles found in a pair's saved blocks, in sheet order:
-- { {key, px, pal} ... }.
function M.gameTiles(S, pair)
  local pack = M.pack(S, pair)
  return pack and pack.sheet.tiles or {}
end

--- How a tile is named on screen: "#37" for the 37th game tile of the
-- sheet, "Y3" for your third, "-" for empty.
function M.tileLabel(S, pair, tile)
  if M.isCustom(tile) then return "Y" .. (tile - M.CUSTOM + 1) end
  if type(tile) == "string" then
    local pack = M.pack(S, pair)
    local n = pack and pack.sheet.index[tile]
    return n and ("#" .. n) or "?"
  end
  if type(tile) == "number" then return "old " .. tile end
  return "-"
end

--- Add a tile: a copy of game tile `base` (a key) to paint over, or blank.
-- Returns its number.
function M.newTile(S, pair, base)
  if type(base) ~= "string" then base = nil end
  local rows = ownTiles(S.project, pair, true)
  for n = M.CUSTOM, M.CUSTOM + M.MAX_CUSTOM do
    if rows[tostring(n)] == nil then
      rows[tostring(n)] = { base = base, px = string.rep(base and "." or "0", 64) }
      return n
    end
  end
  return nil, "This tileset has no room for more of your tiles"
end

--- The 64 colour numbers (0-15, reading order) of any tile, or nil when it
-- draws nothing or can't be found.
function M.tilePixels(S, pair, tile)
  if M.isCustom(tile) then
    local t = M.customTile(S.project, pair, tile)
    if not t then return nil end
    local base = t.base and M.tilePixels(S, pair, t.base)
    local out = {}
    for i = 1, 64 do
      local ch = t.px:sub(i, i)
      out[i] = ch == "." and (base and base[i] or 0) or ((HEX:find(ch, 1, true) or 1) - 1)
    end
    return out
  end
  if type(tile) == "string" then
    local pack = M.pack(S, pair)
    return pack and TS.tile(pack, tile) or nil
  end
  return nil
end

--- Can the game draw this tile? Empty always; game tiles when their block
-- is in the cache; yours when their base is (or every pixel is painted).
function M.tileAvailable(S, pair, tile)
  if tile == false then return true end
  if M.isCustom(tile) then
    local t = M.customTile(S.project, pair, tile)
    if not t then return false end
    if t.base == nil or not t.px:find(".", 1, true) then return true end
    return M.tileAvailable(S, pair, t.base)
  end
  if type(tile) == "string" then
    local pack = M.pack(S, pair)
    return pack ~= nil and TS.tile(pack, tile) ~= nil
  end
  return false -- a ROM tile number from an older project
end

--- Paint one pixel (1-64) of your tile. A pixel painted back to what the
-- base tile has there goes back to "keep". Returns true when it changed.
function M.setPixel(S, pair, tile, i, colour)
  local t = M.customTile(S.project, pair, tile)
  if not t or i < 1 or i > 64 then return false end
  colour = math.max(0, math.min(15, math.floor(colour)))
  local base = t.base and M.tilePixels(S, pair, t.base)
  local ch = (base and base[i] == colour) and "." or HEX:sub(colour + 1, colour + 1)
  if t.px:sub(i, i) == ch then return false end
  t.px = t.px:sub(1, i - 1) .. ch .. t.px:sub(i + 1)
  return true
end

--- Undo every stroke on your tile (back to its base, or blank).
function M.resetTile(S, pair, tile)
  local t = M.customTile(S.project, pair, tile)
  if not t then return false end
  local fresh = string.rep(t.base and "." or "0", 64)
  if t.px == fresh then return false end
  t.px = fresh
  return true
end

--- Delete your tile. Blocks still using it are flagged by `problems`.
function M.deleteTile(S, pair, tile)
  local rows = ownTiles(S.project, pair)
  if not rows or rows[tostring(tile)] == nil then return false end
  rows[tostring(tile)] = nil
  if not next(rows) then S.project.gen3Tiles[pair] = nil end
  if not next(S.project.gen3Tiles) then S.project.gen3Tiles = nil end
  return true
end

--- How many pixels of your tile you painted (the rest come from its base).
function M.paintedCount(project, pair, tile)
  local t = M.customTile(project, pair, tile)
  if not t then return 0 end
  local _, n = t.px:gsub("[^%.]", "")
  return n
end

--- Does this block need new pictures in game? A game block whose tiles and
-- layer type are untouched keeps the game's own (behaviour-only edits).
function M.needsTiles(S, pair, mid, def)
  local game = M.gameDefinition(S, pair, mid)
  if not game then return true end
  if game.layerType ~= def.layerType then return true end
  for i = 1, 8 do
    local a, b = game.slots[i], def.slots[i]
    if a.tile ~= b.tile or a.pal ~= b.pal or a.hflip ~= b.hflip or a.vflip ~= b.vflip then
      return true
    end
  end
  return false
end

--- Slots whose tile the game can't draw. Empty list = fine in game.
function M.problems(S, pair, mid, def)
  def = def or M.definition(S, pair, mid)
  if not def then return {} end
  if not M.needsTiles(S, pair, mid, def) then return {} end
  local out = {}
  for i = 1, 8 do
    if not M.tileAvailable(S, pair, def.slots[i].tile) then out[#out + 1] = i end
  end
  return out
end

--- A block's two pictures (under / over the player; 256 bytes each,
-- palette*16 + colour), composed exactly as the game will.
function M.composeBlock(S, pair, def)
  local tiles, slots = {}, {}
  for i = 1, 8 do
    local sl = def.slots[i]
    local k = sl.tile and tostring(sl.tile) or false
    if k and tiles[k] == nil then tiles[k] = M.tilePixels(S, pair, sl.tile) or false end
    slots[i] = { key = (k and tiles[k]) and k or false, pal = sl.pal, hflip = sl.hflip, vflip = sl.vflip }
  end
  for k, v in pairs(tiles) do if not v then tiles[k] = nil end end
  return TS.compose(tiles, { slots = slots, layerType = def.layerType })
end

-- In game ----------------------------------------------------------------------
--
-- On save, what the game needs goes into project.gen3BlockRuntime and from
-- there into main.lua (Gen3BlocksRuntime):
--
--   pairs[pair][mid] = { behavior, layerType, slots = {{key,pal,hflip,vflip}x8} }
--       slots is left out for a behaviour-only edit (the game keeps its
--       picture) and for a block using a tile the game can't draw.
--   tiles["y:<pair>:<n>"] = { base = <key>|nil, px = <64 chars> }   -- yours
--
-- Game tiles need no table: their key says where they are in the cache.

local function customKey(pair, tile) return "y:" .. pair .. ":" .. tostring(tile) end

--- Build the runtime table, or nil when the project has no blocks.
-- Returns data, warnings (list of strings).
function M.compileRuntime(S)
  local project = S.project or {}
  local any = false
  for _, rows in pairs(project.gen3Blocks or {}) do if next(rows) then any = true end end
  if not any then return nil, {} end
  local data = { pairs = {}, tiles = {} }
  local warnings = {}
  for pair, rows in pairs(project.gen3Blocks) do
    local out = {}
    for key, raw in pairs(rows) do
      local mid = tonumber(key)
      local def = M.normalize(raw)
      local rec = { behavior = def.behavior, layerType = def.layerType }
      if M.needsTiles(S, pair, mid, def) then
        if #M.problems(S, pair, mid, def) == 0 then
          rec.slots = {}
          for i = 1, 8 do
            local sl = def.slots[i]
            local k = sl.tile
            if M.isCustom(k) then
              local t = M.customTile(project, pair, k)
              k = customKey(pair, sl.tile)
              data.tiles[k] = data.tiles[k] or {
                base = t.px:find(".", 1, true) and t.base or nil, px = t.px }
            end
            rec.slots[i] = { key = k or false, pal = sl.pal, hflip = sl.hflip, vflip = sl.vflip }
          end
        else
          warnings[#warnings + 1] = ("%s block %d uses a tile the game can't draw; %s")
            :format(pair, mid, def.new and "it won't appear" or "it keeps its old look")
        end
      end
      out[mid] = rec
    end
    data.pairs[pair] = out
  end
  return data, warnings
end

--- Save hook (LayeredMap.compileProject): refresh project.gen3BlockRuntime.
function M.compileInto(S)
  local data, warnings = M.compileRuntime(S)
  S.project.gen3BlockRuntime = data
  if type(warnings) == "table" and #warnings > 0 then
    S.status = warnings[1] .. (#warnings > 1 and (" (+" .. (#warnings - 1) .. " more)") or "")
  end
  return true
end

-- The map editor ---------------------------------------------------------------
--
-- The map editor lists and draws blocks from the cache. These hooks (called
-- from LayeredMap.uniqueTiles and Gen3Workspace.descriptor / drawTile) add
-- the project's blocks and draw them as edited.

--- The picker's ids plus every block this project added or changed.
function M.mapPickerIds(S, pair, ids)
  local rows = own(S and S.project, pair)
  if not rows or not next(rows) then return ids end
  local seen, out = {}, {}
  for _, id in ipairs(ids or {}) do seen[id] = true; out[#out + 1] = id end
  for key in pairs(rows) do
    local mid = tonumber(key)
    if mid and not seen[mid] then seen[mid] = true; out[#out + 1] = mid end
  end
  table.sort(out)
  return out
end

--- Highest block id the project uses for a pair, or -1.
function M.maxProjectMid(S, pair)
  local top = -1
  for key in pairs(own(S and S.project, pair) or {}) do
    local mid = tonumber(key)
    if mid and mid > top then top = mid end
  end
  return top
end

--- Draw a project block (edited or new) at size x size. Returns false for
-- blocks the project doesn't touch, so the map editor draws its usual
-- cached picture instead.
function M.drawMapTile(S, pair, mid, x, y, size, alpha)
  local rows = own(S and S.project, pair)
  local mine = rows and rows[tostring(mid)]
  if not mine then return false end
  -- The map canvas asks for every cell every frame: remember this frame's
  -- answers (edits land next frame).
  local data = S.data or {}
  local now = require("Kit").time
  local memo = data._g3MapTileMemo
  if not memo or memo.t ~= now then memo = { t = now }; data._g3MapTileMemo = memo end
  local key = pair .. "|" .. tostring(mid)
  local hit = memo[key]
  if hit == nil then
    local u, o = M.blockImages(S, pair, mid, M.normalize(mine))
    hit = u and { u, o } or false
    memo[key] = hit
  end
  if not hit then return false end
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(hit[1], x, y, 0, size / 16, size / 16)
  love.graphics.draw(hit[2], x, y, 0, size / 16, size / 16)
  return true
end

-- Images (LOVE only) -----------------------------------------------------------

local function cache(S)
  local data = S.data or {}
  data._g3BlockImages = data._g3BlockImages or { n = 0, map = {} }
  return data._g3BlockImages
end

function M.clearImages(S)
  if S.data then S.data._g3BlockImages = nil end
end

local function image(w, h, rgba)
  local img = love.graphics.newImage(love.image.newImageData(w, h, "rgba8", rgba))
  img:setFilter("nearest", "nearest")
  return img
end

local function colourByte(pack, pal, c, transparentZero)
  if c == 0 and transparentZero then return string.char(0, 0, 0, 0) end
  local rgb = (pack.rgb[pal] or pack.rgb[0] or {})[c] or { 0, 0, 0 }
  return string.char(rgb[1] or 0, rgb[2] or 0, rgb[3] or 0, 255)
end

--- The two images a block draws as: under the player, and over them.
function M.blockImages(S, pair, mid, def)
  def = def or M.definition(S, pair, mid)
  if not def then return nil end
  local pack = M.pack(S, pair)
  if not pack then return nil end
  -- Your tiles change without the block changing: key on their pixels too.
  local key = "b|" .. pair .. "|" .. M.signature(def)
  for i = 1, 8 do
    local t = M.isCustom(def.slots[i].tile) and M.customTile(S.project, pair, def.slots[i].tile)
    if t then key = key .. "|" .. tostring(t.base) .. t.px end
  end
  local c = cache(S)
  local hit = c.map[key]
  if hit then return hit[1], hit[2] end
  local under, over = M.composeBlock(S, pair, def)
  if not under then return nil end
  local function rgba(idx, transparentZero)
    local out = {}
    for i = 1, 256 do
      local v = idx[i] or 0
      out[i] = colourByte(pack, math.floor(v / 16), v % 16, transparentZero)
    end
    return table.concat(out)
  end
  local u = image(16, 16, rgba(under, false))
  local o = image(16, 16, rgba(over, true))
  if c.n > 4000 then c.map, c.n = {}, 0 end
  c.map[key] = { u, o }
  c.n = c.n + 1
  return u, o
end

--- A tile sheet, `cols` tiles across, colour 0 transparent. `which` is
-- "game" (tiles from the saved blocks, each in its own palette) or "custom"
-- (your tiles, in palette `pal`). Returns image, tile list (keys/numbers).
function M.tileSheet(S, pair, pal, which, cols)
  cols = cols or 16
  local pack = M.pack(S, pair)
  if not pack then return nil, {} end
  local list, pxOf, palOf = {}, {}, {}
  if which == "custom" then
    local parts = {}
    for i, n in ipairs(M.customTiles(S.project, pair)) do
      list[i] = n
      pxOf[i] = M.tilePixels(S, pair, n) or {}
      palOf[i] = pal
      local t = M.customTile(S.project, pair, n)
      parts[i] = tostring(t.base) .. t.px
    end
    pal = pal .. "|" .. table.concat(parts, "|")
  else
    for i, t in ipairs(pack.sheet.tiles) do list[i] = t.key; pxOf[i] = t.px; palOf[i] = t.pal end
    pal = "own"
  end
  if #list == 0 then return nil, list end
  local key = ("t|%s|%s|%s|%d"):format(pair, which, pal, cols)
  local c = cache(S)
  local hit = c.map[key]
  if hit then return hit[1], hit[2] end
  local rows = math.ceil(#list / cols)
  local w, h = cols * 8, rows * 8
  local clear = string.char(0, 0, 0, 0)
  local lines = {}
  for py = 0, h - 1 do
    local line = {}
    local ty, y = math.floor(py / 8), py % 8
    for px = 0, w - 1 do
      local i = ty * cols + math.floor(px / 8) + 1
      local tp = pxOf[i]
      line[px + 1] = tp and colourByte(pack, palOf[i], tp[y * 8 + px % 8 + 1] or 0, true) or clear
    end
    lines[py + 1] = table.concat(line)
  end
  local img = image(w, h, table.concat(lines))
  c.map[key] = { img, list }
  c.n = c.n + 1
  return img, list
end

--- One tile as an 8x8 image in palette `pal` (colour 0 see-through).
function M.tileImage(S, pair, tile, pal)
  local pack = M.pack(S, pair)
  local px = pack and M.tilePixels(S, pair, tile)
  if not px then return nil end
  local key = "i|" .. pair .. "|" .. tostring(tile) .. "|" .. pal
  if M.isCustom(tile) then
    local t = M.customTile(S.project, pair, tile)
    key = key .. "|" .. tostring(t.base) .. t.px
  end
  local c = cache(S)
  local hit = c.map[key]
  if hit then return hit[1] end
  local bytes = {}
  for i = 1, 64 do bytes[i] = colourByte(pack, pal, px[i] or 0, true) end
  local img = image(8, 8, table.concat(bytes))
  if c.n > 4000 then c.map, c.n = {}, 0 end
  c.map[key] = { img }
  c.n = c.n + 1
  return img
end

--- A palette's 16 colours as LOVE {r,g,b} (0-1), for swatches.
function M.paletteColours(S, pair, pal)
  local pack = M.pack(S, pair)
  local colours = pack and (pack.rgb[pal] or pack.rgb[0]) or {}
  local out = {}
  for i = 0, 15 do
    local c = colours[i] or { 0, 0, 0 }
    out[i] = { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
  end
  return out
end

return M
