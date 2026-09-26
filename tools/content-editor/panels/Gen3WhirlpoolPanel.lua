-- Whirlpool crossing settings (Gen3Whirlpool), shown in the map editor's
-- Collision tool while the Whirlpool brush is picked.
local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local RegList = require("RegList")
local W = require("Gen3Whirlpool")

local M = {}

-- Message boxes break lines at "\n"; typed as \n in the one-line fields.
local function shown(text) return (tostring(text or ""):gsub("\n", "\\n")) end
local function typed(text) return (tostring(text or ""):gsub("\\n", "\n")) end

--- The crossing settings (shared by every whirlpool in the project).
function M.settings(S, App, x, y, w)
  local s = Kit.scale
  local cfg = W.settings(S.project)
  local function set(key, value)
    if W.set(S.project, key, value) then App.markDirty() end
  end
  Kit.text("micro", Kit.ellipsize("micro", "WHIRLPOOL CROSSING (every whirlpool in this project)", w), x, y, PAL.caption)
  y = y + 16 * s
  Kit.text("small", Kit.ellipsize("small", "Surf up to it, press A: a Pokémon with the move carries you across.", w),
    x, y, PAL.muted)
  y = y + 24 * s

  Kit.text("small", "Move", x, y + 5 * s, PAL.text)
  local move = RegList.num(App, "g3whirl_move", x + 110 * s, y, 70 * s, 24 * s, cfg.move)
  if move ~= cfg.move then set("move", math.max(1, math.min(1023, math.floor(tonumber(move) or W.MOVE)))) end
  local names = S.data and S.data.moveNames
  local name = type(names) == "table" and names[cfg.move]
  Kit.text("small", name and tostring(name) or (cfg.move == W.MOVE and "WHIRLPOOL" or ("move " .. cfg.move)),
    x + 190 * s, y + 5 * s, PAL.detail)
  y = y + 32 * s

  Kit.text("small", "Badge needed", x, y + 5 * s, PAL.text)
  local bx = x + 110 * s
  for _, b in ipairs(W.BADGES) do
    local bw = (b.flag and 74 or 56) * s
    if bx + bw > x + w then bx = x + 110 * s; y = y + 28 * s end
    if Kit.chip(bx, y, bw, 24 * s, b.label, cfg.flag == b.flag, PAL.blue) then set("flag", b.flag) end
    bx = bx + bw + 4 * s
  end
  y = y + 34 * s

  for _, row in ipairs({ { "ask", "Asks" }, { "cant", "Can't cross" }, { "used", "Used" } }) do
    Kit.text("small", row[2], x, y + 5 * s, PAL.text)
    local value = Kit.textfield("g3whirl_" .. row[1], x + 110 * s, y, math.max(120 * s, w - 110 * s), 24 * s,
      shown(cfg[row[1]]), W.DEFAULTS[row[1]])
    if typed(value) ~= cfg[row[1]] then set(row[1], typed(value)) end
    y = y + 30 * s
  end
  Kit.text("micro", "\\n starts a new line; {MON} is the Pokémon's name.", x + 110 * s, y, PAL.faint)
  y = y + 22 * s
  Kit.text("small", "Sound", x, y + 5 * s, PAL.text)
  local se = Kit.textfield("g3whirl_sound", x + 110 * s, y, math.min(220 * s, w - 110 * s), 24 * s,
    tostring(cfg.sound or ""), "silent")
  if se ~= (cfg.sound or "") then set("sound", se) end
  y = y + 28 * s
  Kit.text("micro", "Played while crossing; empty = silent.", x + 110 * s, y, PAL.faint)
  return y + 20 * s
end

return M
