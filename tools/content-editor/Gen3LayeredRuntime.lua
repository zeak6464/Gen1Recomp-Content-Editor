-- Export source (not bytecode): assembles shared-editor layers against the
-- player's native FireRed atlases. No extracted pixels are bundled in a mod.
local C=require("Gen3Collision")
local encode=require("ModWriter").encodeLua
return "  local collisionModes="..encode(C.modes).."\n  local paintedCollision="..encode(C.painted).."\n"..[=[
  mod.events:on("game.ready",function(ctx)
    local T=require("src.core.game3.tileset_native")
    local Layout=require("src.core.game3.layout_native")
    local Interactions=require("src.core.game3.scripting.interaction_scripts")
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
        local refs=source.slotRefs and source.slotRefs[source.cellSlots[index]]
        local nativeRef,nativePair
        for _,ref in ipairs(refs or {}) do
          if ref.pair and not ref.bridge then nativeRef,nativePair=ref,ref.pair end
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
    local built,images,sourceQuads={},{},{}
    local Map=require("src.core.game3.map")
    local okAnim,NativeAnim=pcall(require,"src.core.game3.tileset_anim")
    local renderNative
    local frameClock=0
    -- FireRed banks are keyed by kind with .mids; Emerald ("rse") banks are a
    -- list whose tile ids live in .row and whose current frame is bank.frame.
    local function nativeFrame(anim,kind)
      if not anim then return nil end
      if anim.rse then return anim.banks[kind] and anim.banks[kind].frame end
      return anim.frames[kind]
    end
    -- mids.idx: 12-byte header, 2 bytes per mid id, then 256 pixel bytes per
    -- atlas slot whose high nibble is the palette (same layout scan_slot reads).
    local function slotUsesPalette(blob,slot,palette,skipZero)
      if type(blob)~="string" or #blob<12 then return false end
      local base=13+(blob:byte(7)+blob:byte(8)*256)*2+slot*256
      for i=base,base+255 do
        local b=blob:byte(i)
        if b and math.floor(b/16)==palette and not (skipZero and b==0) then return true end
      end
      return false
    end
    local function bankHasMid(anim,bank,mid)
      if not bank then return false end
      if anim.rse and bank.row.kind=="palette" then
        local ts=anim.atlas
        local slot=ts and ts.midToSlot[mid]
        if not slot then return false end
        local palette=bank.row.paletteSlot or 0
        return slotUsesPalette(ts.idxBlob,slot,palette,false)
          or slotUsesPalette(ts.overBlob,slot,palette,true)
      end
      local lists=anim.rse and {bank.row.mids,bank.row.overMids} or {bank.mids}
      for _,list in ipairs(lists) do
        for _,m in ipairs(list or {}) do if m==mid then return true end end
      end
      return false
    end
    local function frameFor(ref)
      if not ref.schedule then return ref.tile end
      local clock=frameClock*1000%ref.duration
      for _,f in ipairs(ref.schedule) do if clock<f.untilTime then return f.tile end end
      return ref.tile
    end
    local batches,order
    local function queueDraw(image,quad,x,y,opacity)
      local batch=batches[image]
      if not batch then
        batch=love.graphics.newSpriteBatch(image,64,"stream")
        batches[image]=batch;order[#order+1]=batch
      end
      batch:setColor(1,1,1,opacity or 1);batch:add(quad,x,y)
    end
    local function drawRef(ref,x,y,over)
      if ref.bridge and not over then return end
      local pair=ref.pair
      local tile=ref.frame or ref.tile
      if pair then
        local ts=assert(renderNative[pair],"Missing native tileset "..pair)
        local image=ts.image
        if over and not ref.bridge then image=ts.overImage end
        if image then queueDraw(image,over and not ref.bridge and T.overQuad(ts,T.slotFor(ts,tile)) or T.quad(ts,T.slotFor(ts,tile)),x,y,ref.opacity) end

      elseif not over or ref.bridge then
        local source=assert(layered.sources[ref.source],"Missing tile source "..ref.source)
        local image=images[ref.source]
        if image==nil then
          -- Baked sheets (TilePixels) carry their pixels; older ones load the
          -- PNG. A sheet whose PNG is gone draws nothing (once logged) rather
          -- than stopping every map after this one.
          local ok,loaded=pcall(function()
            if source.pixels then return love.graphics.newImage(tilePixels.imageData(source.pixels)) end
            return mod.assets:image(source.image)
          end)
          if ok and loaded then
            image=loaded;image:setFilter("nearest","nearest")
          else
            image=false
            print("[editor layers] tile sheet "..tostring(ref.source).." can't be drawn: "..tostring(loaded))
          end
          images[ref.source]=image
        end
        if not image then return end
        local columns=source.columns or math.floor(image:getWidth()/16)
        local quads=sourceQuads[ref.source]
        if not quads then quads={};sourceQuads[ref.source]=quads end
        local quad=quads[tile]
        if not quad then
          quad=love.graphics.newQuad(tile%columns*16,math.floor(tile/columns)*16,16,16,image:getDimensions())
          quads[tile]=quad
        end
        queueDraw(image,quad,x,y,ref.opacity)
      end
    end
    local function prepare(entry)
      entry.frameRefs,entry.resolved={},{}
      entry.depth=0
      for i,refs in ipairs(entry.slots) do
        entry.depth=math.max(entry.depth,#refs)
        for _,ref in ipairs(refs) do
          ref.pair=ref.source:match("^@runtime:(.+)$")
          local pair=ref.pair
          if pair and not entry.resolved[pair] then
            entry.resolved[pair]=assert(T.get(pair),"Missing native tileset "..pair)
          end
          local source=layered.sources[ref.source]
          local frames=pair and (layered.animations[pair] or {})[ref.tile]
            or source and (source.animations or {})[ref.tile]
          if frames and #frames>0 then
            ref.schedule={};ref.duration=0
            for _,f in ipairs(frames) do
              ref.duration=ref.duration+math.max(16,f.duration or 200)
              ref.schedule[#ref.schedule+1]={tile=f.tile,untilTime=ref.duration}
            end
          end
          local anim=pair and okAnim and NativeAnim._pairs and NativeAnim._pairs[pair]
          if anim then
            for kind,bank in pairs(anim.banks or {}) do
              if bankHasMid(anim,bank,ref.tile) then
                ref.kind=kind;ref.nativeFrame=nativeFrame(anim,kind);break
              end
            end
          end
          ref.frame=frameFor(ref)
          if ref.schedule or ref.kind then
            entry.frameRefs[#entry.frameRefs+1]={ref=ref,slot=i}
          end
        end
      end
    end
    local function render(entry,dirty)
      renderNative=entry.resolved
      love.graphics.push("all")
      local ok,err=pcall(function()
        love.graphics.origin();love.graphics.setScissor();love.graphics.setColor(1,1,1,1)
        for pass=1,2 do
          local over=pass==2
          love.graphics.setCanvas(over and entry.ts.overImage or entry.ts.image)
          if not dirty then love.graphics.clear(0,0,0,0)
          else
            for i in pairs(dirty) do
              love.graphics.setScissor((i-1)%entry.ts.cols*16,math.floor((i-1)/entry.ts.cols)*16,16,16)
              love.graphics.clear(0,0,0,0)
            end
            love.graphics.setScissor()
          end
          -- Different slots never overlap. Group each layer by texture, retaining
          -- layer order and the separate bridge overlay pass for alpha blending.
          for depth=1,entry.depth do
            batches,order={},{}
            for i,refs in ipairs(entry.slots) do
              if not dirty or dirty[i] then
                local ref=refs[depth]
                if ref then drawRef(ref,(i-1)%entry.ts.cols*16,math.floor((i-1)/entry.ts.cols)*16,over) end
              end
            end
            for _,batch in ipairs(order) do love.graphics.draw(batch);batch:release() end
            if over then
              batches,order={},{}
              for i,refs in ipairs(entry.slots) do
                local ref=refs[depth]
                if (not dirty or dirty[i]) and ref and ref.bridge and ref.pair then
                  local ts=renderNative[ref.pair]
                  if ts.overImage then queueDraw(ts.overImage,T.overQuad(ts,T.slotFor(ts,ref.frame)),
                    (i-1)%entry.ts.cols*16,math.floor((i-1)/entry.ts.cols)*16,ref.opacity) end
                end
              end
              for _,batch in ipairs(order) do love.graphics.draw(batch);batch:release() end
            end
          end
        end
      end)
      love.graphics.pop();renderNative=nil;batches,order=nil,nil
      if not ok then error(err) end
    end
    -- The atlas a cell is redrawn from, loaded: runtimes from 0.3.6x release
    -- atlases beyond NativeTileset.RESIDENT_MAX (their images go nil), so an
    -- atlas held from before may be empty -- fetch it again then.
    local function loaded(pair)
      local ts=T._pairs[pair]
      if not (ts and ts.image) then ts=T.get(pair) end
      if ts and ts.image then return ts end
      return nil
    end
    local function animate(entry)
      if #entry.frameRefs==0 then return end
      local dirty
      for _,state in ipairs(entry.frameRefs) do
        local ref=state.ref;local frame=frameFor(ref)
        local anim=ref.pair and NativeAnim._pairs and NativeAnim._pairs[ref.pair]
        local current=ref.kind and nativeFrame(anim,ref.kind)
        if frame~=ref.frame or current~=ref.nativeFrame then
          -- A cell is cleared before it is redrawn: only redraw it when every
          -- atlas it draws from is loaded, else it would stay blank. It keeps
          -- its last picture and tries again on the next step.
          local all=true
          for _,r in ipairs(entry.slots[state.slot] or {}) do
            if r.pair then
              local ts=loaded(r.pair)
              if ts then entry.resolved[r.pair]=ts else all=false end
            end
          end
          if all then
            dirty=dirty or {};dirty[state.slot]=true
            ref.frame,ref.nativeFrame=frame,current
          end
        end
      end
      if dirty then render(entry,dirty) end
    end
    -- One map that can't be built must not leave the rest unbuilt (which
    -- ones come after it depends on table order, so it differs between
    -- devices).
    local function build(id,source)
      local map=assert(ctx.game.data.maps[id],"Missing map "..id)
      local slots,seen,cells,behaviors,cellSlots={},{},{},{},{}
      local hasFalls=false
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
        local bridge=(source.gen3Bridges or {})[index]
        if bridge and bridge.kind=="deck" and bridge.tile then
          refs[#refs+1]={source=bridge.tile.source,tile=bridge.tile.tile,opacity=1,bridge=true}
          key[#key+1]="bridge:"..bridge.tile.source..":"..bridge.tile.tile
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
        if behavior==0x13 then hasFalls=true end
        key[#key+1]=tostring(behavior);local signature=table.concat(key,"|")
        local mid=seen[signature]
        if mid==nil then mid=#slots;seen[signature]=mid;slots[#slots+1]=refs;behaviors[mid]=behavior end
        -- New surf tiles must connect to native water at elevation 0/1.
        -- Preserve explicit elevations (bridges included); only default new water.
        cellSlots[index]=mid+1
        cells[index]={mid=mid,coll=coll,elev=(source.gen3Elevation or {})[index] or (mode=="water" and 0 or 3)}
      end
      local border=source.gen3Border or {width=1,height=1,mids={0}}
      local borderMids={}
      for i,mid in ipairs(border.mids) do
        borderMids[i]=#slots
        slots[#slots+1]={{source="@runtime:"..(border.pair or source.baseTileset),tile=mid,opacity=1}}
      end
      -- Native interior scripts read and write ROM metatile IDs (the labs
      -- restore their floors on entry). Keep those IDs when the room uses a
      -- single native layer; compact atlas slots would reinterpret script edits.
      local direct=(source.visualInterior or source.visualNativeProfile) and (border.pair or source.baseTileset)==source.baseTileset
      for _,refs in ipairs(slots) do
        if #refs~=1 or refs[1].source~="@runtime:"..source.baseTileset or refs[1].opacity~=1 then direct=false;break end
      end
      if direct then
        for index,cell in ipairs(cells) do cell.mid=slots[cellSlots[index]][1].tile end
        map.pair=source.baseTileset;map.width=width;map.height=height
        map.midLayout=Layout.fromDecoded({width=width,height=height,cells=cells,
          borderWidth=border.width,borderHeight=border.height,borderMids=border.mids},id,source.baseTileset)
        layered.maps[id]={cellWidth=width,cellHeight=height,slotRefs=slots,cellSlots=cellSlots}
        return
      end
      local cols=math.max(1,math.ceil(math.sqrt(#slots)))
      local rows=math.max(1,math.ceil(#slots/cols))
      local ts={cols=cols,rows=rows,midCount=#slots,midToSlot={},quads={},overQuads={},layered=true,
        image=love.graphics.newCanvas(cols*16,rows*16),overImage=love.graphics.newCanvas(cols*16,rows*16)}
      ts.image:setFilter("nearest","nearest");ts.overImage:setFilter("nearest","nearest")
      for i=0,#slots-1 do ts.midToSlot[i]=i end
      local pair="editor_"..mod.id.."_"..id
      local entry={ts=ts,slots=slots};prepare(entry);render(entry);built[id]=entry
      -- Window mode changes can clear Canvas contents without changing size.
      ts._editorRebuild=function() render(entry) end
      layered.maps[id]={cellWidth=width,cellHeight=height,slotRefs=slots,cellSlots=cellSlots}
      T._pairs[pair]=ts;Interactions.behaviors[pair]=behaviors
      map.pair=pair;map.width=width;map.height=height
      map._editorHasWaterfalls=hasFalls
      map._editorBridges=source.gen3Bridges
      map.midLayout=Layout.fromDecoded({width=width,height=height,cells=cells,
        borderWidth=border.width,borderHeight=border.height,borderMids=borderMids},id,pair)
      -- The map's scripts still write ROM metatile IDs of its base tileset
      -- (the Mansion switches, the lab floors, Rocket Hideout doors): written
      -- straight into this layout they would pick compact atlas slots at
      -- random. Translate each written ID to the slot that is exactly that
      -- native block, adding the slot (and growing the canvas) when the map
      -- never painted it.
      local layout=map.midLayout
      local base=source.baseTileset
      local baseRef="@runtime:"..base
      local baseBehaviors=Interactions.behaviors[base] or {}
      local nativeSlot={}
      for i,refs in ipairs(slots) do
        local r=refs[1]
        if #refs==1 and r.source==baseRef and (r.opacity or 1)==1 and not r.bridge then
          local slot=i-1
          -- Prefer the slot that also kept the block's own behaviour.
          if nativeSlot[r.tile]==nil or behaviors[slot]==(baseBehaviors[r.tile] or 0) then nativeSlot[r.tile]=slot end
        end
      end
      local function slotForNative(mid)
        mid=tonumber(mid) or 0
        local slot=nativeSlot[mid]
        if slot then return slot end
        slot=#slots
        slots[slot+1]={{source=baseRef,tile=mid,opacity=1}}
        behaviors[slot]=baseBehaviors[mid] or 0
        nativeSlot[mid]=slot
        ts.midToSlot[slot]=slot;ts.midCount=#slots
        local ok,err=pcall(function()
          if #slots>ts.cols*ts.rows then
            local c=math.max(1,math.ceil(math.sqrt(#slots)))
            local r=math.max(1,math.ceil(#slots/c))
            local image=love.graphics.newCanvas(c*16,r*16)
            local overImage=love.graphics.newCanvas(c*16,r*16)
            image:setFilter("nearest","nearest");overImage:setFilter("nearest","nearest")
            local old,oldOver=ts.image,ts.overImage
            ts.image,ts.overImage,ts.cols,ts.rows=image,overImage,c,r
            ts.quads,ts.overQuads,ts.slotPix={},{},{}
            if old then old:release() end
            if oldOver then oldOver:release() end
          end
          prepare(entry);render(entry)
        end)
        if not ok then print("[editor layers] map "..tostring(id).." script tile "..mid.." not drawn: "..tostring(err)) end
        local okView,FieldView=pcall(require,"src.core.game3.field_view")
        if okView and FieldView then FieldView._nativeDirty=true end
        return slot
      end
      local apply=layout.applyOverride
      layout.applyOverride=function(self,x,y,mid,coll,elev)
        return apply(self,x,y,slotForNative(mid),coll,elev)
      end
      local setRows=layout.setMetatiles
      layout.setMetatiles=function(self,rows)
        local out={}
        for i,r in ipairs(rows or {}) do
          out[i]={x=r.x,y=r.y,mid=r.mid~=nil and slotForNative(r.mid) or nil,coll=r.coll,elev=r.elev}
        end
        return setRows(self,out)
      end
    end
    for id,source in pairs(layered.maps) do
      local ok,err=pcall(build,id,source)
      if not ok then print("[editor layers] map "..tostring(id).." not built: "..tostring(err)) end
    end
    -- Runtimes from 0.3.6x keep at most NativeTileset.RESIDENT_MAX atlases and
    -- release the rest. The field view keeps the atlases of the maps it shows:
    -- for an edited map that is only its own canvas, not the native atlases its
    -- animated cells (water, flowers, the modder's own animations) are redrawn
    -- from -- those were released and the animated cells drew blank. Keep them
    -- with the map that uses them.
    local byPair={}
    for id,entry in pairs(built) do byPair["editor_"..mod.id.."_"..id]=entry end
    if T.trim and not T._editorLayersTrim then
      T._editorLayersTrim=true
      local trim=T.trim
      T.trim=function(...) return Runtime.call("editor.gen3.layers.trim",trim,...) end
    end
    -- The atlases the field view kept on its last trim: the maps it is drawing
    -- (the one you are on and the ones near the camera). Only those animate --
    -- a map further away in Map.world is not drawn, and animating it would
    -- fetch its released atlases again on every step (a Route 36 two links from
    -- Ecruteak rebuilt Ecruteak's pond tileset ~16 times a second: severe lag).
    local lastKeep
    mod.hooks:wrap("editor.gen3.layers.trim",function(proceed,keep,max,busy)
      lastKeep=keep or {}
      local held={}
      -- An edited map's own atlas is a canvas drawn once, here, at game.ready:
      -- NativeTileset.get can't load it back from the cache the way it reloads
      -- a game atlas. Released, the map has no tiles any more (the field view
      -- falls back to the Gen 2 atlas) -- so every one of them stays.
      for p in pairs(byPair) do held[p]=true end
      for p in pairs(keep or {}) do
        held[p]=true
        local entry=byPair[p]
        if entry and #entry.frameRefs>0 then
          for _,state in ipairs(entry.frameRefs) do
            for _,r in ipairs(entry.slots[state.slot] or {}) do if r.pair then held[r.pair]=true end end
          end
        end
      end
      return proceed(held,max,busy)
    end)
    -- The native animation step owns the clock. No draw hook, wall-clock poll,
    -- visible-set allocation or pair rebinding is needed.
    if okAnim and NativeAnim.step then
      local step=NativeAnim.step
      local function activate(entry)
        if not entry then return end
        for _,state in ipairs(entry.frameRefs) do
          local ref=state.ref
          if ref.kind then NativeAnim._visible[ref.pair]=true end
        end
      end
      NativeAnim.step=function(...)
        activate(built[Map.current])
        for _,n in ipairs(Map.neighborList or {}) do activate(built[n.map or n.mapId]) end
        for _,n in ipairs(Map.world or {}) do activate(built[n.id]) end
        -- Emerald steps its own _rse counters and leaves .counter untouched.
        local rse=NativeAnim._rse
        local before,rseBefore=NativeAnim.counter,rse and rse.primary
        local result=step(...)
        if NativeAnim.counter==before and (not rse or rse.primary==rseBefore) then
          return result
        end
        frameClock=frameClock+1/60
        local current=built[Map.current]
        if current then animate(current) end
        local function shown(id) return lastKeep==nil or lastKeep["editor_"..mod.id.."_"..tostring(id)] end
        for _,n in ipairs(Map.neighborList or {}) do
          local id=n.map or n.mapId;local entry=built[id]
          if entry and entry~=current and entry.lastStep~=frameClock and shown(id) then
            entry.lastStep=frameClock;animate(entry)
          end
        end
        for _,n in ipairs(Map.world or {}) do
          local entry=built[n.id]
          if entry and entry~=current and entry.lastStep~=frameClock and shown(n.id) then
            entry.lastStep=frameClock;animate(entry)
          end
        end
        return result
      end
    end
  end,-100)
]=]
