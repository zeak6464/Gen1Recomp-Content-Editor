package.path="tools/content-editor/?.lua;"..package.path
local value="43"
package.loaded.Theme={PAL={text={}}}
package.loaded.Kit={scale=1,caption=function() end,text=function() end,textfield=function(key,x,y,w,h,old) return key:find('/setting/flag') and value or old end,
  ellipsize=function(_,text) return text end,offerTooltip=function() end}
local C=require("Gen3EventCommands")
local step={op="setflag",flag=42,opcode=41,extra="preserve"}
local changes=0
local function changed() changes=changes+1 end
assert(C.draw({},"test",step,0,0,400,changed))
assert(step.flag==43 and step.opcode==41 and step.extra=="preserve" and changes==1)
for _,invalid in ipairs({"-1","1.5","65536","oops",""}) do
  value=invalid;C.draw({},"test",step,0,0,400,changed)
  assert(step.flag==43 and changes==1)
end
assert(C.draw({},"test",{op="setflag",42},0,0,400,changed))
assert(C.draw({},"test",{op="unknown"},0,0,400,changed))
assert(C.summary(step)=="Turn a saved switch ON: 43")
assert(C.label("unknown")=="Undescribed action: unknown")
print("PASS: friendly commands preserve native fields, validate switch IDs, and fall back safely")
