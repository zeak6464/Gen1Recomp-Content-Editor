package.path="tools/content-editor/?.lua;"..package.path
local hook
local Ui={bounceOffset=function(kind) return kind=="mon" and -14 or 2 end}
local battle={_st={player={species=681},enemy={species=681},battlers={[2]={species=681},[3]={species=1}}}}
local present={}
package.loaded["src.core.game3.battle.ui"]=Ui
package.loaded["src.core.game3.battle"]=battle
package.loaded["src.core.game3.battle.anim"]={shownBattler=function(_,b) return b end,present=function() return present end}
package.loaded["src.core.game3.pokemon"]={speciesOf=function(mon) return mon.species end}
package.loaded["src.mods.Runtime"]={call=function(_,original,...) if hook then return hook(original,...) end return original(...) end}
require("Gen3BattlePositionsRuntime").install({content={pokemon={get=function() return {index=681} end}},
  hooks={wrap=function(_,_,fn) hook=fn end}}, {ACCELGOR={frontY=-5,backY=8}})
assert(Ui.bounceOffset("mon",1)==-19)
assert(Ui.bounceOffset("mon",0)==-6)
assert(Ui.bounceOffset("mon",2)==-6)
assert(Ui.bounceOffset("mon",3)==-14)
assert(Ui.bounceOffset("hb",1)==2)
present={substitute=true};assert(Ui.bounceOffset("mon",1)==-14)
present={transformSpecies=1};assert(Ui.bounceOffset("mon",1)==-14)
present={};battle._st.enemy.species="ACCELGOR";assert(Ui.bounceOffset("mon",1)==-19)
hook=nil;assert(Ui.bounceOffset("mon",1)==-14,"Unload must restore the original offset")
print("PASS: battle positions preserve mod lift, support both sides/doubles, skip substitutes, resolve transforms and unload")
