local M={}
local copy=require("src.mods.Merge").deepCopy
local stats={attack="Attack",defense="Defense",speed="Speed",spAtk="Special Attack",spDef="Special Defense",accuracy="Accuracy",evasion="Evasion"}
local statuses={SLEEP="Sleep",POISON="Poison",TOXIC="Bad poison",BURN="Burn",PARALYSIS="Paralysis",FREEZE="Freeze"}
local conditions={always="Always",lowHp="User HP at or below 50%",fullHp="User at full HP",status="User has a status condition",healthy="User has no status condition"}
local actions={heal="Restore HP (%)",damage="Lose HP (% of maximum)",stat="Change a stat",resetStats="Reset all stat stages",weather="Change weather",cure="Cure status condition",status="Inflict status condition",confusion="Confuse",flinch="Flinch"}
local triggers={switchIn="When entering battle",endTurn="At the end of each turn",switchOut="When leaving battle",
  receiveHit="After taking a damaging hit",receiveContact="After taking a contact hit",dealHit="After dealing a damaging hit",knockout="After knocking out an opponent"}
for k,v in pairs({hpBelow="User HP at/below a chosen percentage",hpAbove="User HP above a chosen percentage",foeLowHp="Opponent HP at/below 50%",foeStatus="Opponent has a status condition",
  burned="User is burned",poisoned="User is poisoned",paralyzed="User is paralyzed",asleep="User is asleep",frozen="User is frozen",confused="User is confused",
  sun="In sunlight",rain="In rain",sand="In sandstorm",hail="In hail",noWeather="No weather",boosted="User has raised stat stages",lowered="User has lowered stat stages",
  contact="The triggering hit makes contact",physical="The triggering hit is physical",special="The triggering hit is special"}) do conditions[k]=v end
for k,v in pairs({clearConfusion="Cure confusion",clearFlinch="Clear flinching",clearNegative="Remove lowered stat stages",clearPositive="Remove raised stat stages",
  invertStats="Invert stat stages",copyStats="Copy the other battler's stat stages",swapStats="Swap stat stages with the other battler",setStat="Set a stat stage",
  drain="Heal from triggering hit damage (%)",recoil="Lose HP from triggering hit damage (%)",clearWeather="Clear weather",clearTrap="Remove trapping and escape prevention"}) do actions[k]=v end
M.triggers,M.conditions,M.actions=triggers,conditions,actions
M.presets={
  regeneration={name="Regeneration",trigger="switchOut",target="self",actions={{kind="heal",amount=33}}},
  contactGuard={name="Contact Guard",trigger="receiveContact",target="opponent",actions={{kind="damage",amount=12}}},
  victoryBoost={name="Victory Boost",trigger="knockout",target="self",actions={{kind="stat",stat="attack",amount=1}}},
  rainCaller={name="Rain Caller",trigger="switchIn",target="self",actions={{kind="weather",weather="RAIN",turns=5}}},
  cleanExit={name="Clean Exit",trigger="switchOut",target="self",actions={{kind="cure"},{kind="clearConfusion"}}},
}
function M.new(S,kind)
  S.project.gen3Behaviors=S.project.gen3Behaviors or {};local records=S.project.gen3Behaviors
  local index=78
  if kind=="ability" then
    local used={};for _,r in pairs(records) do if r.kind=="ability" then used[r.index]=true end end
    for id in pairs((S.data.gen3Pokemon or {}).abilityNames or {}) do used[tonumber(id)]=true end
    while used[index] and index<=255 do index=index+1 end
    assert(index<=255,"No free ability number")
  end
  local n=1;while records["CUSTOM_"..n] do n=n+1 end;local id="CUSTOM_"..n
  records[id]={kind=kind,index=kind=="ability" and index or nil,name=(kind=="ability" and "Custom Ability " or "Custom Effect ")..n,
    trigger="endTurn",target="self",chance=100,actions={{kind="heal",amount=6}}}
  return id
end
function M.assignMove(S,id,moveId)
  local rec=assert(S.project.gen3Behaviors[id]);assert(rec.kind=="move")
  local base=assert(S.project.moves[moveId] or S.data.moves[moveId],"Choose a move")
  for other,r in pairs(S.project.gen3Behaviors) do assert(other==id or r.moveId~=moveId,"This move already has a custom behavior") end
  if rec.moveId~=moveId then
    if rec.moveId and rec.originalMoveFields then
      local previous=S.project.moves[rec.moveId]
      if previous then
        for _,field in ipairs({"power","effect","category","target"}) do previous[field]=rec.originalMoveFields[field] end
      end
    end
    rec.originalMoveFields={power=base.power,effect=base.effect,category=base.category,target=base.target}
  end
  local move=copy(base);move.effect=0
  if rec.mode=="damage" then
    move.power=rec.power or 40;move.category=(rec.originalMoveFields or {}).category
    if move.category=="status" then move.category=nil end
    move.target=0
  else move.power=0;move.category="status";move.target=rec.target=="self" and 16 or 0 end
  S.project.moves[moveId]=move;rec.moveId=moveId;rec.moveIndex=move.index
end
function M.validate(records)
  local names,indices,moves={},{},{}
  for _,r in pairs(records or {}) do
    assert(type(r.name)=="string" and #r.name>0 and #r.name<=40 and r.name:match("^[%w _%-]+$"),"Use a name of 1-40 letters, numbers, spaces or hyphens")
    assert(r.kind=="ability" or r.kind=="move","Unknown behavior type")
    assert(r.condition==nil or conditions[r.condition],"Unknown activation condition")
    assert(r.mode==nil or r.mode=="status" or r.mode=="damage","Unknown move behavior mode")
    if r.mode=="damage" then assert(r.kind=="move" and type(r.power)=="number" and r.power%1==0 and r.power>=1 and r.power<=255,"Power must be 1-255") end
    assert(r.target=="self" or r.target=="opponent","Invalid behavior target")
    if r.condition=="hpBelow" or r.condition=="hpAbove" then assert(type(r.hpPercent)=="number" and r.hpPercent%1==0 and r.hpPercent>=1 and r.hpPercent<=100,"Choose HP percent from 1-100") end
    assert(type(r.chance)=="number" and r.chance%1==0 and r.chance>=1 and r.chance<=100,"Chance must be 1-100")
    if r.kind=="ability" then
      assert(r.index and r.index%1==0 and r.index>=78 and r.index<=255 and not indices[r.index],"Invalid or duplicate ability number")
      local name=r.name:upper():gsub("%s+","_")
      assert(not names[name],"Custom ability names must be unique");names[name]=true;indices[r.index]=true
      for _,native in pairs(require("src.core.game3.battle.adapter").ABILITY_BY_ID) do assert(name~=native,"Choose a name different from an original ability") end
      assert(triggers[r.trigger],"Invalid ability trigger")
    elseif r.moveIndex then assert(not moves[r.moveIndex],"Two effects use the same move");moves[r.moveIndex]=true end
    assert(type(r.actions)=="table" and #r.actions>=1 and #r.actions<=8,"Choose 1-8 actions")
    for _,a in ipairs(r.actions) do
      assert(a.target==nil or a.target=="inherit" or a.target=="self" or a.target=="opponent","Invalid action target")
      if a.kind=="heal" or a.kind=="damage" or a.kind=="drain" or a.kind=="recoil" then
        assert(type(a.amount)=="number" and a.amount%1==0 and a.amount>=1 and a.amount<=100,"HP percentage must be 1-100")
        if a.kind=="drain" or a.kind=="recoil" then assert(r.kind=="move" and r.mode=="damage" or r.kind=="ability" and ({receiveHit=true,receiveContact=true,dealHit=true,knockout=true})[r.trigger],"Hit-based HP actions need a damaging move or hit/knockout ability trigger") end
      elseif a.kind=="setStat" then assert(stats[a.stat] and type(a.amount)=="number" and a.amount%1==0 and a.amount>=-6 and a.amount<=6,"Stat stage must be -6 to +6")
      elseif a.kind=="status" then assert(statuses[a.status],"Choose a status condition")
      elseif a.kind=="confusion" or a.kind=="flinch" or a.kind=="resetStats" then
      elseif a.kind=="stat" then assert(stats[a.stat] and type(a.amount)=="number" and a.amount%1==0 and a.amount~=0 and a.amount>=-6 and a.amount<=6,"Choose a stat change from -6 to +6")
      elseif a.kind=="weather" then assert(({SUN=true,RAIN=true,SANDSTORM=true,HAIL=true})[a.weather] and a.turns and a.turns%1==0 and a.turns>=1 and a.turns<=20,"Choose weather for 1-20 turns")
      else assert(actions[a.kind],"Unknown behavior action") end
    end
  end
end
function M.draw(S,x,y,w,h,App)
  local K,L,P=require("Kit"),require("RegList"),require("ChoicePicker");local s=K.scale
  local records=S.project.gen3Behaviors or {};local ids=L.sortedKeys(records)
  local fx,fw=L.drawList(S,App,x,y,w,h,"CUSTOM BEHAVIORS",ids,{selKey="g3BehaviorId",queryKey="g3BehaviorQuery",offsetKey="g3BehaviorOffset",label=function(id) return records[id].name end})
  local yy=y
  for _,kind in ipairs({"ability","move"}) do
    if K.button(fx,yy,210*s,28*s,kind=="ability" and "New ability" or "New move behavior",{kind="good"}) then
      local ok,id=pcall(M.new,S,kind);if ok then S.g3BehaviorId=id;App.markDirty() else S.status=tostring(id) end
    end;yy=yy+36*s
  end
  local r=records[S.g3BehaviorId];if not r then K.caption(fx,yy,"Create a behavior, choose actions, then assign it.");return end
  local top,view=require("FormPane").begin(S,"g3BehaviorForm",fx,yy,fw,h-(yy-y));yy=top;fw=view.contentW
  local function caption(label) K.caption(fx,yy,label);yy=yy+24*s end
  local function choice(label,current,options,onPick)
    caption(label);local ids={};for id in pairs(options) do ids[#ids+1]=id end;table.sort(ids)
    P.field(S,{x=fx,y=yy,w=fw,h=28*s,ids=ids,labels=options,current=current,onPick=function(id) onPick(id);App.markDirty() end});yy=yy+36*s
  end
  caption("Name")
  local name=K.textfield("g3_behavior_name",fx,yy,fw,28*s,r.name,"");if name~=r.name then r.name=name;App.markDirty() end;yy=yy+36*s
  if r.kind=="ability" then
    local labels={};for id,preset in pairs(M.presets) do labels[id]=preset.name end
    choice("Replace behavior with a preset",nil,labels,function(id)
      local preset=copy(M.presets[id]);r.name=preset.name;r.trigger=preset.trigger;r.target=preset.target;r.actions=preset.actions;r.condition="always";r.chance=100
    end)
  end
  if r.kind=="move" then
    choice("Move behavior",r.mode or "status",{status="Status move (actions only)",damage="Damage, then extra actions"},function(v)
      r.mode=v;r.power=r.power or math.max(1,tonumber((r.originalMoveFields or {}).power) or 40)
      if r.moveId then M.assignMove(S,S.g3BehaviorId,r.moveId) end
    end)
    if r.mode=="damage" then
      caption("Attack power (accuracy, type and PP are set in Moves)")
      local power=math.floor(math.max(1,math.min(255,L.num(App,"g3_behavior_power",fx,yy,120*s,28*s,r.power or 40))))
      if power~=r.power then r.power=power;if r.moveId then M.assignMove(S,S.g3BehaviorId,r.moveId) end;App.markDirty() end
      yy=yy+36*s
    end
  end
  if r.kind=="ability" then
    choice("When it happens",r.trigger,triggers,function(v) r.trigger=v end)
    choice("Who it affects",r.target,{self="Ability holder",opponent="Other battler (attacker on received hits, current foe otherwise)"},function(v) r.target=v end)
  else choice(r.mode=="damage" and "Who receives the extra actions" or "Who it affects",r.target,{self="The user",opponent="The selected opponent"},function(v) r.target=v;if r.moveId then M.assignMove(S,S.g3BehaviorId,r.moveId) end end) end
  choice("Activation condition",r.condition or "always",conditions,function(v) r.condition=v end)
  if r.condition=="hpBelow" or r.condition=="hpAbove" then
    caption("HP threshold (%)")
    local n=math.floor(math.max(1,math.min(100,L.num(App,"g3_hp_threshold",fx,yy,120*s,28*s,r.hpPercent or 50))))
    if n~=r.hpPercent then r.hpPercent=n;App.markDirty() end;yy=yy+36*s
  end
  caption("Chance to activate (%)")
  local chance=math.floor(math.max(1,math.min(100,L.num(App,"g3_behavior_chance",fx,yy,120*s,28*s,r.chance))))
  if chance~=r.chance then r.chance=chance;App.markDirty() end;yy=yy+36*s
  for i,a in ipairs(r.actions) do
    choice("Action "..i,a.kind,actions,function(v)
      r.actions[i]={kind=v,amount=(v=="stat" or v=="setStat") and 1 or 25,stat="attack",weather="RAIN",turns=5,status="POISON",target=a.target}
    end)
    if a.kind~="weather" and a.kind~="clearWeather" then
      choice("Action recipient",a.target or "inherit",{inherit="Use behavior target",self="The user",opponent="The selected opponent"},function(v) a.target=v end)
    end
    if a.kind=="status" then choice("Status condition",a.status or "POISON",statuses,function(v) a.status=v end) end
    if a.kind=="stat" or a.kind=="setStat" then choice("Stat",a.stat,stats,function(v) a.stat=v end) end
    if a.kind=="heal" or a.kind=="damage" or a.kind=="stat" or a.kind=="setStat" or a.kind=="drain" or a.kind=="recoil" then
      local isStat=a.kind=="stat" or a.kind=="setStat"
      local lo,hi=isStat and -6 or 1,isStat and 6 or 100
      caption(isStat and (a.kind=="setStat" and "Set stage (-6 to +6)" or "Stages (-6 to +6; zero is invalid)") or (a.kind=="drain" or a.kind=="recoil") and "Percent of triggering hit damage" or "Percent of maximum HP")
      local n=math.floor(math.max(lo,math.min(hi,L.num(App,"g3_action_amount_"..i,fx,yy,120*s,28*s,a.amount))))
      if n~=a.amount then a.amount=n;App.markDirty() end;yy=yy+36*s
    elseif a.kind=="weather" then
      choice("Weather",a.weather,{SUN="Sun",RAIN="Rain",SANDSTORM="Sandstorm",HAIL="Hail"},function(v) a.weather=v end)
      caption("Duration in turns")
      local n=math.floor(math.max(1,math.min(20,L.num(App,"g3_action_turns_"..i,fx,yy,120*s,28*s,a.turns))))
      if n~=a.turns then a.turns=n;App.markDirty() end;yy=yy+36*s
    end
    if #r.actions>1 and K.button(fx,yy,170*s,28*s,"Remove action "..i,{}) then table.remove(r.actions,i);App.markDirty();break end
    if i>1 and K.button(fx+180*s,yy,100*s,28*s,"Move up",{}) then r.actions[i-1],r.actions[i]=r.actions[i],r.actions[i-1];App.markDirty();break end
    yy=yy+36*s
  end
  if #r.actions<8 and K.button(fx,yy,180*s,28*s,"Add another action",{}) then r.actions[#r.actions+1]={kind="heal",amount=25};App.markDirty() end;yy=yy+40*s
  if r.kind=="ability" then
    caption("Assign to a Pokemon")
    require("SpeciesPicker").field(S,{x=fx,y=yy,w=fw,h=28*s,current=S.g3CustomAbilitySpecies,onPick=function(v) S.g3CustomAbilitySpecies=v end});yy=yy+36*s
    choice("Ability slot",S.g3CustomAbilitySlot or "1",{["1"]="First ability",["2"]="Second ability"},function(v) S.g3CustomAbilitySlot=v end)
    if K.button(fx,yy,210*s,28*s,"Assign custom ability",{kind="good"}) then
      local species=S.g3CustomAbilitySpecies;local base=S.project.pokemon[species] or S.data.pokemon[species]
      if base then local mon=copy(base);mon.abilities=mon.abilities or {};mon.abilities[tonumber(S.g3CustomAbilitySlot or "1")]=r.index;S.project.pokemon[species]=mon;App.markDirty();S.status="Custom ability assigned. Save your mod." else S.status="Choose a Pokemon first." end
    end
  else
    caption(r.mode=="damage" and "Assign to a move (replaces its original effect)" or "Assign to a move (sets power to zero and uses these actions)")
    P.field(S,{x=fx,y=yy,w=fw,h=28*s,ids=L.mergeIds(S.project.moves,S.data.moves),current=r.moveId,onPick=function(v)
      local ok,err=pcall(M.assignMove,S,S.g3BehaviorId,v);if ok then App.markDirty() else S.status=tostring(err) end
    end})
  end
  yy=yy+42*s
  local ok,err=pcall(M.validate,records);if not ok then caption(tostring(err):match("[^:]+$") or tostring(err)) end
  require("FormPane").finish(S,"g3BehaviorForm",top,yy,view)
end
function M.emit(p,encode,out)
  local records=p.gen3Behaviors or {};if not next(records) then return end
  M.validate(records)
  for _,r in pairs(records) do if r.kind=="move" and r.moveId then
    local move=(p.moves or {})[r.moveId];assert(move and move.index==r.moveIndex and move.power==(r.mode=="damage" and r.power or 0),"Move power changed; reassign it in the behavior builder")
  end end
  local assignments={}
  for _,mon in pairs(p.pokemon or {}) do if mon.abilities and tonumber(mon.index) then assignments[tonumber(mon.index)]=mon.abilities end end
  local source=assert(love.filesystem.read("tools/content-editor/Gen3BehaviorRuntime.lua"))
  out[#out+1]="  local behaviors=(function()\n"..source.."\nend)()("..encode(records)..",mod,"..encode(assignments)..")\n  behaviors.install()"
end
return M
