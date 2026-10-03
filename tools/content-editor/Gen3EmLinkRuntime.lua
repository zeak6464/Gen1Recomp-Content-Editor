-- Export source (not bytecode) for Emerald Maps (Gen3EmLink): the game side
-- of a FireRed / LeafGreen mod that uses Emerald tilesets, maps and wild
-- Pokemon -- Hoenn in a Kanto game.
--
-- The mod carries names only: tilesets "em__<Emerald tileset>" and map
-- layouts "em:<Emerald map>". Everything they point at is read here, on the
-- player's machine, from the player's own Emerald import (the runtime's
-- emerald/ cache). Without one the mod stops loading with a message, so
-- nothing Emerald-made ever shows up half there.
--
-- Nothing in the engine is changed. The tileset caches get a proxy that sends
-- native/em__<pair>/ reads to that import, Emerald's tile animations run on
-- Emerald's clock next to FireRed's, the behaviour and wild encounter tables
-- get the import's rows for those tilesets (the games share the engine's
-- numbering), door animations, people's pictures, shop lists and the names of
-- places come from the import too, and Gen3Map asks
-- `LayoutNative._editorEmLink.layout(source)` for Emerald layouts.
local M={}
M.PAIR="em__"
M.MAP="em:"
M.REGION="FR_HOENN_"
M.SECTION=1000 -- region map section ids from Emerald are carried as 1000+id

-- The player's Emerald import: "emerald/", or nil. Only a finished import of
-- a known dump counts.
function M.find(readAt)
  local GV=require("src.core.GameVersion")
  local prefix=GV.cachePrefix("emerald")
  local okR,marker=pcall(readAt,prefix.."rom-cache.complete")
  local sha=okR and type(marker)=="string" and marker:match("^rom%-cache%-v%d+%-emerald:(%x+)")
  if sha then
    for _,rev in ipairs(GV.revisions("emerald")) do
      if rev.sha1==sha:lower() then return prefix,"emerald" end
    end
  end
end

--- "…/native/em__X/…" -> "…/native/X/…", or nil for other paths.
function M.redirect(path)
  if type(path)~="string" then return nil end
  local out,n=path:gsub("/native/"..M.PAIR.."([^/]+)/","/native/%1/",1)
  return n>0 and out or nil
end

--- A sign's steps (Gen3EmLink.signSteps) as a script of the game's own.
function M.signOps(steps)
  local ops={{op="lockall",opcode=105}}
  for _,st in ipairs(steps) do
    local key=st[2] and (M.MAP..st[2])
    if st[1]=="text" then
      ops[#ops+1]={op="loadword",opcode=15,[1]=0,[2]=key,dest=0,value=key}
      ops[#ops+1]={op="callstd",opcode=9,[1]=4,std=4}
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

--- A person's steps (Gen3EmLink.personSteps) as a script; `nurse` is the
-- game's own Pokemon Center nurse script (for { "nurse", localId }).
function M.personOps(steps,nurse)
  if steps[1] and steps[1][1]=="nurse" then
    local target=nurse
    if not target then return nil end
    -- pokefirered data/maps/ViridianCity_PokemonCenter_1F/scripts.inc
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
  -- (package.loaded isn't a mod's to read; these are loaded by now anyway)
  local function engine(name) local ok,m=pcall(require,name) return ok and m or nil end

  -- Tiles and tile animations: em__ tileset folders read from the import.
  -- Atlases baked from them are not written anywhere.
  local function proxy(cache)
    if type(cache)~="table" or rawget(cache,"_editorEmLink") then return cache end
    return setmetatable({_editorEmLink=true},{__index=function(self,k)
      local v=cache[k]
      if type(v)~="function" then return v end
      return function(me,p,...)
        if me==self then me=cache end
        local em=M.redirect(p)
        if em then
          if k=="read" then return read(em) end
          if k=="exists" then return read(em)~=nil end
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
  if not T._editorEmLinkDispatch then
    T._editorEmLinkDispatch=true
    local install=T.install
    T.install=function(...) return Runtime.call("editor.gen3.emlink.tiles",install,...) end
  end
  -- (the proxy goes in before install builds the engine's texture stream;
  -- see Gen3FrLinkRuntime)
  mod.hooks:wrap("editor.gen3.emlink.tiles",function(proceed,cache,...)
    local a,b=proceed(proxy(cache),...);proxyAll();return a,b
  end)
  proxyAll()
  if T._cache and T._stream and T.invalidate then pcall(T.invalidate) end

  -- Tile animations. The first Emerald tileset on screen starts Emerald's own
  -- animation clock, and while it runs the stock step only moves Emerald's
  -- tilesets -- so FireRed's (water, sand edges, flowers) are stepped here on
  -- FireRed's clock (pokefirered tileset_anims.c:223), the same frames and
  -- timing as before.
  if okA and Anim and Anim.step and Anim._applyKind then
    if not Anim._editorEmLinkAnim then
      Anim._editorEmLinkAnim=true
      local step=Anim.step
      Anim.step=function(...) return Runtime.call("editor.gen3.emlink.anim",step,...) end
    end
    local okV,Versions=pcall(require,"src.import.gba.versions")
    local counter=0
    mod.hooks:wrap("editor.gen3.emlink.anim",function(proceed,...)
      local a,b=proceed(...)
      if not Anim._rse or Anim._enabled==false or (okV and Versions and Versions.TILESET_ANIM==false) then return a,b end
      counter=(counter+1)%640
      if counter%8==0 then Anim._sandFrame=math.floor(counter/8)%8 end
      if counter%16==1 then Anim._waterFrame=math.floor(counter/16)%8 end
      if counter%16==2 then Anim._flowerFrame=math.floor(counter/16)%5 end
      for pair in pairs(Anim._visible or {}) do
        local entry=Anim._pairs[pair]
        if entry and not entry.rse then
          Anim._applyKind(entry,"sand",Anim._sandFrame)
          Anim._applyKind(entry,"water",Anim._waterFrame)
          Anim._applyKind(entry,"flower",Anim._flowerFrame)
        end
      end
      return a,b
    end)
  end

  -- Doors. FireRed looks its door animations up by block, in its own table; a
  -- door on an Emerald tileset had none. Emerald's door table and door
  -- pictures (from the import) are used for those, the way Emerald does it
  -- (pokeemerald field_door.c): the tileset pair's door for the block, on a
  -- door tile.
  local okDoors,Doors=pcall(require,"src.core.game3.doors")
  if okDoors and type(Doors)=="table" and Doors.getDoorEntryAt then
    local emDoors
    local function doorTable()
      if emDoors==nil then emDoors=lua("data/generated/gba/doors/manifest.lua") or false end
      return emDoors or nil
    end
    local function isEm(pair) return type(pair)=="string" and pair:sub(1,#M.PAIR)==M.PAIR end
    local function norm(name) return (tostring(name or ""):gsub("^gTileset_",""):gsub("_",""):lower()) end
    local pairIndex
    local function pairDoors(man,pair)
      if not pairIndex then
        pairIndex={}
        for _,row in pairs(man.pairs or {}) do
          if type(row)=="table" then pairIndex[norm(row.primary).."|"..norm(row.secondary)]=row.doors end
        end
      end
      local a,b=pair:match("^(.-)__(.+)$")
      return a and pairIndex[norm(a).."|"..norm(b)] or nil
    end
    local function layoutFor(mapId)
      if mapId==nil then return nil end
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
      if not (layout and layout.midAt and isEm(pair) and x and y) then return nil end
      local man=doorTable()
      local mid=layout:midAt(x,y)
      local doors=man and mid and pairDoors(man,pair:sub(#M.PAIR+1))
      local row=doors and doors[mid]
      local info=row and man.doors and man.doors[row.tile]
      if not info then return nil end
      local Collision=engine("src.core.game3.collision")
      local beh=Collision and Collision.behaviorOn and Collision.behaviorOn({midLayout=layout,pair=pair},x,y)
      -- MB_ANIMATED_DOOR, MB_PETALBURG_GYM_DOOR
      if beh~=nil and beh~=0x69 and beh~=0x8D then return nil end
      local file="em_doors/"..row.file
      sheet(file,{file=row.file,width=info.width,height=info.height,frames=info.frames,
        frame_width=info.frame_width,frame_height=info.frame_height})
      local entry={mid=mid,index=row.index,tile=M.PAIR..row.tile,file=file,sound=row.sound,
        size=tonumber(row.size_type)==2 and "2x2" or "1x2",size_type=row.size_type}
      return entry,info
    end
    if not Doors._editorEmLinkDispatch then
      Doors._editorEmLinkDispatch=true
      local lookup=Doors.getDoorEntryAt
      Doors.getDoorEntryAt=function(...) return Runtime.call("editor.gen3.emlink.doors",lookup,...) end
    end
    mod.hooks:wrap("editor.gen3.emlink.doors",function(proceed,mapId,x,y)
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
  -- Emerald-only behaviours FireRed has an equal of: deep sand acts as sand
  -- (footprints) and long grass as tall grass (the wild grass effect). The
  -- tiles' collision is already baked into the layouts.
  local alias
  local function aliases()
    if alias==nil then
      alias=false
      local MB=engine("src.core.game3.mb")
      if type(MB)=="table" and MB.id then
        alias={}
        for from,to in pairs({DEEP_SAND="SAND",LONG_GRASS="TALL_GRASS",LONG_GRASS_SOUTH_EDGE="TALL_GRASS"}) do
          local a,b=MB.id(from),MB.id(to)
          if a and b and a~=b then alias[a]=b end
        end
      end
    end
    return alias or nil
  end
  local function rows(all,kind)
    local p=objects()
    if type(all)~="table" or not p then return end
    local map=kind=="behaviors" and aliases() or nil
    for base,row in pairs(p[kind] or {}) do
      if map then
        local copy={}
        for k,v in pairs(row) do copy[k]=map[v] or v end
        row=copy
      end
      all[M.PAIR..base]=row
    end
  end
  if not Interactions._editorEmLinkDispatch then
    Interactions._editorEmLinkDispatch=true
    local install=Interactions.install
    Interactions.install=function(...) return Runtime.call("editor.gen3.emlink.behaviors",install,...) end
  end
  mod.hooks:wrap("editor.gen3.emlink.behaviors",function(proceed,...)
    local a,b=proceed(...);rows(Interactions.behaviors,"behaviors");return a,b
  end)
  if not Encounters._editorEmLinkDispatch then
    Encounters._editorEmLinkDispatch=true
    local install=Encounters.installEncounterTypes
    Encounters.installEncounterTypes=function(...) return Runtime.call("editor.gen3.emlink.encounters",install,...) end
  end
  mod.hooks:wrap("editor.gen3.emlink.encounters",function(proceed,...)
    local a,b=proceed(...);rows(Encounters._encounterTypes,"encounterTypes");return a,b
  end)
  rows(Interactions.behaviors,"behaviors")
  rows(Encounters._encounterTypes,"encounterTypes")

  -- Emerald's shelves, vases, trash cans and the like: FireRed has no
  -- interaction for these tiles. cfg.furniture gives each behaviour's id (as
  -- text) its script key ("em:furn:<id>"), built from the cfg.signs steps.
  if cfg.furniture and next(cfg.furniture) then
    if not Interactions._editorEmLinkScript then
      Interactions._editorEmLinkScript=true
      local base=Interactions.scriptFor
      Interactions.scriptFor=function(...) return Runtime.call("editor.gen3.emlink.furniture",base,...) end
    end
    mod.hooks:wrap("editor.gen3.emlink.furniture",function(proceed,behavior,...)
      local key=proceed(behavior,...)
      if key then return key end
      return behavior and cfg.furniture[tostring(behavior)] or nil
    end)
  end

  -- Import region: Emerald's wild Pokemon on the FR_HOENN_ maps (the species
  -- numbers are the same in both games). cfg.wild names each map's list in the
  -- import ("group:number"). The mod's own lists win.
  if cfg.wild and next(cfg.wild) then
    local wild
    local function fillWild()
      local all=Encounters._tables
      if type(all)~="table" then return end
      if wild==nil then wild=lua("data/generated/gba/encounters.lua") or false end
      for id,key in pairs(cfg.wild) do
        if all[id]==nil and wild and wild[key] then all[id]=wild[key] end
      end
    end
    if not Encounters._editorEmLinkWild then
      Encounters._editorEmLinkWild=true
      local base=Encounters.loadFromMod
      Encounters.loadFromMod=function(...) return Runtime.call("editor.gen3.emlink.wild",base,...) end
    end
    mod.hooks:wrap("editor.gen3.emlink.wild",function(proceed,...)
      local a,b=proceed(...);fillWild();return a,b
    end)
    fillWild()
  end

  -- Signs and people (Import region): each is rebuilt from its steps
  -- (Gen3EmLink signSteps / personSteps) as a script "em:g3:…", made the
  -- first time it's read; its words come from the import's texts, loaded on
  -- first use.
  local people=cfg.people and next(cfg.people) and cfg.people or nil
  if (cfg.signs and next(cfg.signs)) or people then
    local signs=cfg.signs or {}
    local emText
    local function texts()
      if emText==nil then emText=lua("data/generated/gba/scripts/text.lua") or false end
      return emText or nil
    end
    -- the game's own nurse script, the one its Pokemon Center nurses call
    local nurseKey
    local function gameNurse(Space)
      if nurseKey==nil then
        nurseKey=false
        local R=engine("src.core.game3.runtime")
        local game=type(R)=="table" and R._game
        local maps=type(game)=="table" and game.data and game.data.maps or {}
        local def=maps.FR_VIRIDIAN_CITY_POKEMON_CENTER_1F
        for _,o in ipairs(def and def.objects or {}) do
          -- OBJ_EVENT_GFX_NURSE: the nurse's script calls the shared one
          if o.sprite=="SPRITE_NURSE" or tonumber(o.graphicsId or o.graphics)==64 then
            for _,op in ipairs(Space.bundle.scripts[o.scriptKey] or {}) do
              if op.op=="call" and op.target and not nurseKey then nurseKey=op.target end
            end
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
      local Space=engine("src.core.game3.scripting.space")
      local bundle=Space and (Space.bundle or Space.ensureBundle(nil))
      if not (bundle and type(bundle.scripts)=="table" and type(bundle.text)=="table") or bundle._editorEmSigns then return end
      bundle._editorEmSigns=true
      chain(bundle.scripts,function(_,full)
        local steps=signs[full]
        if steps then return M.signOps(steps) end
        steps=people and people[full]
        return steps and M.personOps(steps,gameNurse(Space))
      end)
      chain(bundle.text,function(key) local t=texts() return t and t[key] end)
    end)
  end

  -- People: Emerald's own sprites from the import, as graphics ids
  -- EMGFX+<Emerald id> (objects carry emGfx; their graphicsId is a FireRed
  -- look-alike the editor shows), and Emerald's shop lists.
  if people then
    local EMGFX=1000
    local Space=require("src.core.game3.scripting.space")
    local OwSprites=require("src.core.game3.ow_sprites")
    local Objects=require("src.core.game3.objects")
    local Marts=require("src.core.game3.marts")
    if not Space._editorEmLink then
      Space._editorEmLink=true
      local resolve=Space.resolveObjectGraphicsId
      Space.resolveObjectGraphicsId=function(...) return Runtime.call("editor.gen3.emlink.gfx",resolve,...) end
      local get=OwSprites.get
      OwSprites.get=function(...) return Runtime.call("editor.gen3.emlink.sprite",get,...) end
      local spawn=Objects.spawnFromDefs
      Objects.spawnFromDefs=function(...) return Runtime.call("editor.gen3.emlink.spawn",spawn,...) end
      local items=Marts.itemsFor
      Marts.itemsFor=function(...) return Runtime.call("editor.gen3.emlink.mart",items,...) end
    end
    mod.hooks:wrap("editor.gen3.emlink.gfx",function(proceed,obj,...)
      local em=type(obj)=="table" and tonumber(obj.emGfx)
      if em then return EMGFX+em end
      return proceed(obj,...)
    end)
    local emCache={read=function(_,path)
      local n=type(path)=="string" and tonumber(path:match("/ow/(%d+)%.")) or nil
      if not (n and n>=EMGFX) then return nil end
      return read(path:gsub("/ow/%d+%.","/ow/"..(n-EMGFX)..".",1))
    end}
    mod.hooks:wrap("editor.gen3.emlink.sprite",function(proceed,gid,...)
      local n=tonumber(gid)
      if not (n and n>=EMGFX) or OwSprites._loaded[n] or not OwSprites._manifest then return proceed(gid,...) end
      local cache=OwSprites._cache
      OwSprites._cache=emCache
      local ok,spr=pcall(proceed,gid,...)
      OwSprites._cache=cache
      return ok and spr or nil
    end)
    -- people on a neighbouring map: ids past the game's own are hidden there
    -- as "variable" sprites; Emerald's aren't
    mod.hooks:wrap("editor.gen3.emlink.spawn",function(proceed,...)
      local pool=proceed(...)
      for _,eo in pairs(type(pool)=="table" and pool.byId or {}) do
        if type(eo)=="table" and eo.def and eo.def.emGfx then eo.invisible=false end
      end
      return pool
    end)
    local marts
    mod.hooks:wrap("editor.gen3.emlink.mart",function(proceed,key,...)
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

  -- Respawns (People, marts & nurses): walking into a Hoenn Pokemon Center
  -- makes it the place a blackout (or Teleport) returns to, the way
  -- FireRed's own centers do -- the player wakes in front of its nurse.
  -- cfg.respawn names each center and where its nurse stands.
  if cfg.respawn and next(cfg.respawn) then
    local Field=require("src.core.game3.field")
    mod.events:on("map.entered",function(e)
      local spot=type(e)=="table" and cfg.respawn[e.mapId]
      local session=spot and Field._session
      if not session then return end
      session.healMap,session.healX,session.healY,session.healHealerLocalId=e.mapId,spot.x,spot.y,spot.healer
    end)
  end

  -- Places: the name a map shows when you walk in comes from its region map
  -- section. Emerald's are carried as 1000+id and named from the import.
  local okS,Sections=pcall(require,"src.import.gba.map_sections_extract")
  if okS and type(Sections)=="table" and Sections.getInfo then
    if not Sections._editorEmLink then
      Sections._editorEmLink=true
      local get=Sections.getInfo
      Sections.getInfo=function(...) return Runtime.call("editor.gen3.emlink.places",get,...) end
    end
    local names
    local THEMES={wood=true,marble=true,stone=true,brick=true}
    mod.hooks:wrap("editor.gen3.emlink.places",function(proceed,secId,mapId,floorNum)
      local n=tonumber(secId)
      if n and n>=M.SECTION then
        if names==nil then names=(lua("data/generated/gba/region_map/map_sections.lua") or {}).sections or false end
        local sec=names and names[n-M.SECTION]
        if sec and sec.name then
          local name,floor=sec.name,tonumber(floorNum) or 0
          if floor==127 then name=name.." ROOFTOP"
          elseif floor<0 then name=string.format("%s B%dF",name,-floor)
          elseif floor>0 then name=string.format("%s %dF",name,floor) end
          return {secId=n,id=sec.id,name=name,rawName=sec.name,theme=THEMES[sec.theme] and sec.theme or "stone",
            floorNum=floor,resolved=true}
        end
      end
      return proceed(secId,mapId,floorNum)
    end)
  end

  -- Emerald map layouts, for Gen3Map's map layouts ("em:EM_…" sources).
  local manifest,layouts
  Layout._editorEmLink={
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
