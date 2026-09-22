return function(S,root,output)
  local copy=require("src.mods.Merge").deepCopy
  local Story=require("Gen3EventStory");local Writer=require("ModWriter")
  local catalog=require("Gen3").catalog(S.data,"map_scripts")
  local map=assert(S.data.maps.FR_BIRTH_ISLAND_EXTERIOR)
  local script=map.objects[1].scriptKey
  local originalProject,originalTarget,originalSelection=S.project,S._eventWindowTarget,S._g3RpgRow
  S.project=copy(S.project);S._eventWindowTarget={mapId="FR_BIRTH_ISLAND_EXTERIOR",kind="objects",index=1}
  S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
  local function find()
    for i,row in ipairs(Story.rows(S,script,catalog)) do
      local source=S.project.gen3.map_scripts[row.script] or catalog[row.script]
      local step=source and source[row.index]
      if step and step.op=="special" and (step.id or step[1])==312 then return i,row end
    end
    error("Birth Island legendary battle is missing")
  end
  local i,row=find();S._g3RpgRow=i;S.rpgEventScroll=math.max(0,i-2)
  assert(row.inputs and row.inputs[1].value==410 and row.inputs[2].value==30 and row.inputs[3].value==0)
  local native=Writer.encodeLua(catalog[row.script]);local before=Writer.encodeLua(S.project)
  local K=require("Kit");local Species=require("SpeciesPicker");local Item=require("ItemPicker")
  local sf,it,tf=Species.field,Item.field,K.textfield
  local editing,dirty=nil,0
  Species.field=function(state,opts) if editing=="species" and opts.title=="CHOOSE POKÉMON" then opts.onPick("MEWTWO") end;return sf(state,opts) end
  Item.field=function(state,opts) if editing=="item" and opts.title=="HELD ITEM" then opts.onPick("POTION") end;return it(state,opts) end
  K.textfield=function(key,x,y,w,h,value,...)
    if editing=="level" and key:find("/input/2",1,true) then return "70" end
    return tf(key,x,y,w,h,value,...)
  end
  local function render(name)
    local canvas=love.graphics.newCanvas(1360,860)
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
    K.layout(1360,860);K.beginFrame(0,0,false,0)
    require("Gen3RpgEventEditor").draw(S,20,50,1320,770,{markDirty=function() dirty=dirty+1 end})
    K.endFrame();love.graphics.setCanvas()
    if name then local f=assert(io.open(output.."/"..name..".png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close() end
  end
  render("legendary-before")
  assert(Writer.encodeLua(S.project)==before and dirty==0,"Opening Birth Island edited its event")
  for _,field in ipairs({"species","level","item"}) do editing=field;render() end
  editing=nil;render("legendary-after")
  i,row=find()
  assert(row.inputs[1].value==150 and row.inputs[2].value==70 and row.inputs[3].value==13 and dirty==3)
  assert(Writer.encodeLua(catalog[row.script])==native,"Editing changed the original game script")
  local saved=assert(require("Gen3Decode").decode("return "..Writer.encodeLua(S.project.gen3.map_scripts),{allowArray=true}))
  S.project.gen3.map_scripts=saved;i,row=find()
  assert(row.inputs[1].value==150 and row.inputs[2].value==70 and row.inputs[3].value==13,"Saved inputs did not round trip")
  Species.field,Item.field,K.textfield=sf,it,tf
  S.project,S._eventWindowTarget,S._g3RpgRow=originalProject,originalTarget,originalSelection
  S.rpgEventScroll=0
end
