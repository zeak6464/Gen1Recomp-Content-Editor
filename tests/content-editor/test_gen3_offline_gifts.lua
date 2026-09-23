return function(data,root)
  local Gifts,IO=require("OfflineGifts"),require("ModIO")
  local S={version="firered",data=data,project=require("State").blankProject("offline_gifts_test")}
  S.project.game="firered";require("Gen3ContentAdapter").prepare(S)
  local id=Gifts.new(S);S.offlineGiftId=id
  local row=S.project.offlineGifts[id];row.quantity=2
  local key=assert(Gifts.build(S,id))
  S.path=root.."/tests/content-editor/gifts-smoke/project"
  assert(IO.ensureDirectory(S.path))
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"offline_gifts_test","name":"Offline gifts test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  assert(IO.save(S.path,S.project))
  S.project=assert(IO.load(S.path));row=S.project.offlineGifts[id]
  assert(row._scripts[key])
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local Native=require("src.core.game3.runtime");local oldSession=Native.session
  local Bag=require("src.core.game3.bag");local potion=data.items.POTION.index
  local session={bag=Bag.new(),party={},name="TEST",trainerId=1};Native.session=session
  local Vm=require("src.core.game3.scripting.vm")
  local function run()
    local messages={}
    local a=require("src.core.game3.scripting.adapters").stub({onMessage=function(t) messages[#messages+1]=t end,openMessageStay=function(t) messages[#messages+1]=t end})
    local vm=Vm.new({scripts=S.project.gen3.map_scripts,text=S.project.text,adapters=a})
    assert(vm:startTalk(key,1,1));for _=1,100 do vm:tick();if not vm:isRunning() then break end end
    assert(not vm:isRunning(),"Gift script did not finish")
    assert(next(a.frozen)==nil,"Gift left NPC frozen")
    return table.concat(messages," "):gsub("%s+"," ")
  end
  Bag.set(session.bag,potion,999)
  assert(run():find(row.full,1,true));assert(not session.modData,"Full bag consumed gift")
  Bag.set(session.bag,potion,0)
  assert(run():find(row.message,1,true));assert(Bag.get(session.bag,potion)==2)
  local Serializer=require("src.core.SaveSerializer")
  session=assert(Serializer.decode(Serializer.encode(session)));Native.session=session
  assert(run():find(row.done,1,true));assert(Bag.get(session.bag,potion)==2)
  local runtime=require("OfflineGiftsRuntime")
  local monGift={MON={kind="pokemon",species="PIKACHU",level=12}}
  for i=1,6 do session.party[i]={species=1} end
  local mod={id="pokemon_gift_test",content=loader.content}
  assert(runtime.claim(mod,monGift,"MON",3,session)==3)
  session.party={}
  assert(runtime.claim(mod,monGift,"MON",3,session)==1)
  assert(#session.party==1 and session.party[1].level==12 and session.party[1].species==data.pokemon.PIKACHU.index)
  assert(runtime.claim(mod,monGift,"MON",3,session)==2)
  local flags=require("src.core.game3.scripting.flags")
  local vm={store=flags.newStore(),ctx={}}
  local passthrough=false
  loader.hooks:call("script.command",function() passthrough=true end,{vm=vm},"editor_offline_gift",{owner="another_mod",gift=id})
  assert(passthrough,"Gift hook intercepted another mod")
  S.project.gen3.map_scripts[key][1]={op="nop"};assert(not Gifts.build(S,id),"Manual script overwritten")
  S.project.gen3.map_scripts[key]=require("src.mods.Merge").deepCopy(row._scripts[key])
  S.project.text[key.."_Text_message"]="Manual text";assert(not Gifts.build(S,id),"Manual dialogue overwritten")
  S.project.text[key.."_Text_message"]=require("src.mods.Merge").deepCopy(row._text[key.."_Text_message"])
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0);S.g3EventMode="gifts"
  require("Gen3Events").draw(S,20,50,1320,790,{markDirty=function() error("Viewing gifts changed the project") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gifts-smoke/gifts.png",canvas:newImageData():encode("png"):getString()))
  Native.session=oldSession;require("src.mods.Runtime").reset()
end
