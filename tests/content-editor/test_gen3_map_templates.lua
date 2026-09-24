return function(data,root,output,game)
  local State=require("State");local S=State.new();S.data=data;S.version=game
  S.project=State.blankProject("map_templates_test");S.project.game=game;S.mapId="FR_PALLET_TOWN"
  require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  require("src.core.game3.rom_text").overrides=data.text
  local Templates=require("Gen3MapTemplates");local Events=require("Gen3MapEvents")
  local Writer=require("ModWriter");local dirty=0;local App={markDirty=function() dirty=dirty+1 end}
  local original=Writer.encodeLua(data.maps[S.mapId]);local d=Templates.draft(S)
  local function place(kind,x)
    d.kind=kind;assert(Events.place(S,"object",x,5,App))
    return S.project.maps[S.mapId].objects[S.mapObjectIndex]
  end
  d.text="Welcome, {PLAYER}!";local npc=place("dialog",5)
  assert(npc.x==5 and npc.y==5 and npc.flag==0)
  local talk=npc.scriptKey
  d.item="POTION";d.quantity="2";local pickup=place("pickup",6)
  assert(pickup.graphicsId==92 and pickup.flag>=0x900 and pickup.localId~=npc.localId)
  local second=place("pickup",7);assert(second.flag~=pickup.flag and second.scriptKey~=pickup.scriptKey)
  local reward=place("item",8);assert(dirty==4)
  assert(Writer.encodeLua(data.maps[S.mapId])==original,"Placement changed imported data")
  local before=Writer.encodeLua(S.project);d.quantity="0"
  assert(Events.place(S,"object",9,5,App));assert(dirty==4 and Writer.encodeLua(S.project)==before,"Invalid placement left partial content")
  d.quantity="1";assert(Events.place(S,"object",-1,5,App));assert(Writer.encodeLua(S.project)==before)
  local catalog=require("Gen3").catalog(data,"map_scripts")
  local scripts=setmetatable(S.project.gen3.map_scripts,{__index=catalog})
  local Flags=require("src.core.game3.scripting.flags");local Vm=require("src.core.game3.scripting.vm")
  local messages=0;local received=0;local removed=0
  local function run(key,full,store)
    local a=require("src.core.game3.scripting.adapters").stub({onMessage=function() messages=messages+1 end,
      openMessageStay=function(_,done) messages=messages+1;if done then done() end end,
      waitFanfare=function(done) if done then done() end end,askYesNo=function(cb) cb(true) end})
    a.modifyItem=function(op,item,qty) if full then return false end;received=received+qty;return true end
    a.checkItemSpace=function() return not full end
    a.removeObject=function(id) assert(id==pickup.localId);removed=removed+1 end
    local vm=Vm.new({store=store or Flags.newStore(),scripts=scripts,text=setmetatable(S.project.text,{__index=data.text}),adapters=a})
    assert(vm:startTalk(key,pickup.localId,1))
    for _=1,1000 do vm:tick();if not vm:isRunning() then break end end
    assert(not vm:isRunning(),"Placed event did not finish: "..tostring(vm.ctx and vm.ctx.pc and vm.ctx.pc.listKey))
  end
  run(talk);assert(messages>0)
  run(pickup.scriptKey,true);assert(received==0 and removed==0,"Full Bag consumed the pickup")
  run(pickup.scriptKey,false);assert(received==2 and removed==1,"Pickup did not use the native standard item script")
  local rewardStore=Flags.newStore()
  run(reward.scriptKey,true,rewardStore);assert(received==2)
  run(reward.scriptKey,false,rewardStore);assert(received==4)
  rewardStore=Flags.loadInto(Flags.newStore(),Flags.serialize(rewardStore))
  run(reward.scriptKey,false,rewardStore);assert(received==4,"Reward repeated after saving flags")
  -- Exercise the same quick editor callbacks used by the map sidebar.
  local K=require("Kit");local Picker=require("ItemPicker");local oldField=Picker.field
  local expected=require("src.mods.Merge").deepCopy(S.project.gen3.map_scripts[pickup.scriptKey])
  expected[1][2]=data.items.ANTIDOTE.index
  Picker.field=function(_,opts) opts.onPick("ANTIDOTE") end
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Gen3RpgEventEditor").drawQuick(S,pickup,20,20,340,App)
  K.endFrame();Picker.field=oldField
  assert(Writer.encodeLua(S.project.gen3.map_scripts[pickup.scriptKey])==Writer.encodeLua(expected),"Quick edit changed unrelated commands")
  assert(require("Gen3EventStory").itemPickup(S.project.gen3.map_scripts[second.scriptKey]).item==data.items.POTION.index,"Quick edit changed another pickup")
  local IO=require("ModIO");IO.ensureDirectory(output.."/project");assert(IO.save(output.."/project",S.project))
  local reopened=assert(IO.load(output.."/project"));assert(reopened.gen3.map_scripts[talk])
  assert(reopened.game==game,"Save changed the target edition")
  assert(reopened.maps[S.mapId].objects[S.mapObjectIndex].scriptKey)
  for _,width in ipairs({340,500}) do
    local canvas=love.graphics.newCanvas(width+40,900)
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
    K.layout(1360,860);K.beginFrame(0,0,false,0)
    S.mapObjectIndex=#S.project.maps[S.mapId].objects-1;S.mapSection="objects"
    local snapshot=Writer.encodeLua(S.project)
    Templates.drawPlacement(S,20,20,width)
    Events.draw(S,20,90,width,780,{markDirty=function() error("Browsing edited content") end})
    K.endFrame();love.graphics.setCanvas()
    assert(Writer.encodeLua(S.project)==snapshot)
    local f=assert(io.open(output.."/sidebar-"..width..".png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
  end
  S.builderTool="object";S.builderPane="details";S.builderMapId=S.mapId;S.mapEditMode="events";S._builderDoFit=true
  local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("MapsWorkspace").draw(S,20,20,1320,820,App)
  K.endFrame();love.graphics.setCanvas()
  local f=assert(io.open(output.."/workspace.png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
end
