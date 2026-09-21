local M={}
function M.choose(f,personality)
  local p=tonumber(personality) or 0
  if f.mode=="unown" then
    local bit=require("bit")
    local letter=bit.bor(bit.rshift(bit.band(p,0x03000000),18),bit.rshift(bit.band(p,0x00030000),12),bit.rshift(bit.band(p,0x00000300),6),bit.band(p,3))%28
    return letter%#f.forms+1
  elseif f.mode=="personality" then return p%#f.forms+1 end
  return math.max(1,math.min(#f.forms,f.default or 1))
end
function M.install(mod,configs)
  local Runtime=require("src.mods.Runtime");local P=require("src.core.game3.pokemon")
  local families,parents,records,pictures={},{},{},{}
  for _,f in ipairs(configs) do
    local parent=assert(mod.content.pokemon:get(f.parent),"Missing form parent "..f.parent);f.index=parent.index;parents[parent.index]=f
    for _,row in ipairs(f.forms) do local rec=assert(mod.content.pokemon:get(row.species),"Missing form "..row.species);row.index=rec.index;families[rec.index]=f;records[rec.index]=rec end
  end
  local function bridge(object,name,key)
    if object[key] then return end;object[key]=true;local original=object[name]
    object[name]=function(...) return Runtime.call(key,original,...) end
  end
  -- FireRed installs its ROM tables again when starting a game. Reapply the
  -- merged registry then, rather than leaving custom form IDs without data.
  local registry,encounterRegistry
  local E=require("src.core.game3.encounters")
  local function restoreEncounters()
    if not encounterRegistry then return end
    for id in pairs(encounterRegistry.ops) do
      local source=encounterRegistry:get(id)
      if source then
        for key,target in pairs(E._tables) do
          if key==id or (source.mapGroup~=nil and source.mapNum~=nil and target.mapGroup==source.mapGroup and target.mapNum==source.mapNum) then
            for _,kind in ipairs({"land","grass","water","rocks","fishing"}) do
              local from,to=source[kind],target[kind]
              if from and to then
                from=from.slots or from.mons or from;to=to.slots or to.mons or to
                for i,slot in ipairs(from) do
                  local rec=mod.content.pokemon:get(slot.species or slot[1])
                  if rec and families[rec.index] and to[i] then
                    if to[i].species~=nil then to[i].species=rec.index else to[i][1]=rec.index end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  local function restore()
    if registry and P._names then registry.spec.write(P,registry) end
    pictures={}
  end
  mod.events:on("mods.loaded",function(ev)
    registry=ev.loader.content.pokemon
    encounterRegistry=ev.loader.content.encounters
    restore()
    restoreEncounters()
  end)
  bridge(E,"ensureLoaded","editor.gen3.forms.encounters")
  mod.hooks:wrap("editor.gen3.forms.encounters",function(proceed,...)
    local result=proceed(...);restoreEncounters();return result
  end)
  bridge(P,"keyName","editor.gen3.forms.key")
  mod.hooks:wrap("editor.gen3.forms.key",function(proceed,species)
    local rec=records[tonumber(species)];return rec and rec.id or proceed(species)
  end)
  bridge(P,"speciesFromName","editor.gen3.forms.lookup")
  mod.hooks:wrap("editor.gen3.forms.lookup",function(proceed,id)
    for index,rec in pairs(records) do if rec.id==id then return index end end
    return proceed(id)
  end)
  mod.hooks:wrap("editor.gen3.forms.reload",function(proceed,...) proceed(...);restore() end)
  P.onReload(function() Runtime.call("editor.gen3.forms.reload",function() end) end,"editor.gen3.forms")
  local function assign(mon)
    if type(mon)~="table" then return end
    local species=tonumber(mon.species or mon.speciesId);local f=parents[species]
    if not f or f.mode=="weather" or mon._editorFormAssigned==f.parent then return end
    local row=f.forms[M.choose(f,mon.personality)]
    mon.species=row.index;mon.speciesId=row.index;mon._editorFormAssigned=f.parent
    mon.ability=P.abilityId(row.index,mon.personality or 0);mon.abilityId=mon.ability
    return row.index~=species
  end
  for _,side in ipairs({"front","back"}) do
    local method=side.."Pic";local hook="editor.gen3.forms."..side
    bridge(P,method,hook)
    mod.hooks:wrap(hook,function(proceed,species,form)
      local rec=records[tonumber(species)]
      local path=rec and rec[side=="front" and "spriteFront" or "spriteBack"]
      if path and not path:match("^data/generated/") then
        if not pictures[path] then
          local img=love.graphics.newImage(path);img:setFilter("nearest","nearest")
          pictures[path]={image=img,w=img:getWidth(),h=img:getHeight()}
        end
        return pictures[path]
      end
      local entry=proceed(species,form);local f=families[tonumber(species)]
      if not entry and f and tonumber(species)~=f.index then return proceed(f.index,0) end
      return entry
    end)
  end
  local Party=require("src.core.game3.party")
  local Battle=require("src.core.game3.battle")
  bridge(Battle,"start","editor.gen3.forms.battleMoves")
  mod.hooks:wrap("editor.gen3.forms.battleMoves",function(proceed,opts)
    if not opts or not opts.foe then return proceed(opts) end
    local clone=require("src.mods.Merge").deepCopy
    local copy={};for k,v in pairs(opts) do copy[k]=v end
    copy.foe=clone(opts.foe)
    if opts.foeParty then copy.foeParty=clone(opts.foeParty) end
    local function prepare(foe)
      if type(foe)~="table" or (foe.moves and #foe.moves>0) then return end
      if foe.personality==nil then foe.personality=require("src.core.game3.rng").Random32() end
      assign(foe)
      local moves,pp,maxPp=P.movesAtLevel(foe.species or foe.id,foe.level or 5)
      if #moves>0 then foe.moves=moves;foe.pp=pp;foe.maxPp=maxPp end
    end
    prepare(copy.foe)
    for _,foe in ipairs(copy.foe.party or {}) do prepare(foe) end
    for _,foe in ipairs(copy.foeParty or {}) do prepare(foe) end
    return proceed(copy)
  end)
  bridge(P,"icon","editor.gen3.forms.icon")
  mod.hooks:wrap("editor.gen3.forms.icon",function(proceed,species)
    local entry=proceed(species);local f=families[tonumber(species)]
    if not entry and f and tonumber(species)~=f.index then return proceed(f.index) end
    return entry
  end)
  bridge(Party,"giveMon","editor.gen3.forms.gift")
  mod.hooks:wrap("editor.gen3.forms.gift",function(proceed,session,species,level,nickname)
    local f=parents[tonumber(species)]
    if f and f.mode=="fixed" then species=f.forms[M.choose(f,0)].index end
    return proceed(session,species,level,nickname)
  end)
  bridge(P,"applyStats","editor.gen3.forms.stats")
  mod.hooks:wrap("editor.gen3.forms.stats",function(proceed,mon) assign(mon);return proceed(mon) end)
  local State=require("src.core.game3.battle.state")
  bridge(State,"makeBattler","editor.gen3.forms.battler")
  mod.hooks:wrap("editor.gen3.forms.battler",function(proceed,mon,...)
    if assign(mon) then P.applyStats(mon) end
    return proceed(mon,...)
  end)
  local Abilities=require("src.core.game3.battle.abilities")
  bridge(Abilities,"castformChange","editor.gen3.forms.weather")
  mod.hooks:wrap("editor.gen3.forms.weather",function(proceed,ad,b)
    local f=b and families[tonumber(b.species)]
    if not f or f.mode~="weather" then return proceed(ad,b) end
    if ad:hp(b)<=0 or ad:abilityOf(b)~="FORECAST" then return 0 end
    local weather=require("src.core.game3.battle.rules").weather.effective(ad._st,ad)
    local selected=f.forms[1]
    for i,row in ipairs(f.forms) do if i>1 and row.weather==weather then selected=row;break end end
    -- Battle appearance and typing are temporary. The saved Pokemon retains its identity and stats.
    if b._editorWeatherIndex~=selected.index then
      local types=P.types(selected.index);b.species=selected.index;b.type1=types[1];b.type2=types[2]~=types[1] and types[2] or nil;b._editorWeatherIndex=selected.index
    end
    return 0
  end)
end
return M
