-- Preview models use native tile references, never bundled extracted graphics.
local M = {}

local function overlaps(a,b)
  return a.x < b.x+b.width and b.x < a.x+a.width
    and a.y < b.y+b.height and b.y < a.y+a.height
end
M.overlaps = overlaps

local function ref(source,x,y)
  if x<0 or y<0 or x>=source.cellWidth or y>=source.cellHeight then return end
  for i=#(source.layers or {}),1,-1 do
    local layer=source.layers[i]
    if layer.visible~=false and layer.export~=false then
      local cell=(layer.cells or {})[y*source.cellWidth+x+1]
      if cell then return cell end
    end
  end
end

M.propDefaults={wall_decor={size=.8,mount=1.2},potted_plant={size=1.4,mount=0},sign={size=1,mount=0},fence={size=.8,mount=0}}
function M.detectProps(source)
  local result={};local pair=source.baseTileset or ''
  local function tile(x,y) local c=ref(source,x,y);return c and c.source=='@runtime:'..pair and c.tile end
  local function add(x,y,w,h,kind,crop)
    local d=M.propDefaults[kind]
    result[#result+1]={x=x,y=y,width=w,height=h,kind=kind,size=d.size,mount=d.mount,crop=crop,automatic=true}
    return result[#result]
  end
  local outdoorEm=pair:match('^general__')
  local outdoorFr=pair=='pallet_outdoor' or source.visualNativeObjects=='frlg'
  for y=0,source.cellHeight-1 do for x=0,source.cellWidth-1 do
    local t=tile(x,y)
    if pair=='building__brendans_mays_house' and ((t==551 and tile(x,y+1)==559) or (t==647 and tile(x,y+1)==655)) then
      local clock=add(x,y,1,2,'wall_decor',{.08,.12,.92,.92})
      clock.style,clock.size,clock.mount='clock',1.1,.8
    elseif pair=='player_house' and ((t==87 and tile(x,y+1)==95) or (t==71 and tile(x,y+1)==79)) then
      add(x,y,1,2,'potted_plant')
    elseif pair=='building__lab' and ((t==572 and tile(x,y+1)==580) or ((t==550 or t==658) and tile(x,y+1)==558)) then
      local p=add(x,y,1,2,'potted_plant');p.leafStart=.85;p.leafEnd=1.45
    elseif (outdoorEm and t==3) or (outdoorFr and (t==2 or t==3)) then
      add(x,y,1,1,'sign')
    elseif pair=='pallet_outdoor' and (t==644 or t==647) and tile(x-1,y)~=644 and tile(x-1,y)~=647 then
      local finish=x+1
      while tile(finish,y)==644 or tile(finish,y)==647 do finish=finish+1 end
      add(x,y,finish-x,1,'fence')
    end
  end end
  return result
end

-- Conservative signatures for native outdoor tiles. Unrecognized art stays 2D;
-- manual footprints work with any native or custom tileset.
function M.detect(source)
  local result, occupied = {}, {}
  local pair=source.baseTileset or ''
  local emerald=pair:match('^general__') ~= nil
  local frlg=pair=='pallet_outdoor' or source.visualNativeObjects=='frlg'
  if not emerald and not frlg then return M.detectProps(source) end
  local function tile(x,y)
    local cell=ref(source,x,y)
    return cell and cell.source=='@runtime:'..pair and cell.tile or -1
  end
  local function add(x,y,w,h,kind,roofRows)
    if x+w>source.cellWidth or y+h>source.cellHeight then return false end
    for cy=y,y+h-1 do for cx=x,x+w-1 do
      if occupied[cy*source.cellWidth+cx+1] then return false end
    end end
    result[#result+1]={x=x,y=y,width=w,height=h,kind=kind,roofRows=roofRows,
      roofInset=frlg and .5 or 0,automatic=true}
    for cy=y,y+h-1 do for cx=x,x+w-1 do occupied[cy*source.cellWidth+cx+1]=true end end
    return true
  end
  for y=0,source.cellHeight-1 do for x=0,source.cellWidth-1 do
    local t=tile(x,y)
    if emerald then
      if t==462 and tile(x+1,y)==463 and (tile(x,y+1)==468 or tile(x,y+1)==470)
          and tile(x,y+2)==476 and tile(x+1,y+2)==477 then
        add(x,y,2,3,'tree')
      elseif t==468 and (tile(x+1,y)==469 or tile(x+1,y)==471)
          and (tile(x,y+1)==476 or tile(x,y+1)==484 or tile(x,y+1)==486)
          and (tile(x+1,y+1)==477 or tile(x+1,y+1)==485 or tile(x+1,y+1)==487) then
        add(x,y,2,2,'tree')
      end
    elseif t==14 and tile(x+1,y)==15 and tile(x,y+1)==30 and tile(x+1,y+1)==31
        and (tile(x,y+2)==20 or tile(x,y+2)==22 or tile(x,y+2)==36 or tile(x,y+2)==38)
        and (tile(x+1,y+2)==21 or tile(x+1,y+2)==23 or tile(x+1,y+2)==37 or tile(x+1,y+2)==39) then
      add(x,y,2,3,'tree')
    elseif (t==28 or t==30) and (tile(x+1,y)==29 or tile(x+1,y)==31)
        and (tile(x,y+1)==20 or tile(x,y+1)==22 or tile(x,y+1)==36 or tile(x,y+1)==38)
        and (tile(x+1,y+1)==21 or tile(x+1,y+1)==23 or tile(x+1,y+1)==37 or tile(x+1,y+1)==39) then
      add(x,y,2,2,'tree')
    end
    local signatures = emerald and {{520,521,522,3,5},{524,525,526,3,5}}
      or {{641,642,643,2,5}}
    for _,sig in ipairs(signatures) do
      if t==sig[1] then
        local finish=x+1
        -- Emerald's lab has a chimney embedded in the top roof row.
        while finish<x+12 and (tile(finish,y)==sig[2]
            or (emerald and sig[1]==524 and (tile(finish,y)==578 or tile(finish,y)==579))) do finish=finish+1 end
        if finish>=x+2 and tile(finish,y)==sig[3] then add(x,y,finish-x+1,sig[5],'building',sig[4]) end
      end
    end
    if frlg and t==680 and tile(x+1,y)==681 then
      local finish=x+1
      while finish<x+12 and tile(finish,y)==681 do finish=finish+1 end
      if tile(finish,y)==701 and tile(finish+1,y)==693 then add(x,y,finish-x+2,5,'building',3) end
    end
  end end
  for _,prop in ipairs(M.detectProps(source)) do
    local overlap=false
    for _,o in ipairs(result) do if overlaps(o,prop) then overlap=true;break end end
    if not overlap then result[#result+1]=prop end
  end
  return result
end

function M.objects(source)
  local result=source.visualAutoObjects==false and {} or M.detect(source)
  for _,manual in ipairs(source.visualObjects or {}) do
    for i=#result,1,-1 do
      if overlaps(result[i],manual) and (manual.kind=='none' or not (manual.allowOverlap or result[i].allowOverlap)) then table.remove(result,i) end
    end
    if manual.kind~='none' then result[#result+1]=manual end
  end
  -- These approved native treatments must also work on an ordinary editable
  -- copy, not only on the special town demo/export recipe. Return copies so
  -- previewing an older project never rewrites its saved/manual object data.
  if source.id=='EM_LITTLEROOT_TOWN' and source.baseTileset=='general__petalburg' then
    for i,o in ipairs(result) do
      local house=o.kind=='building' and o.x==2 and o.y==4 and o.width==5 and o.height==5
      local lab=o.kind=='building' and o.x==3 and o.y==12 and o.width==7 and o.height==5
      local c=ref(source,o.x,o.y)
      if (house or lab) and (o.rotation or 0)==0 and c
          and c.source=='@runtime:general__petalburg' and c.tile==(house and 520 or 524)
          and (o.style==nil or o.style=='native_house' or o.style=='flat_lab'
            or o.style=='littleroot_native_surfaces' or o.style=='littleroot_lab_native_surfaces') then
        local item={};for k,v in pairs(o) do item[k]=v end
        item.style=house and 'littleroot_native_surfaces' or 'littleroot_lab_native_surfaces'
        item.lean=(o.automatic or o.style=='native_house' or o.style=='flat_lab') and 0 or (o.lean or 0)
        result[i]=item
      end
    end
  end
  return result
end

function M.place(source,rect,kind,size,rotation,lean,mount,model,treatment)
  if kind=='model' and not (type(model)=='table' and model.version==1 and model.parts) then return false end
  if kind~='model' and kind~='tree' and kind~='building' and kind~='furniture' and kind~='none' and not M.propDefaults[kind] then return false end
  local x=math.max(0,math.min(rect.x0,rect.x1))
  local y=math.max(0,math.min(rect.y0,rect.y1))
  local right=math.min(source.cellWidth-1,math.max(rect.x0,rect.x1))
  local bottom=math.min(source.cellHeight-1,math.max(rect.y0,rect.y1))
  if x>right or y>bottom then return false end
  rotation=tonumber(rotation) or 0
  lean=tonumber(lean) or 0
  mount=tonumber(mount) or (M.propDefaults[kind] or {}).mount or 0
  if mount~=mount or math.abs(mount)>8 then return false end
  if rotation%45~=0 or (lean~=0 and lean~=45) then return false end
  if treatment=='flat' and kind~='model' then kind='none' end
  local object={x=x,y=y,width=right-x+1,height=bottom-y+1,kind=kind,size=size or (M.propDefaults[kind] or {}).size or 3,
    rotation=rotation%360,lean=lean,mount=mount,model=kind=='model' and model or nil}
  -- Imported scenes overlap other objects and carry their own ground.
  if kind=='model' then object.allowOverlap=true;object.replaceGround=true end
  if object.width==1 and object.height==1 and (kind=='tree' or kind=='building') then
    object.width=math.min(kind=='tree' and 2 or 4,source.cellWidth-x)
    object.height=math.min(kind=='tree' and 2 or 4,source.cellHeight-y)
  end
  source.visualObjects=source.visualObjects or {}
  do
    for _,old in ipairs(M.objects(source)) do
      if old.kind==kind and old.x==x and old.y==y and old.width==object.width and old.height==object.height then
        for _,key in ipairs({'crop','style','roofRows','roofInset','surfaceTopRows','surfaceDepth','surfaceInset','surfaceBevel',
            'profileClass','profileBaseStyle','profileThickness','cutoutColors','groundDX','groundDY','cutoutBackgrounds','surfaceTopRect','surfaceFrontRect','anchorDepth','wallFill','wallTopFill','wallClearRects','leafStart','leafEnd'}) do object[key]=old[key] end
      end
    end
  end
  if treatment=='auto' and object.profileBaseStyle then object.style=object.profileBaseStyle end
  if kind~='model' and kind~='none' and treatment and treatment~='auto' then
    object.style=treatment=='box' and 'native_fixture' or treatment=='voxel' and 'native_profile_voxel' or 'native_profile_cutout'
    object.cutoutColors=object.cutoutColors or source.visualProfileColors
    source.visualNativeCutouts=true
    object.profileThickness=object.profileThickness or .08
  end
  for _,old in ipairs(source.visualObjects) do
    if old.x==x and old.y==y and old.width==object.width and old.height==object.height
        and old.kind==kind and old.model==object.model and old.style==object.style and old.size==object.size and (old.rotation or 0)==object.rotation
        and (old.lean or 0)==object.lean and (old.mount or 0)==object.mount then return false end
  end
  for i=#source.visualObjects,1,-1 do
    if overlaps(source.visualObjects[i],object) and not object.allowOverlap then table.remove(source.visualObjects,i) end
  end
  source.visualObjects[#source.visualObjects+1]=object
  return true
end

function M.resize(source,width,height)
  local objects={}
  for _,object in ipairs(source.visualObjects or {}) do
    -- Remove cut-off models instead of silently moving or distorting them.
    if object.x>=0 and object.y>=0 and object.x+object.width<=width and object.y+object.height<=height then objects[#objects+1]=object end
  end
  if source.visualObjects then source.visualObjects=objects end
end

function M.draw2D(source)
  local g=love.graphics
  for _,o in ipairs(M.objects(source)) do
    if o.kind=='tree' then g.setColor(0.3,1,0.45,0.9) else g.setColor(1,0.72,0.22,0.9) end
    g.rectangle('line',o.x*16+1,o.y*16+1,o.width*16-2,o.height*16-2)
  end
end

return M
