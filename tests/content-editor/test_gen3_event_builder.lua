return function(data,root)
  local S=require("State").new();S.data=data;S.version="firered";S.project=require("State").blankProject("event_builder_test");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  local B=require("Gen3EventBuilder")
  local d={kind="dialog",map="FR_ROUTE10",npc="1",text="Welcome, {PLAYER}!"}
  local key=assert(B.create(S,d))
  assert(S.project.maps[d.map].objects[1].scriptKey==key)
  local before=require("ModWriter").encodeLua(S.project)
  local bad=require("src.mods.Merge").deepCopy(d);bad.npc="99999"
  assert(not B.create(S,bad));assert(require("ModWriter").encodeLua(S.project)==before)
  local messages={};local Flags=require("src.core.game3.scripting.flags")
  local a=require("src.core.game3.scripting.adapters").stub({onMessage=function(t) messages[#messages+1]=t end,openMessageStay=function(t) messages[#messages+1]=t end})
  local vm=require("src.core.game3.scripting.vm").new({store=Flags.newStore(),scripts=S.project.gen3.map_scripts,text=S.project.text,adapters=a})
  assert(vm:startTalk(key,1,1))
  for _=1,100 do vm:tick();if not vm:isRunning() then break end end
  assert(not vm:isRunning());assert(#messages>0)
  d.kind="item";d.item="POTION";d.quantity="2";d.success="Here you go!";d.done="Enjoy!"
  local reward=assert(B.create(S,d));assert(reward~=key and S.project.maps[d.map].objects[1].scriptKey==reward)
  local IO=require("ModIO");local path=root.."/tests/content-editor/gen3-smoke/event-builder-project"
  IO.ensureDirectory(path);assert(IO.save(path,S.project));local p=assert(IO.load(path));assert(p.maps[d.map].objects[1].scriptKey==reward)
  S.g3EventMode="builder";S._eventBuilderProject=S.project;S.eventBuilder=d
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Gen3Events").draw(S,20,80,1320,740,{markDirty=function() error("Browsing changed the mod") end});K.endFrame();love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/event-builder.png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
end

