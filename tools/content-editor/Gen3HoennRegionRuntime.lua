-- Export source (not bytecode) for Hoenn Region (Gen3HoennRegion): the game
-- side of an Emerald mod whose Import region maps (EM_HOENN_<name>) stand in
-- for Emerald's own.
--
-- The mod carries names only. Each EM_HOENN_ map uses its Emerald map's wild
-- Pokemon, and walking into one of its Pokemon Centers makes the EM_HOENN_
-- town outside the place a blackout returns to -- both read here from the
-- game's own data. Nothing in the engine is changed.
local M={}
M.REGION="EM_HOENN_"

-- "EM_HOENN_ROUTE101" -> "EM_ROUTE101", or nil for other maps.
function M.original(id)
  if type(id)~="string" or id:sub(1,#M.REGION)~=M.REGION then return nil end
  return "EM_"..id:sub(#M.REGION+1)
end

function M.install(mod,cfg)
  local Runtime=require("src.mods.Runtime")

  -- Wild Pokemon: an EM_HOENN_ map with no list of its own uses its Emerald
  -- map's. The mod's own lists win.
  if cfg.wild then
    local Encounters=require("src.core.game3.encounters")
    local function fillWild()
      local all=Encounters._tables
      if type(all)~="table" then return end
      local add={}
      for key,t in pairs(all) do
        if type(key)=="string" and key:sub(1,3)=="EM_" and key:sub(1,#M.REGION)~=M.REGION then
          local id=M.REGION..key:sub(4)
          if all[id]==nil then add[id]=t end
        end
      end
      for id,t in pairs(add) do all[id]=t end
    end
    if not Encounters._editorHoennWild then
      Encounters._editorHoennWild=true
      local base=Encounters.loadFromMod
      Encounters.loadFromMod=function(...) return Runtime.call("editor.gen3.hoenn.wild",base,...) end
    end
    mod.hooks:wrap("editor.gen3.hoenn.wild",function(proceed,...)
      local a,b=proceed(...);fillWild();return a,b
    end)
    fillWild()
  end

  -- Blackout points: Emerald's Pokemon Centers set theirs in a map script,
  -- which Import region leaves out. Walking into an EM_HOENN_ center sets the
  -- one its Emerald center would, on the EM_HOENN_ town outside.
  if cfg.respawn then
    local maps
    mod.events:on("game.ready",function(ctx)
      maps=ctx and ctx.game and ctx.game.data and ctx.game.data.maps or maps
    end)
    local spots={}
    local function spot(mapId)
      local source=M.original(mapId)
      if not (source and maps) then return nil end
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
            local town=loc and type(loc.map)=="string" and M.REGION..loc.map:gsub("^EM_","")
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
