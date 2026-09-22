-- A modal desktop child owns a snapshot, never the project's files.
local M={}
local kinds={object="objects",sign="signs",trigger="coordEvents",warp="warps"}
function M.request(S,mapId,kind,index)
  if not S.project or not require("Generation").isGen3(S) then return false end
  if S._eventWindow then S._eventWindow.process.focus();return true end
  kind=kinds[kind] or kind
  if kind~="objects" and kind~="signs" and kind~="coordEvents" and kind~="warps" then return false end
  local owned=(S.project.maps or {})[mapId]
  local map=owned or require("Generation").dataMaps(S)[mapId]
  local patch=not owned and ((S.project.gen3 or {}).maps or {})[mapId]
  local rows=patch and (patch[kind] or kind=="signs" and patch.bgEvents) or map and map[kind]
  if not (rows and rows[index]) then return false end
  S._eventWindowRequest={mapId=mapId,kind=kind,index=index}
  if love and love.graphics and love.graphics.captureScreenshot then
    love.graphics.captureScreenshot(function(pixels)
      if M.busy(S) then S._eventWindowBackdrop=love.graphics.newImage(pixels) end
    end)
  end
  return true
end
function M.read(path)
  local f=io.open(path,"rb");if not f then return nil,"Window data is missing" end
  local bytes=f:read("*a");f:close()
  return require("Gen3Decode").decode(bytes,{allowArray=true,maxBytes=128*1024*1024,
    maxNodes=8000000,maxTableEntries=4000000,maxDepth=100,maxStringBytes=32*1024*1024})
end
function M.write(path,value)
  local encoded,bytes=pcall(require("ModWriter").encodeLua,value)
  if not encoded then return nil,bytes end
  bytes="return "..bytes.."\n"
  local tmp=path..".tmp";local f,err=io.open(tmp,"wb");if not f then return nil,err end
  local ok,problem=f:write(bytes);f:close();if not ok then os.remove(tmp);return nil,problem end
  local done,why=os.rename(tmp,path);if not done then os.remove(tmp) end
  return done,why
end
local function cleanup(path)
  for _,suffix in ipairs({"",".tmp",".result",".result.tmp"}) do os.remove(path..suffix) end
end
function M.start(S,launch)
  local target=S._eventWindowRequest;S._eventWindowRequest=nil
  if not target then return false end
  local path=os.tmpname()
  -- The bundled Windows Lua runtime can return a root-relative name (\s123.).
  if package.config:sub(1,1)=="\\" and not path:match("^%a:") then
    path=(os.getenv("TEMP") or os.getenv("TMP") or love.filesystem.getSaveDirectory()).."/"..path:match("[^/\\]+$")
  end
  os.remove(path)
  local payload={project=S.project,path=S.path,version=S.version,target=target}
  local ok,err=M.write(path,payload)
  if not ok then S.status="Could not prepare event window: "..tostring(err);return false end
  local exe=love.filesystem.getExecutablePath()
  local args={}
  if not love.filesystem.isFused() then args[#args+1]=love.filesystem.getSource() end
  args[#args+1]="--event-session";args[#args+1]=path
  local called,process,problem=pcall(launch or require("EventWindowProcess").start,exe,args)
  if not called or not process then
    cleanup(path);S._eventWindowBackdrop=nil;S.status=tostring(called and problem or process);return false
  end
  S._eventWindow={path=path,process=process,project=S.project,
    baseline=require("ModWriter").encodeLua(S.project)}
  require("Kit").blur();require("Kit").suppressMouseUntilUp()
  S.status="Editing event in a separate window. OK applies; Cancel discards."
  return true
end
function M.update(S,App)
  if S._eventWindowRequest then M.start(S) end
  local session=S._eventWindow;if not session then return false end
  if session.process.running() then return true end
  local result=M.read(session.path..".result")
  session.process.close();S._eventWindow=nil;S._eventWindowBackdrop=nil
  if type(result)=="table" and result.accepted==true and type(result.project)=="table" then
    local Writer=require("ModWriter")
    if S.project~=session.project or Writer.encodeLua(S.project)~=session.baseline then
      S.status="Project changed while the event window was open. Event edits kept at "..session.path..".result"
      os.remove(session.path);return false
    end
    if Writer.encodeLua(result.project)~=session.baseline then
      local History=require("History");History.beginFrame(S);App.beginEditBatch()
      S.project=require("State").ensureProjectFields(result.project)
      History.pruneLiveAfterProjectChange(S);App.markDirty();App.endEditBatch();History.endFrame(S)
    end
    S.status="Event changes applied. Save your mod to write them to disk."
  else S.status=result and "Event changes cancelled." or "Event window closed without applying changes." end
  cleanup(session.path)
  require("Kit").blur();require("Kit").suppressMouseUntilUp()
  return false
end
function M.busy(S) return S and (S._eventWindow or S._eventWindowRequest)~=nil end
function M.drawWaiting(S)
  local K=require("Kit");local Theme=require("Theme");local w,h=love.graphics.getDimensions();local s=K.layout(w,h)
  local mx,my=love.mouse.getPosition();K.beginFrame(mx,my,false,0);Theme.field(w,h)
  if S._eventWindowBackdrop then
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(S._eventWindowBackdrop,0,0,0,w/S._eventWindowBackdrop:getWidth(),h/S._eventWindowBackdrop:getHeight())
    love.graphics.setColor(0,0,0,.65);love.graphics.rectangle("fill",0,0,w,h)
  end
  local width=math.min(w-40*s,650*s);local x=(w-width)/2;local y=h/2-110*s
  K.card(x,y,width,220*s)
  K.text("title","EVENT EDITOR IS OPEN",x+20*s,y+22*s,Theme.PAL.heading)
  K.text("small","Finish in the event window to return to your map.",x+20*s,y+76*s,Theme.PAL.text)
  K.text("small","OK keeps changes. Cancel discards them.",x+20*s,y+106*s,Theme.PAL.text)
  K.text("small","Click here to bring the event window forward.",x+20*s,y+154*s,Theme.PAL.text)
  K.endFrame()
end
return M
