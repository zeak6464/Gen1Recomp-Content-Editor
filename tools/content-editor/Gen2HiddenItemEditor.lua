local M = {}

function M.add(S, map, x, y)
  for _,ev in ipairs(map.bgEvents or {}) do
    if ev.x==x and ev.y==y then return nil,"This cell already has a sign or hidden item. Choose another cell." end
  end
  local used, seen = {}, {}
  local function scan(value)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    for key, entry in pairs(value) do
      if key == "eventFlag" or key == "flag" or key == "event" then
        local flag = tonumber(entry)
        if flag then used[flag] = true end
      end
      scan(entry)
    end
  end
  scan(S.data); scan(S.project); scan(map)
  local flag = 0x8000
  while used[flag] and flag < 0xFFFF do flag = flag + 1 end
  if flag == 0xFFFF then return nil, "No unused hidden item flag available" end
  map.bgEvents = map.bgEvents or {}
  local index = #map.bgEvents + 1
  map.bgEvents[index] = {x=x, y=y, kind=7,
    hiddenItem={item=require("ItemPicker").indexForId(S,"POTION") or "POTION", event=flag}}
  S.mapSection, S.mapSignIndex, S.mapEditMode = "hidden", index, "events"
  return index
end

function M.draw(S, map, mutate, App, x, y, w, fh, s, field)
  local K, Picker = require("Kit"), require("ItemPicker")
  local function changed()
    require("src.world.MapLoader").invalidate(map.id or S.mapId)
    App.markDirty()
  end
  K.text("micro", "Choose an item and its cell. No script needed.", x, y, require("Theme").PAL.muted)
  y=y+22*s
  if K.button(x,y,w,28*s,"+ Add hidden item",{kind="good",
      tooltip="Creates a hidden Potion with its own collection flag. Change the item and location below."}) then
    map=mutate()
    local cx,cy=0,0
    local occupied={}
    local width=math.max(1,(map.width or 1)*2)
    for _,ev in ipairs(map.bgEvents or {}) do occupied[(ev.y or 0)*width+(ev.x or 0)]=true end
    local cell=0
    while occupied[cell] do cell=cell+1 end
    cx,cy=cell%width,math.floor(cell/width)
    local index,err
    if cy>=(map.height or 1)*2 then err="No free cells for a hidden item on this map"
    else index,err=M.add(S,map,cx,cy) end
    if index then changed(); S.status="Hidden item ready — choose its item and cell below"
    else S.status=err end
  end
  y=y+38*s
  local indices={}
  for i,ev in ipairs(map.bgEvents or {}) do
    if tonumber(ev.kind)==7 then indices[#indices+1]=i end
  end
  if #indices==0 then
    K.text("micro","No hidden items yet.",x,y,require("Theme").PAL.muted)
    return y+22*s
  end
  local selected=1
  for n,i in ipairs(indices) do if i==S.mapSignIndex then selected=n end end
  S.mapSignIndex=indices[selected]
  K.caption(x,y,"Hidden item "..selected.." / "..#indices)
  y=y+24*s
  if K.button(x,y,45*s,fh,"<",{}) then selected=math.max(1,selected-1) end
  if K.button(x+52*s,y,45*s,fh,">",{}) then selected=math.min(#indices,selected+1) end
  S.mapSignIndex=indices[selected]
  local i=S.mapSignIndex
  local ev=map.bgEvents[i]
  local hi=ev.hiddenItem or {}
  y=y+fh+12*s
  K.caption(x,y,"Item")
  y=y+20*s
  local raw=hi.item
  local shown=Picker.idForIndex(S,tonumber(raw)) or tostring(raw or "")
  Picker.field(S,{x=x,y=y,w=w,h=fh,current=shown,title="HIDDEN ITEM",emptyLabel="Choose item",
    onPick=function(id)
      local owned=mutate(); local rec=owned.bgEvents[i]
      rec.hiddenItem=rec.hiddenItem or {}
      rec.hiddenItem.item=Picker.indexForId(S,id) or id
      changed()
    end})
  y=y+fh+12*s
  K.caption(x,y,"Cell X / Y")
  y=y+20*s
  local cx=tonumber(field(App,"hidden_x_"..i,x,y,(w-8*s)/2,fh,tostring(ev.x or 0),"0"))
  local cy=tonumber(field(App,"hidden_y_"..i,x+(w+8*s)/2,y,(w-8*s)/2,fh,tostring(ev.y or 0),"0"))
  if cx and cy and cx>=0 and cy>=0 and cx<(map.width or 1)*2 and cy<(map.height or 1)*2
      and cx%1==0 and cy%1==0 and (cx~=ev.x or cy~=ev.y) then
    local occupied=false
    for other,rec in ipairs(map.bgEvents) do if other~=i and rec.x==cx and rec.y==cy then occupied=true end end
    if occupied then S.status="This cell already has a sign or hidden item"
    else local owned=mutate(); owned.bgEvents[i].x=cx; owned.bgEvents[i].y=cy; changed() end
  end
  y=y+fh+12*s
  K.text("micro","Collected once; pickup is handled automatically.",x,y,require("Theme").PAL.muted)
  y=y+26*s
  if K.button(x,y,w,28*s,"Delete hidden item",{kind="danger"}) then
    map=mutate(); table.remove(map.bgEvents,i); S.mapSignIndex=nil; changed()
  end
  return y+36*s
end

return M
