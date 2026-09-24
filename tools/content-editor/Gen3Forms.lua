local M={}
local function copy(v) return require("src.mods.Merge").deepCopy(v) end
function M.family(S,id)
  for parent,f in pairs(S.project.gen3Forms or {}) do
    if parent==id then return f,parent end
    for _,row in ipairs(f.forms) do if row.species==id then return f,parent end end
  end
end
function M.ensure(S,id)
  local family=M.family(S,id);if family then return family end
  S.project.gen3Forms=S.project.gen3Forms or {}
  family={mode="fixed",forms={{name="Original",species=id}},default=1}
  S.project.gen3Forms[id]=family;return family
end
function M.encounterChoices(S,id)
  local family,parent=M.family(S,id);parent=parent or id
  local ids,labels={"automatic"},{automatic="Automatic / original form"}
  if family then
    for i,row in ipairs(family.forms) do ids[#ids+1]=tostring(i);labels[tostring(i)]=row.name end
  elseif parent=="UNOWN" then
    for i=1,28 do ids[#ids+1]=tostring(i);labels[tostring(i)]=i<=26 and string.char(64+i) or i==27 and "!" or "?" end
  elseif parent=="CASTFORM" then
    for i,name in ipairs({"Normal","Sunny","Rainy","Snowy"}) do ids[#ids+1]=tostring(i);labels[tostring(i)]=name end
  elseif parent=="DEOXYS" then
    for i,name in ipairs({"Attack","Normal"}) do ids[#ids+1]=tostring(i);labels[tostring(i)]=name end
  end
  local current="automatic"
  if family then for i,row in ipairs(family.forms) do if row.species==id and id~=parent then current=tostring(i) end end end
  return ids,labels,current,parent
end
function M.encounterSpecies(S,parent,choice)
  if choice=="automatic" then return parent end
  local family=M.family(S,parent) or M.template(S,parent)
  local row=assert(family.forms[assert(tonumber(choice))],"Choose a form")
  if row.species==parent and family.mode~="weather" and family.mode~="held_item" and family.mode~="gender" and family.mode~="fusion" and family.mode~="rules" then
    -- A separate species prevents personality/default selection from replacing an explicitly chosen base form.
    for _,r in ipairs(family.forms) do if r.fixedEncounterBase then return r.species end end
    local fixed=M.add(S,parent,row.name.." (fixed encounter)");fixed.fixedEncounterBase=true
    return fixed.species
  end
  return row.species
end
function M.add(S,parent,name)
  local family=M.ensure(S,parent)
  local base=assert(S.project.pokemon[parent] or S.data.pokemon[parent])
  local id=parent.."_FORM_"..(#family.forms+1);local n=1
  while S.project.pokemon[id] or S.data.pokemon[id] do n=n+1;id=parent.."_FORM_"..(#family.forms+1).."_"..n end
  -- 412 is Egg; 413..439 are the ROM's extra Unown pictures.
  local index=439;for _,bag in ipairs({S.data.pokemon,S.project.pokemon}) do for _,rec in pairs(bag) do index=math.max(index,rec.index or 0) end end
  assert(index<require("Gen3SpeciesCapacity").limit,"No free species slots remain")
  local rec=copy(base);rec.id=id;rec.index=index+1;rec._isNew=true;rec.name=base.name;rec.trueColor=true
  rec.spriteShinyFront=M.spritePath(base,false,true);rec.spriteShinyBack=M.spritePath(base,true,true)
  rec.letters=nil;rec.forms=nil;S.project.pokemon[id]=rec
  local row={name=name or "New form",species=id};family.forms[#family.forms+1]=row
  return row,rec
end
-- Resolve inherited artwork by its source species, never a custom ROM slot.
function M.spritePath(rec,back,shiny,S)
  local side=back and "Back" or "Front"
  local path=rec["sprite"..(shiny and "Shiny" or "")..side]
  if path and path~="" then return path end
  if shiny then
    if S then
      local family,parent=M.family(S,rec.id)
      if family then
        for i,row in ipairs(family.forms) do
          if row.species==rec.id and i>1 then
            local species,frame,palette
            if parent=="UNOWN" and i<=28 then species,frame,palette=411+i,0,0
            elseif parent=="CASTFORM" and i<=4 then species,frame,palette=385,i-1,i-1
            elseif parent=="DEOXYS" and i==2 then species,frame,palette=410,0,0 end
            if species then return "gen3-form-shiny/"..side:lower().."/"..species.."/"..frame.."/"..palette end
            local base=S.project.pokemon[parent] or S.data.pokemon[parent]
            if base then return M.spritePath(base,back,true) end
          end
        end
      end
    end
    local normal=rec["sprite"..side] or ""
    local source=normal:match("/pokemon/[^/]+/(%d+)%.rgba$")
    source=tonumber(source) or (tonumber(rec.index) and rec.index<=439 and rec.index)
    if source then return "gen3-shiny/"..side:lower().."/"..source end
  end
end
local function writePictures(S,rec,species,frame,palette)
  local IO=require("ModIO");local dir="assets/forms/"..rec.id
  assert(IO.ensureDirectory(S.path.."/"..dir))
  for i,key in ipairs({"spriteFront","spriteBack","spriteShinyFront","spriteShinyBack"}) do
    local img,err=require("Gen3Rom").formPicture(S,species,i%2==0,frame,palette,i>2);assert(img,err)
    local path=dir.."/"..key..".png";assert(IO.writeText(S.path.."/"..path,img:encode("png"):getString()));rec[key]=path
  end
end
function M.template(S,parent)
  local family=M.ensure(S,parent);assert(#family.forms==1,"A forms template has already been added")
  if parent=="UNOWN" then
    family.forms[1].name="A";family.mode="unown"
    for i=1,27 do
      local name=i<26 and string.char(65+i) or i==26 and "!" or "?"
      local _,rec=M.add(S,parent,name);writePictures(S,rec,412+i,0,0)
    end
  elseif parent=="CASTFORM" then
    family.forms[1].name="Normal";family.mode="weather"
    for i,name in ipairs({"Sunny","Rainy","Snowy"}) do
      local row,rec=M.add(S,parent,name);rec.types=({{"FIRE"},{"WATER"},{"ICE"}})[i]
      row.weather=({"SUN","RAIN","HAIL"})[i];writePictures(S,rec,385,i,i)
    end
  elseif parent=="DEOXYS" then
    family.forms[1].name="Attack"
    local original=copy(S.project.pokemon[parent] or S.data.pokemon[parent]);S.project.pokemon[parent]=original
    writePictures(S,original,410,1,0)
    local _,normal=M.add(S,parent,"Normal");writePictures(S,normal,410,0,0)
    for _,name in ipairs({"Defense","Speed"}) do local row=M.add(S,parent,name);row.needsArtwork=true end
  end
  return family
end
function M.draw(S,mon,x,y,w,App)
  local K,C=require("Kit"),require("ChoicePicker");local s=K.scale
  local family,parent=M.family(S,mon.id);parent=parent or mon.id
  K.caption(x,y,"Forms share a Pokedex number and can have their own sprites, stats and moves.");y=y+32*s
  if not family then
    if parent=="UNOWN" or parent=="CASTFORM" or parent=="DEOXYS" then
      local ids,labels={},{}
      for i=1,28 do ids[i]=i;labels[i]=i<=26 and string.char(64+i) or i==27 and "!" or "?" end
      if parent=="CASTFORM" then ids={1,2,3,4};labels={"Normal","Sunny","Rainy","Snowy"}
      elseif parent=="DEOXYS" then ids={1,2,3,4};labels={"Attack (FireRed)","Normal","Defense","Speed"} end
      S.g3NativeForms=S.g3NativeForms or {}
      local nativeSelection=parent=="UNOWN" and (S.g3NativeUnown or 1) or (S.g3NativeForms[parent] or 1)
      C.field(S,{x=x,y=y,w=w,h=30*s,current=nativeSelection,ids=ids,labels=labels,title="Pokemon form",onPick=function(id) if parent=="UNOWN" then S.g3NativeUnown=id end;S.g3NativeForms[parent]=id end});y=y+40*s
      K.caption(x,y,parent=="UNOWN" and "All 28 original forms are available." or parent=="CASTFORM" and "Forecast changes the form with the weather." or "FireRed contains Normal and Attack artwork. Defense and Speed need imported sprites.");y=y+30*s
      S._nativeUnownPictures=S._nativeUnownPictures or {}
      local selected=nativeSelection
      S._nativeFormPictures=S._nativeFormPictures or {}
      local cacheKey=parent..selected
      local available=parent~="DEOXYS" or selected<=2
      if available and not S._nativeFormPictures[cacheKey] then
        local ok,pictures=pcall(function()
          local species=parent=="UNOWN" and (selected==1 and 201 or 411+selected) or parent=="CASTFORM" and 385 or 410
          local frame=parent=="CASTFORM" and selected-1 or parent=="DEOXYS" and (selected==1 and 1 or 0) or 0
          local palette=parent=="CASTFORM" and frame or 0
          local pictures={}
          for i=1,4 do pictures[i]=love.graphics.newImage(assert(require("Gen3Rom").formPicture(S,species,i%2==0,frame,palette,i>2))) end
          return pictures
        end)
        if ok then S._nativeFormPictures[cacheKey]=pictures;if parent=="UNOWN" then S._nativeUnownPictures[selected]=pictures end else S.status=tostring(pictures) end
      end
      if not available then K.caption(x,y,"Artwork is not present in this ROM. Use Edit these forms to import it.") end
      for i,img in ipairs(S._nativeFormPictures[cacheKey] or {}) do K.caption(x+(i-1)*160*s,y,({"Front","Back","Shiny front","Shiny back"})[i]);img:setFilter("nearest","nearest");love.graphics.setColor(1,1,1,1);love.graphics.draw(img,x+(i-1)*160*s,y+24*s,0,2*s,2*s) end
      y=y+165*s
      K.caption(x,y,"Party icon")
      local iconIndex=parent=="UNOWN" and (selected==1 and 201 or 411+selected) or mon.index
      require("Preview").drawPokemonIcon(S,{index=iconIndex},x,y+24*s,64*s,64*s)
      y=y+100*s
      if K.button(x,y,300*s,30*s,"Edit these forms",{kind="good"}) then
        local staged=setmetatable({project=copy(S.project)},{__index=S});local ok,err=pcall(M.template,staged,parent)
        if ok then S.project=staged.project;S.g3FormSelection=S.g3FormSelection or {};S.g3FormSelection[parent]=selected;App.markDirty() else S.status=tostring(err) end
      end
      return y+45*s
    end
    if K.button(x,y,210*s,30*s,"Enable multiple forms",{kind="good"}) then M.ensure(S,parent);App.markDirty() end
    return y+45*s
  end
  if #family.forms==1 and (parent=="UNOWN" or parent=="CASTFORM" or parent=="DEOXYS") then
    if K.button(x,y,270*s,30*s,"Add "..parent.." form templates",{}) then
      local staged=setmetatable({project=copy(S.project)},{__index=S});local ok,err=pcall(M.template,staged,parent)
      if ok then S.project=staged.project;App.markDirty() else S.status=tostring(err) end
    end;y=y+40*s
  end
  C.field(S,{x=x,y=y,w=w,h=30*s,current=family.mode,ids={"fixed","personality","unown","weather","held_item","gender","fusion","rules"},
    labels={fixed="Choose a fixed / regional form",personality="Permanent form based on personality",unown="Unown letter from personality",weather="Change appearance and type with weather (Forecast)",held_item="Change form while holding an item",gender="Choose form by gender",fusion="Fuse with a partner using a key item",rules="Transform using move, item or battle rules"},title="How forms are chosen",
    tooltip="Fixed forms include regional variants. Held-item forms update when giving/taking items or entering battle. Gender forms use the Pokemon's gender. Existing moves and PP are preserved when changing forms. Weather forms keep the original stats and moves.",
    onPick=function(id) family.mode=id;App.markDirty() end});y=y+40*s
  local ids,names={},{};for i,row in ipairs(family.forms) do ids[#ids+1]=tostring(i);names[tostring(i)]=row.name end
  S.g3FormSelection=S.g3FormSelection or {};local selection=math.min(S.g3FormSelection[parent] or 1,#ids)
  C.field(S,{x=x,y=y,w=w-180*s,h=30*s,current=tostring(selection),ids=ids,labels=names,title="Form to edit",tooltip="Select the form whose settings you want to edit. This does not change a Pokemon in the player's party.",onPick=function(id) S.g3FormSelection[parent]=tonumber(id) end})
  if K.button(x+w-170*s,y,170*s,30*s,"Add custom form",{kind="good",tooltip="Create a new species record for this family, starting with the parent's data. Configure its artwork, stats and selection rules afterward."}) then M.add(S,parent);S.g3FormSelection[parent]=#family.forms;App.markDirty() end;y=y+42*s
  local row=family.forms[selection];local rec=S.project.pokemon[row.species] or S.data.pokemon[row.species]
  if not rec then K.caption(x,y,"This form's Pokemon record was removed.");return y+35*s end
  local value=K.textfield("g3FormName",x,y,w,30*s,row.name,"Form name","A friendly name such as Sunny, Winter, or Attack.")
  if value~=row.name then row.name=value;App.markDirty() end;y=y+40*s
  if family.mode=="fixed" then
    C.field(S,{x=x,y=y,w=w,h=30*s,current=tostring(family.default or 1),ids=ids,labels=names,title="Default form for the original Pokemon",tooltip="Used when the original species is given or enters battle. You can choose another named form directly in Pokemon dropdowns.",onPick=function(id) family.default=tonumber(id);App.markDirty() end});y=y+40*s
  elseif family.mode=="weather" and selection>1 then
    C.field(S,{x=x,y=y,w=w,h=30*s,current=row.weather or "NONE",ids={"NONE","SUN","RAIN","HAIL","SANDSTORM"},title="Weather for this form",onPick=function(id) row.weather=id;App.markDirty() end});y=y+40*s
  elseif family.mode=="held_item" then
    K.caption(x,y,selection==1 and "Original form is used without a matching held item." or "Held item that activates this form");y=y+30*s
    if selection>1 then
      require("ItemPicker").field(S,{x=x,y=y,w=w,h=30*s,current=row.item,title="FORM HELD ITEM",onPick=function(id) row.item=id;App.markDirty() end});y=y+40*s
    end
  elseif family.mode=="gender" then
    K.caption(x,y,selection==1 and "Original form is used for genders without a rule." or "Gender that uses this form");y=y+30*s
    if selection>1 then
      C.field(S,{x=x,y=y,w=w,h=30*s,current=row.gender,ids={"F","M","U"},labels={F="Female",M="Male",U="Genderless"},title="FORM GENDER",onPick=function(id) row.gender=id;App.markDirty() end});y=y+40*s
    end
  end
  if family.mode=="rules" then y=require("Gen3FormRules").draw(S,family,selection,x,y,w,App) end
  if family.mode=="fusion" then y=require("Gen3Fusion").draw(S,family,parent,row,selection,x,y,w,App) end
  if family.mode~="rules" then
    if K.button(x,y,260*s,28*s,family.extraRules and "Disable additional battle rules" or "Enable additional battle rules",{tooltip="Combine battle-triggered changes with this family's selection mode, including fusion. Disabling preserves the rules for later but stops exporting them."}) then family.extraRules=not family.extraRules;App.markDirty() end;y=y+40*s
    if family.extraRules then y=require("Gen3FormRules").draw(S,family,selection,x,y,w,App) end
  end
  y=require("Gen3AdvancedForms").draw(S,family,selection,x,y,w,App)
  y=require("Gen3FieldForms").draw(S,family,selection,x,y,w,App)
  y=require("Gen3FormMoves").draw(S,row,x,y,w,App)
  K.caption(x,y,"Pokemon entry: "..row.species);y=y+30*s
  if K.button(x,y,290*s,30*s,"Edit this form's stats and moves",{}) then S.pokemonId=row.species;S.pokemonSection="basics" end;y=y+44*s
  if row.needsArtwork then K.caption(x,y,"Template uses copied artwork and stats. Import sprites and edit stats for this form.");y=y+30*s end
  for i,key in ipairs({"spriteFront","spriteBack","spriteShinyFront","spriteShinyBack"}) do
    local xx=x+((i-1)%2)*210*s
    local yy=y+math.floor((i-1)/2)*200*s
    local label=({"Front","Back","Shiny front","Shiny back"})[i]
    K.caption(xx,yy,label)
    require("Preview").draw(S,M.spritePath(rec,i%2==0,i>2,S),xx,yy+22*s,128*s,128*s,false)
    if K.button(xx,yy+156*s,200*s,30*s,"Import "..label:lower().." PNG",{}) then
      App.pickFile("Form sprite","PNG|*.png",function(file)
        local IO=require("ModIO");local bytes=IO.readText(file);local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"form.png")) end)
        if not ok or img:getWidth()~=64 or img:getHeight()~=64 then S.status="Use a 64 x 64 PNG for this form";return end
        local dir="assets/forms/"..row.species;assert(IO.ensureDirectory(S.path.."/"..dir));local path=dir.."/"..key..".png";assert(IO.writeText(S.path.."/"..path,bytes))
        S.project.pokemon[row.species]=S.project.pokemon[row.species] or copy(rec);S.project.pokemon[row.species][key]=path;require("Preview").invalidate();App.markDirty()
      end)
    end
  end
  y=y+400*s
  K.caption(x,y,"Party icon");y=y+24*s
  require("Preview").drawPokemonIcon(S,rec,x,y,64*s,64*s)
  require("Gen3PokemonIcons").drawControls(S,rec.index,App,x+80*s,y,math.max(300*s,w-80*s),30*s,s)
  y=y+76*s
  return y
end
function M.emit(p,encode,out)
  local species={}
  for id in pairs((p.gen3 or {}).pokemon or {}) do species[#species+1]=id end
  table.sort(species)
  if not next(p.gen3Forms or {}) and #species==0 then return end
  local configs,artwork={},{}
  for id,rec in pairs(p.pokemon or {}) do
    artwork[id]={front=rec.spriteShinyFront,back=rec.spriteShinyBack}
  end
  for parent,f in pairs(p.gen3Forms or {}) do
    assert(#f.forms>0 and f.forms[1].species==parent,"Invalid form family")
    assert(f.mode=="fixed" or f.mode=="personality" or f.mode=="unown" or f.mode=="weather" or f.mode=="held_item" or f.mode=="gender" or f.mode=="fusion" or f.mode=="rules","Invalid form selection")
    if f.mode=="rules" or f.extraRules then require("Gen3FormRules").validate(f) end
    require("Gen3AdvancedForms").validate(f)
    require("Gen3FieldForms").validate(f)
    require("Gen3FormMoves").validate(f)
    if f.mode=="fusion" then require("Gen3Fusion").validate(p,parent,f) end
    local seen={}
    for i,row in ipairs(f.forms) do
      if i>1 and f.mode=="held_item" then
        assert(type(row.item)=="string" and row.item~="","Choose a held item for "..row.name)
        assert(not seen[row.item],"Two forms use the same held item: "..row.item);seen[row.item]=true
      elseif i>1 and f.mode=="gender" then
        assert(row.gender=="F" or row.gender=="M" or row.gender=="U","Choose a gender for "..row.name)
        assert(not seen[row.gender],"Two forms use the same gender");seen[row.gender]=true
      end
    end
    local rec=copy(f);rec.parent=parent
    for _,row in ipairs(rec.forms) do if row.fieldRule and row.fieldRule.kind~="none" then rec.fieldControlled=true end end
    configs[#configs+1]=rec
  end
  out[#out+1]="local forms=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FormsRuntime.lua")).."\nend)()\nforms.install(mod,"..encode(configs)..","..encode(species)..","..encode(artwork)..")"
  local rules={};for _,f in ipairs(configs) do if f.mode=="rules" or f.extraRules then rules[#rules+1]=f end end
  if #rules>0 then out[#out+1]="local rules=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FormRulesRuntime.lua")).."\nend)()\nrules.install(mod,"..encode(rules)..")" end
  local fusion={};for _,f in ipairs(configs) do if f.mode=="fusion" then fusion[#fusion+1]=f end end
  if #fusion>0 then
    out[#out+1]="local fusion=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FusionRuntime.lua")).."\nend)()\nfusion.install(mod,"..encode(fusion)..")"
  end
  local advanced={}
  for _,f in ipairs(configs) do for _,row in ipairs(f.forms) do if row.mechanic and row.mechanic.kind and row.mechanic.kind~="none" then advanced[#advanced+1]=f;break end end end
  if #advanced>0 then
    out[#out+1]="local advanced=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3AdvancedFormsRuntime.lua")).."\nend)()\nadvanced.install(mod,"..encode(advanced)..","..encode(require("Gen3Types").ids(p))..")"
  end
  local field={};for _,f in ipairs(configs) do if f.fieldControlled then field[#field+1]=f end end
  if #field>0 then out[#out+1]="local field=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FieldFormsRuntime.lua")).."\nend)()\nfield.install(mod,"..encode(field)..")" end
  local changes={};for _,f in ipairs(configs) do for _,row in ipairs(f.forms) do if #(row.moveChanges or {})>0 then changes[#changes+1]=f;break end end end
  if #changes>0 then out[#out+1]="local changes=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FormMovesRuntime.lua")).."\nend)()\nchanges.install(mod,"..encode(changes)..","..encode(require("Gen3Types").ids(p))..")" end
end
return M
