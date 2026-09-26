-- Export source (not bytecode) for GFX > Blocks: puts the project's Gen 3
-- blocks into the game, on the player's machine, from the player's own cache.
--
-- What the mod carries (project.gen3BlockRuntime, see Gen3Blocks.lua): block
-- definitions -- which tile, where in the game's saved blocks it is, which
-- palette and flips -- and the modder's own painted pixels. No game graphics.
--
-- In game: tiles are cut out of the tileset's cached block pictures
-- (Gen3TileSource, inlined below), the blocks composed exactly as the engine
-- does, and written into that tileset's native atlas -- replacing edited
-- blocks and appending new ones -- so ROM maps, maps built in the editor and
-- palette effects all see them. Behaviours go into the engine's behaviour
-- table. Nothing in the engine is changed; two public functions are wrapped.
return function(data, encode)
  local out = {}
  -- One constructor per bag / per tileset, so no single function grows past
  -- LuaJIT's constant limits on big projects.
  out[#out + 1] = "  local g3blocks=(function() local d={pairs={},tiles={},palettes=" .. encode(data.palettes or {}) .. "}"
  local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
  end
  for _, pair in ipairs(sortedKeys(data.pairs)) do
    out[#out + 1] = "    d.pairs[" .. encode(pair) .. "]=(function() return "
      .. encode(data.pairs[pair]) .. " end)()"
  end
  local tileKeys = sortedKeys(data.tiles)
  for i = 1, #tileKeys, 64 do
    local part = {}
    for j = i, math.min(#tileKeys, i + 63) do part[tileKeys[j]] = data.tiles[tileKeys[j]] end
    out[#out + 1] = "    for k,v in pairs((function() return " .. encode(part) .. " end)()) do d.tiles[k]=v end"
  end
  out[#out + 1] = "    return d end)()"
  out[#out + 1] = "  local g3tileSource=(function()\n"
    .. assert(love.filesystem.read("tools/content-editor/Gen3TileSource.lua"),
      "Gen3TileSource.lua missing")
    .. "\n  end)()"
  out[#out + 1] = [=[
  mod.events:on("game.ready",function(ctx)
    local T=require("src.core.game3.tileset_native")
    local NativePack=require("src.import.gba.native_pack")
    local Interactions=require("src.core.game3.scripting.interaction_scripts")
    local View=require("src.core.game3.field_view")
    local Runtime=require("src.mods.Runtime")
    local okE,Extract=pcall(require,"src.import.gba.extract_island1")
    local NATIVE=(okE and Extract and (Extract.NATIVE_ROOT
      or (Extract.CACHE_ROOT and Extract.CACHE_ROOT.."/native"))) or "data/generated/gba/native"
    local TS=g3tileSource

    -- Behaviours. The engine may install its behaviour table after this
    -- runs (or again later), so reapply whenever it does.
    local function applyBehaviors()
      local all=Interactions.behaviors
      if type(all)~="table" then return end
      for pair,blocks in pairs(g3blocks.pairs) do
        local row=all[pair]
        if not row then row={};all[pair]=row end
        for mid,blk in pairs(blocks) do row[mid]=blk.behavior end
      end
    end
    if not Interactions._editorBlocksDispatch then
      Interactions._editorBlocksDispatch=true
      local install=Interactions.install
      Interactions.install=function(...) return Runtime.call("editor.gen3.blocks.behaviors",install,...) end
    end
    mod.hooks:wrap("editor.gen3.blocks.behaviors",function(proceed,...)
      local a,b=proceed(...);applyBehaviors();return a,b
    end)
    applyBehaviors()

    -- Tiles, cut from the player's cache the first time a tileset needs them.
    local function readPair(pair)
      local cache=T._cache
      if not cache then return nil end
      local okU,u=pcall(function() return cache:read(NATIVE.."/"..pair.."/mids.idx") end)
      local okO,o=pcall(function() return cache:read(NATIVE.."/"..pair.."/mids_over.idx") end)
      return TS.decodePair(okU and u or nil,okO and o or nil)
    end
    local function tilesFor(pair)
      local pack=readPair(pair)
      if not pack then return nil end
      local tiles={}
      local function get(key)
        if tiles[key]~=nil then return tiles[key] end
        local own=g3blocks.tiles[key]
        local px
        if own then
          local base=own.base and TS.tile(pack,own.base)
          if own.base and not base then px=false else
            px={}
            for i=1,64 do
              local ch=own.px:sub(i,i)
              if ch=="." then
                local v=base[i]
                if own.recolour and v~=0 then v=tonumber(own.recolour:sub(v+1,v+1),16) or v end
                px[i]=v
              else px[i]=tonumber(ch,16) or 0 end
            end
          end
        else
          px=TS.tile(pack,key) or false
        end
        tiles[key]=px
        return px
      end
      return setmetatable({},{__index=function(_,key) return get(key) or nil end})
    end

    -- Where each bottom-layer pixel of a block comes from in the game's
    -- saved pictures: [pixel 1-256] = {block, pixel}. Only pixels that are
    -- still visible in the finished block are listed. The tileset animation
    -- (water, sand, flowers) uses this to keep a block built on animated
    -- ground animating.
    local function sources(all,blk)
      local covered=blk.layerType=="covered"
      local out={}
      -- Bottom layer, then (covered blocks draw both under the player) the
      -- top layer over it: each pixel's source is the last tile drawn there.
      for s=1,covered and 8 or 4 do
        local slot=blk.slots[s]
        local key=slot and slot.key
        local own=key and g3blocks.tiles[key]
        local srcKey=own and own.base or key
        local mid,_,q=TS.parseKey(srcKey)
        local omid,_,oq=TS.parseKey(own and own.over)
        local px=key and all[key]
        if px then
          local ox,oy=((s-1)%4%2)*8,math.floor((s-1)%4/2)*8
          for y=0,7 do for x=0,7 do
            local ty,tx=slot.vflip and 7-y or y,slot.hflip and 7-x or x
            local t=ty*8+tx+1
            if (px[t] or 0)~=0 then
              local di=(oy+y)*16+ox+x+1
              if mid and (not own or own.px:sub(t,t)==".") then
                out[di]={mid,(math.floor(q/2)*8+ty)*16+(q%2)*8+tx+1}
              elseif omid and own.overMask:sub(t,t)=="1" then
                -- a merged game tile's pixel: animates with that tile's block
                local bx,by=own.overH and 7-tx or tx,own.overV and 7-ty or ty
                out[di]={omid,(math.floor(oq/2)*8+by)*16+(oq%2)*8+bx+1}
              else
                out[di]=nil
              end
            end
          end end
        end
      end
      return next(out) and out or nil
    end

    -- Write a tileset's blocks into its atlas: replace edited ones in place,
    -- append new ones, rebake. A block that can't be built is left alone.
    local function patch(pair,ts)
      local blocks=g3blocks.pairs[pair]
      if not blocks or not ts or ts._g3Blocks then return end
      ts._g3Blocks=true
      local under=ts.idxBlob and NativePack.decodeIdx(ts.idxBlob)
      local over=ts.overBlob and NativePack.decodeIdx(ts.overBlob)
      if not under then return end
      local mids={}
      for mid,blk in pairs(blocks) do if blk.slots then mids[#mids+1]=mid end end
      table.sort(mids)
      if #mids==0 then return end
      local all=tilesFor(pair)
      if not all then return end
      local changed=false
      ts._g3Sources={}
      for _,mid in ipairs(mids) do
        local blk=blocks[mid]
        local u,o=TS.compose(all,{slots=blk.slots,layerType=blk.layerType})
        if u then
          local src=sources(all,blk)
          if src and not over then
            for i=1,256 do if o[i]~=0 then src[i]=nil end end
          end
          ts._g3Sources[mid]=src or false
          if not over then -- flat atlas: one picture, top drawn over bottom
            for i=1,256 do if o[i]~=0 then u[i]=o[i] end end
          end
          local slot=ts.midToSlot[mid]
          if not slot then
            slot=under.midCount
            under.midCount=slot+1;under.midIds[#under.midIds+1]=mid
            if over then over.midCount=slot+1;over.midIds[#over.midIds+1]=mid end
          end
          local base=slot*256
          for i=1,256 do
            under.pixels[base+i]=u[i]
            if over then over.pixels[base+i]=o[i] end
          end
          ts.midToSlot[mid]=slot
          changed=true
        end
      end
      if not changed then return end
      local cols=under.atlasCols or ts.cols or 16
      local rows=math.max(1,math.ceil(under.midCount/cols))
      under.atlasCols,under.atlasRows=cols,rows
      if over then over.atlasCols,over.atlasRows=cols,rows end
      -- Colours the modder added to free colour numbers of this tileset's palettes.
      local added=g3blocks.palettes[pair]
      if added and ts.bgr then
        for pal,cols in pairs(added) do
          local row=ts.bgr[pal]
          if row then for c,v in pairs(cols) do row[c]=v end end
        end
      end
      local rgb=NativePack.palsToRgb8(ts.bgr or {})
      local function bake(tbl,transparentZero)
        local rgba,w,h=NativePack.bakeRgba(tbl,rgb,{transparentZero=transparentZero})
        local imageData=love.image.newImageData(w,h,"rgba8",rgba)
        local image=love.graphics.newImage(imageData)
        image:setFilter("nearest","nearest")
        return image,imageData
      end
      ts.image,ts.imageData=bake(under,false)
      if over then ts.overImage,ts.overImageData=bake(over,true) end
      ts.idxBlob=NativePack.encodeIdx(under)
      if over then ts.overBlob=NativePack.encodeIdx(over) end
      ts.cols,ts.rows,ts.midCount=cols,rows,under.midCount
      ts.quads,ts.overQuads,ts.slotPix={}, {}, {}
      -- Each block's finished under-picture, for the tileset animation.
      ts._g3Static={}
      for mid in pairs(ts._g3Sources) do
        local slot=ts.midToSlot[mid]
        local ax,ay=slot%cols*16,math.floor(slot/cols)*16
        local px={}
        for i=0,255 do
          local r,g,b,a=ts.imageData:getPixel(ax+i%16,ay+math.floor(i/16))
          px[i+1]=string.char(math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),math.floor(a*255+.5))
        end
        ts._g3Static[mid]=px
      end
      View._nativeDirty=true
    end

    -- Tileset animation. The engine pastes a saved picture per animation
    -- frame over each animated block. Give our blocks their own frames:
    -- the animated source pixels from that frame, everything else as
    -- composed. An edited block with nothing animated under it leaves the
    -- animation, so the edit stays visible.
    local okA,Anim=pcall(require,"src.core.game3.tileset_anim")
    local MID=1024
    local function animate(pair,ts)
      if not okA or type(Anim)~="table" then return end
      local entry=(Anim._pairs or {})[pair]
      if type(entry)~="table" or entry._g3==ts or not ts._g3Sources or not ts.imageData then return end
      entry._g3=ts;entry.atlas=ts;entry.frames={}
      local placed,restore={},{}
      for _,kind in ipairs({"water","sand","flower"}) do
        local bank=entry.banks and entry.banks[kind]
        if bank and bank.frames and bank.frames>0 then
          local old,oldIndex,n=bank.mids,bank.midIndex,#bank.mids
          local mids,own={},{}
          for _,mid in ipairs(old) do
            if ts._g3Sources[mid]==nil then mids[#mids+1]=mid end
          end
          for mid,src in pairs(ts._g3Sources) do
            if src and not placed[mid] then
              for _,s in pairs(src) do
                if oldIndex[s[1]] then own[mid]=src;placed[mid]=true;mids[#mids+1]=mid;break end
              end
            end
          end
          local statics=ts._g3Static or {}
          for _,mid in ipairs(old) do -- edited: back to its own picture unless re-added below
            if ts._g3Sources[mid]~=nil then restore[mid]=true end
          end
          local chunks={}
          for f=0,bank.frames-1 do
            for _,mid in ipairs(mids) do
              local src=own[mid]
              if not src then
                local off=(f*n+oldIndex[mid])*MID
                chunks[#chunks+1]=bank.rgba:sub(off+1,off+MID)
              else
                local px={}
                for i=1,256 do
                  local s=src[i]
                  local si=s and oldIndex[s[1]]
                  if si then
                    local off=(f*n+si)*MID+(s[2]-1)*4
                    px[i]=bank.rgba:sub(off+1,off+4)
                  else
                    px[i]=statics[mid][i]
                  end
                end
                chunks[#chunks+1]=table.concat(px)
              end
            end
          end
          local index={}
          for i,mid in ipairs(mids) do index[mid]=i-1 end
          bank.mids,bank.midIndex,bank.rgba=mids,index,table.concat(chunks)
        end
      end
      -- The engine may already have pasted its own frames over blocks that
      -- have left the animation: put the edited pictures back.
      for mid in pairs(placed) do restore[mid]=nil end
      local cols=ts.cols or 16
      for mid in pairs(restore) do
        local slot,static=ts.midToSlot[mid],ts._g3Static and ts._g3Static[mid]
        if slot and static then
          ts.imageData:paste(love.image.newImageData(16,16,"rgba8",table.concat(static)),slot%cols*16,math.floor(slot/cols)*16)
        end
      end
      if next(restore) and ts.image and ts.image.replacePixels then ts.image:replacePixels(ts.imageData) end
      for _,kind in ipairs({"water","sand","flower"}) do
        pcall(Anim._applyKind,entry,kind,Anim["_"..kind.."Frame"] or 0)
      end
    end

    -- Every tileset the engine loads from now on, and any already loaded.
    if not T._editorBlocksDispatch then
      T._editorBlocksDispatch=true
      local get=T.get
      T.get=function(...) return Runtime.call("editor.gen3.blocks.get",get,...) end
    end
    mod.hooks:wrap("editor.gen3.blocks.get",function(proceed,pair,...)
      local ts=proceed(pair,...)
      if ts and g3blocks.pairs[pair] then
        if not ts._g3Blocks then patch(pair,ts) end
        animate(pair,ts)
      end
      return ts
    end)
    for pair,ts in pairs(T._pairs or {}) do
      if g3blocks.pairs[pair] then patch(pair,ts);animate(pair,ts) end
    end
  end,0)
]=]
  return table.concat(out, "\n")
end
