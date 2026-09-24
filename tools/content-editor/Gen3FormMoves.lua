local M={}
function M.validate(f)
  for _,row in ipairs(f.forms) do
    local seen={}
    for _,r in ipairs(row.moveChanges or {}) do
      assert(r.move and r.move~="" and not seen[r.move],"Choose distinct original moves for each form")
      seen[r.move]=true;assert(r.replacement or r.type,"Choose a replacement move or move type")
    end
  end
end
function M.draw(S,row,x,y,w,App)
  local K,C=require("Kit"),require("ChoicePicker");local s=K.scale
  row.moveChanges=row.moveChanges or {}
  if K.button(x,y,250*s,28*s,"Add form-specific move change",{tooltip="Give this form a replacement move, a different move type, or both. Existing slot PP is retained; substitutions revert when leaving the form."}) then row.moveChanges[#row.moveChanges+1]={};App.markDirty() end;y=y+40*s
  local remove
  for i,r in ipairs(row.moveChanges) do
    for _,entry in ipairs({{"move","Original move"},{"replacement","Replacement move (optional)"}}) do
      local key,title=entry[1],entry[2];K.caption(x,y,title);y=y+26*s
      C.field(S,{x=x,y=y,w=w-90*s,h=30*s,current=r[key],ids=require("Autocomplete").moveIds(S),title=title,tooltip=key=="move" and "The known move affected by this form. Choose a distinct original move for each change." or "Move that replaces the original while in this form. Leave empty for a type-only change. Current slot PP is kept, not converted to the new PP maximum.",onPick=function(id) r[key]=id;App.markDirty() end})
      if key=="replacement" and K.button(x+w-80*s,y,80*s,30*s,"Clear",{tooltip="Remove the replacement; keep any move-type override. Each change needs a replacement or a type."}) then r[key]=nil;App.markDirty() end;y=y+40*s
    end
    K.caption(x,y,"Override this move's type (optional)");y=y+26*s
    C.field(S,{x=x,y=y,w=w-90*s,h=30*s,current=r.type,ids=require("TypeIds").list(S),title="MOVE TYPE",tooltip="Use this type when the move resolves in battle for this form. If a replacement is selected, the override applies to that replacement too.",onPick=function(id) r.type=id;App.markDirty() end})
    if K.button(x+w-80*s,y,80*s,30*s,"Clear",{tooltip="Use the move's normal type. Keep a replacement move or remove this change."}) then r.type=nil;App.markDirty() end;y=y+40*s
    if K.button(x,y,200*s,28*s,"Remove move change "..i,{tooltip="Remove this form's move rule. Does not delete either move from the project."}) then remove=i end;y=y+40*s
  end
  if remove then table.remove(row.moveChanges,remove);App.markDirty() end
  return y
end
return M
