local M={}
function M.used(p)
  if next(p.gen3BattlePositions or {}) then return true end
  if next(p.pokemon or {}) or next((p.gen3 or {}).pokemon or {}) then return true end
  if p.gen3Screens or p.gen3Roamers or p.gen3Fame then return true end
  return next(p.gen3Forms or {}) or p.gen3Fly or next(p.gen3OakScene or {}) or next(p.gen3Oak or {}) or p.gen3Breeding or next(p.gen3Behaviors or {}) or next(p.gen3TrainerMusic or {}) or next(p.items or {}) or next(p.gen3Help or {}) or next(p.gen3Trades or {}) or next(p.gen3Effects or {}) or next(p.gen3BattleRules or {}) or require("Gen3Workbench").used(p) or next(p.gen3Animations or {}) or next(p.gen3Assets or {}) or next(p.gen3Audio or {})
end
function M.emit(p,encode,out)
  require("Gen3TeachyTv").emit(p,encode,out)
  if not M.used(p) then return end
  for path in pairs(p.gen3Assets or {}) do
    if path:match("^data/generated/gba/intro/.*%.png$") then
      out[#out+1]="local introAssets=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3IntroAssetsRuntime.lua")).."\nend)()\nintroAssets.install(mod,"..encode(p.gen3Assets)..")"
      break
    end
  end
  require("Gen3Screens").emit(p,encode,out)
  require("Gen3Fame").emit(p,encode,out)
  require("Gen3Roamers").emit(p,encode,out)
  require("Gen3Forms").emit(p,encode,out)
  require("Gen3Fly").emit(p,encode,out)
  require("Gen3Oak").emit(p,encode,out)
  require("Gen3Workbench").emit(p,encode,out)
  require("Gen3BattleRules").emit(p,encode,out)
  require("Gen3Effects").emit(p,encode,out)
  require("Gen3TrainerMusic").emit(p,encode,out)
  require("Gen3Breeding").emit(p,encode,out)
  require("Gen3Behaviors").emit(p,encode,out)
  require("Gen3Trades").emit(p,encode,out)
  for id,value in pairs(p.gen3Animations or {}) do
    local ok,err=require("Gen3Resources").checkAnimation(id,value);assert(ok,err)
  end
  for path,asset in pairs(p.gen3Assets or {}) do
    assert(path:match("^data/generated/gba/") and not path:find("..",1,true),"Invalid native asset path")
    assert(type(asset.file)=="string" and asset.file:match("^assets/") and not asset.file:find("..",1,true),"Invalid mod asset path")
    if asset.ow then
      local id=tonumber(path:match("^data/generated/gba/ow/(%d+)%.rgba$"))
      assert(id and id<240,"Custom overworld sprites must use an ID below 240")
      assert(type(asset.metaFile)=="string" and asset.metaFile:match("^assets/") and not asset.metaFile:find("..",1,true),"Invalid overworld metadata path")
      for _,key in ipairs({"width","height","frameCount"}) do
        local n=asset.ow[key]
        assert(type(n)=="number" and n%1==0 and n>=1 and n<=(key=="frameCount" and 512 or 256),"Invalid overworld frame layout")
      end
    end
  end
  for section,entries in pairs(p.gen3Audio or {}) do
    assert(section=="songs" or section=="sounds" or section=="cries" or section=="mapSongs","Invalid audio section")
    for id,value in pairs(entries) do
      assert(type(id)=="string","Audio IDs must be strings")
      if type(value)=="table" then
        assert(section~="mapSongs" and type(value.file)=="string" and value.file:match("^assets/") and not value.file:find("..",1,true),"Invalid imported audio path")
        assert(value.loop==nil or type(value.loop)=="boolean","Audio loop must be true or false")
      else assert(type(value)=="number" and value%1==0 and value>=0 and value<=65535,"Audio remaps need an integer ID") end
    end
  end
  out[#out+1]="  local native = "..encode({items=p.items or {},help=p.gen3Help or {},animations=p.gen3Animations or {},assets=p.gen3Assets or {},audio=p.gen3Audio or {}})
  out[#out+1]=M.source
end
M.source=[=[
  local Runtime = require("src.mods.Runtime")
  local Cache = require("src.import.CacheFs")
  local function invalidateNativeImages()
    require("src.core.game3.pokemon")._icons={}
    local cache=require("src.core.game3.dataset").cache()
    local Anim=require("src.core.game3.battle.anim")
    Anim._packLoaded=false;Anim._pack=nil
    for _,name in ipairs({"party_chrome","bag_chrome","battle_chrome","battle_transition_chrome","pokedex_chrome","summary_chrome","shop_chrome","naming_chrome"}) do
      local module=require("src.ui.game3."..name)
      if module.install then module.install(cache) end
    end
    local TrainerPic=require("src.core.game3.trainer_pic");TrainerPic._front={};TrainerPic._back={}
    require("src.core.game3.items_data").install(cache)
    require("src.ui.game3.help_system").install(cache)
    local map=require("src.ui.game3.region_map");map._images={}
    local teachy=package.loaded["src.ui.game3.teachy_tv"]
    if teachy and teachy.reloadAssets then teachy.reloadAssets() end
    local bytes=cache:read("data/generated/gba/region_map/kanto_map.png")
    if bytes and love and love.graphics then
      local ok,img=pcall(function() return love.graphics.newImage(love.filesystem.newFileData(bytes,"map.png")) end)
      if ok then img:setFilter("nearest","nearest");map._images.kanto_map=img end
    end
    require("src.ui.game3.chrome").invalidate()
    require("src.ui.game3.frlg_font").invalidate()
    require("src.core.game3.ow_sprites").install(cache)
    require("src.core.game3.tileset_native").install(cache)
    require("src.core.game3.field_effects").install(cache)
  end
  if not Runtime._contentEditorLifecycle then
    Runtime._contentEditorLifecycle=true
    for _,name in ipairs({"install","reset"}) do
      local original=Runtime[name]
      Runtime[name]=function(...)
        original(...)
        if Cache._contentEditorInvalidate then
          local reset=Cache._contentEditorInvalidate;Cache._contentEditorInvalidate=nil;reset()
        end
      end
    end
  end
  if next(native.items) or next(native.help) or next(native.assets) or next(native.animations) then Cache._contentEditorInvalidate=invalidateNativeImages end
  -- One process-wide dispatcher; callbacks belong to the loader and disappear
  -- on disable/reload. Never overwrite the extracted cache on disk.
  if not Cache._contentEditorBridge then
    Cache._contentEditorBridge = true
    local read = Cache.read
    Cache.read = function(path) return Runtime.call("editor.gen3.cache", read, path) end
  end
  local function encode(v)
    if type(v)=="string" then return string.format("%q",v) end
    if type(v)~="table" then return tostring(v) end
    local parts={"{"}
    for k,c in pairs(v) do parts[#parts+1]="["..encode(k).."]="..encode(c).."," end
    parts[#parts+1]="}";return table.concat(parts)
  end
  local memo={}
  local customOw={}
  for path,asset in pairs(native.assets) do
    if asset.ow then customOw[tonumber(path:match("/ow/(%d+)%.rgba$"))]=true end
  end
  if next(customOw) then
    local Space=require("src.core.game3.scripting.space")
    if not Space._editorOwDispatch then
      Space._editorOwDispatch=true
      local resolve=Space.resolveObjectGraphicsId
      Space.resolveObjectGraphicsId=function(...) return Runtime.call("editor.gen3.ow.resolve",resolve,...) end
    end
    mod.hooks:wrap("editor.gen3.ow.resolve",function(proceed,obj,neighbor)
      if not obj then return proceed(obj,neighbor) end
      local id=tonumber(obj.graphics or obj.graphicsId)
      if obj.graphicsVar or (id and id>=240 and id<=255) then
        local Flags=require("src.core.game3.scripting.flags")
        local Ctx=require("src.core.game3.scripting.ctx")
        local store=(neighbor and neighbor.store) or Space.store or Flags.newStore()
        local ctx=(Space.vm and Space.vm.ctx) or Ctx.new()
        if obj.graphicsVar then
          local value=Flags.getVar(store,ctx,obj.graphicsVar)
          if type(value)=="number" and value~=0 then id=value end
        end
        if id and id>=240 and id<=255 then
          local varId=Ctx.GFX_VAR_LO+(id-240)
          if neighbor and store.vars[varId]==nil then return proceed(obj,neighbor) end
          id=(tonumber(Flags.getVar(store,ctx,varId)) or 0)%256
        end
      end
      if customOw[id] then return id end
      return proceed(obj,neighbor)
    end)
  end
  mod.hooks:wrap("editor.gen3.cache",function(proceed,path)
    local key=path:gsub("^firered/",""):gsub("^leafgreen/","")
    if not key:match("^data/generated/gba/") then key="data/generated/gba/"..key end
    local asset=native.assets[key]
    if asset then
      if not memo[key] then memo[key]=assert(mod:read(asset.file),"Missing native asset "..asset.file) end
      return memo[key]
    end
    local bytes=proceed(path)
    local owId=key:match("^data/generated/gba/ow/(%d+)%.meta$")
    local owAsset=owId and native.assets["data/generated/gba/ow/"..owId..".rgba"]
    if owAsset and owAsset.ow then
      if not memo[key] then memo[key]=assert(mod:read(owAsset.metaFile),"Missing overworld metadata") end
      return memo[key]
    end
    if key=="data/generated/gba/ow/manifest.lua" then
      if not memo[key] then
        local pack=bytes and assert(loadstring(bytes,"@ow/manifest.lua"))() or {sprites={}}
        pack.sprites=pack.sprites or {}
        local changed=false
        for assetPath,rec in pairs(native.assets) do
          if rec.ow then
            local id=tonumber(assetPath:match("/ow/(%d+)%.rgba$"))
            pack.sprites[id]=rec.ow;pack.total=math.max(pack.total or 0,id+1);changed=true
          end
        end
        if changed then
          local count=0;for _ in pairs(pack.sprites) do count=count+1 end;pack.count=count
          memo[key]="return "..encode(pack)
        end
      end
      return memo[key] or bytes
    end
    if key=="data/generated/gba/pokemon/battle_anims/pack.lua" and next(native.animations) then
      if not memo[key] and bytes then
        local pack=assert(loadstring(bytes,"@animation-pack"))()
        for id,value in pairs(native.animations) do
          local section,k=id:match("^([^/]+)/(.+)$");k=tonumber(k) or k
          pack[section]=pack[section] or {};pack[section][k]=value
        end
        memo[key]="return "..encode(pack)
      end
      return memo[key] or bytes
    end
    if key=="data/generated/gba/items/pack.lua" and next(native.items) and bytes then
      if not memo[key] then
        local pack=assert(loadstring(bytes))()
        for _,row in pairs(native.items) do
          local index=tonumber(row.index);assert(index,"Item number missing")
          local entry=pack.items[index] or {};pack.items[index]=entry
          for k,v in pairs(row) do entry[k]=v end
          pack.count=math.max(pack.count or 0,index+1)
        end
        memo[key]="return "..encode(pack)
      end
      return memo[key]
    end
    if key=="data/generated/gba/help/pack.lua" and next(native.help) and bytes then
      if not memo[key] then
        local pack=assert(loadstring(bytes))()
        for id,row in pairs(native.help) do local g,n=id:match("^(%d+):(%d+)$");assert(g and n,"Invalid Help topic");pack.entries[tonumber(g)][tonumber(n)]=row end
        memo[key]="return "..encode(pack)
      end
      return memo[key]
    end
    return bytes
  end)
  mod.events:on("game.ready",function(ctx)
    local Dataset=require("src.core.game3.dataset")
    local cache=Dataset.cache()
    if next(native.animations) or next(native.assets) then
      local Anim=require("src.core.game3.battle.anim")
      Anim._packLoaded=false;Anim._pack=nil
    end
    if next(native.items) or next(native.help) or next(native.assets) then
      invalidateNativeImages()
    end
    for map,song in pairs(native.audio.mapSongs or {}) do
      if ctx.game.data.maps[map] then ctx.game.data.maps[map].music=song end
    end
  end)
  if next(native.audio) then
    local Audio=require("src.core.game3.audio")
    if not Audio._contentEditorBridge then
      Audio._contentEditorBridge=true
      for _,name in ipairs({"playSong","playSe","playCry","playFanfare"}) do
        local base=Audio[name]
        local function vanilla(...)
          if name=="playSong" and Audio._editorMusic then
            Audio._editorMusic:stop();Audio._editorMusic:release()
            if Audio._bgmSource==Audio._editorMusic then Audio._bgmSource=nil end
            Audio._editorMusic=nil
          end
          return base(...)
        end
        Audio[name]=function(...) return Runtime.call("editor.gen3.audio."..name,vanilla,...) end
      end
      local pump,pause,resume,finish=Audio.pumpBgm,Audio.pauseBgm,Audio.resumeBgm,Audio.endSession
      Audio.pumpBgm=function(...) if not Audio._editorMusic then return pump(...) end end
      Audio.pauseBgm=function(...)
        if not Audio._editorMusic then return pause(...) end
        Audio._bgmPaused=true;Audio._editorMusic:pause()
      end
      Audio.resumeBgm=function(...)
        if not Audio._editorMusic then return resume(...) end
        Audio._bgmPaused=false;Audio._editorMusic:play();Audio.applyGain()
      end
      Audio.endSession=function(...) local result=finish(...);Audio._editorMusic=nil;return result end
      local update=Audio.update
      Audio.update=function(...)
        if Audio._editorMusic and Audio._editorBus~=Runtime.hooks then
          Audio._editorMusic:stop();Audio._editorMusic:release()
          if Audio._bgmSource==Audio._editorMusic then Audio._bgmSource=nil end
          Audio._editorMusic=nil;Audio._currentSong=nil
        end
        return update(...)
      end
    end
    for _,entry in ipairs({{"playSong","songs"},{"playSe","sounds"},{"playCry","cries"},{"playFanfare","songs"}}) do
      local operation,section=entry[1],entry[2]
      mod.hooks:wrap("editor.gen3.audio."..operation,function(proceed,id,...)
        if operation=="playSong" and (id==nil or tonumber(id)==0 or tonumber(id)==65535) then return proceed(id,...) end
        if operation=="playSe" or operation=="playFanfare" then id=require("src.core.game3.se_ids").resolve(id) or id end
        local target=(native.audio[section] or {})[tostring(id)]
        if type(target)~="table" then return proceed(target~=nil and target or id,...) end
        local opts=select(1,...) or {}
        if operation=="playSong" and Audio._editorMusic and Audio._currentSong and Audio._currentSong.id==id and not opts.restart then return true end
        local source=love.audio.newSource(mod.assets:path(target.file),operation=="playSong" and "stream" or "static")
        source:setVolume(section=="songs" and (Audio._bgmVolume or 1) or (Audio._sfxVolume or 1))
        if operation=="playSong" then
          proceed(0)
          if Audio._bgmSource then Audio._bgmSource:release() end
          Audio._bgmSource=source;Audio._editorMusic=source;Audio._editorBus=Runtime.hooks
          Audio._currentSong={id=id,loop=target.loop~=false,duration=source:getDuration(),startedAt=os.clock()}
          Audio._bgmGen=id;Audio._bgmLocal=nil;Audio._bgmPaused=false;Audio._fadeIn=nil;Audio._fadeOut=nil
          source:setLooping(target.loop~=false)
          Audio.applyGain();Audio.applyBgmFilter()
        elseif operation=="playCry" then
          Audio.stopCry();Audio._crySource=source
          Audio._cryUntil=(Audio._cryClock or 0)+source:getDuration()*60
          Audio._duck=85/256;Audio._duckHold=2;Audio.applyGain()
        elseif operation=="playFanfare" then
          Audio._fanfareRestore=Audio._bgmGen;Audio.pauseBgm()
          Audio._fanfareActive=true;Audio._fanfareFrames=source:getDuration()*60
          Audio._fanfareSource=source
          Audio._seSources[#Audio._seSources+1]=source;Audio._seMeta[source]={id=tonumber(id) or id}
        else
          Audio._seSources[#Audio._seSources+1]=source;Audio._seMeta[source]={id=tonumber(id) or id,duckBgm=true}
        end
        source:play();return true
      end)
    end
  end
]=]
return M
