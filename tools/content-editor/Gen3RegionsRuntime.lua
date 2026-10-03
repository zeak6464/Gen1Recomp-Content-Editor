-- Export source (not bytecode): the PokeNav wording of the regions a mod
-- defines (Gen3Regions), Emerald only. On a map in a region that has an entry
-- and / or a description, the PokeNav's first menu entry (and the line under
-- it) say that instead of "HOENN MAP" / "Check the map of the HOENN region.".
-- The label is redrawn at run time from the game's own label sheet (the name
-- swapped); nothing from the game is carried in the mod.
local M = {}

local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

--- cfg.regions: { {prefixes, include, exclude, label, desc} }
function M.install(mod, cfg)
  local regions = type(cfg) == "table" and cfg.regions or nil
  if type(regions) ~= "table" or #regions == 0 then return end
  local okG, PGfx = pcall(require, "src.ui.game3.rse.pokenav.gfx")
  local okM, MainMenu = pcall(require, "src.ui.game3.rse.pokenav.main_menu")
  local okMap, Map = pcall(require, "src.core.game3.map")
  if not (okG and okM and okMap and PGfx and MainMenu and Map) then return end

  -- the region a map is in: an explicit add, else the longest prefix
  local function ownerOf(mapId)
    if type(mapId) ~= "string" then return nil end
    for _, r in ipairs(regions) do
      if has(r.include, mapId) then return r end
    end
    local best, bestLen
    for _, r in ipairs(regions) do
      if not has(r.exclude, mapId) then
        for _, p in ipairs(r.prefixes or {}) do
          if #p > 0 and mapId:sub(1, #p) == p and (not bestLen or #p > bestLen) then best, bestLen = r, #p end
        end
      end
    end
    return best
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
      ink[label] = { fg = { data:getPixel(16, y0 + 4) }, shadow = { data:getPixel(17, y0 + 4) } }
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

  local plain, image = PGfx.plain, PGfx.image
  PGfx.plain = function(key, ctx)
    local r = key and ownerOf(Map.current)
    if r and r.desc then
      local man = PGfx.manifest()
      local d = man and man.pageDescriptions
      if d and key == d[MainMenu.ITEM.MAP] then return r.desc end
    end
    return plain(key, ctx)
  end
  local sheets = {}
  PGfx.image = function(entry)
    local img = image(entry)
    local r = img and ownerOf(Map.current)
    if not (r and r.label) then return img end
    local man = PGfx.manifest()
    local opt = man and man.sprites and man.sprites.options
    if not (type(opt) == "table" and (entry == opt or (type(entry) == "table" and entry.png == opt.png))) then return img end
    local per = sheets[img]
    if not per then per = {}; sheets[img] = per end
    local hit = per[r.label]
    if hit == nil then
      local ok, res = pcall(relabel, img, man, r.label)
      hit = ok and res or false
      per[r.label] = hit
    end
    return hit or img
  end
end

return M
