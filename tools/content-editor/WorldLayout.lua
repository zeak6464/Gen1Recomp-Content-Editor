-- Arrange real edge connections; disconnected areas remain separate islands.
local M={}
function M.build(ids,resolve,destination,delta,root,mode)
  local maps,links,inbound,positions,edges={},{},{},{},{}
  local C=require('Gen3Connections')
  for _,id in ipairs(ids) do
    local def=resolve(id)
    if def and type(def.width)=='number' and type(def.height)=='number' then maps[id]=def end
  end
  for _,id in ipairs(ids) do
    local def=maps[id]
    if def then for dir,c in C.each(def.connections) do
      local dest=destination(c)
      if dest then
        local e={from=id,to=dest,dir=dir,offset=c.offset or 0,ok=maps[dest]~=nil}
        links[id]=links[id] or {};table.insert(links[id],e)
        inbound[dest]=inbound[dest] or {};table.insert(inbound[dest],e)
      end
    end end
  end
  local count,components,cursor,rowY,rowH=0,0,0,0,0
  local function component(seed)
    if positions[seed] or not maps[seed] then return end
    components=components+1
    local queue={seed};positions[seed]={x=0,y=0};local head=1
    while head<=#queue do
      local id=queue[head];head=head+1
      local p=positions[id]
      local function visit(e,reverse)
        local other=reverse and e.from or e.to
        if not maps[other] or positions[other] then return end
        local dx,dy=delta(e.dir,e.offset,maps[e.from],maps[e.to])
        positions[other]={x=p.x+(reverse and -dx or dx),y=p.y+(reverse and -dy or dy)}
        queue[#queue+1]=other
      end
      if mode~='neighbors' or id==seed then
        for _,e in ipairs(links[id] or {}) do visit(e,false) end
        for _,e in ipairs(inbound[id] or {}) do visit(e,true) end
      end
    end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    for _,id in ipairs(queue) do
      local p=positions[id];p.w=maps[id].width*32;p.h=maps[id].height*32
      minX=math.min(minX,p.x);minY=math.min(minY,p.y)
      maxX=math.max(maxX,p.x+p.w);maxY=math.max(maxY,p.y+p.h)
    end
    if cursor>0 and cursor+maxX-minX>8192 then rowY=rowY+rowH+256;cursor=0;rowH=0 end
    for _,id in ipairs(queue) do local p=positions[id];p.x=p.x-minX+cursor;p.y=p.y-minY+rowY;count=count+1 end
    rowH=math.max(rowH,maxY-minY)
    cursor=cursor+maxX-minX+256
  end
  component(root)
  if mode=='all' then for _,id in ipairs(ids) do component(id) end end
  local w,h=32,32
  for id,p in pairs(positions) do
    w=math.max(w,p.x+p.w);h=math.max(h,p.y+p.h)
    for _,e in ipairs(links[id] or {}) do
      if positions[e.to] or not e.ok then edges[#edges+1]=e end
    end
  end
  return {positions=positions,maps=maps,edges=edges,bounds={x=0,y=0,w=w,h=h},rootId=root,count=count,components=components}
end
return M
