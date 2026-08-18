-- Pack Pokemonium maps / NPCs / encounters / items / species into a Gold mod.
-- No engine edits. Abilities are skipped. Extra forms are extra species;
-- Unown stays the engine's DV-letter form.

local ModIO = require("ModIO")
local State = require("State")
local History = require("History")
local TmxPokemonium = require("TmxPokemonium")

local PokemoniumPack = {}
local H = {}

local SEP = package.config:sub(1, 1)

function H.join(...)
  local parts = { ... }
  for i = 1, #parts do
    parts[i] = tostring(parts[i] or ""):gsub("[/\\]+$", "")
  end
  return table.concat(parts, SEP)
end

function H.readText(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

function H.exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function H.log(msg)
  local line = "[pokemonium] " .. tostring(msg)
  print(line)
  local path = (os.getenv("TEMP") or ".") .. "\\pokemonium_pack.log"
  local f = io.open(path, "a")
  if f then
    f:write(line .. "\n")
    f:close()
  end
end

local SPECIES_ALIAS = {
  DARKRAY = "DARKRAI", NINETAILS = "NINETALES", MANETRIC = "MANECTRIC",
  MARRIL = "MARILL", MARIL = "MARILL", MINUM = "MINUN", TAILOW = "TAILLOW",
  JINX = "JYNX", PELLIPPER = "PELIPPER", SELVIPER = "SEVIPER",
  SNUBBUL = "SNUBBULL", GIBBLE = "GIBLE", QUASIRE = "QUAGSIRE",
  PHAMPY = "PHANPY", WOBBUFET = "WOBBUFFET", TENTACTRUEL = "TENTACRUEL",
  GYRADOS = "GYARADOS", QYARADOS = "GYARADOS", MAGICARP = "MAGIKARP",
  MAGKIKARP = "MAGIKARP", WHISHCASH = "WHISCASH",
}

function H.token(name)
  local s = tostring(name or ""):upper()
  s = s:gsub("♀", "_F"):gsub("♂", "_M")
  s = s:gsub("FARFETCH['’]D", "FARFETCH_D")
  s = s:gsub("SIRFETCH['’]D", "SIRFETCH_D")
  s = s:gsub("MR%.%s*MIME", "MR_MIME")
  s = s:gsub("MIME%s*JR%.?", "MIME_JR")
  s = s:gsub("HO[- ]OH", "HO_OH")
  s = s:gsub("PORYGON[- ]Z", "PORYGON_Z")
  s = s:gsub("TYPE[- ]NULL", "TYPE_NULL")
  s = s:gsub("JANGMO[- ]O", "JANGMO_O")
  s = s:gsub("HAKAMO[- ]O", "HAKAMO_O")
  s = s:gsub("KOMMO[- ]O", "KOMMO_O")
  s = s:gsub("[^A-Z0-9]+", "_")
  s = s:gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  return SPECIES_ALIAS[s] or s
end

function H.mapId(x, y)
  return ("PM_" .. tonumber(x) .. "_" .. tonumber(y)):gsub("%-", "M")
end

function H.parseJson(str)
  local i, n = 1, #str
  local function peek()
    return str:sub(i, i)
  end
  local function skip()
    while i <= n do
      local c = peek()
      if c == " " or c == "\n" or c == "\r" or c == "\t" then
        i = i + 1
      else
        break
      end
    end
  end
  local parseValue
  local function parseString()
    i = i + 1
    local out = {}
    while i <= n do
      local c = peek()
      if c == '"' then
        i = i + 1
        return table.concat(out)
      elseif c == "\\" then
        local n1 = str:sub(i + 1, i + 1)
        i = i + 2
        if n1 == "n" then out[#out + 1] = "\n"
        elseif n1 == "t" then out[#out + 1] = "\t"
        elseif n1 == "r" then out[#out + 1] = "\r"
        else out[#out + 1] = n1 end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    return table.concat(out)
  end
  local function parseNumber()
    local s, e = str:find("^-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
    local num = tonumber(str:sub(s, e))
    i = e + 1
    return num
  end
  local function parseArray()
    i = i + 1
    local arr = {}
    skip()
    if peek() == "]" then i = i + 1; return arr end
    while true do
      arr[#arr + 1] = parseValue()
      skip()
      local c = peek()
      if c == "]" then i = i + 1; return arr end
      if c == "," then i = i + 1; skip() else return arr end
    end
  end
  local function parseObject()
    i = i + 1
    local obj = {}
    skip()
    if peek() == "}" then i = i + 1; return obj end
    while true do
      skip()
      local key = parseString()
      skip()
      if peek() == ":" then i = i + 1 end
      obj[key] = parseValue()
      skip()
      local c = peek()
      if c == "}" then i = i + 1; return obj end
      if c == "," then i = i + 1 else return obj end
    end
  end
  parseValue = function()
    skip()
    local c = peek()
    if c == '"' then return parseString() end
    if c == "{" then return parseObject() end
    if c == "[" then return parseArray() end
    if c == "t" and str:sub(i, i + 3) == "true" then i = i + 4; return true end
    if c == "f" and str:sub(i, i + 4) == "false" then i = i + 5; return false end
    if c == "n" and str:sub(i, i + 3) == "null" then i = i + 4; return nil end
    return parseNumber()
  end
  return parseValue()
end

function H.loadPokedex()
  local root = ModIO.repoRoot()
  local path = H.join(root, "tools", "content-editor", "data", "pokemonium_pokedex.json")
  local body = H.readText(path)
  if not body then return {} end
  local ok, data = pcall(H.parseJson, body)
  if not ok or type(data) ~= "table" then
    H.log("pokedex json failed: " .. tostring(data))
    return {}
  end
  return data
end

function H.formId(rawName)
  local name = tostring(rawName or "")
  local base, form = name:match("^([^%-]+)%-(.+)$")
  if not base then return H.token(name), nil end
  base, form = H.token(base), H.token(form)
  if base == "UNOWN" then return "UNOWN", form end
  if form == "" then return base, nil end
  return base .. "_" .. form, form
end

local FORM_STATS = {
  DEOXYS_ATTACK = { hp = 50, attack = 180, defense = 20,
    specialAttack = 180, specialDefense = 20, speed = 150 },
  DEOXYS_DEFENSE = { hp = 50, attack = 70, defense = 160,
    specialAttack = 70, specialDefense = 160, speed = 90 },
  DEOXYS_SPEED = { hp = 50, attack = 95, defense = 90,
    specialAttack = 95, specialDefense = 90, speed = 180 },
  CASTFORM_SUN = { hp = 70, attack = 70, defense = 70,
    specialAttack = 70, specialDefense = 70, speed = 70,
    types = { "FIRE" } },
  CASTFORM_RAIN = { hp = 70, attack = 70, defense = 70,
    specialAttack = 70, specialDefense = 70, speed = 70,
    types = { "WATER" } },
  CASTFORM_SNOW = { hp = 70, attack = 70, defense = 70,
    specialAttack = 70, specialDefense = 70, speed = 70,
    types = { "ICE" } },
  WORMADAM_SANDY = { hp = 60, attack = 79, defense = 105,
    specialAttack = 59, specialDefense = 85, speed = 36,
    types = { "BUG", "GROUND" } },
  WORMADAM_TRASH = { hp = 60, attack = 69, defense = 95,
    specialAttack = 69, specialDefense = 95, speed = 36,
    types = { "BUG", "STEEL" } },
  GIRATINA_ORIGIN = { hp = 150, attack = 120, defense = 100,
    specialAttack = 120, specialDefense = 100, speed = 90 },
  SHAYMIN_SKY = { hp = 100, attack = 103, defense = 75,
    specialAttack = 120, specialDefense = 75, speed = 127,
    types = { "GRASS", "FLYING" } },
  ROTOM_HEAT = { hp = 50, attack = 65, defense = 107,
    specialAttack = 105, specialDefense = 107, speed = 86,
    types = { "ELECTRIC", "FIRE" } },
  ROTOM_WASH = { hp = 50, attack = 65, defense = 107,
    specialAttack = 105, specialDefense = 107, speed = 86,
    types = { "ELECTRIC", "WATER" } },
  ROTOM_FROST = { hp = 50, attack = 65, defense = 107,
    specialAttack = 105, specialDefense = 107, speed = 86,
    types = { "ELECTRIC", "ICE" } },
  ROTOM_FAN = { hp = 50, attack = 65, defense = 107,
    specialAttack = 105, specialDefense = 107, speed = 86,
    types = { "ELECTRIC", "FLYING" } },
  ROTOM_MOW = { hp = 50, attack = 65, defense = 107,
    specialAttack = 105, specialDefense = 107, speed = 86,
    types = { "ELECTRIC", "GRASS" } },
}

local WALK_SPRITES = {
  "SPRITE_YOUNGSTER", "SPRITE_BUG_CATCHER", "SPRITE_LASS", "SPRITE_SAILOR",
  "SPRITE_GENTLEMAN", "SPRITE_SUPER_NERD", "SPRITE_HIKER", "SPRITE_BIKER",
  "SPRITE_BLACK_BELT", "SPRITE_COOLTRAINER_M", "SPRITE_COOLTRAINER_F",
  "SPRITE_BEAUTY", "SPRITE_FISHER", "SPRITE_SWIMMER_GUY", "SPRITE_SWIMMER_GIRL",
  "SPRITE_TEACHER", "SPRITE_POKEFAN_M", "SPRITE_POKEFAN_F", "SPRITE_GRAMPS",
  "SPRITE_GRANNY", "SPRITE_TWIN", "SPRITE_SAGE", "SPRITE_OFFICER",
  "SPRITE_SCIENTIST", "SPRITE_ROCKET", "SPRITE_ROCKET_GIRL", "SPRITE_KIMONO_GIRL",
}

local CLASS_MAP = {
  HIKER = "HIKER", PICNICKER = "PICNICKER", CAMPER = "CAMPER",
  YOUNGSTER = "YOUNGSTER", LASS = "LASS", BUGCATCHER = "BUG_CATCHER",
  BUG_CATCHER = "BUG_CATCHER", SAILOR = "SAILOR", SUPERNERD = "SUPER_NERD",
  SUPER_NERD = "SUPER_NERD", BIKER = "BIKER", BURGLAR = "BURGLAR",
  FIREBREATHER = "FIREBREATHER", JUGGLER = "JUGGLER",
  BLACKBELT = "BLACKBELT_T", BLACK_BELT = "BLACKBELT_T",
  PSYCHIC = "PSYCHIC_T", BOARDER = "BOARDER", SKIER = "SKIER",
  SWIMMER = "SWIMMERM", SAGE = "SAGE", MEDIUM = "MEDIUM",
  GENTLEMAN = "GENTLEMAN", BEAUTY = "BEAUTY", FISHER = "FISHER",
  FISHERMAN = "FISHER", TEACHER = "TEACHER", POKEFAN = "POKEFANM",
  OFFICER = "OFFICER", SCIENTIST = "SCIENTIST", ROCKET = "GRUNTM",
  COOLTRAINER = "COOLTRAINERM", COOLTRAINERM = "COOLTRAINERM",
  COOLTRAINERF = "COOLTRAINERF", BIRDKEEPER = "BIRD_KEEPER",
  BIRD_KEEPER = "BIRD_KEEPER", ACE_TRAINER = "COOLTRAINERM",
}

function H.goldSpecies(S)
  local out = {}
  local bags = { S.data and S.data.pokemon, S.data and S.data.gen2Pokemon }
  for b = 1, #bags do
    local bag = bags[b]
    if type(bag) == "table" then
      for id, rec in pairs(bag) do
        if type(id) == "string" and type(rec) == "table" then
          out[id] = rec
          if type(rec.name) == "string" then
            out[H.token(rec.name)] = rec
          end
        end
      end
    end
  end
  return out
end

function H.goldMoves(S)
  local out = {}
  local bag = (S.data and (S.data.moves or S.data.gen2Moves)) or {}
  for id, rec in pairs(bag) do
    if type(id) == "string" then
      out[id] = rec
      if type(rec) == "table" and type(rec.name) == "string" then
        out[H.token(rec.name)] = rec
      end
    end
  end
  return out
end

function H.goldItems(S)
  local out = {}
  local bag = (S.data and (S.data.items or S.data.gen2Items)) or {}
  for id, rec in pairs(bag) do
    if type(id) == "string" then
      out[id] = rec
      if type(rec) == "table" and type(rec.name) == "string" then
        out[H.token(rec.name)] = rec
      end
    end
  end
  return out
end

function H.moveId(name, goldMoves)
  local id = H.token(name)
  if goldMoves[id] then
    return type(goldMoves[id]) == "table" and (goldMoves[id].id or id) or id
  end
  return nil
end

function H.speciesRecord(id, dex, name, types, stats)
  return {
    id = id,
    name = name or id,
    dex = dex or 1,
    types = types,
    baseStats = stats,
    catchRate = 45,
    baseExp = 64,
    growthRate = "GROWTH_MEDIUM_SLOW",
    levelMoves = { { level = 1, move = "TACKLE" } },
    evolutions = {},
    spriteFront = "assets/pokemon/pm_stub.png",
    spriteBack = "assets/pokemon/pm_stub.png",
    picSize = 5,
    trueColor = true,
    _isNew = true,
  }
end

function H.writeStubPng(modDir)
  local destDir = H.join(modDir, "assets", "pokemon")
  ModIO.ensureDirectory(destDir)
  local dest = H.join(destDir, "pm_stub.png")
  if H.exists(dest) then return dest end
  if not (love and love.image and love.image.newImageData) then return nil end
  local img = love.image.newImageData(56, 56)
  img:mapPixel(function(x, y)
    if x == 0 or y == 0 or x == 55 or y == 55 then
      return 0.15, 0.15, 0.2, 1
    end
    return 0.75, 0.78, 0.9, 1
  end)
  local encoded = img:encode("png")
  if img.release then img:release() end
  local f = io.open(dest, "wb")
  if not f then return nil end
  f:write(encoded:getString())
  f:close()
  return dest
end

function H.parseChanceList(chances, levels)
  local slots = {}
  local names = {}
  for name, pct in tostring(chances or ""):gmatch("([^,;]+),(%d+)") do
    names[#names + 1] = { name = name:gsub("^%s+", ""):gsub("%s+$", ""),
      pct = tonumber(pct) or 1 }
  end
  local lv = {}
  for a, b in tostring(levels or ""):gmatch("(%d+)%-(%d+)") do
    lv[#lv + 1] = math.floor(((tonumber(a) or 5) + (tonumber(b) or 5)) / 2)
  end
  for i = 1, #names do
    slots[#slots + 1] = {
      species = names[i].name,
      level = lv[i] or lv[1] or 5,
    }
  end
  return slots
end

function H.padSlots(slots, n, resolve)
  local out = {}
  if #slots == 0 then return out end
  for i = 1, n do
    local src = slots[((i - 1) % #slots) + 1]
    local species = resolve(src.species)
    if species then
      out[#out + 1] = { level = math.max(1, src.level or 5), species = species }
    end
  end
  return out
end

function H.encountersFor(props, resolve)
  if type(props) ~= "table" then return nil end
  local rate = tonumber(props.wildProbability) or 0
  if rate < 0 then rate = 0 end
  if rate > 255 then rate = 255 end
  local day = H.parseChanceList(props.dayPokemonChances, props.dayPokemonLevels)
  local nite = H.parseChanceList(props.nightPokemonChances, props.nightPokemonLevels)
  local water = H.parseChanceList(props.waterPokemonChances, props.waterPokemonLevels)
  local fish = H.parseChanceList(props.fishPokemonChances, props.fishPokemonLevels)
  local grassDay = H.padSlots(day, 7, resolve)
  local grassNite = H.padSlots(#nite > 0 and nite or day, 7, resolve)
  local waterSlots = H.padSlots(water, 3, resolve)
  local enc = {}
  if #grassDay > 0 then
    enc.grass = {
      rates = { MORN = rate, DAY = rate, NITE = rate },
      slots = { MORN = grassDay, DAY = grassDay, NITE = grassNite },
    }
  end
  if #waterSlots > 0 then
    enc.water = { rate = math.max(rate, 5), slots = waterSlots }
  end
  if #fish > 0 then
    enc.fish = H.padSlots(fish, 3, resolve)
  end
  if not enc.grass and not enc.water and not enc.fish then return nil end
  return enc
end

function H.parseNpcFile(path)
  local body = H.readText(path)
  if not body then return { npcs = {}, warps = {} } end
  local npcs, warps = {}, {}
  local lines = {}
  for line in (body .. "\n"):gmatch("(.-)\r?\n") do
    lines[#lines + 1] = line
  end
  local i = 1
  local function take()
    i = i + 1
    return lines[i - 1]
  end
  while i <= #lines do
    local line = take()
    if line == "[npc]" then
      local rec = {
        name = take(),
        facing = string.lower(tostring(take() or "down")),
        sprite = tonumber(take()) or 0,
        x = tonumber(take()) or 0,
        y = tonumber(take()) or 0,
        pokemon = take(),
        partySize = tonumber(take()) or 0,
        badge = tonumber(take()) or -1,
        speech = take(),
        healer = tostring(take() or ""):lower() == "true",
        box = tostring(take() or ""):lower() == "true",
        shop = take(),
      }
      npcs[#npcs + 1] = rec
    elseif line == "[warp]" then
      warps[#warps + 1] = {
        x = tonumber(take()) or 0,
        y = tonumber(take()) or 0,
        destX = tonumber(take()) or 0,
        destY = tonumber(take()) or 0,
        destMapX = tonumber(take()) or 0,
        destMapY = tonumber(take()) or 0,
        badge = tonumber(take()) or 0,
      }
    elseif line == "[hmobject]" or line == "[trade]" then
      while i <= #lines and lines[i] ~= "[/hmobject]" and lines[i] ~= "[/trade]" do
        take()
      end
    end
  end
  return { npcs = npcs, warps = warps }
end

function H.speechLines(path)
  local body = H.readText(path)
  if not body then return {} end
  local lines = {}
  for line in (body .. "\n"):gmatch("(.-)\r?\n") do
    line = line:gsub("%s+$", "")
    if line ~= "" then lines[#lines + 1] = line end
  end
  return lines
end

function H.speechText(ids, lines)
  if not ids or ids == "NULL" then return nil end
  local parts = {}
  for id in tostring(ids):gmatch("%d+") do
    local n = tonumber(id)
    if n and lines[n + 1] then parts[#parts + 1] = lines[n + 1] end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "<NEXT>")
end

function H.parseParty(line, resolve)
  if not line or line == "NULL" or line == "" then return nil end
  local party = {}
  local name
  for token in (line .. ","):gmatch("([^,]*),") do
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token ~= "" then
      if not name then
        name = token
      else
        local species = resolve(name)
        if species then
          party[#party + 1] = {
            level = math.max(1, tonumber(token) or 5),
            species = species,
          }
        end
        name = nil
      end
    end
  end
  if #party == 0 then return nil end
  return party
end

function H.facingMove(facing)
  if facing == "up" then return 7 end
  if facing == "left" then return 8 end
  if facing == "right" then return 9 end
  return 6
end

function H.owSprite(spriteId, healer, shop)
  if healer then return "SPRITE_NURSE" end
  if shop then return "SPRITE_CLERK" end
  local n = tonumber(spriteId) or 0
  if n <= 0 then return "SPRITE_YOUNGSTER" end
  return WALK_SPRITES[((n - 1) % #WALK_SPRITES) + 1]
end

function H.splitTrainerName(name)
  name = tostring(name or "")
  if name == "" or name == "NULL" then return nil, nil end
  local class, rest = name:match("^(%S+)%s+(.+)$")
  if not class then return nil, H.token(name) end
  local key = H.token(class)
  if key == "COOLTRAINER" or key == "ACE_TRAINER" then
    local female = rest:find("a$") or rest:find("y$") or rest:find("ie$")
      or rest:find("ette$") or class:lower():find("f")
    key = female and "COOLTRAINERF" or "COOLTRAINERM"
  end
  return CLASS_MAP[key] or "YOUNGSTER", H.token(rest)
end

function H.parseItems(xml)
  local items, shops = {}, {}
  for block in tostring(xml or ""):gmatch("<item>(.-)</item>") do
    local name = block:match("<name>(.-)</name>")
    local desc = block:match("<description>(.-)</description>") or ""
    local id = tonumber(block:match("<id>(%d+)</id>"))
    local cat = block:match("<category>(.-)</category>") or "OTHER"
    local shop = tonumber(block:match("<shop>(%-?%d+)</shop>")) or 0
    local price = tonumber(block:match("<price>(%d+)</price>")) or 0
    if name and name ~= "" then
      local rec = {
        name = name, desc = desc, pmId = id, category = cat,
        shop = shop, price = price,
      }
      items[#items + 1] = rec
      if shop and shop > 0 then
        shops[shop] = shops[shop] or {}
        shops[shop][#shops[shop] + 1] = rec
      end
    end
  end
  return items, shops
end

function H.goldType(name)
  local id = H.token(name)
  if id == "FAIRY" then return "NORMAL" end
  if id == "PSYCHIC" then return "PSYCHIC_TYPE" end
  if id == "STEEL" then return "STEEL" end
  if id == "DARK" then return "DARK" end
  return id
end

function PokemoniumPack.run(App, opts)
  opts = opts or {}
  local S = App.session and App.session()
  if not S then return false, "editor not loaded" end
  local root = opts.root
  if type(root) ~= "string" or root == "" then
    return false, "missing Pokemonium root"
  end
  root = root:gsub("[/\\]+$", "")
  local mapsDir = opts.maps or H.join(root, "Client", "res", "maps")
  local npcDir = H.join(root, "Server", "res", "npc")
  local speechDir = H.join(root, "Client", "res", "language", "english", "NPC")
  local itemPath = H.join(root, "Server", "res", "itemdex.xml")
  if not H.exists(H.join(mapsDir, "0.0.tmx"))
      and H.exists(H.join(root, "0.0.tmx")) then
    mapsDir = root
  end
  H.log("root " .. root)
  H.log("maps " .. mapsDir)

  S.version = "gold"
  App.dataVersion = "gold"
  local modId = "pokemonium"
  local dest = H.join(ModIO.modsRoot(), modId)
  if H.exists(H.join(dest, "manifest.json")) then
    -- editor_project.lua is hundreds of MB; do not loadfile it.
    H.log("existing " .. dest .. " (fresh in-memory project)")
    S.path = dest
    S.project = State.blankProject(modId, "Pokemonium")
    S.browseModId = modId
    S.dirty = false
  else
    H.log("creating " .. dest)
    if not App.createMod(modId) then return false, "could not create mod" end
  end
  S = App.session()
  S.version = "gold"
  S.project.game = "gold"
  S.project.name = "Pokemonium"
  History.clear(S)

  H.writeStubPng(S.path)
  local goldSpecies = H.goldSpecies(S)
  local goldMoves = H.goldMoves(S)
  local goldItems = H.goldItems(S)
  local pokedex = H.loadPokedex()
  H.log(string.format("gold species %d, pokedex %d",
    (function()
      local n = 0
      for _ in pairs(goldSpecies) do n = n + 1 end
      return n
    end)(), #pokedex))

  local function resolveSpecies(raw)
    local id, form = H.formId(raw)
    if goldSpecies[id] then
      local rec = goldSpecies[id]
      return type(rec) == "table" and (rec.id or id) or id
    end
    if S.project.pokemon[id] then return id end
    if form and goldSpecies[id:match("^(.*)_")] then
      -- Unown-* uses engine forms.
      if id:sub(1, 6) == "UNOWN_" or id == "UNOWN" then return "UNOWN" end
    end
    return id
  end

  -- Register National Dex 252+ and extra forms. 1-251 stay Gold's.
  for i = 1, #pokedex do
    local row = pokedex[i]
    local dex = tonumber(row.id) or i
    if dex >= 252 then
      local id = H.token(row.name and row.name.english or ("PMON" .. dex))
      if not goldSpecies[id] and not S.project.pokemon[id] then
        local types = {}
        for t = 1, #(row.type or {}) do
          types[#types + 1] = H.goldType(row.type[t])
        end
        if #types == 0 then types[1] = "NORMAL" end
        local b = row.base or {}
        local stats = {
          hp = tonumber(b.HP) or 50,
          attack = tonumber(b.Attack) or 50,
          defense = tonumber(b.Defense) or 50,
          specialAttack = tonumber(b["Sp. Attack"]) or 50,
          specialDefense = tonumber(b["Sp. Defense"]) or 50,
          speed = tonumber(b.Speed) or 50,
        }
        S.project.pokemon[id] = H.speciesRecord(
          id, dex, string.upper(row.name.english or id), types, stats)
      end
    end
  end
  for formId, extra in pairs(FORM_STATS) do
    if not goldSpecies[formId] and not S.project.pokemon[formId] then
      local baseId = formId:match("^(.-)_") or formId
      local base = S.project.pokemon[baseId] or goldSpecies[baseId]
      local stats = {
        hp = extra.hp, attack = extra.attack, defense = extra.defense,
        specialAttack = extra.specialAttack, specialDefense = extra.specialDefense,
        speed = extra.speed,
      }
      local types = extra.types
      if not types and type(base) == "table" then types = base.types end
      types = types or { "NORMAL" }
      local dex = (type(base) == "table" and base.dex) or 1
      S.project.pokemon[formId] = H.speciesRecord(
        formId, dex, formId, types, stats)
    end
  end

  S.project.pokedex = S.project.pokedex or {}
  for id, rec in pairs(S.project.pokemon) do
    if type(rec) == "table" then
      S.project.pokedex[id] = {
        id = id,
        dex = rec.dex,
        kind = "POKEMON",
        height = 10,
        weight = 100,
        text = "No data available.",
      }
    end
  end

  local itemXml = H.readText(itemPath) or ""
  local pmItems, pmShops = H.parseItems(itemXml)
  local itemIdByName = {}
  for i = 1, #pmItems do
    local rec = pmItems[i]
    local id = H.token(rec.name)
    local gold = goldItems[id]
    if gold and type(gold) == "table" then
      itemIdByName[rec.name] = gold.id or id
    else
      if not S.project.items[id] then
        S.project.items[id] = {
          id = id,
          name = string.upper(rec.name),
          price = rec.price or 0,
          pocket = rec.category == "POKEBALLS" and "BALL" or "ITEM",
          canToss = true,
          description = rec.desc,
          _isNew = true,
        }
      end
      itemIdByName[rec.name] = id
    end
  end
  S.project.marts = S.project.marts or {}
  for shopId, list in pairs(pmShops) do
    local stock = {}
    for i = 1, math.min(16, #list) do
      stock[#stock + 1] = itemIdByName[list[i].name]
    end
    if #stock > 0 then
      local slot = math.max(0, math.min(33, (tonumber(shopId) or 1) - 1))
      S.project.marts[slot] = stock
    end
  end

  H.log("importing maps from " .. mapsDir)
  local okImport, errImport = TmxPokemonium.importPath(S, mapsDir, App)
  if not okImport then
    return false, errImport or "map import failed"
  end
  -- Do not History.clear here: it deep-copies every layered map.
  S.undoStack, S.redoStack = {}, {}
  S._histBaseline = nil
  collectgarbage("collect")
  local nMaps = 0
  for _ in pairs(S.project.maps or {}) do nMaps = nMaps + 1 end
  H.log("imported " .. nMaps .. " maps")

  local trainerEvent = 30000
  S.project.trainers.POKEMONIUM = {
    id = "POKEMONIUM",
    name = "PKMN TRAINER",
    index = 90,
    baseMoney = 20,
    trainers = {},
    _isNew = true,
  }
  local function addTrainer(tname, party)
    local list = S.project.trainers.POKEMONIUM.trainers
    for i = 1, #list do
      if list[i].name == tname then return i end
    end
    list[#list + 1] = {
      name = tname,
      id = tname,
      trainerType = "TRAINERTYPE_NORMAL",
      party = party,
    }
    return #list
  end

  local pendingWarps = {}
  for id, map in pairs(S.project.maps) do
    local wx, wy = map._pmWx, map._pmWy
    if not wx then
      local xs, ys = id:match("^PM_(M?%d+)_(M?%d+)$")
      if xs then
        wx = tonumber((xs:gsub("^M", "-")))
        wy = tonumber((ys:gsub("^M", "-")))
      end
    end
    local npcPath = wx and H.join(npcDir, wx .. "." .. wy .. ".txt")
    local data = npcPath and H.parseNpcFile(npcPath) or { npcs = {}, warps = {} }
    local speech = wx and H.speechLines(H.join(speechDir, wx .. "." .. wy .. ".txt")) or {}
    local objects, warps = {}, {}
    for wi = 1, #data.warps do
      local w = data.warps[wi]
      local destId = H.mapId(w.destMapX, w.destMapY)
      warps[#warps + 1] = {
        x = w.x, y = w.y, destMap = destId, destWarp = 1,
      }
      pendingWarps[#pendingWarps + 1] = {
        src = id, index = #warps,
        destId = destId, destX = w.destX, destY = w.destY,
      }
    end
    map.warps = warps

    S.project.scripts = S.project.scripts or {}
    S.project.text = S.project.text or {}
    for ni = 1, #data.npcs do
      local npc = data.npcs[ni]
      local shopN = tonumber(npc.shop)
      if not shopN then
        shopN = tostring(npc.shop or ""):lower() == "true" and 1 or 0
      end
      local party = H.parseParty(npc.pokemon, resolveSpecies)
      local obj = {
        index = ni,
        x = npc.x,
        y = npc.y,
        sprite = H.owSprite(npc.sprite, npc.healer, shopN > 0),
        movement = H.facingMove(npc.facing),
        type = party and 2 or 0,
        sight = party and math.max(1, npc.partySize or 1) or 0,
        eventFlag = 65535,
        hours = { -1, -1 },
        radius = { x = 0, y = 0 },
        palette = 0,
      }
      local text = H.speechText(npc.speech, speech) or "..."
      local scriptKey = string.format("mod:%s_OBJ_%d", id, ni)
      local textKey = scriptKey .. "_TEXT"
      S.project.text[textKey] = text
      if npc.healer then
        S.project.scripts[scriptKey] = {
          { op = "faceplayer" },
          { op = "opentext" },
          { op = "writetext", text = textKey },
          { op = "waitbutton" },
          { op = "special", id = "HealParty" },
          { op = "closetext" },
        }
        obj.scriptKey = scriptKey
      elseif shopN and shopN > 0 then
        S.project.scripts[scriptKey] = {
          { op = "faceplayer" },
          { op = "opentext" },
          { op = "writetext", text = textKey },
          { op = "waitbutton" },
          { op = "pokemart", mart = math.max(0, math.min(33, shopN - 1)), dialog = 0 },
          { op = "closetext" },
        }
        obj.scriptKey = scriptKey
      elseif party then
        local _, memberName = H.splitTrainerName(npc.name)
        memberName = memberName or ("TRAINER_" .. ni)
        local member = addTrainer(memberName, party)
        trainerEvent = trainerEvent + 1
        local seenKey = scriptKey .. "_SEEN"
        local winKey = scriptKey .. "_WIN"
        S.project.text[seenKey] = text
        S.project.text[winKey] = "..."
        obj.trainer = {
          class = 90,
          classId = "POKEMONIUM",
          member = member,
          event = trainerEvent,
          seenText = seenKey,
          winText = winKey,
          scriptKey = scriptKey,
        }
        S.project.scripts[scriptKey] = {
          { op = "jumptext", text = winKey },
        }
        obj.scriptKey = scriptKey
      else
        S.project.scripts[scriptKey] = {
          { op = "jumptextfaceplayer", text = textKey },
        }
        obj.scriptKey = scriptKey
      end
      objects[#objects + 1] = obj
    end
    map.objects = objects
    map.signs = {}

    local enc = H.encountersFor(map._pmProps, resolveSpecies)
    if enc then
      map.encounters = { grass = enc.grass, water = enc.water }
      if enc.fish and #enc.fish > 0 then
        local gid = "FISHGROUP_" .. id
        S.project.fishGroups = S.project.fishGroups or {}
        local fishSlots = {}
        for i = 1, #enc.fish do
          fishSlots[#fishSlots + 1] = {
            chance = 85 - (i - 1) * 20,
            level = enc.fish[i].level,
            species = enc.fish[i].species,
          }
        end
        S.project.fishGroups[gid] = {
          id = gid, chance = 15,
          old = fishSlots, good = fishSlots, super = fishSlots,
        }
        map.fishGroup = gid
      end
    end
  end

  for i = 1, #pendingWarps do
    local p = pendingWarps[i]
    local src = S.project.maps[p.src]
    local dest = S.project.maps[p.destId]
    if src and dest and src.warps[p.index] then
      local matched
      dest.warps = dest.warps or {}
      for di = 1, #dest.warps do
        if dest.warps[di].x == p.destX and dest.warps[di].y == p.destY then
          matched = di
          break
        end
      end
      if not matched then
        dest.warps[#dest.warps + 1] = {
          x = p.destX, y = p.destY, destMap = p.src, destWarp = p.index,
        }
        matched = #dest.warps
      end
      src.warps[p.index].destWarp = matched
    end
  end

  S.project.flyPoints = {
    {
      landmark = "NEW_BARK_TOWN",
      spawn = "SPAWN_HOME",
      flag = 0,
      map = "PM_0_0",
      x = 14,
      y = 18,
    },
  }
  S.project.boot = S.project.boot or {}
  S.project.boot.startMap = "PM_0_0"
  S.project.boot.startX = 14
  S.project.boot.startY = 18
  S.project.boot.startFacing = "down"
  S.project.boot.lastHeal = { map = "PM_0_0", x = 14, y = 18 }

  local nPoke, nItem, nNpc = 0, 0, 0
  for _ in pairs(S.project.pokemon) do nPoke = nPoke + 1 end
  for _ in pairs(S.project.items) do nItem = nItem + 1 end
  for _, map in pairs(S.project.maps) do
    nNpc = nNpc + #(map.objects or {})
  end
  H.log(string.format("content: %d maps, %d npcs, %d new species, %d new items",
    nMaps, nNpc, nPoke, nItem))
  H.log("saving (compiles layered maps)…")
  if not App.save() then
    return false, S.status or "save failed"
  end
  H.log("saved " .. tostring(S.path))
  return true
end

return PokemoniumPack
