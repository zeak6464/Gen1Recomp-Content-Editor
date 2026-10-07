package.path="tools/content-editor/?.lua;runtime/gen1recomp/?.lua;"..package.path
local Decode=require("Gen3Decode")
package.loaded["Gen3Connections"]={normalize=function(v) return v or {} end,recover=function() end}
package.loaded["src.mods.Schemas"]={bindGen3=function() end}
package.loaded["src.import.gba.versions"]={MAPS={}}
local Gen3=require("Gen3")
local source,prepared={},{}
for _,name in ipairs(Gen3.cacheTables) do
  local path="data/generated/"..name..".lua"
  source[path]="return {}"
  prepared[path]={bytes=source[path],value=assert(Decode.decode(source[path]))}
end
source["data/generated/maps.lua"]='return {FR_PALLET_TOWN={width=24,height=20}}'
prepared["data/generated/maps.lua"]={bytes=source["data/generated/maps.lua"],
  value=assert(Decode.decode(source["data/generated/maps.lua"]))}
local count=0
local original=Decode.decode
Decode.decode=function(...) count=count+1;return original(...) end
local data={}
Gen3.load(data,function(path) return source[path] end,nil,prepared)
assert(data.maps.FR_PALLET_TOWN.width==24 and data._editorGen3)
assert(count==0,"All worker-prepared tables must avoid main-thread parsing")
source["data/generated/maps.lua"]='return {EM_LITTLEROOT_TOWN={width=40,height=40}}'
Gen3.load(data,function(path) return source[path] end,nil,prepared)
assert(count==1 and data.maps.EM_LITTLEROOT_TOWN and not data.maps.FR_PALLET_TOWN,
  "A changed cache or different mounted source must not use stale worker results")
local Switch=require("GameSwitch")
local messages={{progress="maps"},{path="maps",bytes="return {}",value={}},{complete=true}}
local job={channel={pop=function() return table.remove(messages,1) end},
  thread={getError=function() return nil end}}
local done,result=Switch.poll(job)
assert(done and result.maps.bytes=="return {}" and job.progress=="maps")
assert(not Switch.poll(job))
job.thread.getError=function() return "worker failed" end
local failed,_,err=Switch.poll(job)
assert(failed and err=="worker failed")
local tick=0
love={timer={getTime=function() tick=tick+.005;return tick end}}
messages={{path="maps",bytes="return {}",value={}},{complete=true}}
job.thread.getError=function() return nil end
assert(not Switch.poll(job),"Transfers must yield when the per-frame budget is spent")
assert(Switch.poll(job),"The next frame must finish processing the queue")
print("ok background game switching, changed cache detection and worker failure handling")
