-- Export source (not bytecode): the other game's tile behaviours on maps a mod
-- brings in from it, run by the game's own code in the player's game.
--
--   Hoenn in FireRed / LeafGreen (Gen3EmLink) and Hoenn Region in Emerald
--   (Gen3HoennRegion): muddy slopes, the Fortree and Pacifidlog bridges, cracked
--   floors and ash grass.
--   Kanto in Emerald (Gen3FrLink) and Kanto Region in FireRed / LeafGreen
--   (Gen3KantoRegion): spinner tiles and the Icefall Cave ice.
--
-- Nothing in the engine is changed. The engine has the code for both games but
-- switches each game's own on only in its own project, and starts the per-map
-- callbacks from map scripts the imported maps leave out. This (1) tells the
-- engine which callback each imported map runs, and (2) when the maps come from
-- the other game, lets that code read the other game's constants (and a bike
-- count as the Mach Bike) while it runs.
local M = {}

-- The step callbacks that belong to the maps themselves, by the id the game's
-- onResume script gives them (STEP_CB_* in field_tasks.h). The truck, secret
-- bases and the Sootopolis gym puzzle are story and stay out.
M.NAMES = {
  emerald = { [1] = "ash", [2] = "fortreeBridge", [3] = "pacifidlogBridge", [7] = "crackedFloor" },
  firered = { [4] = "ice" },
}

--- The step callback a script (or the scripts it calls) sets, or nil. `names`
-- is M.NAMES.emerald or M.NAMES.firered.
function M.scan(scripts, key, names, depth, seen)
  seen = seen or {}
  depth = depth or 0
  if type(key) ~= "string" or seen[key] or depth > 4 or type(scripts) ~= "table" then return nil end
  seen[key] = true
  local list = scripts[key]
  if type(list) ~= "table" then return nil end
  for _, op in ipairs(list) do
    if op.op == "setstepcallback" then return (names or M.NAMES.emerald)[tonumber(op[1])] end
    if (op.op == "call" or op.op == "goto") and op.target then
      local name = M.scan(scripts, op.target, names, depth + 1, seen)
      if name then return name end
    end
  end
  return nil
end

--- cfg: host "frlg" | "rse" (the game running); origin "emerald" | "firered"
-- (the game the maps come from); pair (their tileset prefix, "em__" /
-- "frlg__"); steps { mapId = callback } baked from the import (maps from the
-- other game), or region + derive = true to read each map's own onResume
-- script in the game (maps from the same game).
function M.install(mod, cfg)
  cfg = cfg or {}
  local frlg = cfg.host == "frlg"
  local origin = cfg.origin == "firered" and "firered" or "emerald"
  local cross = (frlg and origin == "emerald") or (not frlg and origin == "firered")
  local region = cfg.region
  local steps = cfg.steps or {}
  local okC, Ctx = pcall(require, "src.core.game3.scripting.ctx")
  local okF, FM = pcall(require, "src.core.game3.forced_movement")
  local okK, Collision = pcall(require, "src.core.game3.collision")
  local okM, MapMod = pcall(require, "src.core.game3.map")
  if not (okC and okF and okK and okM) then return end
  local Constants = require("src.core.game3.constants")

  -- Which callback a map runs: the mod's table (baked from the import) or its
  -- original map's own onResume script in the game.
  local maps
  mod.events:on("game.ready", function(ctx)
    maps = ctx and ctx.game and ctx.game.data and ctx.game.data.maps or maps
  end)
  local derived = {}
  local function lookup(mapId)
    if steps[mapId] then return steps[mapId] end
    if not (cfg.derive and region and type(mapId) == "string" and mapId:sub(1, #region) == region and maps) then return nil end
    if derived[mapId] == nil then
      derived[mapId] = false
      local rest = mapId:sub(#region + 1)
      local def = maps[(origin == "emerald" and "EM_" or "FR_") .. rest]
      local key = def and type(def.mapScripts) == "table" and def.mapScripts.onResume
      local okS, Space = pcall(require, "src.core.game3.scripting.space")
      local bundle = okS and Space and Space.bundle
      local name = M.scan(bundle and bundle.scripts, key, M.NAMES[origin])
      if name then derived[mapId] = name end
    end
    return derived[mapId] or nil
  end

  -- Every install (a mod can carry two) adds its lookup to one shared list.
  Ctx._regionLookups = Ctx._regionLookups or {}
  table.insert(Ctx._regionLookups, lookup)

  -- Maps from the other game: the engine's code for them asks the active
  -- game's constants for the other game's metatile / var / item names, and an
  -- Emerald one for a Mach Bike FireRed doesn't have. While it runs, answer as
  -- the other game would and let any bike count as the fastest one.
  local scope = 0
  local shim
  if cross then
    if not Constants._regionActive then
      Constants._regionActive = Constants.active
      Constants.active = function(...)
        if scope > 0 then return Constants.of(origin) end
        return Constants._regionActive(...)
      end
    end
    local okB, Bike = pcall(require, "src.core.game3.bike")
    if origin == "emerald" and okB and Bike and not Bike._regionRse then
      Bike._regionRse = Bike.rse
      Bike.rse = function(...)
        local real = Bike._regionRse(...)
        if real or scope == 0 then return real end
        if not shim then
          local Player = require("src.core.game3.player")
          shim = { SPEED = { FASTEST = 4 }, updateCounterSpeed = function() end,
            playerSpeed = function() return Player.biking and 4 or 0 end }
        end
        return shim
      end
    end
  end
  local function scoped(fn, ...)
    scope = scope + 1
    local ok, a, b = pcall(fn, ...)
    scope = scope - 1
    if not ok then return false end
    return a, b
  end

  -- The maps' callbacks are set from Ctx; hand the engine the one this map
  -- would have had.
  if not Ctx._regionStep then
    Ctx._regionStep = Ctx.stepCallback
    Ctx.stepCallback = function(mapId)
      local name, id = Ctx._regionStep(mapId)
      if name then return name, id end
      local want
      for _, find in ipairs(Ctx._regionLookups) do
        want = find(mapId)
        if want then break end
      end
      if not want then return nil end
      local cb = Ctx._stepCallback
      if not (cb and cb.mapId == mapId and cb.name == want) then
        Ctx._stepCallback = { id = -1, name = want, mapId = mapId }
      end
      return want, -1
    end
  end
  if not cross then return end

  -- The other game's forced movement next to the running game's own rows.
  -- Hoenn in FireRed: the muddy slope. Kanto in Emerald: the spinners.
  local extra, tilePred = {}, nil
  if origin == "emerald" then
    for _, row in ipairs(FM.TABLE_RSE or {}) do
      if row.name == "MuddySlope" then
        extra[1] = { name = "MuddySlope", check = function(beh) return Collision.isMuddySlope(beh) == true end,
          apply = function(game) return scoped(row.apply, game) end }
      end
    end
    tilePred = function(beh) return Collision.isMuddySlope(beh) == true end
  else
    for _, row in ipairs(FM.TABLE or {}) do
      if type(row.name) == "string" and row.name:sub(1, 4) == "Spin" then
        extra[#extra + 1] = { name = row.name, check = row.check, apply = function(game) return scoped(row.apply, game) end }
      end
    end
    tilePred = function(beh) return Collision.isSpinTile ~= nil and Collision.isSpinTile(beh) == true end
  end
  if #extra > 0 and not FM._regionTable then
    local base = frlg and FM.TABLE or FM.TABLE_RSE
    local merged
    FM._regionTable = FM.activeTable
    FM.activeTable = function(...)
      local t = FM._regionTable(...)
      if t ~= base then return t end
      if not merged then
        merged = {}
        for i, row in ipairs(base) do merged[i] = row end
        for _, row in ipairs(extra) do merged[#merged + 1] = row end
      end
      return merged
    end
    FM._regionTile = FM.isForcedMovementTile
    FM.isForcedMovementTile = function(beh)
      return FM._regionTile(beh) or (beh ~= nil and tilePred(beh))
    end
  end

  -- Per step: the map's own callback while on its map, and (Hoenn in
  -- FireRed) the slope's mud animation on any Emerald tileset.
  local Steps
  if frlg then
    local okS, mod2 = pcall(require, "src.core.game3.step_callbacks_rse")
    if okS then Steps = mod2 end
  end
  local function onOrigin()
    local def = Collision._mapDef
    local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
    return type(pair) == "string" and cfg.pair ~= nil and pair:sub(1, #cfg.pair) == cfg.pair
  end
  if not FM._regionRun then
    FM._regionRun = FM.runStepCallback
    FM.runStepCallback = function(game)
      if scope > 0 then return FM._regionRun(game) end
      if Steps and Steps.muddySlopeTask and onOrigin() then scoped(Steps.muddySlopeTask, game) end
      if lookup(MapMod.current) then return scoped(FM._regionRun, game) end
      return FM._regionRun(game)
    end
  end
end

return M
