return function(data,root)
  local Q=require("Gen3Quests");local S=require("State").new()
  S.data=data;S.version="firered";S.project=require("State").blankProject("quest_test");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  local id=assert(Q.new(S));local q=S.project.gen3Quests[id]
  q.requirement="item";q.requiredItem="ANTIDOTE";q.quantity=2
  local key=assert(Q.build(S,id))
  local Flags=require("src.core.game3.scripting.flags")
  local Vm=require("src.core.game3.scripting.vm")
  local store=Flags.newStore();local received=0
  local function run(opts)
    opts=opts or {};local messages={}
    local a=require("src.core.game3.scripting.adapters").stub({onMessage=function(text) messages[#messages+1]=text end,
      openMessageStay=function(text) messages[#messages+1]=text end,
      askYesNo=function(cb) cb(opts.yes~=false) end})
    a.checkItem=function(item,qty) assert(item==data.items.ANTIDOTE.index and qty==1);return opts.hasItem~=false end
    a.modifyItem=function(op,item,qty)
      assert(op=="additem" and item==data.items.POTION.index and qty==2)
      if opts.full then return false end
      received=received+qty;return true
    end
    local vm=Vm.new({store=store,scripts=S.project.gen3.map_scripts,text=S.project.text,adapters=a})
    assert(vm:startTalk(key,1,1))
    for _=1,100 do vm:tick();if not vm:isRunning() then break end end
    assert(not vm:isRunning(),"Quest did not release the script VM")
    assert(next(a.frozen)==nil,"Quest left an NPC frozen")
    return (table.concat(messages," "):gsub("%s+"," "))
  end
  assert(run({hasItem=false}):find(q.missing,1,true));assert(received==0 and not Flags.getFlag(store,nil,q.flag))
  run({yes=false});assert(received==0 and not Flags.getFlag(store,nil,q.flag))
  assert(run({full=true}):find(q.full,1,true));assert(received==0 and not Flags.getFlag(store,nil,q.flag))
  assert(run():find(q.success,1,true));assert(received==2 and Flags.getFlag(store,nil,q.flag))
  store=Flags.loadInto(Flags.newStore(),Flags.serialize(store))
  assert(run():find(q.done,1,true));assert(received==2,"Completed quest awarded twice after save reload")
  q.requirement="trainer";q.trainer=5;assert(Q.build(S,id))
  store=Flags.newStore();run();assert(received==2)
  Flags.setFlag(store,nil,0x505,true);run();assert(received==4)
  S.project.gen3.map_scripts[key][1]={op="nop"}
  local built,err,conflict=Q.build(S,id);assert(not built and conflict,err)
  assert(S.project.gen3.map_scripts[key][1].op=="nop")
  assert(Q.build(S,id,true))
  S.project.text[key.."_Text_offer"]="Manual dialogue"
  assert(not Q.build(S,id),"Rebuild silently overwrote manual dialogue")
  assert(Q.build(S,id,true))
  local old=q.flag;q.flag=0x820;assert(not Q.build(S,id));q.flag=old
  local second=assert(Q.new(S));assert(S.project.gen3Quests[second].flag~=q.flag)
  local decoded=assert(require("Gen3Decode").decode("return "..require("ModWriter").encodeLua(S.project),{allowArray=true}))
  assert(decoded.gen3Quests[id]._scripts[key] and decoded.gen3.map_scripts[key])
  local emitted=require("Gen3").emit(decoded,require("ModWriter").encodeLua)
  local exported={}
  local content={}
  for _,name in ipairs(require("Gen3").registries) do
    exported[name]={}
    content[name]={register=function(_,k,v) exported[name][k]=v end,override=function(_,k,v) exported[name][k]=v end}
  end
  assert(loadstring(emitted))()({generation=3,content=content})
  assert(exported.map_scripts[key][1].op=="lock" and type(exported.text[key.."_Text_offer"])=="table")
  S.project.maps.EDITOR_QUEST_MAP={objects={{scriptKey=key}}}
  local pins=require("Gen3Dialog").pins(S,"EDITOR_QUEST_MAP")
  assert(#pins==5,"Map dialogue omitted generated quest branches")
  S.project.maps.EDITOR_QUEST_MAP=nil
  local IO=require("ModIO");local path=root.."/tests/content-editor/gen3-smoke/quest-project"
  S.path=path;S.mapId="FR_ROUTE10";S.mapSection="objects";S.mapObjectIndex=1
  assert(require("Gen3Workspace").convert(S,S.mapId))
  local object=assert(S.project.maps[S.mapId].objects[1])
  local oldObject=require("src.mods.Merge").deepCopy(object)
  local Picker=require("ChoicePicker");local oldField=Picker.field
  Picker.field=function(_,opts) if opts.title=="EVENT SCRIPT" then opts.onPick(key) end end
  local K=require("Kit");K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Gen3MapEvents").draw(S,20,80,650,740,{markDirty=function() end});K.endFrame()
  Picker.field=oldField
  oldObject.scriptKey=key
  assert(require("ModWriter").encodeLua(S.project.maps[S.mapId].objects[1])==require("ModWriter").encodeLua(oldObject),"Assigning a quest altered NPC properties")
  IO.ensureDirectory(path);assert(IO.save(path,S.project))
  local reopened=assert(IO.load(path))
  assert(reopened.gen3Quests[id].flag==q.flag and reopened.gen3.map_scripts[key][1].op=="lock")
  assert(reopened.maps[S.mapId].objects[1].scriptKey==key)
  S.g3EventMode="quests";S.g3QuestId=id
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0)
  require("Gen3Events").draw(S,20,80,1320,740,{markDirty=function() end});K.endFrame();love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/quest-builder.png","wb"))
  f:write(canvas:newImageData():encode("png"):getString());f:close()
end
