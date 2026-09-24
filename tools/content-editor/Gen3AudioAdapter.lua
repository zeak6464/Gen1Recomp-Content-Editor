-- Native M4A records behind the existing Audio workspace.
local M={}
local groups={music="songs",sfx="sounds",cries="cries",map_songs="mapSongs"}
function M.prepare(S)
  local pack=require("Gen3Resources").audio(S.data)
  if not S.data._editorGen3Audio then
    local audio={songs={},sfx={},cries={},mapSongs={}}
    local se={};for name,n in pairs(require("src.core.game3.se_ids")) do if type(n)=="number" then se[n]=name:gsub("^SE_",""):gsub("_"," ") end end
    local musicNames=require("Gen3MusicNames")
    local locations={}
    for map,rec in pairs(S.data.maps or {}) do
      if rec.music then locations[rec.music]=locations[rec.music] or {};locations[rec.music][require("Gen3Labels").map(map)]=true end
    end
    for id,info in pairs(pack.songs or {}) do
      local names=require("RegList").sortedKeys(locations[tonumber(id)] or {})
      local rec={nativeId=tonumber(id),name=info.name or info.symbol or musicNames[tonumber(id)] or se[tonumber(id)] or (#names>0 and table.concat(names," / ")) or ("Track "..id),generation=3}
      if tonumber(id) and tonumber(id)>=256 then audio.songs[tostring(id)]=rec
      else audio.sfx[tostring(id)]=rec end
    end
    for _,rec in pairs(require("Gen3").catalog(S.data,"pokemon")) do
      if rec.index then audio.cries[tostring(rec.index)]={nativeId=rec.index,name=rec.name,generation=3} end
    end
    for id,map in pairs(S.data.maps or {}) do audio.mapSongs[id]=tostring((pack.mapSongs or {})[id] or map.music or 0) end
    S.data._editorGen3Audio=audio
  end
  S.data.audio=S.data._editorGen3Audio
  local p=S.project
  if p and not p.gen3AudioWorkspace then
    p.audio=p.audio or {}
    for _,group in pairs(groups) do
      local bucket=group=="sounds" and "sfx" or group
      p.audio[bucket]=p.audio[bucket] or {}
      for id,value in pairs((p.gen3Audio or {})[group] or {}) do
        if p.audio[bucket][id]==nil then
          p.audio[bucket][id]=group=="mapSongs" and tostring(value)
            or type(value)=="number" and {nativeId=value,generation=3}
            or require("src.mods.Merge").deepCopy(value)
        end
      end
    end
    p.gen3AudioWorkspace=1
  end
end
function M.label(S,mode,id)
  if mode=="map_songs" then return require("Gen3Labels").map(id) end
  local bucket=mode=="music" and "songs" or mode
  local rec=(((S.project or {}).audio or {})[bucket] or {})[id] or ((S.data.audio or {})[bucket] or {})[id]
  return rec and rec.name and (id.." · "..rec.name) or id
end
function M.nextId(S)
  local id=1000
  local function include(value)
    local n=tonumber(value)
    if n and n<65535 then id=math.max(id,n+1) end
  end
  for key in pairs(require("Gen3Resources").audio(S.data).songs or {}) do include(key) end
  for _,audio in ipairs({S.data.audio or {},S.project.audio or {}}) do
    for _,bucket in ipairs({"songs","sfx","cries"}) do
      for key in pairs(audio[bucket] or {}) do include(key) end
    end
    for _,value in pairs(audio.mapSongs or {}) do include(value) end
  end
  if id>=65535 then return nil,"No unused audio IDs remain" end
  return tostring(id)
end
function M.compile(p)
  if not p.gen3AudioWorkspace then return end
  local result={}
  for _,group in pairs(groups) do
    local bucket=group=="sounds" and "sfx" or group
    result[group]={}
    for id,value in pairs((p.audio or {})[bucket] or {}) do
      if group=="mapSongs" then result[group][id]=assert(tonumber(value),"Choose a native song ID")
      elseif value.file and value.file~="" then result[group][id]={file=value.file,loop=value.loop}
      else result[group][id]=assert(tonumber(value.nativeId),"Choose a native audio ID") end
    end
  end
  p.gen3Audio=result
end
function M.play(S,mode,id,rec)
  local P=require("Gen3Audio")
  P.stop(S)
  S._g3AudioBake=coroutine.create(function()
    local Player=require("src.core.game3.m4a_player")
    local cache={read=function(_,path) return S.data._gen3Read(path) end}
    S.data._g3PreviewPack=S.data._g3PreviewPack or assert(Player.loadPack(cache,"data/generated/gba/audio"))
    local target=assert(tonumber(type(rec)=="table" and rec.nativeId or rec or id),"Invalid audio ID")
    if mode=="cries" then
      return Player.bakeSlot(assert(Player.startCry(S.data._g3PreviewPack,target)),{maxSec=4,yieldEvery=2048})
    end
    return Player.bakeSong(S.data._g3PreviewPack,cache,target,{maxSec=4,yieldEvery=2048})
  end)
  S.status="Rendering native audio preview"
  return true
end
return M
