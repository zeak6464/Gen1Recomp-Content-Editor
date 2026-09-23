-- Adapt FireRed to the editor's existing authoring model. Runtime data stays
-- native; the shared panels edit the same project structures as other games.
local M={}
local function copy(v) return require("src.mods.Merge").deepCopy(v) end
local function behaviorFor(pair,mid)
  local ok,interactions=pcall(require,"src.core.game3.scripting.interaction_scripts")
  local behaviors=ok and interactions and interactions.behaviors
  return behaviors and behaviors[pair] and behaviors[pair][mid]
end
function M.prepare(S)
  local data=S.data
  if not data or not data._gen3Read then return end
  if not data._editorMaps then
    data._editorMaps={};data._editorTilesets={}
    for id,native in pairs(data.maps or {}) do
      local map=copy(native)
      map._gen3Width,map._gen3Height=native.width,native.height
      map.width,map.height=native.width/2,native.height/2
      map.tileset=native.pair;map.label=native.name or id;map.blocks={};map.signs=copy(native.bgEvents or {})
      map.trueColor=true;map._gen3Native=true
      data._editorMaps[id]=map
      if native.pair then data._editorTilesets[native.pair]={id=native.pair,_gen3Pair=native.pair,image="@gen3/"..native.pair,blocks={},trueColor=true} end
    end
  end
  if S.project then S.project.gen3Workspace=1 end
  for _,source in pairs(S.project and S.project.layeredMaps or {}) do
    for i,coll in pairs(source.gen3Collision or {}) do
      if source.collision[i]==(coll==0 and "walk" or "solid") then
        source.collision[i]=require("Gen3Collision").mode(coll)
      end
      if source.gen3Behavior==nil then source.gen3Behavior={} end
      if source.gen3Behavior[i]==nil then
        local ref=source.layers and source.layers[1] and source.layers[1].cells[i]
        if ref then source.gen3Behavior[i]=behaviorFor(source.baseTileset,ref.tile) end
      end
    end
  end
  for id,map in pairs(S.project and S.project.maps or {}) do
    local source=(S.project.layeredMaps or {})[id]
    local native=data.maps[id]
    if source or native then
      map.width=(source and source.cellWidth or native.width)/2
      map.height=(source and source.cellHeight or native.height)/2
      map.tileset=map.tileset or (native and native.pair)
      map._gen3Native=true;map.trueColor=true
      local layout=require("Gen3Map").layout(data,id,S.project)
      if layout then
        local border=(S.project.gen3Borders or {})[id] or layout
        map._gen3Border={width=border.borderWidth,height=border.borderHeight,mids=copy(border.borderMids)}
        if source then source.gen3Border=copy(map._gen3Border) end
      end
    end
  end
  for id,patch in pairs((S.project and S.project.gen3 or {}).maps or {}) do
    if not data._editorMaps[id] and patch.width and patch.height then
      local map=copy(patch)
      map.width,map.height=patch.width/2,patch.height/2
      map.tileset=patch.pair;map.blocks={};map.signs=copy(patch.bgEvents or {})
      map.trueColor=true;map._gen3Native=true
      data._editorMaps[id]=map
    end
  end
end
function M.source(S,id)
  M.prepare(S)
  local L=require("LayeredMap")
  L.ensureProject(S.project)
  if S.project.layeredMaps[id] then return S.project.layeredMaps[id] end
  local native=S.data.maps[id] or S.data._editorMaps[id]
  if not native then return nil,"Unknown Gen 3 map "..tostring(id) end
  local layout,err=require("Gen3Map").layout(S.data,id,S.project)
  if not layout then return nil,err end
  local cells,collision,elevation,nativeCollision,nativeBehavior={},{},{},{},{}
  for y=0,layout.height-1 do for x=0,layout.width-1 do
    local i=y*layout.width+x+1
    local c=require("Gen3Map").cell(S.project,id,layout,x,y)
    cells[i]={source=L.runtimeSourceId(layout.pair),tile=c.mid}
    collision[i]=require("Gen3Collision").mode(c.coll);elevation[i]=c.elev;nativeCollision[i]=c.coll
    nativeBehavior[i]=behaviorFor(layout.pair,c.mid)
  end end
  local border=(S.project.gen3Borders or {})[id] or layout
  local source={id=id,cellWidth=layout.width,cellHeight=layout.height,baseTileset=layout.pair,
    layers={{id="ground",name="Ground",visible=true,export=true,opacity=1,cells=cells}},
    collision=collision,gen3Elevation=elevation,gen3Collision=nativeCollision,gen3Behavior=nativeBehavior,
    gen3Border={width=border.borderWidth,height=border.borderHeight,mids=copy(border.borderMids)}}
  return source
end
function M.convert(S,id)
  if S.project.layeredMaps and S.project.layeredMaps[id] and S.project.maps and S.project.maps[id] then
    return S.project.layeredMaps[id]
  end
  local source,err=M.source(S,id)
  if not source then return nil,err end
  local L=require("LayeredMap")
  local map=copy(S.data._editorMaps[id])
  for k,v in pairs((S.project.gen3 or {}).maps and S.project.gen3.maps[id] or {}) do map[k]=copy(v) end
  local patch=((S.project.gen3 or {}).maps or {})[id]
  if patch and patch.bgEvents then map.signs=copy(patch.bgEvents) end
  map.width,map.height=source.cellWidth/2,source.cellHeight/2
  map._gen3Border=copy(source.gen3Border)
  map._layeredSource=id;S.project.maps[id]=map;S.project.layeredMaps[id]=source
  L.syncMapWarps(S,map)
  return source
end
function M.descriptor(S,pair)
  local ts=require("Gen3Map").tileset(S.data,pair)
  if not ts then return end
  local count=0;for mid in pairs(ts.midToSlot) do count=math.max(count,mid+1) end
  if S.project then
    S.project.runtimeTileAnims=S.project.runtimeTileAnims or {}
    S.project.runtimeTileAnims[pair]=S.project.runtimeTileAnims[pair] or {}
  end
  return {id=require("LayeredMap").runtimeSourceId(pair),name=pair.." (Gen 3 metatiles)",nativePair=pair,
    image="@gen3/"..pair,colorMode="true_color",columns=8,count=count,
    animations=S.project and S.project.runtimeTileAnims and S.project.runtimeTileAnims[pair] or {}}
end
function M.drawTile(S,source,tile,x,y,size,alpha)
  local ts,T=require("Gen3Map").tileset(S.data,source.nativePair)
  if not ts then return false end
  local slot=T.slotFor(ts,tile)
  love.graphics.setColor(1,1,1,alpha or 1)
  love.graphics.draw(ts.image,T.quad(ts,slot),x,y,0,size/16,size/16)
  if ts.overImage then love.graphics.draw(ts.overImage,T.overQuad(ts,slot),x,y,0,size/16,size/16) end
  return true
end
function M.compile(S)
  local p=S.project
  p.gen3=p.gen3 or {};p.gen3.maps=p.gen3.maps or {}
  p.gen3Exact=p.gen3Exact or {};p.gen3Exact.maps=p.gen3Exact.maps or {}
  for id in pairs(p.gen3WorkspaceMaps or {}) do
    if not p.maps[id] then
      p.gen3.maps[id]=nil;p.gen3Exact.maps[id]=nil
      if p.gen3Modes and p.gen3Modes.maps then p.gen3Modes.maps[id]=nil end
    end
  end
  p.gen3WorkspaceMaps={}
  for id,map in pairs(p.maps or {}) do
    local value={}
    for k,v in pairs(map) do
      if not tostring(k):match("^_") and k~="blocks" and k~="width" and k~="height" and k~="tileset" and k~="signs" then value[k]=copy(v) end
    end
    -- Trigger conversion needs a little editor-only bookkeeping in the
    -- workspace. Keep the compiled map clean while preserving the real
    -- FireRed object/coordinate-event representation.
    for _,row in ipairs(value.coordEvents or {}) do row._editorTriggerOwner=nil end
    for _,row in ipairs(value.objects or {}) do
      row.touchScriptKey=nil
      if row.trigger=="player_touch" then row.trigger=nil end
    end
    value.bgEvents=copy(map.signs or map.bgEvents or {})
    for _,row in ipairs(value.bgEvents) do
      row.touchScriptKey=nil
      if row.trigger=="player_touch" then row.trigger=nil end
    end
    value.warps=copy(map.warps or {})
    if map._isNew then
      local source=p.layeredMaps[id]
      value.id,value.width,value.height,value.pair=id,source.cellWidth,source.cellHeight,source.baseTileset
      p.gen3Modes=p.gen3Modes or {};p.gen3Modes.maps=p.gen3Modes.maps or {};p.gen3Modes.maps[id]="register"
    end
    p.gen3.maps[id]=value;p.gen3Exact.maps[id]=true
    p.gen3WorkspaceMaps[id]=true
  end
  -- The shared warp tool stores stable endpoint IDs; resolve the final table
  -- indices once after all endpoints have been ordered.
  local byMap,index={},{ }
  for mapId in pairs(p.layeredMaps or {}) do
    local rows=require("LayeredMap").nodesForMap(p,mapId)
    byMap[mapId]=rows
    for i,node in ipairs(rows) do index[node.id]=i end
  end
  for mapId,rows in pairs(byMap) do
    if p.gen3.maps[mapId] then
      local warps={}
      for _,node in ipairs(rows) do
        local target=node.targetNode and p.mapWarpNodes[node.targetNode]
        warps[#warps+1]={x=node.x,y=node.y,destMap=target and target.map or node.targetMap,
          destWarp=target and index[node.targetNode] or node.targetIndex,disabled=node.active==false}
      end
      p.gen3.maps[mapId].warps=warps
    end
  end
  p.gen3Layered=copy(p.layeredMaps or {})
  p.gen3TileSources=copy(p.mapTileSources or {})
  p.gen3TileAnimations=copy(p.runtimeTileAnims or {})
  return true,"Compiled Gen 3 workspace"
end
return M
