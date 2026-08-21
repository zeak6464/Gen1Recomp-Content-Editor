local ok, err = pcall(function()
  package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;"
    .. "tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
    .. package.path
  -- stub love for Preview
  love = love or {}
  love.filesystem = love.filesystem or {
    getInfo = function() return nil end,
    getSource = function() return "." end,
    newFileData = function() error("no") end,
  }
  love.graphics = love.graphics or {
    newImage = function() end,
    setColor = function() end,
    rectangle = function() end,
    draw = function() end,
  }
  local Preview = require("Preview")
  local Trainers = require("Trainers")
  local Pokemon = require("Pokemon")
  local Manifest = require("Manifest")
  local Code = require("Code")
  local MoveEffects = require("MoveEffects")
  local Audio = require("Audio")
  local Gfx = require("Gfx")
  local AiClasses = require("AiClasses")
  local Project = require("Project")
  local Ui = require("Ui")
  local UiPreview = require("UiPreview")
  local SpriteUtil = require("SpriteUtil")
  local EncounterEdit = require("EncounterEdit")
  local Encounters = require("Encounters")
  local ModWriter = require("ModWriter")
  assert(SpriteUtil.createNew)
  assert(EncounterEdit.drawWild)
  assert(Encounters.draw)
  assert(ModWriter.emitSpecialEncounters)
  assert(ModWriter.applySpecialEncounterBinds)
  assert(ModWriter.ensureTrainerHeaders)
  do
    local stubS = { project = { sprites = {} }, data = { sprites = {} } }
    local id, rec = SpriteUtil.createNew(stubS)
    assert(id == "SPRITE_MOD", id)
    assert(rec and rec._isNew)
    local id2 = SpriteUtil.createNew(stubS)
    assert(id2 == "SPRITE_MOD_2", id2)
  end
  assert(Preview.draw)
  assert(Trainers.draw)
  assert(Pokemon.draw)
  assert(Manifest.draw)
  assert(Code.draw)
  assert(MoveEffects.draw)
  assert(Audio.draw)
  assert(Gfx.draw)
  assert(AiClasses.draw)
  assert(Project.draw)
  assert(Ui.draw)
  assert(UiPreview.draw)
  assert(UiPreview.begin)
  assert(UiPreview.update)
  assert(ModWriter.emitMain)
  local sample = ModWriter.emitMain({
    id = "t", palettes = { P = { colors = { {1,2,3},{4,5,6},{7,8,9},{0,0,0} }, _isNew = true } },
    audio = { songs = { Music_X = { file = "assets/x.ogg" } } },
    aiClasses = { OPP_X = { kind = "class", uses = 1, _isNew = true } },
    -- nil _isNew on a vanilla id must patch (register would error under api 2)
    moves = {
      ROCK_SLIDE = {
        id = "ROCK_SLIDE", name = "ROCK SLIDE", type = "ROCK",
        power = 75, accuracy = 100, pp = 10, effect = "FLINCH_SIDE_EFFECT2",
      },
    },
    boot = { startMap = "PALLET_TOWN",
      screens = { splash = "YellowIntro", title = "TitleState", newGame = "OakSpeech" } },
    constants = {
      levelCap = 80,
      badges = { { id = "BOULDERBADGE", name = "Boulder", icon = "assets/badges/boulder.png" } },
    },
    title = { logo = "assets/logo.png", music = "Music_TitleScreen",
      copyrightText = "(C) test", cycleSpecies = { "PIKACHU" } },
    intro = { skip = true, studio = { logo = "assets/studio.png", credit = "presents" } },
    theme = { cursor = 237, textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 } },
    font = { main = { image = "assets/font/main.png", base = 0, glyphsPerRow = 16, _isNew = true } },
    strings = { ["NEW GAME"] = "START" },
    townMap = { gridPixelSize = 8, locations = { PALLET_TOWN = { x = 3, y = 14, name = "Pallet" } } },
    hiddenItems = { PALLET_TOWN = { { x = 1, y = 2, item = "POTION" } } },
    badgeGates = {},
    moveEffects = {
      FX_RECOIL = { id = "FX_RECOIL", template = "recoil", recoilDiv = 4 },
    },
    maps = {
      VIRIDIAN_CITY = {
        id = "VIRIDIAN_CITY", label = "ViridianCity",
        width = 1, height = 1, blocks = { 1 }, tileset = "OVERWORLD",
        objects = {
          { index = 2, x = 1, y = 1, sprite = "SPRITE_YOUNGSTER",
            text = "TEXT_VIRIDIANCITY_SIGN" },
        },
      },
    },
    specialEncounters = {
      MAGIKARP_LEGEND = {
        kind = "gift", mapId = "PALLET_TOWN", species = "MAGIKARP",
        level = 100, moves = { "HYDRO_PUMP" },
        dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 },
        unique = true, flag = "GOT_MAGIKARP_LEGEND",
        text = "A legendary fish!", after = "Already gifted.",
        bindTextId = "TEXT_PALLETTOWN_SIGN",
      },
      SPEC_BATTLE = {
        kind = "battle", mapId = "VIRIDIAN_CITY", species = "MAGIKARP",
        level = 100, moves = { "HYDRO_PUMP", "TACKLE" },
        dvs = { attack = 15, defense = 15, speed = 15, special = 15 },
        unique = true, flag = "BEAT_SPEC_BATTLE",
        text = "Fight!", won = "Wow!", after = "Strong.",
        bindTextId = "TEXT_VIRIDIANCITY_SIGN",
      },
    },
  }, {
    moves = {
      ROCK_SLIDE = {
        id = "ROCK_SLIDE", name = "ROCK SLIDE", type = "ROCK",
        power = 75, accuracy = 90, pp = 10, effect = "FLINCH_SIDE_EFFECT2",
      },
    },
  })
  assert(sample:find('moves:patch%("ROCK_SLIDE"'), sample)
  assert(sample:find("accuracy = 100"), sample)
  assert(not sample:find('moves:register%("ROCK_SLIDE"'), sample)
  assert(sample:find("mod.content.palettes:register"), sample)
  assert(sample:find("mod.content.music:"), sample)
  assert(sample:find("mod.content.ai_classes:"), sample)
  assert(sample:find('field:patch%("boot"'), sample)
  assert(sample:find("YellowIntro"), sample)
  assert(sample:find('field:patch%("title"'), sample)
  assert(sample:find('field:patch%("intro"'), sample)
  assert(sample:find('field:patch%("theme"'), sample)
  assert(sample:find('field:patch%("townMap"'), sample)
  assert(sample:find("mod.content.font:register"), sample)
  assert(sample:find("mod.content.strings:override"), sample)
  assert(sample:find("assets/badges/boulder.png") or sample:find("boulder"), sample)
  assert(sample:find("move_effects:register"), sample)
  assert(sample:find('trainers:register%("OPP_SPEC_SPEC_BATTLE"'), sample)
  assert(sample:find("trainer_headers:patch"), sample)
  assert(sample:find("ViridianCity"), sample)
  assert(sample:find("OPP_SPEC_SPEC_BATTLE"), sample)
  assert(sample:find("give_special"), sample)
  assert(sample:find("SPECIALS"), sample)
  assert(sample:find("HYDRO_PUMP"), sample)
  assert(sample:find("TEXT_PALLETTOWN_SIGN"), sample)
  -- Bound battle specials use trainer_headers, not a start_battle talk script.
  assert(not sample:find('"start_battle"'), sample)
  assert(sample:find('"OPP_SPEC_SPEC_BATTLE"'), sample)
  assert(sample:find('"t:give_special"'), sample)
  do
    local Gen2Talk = require("Gen2Talk")
    local cmds = {
      { op = "faceplayer" },
      { op = "iftrue", script = "55:4dc0" },
      { class = 3, member = 1, op = "loadtrainer" },
      { op = "startbattle" },
      { op = "special", id = 56 },
    }
    local steps = Gen2Talk.cmdsToSteps(cmds)
    local stub = { project = { scripts = {}, scriptSteps = {}, text = {} } }
    local back = Gen2Talk.stepsToCmds(stub, "55:4d96", steps)
    local found = false
    for _, c in ipairs(back) do
      if c.op == "loadtrainer" and c.class == 3 then found = true end
    end
    assert(found, "Gen2Talk cmds↔steps lost loadtrainer")
  end
  do
    local Gen2Talk = require("Gen2Talk")
    local Breeding = require("Breeding")
    assert(Breeding.draw)
    local cmds = {
      { op = "loadvar", args = { 3, 7 } },
      { op = "loadwildmon", species = 130, level = 30 },
      { op = "startbattle" },
      { op = "reloadmapafterbattle" },
    }
    local steps = Gen2Talk.cmdsToSteps(cmds)
    local wild
    for _, st in ipairs(steps) do
      if st.kind == "wild_battle" then wild = st end
    end
    assert(wild and wild.forceShiny, "forceShiny not folded into wild_battle")
    local stub = { project = { scripts = {}, scriptSteps = {}, text = {} } }
    local back = Gen2Talk.stepsToCmds(stub, "test:shiny", steps)
    local sawLoadvar, sawWild = false, false
    for _, c in ipairs(back) do
      if c.op == "loadvar" and c.args and c.args[1] == 3 and c.args[2] == 7 then
        sawLoadvar = true
      end
      if c.op == "loadwildmon" then sawWild = true end
    end
    assert(sawLoadvar and sawWild, "forceShiny wild_battle lost loadvar")
  end
  do
    -- Gold emit paths for shiny rate / breeding (stub GameVersion → gold).
    package.loaded["src.core.GameVersion"] = nil
    package.preload["src.core.GameVersion"] = function()
      return {
        get = function() return "gold" end,
        generation = function(id) return (id == "gold" or id == "silver") and 2 or 1 end,
      }
    end
    package.loaded["Generation"] = nil
    local ModWriter = require("ModWriter")
    local out = ModWriter.emitMain({
      id = "t",
      shinyRate = 4096,
      breeding = { eggLevel = 5, minStepsToEgg = 100 },
    }, {})
    assert(out:find("shinyRate = 4096"), "missing shinyRate emit")
    assert(out:find("data.breeding"), "missing breeding emit")
    package.preload["src.core.GameVersion"] = nil
    package.loaded["src.core.GameVersion"] = nil
    package.loaded["Generation"] = nil
  end
  print("OK modules load")
end)
if not ok then print("FAIL", err); os.exit(1) end
