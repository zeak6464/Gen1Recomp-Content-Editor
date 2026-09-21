local M={}
function M.progress(session,owner)
  session.modData=session.modData or {};session.modData[owner]=session.modData[owner] or {}
  local d=session.modData[owner];d.fameChecker=d.fameChecker or {};return d.fameChecker
end
function M.available(row,session,original)
  if row.unlock=="always" then return true end
  if row.unlock=="flag" then
    local flags=session.flags or (session.store or {}).flags or {}
    return flags[row.flag]==true or flags[row.flag]==1 or flags[tostring(row.flag)]==true or flags[tostring(row.flag)]==1
  end
  return original==true
end
function M.factOpen(row,j,session,progress)
  return M.available(row.facts[j],session,((progress or {}).facts or {})[tostring(j)]==true)
end
function M.personOpen(row,session,p)
  if M.available(row,session,(p or {}).state~=nil and p.state>0) then return true end
  if row.unlock~="original" then return false end
  for j=1,6 do if M.factOpen(row,j,session,p) then return true end end
  return false
end
function M.messageOpen(row,session,p)
  for j=1,6 do if not M.factOpen(row,j,session,p) then return false end end
  return true
end
local images={}
function M.image(row)
  if row.image then
    if not images[row.image] then
      images[row.image]=love.graphics.newImage(love.filesystem.newFileData(love.data.decode("string","base64",row.image),"fame.png"))
      images[row.image]:setFilter("nearest","nearest")
    end
    return images[row.image]
  end
  local entry=require("src.core.game3.trainer_pic").front(row.portrait);return entry and entry.image
end
local function expand(text,session)
  return tostring(text or ""):gsub("{PLAYER}",function() return session.playerName or "PLAYER" end):gsub("{RIVAL}",function() return session.rivalName or "RIVAL" end)
end
function M.pages(text,session)
  local font=require("src.ui.game3.frlg_font");local pages={}
  for para in (expand(text,session).."\f"):gmatch("(.-)\f") do
    local lines={};for line in (font.wrap(para,222,{small=true}).."\n"):gmatch("(.-)\n") do lines[#lines+1]=line end
    for i=1,#lines,3 do pages[#pages+1]=table.concat(lines,"\n",i,math.min(#lines,i+2)) end
  end
  return #pages>0 and pages or {""}
end
function M.visible(view)
  local ids={};for i,r in ipairs(view.rows) do if view.preview or M.personOpen(r,view.session or {},(view.progress or {})[tostring(i)]) then ids[#ids+1]=i end end
  return ids
end
local function picture(encoded)
  if not images[encoded] then images[encoded]=love.graphics.newImage(love.filesystem.newFileData(love.data.decode("string","base64",encoded),"fame.png"));images[encoded]:setFilter("nearest","nearest") end
  return images[encoded]
end
-- Shared by the editor preview and the exported in-game viewer.
function M.draw(view)
  local row=view.rows[view.person];local font=require("src.ui.game3.frlg_font")
  love.graphics.push("all");love.graphics.setColor(1,1,1,1)
  local bg=view.rows[1].background
  if bg then love.graphics.draw(picture(bg),0,0) else
    love.graphics.setColor(1,.9,.4,1);love.graphics.rectangle("fill",0,0,240,160)
    love.graphics.setColor(.97,.95,.82,1);love.graphics.rectangle("fill",6,22,68,84)
  end
  local function txt(text,x,y,w,color) font.draw(text,x,y,{color=color or {.28,.28,.25,1},maxWidth=w,small=true}) end
  -- The ROM backgrounds have a blank header; retain native positions and colors.
  love.graphics.setColor(.98,.64,.23,1);love.graphics.rectangle("fill",0,0,78,17)
  love.graphics.setColor(.12,.37,.68,1);love.graphics.rectangle("fill",78,0,162,17)
  txt("FAME CHECKER",4,2,74,{1,1,1,1});txt("SEL:PIC  A:READ  B:BACK",91,2,148,{1,1,1,1})
  local visible=M.visible(view);view.visible=visible
  local selected=1;for i,id in ipairs(visible) do if id==view.person then selected=i end end
  local scroll=math.max(0,math.min(view.scroll or 0,math.max(0,#visible-5)))
  if selected<=scroll then scroll=selected-1 elseif selected>scroll+5 then scroll=selected-5 end;view.scroll=scroll
  for n=1,5 do
    local id=visible[scroll+n];if id then
      local chosen=id==view.person;txt((view.rows[id].name=="Professor Oak" and "OAK" or view.rows[id].name):upper(),15,29+(n-1)*14,56,chosen and {.1,.55,.2,1} or nil)
      if chosen then love.graphics.setColor(.1,.55,.2,1);love.graphics.polygon("fill",8,33+(n-1)*14,12,36+(n-1)*14,8,39+(n-1)*14) end
    end
  end
  if scroll>0 then txt("^",37,18,8) end;if scroll+5<#visible then txt("v",37,98,8) end
  local session=view.session or {};local progress=(view.progress or {})[tostring(view.person)] or {}
  local fact=row and row.facts[view.fact];local body="No people discovered yet."
  if row then
    if view.fact==7 then
      local img=M.image(row);if img then
        local colored=view.preview or row.unlock~="original" or (progress.state or 0)>=2
        love.graphics.setColor(colored and 1 or 0,colored and 1 or 0,colored and 1 or 0,1);love.graphics.draw(img,130,24)
      end
      body=(view.preview or M.messageOpen(row,session,progress)) and row.message or "Discover all six facts to read this message."
    else
      local Ow=require("src.core.game3.ow_sprites")
      for j=1,6 do
        local cx=112+(j-1)%3*48;local bottom=j<=3 and 48 or 76
        local unlocked=view.preview or M.factOpen(row,j,session,progress)
        if j==view.fact then love.graphics.setColor(1,.62,.2,1);love.graphics.rectangle("line",cx-11,bottom-24,23,26) end
        if unlocked then
          local gfx=row.facts[j].graphics;local spr=gfx and Ow.get(gfx)
          if spr then love.graphics.setColor(1,1,1,1);love.graphics.draw(spr.image,spr.quads[0],cx-spr.width/2,bottom-spr.height)
          else txt("!",cx-3,bottom-19,12) end
        else
          love.graphics.setColor(.27,.22,.5,1);love.graphics.rectangle("fill",cx-6,bottom-21,12,18,2,2);txt("?",cx-3,bottom-20,10,{1,1,1,1})
        end
      end
      love.graphics.setColor(.35,.35,.4,1);love.graphics.rectangle("fill",112,78,98,29)
      love.graphics.setColor(.98,.97,.9,1);love.graphics.rectangle("fill",114,80,94,25)
      local unlocked=view.preview or M.factOpen(row,view.fact,session,progress)
      local location=unlocked and expand(fact.location,session) or "UNKNOWN"
      local source=unlocked and expand(fact.source,session) or "???"
      txt(location,116,80,90);txt(source,116,92,90)
      body=unlocked and (fact.question.."\f"..fact.text) or "This information has not been discovered yet."
    end
  end
  local pages=M.pages(body,session);view.page=math.min(view.page or 1,#pages);view.pageCount=#pages
  love.graphics.setColor(.42,.66,.89,1);love.graphics.rectangle("fill",2,114,236,44,8,8)
  love.graphics.setColor(.98,.84,.46,1);love.graphics.rectangle("fill",4,116,232,40,7,7)
  love.graphics.setColor(.97,.97,.93,1);love.graphics.rectangle("fill",6,118,228,36,5,5)
  font.draw(pages[view.page],12,120,{color={.28,.28,.25,1},small=true,linePitch=11,maxWidth=216})
  if #pages>1 then txt("v",225,143,8) end
  love.graphics.pop()
end
function M.input(view,input)
  if input:wasPressed("b") then
    if view.focus=="facts" then view.focus="people";view.fact=1;view.page=1;return end
    return "close"
  end
  if input:wasPressed("select") then view.fact=view.fact==7 and 1 or 7;view.focus="facts";view.page=1;return end
  if input:wasPressed("a") then
    if view.focus~="facts" then view.focus="facts" else view.page=(view.page or 1)%(view.pageCount or 1)+1 end
    return
  end
  if view.focus=="facts" then
    if view.fact==7 then return end
    local delta=input:wasPressed("right") and 1 or input:wasPressed("left") and -1 or input:wasPressed("down") and 3 or input:wasPressed("up") and -3 or 0
    if delta~=0 then view.fact=(view.fact-1+delta)%6+1;view.page=1 end
  else
    if input:wasPressed("right") then view.focus="facts";return end
    local ids=M.visible(view);if #ids==0 then return end
    local delta=input:wasPressed("down") and 1 or input:wasPressed("up") and -1 or 0
    if delta~=0 then
      local index=1;for i,id in ipairs(ids) do if id==view.person then index=i end end
      view.person=ids[(index-1+delta)%#ids+1];view.fact=1;view.page=1
    end
  end
end
function M.install(mod,rows)
  local RT=require("src.mods.Runtime");local Field=require("src.core.game3.field")
  local Stack=require("src.ui.game3.stack");local view={rows=rows,person=1,fact=1,page=1}
  local function bridge(t,k,hook)
    t._editorFameBridges=t._editorFameBridges or {};if t._editorFameBridges[k] then return end;t._editorFameBridges[k]=true
    local original=t[k];t[k]=function(...) return RT.call(hook,original,...) end
  end
  local function active() return RT.wantsHook("editor.gen3.fame.item") end
  local function close() Stack.pop("editor_fame_checker") end
  function view.draw() if not active() then close();return end;M.draw(view) end
  function view.isOpen() return active() and Stack.has("editor_fame_checker") end
  function view.handleInput(input)
    if not active() or M.input(view,input)=="close" then close() end
  end
  local Item=require("src.core.game3.item_use");bridge(Item,"useField","editor.gen3.fame.item")
  mod.hooks:wrap("editor.gen3.fame.item",function(proceed,session,bag,id,slot)
    local num=require("src.core.game3.items_data").toNumericId(id)
    if id~="FAME_CHECKER" and num~=363 then return proceed(session,bag,id,slot) end
    if not session then return false,"none","No active game." end
    view.session=session;view.progress=M.progress(session,mod.id);view.person=nil;view.fact=1;view.page=1;view.focus="people";view.scroll=0
    for i,row in ipairs(rows) do if M.personOpen(row,session,view.progress[tostring(i)]) then view.person=i;break end end
    Stack.push("editor_fame_checker",view,{hideBelow=true});return true,"fame_checker",""
  end)
  local Native=require("src.core.game3.scripting.natives");bridge(Native,"special","editor.gen3.fame.special")
  mod.hooks:wrap("editor.gen3.fame.special",function(proceed,ctx,id,adapters)
    if id~=371 and id~=372 then return proceed(ctx,id,adapters) end
    local session=Field.getSession();if not session then return false end
    local Flags=require("src.core.game3.scripting.flags")
    local person=Flags.getVar(session.store,ctx,0x8004);local value=Flags.getVar(session.store,ctx,0x8005)
    if person<0 or person>15 or value<0 or value>=(id==371 and 6 or 3) then return false end
    local progress=M.progress(session,mod.id);local key=tostring(person+1);progress[key]=progress[key] or {state=0,facts={}}
    local p=progress[key]
    if id==371 then p.facts[tostring(value+1)]=true;value=1;Flags.setVar(session.store,ctx,0x8005,1) end
    p.state=math.max(p.state or 0,value);return false
  end)
  return view
end
return M
