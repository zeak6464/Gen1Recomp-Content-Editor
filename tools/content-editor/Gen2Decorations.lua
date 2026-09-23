local M={}
local function resolved(S,id)
  return (S.project.decorations or {})[tostring(id)]
    or (S.data.gen2Decorations or {})["deco:"..id]
    or require("src.core.gen2.Decorations").ATTRIBUTES[tonumber(id)]
end
function M.choices(S)
  local ids,labels={},{}
  local suffix={[2]=" BED",[3]=" CARPET",[4]=" POSTER",[5]=" DOLL",[6]=" BIG DOLL"}
  for id,attr in pairs(require("src.core.gen2.Decorations").ATTRIBUTES) do
    if attr.action and attr.action:match("^SET_UP_") then
      local key=tostring(id);local row=resolved(S,key)
      ids[#ids+1]=key;labels[key]=row.name..(suffix[row.type] or "")
    end
  end
  table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
  return ids,labels
end
function M.validate(rows)
  for id,row in pairs(rows or {}) do
    local original=require("src.core.gen2.Decorations").ATTRIBUTES[tonumber(id)]
    assert(original and original.action and original.action:match("^SET_UP_"),"Unknown collectible decoration")
    assert(type(row.name)=="string" and row.name:match("%S"),"Enter a decoration name")
    assert(type(row.sprite)=="number" and row.sprite%1==0 and row.sprite>=0 and row.sprite<=255,"Decoration artwork number must be 0 to 255")
    assert(row.type==original.type and row.action==original.action and row.flag==original.flag,"Decoration category and ownership flags must be preserved")
  end
end
function M.emit(p,encode,out)
  if not next(p.decorations or {}) then return end
  M.validate(p.decorations)
  out[#out+1]="if mod.generation == 2 then"
  local ids={};for id in pairs(p.decorations or {}) do ids[#ids+1]=id end;table.sort(ids)
  for _,id in ipairs(ids) do
    local row=p.decorations[id]
    out[#out+1]="mod.content.decorations:patch("..string.format("%q","deco:"..id)..","..encode({name=row.name,sprite=row.sprite})..")"
  end
  out[#out+1]="end"
end
function M.draw(S,x,y,w,h,App)
  local K,L=require("Kit"),require("RegList");local s=K.scale
  local ids,labels=M.choices(S)
  local fx,fw=L.drawList(S,App,x,y,w,h,"BEDROOM DECORATIONS",ids,{selKey="decorationId",queryKey="decorationQuery",offsetKey="decorationOffset",label=function(id) return labels[id] end})
  S.decorationId=S.decorationId or ids[1];local id=S.decorationId;local row=id and resolved(S,id)
  if not row then return end
  local function set(key,value)
    S.project.decorations=S.project.decorations or {}
    if not S.project.decorations[id] then S.project.decorations[id]=require("src.mods.Merge").deepCopy(row) end
    S.project.decorations[id][key]=value;App.markDirty()
  end
  K.caption(fx,y,labels[id]);y=y+40*s
  K.caption(fx,y,"Name (category suffix is added in game)");y=y+25*s
  local name=K.textfield("decoration/"..id.."/name",fx,y,fw,30*s,row.name,"")
  if name~=row.name then set("name",name) end;y=y+48*s
  local object=row.action=="SET_UP_DOLL" or row.action=="SET_UP_BIG_DOLL" or row.action=="SET_UP_CONSOLE"
  K.caption(fx,y,object and "Overworld sprite number (0-255)" or "Bedroom tileset block number (0-255)");y=y+25*s
  local sprite=L.num(App,"decoration/"..id.."/sprite",fx,y,140*s,30*s,row.sprite)
  if sprite~=row.sprite then set("sprite",sprite) end;y=y+50*s
  K.caption(fx,y,"Give this decoration through Events > Gifts.");y=y+30*s
  K.caption(fx,y,"Players arrange owned decorations with their bedroom PC.");y=y+30*s
  K.caption(fx,y,"Artwork changes appear when the bedroom map reloads.");y=y+45*s
  if (S.project.decorations or {})[id] and K.button(fx,y,150*s,30*s,"Revert decoration",{}) then S.project.decorations[id]=nil;App.markDirty() end
end
return M
