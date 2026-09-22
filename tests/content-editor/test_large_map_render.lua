package.path = "tools/content-editor/?.lua;" .. package.path
package.loaded.ModIO = {}
package.loaded.Preview = {}
love = { graphics = {
  push = function() end, pop = function() end,
  translate = function() end, setColor = function() end,
} }
local L = require("LayeredMap")
local lookups, draws, revision = 0, 0, 1
L.sourceDescriptor = function(_, id)
  lookups = lookups + 1
  if id == "missing" then return nil end
  return { id = id, revision = revision }
end
L.drawSourceTile = function(_, desc)
  assert(desc.revision == revision, "stale descriptor after edit")
  draws = draws + 1
end
local source = { id = "large", cellWidth = 512, cellHeight = 512,
  layers = { { cells = {} } } }
for i = 1, 512 * 512 do
  source.layers[1].cells[i] = { source = "terrain", tile = 0 }
end
local renderer = L.previewRenderer({}, source)
renderer:draw(160, 160, 320, 240)
assert(draws == 23 * 18, "only visible cells plus margin should draw")
assert(lookups == 1, "resolve once per source, not once per cell")
revision = 2
renderer:draw(160, 160, 320, 240)
assert(lookups == 2, "refresh descriptors on the next draw")
local resolve = L.sourceResolver({})
assert(resolve("missing") == nil and resolve("missing") == nil)
assert(lookups == 3, "cache missing sources within the draw")
print("large map rendering: passed (262144 cells, 414 visible draws, 1 source lookup per frame)")
