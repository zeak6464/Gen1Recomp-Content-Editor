-- Run from the repository root with LuaJIT. Canvas placement without graphics.
local invalidated, dirty, batches = nil, 0, 0
local modules = {
  Theme = { PAL = {} },
  Generation = {
    isGen2 = function(S) return S.version == "gold" or S.version == "silver" or S.version == "crystal" end,
    isGen3 = function(S) return S.version == "firered" end,
    dataMaps = function(S) return S.data.maps end,
  },
  ["src.world.MapLoader"] = { invalidate = function(id) invalidated = id end },
  ItemPicker = {indexForId = function() return 18 end},
}
local chunk = assert(loadfile("tools/content-editor/panels/Maps.lua"))
setfenv(chunk, setmetatable({ require = function(id) return modules[id] or {} end }, { __index = _G }))
local Maps = chunk()
local App = {
  markDirty = function() dirty = dirty + 1 end,
  beginEditBatch = function() batches = batches + 1 end,
  endEditBatch = function() batches = batches - 1 end,
}
for _, version in ipairs({"red", "blue", "yellow"}) do
  local original = { id = "ROUTE_17", width = 4, height = 4, objects = {
    {index = 1, x = 0, y = 0, sprite = "SPRITE_RED"},
  } }
  local S = {version = version, mapId = original.id, mapTool = "select",
    data = {maps = {[original.id] = original}}, project = {maps = {}}}
  assert(Maps.applyEventAtCell(S, "item", 3, 5, App))
  local map = assert(S.project.maps[original.id])
  local obj = assert(map.objects[2])
  assert(#original.objects == 1, "Placement mutated the vanilla map")
  assert(obj.index == 2 and obj.x == 3 and obj.y == 5)
  assert(obj.item == "POTION" and obj.sprite == "SPRITE_POKE_BALL")
  assert(obj.movement == "STAY" and obj.range == "NONE")
  assert(S.data.maps[original.id] == map and invalidated == original.id)
  assert(S.mapSection == "objects" and S.mapObjectIndex == 2)
  assert(S.mapEditMode == "events" and S.mapTool == "select" and batches == 0)
  Maps.applyEventAtCell(S, "item", 8, 0, App)
  assert(#map.objects == 2, "Out-of-bounds placement created an object")
end
assert(dirty == 3)
for _, version in ipairs({"gold", "silver", "crystal"}) do
  local map = {id = "ROUTE_17", width = 4, height = 4, objects = {}}
  local S = {version = version, mapId = map.id, project = {maps = {[map.id] = map}},
    data = {maps = {}, scripts = {{flag = 0x8000}}}}
  Maps.applyEventAtCell(S, "item", 2, 3, App)
  Maps.applyEventAtCell(S, "item", 4, 5, App)
  assert(map.objects[1].type == 1 and map.objects[1].item == nil)
  assert(map.objects[1].itemball.item == 18 and map.objects[1].itemball.quantity == 1)
  assert(map.objects[1].eventFlag == 0x8001 and map.objects[2].eventFlag == 0x8002)
  assert(map.objects[1].movement == 0 and map.objects[1].hours[1] == -1)
end
print("PASS: Gen 1 item placement, selection, vanilla isolation, and bounds")
print("PASS: Gen 2 native item balls and unique persistent flags")
