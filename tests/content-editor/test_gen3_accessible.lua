return function(data,root)
  local S=require("State").new();S.data=data;S.version="firered"
  S.project=require("State").blankProject("accessible");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S)
  local K,P=require("Kit"),require("ChoicePicker")
  local App={markDirty=function() S.dirty=true end}
  local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});K.layout(1360,860)
  local original=P.field
  local selected={}
  P.field=function(state,opts)
    if opts.title=="Trainer class" then selected.class=opts;opts.onPick("81")
    elseif opts.title=="Gender" then opts.onPick("1")
    elseif opts.labels and opts.labels["283"] then opts.onPick("283") end
    return original(state,opts)
  end
  local tr=data.trainers["326"]
  local function mutate() S.project.trainers["326"]=S.project.trainers["326"] or require("src.mods.Merge").deepCopy(tr);return S.project.trainers["326"] end
  K.beginFrame(0,0,false,0);require("Gen3TrainerForms").draw(S,tr,mutate,App,20,20,1000,"basics");K.endFrame()
  P.field=original
  assert(selected.class and selected.class.labels["81"])
  assert(S.project.trainers["326"].gender==1 and S.project.trainers["326"].class==81)
  assert(S.project.gen3TrainerMusic["326"]==283)
  local before=tr.aiFlags or 0
  local chip=K.chip
  K.chip=function(x,y,w,h,label,...) if label=="Use more tactical decisions" then return true end;return false end
  K.beginFrame(0,0,false,0);require("Gen3TrainerForms").draw(S,S.project.trainers["326"],mutate,App,20,20,1000,"ai");K.endFrame();K.chip=chip
  assert(S.project.trainers["326"].aiFlags==before+(math.floor(before/2)%2==1 and -2 or 2))
  S.breedingSpeciesId="BULBASAUR"
  P.field=function(state,opts) if opts.title=="Gender distribution" then opts.onPick("127") end;return original(state,opts) end
  K.beginFrame(0,0,false,0);require("Breeding").draw(S,20,20,1320,800,App);K.endFrame();P.field=original
  assert(S.project.pokemon.BULBASAUR.genderRatio==127)
  S.g3EffectsMode="abilities";S.g3AbilityId="OVERGROW";S.g3AbilitySpecies="CHARMANDER";S.g3AbilitySlot="2"
  local button=K.button
  K.button=function(x,y,w,h,label,...) local result=button(x,y,w,h,label,...);if label=="Assign ability" then return true end;return result end
  love.graphics.clear(.04,.06,.12,1)
  K.beginFrame(0,0,false,0);require("Gen3Effects").draw(S,20,20,1320,800,App);K.endFrame();K.button=button
  assert(S.project.pokemon.CHARMANDER.abilities[2]=="OVERGROW")
  love.graphics.setCanvas();local image=canvas:newImageData():encode("png");local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/accessible-abilities.png","wb"));f:write(image:getString());f:close()
  local serialized=require("ModWriter").serializeProject(S.project)
  local round=assert(loadstring(serialized))()
  assert(round.gen3TrainerMusic["326"]==283)
  require("Gen3ContentAdapter").compile(round)
  assert(round.gen3.pokemon.CHARMANDER.abilities[2]=="OVERGROW")
  local out={};require("Gen3TrainerMusic").emit(round,function() return '{["326"]=283}' end,out)
  local hooks={};local fake={getEncounterMusic=function() return 285 end}
  local runtime={call=function(key,base,...) if hooks[key] then return hooks[key](base,...) end;return base(...) end}
  local env={require=function(name) return name=="src.mods.Runtime" and runtime or fake end,tostring=tostring,mod={hooks={wrap=function(_,key,fn) hooks[key]=fn end}}}
  local chunk=assert(loadstring(table.concat(out,"\n")));setfenv(chunk,env);chunk()
  assert(fake.getEncounterMusic(326)==283 and fake.getEncounterMusic(327)==285)
  hooks={};assert(fake.getEncounterMusic(326)==285,"Disabled music override must restore original behavior")
end
