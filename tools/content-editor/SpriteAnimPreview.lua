-- Overworld sprite walk / still-sheet preview (GFX, Player, Trainers, Maps).
-- Frame layout matches SpriteRenderer / data/sprites/facings.asm.

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local Generation = require("Generation")
local PAL = Theme.PAL

local SpriteAnimPreview = {}

SpriteAnimPreview.FRAME_LABELS = {
  "Stand v", "Stand ^", "Stand <", "Walk v", "Walk ^", "Walk <",
}

local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK = { down = 3, up = 4, left = 5, right = 5 }
local FACINGS = { "down", "up", "left", "right" }
local FACING_LABEL = { down = "v", up = "^", left = "<", right = ">" }

function SpriteAnimPreview.palette(S, rec)
  if not rec or rec.trueColor then return nil end
  if Generation.isGen2(S) then
    return Preview.gen2ObjectPalette(S, rec.palette or rec.paletteId)
  end
  local src = rec.paletteSource or rec.palette
  if type(src) == "string" and src ~= "" and Preview.paletteColors(S, src) then
    return src
  end
  return "MEWMON"
end

function SpriteAnimPreview.image(S, rec)
  if not rec or not rec.image then return nil end
  local pal = SpriteAnimPreview.palette(S, rec)
  if pal then
    return Preview.imageWithPalette(S, rec.image, pal), pal
  end
  return Preview.image(S, rec.image), nil
end

function SpriteAnimPreview.pose(rec, facing, walkPhase, stepFlip)
  local frames = math.max(1, tonumber(rec and rec.frames) or 1)
  if frames <= 1 then return 0, false end
  facing = facing or "down"
  local walking = rec and rec.walker and walkPhase == 1
  local idx = walking and (WALK[facing] or 3) or (STAND[facing] or 0)
  if idx >= frames then idx = math.min(idx, frames - 1) end
  local flip = false
  if facing == "right" then
    flip = true
  elseif walking and (facing == "down" or facing == "up") and stepFlip then
    flip = true
  end
  return idx, flip
end

function SpriteAnimPreview.blit(img, frames, frameIndex, x, y, cell, flip)
  if not img then return end
  frames = math.max(1, frames or 1)
  local iw, ih = img:getWidth(), img:getHeight()
  local frameH = math.max(1, math.floor(ih / frames))
  local fi = math.max(0, math.min(frames - 1, frameIndex or 0))
  local sx = cell / iw
  local sy = cell / frameH
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, cell, cell, 4, 4)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.pushClip(x, y, cell, cell)
  if flip then
    love.graphics.draw(img, x + cell, y - fi * frameH * sy, 0, -sx, sy)
  else
    love.graphics.draw(img, x, y - fi * frameH * sy, 0, sx, sy)
  end
  Kit.popClip()
  love.graphics.setColor(1, 1, 1, 1)
end

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function beatOf(t)
  return math.floor(t / 0.14)
end

function SpriteAnimPreview.clock(rec, t, playing)
  t = t or now()
  local frames = math.max(1, tonumber(rec and rec.frames) or 1)
  local walkPhase, stepFlip, stillFrame = 0, false, 0
  if playing then
    if rec and rec.walker and frames > 3 then
      local beat = beatOf(t)
      walkPhase = beat % 2
      stepFlip = math.floor(beat / 2) % 2 == 1
    elseif frames > 1 then
      stillFrame = math.floor(t / 0.22) % frames
    end
  end
  return walkPhase, stepFlip, stillFrame, frames
end

function SpriteAnimPreview.drawStand(S, rec, x, y, cell)
  local img = SpriteAnimPreview.image(S, rec)
  local frames = math.max(1, tonumber(rec and rec.frames) or 1)
  SpriteAnimPreview.blit(img, frames, 0, x, y, cell, false)
end

-- Always-playing cell (Maps object thumb). Returns nothing.
function SpriteAnimPreview.drawCompact(S, rec, x, y, cell)
  if not rec then return end
  local img = SpriteAnimPreview.image(S, rec)
  local walkPhase, stepFlip, stillFrame, frames =
    SpriteAnimPreview.clock(rec, now(), true)
  local fi, flip
  if rec.walker and frames > 3 then
    fi, flip = SpriteAnimPreview.pose(rec, "down", walkPhase, stepFlip)
  else
    fi, flip = stillFrame, false
  end
  SpriteAnimPreview.blit(img, frames, fi, x, y, cell, flip)
end

function SpriteAnimPreview.drawStrip(S, rec, x, y, cell, s)
  s = s or Kit.scale
  if not rec or not rec.image then return y end
  local img = SpriteAnimPreview.image(S, rec)
  local frames = math.max(1, tonumber(rec.frames) or 1)
  Kit.text("micro", "Sheet frames (right faces = flip of left)", x, y, PAL.caption)
  y = y + 16 * s
  if not img then
    Kit.text("micro", "no image", x, y, PAL.faint)
    return y + 18 * s
  end
  local show = math.min(frames, 6)
  for i = 0, show - 1 do
    local cx = x + i * (cell + 4 * s)
    SpriteAnimPreview.blit(img, frames, i, cx, y, cell, false)
    Kit.text("micro", SpriteAnimPreview.FRAME_LABELS[i + 1] or tostring(i),
      cx, y + cell + 2 * s, PAL.faint)
  end
  return y + cell + 18 * s
end

-- Live walk-cycle preview. opts.prefix namespaces PLAY/facing state.
function SpriteAnimPreview.draw(S, rec, x, y, w, opts)
  opts = opts or {}
  local s = opts.s or Kit.scale
  if not rec then return y end
  local prefix = opts.prefix or "owAnim"
  local playKey = prefix .. "Playing"
  local faceKey = prefix .. "Facing"
  local autoKey = prefix .. "AutoFace"
  local holdWalk = prefix .. "WalkHold"
  local holdFlip = prefix .. "FlipHold"
  local holdStill = prefix .. "StillHold"

  local box = opts.box or (72 * s)
  local fh = 28 * s
  Kit.text("small", opts.title or "Animation preview", x, y, PAL.caption)
  y = y + 18 * s

  if S[playKey] == nil then S[playKey] = true end
  if not S[faceKey] then S[faceKey] = "down" end

  local playing = S[playKey]
  if Kit.chip(x, y, 72 * s, fh, playing and "PLAY" or "PAUSE",
      playing, PAL.green, PAL.steel,
      playing and "Pause the overworld walk cycle"
        or "Play the overworld walk cycle") then
    S[playKey] = not playing
    playing = S[playKey]
  end
  local auto = S[autoKey] and true or false
  if Kit.chip(x + 80 * s, y, 88 * s, fh, auto and "AUTO" or "FACE",
      auto, PAL.blue, nil, "Auto-cycle facing while playing") then
    S[autoKey] = not auto
    auto = S[autoKey]
  end
  local fx = x + 180 * s
  for _, face in ipairs(FACINGS) do
    local on = S[faceKey] == face
    local bw = 36 * s
    if Kit.chip(fx, y, bw, fh, FACING_LABEL[face] or face, on, PAL.yellow,
        PAL.steel, "Preview facing " .. face) then
      S[faceKey] = face
      S[autoKey] = false
    end
    fx = fx + bw + 4 * s
  end
  y = y + fh + 8 * s

  local t = now()
  local facing = S[faceKey] or "down"
  if playing and auto then
    facing = FACINGS[(math.floor(t / 1.2) % #FACINGS) + 1]
    S[faceKey] = facing
  end

  local walkPhase, stepFlip, stillFrame, frames =
    SpriteAnimPreview.clock(rec, t, playing)
  if not playing then
    walkPhase = S[holdWalk] or 0
    stepFlip = S[holdFlip] or false
    stillFrame = S[holdStill] or 0
  else
    S[holdWalk] = walkPhase
    S[holdFlip] = stepFlip
    S[holdStill] = stillFrame
  end

  local img = SpriteAnimPreview.image(S, rec)
  local fi, flip
  if rec.walker and frames > 3 then
    fi, flip = SpriteAnimPreview.pose(rec, facing, walkPhase, stepFlip)
  else
    fi, flip = stillFrame, false
    if facing == "right" and frames > 1 then
      fi, flip = SpriteAnimPreview.pose(rec, facing, 0, false)
    elseif not rec.walker and frames > 1 then
      -- still sheets: keep cycling frames, ignore facing chips except right flip
      if facing == "right" then flip = true end
    end
  end

  Theme.col(PAL.cardBody or PAL.card, 1)
  love.graphics.rectangle("fill", x, y, box + 16 * s, box + 28 * s, 8 * s, 8 * s)
  SpriteAnimPreview.blit(img, frames, fi, x + 8 * s, y + 8 * s, box, flip)

  local pose = (walkPhase == 1 and rec.walker) and "walk" or "stand"
  if not rec.walker and frames > 1 then pose = "frames" end
  local info = string.format("%s · %s · f%d%s",
    FACING_LABEL[facing] or facing, pose, fi, flip and " · flip" or "")
  Kit.text("micro", info, x + 8 * s, y + box + 12 * s, PAL.muted)

  local mini = 28 * s
  local mx = x + box + 28 * s
  local my = y + 8 * s
  Kit.text("micro", "All facings", mx, my - 2 * s, PAL.faint)
  my = my + 14 * s
  for i, face in ipairs(FACINGS) do
    local mfi, mflip
    if rec.walker and frames > 3 then
      mfi, mflip = SpriteAnimPreview.pose(rec, face, walkPhase, stepFlip)
    else
      mfi, mflip = SpriteAnimPreview.pose(rec, face, 0, false)
    end
    SpriteAnimPreview.blit(img, frames, mfi,
      mx + (i - 1) * (mini + 6 * s), my, mini, mflip)
    Kit.text("micro", FACING_LABEL[face],
      mx + (i - 1) * (mini + 6 * s) + 6 * s, my + mini + 2 * s, PAL.faint)
  end

  return y + box + 36 * s
end

return SpriteAnimPreview
