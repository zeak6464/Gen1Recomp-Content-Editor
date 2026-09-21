-- Structured, schema-aware fields shared by Gen 3 record and script editors.
local Kit=require("Kit")
local Writer=require("ModWriter")
local Decode=require("Gen3Decode")
local M={}

local function unwrap(spec)
  while spec and spec.kind=="opt" do spec=spec.inner end
  return spec
end
function M.default(spec)
  spec=unwrap(spec) or {}
  if spec.kind=="enum" then return spec.values[1] end
  if spec.kind=="list" or spec.kind=="map" then return {} end
  if spec.kind=="any" then return {} end
  if spec.fields then
    local t={}
    for key,child in pairs(spec.fields) do if child.kind~="opt" then t[key]=M.default(child) end end
    return t
  end
  if spec.kind=="bool" then return false end
  if spec.kind=="int" or spec.kind=="number" or spec.kind=="num" then return 1 end
  return ""
end

function M.draw(S, identity, x, y, w, drafts, fields)
  S._g3Expanded=S._g3Expanded or {}
  local s=Kit.scale
  local function walk(parent,key,spec,path,depth)
    local value=parent[key]
    spec=unwrap(spec)
    local xx=x+depth*14*s
    local ww=w-depth*14*s
    local label=tostring(key)
    if type(value)=="table" then
      local opened=S._g3Expanded[path]
      if Kit.button(xx,y,math.max(70*s,ww-70*s),26*s,(opened and "- " or "+ ")..label.." ("..tostring(#value)..")",{kind="ghost"}) then
        opened=not opened;S._g3Expanded[path]=opened
      end
      local list=(spec and spec.kind=="list") or value[1]~=nil
      if list and Kit.button(xx+ww-64*s,y,60*s,26*s,"+ Row",{}) then
        local template=value[#value]
        value[#value+1]=template and require("src.mods.Merge").deepCopy(template) or M.default(spec and spec.inner)
        opened=true;S._g3Expanded[path]=true
      end
      y=y+32*s
      if opened then
        local keys={};for child in pairs(value) do keys[#keys+1]=child end
        table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end return tostring(a)<tostring(b) end)
        local remove,swap
        for _,child in ipairs(keys) do
          local childSpec=spec and (spec.fields and spec.fields[child] or spec.inner or spec.value)
          if list and type(child)=="number" then
            if Kit.button(xx,y,24*s,24*s,"x",{kind="ghost"}) then remove=child end
            if child>1 and Kit.button(xx+30*s,y,35*s,24*s,"Up",{}) then swap={child,child-1} end
            if child<#value and Kit.button(xx+70*s,y,48*s,24*s,"Down",{}) then swap={child,child+1} end
            y=y+27*s
          end
          walk(value,child,childSpec,path.."/"..tostring(child),depth+1)
        end
        if remove then table.remove(value,remove) end
        if swap then value[swap[1]],value[swap[2]]=value[swap[2]],value[swap[1]] end
        if spec and spec.fields then
          local missing={};for field in pairs(spec.fields) do if value[field]==nil then missing[#missing+1]=field end end
          table.sort(missing)
          for _,field in ipairs(missing) do
            if Kit.button(xx+14*s,y,math.min(ww-14*s,280*s),25*s,"+ "..field,{kind="ghost"}) then value[field]=M.default(spec.fields[field]) end
            y=y+29*s
          end
        end
        if not list then
          local addpath=identity.."/"..path
          if Kit.button(xx,y,140*s,25*s,"+ Custom field",{kind="ghost"}) then S._g3AddPath=addpath;S._g3AddKey="";S._g3AddValue='""' end
          y=y+30*s
          if S._g3AddPath==addpath then
            S._g3AddKey=Kit.textfield("addkey/"..addpath,xx,y,ww*.4,26*s,S._g3AddKey,"Field name")
            S._g3AddValue=Kit.textfield("addvalue/"..addpath,xx+ww*.42,y,ww*.58,26*s,S._g3AddValue,"Lua value: 0, true, {}, ...")
            y=y+31*s
            if Kit.button(xx,y,85*s,25*s,"Add",{}) then
              local box,err=Decode.decode("return {value="..S._g3AddValue.."}",{allowArray=true})
              if box and box.value~=nil and S._g3AddKey~="" then value[tonumber(S._g3AddKey) or S._g3AddKey]=box.value;S._g3AddPath=nil
              else S.status=tostring(err or "Enter a field name and value") end
            end
            if Kit.button(xx+96*s,y,85*s,25*s,"Cancel",{}) then S._g3AddPath=nil end
            y=y+30*s
          end
        end
      end
    else
      Kit.caption(xx,y,label);y=y+20*s
      if type(value)=="boolean" then
        if Kit.button(xx,y,100*s,26*s,value and "Yes" or "No",{}) then parent[key]=not value end
      elseif spec and spec.kind=="enum" then
        if Kit.button(xx,y,math.min(300*s,ww),26*s,tostring(value),{}) then
          local index=0;for i,v in ipairs(spec.values) do if v==value then index=i end end
          parent[key]=spec.values[index%#spec.values+1]
        end
      else
        local text=Kit.textfield("g3field/"..identity.."/"..path,xx,y,ww,27*s,tostring(value or ""),label)
        if type(value)=="number" then parent[key]=tonumber(text) or value else parent[key]=text end
      end
      y=y+35*s
    end
  end
  local keys={};for key in pairs(drafts) do keys[#keys+1]=key end;table.sort(keys)
  for _,key in ipairs(keys) do
    local box=Decode.decode("return {value="..drafts[key].."}",{allowArray=true})
    if box and box.value~=nil then
      local holder={[key]=box.value}
      walk(holder,key,fields and fields[key],key,0)
      drafts[key]=Writer.encodeLua(holder[key]):gsub("\n%s*"," ")
    else
      Kit.caption(x,y,key.." — Lua value");y=y+20*s
      drafts[key]=Kit.textfield("g3raw/"..identity.."/"..key,x,y,w,27*s,drafts[key],"Lua data")
      y=y+35*s
    end
  end
  return y
end

return M
