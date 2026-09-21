-- Runtime SaveSerializer deliberately rejects nil save values. The GBA
-- extractor uses explicit nil fields in warp tables. Normalize only nil
-- tokens outside strings/comments, then use the bounded data-only parser.
local M = {}
local Serializer = require("src.core.SaveSerializer")
local MARK = "__content_editor_nil_literal_7cf1"

function M.decode(bytes, limits)
  if type(bytes)~="string" then return nil,"Expected Lua data text" end
  if #bytes>((limits or {}).maxBytes or 16*1024*1024) then return nil,"Lua data exceeds size limit" end
  local value, err = Serializer.decode(bytes, limits)
  if not value and bytes:find("local M =",1,true) then
    local result, ended
    for line in bytes:gmatch("[^\r\n]+") do
      line=line:match("^%s*(.-)%s*$")
      if line ~= "" and line:sub(1,2) ~= "--" then
        if ended then return nil,"Unexpected data after return M" end
        local init=line:match("^local M%s*=%s*(.+)$")
        if init and not result then
          result,err=M.decode("return "..init,limits)
          if not result then return nil,err end
        elseif line == "return M" and result then ended=true
        else
          local field,key,rhs=line:match("^M%.([%w_]+)%[([^%]]+)%]%s*=%s*(.+)$")
          if not (result and field and type(result[field])=="table") then return nil,"Unsupported generated statement: "..line:sub(1,80) end
          local box,problem=M.decode("return {key="..key..",value="..rhs.."}",limits)
          if not box or (type(box.key)~="number" and type(box.key)~="string") then return nil,problem or "Invalid generated key" end
          result[field][box.key]=box.value
        end
      end
    end
    if ended then return result end
    return nil,"Missing return M"
  end
  if value or not tostring(err):find("unexpected name 'nil'",1,true) then return value,err end
  local out, pos = {}, 1
  while pos <= #bytes do
    local c = bytes:sub(pos,pos)
    if c == '"' or c == "'" then
      local start, quote = pos, c
      pos = pos+1
      while pos <= #bytes do
        local ch = bytes:sub(pos,pos)
        if ch == "\\" then pos=pos+2
        elseif ch == quote then pos=pos+1;break
        else pos=pos+1 end
      end
      out[#out+1]=bytes:sub(start,pos-1)
    elseif bytes:sub(pos,pos+1)=="--" then
      local ending=bytes:find("\n",pos,true) or #bytes
      out[#out+1]=bytes:sub(pos,ending);pos=ending+1
    elseif c:match("[%a_]") then
      local word=bytes:match("^[%w_]+",pos)
      out[#out+1]=word=="nil" and ('{["'..MARK..'"]=true}') or word
      pos=pos+#word
    else out[#out+1]=c;pos=pos+1 end
  end
  value,err=Serializer.decode(table.concat(out),limits)
  if not value then return nil,err end
  local function clean(t)
    for key,child in pairs(t) do
      if type(child)=="table" then
        if child[MARK] == true and next(child)==MARK and next(child,MARK)==nil then t[key]=nil else clean(child) end
      end
    end
  end
  clean(value)
  return value
end

return M
