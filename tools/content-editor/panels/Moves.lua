-- Moves tab: browse/edit every move in the loaded data plus project-only
-- moves.  First edit clones a vanilla record into the mod (Save = patch).

local Kit = require("Kit")
local Theme = require("Theme")
local Search = require("Search")
local TypeIds = require("TypeIds")
local FormPane = require("FormPane")
local State = require("State")
local BattleAnims = require("BattleAnims")
local BattleAnimPreview = require("BattleAnimPreview")
local RegList = require("RegList")
local Generation = require("Generation")
local PAL = Theme.PAL

local Moves = {}

local CATEGORIES = { "physical", "special", "status" }

local function allMoveIds(S)
  local seen, ids = {}, {}
  for id, rec in pairs((S.project and S.project.moves) or {}) do
    if State.isMoveRecord(id, rec) then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.data and S.data.moves then
    for id, rec in pairs(S.data.moves) do
      if not seen[id] and State.isMoveRecord(id, rec) then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

-- Gen1: move_effects registry. Gold: EFFECT_* from moves + Battle records.
local function effectIds(S)
  local seen, ids = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if Generation.isGen2(S) then
    local function scanMoves(tbl)
      for _, mv in pairs(tbl or {}) do
        if type(mv) == "table" then add(mv.effect) end
      end
    end
    scanMoves(S.project and S.project.moves)
    scanMoves(S.data and S.data.moves)
    local merged = S.data and (S.data.gen2MoveEffects or S.data.move_effects)
    if type(merged) == "table" then
      for id in pairs(merged) do add(id) end
    end
    local ok, Battle = pcall(require, "src.battle.gen2.Battle")
    if ok and Battle and type(Battle.MOVE_EFFECT_RECORDS) == "table" then
      for id in pairs(Battle.MOVE_EFFECT_RECORDS) do add(id) end
    end
    if S.project and S.project.moveEffects then
      for id in pairs(S.project.moveEffects) do add(id) end
    end
    table.sort(ids)
    if #ids == 0 then ids[1] = "EFFECT_NORMAL_HIT" end
    return ids
  end
  if S.data and S.data.move_effects then
    for id in pairs(S.data.move_effects) do add(id) end
  end
  if S.project and S.project.moveEffects then
    for id in pairs(S.project.moveEffects) do add(id) end
  end
  table.sort(ids)
  if #ids == 0 then ids[1] = "NO_ADDITIONAL_EFFECT" end
  return ids
end

local function defaultEffectId(S)
  return Generation.isGen2(S) and "EFFECT_NORMAL_HIT" or "NO_ADDITIONAL_EFFECT"
end

local function deepCloneMove(def)
  local copy = {}
  for k, v in pairs(def) do
    if k == "anim" and type(v) == "table" then
      local a = {}
      for ak, av in pairs(v) do a[ak] = av end
      copy.anim = a
    elseif k == "multiHit" and type(v) == "table" then
      local a = {}
      for i = 1, #v do a[i] = v[i] end
      copy.multiHit = a
    else
      copy[k] = v
    end
  end
  copy._isNew = false
  return copy
end

local function resolveMove(S, id)
  if not id then return nil, false end
  if S.project.moves[id] then return S.project.moves[id], true end
  if S.data and S.data.moves and S.data.moves[id] then
    return S.data.moves[id], false
  end
  return nil, false
end

local function ensureOwned(S, id)
  local def, owned = resolveMove(S, id)
  if not def then return nil end
  if owned then return def end
  local copy = deepCloneMove(def)
  S.project.moves[id] = copy
  return copy
end

local function defaultMove(S, id)
  if Generation.isGen3(S) then return require("Gen3ContentAdapter").newRecord(S,"moves",id) end
  if Generation.isGen2(S) then
    return {
      id = id,
      name = id:gsub("_", " "),
      type = "NORMAL",
      power = 40,
      accuracy = 100,
      accuracyRaw = 255,
      pp = 20,
      effect = "EFFECT_NORMAL_HIT",
      effectId = 0,
      effectChance = 0,
      effectChanceRaw = 0,
      animation = 1,
      description = "",
      _isNew = true,
    }
  end
  return {
    id = id,
    name = id:gsub("_", " "),
    type = "NORMAL",
    power = 40,
    accuracy = 100,
    pp = 20,
    effect = "NO_ADDITIONAL_EFFECT",
    category = "physical",
    _isNew = true,
  }
end

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function numField(App, id, x, y, w, h, value)
  local v = field(App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

local function cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

function Moves.draw(S, x, y, w, h, App)
  if Generation.isGen3(S) then require("Gen3ContentAdapter").prepare(S) end
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end

  local listW = math.min(220 * s, w * 0.28)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s

  Kit.caption(x, y, "MOVES")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "moveQuery", x, qy, listW, qh, "search moves...")
  if qChanged then S.moveListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allMoveIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local mv = S.project.moves[id]
        or (S.data.moves and S.data.moves[id])
      local name = mv and tostring(mv.name or "") or ""
      local typ = mv and tostring(mv.type or "") or ""
      if id:lower():find(ql, 1, true)
          or name:lower():find(ql, 1, true)
          or typ:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local rowH = 30 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 4 * s)))
  local scrollX, scrollY = x + 8 * s, listY + 8 * s
  local scrollW, scrollH = listW - 16 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.moveListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.moveListOffset or 0, #ids, perPage)
  local moveNav = RegList.bindNav(S, ids, {
    selKey = "moveId", offsetKey = "moveListOffset", perPage = perPage,
  })
  local ry = scrollY
  for i = (S.moveListOffset or 0) + 1,
      math.min(#ids, (S.moveListOffset or 0) + perPage) do
    local id = ids[i]
    local owned = S.project.moves[id] ~= nil
    if Kit.row(scrollX, ry, rowW, rowH, S.moveId == id, PAL.yellow) then
      moveNav.activate()
      S.moveId = id
    end
    Kit.text("mono", Kit.ellipsize("mono", id, math.max(8, rowW - 16 * s)),
      x + 16 * s, ry + 7 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 4 * s
  end
  S.moveListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.moveListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New move",
      { kind = "good" }) then
    if Generation.isGen3(S) then require("Gen3Create").open(S,"moves",App) else
    local nid = "NEW_MOVE"
    local n = 1
    while S.project.moves[nid] or (S.data.moves and S.data.moves[nid]) do
      n = n + 1
      nid = "NEW_MOVE_" .. n
    end
    S.project.moves[nid] = defaultMove(S, nid)
    S.moveId = nid
    App.markDirty()
    end
  end

  local move, owned = resolveMove(S, S.moveId)
  if not move then
    local first = ids[1]
    S.moveId = first
    move, owned = resolveMove(S, first)
  end
  if not move then
    Kit.emptyBox(formX, listY, formW, listH, "No moves in data — import a ROM cache")
    return
  end

  local function mutate()
    move = ensureOwned(S, S.moveId)
    owned = true
    return move
  end

  Kit.caption(formX, y, "EDIT  " .. (move.id or "?") .. (owned and "" or "  (vanilla)"))
  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = owned and 44 * s or 12 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "moveFormScroll", tostring(S.moveId))
  local fy, view = FormPane.begin(S, "moveFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local labelW = 120 * s
  local fh = 30 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  row("ID", function(fx, fy_, fw, fh_)
    if Generation.isGen3(S) and not move._isNew then
      Kit.text("small",move.id,fx,fy_+6*s,PAL.muted);return
    end
    local v = field(App, "mv_id", fx, fy_, fw, fh_, move.id, "MOVE_ID")
    if v ~= move.id and v:match("^[%w_]+$")
       and not S.project.moves[v]
       and not (S.data.moves and S.data.moves[v]) then
      move = mutate()
      S.project.moves[move.id] = nil
      move.id = v
      S.project.moves[v] = move
      S.moveId = v
      App.markDirty()
    end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local v = field(App, "mv_name", fx, fy_, fw, fh_, move.name, "NAME")
    if v ~= (move.name or "") then
      move = mutate()
      move.name = v
    end
  end)
  row("Type", function(fx, fy_, fw, fh_)
    require("ChoicePicker").field(S,{x=fx,y=fy_,w=fw,h=fh_,current=move.type or "NORMAL",ids=TypeIds.list(S),title="Move type",onPick=function(id) move=mutate();move.type=id;App.markDirty() end})
  end)
  row("Power", function(fx, fy_, fw, fh_)
    local v = numField(App, "mv_pow", fx, fy_, 80 * s, fh_, move.power or 0)
    v = math.max(0, math.min(255, v))
    if v ~= (move.power or 0) then move = mutate(); move.power = v end
  end)
  row("Accuracy", function(fx, fy_, fw, fh_)
    -- Prefer explicit accuracy (including 0). Do not coalesce with `or 100`
    -- or a missing field looks like 100% and never writes on Save.
    local curAcc = tonumber(move.accuracy)
    if curAcc == nil then curAcc = 100 end
    local v = numField(App, "mv_acc", fx, fy_, 80 * s, fh_, curAcc)
    v = math.max(0, math.min(100, v))
    if v ~= curAcc then
      move = mutate()
      move.accuracy = v
      if Generation.isGen2(S) then
        move.accuracyRaw = math.floor(v * 255 / 100 + 0.5)
      end
    end
  end)
  row("PP", function(fx, fy_, fw, fh_)
    local v = numField(App, "mv_pp", fx, fy_, 80 * s, fh_, move.pp or 20)
    v = math.max(Generation.isGen3(S) and 0 or 1, math.min(64, v))
    if v ~= (move.pp or 20) then move = mutate(); move.pp = v end
  end)
  local gen2 = Generation.isGen2(S)
  if Generation.isGen3(S) then
    fy,move=require("Gen3ContentForms").moves(S,move,mutate,App,viewX,fy,viewW,fh,s)
  else
  local defEff = defaultEffectId(S)
  row("Effect", function(fx, fy_, fw, fh_)
    local cur = move.effect or defEff
    local bw = math.max(80 * s, fw - 88 * s)
    local label = Kit.ellipsize("small", cur, bw - 8 * s)
    if Kit.button(fx, fy_, bw, fh_, label, { kind = "accent" }) then
      move = mutate()
      move.effect = cycle(effectIds(S), move.effect or defEff)
      App.markDirty()
    end
    if Kit.button(fx + bw + 6 * s, fy_, 82 * s, fh_, "Edit FX",
        { kind = "ghost" }) then
      S.moveEffectId = move.effect or defEff
      S.tab = "effects"
    end
  end)
  row("Effect id", function(fx, fy_, fw, fh_)
    local cur = move.effect or defEff
    local ph = gen2 and "EFFECT_NORMAL_HIT" or "NO_ADDITIONAL_EFFECT"
    local v = field(App, "mv_eff", fx, fy_, fw, fh_, cur, ph)
    v = v:upper():gsub("%s+", "_")
    if v ~= cur and v:match("^[%w_]+$") then
      move = mutate()
      move.effect = v
    end
  end)
  if gen2 then
    row("FX chance", function(fx, fy_, fw, fh_)
      local cur = tonumber(move.effectChance)
      if cur == nil then cur = 0 end
      local v = numField(App, "mv_ech", fx, fy_, 80 * s, fh_, cur)
      v = math.max(0, math.min(100, v))
      if v ~= cur then
        move = mutate()
        move.effectChance = v
        move.effectChanceRaw = math.floor(v * 255 / 100 + 0.5)
      end
    end)
    row("Animation", function(fx, fy_, fw, fh_)
      local cur = tonumber(move.animation)
      if cur == nil then cur = tonumber(move.index) or 1 end
      local v = numField(App, "mv_anim", fx, fy_, 80 * s, fh_, cur)
      v = math.max(0, math.min(255, v))
      if v ~= cur then move = mutate(); move.animation = v end
    end)
    row("Description", function(fx, fy_, fw, fh_)
      local cur = move.description or ""
      local v = field(App, "mv_desc", fx, fy_, fw, fh_, cur, "A full-body charge<NEXT>attack.")
      if v ~= cur then
        move = mutate()
        move.description = v
      end
    end)
    row("Battle anim", function(fx, fy_, fw, fh_)
      local mid = move.id
      local ba = S.data and (S.data.gen2BattleAnims or S.data.battle_anims)
      local projMoves = S.project and S.project.battle_anims
        and S.project.battle_anims.moves
      local script = (projMoves and projMoves[mid])
        or (ba and ba.moves and ba.moves[mid])
      local label = (type(script) == "string" and script ~= "" and script)
        or "(no script)"
      local bw = 72 * s
      Kit.text("micro", Kit.ellipsize("micro",
          label .. " · anim# " .. tostring(move.animation or "?"),
          fw - bw - 10 * s),
        fx, fy_ + 8 * s, PAL.muted)
      if Kit.button(fx + fw - bw, fy_, bw, fh_, "Edit", {
          kind = "ghost",
          tooltip = "Open this move on the ANIMS tab",
        }) then
        S.tab = "anims"
        S.battleAnimMode = "moves"
        S.battleAnimId = mid
        S.battleAnimMoveId = mid
        S.battleAnimRow = 1
      end
    end)
    fy = fy + 4 * s
    fy = BattleAnimPreview.draw(S, move.id, viewX, fy, viewW, s)
  else
    row("Category", function(fx, fy_, fw, fh_)
      local cur = move.category or "(auto)"
      if Kit.button(fx, fy_, 140 * s, fh_, cur, { kind = "ghost" }) then
        move = mutate()
        if not move.category then
          move.category = CATEGORIES[1]
        else
          local idx = 0
          for i, c in ipairs(CATEGORIES) do
            if c == move.category then idx = i; break end
          end
          if idx >= #CATEGORIES then
            move.category = nil
          else
            move.category = CATEGORIES[idx + 1]
          end
        end
        App.markDirty()
      end
    end)
    row("Priority", function(fx, fy_, fw, fh_)
      local cur = move.priority or 0
      local v = numField(App, "mv_pri", fx, fy_, 80 * s, fh_, cur)
      v = math.max(-7, math.min(7, v))
      if v ~= cur then
        move = mutate()
        move.priority = (v == 0) and nil or v
      end
    end)
    row("High crit", function(fx, fy_, fw, fh_)
      local on = move.highCrit and true or false
      if Kit.chip(fx, fy_, 100 * s, fh_, on and "YES" or "NO", on, PAL.red) then
        move = mutate()
        move.highCrit = not on
        if not move.highCrit then move.highCrit = nil end
        App.markDirty()
      end
    end)
    row("Fixed dmg", function(fx, fy_, fw, fh_)
      local cur = move.fixedDamage
      local shown = (cur ~= nil) and tostring(cur) or ""
      local v = field(App, "mv_fd", fx, fy_, 80 * s, fh_, shown, "40")
      if v ~= shown then
        move = mutate()
        if v == "" then move.fixedDamage = nil
        else move.fixedDamage = tonumber(v) or move.fixedDamage end
      end
    end)
    row("Multi-hit", function(fx, fy_, fw, fh_)
      local mh = move.multiHit
      local cur
      if type(mh) == "table" then cur = table.concat(mh, ",")
      elseif mh ~= nil then cur = tostring(mh)
      else cur = "" end
      local v = field(App, "mv_mh", fx, fy_, fw, fh_, cur, "2 or 2,2,3,3,4,5")
      if v ~= cur then
        move = mutate()
        if v == "" then
          move.multiHit = nil
        else
          local nums = {}
          for part in v:gmatch("%d+") do nums[#nums + 1] = tonumber(part) end
          if #nums == 1 then move.multiHit = nums[1]
          elseif #nums > 1 then move.multiHit = nums
          end
        end
      end
    end)
    row("Charge text", function(fx, fy_, fw, fh_)
      local cur = move.chargeText or ""
      local v = field(App, "mv_ct", fx, fy_, fw, fh_, cur, "%s\nmade a whirlwind!")
      if v ~= cur then
        move = mutate()
        move.chargeText = (v ~= "" and v) or nil
      end
    end)
    row("Semi-invuln", function(fx, fy_, fw, fh_)
      local on = move.semiInvulnerable and true or false
      if Kit.chip(fx, fy_, 100 * s, fh_, on and "YES" or "NO", on, PAL.blue) then
        move = mutate()
        move.semiInvulnerable = not on
        if not move.semiInvulnerable then move.semiInvulnerable = nil end
        App.markDirty()
      end
    end)
    row("Counterable", function(fx, fy_, fw, fh_)
      local on = move.counterable and true or false
      if Kit.chip(fx, fy_, 100 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
        move = mutate()
        move.counterable = not on
        if not move.counterable then move.counterable = nil end
        App.markDirty()
      end
    end)
    row("Anim sound", function(fx, fy_, fw, fh_)
      local anim = move.anim
      local cur = (type(anim) == "table" and anim.sound) or ""
      local v = field(App, "mv_as", fx, fy_, fw, fh_, cur, "SFX_...")
      if v ~= cur then
        move = mutate()
        if v == "" then
          if move.anim and not move.anim.anim then move.anim = nil end
        else
          move.anim = move.anim or {}
          if type(move.anim) ~= "table" then move.anim = {} end
          move.anim.sound = v
        end
      end
    end)
    row("Battle anim", function(fx, fy_, fw, fh_)
      State.ensureProjectFields(S.project)
      local mid = move.id
      local animRec, animOwned = BattleAnims.resolve(S, mid)
      local n = (type(animRec) == "table" and type(animRec.seq) == "table")
        and #animRec.seq or 0
      local status = animRec
        and ((animOwned and "mod · " or "vanilla · ") .. n .. " rows")
        or "(none)"
      Kit.text("micro", Kit.ellipsize("micro", status, fw - 200 * s),
        fx, fy_ + 8 * s, PAL.muted)
      local bw = 92 * s
      if Kit.button(fx + fw - bw * 2 - 6 * s, fy_, bw, fh_, "Clone…", {
          kind = "accent",
          tooltip = "Copy another move's battle anim onto this move id",
        }) then
        BattleAnims.openPicker(S, {
          current = mid,
          excludeId = mid,
          title = "CLONE BATTLE ANIM ONTO " .. tostring(mid),
          onPick = function(srcId)
            BattleAnims.cloneMoveAnim(S, mid, srcId, App)
            S.status = ("Cloned battle anim %s → %s"):format(srcId, mid)
          end,
        })
      end
      if Kit.button(fx + fw - bw, fy_, bw, fh_, "Edit", {
          kind = "ghost",
          tooltip = "Open this move's anim on the ANIMS tab",
        }) then
        S.tab = "anims"
        S.battleAnimMode = "moves"
        S.battleAnimId = mid
        S.battleAnimMoveId = mid
        S.battleAnimRow = 1
      end
    end)

    fy = fy + 4 * s
    fy = BattleAnimPreview.draw(S, move.id, viewX, fy, viewW, s)
  end

  end
  Kit.text("micro",
    gen2
      and "Gold: EFFECT_*, effect chance, description, animation#. Gen1 flags hidden."
      or "Muted list rows are vanilla. First edit clones into the mod (Save = patch).",
    viewX, fy + 4 * s, PAL.faint)
  fy = fy + 28 * s
  FormPane.finish(S, "moveFormScroll", contentTop, fy, view)

  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    S.project.moves[move.id] = nil
    S.moveId = move.id
    App.markDirty()
  end
end

return Moves
