-- EFFECTS tab: browse move_effects + author new ones from templates.
-- Templates compile to move_effects:register(...) on Save (see ModWriter).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local FormPane = require("FormPane")
local RegList = require("RegList")
local Generation = require("Generation")
local PAL = Theme.PAL

local function vanillaEffectTable(S)
  if Generation.isGen2(S) then
    local merged = S.data and (S.data.gen2MoveEffects or S.data.move_effects)
    if type(merged) == "table" and next(merged) then return merged end
    local ok, Battle = pcall(require, "src.battle.gen2.Battle")
    if ok and Battle and type(Battle.MOVE_EFFECT_RECORDS) == "table" then
      return Battle.MOVE_EFFECT_RECORDS
    end
    return {}
  end
  return S.data and S.data.move_effects or {}
end

local MoveEffects = {}

local TEMPLATES_GEN1 = {
  { id = "status_side", label = "Status side" },
  { id = "flinch_side", label = "Flinch side" },
  { id = "confuse_side", label = "Confuse side" },
  { id = "confuse_primary", label = "Confuse move" },
  { id = "status_primary", label = "Status move" },
  { id = "stat_up", label = "Stat up" },
  { id = "stat_down", label = "Stat down" },
  { id = "stat_down_side", label = "Stat down side" },
  { id = "recoil", label = "Recoil" },
  { id = "drain", label = "Drain HP" },
  { id = "ohko", label = "OHKO" },
  { id = "multi_hit", label = "Multi-hit" },
  { id = "fixed_damage", label = "Fixed dmg" },
  { id = "charge", label = "Charge / Fly" },
  { id = "empty", label = "No-op / full" },
}

-- Gold authoring: status field on the record; secondary chance is move.effectChance.
local TEMPLATES_GEN2 = {
  { id = "status_primary", label = "Status move" },
  { id = "status_secondary", label = "Status hit" },
  { id = "empty", label = "No-op / full" },
}

local STATUSES_GEN1 = { "BRN", "FRZ", "PAR", "PSN", "SLP" }
local STATUSES_GEN2 = {
  "burn", "freeze", "paralyze", "poison", "sleep", "toxic", "confuse",
}
local STATS = { "attack", "defense", "speed", "special", "accuracy", "evasion" }

local function templatesFor(S)
  return Generation.isGen2(S) and TEMPLATES_GEN2 or TEMPLATES_GEN1
end

local function statusesFor(S)
  return Generation.isGen2(S) and STATUSES_GEN2 or STATUSES_GEN1
end

local function normalizeGen2Status(s)
  local map = {
    BRN = "burn", FRZ = "freeze", PAR = "paralyze", PSN = "poison",
    SLP = "sleep", TOX = "toxic", CONFUSE = "confuse",
  }
  if type(s) ~= "string" or s == "" then return "burn" end
  return map[s] or map[s:upper()] or s:lower()
end

local function cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

local function allEffectIds(S)
  local seen, ids = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  for id in pairs((S.project and S.project.moveEffects) or {}) do add(id) end
  for id in pairs(vanillaEffectTable(S)) do add(id) end
  -- Gold: include every EFFECT_* referenced by moves, even without a record.
  if Generation.isGen2(S) and S.data and S.data.moves then
    for _, mv in pairs(S.data.moves) do
      if type(mv) == "table" then add(mv.effect) end
    end
    if S.project and S.project.moves then
      for _, mv in pairs(S.project.moves) do
        if type(mv) == "table" then add(mv.effect) end
      end
    end
  end
  table.sort(ids)
  return ids
end

local function resolveEffect(S, id)
  if not id then return nil, false end
  if S.project.moveEffects and S.project.moveEffects[id] then
    return S.project.moveEffects[id], true
  end
  local vanilla = vanillaEffectTable(S)
  if vanilla[id] then return vanilla[id], false end
  -- Gold unmodelled EFFECT_* (damage-path fallthrough).
  if Generation.isGen2(S) and type(id) == "string" and id:sub(1, 7) == "EFFECT_" then
    return { kind = "unmodelled", id = id }, false
  end
  return nil, false
end

local function movesUsing(S, effectId)
  local out = {}
  local function scan(tbl)
    for mid, mv in pairs(tbl or {}) do
      -- Gold moves.lua also carries meta keys (generation, source) — skip them.
      if type(mv) == "table" and mv.effect == effectId then
        out[#out + 1] = mid
      end
    end
  end
  scan(S.project and S.project.moves)
  if S.data and S.data.moves then
    local seen = {}
    for _, mid in ipairs(out) do seen[mid] = true end
    for mid, mv in pairs(S.data.moves) do
      if type(mv) == "table" and mv.effect == effectId and not seen[mid] then
        out[#out + 1] = mid
      end
    end
  end
  table.sort(out)
  return out
end

local function summarize(S, id, rec, owned)
  if owned then
    local t = rec.template or "?"
    if Generation.isGen2(S) then
      if t == "status_primary" or t == "status_secondary" or t == "status_side" then
        local kind = (t == "status_primary") and "primary" or "secondary"
        return string.format("%s  %s", kind, tostring(rec.status or "?"))
      end
      return t
    end
    if t == "status_side" or t == "status_primary" then
      return string.format("%s  %s  chance=%s", t, tostring(rec.status or "?"),
        tostring(rec.chance or (t == "status_primary" and "-") or 26))
    end
    if t == "flinch_side" or t == "confuse_side" then
      return string.format("%s  chance=%s", t, tostring(rec.chance or 26))
    end
    if t == "stat_up" or t == "stat_down" or t == "stat_down_side" then
      return string.format("%s  %s %+d", t, tostring(rec.stat or "attack"),
        tonumber(rec.delta) or 1)
    end
    return t
  end
  local kind = rec and rec.kind or "?"
  if kind == "unmodelled" then
    local n = #movesUsing(S, id)
    return string.format("damage path  ·  %d move%s", n, n == 1 and "" or "s")
  end
  local extra = ""
  if rec and rec.status then extra = "  " .. tostring(rec.status)
  elseif rec and rec.run then extra = "  run()" end
  local n = #movesUsing(S, id)
  return string.format("%s%s  ·  %d move%s", kind, extra, n, n == 1 and "" or "s")
end

local function defaultEffect(S, id, template)
  local gen2 = Generation.isGen2(S)
  template = template or (gen2 and "status_secondary" or "status_side")
  local rec = {
    id = id,
    template = template,
    _isNew = true,
  }
  if gen2 then
    if template == "status_primary" then
      rec.kind = "primary"
      rec.status = "sleep"
    elseif template == "status_secondary" or template == "status_side" then
      rec.kind = "secondary"
      rec.status = "burn"
      rec.template = "status_secondary"
    else
      rec.kind = "full"
      rec.template = "empty"
    end
    return rec
  end
  if template == "status_side" then
    rec.kind = "secondary"
    rec.status = "BRN"
    rec.chance = 26
  elseif template == "flinch_side" then
    rec.kind = "secondary"
    rec.chance = 26
  elseif template == "confuse_side" then
    rec.kind = "secondary"
    rec.chance = 25
  elseif template == "status_primary" then
    rec.kind = "primary"
    rec.status = "SLP"
    rec.accuracyChecked = true
  elseif template == "stat_up" then
    rec.kind = "primary"
    rec.stat = "attack"
    rec.delta = 1
  elseif template == "stat_down" then
    rec.kind = "primary"
    rec.stat = "defense"
    rec.delta = 1
    rec.accuracyChecked = true
  elseif template == "stat_down_side" then
    rec.kind = "secondary"
    rec.stat = "attack"
    rec.delta = 1
    rec.chance = 85
  elseif template == "recoil" then
    rec.kind = "full"
    rec.recoilDiv = 4
  elseif template == "drain" then
    rec.kind = "full"
  elseif template == "ohko" then
    rec.kind = "full"
  elseif template == "multi_hit" then
    rec.kind = "full"
    rec.multiHit = { 2, 2, 2, 3, 3, 3, 4, 5 }
  elseif template == "fixed_damage" then
    rec.kind = "full"
    rec.fixedDamage = 40
  elseif template == "charge" then
    rec.kind = "full"
    rec.semiInvulnerable = false
    rec.chargeAnim = "TELEPORT"
  elseif template == "confuse_primary" then
    rec.kind = "primary"
    rec.accuracyChecked = true
  elseif template == "empty" then
    rec.kind = "full"
  end
  return rec
end

local function draftFromVanillaGen2(S, id, vanilla)
  local tmpl = "empty"
  local status = vanilla and vanilla.status
  if status then
    tmpl = (vanilla.kind == "secondary") and "status_secondary" or "status_primary"
  end
  local draft = defaultEffect(S, id, tmpl)
  draft._isNew = false
  draft._fromVanilla = true
  if status then draft.status = normalizeGen2Status(status) end
  draft.kind = (tmpl == "status_primary") and "primary"
    or (tmpl == "status_secondary") and "secondary"
    or "full"
  return draft
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

function MoveEffects.draw(S, x, y, w, h, App)
  if Generation.isGen3(S) then return require("Gen3Effects").draw(S,x,y,w,h,App) end
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  S.project.moveEffects = S.project.moveEffects or {}

  local listW = math.min(240 * s, w * 0.30)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s

  Kit.caption(x, y, "MOVE EFFECTS")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "moveEffectQuery", x, qy, listW, qh,
    "search effects...")
  if qChanged then S.moveEffectListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allEffectIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local rec = select(1, resolveEffect(S, id))
      local sum = summarize(S, id, rec or {}, S.project.moveEffects[id] ~= nil)
      if id:lower():find(ql, 1, true) or sum:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end

  local rowH = 34 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 4 * s)))
  local scrollX, scrollY = x + 8 * s, listY + 8 * s
  local scrollW, scrollH = listW - 16 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.moveEffectListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.moveEffectListOffset or 0, #ids, perPage)
  local fxNav = RegList.bindNav(S, ids, {
    selKey = "moveEffectId", offsetKey = "moveEffectListOffset", perPage = perPage,
  })
  local ry = scrollY
  for i = (S.moveEffectListOffset or 0) + 1,
      math.min(#ids, (S.moveEffectListOffset or 0) + perPage) do
    local id = ids[i]
    local owned = S.project.moveEffects[id] ~= nil
    local rec = select(1, resolveEffect(S, id))
    if Kit.row(scrollX, ry, rowW, rowH, S.moveEffectId == id, PAL.yellow) then
      fxNav.activate()
      S.moveEffectId = id
    end
    Kit.text("mono", Kit.ellipsize("mono", id, math.max(8, rowW - 16 * s)),
      x + 16 * s, ry + 2 * s, owned and PAL.text or PAL.muted)
    Kit.text("micro",
      Kit.ellipsize("micro", summarize(S, id, rec or {}, owned),
        math.max(8, rowW - 16 * s)),
      x + 16 * s, ry + 16 * s, PAL.faint)
    ry = ry + rowH + 4 * s
  end
  S.moveEffectListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.moveEffectListOffset or 0, #ids, perPage)

  local gen2 = Generation.isGen2(S)
  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New effect",
      { kind = "good" }) then
    local nid = gen2 and "EFFECT_MOD_STATUS" or "MOD_SIDE_EFFECT"
    local n = 1
    local vanilla = vanillaEffectTable(S)
    while S.project.moveEffects[nid] or vanilla[nid] do
      n = n + 1
      nid = (gen2 and "EFFECT_MOD_STATUS_" or "MOD_SIDE_EFFECT_") .. n
    end
    S.project.moveEffects[nid] = defaultEffect(S, nid,
      gen2 and "status_secondary" or "status_side")
    S.moveEffectId = nid
    App.markDirty()
  end

  local eff, owned = resolveEffect(S, S.moveEffectId)
  if not eff then
    local first = ids[1]
    S.moveEffectId = first
    eff, owned = resolveEffect(S, first)
  end
  if not eff then
    Kit.emptyBox(formX, listY, formW, listH, "No move effects in data")
    return
  end

  local function mutate()
    if owned then return S.project.moveEffects[S.moveEffectId] end
    local id = S.moveEffectId
    local draft
    if gen2 then
      draft = draftFromVanillaGen2(S, id, eff)
    else
      draft = defaultEffect(S, id, "status_side")
      draft._isNew = false
      draft._fromVanilla = true
    end
    S.project.moveEffects[id] = draft
    owned = true
    App.markDirty()
    return draft
  end

  Kit.caption(formX, y,
    (S.moveEffectId or "?") .. (owned and "" or "  (vanilla)"))
  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = 44 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "moveEffectFormScroll", tostring(S.moveEffectId))
  local fy, view = FormPane.begin(S, "moveEffectFormScroll",
    viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  if not owned then
    local kind = tostring(eff.kind or "?")
    if kind == "unmodelled" then
      Kit.text("micro",
        "No move_effects record — Gold runs the normal damage path for this id.",
        viewX, fy, PAL.muted)
      fy = fy + 20 * s
      Kit.text("micro",
        "Create a status primary/secondary record to give it a handler.",
        viewX, fy, PAL.faint)
      fy = fy + 18 * s
    else
      Kit.text("micro",
        gen2
          and "Vanilla Gold effect (read-only). Override in the mod to edit."
          or "Vanilla engine effect (read-only). Create a mod effect, or clone to edit.",
        viewX, fy, PAL.muted)
      fy = fy + 20 * s
      Kit.text("micro",
        "kind: " .. kind
          .. (eff.status and ("  status: " .. tostring(eff.status)) or "")
          .. (eff.run and "  run()" or ""),
        viewX, fy, PAL.detail)
      fy = fy + 18 * s
    end
    local users = movesUsing(S, S.moveEffectId)
    Kit.text("micro",
      (#users > 0)
        and ("Used by: " .. table.concat(users, ", "))
        or "Not referenced by any loaded move",
      viewX, fy, PAL.faint)
    fy = fy + 22 * s

    if gen2 then
      local canOverride = (eff.status ~= nil) or (kind == "unmodelled")
        or (eff.run ~= nil)
      if canOverride and Kit.button(viewX, fy, 180 * s, fh,
          kind == "unmodelled" and "Add status record" or "Override in mod",
          { kind = "accent" }) then
        local draft = draftFromVanillaGen2(S, S.moveEffectId, eff)
        if kind == "unmodelled" or (eff.run and not eff.status) then
          draft = defaultEffect(S, S.moveEffectId, "status_secondary")
          draft._isNew = false
          draft._fromVanilla = true
        end
        S.project.moveEffects[S.moveEffectId] = draft
        App.markDirty()
        S.status = "Override " .. tostring(S.moveEffectId)
      end
      fy = fy + fh + 8 * s
      if Kit.button(viewX, fy, 160 * s, fh, "Clone as new id", { kind = "ghost" }) then
        local base = S.moveEffectId or "EFFECT"
        local nid = base:sub(1, 7) == "EFFECT_" and (base .. "_MOD") or ("EFFECT_" .. base)
        local n = 1
        local vanilla = vanillaEffectTable(S)
        while S.project.moveEffects[nid] or vanilla[nid] do
          n = n + 1
          nid = (base:sub(1, 7) == "EFFECT_" and (base .. "_MOD_") or ("EFFECT_" .. base .. "_")) .. n
        end
        local draft = draftFromVanillaGen2(S, nid, eff)
        draft._isNew = true
        draft._fromVanilla = nil
        draft.id = nid
        S.project.moveEffects[nid] = draft
        S.moveEffectId = nid
        App.markDirty()
        S.status = "Cloned as " .. nid
      end
      fy = fy + fh + 12 * s
    else
      if Kit.button(viewX, fy, 160 * s, fh, "Clone to mod", { kind = "accent" }) then
        local base = S.moveEffectId or "EFFECT"
        local nid = "MOD_" .. base
        local n = 1
        while S.project.moveEffects[nid]
            or (S.data.move_effects and S.data.move_effects[nid]) do
          n = n + 1
          nid = "MOD_" .. base .. "_" .. n
        end
        local tmpl = "empty"
        if base:find("FLINCH") then tmpl = "flinch_side"
        elseif base:find("CONFUSION_SIDE") then tmpl = "confuse_side"
        elseif base:find("SIDE_EFFECT") and (base:find("BURN") or base:find("POISON")
            or base:find("PARA") or base:find("FREEZE")) then
          tmpl = "status_side"
        elseif base:find("_UP") then tmpl = "stat_up"
        elseif base:find("DOWN_SIDE") then tmpl = "stat_down_side"
        elseif base:find("_DOWN") then tmpl = "stat_down"
        elseif base:find("SLEEP") or base:find("POISON_EFFECT")
            or base:find("PARALYZE_EFFECT") then
          tmpl = "status_primary"
        end
        local draft = defaultEffect(S, nid, tmpl)
        if base:find("BURN") then draft.status = "BRN" end
        if base:find("FREEZE") or base:find("FRZ") then draft.status = "FRZ" end
        if base:find("PARA") then draft.status = "PAR" end
        if base:find("POISON") or base:find("PSN") then draft.status = "PSN" end
        if base:find("SLEEP") or base:find("SLP") then draft.status = "SLP" end
        if base:find("EFFECT1") or base:find("SIDE_EFFECT1") then draft.chance = 26 end
        if base:find("EFFECT2") or base:find("SIDE_EFFECT2") then draft.chance = 77 end
        if base:find("POISON_SIDE_EFFECT1") then draft.chance = 52 end
        if base:find("POISON_SIDE_EFFECT2") then draft.chance = 103 end
        S.project.moveEffects[nid] = draft
        S.moveEffectId = nid
        App.markDirty()
        S.status = "Cloned as " .. nid
      end
      fy = fy + fh + 12 * s
    end
  else
    row("ID", function(fx, fy_, fw, fh_)
      local ph = gen2 and "EFFECT_MOD_STATUS" or "EFFECT_ID"
      local v = field(App, "me_id", fx, fy_, fw, fh_, eff.id or S.moveEffectId, ph)
      if v ~= (eff.id or S.moveEffectId) and v:match("^[%w_]+$")
          and not S.project.moveEffects[v]
          and not vanillaEffectTable(S)[v] then
        S.project.moveEffects[S.moveEffectId] = nil
        eff.id = v
        S.project.moveEffects[v] = eff
        S.moveEffectId = v
        App.markDirty()
      end
    end)

    Kit.text("small", "Template", viewX, fy + 6 * s, PAL.caption)
    fy = fy + 20 * s
    local tx, ty = viewX, fy
    local maxX = viewX + viewW - 8 * s
    for _, t in ipairs(templatesFor(S)) do
      local on = (eff.template or "") == t.id
      local bw = Kit.textWidth("micro", t.label) + 16 * s
      if tx + bw > maxX then
        tx = viewX
        ty = ty + fh + 4 * s
      end
      if Kit.chip(tx, ty, bw, fh, t.label, on, PAL.yellow) then
        local id = eff.id or S.moveEffectId
        local nextRec = defaultEffect(S, id, t.id)
        nextRec._isNew = eff._isNew
        nextRec._fromVanilla = eff._fromVanilla
        S.project.moveEffects[S.moveEffectId] = nextRec
        eff = nextRec
        App.markDirty()
      end
      tx = tx + bw + 4 * s
    end
    fy = ty + fh + 12 * s

    local tmpl = eff.template or (gen2 and "status_secondary" or "status_side")
    local statusList = statusesFor(S)
    if tmpl == "status_side" or tmpl == "status_primary"
        or tmpl == "status_secondary" then
      row("Status", function(fx, fy_, fw, fh_)
        local cur = tostring(eff.status or (gen2 and "burn" or "BRN"))
        if gen2 then cur = normalizeGen2Status(cur) end
        if Kit.button(fx, fy_, 120 * s, fh_, cur, { kind = "ghost" }) then
          eff = mutate()
          eff.status = cycle(statusList, cur)
          App.markDirty()
        end
      end)
    end
    if gen2 and (tmpl == "status_secondary" or tmpl == "status_side") then
      Kit.text("micro",
        "Secondary chance comes from the move's FX chance (effectChance %), not here.",
        viewX, fy, PAL.faint)
      fy = fy + 18 * s
    end
    if not gen2 then
      if tmpl == "status_side" or tmpl == "flinch_side"
          or tmpl == "confuse_side" or tmpl == "stat_down_side" then
        row("Chance /256", function(fx, fy_, fw, fh_)
          local cur = tonumber(eff.chance) or 26
          local v = numField(App, "me_ch", fx, fy_, 80 * s, fh_, cur)
          v = math.max(0, math.min(255, v))
          if v ~= cur then
            eff = mutate()
            eff.chance = v
          end
        end)
      end
      if tmpl == "stat_up" or tmpl == "stat_down" or tmpl == "stat_down_side" then
        row("Stat", function(fx, fy_, fw, fh_)
          if Kit.button(fx, fy_, 120 * s, fh_, tostring(eff.stat or "attack"),
              { kind = "ghost" }) then
            eff = mutate()
            eff.stat = cycle(STATS, eff.stat or "attack")
            App.markDirty()
          end
        end)
        row("Stages", function(fx, fy_, fw, fh_)
          local cur = tonumber(eff.delta) or 1
          local v = numField(App, "me_d", fx, fy_, 60 * s, fh_, cur)
          v = math.max(1, math.min(2, v))
          if v ~= cur then
            eff = mutate()
            eff.delta = v
          end
        end)
      end
      if tmpl == "status_primary" or tmpl == "stat_down" or tmpl == "confuse_primary" then
        row("Acc. check", function(fx, fy_, fw, fh_)
          local on = eff.accuracyChecked ~= false
          if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.green) then
            eff = mutate()
            eff.accuracyChecked = not on
            App.markDirty()
          end
        end)
      end
      if tmpl == "recoil" then
        row("Recoil /N", function(fx, fy_, fw, fh_)
          local cur = tonumber(eff.recoilDiv) or 4
          local v = numField(App, "me_rd", fx, fy_, 60 * s, fh_, cur)
          v = math.max(2, math.min(8, v))
          if v ~= cur then eff = mutate(); eff.recoilDiv = v end
        end)
      end
      if tmpl == "fixed_damage" then
        row("Damage", function(fx, fy_, fw, fh_)
          local cur = tonumber(eff.fixedDamage) or 40
          local v = numField(App, "me_fd", fx, fy_, 80 * s, fh_, cur)
          v = math.max(1, math.min(65535, v))
          if v ~= cur then eff = mutate(); eff.fixedDamage = v end
        end)
      end
      if tmpl == "multi_hit" then
        row("Hits CSV", function(fx, fy_, fw, fh_)
          local dist = eff.multiHit
          local cur
          if type(dist) == "table" then
            cur = table.concat(dist, ",")
          else
            cur = tostring(dist or "2,2,2,3,3,3,4,5")
          end
          local v = field(App, "me_mh", fx, fy_, fw, fh_, cur, "2,2,2,3,3,3,4,5")
          if v ~= cur then
            local nums = {}
            for part in v:gmatch("%d+") do nums[#nums + 1] = tonumber(part) end
            eff = mutate()
            if #nums == 1 then eff.multiHit = nums[1]
            elseif #nums > 1 then eff.multiHit = nums
            end
          end
        end)
      end
      if tmpl == "charge" then
        row("Semi-invuln", function(fx, fy_, fw, fh_)
          local on = eff.semiInvulnerable and true or false
          if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.blue) then
            eff = mutate()
            eff.semiInvulnerable = not on
            App.markDirty()
          end
        end)
        row("Charge anim", function(fx, fy_, fw, fh_)
          local cur = tostring(eff.chargeAnim or "TELEPORT")
          local v = field(App, "me_ca", fx, fy_, fw, fh_, cur, "TELEPORT")
          if v ~= cur then eff = mutate(); eff.chargeAnim = v end
        end)
      end
    end

    Kit.text("micro",
      gen2
        and "Save emits move_effects:register/override({ kind, status })."
        or "Save emits mod.content.move_effects:register with a generated run().",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
  end

  -- Assign to currently selected move
  if S.moveId and Kit.button(viewX, fy, 200 * s, fh,
      "Assign to " .. tostring(S.moveId), { kind = "primary" }) then
    State.ensureProjectFields(S.project)
    local mv = S.project.moves[S.moveId]
    if not mv and S.data and S.data.moves and S.data.moves[S.moveId] then
      -- shallow clone into project
      local src = S.data.moves[S.moveId]
      mv = {}
      for k, v in pairs(src) do
        if k == "anim" and type(v) == "table" then
          local a = {}
          for ak, av in pairs(v) do a[ak] = av end
          mv.anim = a
        elseif k == "multiHit" and type(v) == "table" then
          local a = {}
          for i = 1, #v do a[i] = v[i] end
          mv.multiHit = a
        else
          mv[k] = v
        end
      end
      mv._isNew = false
      S.project.moves[S.moveId] = mv
    end
    if mv then
      mv.effect = S.moveEffectId
      App.markDirty()
      S.status = "Set " .. S.moveId .. ".effect = " .. S.moveEffectId
      S.tab = "moves"
    else
      S.status = "Select a move on the Moves tab first"
    end
  end
  fy = fy + fh + 10 * s

  FormPane.finish(S, "moveEffectFormScroll", contentTop, fy, view)

  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Delete", { kind = "danger" }) then
    S.project.moveEffects[S.moveEffectId] = nil
    S.moveEffectId = next(S.project.moveEffects) or ids[1]
    App.markDirty()
  end
end

return MoveEffects
