-- Offline event rewards for all three engines; no link hardware required.
local M = {}
local function encode(v) return require("ModWriter").encodeLua(v) end
local function copy(v) return require("src.mods.Merge").deepCopy(v) end
function M.key(p, id)
  -- Hex-escape punctuation and underscores so distinct mod IDs cannot collide.
  local owner=p.id:gsub("[^%w]",function(c) return string.format("_%02X",c:byte()) end)
  return "EditorGift_" .. owner .. "_" .. id
end

function M.new(S)
  local p = S.project
  p.offlineGifts = p.offlineGifts or {}
  local n = p.nextOfflineGift or 1
  while p.offlineGifts["GIFT_" .. n] do n = n + 1 end
  local id = "GIFT_" .. n; p.nextOfflineGift = n + 1
  p.offlineGifts[id] = {title="A special gift", kind="item", item="POTION", quantity=1,
    species="PIKACHU", level=5, decoration=31, enabled=true,
    message="Please enjoy your gift!", done="You have already collected this gift.",
    full="Make room in your Bag or party, then come back.", unavailable="This gift is not available.",
    map=S.mapId or "", textId="TEXT_EDITOR_" .. id}
  return id
end

function M.validate(rows, generation)
  for id, row in pairs(rows or {}) do
    assert(type(id)=="string" and id:match("^[%w_]+$"), "Invalid gift ID")
    for _,key in ipairs({"title","message","done","full","unavailable"}) do
      assert(type(row[key])=="string" and row[key]:match("%S"), "Enter gift " .. key)
    end
    assert(row.kind=="item" or row.kind=="pokemon" or (row.kind=="decoration" and generation==2), "This reward type is not supported by the selected game")
    if row.kind=="item" then
      assert(type(row.item)=="string" and row.item~="", "Choose a reward item")
      assert(type(row.quantity)=="number" and row.quantity%1==0 and row.quantity>=1 and row.quantity<=99, "Gift quantities must be 1 to 99")
    elseif row.kind=="pokemon" then
      assert(type(row.species)=="string" and row.species~="", "Choose a reward Pokemon")
      assert(type(row.level)=="number" and row.level%1==0 and row.level>=1 and row.level<=100, "Gift levels must be 1 to 100")
    else
      local attr=require("src.core.gen2.Decorations").ATTRIBUTES[row.decoration]
      assert(attr and attr.action and attr.action:match("^SET_UP_"), "Choose a collectible decoration")
    end
  end
end

-- Build is explicit and preserves scripts/dialogue subsequently edited by hand.
function M.build(S, id)
  local p=S.project; local row=p.offlineGifts[id]; local gen=require("Generation").num(S)
  local ok,err=pcall(M.validate,{[id]=row},gen); if not ok then return nil,err end
  if row.kind=="item" and not ((p.items or {})[row.item] or (S.data.items or {})[row.item]) then return nil,"Unknown reward item" end
  if row.kind=="pokemon" and not ((p.pokemon or {})[row.species] or (S.data.pokemon or {})[row.species]) then return nil,"Unknown reward Pokemon" end
  local key=M.key(p,id); local scripts,text={},{}
  if gen==3 then
    scripts[key]={{op="lock"},{op="faceplayer"},{op="editor_offline_gift",owner=p.id,gift=id}}
    for code,label in ipairs({"message","done","full"}) do
      table.insert(scripts[key],{op="compare_var_to_value",var=0x800D,value=code})
      table.insert(scripts[key],{op="goto_if",cond=1,target=key.."_"..label})
    end
    table.insert(scripts[key],{op="goto",target=key.."_unavailable"})
    for _,label in ipairs({"message","done","full","unavailable"}) do
      local ptr=key.."_Text_"..label
      text[ptr]=require("Gen3Dialog").encode(label=="message" and (row.title.."\n"..row.message) or row[label])
      scripts[key.."_"..label]={{op="message",ptr=ptr},{op="waitmessage"},{op="waitbuttonpress"},{op="closemessage"},{op="release"},{op="end"}}
    end
    local existing=(p.gen3 or {}).map_scripts or {}
    local catalog=require("Gen3").catalog(S.data,"map_scripts")
    for name,value in pairs(scripts) do
      if catalog[name] then return nil,"A game script already uses "..name end
      if existing[name] and encode(existing[name])~=encode((row._scripts or {})[name]) then return nil,"Manual script edits preserved: "..name end
    end
    for name,value in pairs(text) do
      if p.text[name] and encode(p.text[name])~=encode((row._text or {})[name]) then return nil,"Manual dialogue edits preserved: "..name end
    end
    p.gen3=p.gen3 or {};p.gen3.map_scripts=existing
    p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
    for name,value in pairs(scripts) do existing[name]=value;p.gen3Modes.map_scripts[name]="register" end
    for name,value in pairs(text) do p.text[name]=value end
  elseif gen==2 then
    local value={{op="faceplayer"},{op="opentext"},{op="modcommand",verb=p.id..":offline_gift",args={id}},
      {op="waitbutton"},{op="closetext"},{op="end"}}
    p.scripts=p.scripts or {}
    if not row._scripts and (S.data.scripts or {})[key] then return nil,"A game script already uses "..key end
    local draft=(p.scriptSteps or {})[key]
    if draft then
      local compiled=require("Gen2Talk").stepsToCmds(S,key,draft.steps)
      if encode(compiled)~=encode((row._scripts or {})[key]) then return nil,"Manual event steps preserved: "..key end
    end
    if p.scripts[key] and encode(p.scripts[key])~=encode((row._scripts or {})[key]) then return nil,"Manual script edits preserved: "..key end
    p.scripts[key]=value;scripts[key]=value
  else
    if not ((p.maps or {})[row.map] or (S.data.maps or {})[row.map]) then return nil,"Choose the delivery NPC's map" end
    if type(row.textId)~="string" or not row.textId:match("^TEXT_[%w_]+$") then return nil,"Choose a TEXT_ identifier for the delivery NPC" end
    key=row.map.."/"..row.textId
    if row._binding and row._binding~=key then return nil,"This gift is already bound to "..row._binding.."; create another gift for a different NPC" end
    local value={mapId=row.map,textId=row.textId,steps={{kind="face_player"},{kind="raw",row={p.id..":offline_gift",id}}}}
    p.talkScripts=p.talkScripts or {}
    if (p.talkScripts[key] and encode(p.talkScripts[key])~=encode((row._scripts or {})[key]))
      or (((p.map_scripts or {})[row.map] or {}).talk or {})[row.textId] then return nil,"Existing event preserved: "..key end
    p.talkScripts[key]=value;scripts[key]=value;row._binding=key
  end
  row._scripts=copy(scripts);row._text=copy(text)
  return key
end

function M.emit(p, encodeLua, out, generation)
  if not next(p.offlineGifts or {}) then return end
  M.validate(p.offlineGifts,generation)
  local rows={}
  for id,row in pairs(p.offlineGifts) do
    rows[id]={}
    for k,v in pairs(row) do if k:sub(1,1)~="_" then rows[id][k]=v end end
  end
  out[#out+1]="local offlineGifts=(function()\n"..assert(love.filesystem.read("tools/content-editor/OfflineGiftsRuntime.lua")).."\nend)()"
  out[#out+1]="offlineGifts.install(mod,"..encodeLua(rows)..","..generation..")"
end

function M.draw(S,x,y,w,h,App)
  local K,L,C=require("Kit"),require("RegList"),require("ChoicePicker")
  local s=K.scale;local gen=require("Generation").num(S)
  if gen==3 then require("Gen3ContentAdapter").prepare(S) end
  local rows=S.project.offlineGifts or {};local ids=L.sortedKeys(rows)
  local fx,fw=L.drawList(S,App,x,y,w,h,"OFFLINE GIFTS",ids,{selKey="offlineGiftId",queryKey="offlineGiftQuery",offsetKey="offlineGiftOffset",
    label=function(id) return rows[id].title end,footerLabel="New gift",onFooter=function() S.offlineGiftId=M.new(S);App.markDirty() end})
  local id=S.offlineGiftId;local row=id and (S.project.offlineGifts or {})[id]
  if not row then K.caption(fx,y,"Create a gift, build its delivery script, then assign it to an NPC on Maps.");return end
  K.caption(fx,y,id.." - once per save, collected by talking to the delivery NPC")
  if K.button(fx,y+28*s,160*s,28*s,"Build delivery script",{kind="good"}) then
    local key,err=M.build(S,id);S.status=key and ("Built "..key..". Assign it to a delivery NPC on Maps.") or err
    if key then App.markDirty() end
  end
  if K.button(fx+175*s,y+28*s,150*s,28*s,row.enabled==false and "Enable gift" or "Disable gift",{}) then row.enabled=row.enabled==false;App.markDirty() end
  local Pane=require("FormPane");Pane.track(S,"offlineGiftForm",id)
  local first,view=Pane.begin(S,"offlineGiftForm",fx,y+70*s,fw,h-70*s);local yy=first;local width=view.contentW
  K.caption(fx,yy,gen==3 and "Offline NPC delivery; native Wonder Card / wireless menus are not available." or "No link hardware needed. Disabling a gift keeps its claim history.");yy=yy+32*s
  local function text(key,label)
    K.caption(fx,yy,label);yy=yy+22*s
    local value=K.textfield("offlineGift/"..id.."/"..key,fx,yy,width,28*s,row[key] or "","")
    if value~=row[key] then row[key]=value;App.markDirty() end;yy=yy+38*s
  end
  text("title","Gift title")
  K.caption(fx,yy,"Reward")
  C.field(S,{x=fx+170*s,y=yy,w=width-170*s,h=28*s,current=row.kind,ids=gen==2 and {"item","pokemon","decoration"} or {"item","pokemon"},
    labels={item="Item",pokemon="Pokemon",decoration="Bedroom decoration"},title="Reward type",onPick=function(v) row.kind=v;App.markDirty() end});yy=yy+40*s
  local function number(key,label)
    K.caption(fx,yy,label);local v=L.num(App,"offlineGift/"..id.."/"..key,fx+170*s,yy,130*s,28*s,row[key])
    if v~=row[key] then row[key]=v;App.markDirty() end;yy=yy+38*s
  end
  if row.kind=="decoration" then
    local options,labels=require("Gen2Decorations").choices(S)
    C.field(S,{x=fx,y=yy,w=width,h=28*s,current=tostring(row.decoration),ids=options,labels=labels,title="Decoration reward",onPick=function(v) row.decoration=tonumber(v);App.markDirty() end});yy=yy+40*s
    K.caption(fx,yy,"After collecting, use the bedroom PC to place your decoration.");yy=yy+32*s
  else
    local key=row.kind=="item" and "item" or "species"
    require(row.kind=="item" and "ItemPicker" or "SpeciesPicker").field(S,{x=fx,y=yy,w=width,h=28*s,current=row[key],onPick=function(v) row[key]=v;App.markDirty() end});yy=yy+40*s
    if row.kind=="item" then number("quantity","Quantity (1-99)") else number("level","Level (1-100)") end
  end
  text("message","Received dialogue");text("done","Already collected");text("full","Bag / party full");text("unavailable","Gift disabled / unavailable")
  if gen==1 then
    K.caption(fx,yy,"Delivery map");yy=yy+24*s
    local maps=L.mergeIds(S.project.maps or {},S.data.maps or {});local names={}
    for _,map in ipairs(maps) do names[map]=map:gsub("_"," ") end
    C.field(S,{x=fx,y=yy,w=width,h=28*s,current=row.map,ids=maps,labels=names,title="Delivery map",onPick=function(v) row.map=v;App.markDirty() end});yy=yy+40*s
    text("textId","Delivery NPC TEXT_ identifier")
    K.caption(fx,yy,"Set the NPC's text identifier on Maps to the identifier above.");yy=yy+30*s
  else K.caption(fx,yy,"NPC script: "..M.key(S.project,id));yy=yy+30*s end
  if gen==3 then K.caption(fx,yy,"Rebuild after editing dialogue. Save exports the built scripts.");yy=yy+30*s end
  Pane.finish(S,"offlineGiftForm",first,yy,view)
end
return M
