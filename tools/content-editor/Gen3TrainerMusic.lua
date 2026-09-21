local M={}
M.labels={["283"]="Team Rocket encounter",["284"]="Girl encounter",["285"]="Boy encounter"}
function M.emit(p,encode,out)
  if not next(p.gen3TrainerMusic or {}) then return end
  for id,song in pairs(p.gen3TrainerMusic) do
    assert(tonumber(id) and M.labels[tostring(song)],"Invalid trainer encounter music")
  end
  out[#out+1]="  local trainerMusic="..encode(p.gen3TrainerMusic)
  out[#out+1]=[=[
  local Trainers=require("src.core.game3.scripting.trainers")
  local Runtime=require("src.mods.Runtime")
  if not Trainers._editorMusicBridge then
    Trainers._editorMusicBridge=true
    local base=Trainers.getEncounterMusic
    Trainers.getEncounterMusic=function(...) return Runtime.call("editor.gen3.trainerMusic",base,...) end
  end
  mod.hooks:wrap("editor.gen3.trainerMusic",function(proceed,id)
    return trainerMusic[tostring(id)] or proceed(id)
  end)
]=]
end
return M
