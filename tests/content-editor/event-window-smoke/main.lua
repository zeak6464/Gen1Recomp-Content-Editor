local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local child,S,App,Window,started,scenario,baseline,childMode,frames,undoCount,seenWindow
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/event-window-smoke/result.txt","wb"));f:write(message);f:close()
end
love.errorhandler=function(err)
  local message=debug.traceback(tostring(err))
  if childMode then
    local f=assert(io.open(root.."/tests/content-editor/event-window-smoke/child-error.txt","wb"));f:write(message);f:close()
  else report(message) end
  return function() return 1 end
end
local function capture()
  local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);child.draw();love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/event-window-smoke/"..childMode..".png","wb"))
  f:write(canvas:newImageData():encode("png"):getString());f:close()
end
function love.load(args)
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  Window=require("Gen3EventWindow")
  if args[1]=="--event-session" then
    childMode=args[4];frames=0
    child=require("Gen3EventWindowChild").load(args[2]);S=require("App").getState()
    return
  end
  App=require("App");App.load(nil,{version="firered",eventWindow=true});S=App.getState()
  assert(S.data.maps.FR_PALLET_TOWN,"Real FireRed cache not loaded")
  S.project=require("State").ensureProjectFields(require("State").blankProject("window_test"));S.project.game="firered";S.tab="maps"
  require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  local id=assert(require("Gen3EventBuilder").create(S,{kind="dialog",map="FR_PALLET_TOWN",npc="1",text="Unsaved parent dialogue"}))
  local map=S.project.maps.FR_PALLET_TOWN
  map.signs={{x=4,y=4,elevation=3,kind=0,scriptKey=id}}
  map.coordEvents={{x=5,y=4,elevation=3,var=16384,value=0,scriptKey=id}}
  S.mapId="FR_PALLET_TOWN"
  require("History").clear(S);baseline=require("ModWriter").encodeLua(S.project)
  -- Exact hit testing includes native step-on triggers, and selecting them records the right index.
  local Maps=require("Maps")
  for _,test in ipairs({{"sign",4,4},{"trigger",5,4}}) do
    local kind,index=Maps.pickEventAt(S,test[2],test[3]);assert(kind==test[1] and index==1)
    Maps.selectEvent(S,kind,index)
  end
  assert(S.g3CoordIndex==1)
  local K=require("Kit");local Builder=require("MapBuilder")
  S.builderMapId=S.mapId;S.builderPane="details";S.mapEditMode="events";S.builderShowScript=true
  local canvas=love.graphics.newCanvas(1360,860)
  for _,case in ipairs({{"object","objects",false},{"sign","signs",false},{"trigger","coordEvents",false},{"object","objects",true}}) do
    S.builderTool=case[1];S._builderEvent={move=true,kind=case[1],index=1,moved=case[3],lastX=3,lastY=10}
    love.graphics.setCanvas({canvas,stencil=true});K.layout(1360,860);K.beginFrame(0,0,false,0)
    Builder.draw(S,20,45,1320,790,App);K.endFrame();love.graphics.setCanvas()
    if case[3] then assert(not S._eventWindowRequest,"Dragging opened the event window")
    else assert(S._eventWindowRequest and S._eventWindowRequest.kind==case[2],"Click release did not open the selected event") end
    S._eventWindowRequest=nil
  end
  require("History").clear(S);baseline=require("ModWriter").encodeLua(S.project)
  scenario=1;started=love.timer.getTime();report("RUNNING")
end
local tests={{"object","accept"},{"sign","cancel"},{"trigger","accept-trigger"},{"object","crash"},{"sign","noop"},{"sign","close"}}
function love.update(dt)
  if child then
    child.update(dt);frames=frames+1
    if frames==8 then
      capture()
      local target=S._eventWindowTarget
      assert(target.mapId=="FR_PALLET_TOWN" and target.index==1)
      if childMode=="crash" then os.exit(0) end
      if childMode=="accept" then
        local script=S.project.maps[target.mapId].objects[1].scriptKey
        assert(require("Gen3EventActions").text(S,S.project.gen3.map_scripts[script][3])=="Unsaved parent dialogue")
        require("Gen3EventActions").setText(S,S.project.gen3.map_scripts[script][3],"Saved through separate window")
        assert(child.accept())
      elseif childMode=="accept-trigger" then
        S.project.maps[target.mapId].coordEvents[1].value=7;assert(child.accept())
      elseif childMode=="noop" then assert(child.accept())
      elseif childMode=="close" then
        S.project.maps[target.mapId].signs[1].x=99;assert(child.quit()==false)
      else
        S.project.maps[target.mapId].signs[1].x=99;assert(child.cancel())
      end
    end
    return
  end
  assert(love.timer.getTime()-started<90,"Event window process timed out")
  if S._eventWindow then
    if not seenWindow then seenWindow=S._eventWindow.process.focus() end
    if Window.update(S,App) then return end
    if require("ffi").os=="Windows" then assert(seenWindow,"Child did not create a visible desktop window") end
    local Writer=require("ModWriter")
    if scenario==1 then
      local script=S.project.maps.FR_PALLET_TOWN.objects[1].scriptKey
      assert(require("Gen3EventActions").text(S,S.project.gen3.map_scripts[script][3])=="Saved through separate window",S.status)
      assert(#S.undoStack==1);assert(require("History").undo(S))
      assert(Writer.encodeLua(S.project)==baseline,"OK must undo as one operation")
      assert(require("History").redo(S))
    elseif scenario==2 then assert(S.project.maps.FR_PALLET_TOWN.signs[1].x==4,"Cancel changed the parent")
    elseif scenario==3 then assert(S.project.maps.FR_PALLET_TOWN.coordEvents[1].value==7)
    elseif scenario==4 then assert(S.project.maps.FR_PALLET_TOWN.coordEvents[1].value==7)
    elseif scenario==5 then assert(#S.undoStack==undoCount,"No-op OK created an undo entry")
    elseif scenario==6 then assert(S.project.maps.FR_PALLET_TOWN.signs[1].x==4) end
    scenario=scenario+1
  end
  local test=tests[scenario]
  if not test then report("PASS: actual child windows; NPC/sign/trigger selection; unsaved data; OK, Cancel, crash recovery; single-step undo/redo");love.event.quit();return end
  assert(Window.request(S,"FR_PALLET_TOWN",test[1],1))
  undoCount=#S.undoStack
  seenWindow=false
  assert(Window.start(S,function(exe,args)
    args[#args+1]="--test-mode";args[#args+1]=test[2]
    return require("EventWindowProcess").start(exe,args)
  end),S.status)
end
function love.draw() if child then child.draw() end end
function love.quit() if child then return child.quit() end end
