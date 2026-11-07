local M={}
function M.natural(a,b)
  local function key(s) return tostring(s):gsub("%d+",function(n) return string.format("%012d",tonumber(n)) end) end
  return key(a)<key(b)
end
function M.map(id)
  local g,n=tostring(id):match("^(%d+):(%d+)$")
  if g then id=require("src.import.gba.map_catalog").mapIdFor(g,n) or id end
  return tostring(id):gsub("^FR_",""):gsub("^EM_",""):gsub("^SEVII_",""):gsub("_"," ")
end
--- One key per map for an encounter table id. The game lists each table
-- under several ids (ROUTE1, ROUTE_1, FR_ROUTE1, FR_ROUTE_1, "3:19") whose
-- names don't all match ("ROUTE1" vs "ROUTE 1"), so the key is the map's
-- group:number when known (the game's own record, then the project's),
-- else the name with its spaces taken out.
function M.encounterKey(id, projectTbl, dataTbl)
  for _, tbl in ipairs({ dataTbl or {}, projectTbl or {} }) do
    local rec = tbl[id]
    if type(rec) == "table" and rec.mapGroup ~= nil and rec.mapNum ~= nil then
      return tostring(rec.mapGroup) .. ":" .. tostring(rec.mapNum)
    end
  end
  local g, n = tostring(id):match("^(%d+):(%d+)$")
  if g then return g .. ":" .. n end
  local ok, name = pcall(M.map, id)
  return "name:" .. (tostring(ok and name or id):gsub(" ", ""))
end

--- Encounter tables: the game has several ids for one map; the Encounters
-- list shows one per map. Returns { [key] = id } (key = M.encounterKey):
-- a table the project has edited wins, then the last named (not
-- "group:num") id.
function M.preferredEncounterIds(projectTbl, dataTbl)
  local seen, ids = {}, {}
  for id in pairs(projectTbl or {}) do seen[id] = true; ids[#ids + 1] = id end
  for id in pairs(dataTbl or {}) do if not seen[id] then ids[#ids + 1] = id end end
  table.sort(ids)
  local preferred = {}
  for _, id in ipairs(ids) do
    local key = M.encounterKey(id, projectTbl, dataTbl)
    local old = preferred[key]
    if not old or (projectTbl or {})[id] or (not (projectTbl or {})[old] and not tostring(id):match("^%d+:")) then
      preferred[key] = id
    end
  end
  return preferred
end

local AREA_KEYS = { "land", "grass", "water", "rocks", "fishing" }

local function slotsOf(area)
  return type(area) == "table" and (area.slots or area) or {}
end

-- How many slots (plus the rate) of `area` differ from `base`.
local function areaChanges(area, base)
  if area == nil then return base == nil and 0 or 1 end
  if base == nil then return 1 + #slotsOf(area) end
  local n = (tonumber(area.rate) or 0) ~= (tonumber(base.rate) or 0) and 1 or 0
  local a, b = slotsOf(area), slotsOf(base)
  for i = 1, math.max(#a, #b) do
    local x, y = a[i], b[i]
    if type(x) ~= "table" or type(y) ~= "table" or x.species ~= y.species
        or x.minLevel ~= y.minLevel or x.maxLevel ~= y.maxLevel then n = n + 1 end
  end
  return n
end

--- A project can hold two records for one map (ROUTE19 and ROUTE_19, from
-- when the list showed both). In game the last one written wins on every
-- other id for that map, so which list you get is luck. Merge each such set
-- into the id the list shows: per area, the record that changed it most
-- from the game's list wins (the shown id on a tie). Day / night lists and
-- Crystal marks follow. An area that lost and differs from both the winner
-- and the game's is kept in project.gen3EncounterMerged[id], so nothing is
-- thrown away. Returns how many records were merged away.
function M.mergeDuplicateEncounters(project, dataTbl)
  local tbl = (project or {}).encounters
  if type(tbl) ~= "table" then return 0 end
  local groups = {}
  for id in pairs(tbl) do
    local key = M.encounterKey(id, tbl, dataTbl)
    groups[key] = groups[key] or {}
    table.insert(groups[key], id)
  end
  local stockShown, merged = nil, 0
  for key, ids in pairs(groups) do
    if #ids > 1 then
      table.sort(ids)
      -- keep the id the list shows for an unedited map (ROUTE_19), else the
      -- last named one
      stockShown = stockShown or M.preferredEncounterIds(nil, dataTbl)
      local keep
      for _, id in ipairs(ids) do if id == stockShown[key] then keep = id end end
      if not keep then
        for _, id in ipairs(ids) do if not tostring(id):match("^%d+:") then keep = id end end
        keep = keep or ids[#ids]
      end
      local base = dataTbl and (dataTbl[keep] or dataTbl[ids[1]]) or nil
      local out = {}
      for k, v in pairs(tbl[keep]) do out[k] = v end
      for _, area in ipairs(AREA_KEYS) do
        local stock = base and base[area]
        local bestN = areaChanges(tbl[keep][area], stock)
        for _, id in ipairs(ids) do
          if id ~= keep then
            local n = areaChanges(tbl[id][area], stock)
            if n > bestN then out[area], bestN = tbl[id][area], n end
          end
        end
      end
      for _, id in ipairs(ids) do
        if id ~= keep then
          local rec = tbl[id]
          for k, v in pairs(rec) do if out[k] == nil then out[k] = v end end
          local lost
          for _, area in ipairs(AREA_KEYS) do
            if rec[area] ~= nil and areaChanges(rec[area], out[area]) > 0
                and areaChanges(rec[area], base and base[area]) > 0 then
              lost = lost or { mergedInto = keep }
              lost[area] = rec[area]
            end
          end
          if lost then
            project.gen3EncounterMerged = project.gen3EncounterMerged or {}
            project.gen3EncounterMerged[id] = lost
          end
          -- day / night lists and Crystal marks follow the record
          local dn = project.gen3DayNight
          if type(dn) == "table" then
            local tl = dn.encounters
            if type(tl) == "table" and tl[id] ~= nil then
              if tl[keep] == nil then tl[keep] = tl[id] end
              tl[id] = nil
            end
            for _, mark in pairs(dn.crystalFilled or {}) do
              if type(mark) == "table" and mark.id == id then mark.id = keep end
            end
          end
          tbl[id] = nil
          merged = merged + 1
        end
      end
      tbl[keep] = out
    end
  end
  return merged
end
--- "LittlerootTown_EventScript_Mom" -> "LittlerootTown EventScript Mom".
function M.script(id)
  local s = tostring(id or "")
  if s == "" then return s end
  return (s:gsub("_", " "))
end

--- The current game's name for a numbered constant, or nil.
-- prefix is the byId group, such as "FLAG_" or "OBJ_EVENT_GFX_".
function M.constant(S, kind, prefix, id)
  local n = tonumber(id)
  local game = S and require("Generation").id(S)
  if not n or not game then return nil end
  local ok, name = pcall(function()
    return require("src.core.game3.constants").of(game):name(kind, n, prefix)
  end)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  local rest = name
  if prefix and name:sub(1, #prefix) == prefix then rest = name:sub(#prefix + 1) end
  rest = rest:gsub("_", " "):lower()
  return (rest:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

function M.scriptMaps(S)
  local result={};local scripts=require("Gen3").catalog(S.data,"map_scripts")
  for map,rec in pairs(S.data.maps or {}) do
    local seen={}
    local function visit(v,depth)
      if depth>40 then return end
      if type(v)=="table" then for _,c in pairs(v) do visit(c,depth+1) end
      elseif type(v)=="string" and scripts[v] and not seen[v] then
        seen[v]=true;result[v]=result[v] or {};result[v][map]=true;visit(scripts[v],depth+1)
      end
    end
    for _,kind in ipairs({"objects","bgEvents","coordEvents","mapScripts"}) do visit(rec[kind],0) end
  end
  return result
end
return M
