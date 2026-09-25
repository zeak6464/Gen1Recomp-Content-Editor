local M={}
local C=require("Gen3Connections")
local function own(S,id)
  local source,err=require("Gen3Workspace").convert(S,id);assert(source,err)
  local map=assert(S.project.maps[id]);map.connections=map.connections or {};return map
end
function M.edit(S,id,dir,index,destination,offset)
  assert(C.opposite[dir],"Invalid connection direction")
  assert(type(offset)=="number" and offset%1==0,"Connection offset must be a whole number")
  local map=own(S,id);local rows=C.copy(C.list(map.connections,dir));local prev=rows[index]
  assert(index>=1 and index<=#rows+1,"Invalid connection index")
  if destination then
    assert(destination~=id,"A map cannot connect to itself")
    for i,c in ipairs(rows) do assert(i==index or c.map~=destination or c.offset~=offset,"This connection already exists") end
    own(S,destination) -- Validate before changing either endpoint.
  end
  local opposite=C.opposite[dir]
  if prev then
    local target=own(S,prev.map or prev.mapId);local backs=C.copy(C.list(target.connections,opposite))
    for i=#backs,1,-1 do if (backs[i].map or backs[i].mapId)==id and (backs[i].offset or 0)==-(prev.offset or 0) then table.remove(backs,i) end end
    C.put(target.connections,opposite,backs)
    target._g3ConnectionsEdited=true
  end
  if destination then
    rows[index]={map=destination,offset=offset}
    local target=own(S,destination);local backs=C.copy(C.list(target.connections,opposite));local found=false
    for _,back in ipairs(backs) do if (back.map or back.mapId)==id and (back.offset or 0)==-offset then found=true end end
    if not found then backs[#backs+1]={map=id,offset=-offset} end
    C.put(target.connections,opposite,backs)
    target._g3ConnectionsEdited=true
  else table.remove(rows,index) end
  C.put(map.connections,dir,rows)
  map._g3ConnectionsEdited=true
  S._worldFitKey=nil
  local Loader=require("src.world.MapLoader");Loader.invalidate(id)
  if prev then Loader.invalidate(prev.map or prev.mapId) end
  if destination then Loader.invalidate(destination) end
  return map
end
function M.draw(S,id,x,y,w,h,App)
  local K,Picker,Pane=require("Kit"),require("ChoicePicker"),require("FormPane");local s=K.scale
  local map=require("Maps").resolveMap(S,id);if not map then return end
  local ids,labels={},{}
  for _,key in ipairs(require("Autocomplete").mapIds(S)) do if key~=id then
    ids[#ids+1]=key;labels[key]=require("Gen3Names").map(key)
  end end
  local top,view=Pane.begin(S,"g3ConnectionsScroll",x,y,w,h);local cy=top;local width=view.contentW
  local function edit(dir,index,dest,offset)
    local ok,result=pcall(M.edit,S,id,dir,index,dest,offset)
    if ok then App.markDirty();S.status="Connection updated, including its return connection" else S.status=tostring(result) end
  end
  for _,dir in ipairs(C.directions) do
    local rows=C.list(map.connections,dir)
    K.caption(x,cy,dir:upper().." ("..#rows..")")
    if K.button(x+width-64*s,cy-3*s,64*s,25*s,"+ Add",{tooltip="Add another connection on this side. Each connection has its own destination and offset."}) then
      local index=#rows+1
      Picker.open(S,{ids=ids,labels=labels,title="CONNECT "..dir:upper(),onPick=function(dest) edit(dir,index,dest,0) end})
    end;cy=cy+32*s
    for i,c in ipairs(rows) do
      local index=i;local destination=c.map or c.mapId;local offset=c.offset or 0
      Picker.field(S,{x=x,y=cy,w=width,h=27*s,current=destination,ids=ids,labels=labels,title="CONNECTION DESTINATION",
        tooltip="Map reached along this section of the edge. Other connections on this side remain intact.",onPick=function(dest) edit(dir,index,dest,offset) end});cy=cy+32*s
      K.caption(x,cy+5*s,"Offset")
      local value=K.textfield("conn_"..id..dir..i,x+62*s,cy,width-132*s,25*s,tostring(offset),"0",
        "Offset in 16px cells: horizontal for north/south, vertical for east/west. The return connection uses the opposite offset. Gaps stay blocked.")
      local n=tonumber(value)
      if n and n%1==0 and n~=offset then edit(dir,index,destination,n) end
      if K.button(x+width-64*s,cy,64*s,25*s,"Remove",{tooltip="Remove only this connection and its matching return link."}) then edit(dir,index,nil,offset) end
      cy=cy+37*s
    end
    cy=cy+10*s
  end
  Pane.finish(S,"g3ConnectionsScroll",top,cy,view)
end
return M
