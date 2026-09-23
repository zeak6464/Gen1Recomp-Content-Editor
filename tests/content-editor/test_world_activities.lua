package.path="tools/content-editor/?.lua;runtime/gen1recomp/?.lua;"..package.path
love=require("tests.love_stub")
love.filesystem.read=function(path) local f=assert(io.open(path,"rb"));local b=f:read("*a");f:close();return b end
local Writer=require("ModWriter")
local Safari=require("SafariSettings")
local Version=require("src.core.GameVersion")
local yes=true;local messages={}
package.loaded["src.render.TextBox"]={new=function(_,text,cb) return {text=text,cb=cb} end}
package.loaded["src.ui.ChoiceBox"]={new=function(_,cb) return {cb=function() cb(yes) end} end}
local function game(money)
  return {save={money=money,player={name="TEST"}},data={text={},maps={SAFARI_ZONE_CENTER={warps={{x=1,y=1},{x=2,y=1}}}}},stack={push=function(_,box)
    messages[#messages+1]=box.text;if box.cb then box.cb() end
  end}}
end
local walk,warp,queued
local ow={player={cellX=3,cellY=2},map={warpAtCell=function() return {def={dest="zone"}} end},
  scriptMove=function(_,_,direction,count,done) walk={direction,count};if done then done() end end,
  takeWarp=function(_,dest) warp=dest end,queueScript=function(_,rows) queued=rows end}
local contributions,fields={},{}
local mod={id="activities",generation=1,content={
  map_scripts={register=function(_,id,row) contributions[id]=row end},field={patch=function(_,id,row) fields[id]=row end}}}
local p={safariSettings=Safari.defaults(1)};p.safariSettings.fee=250;p.safariSettings.balls=12;p.safariSettings.steps=800
local out={};Safari.emit(p,Writer.encodeLua,out,1)
assert(loadstring("return function(mod) "..table.concat(out,"\n").." end"))()(mod)
local Data=require("src.core.Data");local Maps=require("src.script.MapScripts")
local original=require("data.scripts.safari").SAFARI_ZONE_GATE
Maps.attachBase("SAFARI_ZONE_GATE",original)
Data.map_scripts={SAFARI_ZONE_GATE={contributions.SAFARI_ZONE_GATE}}
local gate=Maps.get("SAFARI_ZONE_GATE")
Version.set("red")
local g=game(1000)
assert(gate.onStep(g,ow,3,2));assert(g.save.money==750 and g.save.safari.balls==12 and g.save.safari.steps==800)
assert(warp.dest=="zone" and walk[1]=="up");assert(fields.safari.exitWarp.map=="SAFARI_ZONE_GATE")
gate.onStep(g,ow,3,2);assert(g.save.money==750,"Active visit was charged twice")
ow.player.cellY=1;gate.onEnter(g,ow);assert(queued and queued[1][1]=="ask","Early-exit script was lost");ow.player.cellY=2
g=game(100);gate.onStep(g,ow,3,2);assert(not g.save.safari and g.save.money==100 and walk[1]=="down")
yes=false;g=game(1000);gate.onStep(g,ow,3,2);assert(not g.save.safari and g.save.money==1000);yes=true
Version.set("yellow");g=game(46);gate.onStep(g,ow,3,2);assert(g.save.safari.balls==3 and g.save.money==0)
g=game(0);for _=1,3 do gate.onStep(g,ow,3,2);assert(not g.save.safari) end
gate.onStep(g,ow,3,2);assert(g.save.safari.balls==1)
Data.map_scripts=nil;assert(Maps.get("SAFARI_ZONE_GATE")==original,"Disabled Safari mod did not restore base")
assert(not pcall(Safari.validate,p.safariSettings,2))
p.safariSettings.balls=0;assert(not pcall(Safari.validate,p.safariSettings,1));p.safariSettings.balls=12

local House=require("src.world.gen2.TrainerHouse")
local Hooks=require("src.mods.Hooks").new();local Runtime=require("src.mods.Runtime")
local oldEvents,oldHooks=Runtime.events,Runtime.hooks;Runtime.install(oldEvents,Hooks)
local TH=require("TrainerHouseEditor");local row=TH.defaults();row.name="VISITOR";row.daily=false
row.party={{species="PIKACHU",level=17,item="BERRY",moves={"TACKLE"}}}
local native={classes={CAL={index=12,id="CAL",name="CAL",trainers={
  {name="ROUTE CAL",party={{species="CHIKORITA",level=10}}},
  {name="CAL",party={{species="BAYLEEF",level=30}}},
  {name="CAL",party={{species="MEGANIUM",level=50}}}}}}}
mod={id="activities",generation=2,hooks={wrap=function(_,key,fn) Hooks:wrap(key,fn,0,"activities") end}}
out={};TH.emit({trainerHouse=row},Writer.encodeLua,out)
assert(loadstring("return function(mod) "..table.concat(out,"\n").." end"))()(mod)
local save={engineFlags={[86]=true}}
assert(House.hasCustomTrainer(save))
local entry=House.lookup(native,save,12,2)
assert(entry.name=="VISITOR" and entry.roster[1].level==17 and entry.roster[1].item=="BERRY")
local battleData={pokemon={PIKACHU={name="PIKACHU",baseStats={hp=35,attack=55,defense=40,speed=90,specialAttack=50,specialDefense=50},types={"ELECTRIC"},levelMoves={}}},moves={TACKLE={pp=35}}}
local party=require("src.world.gen2.Trainers").party(battleData,entry)
assert(#party==1 and party[1].level==17 and party[1].item=="BERRY" and party[1].moves[1].id=="TACKLE" and party[1].moves[1].pp==35)
assert(House.name(native,save,12,2)=="VISITOR" and House.name(native,save,12,1)=="ROUTE CAL")
entry.roster[1].level=99;assert(House.lookup(native,save,12,2).roster[1].level==17,"Battle mutated authored roster")
assert(native.classes.CAL.trainers[2].party[1].level==30 and not save.mysteryGift,"Custom visitor overwrote native data/save")
local Vm=require("src.script.gen2.Vm")
local function check(map,flag)
  local vm=Vm.new({test={{op="checkflag",args={flag,0}},{op="end"}}},{},require("src.world.gen2.Events").new(),{mapId=function() return map end,getEngineFlag=function() return true end})
  assert(vm:start("test"));for _=1,5 do vm:update() end;return vm.scriptVar
end
assert(check("TRAINER_HOUSE_B1F",86)==0,"Repeat-battle option ignored")
assert(check("TRAINER_HOUSE_B1F",85)==1 and check("OTHER_MAP",86)==1,"Daily bypass leaked to another flag/map")
Hooks:removeOwner("activities")
assert(not House.hasCustomTrainer(save));assert(House.lookup(native,save,12,2).roster[1].species=="MEGANIUM")
assert(check("TRAINER_HOUSE_B1F",86)==1,"Removing mod left repeat battles enabled")
row.daily=true;require("TrainerHouseRuntime").install(mod,row)
assert(check("TRAINER_HOUSE_B1F",86)==1,"Daily mode bypassed an existing battle flag")
Hooks:removeOwner("activities")
assert(not pcall(TH.validate,row,1));row.party[1].level=101;assert(not pcall(TH.validate,row,2))
Runtime.install(oldEvents,oldHooks)
print("PASS: Gen 1 Safari composed entrance/exit, payment, decline, capacity, Yellow assistance; Gen 2 Trainer House export, roster isolation, daily gate and unload")
