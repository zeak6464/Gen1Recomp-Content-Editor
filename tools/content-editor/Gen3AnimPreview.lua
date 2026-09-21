-- Run the native renderer/VM against a read-only editor cache and a fake battle.
local M={}
local function scoped(p,fn)
  local Dataset=require("src.core.game3.dataset")
  local Cache=require("src.import.CacheFs")
  local Audio=require("src.core.game3.audio")
  local cache,read,active=Dataset.cache,Cache.read,Cache.readActive
  local savedAudio={}
  local muted={"playSe","setSePan","stopSe","playCry","isSePlaying","isCryFinished"}
  for _,name in ipairs(muted) do savedAudio[name]=Audio[name] end
  Dataset.cache=function() return p.cache end
  Cache.read=function(path) return p.cache:read(path) end
  Cache.readActive=Cache.read
  -- Preview is silent; it must not interrupt the Audio tab's own sources.
  for _,name in ipairs(muted) do Audio[name]=function() end end
  Audio.isSePlaying=function() return false end
  Audio.isCryFinished=function() return true end
  local ok,value=xpcall(fn,debug.traceback)
  Dataset.cache,Cache.read,Cache.readActive=cache,read,active
  for _,name in ipairs(muted) do Audio[name]=savedAudio[name] end
  if not ok then p.error=tostring(value);p.paused=true;return nil,p.error end
  return value
end
function M.stop(S)
  local p=S.g3AnimPreview
  if not p then return end
  local Anim=require("src.core.game3.battle.anim")
  Anim.reset({headless=true})
  Anim._pack,Anim._packLoaded=p.previousPack,p.previousPackLoaded
  require("src.core.game3.battle.ui").reset({headless=true})
  require("src.core.game3.pokemon").install(p.previousPokemonCache)
  S.g3AnimPreview=nil
end
function M.play(S,id,script)
  M.stop(S)
  local Resources=require("Gen3Resources")
  local pack=Resources.readTable(S.data,Resources.animationPath)
  for key,value in pairs(S.project.gen3Animations or {}) do
    local section,index=key:match("^([^/]+)/(.+)$")
    pack[section]=pack[section] or {};pack[section][tonumber(index) or index]=require("src.mods.Merge").deepCopy(value)
  end
  local section,index=id:match("^([^/]+)/(.+)$")
  if not section or section=="tags" or section=="animBgs" then return nil,"Select an animation script" end
  pack[section]=pack[section] or {};pack[section][tonumber(index) or index]=script
  local encoded="return "..require("ModWriter").encodeLua(pack)
  local p={id=id,frame=0,elapsed=0,paused=false,source=S.project,data=S.data}
  p.cache={read=function(_,path)
    path=path:gsub("^firered/","")
    if path==Resources.animationPath then return encoded end
    local override=(S.project.gen3Assets or {})[path]
    if override then return require("ModIO").readText(S.path.."/"..override.file) end
    return S.data._gen3Read(path)
  end,write=function() return false end}
  S.g3AnimPreview=p
  return scoped(p,function()
    local Anim=require("src.core.game3.battle.anim")
    local Ui=require("src.core.game3.battle.ui")
    local Pokemon=require("src.core.game3.pokemon")
    p.previousPack,p.previousPackLoaded=Anim._pack,Anim._packLoaded
    p.previousPokemonCache=Pokemon._cache
    Pokemon.install(p.cache)
    Anim._packLoaded=false;Anim._pack=nil
    Anim.reset({headless=false})
    Anim.scriptForMove(1) -- Native loader hydrates palette-indexed animation sheets.
    Ui.reset({headless=false})
    local mons={}
    local Party=require("src.core.game3.party")
    for i,species in ipairs({S.g3PreviewAttacker or "BULBASAUR",S.g3PreviewTarget or "CHARMANDER"}) do
      local rec=(S.project.pokemon or {})[species] or (S.data.pokemon or {})[species]
      local n=rec and rec.index or (i==1 and 1 or 4)
      local session={party={},name="PREVIEW"}
      assert(Party.giveMon(session,n,50),"Cannot create preview Pokemon")
      local mon=session.party[1]
      mons[i]={mon=mon,species=n,level=50,hp=mon.hp,maxHp=mon.maxHp,name=mon.name,side=i==1 and "player" or "enemy"}
    end
    p.battle={player=mons[1],enemy=mons[2],battlers={[0]=mons[1],[1]=mons[2]},double=false}
    Ui.bindState(p.battle,{party={mons[1].mon}})
    Anim.present("player").visible=true;Anim.present("enemy").visible=true
    local stage=Anim.stage();stage.trainer=nil;stage.partyBar=nil
    local reverse=S.g3PreviewReverse
    local opts={attackerSide=reverse and "enemy" or "player",targetSide=reverse and "player" or "enemy",
      attackerSpecies=mons[reverse and 2 or 1].species,targetSpecies=mons[reverse and 1 or 2].species,
      statusAnim=section=="status",phase=section=="moves" and "cb1" or "task"}
    assert(Anim.vm():launch(script,opts),"Animation contains no commands")
    p.canvas=love.graphics.newCanvas(240,160);p.canvas:setFilter("nearest","nearest")
    return true
  end)
end
function M.step(S)
  local p=S.g3AnimPreview;if not p or p.error then return end
  scoped(p,function()
    local Anim=require("src.core.game3.battle.anim")
    if Anim.vm().active then Anim.update(1/60);p.frame=p.frame+1 end
    p.finished=not Anim.vm().active
    if p.frame>=3600 and not p.finished then error("Preview stopped after 60 seconds; check command loops or unfinished tasks") end
    return true
  end)
end
function M.update(S,dt)
  local p=S.g3AnimPreview;if not p then return end
  if S.tab~="anims" or S.project~=p.source or S.data~=p.data then M.stop(S);return end
  if p.paused or p.finished or p.error then return end
  p.elapsed=p.elapsed+math.min(dt or 0,0.25)
  while p.elapsed>=1/60 do p.elapsed=p.elapsed-1/60;M.step(S);if p.error or p.finished then break end end
end
function M.render(S)
  local p=S.g3AnimPreview;if not p or not p.canvas then return end
  local current={love.graphics.getCanvas()}
  love.graphics.push("all")
  love.graphics.setCanvas({p.canvas,stencil=true});love.graphics.origin();love.graphics.setScissor();love.graphics.setShader()
  love.graphics.clear(0.9,0.93,0.9,1)
  scoped(p,function() require("src.core.game3.battle.ui").draw(240,160);return true end)
  love.graphics.setCanvas(unpack(current));love.graphics.pop()
  return p.canvas
end
function M.draw(S,x,y,w,h)
  local K=require("Kit");local p=S.g3AnimPreview;local s=K.scale
  if not p then return end
  if K.button(x,y,90*s,26*s,p.paused and "Resume" or "Pause",{}) then p.paused=not p.paused end
  if K.button(x+98*s,y,90*s,26*s,"Step",{}) then p.paused=true;M.step(S) end
  K.caption(x+204*s,y+5*s,"Frame "..p.frame..(p.finished and " — finished" or ""))
  if p.error then K.caption(x,y+36*s,K.ellipsize("micro",p.error,w));return end
  local canvas=M.render(S)
  if canvas then
    local scale=math.min(w/240,(h-34*s)/160)
    love.graphics.setColor(1,1,1,1);love.graphics.draw(canvas,x,y+34*s,0,scale,scale)
  end
end
return M
