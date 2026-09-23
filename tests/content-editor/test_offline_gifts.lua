package.path="tools/content-editor/?.lua;tools/content-editor/panels/?.lua;runtime/gen1recomp/?.lua;"..package.path
love=require("tests.love_stub")
love.filesystem.read=function(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local Gifts=require("OfflineGifts")
local Runtime=require("OfflineGiftsRuntime")
local Writer=require("ModWriter")
local Serializer=require("src.core.SaveSerializer")
local Events=require("src.world.gen2.Events")
local Decorations=require("src.core.gen2.Decorations")
local data={items={POTION={name="Potion",pocket="ITEM"},ANTIDOTE={name="Antidote",pocket="ITEM"}},pokemon={},maps={PALLET_TOWN={}},constants={bagSize=1}}
local S={version="gold",data=data,project=require("State").blankProject("gift_test")}
S.project.game="gold"
local id=Gifts.new(S);local row=S.project.offlineGifts[id]
assert(Gifts.key({id="a-b"},id)~=Gifts.key({id="a_b"},id),"Gift script owner names collide")
local key=assert(Gifts.build(S,id))
local save={inventory={ANTIDOTE=1},party={}}
local events=Events.new()
local commands={}
local mod={id="gift_test",generation=2,world={game={save=save,data=data,world={events=events}}},content={commands={register=function(_,id,record) commands[id]=record end}}}
-- Run the emitted runtime, rather than only the source module.
local emitted={};Gifts.emit(S.project,Writer.encodeLua,emitted,2)
assert(loadstring("return function(mod)\n"..table.concat(emitted,"\n").."\nend"))()(mod)
local messages={}
local Vm=require("src.script.gen2.Vm")
local vm=Vm.new(S.project.scripts,{},events,{commands=commands,
  showText=function(text,done) messages[#messages+1]=text;done() end,
  waitButton=function(done) done() end})
local function run()
  assert(vm:start(key));for _=1,30 do vm:update() end
  assert(not vm:running(),"Delivery script did not finish")
  assert(not vm.failedVerbs or not next(vm.failedVerbs),"Gift command failed")
  return messages[#messages]
end
assert(run()==row.full);assert(not save.modData,"Full bag consumed the gift")
save.inventory={};save.bagOrder={}
assert(run()==row.title.."\n"..row.message);assert(save.inventory.POTION==1)
assert(run()==row.done);assert(save.inventory.POTION==1)
save=assert(Serializer.decode(Serializer.encode(save)));mod.world.game.save=save
assert(run()==row.done);assert(save.inventory.POTION==1,"Gift repeated after reload")
local second=Gifts.new(S);local other=S.project.offlineGifts[second]
other.kind="decoration";other.decoration=3
assert(Runtime.claim(mod,S.project.offlineGifts,second,2,save,data,events)==1)
assert(Decorations.owns(events,3));assert(Runtime.claim(mod,S.project.offlineGifts,second,2,save,data,events)==2)
assert(Runtime.claim({id="other_mod"},S.project.offlineGifts,id,2,save,data,events)==1,"Mods shared claim state")
other.enabled=false
assert(Runtime.claim(mod,S.project.offlineGifts,second,2,{},data,events)==0)
other.enabled=true;other.kind="pokemon";other.species="PIKACHU"
assert(Runtime.claim(mod,S.project.offlineGifts,second,1,{party={1,2,3,4,5,6}},data)==3)
data.moves={TACKLE={pp=35}}
data.pokemon.PIKACHU={name="PIKACHU",index=25,growthRate="MEDIUM_FAST",types={"ELECTRIC"},catchRate=190,
  baseStats={hp=35,attack=55,defense=40,speed=90,special=50,specialAttack=50,specialDefense=50},
  level1Moves={"TACKLE"},learnset={},levelMoves={{level=1,move="TACKLE"}}}
for _,gen in ipairs({1,2}) do
  local recipient={player={name="TEST",id=123},party={}}
  assert(Runtime.claim(mod,S.project.offlineGifts,second,gen,recipient,data)==1)
  assert(#recipient.party==1 and recipient.party[1].species=="PIKACHU" and recipient.party[1].level==5)
  assert(recipient.pokedex.owned.PIKACHU and recipient.party[1].otId==123)
end
row.quantity=100;assert(not pcall(Gifts.validate,S.project.offlineGifts,2));row.quantity=1
local reopened=assert(loadstring(Writer.serializeProject(S.project)))()
assert(reopened.offlineGifts[id]._scripts[key])
S.project.scripts[key][1]={op="end"}
assert(not Gifts.build(S,id),"Rebuild erased manual scripts")
S.version="red";S.project=require("State").blankProject("red_gift");S.project.game="red"
id=Gifts.new(S);row=S.project.offlineGifts[id];row.map="PALLET_TOWN"
assert(Gifts.build(S,id))
local scripts=Writer.compileTalkScripts(S.project)
assert(scripts.PALLET_TOWN.talk[row.textId][2][1]=="red_gift:offline_gift")
local redSave={inventory={}}
assert(Runtime.claim({id="red_gift"},S.project.offlineGifts,id,1,redSave,data)==1)
assert(Runtime.claim({id="red_gift"},S.project.offlineGifts,id,1,redSave,data)==2)
assert(loadstring(Writer.emitMain(S.project,data)))
local D=require("Gen2Decorations")
S.project.decorations={["3"]=require("src.mods.Merge").deepCopy(Decorations.ATTRIBUTES[3])}
S.project.decorations["3"].name="COZY"
local out={};D.emit(S.project,Writer.encodeLua,out)
local patches={}
assert(loadstring("return function(mod) "..table.concat(out,"\n").." end"))()({generation=2,content={decorations={patch=function(_,id,value) patches[id]=value end}}})
assert(patches["deco:3"].name=="COZY" and patches["deco:3"].flag==nil)
S.project.decorations["3"].flag=1;assert(not pcall(D.validate,S.project.decorations))
local saved,problem=require("ModIO").save("unused-test-path",S.project)
assert(not saved and problem:find("Gen 2"),"Wrong-generation decoration export was allowed")
print("PASS: offline gifts (Gen 1/2 VM delivery, full bag, duplicate/reloaded/disabled claims, namespace isolation, script preservation, decoration export)")
