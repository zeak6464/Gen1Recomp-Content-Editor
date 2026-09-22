local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;"..runtime.."/?.lua;"..package.path
require("src.core.GameVersion").set("firered")
local Story=require("Gen3EventStory")
local A=require("Gen3EventActions")
local D=require("Gen3Dialog")
local encode=require("ModWriter").encodeLua
local S={project={id="story",gen3={map_scripts={}},text={}},data={text={hello=D.encode("Hello there"),question=D.encode("Coming along?")}}}
local catalog={root={{op="checkflag",flag=2},{op="goto_if",cond=1,target="branch"},
  {op="message",ptr="hello"},{op="end"},{op="message",ptr="question"}},
  branch={{op="loadword",dest=0,value="question",[2]="question"},{op="callstd",std=5},{op="return"}},
  loop={{op="goto",target="loop"}},missing={{op="call",target="absent"}}}
local before=encode(catalog)
local rows=Story.rows(S,"root",catalog)
assert(rows[1].label=="If saved switch 2 is ON")
assert(rows[2].text=="Coming along?" and rows[2].depth==1 and rows[2].script=="branch")
assert(rows[2].label=="Ask the player: Yes / No")
assert(rows[3].label=="Otherwise, continue below" and rows[4].text=="Hello there" and #rows==4)
assert(Story.rows(S,"loop",catalog)[1].label=="Repeat earlier behavior")
assert(Story.rows(S,"missing",catalog)[1].label:find("unavailable"))
assert(encode(catalog)==before,"Reading must preserve native scripts")
S.project.gen3.map_scripts.branch=require("src.mods.Merge").deepCopy(catalog.branch)
A.setText(S,S.project.gen3.map_scripts.branch[1],"Changed question")
assert(Story.rows(S,"root",catalog)[2].text=="Changed question")
assert(encode(catalog)==before,"Editing a branch must preserve its original")
local pickup={{op="setorcopyvar",[1]=0x8000,[2]=85},{op="setorcopyvar",[1]=0x8001,[2]=1},{op="callstd",std=1},{op="end"}}
local found=assert(Story.itemPickup(pickup));assert(found.item==85 and found.quantity==1 and found.first==1)
S.data.items={ITEM_MAX_REPEL={index=85}}
catalog.pickup=pickup
local itemRows=Story.rows(S,"pickup",catalog)
assert(#itemRows==1 and itemRows[1].kind=="item" and itemRows[1].label=="Pick up MAX REPEL")
catalog.reward={{op="setorcopyvar",[1]=0x8000,[2]=85},{op="setorcopyvar",[1]=0x8001,[2]=2},{op="callstd",std=0},{op="setflag",flag=2304},{op="end"}}
local rewardRows=Story.rows(S,"reward",catalog)
assert(rewardRows[1].label=="Give the player 2 × MAX REPEL" and not rewardRows[1].pickup)
assert(rewardRows[2].kind=="switch" and rewardRows[2].enabled and rewardRows[2].flag==2304)
print("PASS: branch expansion, dialogue ownership, yes/no, terminal flow, cycles, missing links and read-only browsing")
