-- Map placement uses the same transactional compiler as the event builder.
local M={}
M.labels={dialog="Talking NPC",pickup="Item pickup",item="One-time reward",empty="Empty event"}
function M.draft(S)
  if S._mapTemplateProject~=S.project then
    S._mapTemplateProject=S.project
    S.mapTemplate={kind="dialog",text="Hello!",item="POTION",quantity="1",
      success="Here is your reward!",done="Enjoy your reward!"}
  end
  return S.mapTemplate
end
function M.place(S,x,y,App)
  local d=require("src.mods.Merge").deepCopy(M.draft(S))
  if d.kind=="empty" then return false end
  d.place=true;d.map=S.mapId;d.x=x;d.y=y
  local key,err=require("Gen3EventBuilder").create(S,d)
  if not key then S.status=err;return true end
  S.mapSection="objects";S.mapObjectIndex=#S.project.maps[S.mapId].objects
  S.mapEditMode="events";S.builderPane="details";S._g3EventIdentity=nil
  App.markDirty();S.status=M.labels[d.kind].." placed. Edit it in the sidebar or open the event window."
  return true
end
function M.drawPlacement(S,x,y,w)
  local K=require("Kit");local s=K.scale;local d=M.draft(S)
  local pickerW=math.min(180*s,w*.35)
  require("ChoicePicker").field(S,{x=x,y=y,w=pickerW,h=26*s,current=d.kind,
    ids={"dialog","pickup","item","empty"},labels=M.labels,title="PLACE EVENT",onPick=function(id) d.kind=id end})
  local fx=x+pickerW+8*s;local fw=w-pickerW-8*s
  if d.kind=="dialog" then
    d.text=K.textfield("mapTemplate/text",fx,y,fw,26*s,d.text,"NPC dialogue")
  elseif d.kind=="pickup" or d.kind=="item" then
    require("ItemPicker").field(S,{x=fx,y=y,w=math.max(70*s,fw-76*s),h=26*s,current=d.item,title="REWARD ITEM",onPick=function(id) d.item=id end})
    d.quantity=K.textfield("mapTemplate/quantity",x+w-68*s,y,68*s,26*s,d.quantity,"Quantity")
  end
  return y+30*s
end
return M
