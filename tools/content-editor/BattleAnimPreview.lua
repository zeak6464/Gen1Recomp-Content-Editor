-- In-editor battle move animation preview.
-- Gen1: AnimPlayer + moveAnims.seq.  Gen2: AnimRunner + BattleAnimView.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Preview = require("Preview")
local Generation = require("Generation")
local PAL = Theme.PAL

local BattleAnimPreview = {}

local GB_W, GB_H = 160, 144

local function stripEditor(rec)
  if type(rec) ~= "table" then return rec end
  local out = {}
  for k, v in pairs(rec) do
    if type(k) == "string" and k:sub(1, 1) ~= "_" then
      out[k] = v
    end
  end
  return out
end

local function copyMap(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function cloneValue(v)
  if type(v) ~= "table" then return v end
  local out = {}
  local n = #v
  if n > 0 then
    for i = 1, n do out[i] = cloneValue(v[i]) end
  end
  for k, child in pairs(v) do
    if type(k) ~= "number" or k < 1 or k > n or out[k] == nil then
      out[k] = cloneValue(child)
    end
  end
  return out
end

local function mergeBucket(base, overlay)
  local out = cloneValue(base) or {}
  if type(overlay) ~= "table" then return out end
  for k, v in pairs(overlay) do
    if type(k) == "string" and k:sub(1, 1) == "_" then
      -- skip editor marks
    else
      out[k] = cloneValue(v)
    end
  end
  return out
end

local function isGen2(S)
  if Generation.isGen2(S) then return true end
  local root = S and S.data and (S.data.gen2BattleAnims or S.data.battle_anims)
  return type(root) == "table" and type(root.moves) == "table"
end

local function baRoot(S)
  return S and S.data and (S.data.gen2BattleAnims or S.data.battle_anims) or nil
end

-- Merge vanilla battle_anims with project.battle_anims overrides (Gen1 flat ids).
function BattleAnimPreview.buildData(S)
  local root = S and S.data and S.data.battle_anims
  if type(root) ~= "table" then return nil end
  if type(root.moves) == "table" then
    return BattleAnimPreview.buildDataGen2(S)
  end
  local data = {
    moveAnims = copyMap(root.moveAnims),
    subanims = copyMap(root.subanims),
    tilesheets = copyMap(root.tilesheets),
    frameBlocks = root.frameBlocks or {},
    baseCoords = root.baseCoords or {},
  }
  State.ensureProjectFields(S.project)
  for id, rec in pairs(S.project.battle_anims or {}) do
    if type(rec) == "table" then
      local clean = stripEditor(rec)
      local kind, index = tostring(id):match("^(%a+):(%d+)$")
      if kind == "subanim" then
        data.subanims[tonumber(index)] = clean
      elseif kind == "tilesheet" then
        data.tilesheets[tonumber(index)] = clean
      elseif type(id) == "string"
          and id ~= "moves" and id ~= "scripts" and id ~= "gfx"
          and id ~= "objects" and id ~= "ids" and id ~= "framesets"
          and id ~= "oamsets" then
        data.moveAnims[id] = clean
      end
    end
  end
  return data
end

-- Gold: nested moves / scripts / gfx / objects / …
function BattleAnimPreview.buildDataGen2(S)
  local root = baRoot(S)
  if type(root) ~= "table" then return nil end
  State.ensureProjectFields(S.project)
  local proj = S.project.battle_anims or {}
  local data = {
    moves = mergeBucket(root.moves, proj.moves),
    scripts = mergeBucket(root.scripts, proj.scripts),
    ids = mergeBucket(root.ids, proj.ids),
    objects = mergeBucket(root.objects, proj.objects),
    framesets = mergeBucket(root.framesets, proj.framesets),
    oamsets = mergeBucket(root.oamsets, proj.oamsets),
    gfx = mergeBucket(root.gfx, proj.gfx),
    scriptOrder = root.scriptOrder,
    generation = 2,
  }
  return data
end

local function resolveGen2ScriptKey(data, id)
  if not (data and id) then return nil end
  if type(data.scripts) == "table" and data.scripts[id] then
    return id
  end
  local ptr = data.moves and data.moves[id]
  if type(ptr) == "string" and ptr ~= ""
      and type(data.scripts) == "table" and data.scripts[ptr] then
    return ptr
  end
  return nil
end

function BattleAnimPreview.hasAnim(S, moveId)
  if not moveId then return false end
  if isGen2(S) then
    local data = BattleAnimPreview.buildDataGen2(S)
    return resolveGen2ScriptKey(data, moveId) ~= nil
  end
  local data = BattleAnimPreview.buildData(S)
  local anim = data and data.moveAnims and data.moveAnims[moveId]
  return type(anim) == "table" and type(anim.seq) == "table"
end

function BattleAnimPreview.stop(S)
  if not S then return end
  local p = S.battleAnimPreview
  if p and p.player and p.player.release then
    pcall(p.player.release, p.player)
  end
  S.battleAnimPreview = nil
end

function BattleAnimPreview.isPlaying(S)
  local p = S and S.battleAnimPreview
  if not (p and p.playing) then return false end
  if p.gen2 then
    return p.runner and not p.runner:done()
  end
  return p.player and not p.player:isDone()
end

local function startGen2(S, moveId, opts)
  opts = opts or {}
  local data = BattleAnimPreview.buildDataGen2(S)
  local scriptKey = resolveGen2ScriptKey(data, moveId)
  if not scriptKey then
    S.status = "No battle anim script for " .. tostring(moveId)
    return false
  end
  local okR, AnimRunner = pcall(require, "src.battle.gen2.AnimRunner")
  if not okR then
    S.status = "AnimRunner unavailable"
    return false
  end
  local okV, BattleAnimView = pcall(require, "src.ui.gen2.BattleAnimView")
  if not okV then
    S.status = "BattleAnimView unavailable"
    return false
  end
  BattleAnimPreview.stop(S)
  local attackerIsPlayer = not S.battleAnimPreviewEnemy
  if opts.enemy == true then attackerIsPlayer = false end
  if opts.enemy == false then attackerIsPlayer = true end
  local constants = S.data and (S.data.constants or S.data.gen2Constants) or {}
  local palettes = S.data and (S.data.palettes or S.data.gen2Palettes) or nil
  local runner = AnimRunner.new({
    data = data,
    constants = constants,
    battleTurn = attackerIsPlayer and 0 or 1,
    animId = moveId,
    hooks = {},
  })
  runner:start(scriptKey)
  local rows = data.scripts and data.scripts[scriptKey]
  if type(rows) ~= "table" or #rows == 0 then
    S.status = "Empty anim script " .. tostring(scriptKey)
    return false
  end
  local view = BattleAnimView.new(data, palettes)
  S.battleAnimPreview = {
    gen2 = true,
    runner = runner,
    view = view,
    moveId = moveId,
    scriptKey = scriptKey,
    data = data,
    accum = 0,
    playing = true,
    loop = S.battleAnimPreviewLoop ~= false,
    attackerIsPlayer = attackerIsPlayer,
    flash = 0,
  }
  S.status = "Previewing " .. tostring(moveId)
    .. " → " .. tostring(scriptKey)
  return true
end

function BattleAnimPreview.start(S, moveId, opts)
  opts = opts or {}
  if not (S and moveId) then return false end
  if isGen2(S) then
    return startGen2(S, moveId, opts)
  end
  local data = BattleAnimPreview.buildData(S)
  if not data or not data.moveAnims[moveId] then
    S.status = "No battle anim for " .. tostring(moveId)
    return false
  end
  local okAp, AnimPlayer = pcall(require, "src.battle.AnimPlayer")
  if not okAp then
    S.status = "AnimPlayer unavailable"
    return false
  end
  BattleAnimPreview.stop(S)
  local player = AnimPlayer.new(data)
  local attackerIsPlayer = not S.battleAnimPreviewEnemy
  if opts.enemy == true then attackerIsPlayer = false end
  if opts.enemy == false then attackerIsPlayer = true end
  pcall(player.start, player, moveId, attackerIsPlayer, opts)
  if not player.steps or #player.steps == 0 then
    S.status = "Empty anim sequence for " .. tostring(moveId)
    pcall(player.release, player)
    return false
  end
  S.battleAnimPreview = {
    player = player,
    moveId = moveId,
    data = data,
    accum = 0,
    playing = true,
    loop = S.battleAnimPreviewLoop ~= false,
    attackerIsPlayer = attackerIsPlayer,
    flash = 0,
  }
  S.status = "Previewing " .. tostring(moveId)
  return true
end

function BattleAnimPreview.update(S, dt)
  local p = S and S.battleAnimPreview
  if not p or not p.playing then return end
  if p.gen2 then
    if not p.runner then return end
    p.accum = (p.accum or 0) + (dt or 0)
    local frames = math.floor(p.accum * 60)
    if frames < 1 then return end
    p.accum = p.accum - frames / 60
    if frames > 5 then frames = 5 end
    for _ = 1, frames do
      if (p.flash or 0) > 0 then p.flash = p.flash - 1 end
      pcall(p.runner.step, p.runner)
      if p.runner:done() then
        local loop = S.battleAnimPreviewLoop ~= false
        if loop then
          pcall(p.runner.start, p.runner, p.scriptKey)
        else
          p.playing = false
          break
        end
      end
    end
    return
  end
  if not p.player then return end
  p.accum = (p.accum or 0) + (dt or 0)
  local frames = math.floor(p.accum * 60)
  if frames < 1 then return end
  p.accum = p.accum - frames / 60
  if frames > 5 then frames = 5 end
  for _ = 1, frames do
    if (p.flash or 0) > 0 then p.flash = p.flash - 1 end
    pcall(p.player.update, p.player)
    local ok, fired = pcall(p.player.pollEffects, p.player)
    if ok and type(fired) == "table" then
      for _, ev in ipairs(fired) do
        local eff = tostring(ev.effect or "")
        if eff:find("FLASH", 1, true) or eff == "SE_DARK_SCREEN_FLASH" then
          p.flash = 4
        end
      end
    end
    if p.player:isDone() then
      local loop = S.battleAnimPreviewLoop ~= false
      if loop then
        pcall(p.player.start, p.player, p.moveId, p.attackerIsPlayer)
        if not p.player.steps or #p.player.steps == 0 then
          p.playing = false
          break
        end
      else
        p.playing = false
        break
      end
    end
  end
end

local function drawStage()
  love.graphics.setColor(0.18, 0.28, 0.22, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  love.graphics.setColor(0.22, 0.38, 0.28, 1)
  love.graphics.rectangle("fill", 0, 88, GB_W, 56)
  love.graphics.setColor(0.75, 0.35, 0.32, 1)
  love.graphics.rectangle("fill", 96, 8, 56, 56)
  love.graphics.setColor(0.32, 0.42, 0.78, 1)
  love.graphics.rectangle("fill", 8, 64, 56, 56)
end

-- Draw controls + scaled GB viewport. Returns y below the widget.
function BattleAnimPreview.draw(S, moveId, x, y, w, s)
  s = s or Kit.scale
  local fh = 28 * s
  Kit.text("small", "Animation preview", x, y, PAL.caption)
  y = y + 18 * s

  local p = S.battleAnimPreview
  if p and p.moveId ~= moveId then
    BattleAnimPreview.stop(S)
    p = nil
  end
  local active = p and p.moveId == moveId
  local playing = active and p.playing
  local gen2 = isGen2(S)

  if Kit.chip(x, y, 72 * s, fh, playing and "STOP" or "PLAY",
      playing, PAL.green) then
    if playing then
      BattleAnimPreview.stop(S)
      S.status = "Anim preview stopped"
    else
      BattleAnimPreview.start(S, moveId)
    end
    p = S.battleAnimPreview
    active = p and p.moveId == moveId
    playing = active and p.playing
  end

  local loop = S.battleAnimPreviewLoop ~= false
  if Kit.chip(x + 80 * s, y, 72 * s, fh, loop and "LOOP" or "ONCE",
      loop, PAL.blue) then
    S.battleAnimPreviewLoop = not loop
    if active and p then p.loop = S.battleAnimPreviewLoop ~= false end
  end

  local enemy = S.battleAnimPreviewEnemy and true or false
  if Kit.chip(x + 160 * s, y, 100 * s, fh, enemy and "ENEMY" or "PLAYER",
      enemy, PAL.yellow, nil,
      gen2 and "hBattleTurn — player=0 / enemy=1"
        or "Attacker side (transforms subanims)") then
    S.battleAnimPreviewEnemy = not enemy
    if active and playing then
      BattleAnimPreview.start(S, moveId)
      p = S.battleAnimPreview
      active = p and p.moveId == moveId
    end
  end

  y = y + fh + 8 * s

  local maxScale = math.max(1, math.floor((w - 8 * s) / GB_W))
  local scale = math.min(maxScale, math.max(2, math.floor(2 * s)))
  local vw, vh = GB_W * scale, GB_H * scale

  Theme.col(PAL.cardBody or PAL.card, 1)
  love.graphics.rectangle("fill", x, y, vw + 8 * s, vh + 8 * s, 8 * s, 8 * s)

  local vx, vy = x + 4 * s, y + 4 * s
  Kit.pushClip(vx, vy, vw, vh)
  love.graphics.push()
  love.graphics.translate(vx, vy)
  love.graphics.scale(scale, scale)

  if active and p and p.gen2 and p.runner and p.view then
    local function drawBg()
      drawStage()
    end
    love.graphics.setColor(1, 1, 1, 1)
    pcall(function()
      p.view:present(p.runner, drawBg)
      p.view:drawObjects(p.runner, nil)
    end)
    if (p.flash or 0) > 0 then
      love.graphics.setColor(1, 1, 1, 0.55)
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    end
  else
    drawStage()
    if active and p and p.player then
      love.graphics.setColor(1, 1, 1, 1)
      pcall(p.player.draw, p.player)
      if (p.flash or 0) > 0 then
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
      end
    else
      love.graphics.setColor(1, 1, 1, 0.35)
    end
  end

  love.graphics.pop()
  Kit.popClip()

  local info
  if not BattleAnimPreview.hasAnim(S, moveId) then
    info = gen2
      and "no Gold script for this move / pointer"
      or "no anim data for this move"
  elseif active and p and p.gen2 then
    info = string.format("%s → %s · frame %d%s",
      tostring(moveId), tostring(p.scriptKey or "?"),
      tonumber(p.runner and p.runner.frames) or 0,
      playing and "" or " · done")
  elseif active and p then
    local step = p.player and p.player.stepIndex or 0
    local total = p.player and p.player.steps and #p.player.steps or 0
    info = string.format("%s · step %d/%d%s",
      tostring(moveId), step, total, playing and "" or " · done")
  else
    info = gen2
      and "Press PLAY · Gold AnimRunner + battle_anims.gfx"
      or "Press PLAY · needs ROM battle_anims + tilesheets"
  end
  Kit.text("micro", Kit.ellipsize("micro", info, w), x, y + vh + 12 * s, PAL.muted)

  return y + vh + 28 * s
end

-- Scaled atlas with an 8×8 tile grid. Click a cell to inspect it.
-- rec.path (Gen1) or rec.image (Gold gfx); rec.tiles / rec.wide optional.
function BattleAnimPreview.drawSheet(S, rec, x, y, w, s)
  s = s or Kit.scale or 1
  rec = rec or {}
  local path = rec.path or rec.image
  Kit.text("small", "Tilesheet preview", x, y, PAL.caption)
  y = y + 18 * s
  if type(path) ~= "string" or path == "" then
    Kit.text("micro", "No image path on this sheet.", x, y, PAL.faint)
    return y + 18 * s
  end

  local img = Preview.image(S, path)
  if S._battleAnimSheetPath ~= path then
    S._battleAnimSheetPath = path
    S.battleAnimTileIdx = 0
  end
  if not img then
    Kit.text("micro", "Could not load " .. tostring(path), x, y, PAL.faint)
    return y + 18 * s
  end

  local iw, ih = img:getWidth(), img:getHeight()
  if iw < 1 or ih < 1 then
    Kit.text("micro", "Empty image.", x, y, PAL.faint)
    return y + 18 * s
  end

  local TILE = 8
  local cols = tonumber(rec.wide)
  if not cols or cols < 1 then
    cols = math.max(1, math.floor(iw / TILE))
  end
  local tileW = math.max(1, math.floor(iw / cols))
  local tileH = tileW
  local nTiles = tonumber(rec.tiles) or 0
  if nTiles < 1 then
    nTiles = cols * math.max(1, math.floor(ih / tileH))
  end
  local rows = math.max(1, math.ceil(nTiles / cols))

  local scale = math.max(2, math.min(6, math.floor(w / iw)))
  local dw, dh = iw * scale, ih * scale
  local cell = tileW * scale

  Kit.text("micro",
    string.format("%dx%d px  ·  %d tiles  ·  %d per row  ·  click a cell",
      iw, ih, nTiles, cols),
    x, y, PAL.muted)
  y = y + 16 * s

  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  local G = love and love.graphics
  if G and G.rectangle then
    G.rectangle("fill", x, y, dw + 4 * s, dh + 4 * s, 6 * s, 6 * s)
  end
  local dx, dy = x + 2 * s, y + 2 * s
  if G then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, dx, dy, 0, scale, scale)
  end

  local mark = S.battleAnimTileIdx
  if type(mark) ~= "number" or mark < 0 or mark >= nTiles then
    mark = 0
    S.battleAnimTileIdx = 0
  end

  if Kit.press(dx, dy, dw, dh) then
    local col = math.floor((Kit.mouseX - dx) / cell)
    local row = math.floor((Kit.mouseY - dy) / cell)
    if col >= 0 and col < cols and row >= 0 and row < rows then
      local idx = row * cols + col
      if idx < nTiles then S.battleAnimTileIdx = idx end
    end
  end

  if G and G.rectangle then
    if G.setLineWidth then G.setLineWidth(1) end
    for i = 0, nTiles - 1 do
      local col = i % cols
      local row = math.floor(i / cols)
      local cx = dx + col * cell
      local cy = dy + row * cell
      if i == mark then
        Theme.stroke(cx, cy, cell, cell, 0, PAL.green, 0.95, 2 * s)
      elseif scale >= 3 then
        Theme.col(PAL.caption, 0.22)
        G.rectangle("line", cx, cy, cell, cell)
      end
    end
    -- Grey out slots past the live tile count (tileset 2 uses 64 of 80).
    local slots = cols * math.ceil(ih / tileH)
    for i = nTiles, slots - 1 do
      local col = i % cols
      local row = math.floor(i / cols)
      Theme.col({ 7, 11, 29 }, 0.55)
      G.rectangle("fill", dx + col * cell, dy + row * cell, cell, cell)
    end
  end

  local hoverCol = math.floor((Kit.mouseX - dx) / cell)
  local hoverRow = math.floor((Kit.mouseY - dy) / cell)
  if hoverCol >= 0 and hoverCol < cols and hoverRow >= 0 and hoverRow < rows
      and Kit.hit(dx, dy, dw, dh) then
    local hover = hoverRow * cols + hoverCol
    if hover < nTiles then
      Kit.offerTooltip(dx + hoverCol * cell, dy + hoverRow * cell,
        cell, cell, "Tile " .. tostring(hover))
    end
  end

  y = y + dh + 10 * s

  local mag = math.max(32 * s, tileW * 8)
  local col = mark % cols
  local row = math.floor(mark / cols)
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  if G and G.rectangle then
    G.rectangle("fill", x, y, mag, mag, 6 * s, 6 * s)
  end
  if G and G.newQuad then
    local qx, qy = col * tileW, row * tileH
    local ok, quad = pcall(G.newQuad, qx, qy, tileW, tileH, iw, ih)
    if ok and quad then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, quad, x, y, 0, mag / tileW, mag / tileH)
    end
  end
  Kit.text("micro",
    string.format("Tile %d  ·  %d,%d", mark, col * tileW, row * tileH),
    x + mag + 10 * s, y + mag / 2 - 6 * s, PAL.muted)
  y = y + mag + 10 * s
  return y
end

return BattleAnimPreview
