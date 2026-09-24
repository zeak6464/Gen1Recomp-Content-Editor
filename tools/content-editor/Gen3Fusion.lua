local M={}
function M.validate(p,parent,f)
  assert(type(f.fusionItem)=="string" and f.fusionItem~="","Choose a fusion key item for "..parent)
  assert(#f.forms>=2,"Add a fusion form for "..parent)
  local used={}
  for i,row in ipairs(f.forms) do if i>1 and (row.partner or not row.mechanic or not row.mechanic.kind or row.mechanic.kind=="none") then
    assert(type(row.partner)=="string" and row.partner~="" and row.partner~=parent,"Choose a different partner species for "..row.name)
    assert(not used[row.partner],"Two fusion forms use the same partner");used[row.partner]=true
    for _,other in ipairs(f.forms) do assert(row.partner~=other.species,"A fusion form cannot be its own family's partner") end
  end end
  assert(next(used),"Add at least one fusion partner")
  local item=(p.items or {})[f.fusionItem]
  if item then assert(item.pocket=="KEY_ITEMS","Fusion items must use the Key Items pocket") end
end
function M.createItem(S)
  local id="DNA_SPLICERS";local n=1
  while (S.project.items or {})[id] or (S.data.items or {})[id] do n=n+1;id="DNA_SPLICERS_"..n end
  local rec=require("Gen3ContentAdapter").newRecord(S,"items",id)
  rec.name="DNA SPLICERS";rec.pocket="KEY_ITEMS";rec.fieldUse="key";rec.importance=2
  rec.price=0;rec.holdEffect=0;rec.holdEffectParam=0;rec.battleUsage=0;rec.registrability=0
  rec.description="Combines compatible Pokemon. Use again to separate them."
  S.project.items[id]=rec;return id
end
function M.draw(S,f,parent,row,selection,x,y,w,App)
  local K=require("Kit");local s=K.scale
  K.caption(x,y,"Fusion / separation key item");y=y+28*s
  require("ItemPicker").field(S,{x=x,y=y,w=w,h=30*s,current=f.fusionItem,title="FUSION KEY ITEM",tooltip="Reusable Key Item used on the base Pokemon, then its partner. Use on the fused Pokemon to split them; splitting needs a free party slot.",onPick=function(id)
    local rec=(S.project.items or {})[id] or (S.data.items or {})[id]
    if not rec or rec.pocket~="KEY_ITEMS" then S.status="Choose an item from the Key Items pocket";return end
    f.fusionItem=id;App.markDirty()
  end});y=y+40*s
  if K.button(x,y,260*s,30*s,"Create DNA Splicers key item",{kind="good",tooltip="Create and select a reusable fusion Key Item in this project. Give it to the player through an event; creating it does not add it to the player's Bag."}) then f.fusionItem=M.createItem(S);App.markDirty() end;y=y+42*s
  if selection>1 then
    K.caption(x,y,"Partner Pokemon for "..row.name);y=y+28*s
    require("SpeciesPicker").field(S,{x=x,y=y,w=w,h=30*s,current=row.partner,title="FUSION PARTNER",tooltip="Partner species that produces this fused form. Its individual record is stored and restored on separation. Leave unset for an additional special transformation, such as Ultra Burst after fusion.",onPick=function(id) row.partner=id;App.markDirty() end});y=y+42*s
  end
  K.caption(x,y,"Use the item on the base Pokemon, then choose its partner.");y=y+28*s
  K.caption(x,y,"Use it on the fused Pokemon to separate. One party slot must be free.");y=y+32*s
  return y
end
return M
