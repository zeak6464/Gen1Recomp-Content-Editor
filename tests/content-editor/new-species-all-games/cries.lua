-- Real LÖVE audio device and exported mod; no audio mocks.
local M = {}
local source, remaining, report, log
local screenCalls=0
local function le(n, bytes)
  local out = {}
  for i=1,bytes do out[i]=string.char(n%256);n=math.floor(n/256) end
  return table.concat(out)
end
function M.prepare(S, IO, logger)
  log=logger
  local rate, count = 22050, 11025
  local pcm = {}
  for i=0,count-1 do
    local envelope=math.sin(math.pi*i/count)^2
    local sample=math.floor(math.sin(2*math.pi*(440*i/rate+300*(i/rate)^2))*envelope*12000)
    pcm[#pcm+1]=le(sample%65536,2)
  end
  local bytes=table.concat(pcm)
  local wav="RIFF"..le(36+#bytes,4).."WAVEfmt "..le(16,4)..le(1,2)..le(1,2)
    ..le(rate,4)..le(rate*2,4)..le(2,2)..le(16,2).."data"..le(#bytes,4)..bytes
  assert(IO.ensureDirectory(S.path.."/assets"))
  assert(IO.writeText(S.path.."/assets/test-cry.wav",wav))
  if require("Generation").isGen3(S) then
    require("Gen3Cries").set(S,S.project.pokemon.NEW_MON.index,{file="assets/test-cry.wav"})
  else
    S.project.audio=S.project.audio or {}
    S.project.audio.cries=S.project.audio.cries or {}
    S.project.audio.cries.NEW_MON={file="assets/test-cry.wav",_isNew=true}
    S.project.pokemon.NEW_MON.cry=nil
  end
  log("PASS non-silent custom WAV generated and assigned to added species")
end
function M.verify(S,data)
  if require("Generation").isGen3(S) then
    local Audio=require("src.core.game3.audio")
    assert(Audio.playCry(S.project.pokemon.NEW_MON.index),"Gen 3 playCry failed")
    source=assert(Audio._crySource,"custom species did not create an audio source")
    assert(not Audio.isCryFinished(),"cry wait completed before playback")
    local play=Audio.playCry
    Audio.playCry=function(species,...)
      local result=play(species,...)
      if species==S.project.pokemon.NEW_MON.index then
        screenCalls=screenCalls+1
        assert(Audio._crySource and Audio._crySource:isPlaying(),"screen cry did not play")
      end
      return result
    end
  else
    local def=assert(data.audio.cries.NEW_MON,"exported custom cry was not registered")
    assert(def.file:find("test-cry.wav",1,true),"wrong cry file")
    source=assert(require("src.core.Sound").playCry(data,"NEW_MON"),"custom cry failed to load")
    local Sound=require("src.core.Sound")
    local play=Sound.playCry
    Sound.playCry=function(data,species,...)
      local result=play(data,species,...)
      if species=="NEW_MON" then
        screenCalls=screenCalls+1
        assert(result and result:isPlaying(),"screen cry did not play")
      end
      return result
    end
  end
  assert(source:typeOf("Source") and source:isPlaying(),"real LÖVE audio source is not playing")
  assert(math.abs(source:getDuration()-.5)<.01,"wrong WAV played")
  log("PASS exported mod loaded; added species plays real 0.5-second custom cry")
end
function M.finish(reporter)
  assert(screenCalls>0,"Pokédex screen did not trigger custom cry")
  log("PASS in-game Pokédex screen triggered custom cry playback")
  report=reporter;remaining=.7
end
function M.update(dt)
  if not remaining then return end
  remaining=remaining-dt
  if remaining>0 then return end
  assert(not source:isPlaying(),"custom cry did not finish")
  report("PASS custom cry playback completed")
  remaining=nil
  love.event.quit()
end
return M
