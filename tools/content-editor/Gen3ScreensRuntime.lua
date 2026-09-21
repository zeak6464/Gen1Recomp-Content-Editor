local M={}
local images={}
function M.image(encoded)
 if not encoded then return end
 if not images[encoded] then
  local image=love.graphics.newImage(love.filesystem.newFileData(love.data.decode("string","base64",encoded),"screen.png"))
  image:setFilter("nearest","nearest");images[encoded]=image
 end
 return images[encoded]
end
function M.draw(row,kind,art)
 local g=love.graphics;g.push("all");g.setColor(0,0,0,1);g.rectangle("fill",0,0,240,160)
 local img=M.image(row.image or (art or {})[row.art]);g.setColor(1,1,1,1)
 if img then
  local w,h=img:getDimensions()
  if kind=="areas" then g.draw(img,0,0)
  elseif row.art and row.art:match("^ground_") and not row.image then
   local q=g.newQuad(0,0,64,32,w,h);g.draw(img,q,88,120)
  else local s=math.min(240/w,160/h,1);g.draw(img,(240-w*s)/2,(160-h*s)/2,0,s,s) end
 end
 local font=require("src.ui.game3.frlg_font")
 if kind=="areas" then font.draw(row.name or "",4,4,{color={.2,.2,.2,1},small=true,maxWidth=96}) end
 if kind=="credits" then
  font.draw(row.title or "",12,10,{color={1,1,1,1},small=true,maxWidth=216})
  font.draw(row.text or "",12,40,{color={1,1,1,1},small=true,maxWidth=216,linePitch=12})
 end
 g.pop()
end
function M.install(mod,config)
 local RT=require("src.mods.Runtime");local Stack=require("src.ui.game3.stack");local Field=require("src.core.game3.field")
 local hook="editor.gen3.screens.update";local view={page=1,elapsed=0};local pending;local lastSession,lastMap
 local function bridge(t,k,key)
  t._editorScreenBridges=t._editorScreenBridges or {};if t._editorScreenBridges[k] then return end;t._editorScreenBridges[k]=true
  local old=t[k];t[k]=function(...) return RT.call(key,old,...) end
 end
 local function close()
  Stack.pop("editor_screens");local done=view.done;view.done=nil;view.rows=nil;view.cinematic=nil;if view.music then require("src.core.game3.audio").playSong(view.music);view.music=nil end;if done then done() end
 end
 local function open(rows,kind,done)
  view.rows=rows;view.kind=kind;view.page=1;view.elapsed=0;view.done=done
  if kind=="credits" and config.movie and M.movie then
   local session=Field.getSession() or {};view.cinematic=M.movie.new(config.movie,session.gender==1 or session.gender=="female")
   local A=require("src.core.game3.audio");view.cinematic.onCry=function(id) A.playCry(({charizard=6,venusaur=3,blastoise=9,pikachu=25})[id],0,0) end;view.music=A._currentSong and A._currentSong.id or 0;A.playSong(290)
  end
  Stack.push("editor_screens",view,{hideBelow=true})
 end
 local function advance()
  if not view.rows then return end
  if view.page>=#view.rows then close() else view.page=view.page+1;view.elapsed=0 end
 end
 function view.isOpen() return view.rows~=nil and Stack.has("editor_screens") end
 function view.draw()
  if not RT.wantsHook(hook) then close();return end
  if view.cinematic then M.movie.draw(view.cinematic,M.image) elseif view.rows then M.draw(view.rows[view.page],view.kind,config.art) end
 end
 function view.update(dt)
  if not RT.wantsHook(hook) then close();return end
  if not view.rows then return end
  if view.cinematic then M.movie.update(view.cinematic,dt);if view.cinematic.done then close() end;return end
  view.elapsed=view.elapsed+dt
  if view.elapsed>=(view.rows[view.page].seconds or 4) then advance() end
 end
 function view.handleInput(input)
  if not RT.wantsHook(hook) then close();return end
  if view.cinematic then
   local c=view.cinematic.payload.commands[view.cinematic.index]
   if c and c.op=="wait" and input:wasPressed("a") then close() end;return
  end
  if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then advance() end
 end
 bridge(Field,"update",hook)
 mod.hooks:wrap(hook,function(proceed,dt)
  local result=proceed(dt);local session=Field.getSession()
  if session~=lastSession then lastSession=session;lastMap=session and session.map;pending=nil end
  if session and session.map~=lastMap then
   lastMap=session.map;pending=nil
   for _,row in ipairs(config.areas or {}) do if row.map==lastMap and row.show~="off" then pending=row;break end end
  end
  if pending and session and not Stack.busy() then
   session.modData=session.modData or {};session.modData[mod.id]=session.modData[mod.id] or {}
   local state=session.modData[mod.id];state.areaPreviews=state.areaPreviews or {}
   if pending.show=="every" or not state.areaPreviews[pending.id] then
    state.areaPreviews[pending.id]=true;open({pending},"areas")
   end
   pending=nil
  end
  return result
 end)
 local H=require("src.ui.game3.hall_of_fame");local key="editor.gen3.screens.credits"
 bridge(H,"close",key)
 mod.hooks:wrap(key,function(proceed,...)
  if H.open and config.credits and #config.credits>0 then
   local done=H._onDone;H._onDone=function() open(config.credits,"credits",done) end
  end
  return proceed(...)
 end)
 return view
end
return M
