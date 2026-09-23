local M={}
local Kit=require("Kit")
local List=require("RegList")
local Steps=require("Gen3ScriptSteps")
function M.draw(S,x,y,w,h,App)
  if not S.project then Kit.caption(x,y,"Open a Gen 3 mod first");return end
  local s=Kit.scale
  local body=List.modeChips(S,"g3EventMode",{{id="map",label="Map events"},{id="builder",label="Create event"},{id="quests",label="Reward quests"},{id="gifts",label="Offline gifts"},{id="scripts",label="All scripts"}},x,y,s)
  h=h-(body-y);y=body
  if S.g3EventMode=="map" then require("Gen3EventEditor").draw(S,x,y,w,h,App);return end
  if S.g3EventMode=="builder" then require("Gen3EventBuilder").draw(S,x,y,w,h,App);return end
  if S.g3EventMode=="quests" then require("Gen3Quests").draw(S,x,y,w,h,App);return end
  if S.g3EventMode=="gifts" then require("OfflineGifts").draw(S,x,y,w,h,App);return end
  S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
  local edits=S.project.gen3.map_scripts
  local catalog=require("Gen3").catalog(S.data,"map_scripts")
  local ids=List.mergeIds(edits,catalog)
  if not S.gen3Id or not (edits[S.gen3Id] or catalog[S.gen3Id]) then S.gen3Id=ids[1] end
  local fx,fw=List.drawList(S,App,x,y,w,h,"EVENT SCRIPTS",ids,{selKey="gen3Id",queryKey="g3ScriptQuery",offsetKey="g3ScriptOffset",
    footerLabel="New script",onFooter=function() S.g3NewScript=true end})
  if S.g3NewScript then
    S.g3ScriptName=Kit.textfield("g3ScriptName",fx,y,fw,28*s,S.g3ScriptName or "EDITOR_EVENT","")
    if Kit.button(fx,y+40*s,130*s,28*s,"Create",{kind="good"}) then
      local id=S.g3ScriptName
      if id:match("^[%w_]+$") and not catalog[id] and not edits[id] then
        edits[id]={{op="end"}};S.gen3Id=id;S.g3NewScript=false
        S.project.gen3Modes=S.project.gen3Modes or {};S.project.gen3Modes.map_scripts=S.project.gen3Modes.map_scripts or {}
        S.project.gen3Modes.map_scripts[id]="register";App.markDirty()
      else S.status="Choose an unused script ID" end
    end
    if Kit.button(fx+140*s,y+40*s,130*s,28*s,"Cancel",{}) then S.g3NewScript=false end
    return
  end
  M.drawScript(S,S.gen3Id,fx,y,fw,h,App)
end
function M.drawScript(S,id,fx,y,fw,h,App)
  local s=Kit.scale
  S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
  local edits=S.project.gen3.map_scripts
  local catalog=require("Gen3").catalog(S.data,"map_scripts")
  local value=id and (edits[id] or catalog[id])
  if not value then Kit.caption(fx,y,"Select a script");return end
  local mode="g3StoryAdvanced/"..id
  if Kit.button(fx,y,220*s,28*s,S[mode] and "What happens" or "Advanced commands",{}) then S[mode]=not S[mode];S._g3MessageDraft=nil end
  y=y+40*s;h=h-40*s
  if not S[mode] then require("Gen3EventStory").draw(S,id,catalog,fx,y,fw,h,App);return end
  if S._g3ScriptSource~=value or S._g3ScriptId~=id then
    S._g3ScriptSource=value;S._g3ScriptId=id
    S._g3ScriptDraft=require("src.mods.Merge").deepCopy(value)
  end
  Kit.caption(fx,y,Kit.ellipsize("micro",id..(edits[id] and " (edited)" or " (original)"),fw-155*s))
  if catalog[id] and edits[id] and Kit.button(fx+fw-140*s,y,140*s,28*s,"Revert edits",{}) then
    edits[id]=nil;S._g3ScriptSource=nil;App.markDirty();return
  end
  if S._g3ScriptCatalog~=catalog then
    S._g3ScriptTemplates=Steps.templates(catalog);S._g3ScriptCatalog=catalog
  end
  Steps.draw(S,"event/"..id,S._g3ScriptDraft,S._g3ScriptTemplates,fx,y+42*s,fw,h-42*s,function()
    edits[id]=require("src.mods.Merge").deepCopy(S._g3ScriptDraft)
    S._g3ScriptSource=edits[id];App.markDirty()
  end,{id=id,catalog=catalog,onInputChanged=function() S._g3ScriptSource=nil;App.markDirty() end})
end
return M

