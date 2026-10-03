-- Export source (not bytecode) for Kanto Region (Gen3KantoRegion): the game
-- side of a FireRed / LeafGreen mod whose Import region maps
-- (FR_KANTO_<name>) stand in for the game's own.
--
-- The mod carries names only. Each FR_KANTO_ map uses its map's wild
-- Pokemon, and walking into one of its Pokemon Centers makes the FR_KANTO_
-- town outside the place a blackout returns to -- both read here from the
-- game's own data. Nothing in the engine is changed.
local M={}
M.REGION="FR_KANTO_"

-- "FR_KANTO_ROUTE1" -> "FR_ROUTE1", "FR_KANTO_SEVII_ONE_ISLAND" ->
-- "SEVII_ONE_ISLAND" (whichever the game has), or nil for other maps.
function M.original(id,has)
  if type(id)~="string" or id:sub(1,#M.REGION)~=M.REGION then return nil end
  local rest=id:sub(#M.REGION+1)
  if has==nil or has("FR_"..rest) then return "FR_"..rest end
  if has(rest) then return rest end
  return nil
end
-- the id Import region gives a map of the game's
function M.regionId(key) return M.REGION..key:gsub("^FR_","") end

function M.install(mod,cfg)
  local Runtime=require("src.mods.Runtime")

  -- Wild Pokemon: an FR_KANTO_ map with no list of its own uses its game
  -- map's. The mod's own lists win.
  if cfg.wild then
    local Encounters=require("src.core.game3.encounters")
    local function fillWild()
      local all=Encounters._tables
      if type(all)~="table" then return end
      local add={}
      for key,t in pairs(all) do
        if type(key)=="string" and (key:sub(1,3)=="FR_" or key:sub(1,6)=="SEVII_")
            and key:sub(1,#M.REGION)~=M.REGION and key:sub(1,9)~="FR_HOENN_" then
          local id=M.regionId(key)
          if all[id]==nil then add[id]=t end
        end
      end
      for id,t in pairs(add) do all[id]=t end
    end
    if not Encounters._editorKantoWild then
      Encounters._editorKantoWild=true
      local base=Encounters.loadFromMod
      Encounters.loadFromMod=function(...) return Runtime.call("editor.gen3.kanto.wild",base,...) end
    end
    mod.hooks:wrap("editor.gen3.kanto.wild",function(proceed,...)
      local a,b=proceed(...);fillWild();return a,b
    end)
    fillWild()
  end

  -- Blackout points: the game's Pokemon Centers set theirs in a map script,
  -- which Import region leaves out. Walking into an FR_KANTO_ center sets the
  -- one its own center would, on the FR_KANTO_ town outside.
  if cfg.respawn then
    local maps
    mod.events:on("game.ready",function(ctx)
      maps=ctx and ctx.game and ctx.game.data and ctx.game.data.maps or maps
    end)
    local spots={}
    local function spot(mapId)
      if not maps then return nil end
      local source=M.original(mapId,function(k) return maps[k]~=nil end)
      if not source then return nil end
      if spots[mapId]==nil then
        spots[mapId]=false
        local def=maps[source]
        local key=def and type(def.mapScripts)=="table" and def.mapScripts.onTransition
        local okS,Space=pcall(require,"src.core.game3.scripting.space")
        local bundle=okS and Space and Space.bundle
        local list=type(key)=="string" and bundle and bundle.scripts and bundle.scripts[key]
        for _,op in ipairs(type(list)=="table" and list or {}) do
          if op.op=="setrespawn" then
            local okH,Heal=pcall(require,"src.core.game3.heal_locations")
            local loc=okH and Heal.get(op[1])
            local town=loc and type(loc.map)=="string" and M.regionId(loc.map)
            if town and maps[town] then spots[mapId]={map=town,x=loc.x,y=loc.y} end
            break
          end
        end
      end
      return spots[mapId] or nil
    end
    mod.events:on("map.entered",function(e)
      local s=spot(type(e)=="table" and e.mapId)
      local okF,Field=pcall(require,"src.core.game3.field")
      local session=s and okF and Field._session
      if not session then return end
      session.healMap,session.healX,session.healY,session.healHealerLocalId=s.map,s.x,s.y,nil
    end)
  end
end

return M
