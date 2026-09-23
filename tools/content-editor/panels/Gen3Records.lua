local Kit = require("Kit")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Gen3 = require("Gen3")
local Writer = require("ModWriter")
local Serializer = require("Gen3Decode")
local Panel = {}

local function decode(source)
  local box, err = Serializer.decode("return { value = " .. source .. " }", { allowArray = true })
  return box and box.value, err
end

local function overlay(base, patch)
  local result = {}
  for key, value in pairs(base or {}) do result[key] = value end
  for key, value in pairs(patch or {}) do
    if type(value) == "table" and type(result[key]) == "table" and value[1] == nil then
      result[key] = overlay(result[key], value)
    else result[key] = value end
  end
  return result
end

local function literal(value)
  return Writer.encodeLua(value):gsub("\n%s*", " ")
end

function Panel.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local name = Gen3.tabs[S.tab]
  if not name then
    Kit.caption(x, y, "This workspace has no Gen 3 adapter yet.")
    Kit.caption(x, y + 28*s, "Use Pokemon, Moves, Items, Trainers, Encounters, Maps, Dialog or Events.")
    return
  end
  if not S.project then Kit.caption(x, y, "Create or open a Gen 3 mod on Project first."); return end
  S._gen3Catalog = S._gen3Catalog or {}
  local ok, catalog = true, S._gen3Catalog[name]
  if not catalog then
    ok, catalog = pcall(Gen3.catalog, S.data or {}, name)
    if ok then S._gen3Catalog[name] = catalog end
  end
  if not ok then Kit.caption(x, y, tostring(catalog)); return end
  local Schemas=require("src.mods.Schemas")
  local spec=Schemas.shapeFor(name,Schemas.REGISTRIES[name],3)
  if name=="maps" then
    spec=require("src.mods.Merge").deepCopy(spec)
    for _,key in ipairs({"bgEvents","coordEvents"}) do spec.fields[key]={kind="list",inner={kind="any"}} end
    spec.fields.mapScripts={kind="map",value={kind="any"}}
    spec.fields.music={kind="int"};spec.fields.weather={kind="int"}
  end
  local patches = (S.project.gen3 or {})[name] or {}
  local modes=((S.project.gen3Modes or {})[name] or {})
  local ids = RegList.mergeIds(patches, catalog)
  local fx, fw = RegList.drawList(S, App, x, y, w, h, "Gen 3 " .. name, ids,
    { selKey = "gen3Id", queryKey = "gen3Query", offsetKey = "gen3Offset",
      footerLabel = name ~= "maps" and "New / duplicate" or nil,
      onFooter=function() S._g3Create=name end })
  if S._g3Create==name then
    Kit.caption(fx,y,"New record ID")
    S.g3NewId=Kit.textfield("g3NewId",fx,y+28*s,fw,28*s,S.g3NewId or "","NEW_ID")
    if Kit.button(fx,y+68*s,120*s,28*s,"Create",{kind="primary"}) then
      local newid=S.g3NewId
      if newid and newid:match("^[%w_:%-]+$") and not catalog[newid] and not patches[newid] then
        local value
        if name=="text" then value="New dialog"
        elseif name=="map_scripts" then value={{op="end"}}
        else
          local source=catalog[S.gen3Id]
          value=source and require("src.mods.Merge").deepCopy(source) or require("Gen3Fields").default({fields=spec.fields})
          value.id=newid
          if value.name then value.name=newid end
          if value.index then
            local maximum=0;for _,rec in pairs(catalog) do maximum=math.max(maximum,tonumber(rec.index) or 0) end
            value.index=maximum+1
          end
        end
        S.project.gen3=S.project.gen3 or {};S.project.gen3[name]=S.project.gen3[name] or {}
        S.project.gen3[name][newid]=value
        S.project.gen3Modes=S.project.gen3Modes or {};S.project.gen3Modes[name]=S.project.gen3Modes[name] or {}
        S.project.gen3Modes[name][newid]="register"
        S.gen3Id=newid;S._g3Create=nil;S._g3Identity=nil;App.markDirty()
      else S.status="Choose an unused record ID" end
    end
    if Kit.button(fx+135*s,y+68*s,120*s,28*s,"Cancel",{}) then S._g3Create=nil end
    return
  end
  local id = S.gen3Id
  if not id or (catalog[id] == nil and patches[id] == nil) then
    Kit.caption(fx, y, "Select a record. Import a FireRed or LeafGreen ROM if the list is empty."); return
  end
  local identity = name .. "/" .. id
  -- Rebuild drafts after undo/redo or a data reload as well as selection changes.
  if S._g3Identity ~= identity or S._g3Project ~= S.project or S._g3Data ~= S.data
      or S._g3Patch ~= patches[id] then
    S._g3Identity, S._g3Project, S._g3Data, S._g3Patch = identity, S.project, S.data, patches[id]
    S._g3Draft, S._g3Original = {}, {}
    local base = catalog[id]
    local rootValue = name == "text" or name == "map_scripts"
    if rootValue then
      S._g3Draft.value = literal(patches[id] or base)
    else
      local effective=overlay(base,patches[id])
      if modes[id]=="override" or modes[id]=="register" then effective=patches[id] or base
      elseif ((S.project.gen3Exact or {})[name] or {})[id] then
        effective={};for k,v in pairs(base or {}) do effective[k]=v end
        for k,v in pairs(patches[id] or {}) do effective[k]=v end
      end
      for key, value in pairs(effective or {}) do S._g3Draft[key] = literal(value) end
    end
    for key, value in pairs(S._g3Draft) do S._g3Original[key] = value end
    S._g3Error = nil
  end
  Kit.caption(fx, y, id .. " — Gen 3 record fields")
  Kit.caption(fx, y + 24*s, "Edit fields, expand lists, then Apply record and Save.")
  local by = y + 52*s
  if Kit.button(fx, by, 130*s, 28*s, "Apply record", { kind = "primary" }) then
    local payload = {}
    if type(patches[id]) == "table" then
      for key, value in pairs(patches[id]) do payload[key] = value end
    end
    local valid, errorText = true, nil
    for key, source in pairs(S._g3Draft) do
      if source ~= S._g3Original[key] then
        local value, err = decode(source)
        if value == nil then valid, errorText = false, tostring(err); break end
        payload[key] = value
      end
    end
    if name == "text" or name == "map_scripts" then
      payload, errorText = decode(S._g3Draft.value)
      valid = payload ~= nil
    end
    local operation=modes[id]
    if operation=="override" or operation=="register" then
      if name~="text" and name~="map_scripts" then
        payload={}
        for key,source in pairs(S._g3Draft) do
          local value,err=decode(source)
          if value==nil then valid,errorText=false,err;break end
          payload[key]=value
        end
      end
    end
    if valid then valid, errorText = Gen3.check(name, id, payload, operation) end
    if valid then
      S.project.gen3 = S.project.gen3 or {}
      S.project.gen3[name] = S.project.gen3[name] or {}
      S.project.gen3[name][id] = payload
      S.project.gen3Exact=S.project.gen3Exact or {};S.project.gen3Exact[name]=S.project.gen3Exact[name] or {}
      S.project.gen3Exact[name][id]=true
      App.markDirty()
      S.status = "Applied " .. id .. "; Save to write the mod"
      S._g3Identity = nil
    else S._g3Error = tostring(errorText) end
  end
  if Kit.button(fx + 142*s, by, 130*s, 28*s, "Reset draft", { kind = "ghost" }) then
    S._g3Identity = nil
  end
  if Kit.button(fx+284*s,by,125*s,28*s,"Revert edits",{kind="ghost"}) then
    if S.project.gen3 and S.project.gen3[name] then S.project.gen3[name][id]=nil end
    if S.project.gen3Modes and S.project.gen3Modes[name] then S.project.gen3Modes[name][id]=nil end
    S._g3Identity=nil;App.markDirty()
  end
  if Kit.button(fx+421*s,by,110*s,28*s,S.g3Raw and "Form view" or "Lua view",{}) then S.g3Raw=not S.g3Raw end
  if S._g3Error then Kit.caption(fx, by + 32*s, S._g3Error) end
  FormPane.track(S, "gen3Scroll", identity)
  local top, view = FormPane.begin(S, "gen3Scroll", fx, by + 62*s, fw, math.max(40*s, h - 114*s))
  local row = top
  if S.g3Raw then
  for _, key in ipairs(RegList.sortedKeys(S._g3Draft)) do
    Kit.caption(fx, row, tostring(key))
    row = row + 22*s
    S._g3Draft[key] = Kit.textfield("g3/" .. identity .. "/" .. key,
      fx, row, view.contentW, 28*s, S._g3Draft[key], "Lua data value")
    row = row + 38*s
  end
  else
    local fields=(name=="text" or name=="map_scripts") and {value=spec.value} or spec.fields
    row=require("Gen3Fields").draw(S,identity,fx,row,view.contentW,S._g3Draft,fields)
    for _,key in ipairs(RegList.sortedKeys(fields or {})) do
      if S._g3Draft[key]==nil then
        if Kit.button(fx,row,260*s,26*s,"+ "..key,{kind="ghost"}) then
          S._g3Draft[key]=literal(require("Gen3Fields").default(fields[key]))
        end
        row=row+31*s
      end
    end
  end
  FormPane.finish(S, "gen3Scroll", top, row, view)
end

return Panel
