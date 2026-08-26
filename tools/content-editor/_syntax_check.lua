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
  local Cart = require("Cart")
  local Code = require("Code")
  local MoveEffects = require("MoveEffects")
  local Audio = require("Audio")
  local Gfx = require("Gfx")
  local AiClasses = require("AiClasses")
  local Rules = require("Rules")
  local Project = require("Project")
  local Ui = require("Ui")
  local UiPreview = require("UiPreview")
  local SpriteUtil = require("SpriteUtil")
  local SpriteAnimPreview = require("SpriteAnimPreview")
  local EncounterEdit = require("EncounterEdit")
  local Encounters = require("Encounters")
  local ModWriter = require("ModWriter")
  local EventScriptEditor = require("EventScriptEditor")
  local OpcodeHelp = require("OpcodeHelp")
  assert(OpcodeHelp.label("checkevent") == "Check story flag")
  assert(OpcodeHelp.label("end") == "End script")
  assert(OpcodeHelp.label("farjumptext") == "Say far text and end")
  local Generation = require("Generation")
  assert(Generation.coversGen2({ "crystal" }) == true)
  assert(Generation.coversGen2({ "gold" }) == true)
  assert(Generation.num({ version = "crystal" }) == 2)
  assert(Generation.engine({ version = "crystal" }) == "crystal")
  assert(EventScriptEditor.draw)
  assert(EventScriptEditor.defaultStep)
  assert(EventScriptEditor.stepLine)
  assert(ModWriter.encodeLua)
  do
    local encoded = ModWriter.encodeLua({
      format = "gen1recomp-event-script",
      version = 1,
      scriptKey = "TEST_NPC",
      steps = { { kind = "show_text", text = "Hi" } },
      text = { TEST_NPC_TEXT = "Hello!" },
    })
    assert(encoded:find("gen1recomp%-event%-script"), encoded)
    assert(encoded:find("show_text"), encoded)
    assert(encoded:find("TEST_NPC_TEXT"), encoded)
  end
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
  assert(Cart.draw)
  assert(Cart.save)
  local CartPreview = require("CartPreview")
  assert(CartPreview.draw)
  assert(CartPreview.hex({ 139, 26, 26 }) == "#8b1a1a")
  local parsedShell = CartPreview.parseShell("#8B1A1A")
  assert(parsedShell and parsedShell[1] == 139 and parsedShell[2] == 26)
  assert(CartPreview.parseShell("nope") == nil)
  local Cartkit = require("Cartkit")
  local encoded = Cartkit.encodeCart({
    schema = 1, id = "demo", title = "Demo", version = "1.0.0",
    author = "you", shell = "#8b1a1a", label = "label.png",
    base = "red", engine = ">=0.1.0 <1.0.0", seal = "sealed",
    mods = {
      { id = "mod-a", source = "github", repo = "own/mod-a",
        version = "1.2.3", sha256 = string.rep("a", 64) },
      { id = "mod-b", source = "local", version = "0.4.0" },
    },
  })
  assert(encoded:find('"id":"demo"') or encoded:find('"id": "demo"'), encoded)
  assert(encoded:find("mod%-a"), encoded)
  assert(encoded:find('"source":"local"') or encoded:find('"source": "local"'), encoded)
  assert(encoded:find("mod%-b"), encoded)
  assert(Cartkit.BASES[1] == "red")
  do
    local i1 = Cartkit.interpret(
      "CK003 ERROR label.png: label art is 1157355 bytes; keep it under 1048576\nFAIL x invalid")
    assert(i1.hardFail == true and i1.labelTooBig == true)
    local i2 = Cartkit.interpret(
      "CK004 ERROR cart.json: mods[1] DebugMenu is pinned to one install; a published cart needs a github or gamebanana pin\nFAIL DebugBlue invalid")
    assert(i2.localPins == true and i2.hardFail == false)
    local shown = Cartkit.displayLog(
      "CK004 ERROR cart.json: mods[1] DebugMenu is pinned to one install; a published cart needs a github or gamebanana pin\nFAIL DebugBlue invalid",
      i2)
    assert(not shown:find("FAIL", 1, true), shown)
    assert(not shown:find("ERROR", 1, true), shown)
    assert(shown:find("this PC", 1, true), shown)
    assert(Cartkit.hasLocalPins({ mods = { { source = "local" } } }) == true)
    assert(Cartkit.hasLocalPins({ mods = { { source = "github" } } }) == false)
    assert(Cartkit.packBundle)
  end
  assert(Code.draw)
  assert(MoveEffects.draw)
  assert(Audio.draw)
  assert(Gfx.draw)
  assert(AiClasses.draw)
  assert(Rules.draw)
  assert(Project.draw)
  local TalkIndex = require("TalkIndex")
  local UiMenus = require("UiMenus")
  assert(TalkIndex.catalogLabel("_STD") == "Std scripts")
  assert(TalkIndex.isCatalogMap("_STD") == true)
  assert(TalkIndex.isCatalogMap("NEW_BARK_TOWN") == false)
  assert(TalkIndex.collect)
  assert(Ui.draw)
  assert(UiMenus.draw)
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
      screens = { splash = "YellowIntro", title = "TitleState", newGame = "OakSpeech" },
      namePresets = { player = { "RED", "ASH" }, rival = { "BLUE" } } },
    statuses = { BRN = { label = "BRN", catchBonus = 12 } },
    rulesets = { no_crits = { name = "no crits", critRate = 0, _isNew = true } },
    transitions = { warp_fade = { frames = 48, flash = false } },
    battle_sprite_scales = {
      abra_back = { path = "assets/back.png", scale = 1.5, _isNew = true },
    },
    constants = {
      levelCap = 80,
      badges = { { id = "BOULDERBADGE", name = "Boulder", icon = "assets/badges/boulder.png" } },
    },
    title = { logo = "assets/logo.png", music = "Music_TitleScreen",
      copyrightText = "(C) test", cycleSpecies = { "PIKACHU" } },
    intro = { skip = true, studio = { logo = "assets/studio.png", credit = "presents" } },
    oakSpeech = { oakPic = "assets/oak.png", music = "Music_Routes2" },
    trainerCard = { badges = "assets/badges_sheet.png" },
    theme = { cursor = 237, textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 } },
    font = { main = { image = "assets/font/main.png", base = 0, glyphsPerRow = 16, _isNew = true } },
    strings = { ["NEW GAME"] = "START" },
    townMap = { gridPixelSize = 8, locations = { PALLET_TOWN = { x = 3, y = 14, name = "Pallet" } } },
    menuGfx = {
      overworldFx = { cutTree = { path = "assets/fx/cut_tree.png" } },
      battleHud = { hud1 = { path = "assets/battle/hud1.png" } },
    },
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
  assert(sample:find("mod.content.statuses:"), sample)
  assert(sample:find("mod.content.rulesets:register"), sample)
  assert(sample:find("mod.content.transitions:"), sample)
  assert(sample:find("mod.content.battle_sprite_scales:register"), sample)
  assert(sample:find("namePresets"), sample)
  assert(sample:find('field:patch%("boot"'), sample)
  assert(sample:find("YellowIntro"), sample)
  assert(sample:find('field:patch%("title"'), sample)
  assert(sample:find('field:patch%("intro"'), sample)
  assert(sample:find('field:patch%("oakSpeech"'), sample)
  assert(sample:find("OakSpeech.new bypasses") or sample:find("self.oakPic"), sample)
  assert(sample:find("TrainerCard.new hardcodes") or sample:find("self.faces"), sample)
  assert(sample:find('field:patch%("theme"'), sample)
  assert(sample:find('field:patch%("townMap"'), sample)
  assert(sample:find('field:patch%("overworldFx"'), sample)
  assert(sample:find('field:patch%("battleHud"'), sample)
  assert(sample:find("assets/fx/cut_tree.png") or sample:find("cut_tree"), sample)
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
        generation = function(id)
          return (id == "gold" or id == "silver" or id == "crystal") and 2 or 1
        end,
        engine = function(id)
          if id == "crystal" then return "crystal" end
          if id == "gold" or id == "silver" then return "gs" end
          return "gen1"
        end,
      }
    end
    package.loaded["Generation"] = nil
    local ModWriter = require("ModWriter")
    local out = ModWriter.emitMain({
      id = "t",
      shinyRate = 4096,
      breeding = { eggLevel = 5, minStepsToEgg = 100 },
      menuGfx = { pack = { menu = "assets/pack/menu.png" } },
      diploma = { image = "assets/diploma/diploma.png" },
      boot = { namePresets = { player = { "GOLD" }, rival = { "SILVER" } } },
      apricorns = {
        RED_APRICORN = { apricorn = "RED_APRICORN", ball = "ULTRA_BALL",
          event = 600, index = 1 },
      },
    }, {})
    assert(out:find("shinyRate = 4096"), "missing shinyRate emit")
    assert(out:find("data.breeding"), "missing breeding emit")
    assert(out:find("Gold menu chrome"), "missing gen2 menuGfx emit")
    assert(out:find("data.gen2MenuGfx"), "missing gen2MenuGfx merge")
    assert(out:find("Gold diploma sheet"), "missing diploma emit")
    assert(out:find("data.gen2Diploma"), "missing gen2Diploma merge")
    assert(out:find("namePresets"), "missing gold namePresets emit")
    assert(out:find("mod.content.apricorns:"), "missing apricorns emit")
    package.preload["src.core.GameVersion"] = nil
    package.loaded["src.core.GameVersion"] = nil
    package.loaded["Generation"] = nil
  end
  do
    local oakOut = ModWriter.emitMain({
      id = "t", game = "crystal",
      oakSpeech = { demoSpecies = "AZUMARILL" },
    }, { trainers = { classes = {} } })
    assert(oakOut:find("demoSpecies"), "missing gen2 oak demoSpecies emit")
    assert(oakOut:find("src.ui.gen2.OakSpeech"), "missing gen2 OakSpeech wrap")
    assert(oakOut:find("loadMon"), "missing gen2 oak demo pic reload")
  end
  do
    local out = ModWriter.emitMain({
      id = "t",
      pokemon = {
        PIKACHU = {
          id = "PIKACHU",
          forms = {
            ALOLAN = { spriteFront = "assets/pika_alola_front.png" },
          },
        },
      },
    }, { pokemon = { PIKACHU = { id = "PIKACHU" } } })
    assert(out:find("ALOLAN"), "missing form emit")
    assert(out:find("pokemon.sprite"), "missing form sprite hook")
    assert(out:find("ctx.mon.form"), "missing mon.form lookup")
  end
  do
    local out = ModWriter.emitMain({
      id = "t",
      maps = {
        ROUTE_1 = {
          id = "ROUTE_1", width = 1, height = 1, blocks = { 1 },
          tileset = "OVERWORLD",
          encounters = {
            grass = {
              rate = 25,
              slots = { { level = 3, species = "PIKACHU", form = "ALOLAN" } },
            },
          },
        },
      },
    }, {})
    assert(out:find("ALOLAN"), "missing wild slot form emit")
    assert(out:find("pendingForm"), "missing wild form pending")
    assert(out:find("encounter.roll"), "missing encounter.roll form wrap")
    assert(out:find("battle.started"), "missing wild form battle stamp")
    local schema = ModWriter.encounterFormSchemasLua()
    assert(schema:find("t.fields.form"), "missing encounter form schema")
  end
  do
    local out = ModWriter.emitMain({
      id = "t", game = "crystal",
      trainers = {
        BEAUTY = {
          id = "BEAUTY", name = "BEAUTY",
          trainers = {
            {
              id = "BEAUTY_VICTORIA", name = "VICTORIA",
              trainerType = "TRAINERTYPE_ITEM_MOVES",
              party = {
                {
                  level = 9, species = "SENTRET", item = "BERRY",
                  moves = { "TACKLE", "DEFENSE_CURL" },
                  dvs = { attack = 14, defense = 10, speed = 10, special = 10 },
                  statExp = { hp = 100, attack = 0, defense = 0, speed = 0,
                    special = 0 },
                },
              },
            },
          },
        },
      },
    }, { trainers = { classes = { BEAUTY = { id = "BEAUTY" } } } })
    assert(out:find("item = \"BERRY\"") or out:find('item = "BERRY"'),
      "missing gen2 held item emit")
    assert(out:find("TACKLE"), "missing gen2 move list emit")
    assert(out:find("statExp"), "missing gen2 statExp emit")
    assert(out:find("Trainers.party is fixed"), "missing gen2 DV hook")
    assert(out:find("Schemas.lua"), "missing trainer party schema load")
    local schema = ModWriter.trainerPartySchemasLua()
    assert(schema:find("gen2Fields.trainers"), "missing gen2 trainer party schema")
  end
  print("OK modules load")
end)
if not ok then print("FAIL", err); os.exit(1) end
