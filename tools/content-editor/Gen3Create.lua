local M={}
function M.create(S,kind,source)
  local A=require("Gen3ContentAdapter");A.prepare(S)
  local base=S.project[kind][source] or S.data[kind][source];assert(base,"Choose a starting point")
  local stem=kind=="moves" and "NEW_MOVE" or "NEW_ITEM";local id=stem;local n=1
  while S.project[kind][id] or S.data[kind][id] do n=n+1;id=stem.."_"..n end
  local fresh=A.newRecord(S,kind,id);local rec=require("src.mods.Merge").deepCopy(base)
  rec.id,rec.index,rec.name,rec._isNew=id,fresh.index,"New "..(base.name or source):lower(),true
  if kind=="moves" then
    local key="moves/"..base.index
    local anim=(S.project.gen3Animations or {})[key] or require("Gen3Resources").animations(S.data)[key]
    if anim then S.project.gen3Animations=S.project.gen3Animations or {};S.project.gen3Animations["moves/"..rec.index]=require("src.mods.Merge").deepCopy(anim) end
    S.moveId=id;S.moveFormScroll=0
  else
    if source=="POTION" then rec.fieldUse="heal";rec.holdEffectParam=20 end
    local IO=require("ModIO")
    local key="data/generated/gba/items/bag/icons/"..base.index..".rgba"
    local asset=(S.project.gen3Assets or {})[key]
    local bytes=asset and IO.readText(S.path.."/"..asset.file) or S.data._gen3Read(key)
    if bytes and S.path then
      local rel="assets/gen3/items/"..rec.index..".rgba"
      assert(IO.ensureDirectory(S.path.."/assets/gen3/items"))
      assert(IO.writeText(S.path.."/"..rel,bytes))
      S.project.gen3Assets=S.project.gen3Assets or {}
      S.project.gen3Assets["data/generated/gba/items/bag/icons/"..rec.index..".rgba"]={file=rel,width=24,height=24}
    end
    S.itemId=id;S.itemFormScroll=0
  end
  S.project[kind][id]=rec
  S.status="Created "..rec.name..". Set its name and values, then Save."
  return rec
end
function M.open(S,kind,App)
  local ids,labels={},{}
  if kind=="moves" then
    ids=require("RegList").mergeIds(S.project.moves,S.data.moves)
    for _,id in ipairs(ids) do local rec=S.project.moves[id] or S.data.moves[id];labels[id]=(rec.name or id).." - "..(rec.type or "NORMAL") end
  else
    ids={"POTION","LEFTOVERS","NUGGET","CARD_KEY"}
    labels={POTION="Healing medicine - restores 20 HP",LEFTOVERS="Held item - start from Leftovers",NUGGET="Collectible - an item to sell",CARD_KEY="Key item - important, not usable"}
  end
  require("ChoicePicker").open(S,{ids=ids,labels=labels,title=kind=="moves" and "NEW MOVE - CHOOSE A MOVE TO START FROM" or "NEW ITEM - CHOOSE A STARTING POINT",onPick=function(id) M.create(S,kind,id);App.markDirty() end})
end
return M
