-- Exact RGBA deduplication of authored 16x16 PNG sources. Native ROM
-- metatiles are deliberately outside this operation.
local M={}
local function copy(v)
  if type(v)~="table" then return v end
  local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
end
local function keys(t)
  local out={};for k in pairs(t or {}) do out[#out+1]=k end;table.sort(out);return out
end
local function readImage(S,path)
  local resolved,kind=require("Preview").resolve(S,path)
  assert(resolved,"Image unavailable: "..tostring(path))
  if kind=="love" then return love.image.newImageData(resolved) end
  local bytes=assert(require("ModIO").readText(resolved))
  return love.image.newImageData(love.filesystem.newFileData(bytes,"source.png"))
end
function M.sourcesForMaps(project,selected)
  local ids={}
  local function add(id) if (project.mapTileSources or {})[id] then ids[id]=true end end
  for id in pairs(selected) do
    for _,layer in ipairs(((project.layeredMaps or {})[id] or {}).layers or {}) do
      for _,ref in pairs(layer.cells or {}) do add(ref.source) end
    end
    add(((project.maps or {})[id] or {})._borderSource)
    for _,bridge in pairs(((project.layeredMaps or {})[id] or {}).gen3Bridges or {}) do if bridge.tile then add(bridge.tile.source) end end
  end
  return keys(ids)
end
function M.scan(S,sourceIds,reader)
  local plan={project=S.project,ids=sourceIds,remap={},groups={},before=0,after=0,duplicates={}}
  assert(#sourceIds>0,"Select a map that uses an imported PNG source")
  local images,pixels,groups={},{},{}
  for _,id in ipairs(sourceIds) do
    local src=assert(S.project.mapTileSources[id],"Missing source "..id)
    local image=(reader or readImage)(S,src.image)
    assert(not image.getFormat or image:getFormat()=="rgba8","Use an 8-bit RGBA PNG: "..id)
    assert(src.columns and src.columns>=1 and src.columns%1==0,"Invalid columns: "..id)
    assert(src.count and src.count>0 and src.count%1==0,"Invalid tile count: "..id)
    assert(src.columns*16<=image:getWidth() and math.ceil(src.count/src.columns)*16<=image:getHeight(),"Image is smaller than its tile grid: "..id)
    images[id]=image;pixels[id]={}
    for tile=0,src.count-1 do
      local bytes={};local sx,sy=tile%src.columns*16,math.floor(tile/src.columns)*16
      for y=0,15 do for x=0,15 do
        local r,g,b,a=image:getPixel(sx+x,sy+y)
        bytes[#bytes+1]=string.char(math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),math.floor(a*255+.5))
      end end
      pixels[id][tile]=table.concat(bytes)
    end
  end
  for _,id in ipairs(sourceIds) do
    local src=S.project.mapTileSources[id]
    local mode=src.colorMode or "palette"
    local group=groups[mode]
    if not group then group={mode=mode,tiles={},seen={}};groups[mode]=group;plan.groups[#plan.groups+1]=group end
    local mapping={};plan.remap[id]=mapping
    for tile=0,src.count-1 do
      local frames=(src.animations or {})[tile]
      local signature=pixels[id][tile].."static"
      if frames and #frames>0 then
        local parts={pixels[id][tile],"animated"}
        for _,frame in ipairs(frames) do
          assert(pixels[id][frame.tile],"Animation frame outside source: "..id)
          parts[#parts+1]=tostring(frame.duration or 200)..":"..pixels[id][frame.tile]
        end
        signature=table.concat(parts,"|")
      end
      local index=group.seen[signature]
      if index==nil then
        index=#group.tiles;group.seen[signature]=index
        group.tiles[index+1]={source=id,tile=tile,image=images[id],columns=src.columns,frames=copy(frames)}
        plan.after=plan.after+1
      else
        if #plan.duplicates<12 then plan.duplicates[#plan.duplicates+1]={source=id,tile=tile,kept=group.tiles[index+1]} end
      end
      mapping[tile]={group=group,tile=index};plan.before=plan.before+1
    end
  end
  -- Animation frames sample raw pixels, not other tiles' animation programs.
  for _,group in ipairs(plan.groups) do
    assert(#group.tiles<=65536,"Combined source exceeds 65,536 tiles; select fewer maps")
    group.seen=nil
  end
  plan.saved=plan.before-plan.after
  return plan
end
function M.apply(S,plan,App)
  assert(S.project==plan.project,"Project changed; scan again")
  assert(S.path,"Save the project before combining tiles")
  local IO=require("ModIO")
  local p=copy(S.project)
  local number=1
  repeat
    local stem="COMBINED_TILES_"..number
    local found=false
    for i in ipairs(plan.groups) do
      if p.mapTileSources[stem.."_"..i] or IO.readText(S.path.."/assets/mapbuilder/combined/"..stem.."_"..i..".png") then found=true end
    end
    if not found then break end
    number=number+1
  until false
  local outputs={}
  for i,group in ipairs(plan.groups) do
    group.id="COMBINED_TILES_"..number.."_"..i
    local columns=math.min(256,math.max(1,math.ceil(math.sqrt(#group.tiles))))
    local rows=math.ceil(#group.tiles/columns)
    assert(rows*16<=4096,"Combined image is too tall; select fewer maps")
    local image=love.image.newImageData(columns*16,rows*16)
    local src={id=group.id,name="Combined tiles ("..group.mode..")",image="assets/mapbuilder/combined/"..group.id..".png",
      tileWidth=16,tileHeight=16,columns=columns,count=#group.tiles,colorMode=group.mode,animations={}}
    for j,tile in ipairs(group.tiles) do
      image:paste(tile.image,(j-1)%columns*16,math.floor((j-1)/columns)*16,tile.tile%tile.columns*16,math.floor(tile.tile/tile.columns)*16,16,16)
      if tile.frames then
        local frames=copy(tile.frames)
        for _,frame in ipairs(frames) do frame.tile=assert(plan.remap[tile.source][frame.tile]).tile end
        src.animations[j-1]=frames
      end
    end
    p.mapTileSources[src.id]=src
    outputs[#outputs+1]={path=src.image,bytes=image:encode("png"):getString()}
  end
  local function ref(old)
    local mapping=old and plan.remap[old.source]
    if not mapping then return old end
    local mapped=assert(mapping[old.tile],"Reference outside source: "..old.source)
    local result=copy(old);result.source=mapped.group.id;result.tile=mapped.tile;return result
  end
  for _,map in pairs(p.layeredMaps or {}) do
    for _,layer in ipairs(map.layers or {}) do for index,cell in pairs(layer.cells or {}) do layer.cells[index]=ref(cell) end end
    for _,bridge in pairs(map.gen3Bridges or {}) do bridge.tile=ref(bridge.tile) end
  end
  for _,map in pairs(p.maps or {}) do
    local mapping=plan.remap[map._borderSource]
    if mapping then
      local function tile(value) return value~=nil and assert(mapping[value],"Invalid border tile").tile or nil end
      map._borderTile=tile(map._borderTile);map._borderTile2=tile(map._borderTile2)
      for _,cell in ipairs(map._borderCells or {}) do cell.tile=tile(cell.tile) end
      map._borderSource=mapping[0].group.id
    end
  end
  for _,bucket in ipairs({p.mapStamps or {},p.mapAssemblies or {}}) do
    for _,stamp in pairs(bucket) do
      local mapping=plan.remap[stamp.source]
      if mapping then
        for _,cell in ipairs(stamp.cells or {}) do cell.tile=assert(mapping[cell.tile],"Invalid stamp tile").tile end
        stamp.source=mapping[0].group.id
      end
    end
  end
  -- Retain original assets for undo, reimport and redo's asset pruning.
  p.mapTileSourceArchive=p.mapTileSourceArchive or {}
  for _,id in ipairs(plan.ids) do p.mapTileSourceArchive[id]=p.mapTileSources[id];p.mapTileSources[id]=nil end
  assert(IO.ensureDirectory(S.path.."/assets/mapbuilder/combined"))
  for _,out in ipairs(outputs) do assert(IO.writeText(S.path.."/"..out.path,out.bytes)) end
  App.beginEditBatch()
  S.project=p
  S.builderSourceId=plan.groups[1].id;S.builderTile=0;S.builderTileOffset=0
  S.builderStamp=nil;S.builderClip=nil
  -- Rebind existing editor aliases only; FireRed's native maps use a
  -- different coordinate scale and must not be replaced by editor records.
  for _,name in ipairs({"maps","gen2Maps","_editorMaps"}) do
    local bucket=S.data and S.data[name]
    if bucket then for id,map in pairs(p.maps or {}) do
      if bucket[id]==plan.project.maps[id] then bucket[id]=map end
    end end
  end
  require("Preview").invalidate()
  require("Maps").invalidateCaches(S)
  S.uiPreviewTick=(S.uiPreviewTick or 0)+1;S._mapNeedsRebuild=S.mapId
  App.markDirty();App.endEditBatch()
  return plan.saved
end
return M
