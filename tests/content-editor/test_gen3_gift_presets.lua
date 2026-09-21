return function(data,root)
  local State,IO=require("State"),require("ModIO")
  local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("gift_presets");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  S.path=root.."/tests/content-editor/gen3-smoke/gift-project"
  IO.ensureDirectory(S.path);assert(IO.writeText(S.path.."/manifest.json",'{"id":"gift_presets","name":"Gift test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  local Panel=require("panels.Gen3StartersPanel")
  Panel.add(S,"starters")
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});K.layout(1360,860);K.beginFrame(0,0,false,0)
  Panel.draw(S,20,80,1320,740,{markDirty=function() error("Viewing starter choices changed the project") end})
  K.endFrame();love.graphics.setCanvas()
  for _,g in ipairs(Panel.gifts) do
    local r=Panel.addGift(S,g[1]);assert(data.maps[r.map],r.map);r.species="PIKACHU";r.level=12
    assert(Panel.addGift(S,g[1])==r,"Duplicate preset")
  end
  assert(#S.project.gen3Starters==11)
  assert(IO.save(S.path,S.project));assert(#IO.load(S.path).gen3Starters==11)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  for _,g in ipairs(Panel.gifts) do if not g[5] then
    local ctx={overworld={map={id=g[3]}},save={party={},flags={}}}
    local gift={species=g[1],level=g[4],ctx=ctx};loader.events:emit("pokemon.before_give",gift)
    assert(gift.species=="PIKACHU" and gift.level==12,g[1])
    ctx.overworld.map.id="FR_ROUTE1";gift.species=g[1];loader.events:emit("pokemon.before_give",gift);assert(gift.species==g[1],"Gift leaked to another map")
  end end
  local Flags=require("src.core.game3.scripting.flags")
  local ctx={overworld={map={id="FR_FIVE_ISLAND_WATER_LABYRINTH"}},save={party={},flags={}},vm={store=Flags.newStore(),ctx={specialVars={}}}}
  local function give() return loader.hooks:call("script.command",function() error("Egg was not handled") end,ctx,"giveegg",{species=175}) end
  assert(give());local egg=ctx.save.party[1];assert(egg.species==25 and egg.isEgg and egg.level==12)
  assert(not ctx.save.dex,"Egg was registered in the Pokedex before hatching")
  assert(Flags.getVar(ctx.vm.store,ctx.vm.ctx,0x800D)==0)
  for i=2,6 do ctx.save.party[i]={species=1} end
  assert(give());assert(#ctx.save.party==6 and Flags.getVar(ctx.vm.store,ctx.vm.ctx,0x800D)==2)
  require("src.mods.Runtime").reset()
end
