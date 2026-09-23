local Kit = require("Kit")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Map = require("Gen3Map")
local Panel = {}

local function number(S,key,x,y,w,label,default,limit)
  Kit.caption(x,y,label)
  local str = Kit.textfield(key,x,y+20*Kit.scale,w,26*Kit.scale,tostring(S[key] or default),label)
  S[key] = math.max(0,math.min(limit,math.floor(tonumber(str) or default)))
  return S[key]
end

function Panel.draw(S,x,y,w,h,App)
  local s = Kit.scale
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
  local fx,fw=RegList.drawList(S,App,x,y,w,h,"Gen 3 maps",ids,
    {selKey="g3MapId",queryKey="g3MapQuery",offsetKey="g3MapOffset",listW=210*s})
  if not S.g3MapId then Kit.caption(fx,y,"Import FireRed or LeafGreen to load native maps"); return end
  local layout,err=Map.layout(S.data,S.g3MapId,S.project)
  if not layout then Kit.caption(fx,y,tostring(err)); return end
  if S.g3MapMode=="layout" then
    Kit.caption(fx,y,"Source: "..S.g3MapId..". Use a new FR_ ID to duplicate or create a blank map.")
    if S._g3LayoutFor~=S.g3MapId then
      S._g3LayoutFor=S.g3MapId;S.g3LayoutId=S.g3MapId;S.g3LayoutW=tostring(layout.width);S.g3LayoutH=tostring(layout.height)
    end
    S.g3LayoutId=Kit.textfield("g3LayoutId",fx,y+36*s,fw,28*s,S.g3LayoutId,"FR_MY_MAP")
    S.g3LayoutW=Kit.textfield("g3LayoutW",fx,y+80*s,130*s,28*s,S.g3LayoutW,"Width")
    S.g3LayoutH=Kit.textfield("g3LayoutH",fx+144*s,y+80*s,130*s,28*s,S.g3LayoutH,"Height")
    if Kit.button(fx,y+126*s,210*s,28*s,S.g3BlankMap and "Blank terrain" or "Copy source terrain",{}) then S.g3BlankMap=not S.g3BlankMap end
    Kit.caption(fx,y+168*s,"New maps use this tileset. Add a warp to reach them; blank cells start blocked.")
    if Kit.button(fx,y+208*s,180*s,30*s,"Apply layout",{kind="primary"}) then
      local id=S.g3LayoutId;local width,height=tonumber(S.g3LayoutW),tonumber(S.g3LayoutH)
      if not id:match("^FR_[A-Z0-9_]+$") or (id~=S.g3MapId and maps[id]) then S.status="Choose the current ID or an unused FR_UPPERCASE_ID"
      elseif not width or not height or width%1~=0 or height%1~=0 or width<1 or height<1 or width>512 or height>512 then S.status="Dimensions must be integers from 1 to 512"
      else
        local original=(S.project.gen3MapLayouts or {})[S.g3MapId]
        local spec={source=original and original.source or S.g3MapId,width=width,height=height,blank=S.g3BlankMap or false}
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
        S.g3MapId=id;S.gen3Id=id;S.g3MapMode="terrain";S._g3Identity=nil;App.markDirty();S.status="Map layout applied; Save to export"
      end
    end
    return
  end
  local borderMode=S.g3MapMode=="border"
  local baseLayout=layout
  if borderMode then layout=Map.borderLayout(S.project,S.g3MapId,baseLayout) end
  if S._g3MapFor~=S.g3MapId then S._g3MapFor=S.g3MapId; S.g3PanX=0; S.g3PanY=0 end
  local ts,T=Map.tileset(S.data,layout.pair)
  local rightW=math.min(265*s,fw*0.35)
  local mapW=fw-rightW-12*s
  local rx=fx+mapW+12*s
  Kit.caption(fx,y,S.g3MapId .. (borderMode and " border  " or "  ") .. layout.width .. " x " .. layout.height)
  local row=y+25*s
  local tools={"Paint","Pick","Revert"}
  for i,tool in ipairs(tools) do
    if Kit.button(fx+(i-1)*75*s,row,70*s,26*s,tool,{kind=(S.g3Tool or "Paint")==tool and "primary" or "ghost"}) then S.g3Tool=tool end
  end
  S.g3Zoom=S.g3Zoom or 2
  if Kit.button(fx+230*s,row,32*s,26*s,"-",{}) then S.g3Zoom=math.max(1,S.g3Zoom-1) end
  if Kit.button(fx+267*s,row,32*s,26*s,"+",{}) then S.g3Zoom=math.min(4,S.g3Zoom+1) end
  row=row+34*s
  for i,tool in ipairs(borderMode and {} or {"Object","Warp","Sign","Trigger"}) do
    if Kit.button(fx+(i-1)*75*s,row,70*s,25*s,tool,{kind=S.g3Tool==tool and "primary" or "ghost"}) then S.g3Tool=tool end
  end
  if borderMode then
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
  local viewH=math.max(50*s,h-146*s)
  local viewY=row
  local cols=math.max(1,math.floor(mapW/tile))
  local rows=math.max(1,math.floor(viewH/tile))
  S.g3PanX=math.max(0,math.min(S.g3PanX or 0,math.max(0,layout.width-cols)))
  S.g3PanY=math.max(0,math.min(S.g3PanY or 0,math.max(0,layout.height-rows)))
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
      if Kit.press(px,py,tile,tile) then
        local tool=S.g3Tool or "Paint"
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
  local navY=viewY+viewH+7*s
  for i,nav in ipairs({{"<",-4,0},{">",4,0},{"Up",0,-4},{"Down",0,4}}) do
    if Kit.button(fx+(i-1)*58*s,navY,53*s,26*s,nav[1],{}) then
      S.g3PanX=S.g3PanX+nav[2];S.g3PanY=S.g3PanY+nav[3]
    end
  end
  number(S,"g3Mid",rx,y,rightW,"Metatile",0,1023)
  if not borderMode then
  number(S,"g3Coll",rx,y+53*s,rightW/2-5*s,"Collision byte",0,255)
  number(S,"g3Elev",rx+rightW/2+5*s,y+53*s,rightW/2-5*s,"Elevation",0,15)
  end
  Kit.caption(rx,y+110*s,borderMode and "Border tiles are always blocked" or "Pick a tile to copy its collision")
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
