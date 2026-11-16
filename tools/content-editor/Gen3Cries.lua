-- Gen 3 runtime cries use species numbers, including added species.
local M = {}

function M.set(S, index, value)
  require("Gen3AudioAdapter").prepare(S)
  S.project.audio.cries = S.project.audio.cries or {}
  S.project.audio.cries[tostring(index)] = value
end

function M.draw(S, mon, App, x, y, w, h, s)
  local Kit = require("Kit")
  local index = mon.index
  local key = tostring(index)
  local value = (((S.project or {}).audio or {}).cries or {})[key]
  local label = value and (value.file or ("Species " .. tostring(value.nativeId))) or "Default cry"
  local bw, gap = 72*s, 4*s
  local lw = math.max(0, w - 3*(bw+gap))
  Kit.text("micro", Kit.ellipsize("micro", label, lw), x, y+8*s, require("Theme").PAL.muted)
  x = x+lw+gap
  if Kit.button(x,y,bw,h,"Alias",{kind="ghost",font="small",tooltip="Reuse another Pokemon's cry"}) then
    require("SpeciesPicker").open(S,{current=mon.id,title="CRY ALIAS",onPick=function(id)
      local rec = S.project.pokemon[id] or S.data.pokemon[id]
      if not rec or not rec.index or rec.index == index then return end
      local other = (((S.project or {}).audio or {}).cries or {})[tostring(rec.index)]
      M.set(S,index,other and require("src.mods.Merge").deepCopy(other) or {nativeId=rec.index,generation=3})
      App.markDirty()
    end})
  end
  if Kit.button(x+bw+gap,y,bw,h,"Browse",{kind="ghost",font="small",tooltip="Import a WAV, OGG or MP3 cry"}) then
    App.pickFile("Cry audio","Audio|*.ogg;*.wav;*.mp3|All|*.*",function(path)
      if not path or path == "" then return end
      local ok, source = pcall(function()
        local bytes = assert(require("ModIO").readText(path))
        return love.audio.newSource(love.filesystem.newFileData(bytes,path:match("[^/\\]+$")),"static")
      end)
      if not ok then S.status="Cry could not be decoded: "..tostring(source);return end
      source:release()
      App.importToMod(path,nil,function(rel)
        M.set(S,index,{file=rel})
        App.markDirty()
        S.status="Cry -> "..tostring(rel)
      end)
    end)
  end
  if Kit.button(x+2*(bw+gap),y,bw,h,"Reset",{kind="ghost",font="small",tooltip="Remove this Pokemon's cry override"}) then
    M.set(S,index,nil)
    App.markDirty()
  end
end

return M
