local M={}
function M.install(mod,config)
  local Runtime=require("src.mods.Runtime")
  local Popup=require("src.ui.game3.map_name_popup")
  local Font=require("src.ui.game3.frlg_font")
  mod.events:on("game.ready",function(ctx)
    local maps=ctx.game and ctx.game.data and ctx.game.data.maps or {}
    for id,spec in pairs(config) do
      if spec.enabled~=nil and maps[id] then
        -- Set both aliases: the native loader checks these before calling show.
        maps[id].showMapName=spec.enabled and 1 or 0
        maps[id].show_map_name=spec.enabled and 1 or 0
      end
    end
  end)
  if not Popup._editorBannerDispatch then
    Popup._editorBannerDispatch=true
    for _,name in ipairs({"show","draw","update","dismiss"}) do
      local base=Popup[name]
      Popup[name]=function(...) return Runtime.call("editor.gen3.banner."..name,base,...) end
    end
  end
  local active,pending
  local images={}
  mod.hooks:wrap("editor.gen3.banner.show",function(proceed,def,opts)
    local shown=proceed(def,opts)
    if not shown then return shown end
    local spec=config[def and (def.id or def.name or def.map)]
    if Popup._reshow then pending=spec else active=spec;pending=nil end
    if spec then
      if spec.text and spec.text~="" then
        if Popup._reshow then Popup._pendingName=spec.text else Popup._name=spec.text end
      end
      if spec.image then
        if Popup._reshow then Popup._pendingWidthTiles=14;Popup._pendingWidth=112
        else Popup._widthTiles=14;Popup._contentWidth=112 end
      end
    end
    return shown
  end)
  mod.hooks:wrap("editor.gen3.banner.update",function(proceed,...)
    local reshow=Popup._reshow
    local result=proceed(...)
    if reshow and not Popup._reshow then active=pending;pending=nil end
    return result
  end)
  mod.hooks:wrap("editor.gen3.banner.dismiss",function(proceed,...)
    active=nil;pending=nil
    return proceed(...)
  end)
  mod.hooks:wrap("editor.gen3.banner.draw",function(proceed,...)
    if not active or not active.image then return proceed(...) end
    if not Popup.isActive() or Popup._tPos<=0 then return end
    local img=images[active.image]
    if not img then img=mod.assets:image(active.image);img:setFilter("nearest","nearest");images[active.image]=img end
    local y=Popup._tPos-24
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1);love.graphics.draw(img,0,y)
    local name=Popup._name or ""
    local width=Font.measure(name)
    Font.draw(name,8+math.floor((112-width)/2),y+5,{colors=Font.COLOR.NORMAL,maxWidth=112})
    love.graphics.pop()
  end)
end
return M
