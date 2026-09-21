return function(data,root)
  local S=require("State").new();S.data=data;S.version="firered";S.project=require("State").blankProject("reported_ui");S.project.game="firered"
  S.path=root.."/tests/content-editor/gen3-smoke/native-project"
  require("Gen3ContentAdapter").prepare(S)
  local R=require("Gen3Resources");local assets=R.assets(data)
  assert(assets["data/generated/gba/ow/87.rgba"].width==16)
  assert(assets["data/generated/gba/trainer_card/badges.rgba"].width==128)
  assert(require("Gen3Labels").map("1:0")~="1:0")
  assert(require("Gen3Labels").natural("9","10"))
  local moves=require("Gen3TrainerForms").moves(S,{species="WEEDLE",level=7})
  assert(#moves>0 and moves[1]~="0","Automatic trainer moves are empty")
  local keys,shops=require("Gen3Workbench").shops(S);local named=0
  for _,key in ipairs(keys) do if shops[key].label~=key then named=named+1 end end
  assert(named>15,"Shop map names missing: "..named)
  require("Gen3AudioAdapter").prepare(S)
  assert(require("Gen3AudioAdapter").label(S,"sfx","5"):find("SELECT"))
  assert(S.data.audio.songs["278"].name=="TITLE" and not S.data.audio.songs["5"])
  assert(S.data.audio.sfx["5"] and not S.data.audio.sfx["278"])
  assert(require("Gen3Animations").label(S,"moves/102"):find("MIMIC"),"Move animation name missing")
  local town=assert(require("Gen3Rom").townMap(S));assert(town:getWidth()==240 and town:getHeight()==160)
  local trades=require("Gen3Rom").trades(S)
  assert(trades.ROM_0.nickname=="MIMIEN" and trades.ROM_0.give=="ABRA" and trades.ROM_0.get=="MR_MIME")
  local shiny=assert(require("Gen3Rom").shiny(S,384,false))
  assert(shiny:getString()~=data._gen3Read("data/generated/gba/pokemon/front/384.rgba"))
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  local function save(name,img)
    local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/"..name..".png","wb"));f:write(img:encode("png"):getString());f:close()
  end
  save("shiny-aggron",shiny)
  for _,spec in ipairs({{"Gen3EncounterForms","encounters"},{"Shops","shops"},{"Gen3Trades","trades"},{"Gen3Assets","ow"},{"Pokemon","pokemon"},{"Trainers","trainers"},{"Audio","audio"},{"Gen3Assets","badges"},{"Gen3Assets","elements"},{"Items","items"},{"Gen3Animations","animations"},{"Moves","moves"},{"Gen3Assets","summary-menu"},{"Trainers","trainer-sprite"}}) do
    S.tab=spec[2];S.pokemonId="AGGRON";S.pokemonShinyPreview=true;S.g3AssetId="data/generated/gba/ow/87.rgba"
    if spec[2]=="summary-menu" then S.g3AssetId="data/generated/gba/pokemon/summary/page_moves_info.rgba" end
    S.moveId="ABSORB"
    S.itemId="BURN_HEAL"
    if spec[2]=="elements" then S.g3AssetId="data/generated/gba/pokemon/battle/elements.rgba" end
    S.trainerId="103";S.trainerSection=spec[2]=="trainer-sprite" and "basics" or "parties"
    if spec[2]=="badges" then S.g3AssetId="data/generated/gba/trainer_card/badges.rgba" end
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
    require(spec[1]).draw(S,20,80,1320,740,{markDirty=function() error("Browsing dirtied the mod") end})
    K.endFrame();love.graphics.setCanvas();save("fixed-"..spec[2],canvas:newImageData())
  end
  for _,mode in ipairs({"bag","party","summary","backgrounds"}) do
    S.g3UiMode=mode;S.g3AssetId=nil;S.g3AssetQuery=""
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.beginFrame(0,0,false,0)
    require("Gen3UiWorkspace").draw(S,20,80,1320,740,{markDirty=function() error("Browsing dirtied the mod") end})
    assert(S._g3AssetImage,"Missing "..mode.." image")
    K.endFrame();love.graphics.setCanvas();save("ui-screen-"..mode,canvas:newImageData())
  end
  assert(assets["data/generated/gba/items/bag/bg.rgba"].width==240)
  assert(assets["data/generated/gba/items/bag/list.rgba"].width==144)
  assert(assets["data/generated/gba/items/bag/bag_male.rgba"].frameHeight==64)
  for _,mode in ipairs({"dex","help","town"}) do
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.beginFrame(0,0,false,0)
    require("Gen3UiContent").draw(S,20,80,1320,740,{markDirty=function() error("Browsing dirtied the mod") end},mode)
    assert(not S.g3UiContentError,S.g3UiContentError);K.endFrame();love.graphics.setCanvas();save("ui-"..mode,canvas:newImageData())
  end
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  require("Gen3Dialog").preview(S,"{PLAYER} booted up the PC.",20,80,800,{})
  love.graphics.setCanvas();save("dialog-preview",canvas:newImageData())
  assert(assets["data/generated/gba/pokemon/battle/elements.rgba"].width==320)
  local choice=require("ChoicePicker");local originalField=choice.field;local selected=false
  choice.field=function(state,opts)
    if opts.title=="When held" then assert(opts.labels["5"]=="CURE BRN");opts.onPick("5");selected=true end
  end
  local item=require("src.mods.Merge").deepCopy(S.data.items.BURN_HEAL)
  require("Gen3ContentForms").items(S,item,function() return item end,{markDirty=function() end},20,20,1200,28,1)
  choice.field=originalField;assert(selected and item.holdEffect==5,"Held-effect dropdown did not write native numeric value")
  local P=require("Gen3IntroPreview");S.tab="ui";S.g3UiMode="playback"
  for _,kind in ipairs({"intro","title"}) do
    assert(P.play(S,kind))
    for _=1,600 do P.step(S);assert(not S.g3IntroPreview.error,S.g3IntroPreview.error) end
    local c=assert(P.render(S));assert(not S.g3IntroPreview.error,S.g3IntroPreview.error)
    save("ui-"..kind,c:newImageData());P.stop(S)
  end
end
