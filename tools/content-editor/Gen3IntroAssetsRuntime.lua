-- Boot loads PNGs directly through LÖVE, bypassing CacheFs overrides.
local M={}
function M.install(mod,assets)
  local RT=require("src.mods.Runtime");local Boot=require("src.ui.game3.boot")
  local images={};local token={}
  local aliases={oak="oakSprite",boy="boySprite",girl="girlSprite",rival="rivalSprite",nidoran_f="nidoranFront",pikachu_intro_bg="pikachuBg",title_border_bg="titleBorder"}
  local stateKeys={title_screen="titleScreen",title_logo="titleLogo",box_art_mon="titleMon",title_border_bg="titleBorder",press_start="pressStart",copyright_press_start="copyrightLayer"}
  local function apply(state)
    if state._editorIntroAssets==token then return end
    state.assets=state.assets or {}
    for path,rec in pairs(assets) do
      local name=path:match("^data/generated/gba/intro/([^/]+)%.png$")
      if name then
        if not images[path] then
          images[path]=love.graphics.newImage(love.filesystem.newFileData(assert(mod:read(rec.file)),"intro.png"));images[path]:setFilter("nearest","nearest")
        end
        local img=images[path];state.assets[aliases[name] or name:gsub("_(%w)",string.upper)]=img
        if stateKeys[name] then state[stateKeys[name]]=img end
        if name=="platform" then state.assets.platformQuad=love.graphics.newQuad(0,0,32,32,img:getDimensions()) end
      end
    end
    state._editorIntroAssets=token
  end
  local function bridge(t,key,hook)
    t._editorIntroBridges=t._editorIntroBridges or {};if t._editorIntroBridges[key] then return end;t._editorIntroBridges[key]=true
    local original=t[key];t[key]=function(...) return RT.call(hook,original,...) end
  end
  bridge(Boot,"new","editor.gen3.intro.new");bridge(Boot,"update","editor.gen3.intro.update")
  bridge(require("src.ui.game3.title_screen"),"enter","editor.gen3.intro.title")
  mod.hooks:wrap("editor.gen3.intro.new",function(proceed,...) local state=proceed(...);apply(state);return state end)
  mod.hooks:wrap("editor.gen3.intro.update",function(proceed,state,...) apply(state);return proceed(state,...) end)
  mod.hooks:wrap("editor.gen3.intro.title",function(proceed,state,...) apply(state);return proceed(state,...) end)
end
return M
