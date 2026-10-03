-- Export source (not bytecode): Town Map and Fly for regions a mod brings in
-- from a game. Used by Emerald Maps / Hoenn Region / FireRed Maps / Kanto
-- Region (Gen3EmLink, Gen3HoennRegion, Gen3FrLink, Gen3KantoRegion).
--
--  * Maps from the OTHER game (Hoenn in FireRed / LeafGreen, Kanto in
--    Emerald): on those maps the Town Map and Fly open that game's own map
--    screen, read from the player's own import, with the player's position
--    and the towns they have visited. Fly lands on the imported maps.
--  * Maps from the SAME game (Kanto Region in FireRed / LeafGreen, Hoenn
--    Region in Emerald): the game's own screens already fit; this sets the
--    "visited" flags the original maps' scripts would have set and sends Fly
--    to the imported copies when the originals aren't there.
--
-- Nothing in the engine is changed. While the other game's screen is open the
-- engine is told it is that game (version, constants, import folder, texts);
-- visited flags for it live in the mod's own save data, not the game's flags.
local M = {}

--- Flag ids a map script sets that mean "visited": `accept(op, id)` decides
-- which. Follows call / goto up to depth 4.
function M.scanFlags(scripts, key, accept, out, depth, seen)
  out = out or {}
  seen = seen or {}
  depth = depth or 0
  if type(key) ~= "string" or seen[key] or depth > 4 or type(scripts) ~= "table" then return out end
  seen[key] = true
  local list = scripts[key]
  if type(list) ~= "table" then return out end
  for _, op in ipairs(list) do
    if op.op == "setflag" or op.op == "setworldmapflag" then
      local id = tonumber(op.flag or op[1])
      if id and accept(op.op, id) then out[#out + 1] = id end
    elseif (op.op == "call" or op.op == "goto") and op.target then
      M.scanFlags(scripts, op.target, accept, out, depth + 1, seen)
    end
  end
  return out
end

local ORIGIN_ID = { emerald = { "emerald" }, firered = { "firered", "leafgreen" } }

function M.install(mod, cfg)
  cfg = cfg or {}
  local okF, Field = pcall(require, "src.core.game3.field")
  local okG, GV = pcall(require, "src.core.GameVersion")
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  local okK, Constants = pcall(require, "src.core.game3.constants")
  if not (okF and okG and okC and okK) then return end
  local okFl, Flags = pcall(require, "src.core.game3.scripting.flags")
  local okR, RomText = pcall(require, "src.core.game3.rom_text")
  if not (okFl and okR) then return end

  local St = Field._regionMap
  local first = St == nil
  if first then
    St = { regions = {}, scope = 0, maps = nil, pending = nil, ui = nil, mods = {} }
    Field._regionMap = St
  end
  local origin = cfg.origin == "firered" and "firered" or "emerald"
  local cross = cfg.cross == true
  local region = {
    region = cfg.region, prefix = cfg.prefix or "", origin = origin, cross = cross,
    secBase = tonumber(cfg.secBase) or 0, visits = cfg.visits or {}, derive = cfg.derive == true,
    modId = mod.id, nav = type(cfg.nav) == "table" and cfg.nav or nil,
  }
  St.regions[#St.regions + 1] = region

  -- the player's import of the other game ("emerald/", "firered/" or "leafgreen/")
  if cross then
    for _, id in ipairs(ORIGIN_ID[origin]) do
      local prefix = GV.cachePrefix(id)
      local okM, marker = pcall(CacheFs.readAt, prefix .. "rom-cache.complete")
      if okM and type(marker) == "string" and marker:find("^rom%-cache%-v%d+%-" .. id .. ":") then
        region.game, region.prefixDir = id, prefix
        break
      end
    end
    if not region.game then return end
  end

  mod.events:on("game.ready", function(ctx)
    St.maps = ctx and ctx.game and ctx.game.data and ctx.game.data.maps or St.maps
  end)

  local function regionOf(mapId)
    if type(mapId) ~= "string" then return nil end
    for _, r in ipairs(St.regions) do
      if r.region and mapId:sub(1, #r.region) == r.region then return r end
    end
    return nil
  end
  local function session() return Field.getSession and Field.getSession() or nil end
  local function foreignFlags(r)
    local s = session()
    if not s then return {} end
    s.modData = s.modData or {}
    local d = s.modData[r.modId] or {}
    s.modData[r.modId] = d
    d.regionFlags = d.regionFlags or {}
    d.regionFlags[r.origin] = d.regionFlags[r.origin] or {}
    return d.regionFlags[r.origin]
  end

  -- ---- visited flags -------------------------------------------------
  local derived = {}
  local function nativeVisits(r, mapId)
    if derived[mapId] ~= nil then return derived[mapId] end
    derived[mapId] = false
    local rest = mapId:sub(#r.region + 1)
    local maps = St.maps
    local def = maps and (maps[r.prefix .. rest] or maps[rest])
    local ms = def and type(def.mapScripts) == "table" and def.mapScripts
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    local bundle = okS and Space and Space.bundle
    local key = ms and ms.onTransition
    if not (key and bundle) then return false end
    local accept
    if r.origin == "emerald" then
      local base = Constants.of("emerald"):flag("FLAG_VISITED_LITTLEROOT_TOWN")
      accept = function(op, id) return op == "setflag" and base ~= nil and id >= base and id < base + 16 end
    else
      accept = function(op) return op == "setworldmapflag" end
    end
    local ids = M.scanFlags(bundle.scripts, key, accept)
    if #ids > 0 then derived[mapId] = ids end
    return derived[mapId]
  end
  mod.events:on("map.entered", function(e)
    local mapId = e and e.mapId
    local r = regionOf(mapId)
    if not r then return end
    if r.cross then
      local ids = r.visits[mapId]
      if ids then
        local store = foreignFlags(r)
        for _, id in ipairs(ids) do store[id] = true end
      end
    elseif r.derive then
      local ids = nativeVisits(r, mapId)
      local okS, Space = pcall(require, "src.core.game3.scripting.space")
      if ids and okS and Space and Space.store then
        for _, id in ipairs(ids) do pcall(Flags.setFlag, Space.store, Space.vm and Space.vm.ctx or nil, id, true) end
      end
    end
  end)

  -- ---- Fly: same-game regions land on the imported copies -------------
  local function copyOf(r, orig)
    local rest = orig:sub(1, #r.prefix) == r.prefix and orig:sub(#r.prefix + 1) or orig
    return r.region .. rest
  end
  local function native(mapId)
    local maps = St.maps
    if not maps or maps[mapId] then return nil end
    for _, r in ipairs(St.regions) do
      if not r.cross and r.region then
        local copy = copyOf(r, mapId)
        if maps[copy] then return copy end
      end
    end
    return nil
  end

  if not first then return end

  -- ---- shared wrappers (installed once, for every region) -------------
  local flyDestination, flyTo = Field.flyDestination, Field.flyTo
  Field.flyDestination = function(section)
    local p = St.pending
    if p then St.pending = nil; return p end
    return flyDestination(section)
  end
  Field.flyTo = function(section, mon, info)
    local dest = (info and info.dest) or Field.flyDestination(section)
    if type(dest) == "table" and type(dest.map) == "string" then
      local copy = native(dest.map)
      if copy then
        local d = {}
        for k, v in pairs(dest) do d[k] = v end
        d.map = copy
        info = { dest = d, posWithinMapSec = info and info.posWithinMapSec }
        return flyTo(section, mon, info)
      end
    end
    return flyTo(section, mon, info)
  end

  -- ---- "act as the other game" ----------------------------------------
  local function foreignRun(r, fn, ...)
    local saved = GV.current
    St.scope = St.scope + 1
    St.cur = r
    GV.current = r.game
    local ok, a, b = pcall(fn, ...)
    GV.current = saved
    St.scope = St.scope - 1
    if St.scope == 0 then St.cur = nil end
    if not ok then error(a, 0) end
    return a, b
  end

  -- the other game's flags (the mod's own save data) and texts
  local getFlag, getVar = Flags.getFlag, Flags.getVar
  Flags.getFlag = function(store, ctx, id)
    if St.scope > 0 and St.cur then return foreignFlags(St.cur)[id] == true end
    return getFlag(store, ctx, id)
  end
  Flags.getVar = function(store, ctx, id)
    if St.scope > 0 and St.cur then return 0 end
    return getVar(store, ctx, id)
  end
  local function readLua(r, rel)
    local bytes = CacheFs.readAt(r.prefixDir .. rel)
    local chunk = bytes and load(bytes, "=" .. rel, "t", {})
    if not chunk then return nil end
    local ok, v = pcall(chunk)
    return ok and type(v) == "table" and v or nil
  end
  local texts = {}
  local ir, has = RomText.ir, RomText.has
  local function foreignText(r, key)
    local t = texts[r.game]
    if t == nil then t = readLua(r, "data/generated/gba/scripts/text.lua") or false; texts[r.game] = t end
    return t and t[key] or nil
  end
  RomText.ir = function(key)
    if St.scope > 0 and St.cur then
      local v = foreignText(St.cur, key)
      if v ~= nil then return v end
    end
    return ir(key)
  end
  RomText.has = function(key)
    if St.scope > 0 and St.cur and foreignText(St.cur, key) ~= nil then return true end
    return has(key)
  end

  -- Emerald's screen reads its pictures and tables by path
  local okKit, Kit = pcall(require, "src.ui.game3.rse.scene_kit")
  if okKit and Kit then
    local images, manifests = {}, {}
    local kImage, kLoad = Kit.image, Kit.loadLua
    Kit.image = function(path)
      local r = St.scope > 0 and St.cur
      if not (r and type(path) == "string") then return kImage(path) end
      local key = r.game .. ":" .. path
      local hit = images[key]
      if hit ~= nil then return hit or nil end
      local img = false
      local bytes = CacheFs.readAt(r.prefixDir .. path)
      if bytes then
        local ok, data = pcall(love.image.newImageData, love.data.newByteData(bytes))
        if ok then img = love.graphics.newImage(data); img:setFilter("nearest", "nearest") end
      end
      images[key] = img
      return img or nil
    end
    Kit.loadLua = function(path)
      local r = St.scope > 0 and St.cur
      if not (r and type(path) == "string") then return kLoad(path) end
      local key = r.game .. ":" .. path
      local hit = manifests[key]
      if hit ~= nil then return hit or nil end
      local t = readLua(r, path) or false
      manifests[key] = t
      return t or nil
    end
  end

  -- FireRed's screen finds a map's place in its list of maps by name; the
  -- imported copies are matched by their names instead
  local okMC, MC = pcall(require, "src.import.gba.map_catalog")
  if okMC and MC then
    local function norm(id)
      id = tostring(id):gsub("^EM_KANTO_", ""):gsub("^FR_KANTO_", ""):gsub("^FR_", ""):gsub("^SEVII_", "")
      return (id:gsub("[_%s]", ""):upper())
    end
    local slotKeyFor, resolve = MC.slotKeyFor, MC.resolve
    MC.slotKeyFor = function(id, ...)
      if St.scope > 0 and type(id) == "string" then
        local h = 0
        for c in norm(id):gmatch(".") do h = (h * 31 + c:byte()) % 1000003 end
        return "0_" .. h
      end
      return slotKeyFor(id, ...)
    end
    MC.resolve = function(a, b)
      if St.scope > 0 and type(a) == "string" and b == nil then return a end
      return resolve(a, b)
    end
  end

  local function proxy(s, r)
    local empty = {}
    return setmetatable({}, {
      __index = function(_, k)
        if k == "version" then return r.game end
        if k == "flags" then return empty end
        return s[k]
      end,
      __newindex = function(_, k, v) s[k] = v end,
    })
  end

  -- the other game's Fly destinations, on the imported maps
  local flyData = {}
  local function foreignDest(r, sec)
    local data = flyData[r.game]
    if data == nil then
      local t = readLua(r, "data/generated/gba/region_map/fly_destinations.lua")
      data = {}
      for _, row in pairs(t and t.fly_destinations or {}) do data[tonumber(row.mapsec)] = row end
      flyData[r.game] = data
    end
    local row = data[tonumber(sec)]
    if not row then return nil end
    local copy = copyOf(r, row.map)
    if not (St.maps and St.maps[copy]) then return nil end
    return { mapsec = tonumber(sec), map = copy, x = row.x, y = row.y }
  end

  -- ---- the screens ------------------------------------------------------
  local okRse, Rse = pcall(require, "src.ui.game3.rse.region_map")
  local okFr, Fr = pcall(require, "src.ui.game3.region_map")

  -- FireRed's own screen on the imported copies of FireRed's maps: only the
  -- map lookups need the copies matched by name
  local function nativeRun(fn, ...)
    St.scope = St.scope + 1
    local ok, a, b = pcall(fn, ...)
    St.scope = St.scope - 1
    if not ok then error(a, 0) end
    return a, b
  end

  local function wrapHost(tbl, names, r)
    for _, name in ipairs(names) do
      local fn = tbl[name]
      if type(fn) == "function" and not rawget(tbl, "_regionWrap_" .. name) then
        tbl["_regionWrap_" .. name] = true
        tbl[name] = function(...)
          local cur = St.ui
          if cur and cur.tbl == tbl then
            if cur.native then return nativeRun(fn, ...) end
            return foreignRun(cur.r, fn, ...)
          end
          return fn(...)
        end
      end
    end
  end

  -- Emerald's screen inside FireRed / LeafGreen
  local function openEmerald(r, opts)
    local s = proxy(opts.session, r)
    local fly = opts.mode == "fly"
    local Runtime = require("src.core.game3.runtime")
    local game = Runtime._game
    local gdata = game and game.data
    local real = gdata and gdata.maps
    local base = r.secBase
    local function conv(def)
      local v = type(def) == "table" and tonumber(def.regionMapSectionId)
      if v and base > 0 and v >= base then return setmetatable({ regionMapSectionId = v - base }, { __index = def }) end
      return def
    end
    local Map = require("src.core.game3.map")
    local cur = Map.currentDef and Map.currentDef()
    St.ui = { tbl = Rse.Host, r = r }
    wrapHost(Rse.Host, { "update", "draw", "handleInput" }, r)
    local function done(picked)
      St.ui = nil
      if not picked and opts.onClose then opts.onClose() end
    end
    local ok, err = pcall(function()
      if real and base > 0 then
        gdata.maps = setmetatable({}, { __index = function(_, k) return conv(real[k]) end })
      end
      local okS, e2 = pcall(foreignRun, r, Rse.show, {
        session = s, mode = fly and "fly" or "wall", mapDef = conv(cur),
        onPick = function(sec)
          local dest = foreignDest(r, sec)
          if not dest then return false end
          St.pending = dest
          if opts.onPick then opts.onPick(sec) end
          return true
        end,
        onClose = done,
      })
      if real and base > 0 then gdata.maps = real end
      if not okS then error(e2, 0) end
    end)
    if not ok then
      if real and gdata then gdata.maps = real end
      St.ui = nil
      return false, err
    end
    return true
  end

  -- FireRed's screen inside Emerald
  local function openFireRed(r, opts)
    local s = proxy(opts.session, r)
    St.ui = { tbl = Fr, r = r }
    wrapHost(Fr, { "update", "draw", "handleInput" }, r)
    local ok, err = pcall(foreignRun, r, Fr.show, {
      session = s, mode = opts.mode,
      onPick = function(sym, mapsec)
        local sec = tonumber(mapsec) or tonumber(sym)
        local dest = sec and foreignDest(r, sec)
        if not dest then return false end
        St.pending = dest
        St.ui = nil
        if opts.onPick then opts.onPick(sec, { posWithinMapSec = 0 }) end
        return true
      end,
      onClose = function(picked)
        St.ui = nil
        if not picked and opts.onClose then opts.onClose() end
      end,
    })
    if not ok then St.ui = nil; return false, err end
    return true
  end

  local function currentRegion()
    local okM, Map = pcall(require, "src.core.game3.map")
    local id = okM and Map and Map.current
    local r = regionOf(id)
    return r and r.cross and r or nil
  end

  -- FireRed / LeafGreen: the Town Map item, Town Map scripts and Fly
  if okFr and Fr and Fr.show and not Fr._regionShow then
    Fr._regionShow = Fr.show
    Fr.show = function(opts)
      local r = currentRegion()
      if r and r.origin == "emerald" and okRse and opts and opts.session then
        local ok = openEmerald(r, { session = opts.session, mode = opts.mode == "fly" and "fly" or "wall",
          onPick = opts.onPick, onClose = opts.onClose })
        if ok then return end
      end
      if r == nil and opts and opts.session then
        local okM, Map = pcall(require, "src.core.game3.map")
        local nat = okM and Map and regionOf(Map.current)
        if nat and not nat.cross and nat.origin == "firered" then
          wrapHost(Fr, { "update", "draw", "handleInput" }, nat)
          local o2 = {}
          for k, v in pairs(opts) do o2[k] = v end
          local function done() if St.ui and St.ui.native then St.ui = nil end end
          local onPick, onClose = opts.onPick, opts.onClose
          if onPick then o2.onPick = function(...) done(); return onPick(...) end end
          o2.onClose = function(...) done(); if onClose then return onClose(...) end end
          St.ui = { tbl = Fr, r = nat, native = true }
          local ok, err = pcall(nativeRun, Fr._regionShow, o2)
          if not ok then St.ui = nil; error(err, 0) end
          return
        end
      end
      return Fr._regionShow(opts)
    end
  end

  -- Emerald: Fly (the field move) and the PokeNav map
  if okRse and Rse and Rse.show and not Rse._regionShow then
    Rse._regionShow = Rse.show
    Rse.show = function(opts)
      local r = currentRegion()
      if r and r.origin == "firered" and okFr and opts and opts.mode == "fly" and opts.session then
        local ok = openFireRed(r, { session = opts.session, mode = "fly", onPick = opts.onPick, onClose = opts.onClose })
        if ok then return end
      end
      return Rse._regionShow(opts)
    end
    local rwd = Rse.flyWarpDestination
    Rse.flyWarpDestination = function(...)
      local p = St.pending
      if p then St.pending = nil; return p end
      return rwd(...)
    end
  end

  local okP, Pokenav = pcall(require, "src.ui.game3.rse.pokenav.init")
  local okMM, MainMenu = pcall(require, "src.ui.game3.rse.pokenav.main_menu")
  if okP and okMM and Pokenav and MainMenu and type(MainMenu.callback) == "function" and not MainMenu._regionCb then
    MainMenu._regionCb = MainMenu.callback
    MainMenu.callback = function(self, inp)
      local res = MainMenu._regionCb(self, inp)
      if res == Pokenav.MENU.REGION_MAP then
        local r = currentRegion()
        if r and r.origin == "firered" and okFr then
          St.townMap = { r = r, session = self.session }
          return Pokenav.EXIT
        end
      end
      return res
    end
    local show = Pokenav.show
    Pokenav.show = function(opts)
      opts = opts or {}
      local onClose = opts.onClose
      opts.onClose = function(...)
        if onClose then onClose(...) end
        local t = St.townMap
        St.townMap = nil
        if t then
          -- the PokeNav is gone; clear its frame before FireRed's screen opens
          local okG, Gfx = pcall(require, "src.ui.game3.rse.pokenav.gfx")
          if okG and Gfx and type(Gfx.reset) == "function" then pcall(Gfx.reset) end
          openFireRed(t.r, { session = t.session or session(), mode = "normal" })
        end
      end
      return show(opts)
    end
  end

  -- On a Kanto map the PokeNav's first entry names the region, not Hoenn: the
  -- description line and the "HOENN MAP" label (redrawn from the game's own
  -- label sheet, with the name swapped)
  local okGx, PGfx = pcall(require, "src.ui.game3.rse.pokenav.gfx")
  if okGx and PGfx and okMM and MainMenu and not PGfx._regionPlain then
    local function onKanto()
      local r = currentRegion()
      if r ~= nil and r.origin == "firered" then return r end
      return nil
    end
    local function navText(r, which)
      local v = r and r.nav and r.nav[which]
      if type(v) == "string" and v ~= "" then return v end
      return which == "label" and "REGION MAP" or "Check the map of the region."
    end
    local function relabel(img, man, text)
      local labels = {}
      for t = 0, 2 do
        local m = man.menus and man.menus[t]
        if m and m.items and m.items[1] then labels[m.items[1]] = true end
      end
      if next(labels) == nil then return nil end
      local w, h = img:getDimensions()
      local function canvas(draw)
        local c = love.graphics.newCanvas(w, h)
        love.graphics.push("all")
        love.graphics.origin()
        love.graphics.setCanvas(c)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        draw()
        love.graphics.pop()
        return c
      end
      local c1 = canvas(function()
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.draw(img, 0, 0)
      end)
      local data = c1:newImageData()
      local ink = {}
      for label in pairs(labels) do
        local y0 = (label - 1) * 16
        local fg = { data:getPixel(16, y0 + 4) }
        local shadow = { data:getPixel(17, y0 + 4) }
        ink[label] = { fg = fg, shadow = shadow }
        for y = 0, 15 do
          local bar = { data:getPixel(100, y0 + y) }
          for x = 14, 84 do data:setPixel(x, y0 + y, bar[1], bar[2], bar[3], bar[4]) end
        end
      end
      local base = love.graphics.newImage(data)
      local c2 = canvas(function()
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.draw(base, 0, 0)
        love.graphics.setBlendMode("alpha")
        for label, c in pairs(ink) do
          PGfx.text(text, 16, (label - 1) * 16 + 1, { bg = { 0, 0, 0, 0 }, fg = c.fg, shadow = c.shadow })
        end
      end)
      return love.graphics.newImage(c2:newImageData())
    end

    PGfx._regionPlain, PGfx._regionImage = PGfx.plain, PGfx.image
    PGfx.plain = function(key, ctx)
      local r = key and onKanto()
      if r then
        local man = PGfx.manifest()
        local d = man and man.pageDescriptions
        if d and key == d[MainMenu.ITEM.MAP] then return navText(r, "desc") end
      end
      return PGfx._regionPlain(key, ctx)
    end
    local sheets = {}
    PGfx.image = function(entry)
      local img = PGfx._regionImage(entry)
      local r = img and onKanto()
      if not r then return img end
      local man = PGfx.manifest()
      local opt = man and man.sprites and man.sprites.options
      if not (type(opt) == "table" and (entry == opt or (type(entry) == "table" and entry.png == opt.png))) then return img end
      local text = navText(r, "label")
      local per = sheets[img]
      if not per then per = {}; sheets[img] = per end
      local hit = per[text]
      if hit == nil then
        local ok, res = pcall(relabel, img, man, text)
        hit = ok and res or false
        per[text] = hit
      end
      return hit or img
    end
  end
end

return M
