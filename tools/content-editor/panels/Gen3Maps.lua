local Kit = require("Kit")
local RegList = require("RegList")
local Regions=require("Gen3Regions")
local FormPane = require("FormPane")
local Map = require("Gen3Map")
local Void = require("Gen3Void")
local Panel = {}

-- Zoom levels (x 16 px cells): the - / + buttons and the mouse wheel step
-- through them.
local ZOOMS = {0.5,0.75,1,1.5,2,3,4,6,8}
local function stepZoom(z,dir)
  local at=1
  for i,v in ipairs(ZOOMS) do if math.abs(v-(z or 2))<math.abs(ZOOMS[at]-(z or 2)) then at=i end end
  return ZOOMS[math.max(1,math.min(#ZOOMS,at+dir))]
end

-- Every native tileset (for the tileset pickers).
local function tilesetChoices(S, current)
  local pairsById,labels={},{}
  for _,info in pairs((S.data.gen3Native or {}).layouts or {}) do
    if info.pair then pairsById[info.pair]=true end
  end
  if current then pairsById[current]=true end
  -- GAME PATCHES > FireRed Maps (Emerald): FireRed's tilesets too.
  local FrLink=require("Gen3Link")
  if FrLink.enabled(S.project) and FrLink.editor(S.project) then
    for _,pair in ipairs((FrLink.pairs(S.project))) do pairsById[pair]=true end
  end
  for pair in pairs(pairsById) do labels[pair]=FrLink.label(pair) end
  return RegList.sortedKeys(pairsById),labels
end

-- Emerald, GAME PATCHES > FireRed Maps on: MAPS > Create / resize > Tileset.
-- A tileset for the new layout, Emerald's or FireRed's (read from the
-- player's FireRed or LeafGreen import, Gen3FrLink). FireRed maps come in
-- with Import template map, or all at once with Import region.
local function fireRedRow(S,App,fx,y,fw,layout)
  local s=Kit.scale
  local FrLink=require("Gen3Link")
  local other=FrLink.name(S.project)
  if not FrLink.editor(S.project) then
    Kit.caption(fx,y,"GAME PATCHES > "..other.." Maps is on, but no "..(other=="Emerald" and "Emerald" or "FireRed or LeafGreen").." import was found.")
    return
  end
  local ids,labels=tilesetChoices(S,layout.pair)
  S.g3LayoutPair=S.g3LayoutPair or layout.pair
  Kit.caption(fx,y+6*s,"Tileset")
  require("ChoicePicker").field(S,{x=fx+110*s,y=y,w=math.min(fw-110*s,360*s),h=28*s,current=S.g3LayoutPair,ids=ids,labels=labels,
    title="Tileset for this layout",onPick=function(id) S.g3LayoutPair=id end})
  Kit.caption(fx,y+40*s,other.." tilesets and maps (Import template map) need "..(other=="Emerald" and "Emerald" or "FireRed or LeafGreen").." imported to play the mod.")
end

local function drawMid(S,pair,mid,px,py,tile)
  -- Blocks made or changed in GFX > Blocks draw as edited.
  local okW,drew=pcall(require("Gen3Workspace").drawTile,S,{nativePair=pair},mid,px,py,tile,1)
  if okW and drew then love.graphics.setColor(1,1,1,1);return end
  local ts,T=Map.tileset(S.data,pair)
  love.graphics.setColor(1,1,1,1)
  if ts then
    local slot=T.slotFor(ts,mid)
    love.graphics.draw(ts.image,T.quad(ts,slot),px,py,0,tile/16,tile/16)
    if ts.overImage then love.graphics.draw(ts.overImage,T.overQuad(ts,slot),px,py,0,tile/16,tile/16) end
  else
    love.graphics.setColor(0.12,0.17,0.23,1);love.graphics.rectangle("fill",px,py,tile,tile)
    Kit.text("micro",tostring(mid),px+2,py+2)
  end
end

-- One cell of the map itself, as the game shows it. Custom (layered) maps
-- draw every exported layer; the tile Pick takes is the top one that comes
-- from a tileset.
local function mapCell(S,id,layout,layered,resolve)
  if not layered then
    return function(x,y,px,py,tile)
      local mid=Map.cell(S.project,id,layout,x,y).mid
      if px then drawMid(S,layout.pair,mid,px,py,tile) end
      return mid,layout.pair
    end
  end
  local LayeredMap=require("LayeredMap")
  return function(x,y,px,py,tile)
    local mid,pair
    if px then love.graphics.setColor(0,0,0,1);love.graphics.rectangle("fill",px,py,tile,tile) end
    for _,layer in ipairs(layered.layers or {}) do
      if layer.visible~=false and layer.export~=false then
        local ref=(layer.cells or {})[y*layered.cellWidth+x+1]
        local desc=ref and resolve(ref.source)
        if desc then
          if px then LayeredMap.drawSourceTile(S,desc,ref.tile,px,py,tile,layer.opacity or 1,id) end
          if desc.nativePair then mid,pair=ref.tile,desc.nativePair end
        end
      end
    end
    love.graphics.setColor(1,1,1,1)
    return mid,pair
  end
end

local function connectionsOf(S,id)
  local patch=((S.project.gen3 or {}).maps or {})[id]
  local conns=patch and patch.connections
  if conns==nil then
    local okM,Maps=pcall(require,"Maps")
    local def=okM and Maps.resolveMap and Maps.resolveMap(S,id)
    conns=def and def.connections
  end
  if conns==nil then conns=(((S.data or {}).maps or {})[id] or {}).connections end
  return conns
end

-- The open map and the maps up to 2 connections away, placed as the game
-- places them (Map.computeWorld, WORLD_HOPS = 2). Space outside every map
-- belongs to one of them (Gen3Void.owner).
local function regions(S,id,layout)
  local p=S.project
  local list={{id=id,ox=0,oy=0,w=layout.width,h=layout.height,layout=layout,hops=0}}
  local seen={[id]=true}
  local qi=1
  while list[qi] do
    local cur=list[qi];qi=qi+1
    for _,row in ipairs(cur.hops<2 and require("Gen3Connections").each(connectionsOf(S,cur.id)) or {}) do
      local dir,c=row[1],row[2]
      local nid=c.map or c.mapId
      if nid and not seen[nid] then
        local okL,nl=pcall(Map.layout,S.data,nid,p)
        if okL and nl and nl.width then
          seen[nid]=true
          local off=tonumber(c.offset) or 0
          local ox,oy
          if dir=="north" then ox,oy=off,-nl.height
          elseif dir=="south" then ox,oy=off,cur.h
          elseif dir=="west" then ox,oy=-nl.width,off
          else ox,oy=cur.w,off end
          list[#list+1]={id=nid,dir=cur.hops==0 and dir or nil,ox=cur.ox+ox,oy=cur.oy+oy,
            w=nl.width,h=nl.height,layout=nl,hops=cur.hops+1}
        end
      end
    end
  end
  local DayNight=require("Gen3DayNight")
  local resolve
  for _,r in ipairs(list) do
    local layered=(p.layeredMaps or {})[r.id]
    if layered and not resolve then resolve=require("LayeredMap").sourceResolver(S) end
    r.cell=mapCell(S,r.id,r.layout,layered,resolve)
    r.fill=Void.fillFor(p,r.id,DayNight.isOutdoorMap(S,r.id))
    r.border=Map.borderLayout(p,r.id,r.layout)
    r.margin=Void.margin(p,r.id)
  end
  return list
end

-- Border > Around the map: the map, the maps connected to it and the space
-- around them, as the game draws it (painted tile, extrude or the border
-- pattern of the nearest map). Paint / Revert change single cells outside
-- every map; right-click or Pick copies any cell's tile.
local function drawAround(S,App,fx,viewY,mapW,viewH,tile,layout)
  local id=S.g3MapId
  local list=regions(S,id,layout)
  local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
  for _,r in ipairs(list) do
    minX=math.min(minX,r.ox-r.margin);minY=math.min(minY,r.oy-r.margin)
    maxX=math.max(maxX,r.ox+r.w+r.margin);maxY=math.max(maxY,r.oy+r.h+r.margin)
  end
  local W,H=maxX-minX,maxY-minY
  local cols=math.max(1,math.floor(mapW/tile))
  local rows=math.max(1,math.floor(viewH/tile))
  if S._g3AroundFor~=id then
    -- open on this map, not on a neighbour's far corner
    S._g3AroundFor=id
    S.g3PanX=(-list[1].margin)-minX;S.g3PanY=(-list[1].margin)-minY
  end
  S.g3PanX=math.max(0,math.min(S.g3PanX or 0,math.max(0,W-cols)))
  S.g3PanY=math.max(0,math.min(S.g3PanY or 0,math.max(0,H-rows)))
  local paintPair=Void.paintPair(S.project,id,layout.pair)
  local tool=S.g3Tool or "Paint"
  Kit.pushClip(fx,viewY,mapW,viewH)
  for vy=S.g3PanY,math.min(H-1,S.g3PanY+rows) do
    for vx=S.g3PanX,math.min(W-1,S.g3PanX+cols) do
      local x,y=vx+minX,vy+minY
      local px,py=fx+(vx-S.g3PanX)*tile,viewY+(vy-S.g3PanY)*tile
      local on
      for _,r in ipairs(list) do
        if x>=r.ox and y>=r.oy and x<r.ox+r.w and y<r.oy+r.h then on=r;break end
      end
      local mid,pair,painted,paintedIn,owner
      if on then mid,pair=on.cell(x-on.ox,y-on.oy,px,py,tile)
      else
        local o=Void.owner(list,x,y)
        owner=list[o]
        painted,paintedIn=Void.paintedAt(S.project,list,o,x,y)
        local lx,ly=x-owner.ox,y-owner.oy
        if painted then mid,pair=painted.m,painted.p;drawMid(S,pair,mid,px,py,tile)
        elseif owner.fill=="extrude" then mid,pair=owner.cell(Void.edge(lx,owner.w),Void.edge(ly,owner.h),px,py,tile)
        else
          local b=owner.border
          mid,pair=b:cellAt(lx%b.width,ly%b.height).mid,b.pair
          drawMid(S,pair,mid,px,py,tile)
        end
        love.graphics.setColor(1,1,1,0.10);love.graphics.rectangle("line",px,py,tile,tile)
      end
      if painted then
        love.graphics.setColor(0.2,1,0.6,0.95)
        love.graphics.polygon("fill",px,py,px+tile*0.3,py,px,py+tile*0.3)
      end
      local hit=Kit.press(px,py,tile,tile)
      if hit then S._g3Drag=tool=="Paint" or tool=="Revert" end
      local drag=not hit and S._g3Drag and Kit.mouseDown and not Kit.blockClicks and Kit.hit(px,py,tile,tile)
      -- Right-click picks, like the Pencil in the map builder.
      local rpick=S._g3RightClick and Kit.hit(px,py,tile,tile)
      if hit and tool=="Map" then
        local target=on or owner
        if target and target.id~=id then
          S.g3MapId=target.id;S.gen3Id=target.id
          S.status="Now editing "..target.id.."'s border"
        elseif target then S.status="Already editing "..id end
      elseif rpick or (hit and tool=="Pick") then
        if mid and pair then
          S.g3Mid=mid
          if Void.setPaintPair(S.project,id,pair,layout.pair) then S.g3PaletteScroll=0;App.markDirty() end
          if tool=="Pick" then S.g3Tool="Paint" end
          S.status="Picked tile "..mid
        else S.status="That tile comes from a picture, not a tileset: pick from the palette" end
      elseif (hit or drag) and (tool=="Paint" or tool=="Revert") and not S._g3Panning then
        if on then
          if hit then
            S.status=on.id==id and "That's the map itself (edit it in Terrain). Paint around it."
              or ("That's "..on.id..(on.dir and " (connected "..on.dir..")" or "")..". Paint the space around the maps, or open it to edit its tiles.")
          end
        elseif tool=="Revert" then
          if painted and Void.paint(S.project,paintedIn.id,paintedIn.w,paintedIn.h,x-paintedIn.ox,y-paintedIn.oy,nil) then App.markDirty() end
        else
          -- the tile belongs to the nearest map (kept in its own margin)
          local changed,why=Void.paint(S.project,owner.id,owner.w,owner.h,x-owner.ox,y-owner.oy,S.g3Mid or 0,paintPair)
          if changed then App.markDirty() end
          if why=="margin" and hit then S.status="Past "..owner.id.."'s margin: make its margin bigger to paint here" end
        end
      end
    end
  end
  -- map edges: this map yellow, connected maps blue with their name
  if love.graphics.setLineWidth then love.graphics.setLineWidth(math.max(1,2*Kit.scale)) end
  for i=#list,1,-1 do
    local r=list[i]
    local bx,by=fx+(r.ox-minX-S.g3PanX)*tile,viewY+(r.oy-minY-S.g3PanY)*tile
    if i==1 then love.graphics.setColor(1,0.85,0.25,0.95) else love.graphics.setColor(0.35,0.75,1,0.9) end
    love.graphics.rectangle("line",bx,by,r.w*tile,r.h*tile)
    if i>1 then
      local label=r.dir and (r.id.."  ("..r.dir..")") or r.id
      local tw=Kit.textWidth("micro",label)+10*Kit.scale
      local lx=math.max(fx+4*Kit.scale,math.min(bx+4*Kit.scale,fx+mapW-tw-4*Kit.scale))
      local ly=math.max(viewY+4*Kit.scale,math.min(by+4*Kit.scale,viewY+viewH-22*Kit.scale))
      love.graphics.setColor(0,0,0,0.6);love.graphics.rectangle("fill",lx,ly,tw,18*Kit.scale,4*Kit.scale,4*Kit.scale)
      Kit.text("micro",label,lx+5*Kit.scale,ly+2*Kit.scale,require("Theme").PAL.heading)
    end
  end
  if love.graphics.setLineWidth then love.graphics.setLineWidth(1) end
  Kit.popClip()
  love.graphics.setColor(1,1,1,1)
end

local function number(S,key,x,y,w,label,default,limit)
  Kit.caption(x,y,label)
  local str = Kit.textfield(key,x,y+20*Kit.scale,w,26*Kit.scale,tostring(S[key] or default),label)
  S[key] = math.max(0,math.min(limit,math.floor(tonumber(str) or default)))
  return S[key]
end

function Panel.draw(S,x,y,w,h,App)
  local s = Kit.scale
  -- Left paints (click or drag); right-click picks the tile under the mouse.
  local rmb=love.mouse and love.mouse.isDown and love.mouse.isDown(2)
  S._g3RightClick=(rmb and not S._g3RmbWasDown and not Kit.blockClicks) or nil
  S._g3RmbWasDown=rmb and true or false
  if not Kit.mouseDown then S._g3Drag=nil end
  if Kit.button(x,y,130*s,28*s,"Terrain",{kind=(S.g3MapMode==nil or S.g3MapMode=="terrain") and "primary" or "ghost"}) then S.g3MapMode="terrain" end
  if Kit.button(x+140*s,y,170*s,28*s,"Events / properties",{kind=S.g3MapMode=="records" and "primary" or "ghost"}) then
    local layered=S.project and S.project.layeredMaps and S.project.layeredMaps[S.g3MapId]
    if layered and S.mapWorkspace then
      S.mapBorderEditor=false;S.builderPane="details";S.mapId=S.g3MapId;S.builderMapId=S.g3MapId
    else S.g3MapMode="records";S.gen3Id=S.g3MapId end
  end
  if Kit.button(x+320*s,y,140*s,28*s,"Create / resize",{kind=S.g3MapMode=="layout" and "primary" or "ghost"}) then S.g3MapMode="layout" end
  if Kit.button(x+470*s,y,100*s,28*s,"Border",{kind=S.g3MapMode=="border" and "primary" or "ghost"}) then S.g3MapMode="border";S.g3Tool="Paint" end
  y,h=y+40*s,h-40*s
  if S.g3MapMode=="records" then return require("Gen3Records").draw(S,x,y,w,h,App) end
  if not S.project then Kit.caption(x,y,"Create or open a mod first"); return end
  local maps={};for id,def in pairs(S.data and S.data.maps or {}) do maps[id]=def end
  -- Newly created layered maps do not enter the Gen 3 registry until save.
  -- Include their project records so every editor path has a map definition.
  for id,def in pairs(S.project.maps or {}) do maps[id]=def end
  for id,def in pairs((S.project.gen3 or {}).maps or {}) do if not maps[id] then maps[id]=def end end
  local ids=RegList.sortedKeys(maps)
  S.g3MapId=S.g3MapId or ids[1]
  local fx,fw=RegList.drawList(S,App,x,y,w,h,require("Generation").label(S).." maps",ids,
    {selKey="g3MapId",queryKey="g3MapQuery",offsetKey="g3MapOffset",listW=210*s,
      searchPh="search... (@region)",
      label=function(id) local map=(S.project.maps or {})[id];return map and (map.name or map.label) or id end,
      -- regions you defined: a colour mark per map, and "@name" in the search
      marker=function(id) local c=Regions.colorOf(S.project,id);if not c then return nil end;local r,g,b=Regions.rgb(c);return {r,g,b} end,
      filter=function(id,q)
        local hit=Regions.matches(S.project,id,q)
        if hit~=nil then return hit end
        local map=(S.project.maps or {})[id];local label=map and (map.name or map.label) or id
        return (id.." "..label):lower():find(q:lower(),1,true)~=nil
      end})
  if not S.g3MapId then Kit.caption(fx,y,"Import FireRed, LeafGreen or Emerald to load native maps"); return end
  local layout,err=Map.layout(S.data,S.g3MapId,S.project)
  if not layout then Kit.caption(fx,y,tostring(err)); return end
  if S.g3MapMode=="layout" then
    local prefix=require("Generation").gen3MapPrefix(S)
    Kit.caption(fx,y,"Source: "..S.g3MapId..". Use a new "..prefix.." ID to duplicate or create a blank map.")
    if S._g3LayoutFor~=S.g3MapId then
      S._g3LayoutFor=S.g3MapId;S.g3LayoutId=S.g3MapId;S.g3LayoutPair=nil;S.g3LayoutW=tostring(layout.width);S.g3LayoutH=tostring(layout.height)
    end
    S.g3LayoutId=Kit.textfield("g3LayoutId",fx,y+36*s,fw,28*s,S.g3LayoutId,prefix.."MY_MAP")
    S.g3LayoutW=Kit.textfield("g3LayoutW",fx,y+80*s,130*s,28*s,S.g3LayoutW,"Width")
    S.g3LayoutH=Kit.textfield("g3LayoutH",fx+144*s,y+80*s,130*s,28*s,S.g3LayoutH,"Height")
    if Kit.button(fx,y+126*s,210*s,28*s,S.g3BlankMap and "Blank terrain" or "Copy source terrain",{}) then S.g3BlankMap=not S.g3BlankMap end
    Kit.caption(fx,y+168*s,"New maps use this tileset. Add a warp to reach them; blank cells start blocked.")
    if Kit.button(fx,y+208*s,180*s,30*s,"Apply layout",{kind="primary"}) then
      local id=S.g3LayoutId;local width,height=tonumber(S.g3LayoutW),tonumber(S.g3LayoutH)
      if not id:match("^"..prefix.."[A-Z0-9_]+$") or (id~=S.g3MapId and maps[id]) then S.status="Choose the current ID or an unused "..prefix.."UPPERCASE_ID"
      elseif not width or not height or width%1~=0 or height%1~=0 or width<1 or height<1 or width>512 or height>512 then S.status="Dimensions must be integers from 1 to 512"
      else
        local original=(S.project.gen3MapLayouts or {})[S.g3MapId]
        local spec={source=original and original.source or S.g3MapId,width=width,height=height,blank=S.g3BlankMap or false}
        -- another tileset (MAPS > Create / resize > Tileset, Emerald)
        local pair=S.g3LayoutPair or (original and original.pair)
        if pair and pair~=layout.pair then spec.pair=pair elseif original and original.pair then spec.pair=original.pair end
        S.project.gen3MapLayouts=S.project.gen3MapLayouts or {};S.project.gen3MapLayouts[id]=spec
        S.project.gen3=S.project.gen3 or {};S.project.gen3.maps=S.project.gen3.maps or {}
        if id~=S.g3MapId then
          local def=require("src.mods.Merge").deepCopy(maps[S.g3MapId])
          for k,v in pairs(S.project.gen3.maps[S.g3MapId] or {}) do def[k]=v end
          def.id=id;def.name=id;def.width=width;def.height=height;def.midLayout=nil
          if S.g3BlankMap then def.objects={};def.warps={};def.bgEvents={};def.coordEvents={};def.mapScripts={};def.connections={} end
          S.project.gen3.maps[id]=def
          S.project.gen3Modes=S.project.gen3Modes or {};S.project.gen3Modes.maps=S.project.gen3Modes.maps or {};S.project.gen3Modes.maps[id]="register"
          if not S.g3BlankMap and S.project.gen3Terrain and S.project.gen3Terrain[S.g3MapId] then
            S.project.gen3Terrain[id]=require("src.mods.Merge").deepCopy(S.project.gen3Terrain[S.g3MapId])
          end
        end
        if id~=S.g3MapId and (S.project.gen3Borders or {})[S.g3MapId] then
          S.project.gen3Borders[id]=require("src.mods.Merge").deepCopy(S.project.gen3Borders[S.g3MapId])
        end
        if id~=S.g3MapId and Void.record(S.project,S.g3MapId) then
          S.project.gen3VoidMaps[id]=require("src.mods.Merge").deepCopy(Void.record(S.project,S.g3MapId))
        end
        S.g3MapId=id;S.gen3Id=id;S.g3MapMode="terrain";S._g3Identity=nil;S.g3LayoutPair=nil;App.markDirty();S.status="Map layout applied; Save to export"
      end
    end
    if require("Gen3Link").enabled(S.project) then fireRedRow(S,App,fx,y+256*s,fw,layout) end
    return
  end
  local borderMode=S.g3MapMode=="border"
  local around=borderMode and (S.g3BorderView or "around")=="around"
  local baseLayout=layout
  if borderMode and not around then layout=Map.borderLayout(S.project,S.g3MapId,baseLayout) end
  if S._g3MapFor~=S.g3MapId then S._g3MapFor=S.g3MapId; S.g3PanX=0; S.g3PanY=0 end
  local paintPair=around and Void.paintPair(S.project,S.g3MapId,layout.pair) or layout.pair
  local ts,T=Map.tileset(S.data,paintPair)
  local rightW=math.min(265*s,fw*0.35)
  local mapW=fw-rightW-12*s
  local rx=fx+mapW+12*s
  if around then
    Kit.caption(fx,y,S.g3MapId.."  outside the map  ("..layout.width.." x "..layout.height..", margin "..Void.margin(S.project,S.g3MapId)..")  zoom "..math.floor((S.g3Zoom or 2)*100+0.5).."%")
  else
    Kit.caption(fx,y,S.g3MapId .. (borderMode and " border  " or "  ") .. layout.width .. " x " .. layout.height)
  end
  local row=y+25*s
  -- Map (Around the map only): click a connected map to edit it instead.
  if S.g3Tool=="Map" and not around then S.g3Tool="Paint" end
  local tools=around and {"Paint","Pick","Revert","Pan","Map"} or {"Paint","Pick","Revert","Pan"}
  for i,tool in ipairs(tools) do
    local tips={Paint="Click or drag to paint. Right-click any tile to pick it.",Pick="Click a tile to copy it (right-click does this with any tool)",Revert="Click or drag to put tiles back",
      Pan="Drag to move around. With any tool: hold the middle mouse button, or Space, and drag.",
      Map="Click a connected map to edit its border instead (or the space nearest to it)"}
    if Kit.button(fx+(i-1)*75*s,row,70*s,26*s,tool,{kind=(S.g3Tool or "Paint")==tool and "primary" or "ghost",tooltip=tips[tool]}) then S.g3Tool=tool end
  end
  local zx=#tools*75+5
  S.g3Zoom=S.g3Zoom or 2
  local zoomTip="Zoom "..math.floor(S.g3Zoom*100+0.5).."%. Mouse wheel over the map zooms too; Shift+wheel scrolls up/down, Ctrl+wheel left/right."
  if Kit.button(fx+zx*s,row,32*s,26*s,"-",{tooltip=zoomTip}) then S.g3Zoom=stepZoom(S.g3Zoom,-1) end
  if Kit.button(fx+(zx+37)*s,row,32*s,26*s,"+",{tooltip=zoomTip}) then S.g3Zoom=stepZoom(S.g3Zoom,1) end
  if borderMode then
    for i,view in ipairs({{"around","Around the map","The map with the tiles around it: choose the fill, paint single tiles"},
        {"pattern","Pattern","The game's repeating border pattern"}}) do
      local on=(S.g3BorderView or "around")==view[1]
      if Kit.button(fx+(zx+75+(i-1)*115)*s,row,110*s,26*s,view[2],{kind=on and "primary" or "ghost",font="micro",tooltip=view[3]}) then
        S.g3BorderView=view[1]
      end
    end
  end
  row=row+34*s
  for i,tool in ipairs(borderMode and {} or {"Object","Warp","Sign","Trigger"}) do
    if Kit.button(fx+(i-1)*75*s,row,70*s,25*s,tool,{kind=S.g3Tool==tool and "primary" or "ghost"}) then S.g3Tool=tool end
  end
  if around then
    local id=S.g3MapId
    Kit.caption(fx,row,"This map")
    local own=Void.mapFill(S.project,id)
    local choices={{false,"Mod default","Whatever the mod default says (outdoor maps), otherwise the game border"},
      {"border","Game border","The game's repeating border pattern (see Pattern)"},
      {"extrude","Extrude","The map's last 2 rows and columns carried on outward, so trees stay whole"}}
    for i,c in ipairs(choices) do
      local fill=c[1] or nil
      if Kit.button(fx+(110+(i-1)*98)*s,row-3*s,94*s,26*s,c[2],{kind=own==fill and "primary" or "ghost",font="micro",tooltip=c[3]}) then
        if Void.setMapFill(S.project,id,fill) then App.markDirty() end
      end
    end
    if S._g3VoidMarginFor~=id then S._g3VoidMarginFor=id;S.g3VoidMargin=tostring(Void.margin(S.project,id)) end
    local mx=fx+416*s
    Kit.caption(mx,row,"Margin")
    S.g3VoidMargin=Kit.textfield("g3VoidMargin",mx+54*s,row-3*s,44*s,26*s,S.g3VoidMargin,tostring(Void.DEFAULT_MARGIN),
      "How many tiles out from the map you can paint (0-"..Void.MAX_MARGIN.."). Past that, the fill shows.")
    if Kit.button(mx+104*s,row-3*s,50*s,26*s,"Set",{kind="accent",font="micro"}) then
      local changed,info=Void.setMargin(S.project,id,layout.width,layout.height,S.g3VoidMargin)
      if changed then
        App.markDirty()
        S.status=(info or 0)>0 and ("Margin set; "..info.." painted tile(s) past it were removed") or "Margin set"
      elseif info then S.status=info end
    end
    row=row+31*s
    Kit.caption(fx,row,"Mod default")
    for i,fill in ipairs(Void.FILLS) do
      if Kit.button(fx+(110+(i-1)*98)*s,row-3*s,94*s,26*s,Void.LABELS[fill],{kind=Void.default(S.project)==fill and "primary" or "ghost",font="micro",
          tooltip="For every outdoor map (Town, City, Route, Ocean route) that doesn't choose its own"}) then
        if Void.setDefault(S.project,fill) then App.markDirty() end
      end
    end
    local outdoor=require("Gen3DayNight").isOutdoorMap(S,id)
    Kit.caption(fx+318*s,row,"Outdoor maps.  This map shows: "..Void.LABELS[Void.fillFor(S.project,id,outdoor)]
      ..(own==nil and not outdoor and " (not an outdoor map)" or ""))
  elseif borderMode then
    if S._g3BorderSizeFor~=S.g3MapId then
      S._g3BorderSizeFor=S.g3MapId
      S.g3BorderW=tostring(layout.width);S.g3BorderH=tostring(layout.height)
    end
    Kit.caption(fx,row,"Pattern size")
    S.g3BorderW=Kit.textfield("g3BorderW",fx+88*s,row-3*s,52*s,26*s,S.g3BorderW,"W")
    Kit.caption(fx+147*s,row,"x")
    S.g3BorderH=Kit.textfield("g3BorderH",fx+163*s,row-3*s,52*s,26*s,S.g3BorderH,"H")
    if Kit.button(fx+225*s,row-3*s,92*s,26*s,"Resize",{kind="accent"}) then
      local changed,sizeErr=Map.resizeBorder(S.project,S.g3MapId,baseLayout,
        tonumber(S.g3BorderW),tonumber(S.g3BorderH))
      if changed then
        App.markDirty();S.status="Border pattern resized; paint the new cells, then Save"
      elseif sizeErr then S.status=sizeErr end
    end
    Kit.caption(fx+327*s,row,"Repeats outside the map (1–512 each)")
  end
  row=row+31*s
  local tile=16*s*S.g3Zoom
  local viewH=math.max(50*s,h-146*s-(around and 31*s or 0))
  local viewY=row
  -- Pan: the Pan tool, or the middle mouse button / Space with any tool.
  local mmb=love.mouse and love.mouse.isDown and love.mouse.isDown(3)
  local space=love.keyboard.isDown("space")
  if (S.g3Tool=="Pan" and Kit.mouseDown) or mmb or (space and Kit.mouseDown) then
    local d=S._g3PanDrag
    if not d then
      if Kit.hit(fx,viewY,mapW,viewH) and not Kit.blockClicks then
        S._g3PanDrag={mx=Kit.mouseX,my=Kit.mouseY,px=S.g3PanX or 0,py=S.g3PanY or 0}
      end
    else
      S.g3PanX=math.max(0,math.floor(d.px-(Kit.mouseX-d.mx)/tile+0.5))
      S.g3PanY=math.max(0,math.floor(d.py-(Kit.mouseY-d.my)/tile+0.5))
    end
  else S._g3PanDrag=nil end
  S._g3Panning=S._g3PanDrag~=nil or S.g3Tool=="Pan" or nil
  -- Mouse wheel over the map: zoom around the pointer; Shift / Ctrl scroll.
  local wheel=Kit.wheelY or 0
  if wheel~=0 and not Kit.blockClicks and Kit.hit(fx,viewY,mapW,viewH) then
    Kit.wheelY=0
    local dir=wheel>0 and 1 or -1
    if love.keyboard.isDown("lshift","rshift") then S.g3PanY=math.max(0,(S.g3PanY or 0)-dir*3)
    elseif love.keyboard.isDown("lctrl","rctrl","lgui","rgui") then S.g3PanX=math.max(0,(S.g3PanX or 0)-dir*3)
    else
      local z=stepZoom(S.g3Zoom,dir)
      if z~=S.g3Zoom then
        local ax,ay=(S.g3PanX or 0)+(Kit.mouseX-fx)/tile,(S.g3PanY or 0)+(Kit.mouseY-viewY)/tile
        S.g3Zoom=z;tile=16*s*z
        S.g3PanX=math.max(0,math.floor(ax-(Kit.mouseX-fx)/tile+0.5))
        S.g3PanY=math.max(0,math.floor(ay-(Kit.mouseY-viewY)/tile+0.5))
      end
    end
  end
  if around then drawAround(S,App,fx,viewY,mapW,viewH,tile,layout) end
  local cols=math.max(1,math.floor(mapW/tile))
  local rows=math.max(1,math.floor(viewH/tile))
  if not around then
    S.g3PanX=math.max(0,math.min(S.g3PanX or 0,math.max(0,layout.width-cols)))
    S.g3PanY=math.max(0,math.min(S.g3PanY or 0,math.max(0,layout.height-rows)))
  end
  if not around then
  Kit.pushClip(fx,viewY,mapW,viewH)
  for cy=S.g3PanY,math.min(layout.height-1,S.g3PanY+rows) do
    for cx=S.g3PanX,math.min(layout.width-1,S.g3PanX+cols) do
      local cell=borderMode and layout:cellAt(cx,cy) or Map.cell(S.project,S.g3MapId,layout,cx,cy)
      local px,py=fx+(cx-S.g3PanX)*tile,viewY+(cy-S.g3PanY)*tile
      love.graphics.setColor(1,1,1,1)
      if ts then
        local slot=T.slotFor(ts,cell.mid)
        love.graphics.draw(ts.image,T.quad(ts,slot),px,py,0,tile/16,tile/16)
        if ts.overImage then love.graphics.draw(ts.overImage,T.overQuad(ts,slot),px,py,0,tile/16,tile/16) end
      else
        love.graphics.setColor(0.12,0.17,0.23,1);love.graphics.rectangle("fill",px,py,tile,tile)
        Kit.text("micro",tostring(cell.mid),px+2,py+2)
      end
      love.graphics.setColor(1,1,1,0.14);love.graphics.rectangle("line",px,py,tile,tile)
      local tool=S.g3Tool or "Paint"
      local hit=Kit.press(px,py,tile,tile)
      if hit then S._g3Drag=tool=="Paint" or tool=="Revert" end
      local drag=not hit and S._g3Drag and Kit.mouseDown and not Kit.blockClicks and Kit.hit(px,py,tile,tile)
      -- Right-click picks, like the Pencil in the map builder.
      if S._g3RightClick and Kit.hit(px,py,tile,tile) then
        if borderMode then S.g3Mid=cell.mid
        else S.g3Mid,S.g3Coll,S.g3Elev=cell.mid,cell.coll,cell.elev end
        if tool=="Pick" then S.g3Tool="Paint" end
        S.status="Picked tile "..cell.mid
      elseif not S._g3Panning and (hit or (drag and (tool=="Paint" or tool=="Revert"))) then
        local hitKind,hitIndex
        if not borderMode and tool~="Paint" and tool~="Revert" and not love.keyboard.isDown("lshift","rshift") then
          local patch=((S.project.gen3 or {}).maps or {})[S.g3MapId] or {}
          for _,group in ipairs({"objects","warps","signs","coordEvents"}) do
            local def=maps[S.g3MapId] or {}
            local events=patch[group] or group=="signs" and (patch.bgEvents or def.signs or def.bgEvents) or def[group]
            for i,event in ipairs(events or {}) do
              if event.x==cx and event.y==cy then hitKind,hitIndex=group,i end
            end
          end
        end
        if hitKind then
          require("Gen3EventWindow").request(S,S.g3MapId,hitKind,hitIndex)
        elseif borderMode then
          if tool=="Pick" then S.g3Mid=cell.mid
          else
            local mid=tool=="Revert" and (baseLayout.borderMids[cy*layout.width+cx+1] or 0) or (S.g3Mid or 0)
            if Map.paintBorder(S.project,S.g3MapId,baseLayout,cx,cy,mid) then App.markDirty() end
          end
        elseif tool=="Object" or tool=="Warp" or tool=="Sign" or tool=="Trigger" then
          S.mapId=S.g3MapId
          require("Gen3MapEvents").place(S,tool:lower(),cx,cy,App)
        elseif tool=="Pick" then S.g3Mid,S.g3Coll,S.g3Elev=cell.mid,cell.coll,cell.elev
        else
          local chosen=tool=="Revert" and layout:cellAt(cx,cy)
            or {mid=S.g3Mid or 0,coll=S.g3Coll or cell.coll,elev=S.g3Elev or cell.elev}
          if Map.paint(S.project,S.g3MapId,layout,cx,cy,chosen) then App.markDirty() end
        end
      end
    end
  end
  local def=maps[S.g3MapId] or {};local patch=((S.project.gen3 or {}).maps or {})[S.g3MapId] or {}
  for _,group in ipairs(borderMode and {} or {{"objects","O"},{"warps","W"},{"bgEvents","S"},{"coordEvents","T"}}) do
    local base=def[group[1]]
    if group[1]=="bgEvents" then base=base or def.signs end
    for i,ev in ipairs(patch[group[1]] or base or {}) do
      if ev.x and ev.y then
        local px,py=fx+(ev.x-S.g3PanX)*tile,viewY+(ev.y-S.g3PanY)*tile
        love.graphics.setColor(0.9,0.5,0.1,0.65);love.graphics.rectangle("fill",px,py,tile,tile)
        Kit.text("micro",group[2]..i,px+2,py+2)
      end
    end
  end
  Kit.popClip()
  end
  local navY=viewY+viewH+7*s
  for i,nav in ipairs({{"<",-4,0},{">",4,0},{"Up",0,-4},{"Down",0,4}}) do
    if Kit.button(fx+(i-1)*58*s,navY,53*s,26*s,nav[1],{}) then
      S.g3PanX=S.g3PanX+nav[2];S.g3PanY=S.g3PanY+nav[3]
    end
  end
  number(S,"g3Mid",rx,y,rightW,"Metatile",0,1023)
  if around then
    local ids,labels=tilesetChoices(S,paintPair)
    Kit.caption(rx,y+53*s,"Paint tileset")
    require("ChoicePicker").field(S,{x=rx,y=y+76*s,w=rightW,h=28*s,current=paintPair,
      ids=ids,labels=labels,title="PAINT TILESET",
      tooltip="Tiles painted around the map can come from any tileset. Pick also switches to the picked tile's tileset.",
      onPick=function(pair)
        if Void.setPaintPair(S.project,S.g3MapId,pair,layout.pair) then S.g3PaletteScroll=0;S.g3Tool="Paint";App.markDirty() end
      end})
  elseif borderMode and (S.project.layeredMaps or {})[S.g3MapId] then
    local ids,labels=tilesetChoices(S,layout.pair)
    Kit.caption(rx,y+53*s,"Border tileset")
    require("ChoicePicker").field(S,{x=rx,y=y+76*s,w=rightW,h=28*s,current=layout.pair,
      ids=ids,labels=labels,title="BORDER TILESET",
      tooltip="Choose the tileset used only by this border. Then select a metatile below and paint the border cells. Existing tile numbers are kept; the map interior is unchanged.",
      onPick=function(pair)
        if Map.setBorderTileset(S.project,S.g3MapId,baseLayout,pair) then
          S.g3PaletteScroll=0;S.g3Tool="Paint";App.markDirty();S.status="Border tileset changed; select a tile and paint the border"
        end
      end})
  end
  if not borderMode then
  number(S,"g3Coll",rx,y+53*s,rightW/2-5*s,"Collision byte",0,255)
  number(S,"g3Elev",rx+rightW/2+5*s,y+53*s,rightW/2-5*s,"Elevation",0,15)
  end
  Kit.caption(rx,y+110*s,around and "Only for looks (not walkable)" or borderMode and "Border tiles are always blocked" or "Pick a tile to copy its collision")
  if not ts then Kit.caption(rx,y+140*s,"Native atlas unavailable"); return end
  local mids={};for mid in pairs(ts.midToSlot) do mids[#mids+1]=mid end;table.sort(mids)
  local pt,pv=FormPane.begin(S,"g3PaletteScroll",rx,y+139*s,rightW,math.max(30*s,h-145*s))
  local cellW=32*s
  local ncols=math.max(1,math.floor(pv.contentW/cellW))
  for i,mid in ipairs(mids) do
    local px=rx+((i-1)%ncols)*cellW
    local py=pt+math.floor((i-1)/ncols)*cellW
    if py+cellW>=pv.y and py<=pv.y+pv.h then
      local slot=T.slotFor(ts,mid)
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(ts.image,T.quad(ts,slot),px,py,0,cellW/16,cellW/16)
      if ts.overImage then love.graphics.draw(ts.overImage,T.overQuad(ts,slot),px,py,0,cellW/16,cellW/16) end
      if Kit.press(px,py,cellW,cellW) then S.g3Mid=mid end
      if mid==S.g3Mid then love.graphics.setColor(0,1,0.5,1);love.graphics.rectangle("line",px,py,cellW,cellW) end
    end
  end
  FormPane.finish(S,"g3PaletteScroll",pt,pt+math.ceil(#mids/ncols)*cellW,pv)
  love.graphics.setColor(1,1,1,1)
end

return Panel
