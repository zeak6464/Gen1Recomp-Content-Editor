local root=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;tools/save-editor/?.lua;"..root.."/?.lua;"..package.path
local Builder=require("Gen3Behaviors")
local B=require("Gen3BehaviorRuntime")({}, {}, {})
local user={hp=40,maxHp=100,stages={attack=2},ability="NONE"}
local foe={hp=100,maxHp=100,stages={defense=-2},ability="NONE"}
local ad={rolls=0}
function ad:hp(b) return b.hp end
function ad:maxHp(b) return b.maxHp end
function ad:heal(b,n) b.hp=math.min(b.maxHp,b.hp+n) end
function ad:applyHpLoss(b,n) local lost=math.min(b.hp,n);b.hp=b.hp-lost;return lost end
function ad:status(b) return b.status end
function ad:clearStatus(b) b.status=nil end
function ad:roll(lo) self.rolls=self.rolls+1;return lo end
function ad:say() end
function ad:sayFail() end
function ad:sayText() end
function ad:statusAnim() end
function ad:playAnim() end
function ad:abilityOf(b) return b.ability end
function ad:ownSide(b) return b.side or {} end
function ad:canApplyStatus(b) return not b.status end
function ad:applyStatus(b,status) b.status=status end
local rec={kind="move",name="Combo",target="opponent",chance=100,condition="lowHp",actions={
  {kind="damage",amount=25},{kind="heal",amount=20,target="self"},{kind="status",status="POISON"},{kind="resetStats"}}}
Builder.validate({combo=rec})
assert(B.apply(rec,ad,user,foe))
assert(foe.hp==75 and user.hp==60 and foe.status=="PSN" and foe.stages.defense==0)
assert(ad.rolls==1,"Compound behavior rerolled activation chance")
assert(not B.apply(rec,ad,user,foe),"Low HP condition ignored")
rec.condition="always";foe.hp=100;foe.status=nil;foe.substituteHP=20;user.hp=40
assert(B.apply(rec,ad,user,foe));assert(foe.hp==100 and not foe.status and user.hp==60)
foe.substituteHP=0;foe.side={expSafeguardTurns=3};user.hp=40
assert(B.apply(rec,ad,user,foe));assert(not foe.status,"Status bypassed Safeguard")
foe.side={};foe.ability="SHIELD_DUST";user.hp=40
assert(B.apply(rec,ad,user,foe));assert(not foe.status,"Status bypassed Shield Dust")
rec.actions={{kind="confusion"},{kind="flinch"}};foe.ability="NONE"
assert(B.apply(rec,ad,user,foe));assert(foe.confusionTurns>=2 and foe.flinched)
rec.actions={{kind="damage",amount=101}};assert(not pcall(Builder.validate,{bad=rec}))
rec.actions={{kind="status",status="INVALID"}};assert(not pcall(Builder.validate,{bad=rec}))
rec={kind="ability",name="Departure",index=78,trigger="switchOut",target="self",chance=100,actions={{kind="cure"}}}
Builder.validate({ability=rec});user.status="PSN";assert(B.apply(rec,ad,user,user));assert(not user.status)
print("PASS: expanded behavior validation, compound targeting, conditions, status defenses, confusion/flinch, damage and switch-out definition")
for id,preset in pairs(Builder.presets) do
  local r={kind="ability",index=78,chance=100};for k,v in pairs(preset) do r[k]=v end
  Builder.validate({[id]=r})
end
ad._st={weather="RAIN"}
function ad:setWeather(w,t) self._st.weather=w;self._st.weatherTurns=t end
user.hp=40;user.status="TOX"
assert(B.matches({condition="hpBelow",hpPercent=40},ad,user,foe))
assert(not B.matches({condition="hpAbove",hpPercent=40},ad,user,foe))
assert(B.matches({condition="poisoned"},ad,user,foe))
assert(B.matches({condition="rain"},ad,user,foe))
assert(B.matches({condition="contact"},ad,user,foe,{move={flags=1}}))
assert(B.matches({condition="special"},ad,user,foe,{move={category="special"}}))
local function action(a,ctx)
  return B.apply({name="Test",target="self",actions={a}},ad,user,foe,ctx,true)
end
user.stages={attack=3,defense=-2};foe.stages={attack=-1,defense=4}
action({kind="swapStats"});assert(user.stages.attack==-1 and foe.stages.attack==3)
action({kind="copyStats"});assert(user.stages.attack==3 and user.stages.defense==-2)
action({kind="invertStats"});assert(user.stages.attack==-3 and user.stages.defense==2)
action({kind="clearNegative"});assert(user.stages.attack==0 and user.stages.defense==2)
action({kind="clearPositive"});assert(user.stages.defense==0)
action({kind="setStat",stat="speed",amount=6});assert(user.stages.speed==6)
action({kind="drain",amount=50},{hpDealt=40});assert(user.hp==60)
action({kind="recoil",amount=25},{hpDealt=40});assert(user.hp==50)
user.confusionTurns=3;user.flinched=true;user.expTrapTurns=4
action({kind="clearConfusion"});action({kind="clearFlinch"});action({kind="clearTrap"})
assert(user.confusionTurns==0 and not user.flinched and not user.expTrapTurns)
action({kind="clearWeather"});assert(not ad._st.weather)
rec.actions={{kind="drain",amount=50}};assert(not pcall(Builder.validate,{bad=rec}))
rec.trigger="dealHit";Builder.validate({valid=rec})

-- Exercise the installed dispatcher, including received-contact orientation and faint callbacks.
local hooks={}
package.loaded["src.mods.Runtime"]={call=function(key,base,...) return hooks[key](base,...) end}
local abilities={switchIn=function() end,endTurn=function() end,switchOut=function() end}
package.loaded["src.core.game3.battle.abilities"]=abilities
package.loaded["src.core.game3.pokemon"]={abilities=function() return {} end,abilityName=function() end}
package.loaded["src.core.game3.battle.moves"]={get=function() end}
package.loaded["src.core.game3.battle.effects"]={runForMove=function() end}
local hit={run=function() return "original" end}
package.loaded["src.core.game3.battle.effects.hit"]=hit
local records={guard={kind="ability",name="Guard",trigger="receiveContact",target="opponent",actions={{kind="damage",amount=12}}},
  boost={kind="ability",name="Boost",trigger="knockout",target="self",actions={{kind="setStat",stat="attack",amount=3}}}}
local installed=require("Gen3BehaviorRuntime")(records,{hooks={wrap=function(_,k,fn) hooks[k]=fn end}},{})
installed.install()
user.hp=10;user.ability="BOOST";foe.hp=80;foe.ability="GUARD"
local faint=0
local ctx={adapter=ad,user=user,target=foe,move={flags=1},targetDamaged=true,hpDealt=20,tryFaintUser=function() faint=faint+1 end}
assert(hit.run(ctx)=="original");assert(user.hp==0 and faint==1)
user.hp=100;ctx.hitSubstitute=true;hit.run(ctx);assert(user.hp==100)
ctx.hitSubstitute=nil;foe.hp=0;user.stages.attack=0;hit.run(ctx);assert(user.stages.attack==3)
records.boost.trigger="dealHit";foe.hp=80;foe.ability="NONE";user.stages.attack=0;hit.run(ctx);assert(user.stages.attack==3)
records.guard.trigger="receiveHit";foe.ability="GUARD";ctx.move.flags=0;hit.run(ctx);assert(user.hp==88)
print("PASS: presets, expanded conditions/actions, hit triggers, substitutes, knockout and faint processing")

