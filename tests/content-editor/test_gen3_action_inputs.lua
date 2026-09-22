local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;"..runtime.."/?.lua;"..package.path
require("src.core.GameVersion").set("firered")
local I=require("Gen3ActionInputs");local Story=require("Gen3EventStory")
local encode=require("ModWriter").encodeLua
local S={project={gen3={map_scripts={}}},data={_g3StoryMovements={}}}
local catalog={root={{op="call",target="prepare"},{op="setflag",flag=2055},{op="special",id=312},{op="end"}},
  prepare={{op="setvar",var=32772,value=410,[1]=32772,[2]=410},
    {op="setvar",var=32773,value=30},{op="setvar",var=32774,value=0},{op="special",id=443},
    {op="setvar",var=32772,value=999},{op="return"}}}
local function battle(root)
  for _,row in ipairs(Story.rows(S,root or "root",catalog)) do if row.script==(root or "root") and row.inputs then return row end end
end
local before=encode(catalog);local b=assert(battle())
-- Colosseum action 32 must expose its real prepared inputs, not an unknown label.
catalog.colosseum={{op="setvar",var=0x8004,value=1},{op="setvar",var=0x8005,value=0},{op="special",id=32},{op="end"}}
local colosseum=Story.rows(S,"colosseum",catalog)[3]
assert(colosseum.label=="Start a multiplayer battle at the Colosseum")
assert(colosseum.inputs[1].value==1 and colosseum.inputs[2].value==0)
assert(colosseum.inputs.help:find("current game skips",1,true))
assert(I.edit(S,catalog,colosseum.inputs[1],2))
assert(I.edit(S,catalog,colosseum.inputs[2],1))
assert(S.project.gen3.map_scripts.colosseum[1].value==2 and S.project.gen3.map_scripts.colosseum[2].value==1)
assert(S.project.gen3.map_scripts.colosseum[3].id==32 and catalog.colosseum[1].value==1)
catalog.colosseum=nil;S.project.gen3.map_scripts.colosseum=nil
assert(b.inputs[1].value==410 and b.inputs[2].value==30 and b.inputs[3].value==0)
assert(encode(catalog)==before,"Browsing must not rewrite script inputs")
assert(I.edit(S,catalog,b.inputs[1],150));b=battle();assert(b.inputs[1].value==150)
assert(I.edit(S,catalog,b.inputs[2],70));b=battle();assert(b.inputs[2].value==70)
assert(I.edit(S,catalog,b.inputs[3],13));b=battle();assert(b.inputs[3].value==13)
assert(not I.edit(S,catalog,b.inputs[2],101) and not I.edit(S,catalog,b.inputs[2],0))
assert(S.project.gen3.map_scripts.prepare[1].value==150 and S.project.gen3.map_scripts.prepare[1][2]==150)
assert(S.project.gen3.map_scripts.root==nil and encode(catalog)==before,"Keep battle type, flags, and source data unchanged")
assert(S.project.gen3.map_scripts.prepare[5].value==999,"Edit the captured opponent, not a later variable assignment")
-- A conditional path cannot provide the opponent for the other path.
catalog.branch={{op="compare_var_to_value",var=1,value=0},{op="goto_if",cond=1,target="prepare"},{op="special",id=312},{op="end"}}
assert(battle("branch").inputs.newBattle,"A conditional setup must not leak to the other path")
catalog.empty={{op="special",id=312},{op="end"}}
local empty=battle("empty")
assert(empty.inputs.newBattle and I.prepareBattle(S,catalog,empty.inputs.newBattle,{species=151,level=50,item=0}))
assert(S.project.gen3.map_scripts.empty[1].op=="setwildbattle" and S.project.gen3.map_scripts.empty[2].id==312)
-- An input with no known assignment is explicitly dynamic, then becomes editable.
catalog.dynamic={{op="special",id=0x17C},{op="end"}}
local r=Story.rows(S,"dynamic",catalog)[1]
assert(r.inputs[1].value==nil and I.edit(S,catalog,r.inputs[1],25))
local script=S.project.gen3.map_scripts.dynamic
assert(script[1].op=="setvar" and script[1].var==0x8004 and script[1].value==25 and script[2].id==0x17C)
catalog.query={{op="setvar",var=0x8004,value=0},{op="specialvar",[1]=0x800D,[2]=0x147},{op="end"}}
local query=Story.rows(S,"query",catalog)[2]
assert(#query.inputs==2 and I.edit(S,catalog,query.inputs[2],0x4001))
assert(S.project.gen3.map_scripts.query[2][1]==0x4001 and S.project.gen3.map_scripts.query[2][2]==0x147)
-- Execute edited preparation with the actual runtime handlers, including the
-- fateful-encounter mark and legendary battle flags.
local scripts={root=catalog.root,prepare=S.project.gen3.map_scripts.prepare}
local received
local adapters=require("src.core.game3.scripting.adapters").stub({startWildBattle=function(foe,done,opts)
  received=foe;assert(opts.legendary);done("win")
end})
local vm=require("src.core.game3.scripting.vm").new({store=require("src.core.game3.scripting.flags").newStore(),scripts=scripts,adapters=adapters})
assert(vm:startTalk("root",1,1))
for _=1,100 do vm:tick();if not vm:isRunning() then break end end
assert(received and received.species==150 and received.level==70 and received.item==13,encode(received))
assert(received.legendary and received.fatefulEncounter)
print("PASS: editable prepared opponents, cross-script inputs, branch isolation, preserved source and legendary VM behavior")
