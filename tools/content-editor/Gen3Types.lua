local M={}
function M.ids(project)
  local ids,used={},{}
  for name,index in pairs(require("src.core.game3.battle.types").ID) do ids[name]=index;used[index]=name end
  for name,rec in pairs(project.types or {}) do
    if ids[name]==nil then
      local index=rec.index
      assert(type(index)=="number" and index%1==0 and index>=18 and index<=63,"Custom types need an index from 18 to 63")
      assert(not used[index],"Type index already used by "..tostring(used[index]))
      ids[name]=index;used[index]=name
    end
  end
  return ids
end
function M.nextIndex(project)
  local used={};for _,index in pairs(M.ids(project)) do used[index]=true end
  for index=18,63 do if not used[index] then return index end end
end
function M.compileRecord(project,name,value)
  if name~="pokemon" and name~="moves" then return end
  local ids=M.ids(project)
  local function resolve(id)
    if (project.types or {})[id] and ids[id]>=18 then return tostring(ids[id]) end
    assert(ids[id]~=nil or tonumber(id),"Unknown Pokemon type: "..tostring(id))
    return id
  end
  if name=="pokemon" then for i,id in ipairs(value.types or {}) do value.types[i]=resolve(id) end
  elseif value.type then value.type=resolve(value.type) end
end
return M
