-- Export source (not bytecode) for FireRed Maps (Gen3FrLink): the game side
-- of an Emerald mod that uses FireRed tilesets, maps and wild Pokemon.
--
-- The mod carries names only: tilesets "frlg__<FireRed tileset>" and map
-- layouts "frlg:<FireRed map>". Everything they point at is read here, on the
-- player's machine, from the player's own FireRed or LeafGreen import (the
-- runtime's firered/ or leafgreen/ cache). Without one the mod stops loading
-- with a message, so nothing FireRed-made ever shows up half there.
--
-- Nothing in the engine is changed. The tileset caches get a proxy that sends
-- native/frlg__<pair>/ reads to that import, FireRed's tile animations are
-- stepped on FireRed's clock next to Emerald's, the behaviour and wild
-- encounter tables get the import's rows for those tilesets (Emerald and
-- FireRed behaviours share the engine's numbering), and Gen3Map asks
-- `LayoutNative._editorFrLink.layout(source)` for FireRed layouts.
local M={}
M.PAIR="frlg__"
M.MAP="frlg:"
M.REGION="EM_KANTO_"

-- The player's FireRed or LeafGreen import: "firered/" or "leafgreen/", or
-- nil. Only a finished import of a known dump counts.
function M.find(readAt)
  local GV=require("src.core.GameVersion")
  for _,game in ipairs({"firered","leafgreen"}) do
    local prefix=GV.cachePrefix(game)
    local okR,marker=pcall(readAt,prefix.."rom-cache.complete")
    local sha=okR and type(marker)=="string" and marker:match("^rom%-cache%-v%d+%-"..game..":(%x+)")
    if sha then
      for _,rev in ipairs(GV.revisions(game)) do
        if rev.sha1==sha:lower() then return prefix,game end
      end
    end
  end
end

--- "…/native/frlg__X/…" -> "…/native/X/…", or nil for other paths.
function M.redirect(path)
  if type(path)~="string" then return nil end
  local out,n=path:gsub("/native/"..M.PAIR.."([^/]+)/","/native/%1/",1)
  return n>0 and out or nil
end

--- A sign's steps (Gen3FrLink.signSteps) as an Emerald script.
function M.signOps(steps)
    local ops={{op="lockall",opcode=105}}
    for _,st in ipairs(steps) do
      local key=st[2] and (M.MAP..st[2])
      if st[1]=="text" then
        ops[#ops+1]={op="loadword",opcode=15,[1]=0,[2]=key,dest=0,value=key}
        ops[#ops+1]={op="callstd",opcode=9,[1]=4,std=4}
      elseif st[1]=="braille" then
        ops[#ops+1]={op="braillemessage",opcode=120,[1]=key,ptr=key}
        ops[#ops+1]={op="waitbuttonpress",opcode=109}
        ops[#ops+1]={op="closebraillemessage",opcode=218}
      elseif st[1]=="pic" then
        ops[#ops+1]={op="showmonpic",opcode=117,[1]=st[2],[2]=st[3],[3]=st[4]}
      elseif st[1]=="unpic" then
        ops[#ops+1]={op="hidemonpic",opcode=118}
      end
    end
    ops[#ops+1]={op="releaseall",opcode=107}
    ops[#ops+1]={op="end",opcode=2}
    return ops
  end

--- A person's steps (Gen3FrLink.personSteps) as an Emerald script; `nurse`
-- is Emerald's own nurse script (for { "nurse", localId }).
function M.personOps(steps,nurse)
    if steps[1] and steps[1][1]=="nurse" then
      local target=nurse
      if not target then return nil end
      -- pokeemerald data/maps/OldaleTown_PokemonCenter_1F/scripts.inc
      return {{op="setvar",opcode=22,[1]=0x800B,[2]=steps[1][2] or 1,var=0x800B,value=steps[1][2] or 1},
        {op="call",opcode=4,[1]=target,target=target},{op="waitmessage",opcode=102},
        {op="waitbuttonpress",opcode=109},{op="release",opcode=108},{op="end",opcode=2}}
    end
    local ops={{op="lock",opcode=106},{op="faceplayer",opcode=90}}
    for _,st in ipairs(steps) do
      local key=st[2] and (M.MAP..st[2])
      if st[1]=="text" then
        ops[#ops+1]={op="loadword",opcode=15,[1]=0,[2]=key,dest=0,value=key}
        ops[#ops+1]={op="callstd",opcode=9,[1]=4,std=4}
      elseif st[1]=="say" then
        ops[#ops+1]={op="message",opcode=103,[1]=key,ptr=key}
        ops[#ops+1]={op="waitmessage",opcode=102}
      elseif st[1]=="mart" then
        ops[#ops+1]={op="pokemart",opcode=134,[1]=key,items=key,ptr=key}
      end
    end
    if ops[#ops].op=="waitmessage" then ops[#ops+1]={op="waitbuttonpress",opcode=109} end
    ops[#ops+1]={op="release",opcode=108}
    ops[#ops+1]={op="end",opcode=2}
    return ops
  end

function M.install(mod,cfg)
  local CacheFs=require("src.import.CacheFs")
  local prefix=M.find(CacheFs.readAt)
  if not prefix then error(cfg.message,0) end
  local function read(rel) return CacheFs.readAt(prefix..rel) end
  local function lua(rel)
    local bytes=read(rel)
    local chunk=bytes and load(bytes,"="..rel,"t",{})
    if not chunk then return nil end
    local ok,value=pcall(chunk)
    return ok and type(value)=="table" and value or nil
  end
  local Runtime=require("src.mods.Runtime")
  local T=require("src.core.game3.tileset_native")
  local Layout=require("src.core.game3.layout_native")
  local NativePack=require("src.import.gba.native_pack")
  local Interactions=require("src.core.game3.scripting.interaction_scripts")
  local Encounters=require("src.core.game3.encounters")
  local NATIVE="data/generated/gba/native"

  -- Tiles and tile animations: frlg__ tileset folders read from the import.
  -- Atlases baked from them are not written anywhere.
  local function proxy(cache)
    if type(cache)~="table" or rawget(cache,"_editorFrLink") then return cache end
    return setmetatable({_editorFrLink=true},{__index=function(self,k)
      local v=cache[k]
      if type(v)~="function" then return v end
      return function(me,p,...)
        if me==self then me=cache end
        local fr=M.redirect(p)
        if fr then
          if k=="read" then return read(fr) end
          if k=="exists" then return read(fr)~=nil end
          if k=="write" then return false end
        end
        return v(me,p,...)
      end
    end})
  end
  local okA,Anim=pcall(require,"src.core.game3.tileset_anim")
  local function proxyAll()
    T._cache=proxy(T._cache)
    if okA and Anim then Anim._cache=proxy(Anim._cache) end
  end
  if not T._editorFrLinkDispatch then
    T._editorFrLinkDispatch=true
    local install=T.install
    T.install=function(...) return Runtime.call("editor.gen3.frlink.tiles",install,...) end
  end
  -- The engine builds its texture stream from the cache it is given when
  -- install runs (newer engines read tilesets through it, not through
  -- T._cache), so the proxy goes in first; and when install already ran,
  -- the stream is rebuilt on the proxy.
  mod.hooks:wrap("editor.gen3.frlink.tiles",function(proceed,cache,...)
    local a,b=proceed(proxy(cache),...);proxyAll();return a,b
  end)
  proxyAll()
  if T._cache and T._stream and T.invalidate then pcall(T.invalidate) end

  -- Tile animations (water, sand edges, flowers). Emerald runs its own
  -- animation clock and only steps Emerald's tilesets, so FireRed's are
  -- stepped here on FireRed's clock (pokefirered tileset_anims.c:223) --
  -- the same frames and timing as in FireRed.
  if okA and Anim and Anim.step and Anim._applyKind then
    if not Anim._editorFrLinkAnim then
      Anim._editorFrLinkAnim=true
      local step=Anim.step
      Anim.step=function(...) return Runtime.call("editor.gen3.frlink.anim",step,...) end
    end
    local okV,Versions=pcall(require,"src.import.gba.versions")
    local counter=0
    mod.hooks:wrap("editor.gen3.frlink.anim",function(proceed,...)
      local a,b=proceed(...)
      -- without Emerald's clock the stock step already animates them
      if not Anim._rse or Anim._enabled==false or (okV and Versions and Versions.TILESET_ANIM==false) then return a,b end
      -- FireRed's frame numbers live where the stock code keeps them (it
      -- leaves them alone while Emerald's clock runs), so re-binding a
      -- tileset shows the current frame, not frame 0
      counter=(counter+1)%640
      if counter%8==0 then Anim._sandFrame=math.floor(counter/8)%8 end
      if counter%16==1 then Anim._waterFrame=math.floor(counter/16)%8 end
      if counter%16==2 then Anim._flowerFrame=math.floor(counter/16)%5 end
      for pair in pairs(Anim._visible or {}) do
        local entry=type(pair)=="string" and pair:sub(1,#M.PAIR)==M.PAIR and Anim._pairs[pair]
        if entry and not entry.rse then
          Anim._applyKind(entry,"sand",Anim._sandFrame)
          Anim._applyKind(entry,"water",Anim._waterFrame)
          Anim._applyKind(entry,"flower",Anim._flowerFrame)
        end
      end
      return a,b
    end)
  end

  -- Doors. Emerald looks its door animations up by Emerald tileset, so a
  -- door on a FireRed tileset had none: FireRed's own door table and door
  -- pictures (from the import) are used for those, the way FireRed does it
  -- (pokefirered field_door.c): the block's door entry, on a warp-door tile.
  local okDoors,Doors=pcall(require,"src.core.game3.doors")
  if okDoors and type(Doors)=="table" and Doors.getDoorEntryAt then
    local frDoors
    local function doorTable()
      if frDoors==nil then frDoors=lua("data/generated/gba/doors/manifest.lua") or false end
      return frDoors or nil
    end
    local function isFr(pair) return type(pair)=="string" and pair:sub(1,#M.PAIR)==M.PAIR end
    -- (package.loaded isn't a mod's to read; these are loaded by now anyway)
    local function engine(name) local ok,m=pcall(require,name) return ok and m or nil end
    local function layoutFor(mapId)
      if mapId==nil then return nil end
      local key=tostring(mapId):gsub("^FR_",""):gsub("^MAP_","")
      local cached=Doors._layoutCache and Doors._layoutCache[key]
      if cached then return cached,cached.pair end
      local Map=engine("src.core.game3.map")
      local Collision=engine("src.core.game3.collision")
      local cur=Collision and Collision._mapDef
      if cur and cur.midLayout and Map and Map.current==mapId then return cur.midLayout,cur.pair end
      if Map and Map._def and Map._def.midLayout and Map.current==mapId then return Map._def.midLayout,Map._def.pair end
      for _,n in ipairs(Map and Map.neighborList or {}) do
        if (n.map or n.mapId)==mapId and n.def and n.def.midLayout then return n.def.midLayout,n.def.pair end
      end
      local R=engine("src.core.game3.runtime")
      local maps=R and R._game and R._game.data and R._game.data.maps
      local def=maps and maps[mapId]
      if def and def.midLayout then return def.midLayout,def.pair end
    end
    -- the door's picture, ready for Doors.draw (it keeps pictures by file)
    local function sheet(file,info)
      Doors._sheets=Doors._sheets or {}
      if Doors._sheets[file]~=nil then return end
      local bytes=read("data/generated/gba/doors/"..info.file)
      local ok,img=false,nil
      if bytes and #bytes>=info.width*info.height*4 and love and love.image and love.graphics then
        ok,img=pcall(function()
          local data=love.image.newImageData(info.width,info.height,"rgba8",bytes:sub(1,info.width*info.height*4))
          local image=love.graphics.newImage(data);image:setFilter("nearest","nearest");return image
        end)
      end
      if not ok or not img then Doors._sheets[file]=false;return end
      local quads={}
      for f=0,info.frames-1 do
        quads[f]=love.graphics.newQuad(0,f*info.frame_height,info.frame_width,info.frame_height,info.width,info.height)
      end
      Doors._sheets[file]={image=img,quads=quads,width=info.width,height=info.height,
        frame_width=info.frame_width,frame_height=info.frame_height,frames=info.frames}
    end
    local function doorAt(mapId,x,y)
      local layout,pair=layoutFor(mapId)
      pair=pair or (layout and layout.pair)
      if not (layout and layout.midAt and isFr(pair) and x and y) then return nil end
      local man=doorTable()
      local mid=layout:midAt(x,y)
      local row=man and man.by_mid and mid and man.by_mid[mid]
      local info=row and man.doors and man.doors[row.tile]
      if not info then return nil end
      local okC,Collision=pcall(require,"src.core.game3.collision")
      local beh=okC and Collision and Collision.behaviorOn and Collision.behaviorOn({midLayout=layout,pair=pair},x,y)
      if beh~=nil and beh~=0x69 then return nil end -- MB_WARP_DOOR
      local file="frlg_doors/"..info.file
      sheet(file,info)
      local entry={}
      for k,v in pairs(row) do entry[k]=v end
      entry.tile,entry.file=M.PAIR..row.tile,file
      return entry,info
    end
    if not Doors._editorFrLinkDispatch then
      Doors._editorFrLinkDispatch=true
      local lookup=Doors.getDoorEntryAt
      Doors.getDoorEntryAt=function(...) return Runtime.call("editor.gen3.frlink.doors",lookup,...) end
    end
    mod.hooks:wrap("editor.gen3.frlink.doors",function(proceed,mapId,x,y)
      local R=engine("src.core.game3.runtime")
      local session=R and R.getSession and R.getSession()
      local Map=engine("src.core.game3.map")
      local live=(session and session.map) or (Map and Map.current)
      local e,i
      if live then e,i=doorAt(live,x,y) end
      if not e and live~=mapId then e,i=doorAt(mapId,x,y) end
      if e then return e,i end
      return proceed(mapId,x,y)
    end)
  end

  -- Behaviours and wild encounter types of the import's tilesets.
  local pack
  local function objects()
    if pack==nil then pack=lua("data/generated/gba/objects/pack.lua") or false end
    return pack or nil
  end
  local function rows(all,kind)
    local p=objects()
    if type(all)~="table" or not p then return end
    for base,row in pairs(p[kind] or {}) do all[M.PAIR..base]=row end
  end
  if not Interactions._editorFrLinkDispatch then
    Interactions._editorFrLinkDispatch=true
    local install=Interactions.install
    Interactions.install=function(...) return Runtime.call("editor.gen3.frlink.behaviors",install,...) end
  end
  mod.hooks:wrap("editor.gen3.frlink.behaviors",function(proceed,...)
    local a,b=proceed(...);rows(Interactions.behaviors,"behaviors");return a,b
  end)
  if not Encounters._editorFrLinkDispatch then
    Encounters._editorFrLinkDispatch=true
    local install=Encounters.installEncounterTypes
    Encounters.installEncounterTypes=function(...) return Runtime.call("editor.gen3.frlink.encounters",install,...) end
  end
  mod.hooks:wrap("editor.gen3.frlink.encounters",function(proceed,...)
    local a,b=proceed(...);rows(Encounters._encounterTypes,"encounterTypes");return a,b
  end)
  rows(Interactions.behaviors,"behaviors")
  rows(Encounters._encounterTypes,"encounterTypes")

  -- FireRed's shelves, dressers, trash bins, signs and the like: Emerald has
  -- no interaction for these tiles. cfg.furniture gives each behaviour's id
  -- (as text) its script ("frlg:furn:<id>", built from the cfg.signs steps)
  -- and whether it only reads when the player faces up.
  if cfg.furniture and next(cfg.furniture) then
    if not Interactions._editorFrLinkScript then
      Interactions._editorFrLinkScript=true
      local base=Interactions.scriptFor
      Interactions.scriptFor=function(...) return Runtime.call("editor.gen3.frlink.furniture",base,...) end
    end
    mod.hooks:wrap("editor.gen3.frlink.furniture",function(proceed,behavior,facing,...)
      local key=proceed(behavior,facing,...)
      if key then return key end
      local row=behavior and cfg.furniture[tostring(behavior)]
      if not row then return nil end
      if row.facing=="up" and facing~="up" and facing~=2 then return nil end
      return row.script
    end)
  end

  -- Import region: FireRed's wild Pokemon on the EM_KANTO_ maps (the
  -- species numbers are the same in both games). The mod's own lists win.
  if cfg.wild then
    local wild
    local function fillWild()
      local all=Encounters._tables
      if type(all)~="table" then return end
      if wild==nil then wild=lua("data/generated/gba/encounters.lua") or false end
      for key,t in pairs(wild or {}) do
        if type(key)=="string" and (key:sub(1,3)=="FR_" or key:sub(1,6)=="SEVII_") then
          local id=M.REGION..key:gsub("^FR_","")
          if all[id]==nil then all[id]=t end
        end
      end
    end
    if not Encounters._editorFrLinkWild then
      Encounters._editorFrLinkWild=true
      local base=Encounters.loadFromMod
      Encounters.loadFromMod=function(...) return Runtime.call("editor.gen3.frlink.wild",base,...) end
    end
    mod.hooks:wrap("editor.gen3.frlink.wild",function(proceed,...)
      local a,b=proceed(...);fillWild();return a,b
    end)
    fillWild()
  end

  -- Signs (Import region): each is rebuilt from its steps (Gen3FrLink
  -- signSteps) as an Emerald script "frlg:g3:…", made the first time it's
  -- read; its words come from the import's texts, loaded on first use.
  local people=cfg.people and next(cfg.people) and cfg.people or nil
  if (cfg.signs and next(cfg.signs)) or people then
    local signs=cfg.signs or {}
    local frText
    local function texts()
      if frText==nil then
        frText=lua("data/generated/gba/scripts/text.lua") or false
        -- the import's named scripts (furniture and the like) keep their words in its pack
        if frText then
          setmetatable(frText,{__index=function(_,k)
            local p=objects()
            return p and type(p.text)=="table" and p.text[k] or nil
          end})
        end
      end
      return frText or nil
    end
    -- Emerald's nurse script, the one its own Pokemon Center nurses call
    -- (found from Oldale's, so it follows the player's Emerald).
    local nurseKey
    local function emeraldNurse(Space)
      if nurseKey==nil then
        nurseKey=false
        local R=package.loaded["src.core.game3.runtime"] or select(2,pcall(require,"src.core.game3.runtime"))
        local game=type(R)=="table" and R._game
        local maps=type(game)=="table" and game.data and game.data.maps or {}
        local def=maps.EM_OLDALE_TOWN_POKEMON_CENTER_1F
        for _,o in ipairs(def and def.objects or {}) do
          for _,op in ipairs(Space.bundle.scripts[o.scriptKey] or {}) do
            if op.op=="call" and op.target and not nurseKey then nurseKey=op.target end
          end
        end
      end
      return nurseKey or nil
    end
    local function chain(t,look)
      local mt=getmetatable(t) or {}
      local before=mt.__index
      mt.__index=function(tbl,k)
        if type(k)=="string" and k:sub(1,#M.MAP)==M.MAP then
          local v=look(k:sub(#M.MAP+1),k)
          if v~=nil then rawset(tbl,k,v);return v end
        end
        if type(before)=="function" then return before(tbl,k) end
        if type(before)=="table" then return before[k] end
      end
      setmetatable(t,mt)
    end
    mod.events:on("game.ready",function()
      local okS,Space=pcall(require,"src.core.game3.scripting.space")
      local bundle=okS and Space and (Space.bundle or Space.ensureBundle(nil))
      if not (bundle and type(bundle.scripts)=="table" and type(bundle.text)=="table") or bundle._editorFrSigns then return end
      bundle._editorFrSigns=true
      chain(bundle.scripts,function(_,full)
        local steps=signs[full]
        if steps then return M.signOps(steps) end
        steps=people and people[full]
        return steps and M.personOps(steps,emeraldNurse(Space))
      end)
      chain(bundle.text,function(key) local t=texts() return t and t[key] end)
    end)
  end

  -- People: FireRed's own sprites from the import, as graphics ids
  -- FRGFX+<FireRed id> (objects carry frlgGfx; their graphicsId is an
  -- Emerald look-alike the editor shows), and FireRed's shop lists.
  if people then
    local FRGFX=1000
    local Space=require("src.core.game3.scripting.space")
    local OwSprites=require("src.core.game3.ow_sprites")
    local Objects=require("src.core.game3.objects")
    local Marts=require("src.core.game3.marts")
    if not Space._editorFrLink then
      Space._editorFrLink=true
      local resolve=Space.resolveObjectGraphicsId
      Space.resolveObjectGraphicsId=function(...) return Runtime.call("editor.gen3.frlink.gfx",resolve,...) end
      local get=OwSprites.get
      OwSprites.get=function(...) return Runtime.call("editor.gen3.frlink.sprite",get,...) end
      local spawn=Objects.spawnFromDefs
      Objects.spawnFromDefs=function(...) return Runtime.call("editor.gen3.frlink.spawn",spawn,...) end
      local items=Marts.itemsFor
      Marts.itemsFor=function(...) return Runtime.call("editor.gen3.frlink.mart",items,...) end
    end
    mod.hooks:wrap("editor.gen3.frlink.gfx",function(proceed,obj,...)
      local fr=type(obj)=="table" and tonumber(obj.frlgGfx)
      if fr then return FRGFX+fr end
      return proceed(obj,...)
    end)
    local frCache={read=function(_,path)
      local n=type(path)=="string" and tonumber(path:match("/ow/(%d+)%.")) or nil
      if not (n and n>=FRGFX) then return nil end
      return read(path:gsub("/ow/%d+%.","/ow/"..(n-FRGFX)..".",1))
    end}
    mod.hooks:wrap("editor.gen3.frlink.sprite",function(proceed,gid,...)
      local n=tonumber(gid)
      if not (n and n>=FRGFX) or OwSprites._loaded[n] or not OwSprites._manifest then return proceed(gid,...) end
      local cache=OwSprites._cache
      OwSprites._cache=frCache
      local ok,spr=pcall(proceed,gid,...)
      OwSprites._cache=cache
      return ok and spr or nil
    end)
    -- people on a neighbouring map: ids past Emerald's are hidden there as
    -- "variable" sprites; FireRed's aren't
    mod.hooks:wrap("editor.gen3.frlink.spawn",function(proceed,...)
      local pool=proceed(...)
      for _,eo in pairs(type(pool)=="table" and pool.byId or {}) do
        if type(eo)=="table" and eo.def and eo.def.frlgGfx then eo.invisible=false end
      end
      return pool
    end)
    local marts
    mod.hooks:wrap("editor.gen3.frlink.mart",function(proceed,key,...)
      if type(key)=="string" and key:sub(1,#M.MAP)==M.MAP then
        if marts==nil then
          marts={}
          for _,e in pairs(((lua("data/generated/gba/scripts/marts.lua") or {}).marts) or {}) do
            if type(e)=="table" and e.key and type(e.items)=="table" then marts[e.key]=e end
          end
        end
        local e=marts[key:sub(#M.MAP+1)]
        if e then return e.items,e end
        return nil
      end
      return proceed(key,...)
    end)
  end

  -- Respawns (People, marts & nurses): walking into a Kanto Pokemon Center
  -- makes it the place a blackout (or Teleport) returns to, as FireRed's
  -- own centers do -- in front of its nurse, where FireRed puts the player.
  -- Which maps and where comes from the import's heal locations.
  if cfg.respawn then
    local centers
    local function center(mapId)
      if type(mapId)~="string" or mapId:sub(1,#M.REGION)~=M.REGION then return nil end
      if centers==nil then
        centers={}
        local pack=lua("data/generated/gba/region_map/heal_locations.lua") or {}
        for _,row in pairs(type(pack.whiteout)=="table" and pack.whiteout or {}) do
          if type(row)=="table" and type(row.map)=="string" and row.map:find("POKE",1,true) then
            centers[M.REGION..row.map:gsub("^FR_","")]={x=tonumber(row.x) or 7,y=tonumber(row.y) or 4,healer=tonumber(row.healerLocalId)}
          end
        end
      end
      return centers[mapId]
    end
    local Field=require("src.core.game3.field")
    mod.events:on("map.entered",function(e)
      local spot=center(type(e)=="table" and e.mapId)
      local session=spot and Field._session
      if not session then return end
      session.healMap,session.healX,session.healY,session.healHealerLocalId=e.mapId,spot.x,spot.y,spot.healer
    end)
    -- Emerald turns the player to face down after a blackout (its respawn
    -- points are outdoors); in a Kanto center they face the nurse.
    if not Field._editorFrLinkRespawn then
      Field._editorFrLinkRespawn=true
      local respawn=Field.respawnAtHeal
      Field.respawnAtHeal=function(...) return Runtime.call("editor.gen3.frlink.respawn",respawn,...) end
    end
    mod.hooks:wrap("editor.gen3.frlink.respawn",function(proceed,opts,...)
      local a,b=proceed(opts,...)
      local session=Field._session
      local spot=session and not (type(opts)=="table" and opts.warp) and center(session.healMap)
      if spot then
        local okP,Player=pcall(require,"src.core.game3.player")
        if okP and Player and Player.reset then
          Player.reset(session.healX or spot.x,session.healY or spot.y,"up")
          if Player.syncToHost then Player.syncToHost(Field._game) end
        end
      end
      return a,b
    end)
  end

  -- FireRed map layouts, for Gen3Map's map layouts ("frlg:FR_…" sources).
  local manifest,layouts
  Layout._editorFrLink={
    layout=function(source)
      if type(source)~="string" or source:sub(1,#M.MAP)~=M.MAP then return nil end
      local id=source:sub(#M.MAP+1)
      layouts=layouts or {}
      if layouts[id]==nil then
        manifest=manifest or lua(NATIVE.."/manifest.lua") or {}
        local info=(manifest.layouts or {})[id]
        local blob=info and read(NATIVE.."/"..(info.file or ("layouts/"..id..".mid")))
        local decoded=blob and NativePack.decodeMidLayout(blob)
        layouts[id]=decoded and Layout.fromDecoded(decoded,id,M.PAIR..info.pair) or false
      end
      return layouts[id] or nil
    end,
  }
end

return M
