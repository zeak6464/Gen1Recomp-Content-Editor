-- Resolve the live list of type ids (vanilla TypeChart + project types).

local TypeIds = {}

local FALLBACK = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON",
}

local FALLBACK_GEN2 = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BIRD", "BUG",
  "GHOST", "STEEL", "CURSE_TYPE", "FIRE", "WATER", "GRASS", "ELECTRIC",
  "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK",
}

function TypeIds.list(S)
  if require("Generation").isGen3(S) then
    local ids,seen={},{};for _,id in pairs(require("src.mods.Schemas").gen3View.TYPES) do ids[#ids+1]=id;seen[id]=true end
    for id in pairs(S.project and S.project.types or {}) do if not seen[id] then ids[#ids+1]=id end end
    table.sort(ids);return ids
  end
  local seen, ids = {}, {}
  local function add(id)
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.TYPES then
    for id in pairs(TypeChart.TYPES) do add(id) end
  end
  if S and S.data and S.data.type_chart then
    local tc = S.data.type_chart
    if tc.types then
      for id in pairs(tc.types) do add(id) end
    end
    for _, name in ipairs(tc.names or {}) do
      -- generated names use PSYCHIC; live ids use PSYCHIC_TYPE
      if name == "PSYCHIC" then add("PSYCHIC_TYPE") else add(name) end
    end
  end
  if S and S.project and S.project.types then
    for id in pairs(S.project.types) do add(id) end
  end
  if #ids == 0 then
    local Generation = require("Generation")
    local fb = Generation.isGen2(S) and FALLBACK_GEN2 or FALLBACK
    for _, id in ipairs(fb) do add(id) end
  end
  -- Gold authoring always exposes Gold-only types even if a Gen1 TypeChart
  -- module was required first.
  do
    local Generation = require("Generation")
    if Generation.isGen2(S) then
      for _, id in ipairs({ "DARK", "STEEL", "CURSE_TYPE", "BIRD" }) do
        add(id)
      end
    end
  end
  table.sort(ids)
  return ids
end

function TypeIds.cycle(S, cur, allowNone)
  local list = TypeIds.list(S)
  if allowNone then
    -- append sentinel after last
    local idx = 0
    for i, t in ipairs(list) do
      if t == cur then idx = i; break end
    end
    if cur == nil or cur == "" then return list[1] end
    if idx == 0 then return list[1] end
    if idx >= #list then return nil end
    return list[idx + 1]
  end
  local idx = 0
  for i, t in ipairs(list) do
    if t == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

return TypeIds
