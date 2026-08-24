-- Player tab: overworld wearable sprites (walk/bike/surf/fly) + battle /
-- intro pics.  Gen1 remaps write field.playerSprites / field.playerPics;
-- Gold remaps write data.gen2PlayerSprites + gen2MenuGfx paths.  Sheet
-- edits go through project.sprites (same as GFX).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local SpriteUtil = require("SpriteUtil")
local Generation = require("Generation")
local PAL = Theme.PAL

local Player = {}

local function modesFor(S)
  if Generation.isGen2(S) then
    return {
      { id = "overworld", label = "Overworld",
        tip = "Walk / bike / surf sprite sheets and Chris slot remaps" },
      { id = "pics", label = "Pics",
        tip = "Battle back, Dude back, Oak-speech front (card art: UI → Badges)" },
    }
  end
  return {
    { id = "overworld", label = "Overworld",
      tip = "Walk / bike / surf / fly sprite sheets and slot remaps" },
    { id = "pics", label = "Pics",
      tip = "Battle back pic, trainer card / intro front pic" },
  }
end

local OW_SLOTS_GEN1 = {
  { id = "walk", label = "Walk", tip = "On-foot player (default SPRITE_RED)" },
  { id = "bike", label = "Bike", tip = "Bicycle (default SPRITE_RED_BIKE)" },
  { id = "surf", label = "Surf", tip = "Surfing mount (default SPRITE_SEEL)" },
  { id = "fly", label = "Fly", tip = "Fly bird anim (default SPRITE_BIRD)" },
  { id = "surfPikachu", label = "Surf Pika",
    tip = "Yellow: surf when party Pikachu (SPRITE_SURFING_PIKACHU)" },
}

local OW_SLOTS_GEN2 = {
  { id = "walk", label = "Walk", tip = "On-foot Chris (SPRITE_CHRIS)" },
  { id = "bike", label = "Bike", tip = "Bicycle (SPRITE_CHRIS_BIKE)" },
  { id = "surf", label = "Surf", tip = "Surfing mount (SPRITE_SURF)" },
  { id = "surfPikachu", label = "Surf Pika",
    tip = "Surf when party Pikachu (SPRITE_SURFING_PIKACHU)" },
}

local OW_SLOTS_KRIS = {
  { id = "walkKris", label = "Walk Kris", tip = "On-foot Kris (SPRITE_KRIS)" },
  { id = "bikeKris", label = "Bike Kris", tip = "Bicycle (SPRITE_KRIS_BIKE)" },
}

local PIC_SLOTS_GEN1 = {
  { id = "front", label = "Front",
    tip = "Trainer card / Oak intro / Hall of Fame" },
  { id = "back", label = "Back", tip = "Battle back pic (Go! …)" },
  { id = "demoBack", label = "Demo back", tip = "Old man catch tutorial" },
  { id = "oakBack", label = "Oak back", tip = "Yellow Pallet catch (Oak)" },
}

local PIC_SLOTS_GEN2 = {
  { id = "front", label = "Front",
    tip = "Oak speech / intro player pic (data.playerPic)" },
  { id = "back", label = "Back",
    tip = "Battle back pic (gen2MenuGfx.battleHud.playerBack)" },
  { id = "demoBack", label = "Dude back",
    tip = "Catch tutorial Dude (gen2MenuGfx.battleHud.dudeBack)" },
}

local PIC_SLOTS_KRIS = {
  { id = "frontFemale", label = "Front Kris",
    tip = "Oak speech / intro Kris pic (data.playerPicFemale)" },
  { id = "backFemale", label = "Back Kris",
    tip = "Battle / Hall of Fame Kris back pic (gen2MenuGfx.battleHud.playerBackFemale)" },
}

local function hasKris(S)
  if Generation.isCrystal(S) then return true end
  local sprites = S and S.data and (S.data.sprites or S.data.gen2Sprites)
  return type(sprites) == "table" and sprites.SPRITE_KRIS ~= nil
end

local function owSlots(S)
  if not Generation.isGen2(S) then return OW_SLOTS_GEN1 end
  if not hasKris(S) then return OW_SLOTS_GEN2 end
  local slots = {}
  for i = 1, #OW_SLOTS_GEN2 do slots[i] = OW_SLOTS_GEN2[i] end
  for i = 1, #OW_SLOTS_KRIS do
    slots[#slots + 1] = OW_SLOTS_KRIS[i]
  end
  return slots
end

local function picSlots(S)
  if not Generation.isGen2(S) then return PIC_SLOTS_GEN1 end
  if not hasKris(S) then return PIC_SLOTS_GEN2 end
  return {
    PIC_SLOTS_GEN2[1], PIC_SLOTS_KRIS[1],
    PIC_SLOTS_GEN2[2], PIC_SLOTS_KRIS[2],
    PIC_SLOTS_GEN2[3],
  }
end

local FRAME_LABELS = {
  "Stand v", "Stand ^", "Stand <", "Walk v", "Walk ^", "Walk <",
}

-- Same layout as SpriteRenderer (data/sprites/facings.asm).
local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK = { down = 3, up = 4, left = 5, right = 5 }
local FACINGS = { "down", "up", "left", "right" }
-- ASCII only — editor fonts often lack Unicode arrows (tofu □).
local FACING_LABEL = { down = "v", up = "^", left = "<", right = ">" }

local function defaults()
  local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  if ok and FieldDefaults and FieldDefaults.FIELD then
    return FieldDefaults
  end
  return nil
end

local function defaultPlayerSprites(S)
  if Generation.isGen2(S) then
    local ok, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
    local st = ok and FieldMoves and FieldMoves.STATE_SPRITE or nil
    return {
      walk = (st and st.normal) or "SPRITE_CHRIS",
      bike = (st and st.bike) or "SPRITE_CHRIS_BIKE",
      surf = (st and st.surf) or "SPRITE_SURF",
      surfPikachu = (st and st.surf_pika) or "SPRITE_SURFING_PIKACHU",
      walkKris = "SPRITE_KRIS",
      bikeKris = "SPRITE_KRIS_BIKE",
    }
  end
  local fd = defaults()
  return (fd and fd.FIELD.playerSprites) or {
    walk = "SPRITE_RED", bike = "SPRITE_RED_BIKE", surf = "SPRITE_SEEL",
    fly = "SPRITE_BIRD", surfPikachu = "SPRITE_SURFING_PIKACHU",
  }
end

local function menuGfx(S)
  return S.data and (S.data.gen2MenuGfx or S.data.menu_gfx) or nil
end

local function defaultPlayerPics(S)
  if Generation.isGen2(S) then
    local hud = menuGfx(S) and menuGfx(S).battleHud or {}
    return {
      back = hud.playerBack or "assets/generated/battle/player_back.png",
      backFemale = hud.playerBackFemale
        or "assets/generated/battle/player_back_female.png",
      demoBack = hud.dudeBack or "assets/generated/battle/dude_back.png",
      front = (S.data and S.data.playerPic)
        or "assets/generated/intro/cal.png",
      frontFemale = (S.data and S.data.playerPicFemale)
        or "assets/generated/intro/kris.png",
    }
  end
  local fd = defaults()
  return (fd and fd.FIELD.playerPics) or {
    back = "assets/generated/battle/redb.png",
    demoBack = "assets/generated/battle/oldmanb.png",
    oakBack = "assets/generated/battle/profoakb.png",
    front = "assets/generated/trainer_card/red.png",
  }
end

local function slotSpriteId(S, slot)
  local proj = S.project and S.project.playerSprites
  if proj and type(proj[slot]) == "string" and proj[slot] ~= "" then
    return proj[slot], true
  end
  if Generation.isGen2(S) then
    local ov = S.data and S.data.gen2PlayerSprites
    if ov and type(ov[slot]) == "string" and ov[slot] ~= "" then
      return ov[slot], false
    end
    return defaultPlayerSprites(S)[slot], false
  end
  local fd = defaults()
  if fd and fd.fieldValue then
    local v = fd.fieldValue(S.data, "playerSprites", slot)
    if type(v) == "string" and v ~= "" then return v, false end
  end
  return defaultPlayerSprites(S)[slot], false
end

local function slotPicPath(S, slot)
  local proj = S.project and S.project.playerPics
  if proj and type(proj[slot]) == "string" and proj[slot] ~= "" then
    return proj[slot], true
  end
  if Generation.isGen2(S) then
    return defaultPlayerPics(S)[slot], false
  end
  local fd = defaults()
  if fd and fd.fieldValue then
    local v = fd.fieldValue(S.data, "playerPics", slot)
    if type(v) == "string" and v ~= "" then return v, false end
  end
  return defaultPlayerPics(S)[slot], false
end

local function resolveSprite(S, id)
  if not id then return nil, false end
  if S.project and S.project.sprites and S.project.sprites[id] then
    return S.project.sprites[id], true
  end
  if S.data and S.data.sprites and S.data.sprites[id] then
    return S.data.sprites[id], false
  end
  return nil, false
end

local function ensureSprite(S, id, template, App)
  State.ensureProjectFields(S.project)
  S.project.sprites = S.project.sprites or {}
  if S.project.sprites[id] then return S.project.sprites[id] end
  local copy = {}
  if type(template) == "table" then
    for k, v in pairs(template) do
      if type(v) ~= "function" then copy[k] = v end
    end
    copy._isNew = false
  else
    copy = {
      id = id,
      image = "assets/" .. tostring(id):lower() .. ".png",
      frames = 6, walker = true, _isNew = true,
    }
  end
  copy.id = copy.id or id
  S.project.sprites[id] = copy
  if App then App.markDirty() end
  return copy
end

local function setSlotSprite(S, slot, spriteId, App)
  State.ensureProjectFields(S.project)
  local def = defaultPlayerSprites(S)[slot]
  if spriteId == nil or spriteId == "" or spriteId == def then
    S.project.playerSprites[slot] = nil
  else
    S.project.playerSprites[slot] = spriteId
  end
  if App then App.markDirty() end
end

local function setSlotPic(S, slot, path, App)
  State.ensureProjectFields(S.project)
  local def = defaultPlayerPics(S)[slot]
  if path == nil or path == "" or path == def then
    S.project.playerPics[slot] = nil
  else
    S.project.playerPics[slot] = path
  end
  if App then App.markDirty() end
end

-- Gen1: SGB palette name (MEWMON default). Gold: PAL_OW_* color row
-- (same as Gfx / Maps — paletteSource is Gen1-only).
local function spritePal(S, rec)
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

local function loadSpriteImage(S, rec)
  if not rec or not rec.image then return nil end
  local pal = spritePal(S, rec)
  if pal then
    return Preview.imageWithPalette(S, rec.image, pal), pal
  end
  return Preview.image(S, rec.image), nil
end

local function blitSheetFrame(img, frames, frameIndex, x, y, cell, flip)
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

-- Resolve stand/walk frame + flip the way SpriteRenderer:draw does.
local function poseFrame(rec, facing, walkPhase, stepFlip)
  local frames = math.max(1, tonumber(rec and rec.frames) or 1)
  if frames <= 1 then return 0, false end
  facing = facing or "down"
  local walking = rec.walker and walkPhase == 1
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

-- Draw a 16×N frame strip with stand/walk labels (right = flip of left).
local function drawFrameStrip(S, rec, x, y, cell, s)
  if not rec or not rec.image then return y end
  local img = loadSpriteImage(S, rec)
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
    blitSheetFrame(img, frames, i, cx, y, cell, false)
    Kit.text("micro", FRAME_LABELS[i + 1] or tostring(i),
      cx, y + cell + 2 * s, PAL.faint)
  end
  return y + cell + 18 * s
end

-- Live walk-cycle preview (stand ↔ walk + step flip, optional auto-face).
local function drawAnimPreview(S, rec, x, y, w, s)
  if not rec then return y end
  local box = 72 * s
  local fh = 28 * s
  Kit.text("small", "Animation preview", x, y, PAL.caption)
  y = y + 18 * s

  if S.playerAnimPlaying == nil then S.playerAnimPlaying = true end
  if not S.playerAnimFacing then S.playerAnimFacing = "down" end

  local playing = S.playerAnimPlaying
  if Kit.chip(x, y, 72 * s, fh, playing and "PLAY" or "PAUSE",
      playing, PAL.green, PAL.steel,
      playing and "Pause the overworld walk cycle"
        or "Play the overworld walk cycle") then
    S.playerAnimPlaying = not playing
    playing = S.playerAnimPlaying
  end
  local auto = S.playerAnimAutoFace and true or false
  if Kit.chip(x + 80 * s, y, 88 * s, fh, auto and "AUTO" or "FACE",
      auto, PAL.blue, nil, "Auto-cycle facing while playing") then
    S.playerAnimAutoFace = not auto
    auto = S.playerAnimAutoFace
  end
  local fx = x + 180 * s
  for _, face in ipairs(FACINGS) do
    local on = S.playerAnimFacing == face
    local bw = 36 * s
    if Kit.chip(fx, y, bw, fh, FACING_LABEL[face] or face, on, PAL.yellow,
        PAL.steel, "Preview facing " .. face) then
      S.playerAnimFacing = face
      S.playerAnimAutoFace = false
    end
    fx = fx + bw + 4 * s
  end
  y = y + fh + 8 * s

  local t = (love and love.timer and love.timer.getTime and love.timer.getTime())
    or 0
  local facing = S.playerAnimFacing or "down"
  if playing and auto then
    facing = FACINGS[(math.floor(t / 1.2) % #FACINGS) + 1]
    S.playerAnimFacing = facing
  end

  -- Match overworld cadence roughly: stand/walk toggle + step flip on walk.
  local walkPhase, stepFlip = 0, false
  if playing and rec.walker and (tonumber(rec.frames) or 1) > 3 then
    local beat = math.floor(t / 0.14)
    walkPhase = beat % 2
    stepFlip = math.floor(beat / 2) % 2 == 1
  elseif not playing then
    walkPhase = S.playerAnimWalkHold or 0
    stepFlip = S.playerAnimFlipHold or false
  end
  if playing then
    S.playerAnimWalkHold = walkPhase
    S.playerAnimFlipHold = stepFlip
  end

  local img = loadSpriteImage(S, rec)
  local frames = math.max(1, tonumber(rec.frames) or 1)
  local fi, flip = poseFrame(rec, facing, walkPhase, stepFlip)

  Theme.col(PAL.cardBody or PAL.card, 1)
  love.graphics.rectangle("fill", x, y, box + 16 * s, box + 28 * s, 8 * s, 8 * s)
  blitSheetFrame(img, frames, fi, x + 8 * s, y + 8 * s, box, flip)

  local pose = (walkPhase == 1 and rec.walker) and "walk" or "stand"
  local info = string.format("%s · %s · f%d%s",
    FACING_LABEL[facing] or facing, pose, fi, flip and " · flip" or "")
  Kit.text("micro", info, x + 8 * s, y + box + 12 * s, PAL.muted)

  -- Mini facing strip: current pose in all 4 directions
  local mini = 28 * s
  local mx = x + box + 28 * s
  local my = y + 8 * s
  Kit.text("micro", "All facings", mx, my - 2 * s, PAL.faint)
  my = my + 14 * s
  for i, face in ipairs(FACINGS) do
    local mfi, mflip = poseFrame(rec, face, walkPhase, stepFlip)
    blitSheetFrame(img, frames, mfi, mx + (i - 1) * (mini + 6 * s), my, mini, mflip)
    Kit.text("micro", FACING_LABEL[face],
      mx + (i - 1) * (mini + 6 * s) + 6 * s, my + mini + 2 * s, PAL.faint)
  end

  return y + box + 36 * s
end

local function drawOverworld(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  S.project.sprites = S.project.sprites or {}
  S.project.playerSprites = S.project.playerSprites or {}

  local slots = owSlots(S)
  local slotIds = {}
  for _, slot in ipairs(slots) do slotIds[#slotIds + 1] = slot.id end
  -- Drop a Gen1-only selection (fly) after switching to Gold.
  do
    local ok = false
    for _, id in ipairs(slotIds) do
      if id == S.playerOwSlot then ok = true; break end
    end
    if not ok then S.playerOwSlot = slotIds[1] or "walk" end
  end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "PLAYER SPRITES", slotIds, {
      queryKey = "playerOwQuery",
      offsetKey = "playerOwOffset",
      selKey = "playerOwSlot",
      accent = PAL.green,
      listW = math.min(160 * s, w * 0.22),
      isOwned = function(id)
        local _, remapped = slotSpriteId(S, id)
        local sid = select(1, slotSpriteId(S, id))
        local _, sprOwned = resolveSprite(S, sid)
        return remapped or sprOwned
      end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        local sid = select(1, slotSpriteId(S, id)) or ""
        return sid:lower():find(ql, 1, true) ~= nil
      end,
    })

  if not S.playerOwSlot then S.playerOwSlot = shown[1] or "walk" end
  local slot = S.playerOwSlot
  local slotMeta
  for _, row in ipairs(slots) do
    if row.id == slot then slotMeta = row; break end
  end

  local spriteId, remapped = slotSpriteId(S, slot)
  local rec, sprOwned = resolveSprite(S, spriteId)

  Kit.caption(formX, y,
    (slotMeta and slotMeta.label or slot) .. " · " .. tostring(spriteId or "?")
      .. ((remapped or sprOwned) and "" or "  (vanilla)"))

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "playerOwScroll", tostring(slot) .. "|" .. tostring(spriteId),
    44 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s
  local prev = 72 * s

  Kit.text("micro",
    (slotMeta and slotMeta.tip) or "",
    viewX, fy, PAL.muted)
  fy = fy + 18 * s

  Kit.text("micro", Generation.isGen2(S)
      and (hasKris(S)
        and "Crystal: Chris and Kris sheets. Remap writes gen2PlayerSprites; sheet → sprites:patch."
        or "Gold: ChrisStateSprites. Remap writes gen2PlayerSprites; sheet → sprites:patch.")
      or "Sheet layout: 16×(16×frames). Walkers use 6 frames — stand D/U/L, walk D/U/L; right = flip left.",
    viewX, fy, PAL.faint)
  fy = fy + 28 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  row("Sprite id", function(fx, fy_, fw, fh_)
    local cur = spriteId or ""
    local ph = "SPRITE_RED"
    if Generation.isGen2(S) then
      if slot == "walkKris" then ph = "SPRITE_KRIS"
      elseif slot == "bikeKris" then ph = "SPRITE_KRIS_BIKE"
      else ph = "SPRITE_CHRIS" end
    end
    local v = RegList.field(App, "pl_sid", fx, fy_, math.max(40 * s, fw - 100 * s),
      fh_, cur, ph)
    if v ~= cur and v:match("^[%w_]+$") then
      setSlotSprite(S, slot, v, App)
      spriteId = v
      rec, sprOwned = resolveSprite(S, spriteId)
    end
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Reset", {
        kind = "ghost", tooltip = "Restore vanilla sprite id for this slot",
      }) then
      setSlotSprite(S, slot, nil, App)
      spriteId = select(1, slotSpriteId(S, slot))
      rec, sprOwned = resolveSprite(S, spriteId)
    end
  end)

  if not rec then
    Kit.text("micro", "No sprite record for " .. tostring(spriteId)
        .. " — create one or pick an existing id.",
      viewX, fy, PAL.yellow)
    fy = fy + 20 * s
    if Kit.button(viewX, fy, 180 * s, fh, "+ Create sprite", { kind = "good" }) then
      local sid = spriteId
      if not sid or sid == "" then
        sid = "SPRITE_PLAYER_" .. tostring(slot):upper()
        setSlotSprite(S, slot, sid, App)
        spriteId = sid
      end
      ensureSprite(S, sid, nil, App)
      rec, sprOwned = resolveSprite(S, sid)
    end
    fy = fy + fh + 12 * s
    FormPane.finish(S, "playerOwScroll", contentTop, fy, view)
    return
  end

  -- Live preview (may refresh after edits)
  rec = select(1, resolveSprite(S, spriteId)) or rec
  local pal = spritePal(S, rec)
  local prevY = fy
  Preview.draw(S, rec.image, viewX + viewW - prev, prevY, prev, prev, pal)
  if type(pal) == "table" then
    Preview.drawSwatches(pal,
      viewX + viewW - prev, prevY + prev + 4 * s, prev, 12 * s)
  elseif type(pal) == "string" then
    Preview.drawNamedSwatches(S, pal,
      viewX + viewW - prev, prevY + prev + 4 * s, prev, 12 * s)
  end

  local fieldW = viewW - labelW - prev - 12 * s
  if fieldW < 120 * s then fieldW = viewW - labelW - 8 * s end

  local function ensure()
    return ensureSprite(S, spriteId, rec, App)
  end

  row = function(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  row("Image", function(fx, fy_, fw, fh_)
    Kit.text("micro", Kit.ellipsize("micro", tostring(rec.image or ""), fw - 100 * s),
      fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
        kind = "ghost", tooltip = "Import player overworld PNG",
      }) then
      local sid = spriteId
      App.pickFile("Player sprite PNG", "PNG (*.png)|*.png|All|*.*",
        function(picked)
          local e = ensureSprite(S, sid, select(1, resolveSprite(S, sid)), App)
          App.importToMod(picked, nil, function(rel)
            e.image = rel
            Preview.invalidate()
          end)
        end)
    end
  end)

  row("Frames", function(fx, fy_, fw, fh_)
    local cur = rec.frames or 1
    local v = RegList.num(App, "pl_fr", fx, fy_, 60 * s, fh_, cur)
    v = math.max(1, math.min(16, v))
    if v ~= cur then ensure().frames = v; rec = ensure() end
  end)

  row("Walker", function(fx, fy_, fw, fh_)
    local on = rec.walker and true or false
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.green) then
      ensure().walker = not on
      rec = ensure()
      App.markDirty()
    end
  end)

  row("TrueColor", function(fx, fy_, fw, fh_)
    local on = rec.trueColor and true or false
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow,
        nil, "YES = raw PNG colors (skip palette remap)") then
      local e = ensure()
      e.trueColor = not on
      if not e.trueColor then e.trueColor = nil end
      rec = e
      Preview.invalidate()
      App.markDirty()
    end
    Kit.text("micro",
      on and "raw PNG"
        or (Generation.isGen2(S) and "OBJ remap" or "SGB remap"),
      fx + 90 * s, fy_ + 8 * s, PAL.faint)
  end)

  if Generation.isGen2(S) then
    row("Palette", function(fx, fy_, fw, fh_)
      if rec.trueColor then
        Kit.text("small", "(ignored — TrueColor)", fx, fy_ + 6 * s, PAL.faint)
        return
      end
      local cur = rec.palette or "PAL_OW_RED"
      if Kit.button(fx, fy_, math.min(fw, 160 * s), fh_,
          Kit.ellipsize("small", cur, math.min(fw, 160 * s) - 8 * s),
          { kind = "ghost", tooltip = "Cycle PAL_OW_*" }) then
        local e = ensure()
        e.palette = RegList.cycle(SpriteUtil.OW_PALETTES, cur)
        local idx
        for i, name in ipairs(SpriteUtil.OW_PALETTES) do
          if name == e.palette then idx = i - 1; break end
        end
        if idx then e.paletteId = idx end
        rec = e
        Preview.invalidate()
        App.markDirty()
      end
      local colors = spritePal(S, rec)
      if colors then
        Preview.drawSwatches(colors, fx + fw - 80 * s,
          fy_ + (fh_ - 14 * s) / 2, 80 * s, 14 * s)
      end
    end)
    row("Palette id", function(fx, fy_, fw, fh_)
      local cur = tonumber(rec.paletteId) or 0
      local v = RegList.num(App, "pl_pid", fx, fy_, 60 * s, fh_, cur)
      v = math.max(0, math.min(7, math.floor(v)))
      if v ~= cur then
        local e = ensure()
        e.paletteId = v
        e.palette = SpriteUtil.OW_PALETTES[v + 1] or e.palette
        rec = e
        Preview.invalidate()
        App.markDirty()
      end
    end)
  else
    row("Palette", function(fx, fy_, fw, fh_)
      PalettePicker.row(S, {
        x = fx, y = fy_, w = fw, h = fh_,
        current = rec.paletteSource or "",
        effective = type(pal) == "string" and pal or nil,
        emptyLabel = "(MEWMON)",
        clearLabel = "(MEWMON default)",
        allowClear = true,
        title = "PLAYER SPRITE PALETTE",
        tooltip = "SGB palette for this overworld sheet",
        onPick = function(id)
          local e = ensure()
          e.paletteSource = id
          Preview.invalidate()
          App.markDirty()
        end,
        owner = {
          kind = "sprite",
          entityId = spriteId,
          entityLabel = spriteId,
          assign = function(id)
            local e = ensure()
            e.paletteSource = id
            Preview.invalidate()
            App.markDirty()
          end,
        },
      })
    end)
  end

  fy = fy + 4 * s
  fy = drawAnimPreview(S, rec, viewX, fy, viewW, s)
  fy = fy + 8 * s
  fy = drawFrameStrip(S, rec, viewX, fy, 40 * s, s)

  if Kit.button(viewX, fy, 140 * s, fh, "Open in GFX", {
      kind = "ghost", tooltip = "Edit this sprite on the GFX tab",
    }) then
    S.tab = "gfx"
    S.gfxMode = "sprites"
    S.spriteEditId = spriteId
  end
  fy = fy + fh + 8 * s

  if sprOwned and Kit.button(viewX, fy, 160 * s, fh, "Revert sheet", {
      kind = "danger", tooltip = "Drop mod override for this sprite record",
    }) then
    S.project.sprites[spriteId] = nil
    App.markDirty()
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "playerOwScroll", contentTop, fy, view)
end

local function drawPics(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  S.project.playerPics = S.project.playerPics or {}

  local slots = picSlots(S)
  local slotIds = {}
  for _, slot in ipairs(slots) do slotIds[#slotIds + 1] = slot.id end
  do
    local ok = false
    for _, id in ipairs(slotIds) do
      if id == S.playerPicSlot then ok = true; break end
    end
    if not ok then S.playerPicSlot = slotIds[1] or "front" end
  end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "PLAYER PICS", slotIds, {
      queryKey = "playerPicQuery",
      offsetKey = "playerPicOffset",
      selKey = "playerPicSlot",
      accent = PAL.blue,
      listW = math.min(160 * s, w * 0.22),
      isOwned = function(id)
        return select(2, slotPicPath(S, id))
      end,
    })

  if not S.playerPicSlot then S.playerPicSlot = shown[1] or "front" end
  local slot = S.playerPicSlot
  local slotMeta
  for _, row in ipairs(slots) do
    if row.id == slot then slotMeta = row; break end
  end
  local path, owned = slotPicPath(S, slot)

  Kit.caption(formX, y,
    (slotMeta and slotMeta.label or slot) .. (owned and "" or "  (vanilla)"))

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "playerPicScroll", tostring(slot) .. "|" .. tostring(path),
    owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 100 * s
  local fh = 28 * s
  local prev = 96 * s

  Kit.text("micro", (slotMeta and slotMeta.tip) or "", viewX, fy, PAL.muted)
  fy = fy + 20 * s

  Preview.draw(S, path, viewX + viewW - prev, fy, prev, prev)
  local fieldW = viewW - labelW - prev - 12 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  row("Path", function(fx, fy_, fw, fh_)
    local cur = path or ""
    local v = RegList.field(App, "pl_pic", fx, fy_, math.max(40 * s, fw - 100 * s),
      fh_, cur, "assets/...")
    if v ~= cur then
      setSlotPic(S, slot, v, App)
      path = v
    end
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
        kind = "ghost", tooltip = "Import player pic PNG",
      }) then
      App.pickFile("Player pic PNG", "PNG (*.png)|*.png|All|*.*",
        function(picked)
          App.importToMod(picked, nil, function(rel)
            setSlotPic(S, slot, rel, App)
            Preview.invalidate()
          end)
        end)
    end
  end)

  if owned then
    if Kit.button(viewX, fy, 120 * s, fh, "Reset", {
        kind = "danger", tooltip = "Restore vanilla pic path",
      }) then
      setSlotPic(S, slot, nil, App)
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "playerPicScroll", contentTop, fy, view)
end

function Player.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local modeY = RegList.modeChips(S, "playerMode", modesFor(S), x, y, s)
  local mode = S.playerMode or "overworld"
  if mode == "pics" then
    drawPics(S, x, modeY, w, h - (modeY - y), App)
  else
    drawOverworld(S, x, modeY, w, h - (modeY - y), App)
  end
end

return Player
