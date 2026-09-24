-- Canonical FireRed records behind the established species/item/move editors.
local M={}
local names={"pokemon","items","moves","trainers","encounters","text"}
local function copy(v) return require("src.mods.Merge").deepCopy(v) end
function M.prepare(S)
  if not S.project then return end
  local p=S.project
  S.data._gen3EditorContent=S.data._gen3EditorContent or {}
  p.gen3ContentWorkspaces=p.gen3ContentWorkspaces or {}
  for _,name in ipairs(names) do
    local base=S.data._gen3EditorContent[name]
    if not base then
      base=copy(require("Gen3").catalog(S.data,name))
      if name=="pokemon" then for _,rec in pairs(base) do rec.trueColor=true end end
      S.data._gen3EditorContent[name]=base
    end
    S.data[name]=base
    p[name]=p[name] or {}
    if not p.gen3ContentWorkspaces[name] then
      for id,patch in pairs((p.gen3 or {})[name] or {}) do
        if name=="text" then
          if p[name][id]==nil then p[name][id]=copy(patch) end
        else
        local value=copy(base[id] or {})
        for key,v in pairs(patch) do
          if (key=="baseStats" or key=="dexEntry" or name=="encounters" and (key=="land" or key=="grass" or key=="water" or key=="rocks" or key=="fishing")) and type(v)=="table" and not (((p.gen3Exact or {})[name] or {})[id]) then
            value[key]=value[key] or {};for field,child in pairs(v) do value[key][field]=copy(child) end
          else value[key]=copy(v) end
        end
        value._isNew=base[id]==nil
        if p[name][id]==nil then p[name][id]=value end
        end
      end
      p.gen3ContentWorkspaces[name]=true
    end
  end
end
function M.compile(p)
  local Schemas=require("src.mods.Schemas")
  p.gen3=p.gen3 or {};p.gen3Modes=p.gen3Modes or {};p.gen3Exact=p.gen3Exact or {}
  for _,name in ipairs(names) do
    if (p.gen3ContentWorkspaces or {})[name] then
      local records,modes,exact={},{},{}
      for id,rec in pairs(p[name] or {}) do
        if name=="text" then
          records[id]=copy(rec);modes[id]="override";exact[id]=true
        else
        local value={}
        for key in pairs(Schemas.REGISTRIES[name].gen3Fields) do value[key]=copy(rec[key]) end
        require("Gen3Types").compileRecord(p,name,value)
        records[id]=value;modes[id]=rec._isNew and "register" or "patch";exact[id]=true
        end
      end
      p.gen3[name],p.gen3Modes[name],p.gen3Exact[name]=records,modes,exact
    end
  end
end
function M.newRecord(S,name,id)
  M.prepare(S)
  local base=S.data[name];local template=base[name=="pokemon" and "BULBASAUR" or name=="moves" and "TACKLE" or "POTION"]
  -- 412 is Egg and 413..439 are reserved native Unown artwork slots.
  local rec=copy(template or {});local max=name=="pokemon" and 439 or 0
  for _,bag in ipairs({base,S.project[name]}) do for _,v in pairs(bag) do max=math.max(max,tonumber(v.index) or 0) end end
  rec.id,rec.name,rec.index,rec._isNew=id,id,max+1,true
  if name=="pokemon" then
    assert(rec.index<=require("Gen3SpeciesCapacity").limit,"No free species slots remain")
    local dex=0
    for _,bag in ipairs({base,S.project[name]}) do
      for _,v in pairs(bag) do dex=math.max(dex,tonumber(v.dex) or 0) end
    end
    rec.dex=dex+1
    rec.spriteShinyFront=require("Gen3Forms").spritePath(template,false,true)
    rec.spriteShinyBack=require("Gen3Forms").spritePath(template,true,true)
  end
  return rec
end
return M
