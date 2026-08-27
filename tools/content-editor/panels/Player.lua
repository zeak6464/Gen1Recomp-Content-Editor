-- Player tab: new-game start, advanced limits/Fly, overworld sprites, pics.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local SpriteUtil = require("SpriteUtil")
local SpriteAnimPreview = require("SpriteAnimPreview")
local Generation = require("Generation")
local ItemPicker = require("ItemPicker")
local PAL = Theme.PAL

local Player = {}

local FACINGS = { "up", "down", "left", "right" }

local GEN2_PLAYER_NAME = {
  gold = "GOLD", silver = "SILVER", crystal = "CHRIS",
}
local GEN2_PLAYER_PRESETS = {
  gold = { "GOLD", "HIRO", "TAYLOR", "KARL" },
  silver = { "SILVER", "KAMON", "OSCAR", "MAX" },
  crystal = { "CHRIS", "MAT", "ALLAN", "JON" },
}

local function modesFor(S)
  local start = { id = "start", label = "New game",
    tip = "Spawn, money, bag, and PC items" }
  local advanced = { id = "advanced", label = "Advanced",
    tip = "Limits, badges, and Fly" }
  if Generation.isGen2(S) then
    return {
      start, advanced,
      { id = "overworld", label = "Overworld",
        tip = "Walk / bike / surf sprite sheets and Chris slot remaps" },
      { id = "pics", label = "Pics",
        tip = "Battle back, Dude back, Oak-speech front (card art: UI → Badges)" },
    }
  end
  return {
    start, advanced,
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

local function spritePal(S, rec)
  return SpriteAnimPreview.palette(S, rec)
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
  fy = SpriteAnimPreview.draw(S, rec, viewX, fy, viewW, {
    prefix = "playerAnim", s = s,
  })
  fy = fy + 8 * s
  fy = SpriteAnimPreview.drawStrip(S, rec, viewX, fy, 40 * s, s)

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

local function copyItemRows(src)
  local out = {}
  for i, row in ipairs(src or {}) do
    if type(row) == "table" then
      out[i] = { id = row.id, count = tonumber(row.count) or 1 }
    end
  end
  return out
end

local function parseCsvIds(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function joinCsvIds(t)
  if type(t) ~= "table" then return "" end
  return table.concat(t, ", ")
end

local function copyStrList(src)
  local out = {}
  if type(src) ~= "table" then return out end
  for i, v in ipairs(src) do out[i] = v end
  return out
end

-- Crystal/Gold ignore Data.field.boot (still Red's house). New game uses
-- landmarks.spawns.SPAWN_HOME, 3000 money, empty bag/PC.
function Player.vanillaBoot(S)
  if Generation.isGen2(S) then
    local lm = S.data and (S.data.gen2Landmarks or S.data.landmarks)
    local spot = lm and lm.spawns and lm.spawns.SPAWN_HOME
    local map = (type(spot) == "table" and spot.map) or "PLAYERS_HOUSE_2F"
    local x = (type(spot) == "table" and tonumber(spot.x)) or 3
    local y = (type(spot) == "table" and tonumber(spot.y)) or 3
    local ver = Generation.id(S)
    local presets = GEN2_PLAYER_PRESETS[ver] or GEN2_PLAYER_PRESETS.gold
    return {
      startMap = map, startX = x, startY = y, startFacing = "down",
      startMoney = 3000,
      playerName = GEN2_PLAYER_NAME[ver] or "GOLD",
      rivalName = "???",
      lastHeal = { map = map, x = x, y = y },
      namePresets = {
        player = copyStrList(presets),
        rival = { "SILVER" },
      },
      startItems = {},
      startPcItems = {},
    }
  end
  local b = (S.data and S.data.field and S.data.field.boot) or {}
  local map = b.startMap or "REDS_HOUSE_2F"
  local x = b.startX or 3
  local y = b.startY or 6
  local facing = b.startFacing or "down"
  if map == "REDS_HOUSE_2F" and Generation.id(S) ~= "yellow" then
    facing = "up"
  end
  local heal = b.lastHeal
  if type(heal) ~= "table" or not heal.map then
    if map == "REDS_HOUSE_2F" then
      heal = { map = "PALLET_TOWN", x = 5, y = 6 }
    else
      heal = { map = map, x = x, y = y }
    end
  end
  local presets = b.namePresets
  if type(presets) ~= "table" then
    presets = { player = { "RED", "ASH", "JACK" }, rival = { "BLUE", "GARY", "JOHN" } }
  end
  return {
    startMap = map, startX = x, startY = y, startFacing = facing,
    startMoney = b.startMoney or 3000,
    playerName = b.playerName or "RED",
    rivalName = b.rivalName or "BLUE",
    lastHeal = heal,
    namePresets = {
      player = copyStrList(presets.player),
      rival = copyStrList(presets.rival),
    },
    startItems = {},
    startPcItems = { { id = "POTION", count = 1 } },
  }
end

local function bootField(S, key)
  local b = S.project and S.project.boot
  if b and b[key] ~= nil then
    if not (type(b[key]) == "string" and b[key] == "") then
      return b[key]
    end
  end
  return Player.vanillaBoot(S)[key]
end

local function lastHealField(S, key)
  local lh = S.project and S.project.boot and S.project.boot.lastHeal
  if lh and lh[key] ~= nil then
    if not (type(lh[key]) == "string" and lh[key] == "") then
      return lh[key]
    end
  end
  local heal = Player.vanillaBoot(S).lastHeal
  return heal and heal[key]
end

local function setBoot(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.boot[key] = val
  App.markDirty()
end

local function setLastHeal(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.boot.lastHeal = S.project.boot.lastHeal or {}
  S.project.boot.lastHeal[key] = val
  App.markDirty()
end

local function ensureBootItemList(S, key, App)
  State.ensureProjectFields(S.project)
  if type(S.project.boot[key]) ~= "table" then
    S.project.boot[key] = copyItemRows(Player.vanillaBoot(S)[key])
    App.markDirty()
  end
  return S.project.boot[key]
end

local function drawBootItemList(S, App, key, title, x, y, w, fh, s)
  Kit.text("small", title, x, y + 6 * s, PAL.caption)
  y = y + 24 * s
  local owned = type(S.project.boot and S.project.boot[key]) == "table"
  local list = owned and S.project.boot[key]
    or copyItemRows(Player.vanillaBoot(S)[key])
  if not owned then
    Kit.text("micro", "Vanilla for this ROM. Edit to override.",
      x, y, PAL.muted)
  elseif #list == 0 then
    Kit.text("micro", "Starts with no items. Vanilla restores the original bag or PC.",
      x, y, PAL.muted)
  else
    Kit.text("micro", "Qty is how many of that item. X removes the row.",
      x, y, PAL.muted)
  end
  y = y + 20 * s
  for i, row in ipairs(list) do
    local slot = i
    ItemPicker.field(S, {
      x = x, y = y, w = w - 160 * s, h = fh,
      current = (row and row.id) or "",
      title = title,
      onPick = function(id)
        local e = ensureBootItemList(S, key, App)
        e[slot] = e[slot] or {}
        e[slot].id = id
        e[slot].count = tonumber(e[slot].count) or 1
        App.markDirty()
      end,
    })
    local count = tonumber(row and row.count) or 1
    local shown = RegList.num(App, "pl_" .. key .. "_" .. slot,
      x + w - 152 * s, y, 72 * s, fh, count)
    if shown ~= count then
      local e = ensureBootItemList(S, key, App)
      e[slot] = e[slot] or {}
      e[slot].count = math.max(1, math.floor(tonumber(shown) or 1))
      App.markDirty()
    end
    if Kit.button(x + w - 36 * s, y, 32 * s, fh, "X", { kind = "danger" }) then
      table.remove(ensureBootItemList(S, key, App), slot)
      App.markDirty()
      break
    end
    y = y + fh + 6 * s
  end
  if Kit.button(x, y, 140 * s, fh, "+ Add item", { kind = "good" }) then
    local e = ensureBootItemList(S, key, App)
    e[#e + 1] = { id = "POTION", count = 1 }
    App.markDirty()
  end
  if owned and Kit.button(x + 148 * s, y, 150 * s, fh, "Vanilla", { kind = "ghost" }) then
    S.project.boot[key] = nil
    App.markDirty()
  end
  return y + fh + 8 * s
end

local function drawStart(S, x, y, w, h, App)
  local s = Kit.scale
  local pad = 16 * s
  local fh = 28 * s
  FormPane.track(S, "playerStartScroll", S.project and S.project.id or "")
  local row, pageView = FormPane.begin(S, "playerStartScroll", x, y, w, h)
  local pageTop = row
  w = pageView.contentW or w

  Kit.caption(x, row, "NEW-GAME START")
  row = row + 24 * s
  Kit.text("micro",
    "Values shown are this ROM's vanilla new game. Change a field to override it.",
    x, row, PAL.muted)
  row = row + 22 * s

  local innerY = row
  local cardH = S._playerStartH or (760 * s)
  Kit.card(x, innerY, w, cardH, 14 * s)
  local scrollPad = 12 * s
  local viewX = x + scrollPad
  local viewW = w - 2 * scrollPad
  local fy = innerY + scrollPad
  local labelW = 120 * s

  local function bootRow(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  local vanilla = Player.vanillaBoot(S)
  local mapHint = tostring(vanilla.startMap or "")
  bootRow("Start map", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "startMap") or "")
    local v = RegList.field(App, "pl_boot_map", fx, fy_, fw, fh_, cur, mapHint)
    if v ~= cur then setBoot(S, "startMap", v, App) end
  end)
  bootRow("Start X", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startX") or 0
    local v = RegList.num(App, "pl_boot_x", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startX", v, App) end
  end)
  bootRow("Start Y", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startY") or 0
    local v = RegList.num(App, "pl_boot_y", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startY", v, App) end
  end)
  bootRow("Facing", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "startFacing") or "down")
    if Kit.button(fx, fy_, fw, fh_, Kit.ellipsize("small", cur, fw - 8 * s),
        { kind = "ghost" }) then
      setBoot(S, "startFacing", RegList.cycle(FACINGS, cur), App)
    end
  end)
  bootRow("Starting money", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startMoney") or 0
    local v = RegList.num(App, "pl_boot_money", fx, fy_, 100 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startMoney", v, App) end
  end)
  bootRow("Last heal map", function(fx, fy_, fw, fh_)
    local cur = tostring(lastHealField(S, "map") or "")
    local v = RegList.field(App, "pl_boot_lhm", fx, fy_, fw, fh_, cur, mapHint)
    if v ~= cur then setLastHeal(S, "map", v, App) end
  end)
  bootRow("Last heal X", function(fx, fy_, fw, fh_)
    local cur = lastHealField(S, "x") or 0
    local v = RegList.num(App, "pl_boot_lhx", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setLastHeal(S, "x", v, App) end
  end)
  bootRow("Last heal Y", function(fx, fy_, fw, fh_)
    local cur = lastHealField(S, "y") or 0
    local v = RegList.num(App, "pl_boot_lhy", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setLastHeal(S, "y", v, App) end
  end)

  bootRow("Player", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "playerName") or "")
    local v = RegList.field(App, "pl_boot_pname", fx, fy_, fw, fh_, cur,
      vanilla.playerName or "")
    if v ~= cur then setBoot(S, "playerName", v, App) end
  end)
  bootRow("Rival", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "rivalName") or "")
    local v = RegList.field(App, "pl_boot_rname", fx, fy_, fw, fh_, cur,
      vanilla.rivalName or "")
    if v ~= cur then setBoot(S, "rivalName", v, App) end
  end)

  local function namePresetList(who)
    local presets = bootField(S, "namePresets")
    if type(presets) == "table" and type(presets[who]) == "table" then
      return presets[who]
    end
    local base = vanilla.namePresets
    return base and base[who]
  end

  local function setNamePresets(who, list)
    State.ensureProjectFields(S.project)
    local cur = S.project.boot.namePresets
    if type(cur) ~= "table" then
      local base = vanilla.namePresets or {}
      cur = {
        player = copyStrList(base.player),
        rival = copyStrList(base.rival),
      }
      S.project.boot.namePresets = cur
    end
    cur[who] = list
    App.markDirty()
  end

  bootRow("Player names", function(fx, fy_, fw, fh_)
    local cur = joinCsvIds(namePresetList("player"))
    local v = RegList.field(App, "pl_boot_pnames", fx, fy_, fw, fh_, cur,
      joinCsvIds(vanilla.namePresets and vanilla.namePresets.player))
    if v ~= cur then setNamePresets("player", parseCsvIds(v)) end
  end)
  bootRow("Rival names", function(fx, fy_, fw, fh_)
    local cur = joinCsvIds(namePresetList("rival"))
    local v = RegList.field(App, "pl_boot_rnames", fx, fy_, fw, fh_, cur,
      joinCsvIds(vanilla.namePresets and vanilla.namePresets.rival))
    if v ~= cur then setNamePresets("rival", parseCsvIds(v)) end
  end)

  fy = fy + 8 * s
  fy = drawBootItemList(S, App, "startItems", "Bag items",
    viewX, fy, viewW, fh, s)
  fy = drawBootItemList(S, App, "startPcItems", "PC items",
    viewX, fy, viewW, fh, s)

  S._playerStartH = math.max(120 * s, fy - innerY + scrollPad)
  row = innerY + S._playerStartH + pad
  FormPane.finish(S, "playerStartScroll", pageTop, row, pageView)
end

function Player.dataConstants(S)
  return (S.data and S.data.constants) or {}
end

function Player.constField(S, key)
  local c = S.project and S.project.constants
  if c and c[key] ~= nil then return c[key] end
  return Player.dataConstants(S)[key]
end

function Player.setConst(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.constants[key] = val
  App.markDirty()
end

function Player.badgeRows(S)
  local c = S.project and S.project.constants
  if c and c.badges and #c.badges > 0 then return c.badges end
  local dc = Player.dataConstants(S).badges
  if type(dc) == "table" and #dc > 0 then return dc end
  return {}
end

function Player.ensureBadges(S, App)
  State.ensureProjectFields(S.project)
  if not S.project.constants.badges or #S.project.constants.badges == 0 then
    local src = Player.dataConstants(S).badges
    S.project.constants.badges = {}
    if type(src) == "table" then
      for i, row in ipairs(src) do
        S.project.constants.badges[i] = {
          id = row.id or "",
          name = row.name or "",
        }
      end
    end
    App.markDirty()
  end
  return S.project.constants.badges
end

function Player.drawAdvanced(S, x, y, w, h, App)
  local s = Kit.scale
  local pad = 16 * s
  local fh = 28 * s
  FormPane.track(S, "playerAdvScroll", S.project and S.project.id or "")
  local row, pageView = FormPane.begin(S, "playerAdvScroll", x, y, w, h)
  local pageTop = row
  w = pageView.contentW or w

  Kit.caption(x, row, "ADVANCED")
  row = row + 24 * s
  Kit.text("micro",
    "Optional rules, capacity, and Fly. Unchanged fields keep this ROM's defaults.",
    x, row, PAL.muted)
  row = row + 22 * s

  local innerY = row
  local cardH = S._playerAdvancedH or (520 * s)
  Kit.card(x, innerY, w, cardH, 14 * s)
  local scrollPad = 12 * s
  local viewX = x + scrollPad
  local viewW = w - 2 * scrollPad
  local fy = innerY + scrollPad
  local labelW = 120 * s
  local secGap = 20 * s

  local function advRow(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.caption(viewX, fy, "CONSTANTS")
  fy = fy + 24 * s
  Kit.text("micro",
    "Optional rules and capacity limits.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s

  if Generation.isGen2(S) then
    advRow("Shiny rate", function(fx, fy_, fw, fh_)
      local cur = tonumber(S.project.shinyRate) or 8192
      local v = RegList.num(App, "pl_shiny_rate", fx, fy_, 80 * s, fh_, cur)
      v = math.max(1, math.floor(v))
      if v ~= cur then
        State.ensureProjectFields(S.project)
        S.project.shinyRate = v
        App.markDirty()
      end
    end)
    Kit.text("micro",
      "1 / N chance a wild/gift mon rolls forced shiny DVs (vanilla 8192).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
  end

  advRow("Level cap", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "levelCap") or 100
    local v = RegList.num(App, "pl_const_lvl", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "levelCap", v, App) end
  end)
  advRow("Dex size", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "dexSize") or 151
    local v = RegList.num(App, "pl_const_dex", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "dexSize", v, App) end
  end)
  advRow("Dex digits", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "dexDigits") or 3
    local v = RegList.num(App, "pl_const_ddig", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "dexDigits", v, App) end
  end)
  advRow("Party max", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "partyMax") or 6
    local v = RegList.num(App, "pl_const_party", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "partyMax", v, App) end
  end)
  advRow("Bag size", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "bagSize") or 20
    local v = RegList.num(App, "pl_const_bag", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "bagSize", v, App) end
  end)
  advRow("Money cap", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "moneyCap") or 999999
    local v = RegList.num(App, "pl_const_money", fx, fy_, 100 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "moneyCap", v, App) end
  end)
  advRow("Coin cap", function(fx, fy_, fw, fh_)
    local cur = Player.constField(S, "coinCap") or 9999
    local v = RegList.num(App, "pl_const_coin", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then Player.setConst(S, "coinCap", v, App) end
  end)
  advRow("HM moves", function(fx, fy_, fw, fh_)
    local cur = joinCsvIds(Player.constField(S, "hmMoves"))
    local v = RegList.field(App, "pl_const_hm", fx, fy_, fw, fh_, cur, "CUT, FLY, SURF")
    if v ~= cur then Player.setConst(S, "hmMoves", parseCsvIds(v), App) end
  end)

  Kit.text("small", "Badges", viewX, fy + 6 * s, PAL.caption)
  fy = fy + 28 * s
  local badges = Player.badgeRows(S)
  if #badges == 0 then
    Kit.text("micro", "(no badges — add one below)", viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end
  for i = 1, math.max(#badges, 0) do
    local badge = badges[i] or { id = "", name = "" }
    local idCur = tostring(badge.id or "")
    local nameCur = tostring(badge.name or "")
    Kit.text("micro", "#" .. i, viewX, fy + 8 * s, PAL.muted)
    local idV = RegList.field(App, "pl_bdg_id_" .. i, viewX + 28 * s, fy, 140 * s, fh,
      idCur, "BOULDERBADGE")
    local nameV = RegList.field(App, "pl_bdg_nm_" .. i, viewX + 176 * s, fy,
      viewW - 176 * s - 44 * s, fh, nameCur, "Boulder")
    if idV ~= idCur or nameV ~= nameCur then
      local rows = Player.ensureBadges(S, App)
      rows[i] = rows[i] or {}
      rows[i].id = idV
      rows[i].name = nameV
    end
    if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X", { kind = "danger" }) then
      local rows = Player.ensureBadges(S, App)
      table.remove(rows, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(viewX, fy, 100 * s, fh, "+ Badge", { kind = "good" }) then
    local rows = Player.ensureBadges(S, App)
    rows[#rows + 1] = { id = "NEW_BADGE", name = "Badge" }
    App.markDirty()
  end
  fy = fy + fh + secGap

  Kit.caption(viewX, fy, "TRADES / SHOPS")
  fy = fy + 24 * s
  Kit.text("micro",
    "Open the dedicated editors for in-game trades and shop inventories.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s
  if Kit.button(viewX, fy, 100 * s, fh, "Trades", { kind = "accent" }) then
    S.tab = "trades"
  end
  if Kit.button(viewX + 110 * s, fy, 100 * s, fh, "Shops", { kind = "accent" }) then
    S.tab = "shops"
  end
  fy = fy + fh + secGap

  if not Generation.isGen2(S) then
    Kit.caption(viewX, fy, "FLY ORDER")
    fy = fy + 24 * s
    Kit.text("micro",
      "Controls the order and availability of destinations shown by the Fly menu.",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s

    local function ensureFlyOrder()
      if type(S.project.flyOrder) == "table" then return S.project.flyOrder end
      local base = (S.data and S.data.field and S.data.field.flyOrder) or {}
      local copy = {}
      for i, mid in ipairs(base) do copy[i] = mid end
      S.project.flyOrder = copy
      if next(S.project.flyWarps or {}) == nil then
        local fw = (S.data and S.data.field and S.data.field.flyWarps) or {}
        S.project.flyWarps = {}
        for mid, spot in pairs(fw) do
          if type(spot) == "table" then
            S.project.flyWarps[mid] = { x = spot.x or 0, y = spot.y or 0 }
          end
        end
      end
      App.markDirty()
      return copy
    end

    if type(S.project.flyOrder) ~= "table" then
      if Kit.button(viewX, fy, 160 * s, fh, "Edit fly order…", { kind = "accent" }) then
        ensureFlyOrder()
      end
      fy = fy + fh + 8 * s
    else
      local order = S.project.flyOrder
      S.project.flyWarps = S.project.flyWarps or {}
      for i, mid in ipairs(order) do
        local midV = RegList.field(App, "pl_fly_" .. i, viewX, fy,
          160 * s, fh, tostring(mid or ""), "PALLET_TOWN"):upper():gsub("%s+", "_")
        if midV ~= mid then
          order[i] = midV
          if S.project.flyWarps[mid] and not S.project.flyWarps[midV] then
            S.project.flyWarps[midV] = S.project.flyWarps[mid]
            S.project.flyWarps[mid] = nil
          end
          App.markDirty()
          mid = midV
        end
        local spot = S.project.flyWarps[mid]
        if not spot then
          local base = S.data and S.data.field and S.data.field.flyWarps
            and S.data.field.flyWarps[mid]
          spot = { x = (base and base.x) or 0, y = (base and base.y) or 0 }
          S.project.flyWarps[mid] = spot
        end
        local xV = tonumber(RegList.num(App, "pl_flyx_" .. i,
          viewX + 170 * s, fy, 50 * s, fh, tonumber(spot.x) or 0)) or 0
        local yV = tonumber(RegList.num(App, "pl_flyy_" .. i,
          viewX + 228 * s, fy, 50 * s, fh, tonumber(spot.y) or 0)) or 0
        if xV ~= (spot.x or 0) or yV ~= (spot.y or 0) then
          spot.x, spot.y = xV, yV
          App.markDirty()
        end
        Kit.text("micro", "land x,y", viewX + 286 * s, fy + 8 * s, PAL.faint)
        if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
            { kind = "danger" }) then
          S.project.flyWarps[mid] = nil
          table.remove(order, i)
          App.markDirty()
          break
        end
        fy = fy + fh + 6 * s
      end
      if Kit.button(viewX, fy, 120 * s, fh, "+ Fly spot", { kind = "good" }) then
        order[#order + 1] = "NEW_TOWN"
        S.project.flyWarps["NEW_TOWN"] = { x = 0, y = 0 }
        App.markDirty()
      end
      fy = fy + fh + 8 * s
    end
  else
    Kit.caption(viewX, fy, "FLY POINTS")
    fy = fy + 24 * s
    Kit.text("micro",
      "Maps each Fly landmark to the spawn and landing position used on arrival.",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s

    local function ensureFlyPoints()
      if type(S.project.flyPoints) == "table" and #S.project.flyPoints > 0 then
        return S.project.flyPoints
      end
      local ok, FieldMoves = pcall(require, "src.world.gen2.FieldMoves")
      local base = (ok and FieldMoves and FieldMoves.FLYPOINTS) or {}
      local spawns = S.data and S.data.gen2Landmarks and S.data.gen2Landmarks.spawns
      local copy = {}
      for i, row in ipairs(base) do
        local spot = spawns and spawns[row.spawn]
        copy[i] = {
          landmark = row.landmark, spawn = row.spawn, flag = row.flag,
          map = spot and spot.map, x = spot and spot.x, y = spot and spot.y,
        }
      end
      S.project.flyPoints = copy
      App.markDirty()
      return copy
    end

    if type(S.project.flyPoints) ~= "table" or #S.project.flyPoints == 0 then
      if Kit.button(viewX, fy, 160 * s, fh, "Edit fly points…", { kind = "accent" }) then
        ensureFlyPoints()
      end
      fy = fy + fh + 8 * s
    else
      local rows = S.project.flyPoints
      for i, row in ipairs(rows) do
        local landmarkV = RegList.field(App, "pl_flylm_" .. i, viewX, fy,
          150 * s, fh, tostring(row.landmark or ""), "LANDMARK_...")
          :upper():gsub("%s+", "_")
        if landmarkV ~= row.landmark then row.landmark = landmarkV end
        local spawnV = RegList.field(App, "pl_flysp_" .. i, viewX + 158 * s, fy,
          130 * s, fh, tostring(row.spawn or ""), "SPAWN_...")
          :upper():gsub("%s+", "_")
        if spawnV ~= row.spawn then row.spawn = spawnV end
        local flagV = tonumber(RegList.num(App, "pl_flyfl_" .. i,
          viewX + 294 * s, fy, 44 * s, fh, tonumber(row.flag) or 0)) or 0
        if flagV ~= (row.flag or 0) then row.flag = flagV end
        local mapV = RegList.field(App, "pl_flymap_" .. i, viewX + 344 * s, fy,
          130 * s, fh, tostring(row.map or ""), "map")
          :upper():gsub("%s+", "_")
        if mapV ~= (row.map or "") then row.map = (mapV ~= "" and mapV) or nil end
        local xV = tonumber(RegList.num(App, "pl_flyx_" .. i,
          viewX + 480 * s, fy, 44 * s, fh, tonumber(row.x) or 0)) or 0
        local yV = tonumber(RegList.num(App, "pl_flyy_" .. i,
          viewX + 528 * s, fy, 44 * s, fh, tonumber(row.y) or 0)) or 0
        if xV ~= (row.x or 0) then row.x = xV end
        if yV ~= (row.y or 0) then row.y = yV end
        Kit.text("micro", "land map/x,y", viewX + 576 * s, fy + 8 * s, PAL.faint)
        if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
            { kind = "danger" }) then
          table.remove(rows, i)
          App.markDirty()
          break
        end
        fy = fy + fh + 6 * s
      end
      if Kit.button(viewX, fy, 120 * s, fh, "+ Fly point", { kind = "good" }) then
        rows[#rows + 1] = { landmark = "LANDMARK_NEW", spawn = "SPAWN_NEW", flag = 0 }
        App.markDirty()
      end
      fy = fy + fh + 8 * s
    end
  end

  S._playerAdvancedH = math.max(120 * s, fy - innerY + scrollPad)
  row = innerY + S._playerAdvancedH + pad
  FormPane.finish(S, "playerAdvScroll", pageTop, row, pageView)
end

function Player.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local modeY = RegList.modeChips(S, "playerMode", modesFor(S), x, y, s)
  local mode = S.playerMode or "start"
  local bodyH = h - (modeY - y)
  if mode == "pics" then
    drawPics(S, x, modeY, w, bodyH, App)
  elseif mode == "overworld" then
    drawOverworld(S, x, modeY, w, bodyH, App)
  elseif mode == "advanced" then
    Player.drawAdvanced(S, x, modeY, w, bodyH, App)
  else
    drawStart(S, x, modeY, w, bodyH, App)
  end
end

return Player
