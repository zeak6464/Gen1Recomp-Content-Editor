local Kit=require("Kit")
local R=require("Gen3Resources")
local List=require("RegList")
local Pane=require("FormPane")
local Writer=require("ModWriter")
local Panel={}
function Panel.label(S,id)
  local index=tonumber(id:match("^moves/(%d+)$"))
  if not index then return id end
  local catalogs={S.project and S.project.moves or {},S.data.moves or {},require("Gen3").catalog(S.data,"moves")}
  for _,catalog in ipairs(catalogs) do for key,rec in pairs(catalog) do
    if type(rec)=="table" and tonumber(rec.index)==index then return (rec.name or key):gsub("_"," ").." ("..index..")" end
  end end
  return index==0 and "No move (0)" or id
end
function Panel.draw(S,x,y,w,h,App)
  if not S.project then Kit.caption(x,y,"Open a FireRed project first");return end
  local s=Kit.scale
  local catalog=R.animations(S.data)
  local edits=S.project.gen3Animations or {}
  local body=List.modeChips(S,"g3AnimSection",{{id="moves",label="Moves"},{id="status",label="Status"},
    {id="general",label="General"},{id="special",label="Special"},{id="labels",label="Subroutines"},
    {id="tags",label="Sprites"},{id="animBgs",label="Backgrounds"}},x,y,s)
  h=h-(body-y);y=body
  local ids={}
  for _,id in ipairs(List.mergeIds(edits,catalog)) do
    if id:match("^([^/]+)/")==S.g3AnimSection then ids[#ids+1]=id end
  end
  table.sort(ids,require("Gen3Labels").natural)
  if S.g3AnimId and S.g3AnimId:match("^([^/]+)/")~=S.g3AnimSection then S.g3AnimId=ids[1] end
  S.g3AnimId=S.g3AnimId or (catalog["moves/1"] and "moves/1") or ids[1]
  local fx,fw=List.drawList(S,App,x,y,w,h,"Battle animations",ids,{selKey="g3AnimId",queryKey="g3AnimQuery",offsetKey="g3AnimOffset",label=function(id) return Panel.label(S,id) end,
    footerLabel="New script",onFooter=function() S.g3AnimCreating=true end})
  if S.g3AnimCreating then
    Kit.caption(fx,y,"New ID: moves/355 or labels/MyAnimation")
    S.g3AnimNew=Kit.textfield("g3AnimNew",fx,y+30*s,fw,28*s,S.g3AnimNew or "labels/MyAnimation","")
    if Kit.button(fx,y+70*s,120*s,28*s,"Create",{}) then
      local id=S.g3AnimNew
      local value={{op="end"}}
      local ok,err=R.checkAnimation(id,value)
      if ok and not catalog[id] and not edits[id] then
        S.project.gen3Animations=S.project.gen3Animations or {};S.project.gen3Animations[id]=value
        S.g3AnimId=id;S.g3AnimCreating=false;App.markDirty()
      else S.status=err or "That ID already exists" end
    end
    if Kit.button(fx+135*s,y+70*s,120*s,28*s,"Cancel",{}) then S.g3AnimCreating=false end
    return
  end
  local id=S.g3AnimId
  if not id then Kit.caption(fx,y,"Import FireRed to extract animations");return end
  local value=edits[id] or catalog[id]
  if S._g3AnimValue~=value or S._g3AnimId~=id then
    if S._g3AnimId~=id then
      require("Gen3AnimPreview").stop(S)
      S.g3ShowAnimPreview=false
    end
    S._g3AnimId,S._g3AnimValue=id,value
    S._g3AnimDraft={value=Writer.encodeLua(value)}
    S._g3Expanded=S._g3Expanded or {};S._g3Expanded.value=true
  end
  Kit.caption(fx,y,Panel.label(S,id))
  Kit.caption(fx,y+25*s,"Edit commands and arguments; Apply, then Save. Asset sheets are in UI / assets.")
  if Kit.button(fx,y+57*s,130*s,28*s,"Apply animation",{kind="primary"}) then
    local box,err=require("Gen3Decode").decode("return {value="..S._g3AnimDraft.value.."}",{allowArray=true})
    local ok=false
    if box then ok,err=R.checkAnimation(id,box.value) end
    if ok then
      S.project.gen3Animations=S.project.gen3Animations or {};S.project.gen3Animations[id]=box.value
      App.markDirty();S.status="Applied "..id
    else S.status=tostring(err) end
  end
  if Kit.button(fx+142*s,y+57*s,120*s,28*s,"Revert edits",{}) then
    if S.project.gen3Animations then S.project.gen3Animations[id]=nil end
    S._g3AnimValue=nil;App.markDirty()
  end
  local spec=id:match("^(tags)/") or id:match("^(animBgs)/")
  if not spec then
    local box=require("Gen3Decode").decode("return {value="..S._g3AnimDraft.value.."}",{allowArray=true})
    if box then
      if Kit.button(fx+274*s,y+57*s,120*s,28*s,"Play draft",{kind="primary"}) then
        require("Gen3ContentAdapter").prepare(S)
        local ok,err=require("Gen3AnimPreview").play(S,id,box.value)
        S.g3ShowAnimPreview=true
        if not ok then S.status=tostring(err) end
      end
      if Kit.button(fx+406*s,y+57*s,120*s,28*s,S.g3ShowAnimPreview and "Commands" or "Preview",{}) then
        S.g3ShowAnimPreview=not S.g3ShowAnimPreview
        if not S.g3ShowAnimPreview then require("Gen3AnimPreview").stop(S) end
      end
      if S.g3ShowAnimPreview then
        for i,key in ipairs({"g3PreviewAttacker","g3PreviewTarget"}) do
          require("SpeciesPicker").field(S,{x=fx+(i-1)*fw/2,y=y+100*s,w=fw/2-8*s,h=28*s,
            current=S[key] or (i==1 and "BULBASAUR" or "CHARMANDER"),onPick=function(species) S[key]=species end})
        end
        if Kit.button(fx,y+136*s,180*s,26*s,S.g3PreviewReverse and "Enemy attacks" or "Player attacks",{}) then S.g3PreviewReverse=not S.g3PreviewReverse end
        require("Gen3AnimPreview").draw(S,fx,y+174*s,fw,h-174*s)
        return
      end
      local Steps=require("Gen3ScriptSteps")
      if S._g3AnimTemplatesCatalog~=catalog then S._g3AnimTemplates=Steps.templates(catalog);S._g3AnimTemplatesCatalog=catalog end
      Steps.draw(S,"animation/"..id,box.value,S._g3AnimTemplates,fx,y+100*s,fw,h-100*s,function()
        S._g3AnimDraft.value=Writer.encodeLua(box.value)
      end)
    end
    return
  end
  local top,view=Pane.begin(S,"g3AnimScroll",fx,y+100*s,fw,h-100*s)
  local ending=require("Gen3Fields").draw(S,"anim/"..id,fx,top,view.contentW,S._g3AnimDraft,
    {value=not spec and {kind="list",inner={fields={op={kind="string"}}}} or nil})
  Pane.finish(S,"g3AnimScroll",top,ending,view)
end
return Panel
