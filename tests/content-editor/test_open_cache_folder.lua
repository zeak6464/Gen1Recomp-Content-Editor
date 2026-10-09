package.path = "tools/content-editor/?.lua;" .. package.path
for _, name in ipairs({"src.link.Json", "src.core.Data", "src.import.CacheFs", "ProcessRunner"}) do
  package.loaded[name] = {}
end
package.loaded["src.core.GameVersion"] = {
  cachePrefix = function(version) return version == "red" and "" or version .. "/" end,
}
local created, writable = {}, true
love = {filesystem = {
  getSaveDirectory = function() return "C:/Users/Test User/AppData/Roaming/editor" end,
  getInfo = function() error("Mounted folders must not determine physical cache paths") end,
  createDirectory = function(path)
    created[#created + 1] = path
    return writable
  end,
}}
local D = require("DataSource")
local path = D.importedCacheFolder("crystal")
assert(path:match("[/\\]crystal$"))
assert(#created == 0, "Drawing the button must not create directories")
assert(D.importedCacheFolder("crystal", true) == path)
assert(created[1] == "crystal", "Create the selected game's physical save folder")
assert(D.importedCacheFolder("red", true) == love.filesystem.getSaveDirectory())
assert(created[2] == ".")
writable = false
assert(D.importedCacheFolder("gold", true) == nil, "Do not launch a nonexistent destination")
love.filesystem.getSaveDirectory = function() return "" end
assert(D.importedCacheFolder("crystal", true) == nil)
print("ok open cache folder uses a physical save-directory destination")
