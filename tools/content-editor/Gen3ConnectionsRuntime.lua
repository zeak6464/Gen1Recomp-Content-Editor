local M={}
function M.install(mod,C,authored)
  local Runtime=require("src.mods.Runtime")
  local Map=require("src.core.game3.map")
  local Collision=require("src.core.game3.collision")
  local function bridge(object,name,fn)
    local key="editor.gen3.connections."..name
    if not object[key] then object[key]=true;local original=object[name];object[name]=function(...) return Runtime.call(key,original,...) end end
    mod.hooks:wrap(key,fn)
  end
  mod.events:on("game.ready",function(ev) C.recover(ev.game.data.maps,authored) end)
  local function size(def) local l=def.midLayout or def;return l.width or 0,l.height or 0 end
  local function delta(dir,offset,from,to)
    local w,h=size(from);local dw,dh=size(to)
    if dir=="north" then return offset,-dh elseif dir=="south" then return offset,h
    elseif dir=="west" then return -dw,offset else return w,offset end
  end
  bridge(Map,"loadNeighborsDepth1",function(_,game,def)
    local result={};local maps=game and game.data and game.data.maps or {}
    for dir,c,i in C.each(def and def.connections) do
      local id=c.map or c.mapId;local dest=maps[id]
      if dest then
        Map.ensureMidLayout(game,id,dest)
        result[i==1 and dir or dir..":"..i]={dir=dir,map=id,mapId=id,def=dest,offset=c.offset or 0}
        Map._loadedLayouts[id]=true
      end
    end
    Map.neighbors=result;return result
  end)
  bridge(Map,"overscanSlices",function()
    local rows={};for key,n in pairs(Map.neighbors or {}) do rows[#rows+1]={dir=n.dir or key,mapId=n.map,offset=n.offset} end;return rows
  end)
  bridge(Map,"computeWorld",function(_,maps,rootId,hops,reachW,reachH,ensure)
    local root=maps and maps[rootId];if not root then return {} end
    ensure=ensure or function() end;ensure(rootId,root)
    local rw,rh=size(root);local out,seen,queue={},{[rootId]=true},{{def=root,ox=0,oy=0,hops=0}};local index=1
    while queue[index] do
      local current=queue[index];index=index+1
      for dir,c in C.each(current.def.connections) do
        local id=c.map or c.mapId;local dest=maps[id]
        if dest and not seen[id] then
          ensure(id,dest);local dx,dy=delta(dir,c.offset or 0,current.def,dest)
          local ox,oy=current.ox+dx,current.oy+dy;local w,h=size(dest)
          local inReach=reachW and reachH and ox+w>-reachW and ox<rw+reachW and oy+h>-reachH and oy<rh+reachH
          if current.hops+1<=(hops or 0) or inReach then
            seen[id]=true;out[#out+1]={id=id,def=dest,ox=ox,oy=oy}
            if current.hops+1<(hops or 0) or inReach then queue[#queue+1]={def=dest,ox=ox,oy=oy,hops=current.hops+1} end
          end
        end
      end
    end
    return out
  end)
  bridge(Map,"worldMidAt",function(proceed,x,y,def)
    if not def or not def.midLayout then return proceed(x,y,def) end
    local w,h=size(def)
    if x>=0 and y>=0 and x<w and y<h then return proceed(x,y,def) end
    -- Walk connections in authored order; gaps remain the primary border.
    for dir,c in C.each(def.connections) do
      for _,n in pairs(Map.neighbors or {}) do
        if (n.dir==dir or not n.dir) and n.map==(c.map or c.mapId) and n.offset==(c.offset or 0) and n.def.midLayout then
          local ox,oy=delta(dir,c.offset or 0,def,n.def);local l=n.def.midLayout;local nx,ny=x-ox,y-oy
          if nx>=0 and ny>=0 and nx<l.width and ny<l.height then return l:midAt(nx,ny),l.pair or n.def.pair end
        end
      end
    end
    return proceed(x,y,def)
  end)
  bridge(Collision,"connectionLanding",function(_,def,c,dir,x,y) return C.landing(def,c,dir,x,y) end)
  bridge(require("src.core.game3.itemfinder"),"scan",function(proceed,opts)
    if not opts.neighbors or not opts.eventsFor or not opts.width or not opts.height then return proceed(opts) end
    local scan={};for k,v in pairs(opts) do scan[k]=v end;scan.events={};scan.neighbors=nil
    for _,ev in ipairs(opts.events or {}) do scan.events[#scan.events+1]=ev end
    local current={width=opts.width,height=opts.height}
    for key,n in pairs(opts.neighbors) do
      local dir=n.dir or C.alias[key] or key
      if C.opposite[dir] and n.def then
        local ox,oy=delta(dir,n.offset or 0,current,n.def)
        for _,ev in ipairs(opts.eventsFor(n.map or n.mapId) or {}) do
          if not ev.underfoot and (ev.type=="hidden_item" or ev.kind==7) and ev.x and ev.y then
            local x,y=ev.x+ox,ev.y+oy
            if x<0 or y<0 or x>=opts.width or y>=opts.height then
              local copy=C.copy(ev);copy.x=x;copy.y=y;scan.events[#scan.events+1]=copy
            end
          end
        end
      end
    end
    return proceed(scan)
  end)
  bridge(Collision,"tryConnection",function(proceed,game,x,y,dir,run)
    local def=Collision._mapDef;local cardinal=C.alias[dir] or dir
    if not def then return false end
    local selected
    for _,c in ipairs(C.list(def.connections,cardinal)) do
      local id=c.map or c.mapId;local dest=game and game.data and game.data.maps[id]
      if dest then Map.ensureMidLayout(game,id,dest);if C.landing(dest,c,dir,x,y) then selected=c;break end end
    end
    if not selected then return false end
    -- Delegate collision, surfing, events and the actual transition to native code.
    local proxy={};for k,v in pairs(def) do proxy[k]=v end
    proxy.connections={[dir]=selected,[cardinal]=selected};Collision._mapDef=proxy
    local ok,result=pcall(proceed,game,x,y,dir,run)
    if Collision._mapDef==proxy then Collision._mapDef=def end
    if not ok then error(result,0) end;return result
  end)
end
return M
