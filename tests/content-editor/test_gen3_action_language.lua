local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;"..runtime.."/?.lua;"..package.path
local L=require("Gen3ActionLanguage")
local C=require("Gen3EventCommands")
for _,op in pairs(require("src.core.game3.scripting.opcodes").TABLE) do
  assert(L.names[op.name] or C.definitions[op.name],"Missing readable action name: "..op.name)
  local step={op=op.name}
  for i=1,#op.args do
    assert((L.schemas[op.name] or {})[i],"Missing settings for "..op.name.." input "..i)
    step[i]=0
  end
  for _,field in ipairs(L.fields(step)) do assert(not field.label:find("meaning not yet described"),op.name) end
end
local encode=require("ModWriter").encodeLua
for name,id in pairs(require("src.core.game3.scripting.stdscripts").SPECIAL) do
  assert(L.specials[id],"Missing built-in action description: "..name)
end
local choiceState={data={pokemon={BULBASAUR={index=1}},moves={TACKLE={index=33}},trainers={YOUNGSTER={index=1,name="Ben"}}},
  project={pokemon={BULBASAUR={index=1,name="Bulbasaur"}},maps={TEST={objects={{localId=2,editorName="Nurse",x=3,y=4}}}}},mapId="TEST"}
local ids,labels=L.choiceData(choiceState,"species",65000)
assert(labels["1"]=="Bulbasaur (1)" and labels["65000"],"Choices must include edits and preserve unknown values")
ids,labels=L.choiceData(choiceState,"move",33);assert(labels["33"]=="TACKLE (33)")
ids,labels=L.choiceData(choiceState,"trainer",1);assert(labels["1"]=="Ben (1)")
ids,labels=L.choiceData(choiceState,"movingCharacter",0)
assert(labels["0"]=="All moving characters" and labels["255"]=="The player" and labels["2"]=="Nurse at 3, 4")
assert(L.options.fade[1]=="Fade to black" and L.options.direction[3]=="Left")
local ML=require("Gen3MovementLanguage")
assert(ML.label(20)=="Jump two tiles down" and ML.label(61)=="Run down" and ML.label(104)=="Break a rock")
assert(ML.label(200):find("Unrecognized movement 200"))
local seen={};for _,id in ipairs(ML.choices) do assert(not seen[id]);seen[id]=true end
local source={op="special",[1]=0,id=0,opcode=37,extra={keep=true}}
local before=encode(source)
assert(L.label(source)=="Heal the player's Pokémon")
assert(L.label({op="specialvar",[1]=32781,[2]=60})=="Open Pokémon storage and remember the answer")
assert(L.label({op="special",id=65535}):find("purpose not yet described"))
local fields=L.fields(source)
assert(encode(source)==before,"Opening a description must not mutate source data")
L.set(source,fields[1],60)
assert(source.id==60 and source[1]==60 and source.opcode==37 and source.extra.keep)
local numeric={op="setvar",[1]=16384,[2]=3};local f=L.fields(numeric)
L.set(numeric,f[2],4);assert(numeric[2]==4 and numeric.value==nil)
local named={op="setvar",var=16384,value=3};f=L.fields(named)
L.set(named,f[2],4);assert(named.value==4 and named[2]==nil)
assert(not L.validNumber({op="fadescreen"},{index=1},256))
assert(L.validNumber({op="addmoney"},{index=1},100000))
assert(not L.validNumber({op="setflag"},{index=1},65536))
assert(not L.validNumber({op="setflag"},{index=1},-1))
assert(not L.validNumber({op="setflag"},{index=1},1.5))
local Story=require("Gen3EventStory")
local S={project={gen3={map_scripts={}}},data={_g3StoryMovements={}}}
local catalog={root={{op="special",id=0},{op="specialvar",[1]=32781,[2]=60},{op="addmoney",[1]=100},{op="end"}}}
local rows=Story.rows(S,"root",catalog)
assert(rows[1].label=="Heal the player's Pokémon" and rows[2].label:find("Open Pokémon storage") and rows[3].label=="Give the player money")
assert(rows[2].script=="root" and rows[2].index==2)
print("PASS: readable game actions, source ownership, alias preservation and numeric bounds")
