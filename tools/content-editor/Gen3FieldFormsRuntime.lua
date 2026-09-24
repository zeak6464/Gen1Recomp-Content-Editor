local M={}
function M.install(mod,configs)
  local Runtime=require("src.mods.Runtime");local P=require("src.core.game3.pokemon");local families,items={},{}
  for _,f in ipairs(configs) do
    for _,row in ipairs(f.forms) do
      row.index=assert(mod.content.pokemon:get(row.species)).index;families[row.index]=f
      local c=row.fieldRule
      if c and c.kind=="grooming" then c.itemIndex=assert(mod.content.items:get(c.item)).index;items[c.itemIndex]=true end
    end
  end
  local function bridge(object,name,fn)
    local key="editor.gen3.fieldforms."..name
    if not object[key] then object[key]=true;local original=object[name];object[name]=function(...) return Runtime.call(key,original,...) end end
    mod.hooks:wrap(key,fn)
  end
  local function session() local r=package.loaded["src.core.game3.runtime"];return r and r.getSession and r.getSession() end
  local function environment(s)
    s=s or session() or {};local e=s.editorFormEnvironment or {};local date=os.date("*t")
    return {map=e.map or s.map,hour=e.hour or date.hour,season=e.season or ((date.month-1)%4+1),now=e.now or os.time(),flags=s.flags or {}}
  end
  local function match(c,mon,e)
    if c.kind=="map" then return e.map==c.map
    elseif c.kind=="hour" then local a,b=c.startHour or 6,c.endHour or 18;return a==b or (a<b and e.hour>=a and e.hour<b) or (a>b and (e.hour>=a or e.hour<b))
    elseif c.kind=="season" then return e.season==(c.season or 1)
    elseif c.kind=="nature" then return P.natureId(mon.personality or 0)==(c.nature or 0)
    elseif c.kind=="personality" then return (mon.personality or 0)%(c.modulus or 100)==(c.remainder or 0)
    elseif c.kind=="flag" then return e.flags[tonumber(c.flag)] or e.flags[tostring(c.flag)]
    elseif c.kind=="tag" then return mon._editorFormTag==c.tag
    elseif c.kind=="grooming" then return mon._editorGroom and mon._editorGroom.item==c.itemIndex and e.now<mon._editorGroom.expires end
    return false
  end
  local busy=false
  local function select(mon,s)
    if busy or not mon or mon.isEgg or mon.egg or mon._editorFusion then return end
    local f=families[tonumber(mon.species)];if not f then return end
    if mon._editorFormTag==nil then
      for _,row in ipairs(f.forms) do if row.index==mon.species and row.fieldRule and row.fieldRule.kind=="tag" then mon._editorFormTag=row.fieldRule.tag end end
    end
    local e=environment(s);local selected=f.forms[1]
    for _,row in ipairs(f.forms) do if row.fieldRule and match(row.fieldRule,mon,e) then selected=row;break end end
    if mon.species==selected.index then return end
    local hp,max=mon.hp,mon.maxHp;mon.species=selected.index;mon.speciesId=selected.index
    mon.ability=P.abilityId(selected.index,mon.personality or 0);mon.abilityId=mon.ability
    busy=true;P.applyStats(mon);busy=false
    if hp and max then mon.hp=hp==0 and 0 or math.max(1,math.min(mon.maxHp,mon.maxHp-(max-hp))) end
  end
  local function update(s) for _,mon in ipairs(s and s.party or {}) do select(mon,s) end end
  bridge(P,"applyStats",function(proceed,mon,...) select(mon);return proceed(mon,...) end)
  mod.hooks:wrap("editor.gen3.forms.environment",function(_,s) update(s);return true end)
  for _,event in ipairs({"map.entered","world.stepped","flag.changed","game.ready","save.loaded"}) do mod.events:on(event,function(ev) update(ev.save or session()) end) end
  mod.events:on("pokemon.evolved",function(ev) select(ev.mon) end)
  local Breeding=require("src.core.game3.breeding")
  bridge(Breeding,"setInitialEggData",function(proceed,s,species,dc)
    local egg=proceed(s,species,dc)
    if egg and dc then
      local _,mother,father=Breeding.parentSlots(dc);local Daycare=require("src.core.game3.daycare")
      local parent=Daycare.mon(dc,mother)
      if parent and parent.species==132 then parent=Daycare.mon(dc,father) end
      if parent then
        egg._editorFormTag=parent._editorFormTag
        local f=families[tonumber(parent.species)]
        for _,row in ipairs(f and f.forms or {}) do if row.index==parent.species and row.fieldRule and row.fieldRule.kind=="tag" then egg._editorFormTag=row.fieldRule.tag end end
      end
    end
    return egg
  end)
  local Use=require("src.core.game3.item_use");local Bag=require("src.core.game3.bag");local Items=require("src.core.game3.items_data")
  bridge(Use,"needsPartyTarget",function(proceed,id,...) if items[Items.toNumericId(id)] then return true end;return proceed(id,...) end)
  bridge(Use,"useField",function(proceed,s,bag,id,slot,...)
    local numeric=Items.toNumericId(id);local mon=s and s.party and s.party[slot];local f=mon and families[tonumber(mon.species)]
    if f and items[numeric] then
      for _,row in ipairs(f.forms) do local c=row.fieldRule
        if c and c.kind=="grooming" and c.itemIndex==numeric and not mon.isEgg and not mon.egg and Bag.has(bag,numeric,1) then
          mon._editorGroom={item=numeric,expires=environment(s).now+(c.days or 5)*86400};select(mon,s);return true,"form","The Pokemon changed appearance!"
        end
      end
      return false,"form","It would have no effect."
    end
    return proceed(s,bag,id,slot,...)
  end)
end
return M
