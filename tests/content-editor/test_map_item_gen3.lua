-- Exercise the Item tool through the real pickup compiler, without graphics.
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for k,v in pairs(value) do out[k] = copy(v) end; return out
end
local modules = {
  ["src.mods.Merge"] = {deepCopy = copy},
  Gen3ContentAdapter = {prepare = function() end},
  Gen3Workspace = {convert = function(S,id)
    S.project.maps[id] = S.project.maps[id] or {objects = {}}
    return {cellWidth = 8, cellHeight = 8}
  end},
  Gen3 = {catalog = function() return {} end},
  Gen3Quests = {usedFlags = function(S)
    local used = {}; for _,map in pairs(S.project.maps) do
      for _,obj in ipairs(map.objects) do used[obj.flag] = true end
    end; return used
  end},
}
local function loadModule(id)
  local chunk = assert(loadfile("tools/content-editor/"..id..".lua"))
  setfenv(chunk,setmetatable({require = function(name) return assert(modules[name],name) end},{__index = _G}))
  modules[id] = chunk(); return modules[id]
end
loadModule("Gen3EventBuilder")
local Templates = loadModule("Gen3MapTemplates")
local Events = loadModule("Gen3MapEvents")
for _,game in ipairs({"firered","leafgreen","ruby","sapphire","emerald"}) do
  local S = {version = game, mapId = "TEST_MAP", project = {id = game,maps = {}},
    data = {items = {POTION = {index = 13}}}}
  local draft = Templates.draft(S)
  draft.kind = "empty" -- Item tool must override the regular Event template.
  draft.quantity = "3"
  local dirty = 0
  local App = {markDirty = function() dirty = dirty + 1 end}
  assert(Events.place(S,"item",2,4,App))
  assert(Events.place(S,"item",3,4,App))
  local objects = S.project.maps[S.mapId].objects
  assert(#objects == 2 and objects[1].graphicsId == 92)
  assert(objects[1].x == 2 and objects[1].y == 4)
  assert(objects[1].flag == 0x900 and objects[2].flag == 0x901)
  local steps = S.project.gen3.map_scripts[objects[1].scriptKey]
  assert(steps[1][2] == 13 and steps[2][2] == 3 and steps[3].std == 1)
  assert(S.mapObjectIndex == 2 and S.mapSection == "objects" and dirty == 2)
  assert(draft.kind == "empty", "Item tool changed the regular Event template")
  assert(Events.place(S,"item",99,4,App))
  assert(#S.project.maps[S.mapId].objects == 2 and dirty == 2)
end
print("PASS: all Gen 3 Item tool routes, pickup compilation, flags, quantities, and bounds")
