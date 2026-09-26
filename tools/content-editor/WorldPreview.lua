local M={}
function M.cache(S)
  local c=S._worldPreviews
  if not c or c.data~=S.data or c.project~=S.project or c.tick~=S.uiPreviewTick or c.scope~=S.worldScope then
    if c then for _,entry in pairs(c.images) do entry.image:release() end end
    c={data=S.data,project=S.project,tick=S.uiPreviewTick,scope=S.worldScope,images={},count=0}
    S._worldPreviews=c
  end
  return c
end
function M.bake(cache,id,p,draw)
  -- Bound GPU memory even in All Maps. Each preview is at most 512px wide/high.
  if cache.count>=512 then
    local key=next(cache.images)
    if key then cache.images[key].image:release();cache.images[key]=nil;cache.count=cache.count-1 end
  end
  local scale=math.min(1,(cache.scope=='all' and 128 or 512)/math.max(p.w,p.h))
  local canvas=love.graphics.newCanvas(math.max(1,math.ceil(p.w*scale)),math.max(1,math.ceil(p.h*scale)))
  canvas:setFilter('nearest','nearest')
  love.graphics.push('all')
  love.graphics.setCanvas(canvas);love.graphics.origin();love.graphics.setScissor()
  love.graphics.clear(0,0,0,0);love.graphics.scale(scale,scale)
  local ok,err=pcall(draw)
  love.graphics.pop()
  if not ok then canvas:release();error(err) end
  cache.images[id]={image=canvas,scale=scale};cache.count=cache.count+1
end
return M
