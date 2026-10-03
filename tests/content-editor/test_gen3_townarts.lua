-- Which Town Map pictures the editor offers (Gen3UiContent.townArts): the
-- game's own, plus the other game's when its import is there. Plain LuaJIT. From
-- the repository root:
--   luajit tests/content-editor/test_gen3_townarts.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local game, haveFr, haveEm = "emerald", false, false
package.loaded["Generation"] = { id = function() return game end }
package.loaded["Gen3FrLink"] = { NAME = "FireRed", editor = function() return haveFr and { read = function(p) return "fr:" .. p end } or nil end }
package.loaded["Gen3EmLink"] = { NAME = "Emerald", editor = function() return haveEm and { read = function(p) return "em:" .. p end } or nil end }
for _, m in ipairs({ "Kit", "Gen3Resources", "ChoicePicker" }) do package.loaded[m] = package.loaded[m] or {} end
local U = require("Gen3UiContent")
local function ids(list) local t = {} for _, a in ipairs(list) do t[#t + 1] = a.id end return table.concat(t, ",") end

run("Emerald without the FireRed import: Hoenn only, view only", function()
  game, haveFr = "emerald", false
  local a = U.townArts({})
  assert(ids(a) == "hoenn" and not a[1].editable and not a[1].source)
end)

run("Emerald with the FireRed import: Kanto and Sevii pictures from that import", function()
  game, haveFr = "emerald", true
  local a = U.townArts({})
  assert(ids(a) == "hoenn,kanto,sevii123,sevii45,sevii67")
  assert(a[2].source and not a[2].editable and a[2].source.read(a[2].path) == "fr:data/generated/gba/region_map/kanto_map.png")
  assert(a[2].source.NAME == "FireRed")
end)

run("FireRed: its own pictures are editable; Hoenn appears with the Emerald import, view only", function()
  game, haveEm = "firered", false
  local a = U.townArts({})
  assert(ids(a) == "kanto,sevii123,sevii45,sevii67" and a[1].editable and not a[1].source)
  haveEm = true
  a = U.townArts({})
  assert(ids(a) == "kanto,sevii123,sevii45,sevii67,hoenn")
  local h = a[#a]
  assert(h.source and not h.editable and h.source.read(h.path) == "em:data/generated/gba/rse/region_map/map.png")
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
