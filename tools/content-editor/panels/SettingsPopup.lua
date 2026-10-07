-- The Settings button on the top bar and its pop-up (EditorSettings keeps the
-- values). Theme: ready-made looks plus any colour from the hue bar; the
-- editor recolours as you choose.

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local Settings = require("EditorSettings")

local M = {}

function M.isOpen(S) return S._settingsOpen == true end
function M.open(S) S._settingsOpen = true end
function M.close(S) S._settingsOpen = nil; S._settingsDragHue = nil end

local function choose(id, hue)
  Theme.apply(id, hue)
  Settings.set("theme", id)
  if hue then Settings.set("themeHue", hue) end
end
M.choose = choose

-- One look, drawn as the front of a Game Boy Advance cartridge in the
-- theme's colour: the wider grip band on top, the arched ridge under it, the
-- big label (a tiny view of the editor in that theme) and the small arrow
-- at the bottom, with the name below.
local function shade(c, f) return { c[1] * f, c[2] * f, c[3] * f } end

-- The cart's Pokemon: its front sprite, read from an imported FireRed or
-- LeafGreen (same sprites, same numbers). Looks in the open game first, then
-- the firered/ and leafgreen/ imports in the editor's save folder, the linked
-- Gen1Recomp folder and the game's own save folder. Nothing is shipped;
-- without an import the cart just has no Pokemon.
local SPRITE = "data/generated/gba/pokemon/front/%d.rgba"
local SPRITE_BYTES = 64 * 64 * 4
local GAMES = { "firered/", "leafgreen/" }

local function diskRoots()
  local roots = {}
  local okD, DataSource = pcall(require, "DataSource")
  if okD and type(DataSource) == "table" and DataSource.loadPrefs then
    local okP, prefs = pcall(DataSource.loadPrefs)
    if okP and type(prefs) == "table" and type(prefs.recompRoot) == "string" and prefs.recompRoot ~= "" then
      roots[#roots + 1] = (prefs.recompRoot:gsub("[/\\]+$", ""))
    end
  end
  -- Both places Gen1Recomp saves to (love.exe and the fused game differ).
  if okD and type(DataSource) == "table" and DataSource.sharedCacheRoots then
    for _, root in ipairs(DataSource.sharedCacheRoots()) do roots[#roots + 1] = root end
  end
  return roots
end

local function good(b) return type(b) == "string" and #b == SPRITE_BYTES end

local function readSprite(S, index, roots)
  local path = SPRITE:format(index)
  local read = S and S.data and S.data._gen3Read
  if read then
    local ok, b = pcall(read, path)
    if ok and good(b) then return b end
  end
  local fs = love.filesystem
  for _, game in ipairs(GAMES) do
    if fs and fs.getInfo and fs.getInfo(game .. path, "file") then
      local b = fs.read(game .. path)
      if good(b) then return b end
    end
  end
  for _, root in ipairs(roots) do
    for _, game in ipairs(GAMES) do
      local f = io.open(root .. "/" .. game .. path, "rb")
      if f then
        local b = f:read("*a")
        f:close()
        if good(b) then return b end
      end
    end
  end
end

local mascots, mascotsFor, roots = {}, nil, nil
local function mascot(S, index)
  if not index then return nil end
  -- a game opened or changed: look again for the ones not found yet
  local data = S and S.data or false
  if mascotsFor ~= data then
    mascotsFor, roots = data, nil
    for k, v in pairs(mascots) do if v == false then mascots[k] = nil end end
  end
  if mascots[index] ~= nil then return mascots[index] or nil end
  roots = roots or diskRoots()
  local bytes = readSprite(S, index, roots)
  local img = false
  if good(bytes) then
    local ok, i = pcall(function()
      local im = love.graphics.newImage(love.image.newImageData(64, 64, "rgba8", bytes))
      im:setFilter("nearest", "nearest")
      return im
    end)
    if ok then img = i end
  end
  mascots[index] = img
  return img or nil
end

local function swatch(x, y, w, h, pal, label, on, img)
  local s = Kit.scale
  local G = love.graphics
  local areaH = h - 22 * s
  local cw = math.min(w - 8 * s, (areaH - 6 * s) * 1.75)
  local ch = cw / 1.75
  local cx, cy = x + (w - cw) / 2, y + (areaH - ch) / 2
  local body, band, dark, light = shade(pal.blue, 0.46), shade(pal.blue, 0.54), shade(pal.blue, 0.22), shade(pal.blue, 0.7)
  local r = ch * 0.07
  local lw = math.max(1, 1.2 * s)
  if G.setLineWidth then G.setLineWidth(lw) end
  -- body: a little narrower than the grip band, rounded at the bottom
  local bx0, bw0, by0 = cx + cw * 0.035, cw * 0.93, cy + ch * 0.1
  Theme.col(body, 1)
  G.rectangle("fill", bx0, by0, bw0, ch - ch * 0.1, r, r)
  G.rectangle("fill", bx0, by0, bw0, r)
  Theme.col(dark, 1)
  G.rectangle("line", bx0, by0, bw0, ch - ch * 0.1, r, r)
  -- grip band across the top
  local gh = ch * 0.15
  Theme.col(band, 1)
  G.rectangle("fill", cx, cy, cw, gh, ch * 0.03, ch * 0.03)
  Theme.col(dark, 1)
  G.rectangle("line", cx, cy, cw, gh, ch * 0.03, ch * 0.03)
  -- arched ridge under the band
  local ridge = {}
  for i = 0, 16 do
    local t = i / 16
    ridge[#ridge + 1] = cx + cw * (0.1 + 0.8 * t)
    ridge[#ridge + 1] = cy + ch * (0.235 - 0.07 * math.sin(t * math.pi))
  end
  Theme.col(light, 0.55)
  G.line(ridge)
  -- the label, set into the front
  local lx, ly, lwid, lh = cx + cw * 0.12, cy + ch * 0.27, cw * 0.76, ch * 0.58
  Theme.col(dark, 1)
  G.rectangle("fill", lx - 1.5 * s, ly - 1.5 * s, lwid + 3 * s, lh + 3 * s, 4 * s, 4 * s)
  Theme.gradRounded(lx, ly, lwid, lh, 3 * s, pal.bgTop, pal.bgBot, 1, 1)
  Theme.col(pal.cardBody, 1)
  G.rectangle("fill", lx + lwid * 0.08, ly + lh * 0.14, lwid * 0.84, lh * 0.5, 3 * s, 3 * s)
  Theme.col(pal.text, 1)
  G.rectangle("fill", lx + lwid * 0.14, ly + lh * 0.24, lwid * 0.5, math.max(1, lh * 0.07))
  G.rectangle("fill", lx + lwid * 0.14, ly + lh * 0.40, lwid * 0.32, math.max(1, lh * 0.07))
  Theme.col(pal.blue, 1)
  G.rectangle("fill", lx + lwid * 0.08, ly + lh * 0.74, lwid * 0.84, lh * 0.12, 2 * s, 2 * s)
  -- the little arrow at the bottom
  local ax, ay, aw = cx + cw / 2, cy + ch * 0.895, cw * 0.05
  Theme.col(dark, 1)
  G.polygon("fill", ax - aw, ay, ax + aw, ay, ax, ay + aw * 0.7)
  -- chosen: a green ring
  if on then
    Theme.stroke(cx - 4 * s, cy - 4 * s, cw + 8 * s, ch + 8 * s, 6 * s, PAL.green, 1, 2 * s)
  end
  -- the game's Pokemon, coming in from the bottom-left corner
  if img then
    local size = ch * 0.78
    local k = size / 64
    G.setColor(1, 1, 1, 1)
    G.draw(img, cx - cw * 0.08, cy + ch - size + ch * 0.1, 0, k, k)
  end
  if G.setLineWidth then G.setLineWidth(1) end
  G.setColor(1, 1, 1, 1)
  Kit.text("micro", label, x + (w - Kit.textWidth("micro", label)) / 2, y + h - 18 * s,
    on and PAL.heading or PAL.muted)
  return Kit.press(x, y, w, h)
end

-- The hue bar: drag along it for any colour.
local function hueBar(S, x, y, w, h, hue, on)
  local s = Kit.scale
  local G = love.graphics
  local steps = 72
  for i = 0, steps - 1 do
    local c = Theme.hslToRgb(i * 360 / steps, 0.75, 0.55)
    Theme.col(c, 1)
    G.rectangle("fill", x + w * i / steps, y, w / steps + 1, h)
  end
  Theme.stroke(x, y, w, h, 4 * s, PAL.cardBorder, 0.6, 1 * s)
  if on then
    local mx = x + w * (hue % 360) / 360
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", mx - 2 * s, y - 4 * s, 4 * s, h + 8 * s, 2 * s, 2 * s)
  end
  local changed
  if Kit.mouseClicked and Kit.hit(x, y - 4 * s, w, h + 8 * s) then S._settingsDragHue = true end
  if S._settingsDragHue then
    if Kit.mouseDown then
      local nh = math.floor(Theme.clamp((Kit.mouseX - x) / w, 0, 0.9999) * 360)
      if nh ~= hue or not on then changed = nh end
    else
      S._settingsDragHue = nil
    end
  end
  return changed
end

function M.draw(S, App, W, H)
  if not M.isOpen(S) then return end
  local s = Kit.scale
  local G = love.graphics
  local bw = math.min(W - 40 * s, 940 * s)
  local bh = 540 * s
  local bx, by = (W - bw) / 2, math.max(40 * s, (H - bh) / 3)
  Theme.col(PAL.bgBot, 0.7)
  G.rectangle("fill", 0, 0, W, H)
  Theme.col(PAL.bgMid, 1)
  G.rectangle("fill", bx, by, bw, bh, 16 * s, 16 * s)
  Kit.card(bx, by, bw, bh)
  Kit.text("button", "Editor settings", bx + 20 * s, by + 18 * s, PAL.heading)
  Kit.text("small", "Saved on this computer only. Your mods don't change.", bx + 20 * s, by + 46 * s, PAL.muted)

  local cur = Theme.current or { id = "stock" }
  local y = by + 82 * s
  Kit.caption(bx + 20 * s, y, "THEME")
  y = y + 26 * s
  local n = #Theme.PRESETS
  local gap = 10 * s
  local sw = (bw - 40 * s - gap * (n - 1)) / n
  for i, p in ipairs(Theme.PRESETS) do
    local x = bx + 20 * s + (i - 1) * (sw + gap)
    if swatch(x, y, sw, 116 * s, Theme.palette(p.id), p.label, cur.id == p.id, mascot(S, p.mascot)) then
      choose(p.id, p.hue)
    end
  end
  y = y + 132 * s
  Kit.caption(bx + 20 * s, y, "ANY COLOUR")
  local custom = cur.id == "custom"
  local hue = tonumber(cur.hue) or tonumber(Settings.get("themeHue")) or 294
  Kit.text("small", custom and ("Custom (hue " .. hue .. ")") or "Drag along the bar", bx + 140 * s, y - 2 * s,
    custom and PAL.text or PAL.muted)
  y = y + 26 * s
  local newHue = hueBar(S, bx + 20 * s, y, bw - 40 * s, 22 * s, hue, custom)
  if newHue then choose("custom", newHue) end
  y = y + 40 * s
  Kit.text("micro", "Green, yellow and red keep their meaning (save, attention, delete), and the game colours on the top stripe stay.",
    bx + 20 * s, y, PAL.faint)

  -- Updates -----------------------------------------------------------------
  y = y + 34 * s
  Kit.caption(bx + 20 * s, y, "UPDATES")
  y = y + 24 * s
  local U = require("Updater")
  local envOff = os.getenv("POKEPORT_NO_UPDATE_CHECK") == "1"
  local on = Settings.get("autoUpdate") ~= false
  local value, changed = Kit.checkbox(bx + 16 * s, y, bw - 40 * s, 28 * s, on,
    "Update the editor automatically from GitHub")
  if changed then
    Settings.set("autoUpdate", value and true or false)
    if value and U.state.step == "idle" then pcall(U.check, true) end
  end
  y = y + 32 * s
  local note
  if envOff then
    note = "Off for this session (POKEPORT_NO_UPDATE_CHECK=1)."
  elseif on then
    note = "Checks on start and every 15 minutes, and installs when you close the editor. Changes made to the editor's own files are replaced."
  else
    note = "Off: the editor stays exactly as it is, so local changes to its files are safe. Updates > Check now still updates by hand."
    if U.state.step == "staged" then note = note .. " A downloaded update is waiting and won't install on its own." end
  end
  local f = Kit.fonts and (Kit.fonts.micro or Kit.fonts.small)
  Theme.col((on and not envOff) and PAL.faint or PAL.yellow, 1)
  if f then G.setFont(f) end
  G.printf(note, bx + 20 * s, y, bw - 40 * s, "left")
  G.setColor(1, 1, 1, 1)

  local yb = by + bh - 46 * s
  if Kit.button(bx + 20 * s, yb, 150 * s, 30 * s, "Reset theme", { kind = "ghost", font = "micro",
      tooltip = "Back to Alpha Sapphire, the editor's original look" }) then
    choose("stock")
  end
  if Kit.button(bx + bw - 140 * s, yb, 120 * s, 30 * s, "Close", { kind = "ghost", font = "micro" }) then
    M.close(S)
  end
end

return M
