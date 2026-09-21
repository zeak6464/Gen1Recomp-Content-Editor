-- Breeding tab (Gold): species egg fields + Day-Care knobs.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local Generation = require("Generation")
local PAL = Theme.PAL

local Breeding = {}

local EGG_GROUPS = {
  "EGG_MONSTER", "EGG_WATER_1", "EGG_BUG", "EGG_FLYING", "EGG_GROUND",
  "EGG_FAIRY", "EGG_PLANT", "EGG_HUMANSHAPE", "EGG_WATER_3", "EGG_MINERAL",
  "EGG_INDETERMINATE", "EGG_WATER_2", "EGG_DITTO", "EGG_DRAGON", "EGG_NONE",
}

local DAYCARE_KEYS = {
  { key = "eggLevel", label = "Egg level", default = 5, tip = "Hatch / egg party level" },
  { key = "hatchHappiness", label = "Hatch happiness", default = 120, tip = "$78 on cart" },
  { key = "minStepsToEgg", label = "Min steps to egg", default = 150, tip = "First egg countdown floor" },
  { key = "withdrawFee", label = "Withdraw fee", default = 100, tip = "Flat ¥ on retrieve" },
  { key = "withdrawFeePerLevel", label = "Fee / level", default = 100, tip = "¥ per level grown" },
}

local function cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1] or list[1]
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

local function resolveMon(S, id)
  if not id then return nil, false end
  if S.project.pokemon[id] then return S.project.pokemon[id], true end
  if S.data and S.data.pokemon and S.data.pokemon[id] then
    return S.data.pokemon[id], false
  end
  return nil, false
end

local function copyStringList(v)
  local out = {}
  if type(v) ~= "table" then return out end
  for i, s in ipairs(v) do out[i] = s end
  return out
end

local function deepCloneMon(def)
  local copy = {}
  for k, v in pairs(def) do
    if k == "types" or k == "tmhm" or k == "eggGroups" or k == "eggMoves"
        or k == "tmhmRaw" then
      copy[k] = copyStringList(v)
    elseif k == "baseStats" and type(v) == "table" then
      local s = {}
      for sk, sv in pairs(v) do s[sk] = sv end
      copy.baseStats = s
    elseif (k == "learnset" or k == "levelMoves" or k == "evolutions")
        and type(v) == "table" then
      local a = {}
      for i, row in ipairs(v) do
        if type(row) == "table" then
          local r = {}
          for rk, rv in pairs(row) do r[rk] = rv end
          a[i] = r
        else
          a[i] = row
        end
      end
      copy[k] = a
    elseif k == "items" and type(v) == "table" then
      copy.items = copyStringList(v)
    else
      copy[k] = v
    end
  end
  copy._isNew = false
  return copy
end

local function ensureOwned(S, id)
  local def, owned = resolveMon(S, id)
  if not def then return nil end
  if owned then return def end
  local copy = deepCloneMon(def)
  S.project.pokemon[id] = copy
  return copy
end

local function parseMoveList(str)
  local moves = {}
  for part in (str .. ","):gmatch("([^,]*),") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then moves[#moves + 1] = part:upper():gsub("%s+", "_") end
  end
  return moves
end

local function field(S, App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function numField(S, App, id, x, y, w, h, value)
  local v = field(S, App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

local function ensureBreeding(S, App)
  State.ensureProjectFields(S.project)
  S.project.breeding = S.project.breeding or {}
  if App then App.markDirty() end
  return S.project.breeding
end

local function breedField(S, key, default)
  local b = S.project and S.project.breeding
  if b and b[key] ~= nil then return tonumber(b[key]) or default end
  local db = S.data and S.data.breeding
  if db and db[key] ~= nil then return tonumber(db[key]) or default end
  return default
end

function Breeding.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  if Generation.isGen3(S) then require("Gen3ContentAdapter").prepare(S) end
  if not Generation.isGen2(S) and not Generation.isGen3(S) then
    Kit.emptyBox(x, y, w, h, "Breeding is Gold-only (Day-Care / eggs)")
    return
  end
  State.ensureProjectFields(S.project)
  if Generation.isGen3(S) then
    local top=RegList.modeChips(S,"g3BreedingMode",{{id="species",label="Species and egg moves"},{id="daycare",label="Day-Care service"}},x,y,s)
    h=h-(top-y);y=top
    if S.g3BreedingMode=="daycare" then return require("Gen3Breeding").draw(S,x,y,w,h,App) end
  end

  local listW = math.min(220 * s, w * 0.28)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s

  Kit.caption(x, y, "SPECIES")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "breedingQuery", x, qy, listW, qh,
    "search species...")
  if qChanged then S.breedingListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 8 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allSpeciesIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local mon = S.project.pokemon[id]
        or (S.data.pokemon and S.data.pokemon[id])
      local name = mon and tostring(mon.name or "") or ""
      if id:lower():find(ql, 1, true) or name:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end

  local rowH = 30 * s
  local thumb = 24 * s
  local listInnerX, listInnerY = x + 8 * s, listY + 8 * s
  local listInnerW, listInnerH = listW - 16 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(listInnerW)
  local perPage = math.max(1, math.floor(listInnerH / (rowH + 4 * s)))
  S.breedingListOffset = Kit.scroll(listInnerX, listInnerY, listInnerW, listInnerH,
    S.breedingListOffset or 0, #ids, perPage)
  local nav = RegList.bindNav(S, ids, {
    selKey = "breedingSpeciesId", offsetKey = "breedingListOffset",
    perPage = perPage,
  })
  Kit.pushClip(listInnerX, listInnerY, rowW, listInnerH)
  local ry = listInnerY
  for i = (S.breedingListOffset or 0) + 1,
      math.min(#ids, (S.breedingListOffset or 0) + perPage) do
    local id = ids[i]
    local rowMon = S.project.pokemon[id]
      or (S.data.pokemon and S.data.pokemon[id])
    local owned = S.project.pokemon[id] ~= nil
    if Kit.row(listInnerX, ry, rowW, rowH, S.breedingSpeciesId == id, PAL.green) then
      nav.activate()
      S.breedingSpeciesId = id
    end
    Preview.drawPokemonIcon(S, rowMon, listInnerX + 4 * s,
      ry + (rowH - thumb) / 2, thumb, thumb, id)
    local textX = listInnerX + 8 * s + thumb
    Kit.text("mono", Kit.ellipsize("mono", id, rowW - (textX - listInnerX) - 4 * s),
      textX, ry + 7 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 4 * s
  end
  Kit.popClip()
  Kit.scrollbar(listInnerX, listInnerY, listInnerW, listInnerH,
    S.breedingListOffset or 0, #ids, perPage)

  local mon, owned = resolveMon(S, S.breedingSpeciesId)
  if not mon then
    local first = ids[1]
    S.breedingSpeciesId = first
    mon, owned = resolveMon(S, first)
  end
  if not mon then
    Kit.emptyBox(formX, listY, formW, listH, "No species in data — import a Gold cache")
    return
  end

  local function mutate()
    mon = ensureOwned(S, S.breedingSpeciesId)
    owned = true
    return mon
  end

  Kit.caption(formX, y,
    "BREEDING  " .. (mon.id or "?") .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "breedingFormScroll", tostring(S.breedingSpeciesId), 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.caption(viewX, fy, "SPECIES")
  fy = fy + 22 * s
  Kit.text("micro",
    "Same fields as Pokemon → Basics; Save patches mod.content.pokemon.",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s

  row("Gender", function(fx, fy_, fw, fh_)
    local cur = mon.genderRatio
    if cur == nil then cur = 31 end
    if Generation.isGen3(S) then
      local labels={["0"]="Male only",["31"]="Female 12.5% / Male 87.5%",["63"]="Female 25% / Male 75%",
        ["127"]="Female 50% / Male 50%",["191"]="Female 75% / Male 25%",["254"]="Female only",["255"]="Genderless"}
      local ids={"0","31","63","127","191","254","255"}
      if not labels[tostring(cur)] then ids[#ids+1]=tostring(cur);labels[tostring(cur)]="Custom ratio ("..cur..")" end
      require("ChoicePicker").field(S,{x=fx,y=fy_,w=fw,h=fh_,current=tostring(cur),ids=ids,labels=labels,title="Gender distribution",
        onPick=function(id) mon=mutate();mon.genderRatio=tonumber(id);App.markDirty() end})
      return
    end
    local v = numField(S, App, "br_gender", fx, fy_, 80 * s, fh_, cur)
    v = math.max(0, math.min(255, v))
    if v ~= cur then mon = mutate(); mon.genderRatio = v end
  end)
  row(Generation.isGen3(S) and "Egg cycles" or "Egg steps", function(fx, fy_, fw, fh_)
    local key=Generation.isGen3(S) and "eggCycles" or "eggSteps"
    local cur = mon[key] or 20
    local v = numField(S, App, "br_eggs", fx, fy_, 80 * s, fh_, cur)
    v=math.max(0,math.min(255,math.floor(v)))
    if v ~= cur then mon = mutate(); mon[key] = v end
  end)
  row("Egg groups", function(fx, fy_, fw, fh_)
    if Generation.isGen3(S) then
      for i=1,2 do
        local cur=(mon.eggGroups or {})[i] or 0
        local names={"Monster","Water 1","Bug","Flying","Field","Fairy","Grass","Human-like","Water 3","Mineral","Amorphous","Water 2","Ditto","Dragon","Cannot breed"}
        local ids,labels={"0"},{["0"]="Not specified"};for n,label in ipairs(names) do ids[#ids+1]=tostring(n);labels[tostring(n)]=label end
        require("ChoicePicker").field(S,{x=fx+(i-1)*fw/2,y=fy_,w=fw/2-4*s,h=fh_,current=tostring(cur),ids=ids,labels=labels,
          onPick=function(id) mon=mutate();mon.eggGroups=mon.eggGroups or {};mon.eggGroups[i]=tonumber(id:match("^%d+"));App.markDirty() end})
      end
      return
    end
    mon.eggGroups = mon.eggGroups or { "EGG_GROUND", "EGG_GROUND" }
    local g1 = mon.eggGroups[1] or "EGG_GROUND"
    local g2 = mon.eggGroups[2] or g1
    if Kit.button(fx, fy_, 120 * s, fh_, g1, { kind = "accent" }) then
      mon = mutate()
      mon.eggGroups = mon.eggGroups or {}
      mon.eggGroups[1] = cycle(EGG_GROUPS, g1)
      App.markDirty()
    end
    if Kit.button(fx + 128 * s, fy_, 120 * s, fh_, g2, { kind = "accent" }) then
      mon = mutate()
      mon.eggGroups = mon.eggGroups or {}
      mon.eggGroups[2] = cycle(EGG_GROUPS, g2)
      App.markDirty()
    end
  end)
  if Generation.isGen3(S) then
    Kit.caption(viewX,fy,"Hatching takes about "..tostring((mon.eggCycles or 20)*256).." steps at this setting.")
    fy=fy+32*s
    Kit.caption(viewX,fy,"Parents normally need a shared egg group; Ditto is the special pairing group.");fy=fy+32*s
    fy=require("Gen3Breeding").eggFields(S,mon,viewX,fy,viewW,App)
    FormPane.finish(S,"breedingFormScroll",contentTop,fy,view)
    return
  end
  row("Egg moves", function(fx, fy_, fw, fh_)
    local joined = table.concat(mon.eggMoves or {}, ",")
    local v = field(S, App, "br_eggm", fx, fy_, fw, fh_, joined, "CHARM,FLAIL")
    if v ~= joined then mon = mutate(); mon.eggMoves = parseMoveList(v) end
  end)

  fy = fy + 8 * s
  Kit.caption(viewX, fy, "DAY-CARE")
  fy = fy + 22 * s
  Kit.text("micro",
    "Optional overrides (data.breeding). Leave untouched for cart defaults.",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s

  for _, rowDef in ipairs(DAYCARE_KEYS) do
    row(rowDef.label, function(fx, fy_, fw, fh_)
      local cur = breedField(S, rowDef.key, rowDef.default)
      local v = numField(S, App, "br_dc_" .. rowDef.key, fx, fy_, 80 * s, fh_, cur)
      v = math.max(0, math.floor(v))
      if v ~= cur then
        local b = ensureBreeding(S, App)
        b[rowDef.key] = v
      end
    end)
  end

  FormPane.finish(S, "breedingFormScroll", contentTop, fy, view)
end

return Breeding
