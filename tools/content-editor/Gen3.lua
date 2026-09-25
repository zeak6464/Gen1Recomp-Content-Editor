-- Editor bridge to the runtime's public Gen 3 content schemas.
local Gen3 = {}
Gen3.tabs = { pokemon = "pokemon", moves = "moves", items = "items",
  trainers = "trainers", encounters = "encounters", maps = "maps",
  dialog = "text", events = "map_scripts" }
Gen3.registries = { "pokemon", "moves", "items", "trainers", "encounters",
  "maps", "text", "map_scripts" }

function Gen3.load(data, read, list)
  local Serializer = require("Gen3Decode")
  local function get(name, required)
    local path = "data/generated/" .. name .. ".lua"
    local bytes = read(path)
    if not bytes then
      assert(not required, "Missing Gen 3 cache: " .. path)
      return {}
    end
    local value, err = Serializer.decode(bytes, { allowArray = true, allowComments = true,
      maxBytes = 16 * 1024 * 1024, maxNodes = 1000000, maxTableEntries = 500000,
      maxDepth = 64, maxStringBytes = 4 * 1024 * 1024 })
    assert(type(value) == "table", path .. ": " .. tostring(err))
    return value
  end
  data.maps = get("maps", true)
  if data.maps.stub then data.maps = {} end
  data._gen3Read = read
  data._gen3List = list
  data._g3Animations,data._g3Audio,data._g3Assets=nil,nil,nil
  data._g3ActionMarts=nil
  data._editorGen3Catalog,data._gen3Layouts,data._gen3DerivedLayouts=nil,nil,nil
  data._editorGen3Report=nil
  data._modPokemonArt=nil
  data._editorEvolutionReference=nil
  data._g3PreviewPack=nil
  data._g3TownMap=nil
  data._g3TownMaps=nil
  data._g3Fame=nil
  data._editorGen3Audio,data._g3ShopLocations=nil,nil
  data._g3RomBytes,data._g3RomTrades,data._g3ShinyImages=nil,nil,nil
  data._editorMaps,data._editorTilesets=nil,nil
  data._gen3EditorContent=nil
  data._g3IconImages=nil
  data._g3ItemIcons=nil
  data.gen3Native = get("gba/native/manifest", false)
  local warps = get("gba/warps", false)
  local connections = get("gba/connections", false)
  local events = get("gba/scripts/events", false)
  local okV, Versions = pcall(require,"src.import.gba.versions")
  for id, info in pairs(data.gen3Native.layouts or {}) do
    local def = data.maps[id] or {}
    local spec = okV and Versions.MAPS and Versions.MAPS[id] or {}
    def.id, def.name = id, def.name or id
    def.width, def.height = info.width, info.height
    def.pair, def.warps, def.connections = info.pair, warps[id] or {}, connections[id] or {}
    for _, key in ipairs({"kind","environment","weather","mapType","regionMapSectionId","showMapName"}) do
      if def[key] == nil then def[key] = spec[key] end
    end
    local ev = events[id] or {}
    def.objects = ev.objects or ev.objectEvents or {}
    for _, key in ipairs({"bgEvents","coordEvents","mapScripts","music"}) do def[key] = ev[key] end
    data.maps[id] = def
  end
  require("Gen3Connections").recover(data.maps)
  data.gen3Pokemon = {}
  local parts = { names = "names", types = "types", stats = "stats",
    abilities = "abilities", abilityNames = "ability_names", meta = "meta",
    learnsets = "learnsets", evolutions = "evolutions", dex = "dex", moveNames = "move_names" }
  for key, file in pairs(parts) do
    data.gen3Pokemon[key] = get("gba/pokemon/" .. file, true)
  end
  data.gen3Pokemon.national = get("gba/pokemon/national", false)
  data.gen3Pokemon.tmhm = get("gba/pokemon/tmhm", false)
  data.gen3Moves = { rom = get("gba/pokemon/battle_moves", true),
    names = data.gen3Pokemon.moveNames }
  data.gen3Items = get("gba/items/pack", true)
  data.gen3Trainers = get("gba/trainers", true)
  data.gen3Encounters = get("gba/encounters", true)
  data.gen3Text = get("gba/scripts/text", true)
  data.gen3Scripts = get("gba/scripts/scripts", true)
  local Schemas = require("src.mods.Schemas")
  assert(Schemas.bindGen3, "Linked runtime needs Gen 3 content-schema support")
  Schemas.bindGen3(data)
  data._editorGen3 = true
end

function Gen3.catalog(data, name)
  if data._editorGen3Catalog and data._editorGen3Catalog[name] then
    return data._editorGen3Catalog[name]
  end
  local Schemas = require("src.mods.Schemas")
  local raw = assert(Schemas.REGISTRIES[name], "Unknown registry")
  local spec = Schemas.shapeFor(name, raw, 3)
  local base = data[Schemas.targetFor(name, raw, 3)] or {}
  local ids = spec.baseIds and spec.baseIds(base) or {}
  if not spec.baseIds then for id in pairs(base) do ids[#ids + 1] = id end end
  local result = {}
  for _, id in ipairs(ids) do
    local rec = spec.baseAt and spec.baseAt(base, id) or base[id]
    if rec ~= nil then result[tostring(id)] = rec end
  end
  return result
end

function Gen3.check(name, id, value, operation)
  local Schemas = require("src.mods.Schemas")
  local mode = operation or ((name == "text" or name == "map_scripts") and "override" or "patch")
  if mode~="patch" and mode~="override" and mode~="register" then return false,"Invalid content operation" end
  local ok, errors = Schemas.check(Schemas.REGISTRIES[name], name, id, value, mode, 3)
  return ok, type(errors) == "table" and table.concat(errors, "; ") or errors, mode
end

function Gen3.projectError(project)
  local Generation = require("Generation")
  if not Generation.isGen3({version=project.game or project.version}) then
    if (project.gen3 and next(project.gen3)) or next(project.gen3Borders or {}) or next(project.gen3Terrain or {}) or next(project.gen3Hooks or {}) or next(project.gen3Starters or {}) or require("Gen3Native").used(project) or next(project.gen3MapLayouts or {}) then
      return "This project has Gen 3 edits. Select FireRed or LeafGreen before saving."
    end
    return nil
  end
  local function hasValues(value)
    if type(value) ~= "table" then return value ~= nil end
    for _, child in pairs(value) do if hasValues(child) then return true end end
    return false
  end
  local shared=project.gen3Workspace and {maps=true,layeredMaps=true,mapTileSources=true,
    runtimeTileAnims=true,mapWarpNodes=true,mapStamps=true,mapAssemblies=true} or {}
  if project.gen3AudioWorkspace then shared.audio=true end
  if project.gen3Workbench then shared.boot=true;shared.marts=true;shared.types=true;shared.type_matchups=true end
  for name in pairs(project.gen3ContentWorkspaces or {}) do shared[name]=true end
  for key, default in pairs(require("State").blankProject("check")) do
    if not shared[key] and type(default) == "table" and hasValues(project[key]) then
      return "Gen 3 cannot export legacy " .. key .. " edits. Create a new Gen 3 project."
    end
  end
end

function Gen3.emit(project, encode)
  require("Gen3SpeciesCapacity").install()
  require("Gen3Trades").prepare(project)
  require("Gen3ContentAdapter").compile(project)
  require("Gen3AudioAdapter").compile(project)
  local problem = Gen3.projectError(project)
  assert(not problem, problem)
  local out = { "-- generated by tools/content-editor (Gen 3).",
    "return function(mod)",
    "  if mod.generation ~= 3 then return end" }
  out[#out+1]=require("Gen3SpeciesCapacity").source
  local authoredConnections={}
  for id,record in pairs((project.gen3 or {}).maps or {}) do if record.connections~=nil then
    require("Gen3Connections").validate(record.connections);authoredConnections[id]=true
  end end
  out[#out+1]="local connections=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3Connections.lua")).."\nend)()"
  out[#out+1]="local connectionRuntime=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3ConnectionsRuntime.lua")).."\nend)()\nconnectionRuntime.install(mod,connections,"..encode(authoredConnections)..")"
  out[#out+1] = [[  local function assetPaths(value)
    if type(value) ~= "table" then return value end
    for key, child in pairs(value) do
      if type(child) == "string" and tostring(key):match("^sprite") and child:sub(1,7) == "assets/" then
        value[key] = mod.path .. "/" .. child
      elseif type(child) == "table" then assetPaths(child) end
    end
    return value
  end]]
  for _, name in ipairs(Gen3.registries) do
    local records = (project.gen3 or {})[name] or {}
    local ids = {}
    for id in pairs(records) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local operation = ((project.gen3Modes or {})[name] or {})[id]
      local ok, err, mode = Gen3.check(name, id, records[id], operation)
      assert(ok, tostring(err))
      -- Expansion mods can edit thousands of records. Keep each payload in
      -- its own function so the entry point stays within LuaJIT's limits.
      out[#out+1]="  do local function applyRecord()"
      if mode=="patch" and ((project.gen3Exact or {})[name] or {})[id] then
        out[#out+1]=string.format("  do local value = {}; for k,v in pairs(mod.content.%s:get(%q) or {}) do value[k]=v end",name,id)
        out[#out+1]="    for k,v in pairs(assetPaths("..encode(records[id])..")) do value[k]=v end"
        out[#out+1]=string.format("    mod.content.%s:override(%q,value) end",name,id)
      else
        out[#out + 1] = string.format("  mod.content.%s:%s(%q, %s)", name, mode, id, "assetPaths(" .. encode(records[id]) .. ")")
      end
      out[#out+1]="  end; applyRecord() end"
    end
  end
  require("Gen3Map").emit(project, encode, out)
  require("Gen3Starters").emit(project, encode, out)
  require("Gen3Native").emit(project, encode, out)
  require("Gen3BattlePositions").emit(project,encode,out)
  require("OfflineGifts").emit(project, encode, out, 3)
  require("SafariSettings").emit(project, encode, out, 3)
  if next(project.gen3Layered or {}) then
    out[#out+1]="local bridges=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3BridgesRuntime.lua")).."\nend)()\nbridges.install(mod)"
    -- Keep large map constructors outside the entry function's early-return
    -- jump span, and give each map its own LuaJIT constant/instruction budget.
    out[#out+1]="  local layered=(function() local data={}"
    for _, bag in ipairs({{"maps",project.gen3Layered},
        {"sources",project.gen3TileSources or {}},
        {"animations",project.gen3TileAnimations or {}}}) do
      out[#out+1]="    data."..bag[1].."={}"
      local keys={}
      for key in pairs(bag[2]) do keys[#keys+1]=key end
      table.sort(keys)
      for _,key in ipairs(keys) do
        out[#out+1]="    data."..bag[1].."["..encode(key).."]=(function() return "
          ..encode(bag[2][key]).." end)()"
      end
    end
    out[#out+1]="    return data end)()"
    out[#out+1]=require("Gen3LayeredRuntime")
  end
  out[#out + 1] = "end\n"
  return table.concat(out, "\n")
end

return Gen3
