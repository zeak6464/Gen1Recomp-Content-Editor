package.path="tools/content-editor/?.lua;"..package.path
local Status=require("ProjectStatus")
local now, reads=0,0
love={timer={getTime=function() return now end}}
local function read(value) reads=reads+1;return value end
local D={
  loadPrefs=function() return read({recompRoot="linked"}) end,
  isValidRecompRoot=function() return read(true) end,
  hasImportedCache=function() error("Full cache validation must never run during drawing") end,
  hasImportedCacheMarker=function(v) return read(v=="emerald") end,
  hasLocalCache=function() return read(false) end,
  recompHasVersion=function(_,v) return read(v=="red") end,
}
local mods={listMods=function() return read({"example"}) end}
local S={version="red",dataPrefs={}}
local order={"red","emerald","gold"}
local first=Status.get(S,D,mods,order)
assert(first.ready.red and first.ready.emerald and not first.ready.gold)
assert(first.imported.emerald and not first.imported.red and first.validRoot)
local count=reads
for i=1,180 do now=i/100;assert(Status.get(S,D,mods,order)==first) end
assert(reads==count,"Drawing successive frames must not perform disk discovery")
now=3
assert(Status.get(S,D,mods,order)~=first,"External changes refresh after the TTL")
for _,change in ipairs({function() S.version="emerald" end,
    function() S.project={} end,function() S.dataSource="imported" end,
    function() S.dataPrefs={} end}) do
  local previous=Status.get(S,D,mods,order)
  change()
  assert(Status.get(S,D,mods,order)~=previous,"Context changes refresh immediately")
end
print("ok project status avoids per-frame IO and refreshes on context changes")
