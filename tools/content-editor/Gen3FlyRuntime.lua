local M={}
function M.available(row,session,visited)
  if row.enabled==false then return false end
  if row.unlock=="always" then return true end
  if row.unlock=="flag" then
    return require("src.core.game3.scripting.flags").getFlag(session,nil,row.flag)
  end
  return session.map==row.map or visited[row.map]==true
end
function M.install(mod,rows)
  local Runtime=require("src.mods.Runtime")
  local Field=require("src.core.game3.field")
  local Region=require("src.ui.game3.region_map")
  local function bridge(object,name,key)
    if object[key] then return end
    object[key]=true;local original=object[name]
    object[name]=function(...) return Runtime.call(key,original,...) end
  end
  bridge(Field,"executeFieldMove","editor.gen3.fly")
  for _,name in ipairs({"show","close","handleInput","draw","currentLocationName"}) do bridge(Region,name,"editor.gen3.fly."..name) end
  local active,index=nil,1
  local function visited(session)
    session.modData=session.modData or {};session.modData[mod.id]=session.modData[mod.id] or {}
    local data=session.modData[mod.id];data.flyVisited=data.flyVisited or {};return data.flyVisited
  end
  mod.events:on("map.entered",function(e)
    local session=Field.getSession();if session then visited(session)[e.mapId]=true end
  end)
  local function selectRow() local row=active and active[index];if row then Region.cursorX=row.mapX;Region.cursorY=row.mapY end end
  mod.hooks:wrap("editor.gen3.fly.show",function(proceed,opts) active=nil;return proceed(opts) end)
  mod.hooks:wrap("editor.gen3.fly.close",function(proceed,...) active=nil;return proceed(...) end)
  mod.hooks:wrap("editor.gen3.fly",function(proceed,payload)
    if not payload or payload.action~="fly" then return proceed(payload) end
    local session=Field.getSession();if not session then return end
    local choices={};for _,row in ipairs(rows) do if M.available(row,session,visited(session)) then choices[#choices+1]=row end end
    if #choices==0 then
      local Message=require("src.ui.game3.message")
      Message.show("Visit a Fly destination first.",function() Message.close() end);return
    end
    Region.show({session=session});active=choices;index=1;selectRow()
  end)
  mod.hooks:wrap("editor.gen3.fly.currentLocationName",function(proceed)
    return active and active[index].name or proceed()
  end)
  mod.hooks:wrap("editor.gen3.fly.handleInput",function(proceed,input)
    if not active then return proceed(input) end
    if input:wasPressed("b") or input:wasPressed("start") then Region.close();return end
    if input:wasPressed("a") then
      local row=active[index];Region.close()
      local Map=require("src.core.game3.map");local Player=require("src.core.game3.player")
      Map.load(Field._mod,Field._game,row.map,{x=row.x,y=row.y,facing="down",depth1Connections=true,via="fly"})
      Player.reset(row.x,row.y,"down");Player.syncToHost(Field._game)
      return
    end
    local delta=(input:wasPressed("right") or input:wasPressed("down")) and 1 or (input:wasPressed("left") or input:wasPressed("up")) and -1 or 0
    index=(index-1+delta)%#active+1;selectRow()
  end)
  mod.hooks:wrap("editor.gen3.fly.draw",function(proceed)
    proceed();if not active then return end
    love.graphics.push("all")
    for i,row in ipairs(active) do
      love.graphics.setColor(i==index and 1 or .2,1,.2,1)
      love.graphics.rectangle("line",36+row.mapX*8,24+row.mapY*8,8,8)
    end
    love.graphics.setColor(.12,.22,.18,1);love.graphics.rectangle("fill",0,144,240,16)
    require("src.ui.game3.frlg_font").draw("D-PAD: SELECT  A: FLY  B: BACK",4,146,{color={1,1,1,1},small=true})
    love.graphics.pop()
  end)
end
return M
