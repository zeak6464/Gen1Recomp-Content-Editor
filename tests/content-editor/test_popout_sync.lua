-- Map builder fullscreen preview: what travels from the editor to the preview
-- window (PopoutSync) and which fields of the editor state it follows.
-- Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_popout_sync.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local Sync = require("PopoutSync")
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function project()
  local grass = { source = "@runtime:town", tile = 1 }
  local cells = {}
  for i = 1, 30 do cells[i] = grass end -- the editor shares one table per tile
  return { name = "demo", layeredMaps = { TOWN = { cellWidth = 6, cellHeight = 5,
      layers = { { id = "ground", cells = cells, visible = true } },
      collision = { "walk", "walk", "solid", "walk", "walk", "walk", "walk", "walk", "walk", "walk" } } },
    maps = { TOWN = { width = 3, height = 2, objects = { { x = 1, y = 2, sprite = "BOY", script = { "a", "b" } } } } } }
end

run("no difference, no changes", function()
  local a = project()
  local b = Sync.copy(a)
  assert(#Sync.diff(a, b) == 0 and #Sync.diff(b, a) == 0)
end)

run("a painted cell is one small change, and the other copy ends up the same", function()
  local mine = project()
  local shadow, theirs = Sync.copy(mine), Sync.copy(mine)
  mine.layeredMaps.TOWN.layers[1].cells[7] = { source = "@runtime:town", tile = 9 }
  mine.layeredMaps.TOWN.collision[7] = "solid"
  local ops = Sync.diff(shadow, mine)
  assert(#ops == 2, #ops)
  assert(Sync.cellsOnly(ops))
  Sync.apply(theirs, ops, true)
  assert(equal(theirs, mine))
  assert(theirs.layeredMaps.TOWN.layers[1].cells[7] ~= mine.layeredMaps.TOWN.layers[1].cells[7], "copied in, not shared")
end)

run("a shared cell table is replaced, never changed in place", function()
  -- every cell showing grass is the same table: changing its tile in place
  -- would repaint all of them
  local theirs = project()
  local grass = theirs.layeredMaps.TOWN.layers[1].cells[1]
  local mine = Sync.copy(theirs)
  local shadow = Sync.copy(mine)
  mine.layeredMaps.TOWN.layers[1].cells[4] = { source = "@runtime:town", tile = 5 }
  local ops = Sync.diff(shadow, mine)
  assert(#ops == 1 and #ops[1].p == 6 and ops[1].p[6] == 4 and type(ops[1].v) == "table", "the cell, whole")
  Sync.apply(theirs, ops, true)
  assert(grass.tile == 1, "the shared grass table is untouched")
  assert(theirs.layeredMaps.TOWN.layers[1].cells[4].tile == 5)
  assert(theirs.layeredMaps.TOWN.layers[1].cells[5] == grass and theirs.layeredMaps.TOWN.layers[1].cells[5].tile == 1)
end)

run("removed, added and nested values", function()
  local mine = project()
  local shadow, theirs = Sync.copy(mine), Sync.copy(mine)
  local keep = theirs.maps.TOWN.objects
  mine.maps.TOWN.objects[1].script[3] = "c"
  mine.maps.TOWN.objects[2] = { x = 4, y = 4, sprite = "GIRL", script = { "hello" } }
  mine.maps.TOWN.width = nil
  mine.maps.CAVE = { width = 2, height = 2, warps = {} }
  mine.layeredMaps.TOWN.layers[1].visible = false
  local ops = Sync.diff(shadow, mine)
  assert(not Sync.cellsOnly(ops))
  Sync.apply(theirs, ops, true)
  assert(equal(theirs, mine))
  assert(theirs.maps.TOWN.objects == keep, "lists that are there are changed in place")
  assert(theirs.maps.TOWN.width == nil and theirs.layeredMaps.TOWN.layers[1].visible == false)
  -- and applying the same changes twice changes nothing more
  Sync.apply(theirs, ops, true)
  assert(equal(theirs, mine))
end)

run("only plain data is sent", function()
  local p = Sync.plain({ a = 1, f = function() end, list = { 1, "x", io.stdout, { deep = true } }, [true] = 1 })
  assert(p.a == 1 and p.f == nil and p[true] == nil)
  assert(p.list[1] == 1 and p.list[2] == "x" and p.list[3] == nil and p.list[4].deep == true)
  assert(Sync.plain(function() end) == nil and Sync.plain("s") == "s" and Sync.plain(false) == false)
end)

run("messages: framed, split anywhere, taken off whole", function()
  local wire = Sync.frame("hello") .. Sync.frame("") .. Sync.frame(("x"):rep(300))
  local got, buffer = {}, ""
  for i = 1, #wire, 7 do
    buffer = buffer .. wire:sub(i, i + 6)
    local texts, rest = Sync.unframe(buffer)
    assert(texts, rest)
    for _, t in ipairs(texts) do got[#got + 1] = t end
    buffer = rest
  end
  assert(#got == 3 and got[1] == "hello" and got[2] == "" and #got[3] == 300 and buffer == "")
  assert(Sync.unframe("not a frame") == nil)
end)

run("what the preview follows: the map and the overlays, nothing else", function()
  package.loaded["ModWriter"] = package.loaded["ModWriter"] or {}
  local Preview = require("MapPopout")
  local snap = Preview.snapshot({ mapId = "TOWN", builderMapId = "TOWN", mapShowGrid = false, mapShowCollision = true,
    builderTool = "fill", builderZoom = 3, builderCamX = 40, project = {}, status = "x" })
  assert(snap.mapId == "TOWN" and snap.builderMapId == "TOWN" and snap.mapShowGrid == false and snap.mapShowCollision == true)
  -- the preview keeps its own tool (Pan), zoom and position
  assert(snap.builderTool == nil and snap.builderZoom == nil and snap.builderCamX == nil and snap.project == nil and snap.status == nil)
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
