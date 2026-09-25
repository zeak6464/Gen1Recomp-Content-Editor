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
  -- Maps created in the shared map builder have no ROM-backed native layout.
  -- Expose their layered cells through the same small interface used by this
  -- panel so border/terrain tools can edit them immediately after creation.
  local source=((project or {}).layeredMaps or {})[id]
  if source then
    local border=source.gen3Border or {width=1,height=1,mids={0}}
    local layout={mapId=id,width=source.cellWidth,height=source.cellHeight,
      trueWidth=source.cellWidth,trueHeight=source.cellHeight,pair=source.baseTileset,
      borderPair=border.pair or source.baseTileset,borderWidth=border.width or 1,borderHeight=border.height or 1,
      borderMids=require("src.mods.Merge").deepCopy(border.mids or {0})}
    function layout:cellAt(x,y)
      local i=y*self.width+x+1
      local ref
      for _,layer in ipairs(source.layers or {}) do
        if layer.visible~=false and layer.export~=false and layer.cells and layer.cells[i] then
          ref=layer.cells[i]
        end
      end
      local coll=source.gen3Collision and source.gen3Collision[i]
      return {mid=ref and ref.tile or 0,coll=coll == nil and 0 or coll,
        elev=(source.gen3Elevation and source.gen3Elevation[i]) or 0}
    end
    return layout
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

-- Borders repeat outside the map and always remain blocked.
function M.borderLayout(project,id,base)
  local border=(project.gen3Borders or {})[id] or base
  local layout={width=border.borderWidth,height=border.borderHeight,pair=border.borderPair or base.borderPair or base.pair}
  function layout:cellAt(x,y)
    return {mid=border.borderMids[y*self.width+x+1] or 0,coll=255,elev=0}
  end
  return layout
end

local function syncBorder(project,id)
  local border=project.gen3Borders[id]
  local value={pair=border.borderPair,width=border.borderWidth,height=border.borderHeight,
    mids=require("src.mods.Merge").deepCopy(border.borderMids)}
  local source=(project.layeredMaps or {})[id]
  local map=(project.maps or {})[id]
  if source then source.gen3Border=value end
  if map then map._gen3Border=require("src.mods.Merge").deepCopy(value) end
end

function M.setBorderTileset(project,id,base,pair)
  if not (project.layeredMaps or {})[id] then return false,"Separate border tilesets require a custom layered map" end
  assert(type(pair)=="string" and pair~="","Choose a border tileset")
  local old=M.borderLayout(project,id,base)
  if old.pair==pair then return false end
  project.gen3Borders=project.gen3Borders or {}
  local border=project.gen3Borders[id] or {borderWidth=base.borderWidth,borderHeight=base.borderHeight,
    borderMids=require("src.mods.Merge").deepCopy(base.borderMids)}
  border.borderPair=pair;project.gen3Borders[id]=border
  syncBorder(project,id)
  return true
end

function M.resizeBorder(project,id,base,width,height)
  width,height=tonumber(width),tonumber(height)
  if not width or not height or width%1~=0 or height%1~=0
      or width<1 or height<1 or width>512 or height>512 then
    return false,"Border dimensions must be integers from 1 to 512"
  end
  local old=M.borderLayout(project,id,base)
  if old.width==width and old.height==height then return false end
  local mids={}
  for y=0,height-1 do for x=0,width-1 do
    mids[y*width+x+1]=old:cellAt(x%old.width,y%old.height).mid
  end end
  project.gen3Borders=project.gen3Borders or {}
  project.gen3Borders[id]={borderPair=old.pair,borderWidth=width,borderHeight=height,borderMids=mids}
  syncBorder(project,id)
  return true
end

function M.paintBorder(project,id,base,x,y,mid)
  local layout=M.borderLayout(project,id,base)
  if x<0 or y<0 or x>=layout.width or y>=layout.height then return false end
  assert(type(mid)=="number" and mid%1==0 and mid>=0 and mid<=1023,"Invalid border metatile")
  if layout:cellAt(x,y).mid==mid then return false end
  project.gen3Borders=project.gen3Borders or {}
  if not project.gen3Borders[id] then
    project.gen3Borders[id]={borderPair=base.borderPair,borderWidth=base.borderWidth,borderHeight=base.borderHeight,
      borderMids=require("src.mods.Merge").deepCopy(base.borderMids)}
  end
  project.gen3Borders[id].borderMids[y*layout.width+x+1]=mid
  syncBorder(project,id)
  return true
end

function M.emit(project, encode, out)
  for _,border in pairs(project.gen3Borders or {}) do
    for _,key in ipairs({"borderWidth","borderHeight"}) do
      local n=border[key];assert(type(n)=="number" and n%1==0 and n>=1 and n<=512,"Invalid border dimensions")
    end
    assert(type(border.borderMids)=="table" and #border.borderMids==border.borderWidth*border.borderHeight,"Invalid border pattern")
    for _,mid in ipairs(border.borderMids) do
      assert(type(mid)=="number" and mid%1==0 and mid>=0 and mid<=1023,"Invalid border metatile")
    end
  end
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
  for id in pairs(project.gen3Borders or {}) do terrain[id]=terrain[id] or {} end
  if not next(terrain) then return end
  out[#out+1] = "  local terrain = " .. encode(terrain)
  out[#out+1] = "  local mapLayouts = " .. encode(project.gen3MapLayouts or {})
  out[#out+1] = "  local borders = " .. encode(project.gen3Borders or {})
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
          local border=borders[id]
          if border then
            layout.borderWidth=border.borderWidth;layout.borderHeight=border.borderHeight
            layout.borderMids=border.borderMids
          end
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
