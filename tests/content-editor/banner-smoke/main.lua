local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cacheRoot=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
local function report(msg) local f=assert(io.open(root.."/tests/content-editor/banner-smoke/result.txt","wb"));f:write(msg);f:close() end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local IO=require("ModIO")
  local function read(path) return IO.readText(cacheRoot.."/"..path) end
  require("src.import.CacheFs").read=function(path) return read((path:gsub("^firered/",""))) end
  assert(lib.PHYSFS_mount(cacheRoot,"firered",1)~=0)
  require("src.core.GameVersion").set("firered")
  local dir=root.."/tests/content-editor/banner-smoke/output";assert(IO.ensureDirectory(dir))
  local S={data={_gen3Read=read,maps={FR_CINNABAR_ISLAND={},FR_ROUTE_49={}}},project={game="firered",maps={}},path=dir,version="firered"}
  local B=require("Gen3Banners")
  local image=assert(B.template(S));assert(image:getWidth()==128 and image:getHeight()==24)
  assert(IO.writeText(dir.."/template.png",image:encode("png"):getString()))
  image:mapPixel(function() return .2,.6,.8,1 end)
  assert(IO.writeText(dir.."/custom.png",image:encode("png"):getString()))
  local art=assert(B.import(S,"FR_CINNABAR_ISLAND",dir.."/custom.png"))
  local second=assert(B.import(S,"FR_CINNABAR_ISLAND",dir.."/custom.png"));assert(art~=second)
  S.project.gen3Banners.FR_CINNABAR_ISLAND.text="CUSTOM ISLAND"
  S.project.gen3Banners.FR_ROUTE_49={text="SOUTH ROUTE",enabled=true}
  S.project.gen3Banners.FR_DISABLED={enabled=false}
  assert(B.enabled(S,"FR_ROUTE_49") and not B.enabled(S,"FR_DISABLED"))
  S.data.maps.FR_CINNABAR_ISLAND.showMapName=1
  assert(B.enabled(S,"FR_CINNABAR_ISLAND"))
  assert(not B.enabled(S,"FR_NEW_MAP"))
  local W=require("ModWriter")
  local p=assert(loadstring(W.serializeProject(S.project)))();assert(p.gen3Banners.FR_CINNABAR_ISLAND.image==second)
  assert(loadstring(require("Gen3").emit(p,W.encodeLua)))
  local hooks={}
  package.loaded["src.mods.Runtime"]={call=function(name,base,...) if hooks[name] then return hooks[name](base,...) end;return base(...) end}
  local ready
  local mod={events={on=function(_,event,callback) assert(event=="game.ready");ready=callback end},hooks={wrap=function(_,key,fn) hooks[key]=fn end},assets={image=function(_,rel)
    return love.graphics.newImage(love.filesystem.newFileData(assert(IO.readText(dir.."/"..rel)),"banner.png")) end}}
  require("Gen3BannersRuntime").install(mod,p.gen3Banners)
  local runtimeMaps={FR_ROUTE_49={id="FR_ROUTE_49"},FR_DISABLED={id="FR_DISABLED",showMapName=1,show_map_name=1},FR_CINNABAR_ISLAND={id="FR_CINNABAR_ISLAND",showMapName=1}}
  ready({game={data={maps=runtimeMaps}}})
  assert(runtimeMaps.FR_ROUTE_49.showMapName==1 and runtimeMaps.FR_ROUTE_49.show_map_name==1,"New map banner was not enabled")
  assert(runtimeMaps.FR_DISABLED.showMapName==0 and runtimeMaps.FR_DISABLED.show_map_name==0,"Banner was not disabled")
  assert(runtimeMaps.FR_CINNABAR_ISLAND.showMapName==1,"Unchanged map setting was overwritten")
  local Popup=require("src.ui.game3.map_name_popup")
  local island={id="FR_CINNABAR_ISLAND",showMapName=1}
  Popup.dismiss();assert(Popup.show(island));Popup.update(12/60)
  assert(Popup._name=="CUSTOM ISLAND" and Popup._tPos==24)
  local canvas=love.graphics.newCanvas(128,24)
  love.graphics.setCanvas(canvas);love.graphics.clear();Popup.draw();love.graphics.setCanvas()
  local red,green=canvas:newImageData():getPixel(0,0)
  assert(math.abs(red-.2)<.01 and math.abs(green-.6)<.01,"Custom frame was not drawn")
  assert(Popup.show(runtimeMaps.FR_ROUTE_49));assert(Popup._pendingName=="SOUTH ROUTE" and Popup._name=="CUSTOM ISLAND")
  Popup.update(24/60);assert(Popup._name=="SOUTH ROUTE")
  love.graphics.setCanvas(canvas);love.graphics.clear();Popup.draw();love.graphics.setCanvas()
  local nativeRed=canvas:newImageData():getPixel(0,0);assert(math.abs(nativeRed-red)>.01,"Art leaked onto an unedited frame")
  Popup.dismiss();assert(not Popup.show({id=island.id,showMapName=0}))
  assert(not Popup.show(runtimeMaps.FR_DISABLED))
  for key in pairs(hooks) do hooks[key]=nil end
  Popup.dismiss();Popup.show(island);assert(Popup._name~="CUSTOM ISLAND");Popup.dismiss()
  local K=require("Kit")
  local ui=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({ui,stencil=true});love.graphics.clear(.06,.07,.1,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  S.g3UiMode="banners";S.g3BannerMap=island.id
  require("Gen3UiWorkspace").draw(S,20,50,1320,780,{markDirty=function() end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(dir.."/panel.png",ui:newImageData():encode("png"):getString()))
  report("PASS: banner import, unique files, project roundtrip/export, custom text/art, pending transitions, native artwork isolation, suppression, mod removal, panel rendering")
  love.event.quit()
end
