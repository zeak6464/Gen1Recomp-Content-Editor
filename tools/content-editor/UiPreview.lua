-- In-editor UI screen preview (160×144 GB viewport): title drop/cycle,
-- intro splash, theme boxes, fonts/strings/town map/badges/boot cards.
-- Gen2 intro uses CrystalIntro / GoldSilverIntro with a stub game (no input,
-- so editor clicks do not skip). Gen1 TitleState / IntroMovie stay approximated.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Preview = require("Preview")
local Generation = require("Generation")
local PAL = Theme.PAL

local UiPreview = {}

local GB_W, GB_H = 160, 144
local CYCLE_FRAMES = 240
local DROP_STEPS = {
  { -4, 16 }, { 3, 4 }, { -3, 4 }, { 2, 2 }, { -2, 2 }, { 1, 2 }, { -1, 2 },
}

-- IntroMovie phase-2 timeline (frames from splash start)
local COPYRIGHT_FRAMES = 180
local STAR_START = 64
local STAR_FRAMES = 40
local FLASH_START = STAR_START + STAR_FRAMES
local FLASH_FRAMES = 30
local WAVES_START = FLASH_START + FLASH_FRAMES
local WAVE_FRAMES = 24
local WAVES_END = WAVES_START + 6 * WAVE_FRAMES
local SPLASH_FRAMES = WAVES_END + 40
local STUDIO_BOX = { w = 128, h = 52, cx = 80, cy = 60 }
local STAR_WAVES = {
  { 40, 56, 80, 112 },
  { 48, 64, 88, 104 },
  { 44, 68, 76, 92 },
  { 52, 84, 100, 108 },
}

local function namedPal(S, name, fallback)
  return Preview.paletteColors(S, name) or fallback
end

-- Engine TitleState takes LOGO1's white from LOGO2 so the ribbon band
-- matches the logo (every SuperPal shares color 0 on hardware).
local function withWhiteOf(pal, ref)
  if not pal then return nil end
  if not (ref and ref[1]) then return pal end
  return { ref[1], pal[2], pal[3], pal[4] }
end

-- Remap the grayscale GB canvas through SGB zones (same shader the engine
-- uses after a screen's sgbPalettes()).
local function blitSgbZones(canvas, zones)
  local G = love.graphics
  local okP, P = pcall(require, "src.render.PaletteFX")
  local shader = okP and P and P.shader and P.shader()
  if not shader then
    G.draw(canvas, 0, 0)
    return
  end
  G.setShader(shader)
  for i = 1, #zones do
    local z = zones[i]
    if z and z.colors ~= false and type(z.colors) == "table" then
      pcall(P.sendColors, shader, z.colors)
      local x, y = z.x or 0, z.y or 0
      local w, h = z.w or GB_W, z.h or GB_H
      local okQ, quad = pcall(G.newQuad, x, y, w, h, GB_W, GB_H)
      if okQ and quad then
        G.draw(canvas, quad, x, y)
      else
        G.draw(canvas, 0, 0)
      end
    end
  end
  G.setShader()
end

-- Draw `body` at identity into a 160×144 canvas, then blit (colorized
-- when `zones` is set). LOVE scissors stay in screen space across
-- setCanvas, so the editor clip would empty engine movie layers.
local function presentGbCanvas(st, body, zones)
  local G = love.graphics
  if not st.gbCanvas then
    local ok, canvas = pcall(G.newCanvas, GB_W, GB_H)
    if ok and canvas then
      canvas:setFilter("nearest", "nearest")
      st.gbCanvas = canvas
    end
  end
  local canvas = st.gbCanvas
  if not canvas then
    body()
    G.setColor(1, 1, 1, 1)
    return
  end
  local previous = G.getCanvas()
  local sx, sy, sw, sh = G.getScissor()
  G.push()
  G.origin()
  G.setScissor()
  G.setShader()
  G.setCanvas(canvas)
  G.clear(0, 0, 0, 1)
  G.setColor(1, 1, 1, 1)
  pcall(body)
  if previous then G.setCanvas(previous) else G.setCanvas() end
  if sx then G.setScissor(sx, sy, sw, sh) else G.setScissor() end
  G.pop()
  G.setColor(1, 1, 1, 1)
  if type(zones) == "table" and zones[1] then
    blitSgbZones(canvas, zones)
  else
    G.draw(canvas, 0, 0)
  end
end

local function titleSgbZones(st, S)
  if not st or st.gold or st.crystal then return nil end
  if Generation.isGen2(S) then return nil end
  local okP, P = pcall(require, "src.render.PaletteFX")
  if not (okP and P and P.zone) then return nil end
  local logo2 = namedPal(S, "LOGO2")
  local mew = namedPal(S, "MEWMON")
  if not (logo2 and mew) then return nil end
  if st.yellowLayout then
    return {
      P.zone(logo2, 0, 0, 19, 7),
      P.zone(mew, 0, 8, 19, 17),
      P.zone(logo2, 9, 8, 10, 8),
    }
  end
  local logo1 = namedPal(S, "LOGO1") or logo2
  return {
    P.zone(logo2, 0, 0, 19, 7),
    P.zone(withWhiteOf(logo1, logo2), 0, 8, 19, 9),
    P.zone(mew, 0, 10, 19, 17),
  }
end

-- IntroMovie:sgbPalettes — phase 2 splash / phase 3 fight. Copyright is plain.
local function rbIntroSgbZones(phase, S)
  local okP, P = pcall(require, "src.render.PaletteFX")
  if not (okP and P and P.zone and P.whole) then return nil end
  if phase == 2 then
    local logo = namedPal(S, "GAMEFREAK")
    if not logo then return nil end
    return {
      P.whole(logo),
      P.zone(namedPal(S, "REDMON") or logo, 5, 11, 7, 13),
      P.zone(namedPal(S, "VIRIDIAN") or logo, 8, 11, 9, 13),
      P.zone(namedPal(S, "BLUEMON") or logo, 12, 11, 14, 13),
    }
  elseif phase == 3 then
    local purple = namedPal(S, "PURPLEMON")
    if not purple then return nil end
    local black = namedPal(S, "BLACK") or {
      { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 },
    }
    return {
      P.zone(black, 0, 0, 19, 3),
      P.zone(purple, 0, 4, 19, 13),
      P.zone(black, 0, 14, 19, 17),
    }
  end
  return nil
end

-- YellowIntro: splash delegates to IntroMovie; cinema uses palName + rBGP.
local function yellowIntroSgbZones(st, S)
  local movie = st and st.movie
  if not movie then return nil end
  if movie.pre then
    return rbIntroSgbZones(movie.pre.phase, S)
  end
  local okP, P = pcall(require, "src.render.PaletteFX")
  if not (okP and P and P.whole) then return nil end
  local pal = namedPal(S, movie.palName or "MEWMON")
  if not pal then return nil end
  local bgp = movie.bgp
  if type(bgp) == "number" and P.permute then
    local map = {}
    for i = 0, 3 do
      map[i] = math.floor(bgp / 4 ^ i) % 4
    end
    pal = P.permute(pal, map)
  end
  return { P.whole(pal) }
end

local THEME_DEFAULTS = {
  cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE,
  textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 },
  choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 },
}

local BOOT_DEFAULTS = {
  splash = "IntroMovie", title = "TitleState", newGame = "OakSpeech",
}

-- ---- path / field helpers ----

local function pathOf(v)
  if type(v) == "table" then return tostring(v.path or "") end
  if type(v) == "string" then return v end
  return ""
end

local function dataField(S, key)
  if Generation.isGen2(S) then
    if key == "title" then
      return (S.data and (S.data.title or S.data.gen2Title)) or {}
    elseif key == "intro" then
      return (S.data and (S.data.gen2Intro or S.data.intro)) or {}
    elseif key == "oakSpeech" then
      return (S.data and (S.data.oakSpeech or S.data.gen2OakSpeech)) or {}
    elseif key == "townMap" then
      local L = S.data and (S.data.gen2Landmarks or S.data.landmarks)
      local locs = type(L) == "table" and (L.landmarks or L) or {}
      return { locations = locs }
    elseif key == "theme" then
      return {}
    end
  end
  return (S.data and S.data.field and S.data.field[key]) or {}
end

local function eff(S, bucket, key)
  local p = S.project and S.project[bucket]
  if p ~= nil and p[key] ~= nil then return p[key] end
  return dataField(S, bucket)[key]
end

local function img(S, path)
  if not path or path == "" then return nil end
  return Preview.image(S, path)
end

-- Engine movies read game.input / game.stack. Preview must never skip on click.
local STUB_INPUT = {
  wasPressed = function() return false end,
  isDown = function() return false end,
}
local STUB_STACK = {
  pop = function() end,
  push = function() end,
  clear = function() end,
}

local function stubGame(data, extra)
  local game = {
    data = data or {},
    input = STUB_INPUT,
    stack = STUB_STACK,
    save = {
      player = { name = "RED", id = 1, money = 0,
        playTime = { hours = 0, minutes = 0 } },
      money = 0,
      playTime = 0,
      inventory = {},
      visited = {},
    },
  }
  if type(extra) == "table" then
    for k, v in pairs(extra) do game[k] = v end
  end
  return game
end

local function ensureFont(S)
  if S._uiPreviewFontLoaded then return true end
  if not (S.data and S.data.font) then return false end
  local ok = pcall(function()
    require("src.render.Font").load(S.data)
  end)
  S._uiPreviewFontLoaded = ok
  return ok
end

local function applyTheme(S)
  ensureFont(S)
  local EngTheme = require("src.ui.Theme")
  -- Reset to engine defaults then merge data + project theme.
  EngTheme.cursor = 0xED
  EngTheme.cursorHollow = 0xEC
  EngTheme.moreArrow = 0xEE
  EngTheme.textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 }
  EngTheme.choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 }
  local merged = {}
  local d = dataField(S, "theme")
  local p = (S.project and S.project.theme) or {}
  for k, v in pairs(d) do merged[k] = v end
  for k, v in pairs(p) do
    if type(v) == "table" and type(merged[k]) == "table" then
      local sub = {}
      for sk, sv in pairs(merged[k]) do sub[sk] = sv end
      for sk, sv in pairs(v) do sub[sk] = sv end
      merged[k] = sub
    else
      merged[k] = v
    end
  end
  if next(merged) then
    pcall(function()
      require("src.mods.Merge").deepMerge(EngTheme, merged)
    end)
  end
  return EngTheme
end

local function resolveStr(S, source)
  local p = S.project and S.project.strings and S.project.strings[source]
  if type(p) == "string" and p ~= "" then return p end
  local d = S.data and S.data.strings and S.data.strings[source]
  if type(d) == "string" and d ~= "" then return d end
  return source
end

-- ---- title driver ----

local function crystalTitle(S)
  if Generation.isCrystal(S) then return true end
  return tostring(eff(S, "title", "layout") or "") == "crystal_title"
end

local function frameList(S, key, fallback)
  local out = {}
  local paths = eff(S, "title", key)
  if type(paths) == "table" then
    for i, p in ipairs(paths) do
      out[i] = img(S, pathOf(p))
    end
  end
  if not out[1] and fallback and fallback ~= "" then
    out[1] = img(S, fallback)
  end
  return out
end

local function buildTitle(S)
  local layout = eff(S, "title", "layout")
  local gold = Generation.isGen2(S)
    or layout == "gold_title"
    or layout == "crystal_title"
    or pathOf(eff(S, "title", "hooh")) ~= ""
    or pathOf(eff(S, "title", "screen")) ~= ""
    or pathOf(eff(S, "title", "suicune")) ~= ""

  if gold then
    local logoPath = pathOf(eff(S, "title", "image") or eff(S, "title", "logo"))
    local screenPath = pathOf(eff(S, "title", "screen"))
    local copyPath = pathOf(eff(S, "title", "copyright"))
    if copyPath == "" then copyPath = "assets/generated/title/copyright.png" end

    if crystalTitle(S) then
      if screenPath == "" then
        screenPath = "assets/generated/title/crystal_screen.png"
      end
      local suicunePath = pathOf(eff(S, "title", "suicune"))
      local gemPath = pathOf(eff(S, "title", "gem"))
      local sky = eff(S, "title", "sky")
      if type(sky) ~= "table" or #sky < 3 then
        sky = { 123 / 255, 165 / 255, 255 / 255, 1 }
      end
      return {
        kind = "title",
        gold = true,
        crystal = true,
        screen = img(S, screenPath),
        gem = img(S, gemPath),
        suicuneFrames = frameList(S, "suicuneFrames", suicunePath),
        suicuneX = tonumber(eff(S, "title", "suicuneX")) or 48,
        suicuneY = tonumber(eff(S, "title", "suicuneY")) or 96,
        suicuneEvery = tonumber(eff(S, "title", "suicuneEvery")) or 8,
        suicuneTick = 0,
        suicuneFrame = 1,
        gemX = tonumber(eff(S, "title", "gemX")) or 56,
        gemY = tonumber(eff(S, "title", "gemY")) or 6,
        sky = sky,
        timer = 0,
        data = S.data,
      }
    end

    if logoPath == "" then logoPath = "assets/generated/title/pokemon_logo.png" end
    if screenPath == "" then screenPath = "assets/generated/title/title_screen.png" end
    local hoohPath = pathOf(eff(S, "title", "hooh"))
    if hoohPath == "" then
      local frames = eff(S, "title", "hoohFrames")
      if type(frames) == "table" then hoohPath = pathOf(frames[1]) end
    end
    if hoohPath == "" then hoohPath = "assets/generated/title/hooh.png" end
    local cloudsPath = pathOf(eff(S, "title", "clouds"))
    if cloudsPath == "" then cloudsPath = "assets/generated/title/clouds.png" end
    local hoohFrames = frameList(S, "hoohFrames", hoohPath)
    local sequence = eff(S, "title", "hoohSequence")
    if type(sequence) ~= "table" or #sequence == 0 then
      sequence = { { 1, 10 }, { 2, 9 }, { 3, 10 }, { 4, 10 }, { 3, 9 }, { 5, 10 } }
    end
    return {
      kind = "title",
      gold = true,
      logo = img(S, logoPath),
      screen = img(S, screenPath),
      clouds = img(S, cloudsPath),
      hooh = hoohFrames[1],
      hoohFrames = hoohFrames,
      sequence = sequence,
      seqIndex = 1,
      seqLeft = sequence[1] and sequence[1][2] or 10,
      hoohFrame = sequence[1] and sequence[1][1] or 1,
      hoohPhase = 0,
      copyright = img(S, copyPath),
      hoohX = tonumber(eff(S, "title", "hoohX")) or 48,
      hoohY = tonumber(eff(S, "title", "hoohY")) or 56,
      cloudY = tonumber(eff(S, "title", "cloudY")) or 88,
      timer = 0,
      data = S.data,
    }
  end

  local logoPath = pathOf(eff(S, "title", "logo"))
  if logoPath == "" then logoPath = "assets/logo/pokemon_logo.png" end
  local verPath = pathOf(eff(S, "title", "versionRibbon") or eff(S, "title", "version"))
  if verPath == "" then verPath = "assets/generated/title/red_version.png" end
  local yellow = layout == "yellow_pikachu"
    or Generation.id(S) == "yellow"
  local cycle = eff(S, "title", "cycleSpecies")
  if type(cycle) ~= "table" or #cycle == 0 then
    cycle = yellow and { "PIKACHU" }
      or { "CHARIZARD", "VENUSAUR", "BLASTOISE", "PIKACHU" }
  end
  local pikaPath = pathOf(eff(S, "title", "pikachu"))
  if pikaPath == "" then pikaPath = "assets/generated/title/pikachu.png" end
  local bubblePath = pathOf(eff(S, "title", "pikaBubble"))
  if bubblePath == "" then bubblePath = "assets/generated/title/pika_bubble.png" end

  local st = {
    kind = "title",
    logo = img(S, logoPath),
    version = img(S, verPath),
    player = img(S, "assets/generated/title/player.png"),
    yellow = yellow,
    yellowPikachu = yellow and img(S, pikaPath) or nil,
    yellowBubble = yellow and img(S, bubblePath) or nil,
    eyesHalf = yellow and img(S, "assets/generated/title/eyes_half.png") or nil,
    eyesClosed = yellow and img(S, "assets/generated/title/eyes_closed.png") or nil,
    copyrightText = tostring(eff(S, "title", "copyrightText") or "2026 bois club games"),
    cycleSpecies = cycle,
    cycleIndex = 1,
    sprites = {},
    timer = 0,
    blink = 0,
    slideIn = 0,
    phase = yellow and "drop" or "loop",
    scy = yellow and 0x40 or 0,
    dropStep = 1,
    dropLeft = nil,
    showBubble = not yellow,
    blinkTimer = 0,
    blinkAt = nil,
    data = S.data,
  }
  st.yellowLayout = yellow and st.yellowPikachu ~= nil
  if not st.yellowLayout then
    st.phase = "loop"
    st.showBubble = true
    st.scy = 0
  end
  return st
end

local function titleSprite(st, S)
  local cycle = eff(S, "title", "cycleSpecies")
  if type(cycle) == "table" and #cycle > 0 then
    st.cycleSpecies = cycle
  end
  local n = #(st.cycleSpecies or {})
  if n > 0 then
    st.cycleIndex = ((st.cycleIndex or 1) - 1) % n + 1
  end
  local species = st.cycleSpecies and st.cycleSpecies[st.cycleIndex]
  if not species then return nil end
  local cached = st.sprites[species]
  if cached == nil then
    local path
    local ok, Sprites = pcall(require, "src.pokemon.Sprites")
    if ok and S.data then
      path = select(1, Sprites.path(S.data, species, "front", { kind = "title" }))
    end
    local image = path and img(S, path) or nil
    cached = image or false
    st.sprites[species] = cached
  end
  return cached or nil
end

local function hoohBob(phase)
  local ok, SpriteAnims = pcall(require, "src.ui.gen2.SpriteAnims")
  if ok and SpriteAnims and SpriteAnims.sine then
    local value = SpriteAnims.sine(phase or 0, 2)
    if value >= 0x80 then value = value - 256 end
    return value
  end
  return math.floor(math.sin((phase or 0) * math.pi / 32) * 2 + 0.5)
end

local function updateTitle(st)
  if st.crystal then
    st.timer = (st.timer or 0) + 1
    local every = math.max(1, st.suicuneEvery or 8)
    local c = st.suicuneTick or 0
    st.suicuneTick = (c + 1) % 256
    if c % every == 0 then
      local n = math.max(1, #(st.suicuneFrames or {}))
      st.suicuneFrame = math.floor(c % (every * n) / every) + 1
    end
    return
  end
  if st.gold then
    st.timer = (st.timer or 0) + 1
    st.hoohPhase = ((st.hoohPhase or 0) + 1) % 256
    st.seqLeft = (st.seqLeft or 10) - 1
    if st.seqLeft <= 0 then
      local seq = st.sequence or {}
      st.seqIndex = (st.seqIndex or 1) + 1
      if st.seqIndex > #seq then st.seqIndex = 1 end
      local step = seq[st.seqIndex]
      st.hoohFrame = step and step[1] or 1
      st.seqLeft = step and step[2] or 10
    end
    return
  end
  if st.yellowLayout then
    if st.phase == "drop" then
      local step = DROP_STEPS[st.dropStep]
      if not step then
        st.phase = "settle"
        st.timer = 0
        return
      end
      if st.dropLeft == nil then st.dropLeft = step[2] end
      st.scy = st.scy + step[1]
      st.dropLeft = st.dropLeft - 1
      if st.dropLeft <= 0 then
        st.dropStep = st.dropStep + 1
        st.dropLeft = nil
      end
    elseif st.phase == "settle" then
      st.timer = st.timer + 1
      if st.timer >= 36 then
        st.showBubble = true
        st.phase = "bubble"
        st.timer = 0
      end
    elseif st.phase == "bubble" then
      st.timer = st.timer + 1
      if st.timer >= 3 then
        st.phase = "loop"
        st.blinkTimer = 0
      end
    else
      local t = st.blinkTimer
      st.blinkTimer = (t + 1) % 256
      if t == 0 or t == 0x80 or t == 0x90 then st.blinkAt = 0 end
      if st.blinkAt then
        st.blinkAt = st.blinkAt + 1
        if st.blinkAt > 9 then st.blinkAt = nil end
      end
    end
    return
  end
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 60
  if st.timer >= CYCLE_FRAMES then
    st.timer = 0
    if #st.cycleSpecies > 1 then
      st.cycleIndex = (st.cycleIndex % #st.cycleSpecies) + 1
    end
    st.slideIn = 20
  end
  if st.slideIn and st.slideIn > 0 then st.slideIn = st.slideIn - 1 end
end

local function drawTitleFrame(st, S)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  if st.crystal then
    local sky = st.sky or { 123 / 255, 165 / 255, 1, 1 }
    love.graphics.setColor(sky[1], sky[2], sky[3], 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    love.graphics.setColor(1, 1, 1, 1)
    if st.gem then
      love.graphics.draw(st.gem, st.gemX or 56, st.gemY or 6)
    end
    local frames = st.suicuneFrames
    local suicune = frames and (frames[st.suicuneFrame or 1] or frames[1])
    if suicune then
      love.graphics.draw(suicune, st.suicuneX or 48, st.suicuneY or 96)
    end
    -- Crystal's screen already has the logo and CRYSTAL VERSION wordmark.
    if st.screen then love.graphics.draw(st.screen, 0, 0) end
    return
  end
  if st.gold then
    if st.screen then
      love.graphics.draw(st.screen, 0, 0)
    else
      love.graphics.setColor(123 / 255, 165 / 255, 1, 1)
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if st.clouds then
      local scroll = ((st.timer or 0) / 8) % GB_W
      love.graphics.draw(st.clouds, -scroll, st.cloudY or 88)
      love.graphics.draw(st.clouds, GB_W - scroll, st.cloudY or 88)
    end
    local frames = st.hoohFrames
    local hooh = (frames and frames[st.hoohFrame or 1]) or st.hooh
    if hooh then
      love.graphics.draw(hooh, st.hoohX or 48,
        (st.hoohY or 56) + hoohBob(st.hoohPhase))
    end
    if st.logo then love.graphics.draw(st.logo, 0, 0) end
    if st.copyright then love.graphics.draw(st.copyright, 0, 0) end
    return
  end
  local function body()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    local scrollY = st.yellowLayout and -(st.scy or 0) or 0
    if st.logo then
      love.graphics.draw(st.logo, 16, 8 + scrollY)
    else
      love.graphics.setColor(0.1, 0.1, 0.15, 1)
      love.graphics.rectangle("fill", 24, 16 + scrollY, 112, 40)
    end
    if st.yellowLayout then
      local dy = scrollY
      if st.yellowBubble and st.showBubble then
        love.graphics.draw(st.yellowBubble, 48, 32 + dy)
      end
      if st.yellowPikachu then
        love.graphics.draw(st.yellowPikachu, 32, 64 + dy)
      end
      local overlay
      if st.blinkAt then
        if st.blinkAt <= 3 or st.blinkAt > 6 then
          overlay = st.eyesHalf
        else
          overlay = st.eyesClosed
        end
      end
      if overlay then love.graphics.draw(overlay, 56, 80 + dy) end
    else
      if st.version then
        local iw, ih = st.version:getDimensions()
        local ok, q = pcall(love.graphics.newQuad, 0, 0, math.min(96, iw), math.min(8, ih), iw, ih)
        if ok and q then
          love.graphics.draw(st.version, q, 56, 64)
        else
          love.graphics.draw(st.version, 56, 64)
        end
      end
      local sprite = titleSprite(st, S)
      if sprite then
        local w, h = sprite:getDimensions()
        local slide = (st.slideIn or 0) * 8
        local x = 40 + math.floor((56 - w) / 2) + slide
        local y = 136 - h
        love.graphics.draw(sprite, x, y)
      end
      if st.player then love.graphics.draw(st.player, 82, 80) end
    end
    if ensureFont(S) then
      love.graphics.setColor(0, 0, 0, 1)
      pcall(require("src.render.Font").draw, st.copyrightText, 1, 136 + scrollY)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  local zones = titleSgbZones(st, S)
  if zones then
    presentGbCanvas(st, body, zones)
  else
    body()
  end
end

-- ---- intro driver ----

local function overlayIntro(dst, src)
  if type(src) ~= "table" then return dst end
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      local sub = {}
      for sk, sv in pairs(dst[k]) do sub[sk] = sv end
      overlayIntro(sub, v)
      dst[k] = sub
    else
      dst[k] = v
    end
  end
  return dst
end

-- GoldSilverIntro / CrystalIntro want string paths; extractors often ship
-- { path = "…", width = n, height = n }.
local function flattenActSheets(act)
  if type(act) ~= "table" then return end
  for _, key in ipairs({ "tiles", "sprites", "sprites1" }) do
    local p = pathOf(act[key])
    if p ~= "" then act[key] = p end
  end
end

local function flattenIntroSheets(intro)
  if type(intro) ~= "table" then return intro end
  local copy = overlayIntro({}, intro)
  for _, act in ipairs({ "water", "grass", "fire" }) do
    flattenActSheets(copy[act])
  end
  if type(copy.acts) == "table" then
    for _, act in pairs(copy.acts) do flattenActSheets(act) end
  end
  local grass = pathOf(copy.grassFrames)
  if grass ~= "" then copy.grassFrames = grass end
  return copy
end

local function nestedPath(t, ...)
  local cur = t
  for i = 1, select("#", ...) do
    if type(cur) ~= "table" then return "" end
    cur = cur[select(i, ...)]
  end
  return pathOf(cur)
end

-- Tile atlases are not screens. Drive the Gen2 cinema with the engine movie
-- so Unown / Suicune (Crystal) and water / grass / fire (GS) actually compose.
local function isCrystalIntro(S, intro)
  if Generation.isCrystal(S) then return true end
  if type(intro) ~= "table" then return false end
  if tostring(intro.layout or "") == "crystal" then return true end
  return type(intro.acts) == "table"
end

local function introCinemaSheets(S, intro)
  local sheets = {}
  local function add(label, ...)
    local p = nestedPath(intro, ...)
    if p == "" then return end
    local image = img(S, p)
    if image then sheets[#sheets + 1] = { label = label, image = image } end
  end
  if isCrystalIntro(S, intro) then
    add("Unowns", "acts", "unownA", "tiles")
    add("Pulse", "acts", "unownA", "sprites")
    add("Background", "acts", "background", "tiles")
    add("Suicune", "acts", "background", "sprites")
    add("Pichu", "acts", "background", "sprites1")
    add("Jump", "acts", "suicuneJump", "tiles")
    add("Close", "acts", "suicuneClose", "tiles")
    add("Back", "acts", "suicuneBack", "tiles")
    add("Crystal", "acts", "crystalUnowns", "tiles")
    add("Grass", "grassFrames")
  elseif Generation.isGen2(S) then
    add("Water tiles", "water", "tiles")
    add("Water sprites", "water", "sprites")
    add("Grass tiles", "grass", "tiles")
    add("Grass sprites", "grass", "sprites")
    add("Fire tiles", "fire", "tiles")
    add("Fire sprites", "fire", "sprites")
  end
  return sheets
end

local function buildGen2IntroMovie(S, intro)
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  local sheets = flattenIntroSheets(intro)
  local crystal = isCrystalIntro(S, sheets)
  local mod = crystal and "src.ui.gen2.CrystalIntro" or "src.ui.gen2.GoldSilverIntro"
  local ok, Intro = pcall(require, mod)
  if not (ok and Intro and type(Intro.new) == "function") then return nil end
  -- No input: editor clicks must not skip. No audio.runtime: music stays off.
  local palettes = S.data and (S.data.gen2Palettes or S.data.palettes)
  local game = stubGame({ gen2Intro = sheets, gen2Palettes = palettes })
  local movie
  ok, movie = pcall(Intro.new, game, { intro = sheets })
  if not (ok and movie) then return nil end
  pcall(function() movie:enter() end)
  return movie
end

local function applyYellowAtlases(S, movie, intro)
  if not movie then return end
  local y = type(intro.yellowIntro) == "table" and intro.yellowIntro or {}
  local function load(key, fallback)
    local p = pathOf(y[key])
    if p == "" then p = fallback end
    return img(S, p)
  end
  local a1 = load("atlas1", "assets/generated/intro/yellow_intro_1.png")
  local a2 = load("atlas2", "assets/generated/intro/yellow_intro_2.png")
  local clouds = load("clouds", "assets/generated/intro/clouds.png")
  if a1 then movie.atlas1 = a1 end
  if a2 then movie.atlas2 = a2 end
  if clouds then movie.clouds = clouds end
  movie.quads = {}
  movie.bgDirty = true
end

local function buildYellowIntroMovie(S, intro)
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  local ok, YellowIntro = pcall(require, "src.ui.YellowIntro")
  if not (ok and YellowIntro and type(YellowIntro.new) == "function") then
    return nil
  end
  local title = {}
  overlayIntro(title, dataField(S, "title"))
  overlayIntro(title, (S.project and S.project.title) or {})
  local game = stubGame({ field = { intro = intro, title = title } })
  local movie
  ok, movie = pcall(YellowIntro.new, game, nil)
  if not (ok and movie) then return nil end
  applyYellowAtlases(S, movie, intro)
  pcall(function() movie:enter() end)
  return movie
end

local function drawFitted(image, x, y, w, h)
  if not image then return false end
  local ok, iw, ih = pcall(function() return image:getDimensions() end)
  if not (ok and iw and ih and iw > 0 and ih > 0) then return false end
  local sc = math.min(w / iw, h / ih)
  love.graphics.draw(image, x + (w - iw * sc) / 2, y + (h - ih * sc) / 2, 0, sc, sc)
  return true
end

local function buildIntro(S)
  local intro = {}
  local d = dataField(S, "intro")
  local p = (S.project and S.project.intro) or {}
  overlayIntro(intro, d)
  overlayIntro(intro, p)
  local studio = {}
  if type(d.studio) == "table" then
    for k, v in pairs(d.studio) do studio[k] = v end
  end
  if type(p.studio) == "table" then
    for k, v in pairs(p.studio) do studio[k] = v end
  end
  local logoPath = pathOf(studio.logo)
  if logoPath == "" then logoPath = "assets/logo/minilogo.png" end
  local studioLogo = img(S, logoPath)
  local studioScale, studioX, studioY = 1, 40, 40
  if studioLogo then
    local iw, ih = studioLogo:getDimensions()
    studioScale = math.min(STUDIO_BOX.w / iw, STUDIO_BOX.h / ih)
    studioX = STUDIO_BOX.cx - iw * studioScale / 2
    studioY = STUDIO_BOX.cy - ih * studioScale / 2
  end
  local function frameImg(bucket, key)
    local e = intro[bucket]
    if type(e) == "table" then return img(S, pathOf(e[key])) end
    return nil
  end
  local cinema = introCinemaSheets(S, intro)
  if Generation.isGen2(S) then
    local movie = buildGen2IntroMovie(S, intro)
    if movie then
      return { kind = "movie", movie = movie, done = false }
    end
    return {
      kind = "cinema",
      sheets = cinema,
      index = 1,
      timer = 0,
      done = false,
    }
  end
  if Generation.id(S) == "yellow" then
    local movie = buildYellowIntroMovie(S, intro)
    if movie then
      return {
        kind = "movie",
        movie = movie,
        done = false,
        sgbZonesFn = function(st)
          return yellowIntroSgbZones(st, S)
        end,
      }
    end
    local yellowSheets = {}
    local y = type(intro.yellowIntro) == "table" and intro.yellowIntro or {}
    local function addY(label, key, fallback)
      local p = pathOf(y[key])
      if p == "" then p = fallback end
      local image = img(S, p)
      if image then
        yellowSheets[#yellowSheets + 1] = { label = label, image = image }
      end
    end
    addY("Atlas 1", "atlas1", "assets/generated/intro/yellow_intro_1.png")
    addY("Atlas 2", "atlas2", "assets/generated/intro/yellow_intro_2.png")
    addY("Clouds", "clouds", "assets/generated/intro/clouds.png")
    return {
      kind = "cinema",
      sheets = yellowSheets,
      index = 1,
      timer = 0,
      done = false,
    }
  end
  return {
    kind = "intro",
    skipAll = intro.skip and true or false,
    studio = studio,
    studioLogo = studioLogo,
    studioScale = studioScale,
    studioX = studioX,
    studioY = studioY,
    logo = img(S, pathOf(intro.gamefreakLogo)),
    bigStar = img(S, pathOf(intro.bigStar)),
    smallStar = img(S, pathOf(intro.fallingStar)),
    smallStarBlink = img(S, pathOf(intro.fallingStarBlink)),
    gengarFrames = {
      frameImg("gengar", "frame1"),
      frameImg("gengar", "frame2"),
      frameImg("gengar", "frame3"),
    },
    nidoFrames = {
      frameImg("nidorino", "frame1"),
      frameImg("nidorino", "frame2"),
      frameImg("nidorino", "frame3"),
    },
    phase = 1,
    timer = 0,
    gengarX = 104,
    gengarY = 56,
    nidoX = -8,
    nidoY = 72,
    gengarPose = 1,
    nidoFrame = 1,
    fade = 0,
    fightTick = 0,
  }
end

local function drawBars()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 32)
  love.graphics.rectangle("fill", 0, 112, 160, 32)
  love.graphics.setColor(1, 1, 1, 1)
end

local function updateIntro(st)
  if st.kind == "movie" then
    local movie = st.movie
    if movie and movie.update then
      pcall(movie.update, movie, 0)
      st.done = movie.done == true or movie.finished == true
    else
      st.done = true
    end
    return
  end
  if st.kind == "cinema" then
    st.timer = (st.timer or 0) + 1
    local n = math.max(1, #(st.sheets or {}))
    if st.timer >= 90 then
      st.timer = 0
      st.index = (st.index or 1) + 1
      if st.index > n then
        st.index = 1
        st.done = true
      end
    end
    return
  end
  if st.skipAll then
    st.phase = 2
    st.timer = STAR_START
    st.skipAll = false
  end
  st.timer = st.timer + 1
  if st.phase == 1 then
    if st.timer >= COPYRIGHT_FRAMES then
      st.phase = 2
      st.timer = 0
    end
  elseif st.phase == 2 then
    if st.timer >= SPLASH_FRAMES then
      st.phase = 3
      st.timer = 0
      st.gengarX, st.gengarY = 104, 56
      st.nidoX, st.nidoY = -8, 72
      st.gengarPose, st.nidoFrame = 1, 1
      st.fade = 0
      st.fightTick = 0
    end
  else
    -- Simplified fight scroll: gengar left / nido right, then fade.
    st.fightTick = st.fightTick + 1
    if st.fightTick < 80 then
      if st.fightTick % 2 == 0 then
        st.gengarX = st.gengarX - 2
        st.nidoX = st.nidoX + 2
      end
    elseif st.fightTick < 140 then
      st.nidoFrame = 1 + math.floor((st.fightTick / 10) % 3)
      st.gengarPose = 1 + math.floor((st.fightTick / 16) % 3)
    else
      st.fade = math.min(1, (st.fightTick - 140) / 24)
      if st.fightTick >= 170 then
        st.done = true
      end
    end
  end
end

-- CrystalIntro / GoldSilverIntro bake layers into canvases. LOVE scissors
-- stay in screen space across setCanvas, so the editor clip would empty
-- those layers. Render at identity with scissor off, then blit here.
-- YellowIntro / Credits / TownMap / TrainerCard use draw() the same way.
local function movieSgbZones(st)
  if type(st.sgbZonesFn) == "function" then
    local ok, z = pcall(st.sgbZonesFn, st)
    if ok and type(z) == "table" and z[1] then return z end
  end
  if type(st.sgbZones) == "table" and st.sgbZones[1] then
    return st.sgbZones
  end
  local movie = st.movie
  if not (movie and movie.sgbPalettes) then return nil end
  local ok, zones = pcall(movie.sgbPalettes, movie, movie.game)
  if ok and type(zones) == "table" and zones[1] then return zones end
  return nil
end

local function drawMoviePanel(st)
  local movie = st.movie
  local drawFn = movie and (movie.drawPanel or movie.draw)
  if not (movie and drawFn) then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  presentGbCanvas(st, function()
    pcall(drawFn, movie)
  end, movieSgbZones(st))
end

local function drawIntroFrame(st, S)
  if st.kind == "movie" then
    drawMoviePanel(st)
    return
  end
  if st.kind == "cinema" then
    local function body()
      love.graphics.setColor(0.08, 0.1, 0.16, 1)
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
      love.graphics.setColor(1, 1, 1, 1)
      local sheet = st.sheets and st.sheets[st.index or 1]
      if sheet and sheet.image then
        drawFitted(sheet.image, 0, 8, GB_W, GB_H - 16)
      end
    end
    local zones
    if not Generation.isGen2(S) then
      local pal = namedPal(S, "MEWMON")
      local okP, P = pcall(require, "src.render.PaletteFX")
      if pal and okP and P and P.whole then
        zones = { P.whole(pal) }
      end
    end
    if zones then
      presentGbCanvas(st, body, zones)
    else
      body()
    end
    return
  end
  local function body()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    if st.phase == 1 then
      love.graphics.setColor(0, 0, 0, 1)
      local credit = tostring(st.studio.credit or "bois club")
      if ensureFont(S) then
        local Font = require("src.render.Font")
        pcall(Font.draw, "2026", (160 - 4 * 8) / 2, 48)
        pcall(Font.draw, credit, math.max(0, (160 - #credit * 8) / 2), 64)
      else
        love.graphics.print(credit, 40, 64)
      end
    elseif st.phase == 2 then
      local t = st.timer
      if t >= STAR_START then
        local flashing = t >= FLASH_START and t < FLASH_START + FLASH_FRAMES
        local dim = flashing and math.floor((t - FLASH_START) / 5) % 2 == 0
        love.graphics.setColor(1, 1, 1, dim and 0.35 or 1)
        if st.studioLogo then
          love.graphics.draw(st.studioLogo, st.studioX, st.studioY,
            0, st.studioScale, st.studioScale)
        elseif st.logo then
          love.graphics.draw(st.logo, 72, 56)
        end
        love.graphics.setColor(1, 1, 1, 1)
      end
      if t >= STAR_START and t < FLASH_START then
        local n = t - STAR_START + 1
        local sx, sy = 152 - 4 * n, -16 + 4 * n
        if st.bigStar then
          love.graphics.draw(st.bigStar, sx, sy)
        else
          love.graphics.setColor(0.2, 0.2, 0.25, 1)
          love.graphics.rectangle("fill", sx + 6, sy + 6, 4, 4)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end
      if t >= WAVES_START then
        local substep = math.floor((math.min(t, WAVES_END) - WAVES_START) / 3)
        local blink = substep % 2 == 0
        for w, xs in ipairs(STAR_WAVES) do
          local spawn = (w - 1) * 8
          if substep >= spawn then
            local y = 88 + (substep - spawn)
            if y < 144 then
              local starImg = blink and st.smallStar
                or (st.smallStarBlink or st.smallStar)
              for _, x in ipairs(xs) do
                if starImg then
                  love.graphics.draw(starImg, x, y)
                else
                  love.graphics.setColor(0.15, 0.15, 0.2, 1)
                  love.graphics.rectangle("fill", x + 3, y + 1, 2, 2)
                  love.graphics.setColor(1, 1, 1, 1)
                end
              end
            end
          end
        end
      end
      drawBars()
    else
      local yellow = st.yellowSheets
      if type(yellow) == "table" and #yellow > 0 then
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
        love.graphics.setColor(1, 1, 1, 1)
        local idx = 1 + math.floor((st.fightTick or 0) / 40) % #yellow
        local sheet = yellow[idx]
        if sheet and sheet.image then
          drawFitted(sheet.image, 0, 8, GB_W, GB_H - 16)
        end
      else
        local nido = st.nidoFrames[st.nidoFrame]
        local gengar = st.gengarFrames[st.gengarPose]
        if nido then love.graphics.draw(nido, st.nidoX, st.nidoY) end
        if gengar then love.graphics.draw(gengar, st.gengarX, st.gengarY) end
        if not nido and not gengar then
          love.graphics.setColor(0.45, 0.25, 0.55, 1)
          love.graphics.rectangle("fill", st.gengarX, st.gengarY, 56, 56)
          love.graphics.setColor(0.75, 0.35, 0.4, 1)
          love.graphics.rectangle("fill", st.nidoX, st.nidoY, 48, 48)
        end
      end
      drawBars()
      if st.fade > 0 then
        love.graphics.setColor(1, 1, 1, math.min(1, st.fade))
        love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  local zones = rbIntroSgbZones(st.phase, S)
  if zones then
    presentGbCanvas(st, body, zones)
  else
    body()
  end
end

-- ---- Oak speech preview ----

local OAK_HOLD = 180
local OAK_FADE = 24

local OAK_BEATS_GEN1 = {
  { label = "Welcome", pic = "oak", key = "_OakSpeechText1" },
  { label = "This world", pic = "demo", key = "_OakSpeechText2A" },
  { label = "Pets / fights", pic = "demo", key = "_OakSpeechText2B" },
  { label = "Your name?", pic = "player", key = "_IntroducePlayerText" },
  { label = "Confirm name", pic = "player", key = "_YourNameIsText" },
  { label = "Rival intro", pic = "rival", key = "_IntroduceRivalText" },
  { label = "Confirm rival", pic = "rival", key = "_HisNameIsText" },
  { label = "Legend", pic = "player", key = "_OakSpeechText3" },
  { label = "Shrink 1", pic = "shrink1" },
  { label = "Shrink 2", pic = "shrink2" },
}

local OAK_BEATS_GEN2 = {
  { label = "Welcome", pic = "oak", key = "_OakText1" },
  { label = "This world", pic = "demo", key = "_OakText2" },
  { label = "Live together", pic = "demo", key = "_OakText4" },
  { label = "Mysteries", pic = "oak", key = "_OakText5" },
  { label = "Your name?", pic = "player", key = "_OakText6" },
  { label = "Legend", pic = "player", key = "_OakText7" },
  { label = "Shrink 1", pic = "shrink1" },
  { label = "Shrink 2", pic = "shrink2" },
}

local function oakSpeechMerged(S)
  local speech = {}
  overlayIntro(speech, dataField(S, "oakSpeech"))
  overlayIntro(speech, (S.project and S.project.oakSpeech) or {})
  return speech
end

-- Engine OakSpeech FALLBACKS (local in src/ui/OakSpeech.lua / gen2/OakSpeech.lua).
local OAK_TEXT_FALLBACK = {
  _OakSpeechText1 = "Hello there!\nWelcome to the\vworld of POKéMON!\fMy name is OAK!\nPeople call me\vthe POKéMON PROF!",
  _OakSpeechText2A = "This world is\ninhabited by\vcreatures called\vPOKéMON!",
  _OakSpeechText2B = "\fFor some people,\nPOKéMON are\vpets. Others use\vthem for fights.\fMyself...\fI study POKéMON\nas a profession.",
  _OakSpeechText3 = "{PLAYER}!\fYour very own\nPOKéMON legend is\vabout to unfold!\fA world of dreams\nand adventures\vwith POKéMON\vawaits! Let's go!",
  _IntroducePlayerText = "First, what is\nyour name?",
  _IntroduceRivalText = "This is my grand-\nson. He's been\vyour rival since\vyou were a baby.\f...Erm, what is\nhis name again?",
  _YourNameIsText = "Right! So your\nname is {PLAYER}!",
  _HisNameIsText = "That's right! I\nremember now! His\vname is {RIVAL}!",
  _OakText1 = "Hello! Sorry to\nkeep you waiting!\fWelcome to the\nworld of POKéMON!\fMy name is OAK.\fPeople call me the\nPOKéMON PROF.",
  _OakText2 = "This world is in-\nhabited by crea-\vtures that we call\vPOKéMON.",
  _OakText4 = "People and POKéMON\nlive together by\fsupporting each\nother.\fSome people play\nwith POKéMON, some\vbattle with them.",
  _OakText5 = "But we don't know\neverything about\vPOKéMON yet.\fThere are still\nmany mysteries to\vsolve.\fThat's why I study\nPOKéMON every day.",
  _OakText6 = "Now, what did you\nsay your name was?",
  _OakText7 = "{PLAYER}, are you\nready?\fYour very own\nPOKéMON story is\vabout to unfold.\fYou'll face fun\ntimes and tough\vchallenges.\fA world of dreams\nand adventures\fwith POKéMON\nawaits! Let's go!\fI'll be seeing you\nlater!",
}

local function coerceOakText(v)
  if type(v) == "string" then return v end
  if type(v) == "table" and type(v.source) == "string" then return v.source end
  return nil
end

local function oakSpeechText(S, speech, key)
  if not key then return "" end
  local p = S.project and S.project.oakSpeech
  if type(p) == "table" then
    local body = coerceOakText(type(p.text) == "table" and p.text[key])
    if body then return body end
  end
  local body = coerceOakText(S.project and S.project.text and S.project.text[key])
  if body then return body end
  body = coerceOakText(type(speech.text) == "table" and speech.text[key])
  if body then return body end
  body = coerceOakText(S.data and S.data.text and S.data.text[key])
  if body then return body end
  local ok, CommonText = pcall(require, "src.core.gen2.CommonText")
  if ok and CommonText and CommonText.get then
    body = coerceOakText(CommonText.get(S.data and S.data.text, key))
    if body then return body end
  end
  return OAK_TEXT_FALLBACK[key] or ""
end

local function oakPages(body, player, rival)
  body = tostring(body or "")
  body = body:gsub("{PLAYER}", player):gsub("{RIVAL}", rival)
  if body == "" then return {} end
  local okPaginate, TextBox = pcall(require, "src.render.TextBox")
  if okPaginate and TextBox and TextBox.paginate then
    local ok, result = pcall(TextBox.paginate, body, 18)
    if ok and type(result) == "table" and #result > 0 then
      local pages = {}
      for _, page in ipairs(result) do
        if type(page) == "table" and #page > 0 then
          local i = 1
          while i <= #page do
            if page[i + 1] then
              pages[#pages + 1] = { page[i], page[i + 1] }
              i = i + 2
            else
              pages[#pages + 1] = { page[i] }
              i = i + 1
            end
          end
        end
      end
      if #pages > 0 then return pages end
    end
  end
  local pages = {}
  for chunk in (body .. "\f"):gmatch("(.-)\f") do
    if chunk ~= "" then
      local lines = {}
      chunk = chunk:gsub("\v", "\n")
      for line in (chunk .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
      end
      while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
      if #lines > 0 then pages[#pages + 1] = lines end
    end
  end
  return pages
end

local function oakSpritePath(S, species)
  local ok, Sprites = pcall(require, "src.pokemon.Sprites")
  if not (ok and Sprites and Sprites.path) then return "" end
  local path
  ok, path = pcall(Sprites.path, S.data, species, "front", { kind = "oak" })
  return ok and pathOf(path) or ""
end

local function oakPlayerPath(S, speech)
  local p = pathOf(speech.playerPic)
  if p ~= "" then return p end
  local ok, Sprites = pcall(require, "src.pokemon.Sprites")
  if ok and Sprites and Sprites.playerPath then
    local path
    ok, path = pcall(Sprites.playerPath, S.data, "front", { kind = "intro" })
    if ok then
      p = pathOf(path)
      if p ~= "" then return p end
    end
  end
  if Generation.isGen2(S) then return "assets/generated/intro/cal.png" end
  return ""
end

local function oakTrainerPic(S, id)
  local trainers = S.data and S.data.trainers
  local rec = trainers and trainers[id]
  return img(S, pathOf(rec and rec.pic))
end

local function oakColors(S, kind, species)
  if not Generation.isGen2(S) then return nil end
  local ok, Palettes = pcall(require, "src.world.gen2.Palettes")
  if not (ok and Palettes) then return nil end
  local pals = S.data and (S.data.gen2Palettes or S.data.palettes)
  if kind == "oak" and Palettes.trainerColors then
    local c
    ok, c = pcall(Palettes.trainerColors, pals, "POKEMON_PROF")
    return ok and c or nil
  end
  if kind == "player" and Palettes.trainerColors then
    local c
    ok, c = pcall(Palettes.trainerColors, pals, "CAL")
    return ok and c or nil
  end
  if kind == "demo" and Palettes.monColors then
    local c
    ok, c = pcall(Palettes.monColors, pals, species)
    return ok and c or nil
  end
  return nil
end

-- Vanilla oak_speech.lua ships marillPic (wooper.png) next to demoSpecies.
-- A species pick must win over that leftover pic unless the project set its own.
local function oakDemoPath(S, speech, demoSpecies)
  local owned = (S.project and S.project.oakSpeech) or {}
  local demoPath = pathOf(owned.marillPic)
  if demoPath == "" then demoPath = pathOf(owned.demoPic) end
  if demoPath == "" then demoPath = oakSpritePath(S, demoSpecies) end
  if demoPath == "" then
    demoPath = pathOf(speech.marillPic)
    if demoPath == "" then demoPath = pathOf(speech.demoPic) end
  end
  return demoPath
end

local function oakVisuals(S)
  local speech = oakSpeechMerged(S)
  local gen2 = Generation.isGen2(S)
  local playerName = gen2 and "GOLD" or "RED"
  local rivalName = "BLUE"
  local demoSpecies = tostring(speech.demoSpecies or (gen2 and "MARILL" or "NIDORINO"))
  local oakPath = pathOf(speech.oakPic)
  if oakPath == "" and gen2 then oakPath = "assets/generated/intro/oak.png" end
  local demoPath = oakDemoPath(S, speech, demoSpecies)
  local rivalPath = pathOf(speech.rivalPic)
  return {
    speech = speech,
    gen2 = gen2,
    playerName = playerName,
    rivalName = rivalName,
    pics = {
      oak = img(S, oakPath) or oakTrainerPic(S, "OPP_PROF_OAK"),
      demo = img(S, demoPath),
      player = img(S, oakPlayerPath(S, speech)),
      rival = img(S, rivalPath) or oakTrainerPic(S, "OPP_RIVAL1"),
      shrink1 = img(S, pathOf(speech.shrink1) ~= ""
        and pathOf(speech.shrink1) or "assets/generated/intro/shrink1.png"),
      shrink2 = img(S, pathOf(speech.shrink2) ~= ""
        and pathOf(speech.shrink2) or "assets/generated/intro/shrink2.png"),
    },
    colors = {
      oak = oakColors(S, "oak"),
      demo = oakColors(S, "demo", demoSpecies),
      player = oakColors(S, "player"),
    },
  }
end

local function syncOakBeats(st, S)
  if not (st and st.beats) then return end
  local v = oakVisuals(S)
  local rows = v.gen2 and OAK_BEATS_GEN2 or OAK_BEATS_GEN1
  for i, beat in ipairs(st.beats) do
    local row = rows[i]
    if not row then break end
    beat.key = row.key
    beat.image = v.pics[row.pic]
    beat.colors = v.colors[row.pic]
    beat.pages = oakPages(oakSpeechText(S, v.speech, row.key),
      v.playerName, v.rivalName)
  end
  local beat = st.beats[st.index or 1]
  local nPages = math.max(1, beat and beat.pages and #beat.pages or 1)
  if (st.page or 1) > nPages then st.page = nPages end
end

local function buildOak(S)
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  local gen2 = Generation.isGen2(S)
  local rows = gen2 and OAK_BEATS_GEN2 or OAK_BEATS_GEN1
  local beats = {}
  for i, row in ipairs(rows) do
    beats[i] = { label = row.label, key = row.key, pic = row.pic }
  end
  local st = {
    kind = "oak",
    beats = beats,
    index = 1,
    page = 1,
    timer = 0,
    done = false,
  }
  syncOakBeats(st, S)
  return st
end

local function updateOak(st, S)
  syncOakBeats(st, S)
  st.timer = (st.timer or 0) + 1
  local beat = st.beats and st.beats[st.index or 1]
  local nPages = math.max(1, beat and beat.pages and #beat.pages or 1)
  if st.timer < OAK_HOLD then return end
  st.timer = 0
  st.page = (st.page or 1) + 1
  if st.page <= nPages then return end
  st.page = 1
  st.index = (st.index or 1) + 1
  if st.index > #(st.beats or {}) then
    st.index = 1
    st.done = true
  end
end

local function drawOakPic(image, colors, alpha)
  if not image then return end
  local ok, iw, ih = pcall(function() return image:getDimensions() end)
  if not (ok and iw and ih) then return end
  local x = 48 + math.floor((8 - iw / 8) / 2) * 8
  local y = 32 + (7 - ih / 8) * 8
  local G = love.graphics
  G.setColor(1, 1, 1, alpha)
  local function body()
    G.draw(image, x, y)
  end
  local palOk, GbcPalette = pcall(require, "src.render.GbcPalette")
  if palOk and colors and GbcPalette.available and GbcPalette.available() then
    if not pcall(GbcPalette.with, colors, body) then body() end
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

local function drawOakFrame(st, S)
  syncOakBeats(st, S)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local beat = st.beats and st.beats[st.index or 1]
  local alpha = 1
  if (st.timer or 0) < OAK_FADE then
    alpha = math.max(0, (st.timer or 0) / OAK_FADE)
  end
  if beat then
    drawOakPic(beat.image, beat.colors, alpha)
  end
  -- Pic palettes must not leak onto the box (white fill + black glyphs).
  if love.graphics.setShader then pcall(love.graphics.setShader) end
  local pages = beat and beat.pages
  local lines = pages and pages[st.page or 1]
  -- OakSpeech itself only draws the pic; TextBox on the stack draws the
  -- dialogue. Shrink beats have no key. Every say beat gets a box.
  if beat and beat.key then
    applyTheme(S)
    local tb = THEME_DEFAULTS.textBox
    local okTheme, EngTheme = pcall(require, "src.ui.Theme")
    if okTheme and EngTheme and EngTheme.textBox then
      tb = EngTheme.textBox
    end
    local tw = tonumber(tb.tw) or 20
    local th = tonumber(tb.th) or 6
    local ty = tonumber(tb.ty) or 12
    local line1 = (lines and lines[1]) or ""
    local line2 = (lines and lines[2]) or ""
    if ensureFont(S) then
      local Font = require("src.render.Font")
      love.graphics.setColor(1, 1, 1, 1)
      pcall(Font.drawBox, 0, ty, tw, th)
      love.graphics.setColor(0, 0, 0, 1)
      pcall(Font.draw, line1, 8, ty * 8 + 16)
      pcall(Font.draw, line2, 8, ty * 8 + 32)
    else
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, ty * 8, tw * 8, th * 8)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", 0.5, ty * 8 + 0.5, tw * 8 - 1, th * 8 - 1)
      if love.graphics.print then
        love.graphics.print(line1, 8, ty * 8 + 16)
        love.graphics.print(line2, 8, ty * 8 + 32)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- theme / fonts / strings / townmap / badges / boot ----

local function buildTheme(S)
  local eng = applyTheme(S)
  return {
    kind = "theme",
    eng = eng,
    blink = 0,
    timer = 0,
  }
end

local function updateTheme(st)
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 40
end

local function drawThemeFrame(st, S)
  love.graphics.setColor(0.55, 0.7, 0.45, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local eng = st.eng or applyTheme(S)
  local tb = eng.textBox or THEME_DEFAULTS.textBox
  local cb = eng.choiceBox or THEME_DEFAULTS.choiceBox
  if ensureFont(S) then
    local Font = require("src.render.Font")
    love.graphics.setColor(1, 1, 1, 1)
    pcall(Font.drawBox, tb.tx, tb.ty, tb.tw, tb.th)
    pcall(Font.drawBox, cb.tx, cb.ty, cb.tw, cb.th)
    love.graphics.setColor(0, 0, 0, 1)
    pcall(Font.draw, resolveStr(S, "YES"), (cb.tx + 2) * 8, (cb.ty + 1) * 8)
    pcall(Font.draw, resolveStr(S, "NO"), (cb.tx + 2) * 8, (cb.ty + 3) * 8)
    pcall(Font.draw, "Hello!", (tb.tx + 1) * 8, (tb.ty + 2) * 8)
    local cursor = eng.cursor or THEME_DEFAULTS.cursor
    local hollow = eng.cursorHollow or THEME_DEFAULTS.cursorHollow
    local code = (st.blink < 20) and cursor or hollow
    pcall(Font.drawCode, code, (cb.tx + 1) * 8, (cb.ty + 1) * 8)
  else
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("line", tb.tx * 8, tb.ty * 8, tb.tw * 8, tb.th * 8)
    love.graphics.setColor(1, 0.8, 0.3, 0.9)
    love.graphics.rectangle("line", cb.tx * 8, cb.ty * 8, cb.tw * 8, cb.th * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function buildFonts(S)
  local pages = (S.data and S.data.font and S.data.font.pages) or {}
  local proj = (S.project and S.project.font) or {}
  local id = S.uiFontId
  local rec = (id and proj[id]) or (id and pages[id]) or nil
  if not rec then
    for k, v in pairs(proj) do id, rec = k, v; break end
  end
  if not rec then
    for k, v in pairs(pages) do id, rec = k, v; break end
  end
  return {
    kind = "fonts",
    id = id,
    image = rec and img(S, rec.image) or nil,
    scroll = 0,
    timer = 0,
  }
end

local function updateFonts(st)
  st.timer = st.timer + 1
  if st.image then
    local ih = st.image:getHeight()
    if ih > GB_H then
      st.scroll = (st.timer / 2) % (ih - GB_H + 1)
    end
  end
end

local function drawFontsFrame(st)
  love.graphics.setColor(0.08, 0.1, 0.16, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  if st.image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(st.image, 0, -math.floor(st.scroll or 0))
  else
    love.graphics.setColor(1, 1, 1, 0.4)
  end
end

local function buildStrings(S)
  local source = S.uiStrId or "CONTINUE"
  return {
    kind = "strings",
    source = source,
    text = resolveStr(S, source),
    blink = 0,
    timer = 0,
  }
end

local function updateStrings(st)
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 40
end

local function drawStringsFrame(st, S)
  love.graphics.setColor(0.55, 0.7, 0.45, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  applyTheme(S)
  local text = tostring(st.text or "")
  text = text:gsub("{PLAYER}", "RED"):gsub("{RIVAL}", "BLUE")
  text = text:gsub("%%s", "PIKACHU")
  local lines = {}
  for line in (text .. "\n"):gsub("\r\n", "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then lines[1] = text end
  if ensureFont(S) then
    local Font = require("src.render.Font")
    local EngTheme = require("src.ui.Theme")
    local tb = EngTheme.textBox or THEME_DEFAULTS.textBox
    local tw = tonumber(tb.tw) or 20
    local th = tonumber(tb.th) or 6
    local ty = tonumber(tb.ty) or 12
    love.graphics.setColor(1, 1, 1, 1)
    pcall(Font.drawBox, 0, ty, tw, th)
    love.graphics.setColor(0, 0, 0, 1)
    pcall(Font.draw, lines[1] or "", 8, ty * 8 + 16)
    pcall(Font.draw, lines[2] or "", 8, ty * 8 + 32)
    if st.blink < 20 then
      pcall(Font.drawCode, EngTheme.moreArrow or 0xEE, (tw - 2) * 8, (ty + th - 1) * 8 - 4)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Pokegear region: KANTO_LANDMARK = 46; index 94 is Fast Ship (Johto map).
local function pokegearRegion(index, override)
  if override == "johto" or override == "kanto" then return override end
  index = tonumber(index) or 0
  if index == 94 then return "johto" end
  if index >= 46 then return "kanto" end
  return "johto"
end

local function townMapLocs(S)
  local tm = {}
  local d = dataField(S, "townMap")
  local p = (S.project and S.project.townMap) or {}
  for k, v in pairs(d) do tm[k] = v end
  for k, v in pairs(p) do tm[k] = v end
  local locs = {}
  local src = tm.locations or {}
  for id, e in pairs(src) do
    if type(e) == "table" then
      locs[#locs + 1] = {
        id = id, x = e.x or 0, y = e.y or 0,
        name = e.name or id, index = e.index,
      }
    end
  end
  table.sort(locs, function(a, b) return a.id < b.id end)
  return locs, tm
end

local function mergedTownMap(S)
  local tm = {}
  overlayIntro(tm, dataField(S, "townMap"))
  overlayIntro(tm, (S.project and S.project.townMap) or {})
  local dataBg = dataField(S, "townMap").background
  if type(tm.background) == "string" then
    local bg = {}
    if type(dataBg) == "table" then
      for k, v in pairs(dataBg) do bg[k] = v end
    end
    bg.tiles = { path = tm.background }
    tm.background = bg
  elseif type(tm.background) == "table" then
    local bg = {}
    if type(dataBg) == "table" then
      for k, v in pairs(dataBg) do bg[k] = v end
    end
    overlayIntro(bg, tm.background)
    local tilesPath = pathOf(bg.tiles)
    if tilesPath ~= "" and type(bg.tiles) ~= "table" then
      bg.tiles = { path = tilesPath }
    elseif type(bg.tiles) == "table" and tilesPath ~= "" then
      bg.tiles.path = tilesPath
    end
    local cursorPath = pathOf(bg.cursor)
    if cursorPath ~= "" and type(bg.cursor) ~= "table" then
      bg.cursor = { path = cursorPath }
    elseif type(bg.cursor) == "table" and cursorPath ~= "" then
      bg.cursor.path = cursorPath
    end
    tm.background = bg
  end
  return tm
end

local function buildTownMap(S)
  local locs, tm = townMapLocs(S)
  if Generation.isGen2(S) then
    local gfx = (S.data and (S.data.gen2MenuGfx or S.data.menu_gfx) or {}).pokegear
    local sheet
    if type(gfx) == "table" and type(gfx.tiles) == "string" then
      local okTs, TileSheet = pcall(require, "src.ui.gen2.TileSheet")
      if okTs and TileSheet then
        sheet = TileSheet.new({
          path = gfx.tiles,
          wide = gfx.tilesWide or 16,
          firstTile = 0,
          paletteFor = function(tile)
            if not gfx.palettes then return nil end
            if tile >= 0x60 then return gfx.palettes[1] end
            return gfx.palettes[(gfx.palMap and gfx.palMap[tile + 1]) or 1]
          end,
        })
      end
    end
    local ground = { 0, 0, 0 }
    local pal0 = gfx and gfx.palettes and gfx.palettes[1]
    if type(pal0) == "table" and type(pal0[4]) == "table" then
      ground = pal0[4]
    end
    return {
      kind = "townmap",
      gen2 = true,
      sheet = sheet,
      maps = gfx and gfx.maps,
      ground = ground,
      locs = locs,
      index = 1,
      blink = 0,
      timer = 0,
    }
  end
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  ensureFont(S)
  local merged = mergedTownMap(S)
  local ok, TownMap = pcall(require, "src.ui.TownMap")
  local viewer
  if ok and TownMap and type(TownMap.new) == "function" then
    local game = stubGame({
      field = { townMap = merged },
      sprites = S.data and S.data.sprites,
    })
    ok, viewer = pcall(TownMap.new, game, {})
    if not ok then viewer = nil end
  end
  if viewer then
    local bg = merged.background
    if type(bg) == "table" and bg.map then
      local tiles = img(S, pathOf(bg.tiles))
      if tiles then
        local quads = {}
        local iw, ih = tiles:getDimensions()
        local per = iw / 8
        for i = 0, per * (ih / 8) - 1 do
          quads[i] = love.graphics.newQuad((i % per) * 8,
            math.floor(i / per) * 8, 8, 8, iw, ih)
        end
        viewer.bg = {
          img = tiles,
          quads = quads,
          map = bg.map,
          cursor = img(S, pathOf(bg.cursor)),
        }
        viewer.mode = "grid"
      end
    end
  end
  return {
    kind = "townmap",
    movie = viewer or false,
    locs = locs,
    grid = merged.gridPixelSize or tm.gridPixelSize or 8,
    index = 1,
    blink = 0,
    timer = 0,
  }
end

local function pinTownMapSel(st, S)
  local viewer = st.movie
  if not (viewer and type(viewer.locs) == "table") then return end
  local sel = S and S.uiTmLoc
  if not sel then return end
  local want
  for _, loc in ipairs(st.locs or {}) do
    if loc.id == sel then want = loc; break end
  end
  if not want then return end
  for i, loc in ipairs(viewer.locs) do
    if loc.x == want.x and loc.y == want.y then
      viewer.sel = i
      st.index = i
      return
    end
  end
end

local function updateTownMap(st, S)
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 30
  if st.movie and st.movie.update then
    pinTownMapSel(st, S)
    pcall(st.movie.update, st.movie, 0)
    return
  end
  -- Gold: pin to the landmark selected in the form; Gen1 still cycles.
  if st.gen2 then return end
  if #st.locs > 0 and st.timer % 60 == 0 then
    st.index = (st.index % #st.locs) + 1
  end
end

local function drawPokegearTownMap(st, S)
  local g = st.ground or { 0, 0, 0 }
  love.graphics.setColor(g[1] / 255, g[2] / 255, g[3] / 255, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)

  local loc
  local sel = S and S.uiTmLoc
  if sel then
    for i, e in ipairs(st.locs) do
      if e.id == sel then
        loc, st.index = e, i
        break
      end
    end
  end
  loc = loc or st.locs[st.index]

  local region = pokegearRegion(loc and loc.index, S and S.uiTmRegion)
  local cells = st.maps and st.maps[region]
  if st.sheet and cells then
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, 20 * 18 do
      local tile = cells[i]
      if tile ~= nil then
        local tx = (i - 1) % 20
        local ty = math.floor((i - 1) / 20)
        -- $4f is the solid ground fill tile on the gear sheet.
        if tile == 0x4f then
          love.graphics.setColor(g[1] / 255, g[2] / 255, g[3] / 255, 1)
          love.graphics.rectangle("fill", tx * 8, ty * 8, 8, 8)
          love.graphics.setColor(1, 1, 1, 1)
        else
          pcall(function() st.sheet:draw(tile, tx, ty) end)
        end
      end
    end
  elseif not st.sheet then
    love.graphics.setColor(0.2, 0.35, 0.25, 1)
    love.graphics.rectangle("fill", 0, 24, GB_W, GB_H - 24)
  end

  -- Landmark coords are already screen pixels (extractor undoes OAM +8/+16).
  if loc and st.blink < 15 then
    local x, y = tonumber(loc.x) or 0, tonumber(loc.y) or 0
    love.graphics.setColor(1, 0.15, 0.15, 1)
    love.graphics.rectangle("fill", x - 2, y - 2, 5, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x - 1, y - 1, 3, 3)
  end
  if loc and ensureFont(S) then
    love.graphics.setColor(0, 0, 0, 1)
    local name = tostring(loc.name or "")
    -- Match pokegear name plate: first line at top of screen.
    local line1, line2 = name:match("^(.-)\n(.*)$")
    if not line1 then line1 = name end
    pcall(require("src.render.Font").draw, line1, 72, 0)
    if line2 and line2 ~= "" then
      pcall(require("src.render.Font").draw, line2, 72, 8)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawTownMapFrame(st, S)
  if st.gen2 then
    drawPokegearTownMap(st, S)
    return
  end
  if st.movie then
    pinTownMapSel(st, S)
    drawMoviePanel(st)
    return
  end
  love.graphics.setColor(0.75, 0.85, 0.65, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local loc = st.locs[st.index]
  if loc and st.blink < 15 then
    -- engine TownMapCoordsToOAMCoords: 16x16 nybble grid is 2 tiles in, 1 down
    local x, y = loc.x * 8 + 16, loc.y * 8 + 8
    love.graphics.setColor(1, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", x, y, 8, 8)
  end
  if loc and ensureFont(S) then
    love.graphics.setColor(0, 0, 0, 1)
    pcall(require("src.render.Font").draw, tostring(loc.name), 8, 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Screen order (left-to-right, top-to-bottom). OAM lists Mineral before Storm.
local JOHTO_BADGES = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING",
}
local BADGE_OAM_ORDER = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING",
}

local function trainerCardMerged(S)
  local gfx = S.data and (S.data.gen2MenuGfx or S.data.menu_gfx)
  local base = (gfx and gfx.trainerCard) or {}
  local proj = (S.project and S.project.trainerCard) or {}
  local tc = {}
  for k, v in pairs(base) do tc[k] = v end
  for k, v in pairs(proj) do
    if v ~= nil and v ~= "" then tc[k] = v end
  end
  return tc
end

local function buildBadges(S)
  if Generation.isGen2(S) then
    ensureFont(S)
    local tc = trainerCardMerged(S)
    local owned = {}
    for i = 1, #JOHTO_BADGES do owned[JOHTO_BADGES[i]] = true end
    local card
    local ok, TrainerCard = pcall(require, "src.ui.gen2.TrainerCard")
    if ok and TrainerCard then
      card = TrainerCard.new(nil, {
        save = {
          player = {
            name = "GOLD",
            id = 1,
            money = 0,
            badges = owned,
            pokedex = { caught = {} },
            playTime = { hours = 0, minutes = 0 },
          },
        },
        menuGfx = { trainerCard = tc },
        palettes = S.data and (S.data.gen2Palettes or S.data.palettes),
      })
      card.page = 2
    end
    return {
      kind = "badges",
      gen2 = true,
      card = card or false,
      badgeOam = tc.badgeOam,
      names = JOHTO_BADGES,
      highlight = 1,
      timer = 0,
      frames = 0,
      badges = {}, -- unused; keeps updateBadges safe
    }
  end
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  ensureFont(S)
  local rows = (S.project and S.project.constants and S.project.constants.badges)
    or (S.data and S.data.constants and S.data.constants.badges) or {}
  local inventory = {}
  local badges = {}
  for i, b in ipairs(rows) do
    local id = b.id or ("#" .. i)
    inventory[b.item or id] = true
    badges[i] = {
      id = id,
      name = b.name or "",
      icon = img(S, pathOf(b.icon)),
    }
  end
  local gfx = (S.project and S.project.trainerCard) or {}
  local ok, TrainerCard = pcall(require, "src.ui.TrainerCard")
  local card
  if ok and TrainerCard and type(TrainerCard.new) == "function" then
    local game = stubGame({
      constants = { badges = rows },
      pokemon = S.data and S.data.pokemon,
    }, {
      save = {
        player = { name = "RED" },
        money = 0,
        playTime = 0,
        inventory = inventory,
      },
    })
    ok, card = pcall(TrainerCard.new, game, {})
    if not ok then card = nil end
    if card then
      local function loadSheet(path)
        local p = pathOf(path)
        if p == "" then return nil end
        return img(S, p)
      end
      local sheet = loadSheet(gfx.badges)
        or img(S, "assets/generated/trainer_card/badges.png")
      if sheet then
        local function quads16(image, count, stride, x0, y0)
          local q = {}
          local iw, ih = image:getDimensions()
          for i = 0, count - 1 do
            q[i] = love.graphics.newQuad(x0 or 0, (y0 or 0) + i * stride,
              16, 16, iw, ih)
          end
          return q
        end
        card.faces = { img = sheet, quads = quads16(sheet, 8, 32, 0, 0) }
        card.badges = { img = sheet, quads = quads16(sheet, 8, 32, 0, 16) }
      end
      local nums = loadSheet(gfx.numbers)
        or img(S, "assets/generated/trainer_card/badge_numbers.png")
      if nums then
        card.nums = { img = nums, quads = {} }
        local iw, ih = nums:getDimensions()
        for i = 0, 7 do
          card.nums.quads[i] = love.graphics.newQuad((i % 2) * 8,
            math.floor(i / 2) * 8, 8, 8, iw, ih)
        end
      end
      local frame = loadSheet(gfx.frame)
        or img(S, "assets/generated/trainer_card/trainer_info.png")
      if frame then
        card.frame = { img = frame, quads = {} }
        for i = 0, 8 do
          card.frame.quads[i] = love.graphics.newQuad((i % 3) * 8,
            math.floor(i / 3) * 8, 8, 8, frame:getDimensions())
        end
      end
      local circle = loadSheet(gfx.circle)
        or img(S, "assets/generated/trainer_card/circle_tile.png")
      if circle then card.circle = circle end
    end
  end
  return {
    kind = "badges",
    movie = card or false,
    badges = badges,
    timer = 0,
    highlight = 1,
  }
end

local function updateBadges(st, S)
  st.timer = st.timer + 1
  if st.gen2 then
    st.frames = (st.frames or 0) + 1
    local n = st.names and #st.names or 0
    if n > 0 and st.timer % 45 == 0 then
      st.highlight = (st.highlight % n) + 1
    end
    return
  end
  local sel = S and S.uiBdgId
  if sel then
    for i, b in ipairs(st.badges or {}) do
      if tostring(b.id) == sel then
        st.highlight = i
        return
      end
    end
  end
  if #st.badges > 0 and st.timer % 45 == 0 then
    st.highlight = (st.highlight % #st.badges) + 1
  end
end

local function drawBadgesFrame(st, S)
  if st.gen2 then
    ensureFont(S)
    if st.card then
      st.card.page = 2
      -- Frame 0 is each badge's unique tile. Later frames are shared sparkles.
      st.card.frames = 0
      pcall(function() st.card:draw() end)
    else
      love.graphics.setColor(0.95, 0.92, 0.78, 1)
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    end
    local name = st.names and st.names[st.highlight]
    local list = st.badgeOam
    if name and list then
      for i, obj in ipairs(list) do
        if BADGE_OAM_ORDER[i] == name then
          love.graphics.setColor(1, 0.85, 0.2, 1)
          love.graphics.rectangle("line", obj.x - 1, obj.y - 1, 17, 17)
          break
        end
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local sel = S and S.uiBdgId
  if sel then
    for i, b in ipairs(st.badges or {}) do
      if tostring(b.id) == sel then st.highlight = i; break end
    end
  end
  if st.movie then
    drawMoviePanel(st)
    local i = st.highlight or 1
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local tx, ty = 16 + col * 32, 94 + row * 24
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.rectangle("line", tx + 3, ty + 5, 18, 18)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  love.graphics.setColor(0.9, 0.9, 0.85, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local n = #st.badges
  if n == 0 then return end
  local cols = 4
  local cell = 32
  for i, b in ipairs(st.badges) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = 16 + col * cell
    local y = 24 + row * cell
    if i == st.highlight then
      love.graphics.setColor(1, 0.85, 0.2, 1)
      love.graphics.rectangle("line", x - 2, y - 2, cell - 4, cell - 4)
    end
    love.graphics.setColor(1, 1, 1, 1)
    if b.icon then
      local iw, ih = b.icon:getDimensions()
      local sc = math.min(24 / iw, 24 / ih)
      love.graphics.draw(b.icon, x, y, 0, sc, sc)
    else
      love.graphics.setColor(0.6, 0.55, 0.35, 1)
      love.graphics.rectangle("fill", x + 4, y + 4, 16, 16)
    end
  end
  local cur = st.badges[st.highlight]
  if cur and ensureFont(S) then
    love.graphics.setColor(0, 0, 0, 1)
    pcall(require("src.render.Font").draw, tostring(cur.name or cur.id), 8, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function bootScreen(S, key)
  local boot = S.project and S.project.boot
  if boot and type(boot.screens) == "table" and boot.screens[key] then
    return boot.screens[key]
  end
  local d = dataField(S, "boot")
  if type(d.screens) == "table" and d.screens[key] then
    return d.screens[key]
  end
  return BOOT_DEFAULTS[key]
end

local function buildBoot(S)
  return {
    kind = "boot",
    steps = {
      { key = "splash", id = bootScreen(S, "splash") },
      { key = "title", id = bootScreen(S, "title") },
      { key = "newGame", id = bootScreen(S, "newGame") },
    },
    index = 1,
    timer = 0,
    fade = 0,
    cycles = 0,
  }
end

local function updateBoot(st)
  st.timer = st.timer + 1
  local phase = st.timer % 90
  st.fade = phase < 12 and (phase / 12)
    or (phase > 78 and ((90 - phase) / 12) or 1)
  if phase == 0 and st.timer > 0 then
    if st.index >= #st.steps then
      st.cycles = (st.cycles or 0) + 1
      st.index = 1
    else
      st.index = st.index + 1
    end
  end
end

local function drawBootFrame(st, S)
  love.graphics.setColor(0.08, 0.1, 0.18, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local step = st.steps[st.index]
  love.graphics.setColor(1, 1, 1, st.fade or 1)
  if ensureFont(S) then
    local Font = require("src.render.Font")
    local label = tostring(step and step.key or "?")
    local id = tostring(step and step.id or "?")
    pcall(Font.draw, "BOOT", 64, 40)
    pcall(Font.draw, label, math.max(0, (160 - #label * 8) / 2), 64)
    pcall(Font.draw, id, math.max(0, (160 - #id * 8) / 2), 88)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- credits roll ----

local function mergedCredits(S)
  local cred = {}
  if Generation.isGen2(S) then
    overlayIntro(cred, (S.data and (S.data.gen2Credits or S.data.credits)) or {})
  else
    overlayIntro(cred, dataField(S, "credits"))
  end
  overlayIntro(cred, (S.project and S.project.credits) or {})
  return cred
end

local function snapshotGen2CreditStrings(C)
  if type(C) ~= "table" or type(C.STRINGS) ~= "table" then return nil end
  if type(C._ceVanillaStrings) == "table" then return C._ceVanillaStrings end
  local copy = {}
  for idx, text in pairs(C.STRINGS) do
    if type(text) == "table" then
      local lines = {}
      for i, line in ipairs(text) do lines[i] = line end
      copy[idx] = lines
    else
      copy[idx] = text
    end
  end
  C._ceVanillaStrings = copy
  return copy
end

function UiPreview.gen2CreditCatalog()
  local ok, C = pcall(require, "src.ui.gen2.Credits")
  if not (ok and C and C.ID and C.STRINGS) then return nil, nil end
  return C, snapshotGen2CreditStrings(C)
end

local function applyGen2CreditStrings(S)
  local C, vanilla = UiPreview.gen2CreditCatalog()
  if not C then return end
  if type(vanilla) == "table" then
    for idx, text in pairs(vanilla) do
      if type(text) == "table" then
        local lines = {}
        for i, line in ipairs(text) do lines[i] = line end
        C.STRINGS[idx] = lines
      else
        C.STRINGS[idx] = text
      end
    end
  end
  local strings = S.project and S.project.credits and S.project.credits.strings
  if type(strings) ~= "table" then return end
  for name, text in pairs(strings) do
    local id = C.ID[name]
    if id ~= nil then C.STRINGS[id] = text end
  end
end

function UiPreview.gen2CreditPages()
  local C, vanilla = UiPreview.gen2CreditCatalog()
  if not (C and type(C.SCRIPT) == "table" and C.ID) then return {} end
  local byIdx = {}
  for name, idx in pairs(C.ID) do byIdx[idx] = name end
  local pages, scene, lines = {}, 0, {}
  local function flush()
    if #lines > 0 then
      pages[#pages + 1] = { scene = scene, lines = lines }
      lines = {}
    end
  end
  local script = C.SCRIPT
  local i = 1
  while i <= #script do
    local byte = script[i]
    i = i + 1
    if byte == nil or byte == C.END then
      break
    elseif byte == C.WAIT or byte == C.WAIT2 then
      i = i + 1
      flush()
    elseif byte == C.SCENE then
      scene = tonumber(script[i]) or 0
      i = i + 1
    elseif byte == C.CLEAR or byte == C.MUSIC or byte == C.THEEND then
      -- no operand
    else
      local slot = script[i]
      i = i + 1
      local name = byIdx[byte]
      if type(name) == "string" then
        local src = vanilla and vanilla[byte]
        if src == nil then src = C.STRINGS and C.STRINGS[byte] end
        if type(src) == "table" then
          for row = 1, #src do
            lines[#lines + 1] = { id = name, table = true, row = row }
          end
        else
          lines[#lines + 1] = { id = name, slot = tonumber(slot) or 0 }
        end
      end
    end
  end
  flush()
  return pages
end

local function scriptForCreditPage(C, page)
  if not (C and page and page.lines) then return nil end
  local s = { C.CLEAR, C.SCENE, page.scene or 0 }
  local seen, slot = {}, 0
  for _, line in ipairs(page.lines) do
    local id = C.ID[line.id]
    if id ~= nil then
      if line.table then
        if not seen[line.id] then
          seen[line.id] = true
          s[#s + 1] = id
          s[#s + 1] = 0
        end
      else
        s[#s + 1] = id
        s[#s + 1] = slot
        slot = slot + 1
      end
    end
  end
  s[#s + 1] = C.WAIT
  s[#s + 1] = 20
  s[#s + 1] = C.END
  return s
end

local function buildCredits(S)
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  ensureFont(S)
  local cred = mergedCredits(S)
  if Generation.isGen2(S) then
    applyGen2CreditStrings(S)
    local ok, Credits = pcall(require, "src.ui.gen2.Credits")
    if not (ok and Credits and type(Credits.new) == "function") then
      return { kind = "credits", done = true }
    end
    local game = stubGame({
      gen2Credits = cred,
      gen2Icons = S.data and S.data.gen2Icons,
      gen2Palettes = S.data and (S.data.gen2Palettes or S.data.palettes),
    })
    local C = select(1, UiPreview.gen2CreditCatalog())
    local pages = UiPreview.gen2CreditPages()
    local idx = math.max(1, math.min(S.uiCreditIndex or 1, math.max(1, #pages)))
    local script = scriptForCreditPage(C, pages[idx])
    local movie
    ok, movie = pcall(Credits.new, game, {
      gfx = cred, allowSkip = false, script = script,
    })
    if not (ok and movie) then return { kind = "credits", done = true } end
    pcall(function() movie:enter() end)
    return { kind = "credits", movie = movie, done = false }
  end
  local ok, Credits = pcall(require, "src.ui.Credits")
  if not (ok and Credits and type(Credits.new) == "function") then
    return { kind = "credits", done = true }
  end
  local game = stubGame({
    field = { credits = cred },
    pokemon = S.data and S.data.pokemon,
    text = S.data and S.data.text,
    audio = {},
  })
  local movie
  ok, movie = pcall(Credits.new, game, nil, nil)
  if not (ok and movie) then return { kind = "credits", done = true } end
  pcall(function() movie:enter() end)
  return { kind = "credits", movie = movie, done = false }
end

local function updateCredits(st)
  local movie = st.movie
  if movie and movie.update then
    pcall(movie.update, movie, 0)
    st.done = movie.done == true or movie.finished == true
      or (movie.phase == "end_wait" and (st.waited or 0) > 90)
    if movie.phase == "end_wait" then
      st.waited = (st.waited or 0) + 1
    end
  else
    st.done = true
  end
end

local function drawCreditsFrame(st)
  if st.movie then
    drawMoviePanel(st)
    return
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, 32)
  love.graphics.rectangle("fill", 0, 112, GB_W, 32)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- minigames (Game Corner + Unown puzzle) ----

local SLOT_TEXT_DEFAULTS = {
  betHowMany = { "Bet how many", "coins?" },
  start = { "Start!" },
  notEnough = { "Not enough", "coins." },
  ranOut = { "Darn… Ran out of", "coins…" },
  playAgain = { "Play again?" },
  darn = { "Darn!" },
}

local CARD_TEXT_DEFAULTS = {
  playWithThree = { "Play with", "3 coins?" },
  notEnough = { "Not enough", "coins." },
  chooseACard = { "Choose a", "card." },
  placeYourBet = { "Place", "your bet" },
  playAgain = { "Play", "again?" },
  shuffled = { "The cards", "shuffled." },
  yeah = { "Yeah!" },
  darn = { "Darn…" },
}

local vanillaSlotTexts
local vanillaCardTexts

local function copyTextMap(src)
  local out = {}
  if type(src) ~= "table" then return out end
  for k, v in pairs(src) do
    if type(v) == "table" then
      local row = {}
      for i, line in ipairs(v) do row[i] = line end
      out[k] = row
    else
      out[k] = v
    end
  end
  return out
end

local function linesFrom(v)
  if type(v) == "table" then
    local row = {}
    for i, line in ipairs(v) do row[i] = tostring(line) end
    if #row > 0 then return row end
  elseif type(v) == "string" and v ~= "" then
    local row = {}
    for line in (v .. "\n"):gmatch("(.-)\n") do
      row[#row + 1] = line
    end
    if #row == 0 then row[1] = v end
    return row
  end
  return nil
end

local function overlayTextMap(dst, overlay)
  if type(dst) ~= "table" or type(overlay) ~= "table" then return end
  for k, v in pairs(overlay) do
    local lines = linesFrom(v)
    if lines then dst[k] = lines end
  end
end

local function joinTextLines(v)
  local lines = linesFrom(v)
  if not lines then return "" end
  return table.concat(lines, "\n")
end

function UiPreview.minigameTextDefaults(kind)
  if kind == "cardflip" then
    local ok, CardFlip = pcall(require, "src.ui.gen2.CardFlip")
    if ok and CardFlip and type(CardFlip.TEXTS) == "table" then
      return CardFlip.TEXTS
    end
    return CARD_TEXT_DEFAULTS
  end
  if kind == "surf" then
    return {
      beach = "PIKACHU'S BEACH",
      hiScore = "Hi-Score   %4d Pt",
      pressStart = "PRESS START",
      hpLeft = "HP Left",
      radness = "Radness",
      total = "Total",
      pts = "Pts",
      hiScoreRecord = "Hi-Score!!",
    }
  end
  local ok, SlotMachine = pcall(require, "src.ui.gen2.SlotMachine")
  if ok and SlotMachine and type(SlotMachine.TEXTS) == "table" then
    return SlotMachine.TEXTS
  end
  return SLOT_TEXT_DEFAULTS
end

function UiPreview.minigameText(S, kind, key)
  local p = S and S.project and S.project.minigames and S.project.minigames[kind]
  if type(p) == "table" and type(p.texts) == "table" and p.texts[key] ~= nil then
    return joinTextLines(p.texts[key]), true
  end
  local defaults = UiPreview.minigameTextDefaults(kind)
  return joinTextLines(defaults[key]), false
end

local function applyMinigameTexts(kind, overlay)
  if kind == "cardflip" then
    local ok, CardFlip = pcall(require, "src.ui.gen2.CardFlip")
    if not (ok and CardFlip and type(CardFlip.TEXTS) == "table") then return end
    if not vanillaCardTexts then vanillaCardTexts = copyTextMap(CardFlip.TEXTS) end
    for k in pairs(CardFlip.TEXTS) do CardFlip.TEXTS[k] = nil end
    overlayTextMap(CardFlip.TEXTS, vanillaCardTexts)
    overlayTextMap(CardFlip.TEXTS, overlay)
    return
  end
  local ok, SlotMachine = pcall(require, "src.ui.gen2.SlotMachine")
  if not (ok and SlotMachine and type(SlotMachine.TEXTS) == "table") then return end
  if not vanillaSlotTexts then vanillaSlotTexts = copyTextMap(SlotMachine.TEXTS) end
  for k in pairs(SlotMachine.TEXTS) do SlotMachine.TEXTS[k] = nil end
  overlayTextMap(SlotMachine.TEXTS, vanillaSlotTexts)
  overlayTextMap(SlotMachine.TEXTS, overlay)
end

local function pathStr(v)
  if type(v) == "table" then
    local p = v.path or v.sheet or v.image
    if type(p) == "string" and p ~= "" then return p end
    return nil
  end
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function deepMerge(dst, src)
  if type(src) ~= "table" then return dst end
  dst = type(dst) == "table" and dst or {}
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      dst[k] = deepMerge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- Editor overrides are often `{ path = "mods/..." }`; engine screens want strings.
-- Copy the tree so preview never mutates cache or project tables.
local function flattenGfxPaths(node)
  if type(node) ~= "table" then return node end
  local out = {}
  for k, v in pairs(node) do
    if type(v) == "table" then
      local p = pathStr(v)
      local extras = false
      if p then
        for ck in pairs(v) do
          if ck ~= "path" and ck ~= "sheet" and ck ~= "image" then
            extras = true
            break
          end
        end
      end
      if p and not extras then
        out[k] = p
      else
        out[k] = flattenGfxPaths(v)
        if p and type(out[k]) == "table" and type(out[k].path) ~= "string" then
          out[k].path = p
        end
      end
    else
      out[k] = v
    end
  end
  return out
end

local function minigamePreviewData(S)
  local data = {}
  local src = (S and S.data) or {}
  for k, v in pairs(src) do data[k] = v end
  local gfx = flattenGfxPaths(deepMerge(
    flattenGfxPaths(src.gen2MenuGfx or src.menu_gfx or {}),
    S.project and S.project.menuGfx))
  data.gen2MenuGfx = gfx
  data.menu_gfx = gfx
  local field = flattenGfxPaths(src.field or {})
  local ownedGfx = S.project and S.project.menuGfx
  if type(ownedGfx) == "table" then
    for k, v in pairs(ownedGfx) do
      if type(v) == "table" then
        field[k] = flattenGfxPaths(deepMerge(flattenGfxPaths(field[k] or {}), v))
      end
    end
  end
  data.field = field
  return data
end

local function withQuietMusic(fn)
  local okM, Music = pcall(require, "src.core.Music")
  local play, restore, stop
  if okM and Music then
    play, restore, stop = Music.play, Music.restoreMap, Music.stop
    Music.play = function() end
    Music.restoreMap = function() end
    Music.stop = function() end
  end
  local ok, result = pcall(fn)
  if okM and Music then
    Music.play = play
    Music.restoreMap = restore
    Music.stop = stop
  end
  if not ok then return nil end
  return result
end

local function loadTileSheet(path, wide)
  if type(path) ~= "string" or path == "" then return nil end
  local ok, TileSheet = pcall(require, "src.ui.gen2.TileSheet")
  if not (ok and TileSheet and TileSheet.new) then return nil end
  local sheet
  ok, sheet = pcall(TileSheet.new, { path = path, wide = wide or 2, firstTile = 0 })
  return ok and sheet or nil
end

local function applyNamedSheets(movie, gfx, specs)
  if type(movie) ~= "table" or type(gfx) ~= "table" then return end
  local any = false
  for i = 1, #specs do
    if pathStr(gfx[specs[i].key]) then any = true; break end
  end
  if not any then return end
  for i = 1, #specs do
    local spec = specs[i]
    local sheet = loadTileSheet(pathStr(gfx[spec.key]) or spec.fallback, spec.wide)
    if sheet then movie[spec.field] = sheet end
  end
end

local function applySlotActors(movie, gfx)
  if type(movie) ~= "table" or type(gfx) ~= "table" then return end
  local path = pathStr(gfx.actors) or pathStr(gfx.sheet3)
  if not path then return end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not (okA and Assets and Assets.image) then return end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then return end
  movie.actorsLoaded = img
  local G = love.graphics
  if not (G and G.newQuad) then return end
  movie.quadGolemStand  = G.newQuad(0, 0,   24, 32, 24, 240)
  movie.quadGolemBall   = G.newQuad(0, 32,  24, 32, 24, 240)
  movie.quadChansey1    = G.newQuad(0, 64,  24, 32, 24, 240)
  movie.quadChansey2    = G.newQuad(0, 96,  24, 32, 24, 240)
  movie.quadChansey3    = G.newQuad(0, 128, 24, 32, 24, 240)
  movie.quadChansey4    = G.newQuad(0, 160, 24, 32, 24, 240)
  movie.quadChanseyDrop = G.newQuad(0, 192, 24, 32, 24, 240)
  movie.quadEgg         = G.newQuad(0, 224, 8,  16, 24, 240)
end

local function loadSurfImage(S, path)
  path = pathStr(path)
  if not path then return nil end
  local image = img(S, path)
  if image then return image end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.image then
    local ok, loaded = pcall(Assets.image, path)
    if ok and loaded then return loaded end
  end
  if love and love.graphics and love.graphics.newImage then
    local ok, loaded = pcall(love.graphics.newImage, path)
    if ok and loaded then return loaded end
  end
  return nil
end

local function applySurfArt(movie, S, gfx)
  if type(movie) ~= "table" or type(gfx) ~= "table" then return end
  local G = love.graphics
  if not (G and G.newQuad) then return end
  local bg = loadSurfImage(S, gfx.bg)
  local ob = loadSurfImage(S, gfx.sprites)
  local intro = loadSurfImage(S, gfx.intro)
  local titleBg = loadSurfImage(S, gfx.titleBg)
  if bg then
    movie.bg = bg
    movie.tq = {}
    local bgW, bgH = bg:getDimensions()
    for n = 0, 64 do
      movie.tq[n] = G.newQuad((n % 5) * 8, math.floor(n / 5) * 8, 8, 8, bgW, bgH)
    end
  end
  if ob then
    movie.ob = ob
    movie.oq = {}
    local obW, obH = ob:getDimensions()
    for n = 0, 255 do
      movie.oq[n] = G.newQuad((n % 16) * 8, math.floor(n / 16) * 8, 8, 8, obW, obH)
    end
  end
  if intro then
    movie.intro = intro
    movie.iq = {}
    local iW, iH = intro:getDimensions()
    for n = 0, 143 do
      movie.iq[n] = G.newQuad((n % 12) * 8, math.floor(n / 12) * 8, 8, 8, iW, iH)
    end
    movie.introPikaQuad1 = G.newQuad(0, 0, 24, 32, iW, iH)
    movie.introPikaQuad2 = G.newQuad(24, 0, 24, 32, iW, iH)
    movie.introPikaQuad3 = G.newQuad(48, 0, 24, 32, iW, iH)
    movie.introLogoQuad = G.newQuad(0, 32, 96, 32, iW, iH)
    movie.introTextQuad = G.newQuad(0, 64, 96, 32, iW, iH)
  end
  if titleBg then movie.titleBg = titleBg end
end

local function flattenSurfTexts(overlay)
  local T = {}
  if type(overlay) ~= "table" then return T end
  for k, v in pairs(overlay) do
    if type(v) == "string" and v ~= "" then
      T[k] = v
    elseif type(v) == "table" and v[1] then
      T[k] = table.concat(v, "\n")
    end
  end
  return T
end

local function applySurfTexts(movie, overlay)
  if type(movie) ~= "table" then return end
  local T = flattenSurfTexts(overlay)
  if not next(T) then return end
  local function wrap(orig)
    if type(orig) ~= "function" then return orig end
    return function(self)
      local Font = require("src.render.Font")
      local origDraw = Font.draw
      Font.draw = function(text, x, y, ...)
        text = tostring(text or "")
        if text == "PIKACHU'S BEACH" and T.beach then
          text = T.beach
        elseif text == "PRESS START" and T.pressStart then
          text = T.pressStart
        elseif text == "Hi-Score!!" and T.hiScoreRecord then
          text = T.hiScoreRecord
        elseif T.hiScore and text:sub(1, 8) == "Hi-Score" then
          if T.hiScore:find("%", 1, true) then
            text = string.format(T.hiScore, self.hiScore or 0)
          else
            text = T.hiScore
          end
        elseif text == "HP Left" and T.hpLeft then
          text = T.hpLeft
        elseif text == "Radness" and T.radness then
          text = T.radness
        elseif text == "Total" and T.total then
          text = T.total
        elseif text == "Pts" and T.pts then
          text = T.pts
        end
        return origDraw(text, x, y, ...)
      end
      local ok, err = pcall(orig, self)
      Font.draw = origDraw
      if not ok then error(err) end
    end
  end
  movie.drawTitleScreen = wrap(movie.drawTitleScreen)
  movie.drawResultsOutro = wrap(movie.drawResultsOutro)
end

local function minigameKind(S)
  local kind = S and S.uiMinigame
  if kind == "cardflip" or kind == "unown" or kind == "slots"
      or kind == "surf" then
    return kind
  end
  return "slots"
end

local SURF_BEACH_PAL = {
  { 255, 255, 255 }, { 255, 224, 0 }, { 88, 168, 248 }, { 25, 25, 25 },
}
local SURF_TITLE_PAL = {
  { 255, 255, 255 }, { 132, 132, 132 }, { 255, 206, 74 }, { 25, 25, 25 },
}

local function surfSgbZones(S, screen)
  local okP, P = pcall(require, "src.render.PaletteFX")
  if not (okP and P and P.whole and P.zone) then return nil end
  local beach = namedPal(S, "PIKACHUS_BEACH", SURF_BEACH_PAL)
  if screen == "title" then
    local title = namedPal(S, "PIKACHUS_BEACH_TITLE", SURF_TITLE_PAL)
    return { P.whole(beach), P.zone(title, 4, 0, 15, 5) }
  end
  return { P.whole(beach) }
end

local function slotSgbZones(S)
  local okP, P = pcall(require, "src.render.PaletteFX")
  if not (okP and P and P.zone) then return nil end
  local s1 = namedPal(S, "SLOTS1")
  if not s1 then return nil end
  local s2 = namedPal(S, "SLOTS2") or s1
  local s3 = namedPal(S, "SLOTS3") or s1
  local s4 = namedPal(S, "SLOTS4") or s1
  return {
    P.zone(s2, 0, 0, 19, 11),
    P.zone(s3, 0, 4, 19, 9),
    P.zone(s4, 0, 6, 19, 7),
    P.zone(s1, 4, 4, 15, 9),
    P.zone(s1, 0, 12, 19, 17),
  }
end

local function buildMinigames(S)
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  ensureFont(S)
  local kind = minigameKind(S)
  local data = minigamePreviewData(S)
  local owned = S.project and S.project.minigames and S.project.minigames[kind]
  local texts = type(owned) == "table" and owned.texts or nil
  local game = stubGame(data)
  game.save = game.save or {}
  game.save.coins = 50
  game.save.player = game.save.player or {}
  game.save.player.coins = 50

  if not Generation.isGen2(S) then
    if kind == "surf" then
      local ok, Surf = pcall(require, "src.ui.SurfingMinigame")
      if not (ok and Surf and Surf.new) then
        return { kind = "minigames", game = kind, done = true }
      end
      game.save.surfingHighScore = 9999
      game.version = Generation.id(S)
      local screen = S.uiSurfScreen or "title"
      local skipTitle = screen ~= "title"
      local movie = withQuietMusic(function()
        return Surf.new(game, nil, skipTitle)
      end)
      if not movie then return { kind = "minigames", game = kind, done = true } end
      applySurfArt(movie, S, data.field and data.field.surfPikachu)
      applySurfTexts(movie, texts)
      if screen == "results" then
        -- Draw uses showResultsCard + outroLines, not routine 10 (WaitLast).
        if movie.beginResultsCard then
          pcall(movie.beginResultsCard, movie)
        end
        movie.showResultsCard = true
        movie.hp = 1041
        movie.radness = 1510
        movie.totalScore = 2551
        movie.newRecord = true
        movie.hiScore = 2551
        movie.outroLines = { hp = true, rad = true, total = true, hiScore = true }
        movie.pikaState = 6
        movie.speedFixed = 0
        movie.cloudSpriteX = nil
        movie.distanceSection = 24
        movie.routine = 11
      end
      return {
        kind = "minigames", game = kind, movie = movie,
        surfScreen = screen, done = false,
        sgbZones = surfSgbZones(S, screen),
      }
    end
    local ok, SlotMachine = pcall(require, "src.ui.SlotMachine")
    if not (ok and SlotMachine and SlotMachine.new) then
      return { kind = "minigames", game = kind, done = true }
    end
    local movie = withQuietMusic(function()
      return SlotMachine.new(game, false)
    end)
    if not movie then return { kind = "minigames", game = kind, done = true } end
    return {
      kind = "minigames", game = kind, movie = movie, done = false,
      sgbZones = slotSgbZones(S),
    }
  end

  if kind == "cardflip" then
    applyMinigameTexts("cardflip", texts)
    local ok, CardFlip = pcall(require, "src.ui.gen2.CardFlip")
    if not (ok and CardFlip and CardFlip.new) then
      return { kind = "minigames", game = kind, done = true }
    end
    local movie = withQuietMusic(function()
      return CardFlip.new(game, { save = game.save })
    end)
    if not movie then return { kind = "minigames", game = kind, done = true } end
    local gfx = data.gen2MenuGfx and data.gen2MenuGfx.cardFlip
    applyNamedSheets(movie, gfx, {
      { field = "sheet1", key = "sheet1", wide = 16,
        fallback = "assets/generated/card_flip/card_flip_1.png" },
      { field = "sheet2", key = "sheet2", wide = 3,
        fallback = "assets/generated/card_flip/card_flip_2.png" },
      { field = "sheet3", key = "sheet3", wide = 1,
        fallback = "assets/generated/card_flip/card_flip_3.png" },
      { field = "sheetOn", key = "on", wide = 1,
        fallback = "assets/generated/card_flip/on.png" },
      { field = "sheetOff", key = "off", wide = 1,
        fallback = "assets/generated/card_flip/off.png" },
    })
    return { kind = "minigames", game = kind, movie = movie, done = false }
  end

  if kind == "unown" then
    local ok, UnownPuzzle = pcall(require, "src.ui.gen2.UnownPuzzle")
    if not (ok and UnownPuzzle and UnownPuzzle.new) then
      return { kind = "minigames", game = kind, done = true }
    end
    local puzzle = math.max(0, math.min(3, tonumber(S.uiUnownPuzzle) or 0))
    local movie = withQuietMusic(function()
      return UnownPuzzle.new(game, { puzzle = puzzle })
    end)
    if not movie then return { kind = "minigames", game = kind, done = true } end
    return { kind = "minigames", game = kind, movie = movie, done = false }
  end

  applyMinigameTexts("slots", texts)
  local ok, SlotMachine = pcall(require, "src.ui.gen2.SlotMachine")
  if not (ok and SlotMachine and SlotMachine.new) then
    return { kind = "minigames", game = kind, done = true }
  end
  local movie = withQuietMusic(function()
    return SlotMachine.new(game, { save = game.save })
  end)
  if not movie then return { kind = "minigames", game = kind, done = true } end
  local gfx = data.gen2MenuGfx and data.gen2MenuGfx.slots
  applyNamedSheets(movie, gfx, {
    { field = "sheet1", key = "sheet1", wide = 2,
      fallback = "assets/generated/slots/gold_slots_1.png" },
    { field = "sheet2", key = "sheet2", wide = 2,
      fallback = "assets/generated/slots/gold_slots_2.png" },
    { field = "sheet3", key = "sheet3", wide = 3,
      fallback = "assets/generated/slots/gold_slots_3.png" },
  })
  applySlotActors(movie, gfx)
  return { kind = "minigames", game = kind, movie = movie, done = false }
end

local function updateMinigames(st)
  local movie = st.movie
  if movie and movie.update then
    if st.game == "surf" then
      if st.surfScreen == "results" then
        st.done = false
      else
        pcall(movie.update, movie)
        if st.surfScreen == "ride" then
          local r = movie.routine
          st.done = type(r) == "number" and (r >= 4 or r == 12)
        else
          st.done = false
        end
      end
    else
      pcall(movie.update, movie, 0)
      st.done = movie.done == true or movie.finished == true
        or movie.phase == "quit"
    end
  else
    st.done = true
  end
end

local function drawMinigamesFrame(st)
  if st.movie then
    drawMoviePanel(st)
    return
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- menus (in-game chrome screens) ----

local function firstSpecies(S)
  local poke = S and S.data and S.data.pokemon
  if type(poke) ~= "table" then return "PIKACHU" end
  if poke.PIKACHU then return "PIKACHU" end
  if poke.CYNDAQUIL then return "CYNDAQUIL" end
  local ids = {}
  for k in pairs(poke) do
    if type(k) == "string" then ids[#ids + 1] = k end
  end
  table.sort(ids)
  return ids[1] or "PIKACHU"
end

local function otherSpecies(S, skip)
  local poke = S and S.data and S.data.pokemon
  if type(poke) ~= "table" then return skip or "CHARMANDER" end
  if skip ~= "CHARMANDER" and poke.CHARMANDER then return "CHARMANDER" end
  if skip ~= "SQUIRTLE" and poke.SQUIRTLE then return "SQUIRTLE" end
  local ids = {}
  for k in pairs(poke) do
    if type(k) == "string" and k ~= skip then ids[#ids + 1] = k end
  end
  table.sort(ids)
  return ids[1] or skip or "CHARMANDER"
end

local function makePreviewMon(S, game)
  local species = firstSpecies(S)
  if Generation.isGen2(S) then
    local ok, Mon = pcall(require, "src.battle.gen2.Mon")
    if ok and Mon and Mon.new then
      local built
      ok, built = pcall(Mon.new, game.data, species, 12, {
        dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
      })
      if ok and built then
        built.nickname = built.nickname or built.name or "TEST"
        return built
      end
    end
  else
    local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
    if ok and Pokemon and Pokemon.new then
      local built
      ok, built = pcall(Pokemon.new, game.data, species, 12)
      if ok and built then return built end
    end
  end
  return {
    species = species, level = 12, hp = 40, maxHp = 40,
    dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
    moves = { { id = "TACKLE", pp = 35 } },
    nickname = "TEST",
  }
end

local function stubMenuSave(S, game)
  local mon = makePreviewMon(S, game)
  local seen, caught = {}, {}
  local poke = S.data and S.data.pokemon
  if type(poke) == "table" then
    local ids = {}
    for k in pairs(poke) do
      if type(k) == "string" then ids[#ids + 1] = k end
    end
    table.sort(ids)
    for i = 1, math.min(8, #ids) do
      local id = ids[i]
      seen[id] = true
      caught[id] = true
      local def = poke[id]
      if type(def) == "table" and def.id then
        seen[def.id] = true
        caught[def.id] = true
      end
    end
  elseif mon.species then
    seen[mon.species] = true
    caught[mon.species] = true
  end
  game.save.party = { mon }
  game.save.pokedex = { seen = seen, caught = caught, owned = caught }
  game.save.inventory = game.save.inventory or {}
  game.save.coins = 50
  game.save.player = game.save.player or {}
  game.save.player.name = Generation.isGen2(S) and "GOLD" or "RED"
  game.save.player.gender = "male"
  game.save.player.coins = 50
  game.save.pokegearFlags = { radio = true, map = true, phone = true, expn = true }
  return mon
end

local function collectSheetImages(S, tbl)
  local found = {}
  local function walk(node)
    if type(node) ~= "table" then
      local p = pathStr(node)
      if p then found[#found + 1] = img(S, p) end
      return
    end
    local p = pathStr(node)
    if p then
      found[#found + 1] = img(S, p)
      return
    end
    local keys = {}
    for k in pairs(node) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #keys do
      local k = keys[i]
      if (type(k) == "string" and k:sub(1, 1) ~= "_") or type(k) == "number" then
        walk(node[k])
      end
    end
  end
  walk(tbl)
  local images = {}
  for i = 1, #found do
    if found[i] then images[#images + 1] = found[i] end
  end
  return images
end

local function menuSource(S, id)
  local data = minigamePreviewData(S)
  if id == "diploma" then
    return flattenGfxPaths(deepMerge(
      flattenGfxPaths(S.data and (S.data.gen2Diploma or S.data.diploma) or {}),
      S.project and S.project.diploma))
  end
  if Generation.isGen2(S) then
    local gfx = data.gen2MenuGfx or {}
    if id == "naming" then
      return {
        border = gfx.border, cursor = gfx.cursor,
        middleLine = gfx.middleLine, underLine = gfx.underLine,
      }
    end
    return gfx[id]
  end
  return data.field and data.field[id]
end

local function movieOf(id, ctor)
  local movie = withQuietMusic(ctor)
  if not movie then return nil end
  pcall(function() if movie.enter then movie:enter() end end)
  return { kind = "menus", id = id, movie = movie, done = false }
end

local function applySlotsArt(st, data)
  if not (st and st.movie) then return st end
  local gfx = data.gen2MenuGfx and data.gen2MenuGfx.slots
  applyNamedSheets(st.movie, gfx, {
    { field = "sheet1", key = "sheet1", wide = 2,
      fallback = "assets/generated/slots/gold_slots_1.png" },
    { field = "sheet2", key = "sheet2", wide = 2,
      fallback = "assets/generated/slots/gold_slots_2.png" },
    { field = "sheet3", key = "sheet3", wide = 3,
      fallback = "assets/generated/slots/gold_slots_3.png" },
  })
  applySlotActors(st.movie, gfx)
  return st
end

local function applyCardFlipArt(st, data)
  if not (st and st.movie) then return st end
  local gfx = data.gen2MenuGfx and data.gen2MenuGfx.cardFlip
  applyNamedSheets(st.movie, gfx, {
    { field = "sheet1", key = "sheet1", wide = 16,
      fallback = "assets/generated/card_flip/card_flip_1.png" },
    { field = "sheet2", key = "sheet2", wide = 3,
      fallback = "assets/generated/card_flip/card_flip_2.png" },
    { field = "sheet3", key = "sheet3", wide = 1,
      fallback = "assets/generated/card_flip/card_flip_3.png" },
    { field = "sheetOn", key = "on", wide = 1,
      fallback = "assets/generated/card_flip/on.png" },
    { field = "sheetOff", key = "off", wide = 1,
      fallback = "assets/generated/card_flip/off.png" },
  })
  return st
end

local HUD_PAGES = {
  { key = "fontBattleExtra", base = 0x62 },
  { key = "hud1", base = 0x6D },
  { key = "hud2", base = 0x73 },
  { key = "hud3", base = 0x76 },
}

local function addHudPage(out, image, base)
  if not image then return end
  local ok, iw, ih = pcall(function() return image:getWidth(), image:getHeight() end)
  if not (ok and iw and ih and iw >= 8 and ih >= 8) then return end
  local per = math.floor(iw / 8)
  local count = per * math.floor(ih / 8)
  for i = 0, count - 1 do
    local okQ, q = pcall(love.graphics.newQuad,
      (i % per) * 8, math.floor(i / per) * 8, 8, 8, iw, ih)
    if okQ and q then
      out[base + i] = { img = image, quad = q }
    end
  end
end

local function buildHudTiles(S)
  local src = menuSource(S, "battleHud") or {}
  local tiles = {}
  for i = 1, #HUD_PAGES do
    local page = HUD_PAGES[i]
    local rec = src[page.key]
    local base = (type(rec) == "table" and tonumber(rec.tileBase)) or page.base
    addHudPage(tiles, img(S, pathStr(rec) or pathOf(rec)), base)
  end
  return next(tiles) and tiles or nil
end

local function drawHudTile(tiles, code, x, y)
  local t = tiles and tiles[code]
  if not t then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(t.img, t.quad, x, y)
end

local function drawHudBar(tiles, tx, ty, frac, barType)
  local x, y = tx * 8, ty * 8
  drawHudTile(tiles, 0x71, x, y)
  drawHudTile(tiles, 0x62, x + 8, y)
  local px = math.max(1, math.floor((frac or 1) * 48))
  for i = 0, 5 do
    local seg = math.min(8, math.max(0, px - i * 8))
    drawHudTile(tiles, seg >= 8 and 0x6B or (0x63 + seg), x + 16 + i * 8, y)
  end
  drawHudTile(tiles, barType == 1 and 0x6D or 0x6C, x + 64, y)
end

local function hudNameX(tx, name)
  local n = #tostring(name or "")
  return tx * 8 + (n <= 2 and 16 or n <= 4 and 8 or 0)
end

local function menuWholeZones(S, name)
  local okP, P = pcall(require, "src.render.PaletteFX")
  local pal = namedPal(S, name)
  if not (okP and P and P.whole and pal) then return nil end
  return { P.whole(pal) }
end

local function presentMenu(st, S, palName, body)
  local zones = menuWholeZones(S, palName or "MEWMON")
  if zones then
    presentGbCanvas(st, body, zones)
  else
    body()
  end
end

local function buildBattleHudMenu(S, data)
  if Generation.isGen2(S) then
    local ok, BattleHud = pcall(require, "src.ui.gen2.BattleHud")
    if ok and BattleHud and BattleHud.new then
      local hud = BattleHud.new(data.gen2MenuGfx,
        data.gen2Palettes or data.palettes)
      if hud and hud.available and hud:available() then
        return { kind = "menus", id = "battleHud", hud = hud, done = false }
      end
    end
  end
  local tiles = buildHudTiles(S)
  if tiles then
    return {
      kind = "menus", id = "battleHud", tiles = tiles,
      enemyName = "PIDGEY", enemyLevel = 5,
      playerName = "RED", playerLevel = 12,
      done = false,
    }
  end
  return {
    kind = "menus", id = "battleHud",
    images = collectSheetImages(S, menuSource(S, "battleHud")),
    done = false,
  }
end

local function emoteRects(src, image)
  local iw, ih = 0, 0
  if image then
    local ok
    ok, iw, ih = pcall(function() return image:getWidth(), image:getHeight() end)
    if not ok then iw, ih = 0, 0 end
  end
  local cols = math.max(1, math.floor((iw > 0 and iw or 16) / 16))
  local rows = math.max(1, math.floor((ih > 0 and ih or 16) / 16))
  if image and cols * rows >= 1 then
    local rects = {}
    for row = 0, rows - 1 do
      for col = 0, cols - 1 do
        rects[#rects + 1] = { x = col * 16, y = row * 16, w = 16, h = 16 }
      end
    end
    return rects
  end
  local rects = {}
  if type(src) == "table" and type(src.bubbles) == "table" then
    for i = 1, #src.bubbles do
      local b = src.bubbles[i]
      if type(b) == "table" then
        rects[#rects + 1] = {
          x = tonumber(b.x) or 0, y = tonumber(b.y) or 0,
          w = tonumber(b.w) or 16, h = tonumber(b.h) or 16,
        }
      end
    end
  end
  return rects
end

local function buildEmoteMenu(S)
  local src = menuSource(S, "emotionBubbles") or {}
  local image = img(S, pathStr(src) or pathOf(src))
  return {
    kind = "menus", id = "emotionBubbles",
    image = image, rects = emoteRects(src, image),
    index = 1, timer = 0, done = false,
  }
end

UiPreview._ma = {
  emoteSkip = { order = true, palette = true, palettes = true },
  healPc = {
    machine = { { 26, 16 }, { 30, 16 } },
    balls = { { 24, 22 }, { 32, 22, true }, { 24, 27 }, { 32, 27, true },
      { 24, 32 }, { 32, 32, true } },
  },
  healOx = 48, healOy = 40, healLoop = 6 * 30 + 8 * 10,
  silver = {
    { 248, 248, 248 }, { 248, 248, 248 }, { 104, 104, 104 }, { 16, 16, 16 },
  },
}

function UiPreview._ma.buildEmotes(S)
  local src = menuSource(S, "emotes") or {}
  local skip = UiPreview._ma.emoteSkip
  local frames, used = {}, {}
  local function add(key)
    if not key or used[key] or skip[key] then return end
    local image = img(S, pathStr(src[key]) or pathOf(src[key]))
    if image then
      used[key] = true
      frames[#frames + 1] = { key = key, image = image }
    end
  end
  if type(src.order) == "table" then
    for i = 1, #src.order do add(src.order[i]) end
  end
  add("grassRustle")
  add("fishing")
  add("fishingFemale")
  local extra = {}
  for k in pairs(src) do
    if type(k) == "string" and not used[k] and not skip[k] then
      extra[#extra + 1] = k
    end
  end
  table.sort(extra)
  for i = 1, #extra do add(extra[i]) end
  return {
    kind = "menus", id = "emotes",
    frames = frames, index = 1, timer = 0, done = false,
  }
end

function UiPreview._ma.buildHeal(S)
  local src = menuSource(S, "healMachine") or {}
  local image = img(S, pathStr(src.sheet) or pathOf(src.sheet)
    or pathStr(src) or pathOf(src))
  if not image then
    return {
      kind = "menus", id = "healMachine",
      images = collectSheetImages(S, src),
      timer = 0, done = false,
    }
  end
  return {
    kind = "menus", id = "healMachine",
    image = image, palette = src.palette,
    timer = 0, done = false,
  }
end

local FX_ORDER = {
  "cutTree", "fishingRod", "healMachine", "smoke", "shadow",
  "battleTransition", "pokedexFrame",
  "redFishFront", "redFishBack", "redFishSide",
}

local function buildOverworldFx(S)
  local src = menuSource(S, "overworldFx") or {}
  local used = {}
  local scenes = {}
  local function add(key)
    if used[key] then return end
    local image = img(S, pathStr(src[key]) or pathOf(src[key]))
    if image then
      used[key] = true
      scenes[#scenes + 1] = { key = key, image = image }
    end
  end
  for i = 1, #FX_ORDER do add(FX_ORDER[i]) end
  local extra = {}
  for k, v in pairs(src) do
    if type(k) == "string" and not used[k]
        and (pathStr(v) or pathOf(v) ~= "") then
      extra[#extra + 1] = k
    end
  end
  table.sort(extra)
  for i = 1, #extra do add(extra[i]) end
  return {
    kind = "menus", id = "overworldFx",
    scenes = scenes, timer = 0, done = false,
  }
end

local function buildMenus(S)
  if Preview.installAssetCacheFallback then
    Preview.installAssetCacheFallback()
  end
  ensureFont(S)
  pcall(applyTheme, S)
  local id = tostring(S.uiMenuId or "")
  local data = minigamePreviewData(S)
  data.gen2Diploma = flattenGfxPaths(deepMerge(
    flattenGfxPaths(S.data and (S.data.gen2Diploma or S.data.diploma) or {}),
    S.project and S.project.diploma))
  data.diploma = data.gen2Diploma
  local game = stubGame(data)
  game.version = Generation.id(S)
  local mon = stubMenuSave(S, game)
  local gen2 = Generation.isGen2(S)
  local st

  if id == "naming" then
    if gen2 then
      st = movieOf(id, function()
        return require("src.ui.gen2.NamingScreen").new(game, {
          type = "player", initial = "GOLD",
        })
      end)
    else
      st = movieOf(id, function()
        return require("src.ui.NamingScreen").new(game, {})
      end)
    end
  elseif id == "pack" then
    st = movieOf(id, function()
      return require("src.ui.gen2.PackMenu").new(game, {})
    end)
  elseif id == "pokedex" then
    if gen2 then
      st = movieOf(id, function()
        return require("src.ui.gen2.PokedexMenu").new(game, {})
      end)
    else
      st = movieOf(id, function()
        return require("src.ui.PokedexMenu").new(game, {})
      end)
    end
  elseif id == "pokegear" then
    st = movieOf(id, function()
      return require("src.ui.gen2.Pokegear").new(game, {
        clock = { hour = 10, minute = 0, weekday = 2 },
      })
    end)
  elseif id == "billsPc" then
    st = movieOf(id, function()
      return require("src.ui.gen2.PcMenu").new(game, { bills = true })
    end)
  elseif id == "stats" then
    if gen2 then
      st = movieOf(id, function()
        return require("src.ui.gen2.SummaryMenu").new(game, { mon = mon })
      end)
    else
      st = movieOf(id, function()
        return require("src.ui.SummaryMenu").new(game, mon)
      end)
    end
  elseif id == "diploma" then
    if gen2 then
      st = movieOf(id, function()
        return require("src.ui.gen2.Diploma").new(game, {
          gfx = data.gen2Diploma, playerName = game.save.player.name,
        })
      end)
    else
      st = movieOf(id, function()
        return require("src.ui.Diploma").new(game)
      end)
    end
  elseif id == "eggHatch" then
    st = movieOf(id, function()
      return require("src.ui.gen2.EggHatchAnim").new(game, {
        species = mon.species, mon = mon,
      })
    end)
  elseif id == "slots" or id == "slotSymbols" then
    if gen2 then
      st = applySlotsArt(movieOf(id, function()
        return require("src.ui.gen2.SlotMachine").new(game, { save = game.save })
      end), data)
    else
      st = movieOf(id, function()
        return require("src.ui.SlotMachine").new(game, false)
      end)
    end
  elseif id == "cardFlip" then
    st = applyCardFlipArt(movieOf(id, function()
      return require("src.ui.gen2.CardFlip").new(game, { save = game.save })
    end), data)
  elseif id == "unownPuzzle" then
    st = movieOf(id, function()
      return require("src.ui.gen2.UnownPuzzle").new(game, { puzzle = 0 })
    end)
  elseif id == "tradeArt" then
    local recvSpec = otherSpecies(S, mon and mon.species)
    local recv = mon
    if recvSpec and mon and recvSpec ~= mon.species then
      local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
      if ok and Pokemon and Pokemon.new then
        local built
        ok, built = pcall(Pokemon.new, game.data, recvSpec, 10)
        if ok and built then recv = built end
      end
      if recv == mon then
        recv = {
          species = recvSpec, level = 10, hp = 30, maxHp = 30,
          nickname = recvSpec, stats = { hp = 30 },
        }
      end
    end
    st = movieOf(id, function()
      return require("src.ui.TradeAnim").new(game, {
        sent = mon, received = recv, enemyName = "BLUE",
      })
    end)
  elseif id == "emotionBubbles" then
    return buildEmoteMenu(S)
  elseif id == "emotes" then
    return UiPreview._ma.buildEmotes(S)
  elseif id == "healMachine" then
    return UiPreview._ma.buildHeal(S)
  elseif id == "overworldFx" then
    return buildOverworldFx(S)
  elseif id == "battleHud" then
    return buildBattleHudMenu(S, data)
  end

  if st then return st end
  return {
    kind = "menus", id = id,
    images = collectSheetImages(S, menuSource(S, id)),
    timer = 0, done = false,
  }
end

local function updateMenus(st)
  st.timer = (st.timer or 0) + 1
  local movie = st.movie
  if movie and movie.update then
    pcall(movie.update, movie, 0)
    st.done = movie.done == true or movie.finished == true
      or movie.phase == "quit" or movie.phase == "done"
    return
  end
  if st.id == "emotionBubbles" or st.id == "emotes" then
    local n = math.max(1,
      (st.frames and #st.frames) or (st.rects and #st.rects) or 1)
    st.index = 1 + math.floor((st.timer or 0) / 60) % n
  elseif st.id == "overworldFx" then
    local n = math.max(1, st.scenes and #st.scenes or 1)
    st.scene = 1 + math.floor((st.timer or 0) / 90) % n
  end
  st.done = false
end

local function drawSheetGrid(images)
  love.graphics.setColor(0.12, 0.16, 0.12, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  if type(images) ~= "table" or #images == 0 then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local n = #images
  local cols = n <= 2 and 1 or (n <= 4 and 2 or 3)
  local rows = math.ceil(n / cols)
  local cellW = GB_W / cols
  local cellH = GB_H / rows
  love.graphics.setColor(1, 1, 1, 1)
  for i, image in ipairs(images) do
    local ok, iw, ih = pcall(function()
      return image:getWidth(), image:getHeight()
    end)
    if ok and iw and ih and iw > 0 and ih > 0 then
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local sc = math.min((cellW - 4) / iw, (cellH - 4) / ih, 4)
      local dw, dh = iw * sc, ih * sc
      love.graphics.draw(image,
        col * cellW + (cellW - dw) / 2,
        row * cellH + (cellH - dh) / 2, 0, sc, sc)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawGen1BattleHud(st, S)
  local tiles = st.tiles
  local function body()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    local enemy = st.enemyName or "PIDGEY"
    local player = st.playerName or "RED"
    love.graphics.setColor(0, 0, 0, 1)
    pcall(function()
      local Font = require("src.render.Font")
      Font.draw(enemy, hudNameX(1, enemy), 0)
      Font.draw(tostring(st.enemyLevel or 5), 40, 8)
      Font.draw(player, hudNameX(10, player), 56)
      Font.draw(tostring(st.playerLevel or 12), 120, 64)
      Font.draw(" 32/ 40", 88, 80)
      Font.drawBox(0, 12, 20, 6)
      Font.draw("Wild " .. enemy, 8, 112)
      Font.draw("appeared!", 8, 128)
    end)
    love.graphics.setColor(1, 1, 1, 1)
    drawHudTile(tiles, 0x6E, 32, 8)
    drawHudTile(tiles, 0x73, 8, 16)
    drawHudBar(tiles, 2, 2, 0.85, 0)
    drawHudTile(tiles, 0x74, 8, 24)
    for i = 2, 9 do drawHudTile(tiles, 0x76, i * 8, 24) end
    drawHudTile(tiles, 0x78, 80, 24)
    drawHudTile(tiles, 0x6E, 112, 64)
    drawHudBar(tiles, 10, 9, 0.8, 1)
    drawHudTile(tiles, 0x73, 144, 80)
    drawHudTile(tiles, 0x77, 144, 88)
    for i = 10, 17 do drawHudTile(tiles, 0x76, i * 8, 88) end
    drawHudTile(tiles, 0x6F, 72, 88)
  end
  local zones
  local okP, P = pcall(require, "src.render.PaletteFX")
  if okP and P and P.whole and P.zone then
    local mew = namedPal(S, "MEWMON")
    if mew then
      zones = {
        P.whole(mew),
        P.zone(namedPal(S, "GREENBAR") or mew, 2, 2, 10, 2),
        P.zone(namedPal(S, "YELLOWBAR") or mew, 10, 9, 18, 9),
      }
    end
  end
  if zones then
    presentGbCanvas(st, body, zones)
  else
    body()
  end
end

local function drawEmotePreview(st, S)
  local function body()
    love.graphics.setColor(0.55, 0.78, 0.45, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, 96)
    love.graphics.setColor(0.72, 0.66, 0.42, 1)
    love.graphics.rectangle("fill", 0, 96, GB_W, 48)
    love.graphics.setColor(0.2, 0.2, 0.25, 1)
    love.graphics.rectangle("fill", 72, 88, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
    local frame = st.frames and st.frames[st.index or 1]
    if frame and frame.image then
      local ok, iw, ih = pcall(function()
        return frame.image:getWidth(), frame.image:getHeight()
      end)
      if ok and iw and ih then
        love.graphics.draw(frame.image, 80 - iw / 2, 88 - ih)
      end
      return
    end
    local rect = st.rects and st.rects[st.index or 1]
    if st.image and rect then
      local ok, q = pcall(love.graphics.newQuad, rect.x, rect.y, rect.w, rect.h,
        st.image:getDimensions())
      if ok and q then
        love.graphics.draw(st.image, q, 72, 68)
      end
    end
  end
  presentMenu(st, S, "MEWMON", body)
end

function UiPreview._ma.drawHeal(st, S)
  local ma = UiPreview._ma
  local t = (st.timer or 0) % ma.healLoop
  local lit, rot
  if t < 6 * 30 then
    lit, rot = 1 + math.floor(t / 30), 0
  else
    lit, rot = 6, (1 + math.floor((t - 6 * 30) / 10)) % 4
  end
  local function body()
    love.graphics.setColor(0.78, 0.72, 0.58, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    love.graphics.setColor(0.62, 0.56, 0.45, 1)
    love.graphics.rectangle("fill", 56, 96, 48, 24)
    love.graphics.setColor(0.2, 0.2, 0.25, 1)
    love.graphics.rectangle("fill", 72, 80, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
    local image = st.image
    if not image then return end
    local ok, iw, ih = pcall(function() return image:getWidth(), image:getHeight() end)
    if not (ok and iw and ih) then return end
    local okM, mq = pcall(love.graphics.newQuad, 0, 0, 8, 8, iw, ih)
    local okB, bq = pcall(love.graphics.newQuad, math.min(8, iw - 8), 0, 8, 8, iw, ih)
    if okM and mq then
      for i = 1, #ma.healPc.machine do
        local pos = ma.healPc.machine[i]
        love.graphics.draw(image, mq, ma.healOx + pos[1], ma.healOy + pos[2])
      end
    end
    if okB and bq then
      for i = 1, lit do
        local b = ma.healPc.balls[i]
        if b then
          if b[3] then
            love.graphics.draw(image, bq, ma.healOx + b[1] + 8, ma.healOy + b[2], 0, -1, 1)
          else
            love.graphics.draw(image, bq, ma.healOx + b[1], ma.healOy + b[2])
          end
        end
      end
    end
  end
  local pal
  if type(st.palette) == "table" and type(st.palette[1]) == "table" then
    pal = {}
    for i = 1, 4 do
      local c = st.palette[i]
      if type(c) == "table" then
        pal[i] = c.r and { c.r, c.g, c.b } or { c[1] or 0, c[2] or 0, c[3] or 0 }
      end
    end
    if not pal[1] then pal = nil end
  end
  pal = pal or namedPal(S, "MEWMON") or ma.silver
  local okP, P = pcall(require, "src.render.PaletteFX")
  if okP and P and P.permute and rot ~= 0 then
    local map = {}
    for i = 0, 3 do map[i] = (i + rot) % 4 end
    pal = P.permute(pal, map)
  end
  local zones = (okP and P and P.whole and pal) and { P.whole(pal) } or nil
  if zones then
    presentGbCanvas(st, body, zones)
  else
    body()
  end
end

local function drawTile8(image, index, tx, ty)
  local ok, iw, ih = pcall(function() return image:getWidth(), image:getHeight() end)
  if not (ok and iw and ih and iw >= 8) then return end
  local per = math.max(1, math.floor(iw / 8))
  local okQ, q = pcall(love.graphics.newQuad,
    (index % per) * 8, math.floor(index / per) * 8, 8, 8, iw, ih)
  if okQ and q then love.graphics.draw(image, q, tx * 8, ty * 8) end
end

local function drawOverworldFx(st, S)
  local scenes = st.scenes or {}
  local n = #scenes
  local hold = 90
  local scene = n > 0 and scenes[1 + math.floor(((st.timer or 0) / hold) % n)] or nil
  local t = (st.timer or 0) % hold
  local function body()
    local key = scene and scene.key
    local image = scene and scene.image
    if key == "pokedexFrame" and image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
      for tx = 1, 18 do
        drawTile8(image, 4, tx, 0)
        drawTile8(image, 15, tx, 17)
      end
      for ty = 1, 16 do
        drawTile8(image, 6, 0, ty)
        drawTile8(image, 7, 19, ty)
      end
      drawTile8(image, 3, 0, 0)
      drawTile8(image, 5, 19, 0)
      drawTile8(image, 12, 0, 17)
      drawTile8(image, 14, 19, 17)
      return
    end
    love.graphics.setColor(0.45, 0.72, 0.38, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, 80)
    love.graphics.setColor(0.72, 0.66, 0.42, 1)
    love.graphics.rectangle("fill", 0, 80, GB_W, 64)
    love.graphics.setColor(1, 1, 1, 1)
    if not image then return end
    if key == "cutTree" then
      local ok, iw, ih = pcall(function()
        return image:getWidth(), image:getHeight()
      end)
      if not (ok and iw and ih) then return end
      local half = math.min(8, ih)
      local okT, top = pcall(love.graphics.newQuad, 0, 0, math.min(16, iw), half, iw, ih)
      local okB, bot = pcall(love.graphics.newQuad, 0, half, math.min(16, iw),
        math.max(0, ih - half), iw, ih)
      local off = math.min(8, math.floor(t / 4))
      if t % 2 == 1 then love.graphics.setColor(1, 1, 1, 0.55) end
      if okT and top then love.graphics.draw(image, top, 72 + off, 64) end
      if okB and bot then love.graphics.draw(image, bot, 72 - off, 72) end
      love.graphics.setColor(1, 1, 1, 1)
    elseif key == "fishingRod" then
      love.graphics.setColor(0.2, 0.2, 0.25, 1)
      love.graphics.rectangle("fill", 72, 80, 16, 16)
      love.graphics.setColor(1, 1, 1, 1)
      local right = t >= 45
      local ok, iw, ih = pcall(function()
        return image:getWidth(), image:getHeight()
      end)
      if ok and iw and ih then
        local row = right and 1 or 0
        local okQ, q = pcall(love.graphics.newQuad, 0, row * 8, 8, 8, iw, ih)
        if okQ and q then
          if right then
            love.graphics.draw(image, q, 72 + 24, 80 + 4, 0, -1, 1)
          else
            love.graphics.draw(image, q, 72 + 4, 80 + 15 - 16)
          end
        end
      end
    elseif key == "healMachine" then
      if math.floor(t / 8) % 2 == 1 then
        love.graphics.setColor(1, 1, 1, 0.55)
      end
      local ok, iw, ih = pcall(function()
        return image:getWidth(), image:getHeight()
      end)
      if ok and iw and ih then
        local okM, mon = pcall(love.graphics.newQuad, 0, 0, 8, 8, iw, ih)
        local okB, ball = pcall(love.graphics.newQuad, 0, math.min(8, ih - 8), 8, 8, iw, ih)
        if okM and mon then love.graphics.draw(image, mon, 76, 56) end
        if okB and ball then
          love.graphics.draw(image, ball, 68, 72)
          love.graphics.draw(image, ball, 92, 72, 0, -1, 1)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    elseif key == "smoke" then
      local flicker = math.floor(t / 4) % 2 == 0
      love.graphics.setColor(1, 1, 1, flicker and 1 or 0.55)
      for i = 0, 1 do
        for j = 0, 1 do
          love.graphics.draw(image, 72 + i * 8, 72 + j * 8)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    elseif key == "battleTransition" then
      local r = 1 + math.floor(t / 8)
      for dy = -r, r do
        for dx = -r, r do
          if math.abs(dx) == r or math.abs(dy) == r then
            love.graphics.draw(image, 76 + dx * 8, 64 + dy * 8)
          end
        end
      end
    else
      local ok, iw, ih = pcall(function()
        return image:getWidth(), image:getHeight()
      end)
      if ok and iw and ih then
        love.graphics.draw(image, 80 - iw / 2, 72 - ih / 2)
      end
    end
  end
  presentMenu(st, S, "MEWMON", body)
end

local function drawMenusFrame(st, S)
  if st.movie then
    drawMoviePanel(st)
    return
  end
  if st.hud then
    love.graphics.setColor(0.55, 0.7, 0.45, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    love.graphics.setColor(1, 1, 1, 1)
    pcall(function() st.hud:drawEnemyFrame() end)
    pcall(function() st.hud:drawHpBar(48, 48, 2, 1) end)
    pcall(function() st.hud:drawPlayerFrame() end)
    pcall(function() st.hud:drawHpBar(32, 48, 10, 9) end)
    pcall(function() st.hud:drawExpBar(0.45, 10, 11) end)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if st.tiles then
    drawGen1BattleHud(st, S)
    return
  end
  if st.id == "emotionBubbles" or st.id == "emotes" then
    drawEmotePreview(st, S)
    return
  end
  if st.id == "healMachine" and st.image then
    UiPreview._ma.drawHeal(st, S)
    return
  end
  if st.id == "overworldFx" then
    drawOverworldFx(st, S)
    return
  end
  drawSheetGrid(st.images)
end

-- ---- public API ----

local BUILDERS = {
  title = buildTitle,
  intro = buildIntro,
  oak = buildOak,
  theme = buildTheme,
  fonts = buildFonts,
  strings = buildStrings,
  townmap = buildTownMap,
  badges = buildBadges,
  boot = buildBoot,
  credits = buildCredits,
  minigames = buildMinigames,
  menus = buildMenus,
}

local UPDATERS = {
  title = updateTitle,
  intro = updateIntro,
  oak = updateOak,
  theme = updateTheme,
  fonts = updateFonts,
  strings = updateStrings,
  townmap = updateTownMap,
  badges = updateBadges,
  boot = updateBoot,
  credits = updateCredits,
  minigames = updateMinigames,
  menus = updateMenus,
}

local DRAWERS = {
  title = drawTitleFrame,
  intro = drawIntroFrame,
  oak = drawOakFrame,
  theme = drawThemeFrame,
  fonts = drawFontsFrame,
  strings = drawStringsFrame,
  townmap = drawTownMapFrame,
  badges = drawBadgesFrame,
  boot = drawBootFrame,
  credits = drawCreditsFrame,
  minigames = drawMinigamesFrame,
  menus = drawMenusFrame,
}

local function songId(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function previewMusicId(S, mode, st)
  if mode == "title" then
    return songId(eff(S, "title", "music")) or "Music_TitleScreen"
  end
  if mode == "oak" then
    return songId(eff(S, "oakSpeech", "music"))
      or (Generation.isGen2(S) and "Music_Route30" or "Music_Routes2")
  end
  if mode == "credits" then
    return songId(eff(S, "credits", "music")) or "Music_Credits"
  end
  if mode == "minigames" then
    local kind = minigameKind(S)
    local owned = S.project and S.project.minigames and S.project.minigames[kind]
    local song = songId(owned and owned.music)
    if song then return song end
    if kind == "unown" then return nil end
    if kind == "surf" then return "Music_SurfingPikachu" end
    return "Music_GameCorner"
  end
  if mode == "intro" then
    local owned = songId(eff(S, "intro", "music"))
    if owned then return owned end
    if Generation.isCrystal(S) then return "Music_CrystalOpening" end
    if Generation.isGen2(S) then
      local scene = st and st.movie and tonumber(st.movie.scene)
      if scene and scene >= 10 then return "Music_GoldSilverOpening2" end
      return "Music_GoldSilverOpening"
    end
    if Generation.id(S) == "yellow" then
      local songs = S.data and S.data.audio and S.data.audio.songs
      if songs and songs.Music_YellowIntro then return "Music_YellowIntro" end
    end
    return "Music_IntroBattle"
  end
  return nil
end

local function stopUiPreviewMusic(S)
  if not (S and S.audioPreview and S.audioPreview.fromUiPreview) then return end
  local ok, Audio = pcall(require, "Audio")
  if ok and Audio and Audio.stopPreview then Audio.stopPreview(S) end
end

local function syncPreviewMusic(S, mode, playing, restart)
  if not S then return end
  if not playing then
    stopUiPreviewMusic(S)
    return
  end
  local song = previewMusicId(S, mode, S.uiPreview and S.uiPreview.state)
  if not song then
    stopUiPreviewMusic(S)
    return
  end
  local cur = S.audioPreview
  if not restart and cur and cur.fromUiPreview and cur.id == song then
    return
  end
  if not restart and S.uiPreviewMusicFail == song then return end
  local okA, Audio = pcall(require, "Audio")
  if not (okA and Audio and Audio.playPreview) then return end
  local ok, err = Audio.playPreview(S, "music", song)
  if ok and S.audioPreview then
    S.audioPreview.fromUiPreview = true
    S.audioPreview.id = song
    S.uiPreviewMusicFail = nil
    S.status = "Previewing UI · " .. tostring(mode) .. " · " .. song
  else
    S.uiPreviewMusicFail = song
    S.status = "Preview music: " .. tostring(err or "play failed")
  end
end

function UiPreview.stop(S)
  stopUiPreviewMusic(S)
  if S then S.uiPreview = nil end
end

function UiPreview.isPlaying(S)
  local p = S and S.uiPreview
  return p and p.playing and true or false
end

local PREVIEW_FP_BUCKET = {
  title = "title",
  intro = "intro",
  oak = "oakSpeech",
  credits = "credits",
  boot = "boot",
  theme = "theme",
  fonts = "font",
  strings = "strings",
  townmap = "townMap",
  badges = "trainerCard",
  minigames = "minigames",
  menus = "menuGfx",
}

local function fingerprint(v, depth, acc)
  if depth > 6 then return end
  local tv = type(v)
  if tv == "table" then
    if type(v.path) == "string" then
      acc[#acc + 1] = v.path
      return
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #keys do
      acc[#acc + 1] = tostring(keys[i])
      fingerprint(v[keys[i]], depth + 1, acc)
    end
  elseif tv == "string" or tv == "number" or tv == "boolean" then
    acc[#acc + 1] = tostring(v)
  end
end

local function previewStamp(S, mode)
  local parts = {
    tostring(mode or ""),
    tostring(S and S.uiPreviewTick or 0),
    tostring(Preview._rev or 0),
    tostring(S and S.uiFontId or ""),
    tostring(S and S.uiStrId or ""),
    tostring(S and S.uiTmLoc or ""),
    tostring(S and S.uiCreditIndex or 1),
    tostring(S and S.uiBadgeId or ""),
    tostring(S and S.uiMinigame or "slots"),
    tostring(S and S.uiUnownPuzzle or 0),
    tostring(S and S.uiSurfScreen or "title"),
    tostring(S and S.uiMenuId or ""),
  }
  local bucket = PREVIEW_FP_BUCKET[mode]
  if bucket and S and S.project then
    local acc = {}
    fingerprint(S.project[bucket], 0, acc)
    if mode == "oak" then fingerprint(S.project.text, 0, acc) end
    if mode == "badges" then
      fingerprint(S.project.constants and S.project.constants.badges, 0, acc)
    end
    if mode == "minigames" then
      local gfx = S.project.menuGfx
      fingerprint(gfx and gfx.slots, 0, acc)
      fingerprint(gfx and gfx.cardFlip, 0, acc)
      fingerprint(gfx and gfx.unownPuzzle, 0, acc)
      fingerprint(gfx and gfx.slotSymbols, 0, acc)
      fingerprint(gfx and gfx.surfPikachu, 0, acc)
    end
    if mode == "title" or mode == "intro" or mode == "minigames" then
      fingerprint(S.project.palettes, 0, acc)
    end
    if mode == "menus" then
      fingerprint(S.project.diploma, 0, acc)
    end
    parts[#parts + 1] = table.concat(acc, "\1")
  end
  return table.concat(parts, "\0")
end

local function capturePlay(p)
  local st = p and p.state
  if not st then return { playing = p and p.playing } end
  return {
    playing = p.playing,
    index = st.index,
    page = st.page,
    timer = st.timer,
    phase = st.phase,
    cycleIndex = st.cycleIndex,
    blink = st.blink,
    blinkTimer = st.blinkTimer,
  }
end

local function restorePlay(p, cap)
  if not (p and p.state and cap) then return end
  local st = p.state
  if cap.index ~= nil then
    local n = (st.beats and #st.beats)
      or (st.steps and #st.steps)
      or (st.sheets and #st.sheets)
      or 0
    if n > 0 then
      st.index = math.max(1, math.min(cap.index, n))
    else
      st.index = cap.index
    end
  end
  if cap.page ~= nil then
    local beat = st.beats and st.beats[st.index or 1]
    local nPages = math.max(1, beat and beat.pages and #beat.pages or 1)
    st.page = math.max(1, math.min(cap.page, nPages))
  end
  if cap.timer ~= nil then st.timer = cap.timer end
  if cap.phase ~= nil then st.phase = cap.phase end
  if cap.cycleIndex ~= nil then st.cycleIndex = cap.cycleIndex end
  if cap.blink ~= nil then st.blink = cap.blink end
  if cap.blinkTimer ~= nil then st.blinkTimer = cap.blinkTimer end
end

-- Keep a GB preview on screen and rebuild when UI fields / images change.
local function ensureLive(S, mode)
  local stamp = previewStamp(S, mode)
  local p = S and S.uiPreview
  if p and p.mode == mode and p.state and p.stamp == stamp then
    return p
  end
  local cap = (p and p.mode == mode) and capturePlay(p) or { playing = true }
  if not UiPreview.begin(S, mode, true) then
    return S and S.uiPreview
  end
  p = S and S.uiPreview
  if p then
    restorePlay(p, cap)
    p.playing = cap.playing ~= false
    p.stamp = stamp
  end
  return p
end

function UiPreview.begin(S, mode, quiet)
  if not S or not mode then return false end
  local builder = BUILDERS[mode]
  if not builder then
    S.status = "No UI preview for " .. tostring(mode)
    return false
  end
  State.ensureProjectFields(S.project)
  local ok, st = pcall(builder, S)
  if not ok or type(st) ~= "table" then
    S.status = "UI preview build failed: " .. tostring(st)
    return false
  end
  S.uiPreview = {
    mode = mode,
    state = st,
    playing = true,
    accum = 0,
    loop = S.uiPreviewLoop ~= false,
  }
  if not quiet then
    S.status = "Previewing UI · " .. mode
  end
  return true
end

function UiPreview.rebuild(S)
  local p = S and S.uiPreview
  if not p or not p.mode then return end
  local playing = p.playing
  UiPreview.begin(S, p.mode)
  if S.uiPreview then S.uiPreview.playing = playing end
end

local function sequenceDone(mode, st)
  if mode == "intro" or mode == "oak" or mode == "credits"
      or mode == "minigames" or mode == "menus" then
    return st.done == true
  end
  if mode == "title" and st.yellowLayout then
    return st.phase == "loop" and (st.blinkTimer or 0) >= 200
  end
  if mode == "boot" then
    return (st.cycles or 0) >= 1
  end
  -- Continuous previews (theme/fonts/strings/townmap/badges/RB title): never "done"
  return false
end

function UiPreview.update(S, dt)
  local p = S and S.uiPreview
  if not p or not p.playing or not p.state then return end
  -- Rebuild theme/strings/fonts/badges when selection changes while playing.
  if p.mode == "fonts" and p.state.id ~= S.uiFontId then
    UiPreview.begin(S, "fonts")
    p = S.uiPreview
    if not p then return end
  end
  if p.mode == "badges" and p.state.gen2 and p.state.card == nil then
    UiPreview.begin(S, "badges")
    p = S.uiPreview
    if not p then return end
  end
  if p.mode == "strings" then
    local src = S.uiStrId
    local want = src and resolveStr(S, src) or ""
    if p.state.source ~= src or p.state.text ~= want then
      UiPreview.begin(S, "strings")
      p = S.uiPreview
      if not p then return end
    end
  end
  p.accum = (p.accum or 0) + (dt or 0)
  local frames = math.floor(p.accum * 60)
  if frames < 1 then return end
  p.accum = p.accum - frames / 60
  if frames > 5 then frames = 5 end
  local updater = UPDATERS[p.mode]
  local loop = S.uiPreviewLoop ~= false
  for _ = 1, frames do
    if updater then updater(p.state, S) end
    if not loop and sequenceDone(p.mode, p.state) then
      p.playing = false
      break
    elseif loop and sequenceDone(p.mode, p.state) then
      -- Restart long sequences
      if p.mode == "intro" or p.mode == "oak" or p.mode == "title"
          or p.mode == "boot" or p.mode == "credits"
          or p.mode == "minigames" or p.mode == "menus" then
        local ok, st = pcall(BUILDERS[p.mode], S)
        if ok and type(st) == "table" then p.state = st end
      end
    end
  end
  syncPreviewMusic(S, p.mode, p.playing)
end

-- Draw Play/Stop + scaled GB viewport. Returns y below the widget.
function UiPreview.draw(S, mode, x, y, w, s)
  s = s or Kit.scale
  local fh = 28 * s
  Kit.text("small", "UI preview", x, y, PAL.caption)
  y = y + 18 * s

  local p = ensureLive(S, mode)
  local active = p and p.mode == mode and p.state
  local playing = active and p.playing

  if Kit.chip(x, y, 72 * s, fh, playing and "STOP" or "PLAY",
      playing, PAL.green, PAL.steel,
      playing and "Pause the preview"
        or "Play the preview") then
    if p then
      p.playing = not playing
    elseif not playing then
      p = ensureLive(S, mode)
      if p then p.playing = true end
    end
    playing = p and p.playing
    active = p and p.mode == mode and p.state
  end

  local loop = S.uiPreviewLoop ~= false
  if Kit.chip(x + 80 * s, y, 72 * s, fh, loop and "LOOP" or "ONCE",
      loop, PAL.blue, PAL.steel,
      loop and "Replay the preview when it ends"
        or "Play the preview once, then stop") then
    S.uiPreviewLoop = not loop
    if p then p.loop = S.uiPreviewLoop ~= false end
  end

  if Kit.chip(x + 160 * s, y, 88 * s, fh, "RELOAD", false, PAL.yellow,
      PAL.steel, "Restart the preview from the first frame") then
    UiPreview.begin(S, mode)
    p = S.uiPreview
    if p then
      p.stamp = previewStamp(S, mode)
      p.playing = true
      p.restartMusic = true
    end
    active = p and p.mode == mode and p.state
    playing = active and p.playing
  end

  local restartMusic = p and p.restartMusic
  if p then p.restartMusic = nil end
  syncPreviewMusic(S, mode, playing, restartMusic)

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

  if active and p and p.state then
    local drawer = DRAWERS[mode]
    if drawer then
      love.graphics.setColor(1, 1, 1, 1)
      pcall(drawer, p.state, S)
    end
  else
    love.graphics.setColor(0.12, 0.14, 0.22, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    love.graphics.setColor(1, 1, 1, 0.35)
  end

  love.graphics.pop()
  Kit.popClip()

  local tips = {
    title = "Ho-Oh flap + cloud scroll · live",
    intro = "copyright → studio splash → fight / Gen2 cinema / Yellow · live",
    oak = "Oak pic + speech lines · live",
    theme = "textBox / choiceBox + blinking cursor · live",
    fonts = "scroll selected font sheet · live",
    strings = "selected string in a text box · live",
    townmap = "tiled Kanto map + cursor (Red) / pokegear landmarks (Gold) · live",
    badges = "trainer card badge grid · live",
    boot = "splash → title → newGame screen ids · live",
    credits = "Hall of Fame credits roll · live",
    minigames = "Game Corner / Unown puzzle / Pikachu's Beach · live",
    menus = "In-game chrome screens · live",
  }
  local info = tips[mode] or mode
  if active and p and p.state then
    if mode == "title" and p.state.crystal then
      info = "Suicune + gem · PLAY to animate"
    elseif mode == "title" and p.state.phase then
      info = string.format("title · %s", tostring(p.state.phase))
    elseif mode == "intro" then
      if p.state.kind == "movie" then
        local scene = p.state.movie and p.state.movie.scene
        info = string.format("intro · scene %s", tostring(scene or "?"))
      elseif p.state.kind == "cinema" then
        local sheet = p.state.sheets and p.state.sheets[p.state.index or 1]
        info = string.format("intro · %s", tostring(sheet and sheet.label or "cinema"))
      else
        info = string.format("intro · phase %d", tonumber(p.state.phase) or 0)
      end
    elseif mode == "oak" then
      local beat = p.state.beats and p.state.beats[p.state.index or 1]
      info = string.format("oak · %s", tostring(beat and beat.label or "speech"))
    elseif mode == "boot" and p.state.steps then
      local step = p.state.steps[p.state.index]
      info = string.format("boot · %s = %s",
        tostring(step and step.key), tostring(step and step.id))
    elseif mode == "badges" and p.state.gen2 and p.state.names then
      info = string.format("badges · %s",
        tostring(p.state.names[p.state.highlight] or "?"))
    elseif mode == "credits" then
      info = string.format("credits · card %s", tostring(S.uiCreditIndex or 1))
    elseif mode == "minigames" then
      if S.uiMinigame == "surf" then
        info = string.format("minigames · surf · %s",
          tostring(S.uiSurfScreen or "title"))
      else
        info = string.format("minigames · %s", tostring(S.uiMinigame or "slots"))
      end
    elseif mode == "menus" then
      info = string.format("menus · %s", tostring(S.uiMenuId or "?"))
    elseif mode == "townmap" and p.state.gen2 then
      info = "town map · pokegear landmarks"
    end
  end
  Kit.text("micro", Kit.ellipsize("micro", info, w), x, y + vh + 12 * s, PAL.muted)
  return y + vh + 28 * s
end

-- ---- dialog text-box preview (Dialog tab) ----

local function previewSubstitute(text)
  text = tostring(text or "")
  text = text:gsub("{PLAYER}", "RED")
  text = text:gsub("{RIVAL}", "BLUE")
  return text
end

-- Live Gen1 text-box preview of dialog body (not a full GB screen).
-- opts: page (1-based), lineStart (1-based scroll within page)
-- Returns height consumed, info { page, pageCount, lineStart, canPrev, canNext, hasMore }.
function UiPreview.drawTextBoxPreview(S, text, x, y, maxW, opts)
  opts = opts or {}
  local s = Kit.scale
  local eng = applyTheme(S)
  local tb = eng.textBox or THEME_DEFAULTS.textBox
  local tw = tonumber(tb.tw) or 20
  local th = tonumber(tb.th) or 6
  local maxCols = tonumber(tb.maxCols) or 18
  local boxW, boxH = tw * 8, th * 8

  local substituted = previewSubstitute(text)
  local pages = { { "" } }
  local okPaginate, TextBox = pcall(require, "src.render.TextBox")
  if okPaginate and TextBox.paginate then
    local ok, result = pcall(TextBox.paginate, substituted, maxCols)
    if ok and type(result) == "table" and #result > 0 then
      pages = result
    end
  end

  local pageCount = #pages
  local page = math.max(1, math.min(pageCount, tonumber(opts.page) or 1))
  local lines = pages[page] or { "" }
  local maxLineStart = math.max(1, #lines - 1)
  if #lines <= 2 then maxLineStart = 1 end
  local lineStart = math.max(1, math.min(maxLineStart, tonumber(opts.lineStart) or 1))
  local line1 = lines[lineStart] or ""
  local line2 = lines[lineStart + 1] or ""
  local hasMore = (lineStart + 1 < #lines) or (page < pageCount)
  local canPrev = page > 1 or lineStart > 1
  local canNext = hasMore

  local scale = math.max(1, math.floor((maxW or boxW) / boxW))
  local vw, vh = boxW * scale, boxH * scale
  local pad = 4 * s
  local frameW = vw + pad * 2
  local frameH = vh + pad * 2

  Theme.col(PAL.bgBot or PAL.card, 1)
  love.graphics.rectangle("fill", x, y, frameW, frameH, 6 * s, 6 * s)

  local vx, vy = x + pad, y + pad
  Kit.pushClip(vx, vy, vw, vh)
  love.graphics.push()
  love.graphics.translate(vx, vy)
  love.graphics.scale(scale, scale)

  local fontOk = ensureFont(S)
  if fontOk then
    local Font = require("src.render.Font")
    love.graphics.setColor(1, 1, 1, 1)
    pcall(Font.drawBox, 0, 0, tw, th)
    love.graphics.setColor(0, 0, 0, 1)
    pcall(Font.draw, line1, 8, 16)
    pcall(Font.draw, line2, 8, 32)
    -- Blinking ▼: more text, or wait-for-A/B at end of the box (classic look).
    local blink = 0
    if love and love.timer and love.timer.getTime then
      blink = math.floor(love.timer.getTime() * 2) % 2
    elseif Kit.time then
      blink = math.floor((Kit.time or 0) * 2) % 2
    end
    if blink == 0 then
      local arrow = eng.moreArrow or THEME_DEFAULTS.moreArrow or 0xEE
      pcall(Font.drawCode, arrow, (tw - 2) * 8, (th - 1) * 8 - 4)
    end
  else
    -- No ROM font sheets: approximate the box so editing still has a preview.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, boxW, boxH)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", 0.5, 0.5, boxW - 1, boxH - 1)
    love.graphics.rectangle("line", 2.5, 2.5, boxW - 5, boxH - 5)
    if love.graphics.print then
      love.graphics.print(line1, 8, 16)
      love.graphics.print(line2, 8, 32)
      love.graphics.print("v", (tw - 2) * 8, (th - 1) * 8 - 4)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
  Kit.popClip()

  local info = {
    page = page,
    pageCount = pageCount,
    lineStart = lineStart,
    canPrev = canPrev,
    canNext = canNext,
    hasMore = hasMore,
    scale = scale,
    frameW = frameW,
    frameH = frameH,
  }
  return frameH, info
end

-- Step preview navigation within paginated dialog text.
-- dir: -1 prev, +1 next. Returns new page, lineStart.
function UiPreview.stepTextBoxPreview(S, text, page, lineStart, dir)
  local eng = applyTheme(S)
  local tb = eng.textBox or THEME_DEFAULTS.textBox
  local maxCols = tonumber(tb.maxCols) or 18
  local pages = { { "" } }
  local okPaginate, TextBox = pcall(require, "src.render.TextBox")
  if okPaginate and TextBox.paginate then
    local ok, result = pcall(TextBox.paginate, previewSubstitute(text), maxCols)
    if ok and type(result) == "table" and #result > 0 then pages = result end
  end
  page = math.max(1, math.min(#pages, tonumber(page) or 1))
  local lines = pages[page] or { "" }
  local maxLineStart = math.max(1, #lines <= 2 and 1 or (#lines - 1))
  lineStart = math.max(1, math.min(maxLineStart, tonumber(lineStart) or 1))
  dir = tonumber(dir) or 0
  if dir > 0 then
    if lineStart + 1 < #lines then
      return page, lineStart + 1
    elseif page < #pages then
      return page + 1, 1
    end
  elseif dir < 0 then
    if lineStart > 1 then
      return page, lineStart - 1
    elseif page > 1 then
      local prev = pages[page - 1] or { "" }
      local prevStart = math.max(1, #prev <= 2 and 1 or (#prev - 1))
      return page - 1, prevStart
    end
  end
  return page, lineStart
end

return UiPreview
