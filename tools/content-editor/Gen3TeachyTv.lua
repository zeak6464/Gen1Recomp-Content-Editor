-- Teachy TV uses the same text registry as map dialogue. Keep edits there so
-- save/load, undo, mod export and the dialogue workspace share one value.
local M={}
M.sections={"shared","battle","status","matchups","catching","tms","register"}
M.labels={shared="Shared dialogue",battle="Battling",status="Status problems",matchups="Type matchups",catching="Catching Pokemon",tms="TMs",register="Registering items"}
M.lines={
  shared={{"gText_TeachyTV","TV title"},{"gTeachyTvString_Cancel","Cancel option"},{"gTeachyTvText_PokedudeSaysHello","Host greeting"}},
  battle={{"gTeachyTvString_TeachBattle","Lesson title"},{"gTeachyTvText_BattleScript1","Introduction"},{"gTeachyTvText_BattleScript2","Conclusion"}},
  status={{"gTeachyTvString_StatusProblems","Lesson title"},{"gTeachyTvText_StatusScript1","Introduction"},{"gTeachyTvText_StatusScript2","Conclusion"}},
  matchups={{"gTeachyTvString_TypeMatchups","Lesson title"},{"gTeachyTvText_MatchupsScript1","Introduction"},{"gTeachyTvText_MatchupsScript2","Conclusion"}},
  catching={{"gTeachyTvString_CatchPkmn","Lesson title"},{"gTeachyTvText_CatchingScript1","Introduction"},{"gTeachyTvText_CatchingScript2","Conclusion"}},
  tms={{"gTeachyTvString_AboutTMs","Lesson title"},{"gTeachyTvText_TMsScript1","Introduction"},{"gPokedudeText_TMTypes","TM types explanation"},{"gPokedudeText_ReadTMDescription","TM description explanation"},{"gTeachyTvText_TMsScript2","Conclusion"}},
  register={{"gTeachyTvString_RegisterItem","Lesson title"},{"gTeachyTvText_RegisterScript1","Introduction"},{"gTeachyTvText_RegisterScript2","Conclusion"}},
}
function M.setText(S,id,text)
  require("Gen3ContentAdapter").prepare(S)
  assert(S.data.text[id],"Teachy TV text is missing from this game's imported cache")
  S.project.text[id]=require("Gen3Dialog").encode((text:gsub("\f","\n\n")))
end
function M.emit(p,encode,out)
  local lines={}
  for _,rows in pairs(M.lines) do for _,row in ipairs(rows) do
    local value=(p.text or {})[row[1]] or ((p.gen3 or {}).text or {})[row[1]]
    if value~=nil then lines[row[1]]=require("src.mods.Schemas").gen3View.textIr(value) end
  end end
  if not next(lines) then return end
  out[#out+1]="local teachyLines="..encode(lines)
  out[#out+1]=[=[
  local Text=require("src.core.game3.rom_text")
  local Runtime=require("src.mods.Runtime")
  if not Text._editorTeachyBridge then
    Text._editorTeachyBridge=true
    local original=Text.ir
    Text.ir=function(key,...) return Runtime.call("editor.gen3.teachyText",original,key,...) end
  end
  mod.hooks:wrap("editor.gen3.teachyText",function(proceed,key,...)
    if teachyLines[key]~=nil then return teachyLines[key] end
    return proceed(key,...)
  end)
]=]
end
function M.draw(S,x,y,w,h,App)
  local K,C,D=require("Kit"),require("ChoicePicker"),require("Gen3Dialog")
  local s=K.scale
  if K.button(x,y,140*s,28*s,"Artwork",{kind=not S.g3TeachyDialogue and "primary" or nil}) then S.g3TeachyDialogue=false end
  if K.button(x+150*s,y,140*s,28*s,"Dialogue",{kind=S.g3TeachyDialogue and "primary" or nil}) then S.g3TeachyDialogue=true end
  y=y+40*s;h=h-40*s
  if not S.g3TeachyDialogue then
    if not S.g3AssetId or not S.g3AssetId:find("/teachy_tv/",1,true) then S.g3AssetId="data/generated/gba/teachy_tv/screen.rgba" end
    require("Gen3Assets").draw(S,x,y,w,h,App,function(path) return path:find("/teachy_tv/",1,true) end)
    return
  end
  require("Gen3ContentAdapter").prepare(S)
  local section=S.g3TeachySection or "shared"
  local rows=M.lines[section];local id=S.g3TeachyLine or rows[1][1]
  local ids,labels={},{};local found=false
  for _,r in ipairs(rows) do ids[#ids+1]=r[1];labels[r[1]]=r[2];found=found or id==r[1] end
  if not found then id=rows[1][1] end
  C.field(S,{x=x,y=y,w=w*.48,h=30*s,current=section,ids=M.sections,labels=M.labels,title="Choose a lesson",onPick=function(v) S.g3TeachySection=v;S.g3TeachyLine=nil;S.g3TeachyPage=1 end})
  C.field(S,{x=x+w*.5,y=y,w=w*.5,h=30*s,current=id,ids=ids,labels=labels,title="Choose dialogue",onPick=function(v) S.g3TeachyLine=v;S.g3TeachyPage=1 end})
  y=y+44*s
  local original=S.data.text[id]
  if not original then K.caption(x,y,"Teachy TV text is unavailable. Import this game's ROM with an updated runtime.");return end
  K.caption(x,y,"Use \\n for a new line and \\f for a new page. Keep {CONTROL:...} tokens intact.");y=y+28*s
  local text=D.display(S.project.text[id] or original)
  local shown=text:gsub("\n","\\n"):gsub("\f","\\f")
  local edited=K.textfield("teachy_"..id,x,y,w,40*s,shown,"");y=y+52*s
  if edited~=shown then
    text=edited:gsub("\\n","\n"):gsub("\\f","\f")
    M.setText(S,id,text);S.g3TeachyPage=1;App.markDirty()
  end
  local ph=D.preview(S,text,x,y,math.min(w,700*s),{page=S.g3TeachyPage or 1});y=y+ph+16*s
  for i,dir in ipairs({-1,1}) do
    if K.button(x+(i-1)*150*s,y,140*s,28*s,dir==-1 and "Previous page" or "Next page",{}) then S.g3TeachyPage=D.step(text,S.g3TeachyPage,dir) end
  end
  y=y+40*s
  if K.button(x,y,220*s,28*s,"Restore original dialogue",{}) and S.project.text[id]~=nil then S.project.text[id]=nil;S.g3TeachyPage=1;App.markDirty() end
  y=y+44*s;K.caption(x,y,"Lesson demonstrations and TM Case unlock requirements follow the original game.")
end
return M
