local root = assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\", "/")
local runtime = assert(os.getenv("POKEPORT_RECOMP")):gsub("\\", "/")
package.path = root .. "/tools/content-editor/?.lua;" .. root .. "/tools/content-editor/panels/?.lua;"
  .. root .. "/tools/save-editor/?.lua;" .. runtime .. "/?.lua;" .. package.path
local ffi = require("ffi")
ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib = ffi.load(root .. "/love/love.dll")
assert(lib.PHYSFS_mount(root, "", 1) ~= 0)
assert(lib.PHYSFS_mount(runtime, "", 1) ~= 0)
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/result.txt","wb")); f:write(message); f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err))); return function() return 1 end end
function love.load()
  local data, project = dofile(root .. "/tests/content-editor/test_gen3.lua")
  local originalWrite = love.filesystem.write
  local originalRead = love.filesystem.read
  love.filesystem.write = function() return true end
  love.filesystem.read = function(path, ...)
    if path == "content_editor_data.json" then return nil end
    return originalRead(path, ...)
  end
  local EditorApp = require("App")
  EditorApp.load(nil,{version="firered"})
  assert(EditorApp.getState().version == "firered")
  assert(EditorApp.getState().data.maps.FR_PALLET_TOWN,"Startup did not find the linked runtime's real FireRed cache")
  love.filesystem.write = originalWrite
  love.filesystem.read = originalRead
  local state = EditorApp.getState()
  state.project = require("State").ensureProjectFields(project)
  state.data = data
  state.path = root .. "/tests/content-editor/gen3-smoke/saved-project"
  assert(require("ModIO").ensureDirectory(state.path))
  assert(EditorApp.save(), state.status)
  local Kit=require("Kit")
  local Panel=require("Gen3Records")
  local S={data=data,project=project,version="firered"}
  local App={markDirty=function() S.dirty=true end}
  local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true})
  local count=0
  for tab,name in pairs(require("Gen3").tabs) do
    love.graphics.clear(0.06,0.07,0.1,1)
    S.tab=tab
    S.gen3Id=next(require("Gen3").catalog(data,name))
    Kit.layout(1360,860); Kit.beginFrame(0,0,false,0)
    Panel.draw(S,20,80,1320,740,App)
    Kit.endFrame()
    local button = Kit.button
    Kit.button = function(x,y,w,h,label,opts)
      if label == "Apply record" then return true end
      return button(x,y,w,h,label,opts)
    end
    Kit.beginFrame(0,0,false,0)
    Panel.draw(S,20,80,1320,740,App)
    Kit.endFrame()
    Kit.button = button
    assert(not S._g3Error, S._g3Error)
    count=count+1
  end
  love.graphics.setCanvas()
  local real,loader,read=dofile(root.."/tests/content-editor/test_gen3_real.lua")
  local realCache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
  assert(lib.PHYSFS_mount(realCache,"firered",1)~=0)
  real._gen3List=function(path)
    local result={}
    for _,name in ipairs(love.filesystem.getDirectoryItems("firered/"..path)) do
      result[#result+1]={name=name,type=love.filesystem.getInfo("firered/"..path.."/"..name).type}
    end
    return result
  end
  S={data=real,project=require("State").blankProject("native_smoke"),version="firered",path=root.."/tests/content-editor/gen3-smoke/saved-project",g3MapId="FR_PALLET_TOWN"}
  S.project.game="firered"
  require("Gen3Workspace").prepare(S)
  S.mapId="FR_PALLET_TOWN"
  local nativeWidth=real.maps[S.mapId].width
  local source=assert(require("Gen3Workspace").convert(S,S.mapId))
  assert(source.cellWidth==nativeWidth)
  S.builderMapId=S.mapId;S.builderSourceId=require("LayeredMap").runtimeSourceId(source.baseTileset)
  assert(require("LayeredMap").compileProject(S))
  assert(require("Gen3").emit(S.project,require("ModWriter").encodeLua))
  App.beginEditBatch=function() end;App.endEditBatch=function() end
  App.save=function() end
  love.graphics.setCanvas({canvas,stencil=true})
  for _,name in ipairs({"MapsWorkspace","Gen3Sprites","Gen3StartersPanel","Gen3Animations","Gen3Assets","Audio","Pokemon","Items","Moves","Trainers","Encounters","Dialog","Shops","Types","Gen3Events","Gen3UiWorkspace","Player","Breeding","Rules","AiClasses","MoveEffects","Trades","Gfx"}) do
    love.graphics.clear(0.06,0.07,0.1,1)
    Kit.layout(1360,860);Kit.beginFrame(0,0,false,0)
    require(name).draw(S,20,80,1320,740,App)
    Kit.endFrame();count=count+1
    love.graphics.setCanvas()
    local png=canvas:newImageData():encode("png")
    local file=assert(io.open(root.."/tests/content-editor/gen3-smoke/"..name..".png","wb"));file:write(png:getString());file:close()
    love.graphics.setCanvas({canvas,stencil=true})
  end
  love.graphics.setCanvas()
  S.mapEditMode="events";S.mapSection="objects"
  love.graphics.setCanvas({canvas,stencil=true})
  Kit.beginFrame(0,0,false,0)
  require("MapsWorkspace").draw(S,20,80,1320,740,App)
  Kit.endFrame()
  love.graphics.setCanvas()
  local png=canvas:newImageData():encode("png")
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/panels.png","wb")); f:write(png:getString()); f:close()
  local nativePath=root.."/tests/content-editor/gen3-smoke/native-project"
  S.mapId="FR_ROUTE10";S.builderMapId=S.mapId;S.mapEditMode="map"
  S._vanillaMapBackup={FR_ROUTE10=real.maps.FR_ROUTE10}
  local Maps=require("Maps")
  assert(Maps.resolveMap(S,S.mapId).width*2==real.maps.FR_ROUTE10.width)
  local Preview=require("Preview")
  local shader=Preview.pushPaletteShader
  Preview.pushPaletteShader=function() error("FireRed preview attempted a four-color palette shader") end
  for _,mode in ipairs({"world","editor","editable"}) do
    if mode=="editable" then
      local src=assert(require("Gen3Workspace").convert(S,S.mapId))
      local native=assert(require("Gen3Map").layout(real,S.mapId))
      for cy=-2,-1 do for cx=-2,1 do
        assert(require("LayeredMap").borderCellTile(S.project.maps[S.mapId],cx,cy)==native:midAt(cx,cy),"Incorrect native border pattern")
      end end
      S.builderSourceId=require("LayeredMap").runtimeSourceId(src.baseTileset)
    end
    S.mapViewMode=mode=="world" and "world" or "editor"
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0.06,0.07,0.1,1)
    Kit.beginFrame(0,0,false,0);require("MapsWorkspace").draw(S,20,80,1320,740,App);Kit.endFrame()
    love.graphics.setCanvas()
    local file=assert(io.open(root.."/tests/content-editor/gen3-smoke/route10-"..mode..".png","wb"))
    file:write(canvas:newImageData():encode("png"):getString());file:close()
  end
  Preview.pushPaletteShader=shader
  require("ModIO").ensureDirectory(nativePath)
  assert(lib.PHYSFS_mount(nativePath,"mods/native_integration",1)~=0)
  dofile(root.."/tests/content-editor/test_gen3_workspace.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_content.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_anim_preview.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_movement.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_minigames.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_accessible.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_breeding_behaviors.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_oak_rotation.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_gift_presets.lua")(real,root)
  dofile(root.."/tests/content-editor/test_firered_cart.lua")(root)
  dofile(root.."/tests/content-editor/test_gen3_forms.lua")(real,root,lib.PHYSFS_mount)
  dofile(root.."/tests/content-editor/test_gen3_roamers.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_screens.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_fame.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_intro_assets.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_town_maps.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_fly.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_quests.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_event_builder.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_reported_ui.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_project_audit.lua")(real,root)
  dofile(root.."/tests/content-editor/test_gen3_native.lua")
  report("PASS: rendered "..count.." Gen 3 panels; native exports and imported audio playback using LÖVE 11.5")
  love.event.quit()
end

