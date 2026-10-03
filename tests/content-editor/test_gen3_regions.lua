-- Regions you define (Gen3Regions): membership, overrides, search, what the
-- export carries. Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_gen3_regions.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local R = require("Gen3Regions")
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function fresh() return { project = { game = "emerald" }, data = { maps = { EM_SEVII_ONE_ISLAND = {}, EM_SEVII_TWO_ISLAND = {}, EM_HOENN_OLDALE = {}, EM_OLDALE = {}, FR_KANTO_PALLET = {} } } } end

run("add: names are trimmed, limited and unique", function()
  local S = fresh()
  local a = assert(R.add(S, "  Sevii  "))
  assert(a.name == "Sevii" and a.id == "sevii" and a.color == R.COLORS[1])
  assert(R.add(S, "sevii") == nil and R.add(S, "") == nil)
  local b = assert(R.add(S, "Sevii 2"))
  assert(b.id == "sevii_2" and b.color == R.COLORS[2])
  assert(#R.add(S, ("x"):rep(60)).name == R.NAME_MAX)
end)

run("owner: longest prefix wins, a map is in one region", function()
  local S = fresh()
  local all = R.add(S, "Everything", { "EM_" })
  local sevii = R.add(S, "Sevii", { "EM_SEVII_" })
  assert(R.ownerOf(S.project, "EM_SEVII_ONE_ISLAND") == sevii)
  assert(R.ownerOf(S.project, "EM_OLDALE") == all)
  assert(R.ownerOf(S.project, "FR_KANTO_PALLET") == nil and R.ownerOf(S.project, nil) == nil)
  assert(R.count(S.project, sevii, { "EM_SEVII_A", "EM_SEVII_B", "EM_X" }) == 2)
end)

run("assign: adding by hand, taking out, moving", function()
  local S = fresh()
  local hoenn = R.add(S, "Hoenn", { "EM_HOENN_" })
  local sevii = R.add(S, "Sevii", { "EM_SEVII_" })
  -- a map by hand, whatever its name
  assert(R.assign(S, "FR_KANTO_PALLET", sevii.id) and R.ownerOf(S.project, "FR_KANTO_PALLET") == sevii)
  assert(not R.assign(S, "FR_KANTO_PALLET", sevii.id))
  -- moving it
  assert(R.assign(S, "FR_KANTO_PALLET", hoenn.id) and R.ownerOf(S.project, "FR_KANTO_PALLET") == hoenn)
  assert(#sevii.include == 0 and #hoenn.include == 1)
  -- taking a prefix map out of its region, and putting it back
  assert(R.assign(S, "EM_SEVII_ONE_ISLAND", nil) and R.ownerOf(S.project, "EM_SEVII_ONE_ISLAND") == nil)
  assert(R.ownerOf(S.project, "EM_SEVII_TWO_ISLAND") == sevii)
  assert(R.assign(S, "EM_SEVII_ONE_ISLAND", sevii.id) and R.ownerOf(S.project, "EM_SEVII_ONE_ISLAND") == sevii and #sevii.include == 0)
  -- an explicit add beats another region's prefix
  assert(R.assign(S, "EM_SEVII_TWO_ISLAND", hoenn.id) and R.ownerOf(S.project, "EM_SEVII_TWO_ISLAND") == hoenn)
  assert(R.assign(S, "EM_SEVII_TWO_ISLAND", nil) and R.ownerOf(S.project, "EM_SEVII_TWO_ISLAND") == nil)
end)

run("set: name, colour, prefixes, wording", function()
  local S = fresh()
  local a = R.add(S, "A")
  R.add(S, "B")
  assert(not R.set(S, a.id, "name", "b") and not R.set(S, a.id, "name", "  "))
  assert(R.set(S, a.id, "name", "Alpha") and a.name == "Alpha")
  assert(R.set(S, a.id, "color", R.COLORS[5]) and not R.set(S, a.id, "color", "#123456"))
  assert(R.set(S, a.id, "prefixes", "em_sevii_, fr-x ; EM_SEVII_") and table.concat(a.prefixes, ",") == "EM_SEVII_,FRX")
  assert(not R.set(S, a.id, "prefixes", "EM_SEVII_, FRX"))
  assert(R.set(S, a.id, "navLabel", "sevii map and more") and a.navLabel == ("SEVII MAP AND MORE"):sub(1, 10))
  assert(R.set(S, a.id, "navDesc", ("d"):rep(80)) and #a.navDesc == 40)
  assert(R.set(S, a.id, "navLabel", "") and a.navLabel == nil)
  assert(not R.set(S, "nope", "name", "X"))
end)

run("search: @name, @ and @-", function()
  local S = fresh()
  R.add(S, "Sevii", { "EM_SEVII_" })
  local p = S.project
  assert(R.matches(p, "EM_SEVII_ONE_ISLAND", "@sev") == true and R.matches(p, "EM_SEVII_ONE_ISLAND", "@hoe") == false)
  assert(R.matches(p, "EM_SEVII_ONE_ISLAND", "@") == true and R.matches(p, "EM_OLDALE", "@") == false)
  assert(R.matches(p, "EM_OLDALE", "@-") == true and R.matches(p, "EM_SEVII_ONE_ISLAND", "@-") == false)
  assert(R.matches(p, "EM_OLDALE", "oldale") == nil)
end)

run("suggest: regions for the prefixes the maps use", function()
  local S = fresh()
  local s = R.suggest(S)
  assert(#s == 2 and s[1].name == "Hoenn" and s[1].prefixes[1] == "EM_HOENN_" and s[2].name == "Kanto")
  assert(R.addSuggested(S) == 2 and #R.list(S.project) == 2 and #R.suggest(S) == 0)
  assert(R.ownerOf(S.project, "FR_KANTO_PALLET").name == "Kanto")
  S.data.maps.EM_KANTO_ROUTE_1 = {}
  local more = R.suggest(S)
  assert(#more == 1 and more[1].name == "Kanto" and more[1].prefixes[1] == "EM_KANTO_")
  assert(R.addSuggested(S) == 1 and #R.list(S.project) == 2 and R.ownerOf(S.project, "EM_KANTO_ROUTE_1").name == "Kanto")
end)

run("remove, and the game side only sees wording", function()
  local S = fresh()
  local a = R.add(S, "Sevii", { "EM_SEVII_" })
  assert(not R.used(S.project))
  R.set(S, a.id, "navLabel", "Sevii Map")
  assert(R.used(S.project) and #R.baked(S.project) == 1 and R.baked(S.project)[1].label == "SEVII MAP")
  assert(not R.used({ game = "firered", gen3Regions = S.project.gen3Regions }))
  _G.love = { filesystem = { read = function() return "return {}" end } }
  local out, cfgs = {}, {}
  R.emit(S.project, function(t) cfgs[#cfgs + 1] = t; return "CFG" end, out)
  _G.love = nil
  assert(#out == 1 and out[1]:find("regionNames.install(mod,CFG)", 1, true) and cfgs[1].regions[1].prefixes[1] == "EM_SEVII_")
  assert(R.remove(S, a.id) and #R.list(S.project) == 0 and not R.remove(S, a.id))
  local none = {}
  R.emit(S.project, tostring, none)
  assert(#none == 0)
end)

run("colours: rgb of a hex colour", function()
  local r, g, b = R.rgb("#ff8000")
  assert(r == 1 and math.abs(g - 128 / 255) < 1e-9 and b == 0)
  assert(R.rgb("nope") == 0.5)
end)

run("town or route: map type decides, a name is the fallback", function()
  assert(R.isTownOrRoute(1, "X") and R.isTownOrRoute(2, "X") and R.isTownOrRoute(3, "X") and R.isTownOrRoute("6", "X"))
  assert(not R.isTownOrRoute(8, "EM_OLDALE_TOWN") and not R.isTownOrRoute(4, "EM_ROUTE104") and not R.isTownOrRoute(9, "X"))
  assert(R.isTownOrRoute(nil, "EM_ROUTE104") and R.isTownOrRoute(nil, "EM_KANTO_PALLET_TOWN") and R.isTownOrRoute(nil, "EM_KANTO_VIRIDIAN_CITY"))
  assert(not R.isTownOrRoute(nil, "EM_KANTO_PALLET_TOWN_PLAYERS_HOUSE_1F") and not R.isTownOrRoute(nil, "EM_GRANITE_CAVE_1F") and not R.isTownOrRoute(nil, nil))
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
