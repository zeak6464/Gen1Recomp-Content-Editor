local M={}
function M.natural(a,b)
  local function key(s) return tostring(s):gsub("%d+",function(n) return string.format("%012d",tonumber(n)) end) end
  return key(a)<key(b)
end
function M.map(id)
  local g,n=tostring(id):match("^(%d+):(%d+)$")
  if g then id=require("src.import.gba.map_catalog").mapIdFor(g,n) or id end
  return tostring(id):gsub("^FR_",""):gsub("^SEVII_",""):gsub("_"," ")
end
function M.scriptMaps(S)
  local result={};local scripts=require("Gen3").catalog(S.data,"map_scripts")
  for map,rec in pairs(S.data.maps or {}) do
    local seen={}
    local function visit(v,depth)
      if depth>40 then return end
      if type(v)=="table" then for _,c in pairs(v) do visit(c,depth+1) end
      elseif type(v)=="string" and scripts[v] and not seen[v] then
        seen[v]=true;result[v]=result[v] or {};result[v][map]=true;visit(scripts[v],depth+1)
      end
    end
    for _,kind in ipairs({"objects","bgEvents","coordEvents","mapScripts"}) do visit(rec[kind],0) end
  end
  return result
end
return M
