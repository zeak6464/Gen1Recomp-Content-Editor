-- Regions you define yourself (UI > Town Map > Regions), with no import or link
-- behind them: a name, a colour and the maps in it. The editor shows them (a
-- colour mark in the map lists, "@name" in the search); an Emerald mod also
-- carries each region's PokeNav wording into the game.
--
-- A region owns maps by name prefix ("EM_HOENN_") with per-map overrides: a map
-- you add to a region is in it whatever its name, a map you take out is not.
-- A map is in at most one region.
local M = {}

M.COLORS = { "#e5484d", "#f5a524", "#e5d43d", "#46a758", "#12a594", "#3e63dd", "#8e4ec6", "#d6409f" }
M.NAME_MAX = 24
M.NAV_MAX = { label = 10, desc = 40 }
-- Prefixes the game's own imports use, offered by "Add the regions in use".
M.KNOWN = {
  { name = "Hoenn", prefixes = { "EM_HOENN_", "FR_HOENN_" } },
  { name = "Kanto", prefixes = { "FR_KANTO_", "EM_KANTO_" } },
}

function M.list(project)
  local r = project and project.gen3Regions
  return type(r) == "table" and r or {}
end

function M.find(project, id)
  for _, r in ipairs(M.list(project)) do
    if r.id == id then return r end
  end
  return nil
end

local function ensure(project)
  if type(project.gen3Regions) ~= "table" then project.gen3Regions = {} end
  return project.gen3Regions
end

local function slug(name)
  local s = tostring(name or ""):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return s ~= "" and s or "region"
end

local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

local function without(list, v)
  local out = {}
  for _, x in ipairs(list or {}) do if x ~= v then out[#out + 1] = x end end
  return out
end

--- The region a map is in, or nil. An explicit add wins; otherwise the longest
-- matching prefix among the regions that haven't taken the map out.
function M.ownerOf(project, mapId)
  if type(mapId) ~= "string" then return nil end
  local best, bestLen
  for _, r in ipairs(M.list(project)) do
    if has(r.include, mapId) then return r end
  end
  for _, r in ipairs(M.list(project)) do
    if not has(r.exclude, mapId) then
      for _, p in ipairs(r.prefixes or {}) do
        if #p > 0 and mapId:sub(1, #p) == p and (not bestLen or #p > bestLen) then best, bestLen = r, #p end
      end
    end
  end
  return best
end

function M.colorOf(project, mapId)
  local r = M.ownerOf(project, mapId)
  return r and r.color or nil
end

--- Colour "#rrggbb" as 0..1 r, g, b.
function M.rgb(hex)
  local r, g, b = tostring(hex or ""):match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then return 0.5, 0.5, 0.5 end
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

--- Search: "@hoenn" lists the maps of regions whose name starts so; "@" alone
-- lists every map that is in a region; "@-" lists the maps in none.
function M.matches(project, mapId, query)
  local q = tostring(query or ""):lower()
  if q:sub(1, 1) ~= "@" then return nil end
  q = q:sub(2)
  local r = M.ownerOf(project, mapId)
  if q == "" then return r ~= nil end
  if q == "-" then return r == nil end
  return r ~= nil and r.name:lower():sub(1, #q) == q
end

--- Every map id the project has (game maps and its own).
function M.allMapIds(S)
  local seen, ids = {}, {}
  local function add(t)
    for id in pairs(t or {}) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  add(S.data and S.data.maps)
  add(S.project and S.project.maps)
  add(S.project and (S.project.gen3 or {}).maps)
  table.sort(ids)
  return ids
end

--- How many of `ids` are in the region.
function M.count(project, region, ids)
  local n = 0
  for _, id in ipairs(ids) do
    if M.ownerOf(project, id) == region then n = n + 1 end
  end
  return n
end

local function nextColor(list)
  return M.COLORS[(#list % #M.COLORS) + 1]
end

--- A new region. Returns it, or nil and why.
function M.add(S, name, prefixes)
  local p = S.project
  if not p then return nil, "No project" end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, M.NAME_MAX)
  if name == "" then return nil, "Give the region a name" end
  local list = ensure(p)
  for _, r in ipairs(list) do
    if r.name:lower() == name:lower() then return nil, "There is already a region called " .. r.name end
  end
  local base, id, n = slug(name), nil, 1
  id = base
  while M.find(p, id) do n = n + 1; id = base .. "_" .. n end
  local region = { id = id, name = name, color = nextColor(list), prefixes = prefixes or {}, include = {}, exclude = {} }
  list[#list + 1] = region
  return region
end

function M.remove(S, id)
  local list = M.list(S.project)
  for i, r in ipairs(list) do
    if r.id == id then table.remove(list, i); return true end
  end
  return false
end

--- "EM_HOENN_, fr_hoenn_" -> { "EM_HOENN_", "FR_HOENN_" } (letters, digits and _).
function M.parsePrefixes(text)
  local out = {}
  for token in tostring(text or ""):gmatch("[^,%s;]+") do
    token = token:upper():gsub("[^A-Z0-9_]", "")
    if token ~= "" and not has(out, token) then out[#out + 1] = token end
  end
  return out
end

function M.prefixText(region)
  return table.concat(region.prefixes or {}, ", ")
end

--- Set one field: name, color, prefixes (text), navLabel, navDesc. True when it changed.
function M.set(S, id, field, value)
  local r = M.find(S.project, id)
  if not r then return false end
  if field == "name" then
    value = tostring(value or ""):gsub("^%s+", ""):sub(1, M.NAME_MAX)
    if value:match("^%s*$") then return false end
    for _, o in ipairs(M.list(S.project)) do
      if o ~= r and o.name:lower() == value:lower() then return false end
    end
    if r.name == value then return false end
    r.name = value
    return true
  elseif field == "color" then
    if not has(M.COLORS, value) or r.color == value then return false end
    r.color = value
    return true
  elseif field == "prefixes" then
    local new = M.parsePrefixes(value)
    if table.concat(new, ",") == table.concat(r.prefixes or {}, ",") then return false end
    r.prefixes = new
    return true
  elseif field == "navLabel" or field == "navDesc" then
    local max = field == "navLabel" and M.NAV_MAX.label or M.NAV_MAX.desc
    value = tostring(value or ""):gsub("%c", " "):sub(1, max)
    if field == "navLabel" then value = value:upper() end
    if not value:match("%S") then value = nil end
    if r[field] == value then return false end
    r[field] = value
    return true
  end
  return false
end

--- Put a map in a region (id), or in none (nil). Whatever the name says.
function M.assign(S, mapId, id)
  local p = S.project
  if not (p and type(mapId) == "string") then return false end
  local before = M.ownerOf(p, mapId)
  local target = id and M.find(p, id) or nil
  if (before or nil) == target then return false end
  for _, r in ipairs(M.list(p)) do
    r.include = without(r.include, mapId)
    r.exclude = r.exclude or {}
  end
  if target then
    target.exclude = without(target.exclude, mapId)
    target.include = target.include or {}
    -- by prefix already? then no explicit add is needed
    if M.ownerOf(p, mapId) ~= target then target.include[#target.include + 1] = mapId end
  else
    local owner = M.ownerOf(p, mapId)
    if owner and not has(owner.exclude, mapId) then owner.exclude[#owner.exclude + 1] = mapId end
  end
  return true
end

--- Regions the known prefixes suggest for the maps the project has: { {name, prefixes} }.
function M.suggest(S)
  local ids = M.allMapIds(S)
  local out = {}
  for _, k in ipairs(M.KNOWN) do
    local used = {}
    for _, p in ipairs(k.prefixes) do
      for _, id in ipairs(ids) do
        if id:sub(1, #p) == p then used[#used + 1] = p; break end
      end
    end
    -- not already a region's prefix, and no region of that name
    local fresh = {}
    for _, p in ipairs(used) do
      local taken = false
      for _, r in ipairs(M.list(S.project)) do
        if has(r.prefixes, p) then taken = true end
      end
      if not taken then fresh[#fresh + 1] = p end
    end
    if #fresh > 0 then out[#out + 1] = { name = k.name, prefixes = fresh } end
  end
  return out
end

--- Add every suggested region. Returns how many.
function M.addSuggested(S)
  local n = 0
  for _, s in ipairs(M.suggest(S)) do
    local existing
    for _, r in ipairs(M.list(S.project)) do
      if r.name:lower() == s.name:lower() then existing = r end
    end
    if existing then
      for _, p in ipairs(s.prefixes) do existing.prefixes[#existing.prefixes + 1] = p end
      n = n + 1
    elseif M.add(S, s.name, s.prefixes) then
      n = n + 1
    end
  end
  return n
end

-- In the game ---------------------------------------------------------------

--- The regions that carry wording into the game (Emerald: the PokeNav's map
-- entry and description on the region's maps).
function M.baked(project)
  local out = {}
  for _, r in ipairs(M.list(project)) do
    if r.navLabel or r.navDesc then
      out[#out + 1] = { prefixes = r.prefixes or {}, include = r.include or {}, exclude = r.exclude or {},
        label = r.navLabel, desc = r.navDesc }
    end
  end
  return out
end

function M.used(project)
  return (project or {}).game == "emerald" and #M.baked(project) > 0
end

function M.emit(project, encode, out)
  if not M.used(project) then return end
  out[#out + 1] = "local regionNames=(function()\n" .. assert(love.filesystem.read("tools/content-editor/Gen3RegionsRuntime.lua"),
    "Gen3RegionsRuntime.lua missing") .. "\nend)()\nregionNames.install(mod," .. encode({ regions = M.baked(project) }) .. ")"
end

--- Is this a town, city or route (sea routes too)? `kind` is the map's type
-- (1 Town, 2 City, 3 Route, 6 Ocean route) when it has one; a map without a
-- type is judged by its name.
function M.isTownOrRoute(kind, id)
  kind = tonumber(kind)
  if kind then return kind == 1 or kind == 2 or kind == 3 or kind == 6 end
  local name = tostring(id or ""):upper()
  return name:find("ROUTE", 1, true) ~= nil or name:find("_TOWN$") ~= nil
    or name:find("_CITY$") ~= nil or name:find("_VILLAGE$") ~= nil
end

return M
