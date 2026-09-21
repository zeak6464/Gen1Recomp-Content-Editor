-- Sparse 16px native map edits. ROM cells and atlases never enter the mod.
local M = {}
local ROOT = "data/generated/gba/native/"

function M.layout(data, id, project)
  local spec=((project or {}).gen3MapLayouts or {})[id]
  if spec then
    data._gen3DerivedLayouts=data._gen3DerivedLayouts or {}
    local entry=data._gen3DerivedLayouts[id]
    if entry and entry.spec==spec then return entry.layout end
    local base,err=M.layout(data,spec.source or id)
    if not base then return nil,err end
    local layout=M.resize(base,spec,id)
    data._gen3DerivedLayouts[id]={spec=spec,layout=layout};return layout
  end
  data._gen3Layouts = data._gen3Layouts or {}
  if data._gen3Layouts[id] then return data._gen3Layouts[id] end
  local info = ((data.gen3Native or {}).layouts or {})[id]
  if not info or not data._gen3Read then return nil, "No native layout for " .. tostring(id) end
  local blob = data._gen3Read(ROOT .. (info.file or "layouts/" .. id .. ".mid"))
  if not blob then return nil, "Native map cache is missing" end
  local decoded, err = require("src.import.gba.native_pack").decodeMidLayout(blob)
  if not decoded then return nil, err end
  local layout = require("src.core.game3.layout_native").fromDecoded(decoded, id, info.pair)
  data._gen3Layouts[id] = layout
  return layout
end

function M.resize(base,spec,id)
  assert(spec.width>=1 and spec.width<=512 and spec.width%1==0,"Map width must be 1–512")
  assert(spec.height>=1 and spec.height<=512 and spec.height%1==0,"Map height must be 1–512")
  local copy=require("src.mods.Merge").deepCopy(base)
  copy.mapId=id;copy.width=spec.width;copy.height=spec.height
  copy.trueWidth=spec.width;copy.trueHeight=spec.height;copy.pair=spec.pair or base.pair
  copy.cells={};copy.overrides={}
  for y=0,spec.height-1 do for x=0,spec.width-1 do
    copy.cells[y*spec.width+x+1]=(not spec.blank and x<base.width and y<base.height) and base:cellAt(x,y) or spec.fill or {mid=0,coll=255,elev=0}
  end end
  return setmetatable(copy,require("src.core.game3.layout_native"))
end

function M.tileset(data, pair)
  local T = require("src.core.game3.tileset_native")
  if M._data ~= data then
    M._data = data
    T.install({
      read=function(_,p) return data._gen3Read and data._gen3Read(p) end,
      exists=function(_,p) return data._gen3Read and data._gen3Read(p) ~= nil end,
      write=function() return false end,
    })
  end
  return T.get(pair), T
end

function M.cell(project, id, layout, x, y)
  local edits = ((project or {}).gen3Terrain or {})[id]
  return edits and edits[y*1024+x] or layout:cellAt(x,y)
end

function M.paint(project, id, layout, x, y, cell)
  if x < 0 or y < 0 or x >= layout.width or y >= layout.height then return false end
  assert(cell.mid >= 0 and cell.mid <= 1023 and cell.mid % 1 == 0, "Invalid metatile")
  assert(cell.coll >= 0 and cell.coll <= 255 and cell.coll % 1 == 0, "Invalid collision")
  assert(cell.elev >= 0 and cell.elev <= 15 and cell.elev % 1 == 0, "Invalid elevation")
  project.gen3Terrain = project.gen3Terrain or {}
  project.gen3Terrain[id] = project.gen3Terrain[id] or {}
  local base = layout:cellAt(x,y)
  local current = M.cell(project,id,layout,x,y)
  if current.mid == cell.mid and current.coll == cell.coll and current.elev == cell.elev then return false end
  local key = y*1024+x
  if base.mid == cell.mid and base.coll == cell.coll and base.elev == cell.elev then
    project.gen3Terrain[id][key] = nil
  else project.gen3Terrain[id][key] = {mid=cell.mid,coll=cell.coll,elev=cell.elev} end
  if not next(project.gen3Terrain[id]) then project.gen3Terrain[id] = nil end
  return true
end

function M.emit(project, encode, out)
  for id,spec in pairs(project.gen3MapLayouts or {}) do
    assert(type(id)=="string" and type(spec.source)=="string","Map layouts need a source map")
    for _,key in ipairs({"width","height"}) do
      local n=spec[key];assert(type(n)=="number" and n%1==0 and n>=1 and n<=512,"Map "..key.." must be 1–512")
    end
  end
  for _,edits in pairs(project.gen3Terrain or {}) do for key,cell in pairs(edits) do
    assert(type(key)=="number" and key%1==0 and key>=0 and key<512*1024,"Invalid terrain coordinate")
    for field,max in pairs({mid=1023,coll=255,elev=15}) do
      local n=cell[field];assert(type(n)=="number" and n%1==0 and n>=0 and n<=max,"Invalid terrain "..field)
    end
  end end
  local terrain = require("src.mods.Merge").deepCopy(project.gen3Terrain or {})
  for id in pairs((project.gen3 or {}).maps or {}) do terrain[id] = terrain[id] or {} end
  for id in pairs(project.gen3MapLayouts or {}) do terrain[id]=terrain[id] or {} end
  if not next(terrain) then return end
  out[#out+1] = "  local terrain = " .. encode(terrain)
  out[#out+1] = "  local mapLayouts = " .. encode(project.gen3MapLayouts or {})
  out[#out+1] = [[  mod.events:on("game.ready", function(ctx)
    local maps = ctx.game and ctx.game.data and ctx.game.data.maps or {}
    local Layout = require("src.core.game3.layout_native")
    local Space = require("src.core.game3.scripting.space")
    local bundle=Space.bundle
    local sourceLayouts={}
    for id,def in pairs(maps) do sourceLayouts[id]=def.midLayout end
    for id,spec in pairs(mapLayouts) do
      local def=maps[id]
      local base=sourceLayouts[spec.source or id]
      if def and base then
        setmetatable(base,Layout)
        local cells={}
        for y=0,spec.height-1 do for x=0,spec.width-1 do
          cells[y*spec.width+x+1]=(not spec.blank and x<base.width and y<base.height) and base:cellAt(x,y) or spec.fill or {mid=0,coll=255,elev=0}
        end end
        def.midLayout=Layout.fromDecoded({width=spec.width,height=spec.height,cells=cells,
          borderWidth=base.borderWidth,borderHeight=base.borderHeight,borderMids=base.borderMids},id,spec.pair or base.pair)
        def.width=spec.width;def.height=spec.height;def.pair=spec.pair or base.pair
      end
    end
    for id, edits in pairs(terrain) do
      local def = maps[id]
      if def then
        if bundle then
          bundle.events=bundle.events or {};local ev=bundle.events[id] or {};bundle.events[id]=ev
          for _,key in ipairs({"objects","bgEvents","coordEvents","mapScripts","music"}) do
            if def[key]~=nil then ev[key]=def[key] end
          end
        end
        local layout = def.midLayout
        if layout then
          -- Registry merges copy tables; restore the native layout methods.
          setmetatable(layout, Layout)
          layout.overrides = layout.overrides or {}
          for key, cell in pairs(edits) do
            layout:applyOverride(key % 1024, math.floor(key / 1024), cell.mid, cell.coll, cell.elev)
          end
        end
      end
    end
  end)]]
end

return M
