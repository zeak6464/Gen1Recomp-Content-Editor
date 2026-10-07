package.path="tools/content-editor/?.lua;runtime/gen1recomp/?.lua;"..package.path
package.loaded["src.link.Json"]={}
package.loaded["src.core.Data"]={}
package.loaded["ProcessRunner"]={}
package.loaded["src.core.GameVersion"]={
  cachePrefix=function(version) return version.."/" end,
  revisions=function() return {{sha1="abcd"}} end,
  info=function() return {sha1="abcd"} end,
}
local files={}
local Fs={prefix="emerald/"}
Fs.read=function(path) return files[Fs.prefix..path] end
package.loaded["src.import.CacheFs"]=Fs
local Contract=require("src.import.CacheContract")
Contract.isReady=function() error("UI hints must not walk cache assets") end
local D=require("DataSource")
assert(not D.hasImportedCacheMarker("ruby"))
files["ruby/rom-cache.complete"]=Contract.markerFor("ruby","abcd")
assert(D.hasImportedCacheMarker("ruby"))
assert(Fs.prefix=="emerald/","Hint must not change the active cache mount")
files["ruby/rom-cache.complete"]="rom-cache-v1-ruby:abcd"
assert(not D.hasImportedCacheMarker("ruby"),"Stale cache formats must not appear imported")
files["ruby/rom-cache.complete"]=Contract.markerFor("ruby","other-rom")
assert(not D.hasImportedCacheMarker("ruby"),"Wrong ROM identity must not appear imported")
Fs.read=function() error("unreadable") end
assert(not D.hasImportedCacheMarker("ruby") and Fs.prefix=="emerald/")
print("ok lightweight cache hints validate marker identity and preserve active mount")
