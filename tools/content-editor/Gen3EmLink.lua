-- Emerald maps (FireRed / LeafGreen projects, GAME PATCHES > Emerald Maps):
-- Emerald's tilesets and maps in a FireRed or LeafGreen mod -- Hoenn in a
-- Kanto game -- read from the player's own Emerald import.
--
-- With the patch on (project.gen3EmLink) the editor offers:
--   * every Emerald tileset, "em__<Emerald tileset>" (e.g.
--     em__general__petalburg), wherever FireRed's are offered (map builder,
--     Create / resize, Around the map);
--   * Emerald's maps in MAPS > Import template map: a new map builder map
--     with that map's blocks, collision and border on its Emerald tileset;
--   * Import region: every Emerald map at once as FR_HOENN_<name>, joined
--     by Emerald's own connections and warps, with its wild Pokemon. They are
--     map layouts naming the Emerald map (gen3MapLayouts[id].source =
--     "em:<map>"), so the project holds no Emerald blocks.
-- Signs and everyday people (talkers, Poke Mart clerks, Pokemon Center
-- nurses) come along as the steps they show; other people and scripts stay
-- in Emerald (the two games' scripts differ) and are made in the editor.
--
-- The mod carries names only, never tiles, layouts or lists. The game side
-- is Gen3EmLinkRuntime; a player without an Emerald import can't turn the
-- mod on (it stops with M.MESSAGE). The editor needs one too.
local M = {}
local R = require("Gen3EmLinkRuntime")
M.PAIR, M.MAP = R.PAIR, R.MAP
M.MESSAGE = "This mod uses Emerald maps and tilesets. Import Emerald (USA) in the launcher, then turn the mod on again."
M.redirect = R.redirect
M.REGION = R.REGION
M.NAME = "Emerald"

--- Rebuild the editor's map and tileset lists (after the switch or Import
-- region changed what's in them).
function M.refresh(S)
  if not (S and S.data) then return end
  S.data._editorMaps, S.data._editorTilesets = nil, nil
  pcall(function() require("Gen3Workspace").prepare(S) end)
end

local function copy(v) return require("src.mods.Merge").deepCopy(v) end

--- GAME PATCHES > Emerald Maps > Wild Pokemon: Hoenn's own encounter tables
-- on the Import region maps. On unless turned off (off: they have none
-- until you make some).
function M.wildEnabled(project) return (project or {}).gen3EmWild ~= false end
function M.setWild(S, on)
  local p = S.project
  if M.wildEnabled(p) == (on == true) then return false end
  if on then p.gen3EmWild = nil else p.gen3EmWild = false end
  local base = S.data and S.data._gen3EditorContent and S.data._gen3EditorContent.encounters
  if base then
    if on then M.addWild(S, base)
    else
      -- take Emerald's lists back out of the editor (lists you edited stay yours)
      for id, rec in pairs(base) do
        if type(rec) == "table" and rec._editorEmWild then base[id] = nil end
      end
    end
  end
  return true
end

--- GAME PATCHES > Emerald Maps (FireRed / LeafGreen).
function M.host(project)
  local g = (project or {}).game or (project or {}).version
  return g == "firered" or g == "leafgreen"
end
function M.enabled(project)
  project = project or {}
  return project.gen3EmLink == true and M.host(project)
end
function M.setEnabled(project, on)
  if (project.gen3EmLink == true) == (on == true) then return false end
  project.gen3EmLink = on == true or nil
  return true
end

function M.isPair(p) return type(p) == "string" and p:sub(1, #M.PAIR) == M.PAIR end
function M.isMap(id) return type(id) == "string" and id:sub(1, #M.MAP) == M.MAP end
function M.pairName(base) return M.PAIR .. base end
function M.mapSource(id) return M.MAP .. id end
function M.label(p)
  if M.isPair(p) then return "Emerald: " .. p:sub(#M.PAIR + 1):gsub("__", " / ") end
  return (tostring(p):gsub("_rom_", " / "))
end

-- Editor side -----------------------------------------------------------------

local link -- { prefix, game, read } or false
local function diskRoots()
  local roots = {}
  local okD, DataSource = pcall(require, "DataSource")
  if okD and type(DataSource) == "table" and DataSource.loadPrefs then
    local okP, prefs = pcall(DataSource.loadPrefs)
    if okP and type(prefs) == "table" and type(prefs.recompRoot) == "string" and prefs.recompRoot ~= "" then
      roots[#roots + 1] = (prefs.recompRoot:gsub("[/\\]+$", ""))
    end
  end
  local appdata = os.getenv("APPDATA")
  if appdata then
    roots[#roots + 1] = appdata .. "/LOVE/pokemon-love2d"
    roots[#roots + 1] = appdata .. "/pokemon-love2d"
  end
  local home = os.getenv("HOME")
  if home then roots[#roots + 1] = home .. "/.local/share/love/pokemon-love2d" end
  return roots
end

-- Reads save-folder paths ("emerald/…"): the editor's own folder first, then
-- the linked Gen1Recomp folder and the game's save folders.
local function readAny(rel)
  local fs = love and love.filesystem
  if fs and fs.getInfo and fs.getInfo(rel, "file") then return fs.read(rel) end
  for _, root in ipairs(M._roots or diskRoots()) do
    local f = io.open(root .. "/" .. rel, "rb")
    if f then local b = f:read("*a"); f:close(); return b end
  end
end

--- The Emerald import the editor can use, or nil.
function M.editor()
  if link == nil then
    link = false
    local prefix, game = R.find(readAny)
    if prefix then
      local cache = {}
      link = { prefix = prefix, game = game, read = function(rel)
        if cache[rel] == nil then cache[rel] = readAny(prefix .. rel) or false end
        return cache[rel] or nil
      end }
    end
  end
  return link or nil
end
function M.reset()
  link = nil; M._manifest, M._layouts, M._headers, M._wild, M._pack, M._furniture = nil, nil, nil, nil, nil, nil
  M._scripts, M._texts, M._events, M._nurse, M._slots, M._sections, M._marts = nil, nil, nil, nil, nil, nil, nil
end

--- Emerald bytes for a cache path, or nil. `path` may name an em__ tileset
-- folder (native/em__X/…) or be a plain Emerald cache path.
function M.read(path)
  local l = M.editor()
  if not l then return nil end
  return l.read(M.redirect(path) or path)
end

local function decode(bytes)
  if not bytes then return nil end
  local value = require("Gen3Decode").decode(bytes, { allowArray = true, allowComments = true,
    maxBytes = 16 * 1024 * 1024, maxNodes = 1000000, maxTableEntries = 500000,
    maxDepth = 64, maxStringBytes = 4 * 1024 * 1024 })
  return type(value) == "table" and value or nil
end

function M.manifest()
  if M._manifest == nil then
    M._manifest = decode(M.read("data/generated/gba/native/manifest.lua")) or false
  end
  return M._manifest or nil
end

--- Emerald tilesets as editor tileset ids: { "em__…", … }, labels.
function M.pairs()
  local ids, labels, seen = {}, {}, {}
  for _, info in pairs((M.manifest() or {}).layouts or {}) do
    if info.pair and not seen[info.pair] then
      seen[info.pair] = true
      local id = M.pairName(info.pair)
      ids[#ids + 1] = id; labels[id] = M.label(id)
    end
  end
  table.sort(ids)
  return ids, labels
end

--- Emerald maps that can start a FireRed map: { "EM_…", … }, labels.
function M.maps()
  local ids, labels = {}, {}
  for id in pairs((M.manifest() or {}).layouts or {}) do
    if id:match("^EM_") then
      ids[#ids + 1] = id
      labels[id] = id:gsub("^EM_", ""):gsub("_", " ")
    end
  end
  table.sort(ids)
  return ids, labels
end

--- An Emerald map's layout ("em:EM_…"), with its tileset as em__…
function M.layout(source)
  if not M.isMap(source) then return nil, "Not an Emerald map" end
  if not M.editor() then return nil, "Import Emerald to use Emerald maps" end
  local id = source:sub(#M.MAP + 1)
  M._layouts = M._layouts or {}
  if M._layouts[id] == nil then
    local info = ((M.manifest() or {}).layouts or {})[id]
    local blob = info and M.read("data/generated/gba/native/" .. (info.file or ("layouts/" .. id .. ".mid")))
    local decoded = blob and require("src.import.gba.native_pack").decodeMidLayout(blob)
    M._layouts[id] = decoded and require("src.core.game3.layout_native").fromDecoded(decoded, id, M.pairName(info.pair)) or false
  end
  if not M._layouts[id] then return nil, "Emerald map " .. id .. " is missing from the import" end
  return M._layouts[id]
end

-- Map headers ---------------------------------------------------------------
-- The import's census lists every map as group_number; each has a header.json.
-- scripts/events.lua names the same header by its ROM offset, which is how an
-- EM_ map id finds its header (and its wild Pokemon list, "group:number").
local function slots()
  if not M._slots then
    M._slots = {}
    local okJ, Json = pcall(require, "src.link.Json")
    local census = M.read("data/generated/gba/map_tree/census.json")
    local c = census and okJ and Json.decode(census)
    local byOff = {}
    for _, group in ipairs((c or {}).groups or {}) do
      for _, map in ipairs(group.maps or {}) do
        local header = okJ and Json.decode(M.read("data/generated/gba/map_tree/maps/" .. map.slot .. "/header.json") or "")
        if type(header) == "table" and header.headerOff then byOff[header.headerOff] = { slot = map.slot, header = header } end
      end
    end
    local _, _, events = M.scriptsAndText()
    for id, ev in pairs(events or {}) do
      local row = byOff[ev.headerOff]
      if row then M._slots[id] = row end
    end
  end
  return M._slots
end

--- An Emerald map's header (map type, weather, …), or nil.
function M.header(id)
  local row = slots()[id]
  return row and row.header or nil
end

--- The key of an Emerald map's wild Pokemon list ("group:number"), or nil.
function M.wildKey(id)
  local row = slots()[id]
  return row and (row.slot:gsub("_", ":")) or nil
end

--- The behaviours of an Emerald tileset (em__…): { [block] = behaviour }.
local function pack()
  if M._pack == nil then
    local bytes = M.read("data/generated/gba/objects/pack.lua")
    local chunk = bytes and load(bytes, "=em_pack", "t", {})
    local ok, value = pcall(chunk or error)
    M._pack = ok and type(value) == "table" and value or false
  end
  return M._pack or nil
end

function M.behaviors(pair)
  if not M.isPair(pair) then return nil end
  local p = pack()
  return p and (p.behaviors or {})[pair:sub(#M.PAIR + 1)] or nil
end

--- An Emerald map as a map builder source (MAPS > Import template map): its
-- blocks, collision, heights and border on its Emerald tileset. No events.
function M.templateSource(S, source)
  local layout, err = M.layout(source)
  if not layout then return nil, err end
  local L = require("LayeredMap")
  local runtime = L.runtimeSourceId(layout.pair)
  local behaviors = M.behaviors(layout.pair) or {}
  local cells, collision, elevation, nativeCollision, nativeBehavior = {}, {}, {}, {}, {}
  for y = 0, layout.height - 1 do for x = 0, layout.width - 1 do
    local i = y * layout.width + x + 1
    local c = layout:cellAt(x, y)
    cells[i] = { source = runtime, tile = c.mid }
    collision[i] = require("Gen3Collision").mode(c.coll); elevation[i] = c.elev; nativeCollision[i] = c.coll
    nativeBehavior[i] = behaviors[c.mid]
  end end
  return { id = source, cellWidth = layout.width, cellHeight = layout.height, baseTileset = layout.pair,
    layers = { { id = "ground", name = "Ground", visible = true, export = true, opacity = 1, cells = cells } },
    collision = collision, gen3Elevation = elevation, gen3Collision = nativeCollision, gen3Behavior = nativeBehavior,
    gen3Border = { pair = layout.pair, width = layout.borderWidth, height = layout.borderHeight, mids = copy(layout.borderMids) } }
end

--- Emerald maps for MAPS > Import template map (FireRed / LeafGreen): ids "em:EM_…".
function M.templateMaps(project)
  local ids, labels = {}, {}
  if not M.enabled(project) or not M.editor() then return ids, labels end
  local emIds, emLabels = M.maps()
  for _, id in ipairs(emIds) do
    local key = M.mapSource(id)
    ids[#ids + 1] = key; labels[key] = "Emerald: " .. emLabels[id] .. "  (" .. id .. ")"
  end
  return ids, labels
end

-- Export ----------------------------------------------------------------------

--- The id an Emerald map gets from Import region: FR_HOENN_<name>.
function M.regionId(id) return M.REGION .. tostring(id):gsub("^EM_", "") end

-- FireRed music for an Emerald map, by its type and name (the songs aren't
-- the same): towns, cities, routes and sea, caves, buildings, and the
-- Pokemon Centers, Marts and gyms among them.
local function musicFor(S, id, mapType)
  local maps = (S.data or {}).maps or {}
  local pick = ({ [1] = "FR_PALLET_TOWN", [2] = "FR_VIRIDIAN_CITY", [3] = "FR_ROUTE_1", [5] = "FR_ROUTE_19",
    [6] = "FR_ROUTE_19", [4] = "FR_MT_MOON_1F", [9] = "FR_MT_MOON_1F", [8] = "FR_PLAYERS_HOUSE_1F" })[tonumber(mapType)]
  if tostring(id):find("_POKEMON_CENTER", 1, true) then pick = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  elseif tostring(id):find("_MART$") then pick = "FR_VIRIDIAN_CITY_MART"
  elseif tostring(id):find("_GYM$") then pick = "FR_PEWTER_CITY_GYM" end
  for _, cand in ipairs({ pick, "FR_PALLET_TOWN" }) do
    local def = cand and maps[cand]
    if def and def.music then return def.music end
  end
end

-- Signs and people -------------------------------------------------------------
-- Emerald's scripts can't run in a FireRed game as they are (its specials,
-- flags and variables mean other things there), so each sign is read the way
-- the player sees it -- its messages, Pokemon pictures and braille, on the
-- path where no story flag is set -- and rebuilt from those as steps:
--   { "text", "g3:<text>" } | { "braille", "g3:<text>" }
--   | { "pic", species, x, y } | { "unpic" }
-- Only Emerald's names for the texts are kept; the game reads the words from
-- the player's import (Gen3EmLinkRuntime).
local SIGN_QUIET = { lockall = 1, releaseall = 1, lock = 1, release = 1, faceplayer = 1, special = 1,
  specialvar = 1, setvar = 1, copyvar = 1, checkflag = 1, compare_var_to_value = 1, compare_var_to_var = 1,
  compare = 1, playse = 1, waitse = 1, textcolor = 1, delay = 1, waitstate = 1, waitmessage = 1,
  waitbuttonpress = 1, closemessage = 1, goto_if = 1, call_if = 1, setflag = 1, clearflag = 1,
  addvar = 1, subvar = 1, checkitem = 1 }
local MSGBOX = { [2] = true, [3] = true, [4] = true, [6] = true } -- NPC, sign, default, auto-close
local PERSON_QUIET = { playmoncry = 1, waitmoncry = 1, checkplayergender = 1, textcolor = 1 }
for k in pairs(SIGN_QUIET) do PERSON_QUIET[k] = 1 end

function M.scriptsAndText()
  if M._scripts == nil then
    local function lua(rel)
      local bytes = M.read(rel)
      local chunk = bytes and load(bytes, "=" .. rel, "t", {})
      local ok, value = pcall(chunk or error)
      return ok and type(value) == "table" and value or nil
    end
    M._scripts = lua("data/generated/gba/scripts/scripts.lua") or false
    M._texts = lua("data/generated/gba/scripts/text.lua") or false
    M._events = lua("data/generated/gba/scripts/events.lua") or false
  end
  return M._scripts or nil, M._texts or nil, M._events or nil
end
local scriptsAndText = M.scriptsAndText

-- Emerald's nurse script: the one every Pokemon Center nurse calls after
-- setting VAR_0x800B to her id.
local function nurseScript()
  if M._nurse == nil then
    local scripts, _, events = scriptsAndText()
    local count = {}
    for id, map in pairs(events or {}) do
      if id:find("_POKEMON_CENTER_1F", 1, true) then
        for _, o in ipairs(map.objects or {}) do
          local list = (scripts or {})[o.scriptKey] or {}
          local first, second = list[1], list[2]
          if first and first.op == "setvar" and (first.var or first[1]) == 0x800B and second and second.op == "call" and second.target then
            count[second.target] = (count[second.target] or 0) + 1
          end
        end
      end
    end
    local best, n = false, 0
    for k, c in pairs(count) do if c > n then best, n = k, c end end
    M._nurse = best
  end
  return M._nurse or nil
end

local function walk(key, person)
  local scripts, texts = scriptsAndText()
  if not (scripts and texts) then return nil, "no scripts" end
  local quiet, nurse = person and PERSON_QUIET or SIGN_QUIET, person and nurseScript()
  local steps, stack, seen = {}, {}, {}
  local list, i, word, guard = scripts[key], 1, nil, 0
  if not list then return nil, "missing" end
  while list do
    guard = guard + 1
    if guard > 500 then return nil, "loop" end
    local op = list[i]; i = i + 1
    local name = op and op.op
    if not op or name == "return" then
      if #stack == 0 then break end
      local back = table.remove(stack); list, i = back[1], back[2]
    elseif name == "end" then break
    elseif name == "call" and nurse and op.target == nurse then
      steps[#steps + 1] = { "nurse" }
    elseif person and name == "pokemart" then
      local items = op.items or op.ptr or op[1]
      if type(items) ~= "string" then return nil, "mart" end
      steps[#steps + 1] = { "mart", items }
    elseif person and name == "waitbuttonpress" then
      local last = steps[#steps]
      if last and last[1] == "say" then last[1] = "text" end
    elseif name == "goto" or name == "call" then
      if name == "goto" then
        if seen[op.target] then return nil, "loop" end
        seen[op.target] = true
      else stack[#stack + 1] = { list, i } end
      list, i = scripts[op.target], 1
      if not list then return nil, "missing" end
    elseif name == "loadword" then
      if (op.dest or op[1]) == 0 then word = op.value or op[2] end
    elseif name == "callstd" or name == "message" then
      local t = name == "message" and (op.text or op.ptr or op[1]) or word
      if name == "callstd" and not MSGBOX[op.std or op[1]] then return nil, "menu" end
      if not (t and texts[t]) then return nil, "no text" end
      steps[#steps + 1] = { (person and name == "message") and "say" or "text", t }; word = nil
    elseif name == "braillemessage" then
      local t = op.ptr or op[1]
      if not (t and texts[t]) then return nil, "no text" end
      steps[#steps + 1] = { "braille", t }
    elseif name == "showmonpic" then
      steps[#steps + 1] = { "pic", op[1], op[2], op[3] }
    elseif name == "hidemonpic" then
      steps[#steps + 1] = { "unpic" }
    elseif not quiet[name] then return nil, tostring(name)
    end
  end
  local shown = false
  for _, step in ipairs(steps) do if step[1] ~= "unpic" and step[1] ~= "pic" then shown = true end end
  if not shown then return nil, "nothing to read" end
  if person then
    for _, step in ipairs(steps) do
      if step[1] == "nurse" then return { { "nurse" } } end -- the nurse's own script does the talking
    end
  end
  return steps
end

--- An Emerald sign as steps (see above), or nil and why not.
function M.signSteps(key) return walk(key, false) end

--- Emerald's furniture tiles (picture book shelves, vases, trash cans, shop
-- shelves, blueprints): FireRed has no interaction for them. Returns
-- { [behaviour as text] = "em:furn:<behaviour>" } and the steps of each key,
-- read from the scripts the import's own tile interactions name.
local FURNITURE = { [398] = true, [480] = true, [482] = true, [483] = true, [484] = true, [485] = true, [486] = true }
function M.furniture()
  if M._furniture == nil then
    M._furniture = false
    local function lua(rel)
      local bytes = M.read(rel)
      local chunk = bytes and load(bytes, "=" .. rel, "t", {})
      local ok, value = pcall(chunk or error)
      return ok and type(value) == "table" and value or nil
    end
    local rows = (pack() or {}).interactions
    local labels = lua("data/generated/gba/scripts/labels.lua")
    if rows and labels then
      local keys, steps = {}, {}
      for behavior, row in pairs(rows) do
        local ptr = labels[row.script]
        -- only the plain "read a message" ones; the others check flags or
        -- start events the FireRed game can't run
        if FURNITURE[tonumber(behavior)] and ptr and not row.facing and not row.sameElevation then
          local got = M.signSteps(ptr)
          if got then
            keys[tostring(behavior)] = M.MAP .. "furn:" .. behavior
            steps[M.MAP .. "furn:" .. behavior] = got
          end
        end
      end
      if next(keys) then M._furniture = { keys = keys, steps = steps } end
    end
  end
  return M._furniture and M._furniture.keys or nil, M._furniture and M._furniture.steps or nil
end
--- An Emerald person's script as steps, or nil and why not.
function M.personSteps(key) return walk(key, true) end

--- An Emerald map's signs as FireRed bgEvents, recording their steps in
-- project.gen3EmSigns. Returns the bgEvents and how many were left out.
function M.signsFor(project, eid)
  local _, _, events = scriptsAndText()
  local out, left = {}, 0
  for _, bg in ipairs(((events or {})[eid] or {}).bgEvents or {}) do
    if bg.type == "sign" and bg.scriptKey then
      local key = M.MAP .. bg.scriptKey
      project.gen3EmSigns = project.gen3EmSigns or {}
      local steps = project.gen3EmSigns[key]
      if not steps then
        steps = M.signSteps(bg.scriptKey)
        if steps then project.gen3EmSigns[key] = steps end
      end
      if steps then
        out[#out + 1] = { x = bg.x, y = bg.y, elevation = bg.elevation or 0, kind = bg.kind or 0, type = "sign", scriptKey = key }
      else left = left + 1 end
    end
  end
  return out, left
end

-- People, marts & nurses ------------------------------------------------------
--- GAME PATCHES > Emerald Maps > People, marts & nurses: Emerald's everyday
-- people on the Import region maps -- the ones that talk, Poke Mart clerks
-- and Pokemon Center nurses. On unless turned off. Trainers, item balls and
-- story people (anyone Emerald hides or shows with a flag) stay out.
function M.peopleEnabled(project) return (project or {}).gen3EmPeople ~= false end

-- FireRed's look-alike of an Emerald sprite, for the editor's map view (the
-- game draws Emerald's own sprite from the import) and FireRed movement
-- numbers for Emerald's.
local LOOKS = { BOY_1 = "BOY", BOY_2 = "BOY", BOY_3 = "LITTLE_BOY", LITTLE_BOY_3 = "LITTLE_BOY", GIRL_1 = "LITTLE_GIRL",
  GIRL_2 = "LASS", GIRL_3 = "WOMAN_2", TWIN = "LITTLE_GIRL", MAN_1 = "MAN", MAN_2 = "BALDING_MAN", MAN_3 = "FAT_MAN",
  MAN_4 = "ROCKER", MAN_5 = "MAN", WOMAN_4 = "WOMAN_3", WOMAN_5 = "WOMAN_2", OLD_MAN = "OLD_MAN_1",
  POKEFAN_M = "OLD_MAN_2", POKEFAN_F = "OLD_WOMAN", FISHERMAN = "FISHER", MART_EMPLOYEE = "CLERK",
  SCHOOL_KID_M = "YOUNGSTER", EXPERT_M = "GENTLEMAN", EXPERT_F = "WOMAN_1", HEX_MANIAC = "CHANNELER",
  MANIAC = "POKE_MANIAC", SCIENTIST_1 = "SCIENTIST", SCIENTIST_2 = "SCIENTIST", RICH_BOY = "GENTLEMAN",
  COOK = "CHEF", LINK_RECEPTIONIST = "CABLE_CLUB_RECEPTIONIST", GAMEBOY_KID = "GBA_KID", SAILOR = "SAILOR",
  CONTEST_JUDGE = "MAN", CAMERAMAN = "MAN", REPORTER_M = "MAN", REPORTER_F = "WOMAN_1", ARTIST = "MAN",
  BARD = "OLD_MAN_1", NINJA_BOY = "LITTLE_BOY", DEVON_EMPLOYEE = "MAN", AQUA_MEMBER_M = "ROCKET_M",
  AQUA_MEMBER_F = "ROCKET_F", MAGMA_MEMBER_M = "ROCKET_M", MAGMA_MEMBER_F = "ROCKET_F", PSYCHIC_M = "MAN",
  TUBER_M = "TUBER_M_LAND", SWIMMER_M = "SWIMMER_M_LAND", SWIMMER_F = "SWIMMER_F_LAND",
  RUNNING_TRIATHLETE_M = "MAN", RUNNING_TRIATHLETE_F = "WOMAN_1", CYCLING_TRIATHLETE_M = "BIKER",
  CYCLING_TRIATHLETE_F = "WOMAN_1", HOT_SPRINGS_OLD_WOMAN = "OLD_WOMAN", ROOFTOP_SALE_WOMAN = "WOMAN_1",
  MYSTERY_GIFT_MAN = "MAN", UNION_ROOM_NURSE = "NURSE" }
local function constants()
  if M._const == nil then
    local ok, C = pcall(require, "src.core.game3.constants")
    local okF, fr = pcall(function() return C.of("firered") end)
    local okE, em = pcall(function() return C.of("emerald") end)
    M._const = ok and okF and okE and { fr = fr, em = em } or false
  end
  return M._const or nil
end
local function fireRedLook(emGfx)
  local c = constants()
  local F = c and c.fr.event_objects and c.fr.event_objects.byName or {}
  local name = c and ((c.em.event_objects.byId or {}).OBJ_EVENT_GFX_ or {})[emGfx]
  name = tostring(name or ""):gsub("^OBJ_EVENT_GFX_", "")
  return F["OBJ_EVENT_GFX_" .. name] or F["OBJ_EVENT_GFX_" .. (LOOKS[name] or "")] or F.OBJ_EVENT_GFX_MAN or 19
end
local function fireRedMovement(mt)
  local c = constants()
  local name = c and ((c.em.movement.byId or {}).MOVEMENT_TYPE_ or {})[mt]
  return name and c.fr.movement.byName[name] or mt
end

--- An Emerald map's people as FireRed objects, recording their steps in
-- project.gen3EmTalk. Returns the objects and how many were left out.
function M.peopleFor(project, eid)
  local _, _, events = scriptsAndText()
  local out, left = {}, 0
  for _, o in ipairs(((events or {})[eid] or {}).objects or {}) do
    local gid = tonumber(o.graphicsId or o.graphics)
    local story = (tonumber(o.flag) or 0) ~= 0 or (tonumber(o.trainerType) or 0) ~= 0
    local steps
    if not story and o.scriptKey and gid and gid < 240 then
      local key = M.MAP .. o.scriptKey
      project.gen3EmTalk = project.gen3EmTalk or {}
      steps = project.gen3EmTalk[key]
      if not steps then
        steps = M.personSteps(o.scriptKey)
        if steps then
          if steps[1][1] == "nurse" then steps = { { "nurse", o.localId } } end
          project.gen3EmTalk[key] = steps
        end
      end
      if steps then
        local look = fireRedLook(gid)
        out[#out + 1] = { x = o.x, y = o.y, elevation = o.elevation or 0, localId = o.localId, index = o.localId,
          graphicsId = look, graphics = look, emGfx = gid, kind = 0, flag = 0, trainerType = 0, trainerRange = 0,
          sight = 0, movementType = fireRedMovement(o.movementType), movement = o.movement, range = o.range,
          rangeX = o.rangeX or 0, rangeY = o.rangeY or 0, scriptKey = key }
      end
    end
    if not steps then left = left + 1 end
  end
  return out, left
end

local function ownRegionMaps(p)
  local out = {}
  for _, eid in ipairs(M.maps()) do
    local id = M.regionId(eid)
    if p.gen3 and p.gen3.maps and p.gen3.maps[id] and ((p.gen3MapLayouts or {})[id] or {}).source == M.mapSource(eid) then
      out[#out + 1] = { eid, p.gen3.maps[id] }
    end
  end
  return out
end
local function hasPeople(def)
  for _, o in ipairs(def.objects or {}) do if o.emGfx then return true end end
  return false
end
-- Adds Emerald's people to Import region maps that have none yet.
local function addPeople(p)
  local n = 0
  for _, row in ipairs(ownRegionMaps(p)) do
    local def = row[2]
    if not hasPeople(def) then
      local list = M.peopleFor(p, row[1])
      def.objects = def.objects or {}
      local used = {}
      for _, o in ipairs(def.objects) do used[tonumber(o.localId) or -1] = true end
      for _, o in ipairs(list) do
        if not used[o.localId] then def.objects[#def.objects + 1] = o; n = n + 1 end
      end
    end
  end
  return n
end
function M.setPeople(S, on)
  local p = S.project
  if M.peopleEnabled(p) == (on == true) then return false end
  if on then p.gen3EmPeople = nil else p.gen3EmPeople = false end
  if p.gen3EmRegion then
    if on then addPeople(p)
    else
      -- take Emerald's people back out (people you made stay)
      for _, row in ipairs(ownRegionMaps(p)) do
        local keep = {}
        for _, o in ipairs(row[2].objects or {}) do if not o.emGfx then keep[#keep + 1] = o end end
        row[2].objects = keep
      end
      p.gen3EmTalk = nil
    end
    M.addTalk(S)
    M.refresh(S)
  end
  return true
end

--- The Import region signs and people in the editor: their scripts (the
-- FireRed ones the game builds) and Emerald's words, from the import, so
-- Dialog and Events show and edit them like any other. Only what you change
-- is saved in the mod (as its own text / script); the rest still comes from
-- the player's import in the game.
function M.addTalk(S)
  local p, data = S.project, S.data
  if not (p and data and (p.gen3EmSigns or p.gen3EmTalk) and data.gen3Scripts and M.editor()) then return end
  local _, texts = scriptsAndText()
  if not texts then return end
  local textBase = (data._gen3EditorContent or {}).text
  local nurse
  for _, o in ipairs(((data.maps or {}).FR_VIRIDIAN_CITY_POKEMON_CENTER_1F or {}).objects or {}) do
    if o.sprite == "SPRITE_NURSE" or tonumber(o.graphicsId or o.graphics) == 64 then
      for _, op in ipairs(data.gen3Scripts[o.scriptKey] or {}) do
        if op.op == "call" and op.target and not nurse then nurse = op.target end
      end
    end
  end
  local function add(bag, build)
    for key, steps in pairs(bag or {}) do
      if data.gen3Scripts[key] == nil then data.gen3Scripts[key] = build(steps) end
      for _, step in ipairs(steps) do
        local t = (step[1] == "text" or step[1] == "say" or step[1] == "braille") and step[2]
        local full = t and (M.MAP .. t)
        if full and texts[t] then
          if data.gen3Text and data.gen3Text[full] == nil then data.gen3Text[full] = copy(texts[t]) end
          if textBase and textBase[full] == nil then textBase[full] = copy(texts[t]) end
        end
      end
    end
  end
  add(p.gen3EmSigns, R.signOps)
  add(M.peopleEnabled(p) and p.gen3EmTalk or nil, function(steps) return R.personOps(steps, nurse) end)
end

--- GAME PATCHES > Emerald Maps > Import region: every Emerald map as
-- FR_HOENN_<name>, joined by Emerald's connections and warps. Maps the
-- project already has are left alone. Returns added, skipped (or nil, why).
function M.importRegion(S)
  if not M.enabled(S.project) then return nil, "Turn Emerald Maps on first" end
  if not M.editor() then return nil, "Import Emerald first" end
  local warps = decode(M.read("data/generated/gba/warps.lua")) or {}
  local connections = decode(M.read("data/generated/gba/connections.lua")) or {}
  local ids = M.maps()
  if #ids == 0 then return nil, "The Emerald import has no maps" end
  local known = {}
  for _, id in ipairs(ids) do known[id] = M.regionId(id) end
  local p = S.project
  p.gen3MapLayouts = p.gen3MapLayouts or {}
  p.gen3 = p.gen3 or {}; p.gen3.maps = p.gen3.maps or {}
  p.gen3Modes = p.gen3Modes or {}; p.gen3Modes.maps = p.gen3Modes.maps or {}
  local exists = function(id)
    return ((S.data or {}).maps or {})[id] or p.gen3.maps[id] or (p.maps or {})[id] or (p.layeredMaps or {})[id]
  end
  local added, skipped, signs, signsLeft = 0, 0, 0, 0
  for _, eid in ipairs(ids) do
    local id = known[eid]
    local info = (((M.manifest() or {}).layouts) or {})[eid]
    local ours = p.gen3.maps[id] and (p.gen3MapLayouts[id] or {}).source == M.mapSource(eid)
    if ours and not next(p.gen3.maps[id].bgEvents or {}) then
      -- brought in before signs were: give it its signs now
      local rows, left = M.signsFor(p, eid)
      p.gen3.maps[id].bgEvents = rows
      signs, signsLeft = signs + #rows, signsLeft + left
      skipped = skipped + 1
    elseif exists(id) or not info then skipped = skipped + 1
    else
      local header = M.header(eid) or {}
      local def = { id = id, name = id, width = info.width, height = info.height, pair = M.pairName(info.pair),
        objects = {}, bgEvents = {}, coordEvents = {}, mapScripts = {}, warps = {}, connections = {} }
      for _, key in ipairs({ "mapType", "weather", "showMapName", "allowEscaping",
          "allowRunning", "bikingAllowed", "floorNum", "battleType" }) do
        if header[key] ~= nil then def[key] = header[key] end
      end
      -- the map name shown on arrival: Emerald's region map section, carried
      -- as R.SECTION + id and named from the import in the game
      if header.regionMapSectionId ~= nil then def.regionMapSectionId = R.SECTION + header.regionMapSectionId end
      -- the map keeps its own song, played from the player's import (Gen3ForeignMusic)
      def.music = require("Gen3ForeignMusic").fromImport(M.editor(), header.music) or musicFor(S, eid, header.mapType)
      for _, w in ipairs(warps[eid] or {}) do
        def.warps[#def.warps + 1] = { x = w.x, y = w.y, destMap = known[w.destMap] or w.destMap, destWarp = w.destWarp }
      end
      local rows = {}
      for _, c in ipairs(connections[eid] or {}) do
        if known[c.map] then rows[#rows + 1] = { dir = c.dir, map = known[c.map], offset = c.offset } end
      end
      def.connections = require("Gen3Connections").normalize(rows)
      local signRows, left = M.signsFor(p, eid)
      def.bgEvents = signRows
      signs, signsLeft = signs + #signRows, signsLeft + left
      p.gen3MapLayouts[id] = { source = M.mapSource(eid), width = info.width, height = info.height, blank = false }
      p.gen3.maps[id] = def
      p.gen3Modes.maps[id] = "register"
      added = added + 1
    end
  end
  p.gen3EmRegion = true
  local people = M.peopleEnabled(p) and addPeople(p) or 0
  M.addTalk(S)
  M.refresh(S)
  if S.data and S.data.encounters then M.addWild(S, S.data.encounters) end
  return added, skipped, signs, signsLeft, people
end

--- Import region's wild Pokemon in the editor: Emerald's lists as the
-- FR_HOENN_ maps' own (Encounters tab), from the import. Edited ones are
-- saved as the mod's own lists (new records); the rest come from the
-- player's import in the game. `base` is the editor's encounter catalog.
function M.addWild(S, base)
  if not (S.project and S.project.gen3EmRegion and M.wildEnabled(S.project) and M.editor()) then return end
  M._wild = M._wild or decode(M.read("data/generated/gba/encounters.lua")) or {}
  -- the editor names species (PIDGEY); the import numbers them (16, the same
  -- in every Gen 3 game)
  local names = {}
  for id, rec in pairs(require("Gen3").catalog(S.data, "pokemon")) do
    if tonumber(rec.index) then names[tonumber(rec.index)] = id end
  end
  local function named(area)
    for _, slot in ipairs((area or {}).slots or {}) do
      if type(slot.species) == "number" then slot.species = names[slot.species] or slot.species end
    end
  end
  for _, eid in ipairs(M.maps()) do
    local id = M.regionId(eid)
    local key = M.wildKey(eid)
    local t = key and M._wild[key]
    if type(t) == "table" and base[id] == nil and M.ownMap(S.project, id) then
      local rec = copy(t)
      rec.mapGroup, rec.mapNum, rec.variants = nil, nil, nil
      rec.id, rec._isNew, rec._editorEmWild = id, true, true
      for _, k in ipairs({ "land", "grass", "water", "rocks", "fishing" }) do named(rec[k]) end
      base[id] = rec
    end
  end
end

--- Is `id` an Import region map of the project's (a layout naming an Emerald map)?
function M.ownMap(project, id)
  return M.isMap(((project or {}).gen3MapLayouts or {})[id] and project.gen3MapLayouts[id].source)
end

--- Does the project use anything from Emerald?
function M.used(project)
  project = project or {}
  if project.gen3EmRegion then return true end
  for _, spec in pairs(project.gen3MapLayouts or {}) do
    if M.isMap(spec.source) or M.isPair(spec.pair) then return true end
  end
  for _, border in pairs(project.gen3Borders or {}) do
    if M.isPair(border.borderPair) then return true end
  end
  for _, source in pairs(project.layeredMaps or {}) do
    if M.isPair(source.baseTileset) or M.isPair((source.gen3Border or {}).pair) then return true end
    for _, layer in ipairs(source.layers or {}) do
      for _, cell in pairs(layer.cells or {}) do
        if type(cell) == "table" and type(cell.source) == "string" and cell.source:find(M.PAIR, 1, true) then return true end
      end
    end
  end
  for _, rec in pairs(project.gen3VoidMaps or {}) do
    if M.isPair(rec.pair) then return true end
    for _, cell in pairs(rec.cells or {}) do if M.isPair(cell.p) then return true end end
  end
  return false
end

function M.emit(project, encode, out)
  if not M.used(project) then return end
  assert(M.host(project), "Emerald maps and tilesets can only be used in FireRed and LeafGreen projects")
  local wild, respawn = nil, nil
  local own = {}
  for id, def in pairs((project.gen3 or {}).maps or {}) do
    local spec = (project.gen3MapLayouts or {})[id]
    if spec and M.isMap(spec.source) then own[id] = { eid = spec.source:sub(#M.MAP + 1), def = def } end
  end
  if project.gen3EmRegion == true and M.wildEnabled(project) and M.editor() then
    wild = {}
    for id, row in pairs(own) do
      local key = M.wildKey(row.eid)
      if key then wild[id] = key end
    end
  end
  if project.gen3EmRegion == true and M.peopleEnabled(project) then
    -- each Pokemon Center's nurse: the spot in front of her is where a
    -- blackout wakes the player
    respawn = {}
    for id, row in pairs(own) do
      for _, o in ipairs(row.def.objects or {}) do
        local steps = (project.gen3EmTalk or {})[o.scriptKey]
        if o.emGfx and steps and steps[1] and steps[1][1] == "nurse" and not respawn[id] then
          respawn[id] = { x = o.x, y = o.y + 2, healer = o.localId }
        end
      end
    end
  end
  local furniture, furnitureSteps = M.furniture()
  local signs = project.gen3EmSigns
  if furniture then
    signs = {}
    for key, steps in pairs(project.gen3EmSigns or {}) do signs[key] = steps end
    for key, steps in pairs(furnitureSteps) do signs[key] = steps end
  end
  out[#out + 1] = "local emLink=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3EmLinkRuntime.lua"),
    "Gen3EmLinkRuntime.lua missing") .. "\nend)()\nemLink.install(mod," .. encode({ message = M.MESSAGE, wild = wild,
    furniture = furniture, signs = signs, people = M.peopleEnabled(project) and project.gen3EmTalk or nil,
    respawn = respawn }) .. ")"
  -- Hoenn's own tile behaviours (muddy slopes, Fortree / Pacifidlog bridges,
  -- cracked floors, ash grass), run by the game's Emerald code
  local steps = {}
  local scripts, _, events = M.scriptsAndText()
  local Tiles = require("Gen3RegionTilesRuntime")
  for id, row in pairs(own) do
    local ms = events and events[row.eid] and events[row.eid].mapScripts
    local name = type(ms) == "table" and Tiles.scan(scripts, ms.onResume, Tiles.NAMES.emerald)
    if name then steps[id] = name end
  end
  out[#out + 1] = "local regionTiles=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3RegionTilesRuntime.lua"),
    "Gen3RegionTilesRuntime.lua missing") .. "\nend)()\nregionTiles.install(mod," .. encode({ host = "frlg", origin = "emerald", pair = M.PAIR, steps = steps }) .. ")"
  -- Town Map and Fly for the imported region: Emerald's own screen, with the
  -- towns the player has walked into
  if project.gen3EmRegion == true then
    local MapRT = require("Gen3RegionMapRuntime")
    local base = require("src.core.game3.constants").of("emerald"):flag("FLAG_VISITED_LITTLEROOT_TOWN")
    local visits = {}
    for id, row in pairs(own) do
      local ms = events and events[row.eid] and events[row.eid].mapScripts
      local ids = type(ms) == "table" and MapRT.scanFlags(scripts, ms.onTransition, function(op, flag)
        return op == "setflag" and base ~= nil and flag >= base and flag < base + 16
      end) or {}
      if #ids > 0 then visits[id] = ids end
    end
    out[#out + 1] = "local regionMap=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3RegionMapRuntime.lua"),
    "Gen3RegionMapRuntime.lua missing") .. "\nend)()\nregionMap.install(mod," .. encode({ host = "frlg", origin = "emerald", cross = true, region = M.REGION, prefix = "EM_", secBase = 1000, visits = visits }) .. ")"
  end
end

return M
