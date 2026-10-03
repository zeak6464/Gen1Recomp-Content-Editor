-- Kanto Region (FireRed / LeafGreen projects, GAME PATCHES > Kanto Region):
-- FireRed's own maps (Kanto and the Sevii Islands) brought into the mod
-- without the story, the way Emerald Maps > Import region brings Hoenn in
-- (Gen3EmLink) and Hoenn Region does for Emerald (Gen3HoennRegion). It is
-- for a GAME PATCHES > Clean Project mod, where the game's own maps are
-- hidden and can't be reached.
--
-- Import region adds every map as FR_KANTO_<name>, joined by the game's
-- own connections and warps, with its music, signs and wild Pokemon, and its
-- everyday people: the ones that only talk, Poke Mart clerks and Pokemon
-- Center nurses. Story people, trainers, item balls, map scripts and step
-- triggers stay out.
--
-- The mod carries names only: each map is a layout naming the game's map
-- (gen3MapLayouts[id].source = "FR_…" / "SEVII_…"), and its signs and people
-- name the game's own scripts, which it already has. The game side is
-- Gen3KantoRegionRuntime (wild Pokemon and blackout points).
local M = {}
local R = require("Gen3KantoRegionRuntime")
M.REGION = R.REGION

local function kanto(project)
  local game = (project or {}).game or (project or {}).version
  return game == "firered" or game == "leafgreen"
end
local function copy(v) return require("src.mods.Merge").deepCopy(v) end

--- The id Import region gives a map: FR_KANTO_<name> (the Sevii Islands'
-- SEVII_ONE_ISLAND becomes FR_KANTO_SEVII_ONE_ISLAND).
function M.regionId(id) return M.REGION .. tostring(id):gsub("^FR_", "") end
function M.isRegionId(id) return type(id) == "string" and id:sub(1, #M.REGION) == M.REGION end

--- Has Import region been run on this project?
function M.imported(project) return kanto(project) and (project or {}).gen3KantoRegion == true end

--- The game's own maps (not the project's, not another Import region's): ids.
function M.maps(S)
  local ids = {}
  local Generation = require("Generation")
  local p = S.project or {}
  for id, rec in pairs((S.data or {}).maps or {}) do
    if type(id) == "string" and (id:match("^FR_") or id:match("^SEVII_")) and not M.isRegionId(id)
        and id:sub(1, 9) ~= "FR_HOENN_" and Generation.isRomMap(S, id, rec)
        and not (p.gen3MapLayouts or {})[id] and not (p.layeredMaps or {})[id]
        and not ((((p.gen3Modes or {}).maps) or {})[id] == "register") then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

--- The maps Import region would still add: the game's own that the project
-- has no FR_KANTO_ copy of yet.
function M.pending(S)
  local n, p = 0, S.project or {}
  for _, id in ipairs(M.maps(S)) do
    local copy = M.regionId(id)
    if not ((p.gen3MapLayouts or {})[copy] or ((p.gen3 or {}).maps or {})[copy]) then n = n + 1 end
  end
  return n
end

--- A map's header (map type, weather, map name sign, …), or {}.
function M.header(S, id)
  local data = S.data or {}
  data._g3KantoHeaders = data._g3KantoHeaders or {}
  local header = data._g3KantoHeaders[id]
  if header == nil then
    header = false
    local okC, catalog = pcall(require, "src.import.gba.map_catalog")
    local slot = okC and catalog.slotKeyFor and catalog.slotKeyFor(id)
    local raw = slot and data._gen3Read and data._gen3Read("data/generated/gba/map_tree/maps/" .. slot .. "/header.json")
    if raw then
      local okJ, value = pcall(require("src.link.Json").decode, raw)
      if okJ and type(value) == "table" then header = value end
    end
    data._g3KantoHeaders[id] = header
  end
  return header or {}
end

-- People ----------------------------------------------------------------------
-- FireRed's scripts run as they are, so a person comes across with their own
-- script. Only everyday people do: no flag hides them, they aren't trainers,
-- and their script only talks, opens a shop or is the nurse's -- it sets no
-- flag or variable and gives nothing.
local QUIET = { lock = 1, lockall = 1, release = 1, releaseall = 1, faceplayer = 1, checkflag = 1,
  compare_var_to_value = 1, compare_var_to_var = 1, compare = 1, goto_if = 1, call_if = 1, playse = 1, waitse = 1,
  waitstate = 1, waitmessage = 1, waitbuttonpress = 1, closemessage = 1, delay = 1, checkitem = 1,
  playmoncry = 1, waitmoncry = 1, checkplayergender = 1, textcolor = 1 }
local MSGBOX = { [2] = true, [3] = true, [4] = true, [6] = true } -- NPC, sign, default, auto-close
local QUEST_LOG_STATE = 391 -- special GetQuestLogState
local TEMP = 0x8000 -- variables from here on are scratch values, not saved story

-- The script every Pokemon Center nurse calls (the nurse's own script is
-- lock, faceplayer, call <it>, release).
local function nurseScript(S)
  local data = S.data
  if data._g3KantoNurse == nil then
    local count = {}
    for _, map in pairs(data.maps or {}) do
      for _, o in ipairs(map.objects or {}) do
        if o.sprite == "SPRITE_NURSE" or tonumber(o.graphicsId or o.graphics) == 64 then
          for _, op in ipairs((data.gen3Scripts or {})[o.scriptKey] or {}) do
            if op.op == "call" and op.target then count[op.target] = (count[op.target] or 0) + 1; break end
          end
        end
      end
    end
    local best, n = false, 0
    for k, c in pairs(count) do if c > n then best, n = k, c end end
    data._g3KantoNurse = best
  end
  return data._g3KantoNurse or nil
end

--- What a person's script is: "talk", "mart" or "nurse" -- or nil
-- and why they stay out.
function M.personKind(S, key)
  local scripts = (S.data or {}).gen3Scripts
  if not (scripts and key) then return nil, "no scripts" end
  local nurse = nurseScript(S)
  local stack, seen = {}, {}
  local list, i, guard = scripts[key], 1, 0
  local word, said, kind
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
    elseif name == "call" and nurse and op.target == nurse then kind = "nurse"
    elseif name == "pokemart" then kind = kind or "mart"
    elseif name == "goto" or name == "call" then
      if name == "goto" then
        if seen[op.target] then return nil, "loop" end
        seen[op.target] = true
      else stack[#stack + 1] = { list, i } end
      list, i = scripts[op.target], 1
      if not list then return nil, "missing" end
    elseif name == "loadword" then
      if (op.dest or op[1]) == 0 then word = op.value or op[2] end
    elseif name == "callstd" then
      if not MSGBOX[op.std or op[1]] then return nil, "menu" end
      if not word then return nil, "no text" end
      said, word = true, nil
    elseif name == "message" then said = true
    elseif name == "special" then
      -- a clerk first asks FireRed's Quest Log state (it replays the shop)
      if (tonumber(op.id or op[1]) or 0) ~= QUEST_LOG_STATE then return nil, "special" end
    elseif name == "setvar" or name == "copyvar" then
      if (tonumber(op.var or op[1]) or 0) < TEMP then return nil, name end
    elseif not QUIET[name] then return nil, tostring(name)
    end
  end
  if kind == "nurse" then return "nurse" end
  if not said then return nil, "nothing to say" end
  return kind or "talk"
end

--- GAME PATCHES > Kanto Region > People, marts & nurses. On unless turned off.
function M.peopleEnabled(project) return (project or {}).gen3KantoPeople ~= false end
--- GAME PATCHES > Kanto Region > Wild Pokemon. On unless turned off.
function M.wildEnabled(project) return (project or {}).gen3KantoWild ~= false end

--- A map's everyday people, as they are. Returns the objects and
-- how many were left out.
function M.peopleFor(S, id)
  local out, left = {}, 0
  for _, o in ipairs((((S.data or {}).maps or {})[id] or {}).objects or {}) do
    local story = (tonumber(o.flag) or 0) ~= 0 or (tonumber(o.trainerType) or 0) ~= 0
    if not story and o.scriptKey and M.personKind(S, o.scriptKey) then
      local person = copy(o)
      person.scriptPtr = nil
      out[#out + 1] = person
    else left = left + 1 end
  end
  return out, left
end

--- A map's signs, as they are (hidden items and secret base spots
-- stay out).
function M.signsFor(S, id)
  local out = {}
  for _, bg in ipairs((((S.data or {}).maps or {})[id] or {}).bgEvents or {}) do
    if bg.type == "sign" and bg.scriptKey then
      local sign = copy(bg)
      sign.scriptPtr = nil
      out[#out + 1] = sign
    end
  end
  return out
end

-- The project's Import region maps: { { the game's id, def }, … }.
local function ownRegionMaps(S)
  local p, out = S.project, {}
  for id, spec in pairs(p.gen3MapLayouts or {}) do
    local def = M.isRegionId(id) and ((p.gen3 or {}).maps or {})[id]
    if def and type(spec.source) == "string" and M.regionId(spec.source) == id then
      out[#out + 1] = { spec.source, def }
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- Is this object one of the game's own on that map (same place in its list
-- and same script)?
local function native(S, sourceId, o)
  for _, base in ipairs((((S.data or {}).maps or {})[sourceId] or {}).objects or {}) do
    if base.localId == o.localId and base.scriptKey == o.scriptKey then return true end
  end
  return false
end

-- Adds the game's people to Import region maps that have none of them yet.
local function addPeople(S)
  local n = 0
  for _, row in ipairs(ownRegionMaps(S)) do
    local def = row[2]
    def.objects = def.objects or {}
    local has, used = false, {}
    for _, o in ipairs(def.objects) do
      used[tonumber(o.localId) or -1] = true
      if native(S, row[1], o) then has = true end
    end
    if not has then
      for _, o in ipairs((M.peopleFor(S, row[1]))) do
        if not used[tonumber(o.localId) or -1] then def.objects[#def.objects + 1] = o; n = n + 1 end
      end
    end
  end
  return n
end

local function refresh(S)
  if not (S and S.data) then return end
  S.data._editorMaps, S.data._editorTilesets = nil, nil
  pcall(function() require("Gen3Workspace").prepare(S) end)
end

function M.setPeople(S, on)
  local p = S.project
  if M.peopleEnabled(p) == (on == true) then return false end
  if on then p.gen3KantoPeople = nil else p.gen3KantoPeople = false end
  if p.gen3KantoRegion then
    if on then addPeople(S)
    else
      -- take the game's people back out (people you made stay)
      for _, row in ipairs(ownRegionMaps(S)) do
        local keep = {}
        for _, o in ipairs(row[2].objects or {}) do
          if not native(S, row[1], o) then keep[#keep + 1] = o end
        end
        row[2].objects = keep
      end
    end
    refresh(S)
  end
  return true
end

function M.setWild(S, on)
  local p = S.project
  if M.wildEnabled(p) == (on == true) then return false end
  if on then p.gen3KantoWild = nil else p.gen3KantoWild = false end
  local base = S.data and S.data._gen3EditorContent and S.data._gen3EditorContent.encounters
  if base then
    if on then M.addWild(S, base)
    else
      -- take the game's lists back out of the editor (lists you edited stay yours)
      for id, rec in pairs(base) do
        if type(rec) == "table" and rec._editorKantoWild then base[id] = nil end
      end
    end
  end
  return true
end

--- Import region's wild Pokemon in the editor: each map's lists as its
-- FR_KANTO_ map's own (Encounters tab). Edited ones are saved as the mod's
-- own lists; the rest are the game's, used as they are in the game.
-- `base` is the editor's encounter catalog.
function M.addWild(S, base)
  if not (M.imported(S.project) and M.wildEnabled(S.project)) then return end
  for _, row in ipairs(ownRegionMaps(S)) do
    local id, t = M.regionId(row[1]), base[row[1]]
    if type(t) == "table" and base[id] == nil then
      local rec = copy(t)
      rec.mapGroup, rec.mapNum, rec.variants = nil, nil, nil
      rec.id, rec._isNew, rec._editorKantoWild = id, true, true
      base[id] = rec
    end
  end
end

local HEADER = { "mapType", "weather", "regionMapSectionId", "showMapName", "allowEscaping", "allowRunning",
  "bikingAllowed", "floorNum", "battleType", "cave" }

--- GAME PATCHES > Kanto Region > Import region: every map as
-- FR_KANTO_<name>, joined by the game's connections and warps. Maps the
-- project already has are left alone. Returns added, skipped, signs, people
-- (or nil and why).
function M.importRegion(S)
  if not kanto(S.project) then return nil, "Kanto Region is for FireRed and LeafGreen projects" end
  local ids = M.maps(S)
  if #ids == 0 then return nil, "No maps found" end
  local known = {}
  for _, id in ipairs(ids) do known[id] = M.regionId(id) end
  local p = S.project
  p.gen3MapLayouts = p.gen3MapLayouts or {}
  p.gen3 = p.gen3 or {}; p.gen3.maps = p.gen3.maps or {}
  p.gen3Modes = p.gen3Modes or {}; p.gen3Modes.maps = p.gen3Modes.maps or {}
  local exists = function(id)
    return ((S.data or {}).maps or {})[id] or p.gen3.maps[id] or (p.maps or {})[id] or (p.layeredMaps or {})[id]
      or p.gen3MapLayouts[id]
  end
  local Connections = require("Gen3Connections")
  local added, skipped, signs = 0, 0, 0
  for _, sid in ipairs(ids) do
    local id, base = known[sid], S.data.maps[sid]
    if exists(id) or not (base.width and base.height) then skipped = skipped + 1
    else
      local header = M.header(S, sid)
      local def = { id = id, name = id, width = base.width, height = base.height, pair = base.pair,
        objects = {}, bgEvents = M.signsFor(S, sid), coordEvents = {}, mapScripts = {}, warps = {}, connections = {} }
      for _, key in ipairs(HEADER) do
        local value = base[key]
        if value == nil then value = header[key] end
        if value ~= nil then def[key] = value end
      end
      def.music = base.music or header.music
      for _, w in ipairs(base.warps or {}) do
        def.warps[#def.warps + 1] = { x = w.x, y = w.y, destMap = known[w.destMap] or w.destMap, destWarp = w.destWarp }
      end
      local rows = {}
      for _, row in ipairs(Connections.each(base.connections or {})) do
        local dir, c = row[1], row[2]
        local dest = known[c.map or c.mapId]
        if dest then rows[#rows + 1] = { dir = dir, map = dest, offset = c.offset or 0 } end
      end
      def.connections = Connections.normalize(rows)
      signs = signs + #def.bgEvents
      p.gen3MapLayouts[id] = { source = sid, width = base.width, height = base.height, blank = false }
      p.gen3.maps[id] = def
      p.gen3Modes.maps[id] = "register"
      added = added + 1
    end
  end
  p.gen3KantoRegion = true
  local people = M.peopleEnabled(p) and addPeople(S) or 0
  refresh(S)
  local base = S.data and S.data._gen3EditorContent and S.data._gen3EditorContent.encounters
  if base then M.addWild(S, base) end
  return added, skipped, signs, people
end

function M.emit(project, encode, out)
  if not M.imported(project) then return end
  local wild, respawn = M.wildEnabled(project), M.peopleEnabled(project)
  if wild or respawn then
    out[#out + 1] = "local kantoRegion=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3KantoRegionRuntime.lua"),
      "Gen3KantoRegionRuntime.lua missing") .. "\nend)()\nkantoRegion.install(mod," .. encode({ wild = wild, respawn = respawn }) .. ")"
  end
  -- the maps' own step callback (the Icefall Cave ice), which FireRed starts
  -- from map scripts Import region leaves out
  out[#out + 1] = "local regionTiles=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3RegionTilesRuntime.lua"),
    "Gen3RegionTilesRuntime.lua missing") .. "\nend)()\nregionTiles.install(mod," .. encode({ host = "frlg", origin = "firered", region = M.REGION, derive = true }) .. ")"
  -- visited towns for Fly, and Fly landing on the imported copies
  out[#out + 1] = "local regionMap=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3RegionMapRuntime.lua"),
    "Gen3RegionMapRuntime.lua missing") .. "\nend)()\nregionMap.install(mod," .. encode({ host = "frlg", origin = "firered", cross = false, region = M.REGION, prefix = "FR_", derive = true }) .. ")"
end

return M
