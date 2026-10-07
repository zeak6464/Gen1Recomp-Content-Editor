local M={}
function M.used(p)
  if next(p.gen3BattlePositions or {}) then return true end
  if next(p.pokemon or {}) or next((p.gen3 or {}).pokemon or {}) then return true end
  if p.gen3Screens or p.gen3Roamers or p.gen3Fame or next(p.gen3DexText or {}) or require("Gen3Berries").used(p) then return true end
  return next(p.gen3Forms or {}) or p.gen3Fly or next(p.gen3OakScene or {}) or next(p.gen3Oak or {}) or p.gen3BirchScene or p.gen3Breeding or next(p.gen3Behaviors or {}) or next(p.gen3TrainerMusic or {}) or next(p.items or {}) or next(p.gen3Help or {}) or next(p.gen3Trades or {}) or next(p.gen3Effects or {}) or next(p.gen3BattleRules or {}) or require("Gen3Workbench").used(p) or next(p.gen3Animations or {}) or next(p.gen3Assets or {}) or next(p.gen3Audio or {})
end
function M.emit(p,encode,out)
  require("Gen3TeachyTv").emit(p,encode,out)
  require("Gen3Banners").emit(p,encode,out)
  if not M.used(p) then return end
  local frameAssets={}
  for path,asset in pairs(p.gen3Assets or {}) do
    if path:match("^data/generated/gba/pokemon/front_anim[_%w]*/%d+%.rgba$") then
      assert(asset.width==64 and type(asset.height)=="number" and asset.height>=64 and asset.height<=2048 and asset.height%64==0,"Invalid entrance frame sheet layout")
      frameAssets[path]=asset
    end
  end
  if next(frameAssets) then
    out[#out+1]="local pokemonFrames=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3PokemonFramesRuntime.lua")).."\nend)()\npokemonFrames.install(mod,"..encode(frameAssets)..")"
  end
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
  require("Gen3Birch").emit(p,encode,out)
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
    assert(asset.indexFile==nil or (type(asset.indexFile)=="string" and asset.indexFile:match("^assets/") and not asset.indexFile:find("..",1,true)),"Invalid mod index map path")
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
  local dex={}
  for _,rec in pairs((p.gen3 or {}).pokemon or {}) do
    if rec.index and rec.dexEntry then dex[rec.index]={category=rec.dexEntry.kind,height=rec.dexEntry.height,weight=rec.dexEntry.weight} end
  end
  for index,text in pairs(p.gen3DexText or {}) do
    assert(type(index)=="number" and type(text)=="string","Invalid Pokédex description")
    dex[index]=dex[index] or {};dex[index].description=text;dex[index].description2=text
  end
  require("Gen3Berries").validate(p)
  local berries=p.gen3Berries or {}
  out[#out+1]="  local native = "..encode({items=p.items or {},help=p.gen3Help or {},animations=p.gen3Animations or {},assets=p.gen3Assets or {},audio=p.gen3Audio or {},dex=dex,
    berries={flavors=berries.flavors or {},names=berries.names or {}}})
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
  -- Runtimes from 0.3.5x on read the cache through CacheFs.readAt: CacheFs.read
  -- is a thin wrapper over it and the Game3 dataset calls it directly, so a
  -- bridge on CacheFs.read alone never sees those reads. Older runtimes only
  -- have CacheFs.read.
  if type(Cache.readAt) == "function" then
    if not Cache._contentEditorBridgeAt then
      Cache._contentEditorBridgeAt = true
      local readAt = Cache.readAt
      Cache.readAt = function(path) return Runtime.call("editor.gen3.cache", readAt, path) end
    end
  elseif not Cache._contentEditorBridge then
    Cache._contentEditorBridge = true
    local read = Cache.read
    Cache.read = function(path) return Runtime.call("editor.gen3.cache", read, path) end
  end
  -- The launcher's mod installer deflates .rgba/.idx files as it copies a mod
  -- in, and mod:read returns them as stored. Hand the game the raw bytes.
  local function assetBytes(file, what)
    local bytes = assert(mod:read(file), what)
    if file:match("%.rgba$") or file:match("%.idx$") then
      local a, b = bytes:byte(1, 2)
      if a and b and a % 16 == 8 and a < 128 and (a * 256 + b) % 31 == 0 then
        local okB, Blob = pcall(require, "src.import.CacheBlob")
        if okB and Blob and Blob.inflate then
          local ok, raw = pcall(Blob.inflate, bytes)
          if ok and type(raw) == "string" then bytes = raw end
        end
      end
    end
    return bytes
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
  -- Emerald screens load PNGs through scene_kit straight from disk, not the cache.
  if require("src.core.GameVersion").layout()=="rse" and next(native.assets) then
    local SceneKit=require("src.ui.game3.rse.scene_kit")
    if not SceneKit._editorImageBridge then
      SceneKit._editorImageBridge=true
      local image=SceneKit.image
      SceneKit.image=function(path) return Runtime.call("editor.gen3.rse.image",image,path) end
    end
    local images={}
    -- The new-game intro and the Ruby/Sapphire Trainer Card draw their own
    -- copies of the player's trainer picture, baked at import. An edited
    -- trainers/front/<N>.rgba follows through to those copies, unless the
    -- copy has its own replacement. Manifests are read on first use, once the
    -- game itself is asking for these screens.
    local picPaths,picLoaded={}, {}
    local function trainerPicFor(path)
      local pack=path:match("^data/generated/gba/(birch)/[^/]+%.png$") or path:match("^data/generated/gba/(rse/trainer_card)/[^/]+%.png$")
      if not pack then return nil end
      if not picLoaded.birch then
        picLoaded.birch=true
        local man=SceneKit.manifest("birch")
        for name,pic in pairs(type(man)=="table" and type(man.pics)=="table" and man.pics or {}) do
          if type(pic)=="table" and type(pic.png)=="string" and tonumber(pic.trainerPic) then
            picPaths[pic.png]=tonumber(pic.trainerPic);picLoaded[name]=tonumber(pic.trainerPic)
          end
        end
      end
      if pack=="rse/trainer_card" and not picLoaded.card then
        picLoaded.card=true
        local man=SceneKit.manifest("rse/trainer_card")
        local pics=type(man)=="table" and type(man.pics)=="table" and man.pics or {}
        -- gTrainerFrontPicTable order: the boy, then the girl.
        for key,fallback in pairs({male={"brendan",0},female={"may",1}}) do
          local rec=pics[key]
          if type(rec)=="table" and type(rec.png)=="string" then picPaths[rec.png]=picLoaded[fallback[1]] or fallback[2] end
        end
      end
      local index=picPaths[path]
      return index and native.assets["data/generated/gba/trainers/front/"..index..".rgba"] or nil
    end
    mod.hooks:wrap("editor.gen3.rse.image",function(proceed,path)
      local asset=path and native.assets[path]
      if not asset then
        local pic=type(path)=="string" and trainerPicFor(path)
        if not pic then return proceed(path) end
        if images[path]==nil then
          local ok,img=pcall(function()
            local bytes=assetBytes(pic.file,"Missing native asset "..pic.file)
            local w,h=tonumber(pic.width) or 64,tonumber(pic.height) or 64
            assert(#bytes==w*h*4,"Trainer picture size mismatch")
            return love.graphics.newImage(love.image.newImageData(w,h,"rgba8",bytes))
          end)
          if ok then img:setFilter("nearest","nearest") end
          images[path]=ok and img or false
        end
        return images[path] or proceed(path)
      end
      if images[path]==nil then
        local ok,img=pcall(function() return love.graphics.newImage(love.filesystem.newFileData(assert(mod:read(asset.file)),"asset.png")) end)
        if ok then img:setFilter("nearest","nearest") end
        images[path]=ok and img or false
      end
      return images[path] or proceed(path)
    end)
    -- The title screen and intro ask the PPU for palette-index art. A
    -- replacement is a normal PNG, drawn in its own colours. The runtime is
    -- not changed: while a layer or sprite pass uses one, the PPU gets a copy
    -- of its own shader where a pixel with alpha 254 is colour, not an index
    -- (index art is always 255).
    local Ppu=require("src.core.game3.gba_ppu")
    if not Ppu._editorIndexBridge then
      Ppu._editorIndexBridge=true
      local layer,sheet=Ppu.indexLayer,Ppu.indexSheet
      Ppu.indexLayer=function(...) return Runtime.call("editor.gen3.rse.indexLayer",layer,...) end
      Ppu.indexSheet=function(...) return Runtime.call("editor.gen3.rse.indexSheet",sheet,...) end
      local renderBg,renderObjs=Ppu._renderBg,Ppu._renderObjs
      Ppu._renderBg=function(...) return Runtime.call("editor.gen3.rse.renderBg",renderBg,...) end
      Ppu._renderObjs=function(...) return Runtime.call("editor.gen3.rse.renderObjs",renderObjs,...) end
    end
    -- Copies of gba_ppu's BG_SHADER / OBJ_SHADER plus the colour branch.
    local BG_SHADER=[[
extern Image idxTex;
extern vec2 texSize;
extern Image palTex;
extern Image lineTex;
extern float lineMode;
extern vec2 ofs;
extern float affine;
extern vec4 mat;
extern vec2 ref;
extern float wrap;
extern float bpp8;
vec4 effect(vec4 color, Image t, vec2 tc, vec2 sc) {
  float x = floor(sc.x);
  float y = floor(sc.y);
  vec2 p;
  if (affine > 0.5) {
    float tx = floor((ref.x + mat.x * x + mat.y * y) / 256.0);
    float ty = floor((ref.y + mat.z * x + mat.w * y) / 256.0);
    if (wrap > 0.5) {
      tx = mod(tx, texSize.x);
      ty = mod(ty, texSize.y);
    } else if (tx < 0.0 || ty < 0.0 || tx >= texSize.x || ty >= texSize.y) {
      return vec4(0.0);
    }
    p = vec2(tx, ty);
  } else {
    float h = ofs.x;
    float v = ofs.y;
    if (lineMode > 0.5) {
      vec4 lv = Texel(lineTex, vec2((y + 0.5) / 160.0, 0.5));
      float val = floor(lv.r * 255.0 + 0.5) + floor(lv.g * 255.0 + 0.5) * 256.0;
      if (lineMode < 1.5) h = val; else v = val;
    }
    p = vec2(mod(x + h, texSize.x), mod(y + v, texSize.y));
  }
  vec4 src = Texel(idxTex, (p + 0.5) / texSize);
  if (src.a < 0.998) {
    if (src.a < 0.5) return vec4(0.0);
    return vec4(src.rgb, 1.0);
  }
  float idx = floor(src.r * 255.0 + 0.5);
  if (bpp8 > 0.5) {
    if (idx < 0.5) return vec4(0.0);
  } else if (mod(idx, 16.0) < 0.5) {
    return vec4(0.0);
  }
  return vec4(Texel(palTex, vec2((idx + 0.5) / 256.0, 0.25)).rgb, 1.0);
}
]]
    local OBJ_SHADER=[[
extern Image sheet;
extern vec2 sheetSize;
extern vec2 frameOrigin;
extern vec2 sprSize;
extern vec2 boxPos;
extern vec2 boxSize;
extern float affine;
extern vec4 mat;
extern vec2 flip;
extern float palBase;
extern float bpp8;
extern Image palTex;
extern float tag;
vec4 effect(vec4 color, Image t, vec2 tc, vec2 sc) {
  vec2 l = floor(sc) - boxPos;
  vec2 s;
  if (affine > 0.5) {
    vec2 d = l - floor(boxSize * 0.5);
    s.x = floor((mat.x * d.x + mat.y * d.y) / 256.0) + floor(sprSize.x * 0.5);
    s.y = floor((mat.z * d.x + mat.w * d.y) / 256.0) + floor(sprSize.y * 0.5);
    if (s.x < 0.0 || s.y < 0.0 || s.x >= sprSize.x || s.y >= sprSize.y) discard;
  } else {
    s = l;
    if (flip.x > 0.5) s.x = sprSize.x - 1.0 - s.x;
    if (flip.y > 0.5) s.y = sprSize.y - 1.0 - s.y;
  }
  vec4 src = Texel(sheet, (frameOrigin + s + 0.5) / sheetSize);
  if (src.a < 0.998) {
    if (src.a < 0.5) discard;
    return vec4(src.rgb, tag);
  }
  float idx = floor(src.r * 255.0 + 0.5);
  if (idx < 0.5) discard;
  float pi = bpp8 > 0.5 ? idx : palBase + idx;
  return vec4(Texel(palTex, vec2((pi + 0.5) / 256.0, 0.75)).rgb, tag);
}
]]
    local shaders={}
    local function colourShader(kind)
      if not shaders[kind] then shaders[kind]=love.graphics.newShader(kind=="bg" and BG_SHADER or OBJ_SHADER) end
      return shaders[kind]
    end
    mod.hooks:wrap("editor.gen3.rse.renderBg",function(proceed,self,g,i,...)
      local L=self.bg[i] and self.bg[i].layer
      if not (L and L.trueColor) then return proceed(self,g,i,...) end
      local stock=g.bgShader
      g.bgShader=colourShader("bg")
      local ok,err=pcall(proceed,self,g,i,...)
      g.bgShader=stock
      if not ok then error(err,0) end
    end)
    mod.hooks:wrap("editor.gen3.rse.renderObjs",function(proceed,self,g,list,...)
      local any=false
      for _,e in ipairs(list or {}) do if e.sheet and e.sheet.trueColor then any=true;break end end
      if not any then return proceed(self,g,list,...) end
      local stock=g.objShader
      g.objShader=colourShader("obj")
      local ok,err=pcall(proceed,self,g,list,...)
      g.objShader=stock
      if not ok then error(err,0) end
    end)
    local colourImages={}
    local function colourImage(path)
      local asset=path and native.assets[path:gsub("_idx%.png$",".png")]
      if not asset or not asset.file then return nil end
      if colourImages[asset.file]==nil then
        local ok,img=pcall(function()
          local data=love.image.newImageData(love.filesystem.newFileData(assert(mod:read(asset.file)),"asset.png"))
          data:mapPixel(function(_,_,r,g,b,a)
            if a<0.5 then return 0,0,0,0 end
            return r,g,b,254/255
          end)
          return love.graphics.newImage(data)
        end)
        if ok then img:setFilter("nearest","nearest") end
        colourImages[asset.file]=ok and img or false
      end
      return colourImages[asset.file] or nil
    end
    mod.hooks:wrap("editor.gen3.rse.indexLayer",function(proceed,path,w,h,bpp)
      local img=colourImage(path)
      if not img then return proceed(path,w,h,bpp) end
      return {image=img,w=w or img:getWidth(),h=h or img:getHeight(),bpp=bpp or 4,trueColor=true}
    end)
    mod.hooks:wrap("editor.gen3.rse.indexSheet",function(proceed,path,frameW,frameH,rects)
      local img=colourImage(path)
      if not img then return proceed(path,frameW,frameH,rects) end
      return {image=img,w=img:getWidth(),h=img:getHeight(),frameW=frameW,frameH=frameH,rects=rects,trueColor=true}
    end)
    Ppu.clearCache()
  end
  -- Sprites and tilesets are decoded on a worker thread that opens the cache
  -- files itself, so it never passes through the bridge above. With no worker
  -- spec the game decodes that asset on the main thread, through the bridge.
  local streamed={}
  for path in pairs(native.assets) do
    local dir,name=path:match("^(.*)/([^/]+)%.[^./]+$")
    if dir then streamed[dir.."/"..name]=true end
    local outer,folder=path:match("^(.*)/([^/]+)/[^/]+$")
    if outer then streamed[outer.."/"..folder]=true end
  end
  if next(streamed) then
    local okS,shared=pcall(function() return require("src.core.game3.dataset").cache() end)
    if okS and type(shared)=="table" and type(shared.assetWorkerSpec)=="function" then
      if not shared._contentEditorWorker then
        shared._contentEditorWorker=true
        local spec=shared.assetWorkerSpec
        shared.assetWorkerSpec=function(...) return Runtime.call("editor.gen3.cache.worker",spec,...) end
      end
      mod.hooks:wrap("editor.gen3.cache.worker",function(proceed,self,root,kind,key)
        local rel=tostring(root).."/"..tostring(key)
        if not rel:match("^data/generated/gba/") then rel="data/generated/gba/"..rel end
        if streamed[rel] then return nil end
        return proceed(self,root,kind,key)
      end)
    end
  end
  mod.hooks:wrap("editor.gen3.cache",function(proceed,path)
    local key=path:gsub("^"..require("src.core.GameVersion").cachePrefix(), "")
    if not key:match("^data/generated/gba/") then key="data/generated/gba/"..key end
    local asset=native.assets[key]
    if asset then
      if not memo[key] then memo[key]=assetBytes(asset.file,"Missing native asset "..asset.file) end
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
    if key=="data/generated/gba/pokemon/pokedex/entries.lua" and next(native.dex) and bytes then
      if not memo[key] then
        local pack=assert(loadstring(bytes))()
        for index,row in pairs(native.dex) do
          if not pack[index] then pack[index]={};for k,v in pairs(pack[0] or {}) do pack[index][k]=v end end
          for k,v in pairs(row) do pack[index][k]=v end
        end
        memo[key]="return "..encode(pack)
      end
      return memo[key]
    end
    if key=="data/generated/gba/berries/berries.lua" and (next(native.berries.flavors) or next(native.berries.names)) and bytes then
      if not memo[key] then
        local pack=assert(loadstring(bytes))()
        for index,row in pairs(native.berries.flavors) do
          local berry=assert(pack.berries[index],"Unknown berry "..tostring(index))
          for k,v in pairs(row) do berry[k]=v end
        end
        for color,name in pairs(native.berries.names) do pack.pokeblockNames[color]=name end
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
    local PokedexData=package.loaded["src.core.game3.pokedex_data"]
    if PokedexData and next(native.dex) then PokedexData._entries=nil end
    if next(native.berries.flavors) or next(native.berries.names) then
      require("src.core.game3.rse.berry_blender").resetCaches()
      require("src.core.game3.rse.pokeblock").setNames(nil)
      require("src.core.game3.rse.berry_trees").reset()
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
