return function(S,root,output)
  local K=require("Kit");local Picker=require("ChoicePicker");local L=require("Gen3ActionLanguage")
  local encode=require("ModWriter").encodeLua
  local originalField=Picker.field
  local selected
  Picker.field=function(state,opts)
    if opts.title==selected then opts.onPick(opts.ids[#opts.ids]) end
    return originalField(state,opts)
  end
  local canvas=love.graphics.newCanvas(960,720)
  local cases={
    {step={op="special",id=0,[1]=0},title="Built-in game action"},
    {step={op="fadescreenspeed",[1]=1,[2]=2},title="Screen transition"},
    {step={op="turnobject",localId=255,[1]=255,direction=1,[2]=1},title="Face toward"},
    {step={op="setmonmove",[1]=0,[2]=0,[3]=33},title="Move to replace"},
    {step={op="givemon",[1]=1,[2]=5,[3]=0,[4]=0,[5]=0},title="Pokémon to give"},
  }
  for i,case in ipairs(cases) do
    local changes=0;local before=encode(case.step)
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
    K.layout(960,720);K.beginFrame(0,0,false,0)
    L.draw(S,"forms/"..i,case.step,30,30,900,function() changes=changes+1 end)
    K.endFrame();love.graphics.setCanvas()
    assert(encode(case.step)==before and changes==0,"Browsing changed action fields")
    if i==4 then
      local f=assert(io.open(output.."/plain-action-settings.png","wb"))
      f:write(canvas:newImageData():encode("png"):getString());f:close()
    end
    selected=case.title
    love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
    L.draw(S,"forms/"..i,case.step,30,30,900,function() changes=changes+1 end)
    K.endFrame();love.graphics.setCanvas();selected=nil
    assert(changes==1 and encode(case.step)~=before,"Named choice did not update its value: "..case.title.." / "..changes)
    if case.step.id then assert(case.step.id==case.step[1]) end
    if case.step.direction then assert(case.step.direction==case.step[2]) end
  end
  Picker.field=originalField
  -- Every imported command must render without silently changing its operands.
  local projectBefore=encode(S.project)
  for _,opcode in pairs(require("src.core.game3.scripting.opcodes").TABLE) do
    local step={op=opcode.name}
    for i in ipairs(opcode.args or {}) do step[i]=0 end
    local before=encode(step)
    love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
    L.draw(S,"all-forms/"..opcode.name,step,30,30,900,function() error("Browsing changed "..opcode.name) end)
    K.endFrame();love.graphics.setCanvas()
    assert(encode(step)==before,"Browsing changed "..opcode.name)
  end
  assert(encode(S.project)==projectBefore,"Browsing action settings changed the project")
  local originalProject=S.project
  S.project=require("src.mods.Merge").deepCopy(originalProject)
  local A=require("Gen3EventActions");local Content=require("Gen3ActionContent")
  local textStep={op="message"};A.setText(S,textStep,"Original trainer dialogue")
  local trainer={op="trainerbattle",trainer=1,[1]=1,type=0,[2]=0,introText=textStep.ptr,defeatText=textStep.ptr}
  local oldTextfield,oldButton=K.textfield,K.button
  local changes=0
  K.textfield=function(key,...)
    if key=="trainer-settings/introText/line/1" then return "Let's battle, {PLAYER}!" end
    return oldTextfield(key,...)
  end
  local applied=false
  K.button=function(x,y,w,h,label,opts)
    if label=="Apply text" and opts.enabled and not applied then applied=true;return true end
    return oldButton(x,y,w,h,label,opts)
  end
  love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
  L.draw(S,"trainer-settings",trainer,30,30,900,function() changes=changes+1 end)
  K.endFrame();love.graphics.setCanvas();K.textfield=oldTextfield;K.button=oldButton
  assert(changes==1 and trainer.introText~=textStep.ptr,"Trainer dialogue was not saved")
  assert(A.text(S,{ptr=trainer.introText})=="Let's battle, {PLAYER}!")
  assert(A.text(S,{ptr=trainer.defeatText})=="Original trainer dialogue","Shared dialogue was changed")
  S.project.marts.test_original={"POTION"}
  local shop={op="pokemart",ptr="test_original",[1]="test_original"}
  local Items=require("ItemPicker");local originalItemField=Items.field
  Items.field=function(state,opts)
    if opts.title=="ADD SHOP ITEM" then opts.onPick("POKE_BALL") end
    return originalItemField(state,opts)
  end
  love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
  L.draw(S,"shop-settings",shop,30,30,900,function() changes=changes+1 end)
  K.endFrame();love.graphics.setCanvas();Items.field=originalItemField
  assert(changes==2 and shop.ptr==shop[1] and shop.ptr~="test_original")
  assert(#Content.shop(S,shop.ptr)==2 and #Content.shop(S,"test_original")==1,"Shop edit changed shared inventory")
  local emitted={};require("Gen3Workbench").emit(S.project,encode,emitted)
  assert(table.concat(emitted,"\n"):find(shop.ptr,1,true),"Shop inventory missing from export")
  local target={op="warp",[1]=0,[2]=0,[3]=0,[4]=1,[5]=1}
  Picker.field=function(state,opts)
    if opts.title=="DESTINATION MAP" then
      for _,id in ipairs(opts.ids) do if id~=opts.current then opts.onPick(id);break end end
    end
    return originalField(state,opts)
  end
  love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
  L.draw(S,"destination-settings",target,30,30,900,function() changes=changes+1 end)
  K.endFrame();love.graphics.setCanvas();Picker.field=originalField
  assert(changes==3 and (target[1]~=0 or target[2]~=0),"Map picker did not save map coordinates")
  S.project=originalProject
end
