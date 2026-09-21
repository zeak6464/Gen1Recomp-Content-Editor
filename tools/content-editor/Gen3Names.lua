local M={}
function M.map(id)
  local text=tostring(id or ""):gsub("^FR_",""):gsub("_"," "):lower()
  return (text:gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end))
end
function M.dialog(id,body)
  local text=tostring(body or ""):gsub("\\[nf]"," "):gsub("{CONTROL:%d+}",""):gsub("%s+"," "):match("^%s*(.-)%s*$")
  if text~="" then
    if #text>70 then text=text:sub(1,67):gsub("%s+%S*$","").."..." end
    return text
  end
  if tostring(id):match("^g3:") then return "Dialogue (no spoken text)" end
  return M.map(tostring(id):gsub("^Text_",""):gsub("(%l)(%u)","%1 %2"))
end
return M
