local M={}
local K=require("Kit")
local Movement=require("src.core.game3.scripting.movement")
local Language=require("Gen3MovementLanguage")
local choices,labels=Language.choices,{}
for _,id in ipairs(choices) do labels[id]=Language.label(tonumber(id)) end
function M.label(byte)
  return Language.label(byte)
end
function M.insert(step,byte)
  local bytes=step.movement
  local n=#bytes
  if bytes[n]==254 or bytes[n]==255 then table.insert(bytes,n,byte)
  else bytes[n+1]=byte;bytes[n+2]=254 end
end
function M.path(bytes)
  local points={{0,0}};local x,y=0,0
  for _,action in ipairs(Movement.actionsFromBytes(bytes)) do
    if action.kind=="step" then
      if action.dir=="left" then x=x-1 elseif action.dir=="right" then x=x+1
      elseif action.dir=="up" then y=y-1 else y=y+1 end
      points[#points+1]={x,y}
    end
  end
  return points
end
function M.draw(S,key,step,x,y,w,h,changed)
  local s=K.scale
  K.caption(x,y,"WHO SHOULD MOVE?")
  local ids={"255","32783"};local labels={["255"]="The player",["32783"]="The character being spoken to"}
  local mapId=S.g3EventMap or S.mapId
  local map=((S.project or {}).maps or {})[mapId] or require("Generation").dataMaps(S)[mapId]
  for i,object in ipairs(map and map.objects or {}) do
    local id=tostring(object.localId or i)
    if not labels[id] then ids[#ids+1]=id;labels[id]="Character "..id.." at "..object.x..", "..object.y end
  end
  local current=tostring(step.localId or 255)
  if not labels[current] then ids[#ids+1]=current;labels[current]="Character / variable "..current end
  require("ChoicePicker").field(S,{x=x,y=y+24*s,w=w,h=28*s,ids=ids,labels=labels,current=current,title="CHARACTER TO MOVE",
    onPick=function(value) local n=tonumber(value);if n and n~=step.localId then step.localId=n;changed() end end})
  local bytes=step.movement
  local count=#bytes
  if bytes[count]==254 or bytes[count]==255 then count=count-1 end
  local top=y+64*s;local page=math.max(1,math.floor((h-230*s)/(28*s)))
  local sk="g3MovementScroll/"..key
  S[sk]=K.scroll(x,top,w,page*28*s,S[sk] or 0,count,page)
  for i=S[sk]+1,math.min(count,S[sk]+page) do
    local yy=top+(i-S[sk]-1)*28*s
    K.caption(x,yy+4*s,K.ellipsize("micro",i..". "..M.label(bytes[i]),w-124*s))
    K.offerTooltip(x,yy,w-124*s,25*s,M.label(bytes[i]))
    if K.button(x+w-116*s,yy,52*s,25*s,"Up",{}) and i>1 then bytes[i],bytes[i-1]=bytes[i-1],bytes[i];changed() end
    if K.button(x+w-60*s,yy,52*s,25*s,"Delete",{}) then table.remove(bytes,i);changed();break end
  end
  S[sk]=K.scrollbar(x,top,w,page*28*s,S[sk],count,page)
  local by=top+page*28*s+8*s
  require("ChoicePicker").field(S,{x=x,y=by,w=w,h=28*s,ids=choices,labels=labels,current="",emptyLabel="Add movement action",title="HOW SHOULD THE CHARACTER MOVE?",
    onPick=function(id) M.insert(step,tonumber(id));changed() end})
  K.caption(x,by+36*s,"Path preview · each square is one map cell")
  local points=M.path(bytes);local minx,maxx,miny,maxy=0,0,0,0
  for _,p in ipairs(points) do minx=math.min(minx,p[1]);maxx=math.max(maxx,p[1]);miny=math.min(miny,p[2]);maxy=math.max(maxy,p[2]) end
  local size=math.min(20*s,(w-24*s)/(maxx-minx+1),70*s/(maxy-miny+1))
  love.graphics.setColor(.2,.8,.6,1)
  for i,p in ipairs(points) do
    local px=x+12*s+(p[1]-minx)*size;local py=by+63*s+(p[2]-miny)*size
    love.graphics.rectangle("line",px,py,size,size)
    if i==1 then love.graphics.circle("fill",px+size/2,py+size/2,size/4) end
    if i==#points then love.graphics.rectangle("fill",px+size*.3,py+size*.3,size*.4,size*.4) end
  end
  love.graphics.setColor(1,1,1,1)
end
return M
