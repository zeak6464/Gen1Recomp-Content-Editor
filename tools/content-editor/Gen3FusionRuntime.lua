local M={}
local function copy(v)
  if type(v)~="table" then return v end
  local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
end
function M.install(mod,configs)
  local Runtime=require("src.mods.Runtime")
  local P=require("src.core.game3.pokemon")
  local Use=require("src.core.game3.item_use")
  local Bag=require("src.core.game3.bag")
  local recipes,keys={},{}
  for _,f in ipairs(configs) do
    local item=assert(mod.content.items:get(f.fusionItem),"Missing fusion key item")
    assert(item.pocket=="KEY_ITEMS","Fusion requires a key item")
    local base=assert(mod.content.pokemon:get(f.parent),"Missing fusion base").index
    keys[item.index]=true;keys[f.fusionItem]=item.index
    recipes[item.index]=recipes[item.index] or {}
    local rows={};recipes[item.index][base]=rows
    for i,row in ipairs(f.forms) do if i>1 and row.partner then
      local partner=assert(mod.content.pokemon:get(row.partner),"Missing fusion partner").index
      rows[partner]=assert(mod.content.pokemon:get(row.species),"Missing fusion result").index
    end end
  end
  local function key(id) return type(keys[id])=="number" and keys[id] or (keys[tonumber(id)] and tonumber(id)) end
  local function bridge(object,name,fn)
    local hook="editor.gen3.fusion."..name
    if not object[hook] then
      object[hook]=true;local original=object[name]
      object[name]=function(...) return Runtime.call(hook,original,...) end
    end
    mod.hooks:wrap(hook,fn)
  end
  local function change(mon,index)
    local hp,max=mon.hp,mon.maxHp
    mon.species=index;mon.speciesId=index;mon._editorFormAssigned=nil
    mon.ability=P.abilityId(index,mon.personality)
    P.applyStats(mon)
    if hp and max then mon.hp=hp==0 and 0 or math.max(1,math.min(mon.maxHp,mon.maxHp-(max-hp))) end
  end
  local function overlays(session,fn)
    local seen={}
    for _,name in ipairs({"move_overlay","moveOverlay"}) do
      local t=session[name];if type(t)=="table" and not seen[t] then fn(t,name);seen[t]=true end
    end
  end
  local function transact(session,bag,id,slot,partnerSlot)
    local function fail(s) return false,"fusion",s end
    local party=session and session.party
    local base=party and party[slot]
    if not base or base.isEgg or base.egg then return fail("Choose a compatible Pokemon.") end
    if not Bag.has(bag,id,1) then return fail("You need the fusion key item.") end
    local stored=base._editorFusion
    if stored then
      if stored.item~=id then return fail("Use the original fusion key item.") end
      if #party>=6 then return fail("Make room for one more Pokemon first.") end
      if type(stored.partner)~="table" or not stored.base then return fail("Fusion data is incomplete.") end
      local staged=copy(base);change(staged,stored.base);staged.ability=stored.ability
      staged._editorFusion=nil
      for k in pairs(base) do base[k]=nil end;for k,v in pairs(staged) do base[k]=v end
      party[#party+1]=copy(stored.partner)
      overlays(session,function(t,name) t[#party]=copy((stored.overlays or {})[name]) end)
      return true,"fusion","The Pokemon were separated."
    end
    local rows=recipes[id] and recipes[id][tonumber(base.species or base.speciesId)]
    if not rows then return fail("This Pokemon cannot use this fusion item.") end
    local partner=party[partnerSlot]
    if not partner or partner==base or partner.isEgg or partner.egg or partner._editorFusion then return fail("Choose a compatible partner.") end
    local result=rows[tonumber(partner.species or partner.speciesId)]
    if not result then return fail("These Pokemon cannot fuse.") end
    if base.hp==0 then return fail("Heal the base Pokemon before fusing.") end
    -- Stage the complete result before modifying the party. Nested partner data
    -- survives the runtime's save serializer and PC storage unchanged.
    local staged=copy(base)
    staged._editorFusion={version=1,item=id,base=base.species or base.speciesId,ability=base.ability,partner=copy(partner),overlays={}}
    for _,name in ipairs({"move_overlay","moveOverlay"}) do
      if session[name] then staged._editorFusion.overlays[name]=copy(session[name][partnerSlot]) end
    end
    change(staged,result)
    for k in pairs(base) do base[k]=nil end;for k,v in pairs(staged) do base[k]=v end
    local count=#party;table.remove(party,partnerSlot)
    overlays(session,function(t) for i=partnerSlot,count-1 do t[i]=t[i+1] end;t[count]=nil end)
    return true,"fusion","The Pokemon fused!"
  end
  bridge(Use,"needsPartyTarget",function(proceed,id,...) if key(id) then return true end;return proceed(id,...) end)
  bridge(Use,"useField",function(proceed,session,bag,id,slot,move,partner)
    local numeric=key(id)
    if numeric then return transact(session,bag,numeric,slot,partner) end
    return proceed(session,bag,id,slot,move,partner)
  end)
  local Menu=require("src.ui.game3.party_menu")
  bridge(Menu,"show",function(proceed,party,overlay,opts)
    if not opts and type(overlay)=="table" and overlay.mode then opts=overlay;overlay=nil end
    if not opts or opts.mode~="use" or not key(opts.item) then return proceed(party,overlay,opts) end
    party=party or (opts.session and opts.session.party)
    local options={};for k,v in pairs(opts) do options[k]=v end
    local selected
    options.onSelect=function(slot)
      if not slot then Menu.close();return end
      if opts.battle or opts.battleOrder then Menu.showMessage("Fusion can only be used outside battle.",function() Menu.close() end);return end
      local mon=party[slot];local id=key(opts.item)
      if not selected and mon and not mon._editorFusion and not mon.isEgg and not mon.egg and recipes[id][tonumber(mon.species or mon.speciesId)] then
        selected=mon
        Menu.showMessage("Choose the partner Pokemon.",function() Menu.mode="use" end)
        return
      end
      local baseSlot=slot
      if selected then for i,m in ipairs(party) do if m==selected then baseSlot=i;break end end end
      local ok,_,message=transact(opts.session,opts.bag or (opts.session and (opts.session.bag or opts.session.inventory)),id,baseSlot,selected and slot or nil)
      Menu.showMessage(message,function() if ok then Menu.close() else Menu.mode="use" end end)
    end
    return proceed(party,overlay,options)
  end)
  local refusal="Separate fused Pokemon first."
  local Evolution=require("src.core.game3.evolution")
  bridge(Evolution,"targetSpecies",function(proceed,mon,...)
    if mon and mon._editorFusion then return 0 end
    return proceed(mon,...)
  end)
  local Daycare=require("src.core.game3.daycare")
  for _,method in ipairs({"deposit","depositRoute5"}) do
    local name=method
    bridge(Daycare,name,function(proceed,session,slot,...)
      local rt=package.loaded["src.core.game3.runtime"]
      local s=session or (rt and rt.getSession and rt.getSession())
      if s and s.party and s.party[slot] and s.party[slot]._editorFusion then
        if name=="depositRoute5" then return false,refusal end
        return nil,refusal
      end
      return proceed(session,slot,...)
    end)
  end
  local Trade=require("src.core.game3.scripting.natives_trade")
  bridge(Trade,"canTradeSelectedMon",function(proceed,party,slot,...)
    if party and party[(tonumber(slot) or 0)+1] and party[(tonumber(slot) or 0)+1]._editorFusion then return Trade.CANT_TRADE_INVALID_MON or 4 end
    return proceed(party,slot,...)
  end)
  bridge(Trade,"tradeMons",function(proceed,session,slot,...)
    if session and session.party and session.party[(tonumber(slot) or 0)+1] and session.party[(tonumber(slot) or 0)+1]._editorFusion then return nil,refusal end
    return proceed(session,slot,...)
  end)
  local Storage=require("src.core.game3.storage")
  bridge(Storage,"releaseMon",function(proceed,session,box,slot,...)
    local b=session and session.storage and session.storage.boxes and session.storage.boxes[box]
    if b and b.mons[slot] and b.mons[slot]._editorFusion then return nil,refusal end
    return proceed(session,box,slot,...)
  end)
  local Release=require("src.ui.game3.release_seq")
  bridge(Release,"start",function(proceed,opts,...)
    if opts and opts.mon and opts.mon._editorFusion then
      return Use.showFieldMessage(refusal,function() if opts.onComplete then opts.onComplete(false) end end)
    end
    return proceed(opts,...)
  end)
end
return M
