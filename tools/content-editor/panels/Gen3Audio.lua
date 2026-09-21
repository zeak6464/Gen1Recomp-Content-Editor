local Kit=require("Kit")
local R=require("Gen3Resources")
local List=require("RegList")
local Panel={}
function Panel.stop(S)
  S._g3AudioBake=nil
  if S._g3AudioSource then S._g3AudioSource:stop();S._g3AudioSource:release();S._g3AudioSource=nil end
end
function Panel.update(S)
  if S.tab~="audio" then Panel.stop(S);return end
  local job=S._g3AudioBake
  if not job then return end
  local ok,source=coroutine.resume(job)
  if not ok then S._g3AudioBake=nil;S.status="Preview failed: "..tostring(source)
  elseif coroutine.status(job)=="dead" then
    S._g3AudioBake=nil
    if source then S._g3AudioSource=love.audio.newSource(source,"static");S._g3AudioSource:play();S.status="Playing native audio preview" end
  end
end
function Panel.draw(S,x,y,w,h,App)
  if not S.project then Kit.caption(x,y,"Open a FireRed project first");return end
  local s=Kit.scale
  local groups={"songs","sounds","cries","mapSongs"}
  S.g3AudioGroup=S.g3AudioGroup or "songs"
  for i,group in ipairs(groups) do
    if Kit.button(x+(i-1)*115*s,y,108*s,28*s,group,{kind=group==S.g3AudioGroup and "primary" or "ghost"}) then S.g3AudioGroup=group;S.g3AudioId=nil end
  end
  y,h=y+40*s,h-40*s
  local group=S.g3AudioGroup
  local pack=R.audio(S.data)
  local catalog={}
  if group=="mapSongs" then
    for id,map in pairs(S.data.maps or {}) do catalog[id]=(pack.mapSongs or {})[id] or map.music or 0 end
  elseif group=="cries" then
    for _,rec in pairs(require("Gen3").catalog(S.data,"pokemon")) do
      if rec.index then catalog[tostring(rec.index)]=rec.name or rec.id end
    end
  else for id,info in pairs(pack.songs or {}) do catalog[tostring(id)]=info end end
  local edits=((S.project.gen3Audio or {})[group] or {})
  local ids=List.mergeIds(edits,catalog)
  S.g3AudioId=S.g3AudioId or (group=="songs" and catalog["300"] and "300") or ids[1]
  local fx,fw=List.drawList(S,App,x,y,w,h,"FireRed "..group,ids,{selKey="g3AudioId",queryKey="g3AudioQuery",offsetKey="g3AudioOffset"})
  local id=S.g3AudioId
  if not id then Kit.caption(fx,y,"Import FireRed audio first");return end
  local value=edits[id]
  if S._g3AudioKey~=group..id or S._g3AudioValue~=value then
    S._g3AudioKey,S._g3AudioValue=group..id,value
    S.g3AudioTarget=tostring(type(value)=="number" and value or group=="mapSongs" and catalog[id] or tonumber(id) or 0)
  end
  local info=catalog[id]
  Kit.caption(fx,y,id.."  "..(type(info)=="table" and (info.name or info.symbol or "") or group=="cries" and tostring(info) or ""))
  Kit.caption(fx,y+32*s,group=="cries" and "Play another species' cry (species number)" or "Play another extracted song / sound (numeric ID)")
  S.g3AudioTarget=Kit.textfield("g3AudioTarget",fx,y+60*s,fw,28*s,S.g3AudioTarget,"Numeric ID")
  local function save(v)
    S.project.gen3Audio=S.project.gen3Audio or {};S.project.gen3Audio[group]=S.project.gen3Audio[group] or {}
    S.project.gen3Audio[group][id]=v;App.markDirty();S.status="Applied audio edit; Save to export"
  end
  if Kit.button(fx,y+103*s,125*s,28*s,"Apply remap",{kind="primary"}) then
    local n=tonumber(S.g3AudioTarget)
    if n and n>=0 and n%1==0 and (group=="cries" and catalog[tostring(n)] or group~="cries" and ((pack.songs or {})[n] or n==0)) then save(n)
    else S.status="Choose an existing numeric ID" end
  end
  if Kit.button(fx+139*s,y+103*s,125*s,28*s,"Revert",{}) then save(nil) end
  if group~="mapSongs" then
    if Kit.button(fx,y+150*s,210*s,30*s,"Import OGG / WAV",{}) then
      App.pickFile("Replace "..group.." "..id,"Audio (*.ogg;*.wav)|*.ogg;*.wav",function(path)
        local bytes=require("ModIO").readText(path)
        local ok,source=pcall(function() return love.audio.newSource(love.filesystem.newFileData(bytes,path:match("[^/\\]+$")),"static") end)
        if not ok then S.status="Audio could not be decoded: "..tostring(source);return end
        source:release()
        App.importToMod(path,"assets/gen3/audio/"..group.."_"..id.."."..(path:match("%.([^.]+)$") or "ogg"),function(rel)
          save({file=rel,loop=group=="songs"})
        end)
      end)
    end
    if type(value)=="table" then
      Kit.caption(fx,y+197*s,value.file)
      if group=="songs" and Kit.button(fx,y+225*s,150*s,28*s,value.loop~=false and "Loop: on" or "Loop: off",{}) then
        save({file=value.file,loop=value.loop==false})
      end
      if Kit.button(fx,y+268*s,130*s,28*s,"Play import",{}) then
        if S._g3AudioSource then S._g3AudioSource:stop() end
        local bytes=require("ModIO").readText(S.path.."/"..value.file)
        local ok,source=pcall(function() return love.audio.newSource(love.filesystem.newFileData(bytes,value.file),"static") end)
        if ok then S._g3AudioSource=source;source:play() else S.status=tostring(source) end
      end
    end
  end
  if type(value)~="table" and Kit.button(fx,y+268*s,130*s,28*s,S._g3AudioBake and "Rendering..." or "Play native",{}) then
    Panel.stop(S)
    local target=tonumber(value) or (group=="mapSongs" and tonumber(catalog[id])) or tonumber(id)
    S._g3AudioBake=coroutine.create(function()
      local Player=require("src.core.game3.m4a_player")
      local cache={read=function(_,path) return S.data._gen3Read(path) end}
      S.data._g3PreviewPack=S.data._g3PreviewPack or assert(Player.loadPack(cache,"data/generated/gba/audio"))
      if group=="cries" then
        local slot=assert(Player.startCry(S.data._g3PreviewPack,target))
        return Player.bakeSlot(slot,{maxSec=4,yieldEvery=2048})
      end
      return Player.bakeSong(S.data._g3PreviewPack,cache,target,{maxSec=4,yieldEvery=2048})
    end)
  end
  if Kit.button(fx+145*s,y+268*s,130*s,28*s,"Stop preview",{}) then Panel.stop(S) end
  Kit.caption(fx,y+319*s,"Map songs select native IDs. Song replacements also apply to fanfares.")
end
return Panel
