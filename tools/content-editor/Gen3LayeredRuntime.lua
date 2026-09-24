-- Export source (not bytecode): assembles shared-editor layers against the
-- player's native FireRed atlases. No extracted pixels are bundled in a mod.
local C=require("Gen3Collision")
local encode=require("ModWriter").encodeLua
return "  local collisionModes="..encode(C.modes).."\n  local paintedCollision="..encode(C.painted).."\n"..[=[
  mod.events:on("game.ready",function(ctx)
    local T=require("src.core.game3.tileset_native")
    local Layout=require("src.core.game3.layout_native")
    local Interactions=require("src.core.game3.scripting.interaction_scripts")
    local View=require("src.core.game3.field_view")
    local Runtime=require("src.mods.Runtime")
    local Collision=require("src.core.game3.collision")
    local okDoors,Doors=pcall(require,"src.core.game3.doors")
    if okDoors and Doors.getDoorEntryAt and Doors._layoutCache then
      if not Doors._editorLayerDispatch then
        Doors._editorLayerDispatch=true
        local lookup=Doors.getDoorEntryAt
        Doors.getDoorEntryAt=function(...) return Runtime.call("editor.gen3.doors.lookup",lookup,...) end
      end
      local function lookupEditedDoor(proceed,mapId,x,y)
        local id=tostring(mapId or ""):gsub("^FR_",""):gsub("^MAP_","")
        local source=layered.maps[mapId] or layered.maps["FR_"..id] or layered.maps[id]
        if not source then return proceed(mapId,x,y) end
        if not x or not y or x<0 or y<0 or x>=source.cellWidth or y>=source.cellHeight then return end
        -- Compiled atlas IDs are unrelated to the ROM door manifest. Resolve
        -- the actual painted native tile, including moved and mixed-pair doors.
        local index=y*source.cellWidth+x+1
        local nativeRef,nativePair
        for _,layer in ipairs(source.layers or {}) do
          local ref=(layer.cells or {})[index]
          local pair=ref and ref.source:match("^@runtime:(.+)$")
          if layer.export~=false and pair then nativeRef,nativePair=ref,pair end
        end
        if not nativeRef then return end
        local key="editor_door_"..mod.id.."_"..nativePair.."_"..nativeRef.tile
        -- Door lookups can also query collision behavior. Give them a real
        -- bounded layout, not a partial midAt adapter with missing dimensions.
        if not Doors._layoutCache[key] then
          Doors._layoutCache[key]=Layout.fromDecoded({width=1,height=1,
            cells={{mid=nativeRef.tile,coll=0,elev=3}}},key,nativePair)
        end
        return proceed(key,0,0)
      end
      mod.hooks:wrap("editor.gen3.doors.lookup",function(proceed,mapId,x,y)
        -- Entrance sequencing supplies the destination map, while the door is
        -- still on the bound collision map. Use the module already available
        -- in the sandbox; mod environments intentionally have no `package`.
        local live=Collision._mapId
        if live and live~=mapId then
          local entry,info=lookupEditedDoor(proceed,live,x,y)
          if entry then return entry,info end
        end
        return lookupEditedDoor(proceed,mapId,x,y)
      end)
    end
    if not Collision._editorWarpDispatch then
      Collision._editorWarpDispatch=true
      local install=Collision.installWarps
      Collision.installWarps=function(...) return Runtime.call("editor.gen3.warps.install",install,...) end
    end
    mod.hooks:wrap("editor.gen3.warps.install",function(proceed,map)
      proceed(map)
      for _,warp in ipairs(map and map.warps or {}) do
        if warp.disabled then Collision._warps[warp.y*1024+warp.x]=nil end
      end
    end)
    local built,images={},{}
    local frameClock=0
    local function frameFor(ref)
      local pair=ref.source:match("^@runtime:(.+)$")
      local source=layered.sources[ref.source]
      local frames=pair and (layered.animations[pair] or {})[ref.tile] or source and (source.animations or {})[ref.tile]
      if not frames or #frames==0 then return ref.tile end
      local total=0;for _,f in ipairs(frames) do total=total+math.max(16,f.duration or 200) end
      local clock=frameClock*1000%total
      for _,f in ipairs(frames) do clock=clock-math.max(16,f.duration or 200);if clock<0 then return f.tile end end
      return ref.tile
    end
    local function drawRef(ref,x,y,over)
      local pair=ref.source:match("^@runtime:(.+)$")
      local tile=frameFor(ref)
      love.graphics.setColor(1,1,1,ref.opacity or 1)
      if pair then
        local ts=assert(T.get(pair),"Missing native tileset "..pair)
        local image=ts.image
        if over then image=ts.overImage end
        if image then love.graphics.draw(image,over and T.overQuad(ts,T.slotFor(ts,tile)) or T.quad(ts,T.slotFor(ts,tile)),x,y) end
      elseif not over then
        local source=assert(layered.sources[ref.source],"Missing tile source "..ref.source)
        local image=images[ref.source]
        if not image then image=mod.assets:image(source.image);image:setFilter("nearest","nearest");images[ref.source]=image end
        local columns=source.columns or math.floor(image:getWidth()/16)
        local quad=love.graphics.newQuad(tile%columns*16,math.floor(tile/columns)*16,16,16,image:getDimensions())
        love.graphics.draw(image,quad,x,y)
      end
    end
    local function render(entry)
      love.graphics.push("all")
      for _,over in ipairs({false,true}) do
        love.graphics.setCanvas(over and entry.ts.overImage or entry.ts.image)
        love.graphics.clear(0,0,0,0);love.graphics.origin()
        for i,refs in ipairs(entry.slots) do
          local x,y=(i-1)%entry.ts.cols*16,math.floor((i-1)/entry.ts.cols)*16
          for _,ref in ipairs(refs) do drawRef(ref,x,y,over) end
        end
      end
      love.graphics.pop()
    end
    for id,source in pairs(layered.maps) do
      local map=assert(ctx.game.data.maps[id],"Missing map "..id)
      local slots,seen,cells,behaviors={},{},{},{}
      local width,height=source.cellWidth,source.cellHeight
      for index=1,width*height do
        local refs,key={},{}
        -- Keep the original feet-tile behavior. It distinguishes, for
        -- example, rocks in water from ordinary surfable water even when the
        -- native behavior catalog is unavailable by the time the mod loads.
        local behavior=(source.gen3Behavior or {})[index] or 0
        for _,layer in ipairs(source.layers or {}) do
          local ref=(layer.cells or {})[index]
          if layer.export~=false and ref then
            refs[#refs+1]={source=ref.source,tile=ref.tile,opacity=layer.opacity or 1}
            key[#key+1]=ref.source..":"..ref.tile..":"..(layer.opacity or 1)
            local pair=ref.source:match("^@runtime:(.+)$")
            if pair then
              local native=(Interactions.behaviors[pair] or {})[ref.tile]
              if native~=nil then behavior=native end
            end
          end
        end
        local mode=(source.collision or {})[index] or "solid"
        local original=(source.gen3Collision or {})[index]
        local nativeMode=collisionModes[original] or (original==0 and "walk" or "solid")
        local preserve=original~=nil and (mode==nativeMode or mode==(original==0 and "walk" or "solid"))
        local value=paintedCollision[mode] or paintedCollision.solid
        local coll=preserve and original or value[1]
        -- A new map has no baked collision byte to preserve. Its ordinary
        -- walkable door cell must retain the native MB_WARP_* behavior or the
        -- warp is dead even though its visual tile and event are present.
        local nativeWarp=behavior>=0x60 and (behavior<=0x6F or behavior==0x71)
        if not preserve and not (original==nil and mode=="walk" and nativeWarp) then
          behavior=value[2]
        end
        key[#key+1]=tostring(behavior);local signature=table.concat(key,"|")
        local mid=seen[signature]
        if mid==nil then mid=#slots;seen[signature]=mid;slots[#slots+1]=refs;behaviors[mid]=behavior end
        -- New surf tiles must connect to native water at elevation 0/1.
        -- Preserve explicit elevations (bridges included); only default new water.
        cells[index]={mid=mid,coll=coll,elev=(source.gen3Elevation or {})[index] or (mode=="water" and 0 or 3)}
      end
      local border=source.gen3Border or {width=1,height=1,mids={0}}
      local borderMids={}
      for i,mid in ipairs(border.mids) do
        borderMids[i]=#slots
        slots[#slots+1]={{source="@runtime:"..source.baseTileset,tile=mid,opacity=1}}
      end
      local cols=math.max(1,math.ceil(math.sqrt(#slots)))
      local rows=math.max(1,math.ceil(#slots/cols))
      local ts={cols=cols,rows=rows,midCount=#slots,midToSlot={},quads={},overQuads={},layered=true,
        image=love.graphics.newCanvas(cols*16,rows*16),overImage=love.graphics.newCanvas(cols*16,rows*16)}
      ts.image:setFilter("nearest","nearest");ts.overImage:setFilter("nearest","nearest")
      for i=0,#slots-1 do ts.midToSlot[i]=i end
      local pair="editor_"..mod.id.."_"..id
      local entry={ts=ts,slots=slots};render(entry);built[id]=entry
      T._pairs[pair]=ts;Interactions.behaviors[pair]=behaviors
      map.pair=pair;map.width=width;map.height=height
      map.midLayout=Layout.fromDecoded({width=width,height=height,cells=cells,
        borderWidth=border.width,borderHeight=border.height,borderMids=borderMids},id,pair)
    end
    if not View._editorLayerDispatch then
      View._editorLayerDispatch=true
      local draw=View.draw
      View.draw=function(...) return Runtime.call("editor.gen3.layers.draw",draw,...) end
    end
    local last=0
    mod.hooks:wrap("editor.gen3.layers.draw",function(proceed,game,...)
      local now=love.timer.getTime()
      if now-last>=1/30 then
        last=now
        frameClock=now
        local Map=require("src.core.game3.map")
        local visible={}
        if Map.current then visible[Map.current]=true end
        for _,neighbor in pairs(Map.neighbors or {}) do visible[neighbor.map or neighbor.mapId]=true end
        for _,neighbor in ipairs(Map.world or {}) do visible[neighbor.id]=true end
        for id in pairs(visible) do
          local entry=built[id]
          if entry then render(entry);View._nativeDirty=true end
        end
      end
      return proceed(game,...)
    end)
  end,-100)
]=]
