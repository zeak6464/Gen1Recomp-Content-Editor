-- Export source (not bytecode): assembles shared-editor layers against the
-- player's native FireRed atlases. No extracted pixels are bundled in a mod.
return [=[
  mod.events:on("game.ready",function(ctx)
    local T=require("src.core.game3.tileset_native")
    local Layout=require("src.core.game3.layout_native")
    local Interactions=require("src.core.game3.scripting.interaction_scripts")
    local View=require("src.core.game3.field_view")
    local Runtime=require("src.mods.Runtime")
    local Collision=require("src.core.game3.collision")
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
    local function frameFor(ref)
      local pair=ref.source:match("^@runtime:(.+)$")
      local source=layered.sources[ref.source]
      local frames=pair and (layered.animations[pair] or {})[ref.tile] or source and (source.animations or {})[ref.tile]
      if not frames or #frames==0 then return ref.tile end
      local total=0;for _,f in ipairs(frames) do total=total+math.max(16,f.duration or 200) end
      local clock=love.timer.getTime()*1000%total
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
        local behavior=0
        for _,layer in ipairs(source.layers or {}) do
          local ref=(layer.cells or {})[index]
          if layer.export~=false and ref then
            refs[#refs+1]={source=ref.source,tile=ref.tile,opacity=layer.opacity or 1}
            key[#key+1]=ref.source..":"..ref.tile..":"..(layer.opacity or 1)
            local pair=ref.source:match("^@runtime:(.+)$")
            if pair then behavior=(Interactions.behaviors[pair] or {})[ref.tile] or behavior end
          end
        end
        local mode=(source.collision or {})[index] or "solid"
        local painted={grass=2,water=16,door=105,cave=96,stairs=96,panel=103,
          ledge_down=56,ledge_up=57,ledge_left=58,ledge_right=59}
        behavior=painted[mode] or behavior
        key[#key+1]=mode;local signature=table.concat(key,"|")
        local mid=seen[signature]
        if mid==nil then mid=#slots;seen[signature]=mid;slots[#slots+1]=refs;behaviors[mid]=behavior end
        local coll=mode=="solid" and 255 or 0
        local original=(source.gen3Collision or {})[index]
        if original and ((original==0 and mode=="walk") or (original~=0 and mode=="solid")) then coll=original end
        cells[index]={mid=mid,coll=coll,elev=(source.gen3Elevation or {})[index] or 3}
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
        local id=game and game.session and (game.session.mapId or game.session.map)
        if type(id)=="table" then id=id.id end
        local entry=built[id]
        if entry then render(entry);View._nativeDirty=true end
      end
      return proceed(game,...)
    end)
  end,-100)
]=]
