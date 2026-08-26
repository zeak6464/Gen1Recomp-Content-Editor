-- Evolution family + breeding-partner trees for the Pokemon tab.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Preview = require("Preview")
local Generation = require("Generation")
local PAL = Theme.PAL

local EvoBreedTrees = {}

local EGG_NONE = "EGG_NONE"
local NO_EGGS_RAW = 0xFF
local DITTO = "DITTO"
local NIDORAN_F = "NIDORAN_F"

local function defOf(S, id)
  if not id then return nil end
  local proj = S.project and S.project.pokemon and S.project.pokemon[id]
  if type(proj) == "table" then return proj end
  local data = S.data and S.data.pokemon and S.data.pokemon[id]
  if type(data) == "table" then return data end
  return nil
end

local function allSpeciesIds(S)
  local seen, ids = {}, {}
  local deleted = (S.project and S.project.deleted and S.project.deleted.pokemon) or {}
  for id, rec in pairs((S.project and S.project.pokemon) or {}) do
    if not deleted[id] and State.isPokemonRecord(id, rec) then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.data and S.data.pokemon then
    for id, rec in pairs(S.data.pokemon) do
      if not seen[id] and not deleted[id] and State.isPokemonRecord(id, rec) then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function sortByDex(S, ids)
  table.sort(ids, function(a, b)
    local da = defOf(S, a)
    local db = defOf(S, b)
    local ia = (da and tonumber(da.dex)) or 9999
    local ib = (db and tonumber(db.dex)) or 9999
    if ia ~= ib then return ia < ib end
    return a < b
  end)
end

local function evoInto(evo, gen2)
  if type(evo) ~= "table" then return nil end
  local id = gen2 and (evo.into or evo.species) or (evo.species or evo.into)
  if type(id) == "string" and id ~= "" then return id end
  return nil
end

local function evoLabel(evo)
  local m = tostring((evo and evo.method) or "")
  m = m:gsub("^EVOLVE_", "")
  if m == "LEVEL" then
    return evo.level and ("Lv" .. tostring(evo.level)) or "Level"
  elseif m == "STAT" then
    local lv = evo.level and ("Lv" .. tostring(evo.level)) or "Lv?"
    local c = evo.comparison or ""
    if c == "ATK_LT_DEF" then c = "Atk<Def"
    elseif c == "ATK_GT_DEF" then c = "Atk>Def"
    elseif c == "ATK_EQ_DEF" then c = "Atk=Def"
    end
    return c ~= "" and (lv .. " " .. c) or lv
  elseif m == "ITEM" then
    return evo.item or "Item"
  elseif m == "TRADE" then
    local item = evo.item
    if type(item) == "string" and item ~= "" and item ~= "NO_ITEM" then
      return "Trade " .. item
    end
    return "Trade"
  elseif m == "HAPPINESS" then
    local t = evo.time or "ANYTIME"
    if t == "MORNDAY" then return "Happy day" end
    if t == "NITE" then return "Happy night" end
    return "Happy"
  elseif m ~= "" then
    return m
  end
  return "Evo"
end

local function buildChildren(S, gen2)
  local children, parents = {}, {}
  local function add(from, evo)
    local into = evoInto(evo, gen2)
    if not into or not defOf(S, into) then return end
    children[from] = children[from] or {}
    children[from][#children[from] + 1] = { into = into, evo = evo }
    parents[into] = parents[into] or {}
    for i = 1, #parents[into] do
      if parents[into][i] == from then return end
    end
    parents[into][#parents[into] + 1] = from
  end
  for _, id in ipairs(allSpeciesIds(S)) do
    local def = defOf(S, id)
    for _, evo in ipairs((def and def.evolutions) or {}) do
      add(id, evo)
    end
  end
  return children, parents
end

local function familyRoots(startId, parents)
  local up, stack = {}, { startId }
  while #stack > 0 do
    local id = table.remove(stack)
    if id and not up[id] then
      up[id] = true
      for _, p in ipairs(parents[id] or {}) do
        stack[#stack + 1] = p
      end
    end
  end
  local roots = {}
  for id in pairs(up) do
    local linked = false
    for _, p in ipairs(parents[id] or {}) do
      if up[p] then linked = true; break end
    end
    if not linked then roots[#roots + 1] = id end
  end
  table.sort(roots)
  if #roots == 0 then roots[1] = startId end
  return roots
end

local function baseForm(startId, parents)
  local cur, guard = startId, 0
  while guard < 8 do
    local list = parents[cur]
    local p = list and list[1]
    if not p then break end
    cur = p
    guard = guard + 1
  end
  return cur
end

local function drawSprite(S, id, x, y, size)
  local def = defOf(S, id)
  if def and def.spriteFront then
    local pal = Preview.monPaletteName(S, def, id)
    if def.trueColor then pal = false end
    Preview.draw(S, def.spriteFront, x, y, size, size, pal)
  else
    Preview.drawPokemonIcon(S, def, x, y, size, size, id)
  end
end

local function drawConnector(x1, y1, x2, y2)
  local G = love and love.graphics
  if not (G and G.line) then return end
  Theme.col(PAL.caption, 0.4)
  if G.setLineWidth then G.setLineWidth(1) end
  G.line(x1, y1, x2, y2)
end

local function eggGroupsOf(def)
  local g = def and def.eggGroups
  if type(g) ~= "table" then return nil, nil end
  return g[1], g[2]
end

local function isNoEggs(def)
  if not def then return true end
  if type(def.eggGroupsRaw) == "number" then
    return def.eggGroupsRaw == NO_EGGS_RAW
  end
  local a, b = eggGroupsOf(def)
  return a == EGG_NONE and b == EGG_NONE
end

local function groupsCompatible(def1, def2, id1, id2)
  if not (def1 and def2) then return false end
  if isNoEggs(def2) or isNoEggs(def1) then return false end
  if id1 == DITTO or id2 == DITTO then return true end
  local b, c = eggGroupsOf(def2)
  local d, e = eggGroupsOf(def1)
  if d ~= nil and (d == b or d == c) then return true end
  if e ~= nil and (e == b or e == c) then return true end
  return false
end

-- 0 always male, 254 always female, 255 genderless; anything else can be either.
local function genderKind(def)
  local r = def and tonumber(def.genderRatio)
  if r == nil then r = 31 end
  if r == 255 then return "none" end
  if r == 0 then return "male" end
  if r == 254 then return "female" end
  return "mixed"
end

local function genderOk(idA, defA, idB, defB)
  if idA == DITTO then return idB ~= DITTO end
  if idB == DITTO then return idA ~= DITTO end
  local ga, gb = genderKind(defA), genderKind(defB)
  if ga == "none" or gb == "none" then return false end
  if ga == "mixed" or gb == "mixed" then return true end
  return ga ~= gb
end

local function canBreed(idA, defA, idB, defB)
  return groupsCompatible(defA, defB, idA, idB)
    and genderOk(idA, defA, idB, defB)
end

local function groupTitle(g)
  return tostring(g or ""):gsub("^EGG_", ""):gsub("_", " ")
end

local function genderBlurb(kind)
  if kind == "none" then return "Genderless — only Ditto can produce an egg." end
  if kind == "male" then return "Always male — needs a female or Ditto." end
  if kind == "female" then return "Always female — needs a male or Ditto." end
  return "Can be male or female."
end

local function firstSharedGroup(defA, defB)
  local a1, a2 = eggGroupsOf(defA)
  local b1, b2 = eggGroupsOf(defB)
  for _, g in ipairs({ a1, a2 }) do
    if g and g ~= EGG_NONE and (g == b1 or g == b2) then return g end
  end
  return nil
end

local function drawNode(S, id, x, y, nodeW, nodeH, s)
  local selected = S.pokemonId == id
  Kit.offerTooltip(x, y, nodeW, nodeH, id)
  if Kit.row(x, y, nodeW, nodeH, selected, PAL.green) then
    S.pokemonId = id
  end
  local spr = math.min(nodeW - 8 * s, nodeH - 20 * s)
  drawSprite(S, id, x + (nodeW - spr) / 2, y + 4 * s, spr)
  local name = Kit.ellipsize("micro", id, nodeW - 6 * s)
  Kit.textCenter("micro", name, x, y + nodeH - 14 * s, nodeW,
    selected and PAL.text or PAL.muted)
end

local function drawCellGrid(S, ids, x, y, w, s)
  local cellW = 56 * s
  local cellH = 70 * s
  local gap = 6 * s
  local cols = math.max(1, math.floor((w + gap) / (cellW + gap)))
  for i, id in ipairs(ids) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local cx = x + col * (cellW + gap)
    local cy = y + row * (cellH + gap)
    drawNode(S, id, cx, cy, cellW, cellH, s)
  end
  local rows = math.ceil(#ids / cols)
  if rows < 1 then return y end
  return y + rows * (cellH + gap)
end

local function drawEvoTree(S, speciesId, x, y, w, s)
  Kit.caption(x, y, "EVOLUTION")
  y = y + 22 * s
  Kit.text("micro", "Whole family. Click a sprite to inspect that species.",
    x, y, PAL.muted)
  y = y + 18 * s

  local gen2 = Generation.isGen2(S)
  local children, parents = buildChildren(S, gen2)
  local roots = familyRoots(speciesId, parents)

  local nodeW = 56 * s
  local nodeH = 70 * s
  local arrowW = 78 * s
  local gap = 8 * s

  local memo, inProg = {}, {}
  local function measure(id)
    if memo[id] then return memo[id] end
    if inProg[id] then return nodeH end
    inProg[id] = true
    local kids = children[id]
    local h, n = 0, 0
    for _, kid in ipairs(kids or {}) do
      if kid.into then
        n = n + 1
        h = h + measure(kid.into) + gap
      end
    end
    inProg[id] = nil
    if n == 0 then h = nodeH else h = math.max(nodeH, h - gap) end
    memo[id] = h
    return h
  end

  local function drawTree(id, tx, ty, trail)
    trail = trail or {}
    if trail[id] then
      drawNode(S, id, tx, ty, nodeW, nodeH, s)
      return nodeH
    end
    trail[id] = true
    local h = measure(id)
    local kids = children[id] or {}
    local ny = ty + (h - nodeH) / 2
    drawNode(S, id, tx, ny, nodeW, nodeH, s)
    if #kids == 0 then
      trail[id] = nil
      return h
    end
    local cx = tx + nodeW + arrowW
    local cy = ty
    for _, kid in ipairs(kids) do
      local into = kid.into
      if into then
        local kh = measure(into)
        local x1 = tx + nodeW
        local y1 = ny + nodeH / 2
        local x2 = cx
        local y2 = cy + kh / 2
        drawConnector(x1, y1, x2, y2)
        local label = Kit.ellipsize("micro", evoLabel(kid.evo), arrowW - 4 * s)
        Kit.textCenter("micro", label, tx + nodeW,
          (y1 + y2) / 2 - 6 * s, arrowW, PAL.caption)
        drawTree(into, cx, cy, trail)
        cy = cy + kh + gap
      end
    end
    trail[id] = nil
    return h
  end

  local used = 0
  for _, root in ipairs(roots) do
    used = used + drawTree(root, x, y + used) + gap
  end
  if used > 0 then used = used - gap end
  return y + math.max(used, nodeH) + 12 * s
end

local function drawBreeding(S, speciesId, x, y, w, s)
  Kit.caption(x, y, "BREEDING")
  y = y + 22 * s
  if not Generation.isGen2(S) then
    Kit.text("micro", "Egg groups are Gold / Crystal only. Red, Blue, and Yellow have no breeding.",
      x, y, PAL.muted)
    return y + 20 * s
  end

  local def = defOf(S, speciesId)
  if not def then return y end

  local g1, g2 = eggGroupsOf(def)
  local groups = {}
  if g1 then groups[#groups + 1] = g1 end
  if g2 and g2 ~= g1 then groups[#groups + 1] = g2 end
  local gx = x
  for _, g in ipairs(groups) do
    local label = groupTitle(g)
    local bw = Kit.textWidth("micro", label) + 18 * s
    Kit.chip(gx, y, bw, 22 * s, label, true, PAL.blue)
    gx = gx + bw + 4 * s
  end
  y = y + 28 * s

  local kind = genderKind(def)
  Kit.text("micro", genderBlurb(kind), x, y, PAL.muted)
  y = y + 18 * s

  if isNoEggs(def) then
    Kit.text("micro", "EGG_NONE — this species cannot produce eggs, including with Ditto.",
      x, y, PAL.yellow)
    return y + 20 * s
  end

  local _, parents = buildChildren(S, true)
  local hatch = baseForm(speciesId, parents)
  Kit.text("micro", "Egg hatches as", x, y + 8 * s, PAL.caption)
  drawNode(S, hatch, x + 110 * s, y, 56 * s, 70 * s, s)
  y = y + 78 * s
  if hatch == NIDORAN_F then
    Kit.text("micro", "Nidoran♀ eggs are 50% Nidoran♀ / 50% Nidoran♂.",
      x, y, PAL.muted)
    y = y + 16 * s
  end

  local buckets, order, seen = {}, {}, {}
  if speciesId == DITTO then
    order[1] = "ANY"
    buckets["ANY"] = {}
  end
  for _, id in ipairs(allSpeciesIds(S)) do
    local other = defOf(S, id)
    if other and canBreed(speciesId, def, id, other) then
      local key
      if speciesId == DITTO then
        key = "ANY"
      elseif id == DITTO then
        key = DITTO
      else
        key = firstSharedGroup(def, other) or "OTHER"
      end
      if not buckets[key] then
        buckets[key] = {}
        order[#order + 1] = key
      end
      if not seen[id] then
        seen[id] = true
        buckets[key][#buckets[key] + 1] = id
      end
    end
  end

  local function keyRank(k)
    if k == DITTO then return 90 end
    if k == "ANY" then return 0 end
    if k == "OTHER" then return 80 end
    for i, g in ipairs(groups) do
      if g == k then return i end
    end
    return 50
  end
  table.sort(order, function(a, b)
    local ra, rb = keyRank(a), keyRank(b)
    if ra ~= rb then return ra < rb end
    return a < b
  end)

  local total = 0
  for _, key in ipairs(order) do
    total = total + #buckets[key]
  end
  Kit.text("micro",
    string.format("Can produce an egg with %d species. Click a sprite to inspect it.", total),
    x, y, PAL.muted)
  y = y + 18 * s

  for _, key in ipairs(order) do
    local ids = buckets[key]
    sortByDex(S, ids)
    local heading = key == "ANY" and "Not in the No Eggs group"
      or key == DITTO and "Ditto"
      or groupTitle(key)
    Kit.caption(x, y, string.format("%s  (%d)", heading, #ids))
    y = y + 22 * s
    y = drawCellGrid(S, ids, x, y, w, s) + 8 * s
  end
  return y
end

function EvoBreedTrees.draw(S, speciesId, x, y, w)
  local s = Kit.scale or 1
  if not speciesId then return y end
  y = drawEvoTree(S, speciesId, x, y, w, s)
  y = drawBreeding(S, speciesId, x, y, w, s)
  return y
end

return EvoBreedTrees
