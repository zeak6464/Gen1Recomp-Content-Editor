-- Gen 3 tiles taken from the game's own block cache. No ROM, anywhere.
--
-- When the game (or the editor) imports FireRed it saves every block a map
-- uses as finished 16x16 pictures: native/<pair>/mids.idx (drawn under the
-- player) and mids_over.idx (over the player), one byte per pixel,
-- palette*16 + colour, 0 = see-through. Those pictures are all this module
-- reads. The editor and the game both have them.
--
-- A tile here is one 8x8 quadrant of one of those pictures, in one palette:
--
--   key = "<block>/<layer>/<quadrant>/<palette>"   e.g. "20/u/2/3"
--         layer "u" = under the player, "o" = over; quadrant 0-3 = TL TR BL BR
--
-- Its pixels are the colour numbers (0-15) of the quadrant's pixels drawn in
-- that palette; any other pixel is 0. A "covered" block paints both of its
-- layers into the under picture, usually in two palettes; splitting by
-- palette gives both tiles back. The key is also all a mod needs to rebuild
-- the tile on the player's machine, so it is what projects and mods store.
--
-- Pure Lua: no LOVE, no engine requires. The editor uses it directly and the
-- export inlines it into the mod's main.lua.
local TS = {}

--- Decode a tileset's cached pictures (the engine's "SVMI" files).
-- Returns { mids = {sorted ids}, index = {[mid] = 1-based slot},
--           under = {bytes}, over = {bytes} } or nil.
function TS.decodePair(underBlob, overBlob)
  local function decode(blob)
    if type(blob) ~= "string" or #blob < 12 or blob:sub(1, 4) ~= "SVMI" then return nil end
    local count = blob:byte(7) + blob:byte(8) * 256
    if count < 1 or #blob < 12 + count * 2 + count * 256 then return nil end
    local ids, off = {}, 13
    for i = 1, count do ids[i] = blob:byte(off) + blob:byte(off + 1) * 256; off = off + 2 end
    local pix, n = {}, 0
    for c = off, off + count * 256 - 1, 256 do
      local chunk = { blob:byte(c, c + 255) }
      for i = 1, 256 do n = n + 1; pix[n] = chunk[i] end
    end
    return ids, pix
  end
  local ids, under = decode(underBlob)
  if not ids then return nil end
  local overIds, over = decode(overBlob)
  if not overIds or #overIds ~= #ids then over = {} end
  local index, mids = {}, {}
  for i, mid in ipairs(ids) do index[mid] = i; mids[i] = mid end
  table.sort(mids)
  return { index = index, under = under, over = over, mids = mids }
end

function TS.key(mid, layer, q, pal)
  return ("%d/%s/%d/%d"):format(mid, layer, q, pal)
end

function TS.parseKey(key)
  if type(key) ~= "string" then return nil end
  local mid, layer, q, pal = key:match("^(%d+)/([uo])/([0-3])/(%d+)$")
  if not mid then return nil end
  return tonumber(mid), layer, tonumber(q), tonumber(pal)
end

--- One quadrant of a cached picture: 64 raw bytes (palette*16 + colour).
local function quadrant(pack, mid, layer, q)
  local n = pack.index[mid]
  if not n then return nil end
  local pix = layer == "o" and pack.over or pack.under
  local base = (n - 1) * 256
  local ox, oy = (q % 2) * 8, math.floor(q / 2) * 8
  local out = {}
  for y = 0, 7 do
    for x = 0, 7 do out[y * 8 + x + 1] = pix[base + (oy + y) * 16 + ox + x + 1] or 0 end
  end
  return out
end

--- A tile's 64 colour numbers (reading order), or nil when the block isn't
-- in this cache.
function TS.tile(pack, key)
  local mid, layer, q, pal = TS.parseKey(key)
  if not mid then return nil end
  local raw = quadrant(pack, mid, layer, q)
  if not raw then return nil end
  local out = {}
  for i = 1, 64 do
    local v = raw[i]
    out[i] = (v ~= 0 and math.floor(v / 16) == pal) and v % 16 or 0
  end
  return out
end

local function flipped(px, h, v)
  local out = {}
  for y = 0, 7 do
    for x = 0, 7 do
      out[y * 8 + x + 1] = px[(v and 7 - y or y) * 8 + (h and 7 - x or x) + 1]
    end
  end
  return out
end

--- Every distinct tile in a tileset's cached blocks, and each cached block
-- written as a definition over those tiles (drawing it reproduces the cached
-- pictures exactly). Tiles that are flips of each other are kept once.
-- Returns { tiles = { {key, px, pal} ... }, index = {[key] = n},
--           defs = {[mid] = def} }.
function TS.harvest(pack)
  local tiles, index, seen, defs = {}, {}, {}, {}
  local function ref(mid, layer, q, pal)
    local key = TS.key(mid, layer, q, pal)
    local px = TS.tile(pack, key)
    for _, f in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
      local hit = seen[table.concat(flipped(px, f[1], f[2]), ",")]
      if hit then return { tile = hit, pal = pal, hflip = f[1], vflip = f[2] } end
    end
    seen[table.concat(px, ",")] = key
    tiles[#tiles + 1] = { key = key, px = px, pal = pal }
    index[key] = #tiles
    return { tile = key, pal = pal, hflip = false, vflip = false }
  end
  local function palettesIn(mid, layer, q)
    local raw, set, list = quadrant(pack, mid, layer, q), {}, {}
    for i = 1, 64 do
      local v = raw[i]
      if v ~= 0 then
        local p = math.floor(v / 16)
        if not set[p] then set[p] = true; list[#list + 1] = p end
      end
    end
    table.sort(list)
    return list
  end
  for _, mid in ipairs(pack.mids) do
    local slots, covered = {}, false
    for q = 0, 3 do
      local pals = palettesIn(mid, "u", q)
      if pals[1] then slots[q + 1] = ref(mid, "u", q, pals[1]) end
      if pals[2] then slots[q + 5] = ref(mid, "u", q, pals[2]); covered = true end
    end
    for q = 0, 3 do
      local pals = palettesIn(mid, "o", q)
      if pals[1] and not slots[q + 5] then slots[q + 5] = ref(mid, "o", q, pals[1]) end
    end
    for i = 1, 8 do
      slots[i] = slots[i] or { tile = false, pal = 0, hflip = false, vflip = false }
    end
    defs[mid] = { slots = slots, layerType = covered and "covered" or "normal" }
  end
  return { tiles = tiles, index = index, defs = defs }
end

--- Compose one block the way the engine does (Metatile.compositeIndexedUnder
-- / Over). def.slots[1..8] = { key = tile key or false, pal, hflip, vflip }
-- with slots 1-4 the bottom layer and 5-8 the top; `tiles[key]` = 64 colour
-- numbers. Returns under, over (256 bytes each), or nil and the bad slot.
function TS.compose(tiles, def)
  local under, over = {}, {}
  for i = 1, 256 do under[i] = 0; over[i] = 0 end
  local covered = def.layerType == "covered"
  for s = 1, 8 do
    local slot = def.slots[s]
    local t = slot.key and tiles[slot.key]
    if slot.key and not t then return nil, s end
    if t then
      local top = s > 4
      local q = (s - 1) % 4
      local ox, oy = (q % 2) * 8, math.floor(q / 2) * 8
      local dest = (top and not covered) and over or under
      for y = 0, 7 do
        for x = 0, 7 do
          local c = t[(slot.vflip and 7 - y or y) * 8 + (slot.hflip and 7 - x or x) + 1]
          if c == nil or c < 0 then return nil, s end
          local di = (oy + y) * 16 + ox + x + 1
          if c ~= 0 then
            dest[di] = (slot.pal % 16) * 16 + c
          elseif not top then
            dest[di] = 0
          end
        end
      end
    end
  end
  return under, over
end

return TS
