local M={}
function M.install(mod)
  local Runtime=require("src.mods.Runtime");local Collision=require("src.core.game3.collision");local Player=require("src.core.game3.player")
  local function bridge(name,fn)
    local key="editor.gen3.bridges."..name
    if not Collision[key] then Collision[key]=true;local old=Collision[name];Collision[name]=function(...) return Runtime.call(key,old,...) end end
    mod.hooks:wrap(key,fn)
  end
  local function cell(x,y,def)
    def=def or Collision._mapDef;local l=def and def.midLayout
    if not l or not x or not y or x<0 or y<0 or x>=l.width or y>=l.height then return end
    return (def._editorBridges or {})[y*l.width+x+1]
  end
  local function upper(x,y,def) return Player.elevation==4 and cell(x,y,def)~=nil end
  bridge("canEnter",function(proceed,game,x,y,opts)
    opts=opts or {};local fx,fy=opts.fromX or Player.cellX,opts.fromY or Player.cellY
    local from,to=cell(fx,fy),cell(x,y);local high=Player.elevation==4
    local dx,dy=x-fx,y-fy
    local function along(c) return c.axis=="horizontal" and dy==0 or c.axis=="vertical" and dx==0 end
    if high and from and from.kind=="deck" and not to then return false,"bridge_edge" end
    if to and to.kind=="entrance" then
      if not along(to) or (from and from.kind=="deck" and not high) then return false,"bridge_edge" end
    end
    if from and from.kind=="entrance" and not along(from) then return false,"bridge_edge" end
    if high and from and to and from.axis~=to.axis then return false,"bridge_edge" end
    return proceed(game,x,y,opts)
  end)
  bridge("cell",function(proceed,x,y) if upper(x,y) then return 0 end;return proceed(x,y) end)
  bridge("behaviorOn",function(proceed,def,x,y) if def==Collision._mapDef and upper(x,y,def) then return 0 end;return proceed(def,x,y) end)
  bridge("isWaterOn",function(proceed,def,x,y,coll) if def==Collision._mapDef and upper(x,y,def) then return false end;return proceed(def,x,y,coll) end)
  bridge("elevationAt",function(proceed,x,y)
    local c=cell(x,y)
    if c then
      if c.kind=="entrance" then return 4 end
      if Player.elevation==4 then return 4 end
    end
    return proceed(x,y)
  end)
  local function playerHook(name,fn)
    local key="editor.gen3.bridges.player."..name
    if not Player[key] then Player[key]=true;local old=Player[name];Player[name]=function(...) return Runtime.call(key,old,...) end end
    mod.hooks:wrap(key,fn)
  end
  local function session() return require("src.core.game3.runtime").getSession() end
  local function restore(s,x,y)
    local saved=s and s.meta and s.meta.editorBridgePosition
    if cell(x,y) and saved and saved.map==Collision._mapId and saved.x==x and saved.y==y then
      Player.elevation=saved.upper and 4 or 3
    end
  end
  playerHook("reset",function(proceed,x,y,...)
    if cell(x,y) then Player.elevation=3 end
    local result=proceed(x,y,...);local s=session()
    if not (s and s.meta and s.meta.editorBridgePosition) then
      local rt=require("src.core.game3.runtime");s=rt._game and rt._game.save
    end
    restore(s,x,y);return result
  end)
  playerHook("syncFromSession",function(proceed,s)
    local result=proceed(s);if s then restore(s,s.x,s.y) end;return result
  end)
  playerHook("syncSavePosition",function(proceed,game)
    local result=proceed(game);local s=session();local c=cell(Player.cellX,Player.cellY)
    local position=c and {map=Collision._mapId,x=Player.cellX,y=Player.cellY,upper=Player.elevation==4} or nil
    local function save(target)
      if target then target.meta=target.meta or {};target.meta.editorBridgePosition=position end
    end
    save(s);save(game and game.save);return result
  end)
end
return M
