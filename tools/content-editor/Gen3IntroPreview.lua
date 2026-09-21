local M={}
local function scoped(fn)
  local Audio=require("src.core.game3.audio")
  local saved={};local keys={"playSong","playCry","fadeOutBgm","isBgmStopped"}
  for _,key in ipairs(keys) do saved[key]=Audio[key];Audio[key]=function() return true end end
  local ok,value=xpcall(fn,debug.traceback)
  for _,key in ipairs(keys) do Audio[key]=saved[key] end
  return ok,value
end
function M.stop(S)
  local p=S.g3IntroPreview;if not p then return end
  if p.movie then p.movie:destroy() end
  if p.oak then p.oak:destroy();require("src.ui.game3.naming").dismiss() end
  if p.title then require("src.ui.game3.title_screen").leave(p.title) end
  S.g3IntroPreview=nil
end
function M.play(S,kind)
  M.stop(S)
  local p={kind=kind,frame=0,project=S.project};S.g3IntroPreview=p
  local ok,err=scoped(function()
    local assets={}
    for path in pairs(require("Gen3Resources").assets(S.data)) do
      local file=path:match("/intro/([^/]+)%.png$")
      if file then
        local key=file:gsub("_(%w)",string.upper)
        local override=(S.project.gen3Assets or {})[path]
        local bytes=override and require("ModIO").readText(S.path.."/"..override.file) or S.data._gen3Read(path)
        if bytes then
          local img=love.graphics.newImage(love.filesystem.newFileData(bytes,"preview.png"));img:setFilter("nearest","nearest");assets[key]=img
        end
      end
    end
    if kind=="oak" then
      assets.oakSprite=assets.oak;assets.boySprite=assets.boy;assets.girlSprite=assets.girl;assets.rivalSprite=assets.rival
      assets.nidoranFront=assets.nidoranF;assets.pikachuBg=assets.pikachuIntroBg
      p.oak=require("src.ui.game3.new_game_scene").new(assets)
      require("Gen3OakRuntime").configure(p.oak,S.project.gen3OakScene or {},S.project.gen3Oak or {})
    elseif kind=="title" then
      p.title={assets=assets,titleLogo=assets.titleLogo,titleMon=assets.boxArtMon,titleScreen=assets.titleScreen,
        copyrightLayer=assets.copyrightPressStart,pressStart=assets.pressStart,titleBorder=assets.titleBorderBg}
      assets.titleBorder=assets.titleBorderBg
      require("src.ui.game3.title_screen").enter(p.title)
    else p.movie=require("src.ui.game3.intro_movie").new(assets) end
    p.canvas=love.graphics.newCanvas(240,160);p.canvas:setFilter("nearest","nearest")
  end)
  if not ok then p.error=err end
  return ok,err
end
function M.step(S,dt)
  local p=S.g3IntroPreview;if not p or p.error then return end
  local ok,err=scoped(function()
    if p.oak then
      local pending=p.keys or {};p.keys={}
      p.oak:update({wasPressed=function(_,key) return pending[key] end,isDown=function() return false end},dt or 1/60)
    elseif p.movie then p.movie:update(nil,dt or 1/60)
    else require("src.ui.game3.title_screen").update(p.title,nil,dt or 1/60) end
    p.frame=p.frame+1
  end)
  if not ok then p.error=err end
end
function M.update(S,dt)
  local p=S.g3IntroPreview;if not p then return end
  if S.tab~="ui" or (S.g3UiMode~="playback" and S.g3UiMode~="oak") or S.project~=p.project then M.stop(S);return end
  if not p.paused then M.step(S,math.min(dt,.1)) end
end
function M.render(S)
  local p=S.g3IntroPreview;if not p or p.error then return end
  love.graphics.push("all");local previous=love.graphics.getCanvas()
  love.graphics.setCanvas({p.canvas,stencil=true});love.graphics.origin();love.graphics.setScissor();love.graphics.setShader();love.graphics.clear(0,0,0,1)
  local ok,err=scoped(function() if p.oak then p.oak:draw() elseif p.movie then p.movie:draw() else require("src.ui.game3.title_screen").draw(p.title) end end)
  love.graphics.setCanvas(previous);love.graphics.pop()
  if not ok then p.error=err end
  return p.canvas
end
function M.draw(S,x,y,w,h)
  local K=require("Kit");local s=K.scale
  for i,kind in ipairs({"intro","title"}) do if K.button(x+(i-1)*170*s,y,160*s,28*s,"Play "..kind,{}) then M.play(S,kind) end end
  local p=S.g3IntroPreview;if not p then K.caption(x,y+50*s,"Preview the native intro movie or animated title screen with your asset replacements.");return end
  if K.button(x+340*s,y,90*s,28*s,p.paused and "Resume" or "Pause",{}) then p.paused=not p.paused end
  if K.button(x+440*s,y,80*s,28*s,"Step",{}) then p.paused=true;M.step(S) end
  local canvas=M.render(S)
  if p.error then K.caption(x,y+48*s,K.ellipsize("micro",p.error,w));return end
  if canvas then local scale=math.min(w/240,(h-50*s)/160);love.graphics.setColor(1,1,1,1);love.graphics.draw(canvas,x,y+50*s,0,scale,scale) end
end
return M
