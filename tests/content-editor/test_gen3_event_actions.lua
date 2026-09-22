local runtime=assert(os.getenv("POKEPORT_RECOMP"))
package.path="tools/content-editor/?.lua;"..runtime.."/?.lua;"..package.path
require("src.core.GameVersion").set("firered")
local A=require("Gen3EventActions")
local copy=require("src.mods.Merge").deepCopy
local encode=require("ModWriter").encodeLua
local S={project={id="test",text={}},data={text={}}}
local steps={{op="lock"}}
for _,row in ipairs(A.create(S,"text")) do steps[#steps+1]=row end
steps[#steps+1]={op="end"}
local before=encode(steps)
local rows=A.rows(steps)
assert(#rows==3 and rows[2].first==2 and rows[2].last==5)
assert(#A.rows(steps,true)==6 and encode(steps)==before)
local selected,changed=A.edit(steps,rows,2,"copy")
assert(changed and selected==3 and #steps==10)
assert(steps[2]~=steps[6] and steps[2].ptr==steps[6].ptr)
local original=steps[2].ptr
A.setText(S,steps[6],"Different dialogue")
assert(steps[2].ptr==original and steps[6].ptr~=original)
assert(A.text(S,steps[2])=="Hello!")
assert(A.text(S,steps[6])=="Different dialogue")
rows=A.rows(steps);A.edit(steps,rows,3,"up")
assert(A.text(S,steps[2])=="Different dialogue")
rows=A.rows(steps);A.edit(steps,rows,2,"down")
rows=A.rows(steps);A.edit(steps,rows,3,"delete")
assert(encode(steps)==before)
rows=A.rows(steps);local at=A.insert(steps,rows,3,A.create(S,"wait"))
assert(at==6 and steps[6].op=="delay" and steps[7].op=="end")
local snapshot=encode(steps)
local _,edited=A.edit(steps,A.rows(steps),1,"up")
assert(not edited and encode(steps)==snapshot)
local positional={op="message",[1]=original,opcode=103,extra={keep=true}}
A.setText(S,positional,"New words")
assert(not positional.ptr and positional[1]~=original and positional.extra.keep and positional.opcode==103)
local native={{op="message",ptr=original},{op="waitmessage"},{op="yesnobox",x=20,y=8}}
assert(#A.rows(native)==3,"Do not fold choice prompts into ordinary Show text")
local store=require("src.core.game3.scripting.flags").newStore()
local received={}
local adapters=require("src.core.game3.scripting.adapters").stub({onMessage=function(t) received[#received+1]=t end,
  openMessageStay=function(t) received[#received+1]=t end})
local vm=require("src.core.game3.scripting.vm").new({store=store,scripts={TEST=steps},text=S.project.text,adapters=adapters})
assert(vm:startTalk("TEST",1,1))
for _=1,300 do vm:tick();if not vm:isRunning() then break end end
assert(not vm:isRunning() and #received>0)
print("PASS: logical action edits, isolated text, native fallback, and FireRed VM execution")
