local M={}
function M.attach(S,path,payload)
  payload=payload or assert(require("Gen3EventWindow").read(path))
  S.project=payload.project;S.path=payload.path;S.version=payload.version
  S.g3EventMap=payload.target.mapId;S.g3MapEventId=payload.target.kind.."/"..payload.target.index
  S._eventWindowTarget=payload.target;S.g3InlineEventSettings=false;S.g3EventMode="map"
  S.status="Changes stay in this window until you press OK."
  require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  if ((S.project.gen3 or {}).maps or {})[payload.target.mapId] then
    assert(require("Gen3Workspace").convert(S,payload.target.mapId))
  end
  local K=require("Kit");local History=require("History");local Theme=require("Theme")
  local Choice=require("ChoicePicker");local Items=require("ItemPicker")
  History.clear(S);History.resetBaseline(S)
  local window={};local clicked,wheel=false,0;local done=false
  local App={markDirty=function() History.noteDirty(S);S.dirty=true end}
  local targetLabel=({objects="Character",signs="Sign",coordEvents="Trigger",warps="Exit"})[payload.target.kind] or "Event"
  function window.accept()
    if done then return true end
    -- Finish an inline text draft as part of OK, so no separate Apply is required.
    local draft=S._g3MessageDraft
    local source=((S.project.gen3 or {}).map_scripts or {})[S._g3ScriptId]
      or require("Gen3").catalog(S.data,"map_scripts")[S._g3ScriptId]
    if draft and S._g3ScriptDraft and source==S._g3ScriptSource then
      local present=false;for _,row in ipairs(S._g3ScriptDraft) do if row==draft.step then present=true;break end end
      local value=table.concat(draft.lines,"\n")
      if present and value~=draft.source then
        require("Gen3EventActions").setText(S,draft.step,value)
        S.project.gen3.map_scripts[S._g3ScriptId]=require("src.mods.Merge").deepCopy(S._g3ScriptDraft)
      end
    end
    local ok,err=require("Gen3EventWindow").write(path..".result",{accepted=true,project=S.project})
    if not ok then S.status="Could not apply changes: "..tostring(err);return false end
    done=true;love.event.quit();return true
  end
  function window.cancel()
    if done then return true end
    local ok,err=require("Gen3EventWindow").write(path..".result",{accepted=false})
    if not ok then S.status="Could not close event window: "..tostring(err);return false end
    done=true;love.event.quit();return true
  end
  function window.update(dt) if K.scrollUpdate then K.scrollUpdate(dt) end end
  function window.draw()
    local w,h=love.graphics.getDimensions();local s=K.layout(w,h);local mx,my=love.mouse.getPosition()
    K.beginFrame(mx,my,clicked,wheel);clicked=false;wheel=0;Theme.field(w,h)
    K.text("title","EDIT EVENT",20*s,15*s,Theme.PAL.heading)
    local target=payload.target
    K.text("small",require("Gen3Names").map(target.mapId).." / "..targetLabel.." "..target.index,20*s,48*s,Theme.PAL.text)
    local modal=Choice.isOpen(S) or Items.isOpen(S)
    K.blockClicks=modal
    if K.button(w-230*s,18*s,95*s,32*s,"OK",{kind="good"}) then window.accept() end
    if K.button(w-125*s,18*s,105*s,32*s,"Cancel",{}) then window.cancel() end
    History.beginFrame(S)
    require("Gen3EventEditor").draw(S,20*s,90*s,w-40*s,h-140*s,App)
    History.endFrame(S)
    K.text("small",K.ellipsize("small",S.status or "",w-40*s),20*s,h-30*s,Theme.PAL.text)
    K.blockClicks=false
    if Choice.isOpen(S) then Choice.draw(S,0,0,w,h) end
    if Items.isOpen(S) then Items.draw(S,0,0,w,h) end
    K.endFrame()
  end
  function window.keypressed(key)
    if Choice.isOpen(S) and Choice.keypressed(S,key) then return end
    if Items.isOpen(S) and Items.keypressed(S,key) then return end
    local ctrl=love.keyboard.isDown("lctrl","rctrl","lgui","rgui")
    if ctrl and key=="s" then window.accept();return end
    if ctrl and (key=="z" or key=="y") then
      if key=="z" then History.undo(S) else History.redo(S) end
      return
    end
    if K.keypressed(key) then return end
    if key=="escape" then window.cancel() end
  end
  function window.textinput(text) K.textinput(text) end
  function window.mousepressed(_,_,button) if button==1 then clicked=true end end
  function window.mousereleased() end
  function window.wheelmoved(_,y) wheel=wheel+y end
  function window.filedropped() end
  function window.quit() if not done then return not window.cancel() end;return false end
  love.window.setMode(1360,860,{resizable=true,minwidth=1000,minheight=700,vsync=1})
  love.window.setTitle("Edit Event - "..require("Gen3Names").map(payload.target.mapId).." - "..targetLabel.." "..payload.target.index)
  return window
end
function M.load(path)
  local payload=assert(require("Gen3EventWindow").read(path))
  assert(payload.version=="firered","Separate event windows require a FireRed project")
  local App=require("App");App.load(nil,{version=payload.version,eventWindow=true})
  return M.attach(App.getState(),path,payload)
end
return M
